// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPaymentProcessor
 * @notice Interface for processing QR payment requests with off-chain merchant signatures
 * @dev Enables gasless payment requests for merchants via off-chain signing
 */
interface IPaymentProcessor {
    /// @notice Payment status enum
    enum PaymentStatus { Pending, Completed, Cancelled, Expired }

    /**
     * @notice Payment request data signed by merchant off-chain
     * @param recipient Merchant payout address
     * @param requestedToken Token merchant wants to receive
     * @param requestedAmount Amount merchant wants
     * @param deadline Expiry timestamp
     * @param nonce Unique nonce for replay protection
     * @param merchantSigner EOA that signs off-chain request
     */
    struct PaymentRequest {
        address recipient;       
        address requestedToken;  
        uint256 requestedAmount; 
        uint256 deadline;       
        bytes32 nonce;           
        address merchantSigner;  
    }

    /**
     * @notice Fee breakdown for payment calculation
     * @param baseAmount Base amount before fees
     * @param platformFee Platform fee (0.3%)
     * @param swapFee Swap fee if cross-token payment (0.1%)
     * @param totalRequired Total amount user needs to pay
     */
    struct FeeBreakdown {
        uint256 baseAmount;
        uint256 platformFee;    
        uint256 swapFee;        
        uint256 totalRequired; 
    }

    /**
     * @notice Emitted when payment is completed
     * @param nonce Unique payment request nonce
     * @param recipient Merchant address
     * @param payer Customer address
     * @param requestedToken Token merchant requested
     * @param payToken Token customer paid with
     * @param requestedAmount Amount merchant requested
     * @param paidAmount Total amount customer paid
     */
    event PaymentCompleted(
        bytes32 indexed nonce,
        address indexed recipient,
        address indexed payer,
        address requestedToken,
        address payToken,
        uint256 requestedAmount,
        uint256 paidAmount
    );

    /**
     * @notice Calculate payment cost including fees
     * @param requestedToken Token merchant wants
     * @param requestedAmount Amount merchant wants
     * @param payToken Token customer will pay with
     * @return Fee breakdown showing total cost
     */
    function calculatePaymentCost(
        address requestedToken,
        uint256 requestedAmount,
        address payToken
    ) external view returns (FeeBreakdown memory);

    /**
     * @notice Execute payment with merchant's off-chain signature
     * @param request Payment request data
     * @param merchantSignature Merchant's signature over request
     * @param payToken Token customer pays with
     * @param maxAmountToPay Maximum amount customer willing to pay
     */
    function executePayment(
        PaymentRequest calldata request,
        bytes calldata merchantSignature,
        address payToken,
        uint256 maxAmountToPay
    ) external;
}
