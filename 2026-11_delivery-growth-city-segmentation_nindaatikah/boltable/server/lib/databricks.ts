// Databricks SQL client, same setup as the campaign AB scorecard app: an all-purpose cluster, and a token from the DATABRICKS_TOKEN Portal Secret.
// Host and HTTP path are not secrets; set DATABRICKS_HOST / DATABRICKS_HTTP_PATH to override.
import { DBSQLClient } from "@databricks/sql";

// Workspace host and cluster HTTP path are set per deployment (not stored in this repo).
const HOST = process.env.DATABRICKS_HOST?.replace(/^https?:\/\//, "").replace(/\/$/, "");
const HTTP_PATH = process.env.DATABRICKS_HTTP_PATH;

export async function runQuery(sql: string): Promise<Record<string, string | null>[]> {
  const token = process.env.DATABRICKS_TOKEN;
  if (!token) throw new Error("DATABRICKS_TOKEN is not set: add it as a Portal Secret");
  if (!HOST || !HTTP_PATH) throw new Error("DATABRICKS_HOST and DATABRICKS_HTTP_PATH must be set");

  const client = new DBSQLClient();
  try {
    const conn = await client.connect({ host: HOST, path: HTTP_PATH, token });
    const session = await conn.openSession();
    try {
      const op = await session.executeStatement(sql, { runAsync: true });
      const rows = (await op.fetchAll()) as Record<string, unknown>[];
      await op.close();
      // Callers parse numbers themselves, so hand back plain strings.
      return rows.map((r) =>
        Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v == null ? null : String(v)])));
    } finally {
      await session.close();
    }
  } finally {
    await client.close();
  }
}
