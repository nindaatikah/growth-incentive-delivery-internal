"""Read and write the dashboard tables.

DATA_BUCKET set (Boltable File Storage): parquet in S3 under outputs/.
Otherwise a local folder: LOCAL_DATA_DIR, default ./local_data/outputs on a laptop and /tmp/outputs on Boltable
(only /tmp is writable there, and it is wiped on restart).

Until a refresh has written a full set of tables, reads fall back to the snapshot committed in ./data.
"""

from __future__ import annotations

import io
import json
import os
from pathlib import Path

import pandas as pd

BUCKET = os.environ.get("DATA_BUCKET")
PREFIX = "outputs/"
_DEFAULT_LOCAL = "/tmp/outputs" if os.environ.get("BOLTABLE_GIT_SHA") else Path(__file__).parent / "local_data" / "outputs"
LOCAL_DIR = Path(os.environ.get("LOCAL_DATA_DIR", _DEFAULT_LOCAL))
BUNDLED_DIR = Path(__file__).parent / "data"


def _s3():
    import boto3

    return boto3.client("s3", region_name="eu-central-1")


def _put(name: str, body: bytes) -> None:
    if BUCKET:
        _s3().put_object(Bucket=BUCKET, Key=PREFIX + name, Body=body)
    else:
        LOCAL_DIR.mkdir(parents=True, exist_ok=True)
        (LOCAL_DIR / name).write_bytes(body)


def _get_primary(name: str) -> bytes | None:
    if BUCKET:
        s3 = _s3()
        try:
            return s3.get_object(Bucket=BUCKET, Key=PREFIX + name)["Body"].read()
        except s3.exceptions.NoSuchKey:
            return None
    path = LOCAL_DIR / name
    return path.read_bytes() if path.exists() else None


def _get_bundled(name: str) -> bytes | None:
    path = BUNDLED_DIR / name
    return path.read_bytes() if path.exists() else None


def _reader():
    # meta.json is written last, so its presence means the primary store holds a full set of tables.
    return _get_primary if _get_primary("meta.json") is not None else _get_bundled


def save_outputs(outputs: dict[str, pd.DataFrame], meta: dict) -> None:
    for name, df in outputs.items():
        buf = io.BytesIO()
        df.to_parquet(buf, index=False)
        _put(f"{name}.parquet", buf.getvalue())
    _put("meta.json", json.dumps(meta, default=str).encode())


def load_meta() -> dict | None:
    body = _reader()("meta.json")
    return json.loads(body) if body else None


def load_outputs(names: list[str]) -> dict[str, pd.DataFrame]:
    get = _reader()
    out = {}
    for name in names:
        body = get(f"{name}.parquet")
        if body is not None:
            out[name] = pd.read_parquet(io.BytesIO(body))
    return out
