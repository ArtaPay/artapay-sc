// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/paymaster/Paymaster.sol";

/**
 * @title SetPaymasterSigner
 * @notice Script to add or remove authorized signers for Paymaster
 * 
 * Usage:
 *   # Add signer
 *   SIGNER_ADDRESS=0x... AUTHORIZED=true forge script script/SetPaymasterSigner.s.sol --rpc-url $LISK_SEPOLIA_RPC_URL --broadcast
 *   
 *   # Remove signer
 *   SIGNER_ADDRESS=0x... AUTHORIZED=false forge script script/SetPaymasterSigner.s.sol --rpc-url $LISK_SEPOLIA_RPC_URL --broadcast
 */
contract SetPaymasterSigner is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address paymasterAddress = vm.envAddress("PAYMASTER_ADDRESS");
        address signerAddress = vm.envAddress("SIGNER_ADDRESS");
        bool authorized = true;
        
        vm.startBroadcast(deployerPrivateKey);
        
        Paymaster paymaster = Paymaster(payable(paymasterAddress));
        
        console.log("\n=== Set Paymaster Signer ===");
        console.log("Paymaster:", paymasterAddress);
        console.log("Signer:", signerAddress);
        console.log("Authorized:", authorized);
        
        // Check current status
        bool currentStatus = paymaster.isAuthorizedSigner(signerAddress);
        console.log("Current status:", currentStatus);
        
        // Set signer
        paymaster.setSigner(signerAddress, authorized);
        console.log("Signer updated");
        
        // Verify
        bool newStatus = paymaster.isAuthorizedSigner(signerAddress);
        console.log("New status:", newStatus);
        
        vm.stopBroadcast();
    }
}
