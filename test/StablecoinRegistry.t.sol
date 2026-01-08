// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/token/MockStableCoin.sol";

/**
 * @title StablecoinRegistryTest
 * @notice Comprehensive tests for StablecoinRegistry contract
 */
contract StablecoinRegistryTest is Test {
    StablecoinRegistry public registry;
    MockStableCoin public usdc;
    MockStableCoin public usdt;
    MockStableCoin public idrx;
    MockStableCoin public jpyc;
    MockStableCoin public euroc;

    address public owner = address(1);
    address public unauthorized = address(2);

    function setUp() public {
        vm.startPrank(owner);
        registry = new StablecoinRegistry();
        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        usdt = new MockStableCoin("Tether USD", "USDT", 6, "US");
        idrx = new MockStableCoin("Rupiah Token", "IDRX", 2, "ID");
        jpyc = new MockStableCoin("JPY Coin", "JPYC", 18, "JP");
        euroc = new MockStableCoin("EURO Coin", "EUROC", 6, "EU");

        registry.registerStablecoin(address(usdc), "USDC", "US", 1e8);
        registry.registerStablecoin(address(usdt), "USDT", "US", 1e8);
        registry.registerStablecoin(address(idrx), "IDRX", "ID", 16000e8);
        registry.registerStablecoin(address(jpyc), "JPYC", "JP", 150e8);
        registry.registerStablecoin(address(euroc), "EUROC", "EU", 0.92e8);

        vm.stopPrank();
    }

    function testRegisterStablecoin() public {
        MockStableCoin newToken = new MockStableCoin("New Token", "NEW", 8, "XX");

        vm.prank(owner);
        registry.registerStablecoin(address(newToken), "NEW", "XX", 1e8);

        assertTrue(registry.isStablecoinActive(address(newToken)));

        IStablecoinRegistry.StablecoinInfo memory info = registry.getStablecoin(address(newToken));
        assertEq(info.symbol, "NEW");
        assertEq(info.decimals, 8);
        assertEq(info.region, "XX");
        assertEq(info.rateToUSD, 1e8);
        assertTrue(info.isActive);
    }

    function testAutoDetectDecimals() public {
        MockStableCoin token6 = new MockStableCoin("Six Decimals", "SIX", 6, "XX");
        MockStableCoin token18 = new MockStableCoin("Eighteen Decimals", "EIGH", 18, "XX");

        vm.startPrank(owner);
        registry.registerStablecoin(address(token6), "SIX", "XX", 1e8);
        registry.registerStablecoin(address(token18), "EIGH", "XX", 1e8);
        vm.stopPrank();

        IStablecoinRegistry.StablecoinInfo memory info6 = registry.getStablecoin(address(token6));
        IStablecoinRegistry.StablecoinInfo memory info18 = registry.getStablecoin(address(token18));

        assertEq(info6.decimals, 6, "Should auto-detect 6 decimals");
        assertEq(info18.decimals, 18, "Should auto-detect 18 decimals");
    }

    function testCannotRegisterSameTokenTwice() public {
        vm.prank(owner);
        vm.expectRevert("Registry: token already registered");
        registry.registerStablecoin(address(usdc), "USDC", "US", 1e8);
    }

    function testUnauthorizedCannotRegister() public {
        MockStableCoin newToken = new MockStableCoin("New", "NEW", 6, "XX");

        vm.prank(unauthorized);
        vm.expectRevert();
        registry.registerStablecoin(address(newToken), "NEW", "XX", 1e8);
    }

    function testBatchRegisterStablecoins() public {
        MockStableCoin token1 = new MockStableCoin("Token 1", "TK1", 6, "XX");
        MockStableCoin token2 = new MockStableCoin("Token 2", "TK2", 8, "YY");

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        string[] memory symbols = new string[](2);
        symbols[0] = "TK1";
        symbols[1] = "TK2";

        string[] memory regions = new string[](2);
        regions[0] = "XX";
        regions[1] = "YY";

        uint256[] memory rates = new uint256[](2);
        rates[0] = 1e8;
        rates[1] = 2e8;

        vm.prank(owner);
        registry.batchRegisterStablecoins(tokens, symbols, regions, rates);

        assertTrue(registry.isStablecoinActive(address(token1)));
        assertTrue(registry.isStablecoinActive(address(token2)));
    }

    function testUpdateRate() public {
        uint256 oldRate = 1e8;
        uint256 newRate = 1.1e8;

        vm.prank(owner);
        registry.updateRate(address(usdc), newRate);

        IStablecoinRegistry.StablecoinInfo memory info = registry.getStablecoin(address(usdc));
        assertEq(info.rateToUSD, newRate);
    }

    function testUpdateRateEnforcesChangeLimit() public {
        uint256 currentRate = 1e8;
        uint256 tooHighRate = 2e8;

        vm.prank(owner);
        vm.expectRevert("Registry: rate change too large");
        registry.updateRate(address(usdc), tooHighRate);
    }

    function testBatchUpdateRates() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);

        uint256[] memory rates = new uint256[](2);
        rates[0] = 1.1e8;
        rates[1] = 1.1e8;

        vm.prank(owner);
        registry.batchUpdateRates(tokens, rates);

        IStablecoinRegistry.StablecoinInfo memory usdcInfo = registry.getStablecoin(address(usdc));
        IStablecoinRegistry.StablecoinInfo memory usdtInfo = registry.getStablecoin(address(usdt));

        assertEq(usdcInfo.rateToUSD, 1.1e8);
        assertEq(usdtInfo.rateToUSD, 1.1e8);
    }

    function testUnauthorizedCannotUpdateRate() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.updateRate(address(usdc), 1.1e8);
    }

    function testSetStablecoinStatus() public {
        vm.prank(owner);
        registry.setStablecoinStatus(address(usdc), false);

        assertFalse(registry.isStablecoinActive(address(usdc)));

        vm.prank(owner);
        registry.setStablecoinStatus(address(usdc), true);

        assertTrue(registry.isStablecoinActive(address(usdc)));
    }

    function testSetEthUsdRate() public {
        uint256 newRate = 3000e8;

        vm.prank(owner);
        registry.setEthUsdRate(newRate);

        assertEq(registry.ethUsdRate(), newRate);
    }

    function testSetEthUsdRateEnforcesBounds() public {
        vm.prank(owner);
        vm.expectRevert("Registry: rate too low");
        registry.setEthUsdRate(500e8);

        vm.prank(owner);
        vm.expectRevert("Registry: rate too high");
        registry.setEthUsdRate(200000e8);
    }

    function testConvertSameToken() public {
        uint256 amount = 100 * 10 ** 6;
        uint256 result = registry.convert(address(usdc), address(usdc), amount);

        assertEq(result, amount, "Same token conversion should return same amount");
    }

    function testConvertUSDCToUSDT() public {
        uint256 usdcAmount = 100 * 10 ** 6;
        uint256 usdtResult = registry.convert(address(usdc), address(usdt), usdcAmount);

        assertApproxEqRel(usdtResult, 100 * 10 ** 6, 0.01e18);
    }

    function testConvertUSDCToIDRX() public {
        uint256 usdcAmount = 1 * 10 ** 6;
        uint256 idrxResult = registry.convert(address(usdc), address(idrx), usdcAmount);

        assertEq(idrxResult, 16000 * 10 ** 2, "1 USDC should equal 16000 IDRX");
    }

    function testConvertIDRXToUSDC() public {
        uint256 idrxAmount = 16000 * 10 ** 2;
        uint256 usdcResult = registry.convert(address(idrx), address(usdc), idrxAmount);

        assertApproxEqRel(usdcResult, 1 * 10 ** 6, 0.01e18);
    }

    function testConvertWithDifferentDecimals() public {
        uint256 jpycAmount = 150 * 10 ** 18;
        uint256 usdcResult = registry.convert(address(jpyc), address(usdc), jpycAmount);

        assertApproxEqRel(usdcResult, 1 * 10 ** 6, 0.01e18);
    }

    function testEthToToken() public {
        uint256 ethAmount = 1 ether;
        uint256 usdcResult = registry.ethToToken(address(usdc), ethAmount);

        assertApproxEqRel(usdcResult, 3000 * 10 ** 6, 0.01e18);

        console.log("1 ETH =", usdcResult, "USDC");
    }

    function testEthToTokenDifferentRates() public {
        uint256 ethAmount = 0.1 ether;

        uint256 usdcResult = registry.ethToToken(address(usdc), ethAmount);
        assertApproxEqRel(usdcResult, 300 * 10 ** 6, 0.01e18);

        uint256 idrxResult = registry.ethToToken(address(idrx), ethAmount);
        assertApproxEqRel(idrxResult, 4800000 * 10 ** 2, 0.01e18);

        console.log("0.1 ETH =", usdcResult, "USDC");
        console.log("0.1 ETH =", idrxResult, "IDRX");
    }

    function testTokenToEth() public {
        uint256 usdcAmount = 3000 * 10 ** 6;
        uint256 ethResult = registry.tokenToEth(address(usdc), usdcAmount);

        assertApproxEqRel(ethResult, 1 ether, 0.01e18);

        console.log(usdcAmount, "USDC =", ethResult, "wei");
    }

    function testGetAllStablecoins() public {
        address[] memory tokens = registry.getAllStablecoins();

        assertEq(tokens.length, 5);
        assertEq(tokens[0], address(usdc));
    }

    function testGetActiveStablecoins() public {
        vm.prank(owner);
        registry.setStablecoinStatus(address(usdc), false);

        address[] memory active = registry.getActiveStablecoins();

        assertEq(active.length, 4);
    }

    function testGetStablecoinCount() public {
        uint256 count = registry.getStablecoinCount();
        assertEq(count, 5);
    }

    function testGetStablecoinByIndex() public {
        IStablecoinRegistry.StablecoinInfo memory info = registry.getStablecoinByIndex(0);
        assertEq(info.tokenAddress, address(usdc));
    }

    function testGetConversionQuote() public {
        uint256 amount = 100 * 10 ** 6;

        (uint256 toAmount, uint256 fromRate, uint256 toRate) =
            registry.getConversionQuote(address(usdc), address(idrx), amount);

        assertEq(fromRate, 1e8);
        assertEq(toRate, 16000e8);
        assertGt(toAmount, 0);

        console.log("Quote: 100 USDC =", toAmount, "IDRX");
    }

    function testGetStablecoinsByRegion() public {
        address[] memory usTokens = registry.getStablecoinsByRegion("US");
        assertEq(usTokens.length, 2);

        address[] memory idTokens = registry.getStablecoinsByRegion("ID");
        assertEq(idTokens.length, 1);

        address[] memory jpTokens = registry.getStablecoinsByRegion("JP");
        assertEq(jpTokens.length, 1);
    }

    function testGetRateBounds() public {
        (uint256 minRate, uint256 maxRate, uint256 maxChange, uint256 minEth, uint256 maxEth) = registry.getRateBounds();

        assertEq(minRate, 1e4);
        assertEq(maxRate, 1e16);
        assertEq(maxChange, 5000);
        assertEq(minEth, 1000e8);
        assertEq(maxEth, 100000e8);
    }

    function testPauseBlocksConversion() public {
        vm.prank(owner);
        registry.pause();

        vm.expectRevert();
        registry.convert(address(usdc), address(usdt), 100 * 10 ** 6);
    }

    function testPauseBlocksEthConversion() public {
        vm.prank(owner);
        registry.pause();

        vm.expectRevert();
        registry.ethToToken(address(usdc), 1 ether);
    }

    function testUnpauseRestoresFunctionality() public {
        vm.prank(owner);
        registry.pause();

        vm.prank(owner);
        registry.unpause();

        uint256 result = registry.convert(address(usdc), address(usdt), 100 * 10 ** 6);
        assertGt(result, 0);
    }

    function testUnauthorizedCannotPause() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.pause();
    }

    function testConvertZeroAmount() public {
        uint256 result = registry.convert(address(usdc), address(usdt), 0);
        assertEq(result, 0);
    }

    function testConvertVerySmallAmount() public {
        uint256 result = registry.convert(address(usdc), address(usdt), 1);
        assertTrue(result >= 0);
    }

    function testConvertVeryLargeAmount() public {
        uint256 largeAmount = 1000000 * 10 ** 6;
        uint256 result = registry.convert(address(usdc), address(idrx), largeAmount);

        assertTrue(result > 0);
        console.log("1M USDC =", result, "IDRX");
    }
}
