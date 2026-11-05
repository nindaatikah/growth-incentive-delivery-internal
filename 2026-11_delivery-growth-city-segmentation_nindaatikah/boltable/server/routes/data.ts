import { Router } from "express";
import fs from "node:fs";
import path from "node:path";
import { runQuery as realQuery } from "../lib/databricks.js";
import { mockQuery } from "../lib/mock.js";
import { readSnapshot, snapshotEnabled, writeSnapshot } from "../lib/snapshot.js";

type Row = Record<string, string | null>;

const queryFn = process.env.MOCK_DATA === "1" ? async (sql: string) => mockQuery(sql) : realQuery;

// A cold cluster can take several minutes to start; past this, report an error instead of waiting forever.
const QUERY_TIMEOUT_MS = 15 * 60 * 1000;
// Queries in flight (label -> start time) and the last finished ones, shown on the page while loading.
const running = new Map<string, number>();
const finished: { label: string; rows: number; seconds: number }[] = [];

// Logs how long each query takes, so slow loads can be diagnosed from the Portal app logs.
async function runQuery(label: string, sql: string): Promise<Row[]> {
  const t0 = Date.now();
  running.set(label, t0);
  let timer: NodeJS.Timeout | undefined;
  try {
    const rows = await Promise.race([
      queryFn(sql),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(`query ${label} timed out after 15 minutes`)), QUERY_TIMEOUT_MS);
      }),
    ]);
    const seconds = Math.round((Date.now() - t0) / 1000);
    console.log(`query ${label}: ${rows.length} rows in ${seconds}s`);
    finished.unshift({ label, rows: rows.length, seconds });
    finished.length = Math.min(finished.length, 10);
    return rows;
  } finally {
    clearTimeout(timer);
    running.delete(label);
  }
}

export const dataRouter = Router();

const queriesDir = path.join(import.meta.dirname!, "..", "..", "queries");
const readSql = (name: string) => fs.readFileSync(path.join(queriesDir, name), "utf8");
const dailySql = (from: string, to: string) =>
  readSql("daily_city.sql").replaceAll("__FROM__", from).replaceAll("__TO__", to);

// Refreshed once a day, at this hour UTC (08:00 UTC = 10:00 in Estonia in winter, 11:00 in summer).
const REFRESH_HOUR_UTC = Number(process.env.REFRESH_HOUR_UTC ?? 8);
// Also dropped from old snapshots, so they disappear without a full reload.
const EXCLUDED_COUNTRIES = new Set(["Georgia", "Tuvalu", "Croatia"]);
// Late spend and cancellations can still change the last few days, so each refresh re-reads them.
const RELOAD_DAYS = 3;
// Far enough back for the weekly default (last 12 weeks, plus the week before for WoW) at any date from now on.
const RECENT_START = "2026-07-01";
// Last year's data (for YoY) starts here and runs up to the end of this month one year ago.
const HISTORY_START = "2025-07-01"; // a year before RECENT_START, so YoY works for every day the trend tabs can show
/** Exclusive end of the history window: the 1st of next month, one year back. */
function historyEnd(now = new Date()) {
  return new Date(Date.UTC(now.getUTCFullYear() - 1, now.getUTCMonth() + 1, 1)).toISOString().slice(0, 10);
}

// Raw query results. History (last year's months) never changes; recent is refreshed incrementally.
// Bump when the row shape changes, so an old S3 snapshot is ignored instead of misread.
const STATE_VERSION = 8; // 8: history window starts 2025-07-01 (YoY on the trend tabs); 7: history window starts 2026-07-01 (12-week default); 6: + Bolt Plus spend; 5: + BA spend and objective spend columns; 4: local dates, CP includes failed orders (SSOT definition)
type State = { version: number; at: string; hist: Row[]; histTo?: string; recent: Row[]; budget: Row[]; budgetAt?: string };
let state: State | null = null;
let payload: unknown = null;
let inflight: Promise<void> | null = null;
let loadingSince: number | null = null;
let lastError: { at: number; message: string } | null = null;

const num = (v: string | null | undefined) => (v == null || v === "" ? 0 : Number(v));
// Missing / blank budget cell = "no target" (not a target of 0).
const opt = (v: string | null | undefined) => (v == null || v === "" || Number.isNaN(Number(v)) ? undefined : Number(v));

// Daily row columns after [day, unit], in this order (the client's AGG_KEYS).
const ROW_FIELDS = ["gmv", "bolt", "act", "react", "eng", "cp1", "cp2", "ba", "elc", "mkt", "am", "churn", "bdm", "p1", "plus"];
// Budget ratio columns (share of GMV) -> payload keys.
const RATIO_COLUMNS: Record<string, string> = {
  activation_spend: "act", reactivation_spend: "react", engagement_spend: "eng", total_bolt_spend: "bolt",
  ba_total_spend: "ba", elc: "elc", marketing: "mkt", am: "am", churn: "churn", bdm_3p: "bdm", store_1p: "p1", bolt_plus: "plus",
};
function ratios(b: Row) {
  const out: Record<string, number> = {};
  for (const [col, key] of Object.entries(RATIO_COLUMNS)) {
    const v = opt(b[col]);
    if (v !== undefined) out[key] = v;
  }
  return out;
}

