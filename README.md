# Solana ↔ ISO 20022 Message Gateway

Bridge stablecoin transactions on Solana to the banking world's native language. Generate ISO 20022 bank statements, custody reports, and execute payment orders — all from a single HTML file running in your browser.

![Alt text](public/images/isofix-pic-01.png)

Built by [Gbits.io](https://gbits.io) during [StableHacks: Building Institutional Stablecoin Infrastructure on Solana](https://dorahacks.io/hackathon/stablehacks/tracks) (Deadline: 2026/03/22).


[![License: BSL 1.1](https://img.shields.io/badge/Code-BSL%201.1-green)](LICENSE)
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/Docs-CC%20BY--NC--SA%204.0-blue)](https://creativecommons.org/licenses/by-nc-sa/4.0/)
[![Solana](https://img.shields.io/badge/Solana-Devnet-9945ff)](https://explorer.solana.com/?cluster=devnet)
[![Hackathon](https://img.shields.io/badge/Hackathon-Stablehacks%20Q1%202026-f59e0b)]()
[![Zero Build](https://img.shields.io/badge/Zero_Dependencies-No_Build_Step-22c55e)]()


---

## What it does

**Solana → ISO 20022 (primary direction)**

Connect your Solana wallet, select a date range, and generate XML reports that import directly into accounting software like Bexio, SAP, or Abacus — no manual data entry, no CSV hacks.

- **camt.053.001.04** — BankToCustomerStatement. Your stablecoin transaction history as a standard bank statement.
- **camt.054.001.08** — BankToCustomerDebitCreditNotification (SPS 2024). Real-time payment notifications for instant payment workflows.
- **semt.002.001.11** — SecuritiesBalanceCustodyReport. A point-in-time snapshot of all SPL token holdings in your wallet. Uses the v11 `<BlckChainAdrOrWllt>` element — ISO 20022's native blockchain address field.

**ISO 20022 → Solana (reverse direction)**

- **pain.001.001.03** — CustomerCreditTransferInitiation (SPS 2009 Swiss flavor). Upload a standard Swiss payment order file. The gateway parses each payment, resolves the creditor's IBAN to a Solana address via [verified-iban.sol](https://www.sns.id/domain/verified-iban) SNS subdomains, and constructs SPL token transfers with memo.

**Real-time camt.054 notifications**

The Realtime tab demonstrates inbound payment monitoring: when a stablecoin payment arrives on-chain, ISOFIX generates a camt.054 debit/credit notification. Currently simulated in the browser; a Cloudflare Worker backend for live Helius webhook processing is planned.

- Simulate inbound payments with randomized counterparty, stablecoin, and amount
- Show your wallet address as a scannable Solana QR code for easy testing
- View, download, copy, or email each notification
- Syntax-highlighted XML viewer for inspecting generated messages

## Supported stablecoins

| Token | Currency | Mint |
|-------|----------|------|
| USDC  | USD      | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` |
| USDT  | USD      | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` |
| PYUSD | USD      | `2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo` |
| EURC  | EUR      | `HzwqbKZw8HxMN6bF2yFZNrht3c2iXXzpKcFu7uBEDKtr` |
| EUROe | EUR      | `2VhjJ9WxaGC3EZFwJG9BDUs9KxKCAjQY4vgd1qxgYWVg` |
| VCHF  | CHF      | `AhhdRu5YZdjVkKR3wbnUDaymVQL2ucjMQ63sZ3LFHsch` |

The semt.002 custody report includes **all** SPL tokens in the wallet, not just stablecoins.

## Architecture

```
┌───────────────┐           ┌───────────────────────┐           ┌────────────────┐
│  Solana       │  ──RPC──▶ │  isofix               │  ──XML──▶ │  Bexio / SAP   │
│  Blockchain   │           │  (single HTML file)   │           │  / Abacus      │
└───────────────┘           └───────────┬───────────┘           └────────────────┘
                                        │
                            ┌───────────┴───────────┐
                            │  Browser-only         │
                            │  No backend           │
                            │  No build step        │
                            │  No frameworks        │
                            └───────────────────────┘
```

**By design, this is one `.html` file.** No React, no Node.js, no build tools, no bundlers. Open the file in a browser and it works. This is intentional:

- **Auditability** — Every line of code is visible in a single file. You can read exactly what it does before connecting your wallet.
- **Portability** — Drag it to Netlify, open it from your desktop, host it on IPFS. It runs anywhere a browser runs.
- **Zero supply chain** — No `node_modules`, no dependency vulnerabilities, no build artifacts to trust.

External dependencies loaded from CDN:
- `@solana/web3.js` v1.95.8 (transaction construction for pain.001 execution)
- Google Fonts (Outfit + JetBrains Mono)

### Planned: thin server layer

A minimal Cloudflare Worker is planned for:
- **Helius RPC proxy** — Move the API key server-side instead of embedding it in the client. Required for production use.
- **Real-time notifications** — Helius Webhook → Cloudflare Worker → SSE → Browser for live camt.054 generation when payments arrive.
- **ISOFIX REST API** — Companies fetch camt.053/054 reports programmatically via `GET /api/v1/reports/camt053?address={addr}&from={date}&to={date}`.
- **Multi-chain extensibility** — The same relay pattern works with Infura/Alchemy webhooks for Ethereum L1/L2 stablecoins (USDC on Base, Arbitrum, etc.).

The client remains a static HTML file. The server is a stateless relay (~50 lines of Cloudflare Worker). See `docs/ISOFIX_ServerSide_Plan.md` for the full plan.

## IBAN → Solana resolution

The pain.001 executor resolves creditor IBANs to Solana addresses using [Bonfida SNS](https://sns.id) subdomain lookups:

```
IBAN: CH5204835012345671000
  ↓ normalize to lowercase
ch5204835012345671000.verified-iban.sol
  ↓ SNS resolution
Solana address: 4dcVxYLg8ofyC9tbUvS4JBV7nBMUsHN1hTHmzU1BJy7Y
```

The `verified-iban.sol` domain is owned by the project. IBAN subdomains are registered manually after verification.

## The round-trip

This is the key demo: a Swiss payment standard file goes in, a Solana transaction comes out, and a Swiss accounting import comes back.

1. Creditor creates a QR-bill → encodes as pain.001
2. Debtor uploads pain.001 to isofix → sends VCHF on Solana with `QRR:{ref}` memo
3. Creditor connects wallet → generates camt.054 → imports into Bexio
4. Bexio auto-matches the payment to the invoice via QR reference

All without touching a bank.

## Swiss Payment Standards compliance

- **camt.053.001.04** — SPS 2009, namespace `urn:iso:std:iso:20022:tech:xsd:camt.053.001.04`
- **camt.054.001.08** — SPS 2024 v2.1.1, with structured `<Sts><Cd>BOOK</Cd></Sts>` and `<DtTm>` booking dates for instant payments
- **pain.001.001.03** — SPS 2009 Swiss flavor, supports both SIX namespace (`http://www.six-interbank-clearing.com/de/pain.001.001.03.ch.02.xsd`) and ISO namespace
- **semt.002.001.11** — ISO 20022 Release 2019, with `<BlckChainAdrOrWllt>` blockchain address element
- QR reference forwarding via SPL Memo (`QRR:{ref}` pattern)
- Bexio import validated (Feb 2026): camt.053, camt.054, duplicate detection across message types

## Quick start

1. Open `index.html` in a browser (or visit [iso.gbits.io](https://iso.gbits.io))
2. Connect your Solana wallet (Phantom, Solflare, Backpack)
3. Verify wallet ownership (sign a message)
4. Select a date range and report type
5. Click Generate → download the XML → import into your accounting software

For pain.001 execution: switch to the "Execute Payments" tab, upload a pain.001 XML file, review parsed payments, and send.

For real-time notifications: switch to the "Realtime" tab, simulate an inbound payment or show your wallet QR code to receive a real one.

## Status

| Feature | Status |
|---------|--------|
| camt.053 generation | ✅ Working, Bexio-validated |
| camt.054 generation | ✅ Working, Bexio-validated |
| semt.002 generation | ✅ Working |
| pain.001 parsing | ✅ Working |
| IBAN → Solana (SNS) | ✅ Working |
| Syntax-highlighted XML viewer | ✅ Working |
| Realtime camt.054 (simulated) | ✅ Working |
| Wallet QR code for testing | ✅ Working |
| Field mapping reference | ✅ Working |
| Message flow animation | ✅ Working |
| pain.001 → SPL transfer | ⚠️ Needs paid Helius key |
| Real-time notifications (live) | 🔲 Planned (Cloudflare Worker) |
| Helius RPC proxy | 🔲 Planned (Cloudflare Worker) |
| ISOFIX REST API | 🔲 Planned |
| Ethereum L1/L2 support | 🔲 Planned |

## Project structure

```
isofix/
├── public/                              # Deployable web root
│   ├── index.html                       # The entire application (~130KB)
│   ├── isofix_flow.html                 # Landing page message flow animation
│   ├── camt053_field_mapping.html       # Solana → camt.053 field mapping reference
│   └── images/
│       └── isofix-pic-01.png
├── docs/
│   ├── ISOFIX_Project_Knowledge.md      # Detailed technical documentation
│   ├── ISOFIX_ServerSide_Plan.md        # Cloudflare Worker implementation plan
│   └── roadmap.md                       # Milestone roadmap with timeline
├── llms.txt
├── README.md
└── LICENSE
```

Yes, the web app is one HTML file.

## Documentation

| Document | Purpose |
|----------|---------|
| [Field Mapping](https://iso.gbits.io/camt053_field_mapping.html) | Interactive reference showing how each Solana on-chain field maps to camt.053 XML elements |
| [Message Flow](https://iso.gbits.io/isofix_flow.html) | Animated diagram of the bidirectional Solana ↔ ISO 20022 architecture |
| [Project Knowledge](docs/ISOFIX_Project_Knowledge.md) | Technical deep-dive: architecture, all three tabs, wallet integration, known issues, how to resume work |
| [Server-Side Plan](docs/ISOFIX_ServerSide_Plan.md) | Cloudflare Worker implementation plan with route structure and TODO list |
| [Roadmap](docs/roadmap.md) | Five milestones: server-side, live realtime, multi-chain, REST API, improvements |

## License

Business Source License 1.1

**Parameters:**

- **Licensor:** Roman Bischoff, Zürich
- **Licensed Work:** isofix
- **Additional Use Grant:** You may use the Licensed Work for non-commercial, personal, academic, research, and development purposes, including use on Solana testnet and devnet. Production use for commercial payment processing services requires a separate commercial license.
- **Change Date:** 2028-03-01
- **Change License:** Apache License, Version 2.0

The full BSL 1.1 text is available at https://mariadb.com/bsl11/

© 2026 Roman Bischoff. All rights reserved.

---

Built with stubbornness and a single HTML file by the [Gbits.io](https://gbits.io) team.
