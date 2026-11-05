// Data model + aggregation. All dates are 'YYYY-MM-DD' strings (UTC order_created_date).

/** Daily columns after [day, unit]; the server writes them in this order. */
export const AGG_KEYS = ["gmv", "bolt", "act", "react", "eng", "cp1", "cp2", "ba", "elc", "mkt", "am", "churn", "bdm", "p1", "plus"] as const;
export type AggKey = (typeof AGG_KEYS)[number];
export type Agg = Record<AggKey, number>;

/** Budget ratios (share of GMV). A missing key means that row has no target for it. */
export type Ratios = Partial<Record<"act" | "react" | "eng" | "bolt" | "ba" | "elc" | "mkt" | "am" | "churn" | "bdm" | "p1" | "plus", number>>;

export type Payload = {
  generatedAt: string;
  asOf: string;
  /** When the budget (targets) was last read from Databricks. */
  budgetAt?: string;
  cities: { country: string; city: string }[];
  // A unit is one (city, zone cluster) pair: [cityIdx, cluster]
  units: [number, string][];
  // [day, unitIdx, ...AGG_KEYS values]
  rows: [string, number, ...number[]][];
  // City / country (GLOBAL = total) / segment budgets; gmv is the GMV target in EUR.
  budget: ({ month: string; country: string; city: string; segment: string; gmv: number } & Ratios)[];
  budgetCountry: ({ month: string; country: string; gmv: number } & Ratios)[];
  budgetSegment: ({ month: string; segment: string; gmv: number } & Ratios)[];
};

export const emptyAgg = (): Agg => ({
  gmv: 0, bolt: 0, act: 0, react: 0, eng: 0, cp1: 0, cp2: 0, ba: 0, elc: 0, mkt: 0, am: 0, churn: 0, bdm: 0, p1: 0, plus: 0,
});
export const addAgg = (a: Agg, b: Agg) => { for (const k of AGG_KEYS) a[k] += b[k]; };
export const scaleAgg = (a: Agg, k: number): Agg => {
  const o = emptyAgg();
  for (const key of AGG_KEYS) o[key] = a[key] * k;
  return o;
};

export type Unit = "pct" | "eur";
export type MetricKey = AggKey | "ulc";

export const METRICS: { key: MetricKey; label: string; hasTarget: boolean }[] = [
  { key: "gmv", label: "GMV", hasTarget: true },
  { key: "bolt", label: "Bolt Spend", hasTarget: true },
  { key: "ba", label: "Bolt Spend (BA)", hasTarget: true },
  { key: "cp1", label: "CP L1", hasTarget: false },
  { key: "cp2", label: "CP L2", hasTarget: false },
  { key: "ulc", label: "ULC Spend", hasTarget: true },
  { key: "act", label: "Activation Spend", hasTarget: true },
  { key: "react", label: "Reactivation Spend", hasTarget: true },
  { key: "eng", label: "Engagement Spend", hasTarget: true },
  { key: "elc", label: "ELC", hasTarget: true },
  { key: "mkt", label: "Marketing", hasTarget: true },
  { key: "am", label: "AM", hasTarget: true },
  { key: "churn", label: "Churn", hasTarget: true },
  { key: "bdm", label: "BDM 3P", hasTarget: true },
  { key: "p1", label: "1P (Bolt Market)", hasTarget: true },
  { key: "plus", label: "Bolt Plus", hasTarget: true },
];
export const metricDef = (k: MetricKey) => METRICS.find((m) => m.key === k)!;
/** All metrics, in table order; the monthly tables show them in two groups (ELC onwards is the spend breakdown). */
export const ALL_METRICS: MetricKey[] = METRICS.map((m) => m.key);
export const PERF_METRICS: MetricKey[] = ALL_METRICS.slice(0, ALL_METRICS.indexOf("elc"));
export const SPEND_METRICS: MetricKey[] = ALL_METRICS.slice(ALL_METRICS.indexOf("elc"));

// ULC Bolt spend = activation + reactivation + engagement (matches the budget table).
export const rawValue = (a: Agg, k: MetricKey): number =>
  k === "ulc" ? a.act + a.react + a.eng : a[k];

