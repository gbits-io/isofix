# ISOFIX Roadmap

**Last updated:** 2026-03-14

---

## Milestone 1 — Server-Side Foundation (Cloudflare Worker)

> Move from a fully client-side app to a proper backend that hides API keys,
> receives webhooks, and enables real-time features.

| # | Task | Detail |
|---|------|--------|
| 1.1 | Scaffold Cloudflare Worker | Hono router, wrangler config, route structure |
| 1.2 | Helius RPC proxy (`POST /rpc`) | Forwards JSON-RPC to Helius with API key injected from Worker Secret. CORS for allowed origins |
| 1.3 | Remove API key from client JS | Replace `HELIUS_RPC` URL in `index.html` with `/rpc` proxy endpoint. Delete `HELIUS_API_KEY` constant |
| 1.4 | Helius webhook receiver (`POST /webhook/helius`) | Parse enhanced transaction payload, validate webhook signature, extract SPL token transfer fields |
| 1.5 | Port `generateCamt054()` to Worker | Translate the client-side camt.054 generator to run server-side. Include stablecoin config and XML helpers |
| 1.6 | Real-time delivery mechanism | **Hackathon:** KV polling — webhook writes to KV, browser polls `/stream/camt054?since={ts}` every 2-3s. **Later:** Durable Objects with SSE for true push |
| 1.7 | Health check endpoint (`GET /health`) | Return Worker status, version, uptime |
| 1.8 | Deploy and configure DNS | Set up `api.gbits.io` (or chosen subdomain) in Cloudflare |

**Depends on:** Roman registering Helius webhook, storing secrets via `wrangler secret put`
**Detailed plan:** See `ISOFIX_ServerSide_Plan.md`

---

## Milestone 2 — Connect Realtime Tab to Server-Side

> Replace the simulation button with a live connection to the Worker,
> so inbound stablecoin payments trigger real camt.054 notifications in the browser.

| # | Task | Detail |
|---|------|--------|
| 2.1 | Add polling client to `index.html` | On tab activation, start polling `/stream/camt054?since={ts}`. Parse response, push to `realtimeNotifications[]`, call `renderRealtimeList()` |
| 2.2 | Keep "Simulate" button as fallback | Useful for demos when no real payments are flowing. Add a visual indicator distinguishing simulated vs. live notifications |
| 2.3 | Connection status indicator | Show "Connected · listening" / "Disconnected · retrying" in the Realtime tab header |
| 2.4 | Wallet address registration | Browser tells the Worker which wallet address to monitor — Worker filters webhook events accordingly |
| 2.5 | End-to-end test on devnet | Send a devnet stablecoin transfer → Helius webhook fires → Worker generates camt.054 → browser receives notification |
| 2.6 | Test camt.054 import in Bexio | Verify that a webhook-generated camt.054 imports correctly into Bexio as a debit/credit notification |

**Depends on:** Milestone 1 deployed and webhook registered

---

## Milestone 3 — Multi-Chain Support (Ethereum, Base)

> Extend ISOFIX beyond Solana to support EVM-based stablecoin payments,
> starting with Ethereum mainnet and Base L2.

| # | Task | Detail |
|---|------|--------|
| 3.1 | Research EVM RPC providers | Evaluate Infura, Alchemy, QuickNode, or Tenderly for transaction indexing and webhooks. Needs: parsed token transfer events, webhook on ERC-20 Transfer, historical tx query |
| 3.2 | Define EVM stablecoin config | Map ERC-20 contract addresses to currencies: USDC, USDT, EURC on Ethereum and Base. Include decimals (6 for USDC/USDT, 6 for EURC) |
| 3.3 | Add EVM RPC proxy route to Worker | `POST /rpc/evm` — same pattern as Helius proxy but forwarding to Infura/Alchemy |
| 3.4 | Add EVM webhook receiver | `POST /webhook/evm` — parse ERC-20 Transfer events, map to camt.054 |
| 3.5 | Extend `generateCamt053/054` for EVM | Add EVM-specific fields: use chain-specific BIC placeholder (e.g., `ETHECHZZXXX`, `BASECHZZXXX`), map tx hash as `AcctSvcrRef`, block timestamp as `BookgDt` |
| 3.6 | UI: chain selector in index.html | Add a chain toggle (Solana / Ethereum / Base) in the Generate Reports tab. Show chain badge on report cards |
| 3.7 | pain.001 execution on EVM | Extend pain.001 executor to send ERC-20 transfers via MetaMask / WalletConnect. IBAN→address resolution needs an EVM equivalent of SNS (possibly ENS subdomains or a custom registry) |
| 3.8 | Unified report output | A single camt.053 that includes entries from multiple chains, distinguished by `BkTxCd` or `AddtlNtryInf` |

