import { useEffect, useMemo, useRef, useState } from "react";
import { Typography } from "@bolteu/clay-react";
import {
  METRICS, PERF_METRICS, SPEND_METRICS, METRIC_DEFS, Agg, Filters, Level, MetricKey, Node, Payload, SegIndex, TargetMode, TargetSet, Unit, UnitMeta,
  activeUnits, addDays, aggregateInto, buildTree, change, daysInMonth, emptyTargets, fmtDelta, fmtValue, metricDef,
  Light, STATUS_RULES, Signal, Status, rowStatus,
  metricValue, mondayOf, monthEnd, nodeTarget, noFilters, prevMonth, SEGMENT_ORDER, shiftYear, sumIdx, targetValue, targetsInto,
} from "../lib/model";

type Tab = "monthly" | "weekly" | "daily";
type Basis = "same" | "run";
// First month offered; later months appear automatically as data arrives.
const FIRST_MONTH = "2026-10";
const TREND_START = "2026-10-01";

/** Months from FIRST_MONTH to the month of the latest data day, newest first. */
function availableMonths(asOf: string): string[] {
  const out: string[] = [];
  for (let m = FIRST_MONTH; m <= asOf.slice(0, 7); ) {
    out.unshift(m);
    const [y, mo] = m.split("-").map(Number);
    m = mo === 12 ? `${y + 1}-01` : `${y}-${String(mo + 1).padStart(2, "0")}`;
  }
  return out.length ? out : [FIRST_MONTH];
}
const MAIN_LEVELS: Level[] = ["country", "segment", "city", "cluster"];

// ---------- shared UI ----------
const border = "1px solid var(--color-border-separator)";
const th: React.CSSProperties = {
  position: "sticky", top: 0, background: "var(--color-layer-floor-2)", padding: "6px 10px",
  textAlign: "right", whiteSpace: "nowrap", borderBottom: border, fontWeight: 600, zIndex: 2,
};
const td: React.CSSProperties = { padding: "4px 10px", textAlign: "right", whiteSpace: "nowrap", borderBottom: border };
const linkBtn: React.CSSProperties = { background: "none", border: "none", cursor: "pointer", color: "var(--color-content-action-primary)", font: "inherit", padding: 0 };
const control: React.CSSProperties = { padding: "6px 10px", borderRadius: 8, border, font: "inherit", background: "var(--color-layer-surface)", color: "var(--color-content-primary)" };
const row: React.CSSProperties = { display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" };

function Seg<T extends string>({ value, options, onChange }: { value: T; options: [T, string][]; onChange: (v: T) => void }) {
  return (
    <div style={{ display: "inline-flex", border, borderRadius: 8, overflow: "hidden" }}>
      {options.map(([v, label]) => (
        <button key={v} onClick={() => onChange(v)} style={{
          padding: "6px 14px", border: "none", cursor: "pointer", font: "inherit",
          background: v === value ? "var(--color-bg-action-primary)" : "var(--color-layer-surface)",
          color: v === value ? "var(--color-content-primary-inverted)" : "var(--color-content-primary)",
        }}>{label}</button>
      ))}
    </div>
  );
}

function MultiSelect({ label, options, selected, onChange }: {
  label: string; options: [string, string][]; selected: string[]; onChange: (v: string[]) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent) => { if (!ref.current?.contains(e.target as globalThis.Node)) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);
  const shown = options.filter(([, l]) => l.toLowerCase().includes(query.toLowerCase()));
  const toggle = (v: string) => onChange(selected.includes(v) ? selected.filter((x) => x !== v) : [...selected, v]);
  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button onClick={() => setOpen((o) => !o)} style={{ ...control, cursor: "pointer" }}>
        {label}: {selected.length === 0 ? "All" : selected.length === 1 ? options.find(([v]) => v === selected[0])?.[1] ?? "1 selected" : `${selected.length} selected`} ▾
      </button>
      {open && (
        <div style={{
          position: "absolute", top: "calc(100% + 4px)", left: 0, zIndex: 20, minWidth: 220, maxHeight: 320, overflow: "auto",
          background: "var(--color-layer-floor-1)", border, borderRadius: 8, padding: 8, boxShadow: "0 4px 16px rgba(0,0,0,.15)",
        }}>
          {options.length > 10 && (
            <input autoFocus placeholder="Search…" value={query} onChange={(e) => setQuery(e.target.value)} style={{ ...control, width: "100%", boxSizing: "border-box", marginBottom: 6 }} />
          )}
          <button onClick={() => onChange([])} style={{ ...linkBtn, marginBottom: 6 }}>Clear (all)</button>
          {shown.map(([v, l]) => (
            <label key={v} style={{ display: "flex", gap: 8, padding: "3px 0", cursor: "pointer", whiteSpace: "nowrap" }}>
              <input type="checkbox" checked={selected.includes(v)} onChange={() => toggle(v)} />{l}
            </label>
          ))}
          {shown.length === 0 && <div className="text-secondary">No matches</div>}
        </div>
      )}
    </div>
  );
}

function DateInput({ label, value, min, max, onChange }: { label: string; value: string; min: string; max: string; onChange: (v: string) => void }) {
  return (
    <label style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
      {label}
      <input type="date" value={value} min={min} max={max} style={control}
        onChange={(e) => { const v = e.target.value; if (v && v >= min && v <= max) onChange(v); }} />
    </label>
  );
}

// positive = good for GMV/CP; for spend lines "good" is ambiguous, so only vs-target is toned.
function tone(v: number | null, k: MetricKey, kind: "delta" | "target"): string | undefined {
  if (v == null || Math.abs(v) < 1e-9) return undefined;
  const higherIsGood = k === "gmv" || k === "cp1" || k === "cp2";
  if (higherIsGood) return v > 0 ? "var(--color-content-positive-primary)" : "var(--color-content-danger-primary)";
  if (kind === "target") return v > 0 ? "var(--color-content-danger-primary)" : "var(--color-content-positive-primary)";
  return undefined;
}

/** Colour of a WoW / DoD change: GMV and CP up = green; spend up = red (more spend), down = green. */
function trendTone(v: number | null, k: MetricKey): string | undefined {
  if (v == null || Math.abs(v) < 1e-9) return undefined;
  const upIsGood = k === "gmv" || k === "cp1" || k === "cp2";
  return (v > 0) === upIsGood ? "var(--color-content-positive-primary)" : "var(--color-content-danger-primary)";
}

