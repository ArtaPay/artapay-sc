# ArtaPay Smart Contracts

Smart Contract for ArtaPay dApp using ERC-4337 Account Abstraction payment infrastructure enabling gasless stablecoin transactions on Lisk Sepolia.

## Overview

ArtaPay is a decentralized payment platform that leverages ERC-4337 Account Abstraction to provide:

- **Only time approval**: Users only need eth in the beginning for one time approval and then become gasless
- **Gasless Transactions**: Users pay fees in stablecoins instead of native ETH
- **Multi-Stablecoin Support**: Support for 7 stablecoins (USDC, USDT, IDRX, JPYC, EURC, MXNT, CNHT)
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

- Supports 7 stablecoins with hardcoded exchange rates
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
LISK_SEPOLIA_RPC_URL=https://rpc.sepolia-api.lisk.com
BLOCKSCOUT_API_KEY=your_api_key

# EntryPoint (ERC-4337 v0.7)
ENTRYPOINT_ADDRESS=0x0000000071727De22E5E9d8BAf0edAc6f37da032

# Initial Configuration
INITIAL_ETH_USD_RATE=300000000000  # $3000 with 8 decimals

# Stablecoin Rates (8 decimal precision)
USDC_RATE=100000000        # 1 USD
USDT_RATE=100000000        # 1 USD
IDRX_RATE=1600000000000    # 16,000 IDR per USD
JPYC_RATE=15000000000      # 150 JPY per USD
EURC_RATE=95000000         # 0.95 EUR per USD
MXNT_RATE=2000000000000    # 20,000 MXN per USD
CNHT_RATE=700000000        # 7 CNY per USD

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
# Deploy to Lisk Sepolia
forge script script/DeployAll.s.sol \
  --rpc-url $LISK_SEPOLIA_RPC_URL \
  --broadcast \
  --verify

# Or use the shorthand
forge script script/DeployAll.s.sol --rpc-url lisk_sepolia --broadcast --verify
```

## Network Information

### Lisk Sepolia Testnet

- **Chain ID**: 4202
- **RPC URL**: https://rpc.sepolia-api.lisk.com
- **Block Explorer**: https://sepolia-blockscout.lisk.com

## Supported Stablecoins

| Symbol | Name               | Decimals | Region |
| ------ | ------------------ | -------- | ------ |
| USDC   | USD Coin           | 6        | US     |
| USDT   | Tether USD         | 6        | US     |
| IDRX   | Indonesia Rupiah   | 6        | ID     |
| JPYC   | JPY Coin           | 8        | JP     |
| EURC   | Euro Coin          | 6        | EU     |
| MXNT   | Mexican Peso Token | 6        | MX     |
| CNHT   | Chinese Yuan Token | 6        | CN     |

## Contract Addresses

### Lisk Sepolia (Testnet)

```
EntryPoint:            0x0000000071727De22E5E9d8BAf0edAc6f37da032
StablecoinRegistry:    0x682C2619E044B7200F2e6198835C934AB3a7199C
Paymaster:             0x6f1330f207Ab5e2a52c550AF308bA28e3c517311
StableSwap:            0x49c37C3b3a96028D2A1A1e678A302C1d727f3FEF
PaymentProcessor:      0x04Ef4D2E10a35b027050816B8F801DEDC67ee49E
SimpleAccountFactory:  0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985

Mock Tokens:
  USDC:  0x301D9ed91BACB39B798a460D133105BA729c6302
  USDT:  0x03F60361Aa488826e7DA7D7ADB2E1c6fC96D1B8B
  IDRX:  0x18bEA3CDa9dE68E74ba9F33F1B2e11ad345112f0
  JPYC:  0x97F9812a67b6cBA4F4D9b1013C5f4D708Ce9aA9e
  EURC:  0xd10F51695bc3318759A75335EfE61E32727330b6
  MXNT:  0x5e8B38DC8E00c2332AC253600975502CF9fbF36a
  CNHT:  0xDFaE672AD0e094Ee64e370da99b1E37AB58AAc4f
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
