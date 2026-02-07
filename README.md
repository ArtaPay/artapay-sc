# ArtaPay Smart Contracts

Smart Contract for ArtaPay dApp using ERC-4337 Account Abstraction payment infrastructure enabling gasless stablecoin transactions on Base Sepolia and Etherlink Shadownet.

## Overview

ArtaPay is a decentralized payment platform that leverages ERC-4337 Account Abstraction to provide:

- **One-time approval**: Users approve once, then all future transactions are gasless
- **Gasless Transactions**: Users pay fees in stablecoins instead of native ETH
- **Multi-Stablecoin Support**: Support for 10 stablecoins (USDC, USDT, USDS, EURC, BRZ, AUDD, CADC, ZCHF, tGBP, IDRX)
- **QR Payment Requests**: Merchants create gasless payment requests via off-chain signatures
- **QRIS Supported**: Pay to QRIS (Quick Response Code Indonesian Standard)
- **Auto-Swap**: Automatic cross-token swaps during payments
- **Deterministic Smart Accounts**: Predictable account addresses using CREATE2

## Architecture

### Core Contracts

#### 1. **Paymaster.sol** - ERC-4337 Paymaster

The central contract for sponsoring gas fees and collecting payment in stablecoins.

**Key Features:**

- ERC-4337 v0.7 compatible
- Works with Pimlico Bundler
- Supports ERC-2612 Permit for gasless approvals
- 5% gas fee markup (configurable)
- Multi-token support via StablecoinRegistry

**Main Functions:**

- `validatePaymasterUserOp()` - Validates UserOperations and sponsors gas
- `postOp()` - Collects fees in stablecoins after execution
- `calculateFee()` - Calculates stablecoin cost for ETH gas

#### 2. **StablecoinRegistry.sol** - Rate and Conversion Registry

Manages stablecoin metadata and handles conversions between different tokens.

**Key Features:**

- Supports 10 stablecoins with hardcoded exchange rates
- 8 decimal precision for all rates
- Uses USD as intermediate for conversions
- ETH <-> Stablecoin conversion for gas calculations
- Rate change limits (50% max per update)

**Main Functions:**

- `convert()` - Convert between any two registered stablecoins
- `ethToToken()` - Convert ETH amount to stablecoin for gas fees
- `updateRate()` - Update exchange rates (owner only)

#### 3. **QRISRegistry.sol** - QRIS Registry

Binds QRIS hashes to ArtaPay Smart Accounts with whitelist-based onboarding.

**Key Features:**

- One SA can register only one QRIS hash
- Stores merchant metadata (name, id, city)

**Main Functions:**

- `registerQris()` - Register QRIS hash to caller SA
- `removeQris()` - Remove QRIS binding
- `getQris()` / `getQrisBySa()` - Lookup registry data

#### 4. **PaymentProcessor.sol** - Payment Request Handler

Processes QR-based payment requests with off-chain merchant signatures.

**Key Features:**

- Gasless for merchants (sign request off-chain)
- Platform fee: 0.3% (30 BPS)
- Auto-swap if payer uses different token
- Replay protection with nonces
- Deadline validation

**Main Functions:**

- `executePayment()` - Execute payment with merchant signature
- `calculatePaymentCost()` - Calculate total cost including fees

#### 5. **StableSwap.sol** - Liquidity Pool

Owner-managed liquidity pool for stablecoin swaps.

**Key Features:**

- Swap fee: 0.1% (10 BPS)
- Owner-controlled liquidity (private pool)
- Slippage protection
- Uses StablecoinRegistry for conversion rates

**Main Functions:**

- `swap()` - Execute token swap
- `getSwapQuote()` - Get swap quote without execution
- `deposit()` / `withdraw()` - Manage liquidity (owner only)

#### 6. **SimpleAccount.sol** - ERC-4337 Smart Account

Minimal smart account implementation with owner-signature validation.

**Key Features:**

- ERC-4337 v0.7 compatible
- Owner-controlled execution
- Single-owner signature validation
- Batch execution support

#### 7. **SimpleAccountFactory.sol** - Smart Account Factory