// ---------- status + insights ----------
const LIGHT_COLOR: Record<Light, string> = {
  green: "var(--color-content-positive-primary)",
  yellow: "var(--color-content-warning-primary, #d99a00)",
  red: "var(--color-content-danger-primary)",
};
const p0 = (v: number) => `${(v * 100).toFixed(0)}%`;
const pctSigned = (v: number) => `${v > 0 ? "+" : ""}${(v * 100).toFixed(1)}%`;

function StatusDot({ st }: { st: Status }) {
  if (!st.light) return <span className="text-secondary">–</span>;
  const part = (name: string, x: Signal) => `${name}: ${x.light ? `${pctSigned(x.value!)} (${x.light})` : "n/a"}`;
  const title = [`Status: ${st.light}`, part("GMV vs target", st.gmv), part("Bolt spend ratio vs target", st.bolt), part("GMV YoY", st.yoy)].join("\n");
  return <span role="img" aria-label={`status ${st.light}`} title={title}
    style={{ display: "inline-block", width: 12, height: 12, borderRadius: 6, background: LIGHT_COLOR[st.light] }} />;
}

function buildInsights(m: MonthModel, country: Node, seg: Node, filters: Filters) {
  const eur = (v: number) => `€${fmtValue(v, "gmv", "eur")}`;
  const evalNode = (mode: TargetMode, n: Node) => {
    const cur = sumIdx(m.cur, n.units), mom = sumIdx(m.mom, n.units), yoy = sumIdx(m.yoy, n.units);
    const tgt = nodeTarget(mode, n, m.tgt, filters);
    const boltTarget = targetValue(tgt, "bolt", "pct");
    const boltNow = metricValue(cur, "bolt", "pct");
    return { n, cur, mom, yoy, tgt, st: rowStatus(cur, yoy, tgt), boltNow, boltTarget,
      boltPp: boltNow != null && boltTarget != null ? (boltNow - boltTarget) * 100 : null };
  };
  const top = (xs: ReturnType<typeof evalNode>[], by: (x: ReturnType<typeof evalNode>) => number | null, dir: 1 | -1, k: number, keep: (v: number) => boolean) =>
    xs.map((x) => ({ x, v: by(x) })).filter((y): y is { x: ReturnType<typeof evalNode>; v: number } => y.v != null && keep(y.v))
      .sort((a, b) => dir * (a.v - b.v)).slice(0, k);

  const tot = evalNode("country", country);
  const countries = country.children.map((c) => evalNode("country", c)).filter((x) => x.cur.gmv > 0);
  const segments = seg.children.map((c) => evalNode("segment", c)).filter((x) => x.cur.gmv > 0);
  const counts: Record<Light, number> = { green: 0, yellow: 0, red: 0 };
  for (const c of countries) if (c.st.light) counts[c.st.light]++;

  const lines: string[] = [];
  const head = [`GMV ${eur(tot.cur.gmv)}`];
  if (tot.st.gmv.value != null) head.push(`${pctSigned(tot.st.gmv.value)} vs target`);
  if (tot.st.yoy.value != null) head.push(`${pctSigned(tot.st.yoy.value)} YoY`);
  let line = `Total: ${head.join(", ")}.`;
  if (tot.boltNow != null) {
    line += ` Bolt spend ${(tot.boltNow * 100).toFixed(2)}% of GMV`;
    line += tot.boltTarget != null ? ` (target ${(tot.boltTarget * 100).toFixed(2)}%, ${tot.boltPp! > 0 ? "+" : ""}${tot.boltPp!.toFixed(2)}pp).` : ".";
  }
  const cp1 = metricValue(tot.cur, "cp1", "pct"), cp1Mom = change(cp1, metricValue(tot.mom, "cp1", "pct"), "cp1", "pct");
  if (cp1 != null) line += ` CP L1 ${(cp1 * 100).toFixed(2)}% of GMV${cp1Mom != null ? ` (${cp1Mom > 0 ? "+" : ""}${cp1Mom.toFixed(2)}pp MoM)` : ""}.`;
  lines.push(line);

  const reds = countries.filter((c) => c.st.light === "red").sort((a, b) => b.cur.gmv - a.cur.gmv).map((c) => c.n.label);
  if (countries.some((c) => c.st.light)) {
    lines.push(`${counts.green} green, ${counts.yellow} yellow, ${counts.red} red of ${countries.length} countries.${reds.length ? ` Red: ${reds.slice(0, 6).join(", ")}${reds.length > 6 ? ` +${reds.length - 6}` : ""}.` : ""}`);
  }
  const below = top(countries, (x) => x.st.gmv.value, 1, 3, (v) => v < 0);
  if (below.length) lines.push(`Furthest below GMV target: ${below.map((b) => `${b.x.n.label} ${pctSigned(b.v)}`).join(", ")}.`);
  const over = top(countries, (x) => x.boltPp, -1, 3, (v) => v > 0);
  if (over.length) lines.push(`Most over the Bolt spend target (pp of GMV): ${over.map((b) => `${b.x.n.label} +${b.v.toFixed(2)}pp`).join(", ")}.`);
  // YoY: ignore very small markets, their growth rates are noise.
  const big = countries.filter((c) => c.cur.gmv >= 0.01 * tot.cur.gmv);
  const best = top(big, (x) => x.st.yoy.value, -1, 2, () => true), worst = top(big, (x) => x.st.yoy.value, 1, 2, (v) => v < 0);
  if (best.length) lines.push(`YoY GMV: strongest ${best.map((b) => `${b.x.n.label} ${pctSigned(b.v)}`).join(", ")}${worst.length ? `; weakest ${worst.map((b) => `${b.x.n.label} ${pctSigned(b.v)}`).join(", ")}` : ""}.`);
  const segMiss = top(segments, (x) => x.st.gmv.value, 1, 1, (v) => v < 0)[0], segOver = top(segments, (x) => x.boltPp, -1, 1, (v) => v > 0)[0];
  if (segMiss || segOver) lines.push(`By segment: ${[segMiss && `biggest GMV miss ${segMiss.x.n.label} ${pctSigned(segMiss.v)}`, segOver && `most over Bolt spend target ${segOver.x.n.label} +${segOver.v.toFixed(2)}pp`].filter(Boolean).join("; ")}.`);
  if (!tot.st.gmv.light && !countries.some((c) => c.st.gmv.light)) lines.push("No targets found for this selection (or the budget table has not been refreshed yet), so status uses YoY only.");
  return { counts, lines };
}

