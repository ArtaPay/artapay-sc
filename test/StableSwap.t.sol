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

    uint256 constant USDC_RATE = 1e8;
    uint256 constant IDRX_RATE = 16000e8;
    uint256 constant JPYC_RATE = 150e8;

    function setUp() public {
        registry = new StablecoinRegistry();
        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        idrx = new MockStableCoin("Indonesian Rupiah Token", "IDRX", 2, "ID");
        jpyc = new MockStableCoin("JPY Coin", "JPYC", 18, "JP");
        registry.registerStablecoin(address(usdc), "USDC", "US", USDC_RATE);
        registry.registerStablecoin(address(idrx), "IDRX", "ID", IDRX_RATE);
        registry.registerStablecoin(address(jpyc), "JPYC", "JP", JPYC_RATE);
        stableSwap = new StableSwap(address(registry));

        usdc.mint(owner, 1000000 * 10 ** 6);
        idrx.mint(owner, 16000000000 * 10 ** 2);
        jpyc.mint(owner, 150000000 * 10 ** 18);

        usdc.mint(user1, 10000 * 10 ** 6);
        idrx.mint(user1, 160000000 * 10 ** 2);

        usdc.approve(address(stableSwap), type(uint256).max);
        idrx.approve(address(stableSwap), type(uint256).max);
        jpyc.approve(address(stableSwap), type(uint256).max);

        stableSwap.deposit(address(usdc), 100000 * 10 ** 6);
        stableSwap.deposit(address(idrx), 1600000000 * 10 ** 2);
        stableSwap.deposit(address(jpyc), 15000000 * 10 ** 18);
    }

    function test_Deposit() public {
        uint256 initialReserve = stableSwap.reserves(address(usdc));
        uint256 depositAmount = 1000 * 10 ** 6;

        stableSwap.deposit(address(usdc), depositAmount);

        assertEq(stableSwap.reserves(address(usdc)), initialReserve + depositAmount);
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

    function test_Withdraw() public {
        uint256 initialReserve = stableSwap.reserves(address(usdc));
        uint256 withdrawAmount = 1000 * 10 ** 6;

        stableSwap.withdraw(address(usdc), withdrawAmount);

        assertEq(stableSwap.reserves(address(usdc)), initialReserve - withdrawAmount);
    }

    function test_Withdraw_RevertIfInsufficientBalance() public {
        uint256 reserve = stableSwap.reserves(address(usdc));

        vm.expectRevert(StableSwap.InsufficientBalance.selector);
        stableSwap.withdraw(address(usdc), reserve + 1);
    }

    function test_GetSwapQuote_SameValue() public view {
        uint256 amountIn = 1600000 * 10 ** 2;

        (uint256 amountOut, uint256 fee, uint256 totalUserPays) =
            stableSwap.getSwapQuote(address(idrx), address(usdc), amountIn);

        assertEq(fee, (amountIn * 10) / 10000);

        assertEq(totalUserPays, amountIn + fee);

        assertGt(amountOut, 99 * 10 ** 6);
        assertLt(amountOut, 101 * 10 ** 6);
    }

    function test_Swap_IDRX_to_USDC() public {
        uint256 amountIn = 1600000 * 10 ** 2;

        (uint256 expectedOut, uint256 fee, uint256 totalPay) =
            stableSwap.getSwapQuote(address(idrx), address(usdc), amountIn);

        vm.startPrank(user1);
        idrx.approve(address(stableSwap), totalPay);

        uint256 userUsdcBefore = usdc.balanceOf(user1);
        uint256 userIdrxBefore = idrx.balanceOf(user1);

        uint256 amountOut = stableSwap.swap(amountIn, address(idrx), address(usdc), expectedOut);

        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), userUsdcBefore + amountOut);
        assertEq(idrx.balanceOf(user1), userIdrxBefore - totalPay);

        assertGt(stableSwap.collectedFees(address(idrx)), 0);
    }

    function test_Swap_RevertIfSlippageExceeded() public {
        uint256 amountIn = 1600000 * 10 ** 2;

        vm.startPrank(user1);
        idrx.approve(address(stableSwap), type(uint256).max);

        vm.expectRevert(StableSwap.SlippageExceeded.selector);
        stableSwap.swap(amountIn, address(idrx), address(usdc), 1000 * 10 ** 6);

        vm.stopPrank();
    }

    function test_Swap_RevertIfInsufficientReserve() public {
        uint256 hugeAmount = 100000000000 * 10 ** 2;

        vm.startPrank(user1);
        idrx.mint(user1, hugeAmount);
        idrx.approve(address(stableSwap), type(uint256).max);

        vm.expectRevert(StableSwap.InsufficientBalance.selector);
        stableSwap.swap(hugeAmount, address(idrx), address(usdc), 0);

        vm.stopPrank();
    }

    function test_WithdrawFees() public {
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
