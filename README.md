# ArtaPay Smart Contracts

Smart Contract for ArtaPay dApp using ERC-4337 Account Abstraction payment infrastructure enabling gasless stablecoin transactions on Base Sepolia.

## Overview

ArtaPay is a decentralized payment platform that leverages ERC-4337 Account Abstraction to provide:

- **Only time approval**: Users only need eth in the beginning for one time approval and then become gasless
- **Gasless Transactions**: Users pay fees in stablecoins instead of native ETH
- **Multi-Stablecoin Support**: Support for 9 stablecoins (USDC, USDS, EURC, BRZ, AUDD, CADC, ZCHF, tGBP, IDRX)
- **QR Payment Requests**: Merchants create gasless payment requests via off-chain signatures
- **Auto-Swap**: Automatic cross-token swaps during payments
- **Deterministic Smart Accounts**: Predictable account addresses using CREATE2

## Architecture

### Core Contracts

#### 1. **Paymaster.sol** - ERC-4337 Paymaster

The central contract for sponsoring gas fees and collecting payment in stablecoins.

**Key Features:**

- ERC-4337 v0.7 compatible
- Works with Gelato Bundler
- Supports ERC-2612 Permit for gasless approvals
- 5% gas fee markup (configurable)
- Multi-token support via StablecoinRegistry

**Main Functions:**

- `validatePaymasterUserOp()` - Validates UserOperations and sponsors gas
- `postOp()` - Collects fees in stablecoins after execution
- `calculateFee()` - Calculates stablecoin cost for ETH gas

#### 2. **StablecoinRegistry.sol** - Rate & Conversion Registry

Manages stablecoin metadata and handles conversions between different tokens.

**Key Features:**

- Supports 9 stablecoins with hardcoded exchange rates
- 8 decimal precision for all rates
- Uses USD as intermediate for conversions
- ETH ↔ Stablecoin conversion for gas calculations
- Rate change limits (50% max per update)

**Main Functions:**

- `convert()` - Convert between any two registered stablecoins
- `ethToToken()` - Convert ETH amount to stablecoin for gas fees
- `updateRate()` - Update exchange rates (owner only)

#### 3. **PaymentProcessor.sol** - Payment Request Handler

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

#### 4. **StableSwap.sol** - Liquidity Pool

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

#### 5. **SimpleAccount.sol** - ERC-4337 Smart Account

Minimal smart account implementation with owner-signature validation.

**Key Features:**

- ERC-4337 v0.7 compatible
- Owner-controlled execution
- Single-owner signature validation
- Batch execution support

#### 6. **SimpleAccountFactory.sol** - Smart Account Factory

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

## Setup & Installation

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
# Deployment & Verification
PRIVATE_KEY=0x...
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=your_api_key

# EntryPoint (ERC-4337 v0.7)
ENTRYPOINT_ADDRESS=0x0000000071727De22E5E9d8BAf0edAc6f37da032

# Initial Configuration
INITIAL_ETH_USD_RATE=300000000000  # $3000 with 8 decimals

# Stablecoin Rates (8 decimal precision)
USDC_RATE=100000000        # 1 USD
USDS_RATE=100000000        # 1 USD
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
```

## Network Information

### Base Sepolia Testnet

- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org

## Supported Stablecoins

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

## Contract Addresses

### Base Sepolia (Testnet)

```
EntryPoint:            0x0000000071727De22E5E9d8BAf0edAc6f37da032
StablecoinRegistry:    TBD
Paymaster:             TBD
StableSwap:            TBD
PaymentProcessor:      TBD
SimpleAccountFactory:  TBD

Mock Tokens:
  USDC:  TBD
  USDS:  TBD
  EURC:  TBD
  BRZ:   TBD
  AUDD:  TBD
  CADC:  TBD
  ZCHF:  TBD
  tGBP:  TBD
  IDRX:  TBD
```

## Security Considerations

- **Rate Updates**: StablecoinRegistry has a 50% max rate change limit per update to prevent abuse.
- **Paymaster Deposits**: Monitor EntryPoint deposits to ensure sufficient gas sponsorship funds.
- **Nonce Replay**: PaymentProcessor uses nonces to prevent replay attacks.
- **Signature Validation**: All off-chain signatures are validated on-chain before execution.

## Development

### Code Style

This project uses:

- Solidity 0.8.31 Cancun
- Foundry for testing and deployment
- OpenZeppelin contracts for standards

### Project Structure

```
artapay-sc/
├── src/
│   ├── account/          # ERC-4337 Smart Account contracts
│   ├── interfaces/       # Contract interfaces
│   ├── paymaster/        # Paymaster contract
│   ├── payment/          # Payment processing contracts
│   ├── registry/         # Stablecoin registry
│   ├── swap/             # Swap pool contracts
│   └── token/            # Mock token contracts
├── test/                 # Test files
├── script/               # Deployment scripts
└── foundry.toml          # Foundry configuration
```

## License

MIT License - see LICENSE file for details
