# ISOFIX EVM Port — Implementation Plan

Porting the ISOFIX Solana-to-ISO-20022 gateway ([`public/index.html`](../public/index.html)) to Ethereum and EVM-compatible chains.

**Companion to, not replacement of, the Solana gateway.** The Solana gateway is the reference implementation and remains untouched; the EVM port is a parallel page, [`public/index-evm.html`](../public/index-evm.html), sharing XML namespaces, UI, and most of the code verbatim.

---

## 1. Scope & non-goals

**In scope:**
- All eight features of the Solana gateway, re-expressed for Ethereum:
  1. Wallet connect + ownership verification
  2. Reverse domain lookup
  3. Historical stablecoin transaction fetch (ISO 20022 camt.053 / camt.054 / BAI2)
  4. Token-balance snapshot (ISO 20022 semt.002 custody report)
  5. Real-time inbound-payment simulation (camt.054)
  6. pain.001 upload → IBAN resolution → stablecoin selection → sign + send
  7. Report list UI (download / copy / email / view)
  8. Theme toggle, tab navigation, and all chain-agnostic chrome
- Mainnet (read-only for real balances/transactions) **and** Sepolia (read + write, using the `demo-evm` mock tokens).
- Zero-key operation is possible; optional Etherscan key improves speed.

**Non-goals:**
- Modifying [`public/index.html`](../public/index.html) or any file the Solana gateway depends on.
- L2 support (Base, Arbitrum, Polygon, Optimism). The network picker is architected to allow L2 additions, but this plan targets Ethereum mainnet + Sepolia only.
- WalletConnect v2 integration. MetaMask (desktop extension + mobile deeplink) is the only supported wallet in v1.
- Replacing the ACTUS classification demo — that already exists as [`public/demo-evm.html`](../public/demo-evm.html).

---

## 2. Design decisions

### 2.1 Transaction-history data source

Unlike Solana's Helius REST API, Ethereum has no canonical RPC call that returns "all ERC-20 transfers for an address." The plan uses a **two-tier strategy**:

| Tier | Source | Requires | Speed | Trigger |
|------|--------|----------|-------|---------|
| Primary | Etherscan API (`action=tokentx`) | Free API key (user-provided) | Fast (~1 s for a 30-day window) | Set once via settings drawer, stored in `localStorage` |
| Fallback | Chunked `eth_getLogs` against a public RPC | None | Slower (~30–60 s for 90 days) | Used automatically when no key is set |

The response is normalized to the same internal shape the existing code already consumes (`{signature, timestamp, tokenTransfers:[{mint, tokenAmount, fromUserAccount, toUserAccount}]}`), so the camt.053 / camt.054 / BAI2 pipeline does not change.

