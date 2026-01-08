// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC-4337 Core Interfaces
 * @notice Standard interfaces required for ERC-4337 Account Abstraction
 * @dev Based on account-abstraction
 */

/// @notice UserOperation structure for ERC-4337
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

/// @notice Validation result returned by validateUserOp
struct ValidationData {
    uint256 validAfter;
    uint256 validUntil;
    bool sigFailed;
}

/// @notice Post-operation mode
enum PostOpMode {
    opSucceeded,
    opReverted,
    postOpReverted
}

/**
 * @title IEntryPoint
 * @notice Standard interface for ERC-4337 EntryPoint
 */
interface IEntryPoint {
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);
    function getNonce(address sender, uint192 key) external view returns (uint256);
    function depositTo(address account) external payable;
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;
    function getDepositInfo(address account)
        external
        view
        returns (uint256 deposit, bool staked, uint112 stake, uint32 unstakeDelaySec, uint48 withdrawTime);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title IPaymaster (ERC-4337)
 * @notice Standard Paymaster interface for ERC-4337
 * @dev Must be implemented by all ERC-4337 Paymasters
 */
interface IPaymaster {
    /**
     * @notice Validate a UserOperation and decide whether to sponsor it
     * @param userOp - The UserOperation to validate
     * @param userOpHash - Hash of the UserOperation
     * @param maxCost - Maximum cost in wei the paymaster might pay
     * @return context - Context to pass to postOp (can be empty)
     * @return validationData - Packed validation data (sigFailed, validUntil, validAfter)
     */
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        returns (bytes memory context, uint256 validationData);

    /**
     * @notice Post-operation handler (called after UserOp execution)
     * @param mode - Whether the UserOp succeeded or reverted
     * @param context - Context from validatePaymasterUserOp
     * @param actualGasCost - Actual gas cost used
     * @param actualUserOpFeePerGas - Actual fee per gas
     */
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external;
}

/**
 * @title IAccount (ERC-4337)
 * @notice Standard Account interface for ERC-4337 Smart Accounts
 */
interface IAccount {
    /**
     * @notice Validate a UserOperation
     * @param userOp - The UserOperation to validate
     * @param userOpHash - Hash of the UserOperation
     * @param missingAccountFunds - Amount to deposit to EntryPoint
     * @return validationData - Packed validation data
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}
