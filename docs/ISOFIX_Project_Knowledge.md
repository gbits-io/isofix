# ISOFIX — Project Knowledge

> **What is this?** ISOFIX is a bidirectional bridge between Solana blockchain stablecoin
> payments and ISO 20022 banking messages. It runs as a single-page web app at `iso.gbits.io`.
> Part of the Gbits.io ecosystem, built for the **StableHacks 2026** hackathon on DoraHacks.

**Owner:** Roman (romanix@gbits.io) · Koivu GmbH, Zürich
**Last updated:** 2026-03-11
**Repository/Deployment:** Hosted on Cloudflare Pages at `iso.gbits.io`

---

## Quick Orientation

ISOFIX does three things:

1. **Generate bank statements** (camt.053, camt.054) from on-chain Solana stablecoin transactions
2. **Execute bank payments** (pain.001) as on-chain Solana SPL token transfers
3. **Receive real-time notifications** (camt.054) when inbound stablecoin payments arrive (planned: Helius webhook; current: simulated)

Everything runs client-side in the browser. There is no backend yet (a Cloudflare Worker is planned — see `ISOFIX_ServerSide_Plan.md`).

---

## Architecture

```
                                    ISOFIX (iso.gbits.io)
                                    Single HTML file, ~130KB
                                    Vanilla JS, no framework

    ┌──────────────────────────────────────────────────────────────────────┐
    │                        BROWSER (index.html)                         │
    │                                                                     │
    │  ┌─────────────┐  ┌──────────────────┐  ┌───────────────────────┐  │
    │  │ Tab 1:      │  │ Tab 2: Realtime  │  │ Tab 3: Execute        │  │
    │  │ Generate    │  │ camt.054         │  │ Payments              │  │
    │  │ Reports     │  │                  │  │                       │  │
    │  │             │  │ • Simulate btn   │  │ • Upload pain.001 XML │  │
    │  │ • Connect   │  │ • QR code for    │  │ • Parse creditor list │  │
    │  │   wallet    │  │   wallet addr    │  │ • Resolve IBAN→Solana │  │
    │  │ • Verify    │  │ • Notification   │  │   via SNS subdomains  │  │
    │  │   ownership │  │   feed           │  │ • Sign & send SPL     │  │
    │  │ • Fetch txs │  │                  │  │   token transfers     │  │
    │  │ • Generate  │  │ (Future: SSE     │  │                       │  │
    │  │   XML       │  │  from Worker)    │  │                       │  │
    │  └──────┬──────┘  └────────┬─────────┘  └───────────┬───────────┘  │
    └─────────┼──────────────────┼────────────────────────┼──────────────┘
              │                  │                        │
              ▼                  ▼                        ▼
    ┌──────────────────┐  ┌───────────┐  ┌──────────────────────────────┐
    │   Helius RPC     │  │  Helius   │  │  Bonfida SNS Proxy           │
    │   (API key in    │  │  Webhook  │  │  sns-sdk-proxy.bonfida.      │
    │    client JS!)   │  │  (planned)│  │  workers.dev                 │
    │                  │  │           │  │                              │
    │  • getSignatures │  │  • POST   │  │  Resolves:                   │
    │    ForAddress    │  │    on SPL │  │  {iban}.verified-iban.sol     │
    │  • parseTransac- │  │    token  │  │  → Solana wallet address     │
    │    tions (DAS)   │  │    xfer   │  │                              │
    └────────┬─────────┘  └─────┬─────┘  └──────────────────────────────┘
             │                  │
             ▼                  ▼
    ┌──────────────────────────────────────┐
    │         Solana Blockchain            │
    │                                      │
    │  SPL Token Transfers:                │
    │  • USDC  (EPjFWdd5Aufq...Dt1v)  USD │
    │  • USDT  (Es9vMFrzaCER...NYB)   USD │
    │  • PYUSD (2b1kV6DkPAnx...GXo)  USD │
    │  • EURC  (HzwqbKZw8HxM...Ktr)  EUR │
    │  • EUROe (2VhjJ9WxaGC3...Vg)   EUR │
    │  • VCHF  (AhhdRu5YZdjV...sch)  CHF │
    └──────────────────────────────────────┘
```

---

## File Inventory

| File | Size | What it is |
|------|------|------------|
| `index.html` | ~130KB | The entire application: HTML + CSS + JS in one file |
| `isofix_flow.html` | ~32KB | Landing page animation showing the bidirectional message flow |
| `camt053_field_mapping.html` | ~25KB | Reference table: Solana fields → camt.053 XML elements |
| `ISOFIX_ServerSide_Plan.md` | ~12KB | Cloudflare Worker implementation plan and TODO list |
| `ISOFIX_Project_Knowledge.md` | this file | Project knowledge for future sessions |

---

## The Three Tabs in Detail

