import { Component, StrictMode, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "@bolteu/clay-react/css";

/** Shows the error instead of a blank page if the page crashes while rendering. */
class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };
  static getDerivedStateFromError(error: Error) { return { error }; }
  componentDidCatch(error: Error) { console.error("Page crashed:", error); }
  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <main style={{ padding: 24, display: "grid", gap: 12, maxWidth: 900 }}>
        <h1 style={{ margin: 0 }}>Something went wrong</h1>
        <p style={{ margin: 0 }}>The page crashed while showing the data. Reload the page; if it happens again, send this message to the dashboard owner.</p>
        <pre style={{ whiteSpace: "pre-wrap", padding: 12, border: "1px solid var(--color-border-separator)", borderRadius: 8 }}>{String(error.stack ?? error.message)}</pre>
        <button onClick={() => location.reload()} style={{ width: "fit-content", padding: "6px 14px" }}>Reload</button>
      </main>
    );
  }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
);
