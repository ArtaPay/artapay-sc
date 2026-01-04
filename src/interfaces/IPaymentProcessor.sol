// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPaymentProcessor {
    enum PaymentStatus { Pending, Completed, Cancelled, Expired }

    struct PaymentRequest {
        bytes32 requestId;
        address recipient;
        address requestedToken;
        uint256 requestedAmount;
        address payer;
        address payToken;
        uint256 paidAmount;
        uint256 createdAt;
        uint256 expiresAt;
        PaymentStatus status;
    }


    struct FeeBreakdown {
        uint256 baseAmount;
        uint256 platformFee;    // 0.5%
        uint256 swapFee;        // 0.1% (jika swap)
        uint256 totalRequired;  //total yg user bayar
    }

    event PaymentRequestCreated(bytes32 indexed requestId, address indexed recipient, address requestedToken, uint256 requestedAmount, uint256 expiresAt );
    event PaymentCompleted(bytes32 indexed requestId, address indexed payer, address payToken, uint256 paidAmount);
    event PaymentCancelled(bytes32 indexed requestId);

    function createPaymentRequest(address requestedToken, uint256 requestedAmount) external returns(bytes32 requestId);
    function calculatePaymentCost(bytes32 requestId, address payToken) external view returns(FeeBreakdown memory);
    function executePayment(bytes32 requestId, uint256 maxAmountToPay, address payToken) external;
    function cancelPayment(bytes32 requestId) external;
    function getPayment(bytes32 requestId) external view returns (PaymentRequest memory);
}