**Etherscan free tier:** 5 req/s, 100k req/day, no card required, 30-second signup at [etherscan.io/apis](https://etherscan.io/apis). Sepolia uses the separate `api-sepolia.etherscan.io` endpoint with the same key.

**Rationale:** Most users will paste a free Etherscan key once and get instant responses. The zero-key fallback keeps the gateway fully functional for anyone who doesn't want another credential, at the cost of slower scans. Alchemy / Infura support is a one-line config swap for users who have those keys.

### 2.2 Chain scope

Two chains, switched via a network picker in the header:

| Network           | Chain ID   | RPC (public)                                     | Explorer                          | Etherscan base                            | Use case                                      |
|-------------------|-----------|--------------------------------------------------|-----------------------------------|-------------------------------------------|-----------------------------------------------|
| Ethereum mainnet  | 1         | `https://ethereum-rpc.publicnode.com`            | `https://etherscan.io`            | `https://api.etherscan.io/api`            | Real data. Reads only; sends disabled (real gas) |
| Ethereum Sepolia  | 11155111  | `https://ethereum-sepolia-rpc.publicnode.com`    | `https://sepolia.etherscan.io`    | `https://api-sepolia.etherscan.io/api`    | Demo / testing. Full read + send flow        |

The picker persists in `localStorage`. When MetaMask is connected, the picker reflects MetaMask's current chain; switching the picker calls `wallet_switchEthereumChain`.

**Send path on mainnet** is deliberately disabled with a tooltip pointing users to Sepolia for the full end-to-end send demo. This avoids accidentally burning real ETH and keeps the gateway "safe by default."

### 2.3 Stablecoin list

Ethereum mainnet has a richer stablecoin ecosystem than Solana. The v1 list matches the existing 6-slot pattern; **Frankencoin (ZCHF) replaces VCHF** as the CHF representative (VCHF has no Ethereum deployment).

| Ticker   | Network  | Contract address                             | Decimals | Currency | Notes                                          |
|----------|----------|----------------------------------------------|----------|----------|------------------------------------------------|
| USDC     | Mainnet  | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 6        | USD      | Circle's canonical USDC                        |
| USDT     | Mainnet  | `0xdAC17F958D2ee523a2206206994597C13D831ec7` | 6        | USD      | Tether                                         |
| DAI      | Mainnet  | `0x6B175474E89094C44Da98b954EedeAC495271d0F` | 18       | USD      | MakerDAO's DAI                                 |
| EURC     | Mainnet  | `0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c` | 6        | EUR      | Circle's EURC on Ethereum                      |
| PYUSD    | Mainnet  | `0x6c3ea9036406852006290770BEdFcAbA0e23A0e8` | 6        | USD      | PayPal USD                                     |
| **ZCHF** | Mainnet  | `0xB58E61C3098d85632Df34EecfB899A1Ed80921cB` | 18       | CHF      | **Frankencoin** — decentralized CHF stablecoin |

> **Verify at implementation time.** Contract addresses must be checked against Etherscan before the page ships. Frankencoin has had governance-driven redeployments in the past; the canonical address should be confirmed from [frankencoin.com](https://frankencoin.com) or the official docs.

**Sepolia list** is read from [`demo-evm/mock-tokens.json`](../demo-evm/mock-tokens.json) after running [`public/demo-evm-deploy.html`](../public/demo-evm-deploy.html). If that file is absent, the Sepolia network displays an empty state directing the user to deploy mocks first.

**Frankencoin specifics worth noting:**
- 18 decimals (unlike most other stablecoins which use 6), so `balanceOf()` and `amount * 10^decimals` must respect per-token decimals rather than assuming 6.
- The token is a non-custodial collateralized stablecoin — mentioning this in the UI ("ZCHF — decentralized CHF collateralized stablecoin") gives the demo audience something distinctive to point at.

### 2.4 Memo / reference on-chain

ERC-20 `transfer(address,uint256)` has no memo slot. Three layers:

**Layer 1 (v1):** pain.001 memo / `EndToEndId` is stored in the gateway's in-page audit record and displayed in the UI, but **not** persisted on-chain. A warning badge explains this in the pain.001 tab.

**Layer 2 (Phase 4, part of this plan):** Deploy [`ISOFIXMemo.sol`](../contracts-evm/ISOFIXMemo.sol) — an event-only registry:

```solidity
contract ISOFIXMemo {
    event MemoRecorded(
        address indexed payer,
        address indexed token,
        bytes32 indexed endToEndId,
        uint256 amount,
        string  memo
    );

    function record(
        address   token,
        bytes32   endToEndId,
        uint256   amount,
        string calldata memo
    ) external {
        emit MemoRecorded(msg.sender, token, endToEndId, amount, memo);
    }
}
```

Send flow becomes two transactions per payment (`transfer` + `record`). MetaMask batches the signing prompts cleanly. A downstream camt.053 consumer can re-derive remittance info by querying `MemoRecorded` events filtered by `endToEndId`.

Registry deployed once per chain (mainnet + Sepolia) via the same in-browser deploy pattern used for [`public/demo-evm-deploy.html`](../public/demo-evm-deploy.html). Addresses committed to [`contracts-evm/deployments.json`](../contracts-evm/deployments.json).

**Rationale for not using `transferWithMemo` wrapper contracts:** would require the token itself (or a router) to be memo-aware, ruling out standard ERC-20s. The registry-event pattern keeps the token flow untouched.

### 2.5 Pain.001 IBAN → wallet-address resolution

Solana uses the SNS `.verified-iban` TLD to resolve IBANs to wallet addresses. ENS has no equivalent registrar today. **v1 behavior:**

- Each uploaded pain.001 payment row gets an editable `0x…` address field.
- The resolver column shows `manual` by default (instead of Solana's `resolved` / `pending` / `failed`).
- A tooltip explains: "ENS → IBAN mapping has no canonical standard. Enter the recipient's 0x address manually."
- Once a valid 40-hex-char address is entered, the row is marked resolved and `Send` is enabled.

A future ENS text-record scheme (e.g. `iban.<name>.eth` resolves to `0x…`) is noted as an enhancement but out of scope for v1.

### 2.6 ENS reverse lookup

Solana's SNS lookup goes via the Bonfida SNS API. The EVM equivalent is much simpler:

```js
const name = await provider.lookupAddress(address);   // e.g. "vitalik.eth"
```

This works out-of-the-box against mainnet with zero configuration (ethers does its own name-resolution under the hood, making multicall RPC calls). On Sepolia, ENS resolution is rare; we render "No .eth domain" as the default.

### 2.7 Wallet connection

- **Desktop:** `window.ethereum` detection (MetaMask, Rabby, Brave Wallet — all expose the same EIP-1193 provider).
- **Mobile:** deeplink to `https://metamask.app.link/dapp/<url>` when `window.ethereum` is absent and user agent matches mobile.
- **Sign-to-verify:** `personal_sign` with message `"Gbits.io ISOFIX EVM Gateway\n\nI verify ownership of this Ethereum address for ISO 20022 statement generation.\n\nTimestamp: <ISO>"`.
- **Disconnect:** ethers / EIP-1193 has no programmatic disconnect. The gateway clears its in-page state; the user disconnects at the wallet level if desired.
- **Chain-change handling:** listen to `chainChanged` and `accountsChanged`, reload the page (same behavior as the ACTUS demo).

---

## 3. XML / ISO 20022 field changes

Identical XML shape and namespaces; only chain-identification fields swap:

| Field                                | Solana (mainnet)                                 | EVM (mainnet)                                      | EVM (Sepolia)                                     |
|--------------------------------------|--------------------------------------------------|----------------------------------------------------|---------------------------------------------------|
| `BkToCstmrStmt/../Stmt/../Svcr/BICFI`| `SOLNCHZZXXX`                                    | `ETHCHZZXXX`                                       | `ETHSCHZZXXX` *(or same as mainnet, see note)*    |
| `AcctOwnr/../SchmeNm/Prtry`          | `SOLANA_WALLET`                                  | `EVM_WALLET`                                       | `EVM_WALLET`                                      |
| `AcctSvcr/Id/Nm`                     | `Solana Blockchain (Self-Custody)`               | `Ethereum (Self-Custody, Mainnet)`                 | `Ethereum (Self-Custody, Sepolia Testnet)`        |
| `SfkpgAcct/Tp/Prtry`                 | `SOLANA_WALLET`                                  | `EVM_WALLET`                                       | `EVM_WALLET`                                      |
| `BlckChainAdrOrWllt/Ntwk/Cd`         | `SOLANA`                                         | `ETHEREUM`                                         | `ETHEREUM`                                        |
| `FinInstrmId/OthrId/Id`              | SPL mint address (base58)                        | ERC-20 contract address (0x-hex)                   | ERC-20 contract address (0x-hex)                  |
| `FinInstrmId/OthrId/Desc`            | `SPL Token on Solana`                            | `ERC-20 Token on Ethereum Mainnet`                 | `ERC-20 Token on Ethereum Sepolia`                |
| `SfkpgPlc/LEI`                       | `SOLANA-MAINNET-BETA`                            | `ETHEREUM-MAINNET`                                 | `ETHEREUM-SEPOLIA`                                |
| `AddtlNtryInf` (camt.054 real-time)  | `Solana <ticker> via SPL Token — Helius Webhook` | `Ethereum <ticker> via ERC-20 — Etherscan API`     | `Ethereum <ticker> via ERC-20 — Sepolia`          |
| Remittance `Ustrd`                   | `SOL-<TICKER> <signature>`                       | `ETH-<TICKER> <txHash>`                            | `ETH-<TICKER> <txHash>`                           |

> **Pseudo-BIC note:** The Solana gateway uses `SOLNCHZZXXX` as a placeholder BIC (8 chars + XXX branch). The EVM port uses the same pattern with `ETH` prefix. These are not registered with SWIFT; they're stable identifiers for the gateway's own output. A future version may replace them with the gateway operator's real BIC.

---

## 4. File layout

```
public/
  index.html               ← UNCHANGED — Solana gateway
  index-evm.html           ← NEW — this plan
  demo.html                ← UNCHANGED — Solana ACTUS demo
  demo-evm.html            ← already shipped — EVM ACTUS demo
  demo-evm-deploy.html     ← already shipped — EVM mock-token deploy
  index-evm-deploy-memo.html  ← NEW — one-off deploy page for ISOFIXMemo.sol (Phase 4)
contracts-evm/
  ISOFIXMemo.sol           ← NEW — event-only memo registry
  MockRWAToken.sol         ← already shipped (under demo-evm/) — unchanged
  deployments.json         ← NEW — { mainnet: {memo: "0x..."}, sepolia: {memo: "0x..."} }
docs/
  ISOFIX_EVM_Port_Plan.md  ← this document
```

Nothing in `demo/`, `demo-evm/`, `scripts/`, or `netlify/` needs to change for this port. The existing shared NAV service, mock token deployer, and Solana demo remain untouched.

---

## 5. Phasing

Four phases, each independently shippable and independently useful.

### Phase 1 — Read-only gateway on mainnet

**Goal:** `index-evm.html` produces correct camt.053 / camt.054 / semt.002 / BAI2 from real Ethereum mainnet data for a connected wallet.

**Scope:**
- Clone `index.html` → `index-evm.html`.
- Swap wallet layer (MetaMask + ENS + `personal_sign`).
- Implement `fetchStablecoinTxns` with Etherscan API primary + chunked `eth_getLogs` fallback.
- Implement `fetchTokenBalances` via iteration over `STABLECOIN_CONFIG` + `balanceOf()`.
- Swap all chain-identification XML fields per the table in §3.
- Add settings drawer for Etherscan API key (localStorage-backed).
- Disable pain.001 `Send` button with a tooltip: "Available on Sepolia in Phase 2."
- Disable the real-time tab's simulated wallet-pay path, or leave it as pure UI simulation (no chain writes needed).

**Out of scope for Phase 1:**
- Network picker (mainnet is the only choice).
- pain.001 send flow.

**Verification:**
1. Connect MetaMask on mainnet → wallet badge shows ENS name (if set) and short address.
2. Paste an Etherscan API key → settings drawer confirms "key saved."
3. Pick a 30-day date range → click Generate → camt.053 XML for USD / EUR / CHF currency groups appears in the report list.
4. Without an Etherscan key → same flow succeeds, progress bar advances through `eth_getLogs` chunks, takes longer but produces the same XML.
5. `semt.002.001.11` path → queries the 6 token `balanceOf` calls, produces a custody report with all non-zero balances.
6. All generated XML has `<Ntwk><Cd>ETHEREUM</Cd></Ntwk>`, `ETHEREUM-MAINNET` safekeeping LEI, and `ETHCHZZXXX` BIC.

### Phase 2 — Sepolia support + pain.001 send (without memo)

**Goal:** Network picker; full send path on Sepolia.

**Scope:**
- Add network-picker dropdown to header. Persists to `localStorage`.
- On switch, calls `wallet_switchEthereumChain` if MetaMask is on wrong chain.
- Populate `STABLECOIN_CONFIG_SEPOLIA` from [`demo-evm/mock-tokens.json`](../demo-evm/mock-tokens.json). Graceful empty-state if file missing.
- pain.001 tab:
  - Each row has an editable 0x address input (replaces Solana's SNS-resolver display).
  - `Send` button wired to ethers.js `Contract(token, ERC20_ABI, signer).transfer(to, amountUnits)`.
  - On mainnet: button disabled with "Switch to Sepolia to send."
  - On Sepolia: button enabled when row has a valid 0x address.
  - Explorer link goes to Etherscan (correct sub-domain per chain).
- XML chain fields respect current network (Sepolia LEI when on Sepolia).

**Verification:**
1. Deploy mock tokens via `demo-evm-deploy.html` first (prerequisite).
2. Switch gateway to Sepolia → balance snapshot shows MOCK-USDC / etc. holdings.
3. Upload a pain.001 XML with 3 payments → enter 3 x 0x addresses manually → click Send on each → each transaction appears in Etherscan (Sepolia) and recipient `balanceOf()` increases.
4. Switch back to mainnet → Send buttons disable, tooltip explains why.

### Phase 3 — `eth_getLogs` polish

**Goal:** Make the zero-key fallback production-acceptable, not just functional.

**Scope:**
- Progress UI: "Scanning blocks 18,500,000 → 18,600,000 (token 3/6: DAI)…"
- Exponential backoff + retry on RPC rate-limit errors.
- Configurable chunk size (default 10,000 blocks, overridable via URL param for debugging).
- Cache scan results per (wallet, token, dateRange) in `localStorage` — re-running an identical query is instant on the second try.
- Honest time estimate before scan starts ("~45 seconds for a 90-day window over 6 tokens on a public RPC — consider adding an Etherscan key").

**Verification:**
1. Without key, 90-day scan on a wallet with a handful of transfers completes without timeouts.
2. Progress bar is smooth, not jumpy.
3. Re-running the same query within the session returns instantly from cache.
4. Killing the tab mid-scan and restarting resumes from cache (no duplicate network work).

### Phase 4 — `ISOFIXMemo` registry

**Goal:** pain.001 memos persisted on-chain.

**Scope:**
- `contracts-evm/ISOFIXMemo.sol` written per §2.4.
- `public/index-evm-deploy-memo.html` — one-off deploy page (same pattern as `demo-evm-deploy.html`). User deploys once per chain.
- Deployment results written to `contracts-evm/deployments.json`:
  ```json
  { "mainnet": { "isofix_memo": "0x…" }, "sepolia": { "isofix_memo": "0x…" } }
  ```
- Send flow in `index-evm.html` updated:
  - If `deployments.json` has an entry for the current chain: after `transfer()` succeeds, send a second tx calling `ISOFIXMemo.record(token, endToEndIdBytes32, amount, memo)`.
  - If not deployed on current chain: fall back to Phase 2 behavior (no on-chain memo), show a "deploy registry" info banner.
- `viewXml` for camt.053 entries with registry-recorded memos shows a "verified on-chain" badge and an explorer link to the memo tx.

**Verification:**
1. Deploy the registry on Sepolia via `index-evm-deploy-memo.html`.
2. Send a pain.001 payment → MetaMask prompts for 2 transactions (transfer + memo.record).
3. Query `MemoRecorded` events from Etherscan → memo text and endToEndId match the pain.001 input.
4. Generate camt.053 covering that tx → remittance field contains memo, report UI links back to the memo tx on the explorer.

---

## 6. Files to copy vs. change

| Source (Solana)                   | Target (EVM)                      | Change required                                       |
|-----------------------------------|-----------------------------------|-------------------------------------------------------|
| `public/index.html` :1-844 (CSS) | `public/index-evm.html` :1-844    | None — copy verbatim                                  |
| :845-864 (config constants)       | :845-900                          | `STABLECOIN_CONFIG` rewritten per §2.3; network constants added |
| :869-877 (wallet state)           | :905-913                          | Rename `publicKey` → `address`; add `chainId`         |
| :1063-1076 (getProvider)          | replaced                          | MetaMask EIP-1193 detection                           |
| :1085-1138 (connectWallet)        | replaced                          | `eth_requestAccounts` + chain enforcement             |
| :1140-1169 (verifyWallet)         | adapted                           | `personal_sign` instead of `signMessage`              |
| :1202-1256 (SNS lookup)           | replaced                          | `provider.lookupAddress()`                            |
| :1285-1344 (fetchStablecoinTxns)  | replaced                          | Etherscan + `eth_getLogs` (§2.1)                      |
| :1350-1991 (camt.053 + camt.054)  | copy with field swaps per §3      | Only the chain-identification XML tags change        |
| :2094-2105 (fetchTokenBalances)   | replaced                          | `balanceOf()` iteration                               |
| :2107-2167 (generateSemt002)      | copy with field swaps             | Same as above                                         |
| :2173-2247 (generateBAI2)         | copy verbatim                     | None — BAI2 has no chain-specific fields              |
| :2271-2702 (real-time tab)        | cosmetic swaps                    | Ticker labels, XML field swaps, fake tx-hash shape    |
| :2768-2948 (pain.001 tab)         | replaced                          | Manual 0x address entry; ethers ERC-20 transfer; optional memo tx (Phase 4) |
| All utility functions             | copy verbatim                     | `escXml`, `fmtDate`, `fmtDateTime`, `formatXml`, `highlightXml`, `trunc`, `shortAddr` |

Estimated delta: ~500 lines change out of 2951. The rest is copied unchanged.

---

## 7. Open risks & mitigations

| Risk                                                                                   | Mitigation                                                                                     |
|----------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| Etherscan free tier rate-limited mid-query for a large wallet                          | Exponential backoff + resumable pagination; cache partial results in `localStorage`             |
| Public RPC (`publicnode.com`) returns an error under heavy `eth_getLogs` load          | Retry with halved chunk size; progressive fallback to multiple public RPCs                      |
| User accidentally sends on mainnet thinking they're on Sepolia                         | Disable `Send` on mainnet entirely in v1 (conscious design choice per §2.2)                    |
| Frankencoin contract address changes due to governance action                          | Contract address is a single config constant; update takes seconds. Document the source of truth in `STABLECOIN_CONFIG` comments |
| ENS reverse lookup is slow or fails                                                    | Non-blocking; lookup runs after balance fetch; on timeout the UI just shows short address       |
| MetaMask mobile deeplink fails silently (iOS Safari PWA quirk)                         | Same "paste this URL into your wallet's browser tab" fallback as the Solana gateway uses        |
| ERC-20 with unusual decimals (e.g. DAI: 18, ZCHF: 18) treated as 6                     | Always read decimals from `STABLECOIN_CONFIG` per token; never assume                           |
| Registry (Phase 4) deployed to wrong chain or lost after Sepolia reset                 | `deployments.json` is versioned in git; redeploy script is idempotent                           |

---

## 8. Implementation order (reading left to right)

```
[Phase 1]                                 [Phase 2]                          [Phase 3]             [Phase 4]
Clone index.html                          Network picker                     eth_getLogs polish    ISOFIXMemo.sol
 ├─ wallet layer                           ├─ Sepolia config                  ├─ progress bar       ├─ deploy page
 ├─ fetchStablecoinTxns (Etherscan)        ├─ pain.001 manual 0x              ├─ backoff            ├─ deployments.json
 ├─ fetchStablecoinTxns (getLogs fallback) └─ ERC-20 send (no memo)           ├─ caching            └─ send flow extension
 ├─ fetchTokenBalances                                                        └─ time estimate
 ├─ XML field swaps
 └─ settings drawer
```

After Phase 1 the gateway is 85% useful (all read paths work). Phases 2–4 are additive; each can ship independently.

---

## 9. Documentation deliverables

When the port ships, also update:

- **[`README.md`](../README.md)** — add a section "EVM Gateway" linking to `public/index-evm.html` and briefly explaining the mainnet / Sepolia split.
- **[`docs/roadmap.md`](./roadmap.md)** — tick off the EVM port as delivered.
- **[`docs/GBITS_CAMT_PROJECT_KNOWLEDGE.md`](./GBITS_CAMT_PROJECT_KNOWLEDGE.md)** — add a paragraph on the EVM port's data-source strategy (Etherscan + getLogs), the decimals-aware config, and the memo-registry pattern.

---

## 10. Summary

A lot of the EVM port is surface-level field swaps. The interesting engineering is concentrated in three places:

1. **Transaction history** — Etherscan primary + zero-key `eth_getLogs` fallback, both normalized to the existing Solana-shaped internal record.
2. **Memo persistence** — the `ISOFIXMemo` registry closes the gap between ISO 20022's rich remittance model and ERC-20's memo-less transfer primitive without requiring memo-aware tokens.
3. **Network picker with safety defaults** — mainnet read, Sepolia write; impossible to send on mainnet by accident in v1.

Everything else is a careful clone.
