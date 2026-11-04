import { useEffect, useState } from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { Button, Typography } from "@bolteu/clay-react";
import Dashboard from "./pages/Dashboard";

type Mode = "light" | "dark";

const STORAGE_KEY = "theme-mode";

function getInitialMode(): Mode {
  if (typeof window === "undefined") return "light";
  const stored = window.localStorage.getItem(STORAGE_KEY);
  if (stored === "light" || stored === "dark") return stored;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

// This footer is an example and can be removed. Platform-injected metadata —
// see "Environment variables" in AGENTS.md.
function DeployFooter() {
  const [health, setHealth] = useState<{ gitSha?: string; builtAt?: string }>({});

  useEffect(() => {
    fetch("/api/health")
      .then((res) => res.json())
      .then(setHealth)
      .catch(() => {});
  }, []);

  if (!health.gitSha || !health.builtAt) return null;

  const builtAt = new Date(health.builtAt).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "UTC",
  });

  return (
    <Typography
      className="bolt-font-body-s-regular text-secondary"
      style={{ maxWidth: 860, margin: "0 auto", padding: "var(--dimension-600)" }}
    >
      Built {health.gitSha.slice(0, 12)} · {builtAt} UTC
    </Typography>
  );
}

export default function App() {
  const [mode, setMode] = useState<Mode>(getInitialMode);

  useEffect(() => {
    document.documentElement.dataset.mode = mode;
    window.localStorage.setItem(STORAGE_KEY, mode);
    // Kalep tokens (shipped in @bolteu/clay-react/css) drive the page chrome.
    document.body.style.background = "var(--color-layer-floor-0-grouped)";
    document.body.style.color = "var(--color-content-primary)";
    document.body.style.margin = "0";
    document.body.style.minHeight = "100vh";
  }, [mode]);

  return (
    <BrowserRouter>
      <nav
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          padding: "var(--dimension-500) var(--dimension-600) 0",
        }}
      >
        <span />
        <Button
          variant="secondary"
          onClick={() => setMode((m) => (m === "light" ? "dark" : "light"))}
          aria-label="Toggle theme"
        >
          <Button.Label>{mode === "light" ? "Dark mode" : "Light mode"}</Button.Label>
        </Button>
      </nav>
      <Routes>
        <Route path="/" element={<Dashboard />} />
      </Routes>
      <DeployFooter />
    </BrowserRouter>
  );
}
