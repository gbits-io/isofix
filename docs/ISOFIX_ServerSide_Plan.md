# ISOFIX Server-Side Implementation Plan

## Cloudflare Workers — Shared Backend for Gbits Pay, AlpenSign & Koivu

**Created:** 2026-03-11
**Context:** This document captures all decisions and technical details from the ISOFIX planning session so that work on the Cloudflare Worker backend can continue in a future session.

---

## 1. Why Cloudflare Workers

Roman wants a single server-side approach across multiple projects. Cloudflare Workers was chosen because:

- AlpenSign already needs a Worker for the swiyu E-ID integration
- Both AlpenSign and ISOFIX need to stop exposing the Helius API key in browser JS
- Gbits Pay (app.gbits.io) will also need swiyu E-ID verification
- Workers offer edge deployment, Durable Objects for stateful connections, KV for simple storage, and Secrets for API keys
- A single Worker project can serve all three apps via route-based handlers

---

## 2. Architecture Overview

```
                    ┌─────────────────────────────────────┐
                    │   Cloudflare Worker (api.gbits.io)   │
                    │                                       │
  AlpenSign ───────►│  /rpc          Helius RPC proxy       │◄─── Gbits Pay
  (app)             │  /swiyu/*      E-ID verification      │     (app)
                    │  /webhook      Helius webhook receiver │
  ISOFIX ──────────►│  /stream       SSE camt.054 push      │
  (browser)         │                                       │
                    └───────────────┬───────────────────────┘
                                    │
                          ┌─────────┴─────────┐
                          │                   │
                     Helius API          swiyu API
                     (RPC + webhooks)    (E-ID)
```

### Route Structure

| Route | Purpose | Used by |
|-------|---------|---------|
| `POST /rpc` | Proxy RPC calls to Helius (hides API key) | ISOFIX, AlpenSign, Gbits Pay |
| `POST /webhook/helius` | Receives Helius webhook POSTs for inbound payments | ISOFIX (server-side) |
| `/stream/camt054` | SSE endpoint — pushes real-time camt.054 to browsers | ISOFIX (browser) |
| `POST /swiyu/verify` | Initiates swiyu E-ID verification | AlpenSign, Gbits Pay |
| `GET /swiyu/callback` | Handles swiyu verification callback | AlpenSign, Gbits Pay |

---

## 3. Component Details

### 3.1 Helius RPC Proxy (`/rpc`)

**What it does:** Browser sends RPC request to Worker → Worker appends Helius API key → forwards to Helius → returns response to browser.

**Why:** The Helius API key (`cf479a6e-8fe8-4363-ab5b-8898913fbaff`) is currently exposed in client-side JS in both ISOFIX (`index.html` line ~588) and AlpenSign. This is the single most impactful change.

**Implementation notes:**
- Store Helius API key as a Worker Secret via `wrangler secret put HELIUS_API_KEY`
- Accept JSON-RPC body from browser, forward to `https://mainnet.helius-rpc.com/?api-key=${env.HELIUS_API_KEY}`
- Add CORS headers for `iso.gbits.io`, `app.gbits.io`, and AlpenSign origins
- Consider rate limiting per origin or IP

**Client-side migration:**
- In ISOFIX `index.html`: replace `const HELIUS_RPC = \`https://mainnet.helius-rpc.com/?api-key=${HELIUS_API_KEY}\`` with `const HELIUS_RPC = 'https://api.gbits.io/rpc'`
- Remove the `HELIUS_API_KEY` constant from client JS entirely
- Same change in AlpenSign

### 3.2 Helius Webhook Receiver (`/webhook/helius`)

**What it does:** Helius sends a POST when an SPL token transfer is detected on a monitored wallet → Worker parses the transaction → generates camt.054 XML → pushes to connected browsers via SSE.

**Helius webhook payload format:** Enhanced transaction format with `tokenTransfers[]` array containing `mint`, `fromUserAccount`, `toUserAccount`, `tokenAmount`, plus `signature`, `timestamp`, and `memo`.

**camt.054 generation logic:** Already exists client-side in `generateCamt054()` in ISOFIX `index.html` (lines ~1392-1465). This function needs to be ported to the Worker. It takes: `address`, `currency`, `entries[]`, `startDate`, `endDate`, `ntfctnId`, `iban`.