Factory for deploying deterministic smart accounts using CREATE2.

**Key Features:**

- Deterministic address generation
- CREATE2 deployment
- Same owner + salt = same address

## Fee Structure

| Fee Type       | Rate          | Paid By | Token      |
| -------------- | ------------- | ------- | ---------- |
| Platform Fee   | 0.3% (30 BPS) | Payer   | Stablecoin |
| Swap Fee       | 0.1% (10 BPS) | Payer   | Stablecoin |

## Setup and Installation

### Installation

```bash
# Clone repository
git clone <repository-url>
cd artapay-sc

# Install dependencies
forge install
```

### Environment Setup

Create a `.env` file in the root directory:

```bash
# Deployment and Verification
PRIVATE_KEY=0x...
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
ETHERLINK_SHADOWNET_RPC_URL=https://node.shadownet.etherlink.com
BASESCAN_API_KEY=your_api_key

# EntryPoint (ERC-4337 v0.7)
# Update this address to match the target network you deploy to.
ENTRYPOINT_ADDRESS=0x0000000071727De22E5E9d8BAf0edAc6f37da032

# Initial Configuration
INITIAL_ETH_USD_RATE=300000000000  # $3000 with 8 decimals

# Stablecoin Rates (8 decimal precision)
USDC_RATE=100000000        # 1 USD
USDS_RATE=100000000        # 1 USD
USDT_RATE=100000000        # 1 USD
EURC_RATE=95000000         # 0.95 EUR per USD
BRZ_RATE=500000000         # 5 BRL per USD
AUDD_RATE=160000000        # 1.6 AUD per USD
CADC_RATE=135000000        # 1.35 CAD per USD
ZCHF_RATE=90000000         # 0.9 CHF per USD
TGBP_RATE=80000000         # 0.8 GBP per USD
IDRX_RATE=1600000000000    # 16,000 IDR per USD

# Optional: EntryPoint deposit for gas sponsorship
ENTRYPOINT_DEPOSIT_WEI=10000000000000000000  # 10 ETH
```

## Testing

Run the test suite:

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/Paymaster.t.sol
```

## Deployment

### Deploy All Contracts

```bash
# Deploy to Base Sepolia
forge script script/DeployAll.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify

# Or use the shorthand
forge script script/DeployAll.s.sol --rpc-url base_sepolia --broadcast --verify

# Deploy to Etherlink Shadownet (EVM Osaka)
# Use DeployEtherlink.s.sol if you only want USDC, USDT, and IDRX.
forge script script/DeployAll.s.sol \
  --rpc-url $ETHERLINK_SHADOWNET_RPC_URL \
  --broadcast \
  --profile etherlink

# Or use the shorthand
forge script script/DeployAll.s.sol --rpc-url etherlink_shadownet --broadcast --profile etherlink

# Deploy to Etherlink Shadownet (USDC, USDT, IDRX only)
forge script script/DeployEtherlink.s.sol \
  --rpc-url $ETHERLINK_SHADOWNET_RPC_URL \
  --broadcast \
  --profile etherlink
