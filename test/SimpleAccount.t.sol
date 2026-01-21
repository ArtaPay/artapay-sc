// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/account/SimpleAccount.sol";
import "../src/interfaces/IERC4337.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title MockEntryPoint
 * @notice Simple mock of ERC-4337 EntryPoint for testing
 */
contract MockEntryPoint {
    mapping(address => uint256) public deposits;
    mapping(address => mapping(uint192 => uint256)) public nonces;

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

    function getNonce(address sender, uint192 key) external view returns (uint256) {
        return nonces[sender][key];
    }

    function incrementNonce(address sender, uint192 key) external {
        nonces[sender][key]++;
    }

    receive() external payable {}
}

/**
 * @title SimpleAccountTest
 * @notice Comprehensive tests for SimpleAccount contract
 */
contract SimpleAccountTest is Test {
    using MessageHashUtils for bytes32;

    SimpleAccount public account;
    MockEntryPoint public entryPoint;

    address public owner;
    address public unauthorized = address(2);
    address public recipient = address(3);

    uint256 public ownerPrivateKey = 0xa11ce;

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);

        entryPoint = new MockEntryPoint();

        SimpleAccount implementation = new SimpleAccount(IEntryPoint(address(entryPoint)));
        account = SimpleAccount(
            payable(new ERC1967Proxy(address(implementation), abi.encodeCall(SimpleAccount.initialize, (owner))))
        );

        vm.deal(address(account), 10 ether);
    }

    function testDeployment() public {
        assertEq(account.owner(), owner);
        assertEq(address(account.entryPoint()), address(entryPoint));
    }

    function testCannotDeployWithZeroEntryPoint() public {
        vm.expectRevert("SimpleAccount: invalid entrypoint");
        new SimpleAccount(IEntryPoint(address(0)));
    }

    function testCannotDeployWithZeroOwner() public {
        SimpleAccount implementation = new SimpleAccount(IEntryPoint(address(entryPoint)));
        vm.expectRevert("SimpleAccount: invalid owner");
        new ERC1967Proxy(address(implementation), abi.encodeCall(SimpleAccount.initialize, (address(0))));
    }

    function testExecuteAsOwner() public {
        uint256 transferAmount = 1 ether;
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        account.execute(recipient, transferAmount, "");

        assertEq(recipient.balance, recipientBalanceBefore + transferAmount);
    }

    function testUnauthorizedCannotExecute() public {
        vm.prank(unauthorized);
        vm.expectRevert("SimpleAccount: not owner");
        account.execute(recipient, 1 ether, "");
    }

    function testExecuteWithCalldata() public {
        Counter counter = new Counter();

        bytes memory callData = abi.encodeWithSelector(Counter.increment.selector);

        vm.prank(owner);
        account.execute(address(counter), 0, callData);

        assertEq(counter.count(), 1);
    }

    function testExecuteBatch() public {
        address[] memory destinations = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        uint256[] memory values = new uint256[](0);

        destinations[0] = recipient;
        destinations[1] = recipient;
        calldatas[0] = "";
        calldatas[1] = "";

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        account.executeBatch(destinations, values, calldatas);

        assertEq(recipient.balance, recipientBalanceBefore);
    }

    function testExecuteBatchLengthMismatch() public {
        address[] memory destinations = new address[](2);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](2);

        destinations[0] = recipient;
        destinations[1] = recipient;
        calldatas[0] = "";

        vm.prank(owner);
        vm.expectRevert("SimpleAccount: length mismatch");
        account.executeBatch(destinations, values, calldatas);
    }

    function testValidateUserOp() public {
        PackedUserOperation memory userOp;
        userOp.sender = address(account);
        userOp.nonce = 0;

        bytes32 userOpHash = keccak256(abi.encodePacked("test-userop"));

        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0);
    }

    function testValidateUserOpWithDeposit() public {
        PackedUserOperation memory userOp;
        userOp.sender = address(account);

        bytes32 userOpHash = keccak256(abi.encodePacked("test-userop"));

        bytes32 digest = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        uint256 missingFunds = 1 ether;

        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, userOpHash, missingFunds);

        assertEq(entryPoint.balanceOf(address(account)), missingFunds);
    }

    function testOnlyEntryPointCanValidate() public {
        PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256(abi.encodePacked("test"));

        vm.prank(unauthorized);
        vm.expectRevert("SimpleAccount: not EntryPoint");
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function testGetNonce() public {
        uint256 nonce = account.getNonce();
        assertEq(nonce, 0);
    }

    function testAddDeposit() public {
        uint256 depositAmount = 5 ether;

        vm.deal(address(this), depositAmount);
        account.addDeposit{value: depositAmount}();

        assertEq(entryPoint.balanceOf(address(account)), depositAmount);
    }

    function testWithdrawDeposit() public {
        uint256 depositAmount = 3 ether;
        vm.deal(address(this), depositAmount);
        account.addDeposit{value: depositAmount}();

        uint256 withdrawAmount = 1 ether;
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        account.withdrawDepositTo(payable(owner), withdrawAmount);

        assertEq(owner.balance, ownerBalanceBefore + withdrawAmount);
        assertEq(entryPoint.balanceOf(address(account)), depositAmount - withdrawAmount);
    }

    function testUnauthorizedCannotWithdraw() public {
        vm.prank(unauthorized);
        vm.expectRevert("SimpleAccount: not owner");
        account.withdrawDepositTo(payable(unauthorized), 1 ether);
    }

    function testReceiveEth() public {
        uint256 sendAmount = 2 ether;
        uint256 balanceBefore = address(account).balance;

        (bool success,) = address(account).call{value: sendAmount}("");

        assertTrue(success);
        assertEq(address(account).balance, balanceBefore + sendAmount);
    }
}

/**
 * @notice Simple counter contract for testing execute with calldata
 */
contract Counter {
    uint256 public count;

    function increment() external {
        count++;
    }
}
