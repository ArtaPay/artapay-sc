// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SimpleAccount.sol";
import "../interfaces/IERC4337.sol";

/**
 * @title SimpleAccountFactory
 * @notice Deploys SimpleAccount instances with CREATE2 for deterministic addresses.
 */
contract SimpleAccountFactory {
    IEntryPoint public immutable entryPoint;

    event AccountCreated(address indexed account, address indexed owner, uint256 salt);

    constructor(IEntryPoint _entryPoint) {
        require(address(_entryPoint) != address(0), "Factory: invalid entrypoint");
        entryPoint = _entryPoint;
    }

    /**
     * @notice Create a SimpleAccount for owner with deterministic salt.
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
     * @notice Compute the address for owner+salt without deploying.
     */
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(SimpleAccount).creationCode,
                abi.encode(entryPoint, owner)
            )
        );
        bytes32 _data = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), bytecodeHash)
        );
        return address(uint160(uint256(_data)));
    }

    function _isContract(address addr) internal view returns (bool) {
        return addr.code.length > 0;
    }
}
