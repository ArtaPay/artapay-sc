// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC4337.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleAccount
 * @notice Minimal ERC-4337 smart account compatible with EntryPoint v0.7
 * @dev Owner-signature based account
 */
contract SimpleAccount is IAccount, Initializable, UUPSUpgradeable {
    using MessageHashUtils for bytes32;

    uint256 private constant SIG_VALIDATION_FAILED = 1;
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _CSW_TYPEHASH = keccak256("CoinbaseSmartWalletMessage(bytes32 hash)");
    bytes32 private constant _CSW_NAME_HASH = keccak256("Coinbase Smart Wallet");
    bytes32 private constant _CSW_VERSION_HASH = keccak256("1");

    address public owner;
    IEntryPoint public immutable entryPoint;

    event SimpleAccountInitialized(address indexed owner, address indexed entryPoint);

    /// @notice Restricts function to EntryPoint only
    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "SimpleAccount: not EntryPoint");
        _;
    }

    /// @notice Restricts function to owner only
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /**
     * @notice Initialize the implementation
     * @param _entryPoint ERC-4337 EntryPoint address
     */
    constructor(IEntryPoint _entryPoint) {
        require(address(_entryPoint) != address(0), "SimpleAccount: invalid entrypoint");
        entryPoint = _entryPoint;
        _disableInitializers();
    }

    /**
     * @notice Initialize the smart account
     * @param _owner Owner address for this account
     */
    function initialize(address _owner) public initializer {
        require(_owner != address(0), "SimpleAccount: invalid owner");
        owner = _owner;
        emit SimpleAccountInitialized(_owner, address(entryPoint));
    }

    /**
     * @notice Execute a call from the smart account
     * @param dest Destination address
     * @param value ETH value to send
     * @param func Calldata to execute
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * @notice Execute multiple calls
     * @param dest Array of destination addresses
     * @param value Array of ETH values (empty array = all zero)
     * @param func Array of calldata
     */
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(
            dest.length == func.length && (value.length == 0 || value.length == func.length),
            "SimpleAccount: length mismatch"
        );
        if (value.length == 0) {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], 0, func[i]);
            }
            return;
        }
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], value[i], func[i]);
        }
    }

    /**
     * @notice ERC-4337 validation hook
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param missingAccountFunds Funds needed in EntryPoint
     * @return validationData Validation result (0 = success)
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        onlyEntryPoint
        returns (uint256 validationData)
    {
        if (!_validateSignature(userOpHash, userOp.signature)) {
            return SIG_VALIDATION_FAILED;
        }

        if (missingAccountFunds > 0) {
            entryPoint.depositTo{value: missingAccountFunds}(address(this));
        }
        return 0;
    }

    /**
     * @notice Get current nonce from EntryPoint
     * @return Current nonce value
     */
    function getNonce() external view returns (uint256) {
        return entryPoint.getNonce(address(this), 0);
    }

    /**
     * @notice Deposit ETH to EntryPoint for this account
     */
    function addDeposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /**
     * @notice Withdraw deposited ETH from EntryPoint
     * @param withdrawAddress Address to receive ETH
     * @param amount Amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /**
     * @notice Validate signature from owner
     * @param userOpHash Hash to validate
     * @param signature Signature to check
     */
    function _validateSignature(bytes32 userOpHash, bytes calldata signature) internal view returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(userOpHash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == owner) {
            return true;
        }

        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (address recoveredEth, ECDSA.RecoverError errEth,) = ECDSA.tryRecover(digest, signature);
        if (errEth == ECDSA.RecoverError.NoError && recoveredEth == owner) {
            return true;
        }

        if (_isValidERC1271Signature(userOpHash, signature)) {
            return true;
        }

        bytes32 cswDigest = _coinbaseSmartWalletDigest(userOpHash);
        if (_isValidERC1271Signature(cswDigest, signature)) {
            return true;
        }

        (bool ok, bytes memory data) = owner.staticcall(abi.encodeWithSignature("replaySafeHash(bytes32)", userOpHash));
        if (ok && data.length == 32) {
            bytes32 replaySafeHash = abi.decode(data, (bytes32));
            if (_isValidERC1271Signature(replaySafeHash, signature)) {
                return true;
            }
        }

        return _isValidERC1271Signature(digest, signature);
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner || msg.sender == address(this), "SimpleAccount: not owner");
    }

    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint) || msg.sender == owner, "SimpleAccount: not owner");
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        newImplementation;
        _onlyOwner();
    }

    /**
     * @notice Internal function to execute a call
     * @param target Target address
     * @param value ETH value
     * @param data Calldata
     */
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _isValidERC1271Signature(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        (bool ok, bytes memory result) =
            owner.staticcall(abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature));
        return ok && result.length >= 4 && bytes4(result) == IERC1271.isValidSignature.selector;
    }

    function _coinbaseSmartWalletDigest(bytes32 userOpHash) internal view returns (bytes32) {
        bytes32 domainSeparator =
            keccak256(abi.encode(_DOMAIN_TYPEHASH, _CSW_NAME_HASH, _CSW_VERSION_HASH, block.chainid, owner));
        bytes32 structHash = keccak256(abi.encode(_CSW_TYPEHASH, userOpHash));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// @notice Accept ETH transfers
    receive() external payable {}
}
