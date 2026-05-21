// ═══════════════════════════════════════════════════════════════════════════════
// ISOFIX Demo — Mock NAV Service (Netlify Edge Function / Deno)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Simulates the off-chain data that real fund administrators (Securitize,
// Superstate, Ondo, Circle) would provide to a custody system consuming
// tokenized instruments. Default values are drawn from publicly available
// data about the real tokens where possible.
//
// This is demo infrastructure for StableHacks. Not production code.
//
// Endpoints:
//   GET  /nav/:ticker          — current NAV / yield state
//   GET  /nav/:ticker/history  — synthetic historical NAV (query: ?days=N)
//   POST /nav/:ticker/set      — override values for live demo moments
//
// Every response includes _mock: true and a disclaimer.
// ═══════════════════════════════════════════════════════════════════════════════

interface NavDataMMF {
  ticker: string;
  name: string;
  structural_category: 'mmf_perpetual' | 'tbill_fund';
  nav_per_share: number;
  accrued_dividend_per_share: number;
  dividend_rate_annualized: number;
  last_distribution_date: string;
  fund_classification: string;
  issuer_lei: string;
  isin: string;
  reporting_currency: string;
}

interface NavDataNote {
  ticker: string;
  name: string;
  structural_category: 'yield_note';
  price_per_token: number;
  accrued_yield: number;
  yield_rate_annualized: number;
  issuer_lei: string;
  isin: string;
  reporting_currency: string;
}

interface NavDataStablecoin {
  ticker: string;
  name: string;
  structural_category: 'stablecoin';
  price_per_token: number;
  no_yield_structure: true;
}

type NavData = NavDataMMF | NavDataNote | NavDataStablecoin;

// ── In-memory state store (resets on cold start) ────────────────────────────

const navState: Record<string, NavData> = {
  'MOCK-BUIDL': {
    ticker: 'MOCK-BUIDL',
    name: 'Mock BlackRock USD Institutional Digital Liquidity Fund',
    structural_category: 'mmf_perpetual',
    nav_per_share: 1.0000,
    accrued_dividend_per_share: 0.000137,
    dividend_rate_annualized: 0.0501,
    last_distribution_date: '2026-04-14',
    fund_classification: 'MMKT',
    issuer_lei: 'MOCK549300OGYHAMBK0X11',
    isin: 'MOCK0BUIDL001',
    reporting_currency: 'USD',
  },
  'MOCK-USTB': {
    ticker: 'MOCK-USTB',
    name: 'Mock Superstate Short Duration US Government Securities Fund',
    structural_category: 'tbill_fund',
    nav_per_share: 10.1834,
    accrued_dividend_per_share: 0.001199,
    dividend_rate_annualized: 0.0430,
    last_distribution_date: '2026-04-14',
    fund_classification: 'DBTS',
    issuer_lei: 'MOCK549300SUPERST8K2Y22',
    isin: 'MOCK0USTB0001',
    reporting_currency: 'USD',
  },
  'MOCK-USDY': {
    ticker: 'MOCK-USDY',
    name: 'Mock Ondo US Dollar Yield Token',
    structural_category: 'yield_note',
    price_per_token: 1.0491,
    accrued_yield: 0.000118,
    yield_rate_annualized: 0.0435,
    issuer_lei: 'MOCK549300ONDOFIN7X333',
    isin: 'MOCK0USDY0001',
    reporting_currency: 'USD',
  },
  'MOCK-USDC': {
    ticker: 'MOCK-USDC',
    name: 'Mock USD Coin (demo stablecoin)',
    structural_category: 'stablecoin',
    price_per_token: 1.0000,
    no_yield_structure: true,
  },
};

// ── Helpers ─────────────────────────────────────────────────────────────────

const DISCLAIMER = 'Simulated data for demo purposes. Not connected to real fund administrator APIs.';

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}

function errorResponse(message: string, status: number): Response {
  return jsonResponse({ error: message, _mock: true, _disclaimer: DISCLAIMER }, status);
}

function parseTicker(pathname: string): { ticker: string; subpath: string } | null {
  // pathname is like /nav/MOCK-BUIDL or /nav/MOCK-BUIDL/history or /nav/MOCK-BUIDL/set
  const match = pathname.match(/^\/nav\/([A-Z0-9-]+)(\/.*)?$/);
  if (!match) return null;
  return { ticker: match[1], subpath: match[2] || '' };
}