function buildPayload(s: State) {
  // Compact payload: cities and (city, zone cluster) units are indexed, daily rows are arrays.
  const cityIndex = new Map<string, number>();
  const cities: { country: string; city: string }[] = [];
  const cityIdx = (country: string, city: string) => {
    const key = `${country}|${city}`;
    let i = cityIndex.get(key);
    if (i === undefined) {
      i = cities.length;
      cityIndex.set(key, i);
      cities.push({ country, city });
    }
    return i;
  };
  const unitIndex = new Map<string, number>();
  const units: [number, string][] = [];
  const unitIdx = (c: number, cluster: string) => {
    const key = `${c}|${cluster}`;
    let i = unitIndex.get(key);
    if (i === undefined) {
      i = units.length;
      unitIndex.set(key, i);
      units.push([c, cluster]);
    }
    return i;
  };

  const rows = [...s.hist, ...s.recent]
    .filter((r) => !EXCLUDED_COUNTRIES.has(r.country_name!))
    .map((r) => [
      r.day,
      unitIdx(cityIdx(r.country_name!, r.city_name!), r.zone_cluster ?? "Unclustered"),
      ...ROW_FIELDS.map((f) => num(r[f])),
    ]);

  // Budget comes at three levels. A table loaded before the aggregation column existed is all city rows.
  const level = (b: Row) => (b.aggregation ?? "city").toLowerCase();
  const month = (b: Row) => {
    const m = b.month ?? "";
    if (/^\d{4}-\d{2}/.test(m)) return m.slice(0, 7);
    const d = new Date(m);
    return Number.isNaN(+d) ? m : d.toISOString().slice(0, 7);
  };
  // If the table holds the same budget row twice (the load notebook run twice), the newest copy wins.
  const newest = new Map<string, Row>();
  for (const b of [...s.budget].sort((x, y) => (x._ingested_at ?? "").localeCompare(y._ingested_at ?? ""))) {
    const lv = level(b);
    newest.set([lv, month(b), b.country_name ?? "", b.city_name ?? "", lv === "segment" ? b.city_segment || b.final_segment || "" : ""].join("|"), b);
  }
  const budget = [...newest.values()];
  const budgetRows = budget
    .filter((b) => level(b) === "city" && !EXCLUDED_COUNTRIES.has(b.country_name!))
    .map((b) => ({
      month: month(b), country: b.country_name!, city: b.city_name!, segment: b.city_segment ?? "Needs data",
      gmv: num(b.gmv_ba), ...ratios(b),
    }));
  // Country rows (GLOBAL = total) and segment rows carry their own targets.
  const budgetCountry = budget
    .filter((b) => level(b) === "country" && !EXCLUDED_COUNTRIES.has(b.country_name!))
    .map((b) => ({ month: month(b), country: b.country_name!, gmv: num(b.gmv_ba), ...ratios(b) }));
  const budgetSegment = budget
    .filter((b) => level(b) === "segment")
    .map((b) => ({ month: month(b), segment: (b.city_segment || b.final_segment || "").trim(), gmv: num(b.gmv_ba), ...ratios(b) }))
    .filter((b) => b.segment);
  // Make sure budget-only cities exist in the index too.
  for (const b of budgetRows) cityIdx(b.country, b.city);

  const asOf = rows.reduce((m, r) => (String(r[0]) > m ? String(r[0]) : m), "");
  return { generatedAt: s.at, asOf, budgetAt: s.budgetAt ?? s.at, cities, units, rows, budget: budgetRows, budgetCountry, budgetSegment };
}

