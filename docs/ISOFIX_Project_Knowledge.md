# ISOFIX — Project Knowledge

> **What is this?** ISOFIX is a bidirectional bridge between Solana blockchain stablecoin
> payments and ISO 20022 banking messages. It runs as a single-page web app at `iso.gbits.io`.
> Part of the Gbits.io ecosystem, built for the **StableHacks 2026** hackathon on DoraHacks.

**Owner:** Roman (romanix@gbits.io), Zürich
**Last updated:** 2026-03-14
**Repository/Deployment:** Hosted on Cloudflare Pages at `iso.gbits.io`, GitHub at `github.com/gbits-io/isofix`

---

## Quick Orientation

ISOFIX does three things:

1. **Generate bank statements** (camt.053, camt.054, BAI2) from on-chain Solana stablecoin transactions
2. **Execute bank payments** (pain.001) as on-chain Solana SPL token transfers
3. **Receive real-time notifications** (camt.054) when inbound stablecoin payments arrive (planned: Helius webhook; current: simulated)
4. **Generate custody reports** (semt.002) showing all SPL token holdings

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
    │   Helius RPC     │  │  Helius   │  │  SNS API / SDK Proxy         │
    │   (API key in    │  │  Webhook  │  │  sns-api.bonfida.com         │
    │    client JS!)   │  │  (planned)│  │  sdk-proxy.sns.id            │
    │                  │  │           │  │                              │
    │  • getSignatures │  │  • POST   │  │  Resolves:                   │
    │    ForAddress    │  │    on SPL │  │  {iban}.verified-iban.sol     │
    │  • parseTransac- │  │    token  │  │  → Solana wallet address     │
    │    tions (DAS)   │  │    xfer   │  │  Reverse: address → domains  │
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
| `index.html` | ~165KB | The entire application: HTML + CSS + JS in one file |
| `flows.html` | ~36KB | Landing page animation showing the bidirectional message flow |
| `camt053_field_mapping.html` | ~29KB | Reference table: Solana fields → camt.053 XML elements |
| `field-mapping-faq.html` | ~36KB | FAQ page: 16 questions covering Solana ↔ ISO 20022 mapping decisions |
| `ISOFIX_ServerSide_Plan.md` | ~12KB | Cloudflare Worker implementation plan and TODO list |
| `ISOFIX_Project_Knowledge.md` | this file | Project knowledge for future sessions |
| `hackathon_talking_points.md` | ~9KB | Demo script, talking points, and Q&A for StableHacks 2026 |
| `roadmap.md` | ~11KB | 5-milestone roadmap |

---

## The Three Tabs in Detail

### Tab 1: Generate Reports (camt.053, camt.054, semt.002, BAI2)

**User flow:**
1. Connect Solana wallet (Phantom, Solflare, Backpack — or paste address manually)
2. Verify wallet ownership via `signMessage` (optional but recommended)
3. .sol domain reverse lookup — automatically queries `sns-api.bonfida.com/v2/user/domains/{address}` when wallet connects, displays owned domains as clickable badges
4. Enter IBAN (links the XML to a Bexio bank account) — "Use Demo IBAN" button fills `LI21088100002324013AA`
5. Account Owner (optional) — structured CBPR+ fields: name, street, building number, postal code, town, country. "Use Demo Name" fills Felix Muster, Hugo street 12, 8050 Zürich, CH. Populates `Acct/Ownr/Nm` and `Acct/Ownr/PstlAdr` in generated XML
6. Select date range — quick filter buttons: "This month", "2026", "2025", "Last 30 days"
7. Choose report type: camt.053 (statement), camt.054 (notification), semt.002 (custody), or BAI2 (US bank statement format)
8. Click Generate → app fetches stablecoin transactions from Helius → generates XML or BAI2 text

**How transaction fetching works:**
- Calls Helius `getSignaturesForAddress` to get signature list in date range
- Then calls Helius `parseTransaction` (DAS API) for each batch
- Filters for SPL token transfers matching known stablecoin mints
- Groups by currency (USD/EUR/CHF) — generates one XML file per currency

**Key functions:**
- `fetchStablecoinTxns()` — Helius RPC calls, pagination, date filtering
- `generateCamt053()` — builds camt.053.001.04 XML (SPS/1.7), accepts ownerInfo for structured Ownr/PstlAdr
- `generateCamt054()` — builds camt.054.001.08 XML (SPS/2.1), accepts ownerInfo
- `generateSemt002()` — builds semt.002.001.11 XML (custody report of all SPL holdings)
- `generateBAI2()` — builds BAI2 text file (US bank statement format, amounts in cents, BAI type codes 175/195/475/495)
- `lookupDomainsForAddress()` — reverse SNS lookup via `sns-api.bonfida.com/v2/user/domains/{address}`
- `getOwnerInfo()` — reads account owner form fields, returns structured object for XML generators
- `setDateRange()` — quick date filter presets (thismonth, 2025, 2026, last30)
- `showXmlModal()` — token-based XML syntax highlighter with BAI2 auto-detection and record-type colorizer

**Report cards** appear below with: View (syntax-highlighted XML/BAI2 modal), Download, Copy buttons.

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
| BAI2 | Solana → ERP | Bank Administration Institute v2 (US) | BAI 2005 (non-ISO 20022) |

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
| SNS API (Bonfida) | `sns-api.bonfida.com` | Reverse domain lookup: address → .sol domain names |
| SNS SDK Proxy | `sdk-proxy.sns.id` | Forward resolution: domain → address, IBAN → Solana via verified-iban.sol |
| Google Fonts | `fonts.googleapis.com` | Outfit (body), JetBrains Mono (code) |