**Stablecoin → currency mapping** (also already in client code):

| Token | Mint Address | Currency |
|-------|-------------|----------|
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` | USD |
| USDT | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB` | USD |
| PYUSD | `2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo` | USD |
| EURC | `HzwqbKZw8HxMN6bF2yFZNrht3c2iXXzpKcFu7uBEDKtr` | EUR |
| EUROe | `2VhjJ9WxaGC3EZFwJG9BDUs9KxKCAjQY4vgd1qxgYWVg` | EUR |
| VCHF | `AhhdRu5YZdjVkKR3wbnUDaymVQL2ucjMQ63sZ3LFHsch` | CHF |

**Webhook verification:** Helius webhooks can be verified via a shared secret. Store as `HELIUS_WEBHOOK_SECRET` in Worker Secrets.

### 3.3 SSE Stream (`/stream/camt054`)

**What it does:** Browser opens a persistent SSE connection. When a webhook arrives and a camt.054 is generated, the Worker pushes it to all connected browsers.

**Statefulness challenge:** Workers are stateless by default. Two options:

**Option A — Durable Objects (recommended for production):**
- A single Durable Object instance holds all active SSE connections (via WebSockets upgraded from SSE)
- Webhook handler calls the Durable Object to broadcast
- True real-time push, proper architecture
- More complex to implement

**Option B — KV polling (recommended for hackathon demo):**
- Webhook writes latest camt.054 to KV with a timestamp key
- Browser polls `/stream/camt054?since={timestamp}` every 2-3 seconds
- Looks real-time enough for a demo
- Trivially simple to build

**Recommendation:** Start with Option B for the hackathon, migrate to Option A later.

### 3.4 swiyu E-ID Verification (`/swiyu/*`)

**Shared across:** AlpenSign and Gbits Pay (and potentially Koivu services later).

**Implementation:** Already discussed in previous AlpenSign sessions. The same Worker routes serve all apps — only the callback URL / origin differs.

**Per-app isolation:** For hackathon, share credentials. For production, use separate environment variables per app (`SWIYU_CLIENT_ID_ALPENSIGN`, `SWIYU_CLIENT_ID_GBITSPAY`, etc.).

---

## 4. Current State of the Frontend

### ISOFIX (`iso.gbits.io`)

The ISOFIX `index.html` already has:

- **"Realtime" tab** with a "Simulate Inbound Stablecoin Payment" button that generates a hardcoded camt.054 with randomized counterparty, stablecoin, amount, and timestamp
- **Notification list** showing incoming camt.054 reports with View, Download, Copy, Email buttons
- **Syntax-highlighted XML viewer** (token-based parser, properly handles all XML structures)
- **On-demand camt.053/054 generation** via Helius RPC (currently direct, needs migration to proxy)

**What needs to change when the Worker is ready:**
1. Replace `simulateInboundPayment()` with an SSE/polling connection to `/stream/camt054`
2. Replace direct Helius RPC URL with `/rpc` proxy
3. Remove `HELIUS_API_KEY` from client JS

### Flow Animation (`isofix_flow.html`)

The landing page flow animation already shows both flows with correct architecture. The "Webhook — planned" tab (currently dimmed) can be switched to active once the Worker is deployed.

---

## 5. Helius Webhook Setup

Roman needs to configure a webhook in the Helius dashboard:

- **Webhook URL:** `https://api.gbits.io/webhook/helius`
- **Webhook type:** Enhanced (parsed transaction data)
- **Transaction type:** TOKEN_TRANSFER (or equivalent filter)
- **Account addresses:** The wallet(s) to monitor for inbound stablecoin payments
- **Network:** Mainnet (or Devnet for testing)

---

## 6. TODO List

### Roman (account setup & configuration)

- [ ] **Choose a domain** for the Worker API (e.g., `api.gbits.io`) and configure DNS in Cloudflare
- [ ] **Install Wrangler CLI** if not already: `npm install -g wrangler` and authenticate with `wrangler login`
- [ ] **Create Cloudflare Worker project**: `wrangler init isofix-worker`
- [ ] **Store secrets** via Wrangler:
  - `wrangler secret put HELIUS_API_KEY` (value: `cf479a6e-...`)
  - `wrangler secret put HELIUS_WEBHOOK_SECRET` (value: from Helius dashboard)
