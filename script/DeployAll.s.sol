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
    MockStableCoin public usds;
    MockStableCoin public eurc;
    MockStableCoin public brz;
    MockStableCoin public audd;
    MockStableCoin public cadc;
    MockStableCoin public zchf;
    MockStableCoin public tgbp;
    MockStableCoin public idrx;

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

        usds = new MockStableCoin("Sky Dollar", "USDS", 6, "US");
        console.log("USDS deployed at:", address(usds));

        eurc = new MockStableCoin("EURC", "EURC", 6, "EU");
        console.log("EURC deployed at:", address(eurc));

        brz = new MockStableCoin("Brazilian Digital", "BRZ", 6, "BR");
        console.log("BRZ deployed at:", address(brz));

        audd = new MockStableCoin("AUDD", "AUDD", 6, "AU");
        console.log("AUDD deployed at:", address(audd));

        cadc = new MockStableCoin("CAD Coin", "CADC", 6, "CA");
        console.log("CADC deployed at:", address(cadc));

        zchf = new MockStableCoin("Frankencoin", "ZCHF", 6, "CH");
        console.log("ZCHF deployed at:", address(zchf));

        tgbp = new MockStableCoin("Tokenised GBP", "tGBP", 18, "GB");
        console.log("tGBP deployed at:", address(tgbp));

        idrx = new MockStableCoin("Indonesia Rupiah", "IDRX", 6, "ID");
        console.log("IDRX deployed at:", address(idrx));

        console.log("\n=== Step 2: Minting Initial Supply ===");

        usdc.mint(deployer, 100000 * 10 ** 6); // 100K USDC
        console.log("Minted 100,000 USDC to deployer");

        usds.mint(deployer, 100000 * 10 ** 6); // 100K USDS
        console.log("Minted 100,000 USDS to deployer");

        eurc.mint(deployer, 100000 * 10 ** 6); // 100K EURC
        console.log("Minted 100,000 EURC to deployer");

        brz.mint(deployer, 100000 * 10 ** 6); // 100K BRZ
        console.log("Minted 100,000 BRZ to deployer");

        audd.mint(deployer, 100000 * 10 ** 6); // 100K AUDD
        console.log("Minted 100,000 AUDD to deployer");

        cadc.mint(deployer, 100000 * 10 ** 6); // 100K CADC
        console.log("Minted 100,000 CADC to deployer");

        zchf.mint(deployer, 100000 * 10 ** 6); // 100K ZCHF
        console.log("Minted 100,000 ZCHF to deployer");

        tgbp.mint(deployer, 100000 * 10 ** 18); // 100K tGBP
        console.log("Minted 100,000 tGBP to deployer");

        idrx.mint(deployer, 1600000000 * 10 ** 6); // 1.6B IDRX
        console.log("Minted 1,600,000,000 IDRX to deployer");

        console.log("\n=== Step 3: Deploying StablecoinRegistry ===");

        registry = new StablecoinRegistry();
        console.log("StablecoinRegistry deployed at:", address(registry));

        // Set ETH/USD rate
        registry.setEthUsdRate(vm.envUint("INITIAL_ETH_USD_RATE"));
        console.log("ETH/USD rate set to:", vm.envUint("INITIAL_ETH_USD_RATE"));

        console.log("\n=== Step 4: Registering Stablecoins ===");

        address[] memory tokens = new address[](9);
        string[] memory symbols = new string[](9);
        string[] memory regions = new string[](9);
        uint256[] memory rates = new uint256[](9);

        tokens[0] = address(usdc);
        symbols[0] = "USDC";
        regions[0] = "US";
        rates[0] = vm.envUint("USDC_RATE");

        tokens[1] = address(usds);
        symbols[1] = "USDS";
        regions[1] = "US";
        rates[1] = vm.envUint("USDS_RATE");

        tokens[2] = address(eurc);
        symbols[2] = "EURC";
        regions[2] = "EU";
        rates[2] = vm.envUint("EURC_RATE");

        tokens[3] = address(brz);
        symbols[3] = "BRZ";
        regions[3] = "BR";
        rates[3] = vm.envUint("BRZ_RATE");

        tokens[4] = address(audd);
        symbols[4] = "AUDD";
        regions[4] = "AU";
        rates[4] = vm.envUint("AUDD_RATE");

        tokens[5] = address(cadc);
        symbols[5] = "CADC";
        regions[5] = "CA";
        rates[5] = vm.envUint("CADC_RATE");

        tokens[6] = address(zchf);
        symbols[6] = "ZCHF";
        regions[6] = "CH";
        rates[6] = vm.envUint("ZCHF_RATE");

        tokens[7] = address(tgbp);
        symbols[7] = "tGBP";
        regions[7] = "GB";
        rates[7] = vm.envUint("TGBP_RATE");

        tokens[8] = address(idrx);
        symbols[8] = "IDRX";
        regions[8] = "ID";
        rates[8] = vm.envUint("IDRX_RATE");

        registry.batchRegisterStablecoins(tokens, symbols, regions, rates);
        console.log("Registered 9 stablecoins in registry");

        console.log("\n=== Step 5: Deploying Paymaster ===");

        paymaster = new Paymaster(vm.envAddress("ENTRYPOINT_ADDRESS"), address(registry));
        console.log("Paymaster deployed at:", address(paymaster));

        // Add supported tokens to Paymaster
        paymaster.addSupportedTokens(tokens);
        console.log("Added 9 supported tokens to Paymaster");

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
        console.log("  USDS:", address(usds));
        console.log("  EURC:", address(eurc));
        console.log("  BRZ:", address(brz));
        console.log("  AUDD:", address(audd));
        console.log("  CADC:", address(cadc));
        console.log("  ZCHF:", address(zchf));
        console.log("  tGBP:", address(tgbp));
        console.log("  IDRX:", address(idrx));

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
        console.log("MOCK_USDS_ADDRESS=%s", address(usds));
        console.log("MOCK_EURC_ADDRESS=%s", address(eurc));
        console.log("MOCK_BRZ_ADDRESS=%s", address(brz));
        console.log("MOCK_AUDD_ADDRESS=%s", address(audd));
        console.log("MOCK_CADC_ADDRESS=%s", address(cadc));
        console.log("MOCK_ZCHF_ADDRESS=%s", address(zchf));
        console.log("MOCK_TGBP_ADDRESS=%s", address(tgbp));
        console.log("MOCK_IDRX_ADDRESS=%s", address(idrx));

        console.log("\n========================================\n");
        console.log("Deployment completed successfully!");
        console.log("Run verification manually using forge verify-contract\n");

        vm.stopBroadcast();
    }
}
