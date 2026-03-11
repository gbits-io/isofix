# ISOFIX — Hackathon Demo Talking Points

**Event:** StableHacks 2026 (DoraHacks)
**Demo URL:** https://iso.gbits.io
**GitHub:** https://github.com/gbits-io/isofix
**Presenter:** Roman Bischoff, Zürich

---

## Demo Structure (3–5 minutes)

### Opening (30 seconds)

> "The global banking system runs on ISO 20022 — it's the message standard behind SWIFT, SIC, SEPA, and every major payment rail. Stablecoins are the fastest-growing payment method on earth. But they don't speak the same language. ISOFIX is the translator."

Show `flows.html` briefly — point at the two directions, mention on-demand is live, webhook is next.

### Live Demo — ISOFIX only (2–3 minutes)

**Single screen, single app, no context-switching.**

1. **Connect wallet** — use a wallet with existing stablecoin transaction history. No need to send a live payment.

2. **Generate camt.053** — select a date range that covers real transactions. Click Generate. Multiple reports appear (one per currency). "These are real on-chain transactions from Solana mainnet, turned into standard bank statements."

3. **Open the XML viewer** — click View on one report. Walk through key fields:
   - "This `AcctSvcrRef` is the Solana transaction signature — verifiable on Solscan."
   - "This `Amt Ccy='CHF'` came from a VCHF stablecoin transfer."
   - "This `BookgDt` is the block timestamp."
   - "This QR reference in `CdtrRefInf` is what Bexio uses to auto-match payments to invoices."

4. **Show semt.002 custody report** — switch report type, generate. "This uses ISO 20022's native `BlckChainAdrOrWllt` element from the 2019 release. The standard already anticipated blockchain custody reporting — we're using it as designed."

5. **Show Realtime tab** — simulate 1-2 inbound payments. "In production, a Helius webhook triggers this automatically when a stablecoin payment arrives. The camt.054 notification appears in seconds."

6. **Show pain.001 direction** — upload a sample file. "A standard Swiss payment file goes in, each IBAN resolves to a Solana address via SNS subdomains, and ISOFIX constructs SPL token transfers. The banking world's payment instruction becomes a blockchain transaction."

### End-to-End Story (on a slide, not live)

> "We've validated the full round-trip with Bexio: a Swiss QR invoice gets paid with VCHF stablecoins via our Gbits Pay app, the creditor generates a camt.053 in ISOFIX, imports it into Bexio, and the payment auto-matches to the invoice via the QR reference. All without a bank. I won't demo all four systems live — but it works, and the field mapping reference on the site shows exactly how every on-chain field maps to the XML."

*Show the slide with the round-trip diagram or a 30-second screen recording.*

### Closing — What's Next (30 seconds)

> "Next steps: a Cloudflare Worker for live webhook-driven camt.054, a REST API so companies can fetch reports programmatically, and multi-chain support — the same pattern works with Infura for Ethereum and Base stablecoins. This is open source under BSL 1.1 — anyone in the Solana ecosystem can build on it."

---

## Slide: Solana Meets ISO 20022

**The narrative to counter (without being combative):**

The XRP/Ripple community has long claimed that Ripple is "ISO 20022 compliant" and therefore positioned to replace SWIFT. This claim is based on Ripple's membership in the ISO 20022 Registration Management Group (RMG) — an industry standards body. Membership doesn't mean their blockchain produces or consumes ISO 20022 messages natively.

**The framing (factual, positive about Solana):**

> "There's a common narrative that certain blockchains are 'ISO 20022 compliant.' But compliance isn't a blockchain property — it's an integration layer. ISOFIX provides that layer for Solana."

**Two-column comparison for the slide:**

