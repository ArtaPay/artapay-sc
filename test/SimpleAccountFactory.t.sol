// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/account/SimpleAccountFactory.sol";
import "../src/account/SimpleAccount.sol";

/**
 * @title MockEntryPointForFactory
 * @notice Simple mock EntryPoint for factory testing
 */
contract MockEntryPointForFactory {
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

    receive() external payable {}
}

/**
 * @title SimpleAccountFactoryTest
 * @notice Comprehensive tests for SimpleAccountFactory contract
 */
contract SimpleAccountFactoryTest is Test {
    SimpleAccountFactory public factory;
    MockEntryPointForFactory public entryPoint;

    address public owner1 = address(1);
    address public owner2 = address(2);

    function setUp() public {
        entryPoint = new MockEntryPointForFactory();
        factory = new SimpleAccountFactory(IEntryPoint(address(entryPoint)));
    }

    function testDeployment() public {
        assertEq(address(factory.entryPoint()), address(entryPoint));
    }

    function testCannotDeployWithZeroEntryPoint() public {
        vm.expectRevert("Factory: invalid entrypoint");
        new SimpleAccountFactory(IEntryPoint(address(0)));
    }

    function testCreateAccount() public {
        uint256 salt = 0;

        SimpleAccount account = factory.createAccount(owner1, salt);
        assertTrue(address(account) != address(0));
        assertEq(account.owner(), owner1);
        assertEq(address(account.entryPoint()), address(entryPoint));
    }

    function testCreateAccountEmitsEvent() public {
        uint256 salt = 1;
        address predictedAddress = factory.getAddress(owner1, salt);

        vm.expectEmit(true, true, false, true);
        emit SimpleAccountFactory.AccountCreated(predictedAddress, owner1, salt);

        factory.createAccount(owner1, salt);
    }

    function testGetAddress() public {
        uint256 salt = 0;

        address predictedAddress = factory.getAddress(owner1, salt);

        SimpleAccount account = factory.createAccount(owner1, salt);

        assertEq(address(account), predictedAddress);
    }

    function testSameOwnerSameSaltSameAddress() public {
        uint256 salt = 42;

        address predicted1 = factory.getAddress(owner1, salt);
        address predicted2 = factory.getAddress(owner1, salt);

        assertEq(predicted1, predicted2);
    }

    function testDifferentSaltDifferentAddress() public {
        uint256 salt1 = 1;
        uint256 salt2 = 2;

        address address1 = factory.getAddress(owner1, salt1);
        address address2 = factory.getAddress(owner1, salt2);

        assertTrue(address1 != address2);
    }

    function testDifferentOwnerDifferentAddress() public {
        uint256 salt = 0;

        address address1 = factory.getAddress(owner1, salt);
        address address2 = factory.getAddress(owner2, salt);

        assertTrue(address1 != address2);
    }

    function testIdempotentDeployment() public {
        uint256 salt = 10;

        SimpleAccount account1 = factory.createAccount(owner1, salt);
        SimpleAccount account2 = factory.createAccount(owner1, salt);

        assertEq(address(account1), address(account2));
    }

    function testMultipleAccountsForSameOwner() public {
        uint256 salt1 = 100;
        uint256 salt2 = 200;

        SimpleAccount account1 = factory.createAccount(owner1, salt1);
        SimpleAccount account2 = factory.createAccount(owner1, salt2);

        assertTrue(address(account1) != address(account2));

        assertEq(account1.owner(), owner1);
        assertEq(account2.owner(), owner1);
    }

    function testMultipleOwnersMultipleAccounts() public {
        uint256 salt1 = 1;
        uint256 salt2 = 2;

        SimpleAccount account1 = factory.createAccount(owner1, salt1);
        SimpleAccount account2 = factory.createAccount(owner2, salt2);

        assertTrue(address(account1) != address(account2));

        assertEq(account1.owner(), owner1);
        assertEq(account2.owner(), owner2);
    }

    function testCreatedAccountHasCorrectOwner() public {
        uint256 salt = 0;

        SimpleAccount account = factory.createAccount(owner1, salt);

        assertEq(account.owner(), owner1);
    }

    function testCreatedAccountLinkedToEntryPoint() public {
        uint256 salt = 0;

        SimpleAccount account = factory.createAccount(owner1, salt);

        assertEq(address(account.entryPoint()), address(entryPoint));
    }

    function testCreateAccountGasUsage() public {
        uint256 salt = 999;

        uint256 gasBefore = gasleft();
        factory.createAccount(owner1, salt);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for createAccount:", gasUsed);
    }

    function testCreateWithZeroSalt() public {
        uint256 salt = 0;

        SimpleAccount account = factory.createAccount(owner1, salt);

        assertTrue(address(account) != address(0));
        assertEq(account.owner(), owner1);
    }

    function testCreateWithMaxSalt() public {
        uint256 salt = type(uint256).max;

        SimpleAccount account = factory.createAccount(owner1, salt);

        assertTrue(address(account) != address(0));
        assertEq(account.owner(), owner1);
    }

    function testGetAddressBeforeDeployment() public {
        uint256 salt = 123;
        address predicted = factory.getAddress(owner1, salt);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(predicted)
        }
        assertEq(codeSize, 0);
        SimpleAccount account = factory.createAccount(owner1, salt);
        assembly {
            codeSize := extcodesize(predicted)
        }
        assertTrue(codeSize > 0);
        assertEq(address(account), predicted);
    }
}
