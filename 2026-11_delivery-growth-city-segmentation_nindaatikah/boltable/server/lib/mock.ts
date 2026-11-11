// Synthetic data for local UI development only (MOCK_DATA=1). Never used in production.
type Row = Record<string, string | null>;
const cities: [string, string, string, string][] = [
  ["Estonia", "Tallinn", "Monetise", "Tallinn"], ["Estonia", "Tartu", "Grow Share", "Rest Cities"],
  ["Estonia", "Parnu", "Launch", "New Cities"], ["Latvia", "Riga", "Maintain Share", "Riga"],
  ["Latvia", "Jelgava", "Non Priority", "Rest Cities"],
];
export function mockQuery(sql: string): Row[] {
  if (sql.includes("delivery_budget_capital_allocation")) {
    const months = ["2026-10-01", "2026-11-01"];
    const ratios = (k: number) => ({
      activation_spend: "0.03", reactivation_spend: "0.02", engagement_spend: "0.04", ulc_bolt_spend: "0.09",
      total_bolt_spend: String(0.14 + k * 0.005), ba_total_spend: String(0.13 + k * 0.005),
      elc: "0.001", marketing: "0.004", am: "0.007", churn: "0.0005", bdm_3p: "0.002", store_1p: "0.002", bolt_plus: "0.02",
    });
    const cityRows = months.flatMap((m) =>
      cities.map(([country, city, seg, cl], i) => ({
        aggregation: "city", month: m, country_name: country, city_name: city, final_segment: null,
        city_segment: city === "Tartu" && m === "2026-11-01" ? "Monetise" : seg, capital_allocation_group: cl,
        ...ratios(0), gmv_ba: String(2_000_000 * (5 - i)),
      })));
    const countryRows = months.flatMap((m) =>
      [["Estonia", 3], ["Latvia", 2], ["GLOBAL", 5]].map(([c, n], k) => ({
        aggregation: "country", month: m, country_name: String(c), city_name: "", city_segment: "", final_segment: null,
        // Latvia in Nov has no BA target in the budget (blank cell): the app must show "–", not a 0 target.
        ...ratios(k), ...(c === "Latvia" && m === "2026-11-01" ? { ba_total_spend: null } : {}), gmv_ba: String(2_000_000 * 3 * Number(n)),
      })));
    const segmentRows = months.flatMap((m) =>
      ["Monetise", "Maintain Share", "Grow Share", "Launch", "Non Priority", "Needs Data"].map((seg, k) => ({
        aggregation: "segment", month: m, country_name: "", city_name: "", city_segment: seg, final_segment: seg,
        activation_spend: "0.03", reactivation_spend: "0.02", engagement_spend: "0.04", total_bolt_spend: String(0.12 + k * 0.004),
        gmv_ba: String(3_000_000 * (6 - k)),
      })));
    return [...cityRows, ...countryRows, ...segmentRows];
  }
  const rows: Row[] = [];
  const days = (from: string, to: string) => {
    const out: string[] = [];
    for (let d = new Date(from + "T00:00:00Z"); d <= new Date(to + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + 1)) out.push(d.toISOString().slice(0, 10));
    return out;
  };
  const from = /order_created_date_local >= DATE'(\d{4}-\d{2}-\d{2})'/.exec(sql)?.[1] ?? "2026-09-01";
  const to = /order_created_date_local < DATE'(\d{4}-\d{2}-\d{2})'/.exec(sql)?.[1];
  const range = to ? days(from, new Date(Date.parse(to) - 864e5).toISOString().slice(0, 10)) : days(from, "2026-11-02");
  for (const day of range) {
    cities.forEach(([country, city], i) => {
      // October differs from November for some cities, so MoM changes and their drivers can be tested.
      const octFactor = day < "2026-11-01" ? ({ Tartu: 0.8, Riga: 1.2, Parnu: 1.05 } as Record<string, number>)[city] ?? 1 : 1;
      const gmv = (60_000 * (5 - i)) * (1 + 0.1 * Math.sin(Number(day.slice(8)))) * octFactor;
      const split = city === "Tallinn" ? [["Tallinn A", 0.6], ["Tallinn B", 0.4]] as const : [["Unclustered", 1]] as const;
      for (const [zone_cluster, w] of split) rows.push({ day, country_name: country, city_name: city, zone_cluster, gmv: String(gmv * w), bolt: String(gmv * w * (day < "2026-11-01" && city === "Tallinn" ? 0.06 : 0.08)), act: String(gmv * w * 0.03), react: String(gmv * w * 0.02), eng: String(gmv * w * 0.035), cp1: String(gmv * w * 0.1), cp2: String(gmv * w * 0.05), ba: String(gmv * w * 0.07), elc: String(gmv * w * 0.001), mkt: String(gmv * w * 0.003), am: String(gmv * w * 0.006), churn: String(gmv * w * 0.0004), bdm: String(gmv * w * 0.002), p1: String(gmv * w * 0.0015), plus: String(gmv * w * 0.02) });
    });
  }
  return rows;
}
