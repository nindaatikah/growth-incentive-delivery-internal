// This file is an example route and can be removed. Platform-injected
// metadata — see "Environment variables" in AGENTS.md.

import { Router } from "express";

export const healthRouter = Router();

healthRouter.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    gitSha: process.env.BOLTABLE_GIT_SHA,
    builtAt: process.env.BOLTABLE_BUILT_AT,
  });
});