function Insights({ m, country, seg, filters }: { m: MonthModel; country: Node; seg: Node; filters: Filters }) {
  const { counts, lines } = useMemo(() => buildInsights(m, country, seg, filters), [m, country, seg, filters]);
  const r = STATUS_RULES;
  const p = (v: number) => `${(v * 100).toFixed(0)}%`;
  return (
    <section style={{ display: "grid", gap: 8, padding: 12, border, borderRadius: 8, background: "var(--color-layer-floor-1)" }}>
      <div style={{ ...row, justifyContent: "space-between" }}>
        <Typography defaultTag="h2" className="bolt-font-heading-s-accent">Insights</Typography>
        <div style={row}>
          {(["green", "yellow", "red"] as Light[]).map((l) => (
            <span key={l} style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
              <span style={{ width: 12, height: 12, borderRadius: 6, background: LIGHT_COLOR[l], display: "inline-block" }} />{counts[l]}
            </span>
          ))}
          <span className="text-secondary">countries</span>
        </div>
      </div>
      <ul style={{ margin: 0, paddingLeft: 18, display: "grid", gap: 4 }}>{lines.map((l, i) => <li key={i}>{l}</li>)}</ul>
      <Typography className="bolt-font-body-s-regular text-secondary">
        Generated from the tables below. Status = worst of three checks: GMV vs target (green ≥ {p(r.gmv.green)}, yellow ≥ {p(r.gmv.yellow)}, else red),
        Bolt spend as % of GMV vs its target ratio (green up to {p(r.bolt.green)} over, yellow up to {p(r.bolt.yellow)}, else red)
        and GMV YoY (green ≥ {p(r.yoy.green)}, yellow ≥ {p(r.yoy.yellow)}, else red). Rows without a target use the checks they have. Hover a dot for the detail.
      </Typography>
    </section>
  );
}

