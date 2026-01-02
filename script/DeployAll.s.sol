// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/token/MockStableCoin.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/paymaster/Paymaster.sol";

/**
 * @title DeployAll
 * @notice Comprehensive deployment script for LBC ERC-4337 Paymaster system
 * @dev Deploys all mock tokens, registry, and paymaster on Lisk Sepolia
 * 
 * Usage:
 *   forge script script/DeployAll.s.sol --rpc-url $LISK_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployAll is Script {
    // Deployed contracts
    MockStableCoin public usdc;
    MockStableCoin public usdt;
    MockStableCoin public idrx;
    MockStableCoin public jpyc;
    MockStableCoin public euroc;
    MockStableCoin public mxnt;
    MockStableCoin public cnht;
    
    StablecoinRegistry public registry;
    Paymaster public paymaster;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n=== Configuration ===");
        console.log("Deployer Address:", deployer);
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("Initial ETH/USD Rate:", vm.envUint("INITIAL_ETH_USD_RATE"));
        
        // ============ Step 1: Deploy Mock Stablecoins ============
        console.log("\n=== Deploying Mock Stablecoins ===");
        
        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        console.log("USDC deployed at:", address(usdc));
        
        usdt = new MockStableCoin("Tether USD", "USDT", 6, "US");
        console.log("USDT deployed at:", address(usdt));
        
        idrx = new MockStableCoin("Indonesia Rupiah", "IDRX", 6, "ID");
        console.log("IDRX deployed at:", address(idrx));
        
        jpyc = new MockStableCoin("JPY Coin", "JPYC", 8, "JP");
        console.log("JPYC deployed at:", address(jpyc));
        
        euroc = new MockStableCoin("Euro Coin", "EURC", 6, "EU");
        console.log("EUROC deployed at:", address(euroc));
        
        mxnt = new MockStableCoin("Mexican Peso Token", "MXNT", 6, "MX");
        console.log("MXNT deployed at:", address(mxnt));
        
        cnht = new MockStableCoin("Chinese Yuan Token", "CNHT", 6, "CN");
        console.log("CNHT deployed at:", address(cnht));
        
        // ============ Step 2: Mint Initial Supply to Deployer ============
        console.log("\n=== Minting Initial Supply ===");
        
        // Mint tokens to deployer for testing
        usdc.mint(deployer, 1000 * 10**6);   // 1M USDC
        console.log("Minted 1000 USDC to deployer");
        
        usdt.mint(deployer, 1000 * 10**6);   // 1M USDT
        console.log("Minted 1000 USDT to deployer");
        
        idrx.mint(deployer, 16000000 * 10**6); // 16B IDRX (~ $1M)
        console.log("Minted 16,000,000 IDRX to deployer");
        
        jpyc.mint(deployer, 150000 * 10**8); // 150M JPYC (~ $1M)
        console.log("Minted 150,000 JPYC to deployer");
        
        euroc.mint(deployer, 1000 * 10**6);  // 1M EURC (~ $1M)
        console.log("Minted 1,000 EURC to deployer");
        
        mxnt.mint(deployer, 20000000 * 10**6); // 20B MXNT (~ $1M)
        console.log("Minted 20,000,000 MXNT to deployer");
        
        cnht.mint(deployer, 7000 * 10**6);   // 7M CNHT (~ $1M)
        console.log("Minted 7,000 CNHT to deployer");
        
        // ============ Step 3: Deploy StablecoinRegistry ============
        console.log("\n=== Deploying StablecoinRegistry ===");
        
        registry = new StablecoinRegistry();
        console.log("StablecoinRegistry deployed at:", address(registry));
        
        // Set ETH/USD rate
        registry.setEthUsdRate(vm.envUint("INITIAL_ETH_USD_RATE"));
        console.log("ETH/USD rate set to:", vm.envUint("INITIAL_ETH_USD_RATE"));
        
        // ============ Step 4: Register Stablecoins ============
        console.log("\n=== Registering Stablecoins ===");
        
        // Prepare arrays for batch registration
        address[] memory tokens = new address[](7);
        string[] memory symbols = new string[](7);
        string[] memory regions = new string[](7);
        uint256[] memory rates = new uint256[](7);
        
        // USDC
        tokens[0] = address(usdc);
        symbols[0] = "USDC";
        regions[0] = "US";
        rates[0] = vm.envUint("USDC_RATE");
        
        // USDT
        tokens[1] = address(usdt);
        symbols[1] = "USDT";
        regions[1] = "US";
        rates[1] = vm.envUint("USDT_RATE");
        
        // IDRX
        tokens[2] = address(idrx);
        symbols[2] = "IDRX";
        regions[2] = "ID";
        rates[2] = vm.envUint("IDRX_RATE");
        
        // JPYC
        tokens[3] = address(jpyc);
        symbols[3] = "JPYC";
        regions[3] = "JP";
        rates[3] = vm.envUint("JPYC_RATE");
        
        // EUROC
        tokens[4] = address(euroc);
        symbols[4] = "EURC";
        regions[4] = "EU";
        rates[4] = vm.envUint("EURC_RATE");
        
        // MXNT
        tokens[5] = address(mxnt);
        symbols[5] = "MXNT";
        regions[5] = "MX";
        rates[5] = vm.envUint("MXNT_RATE");
        
        // CNHT
        tokens[6] = address(cnht);
        symbols[6] = "CNHT";
        regions[6] = "CN";
        rates[6] = vm.envUint("CNHT_RATE");
        
        // Batch register all tokens
        registry.batchRegisterStablecoins(tokens, symbols, regions, rates);
        console.log("Registered 7 stablecoins in registry");
        
        // ============ Step 5: Deploy Paymaster ============
        console.log("\n=== Deploying Paymaster ===");
        
        paymaster = new Paymaster(vm.envAddress("ENTRYPOINT_ADDRESS"), address(registry));
        console.log("Paymaster deployed at:", address(paymaster));
        
        // Add supported tokens to Paymaster
        paymaster.addSupportedTokens(tokens);
        console.log("Added 7 supported tokens to Paymaster");
        
        // Deposit ETH to EntryPoint for gas sponsorship (if specified)
        uint256 depositAmountEth = vm.envOr("ENTRYPOINT_INITIAL_DEPOSIT", uint256(0));
        if (depositAmountEth > 0) {
            paymaster.deposit{value: depositAmountEth * 1 ether}();
            console.log("Deposited to EntryPoint:", depositAmountEth, "ETH");
        } else {
            console.log("Skipping deposit (ENTRYPOINT_INITIAL_DEPOSIT not set or = 0)");
        }
        
        // ============ Step 6: Verification ============
        console.log("\n=== Deployment Summary ===");
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("\nMock Stablecoins:");
        console.log("  USDC:", address(usdc));
        console.log("  USDT:", address(usdt));
        console.log("  IDRX:", address(idrx));
        console.log("  JPYC:", address(jpyc));
        console.log("  EURC:", address(euroc));
        console.log("  MXNT:", address(mxnt));
        console.log("  CNHT:", address(cnht));
        console.log("\nCore Contracts:");
        console.log("  StablecoinRegistry:", address(registry));
        console.log("  Paymaster:", address(paymaster));
        
        // Verify configurations
        uint256 registeredCount = registry.getStablecoinCount();
        console.log("\nVerification:");
        console.log("  Registered stablecoins:", registeredCount);
        console.log("  Paymaster deposit:", paymaster.getDeposit());
        
        // Output .env format
        console.log("\n=== Copy to .env ===");
        console.log("STABLECOIN_REGISTRY_ADDRESS=%s", address(registry));
        console.log("PAYMASTER_ADDRESS=%s", address(paymaster));
        console.log("MOCK_USDC_ADDRESS=%s", address(usdc));
        console.log("MOCK_USDT_ADDRESS=%s", address(usdt));
        console.log("MOCK_IDRX_ADDRESS=%s", address(idrx));
        console.log("MOCK_JPYC_ADDRESS=%s", address(jpyc));
        console.log("MOCK_EURC_ADDRESS=%s", address(euroc));
        console.log("MOCK_MXNT_ADDRESS=%s", address(mxnt));
        console.log("MOCK_CNHT_ADDRESS=%s", address(cnht));
        
        vm.stopBroadcast();
    }
}
