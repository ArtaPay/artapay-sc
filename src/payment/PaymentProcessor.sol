// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPaymentProcessor.sol";
import "../interfaces/IStableSwap.sol";
import "../interfaces/IStablecoinRegistry.sol";

contract PaymentProcessor is IPaymentProcessor, Ownable {
    IStableSwap public swap;
    IStablecoinRegistry public registry;
    address feeRecipient;

    uint256 constant PLATFORM_FEE = 50;
    uint256 constant SWAP_FEE = 10;
    uint256 constant BPS_DENOMINATOR = 10000;
    uint256 constant PAYMENT_EXPIRY = 5 minutes;

    mapping(bytes32 => PaymentRequest) public payments;
    uint256 private nonce;

    error InvalidAmount();
    error InvalidToken();
    error PaymentNotFound();
    error PaymentExpired();
    error PaymentAlreadyCompleted();
    error NotRecipient();
    error PaymentNotPending();
    error SlippageExceeded();

    constructor(
        address _swap,
        address _registry,
        address _feeRecipient
    ) Ownable(msg.sender) {
        swap = IStableSwap(_swap);
        registry = IStablecoinRegistry(_registry);
        feeRecipient = _feeRecipient;
    }

    function createPaymentRequest(
        address requestedToken,
        uint256 requestedAmount
    ) external returns (bytes32 requestId) {
        if (requestedAmount == 0) revert InvalidAmount();
        if (!registry.isStablecoinActive(requestedToken)) revert InvalidToken();

        uint256 expiresAt = block.timestamp + PAYMENT_EXPIRY;

        requestId = keccak256(
            abi.encodePacked(msg.sender, requestedToken, requestedAmount,block.timestamp, nonce));
        nonce++;

        payments[requestId] = PaymentRequest({
            requestId: requestId,
            recipient: msg.sender,
            requestedToken: requestedToken,
            requestedAmount: requestedAmount,
            payer: address(0),
            payToken: address(0),
            paidAmount: 0,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            status: PaymentStatus.Pending
        });

        emit PaymentRequestCreated(
            requestId,
            msg.sender,
            requestedToken,
            requestedAmount,
            expiresAt
        );

        return requestId;
    }

    function calculatePaymentCost(bytes32 requestId, address payToken) external view returns (FeeBreakdown memory) {
        PaymentRequest storage payment = payments[requestId];
        if (payment.recipient == address(0)) revert PaymentNotFound();
        if (payment.expiresAt < block.timestamp) revert PaymentExpired();
        if (payment.status != PaymentStatus.Pending) revert PaymentNotPending();

        bool needSwap = (payToken != payment.requestedToken);

        uint256 baseAmount = payment.requestedAmount;
        uint256 platformFee = (baseAmount * PLATFORM_FEE) / BPS_DENOMINATOR;
        uint256 totalRequired = baseAmount + platformFee;
        uint256 swapFee = 0;

        if (needSwap == true) {
            uint256 convertedAmount = registry.convert(
                payment.requestedToken,
                payToken,
                totalRequired
            );
            swapFee = (convertedAmount * SWAP_FEE) / BPS_DENOMINATOR;

            totalRequired = convertedAmount + swapFee;
        }

        return
            FeeBreakdown({
                baseAmount: baseAmount,
                platformFee: platformFee,
                swapFee: swapFee,
                totalRequired: totalRequired
            });
    }

    function executePayment(bytes32 requestId, uint256 maxAmountToPay, address payToken) external {
        PaymentRequest storage payment = payments[requestId];
        if (payment.recipient == address(0)) revert PaymentNotFound();
        if (payment.expiresAt < block.timestamp) revert PaymentExpired();
        if (payment.status != PaymentStatus.Pending) revert PaymentNotPending();
        if (!registry.isStablecoinActive(payToken)) revert InvalidToken();

        bool needSwap = (payToken != payment.requestedToken);
        uint256 baseAmount = payment.requestedAmount;
        uint256 platformFee = (baseAmount * PLATFORM_FEE) / BPS_DENOMINATOR;
        uint256 totalInRequestedToken = baseAmount + platformFee;

        uint256 totalRequired;
        uint256 swapFee = 0;

        if (needSwap) {
            uint256 totalInPayToken = registry.convert(payment.requestedToken, payToken, totalInRequestedToken);
            swapFee = (totalInPayToken * SWAP_FEE) / BPS_DENOMINATOR;
            totalRequired = totalInPayToken + swapFee;
        } else {
            totalRequired = totalInRequestedToken;
        }

        if (totalRequired > maxAmountToPay) revert SlippageExceeded();

        IERC20(payToken).transferFrom(msg.sender, address(this), totalRequired);

        uint256 amountForRecipient = baseAmount;
        uint256 amountForFeeRecipient = platformFee;

        if (needSwap) {
            IERC20(payToken).approve(address(swap), totalRequired);

            uint256 swapAmountIn = totalRequired - swapFee;
            swap.swap(swapAmountIn, payToken, payment.requestedToken, totalInRequestedToken);
        }

        IERC20(payment.requestedToken).transfer(payment.recipient, amountForRecipient);
        
        IERC20(payment.requestedToken).transfer(feeRecipient, amountForFeeRecipient);

        payment.payer = msg.sender;
        payment.payToken = payToken;
        payment.paidAmount = totalRequired;
        payment.status = PaymentStatus.Completed;

        emit PaymentCompleted(requestId, msg.sender, payToken, totalRequired);
    }

    function cancelPayment(bytes32 requestId) external {
        PaymentRequest storage payment = payments[requestId];
        if (payment.recipient == address(0)) revert PaymentNotFound();
        if (payment.recipient != msg.sender) revert NotRecipient();
        if (payment.status != PaymentStatus.Pending) revert PaymentNotPending();

        payment.status = PaymentStatus.Cancelled;

        emit PaymentCancelled(requestId);
    }

    function getPayment(bytes32 requestId) external view returns (PaymentRequest memory) {
        return payments[requestId];
    }
}
