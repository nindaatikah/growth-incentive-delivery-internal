# AGENTS.md

Instructions for AI coding agents (Cursor, Claude Code, ChatGPT, Codex, etc.) generating or editing code in this repository.

## About this app

This is a Streamlit app deployed on **Boltable**, Bolt's internal "push-to-live" hosting platform.

- **Stack**: Python + [Streamlit](https://streamlit.io/) in `app.py`.
- **Production URL**: `https://<repo-name>.boltable.eu`.
- **Access**: internal-only — gated by NetBird VPN, with optional Bolt SSO on top. No public internet exposure. Don't write code that assumes anonymous external callers.
- **Audience**: the user is likely a non-engineer ("vibe coder"). Streamlit is designed for exactly this — keep code simple and use Streamlit's built-in widgets rather than building custom UI.

## Boltable platform guidance

For everything about *how Boltable works* — build/deploy mechanics, storage (S3/EBS), the managed database and migrations, Secrets, the LLM Gateway, Google Workspace (WIF, including the verbatim auth client), SSO-based access control, resource tiers, and debugging — see the Boltable skills vendored in this repo at `.agents/skills/`:

- [boltable-core](.agents/skills/boltable-core/SKILL.md) — platform overview, deploying, stack/structure, access control, resource tiers, debugging
- [boltable-storage](.agents/skills/boltable-storage/SKILL.md) — File Storage (S3), Persistent Storage (EBS), writable paths
- [boltable-database](.agents/skills/boltable-database/SKILL.md) — managed MySQL + migrations
- [boltable-integrations](.agents/skills/boltable-integrations/SKILL.md) — Secrets, LLM Gateway, Google Workspace (WIF)

Claude Code loads these automatically (`.claude/skills` is a symlink to `.agents/skills`); Cursor reads `.agents/skills` directly, no setup needed. For any other agent, or when working in a Boltable repo that doesn't vendor these files, install the [Boltable plugin](https://aimarketplace.bolt.eu/?plugins=180001) from the AI Marketplace instead — same content, kept in sync by hand for now.

If the coding tool in use doesn't support skills or plugins at all, read [Boltable docs](https://portal.boltable.eu/docs/boltable) directly instead of guessing whether a feature exists.

### Platform essentials (fallback, even with the skills present)

- Push to `main` deploys automatically. Add the GitHub repo topic `noautodeploy` to disable.
- **Don't change the `Procfile`.** The starter's `web: streamlit run app.py --server.port=8080 --server.address=0.0.0.0 --server.headless=true` is required — headless mode disables first-run prompts, and `0.0.0.0:8080` is what Kubernetes health checks hit.
- The filesystem is read-only except `/tmp` — writing anywhere else fails at runtime with `OSError: [Errno 30] Read-only file system`. This works on a laptop and only fails once deployed.
- Some Python libraries write to `$HOME` on import and crash on this read-only filesystem — matplotlib (font cache), Hugging Face, anything using `~/.cache`. Redirect them to `/tmp` before importing, e.g. `os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")`.
- The app runs as a single Kubernetes pod (one replica). A restart wipes `st.session_state`, `@st.cache_data`, and `@st.cache_resource` — useful within a session, not for persistence.

### Python-specific footgun: stdlib `sqlite3` doesn't import on Boltable

The Paketo cpython buildpack's runtime image doesn't ship `libsqlite3.so.0`, so `import sqlite3` raises `ImportError: libsqlite3.so.0: cannot open shared object file` at startup — this is a Boltable platform gap, not something you did wrong. If the app needs SQLite (see the `boltable-storage` skill for when that's the right call), add `pysqlite3-binary` to `requirements.txt` and use it as a drop-in replacement:

```python
try:
    import pysqlite3 as sqlite3
except ImportError:
    import sqlite3
```

For MySQL (the managed database), this doesn't apply — use **PyMySQL** (pure Python) as covered in the `boltable-database` skill.

## Folder structure

```
app.py            # Streamlit entry point (referenced by Procfile)
requirements.txt  # Python dependencies (must include `streamlit`)
Procfile          # Defines the streamlit run command
```

- The starter is intentionally minimal. As the app grows, organize code into modules (e.g. `data.py`, `charts.py`) and import them from `app.py`.

## Local development

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
streamlit run app.py
```

Then open `http://localhost:8501` (Streamlit's default local port; production runs on `8080` via the `Procfile`).

If the app uses the managed MySQL database, note it's reachable **only from the deployed app, not from your laptop**. So locally the app will show its "database initializing" state until you deploy — that's expected, and the rest of the UI still works. To work on DB features locally, point the connection at a reachable MySQL (e.g. a local one) via a gitignored `.env`.

## Common tasks

**"Cache an expensive computation."**
→ Use `@st.cache_data` for serializable results, `@st.cache_resource` for connections/models. Both are in-memory and wiped on restart — that's fine for derived data.

**"Add Google Workspace access."**
→ The verbatim `google_auth.py` client (wrap the credentials function in `@st.cache_resource` so it's built once per process and survives reruns) is in [boltable-integrations](.agents/skills/boltable-integrations/SKILL.md) — drop it in as-is, don't hand-roll a replacement.

**"How do I push my code to GitHub?"**
→ Recommend Cursor or VS Code's built-in **Source Control** panel — both editors handle GitHub sign-in automatically, no token setup. For terminal users, install the [GitHub CLI](https://cli.github.com/) and run `gh auth login`, or set up an [SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh). **Don't tell the user to create a GitHub Personal Access Token (PAT) just to push code** — creating one in the Boltable GitHub org requires admin approval, and it's not needed for a plain push.

For anything else (storage, database, secrets, LLM/AI features, SSO, deploy/runtime debugging), see the **Boltable skills** — see above.

## Getting help

- Slack: [#boltable-support](https://bolt.enterprise.slack.com/archives/C0AFQCGN62F)
- Your applications: [https://portal.boltable.eu/repos](https://portal.boltable.eu/repos)
- Platform docs: [https://portal.boltable.eu/docs/boltable](https://portal.boltable.eu/docs/boltable)