- [ ] **Register Helius webhook** in the Helius dashboard pointing to `https://api.gbits.io/webhook/helius`, filtered for SPL token transfers on the target wallet(s)
- [ ] **Test webhook delivery** — send a small VCHF or USDC transfer to the monitored wallet and verify the POST arrives at the Worker
- [ ] **Configure CORS origins** — decide which origins are allowed (`iso.gbits.io`, `app.gbits.io`, AlpenSign domain)
- [ ] **Decide on KV vs Durable Objects** for the hackathon (recommendation: KV polling)
- [ ] **If using KV:** Create a KV namespace: `wrangler kv:namespace create ISOFIX_REALTIME`
- [ ] **Deploy and test** the Worker with `wrangler deploy`
- [ ] **Update DNS** for `iso.gbits.io` if needed so the main app can reach the Worker API

### Claude (implementation)

- [ ] **Scaffold the Cloudflare Worker** project with Hono router and route structure
- [ ] **Implement `/rpc` proxy** — forward JSON-RPC to Helius with API key injection, CORS headers
- [ ] **Implement `/webhook/helius`** — parse incoming webhook POST, validate signature, extract SPL token transfer fields
- [ ] **Port `generateCamt054()` to the Worker** — translate the existing client-side JS function to run server-side in the Worker
- [ ] **Implement real-time delivery** (KV polling for hackathon):
  - Webhook handler writes camt.054 XML + metadata to KV
  - `/stream/camt054?since={ts}` endpoint returns new notifications since timestamp
- [ ] **Update ISOFIX `index.html`** — replace `simulateInboundPayment()` with polling loop that hits `/stream/camt054`, replace `HELIUS_RPC` with proxy URL, remove API key from client code
- [ ] **Update `isofix_flow.html`** — switch "Webhook — planned" tab to active/live status
- [ ] **Add `/swiyu/*` routes** — placeholder or full implementation depending on swiyu API readiness
- [ ] **Write a simple health check endpoint** (`GET /health`) returning Worker status and version

### Both (testing & integration)

- [ ] **End-to-end test on devnet:** Roman sends a devnet stablecoin transfer → Helius webhook fires → Worker generates camt.054 → browser receives notification in real time
- [ ] **Verify camt.054 XML validity** — import a webhook-generated camt.054 into Bexio and confirm it parses correctly
- [ ] **Performance check** — confirm the RPC proxy doesn't add noticeable latency vs direct Helius calls
- [ ] **Security review** — ensure API key is not leaked in error responses, CORS is locked down, webhook signature is verified

---

## 7. File Reference

| File | Location | Description |
|------|----------|-------------|
| `index.html` | `iso.gbits.io` | Main ISOFIX app — has Realtime tab with simulate button, on-demand camt.053/054/semt.002 generation, pain.001 executor |
| `isofix_flow.html` | `iso.gbits.io` | Landing page flow animation — tabbed inbound (webhook planned / on-demand live) + outbound |
| `camt053_field_mapping.html` | `iso.gbits.io` | Field mapping reference: Solana SPL Token → camt.053 XML elements |

---

## 8. Technical Notes

**File truncation warning:** The ISOFIX `index.html` is ~117KB and has been repeatedly truncated during editing sessions (cuts off mid-line near the end of the `sendPainPayment` function). The canonical version is the one generated in this session. Always verify the file ends with `</script></body></html>` after any edit.

**Cloudflare artifacts:** When saving `index.html` from the live Cloudflare-served site, Cloudflare injects `email-decode.min.js` (causes 404 locally) and obfuscates email addresses. Always work from the local canonical copy, not a re-download from `iso.gbits.io`.

**Existing client-side functions to port server-side:**
- `generateCamt054()` at line ~1432 in `index.html` — the core camt.054 XML generator
- `STABLECOIN_CONFIG` at line ~591 — mint address → currency/label mapping
- `escXml()` and `trunc()` — helper functions for XML-safe string handling

**Hackathon target:** StableHacks 2026 on DoraHacks (the isochain project).
