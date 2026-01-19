// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../interfaces/IPaymentProcessor.sol";
import "../interfaces/IStableSwap.sol";
import "../interfaces/IStablecoinRegistry.sol";

/**
 * @title PaymentProcessor
 * @notice Handles payment requests via off-chain signatures (Gasless for Merchant)
 * @dev Merchant signs request off-chain (FREE), payer submits with signature.
 */
contract PaymentProcessor is IPaymentProcessor, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    IStableSwap public swap;
    IStablecoinRegistry public registry;
    address public feeRecipient;

    uint256 public constant PLATFORM_FEE = 30; // 0.3% (30 BPS)
    uint256 public constant BPS_DENOMINATOR = 10000;

    mapping(bytes32 => bool) public usedNonces;

    error InvalidAmount();
    error InvalidToken();
    error InvalidRecipient();
    error InvalidSignature();
    error SlippageExceeded();
    error NonceAlreadyUsed();
    error DeadlineExpired();
    error InvalidPaymentArray();
    error InsufficientPayment();

    constructor(address _swap, address _registry, address _feeRecipient) Ownable(msg.sender) {
        swap = IStableSwap(_swap);
        registry = IStablecoinRegistry(_registry);
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Calculate payment cost for a request (pure calculation, no storage read)
     * @param requestedToken Token the merchant wants to receive
     * @param requestedAmount Amount the merchant wants
     * @param payToken Token the payer will use
     */
    function calculatePaymentCost(address requestedToken, uint256 requestedAmount, address payToken)
        external
        view
        returns (FeeBreakdown memory)
    {
        if (!registry.isStablecoinActive(requestedToken)) revert InvalidToken();
        if (!registry.isStablecoinActive(payToken)) revert InvalidToken();

        return _calculateCost(requestedToken, requestedAmount, payToken);
    }

    /**
     * @notice Execute payment using off-chain signed request (GASLESS FOR MERCHANT)
     * @dev Merchant signs the request off-chain, payer submits with the signature
     * @param request The payment request data signed by merchant
     * @param merchantSignature Merchant's signature over the request hash
     * @param payToken Token the payer will use
     * @param maxAmountToPay Maximum amount payer is willing to pay (slippage protection)
     */
    function executePayment(
        PaymentRequest calldata request,
        bytes calldata merchantSignature,
        address payToken,
        uint256 maxAmountToPay
    ) external {
        if (request.recipient == address(0)) revert InvalidRecipient();
        if (request.requestedAmount == 0) revert InvalidAmount();
        if (request.deadline < block.timestamp) revert DeadlineExpired();
        if (usedNonces[request.nonce]) revert NonceAlreadyUsed();
        if (!registry.isStablecoinActive(request.requestedToken)) revert InvalidToken();
        if (!registry.isStablecoinActive(payToken)) revert InvalidToken();
        if (request.merchantSigner == address(0)) revert InvalidSignature();

        bytes32 requestHash = _hashPaymentRequest(request);
        bytes32 ethSignedHash = requestHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedHash.recover(merchantSignature);

        if (recoveredSigner != request.merchantSigner) revert InvalidSignature();

        usedNonces[request.nonce] = true;

        FeeBreakdown memory cost = _calculateCost(request.requestedToken, request.requestedAmount, payToken);

        if (cost.totalRequired > maxAmountToPay) revert SlippageExceeded();

        _processPayment(msg.sender, request.recipient, payToken, request.requestedToken, request.requestedAmount, cost);

        emit PaymentCompleted(
            request.nonce,
            request.recipient,
            msg.sender,
            request.requestedToken,
            payToken,
            request.requestedAmount,
            cost.totalRequired
        );
    }

    /**
     * @notice Execute payment using multiple tokens (SPLIT PAYMENT)
     * @dev Merchant signs the request off-chain, payer can pay with multiple tokens
     * @param request The payment request data signed by merchant
     * @param merchantSignature Merchant's signature over the request hash
     * @param payments Array of token/amount pairs the payer will use
     */
    function executeMultiTokenPayment(
        PaymentRequest calldata request,
        bytes calldata merchantSignature,
        IPaymentProcessor.TokenPayment[] calldata payments
    ) external {
        // Validate request
        if (request.recipient == address(0)) revert InvalidRecipient();
        if (request.requestedAmount == 0) revert InvalidAmount();
        if (request.deadline < block.timestamp) revert DeadlineExpired();
        if (usedNonces[request.nonce]) revert NonceAlreadyUsed();
        if (!registry.isStablecoinActive(request.requestedToken)) revert InvalidToken();
        if (request.merchantSigner == address(0)) revert InvalidSignature();
        if (payments.length == 0) revert InvalidPaymentArray();

        // Verify merchant signature
        bytes32 requestHash = _hashPaymentRequest(request);
        bytes32 ethSignedHash = requestHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedHash.recover(merchantSignature);

        if (recoveredSigner != request.merchantSigner) revert InvalidSignature();

        // Mark nonce as used
        usedNonces[request.nonce] = true;

        // Track amounts for event
        address[] memory tokensUsed = new address[](payments.length);
        uint256[] memory amountsUsed = new uint256[](payments.length);

        uint256 totalCollectedInRequestedToken = 0;

        // Process each payment token
        for (uint256 i = 0; i < payments.length; i++) {
            address payToken = payments[i].token;
            uint256 payAmount = payments[i].amount;

            if (!registry.isStablecoinActive(payToken)) revert InvalidToken();
            if (payAmount == 0) revert InvalidAmount();

            tokensUsed[i] = payToken;
            amountsUsed[i] = payAmount;

            // Transfer from payer to contract
            IERC20(payToken).safeTransferFrom(msg.sender, address(this), payAmount);

            // Convert to requested token if needed
            if (payToken != request.requestedToken) {
                // Calculate swap fee (0.1%)
                uint256 swapFee = (payAmount * 10) / BPS_DENOMINATOR;
                uint256 amountToSwap = payAmount - swapFee;

                // Approve and swap
                IERC20(payToken).approve(address(swap), payAmount);
                
                // Get expected output
                uint256 expectedOut = registry.convert(payToken, request.requestedToken, amountToSwap);
                
                // Execute swap
                swap.swap(amountToSwap, payToken, request.requestedToken, expectedOut);

                // Add swapped amount to total
                totalCollectedInRequestedToken += expectedOut;
            } else {
                // Same token, just add directly
                totalCollectedInRequestedToken += payAmount;
            }
        }

        // Calculate platform fee (0.3% of requested amount)
        uint256 platformFee = (request.requestedAmount * PLATFORM_FEE) / BPS_DENOMINATOR;
        uint256 requiredTotal = request.requestedAmount + platformFee;

        // Ensure payer sent enough to cover merchant amount + platform fee
        if (totalCollectedInRequestedToken < requiredTotal) revert InsufficientPayment();

        // Pay merchant and fee recipient
        IERC20(request.requestedToken).safeTransfer(request.recipient, request.requestedAmount);
        IERC20(request.requestedToken).safeTransfer(feeRecipient, platformFee);

        // Return excess to payer if any
        uint256 excess = totalCollectedInRequestedToken - requiredTotal;
        if (excess > 0) {
            IERC20(request.requestedToken).safeTransfer(msg.sender, excess);
        }

        emit MultiTokenPaymentCompleted(
            request.nonce,
            request.recipient,
            msg.sender,
            request.requestedToken,
            request.requestedAmount,
            tokensUsed,
            amountsUsed
        );
    }

    /**
     * @notice Check if a nonce has been used
     */
    function isNonceUsed(bytes32 nonceValue) external view returns (bool) {
        return usedNonces[nonceValue];
    }

    /**
     * @notice Get the hash of a payment request (for merchant to sign)
     * @dev This is a helper for frontend/backend to construct the correct hash
     */
    function getPaymentRequestHash(PaymentRequest calldata request) external view returns (bytes32) {
        return _hashPaymentRequest(request);
    }

    /**
     * @dev Calculate fee breakdown for a payment
     */
    function _calculateCost(address requestedToken, uint256 requestedAmount, address payToken)
        internal
        view
        returns (FeeBreakdown memory)
    {
        bool needSwap = (payToken != requestedToken);

        uint256 baseAmount = requestedAmount;
        uint256 platformFee = (baseAmount * PLATFORM_FEE) / BPS_DENOMINATOR;
        uint256 totalInRequestedToken = baseAmount + platformFee;
        uint256 swapFee = 0;
        uint256 totalRequired = totalInRequestedToken;

        if (needSwap) {
            uint256 payTokenAmount = registry.convert(requestedToken, payToken, totalInRequestedToken);

            uint256 swappedOut = registry.convert(payToken, requestedToken, payTokenAmount);
            if (swappedOut < totalInRequestedToken) {
                if (swappedOut == 0) {
                    payTokenAmount += 1;
                } else {
                    uint256 adjusted = (payTokenAmount * totalInRequestedToken + swappedOut - 1) / swappedOut;
                    if (adjusted <= payTokenAmount) {
                        adjusted = payTokenAmount + 1;
                    }
                    payTokenAmount = adjusted;
                }

                swappedOut = registry.convert(payToken, requestedToken, payTokenAmount);
                if (swappedOut < totalInRequestedToken) {
                    payTokenAmount += 1;
                }
            }

            swapFee = (payTokenAmount * 10) / BPS_DENOMINATOR;
            totalRequired = payTokenAmount + swapFee;
        }

        return FeeBreakdown({
            baseAmount: baseAmount, platformFee: platformFee, swapFee: swapFee, totalRequired: totalRequired
        });
    }

    /**
     * @dev Process the actual payment transfer
     */
    function _processPayment(
        address payer,
        address recipient,
        address payToken,
        address requestedToken,
        uint256 requestedAmount,
        FeeBreakdown memory cost
    ) internal {
        bool needSwap = (payToken != requestedToken);

        IERC20(payToken).safeTransferFrom(payer, address(this), cost.totalRequired);

        uint256 amountForRecipient = requestedAmount;
        uint256 amountForFeeRecipient = cost.platformFee;

        if (needSwap) {
            uint256 baseAmountForSwap = cost.totalRequired - cost.swapFee;

            IERC20(payToken).approve(address(swap), cost.totalRequired);
            swap.swap(baseAmountForSwap, payToken, requestedToken, requestedAmount + amountForFeeRecipient);
        }

        IERC20(requestedToken).safeTransfer(recipient, amountForRecipient);
        IERC20(requestedToken).safeTransfer(feeRecipient, amountForFeeRecipient);
    }

    /**
     * @dev Hash the payment request for signature verification
     */
    function _hashPaymentRequest(PaymentRequest calldata request) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                address(this),
                block.chainid,
                request.recipient,
                request.requestedToken,
                request.requestedAmount,
                request.deadline,
                request.nonce,
                request.merchantSigner
            )
        );
    }

    /**
     * @notice Update fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Update swap contract
     */
    function setSwap(address _swap) external onlyOwner {
        require(_swap != address(0), "Invalid swap address");
        swap = IStableSwap(_swap);
    }

    /**
     * @notice Update registry contract
     */
    function setRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "Invalid registry address");
        registry = IStablecoinRegistry(_registry);
    }
}
