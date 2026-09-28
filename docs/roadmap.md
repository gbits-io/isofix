# ISOFIX Roadmap

**Last updated:** 2026-09-28

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
| 2.7 | Squads multi-sig for pain.001 | For UI-mode pain.001 execution, create a Squads transaction proposal instead of a single-signer tx. Allows CFO + Treasurer approval before settlement |
| 2.8 | DNS-style SNS attributes | Add metadata to verified-iban.sol subdomains: token preference (USDC, EURC), legal entity name, verification source. Stored as SNS record data, queried at resolution time |

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
| 4.1 | API design | RESTful endpoints: `POST /api/v1/pain001` (accepts pain.001 XML, returns 202 + UETR), `GET /api/v1/reports/camt053?address={addr}&currency={ccy}&from={date}&to={date}`, `GET /api/v1/reports/camt054?address={addr}&since={ts}`, etc. |
| 4.2 | Authentication | API key per customer, stored in Worker KV or D1. Rate limiting per key |
| 4.3 | pain.002 status response | After pain.001 intake: return pain.002 with ACCP (accepted), ACSC (settled/finalized), or RJCT (simulation failed/dropped). Reference the Solana transaction in `<AcctSvcrRef>` (max. 35 characters, so use the same per-transfer reference as the camt statements; the full signature doesn't fit). Delivered via webhook POST to customer's registered callback URL |
| 4.4 | On-demand camt.053 generation | Port the full `fetchStablecoinTxns()` + `generateCamt053()` pipeline to the Worker. Return XML directly or as a download |
| 4.5 | On-demand camt.054 generation | Same as camt.053 but for notification format |
| 4.6 | Webhook subscription API | `POST /api/v1/webhooks` — let companies register a callback URL to receive camt.054 notifications and pain.002 status reports in real time (ISOFIX as a webhook relay: Helius → ISOFIX Worker → customer endpoint). Include `X-ISO-Signature` (HMAC-SHA256) header for verification |
| 4.7 | semt.002 via API | Port custody report generation. Useful for portfolio reporting tools |
| 4.8 | OpenAPI spec / documentation | Publish API docs so companies can integrate. Host at `api.gbits.io/docs` |
| 4.9 | Usage dashboard | Simple admin page showing API usage per key, report counts, webhook delivery status |

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
| 5.21 | **Supplier wallet registry with four-eyes approval** | The pain.001 executor pays any SNS-resolved or pasted address, with no second person involved. Pay only wallets that a second approver has activated (idea from SAP Digital Currency Hub). Spec: *TODO 5.21* section below |

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

## TODO 5.21 — Supplier Wallet Registry with Four-Eyes Approval

> **Status:** planned 2026-09-28, not started.
> The pain.001 executor should pay only supplier wallets that a second person has approved.
> Idea borrowed from SAP Digital Currency Hub.

### Problem

Today one person can send a payment to any address, and nothing checks that the address belongs to the supplier:

- `resolveIbanToSolana()` turns the creditor IBAN into an address through the `<iban>.verified-iban` SNS lookup, via a third-party HTTP proxy (`sdk-proxy.sns.id`).
- `painManualAddr()` accepts any pasted string of 32 or more characters as "resolved".
- `sendPainPayment()` pays `p.solanaAddress` without further checks.

A tampered pain.001 file, a compromised proxy, or one person pasting a wrong or fraudulent address sends the money elsewhere. "Our payment details have changed" fraud is one of the most common B2B payment frauds, and an on-chain payment can't be recalled.

### What SAP does

- One role enters a supplier's wallet address; a separate reviewer role must activate it. SAP forbids one user holding both roles.
- Payments go only to addresses assigned to a business partner.
- SAP advises validating a new address with a very small test payment.

### Target behaviour

- **Pay only active registry entries.** `sendPainPayment()` refuses unless the (IBAN, wallet, token) combination matches an active entry. SNS results and pasted addresses become *proposals*; they are never payable directly.
- **Four-eyes activation.** An entry becomes active only when a second approver, different from the proposer, approves it.
- **Changes need fresh approval.** A new wallet for a known IBAN creates a pending version. Payments to the new wallet stay blocked until it's approved, and the old wallet remains active until someone revokes it.
- **Fast to block, slow to add.** Any single approver can revoke an entry, effective immediately.
- **Proof of control before the first payment.** At least one of these:
  - the supplier signs a challenge message with the wallet;
  - the supplier confirms receipt of a small test transfer.

  The approver also records how the request was confirmed outside the app, for example by calling the supplier back on a known number.
- **Audit log** of proposals, approvals, revocations and proofs, exportable with their signatures.
- **UI:** each payment row shows the registry status (Approved / Pending approval / Not registered / Wallet changed), plus a registry view.

### Design constraint: no backend

isofix has no server and no user accounts, so "a different person" can't be enforced with server-side roles. Proposal: make approvals cryptographic.

- **Approvers are wallets** on a company approver list. Proposing and approving are both `signMessage` signatures over a canonical entry payload: IBAN, wallet, token mint, supplier name, version and timestamp.
- **Checked at payment time.** Before paying, the executor verifies both signatures and checks that the two signers are different and both on the approver list.
- **The approver list needs a root of trust.** For example, the paying (treasury) wallet signs it once at setup, and changing it later needs two existing approvers.
- **Storage can be untrusted.** Because every entry is signed, localStorage plus an export/import JSON file is enough to start, and the Worker from Milestone 1 can take over later. Editing a stored entry breaks its signature and blocks payment.
- **Signatures must be verified cryptographically** (Ed25519, available in browsers through WebCrypto). Today's `verifyWallet()` only checks that the wallet returned *something* and has a mobile bypass. Neither is acceptable here.

Alternative: wait for Milestone 1 and enforce proposer/approver roles on the server. The approval flow is simpler that way, but it needs user accounts and a server you have to trust.

### Acceptance criteria

- A pain.001 payment to an IBAN without an active registry entry can't be sent, including through a pasted address.
- The same approver can't both propose and approve an entry.
- A new wallet for a known IBAN is blocked until it's approved.
- Editing a stored entry by hand invalidates it.
- One person alone can't change the approver list.
- Revoking an entry blocks the next payment immediately.
- The audit log exports every event with its signatures.

### Open questions

- Should proof of control be mandatory, or configurable per company?
- Does an entry cover one token mint or a whole currency (for example USDC and PYUSD for USD)?
- Is the registry kept per paying wallet or per company, for companies with several treasury wallets?
- Should app.gbits.io share the same registry?

### Related

- **2.7 Squads multi-sig** adds four-eyes to each *payment*; this item adds four-eyes to the *wallet master data*. They complement each other.
- **2.8 SNS attributes:** SNS stays a source of suggestions for proposals, not the authority.
- **5.4 / 5.7 IBAN validation:** a prerequisite. Validate the IBAN before it can be proposed.
- **Sanctions screening** (also from the SAP comparison): screen the wallet when it's proposed, once screening exists.

---

## Timeline (Suggested)

```
  2026-Q1 (done)         Q2                    Q3                  Q4
  ─────────────────────────────────────────────────────────────────────
  ████ M1: Worker         ██ M2: Live          ████ M3: EVM        ██ M4: API
  ✓ StableHacks            realtime             multi-chain          REST API
    submitted              camt.054              Ethereum/Base
                           + Squads
                           + SNS attrs

  ───── Ongoing: M5 improvements and hardening ─────────────────────►
```

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-09-28 | Status reports for pain.001 use pain.002, not pacs.002 (corrected in 4.3, 4.6 and the 2026-03-26 entries) | pacs.002 is the bank-to-bank status report; the customer-facing report for a pain.001 is pain.002, which is what ERPs such as SAP import. pain.002 has no `<TxId>`, so the Solana transaction is referenced in `<AcctSvcrRef>` |
| 2026-09-28 | Plan supplier wallet registry with four-eyes approval (5.21) | Borrowed from SAP Digital Currency Hub: pay only wallets a second person has activated. Defends against changed-payment-details fraud, which irreversible on-chain payments can't recall. Approvals are two wallet signatures, so it works without a backend |
| 2026-03-26 | Add pain.002 status response for REST-mode pain.001 | When ERP POSTs pain.001 via API (no human in loop), the gateway must return a machine-readable status. pain.002 with ACCP/ACSC/RJCT codes maps directly to what ERPs expect. References the Solana transaction in `<AcctSvcrRef>` for audit trail |
| 2026-03-26 | Plan Squads multi-sig for pain.001 execution | Single-key signing is a non-starter for enterprise. Squads creates a transaction proposal requiring multiple approvers (e.g. CFO + Treasurer) before on-chain settlement |
| 2026-03-26 | DNS-style SNS attributes on verified-iban.sol | Expand each SNS subdomain record to carry metadata: token preference (USDC, EURC), legal entity name, verification source. Turns the registry into a financial discovery layer |
| 2026-03-26 | Webhook-first for pain.002 delivery | Webhooks beat WebSockets for ERP integration: stateless, retry-safe, compatible with SAP/NetSuite/Bexio. HMAC-signed headers for verification. WebSockets remain only for the browser UI |
| 2026-03-26 | RTGS framing for positioning | "Global RTGS at ~$0.001 per message, zero bank permission" — clearer positioning than "ISO 20022 bridge." Added to presentation and landing page |
| 2026-03-26 | Remove AlpenSign/swiyu from ISOFIX roadmap | These are separate projects. ISOFIX roadmap should focus on gateway features only |
| 2026-03-26 | Add stablehacks-presentation.html | 9-slide presentation deck covering problem, translation, architecture, and roadmap. Linked from stablehacks.html and gbits.io landing page |
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
