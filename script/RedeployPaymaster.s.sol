// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/paymaster/Paymaster.sol";

/**
 * @title RedeployPaymaster
 * @notice Redeploy only the Paymaster using existing mock tokens and registry addresses
 * @dev Uses addresses from .env file
 * 
 * Usage:
 *   forge script script/RedeployPaymaster.s.sol --rpc-url $LISK_SEPOLIA_RPC_URL --broadcast --verify
 */
contract RedeployPaymaster is Script {
    Paymaster public paymaster;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n=== Configuration ===");
        console.log("Deployer Address:", deployer);
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("StablecoinRegistry:", vm.envAddress("STABLECOIN_REGISTRY_ADDRESS"));
        
        // ============ Step 1: Load existing addresses ============
        console.log("\n=== Loading Existing Addresses ===");
        
        address registryAddress = vm.envAddress("STABLECOIN_REGISTRY_ADDRESS");
        console.log("Using StablecoinRegistry at:", registryAddress);
        
        // Load mock token addresses
        address[] memory tokens = new address[](7);
        tokens[0] = vm.envAddress("MOCK_USDC_ADDRESS");
        tokens[1] = vm.envAddress("MOCK_USDT_ADDRESS");
        tokens[2] = vm.envAddress("MOCK_IDRX_ADDRESS");
        tokens[3] = vm.envAddress("MOCK_JPYC_ADDRESS");
        tokens[4] = vm.envAddress("MOCK_EURC_ADDRESS");
        tokens[5] = vm.envAddress("MOCK_MXNT_ADDRESS");
        tokens[6] = vm.envAddress("MOCK_CNHT_ADDRESS");
        
        console.log("\nMock Token Addresses:");
        console.log("  USDC:", tokens[0]);
        console.log("  USDT:", tokens[1]);
        console.log("  IDRX:", tokens[2]);
        console.log("  JPYC:", tokens[3]);
        console.log("  EURC:", tokens[4]);
        console.log("  MXNT:", tokens[5]);
        console.log("  CNHT:", tokens[6]);
        
        // ============ Step 2: Deploy Paymaster ============
        console.log("\n=== Deploying Paymaster ===");
        
        paymaster = new Paymaster(vm.envAddress("ENTRYPOINT_ADDRESS"), registryAddress);
        console.log("Paymaster deployed at:", address(paymaster));
        
        // Add supported tokens to Paymaster
        paymaster.addSupportedTokens(tokens);
        console.log("Added 7 supported tokens to Paymaster");
        
        // Deposit ETH to EntryPoint for gas sponsorship (if specified)
        // ENTRYPOINT_DEPOSIT_WEI should be in wei (e.g., 10000000000000000 for 0.01 ETH)
        uint256 depositWei = vm.envOr("ENTRYPOINT_DEPOSIT_WEI", uint256(0));
        if (depositWei > 0) {
            paymaster.deposit{value: depositWei}();
            console.log("Deposited to EntryPoint:", depositWei, "wei");
        } else {
            console.log("Skipping deposit (ENTRYPOINT_DEPOSIT_WEI not set or = 0)");
        }
        
        // ============ Step 3: Verification ============
        console.log("\n=== Deployment Summary ===");
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("StablecoinRegistry:", registryAddress);
        console.log("Paymaster:", address(paymaster));
        console.log("Paymaster deposit:", paymaster.getDeposit());
        
        // Verify supported tokens
        console.log("\nVerifying supported tokens:");
        for (uint256 i = 0; i < tokens.length; i++) {
            bool isSupported = paymaster.isSupportedToken(tokens[i]);
            console.log("  Token %s: %s", tokens[i], isSupported ? "supported" : "NOT supported");
        }
        
        // Output .env format
        console.log("\n=== Update .env ===");
        console.log("PAYMASTER_ADDRESS=%s", address(paymaster));
        
        vm.stopBroadcast();
    }
}
