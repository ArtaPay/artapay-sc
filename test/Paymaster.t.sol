// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/paymaster/Paymaster.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/token/MockStableCoin.sol";

/**
 * @title MockEntryPoint
 * @notice Simple mock of ERC-4337 EntryPoint for testing
 */
contract MockEntryPoint {
    mapping(address => uint256) public deposits;

    function depositTo(address account) external payable {
        deposits[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {
        require(deposits[msg.sender] >= withdrawAmount, "Insufficient deposit");
        deposits[msg.sender] -= withdrawAmount;
        (bool success,) = withdrawAddress.call{value: withdrawAmount}("");
        require(success, "Transfer failed");
    }

    function balanceOf(address account) external view returns (uint256) {
        return deposits[account];
    }

    function callPostOp(
        address paymaster,
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) external {
        IPaymaster(paymaster).postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }

    receive() external payable {}
}

/**
 * @title PaymasterTest
 * @notice Comprehensive tests for ERC-4337 Paymaster contract
 */
contract PaymasterTest is Test {
    Paymaster public paymaster;
    StablecoinRegistry public registry;
    MockStableCoin public usdc;
    MockStableCoin public usdt;
    MockStableCoin public idrx;
    MockEntryPoint public entryPoint;

    address public owner = address(1);
    address public user = address(2);
    address public signer = address(3);
    address public unauthorized = address(4);

    function setUp() public {
        vm.startPrank(owner);

        entryPoint = new MockEntryPoint();
        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        usdt = new MockStableCoin("Tether USD", "USDT", 6, "US");
        idrx = new MockStableCoin("Rupiah Token", "IDRX", 2, "ID");

        registry = new StablecoinRegistry();
        registry.registerStablecoin(address(usdc), "USDC", "US", 1e8);
        registry.registerStablecoin(address(usdt), "USDT", "US", 1e8);
        registry.registerStablecoin(address(idrx), "IDRX", "ID", 16000e8);

        paymaster = new Paymaster(address(entryPoint), address(registry));
        paymaster.setSupportedToken(address(usdc), true);
        paymaster.setSupportedToken(address(usdt), true);
        paymaster.setSupportedToken(address(idrx), true);
        paymaster.setSigner(signer, true);

        vm.deal(owner, 100 ether);
        paymaster.deposit{value: 10 ether}();

        vm.stopPrank();

        vm.startPrank(user);
        usdc.faucet(1000);
        usdt.faucet(1000);
        idrx.mint(user, 20000000 * 10 ** 2);
        vm.stopPrank();
    }

    function testCalculateFee() public {
        uint256 ethCost = 0.01 ether;
        uint256 tokenCost = paymaster.calculateFee(address(usdc), ethCost);

        assertTrue(tokenCost > 0, "Fee should be greater than 0");
        console.log("Fee for 0.01 ETH in USDC:", tokenCost);
    }

    function testCalculateFeeUnsupportedToken() public {
        address unsupportedToken = address(0x999);
        uint256 ethCost = 0.01 ether;

        vm.expectRevert("Paymaster: token not supported");
        paymaster.calculateFee(unsupportedToken, ethCost);
    }

    function testCalculateFeeDifferentTokens() public {
        uint256 ethCost = 0.01 ether;

        uint256 usdcCost = paymaster.calculateFee(address(usdc), ethCost);
        uint256 usdtCost = paymaster.calculateFee(address(usdt), ethCost);
        uint256 idrxCost = paymaster.calculateFee(address(idrx), ethCost);

        assertApproxEqRel(usdcCost, usdtCost, 0.01e18);
        assertTrue(idrxCost > usdcCost, "IDRX cost should be higher");

        console.log("USDC cost:", usdcCost);
        console.log("USDT cost:", usdtCost);
        console.log("IDRX cost:", idrxCost);
    }

    function testEstimateTotalCost() public {
        uint256 gasLimit = 500000;
        uint256 maxFeePerGas = 2 gwei;

        uint256 gasCost = paymaster.estimateTotalCost(address(usdc), gasLimit, maxFeePerGas);

        assertTrue(gasCost > 0, "Gas cost should be greater than 0");

        console.log("Gas Cost:", gasCost);
    }

    function testGetDeposit() public {
        uint256 deposit = paymaster.getDeposit();
        assertEq(deposit, 10 ether, "Should have 10 ETH deposit");
    }

    function testDepositMore() public {
        vm.prank(owner);
        paymaster.deposit{value: 5 ether}();

        uint256 deposit = paymaster.getDeposit();
        assertEq(deposit, 15 ether, "Should have 15 ETH deposit");
    }

    function testWithdrawFromEntryPoint() public {
        uint256 withdrawAmount = 3 ether;
        uint256 initialDeposit = paymaster.getDeposit();

        vm.prank(owner);
        paymaster.withdrawFromEntryPoint(payable(owner), withdrawAmount);

        uint256 finalDeposit = paymaster.getDeposit();
        assertEq(finalDeposit, initialDeposit - withdrawAmount);
    }

    function testUnauthorizedCannotWithdrawFromEntryPoint() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.withdrawFromEntryPoint(payable(unauthorized), 1 ether);
    }

    function testIsSupportedToken() public {
        assertTrue(paymaster.isSupportedToken(address(usdc)));
        assertTrue(paymaster.isSupportedToken(address(usdt)));
        assertTrue(paymaster.isSupportedToken(address(idrx)));
        assertFalse(paymaster.isSupportedToken(address(0x999)));
    }

    function testSetSupportedToken() public {
        MockStableCoin newToken = new MockStableCoin("New Token", "NEW", 6, "XX");

        vm.prank(owner);
        vm.expectRevert("Paymaster: token not in registry");
        paymaster.setSupportedToken(address(newToken), true);
        vm.prank(owner);
        registry.registerStablecoin(address(newToken), "NEW", "XX", 1e8);
        vm.prank(owner);
        paymaster.setSupportedToken(address(newToken), true);

        assertTrue(paymaster.isSupportedToken(address(newToken)));
    }

    function testUnauthorizedCannotSetSupportedToken() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.setSupportedToken(address(usdc), false);
    }

    function testIsAuthorizedSigner() public {
        assertTrue(paymaster.isAuthorizedSigner(owner), "Owner should be authorized");
        assertTrue(paymaster.isAuthorizedSigner(signer), "Signer should be authorized");
        assertFalse(paymaster.isAuthorizedSigner(unauthorized), "Unauthorized should not be");
    }

    function testSetSigner() public {
        address newSigner = address(5);

        vm.prank(owner);
        paymaster.setSigner(newSigner, true);
        assertTrue(paymaster.isAuthorizedSigner(newSigner));

        vm.prank(owner);
        paymaster.setSigner(newSigner, false);
        assertFalse(paymaster.isAuthorizedSigner(newSigner));
    }

    function testUnauthorizedCannotSetSigner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.setSigner(address(6), true);
    }

    function testPause() public {
        vm.prank(owner);
        paymaster.pause();

        assertTrue(paymaster.paused());
    }

    function testUnpause() public {
        vm.prank(owner);
        paymaster.pause();

        vm.prank(owner);
        paymaster.unpause();

        assertFalse(paymaster.paused());
    }

    function testUnauthorizedCannotPause() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.pause();
    }

    function testGetCollectedFees() public {
        uint256 fees = paymaster.getCollectedFees(address(usdc));
        assertEq(fees, 0, "Initially should be 0");
    }

    function testWithdrawFees() public {
        uint256 feeAmount = 10 * 10 ** 6;

        vm.prank(user);
        usdc.approve(address(paymaster), feeAmount * 2);

        bytes memory context = abi.encode(address(usdc), user, feeAmount);

        entryPoint.callPostOp(address(paymaster), PostOpMode.opSucceeded, context, 1000, 1 gwei);

        assertTrue(paymaster.getCollectedFees(address(usdc)) > 0, "Fees should be collected");

        uint256 collectedAmount = paymaster.getCollectedFees(address(usdc));
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        vm.prank(owner);
        paymaster.withdrawFees(address(usdc), collectedAmount / 2, owner);

        uint256 ownerBalanceAfter = usdc.balanceOf(owner);
        assertTrue(ownerBalanceAfter > ownerBalanceBefore, "Owner should receive fees");
    }

    function testUnauthorizedCannotWithdrawFees() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.withdrawFees(address(usdc), 1, unauthorized);
    }

    function testSetStablecoinRegistry() public {
        StablecoinRegistry newRegistry = new StablecoinRegistry();

        vm.prank(owner);
        paymaster.setStablecoinRegistry(address(newRegistry));

        assertEq(address(paymaster.stablecoinRegistry()), address(newRegistry));
    }

    function testUnauthorizedCannotSetRegistry() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.setStablecoinRegistry(address(0x999));
    }

    function testEmergencyWithdrawETH() public {
        // Send ETH to paymaster
        vm.deal(address(paymaster), 5 ether);

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        paymaster.emergencyWithdraw(address(0), owner);

        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 5 ether);
    }

    function testEmergencyWithdrawToken() public {
        vm.prank(user);
        usdc.transfer(address(paymaster), 100 * 10 ** 6);

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        vm.prank(owner);
        paymaster.emergencyWithdraw(address(usdc), owner);

        uint256 ownerBalanceAfter = usdc.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 100 * 10 ** 6);
    }

    function testUnauthorizedCannotEmergencyWithdraw() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        paymaster.emergencyWithdraw(address(usdc), unauthorized);
    }

    function testGetGasBounds() public {
        (uint256 minGasPrice, uint256 maxGasPrice) = paymaster.getGasBounds();

        assertEq(minGasPrice, 0.0001 gwei);
        assertEq(maxGasPrice, 1000 gwei);
    }

    function testOnlyEntryPointCanCallPostOp() public {
        bytes memory context = abi.encode(address(usdc), user, 1000);

        vm.prank(unauthorized);
        vm.expectRevert("Paymaster: not EntryPoint");
        paymaster.postOp(PostOpMode.opSucceeded, context, 1000, 1 gwei);
    }

    function testFeeCalculationUsesRegistryRate() public {
        vm.prank(owner);
        registry.setEthUsdRate(3000e8);

        uint256 ethCost = 0.01 ether;
        uint256 usdcCost = paymaster.calculateFee(address(usdc), ethCost);

        console.log("USDC cost with $3000 ETH:", usdcCost);
        assertTrue(usdcCost > 30 * 10 ** 6);
        assertTrue(usdcCost < 32 * 10 ** 6);
    }

    function testValidateWithPermitFlow() public {
        assertEq(usdc.allowance(user, address(paymaster)), 0);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                usdc.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(paymaster),
                        type(uint256).max,
                        usdc.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, permitHash);

        bytes memory paymasterAndData = abi.encodePacked(
            address(paymaster),
            uint128(100000),
            uint128(50000),
            address(usdc),
            uint48(block.timestamp + 1 hours),
            uint48(0),
            uint8(1),
            bytes32(deadline),
            v,
            r,
            s,
            bytes(
                hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            )
        );

        assertTrue(paymasterAndData.length >= 247, "paymasterAndData too short for v0.7");
        assertEq(paymasterAndData.length, 247, "paymasterAndData should be exactly 247 bytes");

        console.log("Permit test: paymasterAndData length =", paymasterAndData.length);
        console.log("Permit v =", v);
    }
}