**Depends on:** Milestones 1-2 stable. Roman choosing an EVM RPC provider.

---

## Milestone 4 — ISOFIX REST API

> Expose ISOFIX as a service: companies connect their wallet addresses and
> fetch ISO 20022 reports programmatically, no browser required.

| # | Task | Detail |
|---|------|--------|
| 4.1 | API design | RESTful endpoints: `GET /api/v1/reports/camt053?address={addr}&currency={ccy}&from={date}&to={date}`, `GET /api/v1/reports/camt054?address={addr}&since={ts}`, etc. |
| 4.2 | Authentication | API key per customer, stored in Worker KV or D1. Rate limiting per key |
| 4.3 | On-demand camt.053 generation | Port the full `fetchStablecoinTxns()` + `generateCamt053()` pipeline to the Worker. Return XML directly or as a download |
| 4.4 | On-demand camt.054 generation | Same as camt.053 but for notification format |
| 4.5 | Webhook subscription API | `POST /api/v1/webhooks` — let companies register a callback URL to receive camt.054 notifications in real time (ISOFIX as a webhook relay: Helius → ISOFIX Worker → customer endpoint) |
| 4.6 | semt.002 via API | Port custody report generation. Useful for portfolio reporting tools |
| 4.7 | OpenAPI spec / documentation | Publish API docs so companies can integrate. Host at `api.gbits.io/docs` |
| 4.8 | Usage dashboard | Simple admin page showing API usage per key, report counts, webhook delivery status |

**Depends on:** Milestone 1, and a decision on pricing/access model

---

## Milestone 5 — Improvements and Hardening

> Things Claude thinks should be fixed, improved, or added — based on reviewing the codebase.

### Security

| # | Task | Why |
|---|------|-----|
| 5.1 | **Remove Helius API key from client JS** | Currently exposed at line ~597. Anyone can extract it from the browser. This is the single most urgent fix — covered in Milestone 1.3 but flagged here for emphasis |
| 5.2 | **Webhook signature verification** | The Helius webhook endpoint must verify the `x-helius-signature` header to prevent spoofed notifications |
| 5.3 | **CORS lockdown** | The Worker proxy must only allow requests from known origins (`iso.gbits.io`, `app.gbits.io`, AlpenSign) |
| 5.4 | **Input validation on IBAN** | Currently accepts any string. Add IBAN checksum validation (mod-97) before generating XML to catch typos |

### Reliability

| # | Task | Why |
|---|------|-----|
| 5.5 | **Fix recurring file truncation** | The `index.html` (~130KB) repeatedly truncates during editing. Consider splitting JS into a separate `app.js` file to keep file sizes manageable |
| 5.6 | **Eliminate Cloudflare email-decode artifact** | The source file keeps re-introducing `email-decode.min.js` when saved from the live site. Establish a clean local canonical copy as the single source of truth |
| 5.7 | **IBAN validation in pain.001 parser** | The pain.001 parser extracts IBANs but doesn't validate them before attempting SNS resolution. Invalid IBANs waste resolution calls |
| 5.8 | **Error handling for Helius rate limits** | `fetchStablecoinTxns()` has a basic 200ms courtesy delay but no retry logic. Add exponential backoff for 429 responses |
| 5.9 | **Graceful handling when Helius is down** | Currently shows a generic error. Add specific messaging and a retry button |

### User Experience

