// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleAccount.sol";
import "../interfaces/IERC4337.sol";

/**
 * @title SimpleAccountFactory
 * @notice Deploys SimpleAccount instances with CREATE2 for deterministic addresses
 * @dev Factory contract for creating smart accounts with predictable addresses
 */
contract SimpleAccountFactory {
    /// @notice ERC-4337 EntryPoint contract address
    IEntryPoint public immutable entryPoint;

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

        account = new SimpleAccount{salt: bytes32(salt)}(entryPoint, owner);
        emit AccountCreated(address(account), owner, salt);
    }

    /**
     * @notice Compute the deterministic address without deploying
     * @param owner Owner address for the account
     * @param salt Salt for CREATE2
     * @return Predicted address of the account
     */
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes32 bytecodeHash =
            keccak256(abi.encodePacked(type(SimpleAccount).creationCode, abi.encode(entryPoint, owner)));
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), bytecodeHash));
        return address(uint160(uint256(_data)));
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
