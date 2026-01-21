// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleAccount.sol";
import "../interfaces/IERC4337.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SimpleAccountFactory
 * @notice Deploys SimpleAccount instances with CREATE2 for deterministic addresses
 * @dev Factory contract for creating smart accounts with predictable addresses
 */
contract SimpleAccountFactory {
    /// @notice ERC-4337 EntryPoint contract address
    IEntryPoint public immutable entryPoint;
    /// @notice SimpleAccount implementation used by proxies
    SimpleAccount public immutable accountImplementation;

    /**
     * @notice Emitted when a new account is created
     * @param account Address of the created account
     * @param owner Owner of the account
     * @param salt Salt used for CREATE2
     */
    event AccountCreated(address indexed account, address indexed owner, uint256 salt);

    /**
     * @notice Initialize the factory
     * @param _entryPoint ERC-4337 EntryPoint address
     */
    constructor(IEntryPoint _entryPoint) {
        require(address(_entryPoint) != address(0), "Factory: invalid entrypoint");
        entryPoint = _entryPoint;
        accountImplementation = new SimpleAccount(_entryPoint);
    }

    /**
     * @notice Create a SimpleAccount with deterministic address
     * @param owner Owner address for the account
     * @param salt Salt for CREATE2 deployment
     * @return account Created or existing SimpleAccount
     */
    function createAccount(address owner, uint256 salt) public returns (SimpleAccount account) {
        address predicted = getAddress(owner, salt);
        if (_isContract(predicted)) {
            return SimpleAccount(payable(predicted));
        }

        account = SimpleAccount(
            payable(new ERC1967Proxy{salt: bytes32(salt)}(
                    address(accountImplementation), abi.encodeCall(SimpleAccount.initialize, (owner))
                ))
        );
        emit AccountCreated(address(account), owner, salt);
    }

    /**
     * @notice Compute the deterministic address without deploying
     * @param owner Owner address for the account
     * @param salt Salt for CREATE2
     * @return Predicted address of the account
     */
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes memory initData = abi.encodeCall(SimpleAccount.initialize, (owner));
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(accountImplementation), initData))
        );
        return Create2.computeAddress(bytes32(salt), bytecodeHash, address(this));
    }

    /**
     * @notice Check if address has contract code
     * @param addr Address to check
     * @return True if address is a contract
     */
    function _isContract(address addr) internal view returns (bool) {
        return addr.code.length > 0;
    }
}
