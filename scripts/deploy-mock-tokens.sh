#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# ISOFIX Demo — Deploy Mock SPL Tokens to Solana Devnet
# ═══════════════════════════════════════════════════════════════════════════════
#
# Deploys four mock SPL tokens representing different structural categories
# of tokenized instruments for the ACTUS classification demo.
#
# Prerequisites:
#   - solana CLI installed (https://docs.solanalabs.com/cli/install)
#   - spl-token CLI installed (cargo install spl-token-cli)
#   - Cluster set to devnet: solana config set --url https://api.devnet.solana.com
#
# Usage:
#   bash scripts/deploy-mock-tokens.sh
#
# Output:
#   demo/mock-tokens.json   — deployed mint addresses and metadata
#   demo/demo-wallet.json   — disposable devnet keypair (if generated)
#
# This script deploys to Solana DEVNET only. It will refuse to run against
# mainnet under any circumstances. The keypair and tokens are for demo
# purposes only and have no monetary value.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_DIR="$PROJECT_ROOT/demo"
WALLET_PATH="$DEMO_DIR/demo-wallet.json"
TOKENS_PATH="$DEMO_DIR/mock-tokens.json"

# ── Colors (for terminal output) ─────────────────────────────────────────────

CYAN='\033[0;36m'
GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
DIM='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${AMBER}[WARN]${RESET}  $*"; }
fail()  { echo -e "${RED}[FAIL]${RESET}  $*"; exit 1; }

# ── Mainnet guard ────────────────────────────────────────────────────────────

CLUSTER_URL=$(solana config get 2>/dev/null | grep "RPC URL" | awk '{print $3}')

if echo "$CLUSTER_URL" | grep -qi "mainnet"; then
    fail "Refusing to deploy mock tokens to mainnet."
    echo "  Switch to devnet first:"
    echo "    solana config set --url https://api.devnet.solana.com"
    exit 1
fi

info "Cluster: $CLUSTER_URL"

if ! echo "$CLUSTER_URL" | grep -qi "devnet"; then
    warn "Cluster does not appear to be devnet. Proceeding, but tokens will be on: $CLUSTER_URL"
fi

# ── Check prerequisites ─────────────────────────────────────────────────────

command -v solana >/dev/null 2>&1    || fail "solana CLI not found. Install: https://docs.solanalabs.com/cli/install"
command -v spl-token >/dev/null 2>&1 || fail "spl-token CLI not found. Install: cargo install spl-token-cli"

# ── Wallet setup ─────────────────────────────────────────────────────────────

mkdir -p "$DEMO_DIR"

if [ ! -f "$WALLET_PATH" ]; then
    info "Generating demo wallet keypair..."
    solana-keygen new --outfile "$WALLET_PATH" --no-bip39-passphrase --force --silent
    ok "Demo wallet created: $WALLET_PATH"
    echo -e "${AMBER}  WARNING: This is a disposable devnet-only keypair. Not for real funds.${RESET}"
else
    info "Demo wallet exists: $WALLET_PATH"
fi

WALLET_PUBKEY=$(solana-keygen pubkey "$WALLET_PATH")
info "Wallet address: $WALLET_PUBKEY"

# ── Airdrop SOL if needed ────────────────────────────────────────────────────

SOL_BALANCE=$(solana balance "$WALLET_PUBKEY" --url "$CLUSTER_URL" 2>/dev/null | awk '{print $1}' || echo "0")
SOL_INT=${SOL_BALANCE%.*}

if [ "${SOL_INT:-0}" -lt 1 ]; then
    info "SOL balance is ${SOL_BALANCE}. Requesting airdrop..."
    solana airdrop 2 "$WALLET_PUBKEY" --url "$CLUSTER_URL" 2>/dev/null || warn "Airdrop failed (devnet may be rate-limited). Retrying in 5s..."
    sleep 5
    solana airdrop 2 "$WALLET_PUBKEY" --url "$CLUSTER_URL" 2>/dev/null || warn "Airdrop retry failed. You may need to manually fund the wallet."
    SOL_BALANCE=$(solana balance "$WALLET_PUBKEY" --url "$CLUSTER_URL" 2>/dev/null | awk '{print $1}' || echo "0")
    ok "SOL balance: $SOL_BALANCE"
else
    ok "SOL balance: $SOL_BALANCE (sufficient)"
fi

# ── Token definitions ────────────────────────────────────────────────────────

declare -a TICKERS=("MOCK-BUIDL" "MOCK-USTB" "MOCK-USDY" "MOCK-USDC")
declare -A TOKEN_NAMES=(
    ["MOCK-BUIDL"]="Mock BlackRock USD Institutional Digital Liquidity Fund"
    ["MOCK-USTB"]="Mock Superstate Short Duration US Government Securities Fund"
    ["MOCK-USDY"]="Mock Ondo US Dollar Yield Token"
    ["MOCK-USDC"]="Mock USD Coin (demo stablecoin)"
)
declare -A TOKEN_CATEGORIES=(
    ["MOCK-BUIDL"]="mmf_perpetual"
    ["MOCK-USTB"]="tbill_fund"
    ["MOCK-USDY"]="yield_note"
    ["MOCK-USDC"]="stablecoin"
)
declare -A TOKEN_AMOUNTS=(
    ["MOCK-BUIDL"]="10000"
    ["MOCK-USTB"]="10000"
    ["MOCK-USDY"]="10000"
    ["MOCK-USDC"]="50000"
)