**No framework.** No React, no Vue, no build step. Everything is vanilla JS in a single HTML file. This is intentional — Roman wants the code to be auditable by bank compliance officers who can read plain JS.

---

## Wallet Integration

**Desktop:** Detects Phantom, Solflare, Backpack via `window.phantom.solana`, `window.solflare`, `window.backpack.solana`.

**Mobile:** Auto-detects wallet provider injected in webview. If not in a wallet browser, offers deeplinks to open in Phantom/Solflare.

**Verification:** `signMessage` with a timestamped message proving wallet ownership. Some mobile wallets don't support `signMessage` — the app gracefully falls back with a warning.

**State:** Stored in the global `walletState` object: `{ connected, publicKey, walletName, verified, provider }`.

---

## UI Features Added (2026-03-14 Session)

**Light/Dark Theme Toggle:** Light theme is the default. Moon/sun icon button in the header. All colors driven by ~50 CSS custom properties. Persisted in localStorage.

**Demo Highlight (Presentation Mode):** Clicking or focusing any form section (Steps 1-6, Reports) triggers a pulsing amber border (`demoGlow` animation). Only one section is highlighted at a time. CTA cards (Message Flow, Field Mapping, FAQ) get a brief amber flash on click. Purpose: helps observers follow the presenter's actions during live demos.

**Account Owner (CBPR+ Structured):** Step 4 in the form. Optional name + postal address fields. "Use Demo Name" button fills Felix Muster, Hugo street 12, 8050 Zürich, CH. Generates `<Ownr><Nm>` and optional `<PstlAdr>` with `<StrtNm>`, `<BldgNb>`, `<PstCd>`, `<TwnNm>`, `<Ctry>`. Used by camt.053, camt.054, BAI2, and the realtime simulator.

**BAI2 Report Type:** US bank statement format. Combines all currencies into one file. Amounts in cents. Record types: 01 file header, 02 group header, 03 account, 16 transaction, 88 continuation, 49/98/99 trailers. BAI type codes: 195/175 (credits), 495/475 (debits). Custom syntax highlighter in the viewer color-codes record types.

**Quick Date Filters:** "This month", "2026", "2025", "Last 30 days" buttons below the date range inputs.

**Navigation:** All pages have consistent headers: "Gbits.io" → links to gbits.io, "Solana ISO 20022 Message Gateway" → links to iso.gbits.io/index.html. 3-column CTA grid: Message Flow, Field Mapping, FAQ. Footer includes Field Mapping ↗ and FAQ ↗ links.

**pain.001 XML Viewer Fix:** `showPainXml()` now calls `showXmlModal()` (the proper token-based highlighter) instead of the old regex chain that was injecting `<span style>` into the raw XML.

**SNS Domain Lookup:** `.sol` domain reverse lookup on wallet connect. Primary API: `sns-api.bonfida.com/v2/user/domains/{address}` (returns domain names directly). Fallback: `sdk-proxy.sns.id/favourite-domain/{address}`. The old `sns-sdk-proxy.bonfida.workers.dev` URLs are deprecated — all SNS proxy calls now use `sdk-proxy.sns.id`.

**Open Graph / Twitter Card Meta Tags:** Added for social sharing. Image placeholder at `iso.gbits.io/images/og-image.png` (not yet created).

**GitHub Link:** Octocat icon button in the header linking to `github.com/gbits-io/isofix`.

---

## Known Issues and Gotchas

**File truncation:** The `index.html` is ~165KB. During editing sessions, the file repeatedly gets truncated near the end (inside `sendPainPayment()`). Always verify the file ends with `</script></body></html>` after any edit. The truncation happens at the same spot: `rend` (should be `renderPainTable();`).

**Cloudflare artifacts:** When saving the HTML from the live Cloudflare-served site, Cloudflare injects `email-decode.min.js` (returns 404 locally, blocks JS execution) and obfuscates email addresses with `__cf_email__` spans. Never use a re-download from `iso.gbits.io` as source — always work from the local canonical copy. The fix: `sed` to remove the script tag and restore `mailto:romanix@gbits.io`.

**SNS API migration:** The old Bonfida proxy at `sns-sdk-proxy.bonfida.workers.dev` is deprecated. Forward resolution uses `sdk-proxy.sns.id/resolve/{domain}`. Reverse lookup (address → domain names) uses `sns-api.bonfida.com/v2/user/domains/{address}`. The `/domains/{owner}` endpoint on the SDK proxy returns public keys of domain accounts (not names) — useless for display.

**Helius API key exposed:** The key is in client JS. The planned Cloudflare Worker proxy (`/rpc`) will fix this.

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
| **verified-iban.sol** | SNS domain Roman owns — used for IBAN→Solana resolution in pain.001 execution |

---

## How to Resume Work

1. **Upload `index.html`** (the local canonical copy, NOT a re-download from Cloudflare)
2. **Upload this document** (`ISOFIX_Project_Knowledge.md`) for context
3. **If working on the Worker:** also upload `ISOFIX_ServerSide_Plan.md`
4. **First thing after upload:** verify the HTML ends with `</script></body></html>` and contains no `cdn-cgi` strings
5. **If the file is truncated:** the last function is `sendPainPayment()` — it needs a closing `catch`, `}`, and the HTML closing tags