/** Displayed value: GMV is always EUR; other metrics are % of GMV or EUR. */
export function metricValue(a: Agg, k: MetricKey, unit: Unit): number | null {
  const v = rawValue(a, k);
  if (k === "gmv" || unit === "eur") return v;
  return a.gmv > 0 ? v / a.gmv : null;
}

/** Change vs a comparison value: relative % for EUR values, percentage points for ratios. */
export function change(cur: number | null, prev: number | null, k: MetricKey, unit: Unit) {
  if (cur == null || prev == null) return null;
  if (k === "gmv" || unit === "eur") return prev === 0 ? null : (cur - prev) / Math.abs(prev);
  return (cur - prev) * 100; // percentage points
}

// ---- dates ----
export const parse = (s: string) => new Date(s + "T00:00:00Z");
export const fmt = (d: Date) => d.toISOString().slice(0, 10);
export const daysInMonth = (ym: string) => {
  const [y, m] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
};
export const monthEnd = (ym: string) => `${ym}-${String(daysInMonth(ym)).padStart(2, "0")}`;
export const shiftYear = (ym: string, n: number) => `${Number(ym.slice(0, 4)) + n}${ym.slice(4)}`;
export const prevMonth = (ym: string) => {
  const [y, m] = ym.split("-").map(Number);
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, "0")}`;
};
export const mondayOf = (s: string) => {
  const d = parse(s);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return fmt(d);
};
/** The same calendar day `months` months away (clamped: 31 Mar -> 28 Feb, 29 Feb -> 28 Feb the year after). */
export const sameDayShift = (s: string, months: number) => {
  const [y, m, d] = s.split("-").map(Number);
  const first = new Date(Date.UTC(y, m - 1 + months, 1));
  const dim = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  return fmt(new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), Math.min(d, dim))));
};
export const addDays = (s: string, n: number) => {
  const d = parse(s);
  d.setUTCDate(d.getUTCDate() + n);
  return fmt(d);
};

// ---- segments per month, units, filters ----
// A city's segment can change from month to month, and each day's numbers count under the
// segment of that day's month. So aggregation works on "segmented units": a (city, zone cluster)
// unit together with the segment it had in that month. Targets work on "segmented cities".

/** Segment of a city in a month: that month's budget, else the latest month with a budget. */
export function segmentResolver(p: Payload) {
  const byMonth = new Map<string, string>();
  const latest = new Map<number, { month: string; segment: string }>();
  const index = new Map(p.cities.map((c, i) => [`${c.country}|${c.city}`, i]));
  for (const b of p.budget) {
    const i = index.get(`${b.country}|${b.city}`);
    if (i === undefined) continue;
    byMonth.set(`${b.month}|${i}`, b.segment);
    const l = latest.get(i);
    if (!l || b.month > l.month) latest.set(i, b);
  }
  return (month: string, cityIdx: number) =>
    byMonth.get(`${month}|${cityIdx}`) ?? latest.get(cityIdx)?.segment ?? "Unmapped";
}

export type UnitMeta = { unit: number; cityIdx: number; vcity: number; country: string; city: string; segment: string; cluster: string };

/** Registry of segmented units / cities, filled while aggregating. */
export class SegIndex {
  units: UnitMeta[] = [];
  private unitKeys = new Map<string, number>();
  private cityKeys = new Map<string, number>();
  private segOf: (month: string, cityIdx: number) => string;
  constructor(private p: Payload) { this.segOf = segmentResolver(p); }

  segment(month: string, cityIdx: number) { return this.segOf(month, cityIdx); }

  vcity(cityIdx: number, segment: string) {
    const k = `${cityIdx}|${segment}`;
    let i = this.cityKeys.get(k);
    if (i === undefined) { i = this.cityKeys.size; this.cityKeys.set(k, i); }
    return i;
  }

  private maps = new Map<string, number[]>();
  /** unit index -> segmented unit index, for one month's segments (cached across calls). */
  unitMap(month: string): number[] {
    let m = this.maps.get(month);
    if (!m) { m = []; this.maps.set(month, m); }
    return m;
  }

  get(unit: number, segment: string) {
    const k = `${unit}|${segment}`;
    let i = this.unitKeys.get(k);
    if (i === undefined) {
      const [cityIdx, cluster] = this.p.units[unit];
      const c = this.p.cities[cityIdx];
      i = this.units.length;
      this.unitKeys.set(k, i);
      this.units.push({ unit, cityIdx, vcity: this.vcity(cityIdx, segment), country: c.country, city: c.city, segment, cluster });
    }
    return i;
  }
}

/**
 * Add rows with day in [from, to] into `out` (indexed by segmented unit), times `k`.
 * `segMonth` picks whose segment applies: a fixed month, or (default) each day's own month.
 */
export function aggregateInto(out: Agg[], p: Payload, ix: SegIndex, from: string, to: string, k = 1, segMonth?: string) {
  // Only the days in [from, to] are visited (rows are indexed by day), not every row.
  const { rows, days, starts } = dayIndex(p);
  let lo = 0, hi = days.length;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (days[mid] < from) lo = mid + 1; else hi = mid; }
  for (let d = lo; d < days.length && days[d] <= to; d++) {
    const month = segMonth ?? days[d].slice(0, 7);
    const map = ix.unitMap(month);
    for (let i = starts[d]; i < starts[d + 1]; i++) {
      const r = rows[i];
      const u = r[1];
      let vu = map[u];
      if (vu === undefined) vu = map[u] = ix.get(u, ix.segment(month, p.units[u][0]));
      const a = (out[vu] ??= emptyAgg());
      for (let j = 0; j < AGG_KEYS.length; j++) a[AGG_KEYS[j]] += (r[j + 2] as number) * k;
    }
  }
}

type DayIndex = { rows: Payload["rows"]; days: string[]; starts: number[] };
const dayIndexCache = new WeakMap<Payload, DayIndex>();
/** Rows sorted by day, with where each day starts. Built once per payload. */
function dayIndex(p: Payload): DayIndex {
  let ix = dayIndexCache.get(p);
  if (ix) return ix;
  let sorted = true;
  for (let i = 1; i < p.rows.length; i++) if (p.rows[i][0] < p.rows[i - 1][0]) { sorted = false; break; }
  const rows = sorted ? p.rows : [...p.rows].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const days: string[] = [], starts: number[] = [];
  for (let i = 0; i < rows.length; i++) if (days[days.length - 1] !== rows[i][0]) { days.push(rows[i][0]); starts.push(i); }
  starts.push(rows.length);
  ix = { rows, days, starts };
  dayIndexCache.set(p, ix);
  return ix;
}

/**
 * Targets. EUR target = ratio x the row's own GMV target. Each level comes from its own budget rows:
 * city rows (per segmented city), country rows (GLOBAL = total) and segment rows.
 */
export type TargetSet = {
  city: Agg[]; country: Map<string, Agg>; segment: Map<string, Agg>;
  /** Metrics a country / segment row has no target for (blank budget cell), keyed "country|X" / "segment|x". A blank is not a 0 target. */
  missing: Map<string, Set<MetricKey>>;
};
export const emptyTargets = (): TargetSet => ({ city: [], country: new Map(), segment: new Map(), missing: new Map() });

const RATIO_KEYS = ["act", "react", "eng", "bolt", "ba", "elc", "mkt", "am", "churn", "bdm", "p1", "plus"] as const;
function addTarget(a: Agg, b: { gmv: number } & Ratios, share: number) {
  a.gmv += b.gmv * share;
  for (const k of RATIO_KEYS) if (b[k] !== undefined) a[k] += b[k]! * b.gmv * share;
}
const getOrAdd = <K,>(m: Map<K, Agg>, k: K) => m.get(k) ?? m.set(k, emptyAgg()).get(k)!;
export const segKey = (s: string) => s.trim().toLowerCase();

/** Add a month's targets into `t`, scaled by `share` (the part of the month elapsed, or 1). */
export function targetsInto(t: TargetSet, p: Payload, ix: SegIndex, month: string, share: number) {
  const index = new Map(p.cities.map((c, i) => [`${c.country}|${c.city}`, i]));
  for (const b of p.budget) {
    if (b.month !== month) continue;
    const i = index.get(`${b.country}|${b.city}`);
    if (i === undefined) continue;
    // City budgets only carry spend targets for activation / reactivation / engagement.
    addTarget((t.city[ix.vcity(i, ix.segment(month, i))] ??= emptyAgg()), { gmv: b.gmv, act: b.act, react: b.react, eng: b.eng }, share);
  }
  const note = (key: string, b: { gmv: number } & Ratios) => {
    const m = t.missing.get(key) ?? t.missing.set(key, new Set()).get(key)!;
    for (const k of RATIO_KEYS) if (b[k] === undefined) { m.add(k); if (k === "act" || k === "react" || k === "eng") m.add("ulc"); }
    if (!(b.gmv > 0)) m.add("gmv");
  };
  for (const b of p.budgetCountry) if (b.month === month) { addTarget(getOrAdd(t.country, b.country), b, share); note(`country|${b.country}`, b); }
  for (const b of p.budgetSegment) if (b.month === month) { addTarget(getOrAdd(t.segment, segKey(b.segment)), b, share); note(`segment|${segKey(b.segment)}`, b); }
}

/** Metrics a city-sum target covers; country rows cover everything, segment rows add Bolt spend. */
const CITY_TARGET: MetricKey[] = ["gmv", "ulc", "act", "react", "eng"];
const SEGMENT_TARGET: MetricKey[] = [...CITY_TARGET, "bolt"];
const ALL_TARGET: MetricKey[] = METRICS.filter((m) => m.hasTarget).map((m) => m.key);
export type NodeTarget = { agg: Agg; has: ReadonlySet<MetricKey> };
export type TargetMode = "main" | "segment" | "country";

/**
 * Target of a table row, or null. Country rows (and GLOBAL for the total) are used while no city/segment
 * filter narrows them; segment rows in the segment table while no country/city filter does. Otherwise
 * targets are summed over the row's cities (activation / reactivation / engagement / ULC / GMV only).
 */
export function nodeTarget(mode: TargetMode, n: Node, t: TargetSet, f: Filters): NodeTarget | null {
  const sum = (aggs: (Agg | undefined)[]) => {
    const out = emptyAgg();
    for (const a of aggs) if (a) addAgg(out, a);
    return out;
  };
  // Metrics of `base` that none of the budget rows `keys` leave blank.
  const hasOf = (base: MetricKey[], keys: string[]): ReadonlySet<MetricKey> =>
    new Set(base.filter((k) => keys.every((key) => !t.missing.get(key)?.has(k))));
  const wholeCountries = !f.cities.length && !f.segments.length;
  const noSplit = !f.countries.length && !f.cities.length;
  if (mode !== "segment" && wholeCountries) {
    if (n.level === "country") {
      const c = t.country.get(n.label);
      if (c) return { agg: c, has: hasOf(ALL_TARGET, [`country|${n.label}`]) };
    } else if (n.level === "total") {
      const names = f.countries.length ? f.countries : ["GLOBAL"];
      const rows = names.map((c) => t.country.get(c));
      if (rows.every(Boolean)) return { agg: sum(rows), has: hasOf(ALL_TARGET, names.map((c) => `country|${c}`)) };
    }
  }
  if (mode === "segment" && noSplit) {
    if (n.level === "segment") {
      const s = t.segment.get(segKey(n.label));
      if (s) return { agg: s, has: hasOf(SEGMENT_TARGET, [`segment|${segKey(n.label)}`]) };
    } else if (n.level === "total") {
      if (!f.segments.length) {
        const g = t.country.get("GLOBAL");
        if (g) return { agg: g, has: hasOf(ALL_TARGET, ["country|GLOBAL"]) };
      } else {
        const rows = f.segments.map((x) => t.segment.get(segKey(x)));
        if (rows.every(Boolean)) return { agg: sum(rows), has: hasOf(SEGMENT_TARGET, f.segments.map((x) => `segment|${segKey(x)}`)) };
      }
    }
  }
  if (!n.targetable) return null;
  return { agg: sumIdx(t.city, n.cities), has: new Set(CITY_TARGET) };
}

/** Target value (ratio or EUR) for a metric on a row, or null when that row has none for it. */
export function targetValue(t: NodeTarget | null, k: MetricKey, unit: Unit): number | null {
  if (!t || !t.has.has(k) || !(t.agg.gmv > 0)) return null;
  return metricValue(t.agg, k, unit);
}

export type Filters = { countries: string[]; cities: string[]; segments: string[] };
export const noFilters: Filters = { countries: [], cities: [], segments: [] };

/** Segmented units passing the filters (an empty list means "all"). */
export function activeUnits(meta: UnitMeta[], f: Filters): number[] {
  const out: number[] = [];
  meta.forEach((m, i) => {
    if (f.countries.length && !f.countries.includes(m.country)) return;
    if (f.cities.length && !f.cities.includes(`${m.country}|${m.city}`)) return;
    if (f.segments.length && !f.segments.includes(m.segment)) return;
    out.push(i);
  });
  return out;
}

export type Level = "country" | "segment" | "city" | "cluster";
export type Node = {
  id: string; label: string; level: "total" | Level; depth: number;
  children: Node[]; units: number[]; cities: number[];
  // Targets exist per city, so only nodes made of whole cities have one (not cluster splits).
  targetable: boolean;
};

export const SEGMENT_ORDER = ["Monetise", "Grow Share", "Preparation", "Maintain Share", "Non Priority", "Launch", "Needs data", "Unmapped"];
const segRank = (l: string) => { const i = SEGMENT_ORDER.findIndex((s) => s.toLowerCase() === l.toLowerCase()); return i < 0 ? 99 : i; };

const labelOf = (m: UnitMeta, l: Level) =>
  l === "country" ? m.country : l === "segment" ? m.segment : l === "city" ? m.city : m.cluster;

export function buildTree(meta: UnitMeta[], active: number[], levels: Level[], rootLabel = "TOTAL"): Node {
  const make = (id: string, label: string, level: Node["level"], depth: number, units: number[], targetable: boolean): Node => {
    const node: Node = { id, label, level, depth, children: [], units, cities: [...new Set(units.map((u) => meta[u].vcity))], targetable };
    const next = levels[depth];
    if (!next) return node;
    const groups = new Map<string, number[]>();
    for (const u of units) {
      const k = labelOf(meta[u], next);
      (groups.get(k) ?? groups.set(k, []).get(k)!).push(u);
    }
    // A city with a single zone cluster has nothing to split, so don't add a redundant row.
    if (next === "cluster" && groups.size === 1 && level === "city") return node;
    const keys = [...groups.keys()].sort((a, b) =>
      next === "segment" ? segRank(a) - segRank(b) || a.localeCompare(b)
        : a === "Unclustered" ? 1 : b === "Unclustered" ? -1 : a.localeCompare(b));
    node.children = keys.map((k) =>
      make(`${id}/${k}`, k, next, depth + 1, groups.get(k)!, targetable && next !== "cluster"));
    return node;
  };
  return make("total", rootLabel, "total", 0, active, true);
}

export const sumIdx = (per: Agg[], idx: number[]): Agg => {
  const a = emptyAgg();
  for (const i of idx) if (per[i]) addAgg(a, per[i]);
  return a;
};

export const fmtValue = (v: number | null, k: MetricKey, unit: Unit) => {
  if (v == null || !isFinite(v)) return "–";
  if (k === "gmv" || unit === "eur") {
    const a = Math.abs(v);
    return a >= 1e6 ? `${(v / 1e6).toFixed(2)}M` : a >= 1e3 ? `${(v / 1e3).toFixed(1)}K` : v.toFixed(0);
  }
  return `${(v * 100).toFixed(2)}%`;
};
export const fmtDelta = (v: number | null, k: MetricKey, unit: Unit) => {
  if (v == null || !isFinite(v)) return "–";
  const sign = v > 0 ? "+" : "";
  return k === "gmv" || unit === "eur" ? `${sign}${(v * 100).toFixed(1)}%` : `${sign}${v.toFixed(2)}pp`;
};

/** Metric definitions, shown on the definitions section of the page (and mirrored in the README). */
const AM_OBJECTIVES = "provider_campaign_ retail_growth, manual_churn_prevention, locations, retail_profitability, obligations_commitments, sales_benefit, exclusivity_retention, commission_increase, untested, marketing_3rd_party_partnership, exclusivity_gain, profit_generator, exclusivity_prevention";
export const METRIC_DEFS: { label: string; definition: string; objectives: string; source: string; target: string }[] = [
  { label: "GMV", definition: "Order GMV (EUR) of delivered orders, by local order date.", objectives: "", source: "dim_order_delivery.order_gmv_eur", target: "gmv_ba" },
  { label: "Bolt Spend", definition: "GA Bolt spend incl. VAT: bolt_spend of delivered orders; on 1P (store_1p) orders also provider_spend, because Bolt carries it.", objectives: "all", source: "etl_delivery_campaign_order_metrics.bolt_spend (+ provider_spend on 1P)", target: "total_bolt_spend (country and segment rows)" },
  { label: "Bolt Spend (BA)", definition: "Demand incentives booked on the order itself (BA number), delivered orders.", objectives: "", source: "dim_order_delivery.order_demand_incentives_eur", target: "ba_total_spend (country rows)" },
  { label: "CP L1", definition: "Contribution profit (EUR) over every order state, so failed orders' negative CP counts. Matches the Delivery Business Review SSOT.", objectives: "", source: "dim_order_delivery.contribution_profit_eur", target: "none" },
  { label: "CP L2", definition: "CP L1 minus order demand incentives.", objectives: "", source: "contribution_profit_eur - order_demand_incentives_eur", target: "none" },
  { label: "ULC Spend", definition: "User-led campaign Bolt spend = Activation + Reactivation + Engagement.", objectives: "activation, reactivation, engagement (+ sp_ variants)", source: "see the three below", target: "act + react + eng targets (= ulc_bolt_spend)" },
  { label: "Activation", definition: "Bolt spend of activation campaigns.", objectives: "activation, sp_activation", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "activation_spend" },
  { label: "Reactivation", definition: "Bolt spend of reactivation campaigns.", objectives: "reactivation, sp_reactivation", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "reactivation_spend" },
  { label: "Engagement", definition: "Bolt spend of engagement campaigns.", objectives: "engagement, sp_engagement", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "engagement_spend" },
  { label: "ELC", definition: "Bolt spend of ELC merchant campaigns.", objectives: "provider_campaign_elc_merchant", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "elc (country rows)" },
  { label: "Marketing", definition: "Bolt spend of marketing campaigns.", objectives: "provider_campaign_marketing, provider_marketing_calendar_global_event", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "marketing (country rows)" },
  { label: "AM", definition: "Bolt spend of account-management campaigns.", objectives: AM_OBJECTIVES, source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "am (country rows)" },
  { label: "Churn", definition: "Bolt spend of churn-prevention campaigns.", objectives: "provider_campaign_churn_prevention", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "churn (country rows)" },
  { label: "BDM 3P", definition: "AM + Marketing Bolt spend on 3P orders (delivery_vertical store_3p_ent and store_3p_mm_smb).", objectives: "the AM and Marketing objectives above", source: "etl_delivery_campaign_order_metrics.bolt_spend, dim_order_delivery.delivery_vertical", target: "bdm_3p (country rows)" },
  { label: "1P (Bolt Market)", definition: "Bolt spend + provider spend of Bolt Market campaigns.", objectives: "any objective containing bolt_market", source: "etl_delivery_campaign_order_metrics (bolt_spend + provider_spend)", target: "store_1p (country rows)" },
  { label: "Bolt Plus", definition: "Bolt spend of Bolt Plus campaigns.", objectives: "bolt_plus_campaign, bolt_plus_tested, bolt_plus_untested", source: "etl_delivery_campaign_order_metrics.bolt_spend", target: "bolt_plus (country rows)" },
];

/** What each table column means, shown under "Metric and status definitions" (and mirrored in the README). */
export const COLUMN_DEFS: { column: string; definition: string }[] = [
  { column: "% of GMV (or € with the € switch)", definition: "The row's own value: spend divided by the row's own GMV. GMV, CP L1 and CP L2 follow the same switch." },
  { column: "MoM / YoY", definition: "Change vs the same days of the previous month / the same month last year (or the full month in run-rate view). Percentage points for % values, relative % for GMV and EUR values. Each month is compared on that month's segments." },
  { column: "vs Target", definition: "Actual minus target, in the same unit (pp for % of GMV, relative % for GMV and EUR). Targets come from the budget table, pro-rated for a month in progress. A dash means the row has no target (or the budget cell is blank)." },
  { column: "% of global GMV", definition: "The row's spend divided by the GMV of everything shown (all countries and segments, or the filtered selection). It is how many points of the total spend rate the row adds, so country rows add up to the TOTAL row." },
  { column: "% of country GMV", definition: "The row's spend divided by the GMV of its country (country table only). A country row shows its own spend rate; a segment, city or cluster row shows how many points of its country's rate it adds, so the rows under a country add up to the country row." },
  { column: "Status", definition: "Red / yellow / green: the worst of GMV vs target, Bolt spend ratio vs target and GMV YoY (thresholds below)." },
];

// ---------- status (red / yellow / green) ----------
export type Light = "green" | "yellow" | "red";
/** Thresholds in one place; the page prints them under the Insights box. */
export const STATUS_RULES = {
  // GMV vs target, relative: green at or above, yellow at or above, else red.
  gmv: { green: -0.02, yellow: -0.1 },
  // Bolt spend as % of GMV vs the target ratio, relative overspend: green up to, yellow up to, else red.
  bolt: { green: 0.05, yellow: 0.15 },
  // GMV year on year: green at or above, yellow at or above, else red.
  yoy: { green: 0.1, yellow: 0 },
};
export type Signal = { light: Light | null; value: number | null };
export type Status = { light: Light | null; gmv: Signal; bolt: Signal; yoy: Signal };

const RANK: Record<Light, number> = { green: 0, yellow: 1, red: 2 };
const none: Signal = { light: null, value: null };

/** Status of a row: the worst of GMV vs target, Bolt spend vs target and YoY growth (the ones that exist). */
export function rowStatus(cur: Agg, yoy: Agg, t: NodeTarget | null): Status {
  const r = STATUS_RULES;
  let gmv = none, bolt = none, yo = none;
  if (cur.gmv > 0 && t && t.has.has("gmv") && t.agg.gmv > 0) {
    const v = cur.gmv / t.agg.gmv - 1;
    gmv = { value: v, light: v >= r.gmv.green ? "green" : v >= r.gmv.yellow ? "yellow" : "red" };
  }
  if (cur.gmv > 0 && t && t.has.has("bolt") && t.agg.gmv > 0 && t.agg.bolt > 0) {
    const v = cur.bolt / cur.gmv / (t.agg.bolt / t.agg.gmv) - 1;
    bolt = { value: v, light: v <= r.bolt.green ? "green" : v <= r.bolt.yellow ? "yellow" : "red" };
  }
  if (cur.gmv > 0 && yoy.gmv > 0) {
    const v = cur.gmv / yoy.gmv - 1;
    yo = { value: v, light: v >= r.yoy.green ? "green" : v >= r.yoy.yellow ? "yellow" : "red" };
  }
  const lights = [gmv, bolt, yo].map((x) => x.light).filter((x): x is Light => x !== null);
  const light = lights.length ? lights.reduce((a, b) => (RANK[b] > RANK[a] ? b : a)) : null;
  return { light, gmv, bolt, yoy: yo };
}