```

## Network Information

### Base Sepolia Testnet

- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://base-sepolia.blockscout.com

### Etherlink Shadownet Testnet

- **Chain ID**: 127823
- **RPC URL**: https://node.shadownet.etherlink.com
- **Block Explorer**: https://shadownet.explorer.etherlink.com
- **Faucet**: https://shadownet.faucet.etherlink.com/

## Supported Stablecoins

### Base Sepolia

| Symbol | Name               | Decimals | Region |
| ------ | ------------------ | -------- | ------ |
| USDC   | USD Coin           | 6        | US     |
| USDS   | Sky Dollar         | 6        | US     |
| EURC   | EURC               | 6        | EU     |
| BRZ    | Brazilian Digital  | 6        | BR     |
| AUDD   | AUDD               | 6        | AU     |
| CADC   | CAD Coin           | 6        | CA     |
| ZCHF   | Frankencoin        | 6        | CH     |
| tGBP   | Tokenised GBP      | 18       | GB     |
| IDRX   | IDRX               | 6        | ID     |

### Etherlink Shadownet

| Symbol | Name          | Decimals | Region |
| ------ | ------------- | -------- | ------ |
| USDC   | USD Coin      | 6        | US     |
| USDT   | Tether USD    | 6        | US     |
| IDRX   | IDRX          | 6        | ID     |

## Contract Addresses

### Base Sepolia (Testnet)

```
EntryPoint:            0x0000000071727De22E5E9d8BAf0edAc6f37da032
StablecoinRegistry:    0x573f4D2b5e9E5157693a9Cc0008FcE4e7167c584
Paymaster:             0x1b14BF9ab47069a77c70Fb0ac02Bcb08A9Ffe290
StableSwap:            0x822e1dfb7bf410249b2bE39809A5Ae0cbfae612f
PaymentProcessor:      0x4D053b241a91c4d8Cd86D0815802F69D34a0164B
SimpleAccountFactory:  0xfEA9DD0034044C330c0388756Fd643A5015d94D2
QRISRegistry:          0x243826f0f2487c0D0B07Cb313080BE76818F4aa2

Mock Tokens:
  USDC:  0x74FB067E49CBd0f97Dc296919e388CB3CFB62b4D
  USDS:  0x79f3293099e96b840A0423B58667Bc276Ea19aC0
  EURC:  0xfF4dD486832201F6DC41126b541E3b47DC353438
  BRZ:   0x9d30F685C04f024f84D9A102d0fE8dF348aE7E7d
  AUDD:  0x9f6b8aF49747304Ce971e2b9d131B2bcd1841d83
  CADC:  0x6BB3FFD9279fBE76FE0685Df7239c23488bC96e4
  ZCHF:  0xF27edF22FD76A044eA5B77E1958863cf9A356132
  tGBP:  0xb4db79424725256a6E6c268fc725979b24171857
  IDRX:  0x34976B6c7Aebe7808c7Cab34116461EB381Bc2F8
```

### Etherlink Shadownet (Testnet)

```
EntryPoint:            0x0000000071727De22E5E9d8BAf0edAc6f37da032
StablecoinRegistry:    0x6fe372ef0B695ec05575D541e0DA60bf18A3D0f0
Paymaster:             0xFC7E8c60315e779b1109B252fcdBFB8f3524F9B6
StableSwap:            0xB67b210dEe4C1A744c1d51f153b3B3caF5428F60
PaymentProcessor:      0x5D4748951fB0AF37c57BcCb024B3EE29360148bc
SimpleAccountFactory:  0xb7E56FbAeC1837c5693AAf35533cc94e35497d86
QRISRegistry:          0xD17d8f2819C068A57f0F4674cF439d1eC96C56f5

Mock Tokens:
  USDC:  0x60E48d049EB0c75BF428B028Da947c66b68f5dd2
  USDT:  0xcaF86109F34d74DE0e554FD5E652C412517374fb
  IDRX:  0x8A272505426D4F129EE3493A837367B884653237
```

## Security Considerations

- **Rate Updates**: StablecoinRegistry has a 50% max rate change limit per update to prevent abuse.
- **Paymaster Deposits**: Monitor EntryPoint deposits to ensure sufficient gas sponsorship funds.
- **Nonce Replay**: PaymentProcessor uses nonces to prevent replay attacks.
- **Signature Validation**: All off-chain signatures are validated on-chain before execution.

## Development

### Code Style

This project uses:

- Solidity 0.8.31 (Cancun by default, Osaka for Etherlink profile)
- Foundry for testing and deployment
- OpenZeppelin contracts for standards

### Project Structure

```
artapay-sc/
- src/               # Smart contracts
  - account/         # ERC-4337 Smart Account contracts
  - interfaces/      # Contract interfaces
  - paymaster/       # Paymaster contract
  - payment/         # Payment processing contracts
  - registry/        # Stablecoin registry
  - swap/            # Swap pool contracts
  - token/           # Mock token contracts
- test/              # Test files
- script/            # Deployment scripts
- foundry.toml       # Foundry configuration
```

## License

MIT License - see LICENSE file for details
