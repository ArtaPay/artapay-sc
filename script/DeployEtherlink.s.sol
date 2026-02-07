// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/token/MockStableCoin.sol";
import "../src/registry/StablecoinRegistry.sol";
import "../src/registry/QRISRegistry.sol";
import "../src/paymaster/Paymaster.sol";
import "../src/swap/StableSwap.sol";
import "../src/payment/PaymentProcessor.sol";
import "../src/account/SimpleAccountFactory.sol";

/**
 * @title DeployEtherlink
 * @notice Deployment script for Etherlink Shadownet (USDC, USDT, IDRX only)
 */
contract DeployEtherlink is Script {
    MockStableCoin public usdc;
    MockStableCoin public usdt;
    MockStableCoin public idrx;

    StablecoinRegistry public registry;
    QRISRegistry public qrisRegistry;
    Paymaster public paymaster;
    StableSwap public stableSwap;
    PaymentProcessor public paymentProcessor;
    SimpleAccountFactory public accountFactory;

    function _getNativeUsdRate() internal view returns (uint256) {
        return vm.envOr("INITIAL_XTZ_USD_RATE", vm.envUint("INITIAL_ETH_USD_RATE"));
    }

    function _buildTokenConfig(address usdcAddr, address usdtAddr, address idrxAddr)
        internal
        view
        returns (address[] memory tokens, string[] memory symbols, string[] memory regions, uint256[] memory rates)
    {
        tokens = new address[](3);
        symbols = new string[](3);
        regions = new string[](3);
        rates = new uint256[](3);

        tokens[0] = usdcAddr;
        symbols[0] = "USDC";
        regions[0] = "US";
        rates[0] = vm.envUint("USDC_RATE");

        tokens[1] = usdtAddr;
        symbols[1] = "USDT";
        regions[1] = "US";
        rates[1] = vm.envUint("USDT_RATE");

        tokens[2] = idrxAddr;
        symbols[2] = "IDRX";
        regions[2] = "ID";
        rates[2] = vm.envUint("IDRX_RATE");
    }

    function deployRegistryAndPaymaster() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n========================================");
        console.log("   ARTAPAY ETHERLINK REGISTRY+PAYMASTER");
        console.log("========================================\n");
        console.log("Deployer Address:", deployer);
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("XTZ/USD Rate:", _getNativeUsdRate());

        address usdcAddr = vm.envAddress("MOCK_USDC_ADDRESS");
        address usdtAddr = vm.envAddress("MOCK_USDT_ADDRESS");
        address idrxAddr = vm.envAddress("MOCK_IDRX_ADDRESS");

        (address[] memory tokens, string[] memory symbols, string[] memory regions, uint256[] memory rates) =
            _buildTokenConfig(usdcAddr, usdtAddr, idrxAddr);

        console.log("\n=== Deploying StablecoinRegistry ===");
        registry = new StablecoinRegistry();
        console.log("StablecoinRegistry deployed at:", address(registry));
        registry.setEthUsdRate(_getNativeUsdRate());
        console.log("XTZ/USD rate set to:", _getNativeUsdRate());

        console.log("\n=== Registering Stablecoins ===");
        registry.batchRegisterStablecoins(tokens, symbols, regions, rates);
        console.log("Registered 3 stablecoins in registry");

        console.log("\n=== Deploying Paymaster ===");
        paymaster = new Paymaster(vm.envAddress("ENTRYPOINT_ADDRESS"), address(registry));
        console.log("Paymaster deployed at:", address(paymaster));
        paymaster.addSupportedTokens(tokens);
        console.log("Added 3 supported tokens to Paymaster");

        uint256 totalWei = vm.envOr("ENTRYPOINT_DEPOSIT_WEI", uint256(0));
        if (totalWei > 0) {
            uint256 stakeWei = totalWei / 2;
            uint256 depositWei = totalWei - stakeWei;

            if (depositWei > 0) {
                paymaster.deposit{value: depositWei}();
                console.log("Deposited to EntryPoint:", depositWei, "wei");
            }

            if (stakeWei > 0) {
                uint256 unstakeDelay = vm.envOr("ENTRYPOINT_UNSTAKE_DELAY_SEC", uint256(86400));
                require(unstakeDelay <= type(uint32).max, "ENTRYPOINT_UNSTAKE_DELAY_SEC too large");
                paymaster.addStake{value: stakeWei}(uint32(unstakeDelay));
                console.log("Staked in EntryPoint:", stakeWei, "wei");
                console.log("Unstake delay:", unstakeDelay, "sec");
            }
        } else {
            console.log("Skipping EntryPoint deposit/stake (ENTRYPOINT_DEPOSIT_WEI not set)");
        }

        console.log("\n========================================");
        console.log("   COPY TO .env FILE");
        console.log("========================================\n");
        console.log("STABLECOIN_REGISTRY_ADDRESS=%s", address(registry));
        console.log("PAYMASTER_ADDRESS=%s", address(paymaster));
        console.log("\n========================================\n");

        vm.stopBroadcast();
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n========================================");
        console.log("   ARTAPAY ETHERLINK DEPLOYMENT");
        console.log("========================================\n");
        console.log("Deployer Address:", deployer);
        console.log("EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("XTZ/USD Rate:", _getNativeUsdRate());

        console.log("\n=== Step 1: Deploying Mock Stablecoins ===");

        usdc = new MockStableCoin("USD Coin", "USDC", 6, "US");
        console.log("USDC deployed at:", address(usdc));

        usdt = new MockStableCoin("Tether USD", "USDT", 6, "US");
        console.log("USDT deployed at:", address(usdt));

        idrx = new MockStableCoin("Indonesia Rupiah", "IDRX", 6, "ID");
        console.log("IDRX deployed at:", address(idrx));

        console.log("\n=== Step 2: Minting Initial Supply ===");

        usdc.mint(deployer, 100000 * 10 ** 6); // 100K USDC
        console.log("Minted 100,000 USDC to deployer");

        usdt.mint(deployer, 100000 * 10 ** 6); // 100K USDT
        console.log("Minted 100,000 USDT to deployer");

        idrx.mint(deployer, 1600000000 * 10 ** 6); // 1.6B IDRX
        console.log("Minted 1,600,000,000 IDRX to deployer");

        console.log("\n=== Step 3: Deploying StablecoinRegistry ===");

        registry = new StablecoinRegistry();
        console.log("StablecoinRegistry deployed at:", address(registry));

        registry.setEthUsdRate(_getNativeUsdRate());
        console.log("XTZ/USD rate set to:", _getNativeUsdRate());

        console.log("\n=== Step 4: Deploying QRISRegistry ===");

        qrisRegistry = new QRISRegistry();
        console.log("QRISRegistry deployed at:", address(qrisRegistry));

        console.log("\n=== Step 5: Registering Stablecoins ===");

        (address[] memory tokens, string[] memory symbols, string[] memory regions, uint256[] memory rates) =
            _buildTokenConfig(address(usdc), address(usdt), address(idrx));

        registry.batchRegisterStablecoins(tokens, symbols, regions, rates);
        console.log("Registered 3 stablecoins in registry");

        console.log("\n=== Step 6: Deploying Paymaster ===");

        paymaster = new Paymaster(vm.envAddress("ENTRYPOINT_ADDRESS"), address(registry));
        console.log("Paymaster deployed at:", address(paymaster));

        paymaster.addSupportedTokens(tokens);
        console.log("Added 3 supported tokens to Paymaster");

        uint256 totalWei = vm.envOr("ENTRYPOINT_DEPOSIT_WEI", uint256(0));
        if (totalWei > 0) {
            uint256 stakeWei = totalWei / 2;
            uint256 depositWei = totalWei - stakeWei;

            if (depositWei > 0) {
                paymaster.deposit{value: depositWei}();
                console.log("Deposited to EntryPoint:", depositWei, "wei");
            }

            if (stakeWei > 0) {
                uint256 unstakeDelay = vm.envOr("ENTRYPOINT_UNSTAKE_DELAY_SEC", uint256(86400));
                require(unstakeDelay <= type(uint32).max, "ENTRYPOINT_UNSTAKE_DELAY_SEC too large");
                paymaster.addStake{value: stakeWei}(uint32(unstakeDelay));
                console.log("Staked in EntryPoint:", stakeWei, "wei");
                console.log("Unstake delay:", unstakeDelay, "sec");
            }
        } else {
            console.log("Skipping EntryPoint deposit/stake (ENTRYPOINT_DEPOSIT_WEI not set)");
        }

        console.log("\n=== Step 7: Deploying StableSwap ===");

        stableSwap = new StableSwap(address(registry));
        console.log("StableSwap deployed at:", address(stableSwap));

        console.log("\n=== Adding Initial Liquidity to StableSwap ===");
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = MockStableCoin(tokens[i]).balanceOf(deployer);
            uint256 liquidityAmount = balance / 90; // 90% of balance

            MockStableCoin(tokens[i]).approve(address(stableSwap), liquidityAmount);
            stableSwap.deposit(tokens[i], liquidityAmount);

            console.log("Added", symbols[i], "liquidity:", liquidityAmount);
        }

        console.log("\n=== Step 8: Deploying PaymentProcessor ===");

        paymentProcessor = new PaymentProcessor(
            address(stableSwap),
            address(registry),
            deployer // Fee recipient
        );
        console.log("PaymentProcessor deployed at:", address(paymentProcessor));
        console.log("Fee recipient set to:", deployer);

        console.log("\n=== Step 9: Deploying SimpleAccountFactory ===");

        accountFactory = new SimpleAccountFactory(IEntryPoint(vm.envAddress("ENTRYPOINT_ADDRESS")));
        console.log("SimpleAccountFactory deployed at:", address(accountFactory));

        console.log("\n========================================");
        console.log("   DEPLOYMENT SUMMARY");
        console.log("========================================\n");

        console.log("Network Configuration:");
        console.log("  EntryPoint:", vm.envAddress("ENTRYPOINT_ADDRESS"));
        console.log("  XTZ/USD Rate:", _getNativeUsdRate());

        console.log("\nMock Stablecoins:");
        console.log("  USDC:", address(usdc));
        console.log("  USDT:", address(usdt));
        console.log("  IDRX:", address(idrx));

        console.log("\nCore Contracts:");
        console.log("  StablecoinRegistry:", address(registry));
        console.log("  QRISRegistry:", address(qrisRegistry));
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
        console.log("QRIS_REGISTRY_ADDRESS=%s", address(qrisRegistry));
        console.log("PAYMASTER_ADDRESS=%s", address(paymaster));
        console.log("STABLE_SWAP_ADDRESS=%s", address(stableSwap));
        console.log("PAYMENT_PROCESSOR_ADDRESS=%s", address(paymentProcessor));
        console.log("SIMPLE_ACCOUNT_FACTORY=%s", address(accountFactory));
        console.log("\nMOCK_USDC_ADDRESS=%s", address(usdc));
        console.log("MOCK_USDT_ADDRESS=%s", address(usdt));
        console.log("MOCK_IDRX_ADDRESS=%s", address(idrx));

        console.log("\n========================================\n");
        console.log("Deployment completed successfully!");
        console.log("Run verification manually using forge verify-contract\n");

        vm.stopBroadcast();
    }
}
