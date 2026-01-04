// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/swap/StableSwap.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/token/MockStableCoin.sol";

contract StableSwapTest is Test {
    StableSwap public stableSwap;
    StablecoinRegistry public registry;

    MockStableCoin public usdc;
    MockStableCoin public idrx;
    MockStableCoin public jpyc;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 constant USDC_RATE = 1e8; // 1 USDC = 1 USD
    uint256 constant IDRX_RATE = 16000e8; // 16000 IDRX = 1 USD
    uint256 constant JPYC_RATE = 150e8; // 150 JPYC = 1 USD

    function setUp() public {
        // Deploy Registry
        registry = new StablecoinRegistry();

        // Deploy Mock Stablecoins
        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        idrx = new MockStableCoin("Indonesian Rupiah Token", "IDRX", 2, "ID");
        jpyc = new MockStableCoin("JPY Coin", "JPYC", 18, "JP");

        // Register stablecoins
        registry.registerStablecoin(address(usdc), "USDC", "US", USDC_RATE);
        registry.registerStablecoin(address(idrx), "IDRX", "ID", IDRX_RATE);
        registry.registerStablecoin(address(jpyc), "JPYC", "JP", JPYC_RATE);

        // Deploy StableSwap
        stableSwap = new StableSwap(address(registry));

        // Mint tokens for testing
        usdc.mint(owner, 1000000 * 10 ** 6); // 1M USDC
        idrx.mint(owner, 16000000000 * 10 ** 2); // 16B IDRX
        jpyc.mint(owner, 150000000 * 10 ** 18); // 150M JPYC

        usdc.mint(user1, 10000 * 10 ** 6); // 10K USDC
        idrx.mint(user1, 160000000 * 10 ** 2); // 160M IDRX (10K USD worth)

        // Owner deposits liquidity to vault
        usdc.approve(address(stableSwap), type(uint256).max);
        idrx.approve(address(stableSwap), type(uint256).max);
        jpyc.approve(address(stableSwap), type(uint256).max);

        stableSwap.deposit(address(usdc), 100000 * 10 ** 6); // 100K USDC
        stableSwap.deposit(address(idrx), 1600000000 * 10 ** 2); // 1.6B IDRX
        stableSwap.deposit(address(jpyc), 15000000 * 10 ** 18); // 15M JPYC
    }

    // ============ DEPOSIT TESTS ============

    function test_Deposit() public {
        uint256 initialReserve = stableSwap.reserves(address(usdc));
        uint256 depositAmount = 1000 * 10 ** 6;

        stableSwap.deposit(address(usdc), depositAmount);

        assertEq(
            stableSwap.reserves(address(usdc)),
            initialReserve + depositAmount
        );
    }

    function test_Deposit_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        stableSwap.deposit(address(usdc), 1000 * 10 ** 6);
    }

    function test_Deposit_RevertIfZeroAmount() public {
        vm.expectRevert(StableSwap.InvalidAmount.selector);
        stableSwap.deposit(address(usdc), 0);
    }

    // ============ WITHDRAW TESTS ============

    function test_Withdraw() public {
        uint256 initialReserve = stableSwap.reserves(address(usdc));
        uint256 withdrawAmount = 1000 * 10 ** 6;

        stableSwap.withdraw(address(usdc), withdrawAmount);

        assertEq(
            stableSwap.reserves(address(usdc)),
            initialReserve - withdrawAmount
        );
    }

    function test_Withdraw_RevertIfInsufficientBalance() public {
        uint256 reserve = stableSwap.reserves(address(usdc));

        vm.expectRevert(StableSwap.InsufficientBalance.selector);
        stableSwap.withdraw(address(usdc), reserve + 1);
    }

    // ============ GET SWAP QUOTE TESTS ============

    function test_GetSwapQuote_SameValue() public view {
        // Swap 100 USDC worth of IDRX
        uint256 amountIn = 1600000 * 10 ** 2; // 1,600,000 IDRX = 100 USD

        (uint256 amountOut, uint256 fee, uint256 totalUserPays) = stableSwap
            .getSwapQuote(address(idrx), address(usdc), amountIn);

        // Fee should be 0.1% of amountIn
        assertEq(fee, (amountIn * 10) / 10000);

        // Total user pays = amountIn + fee
        assertEq(totalUserPays, amountIn + fee);

        // amountOut should be ~100 USDC (minus precision differences)
        assertGt(amountOut, 99 * 10 ** 6);
        assertLt(amountOut, 101 * 10 ** 6);
    }

    // ============ SWAP TESTS ============

    function test_Swap_IDRX_to_USDC() public {
        uint256 amountIn = 1600000 * 10 ** 2; // 1,600,000 IDRX

        // Get quote first
        (uint256 expectedOut, uint256 fee, uint256 totalPay) = stableSwap
            .getSwapQuote(address(idrx), address(usdc), amountIn);

        // User1 approves and swaps
        vm.startPrank(user1);
        idrx.approve(address(stableSwap), totalPay);

        uint256 userUsdcBefore = usdc.balanceOf(user1);
        uint256 userIdrxBefore = idrx.balanceOf(user1);

        uint256 amountOut = stableSwap.swap(
            amountIn,
            address(idrx),
            address(usdc),
            expectedOut
        );

        vm.stopPrank();

        // Check balances
        assertEq(usdc.balanceOf(user1), userUsdcBefore + amountOut);
        assertEq(idrx.balanceOf(user1), userIdrxBefore - totalPay);

        // Check fees collected
        assertGt(stableSwap.collectedFees(address(idrx)), 0);
    }

    function test_Swap_RevertIfSlippageExceeded() public {
        uint256 amountIn = 1600000 * 10 ** 2;

        vm.startPrank(user1);
        idrx.approve(address(stableSwap), type(uint256).max);

        // Set minAmountOut higher than possible
        vm.expectRevert(StableSwap.SlippageExceeded.selector);
        stableSwap.swap(amountIn, address(idrx), address(usdc), 1000 * 10 ** 6); // Expect 1000 USDC (impossible)

        vm.stopPrank();
    }

    function test_Swap_RevertIfInsufficientReserve() public {
        // Try to swap more than vault has
        uint256 hugeAmount = 100000000000 * 10 ** 2; // Way more IDRX than vault has USDC

        vm.startPrank(user1);
        idrx.mint(user1, hugeAmount);
        idrx.approve(address(stableSwap), type(uint256).max);

        vm.expectRevert(StableSwap.InsufficientBalance.selector);
        stableSwap.swap(hugeAmount, address(idrx), address(usdc), 0);

        vm.stopPrank();
    }

    // ============ WITHDRAW FEES TESTS ============

    function test_WithdrawFees() public {
        // First do a swap to generate fees
        vm.startPrank(user1);
        idrx.approve(address(stableSwap), type(uint256).max);
        stableSwap.swap(1600000 * 10 ** 2, address(idrx), address(usdc), 0);
        vm.stopPrank();

        uint256 collectedFees = stableSwap.collectedFees(address(idrx));
        assertGt(collectedFees, 0);

        uint256 ownerBalanceBefore = idrx.balanceOf(owner);
        stableSwap.withdrawFees(address(idrx));

        assertEq(idrx.balanceOf(owner), ownerBalanceBefore + collectedFees);
        assertEq(stableSwap.collectedFees(address(idrx)), 0);
    }
}
