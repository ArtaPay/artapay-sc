// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPaymentProcessor {
    enum PaymentStatus { Pending, Completed, Cancelled, Expired }

    /// @notice Payment request data (signed by merchant off-chain)
    struct PaymentRequest {
        address recipient;       // Merchant payout address (can be Smart Account)
        address requestedToken;  // Token merchant wants to receive
        uint256 requestedAmount; // Amount merchant wants
        uint256 deadline;        // Expiry timestamp
        bytes32 nonce;           // Unique nonce for replay protection
        address merchantSigner;  // EOA that signs off-chain request
    }

    struct FeeBreakdown {
        uint256 baseAmount;
        uint256 platformFee;    // 0.3%
        uint256 swapFee;        // 0.1% (if swap needed)
        uint256 totalRequired;  // Total user pays
    }

    // Events
    event PaymentCompleted(
        bytes32 indexed nonce,
        address indexed recipient,
        address indexed payer,
        address requestedToken,
        address payToken,
        uint256 requestedAmount,
        uint256 paidAmount
    );

    // Off-chain flow (gasless for merchant) is the ONLY flow now
    function calculatePaymentCost(
        address requestedToken,
        uint256 requestedAmount,
        address payToken
    ) external view returns (FeeBreakdown memory);

    function executePayment(
        PaymentRequest calldata request,
        bytes calldata merchantSignature,
        address payToken,
        uint256 maxAmountToPay
    ) external;
}
