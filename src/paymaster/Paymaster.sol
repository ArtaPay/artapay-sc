// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../interfaces/IERC4337.sol";
import "../interfaces/IStablecoinRegistry.sol";

/**
 * @title Paymaster
 * @notice ERC-4337 Paymaster for gasless stablecoin transactions
 * @dev Implements IPaymaster interface for EntryPoint integration
 */
contract Paymaster is IPaymaster, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @notice Gas fee markup in basis points (5% = 500/10000 bps)
    uint256 public constant GAS_MARKUP_BPS = 500;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum gas price (0.001 gwei)
    uint256 public constant MIN_GAS_PRICE = 0.0001 gwei;

    /// @notice Maximum gas price (1000 gwei)
    uint256 public constant MAX_GAS_PRICE = 1000 gwei;

    /// @notice Cost of postOp execution (estimated)
    uint256 public constant COST_OF_POST = 40000;

    /// @notice Valid signature marker
    uint256 private constant SIG_VALIDATION_SUCCESS = 0;
    uint256 private constant SIG_VALIDATION_FAILED = 1;

    /// @notice ERC-4337 EntryPoint contract
    IEntryPoint public immutable entryPoint;

    /// @notice Stablecoin registry contract
    IStablecoinRegistry public stablecoinRegistry;

    /// @notice Collected fees per token
    mapping(address => uint256) public collectedFees;

    /// @notice Supported tokens for gas payment
    mapping(address => bool) public supportedTokens;

    /// @notice Authorized signers for paymaster validation
    mapping(address => bool) public authorizedSigners;

    /// @notice Used nonces for replay protection
    mapping(bytes32 => bool) public usedNonces;

    /// @notice Tracks one-time activation sponsorship per payer
    mapping(address => bool) public activationUsed;

    event GasSponsored(address indexed sender, address indexed token, uint256 gasFee);
    event ActivationSponsored(address indexed payer);

    event FeesWithdrawn(address indexed token, uint256 amount, address indexed to);

    event TokenSupportUpdated(address indexed token, bool isSupported);
    event SignerUpdated(address indexed signer, bool authorized);
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event StakeAdded(uint256 amount, uint32 unstakeDelaySec);
    event StakeUnlocked();
    event StakeWithdrawn(address indexed account, uint256 amount);

    error InvalidEntryPoint();
    error InvalidToken();
    error InvalidSigner();
    error InsufficientDeposit();
    error InvalidSignature();
    error ExpiredSignature();
    error UsedNonce();

    /**
     * @notice Restrict calls to EntryPoint only
     */
    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "Paymaster: not EntryPoint");
        _;
    }

    /**
     * @notice Initialize the ERC-4337 Paymaster
     * @param _entryPoint Address of the ERC-4337 EntryPoint contract
     * @param _stablecoinRegistry Address of the StablecoinRegistry contract
     */
    constructor(address _entryPoint, address _stablecoinRegistry) Ownable(msg.sender) {
        if (_entryPoint == address(0)) revert InvalidEntryPoint();
        require(_stablecoinRegistry != address(0), "Paymaster: invalid registry");

        entryPoint = IEntryPoint(_entryPoint);
        stablecoinRegistry = IStablecoinRegistry(_stablecoinRegistry);

        authorizedSigners[msg.sender] = true;

        emit RegistryUpdated(address(0), _stablecoinRegistry);
        emit SignerUpdated(msg.sender, true);
    }

    /**
     * @notice Validate a UserOperation for sponsorship
     * @dev Called by EntryPoint during validation phase
     *      Supports ERC-2612 permit
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation
     * @param maxCost Maximum cost the paymaster might pay
     * @return context Context to pass to postOp (token, sender, maxTokenCost)
     * @return validationData Validation result (0 = success)
     */
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        override
        onlyEntryPoint
        whenNotPaused
        returns (bytes memory context, uint256 validationData)
    {
        require(userOp.paymasterAndData.length >= 171, "Paymaster: invalid paymasterAndData");

        address token = address(bytes20(userOp.paymasterAndData[52:72]));
        address payer = address(bytes20(userOp.paymasterAndData[72:92]));
        uint48 validUntil = uint48(bytes6(userOp.paymasterAndData[92:98]));
        uint48 validAfter = uint48(bytes6(userOp.paymasterAndData[98:104]));
        bool hasPermit = uint8(userOp.paymasterAndData[104]) == 1;
        bool isActivation = uint8(userOp.paymasterAndData[105]) == 1;

        bytes memory signature;
        uint256 cursor = 106;

        if (hasPermit) {
            require(userOp.paymasterAndData.length >= 268, "Paymaster: invalid permit data");

            uint256 deadline = uint256(bytes32(userOp.paymasterAndData[cursor:cursor + 32]));
            uint8 v = uint8(userOp.paymasterAndData[cursor + 32]);
            bytes32 r = bytes32(userOp.paymasterAndData[cursor + 33:cursor + 65]);
            bytes32 s = bytes32(userOp.paymasterAndData[cursor + 65:cursor + 97]);

            IERC20Permit(token).permit(payer, address(this), type(uint256).max, deadline, v, r, s);

            signature = userOp.paymasterAndData[cursor + 97:];
        } else {
            signature = userOp.paymasterAndData[cursor:];
        }

        require(supportedTokens[token], "Paymaster: token not supported");

        require(payer != address(0), "Paymaster: invalid payer");

        bytes32 hash = keccak256(abi.encode(payer, token, validUntil, validAfter, isActivation));
        bytes32 signedHash = hash.toEthSignedMessageHash();
        address signer = signedHash.recover(signature);

        if (!authorizedSigners[signer]) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        if (isActivation) {
            require(!activationUsed[payer], "Paymaster: activation already used");
            require(payer == userOp.sender, "Paymaster: payer mismatch");
            _validateActivationCallData(userOp.callData);
            context = abi.encode(token, payer, uint256(0), true, false);
            validationData = _packValidationData(false, validUntil, validAfter);
            return (context, validationData);
        }

        bool isFaucet = _isFaucetCall(userOp.callData, token);
        if (isFaucet) {
            require(payer == userOp.sender, "Paymaster: payer mismatch");
            context = abi.encode(token, payer, uint256(0), false, true);
            validationData = _packValidationData(false, validUntil, validAfter);
            return (context, validationData);
        }

        uint256 tokenCost = _calculateTokenCost(token, maxCost);
        require(IERC20(token).balanceOf(payer) >= tokenCost, "Paymaster: insufficient balance");
        require(IERC20(token).allowance(payer, address(this)) >= tokenCost, "Paymaster: insufficient allowance");

        context = abi.encode(token, payer, tokenCost, false, false);

        validationData = _packValidationData(false, validUntil, validAfter);

        return (context, validationData);
    }

    /**
     * @notice Handle post-operation fee collection
     * @dev Called by EntryPoint after UserOp execution
     * @param mode Whether the operation succeeded or reverted
     * @param context Context from validatePaymasterUserOp
     * @param actualGasCost Actual gas cost used
     * @param actualUserOpFeePerGas Actual fee per gas
     */
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external
        override
        onlyEntryPoint
    {
        (address token, address payer, uint256 maxTokenCost, bool isActivation, bool isFaucet) =
            abi.decode(context, (address, address, uint256, bool, bool));

        if (isActivation) {
            if (mode == PostOpMode.opSucceeded) {
                activationUsed[payer] = true;
            }
            emit ActivationSponsored(payer);
            return;
        }

        if (isFaucet) {
            return;
        }

        uint256 actualCostWithPostOp = actualGasCost + (COST_OF_POST * actualUserOpFeePerGas);
        uint256 actualTokenCost = _calculateTokenCost(token, actualCostWithPostOp);
        uint256 tokenCost = actualTokenCost < maxTokenCost ? actualTokenCost : maxTokenCost;

        if (mode != PostOpMode.postOpReverted) {
            IERC20(token).safeTransferFrom(payer, address(this), tokenCost);
            collectedFees[token] += tokenCost;

            emit GasSponsored(payer, token, tokenCost);
        }
    }

    /**
     * @notice Deposit ETH to EntryPoint for gas sponsorship
     */
    function deposit() external payable onlyOwner {
        entryPoint.depositTo{value: msg.value}(address(this));
        emit Deposited(address(this), msg.value);
    }

    /**
     * @notice Stake ETH in EntryPoint for paymaster reputation
     * @param unstakeDelaySec Unstake delay in seconds
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
        emit StakeAdded(msg.value, unstakeDelaySec);
    }

    /**
     * @notice Start stake unlock period in EntryPoint
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
        emit StakeUnlocked();
    }

    /**
     * @notice Withdraw stake from EntryPoint after unlock delay
     * @param withdrawAddress Address to receive ETH
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
        emit StakeWithdrawn(withdrawAddress, 0);
    }

    /**
     * @notice Withdraw deposited ETH from EntryPoint
     * @param withdrawAddress Address to send ETH
     * @param amount Amount to withdraw
     */
    function withdrawFromEntryPoint(address payable withdrawAddress, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
        emit Withdrawn(withdrawAddress, amount);
    }

    /**
     * @notice Get current deposit balance in EntryPoint
     * @return deposit Current deposit amount
     */
    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /**
     * @notice Calculate fee in stablecoin for a given ETH cost
     * @param token Stablecoin address
     * @param ethCost Cost in wei
     * @return tokenCost Cost in stablecoin
     */
    function calculateFee(address token, uint256 ethCost) external view returns (uint256 tokenCost) {
        require(supportedTokens[token], "Paymaster: token not supported");
        return _calculateTokenCost(token, ethCost);
    }

    /**
     * @notice Estimate total cost for a transaction
     * @param token Stablecoin address
     * @param gasLimit Estimated gas limit
     * @param maxFeePerGas Max fee per gas
     * @return gasCost Gas cost in stablecoin
     */
    function estimateTotalCost(address token, uint256 gasLimit, uint256 maxFeePerGas)
        external
        view
        returns (uint256 gasCost)
    {
        require(supportedTokens[token], "Paymaster: token not supported");

        uint256 maxEthCost = gasLimit * maxFeePerGas;
        gasCost = _calculateTokenCost(token, maxEthCost);

        return gasCost;
    }

    /**
     * @notice Withdraw collected stablecoin fees
     * @param token Token address
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function withdrawFees(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        require(to != address(0), "Paymaster: invalid recipient");
        require(amount <= collectedFees[token], "Paymaster: insufficient fees");

        collectedFees[token] -= amount;
        IERC20(token).safeTransfer(to, amount);

        emit FeesWithdrawn(token, amount, to);
    }

    /**
     * @notice Get collected fees for a token
     * @param token Token address
     * @return amount Collected fees
     */
    function getCollectedFees(address token) external view returns (uint256) {
        return collectedFees[token];
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Add or remove authorized signer
     * @param signer Signer address
     * @param authorized Whether signer is authorized
     */
    function setSigner(address signer, bool authorized) external onlyOwner {
        if (signer == address(0)) revert InvalidSigner();
        authorizedSigners[signer] = authorized;
        emit SignerUpdated(signer, authorized);
    }

    /**
     * @notice Add or update supported token -> khusus di paymaster
     * @param token Token address
     * @param isSupported Whether to support this token
     */
    function setSupportedToken(address token, bool isSupported) external onlyOwner {
        if (token == address(0)) revert InvalidToken();

        if (isSupported) {
            require(stablecoinRegistry.isStablecoinActive(token), "Paymaster: token not in registry");
        }

        supportedTokens[token] = isSupported;
        emit TokenSupportUpdated(token, isSupported);
    }

    /**
     * @notice Batch add supported tokens -> khusus di paymaster
     * @param tokens Array of token addresses
     */
    function addSupportedTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            require(stablecoinRegistry.isStablecoinActive(tokens[i]), "Paymaster: token not in registry");

            supportedTokens[tokens[i]] = true;
            emit TokenSupportUpdated(tokens[i], true);
        }
    }

    /**
     * @notice Update Stablecoin Registry
     * @param _stablecoinRegistry New registry address
     */
    function setStablecoinRegistry(address _stablecoinRegistry) external onlyOwner {
        require(_stablecoinRegistry != address(0), "Paymaster: invalid registry");

        address oldRegistry = address(stablecoinRegistry);
        stablecoinRegistry = IStablecoinRegistry(_stablecoinRegistry);

        emit RegistryUpdated(oldRegistry, _stablecoinRegistry);
    }

    /**
     * @notice Check if token is supported
     * @param token Token address
     * @return Whether token is supported
     */
    function isSupportedToken(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    /**
     * @notice Check if signer is authorized
     * @param signer Signer address
     * @return Whether signer is authorized
     */
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return authorizedSigners[signer];
    }

    /**
     * @notice Get gas-related bounds for transparency
     * @dev ETH/USD rate bounds are managed by StablecoinRegistry
     */
    function getGasBounds() external pure returns (uint256 minGasPrice, uint256 maxGasPrice) {
        return (MIN_GAS_PRICE, MAX_GAS_PRICE);
    }

    /**
     * @notice Calculate token cost from ETH cost
     * @param token Stablecoin address
     * @param ethCost Cost in wei
     * @return tokenCost Cost in stablecoin (with markup)
     */
    function _calculateTokenCost(address token, uint256 ethCost) internal view returns (uint256 tokenCost) {
        tokenCost = stablecoinRegistry.ethToToken(token, ethCost);
        tokenCost = tokenCost * (BPS_DENOMINATOR + GAS_MARKUP_BPS) / BPS_DENOMINATOR;

        return tokenCost;
    }

    /**
     * @notice Pack validation data for ERC-4337
     * @param sigFailed Whether signature validation failed
     * @param validUntil Validity end timestamp
     * @param validAfter Validity start timestamp
     * @return Packed validation data
     */
    function _packValidationData(bool sigFailed, uint48 validUntil, uint48 validAfter) internal pure returns (uint256) {
        return (sigFailed ? 1 : 0) | (uint256(validUntil) << 160) | (uint256(validAfter) << 208);
    }

    function _validateActivationCallData(bytes calldata callData) internal view {
        require(callData.length >= 4, "Paymaster: invalid callData");
        bytes4 selector = bytes4(callData);
        bytes4 executeSelector = bytes4(keccak256("execute(address,uint256,bytes)"));
        bytes4 executeBatchSelector = bytes4(keccak256("executeBatch(address[],uint256[],bytes[])"));
        bytes4 approveSelector = bytes4(keccak256("approve(address,uint256)"));

        if (selector == executeSelector) {
            (address dest, uint256 value, bytes memory data) = abi.decode(callData[4:], (address, uint256, bytes));
            require(value == 0, "Paymaster: nonzero value");
            require(stablecoinRegistry.isStablecoinActive(dest), "Paymaster: token not in registry");
            _validateApproveData(data, approveSelector);
            return;
        }

        require(selector == executeBatchSelector, "Paymaster: only executeBatch");
        (address[] memory dests, uint256[] memory values, bytes[] memory datas) =
            abi.decode(callData[4:], (address[], uint256[], bytes[]));
        require(dests.length == datas.length, "Paymaster: length mismatch");

        for (uint256 i = 0; i < dests.length; i++) {
            if (values.length != 0) {
                require(values[i] == 0, "Paymaster: nonzero value");
            }
            require(stablecoinRegistry.isStablecoinActive(dests[i]), "Paymaster: token not in registry");
            _validateApproveData(datas[i], approveSelector);
        }
    }

    function _isFaucetCall(bytes calldata callData, address token) internal view returns (bool) {
        if (callData.length < 4) {
            return false;
        }

        bytes4 selector = bytes4(callData);
        bytes4 executeSelector = bytes4(keccak256("execute(address,uint256,bytes)"));
        bytes4 executeBatchSelector = bytes4(keccak256("executeBatch(address[],uint256[],bytes[])"));
        bytes4 faucetSelector = bytes4(keccak256("faucet(uint256)"));

        if (selector == executeSelector) {
            (address dest, uint256 value, bytes memory data) = abi.decode(callData[4:], (address, uint256, bytes));
            if (value != 0 || dest != token) {
                return false;
            }
            return _isFaucetData(data, faucetSelector);
        }

        if (selector != executeBatchSelector) {
            return false;
        }

        (address[] memory dests, uint256[] memory values, bytes[] memory datas) =
            abi.decode(callData[4:], (address[], uint256[], bytes[]));

        if (dests.length != datas.length) {
            return false;
        }

        for (uint256 i = 0; i < dests.length; i++) {
            if (dests[i] != token) {
                return false;
            }
            if (values.length != 0 && values[i] != 0) {
                return false;
            }
            if (!_isFaucetData(datas[i], faucetSelector)) {
                return false;
            }
        }

        return true;
    }

    function _isFaucetData(bytes memory data, bytes4 faucetSelector) internal pure returns (bool) {
        if (data.length < 4 + 32) {
            return false;
        }
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        return selector == faucetSelector;
    }

    function _validateApproveData(bytes memory data, bytes4 approveSelector) internal view {
        require(data.length >= 4 + 32 + 32, "Paymaster: invalid approve");
        bytes4 selector;
        address spender;
        assembly {
            selector := mload(add(data, 32))
            spender := and(mload(add(data, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
        }
        require(selector == approveSelector, "Paymaster: only approve");
        require(spender == address(this), "Paymaster: invalid spender");
    }

    /**
     * @notice Emergency withdraw any stuck tokens
     * @param token Token address (address(0) for ETH)
     * @param to Recipient address
     */
    function emergencyWithdraw(address token, address to) external onlyOwner {
        require(to != address(0), "Paymaster: invalid recipient");

        if (token == address(0)) {
            uint256 balance = address(this).balance;
            (bool success,) = to.call{value: balance}("");
            require(success, "Paymaster: ETH transfer failed");
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(to, balance);
            collectedFees[token] = 0;
        }
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
