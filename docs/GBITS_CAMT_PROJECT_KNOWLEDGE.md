# Gbits.io — Solana → ISO 20022 camt.053 Bridge
## Project Knowledge Document

**Project:** Bidirectional Solana stablecoin ↔ ISO 20022 message gateway (camt.053/054 generation, semt.002 custody reports, pain.001 execution)  
**Hackathon:** StableHacks 2026 on DoraHacks (https://dorahacks.io/hackathon/stablehacks/tracks)  
**Brand:** Gbits.io  
**Contact:** romanix@gbits.io  
**Status:** Working prototype — camt.053/054 generation works end-to-end (Bexio import verified). semt.002 custody reports generate from on-chain token balances. pain.001 parsing and IBAN→Solana resolution work; SPL token transfer signing needs Helius paid API key.  
**Date:** February 26, 2026  

---

## 1. Architecture

**Single-file browser app** (`index.html`) — no build step, no backend.

- Deployed via drag-and-drop to Netlify
- All logic runs client-side in vanilla JavaScript (no React, no frameworks)
- Fonts loaded from Google Fonts CDN (Outfit + JetBrains Mono)
- Wallet connection via `window.solana` / `window.phantom.solana` (Phantom, Solflare, Backpack)
- Solana .sol domain resolution via Bonfida SNS proxy (`https://sns-sdk-proxy.bonfida.workers.dev/resolve/`)
- Transaction fetching via Helius Enhanced Transactions API
- XML generation entirely in-browser via string templating
- Download via `Blob` + `URL.createObjectURL`

**Helius API key** is embedded in the HTML (acceptable for hackathon, needs proxy for production).

---

## 2. Supported Stablecoins

| Token   | Mint Address                                       | Decimals | Mapped Currency | Notes                        |
|---------|---------------------------------------------------|----------|-----------------|------------------------------|
| USDC    | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`   | 6        | USD             | Circle-issued                |
| USDT    | `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB`    | 6        | USD             | Tether-issued                |
| PYUSD   | `2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo`   | 6        | USD             | PayPal USD                   |
| EURC    | `HzwqbKZw8HxMN6bF2yFZNrht3c2iXXzpKcFu7uBEDKtr`   | 6        | EUR             | Circle-issued                |
| EUROe   | `2VhjJ9WxaGC3EZFwJG9BDUs9KxKCAjQY4vgd1qxgYWVg`   | 6        | EUR             | Membrane Finance             |
| VCHF    | `AhhdRu5YZdjVkKR3wbnUDaymVQL2ucjMQ63sZ3LFHsch`   | 6        | CHF             | Swiss franc stablecoin       |

**Currency merging:** USDC + USDT + PYUSD → single USD statement. EURC + EUROe → single EUR statement. VCHF → CHF statement. Up to 3 XML files per generation. The original stablecoin is preserved in `<Prtry><Cd>` (e.g., `SOL-USDC`) and `<AddtlNtryInf>`.

---

## 3. Helius API Integration

**Endpoint:** `https://api-mainnet.helius-rpc.com/v0/addresses/{address}/transactions`  
**NOT** `api.helius.dev` (that domain doesn't resolve from browsers).

**Parameters:**
- `api-key` — Helius API key
- `type=TRANSFER` — filter for token transfers
- `limit=100` — max per page
- `before={signature}` — pagination cursor

**Response processing:**
- Each transaction has `tokenTransfers[]` array
- Filter by known stablecoin mint addresses
- `tokenAmount` from Helius is already in human-readable form (not raw decimals)
- Direction determined by comparing `toUserAccount`/`toTokenAccount` with the user's address
- Pagination: walk backwards through signatures until `timestamp < startDate`
- Rate limiting: 200ms delay between pages, max 50 pages

---

## 4. camt.053.001.04 XML Structure — Bexio-Compatible

The XML structure was reverse-engineered from a real Zürcher Kantonalbank (ZKB) camt.053 file that successfully imports into Bexio. Key learnings below.

### 4.1 Critical Requirements for Bexio Import

| Requirement | Detail |
|---|---|
| **IBAN must match** | The `<IBAN>` in `<Acct><Id>` MUST match a bank account configured in Bexio. Without this, Bexio rejects the file before even parsing it. |
| **XML declaration** | Must include `standalone="yes"` |
| **Namespace** | `urn:iso:std:iso:20022:tech:xsd:camt.053.001.04` — no `xsi:schemaLocation` |
| **SPS identifier** | `<AddtlInf>SPS/1.7/PROD</AddtlInf>` in GrpHdr is expected |
| **MsgPgntn** | Required in GrpHdr (despite being optional in XSD) |
| **BICFI not BIC** | ZKB uses `<BICFI>` (a v8 element) even in v4 namespace files. Bexio accepts this. |
| **Status format** | `<Sts>BOOK</Sts>` (simple string, NOT `<Sts><Cd>BOOK</Cd></Sts>` which is v8) |
| **RvslInd** | `<RvslInd>false</RvslInd>` present in ZKB entries |
| **DateTime format** | Swiss timezone offset: `2024-02-10T00:53:47.790+01:00` (not `Z` suffix) |
| **FrDtTm/ToDtTm** | Include milliseconds and timezone: `2024-09-01T00:00:00.000+01:00` |
| **TxDtls repeats** | `<Amt>`, `<CdtDbtInd>`, and `<BkTxCd>` are repeated inside `<TxDtls>` (ZKB pattern) |
| **TtlNetNtry** | Present inside `<TxsSummry><TtlNtries>` with `<Amt>` and `<CdtDbtInd>` |

### 4.2 Things That Caused Bexio Rejection

These were fixed iteratively during development:

1. **Invalid BIC length** — `SOLANXXXXX` (10 chars). BIC must be exactly 8 or 11 characters.
2. **`<Sts><Cd>BOOK</Cd></Sts>`** — v8 structure in a v4 namespace file.
3. **Missing `<MsgPgntn>`** — We removed it thinking it was v8-only, but ZKB includes it.
4. **Missing `<AddtlInf>SPS/1.7/PROD</AddtlInf>`** — Bexio may use this to identify Swiss SPS files.
5. **`xsi:schemaLocation` attribute** — Not present in real bank files.
6. **No IBAN provided** — Bexio requires IBAN match to a configured bank account.
7. **Wrong Helius endpoint** — `api.helius.dev` doesn't resolve; correct is `api-mainnet.helius-rpc.com`.

---

## 5. Solana Transaction → camt.053 Field Mapping

### 5.1 Header Level

| camt.053 Element | Source | Example Value |
|---|---|---|
| `GrpHdr/MsgId` | Generated: `GBITS` + currency + date + timestamp | `GBITSCHF2024090117719601073` |
| `GrpHdr/CreDtTm` | `new Date()` at generation time | `2026-02-24T20:08:27.000+01:00` |
| `GrpHdr/MsgPgntn/PgNb` | Always `1` | `1` |
| `GrpHdr/MsgPgntn/LastPgInd` | Always `true` | `true` |
| `GrpHdr/AddtlInf` | Hardcoded SPS version | `SPS/1.7/PROD` |

### 5.2 Statement Level

| camt.053 Element | Source | Example Value |
|---|---|---|
| `Stmt/Id` | Generated: `GBITS-STMT-` + currency + date + timestamp | `GBITS-STMT-CHF-2024-09-01-177196` |
| `Stmt/ElctrncSeqNb` | Always `1` | `1` |
| `Stmt/CreDtTm` | Same as GrpHdr/CreDtTm | `2026-02-24T20:08:27.000+01:00` |
| `Stmt/FrToDt/FrDtTm` | User-selected start date | `2024-09-01T00:00:00.000+01:00` |
| `Stmt/FrToDt/ToDtTm` | User-selected end date | `2026-02-24T23:59:59.999+01:00` |

### 5.3 Account Level

| camt.053 Element | Source | Example Value |
|---|---|---|
| `Acct/Id/IBAN` | User input (must match Bexio) | `LI21088100002324013AA` |
| `Acct/Id/Othr/Id` | Solana address (fallback if no IBAN) | `HNxTvnYKt2Cro5aCRnjaN9zUouZWsgqpYi` |
| `Acct/Ccy` | Mapped currency from stablecoin | `CHF` |
| `Acct/Ownr/Nm` | Solana address (truncated to 70 chars) | `HNxTvnYKt2Cro5aCRnjaN9zUouZWsgqpYiCQyjxt388b` |
| `Acct/Svcr/FinInstnId/BICFI` | Synthetic BIC for Solana | `SOLNCHZZXXX` |

### 5.4 Balance Level

| camt.053 Element | Source | Example Value |
|---|---|---|
| `Bal[OPBD]/Amt` | Hardcoded to `0.00` (unknown opening balance) | `0.00` |
| `Bal[OPBD]/CdtDbtInd` | Always `CRDT` | `CRDT` |
| `Bal[OPBD]/Dt/Dt` | Start date | `2024-09-01` |
| `Bal[CLBD]/Amt` | `abs(totalCredit - totalDebit)` | `0.62` |
| `Bal[CLBD]/CdtDbtInd` | `CRDT` if net positive, `DBIT` if net negative | `DBIT` |
| `Bal[CLBD]/Dt/Dt` | End date | `2026-02-24` |

### 5.5 Entry Level (per Solana token transfer)

| camt.053 Element | Solana Source | Notes |
|---|---|---|
| `Ntry/NtryRef` | Sequential index (1, 2, 3...) | Simple counter |
| `Ntry/Amt` | `tokenTransfer.tokenAmount` | Already human-readable from Helius |
| `Ntry/Amt@Ccy` | Mapped currency (USD/EUR/CHF) | From stablecoin config |
| `Ntry/CdtDbtInd` | Direction: `CRDT` if incoming, `DBIT` if outgoing | Compare `toUserAccount` with user address |
| `Ntry/RvslInd` | Always `false` | |
| `Ntry/Sts` | Always `BOOK` | Simple string in v4 |
| `Ntry/BookgDt/Dt` | `tx.timestamp` → date | Unix timestamp to YYYY-MM-DD |
| `Ntry/ValDt/Dt` | Same as BookgDt | Solana has no separate value date |
| `Ntry/AcctSvcrRef` | `tx.signature` (first 35 chars) | Solana transaction signature |
| `Ntry/BkTxCd/Domn/Cd` | Always `PMNT` | Payment domain |
| `Ntry/BkTxCd/Domn/Fmly/Cd` | `RCDT` for credits, `ICDT` for debits | Received/Issued Credit Transfer |
| `Ntry/BkTxCd/Domn/Fmly/SubFmlyCd` | `ESCT` | Maps to "SEPA Credit Transfer" in Bexio |

### 5.6 Transaction Detail Level (inside NtryDtls/TxDtls)

| camt.053 Element | Solana Source | Notes |
|---|---|---|
| `Refs/AcctSvcrRef` | `tx.signature` (first 35 chars) | Repeated from entry level |
| `Refs/EndToEndId` | `tx.signature` (first 35 chars) | End-to-end reference |
| `Amt` | Same as entry-level amount | Repeated per ZKB pattern |
| `CdtDbtInd` | Same as entry-level direction | Repeated per ZKB pattern |
| `BkTxCd` | Same structure as entry level | Repeated per ZKB pattern |
| `RltdPties/Dbtr/Nm` | Counterparty address (for CRDT) | Sender's Solana address |
| `RltdPties/Cdtr/Nm` | Counterparty address (for DBIT) | Recipient's Solana address |
| `RltdPties/CdtrAcct/Id/Othr/Id` | Counterparty address (for DBIT) | Shows as "IBAN" in Bexio (!) |
| `RmtInf/Ustrd` | `SOL-{TOKEN} {signature}` | Fallback when no QR reference, max 140 chars |
| `RmtInf/Strd/CdtrRefInf/Tp/CdOrPrtry/Prtry` | `QRR` (literal) | Only when Solana memo starts with `QRR:` |
| `RmtInf/Strd/CdtrRefInf/Ref` | Solana memo (strip `QRR:` prefix) | The 27-digit QR reference number |
| `RmtInf/Strd/AddtlRmtInf` | `SOL-{TOKEN} {signature}` | Additional info alongside QRR, max 140 chars |

### 5.7 Additional Entry Info

| camt.053 Element | Source | Notes |
|---|---|---|
| `AddtlNtryInf` | `Solana {TOKEN} via SPL Token` | Default description line |
| `AddtlNtryInf` (with QRR) | `Gutschrift QRR: {ref}` / `Belastung QRR: {ref}` | Matches ZKB pattern when QR reference present |

---

### 5.8 QR Reference Mapping (Gbits Pay Integration)

**Rule:** If a Solana transaction includes an SPL Memo and the memo content starts with `QRR:`, the string after the prefix is mapped as a Swiss QR reference number in the structured remittance information block.

**Source:** Solana SPL Memo program (`MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr` or v1 `Memo1UhkJBfCR6MNB2Ok59Fsy2KUmC5GKEMqhAN9WJY`)

**Extraction logic:**
1. Scan `tx.instructions` for SPL Memo program IDs → extract `ix.data` as memo string
2. Fallback: check `tx.description` if it starts with `QRR:`
3. If memo starts with `QRR:` → strip prefix → use remainder as QR reference

**Conditional XML output:**

When QR reference IS present → use `<Strd>` (structured remittance):
```xml
<RmtInf>
    <Strd>
        <CdtrRefInf>
            <Tp>
                <CdOrPrtry>
                    <Prtry>QRR</Prtry>
                </CdOrPrtry>
            </Tp>
            <Ref>114908924020000001000000111</Ref>
        </CdtrRefInf>
        <AddtlRmtInf>SOL-VCHF 3abc...def</AddtlRmtInf>
    </Strd>
</RmtInf>
```

When QR reference is NOT present → use `<Ustrd>` (unstructured, as before):
```xml
<RmtInf>
    <Ustrd>SOL-VCHF 3abc...def</Ustrd>
</RmtInf>
```

**This matches the ZKB camt.053 structure exactly** (see lines 398–409 in `zkb_camt053.xml`).

**Accounting system reconciliation:**
- **Bexio:** Parses `<CdtrRefInf><Ref>` for automatic invoice matching
- **SAP:** Maps QRR to FI document reference for open item clearing
- **Abacus:** Uses QR reference for debtor/creditor matching

**AddtlNtryInf pattern:** When QRR is present, the entry description follows ZKB's pattern:
- Credits: `Gutschrift QRR: 114908924020000001000000111`
- Debits: `Belastung QRR: 114908924020000001000000111`

---

## 6. How Bexio Displays the Imported Data

Based on actual import testing (Feb 24, 2026):

| Bexio Field | camt.053 Source | Example Display |
|---|---|---|
| Date | `Ntry/BookgDt/Dt` | `31 Oct 2025` |
| Description | `Ntry/AddtlNtryInf` | `Solana VCHF via SPL Token` |
| Amount | `Ntry/Amt` with sign from `CdtDbtInd` | `CHF -0.03` |
| Entry date | `Ntry/BookgDt/Dt` | `Friday, 31 October 2025` |
| Value date | `Ntry/ValDt/Dt` | `Friday, 31 October 2025` |
| IBAN | `TxDtls/RltdPties/CdtrAcct/Id/Othr/Id` | Solana address (!) |
| Payment from | `TxDtls/RltdPties/Cdtr/Nm` | Solana address |
| Bank description | Derived from `BkTxCd` codes | `SEPA Credit Transfer` |
| Additional info | `TxDtls/RmtInf/Ustrd` parsed | `SOL-VCHF` + full signature |

---

## 7. User Workflow

1. Install Phantom/Solflare browser extension
2. Open Gbits.io app
3. Connect wallet (Step 1)
4. Sign verification message (proves address ownership)
5. Solana address auto-fills (Step 2), or enter .sol domain / address manually
6. Enter IBAN matching the Bexio bank account (Step 3)
7. Select date range (Step 4)
8. Select report type — currently only camt.053.001.04 (Step 5)
9. Click Generate
10. App fetches transactions from Helius, groups by currency, generates XML
11. Download individual XML files per currency
12. Upload to Bexio via "Import bank transactions"

---

## 8. File & Deployment

- **Single file:** `index.html` (approx. 900 lines)
- **Deployment:** Drag-and-drop to Netlify (no build step)
- **Helius API key:** Embedded in source (current key: `cf479a6e-8fe8-4363-ab5b-8898913fbaff`)
- **No backend required**

---

## 9. TODOs

### High Priority

- [ ] **Helius API key security** — Move key to a Netlify serverless function or Cloudflare Worker proxy. Currently exposed in client source. Rotate key after hackathon.
- [ ] **Opening balance (OPBD)** — Currently hardcoded to `0.00`. Should query on-chain token balance at start-of-period for accurate statements. Helius `getTokenAccountBalance` or a historical snapshot could provide this.
- [ ] **VCHF decimals verification** — Assumed 6 decimals. Confirm this matches the actual token configuration on-chain.
- [ ] **SubFmlyCd mapping** — Currently using `ESCT` (SEPA Credit Transfer) for all entries, which causes Bexio to label everything as "SEPA Credit Transfer." Consider using `DMCT` (Domestic Credit Transfer) or `OTHR` for a more neutral label. Or introduce a proprietary Solana-specific code.
- [ ] **Counterparty in "IBAN" field** — Bexio displays `CdtrAcct/Id/Othr/Id` (Solana address) in the IBAN column. Consider omitting `<CdtrAcct>` entirely for debits, or adding a clearer label. Evaluate impact on reconciliation.

### Medium Priority

- [ ] **ZIP download** — Bundle multiple currency files into a single ZIP (e.g., using JSZip from CDN). Bexio accepts ZIP uploads.
- [ ] **camt.054 support** — Add BankToCustomerDebitCreditNotification for real-time / single-transaction notifications.
- [ ] **camt.053.001.08 (v8) support** — Generate v8 alongside v4. Main differences: `<Sts><Cd>BOOK</Cd></Sts>`, `<BICFI>` is native, some new optional elements.
- [ ] **Duplicate detection** — Track generated report signatures to warn if re-importing would create duplicates in Bexio.
- [ ] **Date range validation** — Warn if range exceeds 1 year (unusual for bank statements) or if future dates are selected.
- [ ] **ElctrncSeqNb incrementing** — Currently always `1`. Should increment per generated statement for the same account/period. Could use localStorage or a counter.
- [ ] **Swap transactions** — Currently only `type=TRANSFER` is fetched. Swaps (e.g., Jupiter) involving stablecoins are missed. Consider also fetching `type=SWAP` and extracting the stablecoin leg.
- [ ] **Transaction fees** — Solana transaction fees (in SOL) are not reflected in the camt.053. Consider adding a separate entry or noting in `<Chrgs>`.

### Low Priority / Nice-to-Have

- [ ] **Report history persistence** — Store last 5 reports in memory (currently done) or localStorage for cross-session access.
- [ ] **PDF statement preview** — Render a human-readable PDF alongside the XML using jsPDF or similar.
- [ ] **Multi-wallet support** — Allow generating statements across multiple Solana addresses.
- [ ] **Auto-detect Bexio IBAN** — If Bexio ever exposes an API, could auto-fill the IBAN.
- [ ] **XSD validation in-browser** — Validate generated XML against the official camt.053.001.04 XSD before download.
- [ ] **Proper BIC registration** — `SOLNCHZZXXX` is a synthetic BIC. For production use, consider registering a real BIC or using a different identification scheme.
- [ ] **Token logo/icon display** — Show stablecoin logos next to the token badges in the UI.
- [ ] **Localization** — German language support for Swiss users.
- [ ] **Rate limiting UI** — Show progress when fetching many pages of transactions (currently just a spinner with text).
- [ ] **Mobile responsiveness** — Basic responsive CSS exists but wallet connection flow needs testing on mobile.

### Hackathon-Specific

- [ ] **README / pitch deck** — Create submission materials for DoraHacks.
- [ ] **Demo video** — Record a walkthrough showing the full flow from wallet connection to Bexio import.
- [ ] **Landing page polish** — Add an "About" section explaining the ISO 20022 bridge concept.

---

## 10. Reference Documents

- **Swiss Payment Standards (SPS) Implementation Guidelines camt.053:** https://www.six-group.com/dam/download/banking-services/interbank-clearing/en/standardization/iso/swiss-recommendations/implementation-guidelines-camt-2022.pdf
- **SPS Download Center:** https://www.six-group.com/en/products-services/banking-services/payment-standardization/downloads-faq/download-center.html
- **ISO 20022 Message Archive (camt.053.001.04 XSD):** https://www.iso20022.org/catalogue-messages/iso-20022-messages-archive
- **Helius Enhanced Transactions API:** https://www.helius.dev/docs/enhanced-transactions
- **Helius API endpoint:** `https://api-mainnet.helius-rpc.com/v0/addresses/{address}/transactions?api-key={key}`
- **Bonfida SNS Resolution:** `https://sns-sdk-proxy.bonfida.workers.dev/resolve/{domain}`
- **Bexio ISO 20022 Info:** https://www.bexio.com/en-CH/iso20022
- **Bexio CAMT Import Guide:** https://magicheidi.ch/blog/connecting-your-bank-account-to-bexio-a-comprehensive-tutorial

---

## 11. Key Technical Gotchas (for future developers)

1. **Bexio IBAN matching is the #1 gatekeeper.** If the IBAN in the XML doesn't match a configured Bexio bank account, the import fails with a generic error that gives no hint about the actual problem.

2. **The Helius API endpoint changed.** Old: `api.helius.dev`. Current: `api-mainnet.helius-rpc.com`. If it changes again, check the Helius docs.

3. **ZKB uses BICFI (v8 element) inside a v4 namespace file.** This is technically non-standard but Bexio accepts it. Using `<BIC>` (the correct v4 element) was not tested — it might also work.

4. **`tokenAmount` from Helius is already parsed.** Don't divide by `10^decimals` again — that would give wrong amounts.

5. **Bexio shows `<Othr><Id>` values in the "IBAN" column.** This is cosmetically odd but functionally fine. Solana addresses appear where IBANs normally would.

6. **The `SPS/1.7/PROD` string in `<AddtlInf>`** may need updating when SPS versions change. Current Swiss banks use 1.7 or 1.8.

7. **All amounts must use period (`.`) as decimal separator** and exactly 2 decimal places for CHF/EUR/USD.

---

## 15. semt.002.001.11 — SecuritiesBalanceCustodyReport

### 15.1 Overview

The semt.002 report provides a **custody statement of holdings** — a point-in-time snapshot of all stablecoin positions held in the connected Solana wallet. Unlike camt.053/054 which report transactions, semt.002 reports what you hold right now.

This bridges the gap between DeFi wallets and traditional securities management systems. In the ISO 20022 world, a custodian (bank, CSD) sends semt.002 reports to account owners. Here, the "custodian" is the Solana blockchain itself (self-custody).

### 15.2 Message Format

- **Message:** `semt.002.001.11` — SecuritiesBalanceCustodyReport (ISO 20022)
- **Namespace:** `urn:iso:std:iso:20022:tech:xsd:semt.002.001.11`
- **Root:** `<SctiesBalCtdyRpt>`
- **Key feature:** Version 11 introduced `<BlckChainAdrOrWllt>` — a first-class blockchain address field in ISO 20022

### 15.3 Data Source

Instead of fetching transaction history, the semt.002 generator calls `getParsedTokenAccountsByOwner` via `@solana/web3.js Connection` to get current SPL token balances. Only known stablecoins (from `MINT_TO_CONFIG`) are included.

### 15.4 Field Mapping

| semt.002 Element | Solana Source | Notes |
|---|---|---|
| `<BlckChainAdrOrWllt><Id>` | Wallet public key | Full Solana address |
| `<BlckChainAdrOrWllt><Tp><Cd>` | `WLLT` | Wallet type |
| `<BlckChainAdrOrWllt><Ntwk><Cd>` | `SOLANA` | Network identifier |
| `<SfkpgAcct><Id>` | Wallet address (35 chars) | Safekeeping account |
| `<AcctOwnr>` | Wallet address | Via `<PrvtId><Othr>` with `SOLANA_WALLET` scheme |
| `<AcctSvcr>` | "Solana Blockchain (Self-Custody)" | The "custodian" |
| `<BalForAcct>` | One per stablecoin holding | Repeating block |
| `<FinInstrmId><OthrId><Id>` | SPL token mint address | Proprietary identifier |
| `<FinInstrmId><Desc>` | e.g. "USDC (USD) — SPL Token" | Human-readable |
| `<AggtBal><Qty><Unit>` | Token balance | From `getTokenAccountsByOwner` |
| `<AcctBaseCcyAmts><TtlMktVal>` | Balance × 1.00 | Stablecoins valued at par |
| `<SfkpgPlc><Tp><Prtry>` | `BLOCKCHAIN` | Safekeeping place type |
| `<StmtGnlDtls><Frqcy>` | `DAIL` | Daily frequency |
| `<StmtGnlDtls><StmtBsis>` | `SETT` | Settlement basis |

### 15.5 UI

- Added as third option in Report Type dropdown: `semt.002.001.11 — SecuritiesBalanceCustodyReport`
- Shows hint text: "Date range and IBAN are not required"
- Report card shows purple `semt` badge, "CUSTODY" label, total holdings value
- No date range or IBAN needed (just wallet connection)

### 15.6 Stablecoin-as-Security Interpretation

The semt.002 mapping treats stablecoins as financial instruments held in custody. This is conceptually valid: a stablecoin is a tokenized claim on a reserve asset, analogous to a money market fund share or a short-term debt instrument. The `<FinInstrmTp><ClssfctnTp>DBFTFR</ClssfctnTp>` classifies them as "Debt — Fixed Term — Fixed Rate" (closest CFI code for a stable-value instrument).

In production, each stablecoin could be assigned a proper ISIN (e.g., if USDC were registered as a security) or a proprietary identifier recognized by the receiving system.