// ── Generate synthetic history ──────────────────────────────────────────────

function generateHistory(ticker: string, days: number): Array<{ date: string; value: number }> {
  const data = navState[ticker];
  if (!data) return [];

  const history: Array<{ date: string; value: number }> = [];
  const now = new Date();

  let currentValue: number;
  let dailyRate: number;

  if (data.structural_category === 'mmf_perpetual' || data.structural_category === 'tbill_fund') {
    currentValue = data.nav_per_share;
    dailyRate = data.dividend_rate_annualized / 365;
  } else if (data.structural_category === 'yield_note') {
    currentValue = data.price_per_token;
    dailyRate = data.yield_rate_annualized / 365;
  } else {
    currentValue = data.price_per_token;
    dailyRate = 0;
  }

  for (let d = days; d >= 0; d--) {
    const date = new Date(now);
    date.setDate(date.getDate() - d);
    const dateStr = date.toISOString().substring(0, 10);
    // Linear interpolation backward from current value
    const value = currentValue / (1 + dailyRate * d);
    history.push({ date: dateStr, value: Math.round(value * 10000) / 10000 });
  }

  return history;
}

// ── Main handler ────────────────────────────────────────────────────────────

export default async function handler(request: Request): Promise<Response> {
  // Handle CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
    });
  }

  const url = new URL(request.url);
  const parsed = parseTicker(url.pathname);

  if (!parsed) {
    // /nav with no ticker — list all available tickers
    if (url.pathname === '/nav' || url.pathname === '/nav/') {
      return jsonResponse({
        _mock: true,
        _disclaimer: DISCLAIMER,
        available_tickers: Object.keys(navState),
        data: Object.values(navState).map(d => ({ ticker: d.ticker, name: d.name, structural_category: d.structural_category })),
      });
    }
    return errorResponse('Invalid path. Use /nav/:ticker', 400);
  }

  const { ticker, subpath } = parsed;

  if (!navState[ticker]) {
    return errorResponse(
      `Unknown ticker: ${ticker}. Available: ${Object.keys(navState).join(', ')}`,
      404,
    );
  }

  // Log request to stdout (visible in terminal during demo)
  const ts = new Date().toISOString().substring(11, 19);
  console.log(`[${ts}] ${request.method} /nav/${ticker}${subpath || ''}`);

  // ── GET /nav/:ticker ──────────────────────────────────────────────────

  if (request.method === 'GET' && (subpath === '' || subpath === '/')) {
    return jsonResponse({
      _mock: true,
      _disclaimer: DISCLAIMER,
      data: navState[ticker],
    });
  }

  // ── GET /nav/:ticker/history ──────────────────────────────────────────

  if (request.method === 'GET' && subpath === '/history') {
    const days = parseInt(url.searchParams.get('days') || '30', 10);
    const clampedDays = Math.max(1, Math.min(days, 365));
    const history = generateHistory(ticker, clampedDays);
    return jsonResponse({
      _mock: true,
      _disclaimer: DISCLAIMER,
      ticker,
      days: clampedDays,
      data: history,
    });
  }

  // ── POST /nav/:ticker/set ─────────────────────────────────────────────

  if (request.method === 'POST' && subpath === '/set') {
    try {
      const body = await request.json();
      const current = navState[ticker];

      // Merge provided fields into current state (shallow)
      for (const [key, value] of Object.entries(body)) {
        if (key === 'ticker' || key === 'structural_category') continue; // immutable
        (current as Record<string, unknown>)[key] = value;
      }

      console.log(`[${ts}]   -> Updated ${ticker}: ${JSON.stringify(body)}`);

      return jsonResponse({
        _mock: true,
        _disclaimer: DISCLAIMER,
        message: `Updated ${ticker}`,
        data: current,
      });
    } catch {
      return errorResponse('Invalid JSON body', 400);
    }
  }

  return errorResponse(`Unknown route: ${request.method} /nav/${ticker}${subpath}`, 404);
}

export const config = { path: '/nav/*' };