| | The claim elsewhere | What ISOFIX does today |
|---|---|---|
| **ISO 20022 messages** | "Our blockchain is compatible" (no public tooling to generate camt/pain/semt from on-chain data) | Generates camt.053, camt.054, semt.002 from real Solana transactions. Executes pain.001 as SPL transfers |
| **Accounting software** | No known import validation | Validated import into Bexio (Feb 2026), designed for SAP and Abacus |
| **Swiss Payment Standards** | Not demonstrated | SPS 2009 (camt.053, pain.001), SPS 2024 (camt.054), QR reference forwarding via SPL Memo |
| **Blockchain-native fields** | Not using ISO 20022's blockchain elements | Uses `<BlckChainAdrOrWllt>` in semt.002 — the standard's own element for blockchain addresses |
| **Open source** | Proprietary protocols | BSL 1.1, public GitHub repo, anyone can extend |
| **Stablecoins** | Primarily proprietary tokens | Works with USDC, USDT, PYUSD, EURC, EUROe, VCHF — the existing Solana stablecoin ecosystem |

**Key line for the Solana Foundation judge:**

> "With ISOFIX, Solana now has concrete, working ISO 20022 support — not a roadmap, not a membership badge, but actual tooling that turns on-chain stablecoin payments into standard banking messages. It's open source. Others in the ecosystem can build on it, extend it to new message types, or integrate it into their payment products."

---

## Anticipated Questions and Answers

**"Is this really ISO 20022 compliant?"**
> "The generated XML validates against the official schemas — camt.053.001.04, camt.054.001.08, pain.001.001.03, semt.002.001.11. We've tested import into Bexio, which is one of the most widely used Swiss accounting platforms. The Swiss Payment Standards compliance is documented in detail on the GitHub repo."

**"Why not just use a CSV export?"**
> "CSV has no standard schema — every bank and every accounting tool expects a different format. ISO 20022 is *the* global standard. Once you produce a valid camt.053, it imports into any compliant system worldwide. And it carries structured data like QR references that enable automatic payment matching — something flat CSV can't do."

**"What about the Helius API key in the client?"**
> "That's a known issue we're actively addressing. The planned Cloudflare Worker proxy will move the API key server-side. For the hackathon demo, it's functional but not production-hardened."

**"How does the IBAN → Solana resolution work?"**
> "We use Solana Name Service subdomains. We own the domain `verified-iban.sol`. Each verified IBAN is registered as a subdomain — so `ch5204835012345671000.verified-iban.sol` resolves to a Solana wallet address. The resolution happens via the Bonfida SNS proxy API."

**"Could this work for other blockchains?"**
> "Absolutely. The ISO 20022 mapping logic is chain-agnostic — it just needs a transaction with an amount, a timestamp, a sender, a receiver, and a currency. Ethereum, Base, Arbitrum all have the same stablecoins. Swap Helius for Infura or Alchemy, and the same pattern works. That's Milestone 3 on our roadmap."

**"What's the business model?"**
> "The open source version is free for non-commercial use. For companies that want production payment processing, we'd offer a commercial license and a hosted REST API — companies call `GET /api/v1/reports/camt053?address={addr}` and get back a bank statement. That's Milestone 4."

**"Why a single HTML file?"**
> "Auditability. If a bank or compliance officer wants to understand what this tool does with their wallet data, they can read the entire source code in one file. No `node_modules`, no build artifacts, no hidden dependencies. Every line is visible."

---

## Demo Checklist

- [ ] Wallet with real stablecoin transaction history on mainnet (preferably multiple currencies)
- [ ] A sample pain.001 XML file ready for upload
- [ ] `iso.gbits.io` loaded and tested in advance (check wallet connection works)
- [ ] `iso.gbits.io/flows.html` loaded in a separate tab
- [ ] Solscan open in a tab (to verify a transaction signature if asked)
- [ ] Screen recording of Bexio round-trip as backup (30 seconds)
- [ ] Slide deck with: flow diagram, field mapping highlights, Solana meets ISO 20022 comparison, what's next
- [ ] Backup: ISOFIX-only demo can run entirely offline once the page is loaded (transactions are already fetched)
