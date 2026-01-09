// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/payment/PaymentProcessor.sol";
import "../src/swap/StableSwap.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/token/MockStableCoin.sol";

/**
 * @title PaymentProcessorTest
 * @notice Comprehensive tests for PaymentProcessor contract
 */
contract PaymentProcessorTest is Test {
    PaymentProcessor public processor;
    StableSwap public swap;
    StablecoinRegistry public registry;
    MockStableCoin public usdc;
    MockStableCoin public usdt;
    MockStableCoin public idrx;

    address public owner = address(1);
    address public merchant;
    address public payer;
    address public feeRecipient = address(4);

    uint256 public merchantPrivateKey = 0xa11ce;
    uint256 public payerPrivateKey = 0xb0b;

    function setUp() public {
        merchant = vm.addr(merchantPrivateKey);
        payer = vm.addr(payerPrivateKey);

        vm.startPrank(owner);

        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        usdt = new MockStableCoin("Tether USD", "USDT", 6, "US");
        idrx = new MockStableCoin("Rupiah Token", "IDRX", 6, "ID");

        registry = new StablecoinRegistry();
        registry.setEthUsdRate(3000e8); // $3000
        registry.registerStablecoin(address(usdc), "USDC", "US", 1e8);
        registry.registerStablecoin(address(usdt), "USDT", "US", 1e8);
        registry.registerStablecoin(address(idrx), "IDRX", "ID", 16000e8);

        swap = new StableSwap(address(registry));

        processor = new PaymentProcessor(address(swap), address(registry), feeRecipient);

        usdc.mint(owner, 1000000 * 10 ** 6);
        usdt.mint(owner, 1000000 * 10 ** 6);
        idrx.mint(owner, 16000000000 * 10 ** 6);

        usdc.approve(address(swap), type(uint256).max);
        usdt.approve(address(swap), type(uint256).max);
        idrx.approve(address(swap), type(uint256).max);

        swap.deposit(address(usdc), 100000 * 10 ** 6);
        swap.deposit(address(usdt), 100000 * 10 ** 6);
        swap.deposit(address(idrx), 1600000000 * 10 ** 6);

        vm.stopPrank();

        vm.startPrank(payer);
        usdc.faucet(10000);
        usdt.faucet(10000);
        idrx.mint(payer, 200000000 * 10 ** 6);
        vm.stopPrank();
    }

    function _makeNonce(string memory seed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(seed));
    }

    function _buildRequest(address requestedToken, uint256 requestedAmount, bytes32 nonce, uint256 deadline)
        internal
        view
        returns (IPaymentProcessor.PaymentRequest memory)
    {
        return IPaymentProcessor.PaymentRequest({
            recipient: merchant,
            requestedToken: requestedToken,
            requestedAmount: requestedAmount,
            deadline: deadline,
            nonce: nonce,
            merchantSigner: merchant
        });
    }

    function _hashRequest(IPaymentProcessor.PaymentRequest memory request) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                address(processor),
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

    function _signRequest(IPaymentProcessor.PaymentRequest memory request, uint256 signerKey)
        internal
        returns (bytes memory)
    {
        bytes32 requestHash = _hashRequest(request);
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", requestHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function testDeployment() public {
        assertEq(address(processor.swap()), address(swap));
        assertEq(address(processor.registry()), address(registry));
        assertEq(processor.feeRecipient(), feeRecipient);
        assertEq(processor.PLATFORM_FEE(), 30); // 0.3%
        assertEq(processor.BPS_DENOMINATOR(), 10000);
    }

    function testCalculatePaymentCostSameToken() public {
        uint256 requestedAmount = 100 * 10 ** 6;

        IPaymentProcessor.FeeBreakdown memory cost =
            processor.calculatePaymentCost(address(usdc), requestedAmount, address(usdc));

        uint256 expectedPlatformFee = (requestedAmount * 30) / 10000;

        assertEq(cost.baseAmount, requestedAmount);
        assertEq(cost.platformFee, expectedPlatformFee);
        assertEq(cost.swapFee, 0);
        assertEq(cost.totalRequired, requestedAmount + expectedPlatformFee);
    }

    function testCalculatePaymentCostCrossToken() public {
        uint256 requestedAmount = 100 * 10 ** 6;

        IPaymentProcessor.FeeBreakdown memory cost =
            processor.calculatePaymentCost(address(usdc), requestedAmount, address(usdt));

        assertTrue(cost.swapFee > 0);
        assertTrue(cost.totalRequired > requestedAmount);
    }

    function testExecutePaymentSameToken() public {
        uint256 requestedAmount = 100 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;
        IPaymentProcessor.PaymentRequest memory request =
            _buildRequest(address(usdc), requestedAmount, _makeNonce("unique-nonce-1"), deadline);
        bytes memory merchantSignature = _signRequest(request, merchantPrivateKey);

        IPaymentProcessor.FeeBreakdown memory cost =
            processor.calculatePaymentCost(address(usdc), requestedAmount, address(usdc));

        vm.startPrank(payer);
        usdc.approve(address(processor), cost.totalRequired);

        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);
        uint256 feeRecipientBalanceBefore = usdc.balanceOf(feeRecipient);

        processor.executePayment(request, merchantSignature, address(usdc), cost.totalRequired);

        assertEq(usdc.balanceOf(merchant) - merchantBalanceBefore, requestedAmount);
        assertEq(usdc.balanceOf(feeRecipient) - feeRecipientBalanceBefore, cost.platformFee);
        assertTrue(processor.usedNonces(request.nonce));

        vm.stopPrank();
    }

    function testExecutePaymentCrossToken() public {
        uint256 requestedAmount = 100 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;
        IPaymentProcessor.PaymentRequest memory request =
            _buildRequest(address(usdc), requestedAmount, _makeNonce("cross-token-nonce"), deadline);
        bytes memory merchantSignature = _signRequest(request, merchantPrivateKey);

        IPaymentProcessor.FeeBreakdown memory cost =
            processor.calculatePaymentCost(address(usdc), requestedAmount, address(usdt));

        vm.startPrank(payer);
        usdt.approve(address(processor), cost.totalRequired);

        uint256 merchantBalanceBefore = usdc.balanceOf(merchant);

        processor.executePayment(request, merchantSignature, address(usdt), cost.totalRequired);

        assertEq(usdc.balanceOf(merchant) - merchantBalanceBefore, requestedAmount);

        vm.stopPrank();
    }

    function testReplayProtection() public {
        uint256 requestedAmount = 50 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;
        IPaymentProcessor.PaymentRequest memory request =
            _buildRequest(address(usdc), requestedAmount, _makeNonce("replay-test"), deadline);
        bytes memory merchantSignature = _signRequest(request, merchantPrivateKey);

        IPaymentProcessor.FeeBreakdown memory cost =
            processor.calculatePaymentCost(address(usdc), requestedAmount, address(usdc));

        vm.startPrank(payer);
        usdc.approve(address(processor), cost.totalRequired * 2);
        processor.executePayment(request, merchantSignature, address(usdc), cost.totalRequired);

        vm.expectRevert(PaymentProcessor.NonceAlreadyUsed.selector);
        processor.executePayment(request, merchantSignature, address(usdc), cost.totalRequired);

        vm.stopPrank();
    }

    function testExpiredDeadline() public {
        uint256 requestedAmount = 50 * 10 ** 6;
        uint256 deadline = block.timestamp - 1; // Already expired
        IPaymentProcessor.PaymentRequest memory request =
            _buildRequest(address(usdc), requestedAmount, _makeNonce("expired-test"), deadline);
        bytes memory merchantSignature = _signRequest(request, merchantPrivateKey);

        vm.startPrank(payer);
        vm.expectRevert(PaymentProcessor.DeadlineExpired.selector);
        processor.executePayment(request, merchantSignature, address(usdc), 1000);
        vm.stopPrank();
    }

    function testInvalidSignature() public {
        uint256 requestedAmount = 50 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;
        IPaymentProcessor.PaymentRequest memory request =
            _buildRequest(address(usdc), requestedAmount, _makeNonce("invalid-sig"), deadline);
        bytes memory invalidSignature = _signRequest(request, payerPrivateKey); // Wrong signer

        vm.startPrank(payer);
        vm.expectRevert(PaymentProcessor.InvalidSignature.selector);
        processor.executePayment(request, invalidSignature, address(usdc), 1000);
        vm.stopPrank();
    }

    function testSlippageProtection() public {
        uint256 requestedAmount = 100 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;
        IPaymentProcessor.PaymentRequest memory request =
            _buildRequest(address(usdc), requestedAmount, _makeNonce("slippage-test"), deadline);
        bytes memory merchantSignature = _signRequest(request, merchantPrivateKey);

        IPaymentProcessor.FeeBreakdown memory cost =
            processor.calculatePaymentCost(address(usdc), requestedAmount, address(usdc));

        vm.startPrank(payer);
        usdc.approve(address(processor), cost.totalRequired);

        uint256 maxAmountToPay = cost.totalRequired - 1;

        vm.expectRevert(PaymentProcessor.SlippageExceeded.selector);
        processor.executePayment(request, merchantSignature, address(usdc), maxAmountToPay);

        vm.stopPrank();
    }

    function testSetFeeRecipient() public {
        address newFeeRecipient = address(5);

        vm.prank(owner);
        processor.setFeeRecipient(newFeeRecipient);

        assertEq(processor.feeRecipient(), newFeeRecipient);
    }

    function testUnauthorizedCannotSetFeeRecipient() public {
        vm.prank(address(999));
        vm.expectRevert();
        processor.setFeeRecipient(address(5));
    }
}
