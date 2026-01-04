// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/payment/PaymentProcessor.sol";
import "../src/swap/StableSwap.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/token/MockStableCoin.sol";

contract PaymentProcessorTest is Test {
    PaymentProcessor public processor;
    StableSwap public stableSwap;
    StablecoinRegistry public registry;

    MockStableCoin public usdc;
    MockStableCoin public idrx;

    address public owner = address(this);
    address public feeRecipient = address(0xFEE);
    address public merchant = address(0x1); // Recipient
    address public customer = address(0x2); // Payer

    uint256 constant USDC_RATE = 1e8; // 1 USDC = 1 USD
    uint256 constant IDRX_RATE = 16000e8; // 16000 IDRX = 1 USD

    function setUp() public {
        // Deploy Registry
        registry = new StablecoinRegistry();

        // Deploy Mock Stablecoins
        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        idrx = new MockStableCoin("Indonesian Rupiah Token", "IDRX", 2, "ID");

        // Register stablecoins
        registry.registerStablecoin(address(usdc), "USDC", "US", USDC_RATE);
        registry.registerStablecoin(address(idrx), "IDRX", "ID", IDRX_RATE);

        // Deploy StableSwap
        stableSwap = new StableSwap(address(registry));

        // Deploy PaymentProcessor
        processor = new PaymentProcessor(
            address(stableSwap),
            address(registry),
            feeRecipient
        );

        // Fund StableSwap with liquidity
        usdc.mint(owner, 1000000 * 10 ** 6);
        idrx.mint(owner, 16000000000 * 10 ** 2);

        usdc.approve(address(stableSwap), type(uint256).max);
        idrx.approve(address(stableSwap), type(uint256).max);

        stableSwap.deposit(address(usdc), 100000 * 10 ** 6); // 100K USDC
        stableSwap.deposit(address(idrx), 1600000000 * 10 ** 2); // 1.6B IDRX

        // Fund customer with tokens
        usdc.mint(customer, 10000 * 10 ** 6); // 10K USDC
        idrx.mint(customer, 160000000 * 10 ** 2); // 160M IDRX
    }

    // ============ CREATE PAYMENT REQUEST TESTS ============

    function test_CreatePaymentRequest() public {
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        IPaymentProcessor.PaymentRequest memory payment = processor.getPayment(
            requestId
        );

        assertEq(payment.recipient, merchant);
        assertEq(payment.requestedToken, address(usdc));
        assertEq(payment.requestedAmount, 100 * 10 ** 6);
        assertEq(
            uint256(payment.status),
            uint256(IPaymentProcessor.PaymentStatus.Pending)
        );
        assertEq(payment.payer, address(0));
    }

    function test_CreatePaymentRequest_RevertIfZeroAmount() public {
        vm.prank(merchant);
        vm.expectRevert(PaymentProcessor.InvalidAmount.selector);
        processor.createPaymentRequest(address(usdc), 0);
    }

    function test_CreatePaymentRequest_RevertIfInvalidToken() public {
        vm.prank(merchant);
        vm.expectRevert(PaymentProcessor.InvalidToken.selector);
        processor.createPaymentRequest(address(0x999), 100);
    }

    // ============ CALCULATE PAYMENT COST TESTS ============

    function test_CalculatePaymentCost_SameToken() public {
        // Merchant wants 100 USDC
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Customer wants to pay with USDC (same token)
        IPaymentProcessor.FeeBreakdown memory cost = processor
            .calculatePaymentCost(requestId, address(usdc));

        // Platform fee = 0.5% of 100 USDC = 0.5 USDC
        assertEq(cost.baseAmount, 100 * 10 ** 6);
        assertEq(cost.platformFee, 500000); // 0.5 USDC
        assertEq(cost.swapFee, 0); // No swap
        assertEq(cost.totalRequired, 100500000); // 100.5 USDC
    }

    function test_CalculatePaymentCost_DifferentToken() public {
        // Merchant wants 100 USDC
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Customer wants to pay with IDRX (different token)
        IPaymentProcessor.FeeBreakdown memory cost = processor
            .calculatePaymentCost(requestId, address(idrx));

        // Base + platform fee in USDC = 100.5 USDC
        // Converted to IDRX = 100.5 * 16000 = 1,608,000 IDRX
        // Swap fee = 0.1% of 1,608,000 = 1,608 IDRX
        // Total = 1,608,000 + 1,608 = 1,609,608 IDRX

        assertEq(cost.baseAmount, 100 * 10 ** 6);
        assertGt(cost.swapFee, 0);
        assertGt(cost.totalRequired, cost.baseAmount);
    }

    // ============ EXECUTE PAYMENT TESTS ============

    function test_ExecutePayment_SameToken() public {
        // Merchant creates payment request for 100 USDC
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Get cost
        IPaymentProcessor.FeeBreakdown memory cost = processor
            .calculatePaymentCost(requestId, address(usdc));

        // Customer pays with USDC
        vm.startPrank(customer);
        usdc.approve(address(processor), cost.totalRequired);

        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(feeRecipient);

        processor.executePayment(requestId, cost.totalRequired, address(usdc));
        vm.stopPrank();

        // Check merchant received base amount
        assertEq(
            usdc.balanceOf(merchant),
            merchantBalanceBefore + 100 * 10 ** 6
        );

        // Check fee recipient received platform fee
        assertEq(
            usdc.balanceOf(feeRecipient),
            feeRecipientBalanceBefore + cost.platformFee
        );

        // Check payment status
        IPaymentProcessor.PaymentRequest memory payment = processor.getPayment(
            requestId
        );
        assertEq(
            uint256(payment.status),
            uint256(IPaymentProcessor.PaymentStatus.Completed)
        );
        assertEq(payment.payer, customer);
    }

    function test_ExecutePayment_DifferentToken_AutoSwap() public {
        // Merchant creates payment request for 100 USDC
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Get cost in IDRX
        IPaymentProcessor.FeeBreakdown memory cost = processor
            .calculatePaymentCost(requestId, address(idrx));

        uint256 merchantUsdcBefore = usdc.balanceOf(merchant);
        uint256 customerIdrxBefore = idrx.balanceOf(customer);

        // Customer pays with IDRX (auto-swap happens)
        vm.startPrank(customer);
        idrx.approve(address(processor), cost.totalRequired);

        processor.executePayment(requestId, cost.totalRequired, address(idrx));
        vm.stopPrank();

        // Merchant should receive USDC (what they requested)
        assertEq(usdc.balanceOf(merchant), merchantUsdcBefore + 100 * 10 ** 6);

        // Customer should have paid IDRX
        assertLt(idrx.balanceOf(customer), customerIdrxBefore);

        // Payment should be completed
        IPaymentProcessor.PaymentRequest memory payment = processor.getPayment(
            requestId
        );
        assertEq(
            uint256(payment.status),
            uint256(IPaymentProcessor.PaymentStatus.Completed)
        );
    }

    function test_ExecutePayment_RevertIfExpired() public {
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Fast forward past expiry (5 minutes + 1 second)
        vm.warp(block.timestamp + 5 minutes + 1);

        vm.startPrank(customer);
        usdc.approve(address(processor), type(uint256).max);

        vm.expectRevert(PaymentProcessor.PaymentExpired.selector);
        processor.executePayment(requestId, 1000 * 10 ** 6, address(usdc));
        vm.stopPrank();
    }

    function test_ExecutePayment_RevertIfSlippageExceeded() public {
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        vm.startPrank(customer);
        usdc.approve(address(processor), type(uint256).max);

        // Set maxAmount too low
        vm.expectRevert(PaymentProcessor.SlippageExceeded.selector);
        processor.executePayment(requestId, 50 * 10 ** 6, address(usdc)); // Only willing to pay 50 USDC
        vm.stopPrank();
    }

    // ============ CANCEL PAYMENT TESTS ============

    function test_CancelPayment() public {
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        vm.prank(merchant);
        processor.cancelPayment(requestId);

        IPaymentProcessor.PaymentRequest memory payment = processor.getPayment(
            requestId
        );
        assertEq(
            uint256(payment.status),
            uint256(IPaymentProcessor.PaymentStatus.Cancelled)
        );
    }

    function test_CancelPayment_RevertIfNotRecipient() public {
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Customer tries to cancel (not allowed)
        vm.prank(customer);
        vm.expectRevert(PaymentProcessor.NotRecipient.selector);
        processor.cancelPayment(requestId);
    }

    function test_CancelPayment_RevertIfAlreadyCompleted() public {
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );

        // Customer pays
        vm.startPrank(customer);
        usdc.approve(address(processor), type(uint256).max);
        processor.executePayment(requestId, 200 * 10 ** 6, address(usdc));
        vm.stopPrank();

        // Merchant tries to cancel (already completed)
        vm.prank(merchant);
        vm.expectRevert(PaymentProcessor.PaymentNotPending.selector);
        processor.cancelPayment(requestId);
    }

    // ============ FULL WORKFLOW TEST ============

    function test_FullWorkflow_QRPayment() public {
        console.log("=== FULL QR PAYMENT WORKFLOW TEST ===");

        // Step 1: Merchant creates payment request (QR Code)
        console.log("Step 1: Merchant creates payment request for 100 USDC");
        vm.prank(merchant);
        bytes32 requestId = processor.createPaymentRequest(
            address(usdc),
            100 * 10 ** 6
        );
        console.log("  Request ID created");

        // Step 2: Customer scans QR and sees payment details
        console.log("Step 2: Customer views payment details");
        IPaymentProcessor.PaymentRequest memory payment = processor.getPayment(
            requestId
        );
        console.log("  Recipient:", payment.recipient);
        console.log("  Requested Amount:", payment.requestedAmount);

        // Step 3: Customer chooses to pay with IDRX
        console.log("Step 3: Customer calculates cost in IDRX");
        IPaymentProcessor.FeeBreakdown memory cost = processor
            .calculatePaymentCost(requestId, address(idrx));
        console.log("  Base Amount (USDC):", cost.baseAmount);
        console.log("  Platform Fee (USDC):", cost.platformFee);
        console.log("  Swap Fee (IDRX):", cost.swapFee);
        console.log("  Total Required (IDRX):", cost.totalRequired);

        // Step 4: Customer approves and pays
        console.log("Step 4: Customer executes payment with IDRX");
        vm.startPrank(customer);
        idrx.approve(address(processor), cost.totalRequired);
        processor.executePayment(requestId, cost.totalRequired, address(idrx));
        vm.stopPrank();

        // Step 5: Verify final state
        console.log("Step 5: Verify final state");
        payment = processor.getPayment(requestId);
        console.log("  Payment Status: Completed");
        console.log("  Payer:", payment.payer);
        console.log("  Merchant USDC Balance:", usdc.balanceOf(merchant));
        console.log(
            "  Fee Recipient USDC Balance:",
            usdc.balanceOf(feeRecipient)
        );

        assertEq(
            uint256(payment.status),
            uint256(IPaymentProcessor.PaymentStatus.Completed)
        );
        assertEq(usdc.balanceOf(merchant), 100 * 10 ** 6);
        assertGt(usdc.balanceOf(feeRecipient), 0);

        console.log("=== WORKFLOW TEST PASSED ===");
    }
}