const lastDay = (rows: Row[]) => rows.reduce((m, r) => (r.day! > m ? r.day! : m), "");
const minusDays = (day: string, n: number) => {
  const d = new Date(day + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
};

async function load(prev: State | null): Promise<State> {
  const t0 = Date.now();
  // Incremental: only re-read the last few days when we already have data.
  const last = prev ? lastDay(prev.recent) : "";
  const from = last ? [minusDays(last, RELOAD_DAYS - 1), RECENT_START].sort().reverse()[0] : RECENT_START;

  // Independent queries run in parallel on the warehouse.
  // History only grows when a new month starts: then just the missing month is fetched.
  const histTo = historyEnd();
  const prevHistTo = prev ? prev.histTo ?? "2025-12-01" : HISTORY_START;
  const histFrom = prevHistTo < histTo ? prevHistTo : null;
  const [newHist, fresh, budget] = await Promise.all([
    histFrom ? runQuery(`history from ${histFrom}`, dailySql(`DATE'${histFrom}'`, `DATE'${histTo}'`)) : Promise.resolve([]),
    runQuery(`recent from ${from}`, dailySql(`DATE'${from}'`, "current_date()")),
    runQuery("budget", readSql("budget.sql")),
  ]);
  const recent = [...(prev?.recent.filter((r) => r.day! < from) ?? []), ...fresh];
  console.log(`data ${prev ? "incremental" : "full"} load done in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  const hist = [...(prev?.hist ?? []), ...newHist];
  return { version: STATE_VERSION, at: new Date().toISOString(), hist, histTo, recent, budget, budgetAt: new Date().toISOString() };
}

function refresh() {
  if (inflight) return inflight;
  loadingSince = Date.now();
  inflight = load(state)
    .then(async (s) => {
      state = s;
      payload = buildPayload(s);
      lastError = null;
      await writeSnapshot(s);
    })
    .catch((err) => {
      lastError = { at: Date.now(), message: err instanceof Error ? err.message : "Data load failed" };
      console.error("data load failed:", lastError.message);
    })
    .finally(() => { inflight = null; loadingSince = null; });
  return inflight;
}

// Page loads never wait for Databricks: they get whatever is loaded, and refreshes run on a timer.
dataRouter.get("/api/data", (_req, res) => {
  if (payload) return res.json(payload);
  if (lastError && !inflight) {
    if (Date.now() - lastError.at > 30_000) refresh(); // retry, but not on every poll
    return res.status(502).json({ error: lastError.message });
  }
  res.status(202).json({
    status: "loading",
    seconds: loadingSince ? Math.round((Date.now() - loadingSince) / 1000) : 0,
    running: [...running.entries()].map(([label, t]) => `${label} (${Math.round((Date.now() - t) / 1000)}s)`),
    finished,
  });
});

// Debug view of the loader: what is running, what finished, the last error.
dataRouter.get("/api/status", (_req, res) => {
  res.json({
    loaded: payload !== null,
    dataAt: state?.at ?? null,
    loadingSeconds: loadingSince ? Math.round((Date.now() - loadingSince) / 1000) : null,
    running: [...running.entries()].map(([label, t]) => ({ label, seconds: Math.round((Date.now() - t) / 1000) })),
    finished,
    lastError,
    snapshot: snapshotEnabled(),
    budget: state && {
      readAt: state.budgetAt ?? state.at,
      rows: state.budget.length,
      countryRowsWithBa: state.budget.filter((b) => (b.aggregation ?? "city") === "country" && b.ba_total_spend != null && b.ba_total_spend !== "").length,
    },
  });
});

// Re-reads only the budget table (a few seconds), e.g. after the budget sheet and its load notebook were updated.
async function reloadBudget(label: string) {
  if (!state) throw new Error("Data is still loading");
  const budget = await runQuery(label, readSql("budget.sql"));
  state = { ...state, budget, budgetAt: new Date().toISOString() };
  payload = buildPayload(state);
  void writeSnapshot(state);
  return budget;
}
dataRouter.post("/api/refresh-budget", async (_req, res) => {
  try {
    const budget = await reloadBudget("budget (manual)");
    res.json({ ok: true, rows: budget.length });
  } catch (err) {
    res.status(err instanceof Error && err.message.includes("loading") ? 409 : 502).json({ error: err instanceof Error ? err.message : "Budget refresh failed" });
  }
});

// Most recent scheduled refresh time at or before `now`.
function lastScheduled(now = new Date()) {
  const t = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), REFRESH_HOUR_UTC));
  if (t > now) t.setUTCDate(t.getUTCDate() - 1);
  return t;
}

function scheduleDaily() {
  const next = lastScheduled();
  next.setUTCDate(next.getUTCDate() + 1);
  setTimeout(async () => {
    await refresh();
    scheduleDaily();
  }, next.getTime() - Date.now()).unref();
  console.log(`next refresh at ${next.toISOString()}`);
}

async function start() {
  const snap = await readSnapshot<State>();
  if (snap?.version === STATE_VERSION) {
    state = snap;
    payload = buildPayload(snap);
    console.log(`served snapshot from ${snap.at}`);
  }
  // Skip the big startup query when the snapshot already has today's refresh, but always re-read the budget
  // (a few seconds): targets are edited more often than the daily refresh.
  if (!state || new Date(state.at) < lastScheduled()) await refresh();
  else reloadBudget("budget (startup)").catch((e) => console.error("budget reload failed:", e instanceof Error ? e.message : e));
  scheduleDaily();
}

if (!snapshotEnabled()) console.log("S3_BUCKET not set: data is only kept in memory");
void start();