// ---------- expandable tree ----------
function useOpen(initial: string[]) {
  const [open, setOpen] = useState<Set<string>>(new Set(initial));
  const toggle = (id: string) => setOpen((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const expandAll = (root: Node) => {
    const ids = new Set<string>();
    const walk = (n: Node) => { if (n.children.length) { ids.add(n.id); n.children.forEach(walk); } };
    walk(root); setOpen(ids);
  };
  return { open, toggle, expandAll, collapse: () => setOpen(new Set(initial)) };
}

function visibleRows(root: Node, open: Set<string>): Node[] {
  const out: Node[] = [root];
  const walk = (n: Node) => {
    if (!open.has(n.id)) return;
    for (const c of n.children) { out.push(c); walk(c); }
  };
  walk(root);
  return out;
}

function Label({ n, open, toggle }: { n: Node; open: Set<string>; toggle: (id: string) => void }) {
  const expandable = n.children.length > 0;
  return (
    <td style={{
      ...td, textAlign: "left", position: "sticky", left: 0, zIndex: 1, minWidth: 240,
      // Opaque, so numbers scrolling underneath do not show through (--color-layer-surface is translucent).
      background: n.depth === 0 ? "var(--color-layer-floor-2)" : "var(--color-layer-floor-1)",
      boxShadow: "1px 0 0 var(--color-border-separator)", paddingLeft: 10 + Math.max(0, n.depth - 1) * 18,
      fontWeight: n.depth <= 1 ? 600 : 400,
      color: n.level === "city" || n.level === "cluster" ? "var(--color-content-secondary)" : undefined,
    }}>
      <span onClick={() => expandable && toggle(n.id)} style={{ cursor: expandable ? "pointer" : "default" }}>
        {expandable ? (open.has(n.id) ? "▾ " : "▸ ") : "· "}{n.label}
      </span>
    </td>
  );
}

function TableShell({ title, children, actions }: { title: string; children: React.ReactNode; actions?: React.ReactNode }) {
  return (
    <section style={{ display: "grid", gap: 8 }}>
      <div style={{ ...row, justifyContent: "space-between" }}>
        <Typography defaultTag="h2" className="bolt-font-heading-s-accent">{title}</Typography>
        <div style={row}>{actions}</div>
      </div>
      <div style={{ overflow: "auto", maxHeight: "70vh", border, borderRadius: 8 }}>
        <table style={{ borderCollapse: "separate", borderSpacing: 0, fontSize: 13, width: "max-content" }}>{children}</table>
      </div>
    </section>
  );
}

// ---------- monthly-style table (value, MoM, YoY, vs target per metric) ----------
type MonthModel = { cur: Agg[]; mom: Agg[]; yoy: Agg[]; tgt: TargetSet };

function MetricTable({ title, firstCol, tree, m, unit, initialOpen, metrics, mode, filters }: {
  title: string; firstCol: string; tree: Node; m: MonthModel; unit: Unit; initialOpen: string[];
  metrics: MetricKey[]; mode: TargetMode; filters: Filters;
}) {
  const cols = metrics.map(metricDef);
  const { open, toggle, expandAll, collapse } = useOpen(initialOpen);
  const rows = visibleRows(tree, open);
  const valueHead = (k: MetricKey) => (k === "gmv" ? "GMV (€)" : unit === "pct" ? "% of GMV" : "€");
  return (
    <TableShell title={title} actions={<>
      <button onClick={collapse} style={linkBtn}>Collapse</button>
      <button onClick={() => expandAll(tree)} style={linkBtn}>Expand all</button>
    </>}>
      <thead>
        <tr>
          <th style={{ ...th, textAlign: "left", left: 0, zIndex: 3 }} rowSpan={2}>{firstCol}</th>
          <th style={{ ...th, textAlign: "center", top: 0 }} rowSpan={2} title="Worst of GMV vs target, Bolt spend vs target and GMV YoY">Status</th>
          {cols.map((x) => (
            <th key={x.key} colSpan={x.hasTarget ? 4 : 3} style={{ ...th, textAlign: "center", borderLeft: border }}>{x.label}</th>
          ))}
        </tr>
        <tr>
          {cols.map((x) => [
            <th key={x.key + "v"} style={{ ...th, top: 31, borderLeft: border }}>{valueHead(x.key)}</th>,
            <th key={x.key + "m"} style={{ ...th, top: 31 }}>MoM</th>,
            <th key={x.key + "y"} style={{ ...th, top: 31 }}>YoY</th>,
            x.hasTarget ? <th key={x.key + "t"} style={{ ...th, top: 31 }}>vs Target</th> : null,
          ])}
        </tr>
      </thead>
      <tbody>
        {rows.map((n) => {
          const cur = sumIdx(m.cur, n.units), mom = sumIdx(m.mom, n.units), yoy = sumIdx(m.yoy, n.units);
          const tgt = nodeTarget(mode, n, m.tgt, filters);
          return (
            <tr key={n.id} style={{ background: n.depth === 0 ? "var(--color-layer-floor-1)" : undefined }}>
              <Label n={n} open={open} toggle={toggle} />
              <td style={{ ...td, textAlign: "center" }}><StatusDot st={rowStatus(cur, yoy, tgt)} /></td>
              {cols.map((x) => {
                const v = metricValue(cur, x.key, unit);
                const dm = change(v, metricValue(mom, x.key, unit), x.key, unit);
                const dy = change(v, metricValue(yoy, x.key, unit), x.key, unit);
                // Which rows have a target depends on the level the budget was set at (see nodeTarget).
                const tv = x.hasTarget ? targetValue(tgt, x.key, unit) : null;
                const dt = change(v, tv, x.key, unit);
                return [
                  <td key={x.key + "v"} style={{ ...td, borderLeft: border }}>{fmtValue(v, x.key, unit)}</td>,
                  <td key={x.key + "m"} style={{ ...td, color: tone(dm, x.key, "delta") }}>{fmtDelta(dm, x.key, unit)}</td>,
                  <td key={x.key + "y"} style={{ ...td, color: tone(dy, x.key, "delta") }}>{fmtDelta(dy, x.key, unit)}</td>,
                  x.hasTarget ? <td key={x.key + "t"} style={{ ...td, color: tone(dt, x.key, "target") }}>{fmtDelta(dt, x.key, unit)}</td> : null,
                ];
              })}
            </tr>
          );
        })}
      </tbody>
    </TableShell>
  );
}

// ---------- trend table (one metric, one column per period) ----------
type Period = { key: string; label: string; from: string; to: string; partial: boolean };

function TrendTable({ title, firstCol, tree, periods, perPeriod, prevPeriod, vsLabel, metric, unit, initialOpen }: {
  title: string; firstCol: string; tree: Node; periods: Period[]; perPeriod: Agg[][]; prevPeriod: Agg[][]; vsLabel: string;
  metric: MetricKey; unit: Unit; initialOpen: string[];
}) {
  const { open, toggle, expandAll, collapse } = useOpen(initialOpen);
  const rows = visibleRows(tree, open);
  return (
    <TableShell title={title} actions={<>
      <span className="text-secondary">small line = {vsLabel}; green = better, red = worse (spend: more = red)</span>
      <button onClick={collapse} style={linkBtn}>Collapse</button>
      <button onClick={() => expandAll(tree)} style={linkBtn}>Expand all</button>
    </>}>
      <thead>
        <tr>
          <th style={{ ...th, textAlign: "left", left: 0, zIndex: 3 }}>{firstCol}</th>
          {periods.map((q) => <th key={q.key} style={th} title={`${q.from} – ${q.to}`}>{q.label}{q.partial ? "*" : ""}</th>)}
        </tr>
      </thead>
      <tbody>
        {rows.map((n) => (
          <tr key={n.id} style={{ background: n.depth === 0 ? "var(--color-layer-floor-1)" : undefined }}>
            <Label n={n} open={open} toggle={toggle} />
            {perPeriod.map((pc, i) => {
              const v = metricValue(sumIdx(pc, n.units), metric, unit);
              const d = change(v, metricValue(sumIdx(prevPeriod[i] ?? [], n.units), metric, unit), metric, unit);
              return (
                <td key={periods[i].key} style={{ ...td, lineHeight: 1.25 }}>
                  <div>{fmtValue(v, metric, unit)}</div>
                  <div style={{ fontSize: 11, fontWeight: 600, color: trendTone(d, metric) ?? "var(--color-content-secondary)" }}>{fmtDelta(d, metric, unit)}</div>
                </td>
              );
            })}
          </tr>
        ))}
      </tbody>
    </TableShell>
  );
}

// ---------- trend chart (plain SVG, no chart library) ----------
const PALETTE = ["#2f9e6b", "#3b82f6", "#f59e0b", "#a855f7", "#ef4444", "#14b8a6", "#ec4899", "#84cc16", "#6366f1", "#f97316", "#06b6d4", "#a3a3a3"];

/** About n round tick values covering [lo, hi]. */
function niceTicks(lo: number, hi: number, n = 5): number[] {
  const span = hi - lo || Math.abs(hi) || 1;
  const raw = span / (n - 1), mag = 10 ** Math.floor(Math.log10(raw));
  const step = ([1, 2, 2.5, 5, 10].map((m) => m * mag).find((x) => x >= raw)) ?? raw;
  const out: number[] = [];
  for (let v = Math.floor(lo / step) * step; out.length < 10; v += step) { out.push(v); if (v >= hi) break; }
  return out;
}

/** One line per row of the tree's first level (and the total) for the selected metric, with data labels. */
function TrendChart({ title, root, periods, perPeriod, metric, unit, defaultLines }: {
  title: string; root: Node; periods: Period[]; perPeriod: Agg[][]; metric: MetricKey; unit: Unit; defaultLines: number;
}) {
  const series = useMemo(() => {
    const nodes = [root, ...root.children];
    return nodes.map((n, i) => ({
      id: n.id, label: n.label, color: i === 0 ? "var(--color-content-primary)" : PALETTE[(i - 1) % PALETTE.length],
      values: perPeriod.map((pc) => metricValue(sumIdx(pc, n.units), metric, unit)),
      size: perPeriod.reduce((t, pc) => t + sumIdx(pc, n.units).gmv, 0),
    }));
  }, [root, perPeriod, metric, unit]);
  // null = default lines (total + the biggest rows by GMV); otherwise the user's picks.
  const [picked, setPicked] = useState<string[] | null>(null);
  const [labels, setLabels] = useState<"total" | "all" | "off">("all");
  const shown = new Set(picked ?? [series[0]?.id, ...series.slice(1).sort((a, b) => b.size - a.size).slice(0, defaultLines).map((x) => x.id)]);
  const toggle = (id: string) => setPicked(shown.has(id) ? [...shown].filter((x) => x !== id) : [...shown, id]);
  const lines = series.filter((x) => shown.has(x.id));

  const W = 960, H = 330, L = 64, R = 24, T = 22, B = 34;
  const vals = lines.flatMap((x) => x.values).filter((v): v is number => v != null && isFinite(v));
  if (!periods.length || !vals.length) return null;
  let lo = Math.min(...vals), hi = Math.max(...vals);
  if (metric === "gmv" || unit === "eur") lo = Math.min(0, lo);
  const ticks = niceTicks(lo, hi);
  const y0 = ticks[0], y1 = ticks[ticks.length - 1] || 1;
  const x = (i: number) => (periods.length === 1 ? (L + W - R) / 2 : L + (i * (W - L - R)) / (periods.length - 1));
  const y = (v: number) => T + (1 - (v - y0) / (y1 - y0 || 1)) * (H - T - B);
  const every = Math.ceil(periods.length / 14);
  // Labels need ~44px each: skip points when they would overlap.
  const labelEvery = Math.max(1, Math.ceil(44 / ((W - L - R) / Math.max(periods.length - 1, 1))));
  const fin = (v: number | null): v is number => v != null && isFinite(v);
  const path = (values: (number | null)[]) => {
    let d = "", pen = false;
    values.forEach((v, i) => {
      if (!fin(v)) { pen = false; return; }
      d += `${pen ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)}`;
      pen = true;
    });
    return d;
  };
  return (
    <section style={{ display: "grid", gap: 8 }}>
      <div style={{ ...row, justifyContent: "space-between" }}>
        <Typography defaultTag="h2" className="bolt-font-heading-s-accent">{title}: {metricDef(metric).label}</Typography>
        <Seg value={labels} onChange={setLabels} options={[["total", "Labels: total"], ["all", "All lines"], ["off", "Off"]]} />
      </div>
      <div style={{ ...row, gap: 8 }}>
        {series.map((x) => (
          <button key={x.id} onClick={() => toggle(x.id)} style={{
            ...linkBtn, color: "var(--color-content-primary)", opacity: shown.has(x.id) ? 1 : 0.4,
            display: "inline-flex", gap: 6, alignItems: "center",
          }}>
            <span style={{ width: 10, height: 10, borderRadius: 5, background: x.color, display: "inline-block" }} />{x.label}
          </button>
        ))}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", maxWidth: 1100, border, borderRadius: 8, background: "var(--color-layer-floor-1)" }}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={L} x2={W - R} y1={y(t)} y2={y(t)} stroke="var(--color-border-separator)" />
            <text x={L - 8} y={y(t) + 4} textAnchor="end" fontSize="11" fill="var(--color-content-secondary)">{fmtValue(t, metric, unit)}</text>
          </g>
        ))}
        {periods.map((q, i) => i % every === 0 && (
          <text key={q.key} x={x(i)} y={H - 12} textAnchor={i === periods.length - 1 ? "end" : "middle"} fontSize="11" fill="var(--color-content-secondary)">{q.label}{q.partial ? "*" : ""}</text>
        ))}
        {lines.map((l, k) => (
          <g key={l.id}>
            <path d={path(l.values)} fill="none" stroke={l.color} strokeWidth={k === 0 ? 2.5 : 1.75} strokeLinejoin="round" />
            {periods.length <= 60 && l.values.map((v, i) => fin(v) && (
              <g key={i}>
                <circle cx={x(i)} cy={y(v)} r={3} fill={l.color}>
                  <title>{`${l.label} · ${periods[i].label}: ${fmtValue(v, metric, unit)}`}</title>
                </circle>
                {(labels === "all" || (labels === "total" && l.id === series[0].id)) && i % labelEvery === 0 && (
                  <text x={x(i)} y={y(v) - 8} textAnchor="middle" fontSize="10" fontWeight={l.id === series[0].id ? 600 : 400} fill={l.id === series[0].id ? "var(--color-content-primary)" : l.color}>
                    {fmtValue(v, metric, unit)}
                  </text>
                )}
              </g>
            ))}
          </g>
        ))}
      </svg>
    </section>
  );
}

