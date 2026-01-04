// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC4337.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SimpleAccount
 * @notice Minimal ERC-4337 smart account compatible with EntryPoint v0.7
 * @dev Owner-signature based account. No modules/guards for simplicity.
 */
contract SimpleAccount is IAccount {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address public owner;
    IEntryPoint public immutable entryPoint;

    event SimpleAccountInitialized(address indexed owner, address indexed entryPoint);

    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "SimpleAccount: not EntryPoint");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SimpleAccount: not owner");
        _;
    }

    constructor(IEntryPoint _entryPoint, address _owner) {
        require(address(_entryPoint) != address(0), "SimpleAccount: invalid entrypoint");
        require(_owner != address(0), "SimpleAccount: invalid owner");
        entryPoint = _entryPoint;
        owner = _owner;
        emit SimpleAccountInitialized(_owner, address(_entryPoint));
    }

    /**
     * @notice Execute a call from the smart account.
     */
    function execute(address dest, uint256 value, bytes calldata func) external onlyOwner {
        _call(dest, value, func);
    }

    /**
     * @notice Execute multiple calls.
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external onlyOwner {
        require(dest.length == func.length, "SimpleAccount: length mismatch");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /**
     * @notice ERC-4337 validation hook.
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override onlyEntryPoint returns (uint256 validationData) {
        _validateSignature(userOpHash, userOp.signature);

        if (missingAccountFunds > 0) {
            entryPoint.depositTo{value: missingAccountFunds}(address(this));
        }
        return 0;
    }

    /**
     * @notice Current nonce from EntryPoint.
     */
    function getNonce() external view returns (uint256) {
        return entryPoint.getNonce(address(this), 0);
    }

    /**
     * @notice Deposit ETH to EntryPoint for this account.
     */
    function addDeposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /**
     * @notice Withdraw deposited ETH from EntryPoint.
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    function _validateSignature(bytes32 userOpHash, bytes calldata signature) internal view {
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        address signer = ECDSA.recover(digest, signature);
        require(signer == owner, "SimpleAccount: invalid signature");
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    receive() external payable {}
}