| # | Task | Why |
|---|------|-----|
| 5.10 | **Devnet/mainnet toggle** | Add a network selector so users can test with devnet tokens without risking real funds. AlpenSign already has this toggle |
| 5.11 | **Progress indicator for transaction fetching** | Large wallets with hundreds of transactions can take 30+ seconds. Show a progress bar or counter ("Fetching page 3/7...") instead of just a spinner |
| 5.12 | **Persist generated reports across tab switches** | Reports disappear if the user switches tabs and comes back. Store in a JS variable (already done for `allReports`) but the re-render is lost. Ensure `renderReports()` is called on tab switch |
| 5.13 | **QR code: add amount and SPL token parameters** | The current `solana:{address}` URI could include `?amount=100&spl-token={mint}` so the sender's wallet pre-fills the stablecoin and amount. Requires upgrading the QR encoder to handle longer URIs |
| 5.14 | ~~**Dark/light theme toggle**~~ | ✅ DONE (2026-03-14). Light is default. CSS custom properties for all colors. Toggle in header. Persisted in localStorage |
| 5.15 | **Keyboard shortcuts** | Escape already closes the XML modal. Add more: `Ctrl+G` to generate, `Ctrl+1/2/3` to switch tabs |

### Code Quality

| # | Task | Why |
|---|------|-----|
| 5.16 | **Split into separate files** | The single 130KB HTML file is hard to maintain. Split into `index.html`, `app.js`, `styles.css`. Can still deploy as static files on Cloudflare Pages |
| 5.17 | **Add accessibility attributes** | Zero `aria-*` or `role=` attributes in the current code. Add labels to buttons, announce notifications to screen readers, ensure keyboard navigation works |
| 5.18 | **XML schema validation** | Validate generated camt.053/054 against the official XSD before download. Catch field length violations, missing required elements |
| 5.19 | **Automated testing** | No tests exist. Add at least: unit tests for `generateCamt053()`, `generateCamt054()`, `escXml()`, `trunc()`; integration test for pain.001 parsing |
| 5.20 | **Replace built-in QR encoder** | The minimal Reed-Solomon QR generator works but is limited to version 6. Swap in `qrcode-generator` library for robustness and higher data capacity |

---

## Timeline (Suggested)

```
  2026-Q1 (now)          Q2                    Q3                  Q4
  ─────────────────────────────────────────────────────────────────────
  ████ M1: Worker         ██ M2: Live          ████ M3: EVM        ██ M4: API
  █ StableHacks            realtime             multi-chain          REST API
    hackathon              camt.054              Ethereum/Base

  ───── Ongoing: M5 improvements and hardening ─────────────────────►
```

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-14 | Add BAI2 report type | Broadens appeal beyond Swiss/European market. US companies use BAI2 for QuickBooks, NetSuite, Oracle, SAP |
| 2026-03-14 | Add structured account owner (CBPR+) | Makes camt.053/054 output look professional. Includes PstlAdr with StrtNm/BldgNb/PstCd/TwnNm/Ctry |
| 2026-03-14 | SNS API migration to sns-api.bonfida.com | Old proxy at sns-sdk-proxy.bonfida.workers.dev deprecated. SDK proxy moved to sdk-proxy.sns.id. Reverse lookup uses SNS API v2 which returns domain names directly |
| 2026-03-14 | Demo highlight feature for presentations | Pulsing amber border follows user interaction through form sections. Helps observers during live demos |
| 2026-03-14 | FAQ page (field-mapping-faq.html) | 16 questions covering ISO 20022 mapping decisions (truncation, BIC, balances, QR references, etc.) |
| 2026-03-14 | Internal links open in same tab | Message Flow, Field Mapping, FAQ no longer open new browser tabs |
| 2026-03-14 | Light theme as default | More professional for presentations and hackathon judges |
| 2026-03-11 | Use Cloudflare Workers (not Netlify Functions) | Shared across ISOFIX, AlpenSign, Gbits Pay. Durable Objects for stateful SSE. Edge deployment |
| 2026-03-11 | KV polling for hackathon, Durable Objects later | KV polling is trivially simple for a demo. Migrate to DO for production real-time |
| 2026-03-11 | Keep vanilla JS, no framework | Auditability by bank compliance officers. No build step. Single-file deployment |
| 2026-03-11 | Solana-first, EVM later | StableHacks focus is Solana. EVM support is Milestone 3 |
| 2026-03-11 | `solana:` URI for QR codes | Standard Solana Pay protocol. Wallet apps (Phantom, Solflare) recognize it natively |