// ---------- period models ----------
type MonthInfo = { month: string; cutoff: number; dim: number };

/**
 * Selected months added together. Each month counts under its own month's segments, and so do its
 * MoM / YoY comparison windows, so the comparison is like-for-like per city.
 */
function monthModel(p: Payload, months: string[], through: string | null, basis: Basis, asOf: string) {
  const ix = new SegIndex(p);
  const m: MonthModel = { cur: [], mom: [], yoy: [], tgt: emptyTargets() };
  const info: MonthInfo[] = [];
  const run = basis === "run";
  for (const month of months) {
    const dim = daysInMonth(month);
    const end = through ?? (asOf < monthEnd(month) ? asOf : monthEnd(month));
    if (end < `${month}-01`) continue;
    const cutoff = Number(end.slice(8));
    info.push({ month, cutoff, dim });
    const cmp = (ym: string) => `${ym}-${String(run ? daysInMonth(ym) : Math.min(cutoff, daysInMonth(ym))).padStart(2, "0")}`;
    // Run rate: average daily value so far x days in month (ratios are unaffected).
    aggregateInto(m.cur, p, ix, `${month}-01`, end, run && cutoff > 0 ? dim / cutoff : 1, month);
    const pm = prevMonth(month), py = shiftYear(month, -1);
    aggregateInto(m.mom, p, ix, `${pm}-01`, cmp(pm), 1, month);
    aggregateInto(m.yoy, p, ix, `${py}-01`, cmp(py), 1, month);
    targetsInto(m.tgt, p, ix, month, run ? 1 : cutoff / dim);
  }
  return { ix, m, info };
}

