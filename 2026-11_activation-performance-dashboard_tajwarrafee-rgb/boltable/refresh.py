"""Weekly refresh: Databricks -> notebook pipeline -> storage.

start_scheduler() must be called once per process (app.py wraps it in
@st.cache_resource). Every deploy restarts the app and resets the timer, so it
also refreshes at startup when the saved data is missing or older than a week.
"""

from __future__ import annotations

import threading
import time
import traceback
from datetime import datetime, timedelta, timezone

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

import extract
import pipeline
import storage

SCHEDULE = CronTrigger(day_of_week="mon", hour=10, minute=0, timezone="Europe/Tallinn")
MAX_AGE = timedelta(days=7)

_lock = threading.Lock()
STATUS: dict = {"running": False, "last_error": None, "last_log": []}


def _log(message: str) -> None:
    line = f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M:%S} UTC {message}"
    print(f"[refresh] {line}", flush=True)
    STATUS["last_log"] = (STATUS["last_log"] + [line])[-20:]


def refresh_now(triggered_by: str = "schedule") -> bool:
    if not extract.has_credentials():
        _log("no Databricks credentials, refresh skipped: showing the bundled snapshot")
        return False
    if not _lock.acquire(blocking=False):
        _log("refresh already running, skipped")
        return False
    STATUS.update(running=True, last_error=None, last_log=[])
    start = time.time()
    try:
        _log(f"refresh started ({triggered_by})")
        raw = extract.extract_all(log=_log)
        refreshed_at = datetime.now(timezone.utc)
        outputs = pipeline.build_outputs(raw, today=refreshed_at.date())
        weekly = outputs["weekly_global"]
        meta = {
            "refreshed_at": refreshed_at.isoformat(),
            "triggered_by": triggered_by,
            "duration_s": round(time.time() - start),
            "latest_week": str(weekly["week"].max().date()) if len(weekly) else None,
            "rows": {name: len(df) for name, df in outputs.items()},
        }
        storage.save_outputs(outputs, meta)
        _log(f"refresh finished in {meta['duration_s']}s")
        return True
    except Exception as exc:
        STATUS["last_error"] = f"{type(exc).__name__}: {exc}"
        _log("refresh failed: " + STATUS["last_error"])
        traceback.print_exc()
        return False
    finally:
        STATUS["running"] = False
        _lock.release()


def refresh_in_background(triggered_by: str) -> None:
    threading.Thread(target=refresh_now, args=(triggered_by,), daemon=True).start()


def _is_stale() -> bool:
    try:
        meta = storage.load_meta()
    except Exception as exc:
        _log(f"could not read saved data: {exc}")
        return True
    if not meta:
        return True
    refreshed_at = datetime.fromisoformat(meta["refreshed_at"])
    return datetime.now(timezone.utc) - refreshed_at > MAX_AGE


def start_scheduler() -> BackgroundScheduler:
    scheduler = BackgroundScheduler()
    scheduler.add_job(refresh_now, SCHEDULE, id="weekly_refresh", max_instances=1, coalesce=True)
    scheduler.start()
    _log("scheduler started (Mondays 10:00 Europe/Tallinn)")
    if extract.has_credentials() and _is_stale():
        refresh_in_background("startup")
    return scheduler