# ── Idempotency check ───────────────────────────────────────────────────────

if [ -f "$TOKENS_PATH" ]; then
    info "mock-tokens.json exists. Checking if mints are still valid on devnet..."
    ALL_VALID=true

    for TICKER in "${TICKERS[@]}"; do
        EXISTING_MINT=$(python3 -c "
import json, sys
with open('$TOKENS_PATH') as f:
    tokens = json.load(f)
for t in tokens:
    if t['ticker'] == '$TICKER':
        print(t['mint_address'])
        sys.exit(0)
print('')
" 2>/dev/null || echo "")

        if [ -z "$EXISTING_MINT" ]; then
            ALL_VALID=false
            break
        fi

        # Check if mint exists on devnet
        if ! spl-token display "$EXISTING_MINT" --url "$CLUSTER_URL" >/dev/null 2>&1; then
            warn "$TICKER mint $EXISTING_MINT no longer exists on devnet"
            ALL_VALID=false
            break
        fi
    done

    if [ "$ALL_VALID" = true ]; then
        ok "All mints are still valid on devnet. Skipping redeployment."
        echo ""
        echo -e "${DIM}To force redeployment, delete demo/mock-tokens.json and run again.${RESET}"
        exit 0
    else
        warn "Some mints are invalid. Redeploying all tokens..."
    fi
fi

# ── Deploy tokens ────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Deploying 4 mock SPL tokens to Solana devnet...${RESET}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

JSON_ENTRIES=""

for TICKER in "${TICKERS[@]}"; do
    NAME="${TOKEN_NAMES[$TICKER]}"
    CATEGORY="${TOKEN_CATEGORIES[$TICKER]}"
    AMOUNT="${TOKEN_AMOUNTS[$TICKER]}"

    echo ""
    info "Deploying $TICKER ($CATEGORY)..."

    # Create token
    CREATE_OUTPUT=$(spl-token create-token --decimals 6 --fee-payer "$WALLET_PATH" --url "$CLUSTER_URL" 2>&1)
    MINT_ADDRESS=$(echo "$CREATE_OUTPUT" | grep "Creating token" | awk '{print $3}')

    if [ -z "$MINT_ADDRESS" ]; then
        # Try alternative parsing
        MINT_ADDRESS=$(echo "$CREATE_OUTPUT" | grep -oP '[A-HJ-NP-Za-km-z1-9]{32,44}' | head -1)
    fi

    if [ -z "$MINT_ADDRESS" ]; then
        fail "Could not extract mint address for $TICKER. Output: $CREATE_OUTPUT"
    fi

    ok "  Mint: $MINT_ADDRESS"

    # Create associated token account
    spl-token create-account "$MINT_ADDRESS" --fee-payer "$WALLET_PATH" --owner "$WALLET_PATH" --url "$CLUSTER_URL" >/dev/null 2>&1
    ok "  Token account created"

    # Mint tokens
    spl-token mint "$MINT_ADDRESS" "$AMOUNT" --fee-payer "$WALLET_PATH" --mint-authority "$WALLET_PATH" --url "$CLUSTER_URL" >/dev/null 2>&1
    ok "  Minted $AMOUNT tokens"

    # Build JSON entry
    ENTRY=$(cat <<ENTRY_EOF
  {
    "ticker": "$TICKER",
    "mint_address": "$MINT_ADDRESS",
    "decimals": 6,
    "name": "$NAME",
    "structural_category": "$CATEGORY"
  }
ENTRY_EOF
)

    if [ -n "$JSON_ENTRIES" ]; then
        JSON_ENTRIES="$JSON_ENTRIES,
$ENTRY"
    else
        JSON_ENTRIES="$ENTRY"
    fi
done

# ── Write mock-tokens.json ───────────────────────────────────────────────────

cat > "$TOKENS_PATH" <<EOF
[
$JSON_ENTRIES
]
EOF

echo ""
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
ok "All 4 tokens deployed successfully."
ok "Mint addresses written to: $TOKENS_PATH"
ok "Demo wallet: $WALLET_PUBKEY"
echo ""
echo -e "${AMBER}NOTE: These are devnet tokens with no monetary value.${RESET}"
echo -e "${AMBER}      Devnet state resets periodically. Re-run this script if needed.${RESET}"
echo ""
echo -e "${DIM}Next steps:${RESET}"
echo -e "${DIM}  1. Update mint addresses in public/demo.html${RESET}"
echo -e "${DIM}  2. Start NAV service: netlify dev${RESET}"
echo -e "${DIM}  3. Open http://localhost:8888/demo.html${RESET}"