function trendPeriods(grain: "weekly" | "daily", from: string, to: string, asOf: string): Period[] {
  const out: Period[] = [];
  if (grain === "daily") {
    for (let d = from; d <= to; d = addDays(d, 1)) out.push({ key: d, label: d.slice(5), from: d, to: d, partial: false });
  } else {
    for (let w = mondayOf(from); w <= to; w = addDays(w, 7)) {
      const end = addDays(w, 6);
      const f = w < from ? from : w, t = end > to ? to : end;
      out.push({ key: w, label: `Wk ${w.slice(5)}`, from: f, to: t, partial: f !== w || t !== end || end > asOf });
    }
  }
  return out;
}

/**
 * Per period, per segmented unit, plus the same window `shift` days earlier (7 = week on week, 1 = day on day;
 * a partial week is compared with the same days of the week before). Each day counts under its own month's segment.
 */
function aggregatePeriods(p: Payload, periods: Period[], shift: number) {
  const ix = new SegIndex(p);
  const agg = (from: string, to: string) => { const out: Agg[] = []; aggregateInto(out, p, ix, from, to); return out; };
  const per = periods.map((q) => agg(q.from, q.to));
  const prev = periods.map((q) => agg(addDays(q.from, -shift), addDays(q.to, -shift)));
  return { ix, per, prev };
}

// ---------- filters ----------
function FilterBar({ meta, filters, setFilters }: { meta: UnitMeta[]; filters: Filters; setFilters: (f: Filters) => void }) {
  const countries = [...new Set(meta.map((m) => m.country))].sort();
  const cities = [...new Map(meta
    .filter((m) => !filters.countries.length || filters.countries.includes(m.country))
    .map((m) => [`${m.country}|${m.city}`, filters.countries.length === 1 ? m.city : `${m.city} (${m.country})`] as [string, string])).entries()]
    .sort((a, b) => a[1].localeCompare(b[1]));
  const present = new Set(meta.map((m) => m.segment));
  const segments = [...SEGMENT_ORDER.filter((s) => present.has(s)), ...[...present].filter((s) => !SEGMENT_ORDER.includes(s)).sort()];
  return (
    <>
      <MultiSelect label="Country" options={countries.map((c) => [c, c])} selected={filters.countries}
        onChange={(v) => setFilters({ ...filters, countries: v, cities: filters.cities.filter((c) => !v.length || v.includes(c.split("|")[0])) })} />
      <MultiSelect label="City" options={cities} selected={filters.cities} onChange={(v) => setFilters({ ...filters, cities: v })} />
      <MultiSelect label="Segment" options={segments.map((s) => [s, s])} selected={filters.segments} onChange={(v) => setFilters({ ...filters, segments: v })} />
      {(filters.countries.length > 0 || filters.cities.length > 0 || filters.segments.length > 0) && (
        <button onClick={() => setFilters(noFilters)} style={linkBtn}>Reset filters</button>
      )}
    </>
  );
}