### Tab 1: Generate Reports (camt.053, camt.054, semt.002)

**User flow:**
1. Connect Solana wallet (Phantom, Solflare, Backpack — or paste address manually)
2. Verify wallet ownership via `signMessage` (optional but recommended)
3. Enter IBAN (links the XML to a Bexio bank account) — "Use Demo IBAN" button fills `LI21088100002324013AA`
4. Select date range
5. Choose report type: camt.053 (statement), camt.054 (notification), or semt.002 (custody)
6. Click Generate → app fetches stablecoin transactions from Helius → generates XML

**How transaction fetching works:**
- Calls Helius `getSignaturesForAddress` to get signature list in date range
- Then calls Helius `parseTransaction` (DAS API) for each batch
- Filters for SPL token transfers matching known stablecoin mints
- Groups by currency (USD/EUR/CHF) — generates one XML file per currency

**Key functions:**
- `fetchStablecoinTxns()` — Helius RPC calls, pagination, date filtering
- `generateCamt053()` — builds camt.053.001.04 XML (SPS/1.7)
- `generateCamt054()` — builds camt.054.001.08 XML (SPS/2.1)
- `generateSemt002()` — builds semt.002.001.11 XML (custody report of all SPL holdings)

**Report cards** appear below with: View (syntax-highlighted XML modal), Download, Copy, Email buttons.

### Tab 2: Realtime camt.054

**Purpose:** Demonstrate real-time ISO 20022 notifications triggered by blockchain payments.

**Current state (hackathon demo):**
- "Simulate Inbound Stablecoin Payment" button generates a fake camt.054 with random counterparty, stablecoin, amount, and realistic Solana signature
- "Show Connected Address" button displays a Solana QR code (rendered via a pure-JS QR encoder, no external library) so someone can scan with a wallet app and send a real payment
- Notification list shows incoming camt.054s with View/Download/Copy/Email

**Planned state (post-Worker):**
- Browser opens SSE/polling connection to Cloudflare Worker
- Helius webhook fires on inbound SPL transfer → Worker generates camt.054 → pushes to browser
- The `simulateInboundPayment()` function gets replaced by the SSE `onmessage` handler

### Tab 3: Execute Payments (pain.001 → Solana)

**User flow:**
1. Upload a pain.001.001.03 XML file (Swiss SPS 2009 flavor)
2. App parses creditor list: name, IBAN, amount, currency, memo
3. For each creditor IBAN, resolves to a Solana address via SNS subdomain: `{iban}.verified-iban.sol` (Roman owns `verified-iban.sol` on SNS)
4. User selects stablecoin per payment (auto-suggested by currency)
5. Each payment is signed and sent individually via Mobile Wallet Adapter (MWA) or browser wallet

**Key functions:**
- `handlePainFile()` — parses pain.001 XML, extracts payment instructions
- `resolveIbanToSolana()` — calls Bonfida SNS proxy to resolve IBAN subdomain
- `sendPainPayment()` — builds SPL token transfer instruction + memo, signs via wallet

**SNS resolution pattern:** `ch4308005000065810500.verified-iban.sol` → Solana address

---

## ISO 20022 Message Types

| Message | Direction | ISO Name | Schema Version |
|---------|-----------|----------|----------------|
| camt.053 | Solana → ERP | BankToCustomerStatement | camt.053.001.04 (SPS 1.7) |
| camt.054 | Solana → ERP | BankToCustomerDebitCreditNotification | camt.054.001.08 (SPS 2.1) |
| semt.002 | Solana → ERP | SecuritiesBalanceCustodyReport | semt.002.001.11 |
| pain.001 | ERP → Solana | CustomerCreditTransferInitiation | pain.001.001.03 (SPS 2009) |

**Swiss-specific conventions used:**
- BIC `SOLNCHZZXXX` — synthetic BIC for "Solana Network, Zurich" (not a real SWIFT code)
- `AddtlInf: SPS/1.7/PROD` or `SPS/2.1/PROD` — Swiss Payment Standards version tag
- `SubFmlyCd: ESCT` — European SEPA Credit Transfer (for accounting software compatibility)
- QR references: memo field starting with `QRR:` maps to `Strd/CdtrRefInf` with `Prtry: QRR`
- Tested import targets: Bexio, SAP, Abacus

---

## Stablecoin Configuration

Defined in `STABLECOIN_CONFIG` (line ~600). Each entry has: `mint` (SPL address), `decimals` (all 6), `currency` (ISO 4217), `label`.

```
Token   Mint (first 8 chars)   Currency   Report Grouping
─────   ───────────────────    ────────   ──────────────────
USDC    EPjFWdd5...            USD        ┐
USDT    Es9vMFrz...            USD        ├─ One camt per currency
PYUSD   2b1kV6Dk...            USD        ┘
EURC    HzwqbKZw...            EUR        ┐
EUROe   2VhjJ9Wx...            EUR        ┘
VCHF    AhhdRu5Y...            CHF        ── Sole CHF stablecoin
```

