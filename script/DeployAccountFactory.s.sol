// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/account/SimpleAccountFactory.sol";
import "../src/account/SimpleAccount.sol";
import "../src/interfaces/IERC4337.sol";

/**
 * @title DeployAccountFactory
 * @notice Deploys SimpleAccountFactory for EntryPoint v0.7 on Lisk Sepolia
 *
 * Usage:
 * forge script script/DeployAccountFactory.s.sol --rpc-url $LISK_SEPOLIA_RPC_URL --broadcast
 * (Requires PRIVATE_KEY, ENTRYPOINT_ADDRESS in env)
 */
contract DeployAccountFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address entryPointAddr = vm.envAddress("ENTRYPOINT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        SimpleAccountFactory factory = new SimpleAccountFactory(IEntryPoint(entryPointAddr));
        vm.stopBroadcast();

        console.log("SimpleAccountFactory deployed at:", address(factory));
        console.log("EntryPoint:", entryPointAddr);
    }
}
