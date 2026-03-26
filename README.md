# 4TEEN Smart Contracts

Core smart contracts powering the **4TEEN ecosystem on TRON**.

This repository is not just a storage place for contract files.  
It documents the **full on-chain architecture** of the 4TEEN system and shows how the contracts interact with each other.

The system is built as a **modular on-chain infrastructure**, where token issuance, ownership control, liquidity scheduling, DEX execution, vault distribution, and ambassador rewards are separated into dedicated contracts.

This separation makes the system easier to audit, verify, and evolve without mixing all logic into a single contract.

---

# Overview

4TEEN is a TRC-20 token with a **mint-on-purchase model**, **14-day lock mechanics**, **controller-based ownership**, and **scheduled liquidity injection**.

The architecture combines:

- mint-on-demand token issuance
- per-purchase token locks
- controller-managed token administration
- scheduled liquidity release
- DEX-specific executor contracts
- vault-based token distribution
- ambassador and referral reward logic

All core rules are enforced **on-chain**.

Important:

- The token itself does not generate profit.
- Market price depends on liquidity and demand.
- Price growth logic affects only the direct purchase price inside the token contract.
- The token contract owner is not an EOA wallet anymore — it is the **FourteenController** contract.

---

# System Interaction

The 4TEEN architecture is built as a connected contract system.

## Purchase Flow

When a user buys 4TEEN through the token contract:

1. User sends TRX to **FourteenToken**
2. **FourteenToken** mints tokens on demand
3. Purchased tokens are locked for **14 days**
4. Incoming TRX is distributed automatically:
   - **90%** → `FourteenLiquidityController`
   - **7%** → `FourteenController`
   - **3%** → `AirdropVault`

## Ownership and Control Flow

`FourteenToken` is administered by **FourteenController**.

That means privileged token actions are no longer executed by a wallet directly.  
Instead, the token contract delegates ownership-based administration to a dedicated controller contract.

This controller can manage:

- token administrative settings
- liquidity-related administrative actions
- referral and ambassador logic
- reward accounting and withdrawals

## Liquidity Flow

Liquidity does not go directly from user purchase into DEX pools.

Instead:

1. TRX purchase allocation goes into **FourteenLiquidityController**
2. Controller releases liquidity only **once per UTC day**
3. The released amount is **6.43% of controller balance**
4. Released liquidity is split equally:
   - **50%** → `LiquidityExecutorJustMoney`
   - **50%** → `LiquidityExecutorSunV3`
5. Executors add liquidity into their corresponding DEX pools

## Vault Flow

Token reserves are separated into dedicated vault contracts.

- **FourteenVault** stores tokens reserved for liquidity provisioning
- **TeamLockVault** stores team allocation locked for a fixed period
- **AirdropVault** stores community distribution reserves

This creates clean separation between market logic, admin logic, and reserve storage.

---

# High-Level Architecture

```text
User TRX
   ↓
FourteenToken
   ├─ Mint 4TEEN to buyer
   ├─ Lock purchased tokens for 14 days
   ├─ 90% TRX → FourteenLiquidityController
   ├─ 7% TRX  → FourteenController
   └─ 3% TRX  → AirdropVault

FourteenController
   ├─ Owns FourteenToken
   ├─ Manages token owner functions
   ├─ Runs ambassador/referral logic
   └─ Manages reward accounting and withdrawals

FourteenLiquidityController
   ├─ Holds liquidity TRX
   ├─ Releases 6.43% once per UTC day
   └─ Splits liquidity between executors

LiquidityExecutorJustMoney
   └─ Adds liquidity to JustMoney

LiquidityExecutorSunV3
   └─ Adds liquidity to Sun.io V3

Vaults
   ├─ FourteenVault
   ├─ TeamLockVault
   └─ AirdropVault
```

---

# Contracts

## FourteenToken

Main TRC-20 token contract.

Responsibilities:

- mint-on-purchase token issuance
- 14-day lock for each purchase
- direct buy pricing logic
- purchase price growth logic
- automatic TRX distribution on purchase

TRX distribution on purchase:

| Destination | Share |
|-------------|------:|
| FourteenLiquidityController | 90% |
| FourteenController | 7% |
| AirdropVault | 3% |

Important:

The token contract is not directly owned by a regular wallet anymore.  
Its current `owner()` is **FourteenController**, which acts as the administrative control layer of the system.

---

## FourteenController

Administrative control and referral infrastructure contract for the 4TEEN ecosystem.

This contract is the current **owner of FourteenToken**.

Responsibilities:

- manages privileged FourteenToken owner functions
- serves as the administrative control layer above the token
- supports ambassador and referral system logic
- handles reward accounting
- enables claimable reward withdrawals
- separates operational funds from referral balances

In practice, this contract is the bridge between token administration and ecosystem-level incentive mechanics.

---

## FourteenLiquidityController

Responsible for **scheduled liquidity injections**.

Key rules:

- liquidity can execute only once per UTC day
- minimum controller balance: **100 TRX**
- daily release amount: **6.43% of controller balance**
- execution is **permissionless**

Released liquidity is split as follows:

- **50%** → JustMoney executor
- **50%** → Sun.io executor

This contract controls **when** liquidity is released, but not the DEX-specific implementation details.

---

## LiquidityExecutorSunV3

DEX-specific executor for **Sun.io V3 concentrated liquidity**.

Responsibilities:

- reads current pool price
- calculates token amount dynamically
- adds liquidity to Sun.io V3
- manages liquidity through Sun-compatible execution flow

This contract contains only Sun.io-specific execution logic.

---

## LiquidityExecutorJustMoney

DEX-specific executor for **JustMoney AMM pools**.

Responsibilities:

- reads pool reserves
- calculates proportional token amount
- adds liquidity through JustMoney router
- handles JustMoney-specific pool interaction

