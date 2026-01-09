# ArtaPay Smart Contracts

Smart Contract for ArtaPay dApp using ERC-4337 Account Abstraction payment infrastructure enabling gasless stablecoin transactions on Lisk Sepolia.

## Overview

ArtaPay is a decentralized payment platform that leverages ERC-4337 Account Abstraction to provide:

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
| Swap Fee       | 0.1% (10 BPS) | User    | Stablecoin |

## Setup & Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for scripts)

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

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/Paymaster.t.sol

# Run with gas report
forge test --gas-report
```

### Test Coverage

```bash
forge coverage
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

### Manual Deployment Steps

1. **Deploy Mock Tokens** (if not using existing tokens)
2. **Deploy StablecoinRegistry**
3. **Register Stablecoins** in Registry
4. **Deploy Paymaster** with Registry address
5. **Add Supported Tokens** to Paymaster
6. **Deposit ETH** to EntryPoint for gas sponsorship
7. **Deploy StableSwap** (optional)
8. **Deploy PaymentProcessor** (optional)

### Verify Contracts

Contracts are automatically verified during deployment if `--verify` flag is used. To verify manually:

```bash
forge verify-contract <CONTRACT_ADDRESS> \
  src/<PATH>/<CONTRACT>.sol:<CONTRACT_NAME> \
  --chain lisk-sepolia \
  --watch
```

## Network Information

### Lisk Sepolia Testnet

- **Chain ID**: 4202
- **RPC URL**: https://rpc.sepolia-api.lisk.com
- **Block Explorer**: https://sepolia-blockscout.lisk.com
- **EntryPoint v0.7**: `0x0000000071727De22E5E9d8BAf0edAc6f37da032`

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
StablecoinRegistry:    <DEPLOYED_ADDRESS>
Paymaster:             <DEPLOYED_ADDRESS>
StableSwap:            <DEPLOYED_ADDRESS>
PaymentProcessor:      <DEPLOYED_ADDRESS>
SimpleAccountFactory:  <DEPLOYED_ADDRESS>

Mock Tokens:
  USDC:  <DEPLOYED_ADDRESS>
  USDT:  <DEPLOYED_ADDRESS>
  IDRX:  <DEPLOYED_ADDRESS>
  JPYC:  <DEPLOYED_ADDRESS>
  EURC:  <DEPLOYED_ADDRESS>
  MXNT:  <DEPLOYED_ADDRESS>
  CNHT:  <DEPLOYED_ADDRESS>
```

## Security Considerations

- **Private Key Management**: Never commit private keys. Use environment variables or hardware wallets.
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