---

## External Dependencies

| Dependency | Loaded from | Purpose |
|------------|-------------|---------|
| `@solana/web3.js` v1.95.8 | unpkg CDN | Transaction building, PublicKey, Connection |
| Helius RPC | `mainnet.helius-rpc.com` | Transaction fetching and parsing |
| Bonfida SNS Proxy | `sns-sdk-proxy.bonfida.workers.dev` | IBAN → Solana address resolution |
| Google Fonts | `fonts.googleapis.com` | Outfit (body), JetBrains Mono (code) |

**No framework.** No React, no Vue, no build step. Everything is vanilla JS in a single HTML file. This is intentional — Roman wants the code to be auditable by bank compliance officers who can read plain JS.

---

## Wallet Integration

**Desktop:** Detects Phantom, Solflare, Backpack via `window.phantom.solana`, `window.solflare`, `window.backpack.solana`.

**Mobile:** Auto-detects wallet provider injected in webview. If not in a wallet browser, offers deeplinks to open in Phantom/Solflare.

**Verification:** `signMessage` with a timestamped message proving wallet ownership. Some mobile wallets don't support `signMessage` — the app gracefully falls back with a warning.

**State:** Stored in the global `walletState` object: `{ connected, publicKey, walletName, verified, provider }`.

---

## Known Issues and Gotchas

**File truncation:** The `index.html` is ~130KB. During editing sessions, the file repeatedly gets truncated near the end (inside `sendPainPayment()`). Always verify the file ends with `</script></body></html>` after any edit.

**Cloudflare artifacts:** When saving the HTML from the live Cloudflare-served site, Cloudflare injects `email-decode.min.js` (returns 404 locally, blocks JS execution) and obfuscates email addresses with `__cf_email__` spans. Never use a re-download from `iso.gbits.io` as source — always work from the local canonical copy.

**Helius API key exposed:** The key `cf479a6e-8fe8-4363-ab5b-8898913fbaff` is in client JS. The planned Cloudflare Worker proxy (`/rpc`) will fix this.

**Helius public endpoints deprecated:** Solana's public RPC endpoints (`api.mainnet-beta.solana.com`) now return HTTP 403 for browser-origin requests. All RPC calls must go through Helius. This was the migration that prompted the Helius integration.

**pain.001 sending paused:** The `sendPainPayment()` function works but Roman paused transaction sending pending a paid Helius subscription (free tier has rate limits).

**QR code generator:** The built-in QR encoder is a minimal Reed-Solomon implementation (version 1-6, byte mode, ECC-L). It works for `solana:{address}` URIs but may not handle complex URIs with query parameters. Consider swapping for `qrcode-generator` library if needed.

---

## Planned Server-Side Component

A Cloudflare Worker (`api.gbits.io`) will serve multiple projects:

```
┌─────────────────────────────────────────────────┐
│           Cloudflare Worker                      │
│                                                  │
│  POST /rpc ─────────── Helius RPC proxy          │
│  POST /webhook/helius ─ Webhook receiver         │
│  GET  /stream/camt054 ─ SSE/polling to browser   │
│  POST /swiyu/verify ─── E-ID verification        │
│  GET  /swiyu/callback ─ E-ID callback            │
│                                                  │
│  Used by: ISOFIX, AlpenSign, Gbits Pay           │
└─────────────────────────────────────────────────┘
```

Full details in `ISOFIX_ServerSide_Plan.md`.

---

## Related Projects

| Project | Relation to ISOFIX |
|---------|-------------------|
| **AlpenSign** | Solana Seeker hackathon — biometric payment authorization. Shares Helius RPC proxy and swiyu E-ID via same Worker |
| **Gbits Pay** (`app.gbits.io`) | Stablecoin payment system for Swiss QR invoices. Will share swiyu E-ID integration |
| **Koivu GmbH** (`koivu.network`) | Roman's fintech company — continuous payment monitoring for banks. ISOFIX is a complementary tool |
| **verified-iban.sol** | SNS domain Roman owns — used for IBAN→Solana resolution in pain.001 execution |

---

## How to Resume Work

1. **Upload `index.html`** (the local canonical copy, NOT a re-download from Cloudflare)
2. **Upload this document** (`ISOFIX_Project_Knowledge.md`) for context
3. **If working on the Worker:** also upload `ISOFIX_ServerSide_Plan.md`
4. **First thing after upload:** verify the HTML ends with `</script></body></html>` and contains no `cdn-cgi` strings
5. **If the file is truncated:** the last function is `sendPainPayment()` — it needs a closing `catch`, `}`, and the HTML closing tags
