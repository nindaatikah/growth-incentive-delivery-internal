import express from "express";
import fs from "node:fs";
import helmet from "helmet";
import path from "node:path";
import { healthRouter } from "./routes/health.js";
import compression from "compression";
import { dataRouter } from "./routes/data.js";

// A dropped Databricks connection must not take the whole app down (and restart the load from scratch).
process.on("unhandledRejection", (err) => console.error("unhandled rejection:", err instanceof Error ? err.message : err));
process.on("uncaughtException", (err) => console.error("uncaught exception:", err.message));

const app = express();
const port = parseInt(process.env.PORT || "8080", 10);

app.use(helmet());
app.use(compression());
app.use(express.json());

app.use(dataRouter);
app.use(healthRouter);

// res.send → content-based etag. Avoids express.static's stat-etag, which collides
// across Paketo deploys (frozen mtimes + constant size) and 304s onto a stale shell.
const indexHtmlPath = path.join(import.meta.dirname!, "..", "dist", "index.html");
const sendIndexHtml: express.RequestHandler = (_req, res) => {
  res.setHeader("Cache-Control", "no-cache");
  res.type("html").send(fs.readFileSync(indexHtmlPath));
};

app.get(["/", "/index.html"], sendIndexHtml);

// /assets/* are content-hashed by Vite, so safe to pin for a year.
app.use(
  express.static(path.join(import.meta.dirname!, "..", "dist"), {
    index: false, // we own "/" so express.static must not auto-serve dist/index.html
    setHeaders: (res, filePath) => {
      if (filePath.includes(`${path.sep}assets${path.sep}`)) {
        res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
      }
    },
  }),
);

// Missing /assets/* must 404 loudly rather than fall through to the SPA shell —
// that's what hides stale-cache bugs as silent blank pages.
app.get("/assets/*splat", (_req, res) => {
  res.status(404).type("text/plain").send("Not found");
});

// "*rest" is an Express 5 wildcard pattern — it catches all unmatched GET
// requests and serves the frontend's index.html so client-side routing works.
app.get("*rest", sendIndexHtml);

app.listen(port, () => {
  console.log(
    `Server listening on port ${port} (${process.env.BOLTABLE_GIT_SHA ?? "unknown sha"}, built ${process.env.BOLTABLE_BUILT_AT ?? "unknown time"})`,
  );
});
