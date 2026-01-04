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
 * 
 * Architecture:
 * - Full ERC-4337 Account Abstraction support
 * - Works with Gelato Smart Wallet SDK (uses Gelato Bundler)
 * - Sponsors gas fees and collects payment in stablecoins
 * - Supports ERC-2612 Permit for gasless approval
 * 
 * Key Features:
 * - validatePaymasterUserOp: Validates and approves UserOperations
 * - postOp: Handles post-execution fee collection
 * - Gas fee markup (5% default for gas price volatility)
 * - Multi-stablecoin support via StablecoinRegistry
 */
contract Paymaster is IPaymaster, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ============ Constants ============
    
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

    // ============ State Variables ============
    
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

    // ============ Events ============
    
    event GasSponsored(
        address indexed sender,
        address indexed token,
        uint256 gasFee
    );
    
    event FeesWithdrawn(
        address indexed token,
        uint256 amount,
        address indexed to
    );
    
    event TokenSupportUpdated(address indexed token, bool isSupported);
    event SignerUpdated(address indexed signer, bool authorized);
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);

    // ============ Errors ============
    
    error InvalidEntryPoint();
    error InvalidToken();
    error InvalidSigner();
    error InsufficientDeposit();
    error InvalidSignature();
    error ExpiredSignature();
    error UsedNonce();

    // ============ Modifiers ============
    
    /**
     * @notice Restrict calls to EntryPoint only
     */
    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "Paymaster: not EntryPoint");
        _;
    }

    // ============ Constructor ============
    
    /**
     * @notice Initialize the ERC-4337 Paymaster
     * @param _entryPoint Address of the ERC-4337 EntryPoint contract
     * @param _stablecoinRegistry Address of the StablecoinRegistry contract
     */
    constructor(
        address _entryPoint,
        address _stablecoinRegistry
    ) Ownable(msg.sender) {
        if (_entryPoint == address(0)) revert InvalidEntryPoint();
        require(_stablecoinRegistry != address(0), "Paymaster: invalid registry");
        
        entryPoint = IEntryPoint(_entryPoint);
        stablecoinRegistry = IStablecoinRegistry(_stablecoinRegistry);
        
        // Owner is authorized signer by default
        authorizedSigners[msg.sender] = true;
        
        emit RegistryUpdated(address(0), _stablecoinRegistry);
        emit SignerUpdated(msg.sender, true);
    }

    // ============ ERC-4337 Paymaster Interface ============
    
    /**
     * @notice Validate a UserOperation for sponsorship
     * @dev Called by EntryPoint during validation phase
     *      Supports ERC-2612 permit for gasless approval
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation
     * @param maxCost Maximum cost the paymaster might pay
     * @return context Context to pass to postOp (token, sender, maxTokenCost)
     * @return validationData Validation result (0 = success)
     * 
     * paymasterAndData format (ERC-4337 v0.7):
     * 
     * Standard v0.7 header (52 bytes):
     * [paymaster (20)] [paymasterVerificationGasLimit (16 - uint128)] [paymasterPostOpGasLimit (16 - uint128)]
     * 
     * New custom data (payer can differ from sender):
     * Without permit (170 bytes total):
     *   [token (20)] [payer (20)] [validUntil (6)] [validAfter (6)] [hasPermit=0 (1)] [signature (65)]
     * With permit (267 bytes total):
     *   [token (20)] [payer (20)] [validUntil (6)] [validAfter (6)] [hasPermit=1 (1)] [deadline (32)] [v (1)] [r (32)] [s (32)] [signature (65)]
     * 
     * Byte offsets from start of paymasterAndData:
     * - 0-20:   Paymaster address (handled by EntryPoint)
     * - 20-36:  paymasterVerificationGasLimit (uint128 - handled by EntryPoint)
     * - 36-52:  paymasterPostOpGasLimit (uint128 - handled by EntryPoint)
     * - 52-72:  Token address
     * - 72-92:  Payer address (stablecoin payer)
     * - 92-98:  validUntil (uint48)
     * - 98-104: validAfter (uint48)
     * - 104:    hasPermit flag (uint8)
     * - 105+:   permit data (if hasPermit=1: deadline 32 + v 1 + r 32 + s 32) + signature (65 bytes)
     */
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override onlyEntryPoint whenNotPaused returns (bytes memory context, uint256 validationData) {
        // Minimum length check (header 52 + token 20 + payer 20 + time 12 + flag 1 + sig 65 = 170)
        require(userOp.paymasterAndData.length >= 170, "Paymaster: invalid paymasterAndData");

        address token = address(bytes20(userOp.paymasterAndData[52:72]));
        address payer = address(bytes20(userOp.paymasterAndData[72:92]));
        uint48 validUntil = uint48(bytes6(userOp.paymasterAndData[92:98]));
        uint48 validAfter = uint48(bytes6(userOp.paymasterAndData[98:104]));
        bool hasPermit = uint8(userOp.paymasterAndData[104]) == 1;
        
        bytes memory signature;

        // Handle permit if present
        if (hasPermit) {
            // Length check with permit (header 52 + custom 148 + permit 97 + sig 65 = 267)
            require(userOp.paymasterAndData.length >= 267, "Paymaster: invalid permit data");

            // Decode permit data (starts at byte 105)
            uint256 deadline = uint256(bytes32(userOp.paymasterAndData[105:137]));
            uint8 v = uint8(userOp.paymasterAndData[137]);
            bytes32 r = bytes32(userOp.paymasterAndData[138:170]);
            bytes32 s = bytes32(userOp.paymasterAndData[170:202]);

            // Execute permit (payer -> paymaster)
            IERC20Permit(token).permit(
                payer,
                address(this), // paymaster as spender
                type(uint256).max,
                deadline,
                v, r, s
            );

            // Signature starts at byte 202
            signature = userOp.paymasterAndData[202:];
        } else {
            // No permit, signature starts at byte 105
            signature = userOp.paymasterAndData[105:];
        }
        
        // Validate token is supported
        require(supportedTokens[token], "Paymaster: token not supported");

        // Payer must be set
        require(payer != address(0), "Paymaster: invalid payer");
        
        // Verify signature from authorized signer
        // Sign static components instead of userOpHash to avoid chicken-egg problem
        // Hash: keccak256(payer, token, validUntil, validAfter)
        bytes32 hash = keccak256(abi.encode(
            payer,          // Stablecoin payer (can be different from sender)
            token,
            validUntil,
            validAfter
        ));
        bytes32 signedHash = hash.toEthSignedMessageHash();
        address signer = signedHash.recover(signature);
        
        if (!authorizedSigners[signer]) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }
        
        // Calculate token cost from ETH cost
        uint256 tokenCost = _calculateTokenCost(token, maxCost);
        
        // Check payer has sufficient stablecoin balance
        require(IERC20(token).balanceOf(payer) >= tokenCost, "Paymaster: insufficient balance");
        
        // Check allowance (permit above sets allowance for paymaster as spender)
        require(
            IERC20(token).allowance(payer, address(this)) >= tokenCost,
            "Paymaster: insufficient allowance"
        );
        
        // Encode context for postOp
        context = abi.encode(token, payer, tokenCost);
        
        // Return validation data
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
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external override onlyEntryPoint {
        // Decode context
        (address token, address payer, uint256 maxTokenCost) = abi.decode(
            context,
            (address, address, uint256)
        );
        
        // Calculate actual token cost (with postOp gas included)
        uint256 actualCostWithPostOp = actualGasCost + (COST_OF_POST * actualUserOpFeePerGas);
        uint256 actualTokenCost = _calculateTokenCost(token, actualCostWithPostOp);
        
        // Use smaller of actual cost or max cost
        uint256 tokenCost = actualTokenCost < maxTokenCost ? actualTokenCost : maxTokenCost;
        
        
        // Collect fees from user
        if (mode != PostOpMode.postOpReverted) {
            IERC20(token).safeTransferFrom(payer, address(this), tokenCost);
            collectedFees[token] += tokenCost;
            
            emit GasSponsored(payer, token, tokenCost);
        }
    }

    // ============ Deposit Management ============
    
    /**
     * @notice Deposit ETH to EntryPoint for gas sponsorship
     */
    function deposit() external payable onlyOwner {
        entryPoint.depositTo{value: msg.value}(address(this));
        emit Deposited(address(this), msg.value);
    }

    /**
     * @notice Withdraw deposited ETH from EntryPoint
     * @param withdrawAddress Address to send ETH
     * @param amount Amount to withdraw
     */
    function withdrawFromEntryPoint(
        address payable withdrawAddress,
        uint256 amount
    ) external onlyOwner {
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

    // ============ Fee Calculation ============
    
    /**
     * @notice Calculate fee in stablecoin for a given ETH cost
     * @param token Stablecoin address
     * @param ethCost Cost in wei
     * @return tokenCost Cost in stablecoin
     */
    function calculateFee(
        address token,
        uint256 ethCost
    ) external view returns (uint256 tokenCost) {
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
    function estimateTotalCost(
        address token,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) external view returns (uint256 gasCost) {
        require(supportedTokens[token], "Paymaster: token not supported");
        
        uint256 maxEthCost = gasLimit * maxFeePerGas;
        gasCost = _calculateTokenCost(token, maxEthCost);
        
        return gasCost;
    }

    // ============ Fee Withdrawal ============
    
    /**
     * @notice Withdraw collected stablecoin fees
     * @param token Token address
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function withdrawFees(
        address token, 
        uint256 amount, 
        address to
    ) external onlyOwner nonReentrant {
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

    // ============ Admin Functions ============
    
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
            require(
                stablecoinRegistry.isStablecoinActive(token),
                "Paymaster: token not in registry"
            );
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
            require(
                stablecoinRegistry.isStablecoinActive(tokens[i]),
                "Paymaster: token not in registry"
            );
            
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

    // ============ View Functions ============
    
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
    function getGasBounds() external pure returns (
        uint256 minGasPrice,
        uint256 maxGasPrice
    ) {
        return (MIN_GAS_PRICE, MAX_GAS_PRICE);
    }

    // ============ Internal Functions ============
    
    /**
     * @notice Calculate token cost from ETH cost
     * @param token Stablecoin address
     * @param ethCost Cost in wei
     * @return tokenCost Cost in stablecoin (with markup)
     */
    function _calculateTokenCost(
        address token,
        uint256 ethCost
    ) internal view returns (uint256 tokenCost) {
        // Convert ETH to stablecoin via registry
        tokenCost = stablecoinRegistry.ethToToken(token, ethCost);
        
        // Apply gas markup (5%)
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
    function _packValidationData(
        bool sigFailed,
        uint48 validUntil,
        uint48 validAfter
    ) internal pure returns (uint256) {
        return (sigFailed ? 1 : 0) | (uint256(validUntil) << 160) | (uint256(validAfter) << 208);
    }

    // ============ Emergency Functions ============
    
    /**
     * @notice Emergency withdraw any stuck tokens
     * @param token Token address (address(0) for ETH)
     * @param to Recipient address
     */
    function emergencyWithdraw(address token, address to) external onlyOwner {
        require(to != address(0), "Paymaster: invalid recipient");
        
        if (token == address(0)) {
            uint256 balance = address(this).balance;
            (bool success, ) = to.call{value: balance}("");
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
