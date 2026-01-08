// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/token/MockStableCoin.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/paymaster/Paymaster.sol";
import "../src/swap/StableSwap.sol";
import "../src/payment/PaymentProcessor.sol";
import "../src/account/SimpleAccountFactory.sol";

/**
 * @title DeployAll
 * @notice Comprehensive deployment script for ArtaPay ERC-4337 system
 * @dev Deploys all contracts: tokens, registry, paymaster, swap, payment processor, and account factory
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
    StableSwap public stableSwap;
    PaymentProcessor public paymentProcessor;
    SimpleAccountFactory public accountFactory;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n========================================");
        console.log("   ARTAPAY DEPLOYMENT SCRIPT");
        console.log("========================================\n");
        console.log("Deployer Address:", deployer);
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("Initial ETH/USD Rate:", vm.envUint("INITIAL_ETH_USD_RATE"));
        
        console.log("\n=== Step 1: Deploying Mock Stablecoins ===");
        
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
        
        console.log("\n=== Step 2: Minting Initial Supply ===");
        
        usdc.mint(deployer, 100000 * 10**6);   // 100K USDC
        console.log("Minted 100,000 USDC to deployer");
        
        usdt.mint(deployer, 100000 * 10**6);   // 100K USDT
        console.log("Minted 100,000 USDT to deployer");
        
        idrx.mint(deployer, 1600000000 * 10**6); // 160M IDRX
        console.log("Minted 160,000,000 IDRX to deployer");
        
        jpyc.mint(deployer, 15000000 * 10**8); // 15M JPYC
        console.log("Minted 15,000,000 JPYC to deployer");
        
        euroc.mint(deployer, 100000 * 10**6);  // 100K EURC
        console.log("Minted 100,000 EURC to deployer");
        
        mxnt.mint(deployer, 2000000 * 10**6); // 2M MXNT
        console.log("Minted 2,000,000 MXNT to deployer");
        
        cnht.mint(deployer, 700000 * 10**6);   // 700K CNHT
        console.log("Minted 700,000 CNHT to deployer");
        
        console.log("\n=== Step 3: Deploying StablecoinRegistry ===");
        
        registry = new StablecoinRegistry();
        console.log("StablecoinRegistry deployed at:", address(registry));
        
        // Set ETH/USD rate
        registry.setEthUsdRate(vm.envUint("INITIAL_ETH_USD_RATE"));
        console.log("ETH/USD rate set to:", vm.envUint("INITIAL_ETH_USD_RATE"));
        
        console.log("\n=== Step 4: Registering Stablecoins ===");
        
        address[] memory tokens = new address[](7);
        string[] memory symbols = new string[](7);
        string[] memory regions = new string[](7);
        uint256[] memory rates = new uint256[](7);
        
        tokens[0] = address(usdc);
        symbols[0] = "USDC";
        regions[0] = "US";
        rates[0] = vm.envUint("USDC_RATE");
        
        tokens[1] = address(usdt);
        symbols[1] = "USDT";
        regions[1] = "US";
        rates[1] = vm.envUint("USDT_RATE");
        
        tokens[2] = address(idrx);
        symbols[2] = "IDRX";
        regions[2] = "ID";
        rates[2] = vm.envUint("IDRX_RATE");
        
        tokens[3] = address(jpyc);
        symbols[3] = "JPYC";
        regions[3] = "JP";
        rates[3] = vm.envUint("JPYC_RATE");
        
        tokens[4] = address(euroc);
        symbols[4] = "EURC";
        regions[4] = "EU";
        rates[4] = vm.envUint("EURC_RATE");
        
        tokens[5] = address(mxnt);
        symbols[5] = "MXNT";
        regions[5] = "MX";
        rates[5] = vm.envUint("MXNT_RATE");
        
        tokens[6] = address(cnht);
        symbols[6] = "CNHT";
        regions[6] = "CN";
        rates[6] = vm.envUint("CNHT_RATE");
        
        registry.batchRegisterStablecoins(tokens, symbols, regions, rates);
        console.log("Registered 7 stablecoins in registry");
        
        console.log("\n=== Step 5: Deploying Paymaster ===");
        
        paymaster = new Paymaster(vm.envAddress("ENTRYPOINT_ADDRESS"), address(registry));
        console.log("Paymaster deployed at:", address(paymaster));
        
        // Add supported tokens to Paymaster
        paymaster.addSupportedTokens(tokens);
        console.log("Added 7 supported tokens to Paymaster");
        
        // Deposit ETH to EntryPoint for gas sponsorship (if specified)
        uint256 depositWei = vm.envOr("ENTRYPOINT_DEPOSIT_WEI", uint256(0));
        if (depositWei > 0) {
            paymaster.deposit{value: depositWei}();
            console.log("Deposited to EntryPoint:", depositWei, "wei");
        } else {
            console.log("Skipping EntryPoint deposit (ENTRYPOINT_DEPOSIT_WEI not set)");
        }
        
        console.log("\n=== Step 6: Deploying StableSwap ===");
        
        stableSwap = new StableSwap(address(registry));
        console.log("StableSwap deployed at:", address(stableSwap));
        
        // Add initial liquidity (90% of minted tokens)
        console.log("\n=== Adding Initial Liquidity to StableSwap ===");
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = MockStableCoin(tokens[i]).balanceOf(deployer);
            uint256 liquidityAmount = balance / 90; // 90% of balance
            
            MockStableCoin(tokens[i]).approve(address(stableSwap), liquidityAmount);
            stableSwap.deposit(tokens[i], liquidityAmount);
            
            console.log("Added", symbols[i], "liquidity:", liquidityAmount);
        }
        
        console.log("\n=== Step 7: Deploying PaymentProcessor ===");
        
        paymentProcessor = new PaymentProcessor(
            address(stableSwap),
            address(registry),
            deployer // Fee recipient
        );
        console.log("PaymentProcessor deployed at:", address(paymentProcessor));
        console.log("Fee recipient set to:", deployer);
        
        console.log("\n=== Step 8: Deploying SimpleAccountFactory ===");
        
        accountFactory = new SimpleAccountFactory(IEntryPoint(vm.envAddress("ENTRYPOINT_ADDRESS")));
        console.log("SimpleAccountFactory deployed at:", address(accountFactory));
        
        console.log("\n========================================");
        console.log("   DEPLOYMENT SUMMARY");
        console.log("========================================\n");
        
        console.log("Network Configuration:");
        console.log("  EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("  ETH/USD Rate:", vm.envUint("INITIAL_ETH_USD_RATE"));
        
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
        console.log("  StableSwap:", address(stableSwap));
        console.log("  PaymentProcessor:", address(paymentProcessor));
        console.log("  SimpleAccountFactory:", address(accountFactory));
        
        console.log("\nVerification:");
        console.log("  Registered stablecoins:", registry.getStablecoinCount());
        console.log("  Paymaster deposit:", paymaster.getDeposit(), "wei");
        
        console.log("\n========================================");
        console.log("   COPY TO .env FILE");
        console.log("========================================\n");
        console.log("STABLECOIN_REGISTRY_ADDRESS=%s", address(registry));
        console.log("PAYMASTER_ADDRESS=%s", address(paymaster));
        console.log("STABLE_SWAP_ADDRESS=%s", address(stableSwap));
        console.log("PAYMENT_PROCESSOR_ADDRESS=%s", address(paymentProcessor));
        console.log("SIMPLE_ACCOUNT_FACTORY=%s", address(accountFactory));
        console.log("\nMOCK_USDC_ADDRESS=%s", address(usdc));
        console.log("MOCK_USDT_ADDRESS=%s", address(usdt));
        console.log("MOCK_IDRX_ADDRESS=%s", address(idrx));
        console.log("MOCK_JPYC_ADDRESS=%s", address(jpyc));
        console.log("MOCK_EURC_ADDRESS=%s", address(euroc));
        console.log("MOCK_MXNT_ADDRESS=%s", address(mxnt));
        console.log("MOCK_CNHT_ADDRESS=%s", address(cnht));
        
        console.log("\n========================================\n");
        console.log("Deployment completed successfully!");
        console.log("Run verification manually using forge verify-contract\n");
        
        vm.stopBroadcast();
    }
}