// ---------- Page ----------
export default function Dashboard() {
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState("");
  const [loadingFor, setLoadingFor] = useState(0);
  const [loadingDetail, setLoadingDetail] = useState("");
  const [tab, setTab] = useState<Tab>("monthly");
  const [unit, setUnit] = useState<Unit>("pct");
  const [filters, setFilters] = useState<Filters>(noFilters);
  // null = default (latest month); [] = all months.
  const [pickedMonths, setMonths] = useState<string[] | null>(null);
  const [through, setThrough] = useState<Record<string, string>>({});
  const [basis, setBasis] = useState<Basis>("same");
  const [range, setRange] = useState<{ from: string; to: string } | null>(null);
  const [metric, setMetric] = useState<MetricKey>("gmv");
  // Daily trend: compare with the day before (DoD) or the same weekday last week (WoW).
  const [dayShift, setDayShift] = useState<1 | 7>(1);
  const [refreshing, setRefreshing] = useState("");

  /** Re-read the budget (targets) without waiting for the daily refresh. */
  async function refreshTargets() {
    setRefreshing("Refreshing targets…");
    try {
      const r = await fetch("/api/refresh-budget", { method: "POST" });
      if (!r.ok) throw new Error((await r.json().catch(() => null))?.error ?? `Server returned ${r.status}`);
      const d = await fetch("/api/data");
      if (d.ok) setData((await d.json()) as Payload);
      setRefreshing("Targets refreshed");
    } catch (e) {
      setRefreshing(`Could not refresh: ${(e as Error).message}`);
    }
    setTimeout(() => setRefreshing(""), 6000);
  }

  useEffect(() => {
    let stop = false;
    let networkFailures = 0;
    async function poll() {
      let r: Response;
      try {
        r = await fetch("/api/data");
        networkFailures = 0;
      } catch {
        // No response at all: the app is restarting/redeploying, or the SSO session expired.
        // Retry for a while before giving up.
        if (stop) return;
        if (++networkFailures <= 20) { setTimeout(poll, 5000); return; }
        setError("Lost connection to the app. Reload the page (you may need to sign in again).");
        return;
      }
      try {
        const text = await r.text();
        let j: any = null;
        try { j = JSON.parse(text); } catch { /* proxy error page */ }
        if (stop) return;
        if (r.status === 202 || (j === null && r.status >= 500)) {
          if (typeof j?.seconds === "number") setLoadingFor(j.seconds);
          if (j) {
            const done = (j.finished ?? []).map((f: { label: string; seconds: number }) => `${f.label} done in ${f.seconds}s`);
            const run = (j.running ?? []).map((x: string) => `running ${x}`);
            setLoadingDetail([...run, ...done].join(" · "));
          }
          setTimeout(poll, 3000);
          return;
        }
        if (r.ok && j === null) throw new Error("Got a web page instead of data (sign-in expired?). Reload the page.");
        if (!r.ok || j === null) throw new Error(j?.error ?? `Server returned ${r.status}`);
        setData(j as Payload);
      } catch (e) {
        if (!stop) setError(String((e as Error).message ?? e));
      }
    }
    poll();
    return () => { stop = true; };
  }, []);

  const asOf = data?.asOf ?? "";
  const months = useMemo(() => availableMonths(asOf || `${FIRST_MONTH}-01`), [asOf]);
  const selected = (pickedMonths ?? [months[0]]).filter((m) => months.includes(m));
  const selMonths = (selected.length ? selected : months).slice().sort();
  const single = selMonths.length === 1 ? selMonths[0] : null;
  // Monthly tab: months + (for a single month) a "through" date, default the latest day.
  const monthMax = single ? (asOf && asOf < monthEnd(single) ? asOf : monthEnd(single)) : "";
  const throughDay = single ? (through[single] && through[single] <= monthMax ? through[single] : monthMax) : null;
  // Weekly / Daily tabs: date range (defaults to Oct 1 → latest day).
  const from = range?.from ?? TREND_START, to = range?.to && range.to <= asOf ? range.to : asOf;

  const isMonthly = tab === "monthly";
  const mm = useMemo(() => (data && isMonthly ? monthModel(data, selMonths, throughDay, basis, asOf) : null),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [data, isMonthly, selMonths.join(), throughDay, basis, asOf]);
  const periods = useMemo(() => (data && !isMonthly ? trendPeriods(tab as "weekly" | "daily", from, to, asOf) : []),
    [data, isMonthly, tab, from, to, asOf]);
  const shift = tab === "weekly" ? 7 : dayShift;
  const cmpName = tab === "weekly" ? "WoW" : dayShift === 1 ? "DoD" : "WoW";
  const vsLabel = tab === "weekly" ? "change vs the same days of the week before (WoW)" : dayShift === 1 ? "change vs the day before (DoD)" : "change vs the same weekday last week (WoW)";
  const trend = useMemo(() => (data && periods.length ? aggregatePeriods(data, periods, shift) : null), [data, periods, shift]);

  // Segmented units seen in the current view (filters and tables are built from them).
  const meta: UnitMeta[] = mm?.ix.units ?? trend?.ix.units ?? [];
  const active = useMemo(() => activeUnits(meta, filters), [meta, filters]);

  const globalSeg = useMemo(() => buildTree(meta, active, ["segment"], "GLOBAL"), [meta, active]);
  const mainTree = useMemo(() => buildTree(meta, active, MAIN_LEVELS), [meta, active]);

  const monthLabel = (m: string) => new Date(m + "-01T00:00:00Z").toLocaleString("en", { month: "long", year: "numeric", timeZone: "UTC" });

  return (
    <main style={{ padding: "var(--dimension-500) var(--dimension-600)", display: "grid", gap: 16 }}>
      <header style={{ ...row, justifyContent: "space-between", alignItems: "end" }}>
        <div>
          <Typography defaultTag="h1" className="bolt-font-heading-l-accent">Delivery Growth Incentive - City Segmentation</Typography>
          <Typography className="bolt-font-body-s-regular text-secondary">
            {data ? `Data through ${data.asOf} · updated ${new Date(data.generatedAt).toLocaleString()} · targets read ${new Date(data.budgetAt ?? data.generatedAt).toLocaleString()} · refreshes daily` : "Loading from Databricks…"}
          </Typography>
        </div>
        <div style={row}>
          {refreshing && <span className="text-secondary">{refreshing}</span>}
          <button onClick={refreshTargets} disabled={!data || refreshing === "Refreshing targets…"} style={{ ...control, cursor: "pointer" }}
            title="Re-read the budget table now (otherwise it refreshes daily at 08:00 UTC)">Refresh targets</button>
          <Seg value={unit} onChange={setUnit} options={[["pct", "% of GMV"], ["eur", "€"]]} />
        </div>
      </header>

      <Seg value={tab} onChange={setTab} options={[["monthly", "Monthly"], ["weekly", "Weekly trend"], ["daily", "Daily trend"]]} />

      {error && <div style={{ color: "var(--color-content-danger-primary)" }}>Could not load data: {error}</div>}
      {!data && !error && (
        <div>
          Loading from Databricks{loadingFor > 0 ? ` (${Math.floor(loadingFor / 60)}m ${loadingFor % 60}s so far)` : ""}…
          {" "}The first load after a deploy runs the full queries (and may wait for the cluster to start), so it can take a few minutes; after that pages load instantly.
          {loadingDetail && <div className="bolt-font-body-s-regular text-secondary" style={{ marginTop: 6 }}>{loadingDetail}</div>}
        </div>
      )}

      {data && (
        <>
          <div style={{ ...row, padding: 12, border, borderRadius: 8, background: "var(--color-layer-floor-1)" }}>
            {tab === "monthly" ? (
              <>
                <MultiSelect label="Month" options={months.map((m) => [m, monthLabel(m)])} selected={pickedMonths ?? [months[0]]}
                  onChange={setMonths} />
                {single && throughDay && (
                  <DateInput label="Through" value={throughDay} min={`${single}-01`} max={monthMax}
                    onChange={(v) => setThrough({ ...through, [single]: v })} />
                )}
                <Seg value={basis} onChange={setBasis} options={[["same", "Same days"], ["run", "Run rate"]]} />
              </>
            ) : (
              <>
                <DateInput label="From" value={from} min={TREND_START} max={to} onChange={(v) => setRange({ from: v, to })} />
                <DateInput label="To" value={to} min={from} max={asOf} onChange={(v) => setRange({ from, to: v })} />
                <select value={metric} onChange={(e) => setMetric(e.target.value as MetricKey)} style={control}>
                  {METRICS.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}
                </select>
                {tab === "daily" && <Seg value={String(dayShift) as "1" | "7"} onChange={(v) => setDayShift(Number(v) as 1 | 7)} options={[["1", "DoD"], ["7", "WoW"]]} />}
              </>
            )}
            <FilterBar meta={meta} filters={filters} setFilters={setFilters} />
          </div>

          {active.length > 0 && mm && tab === "monthly" && (
            <Insights m={mm.m} country={mainTree} seg={globalSeg} filters={filters} />
          )}

          <Typography className="bolt-font-body-s-regular text-secondary">
            {mm
              ? <>
                  {mm.info.map((i) => `${monthLabel(i.month)}: ${i.cutoff >= i.dim ? "full month" : basis === "run"
                    ? `run rate (days 1–${i.cutoff} projected to ${i.dim})` : `days 1–${i.cutoff}`}`).join(" · ")}.{" "}
                  {basis === "run" ? "MoM/YoY vs full months; full-month targets. " : "MoM/YoY compare the same days; targets pro-rated. "}
                  Δ columns: {unit === "pct" ? "percentage points (GMV: %)" : "relative %"}.{" "}
                </>
              : `${tab === "weekly" ? "Weeks start Monday; * = partial week. " : ""}Values: ${metric === "gmv" ? "GMV in €" : unit === "pct" ? "% of GMV" : "€"}. `}
            Segments follow each month's budget (October uses October segments, November uses November).
            {" "}Spend is the GA number, including VAT.
            {" "}Targets: country rows (and GLOBAL for the total) from the country budget; segments from the segment budget; cities summed from the city budget.
            Zone clusters have no targets. Bolt spend by objective and Bolt spend (BA) only have country-level targets.
          </Typography>

          {active.length === 0 && <div>No data for these filters.</div>}

          {active.length > 0 && mm && tab === "monthly" && (
            <>
              <MetricTable key="g" title="Global performance by segment" firstCol="Segment" tree={globalSeg} m={mm.m} unit={unit} initialOpen={["total"]}
                metrics={PERF_METRICS} mode="segment" filters={filters} />
              <MetricTable key="gs" title="Global spend by objective, by segment" firstCol="Segment" tree={globalSeg} m={mm.m} unit={unit} initialOpen={["total"]}
                metrics={SPEND_METRICS} mode="segment" filters={filters} />
              <MetricTable key="m" title="Country / Segment / City / Cluster" firstCol="Country / Segment / City / Cluster" tree={mainTree} m={mm.m} unit={unit} initialOpen={["total"]}
                metrics={PERF_METRICS} mode="main" filters={filters} />
              <MetricTable key="ms" title="Spend by objective: Country / Segment / City / Cluster" firstCol="Country / Segment / City / Cluster" tree={mainTree} m={mm.m} unit={unit} initialOpen={["total"]}
                metrics={SPEND_METRICS} mode="main" filters={filters} />
            </>
          )}
          {active.length > 0 && (tab === "weekly" || tab === "daily") && trend && (
            <>
              <TrendTable key={`gt-${tab}`} title={`Global performance by segment · ${cmpName}`} firstCol="Segment" tree={globalSeg} periods={periods} perPeriod={trend.per} prevPeriod={trend.prev} vsLabel={vsLabel} metric={metric} unit={unit} initialOpen={["total"]} />
              <TrendTable key={`mt-${tab}`} title={`Country / Segment / City / Cluster · ${cmpName}`} firstCol="Country / Segment / City / Cluster" tree={mainTree} periods={periods} perPeriod={trend.per} prevPeriod={trend.prev} vsLabel={vsLabel} metric={metric} unit={unit} initialOpen={["total"]} />
              <TrendChart key={`gc-${tab}`} title="Trend by segment" root={globalSeg} periods={periods} perPeriod={trend.per} metric={metric} unit={unit} defaultLines={8} />
              <TrendChart key={`mc-${tab}`} title="Trend by country" root={mainTree} periods={periods} perPeriod={trend.per} metric={metric} unit={unit} defaultLines={5} />
            </>
          )}

          <details style={{ border, borderRadius: 8, padding: 12 }}>
            <summary style={{ cursor: "pointer", fontWeight: 600 }}>Metric and status definitions</summary>
            <div style={{ overflow: "auto", marginTop: 8, display: "grid", gap: 12 }}>
              <table style={{ borderCollapse: "collapse", fontSize: 13 }}>
                <thead>
                  <tr>{["Metric", "Definition", "Spend objectives (spend_objective)", "Source", "Target"].map((h) => <th key={h} style={{ ...th, position: "static", textAlign: "left" }}>{h}</th>)}</tr>
                </thead>
                <tbody>
                  {METRIC_DEFS.map((d) => (
                    <tr key={d.label}>
                      <td style={{ ...td, textAlign: "left", fontWeight: 600 }}>{d.label}</td>
                      <td style={{ ...td, textAlign: "left", whiteSpace: "normal", minWidth: 280 }}>{d.definition}</td>
                      <td style={{ ...td, textAlign: "left", whiteSpace: "normal", minWidth: 280 }}>{d.objectives ? <code>{d.objectives}</code> : "–"}</td>
                      <td style={{ ...td, textAlign: "left", whiteSpace: "normal" }}><code>{d.source}</code></td>
                      <td style={{ ...td, textAlign: "left", whiteSpace: "normal" }}><code>{d.target}</code></td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <Typography className="bolt-font-body-s-regular text-secondary">
                Spend and GMV: delivered orders, local order date. Spend ratios are % of GMV; targets are ratio × GMV target, pro-rated by elapsed days
                (full month in run-rate view). Δ for ratios is in percentage points, for GMV and € it is relative %.
              </Typography>
              <table style={{ borderCollapse: "collapse", fontSize: 13 }}>
                <thead>
                  <tr>{["Status check", "Green", "Yellow", "Red"].map((h) => <th key={h} style={{ ...th, position: "static", textAlign: "left" }}>{h}</th>)}</tr>
                </thead>
                <tbody>
                  <tr><td style={{ ...td, textAlign: "left" }}>GMV vs target (relative)</td><td style={{ ...td, textAlign: "left" }}>≥ {p0(STATUS_RULES.gmv.green)}</td><td style={{ ...td, textAlign: "left" }}>≥ {p0(STATUS_RULES.gmv.yellow)}</td><td style={{ ...td, textAlign: "left" }}>below {p0(STATUS_RULES.gmv.yellow)}</td></tr>
                  <tr><td style={{ ...td, textAlign: "left" }}>Bolt spend % of GMV vs target ratio (relative overspend)</td><td style={{ ...td, textAlign: "left" }}>up to +{p0(STATUS_RULES.bolt.green)}</td><td style={{ ...td, textAlign: "left" }}>up to +{p0(STATUS_RULES.bolt.yellow)}</td><td style={{ ...td, textAlign: "left" }}>above +{p0(STATUS_RULES.bolt.yellow)}</td></tr>
                  <tr><td style={{ ...td, textAlign: "left" }}>GMV YoY</td><td style={{ ...td, textAlign: "left" }}>≥ +{p0(STATUS_RULES.yoy.green)}</td><td style={{ ...td, textAlign: "left" }}>≥ {p0(STATUS_RULES.yoy.yellow)}</td><td style={{ ...td, textAlign: "left" }}>below {p0(STATUS_RULES.yoy.yellow)}</td></tr>
                </tbody>
              </table>
              <Typography className="bolt-font-body-s-regular text-secondary">
                Row status = the worst of its checks; rows without a target use the checks they have.
              </Typography>
            </div>
          </details>
        </>
      )}
    </main>
  );
}
