# 4TEEN Smart Contracts

Core smart contracts powering the **4TEEN ecosystem on TRON**.

This repository contains the full on-chain infrastructure behind the 4TEEN token system including the token contract, liquidity controller, DEX executors, vault architecture, and automation tools.

The system is designed as a **modular on-chain liquidity infrastructure**, where token issuance, liquidity scheduling, and distribution logic are separated into dedicated contracts.

---

# Overview

4TEEN is a TRC-20 token with a **mint-on-purchase model and time-locked supply mechanics**.

The system combines:

• mint-on-demand token issuance  
• per-purchase time locks  
• scheduled liquidity injection  
• modular executor architecture for DEX integration  
• transparent vault-based token distribution  

All core logic is executed **on-chain**.

Important:

- The token itself does not generate profit.
- Market price depends on liquidity and demand.
- Price growth logic affects only the purchase price inside the token contract.

---

# Architecture

The 4TEEN system is built as a **multi-contract architecture**.
User TRX
↓
FourteenToken
↓
Liquidity Controller
↓
DEX Executors
↓
DEX Pools (Sun.io / JustMoney)
Additional vault contracts manage token distribution and team allocations.

---

# Contracts

## FourteenToken

Main TRC-20 token contract.

Features:

- mint-on-purchase token issuance
- 14-day lock for each purchase
- algorithmic purchase price growth
- automatic TRX distribution

TRX distribution on purchase:

| Destination | Share |
|-------------|------|
| Liquidity Controller | 90% |
| Owner wallet | 7% |
| Airdrop Vault | 3% |

---

## FourteenLiquidityController

Responsible for **scheduled liquidity injections**.

Key rules:

- liquidity can execute once per UTC day
- minimum controller balance: **100 TRX**
- daily release: **6.43% of controller balance**
- execution is **permissionless**

Liquidity is split:
50% → JustMoney executor
50% → Sun.io executor
---

## Liquidity Executors

Executors contain **DEX-specific liquidity logic**.

### LiquidityExecutorSunV3

Adds liquidity to **Sun.io V3 concentrated liquidity pools**.

Features:

- reads pool price from `slot0()`
- calculates token ratio dynamically
- mints or increases NFT liquidity position

---

### LiquidityExecutorJustMoney

Adds liquidity to **JustMoney AMM pools**.

Features:

- reads reserves from pair contract
- calculates proportional token amount
- adds liquidity via router

---

# Vault Contracts

## FourteenVault

Secure vault storing 4TEEN tokens used for liquidity provisioning.

Features:

- tokens can only be pulled by the LiquidityBootstrapper
- no owner withdrawal of tokens
- prevents unauthorized liquidity access

---

## TeamLockVault

Team token lock contract.

Properties:

- locks tokens for **365 days**
- tokens release only after the lock expires
- funds go directly to beneficiary
- no emergency withdrawal

---

## AirdropVault

Handles staged community token distribution.

Distribution schedule:

| Wave | Allocation |
|-----|-------------|
| 1 | 500,000 |
| 2 | 350,000 |
| 3 | 250,000 |
| 4 | 180,000 |
| 5 | 120,000 |
| 6 | 100,000 |

Total: **1,500,000 4TEEN**

Each wallet can claim through multiple social platforms.

---

# Liquidity Bootstrapper

The **LiquidityBootstrapper** prepares executors before liquidity execution.

Responsibilities:

- calculates token requirements for each executor
- pulls required tokens from the vault
- triggers controller execution

This ensures executors always have enough tokens to pair with TRX liquidity.

---

# Automation

Automation is implemented through **GitHub Actions**.

The automation script:

1. Runs daily
2. Calls `bootstrapAndExecute()`
3. Confirms transaction
4. Sends result to monitoring webhook

Schedule:
00:10 UTC every day
The automation does **not control liquidity rules**, it only triggers the on-chain mechanism.

---

# Repository Structure
contracts/
token/
FourteenToken.sol

liquidity/
FourteenLiquidityController.sol
LiquidityExecutorSunV3.sol
LiquidityExecutorJustMoney.sol
LiquidityBootstrapper.sol

vaults/
FourteenVault.sol
TeamLockVault.sol
AirdropVault.sol

automation/
runBootstrapper.js
daily.yml

docs/
architecture.md
---

# Deployed Contracts

TRON Mainnet:

FourteenToken  
https://tronscan.org/#/token20/TMLXiCW2ZAkvjmn79ZXa4vdHX5BE3n9x4A

FourteenLiquidityController  
https://tronscan.org/#/contract/TVKBLwg222skKnZ3F3boTiH35KC7nvYEuZ

FourteenVault  
https://tronscan.org/#/contract/TNwkuHA727RZGtpbowH7q5B1yZWk2JEZTq

TeamLockVault  
https://tronscan.org/#/contract/TYBfbgvMW6awPdZfSSwWoEX3nJjrKWZS3h

AirdropVault  
https://tronscan.org/#/contract/TV6eXKWCsZ15c3Svz39mRQWtBsqvNNBwpQ

LiquidityBootstrapper  
https://tronscan.org/#/contract/TWfUee6qFV91t7KbFdYLEfpi8nprUaJ7dc

Sun.io Executor  
https://tronscan.org/#/contract/TU8EwEWg4K594zwThvhTZxqzEuEYuR46xh

JustMoney Executor  
https://tronscan.org/#/contract/TWrz68MRTf1m9vv8xpcdMD4z9kjBxiHw7F

---

# Transparency

All contracts are open-source.

Anyone can:

- review the code
- verify on-chain logic
- trigger liquidity execution
- inspect transactions

The frontend interface is informational only.  
The smart contracts are the **sole source of truth**.

---

# License

MIT License