This contract contains only JustMoney-specific execution logic.

---

## LiquidityBootstrapper

The bootstrapper prepares executors before liquidity execution.

Responsibilities:

- calculates required token amounts
- pulls tokens from **FourteenVault**
- supplies executors before liquidity execution
- triggers liquidity execution flow

This ensures executors have enough tokens available when TRX liquidity is released.

---

# Vault Contracts

## FourteenVault

Secure vault storing 4TEEN tokens reserved for liquidity provisioning.

Properties:

- stores the liquidity reserve allocation
- tokens are used for liquidity operations
- isolated from direct public distribution logic
- keeps liquidity reserves separate from team and airdrop reserves

Funding reference:

- Source wallet: `TN95o1fsA7mNwJGYGedvf3y7DJZKLH6TCT`
- Amount transferred: **2,000,000 4TEEN**
- Transaction:  
  `https://tronscan.org/#/transaction/43e89110f01f00e414768a696788099fbd423bb2b2b63225aa7db37b1e6a46f9`

---

## TeamLockVault

Team token lock contract.

Properties:

- stores team allocation
- tokens are locked for a fixed period
- designed to prevent immediate access to team reserve
- release happens only according to lock rules

Funding reference:

- Source wallet: `TN95o1fsA7mNwJGYGedvf3y7DJZKLH6TCT`
- Amount transferred: **3,000,000 4TEEN**
- Transaction:  
  `https://tronscan.org/#/transaction/981c58cea9d81603288ab9b1154026aca54cc14664c691102117aeb72139454e`

---

## AirdropVault

Community allocation vault for staged ecosystem distribution.

Properties:

- stores community and growth reserve
- supports controlled airdrop allocation
- isolated from liquidity and team reserves
- used for ecosystem expansion and distribution campaigns

Funding reference:

- Source wallet: `TN95o1fsA7mNwJGYGedvf3y7DJZKLH6TCT`
- Amount transferred: **1,500,000 4TEEN**
- Transaction:  
  `https://tronscan.org/#/transaction/c513facce1068fb433f0fd2af83ce2ec44c42020d73dca5dd5ce9e1e272740e1`

---

# Why the Architecture Is Split

The 4TEEN system intentionally separates responsibilities across contracts.

## Why FourteenToken is separated

The token contract should focus on:

- token issuance
- lock logic
- pricing logic
- purchase distribution

It should not become overloaded with:

- referral accounting
- ambassador management
- daily liquidity execution
- vault storage rules
- DEX-specific liquidity logic

## Why FourteenController exists

The controller allows token ownership and ecosystem control to be handled by a dedicated contract instead of a direct wallet.

This improves:

- transparency
- modularity
- upgrade flexibility at the system level
- separation of concerns between token logic and ecosystem logic

## Why executors are separated

Each DEX has its own technical model.

Sun.io V3 and JustMoney do not use the same liquidity flow, so their logic is isolated into separate executor contracts.

This keeps the liquidity layer cleaner and easier to maintain.

## Why vaults are separated

Vault separation makes reserves easier to audit.

Instead of mixing all allocated tokens inside one storage contract, the system isolates:

- liquidity reserve
- team reserve
- community reserve

This makes token allocation more transparent.

---

# Repository Structure

```text
contracts/
  controller/
    FourteenController.sol

  liquidity/
    FourteenLiquidityController.sol
    LiquidityExecutorSunV3.sol
    LiquidityExecutorJustMoney.sol
    LiquidityBootstrapper.sol

  token/
    FourteenToken.sol

  vaults/
    FourteenVault.sol
    TeamLockVault.sol
    AirdropVault.sol
```

---

# Deployed Contracts

## TRON Mainnet

### Core

**FourteenToken**  
https://tronscan.org/#/token20/TMLXiCW2ZAkvjmn79ZXa4vdHX5BE3n9x4A

**FourteenController**  
https://tronscan.org/#/contract/TF8yhohRfMxsdVRr7fFrYLh5fxK8sAFkeZ

**FourteenLiquidityController**  
https://tronscan.org/#/contract/TVKBLwg222skKnZ3F3boTiH35KC7nvYEuZ

### Vaults

**FourteenVault**  
https://tronscan.org/#/contract/TNwkuHA727RZGtpbowH7q5B1yZWk2JEZTq

**TeamLockVault**  
https://tronscan.org/#/contract/TYBfbgvMW6awPdZfSSwWoEX3nJjrKWZS3h

**AirdropVault**  
https://tronscan.org/#/contract/TV6eXKWCsZ15c3Svz39mRQWtBsqvNNBwpQ

### Liquidity Execution

**LiquidityBootstrapper**  
https://tronscan.org/#/contract/TWfUee6qFV91t7KbFdYLEfpi8nprUaJ7dc

**LiquidityExecutorSunV3**  
https://tronscan.org/#/contract/TU8EwEWg4K594zwThvhTZxqzEuEYuR46xh

**LiquidityExecutorJustMoney**  
https://tronscan.org/#/contract/TWrz68MRTf1m9vv8xpcdMD4z9kjBxiHw7F

---

# Automation

Liquidity automation is triggered externally, while the rules remain on-chain.

Automation responsibilities:

1. run on schedule
2. call bootstrap and execution flow
3. confirm transaction
4. send monitoring result if needed

Important:

- automation does **not** define the liquidity rules
- automation only triggers contracts that already enforce those rules on-chain
- if automation changes, the contract rules still remain the source of truth

---

# Transparency

All contracts are open-source.

Anyone can:

- inspect the code
- verify contract interactions
- review on-chain execution
- check vault funding history
- track liquidity logic
- inspect ownership structure

The frontend interface is informational only.  
The smart contracts are the **sole source of truth**.

---

# License

MIT License
