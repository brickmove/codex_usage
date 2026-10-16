#!/usr/bin/env python3
"""Compare the reader against CC Switch's correlated dedup query on one private snapshot."""
import argparse
import datetime as dt
import json
import math
from pathlib import Path
import sqlite3
import subprocess
import tempfile

parser = argparse.ArgumentParser(description="只读取得 Codex 统计快照，并核对 CC Switch 统计口径")
parser.add_argument("--database", default="~/.cc-switch/cc-switch.db")
parser.add_argument("--executable", default=".build/debug/CodexUsage")
args = parser.parse_args()

# Copy only statistics columns; provider settings and credentials are never copied.
columns = ["app_type", "model", "input_tokens", "output_tokens", "cache_read_tokens",
           "cache_creation_tokens", "total_cost_usd", "status_code", "created_at",
           "data_source", "input_token_semantics"]
rollup_columns = ["date", "app_type", "request_count", "input_tokens", "output_tokens",
                  "cache_read_tokens", "cache_creation_tokens", "total_cost_usd", "input_token_semantics"]


def fresh(alias):
    return f"""CASE WHEN {alias}.input_token_semantics = 2 THEN {alias}.input_tokens
        WHEN {alias}.input_token_semantics = 1
         AND {alias}.input_tokens >= {alias}.cache_read_tokens + {alias}.cache_creation_tokens
        THEN {alias}.input_tokens - {alias}.cache_read_tokens - {alias}.cache_creation_tokens
        WHEN {alias}.input_token_semantics = 0 AND {alias}.input_tokens >= {alias}.cache_read_tokens
        THEN {alias}.input_tokens - {alias}.cache_read_tokens ELSE {alias}.input_tokens END"""


# Adapted from CC Switch effective_usage_log_filter, rather than the app's NOT IN optimization.
effective = """NOT (
    COALESCE(l.data_source,'proxy') IN ('session_log','codex_session','gemini_session','opencode_session')
    AND EXISTS (SELECT 1 FROM proxy_request_logs p
        WHERE COALESCE(p.data_source,'proxy')='proxy' AND p.app_type=l.app_type
        AND p.status_code>=200 AND p.status_code<300
        AND p.input_tokens=l.input_tokens AND p.output_tokens=l.output_tokens
        AND p.cache_read_tokens=l.cache_read_tokens
        AND (p.cache_creation_tokens=l.cache_creation_tokens
             OR (l.cache_creation_tokens=0 AND l.data_source IN ('codex_session','gemini_session','opencode_session'))
             OR (p.cache_creation_tokens=0 AND p.input_token_semantics=0 AND l.data_source='codex_session'))
        AND p.created_at BETWEEN l.created_at-600 AND l.created_at+600
        AND (LOWER(p.model)=LOWER(l.model) OR LOWER(p.model)='unknown' OR LOWER(l.model)='unknown'))
    )"""

source = sqlite3.connect(Path(args.database).expanduser().resolve().as_uri() + "?mode=ro", uri=True)
source.execute("PRAGMA query_only=ON")
source.execute("BEGIN")
with tempfile.TemporaryDirectory(prefix="codex-usage-verify-") as directory:
    path = Path(directory) / "statistics.db"
    snapshot = sqlite3.connect(path)
    for table, fields in [("proxy_request_logs", columns), ("usage_daily_rollups", rollup_columns)]:
        definitions = ",".join(f"{name} {'TEXT' if name in ['app_type','model','total_cost_usd','data_source','date'] else 'INTEGER'}" for name in fields)
        snapshot.execute(f"CREATE TABLE {table} ({definitions})")
        snapshot.executemany(f"INSERT INTO {table} VALUES ({','.join('?' for _ in fields)})",
                             source.execute(f"SELECT {','.join(fields)} FROM {table} WHERE app_type='codex'"))
    snapshot.execute("CREATE INDEX dedup ON proxy_request_logs(app_type,COALESCE(data_source,'proxy'),input_tokens,output_tokens,cache_read_tokens,created_at,cache_creation_tokens)")
    snapshot.commit()
    source.rollback()
    source.close()
    for preset in ["today", "last24Hours", "week", "month", "all"]:
        actual = json.loads(subprocess.check_output([str(Path(args.executable).resolve()), "--diagnose", "--statistics-only",
                            "--database", str(path), "--range", preset], text=True))["statistics"]
        start = dt.datetime.fromisoformat(actual["start"].replace("Z", "+00:00")).astimezone()
        end = dt.datetime.fromisoformat(actual["end"].replace("Z", "+00:00")).astimezone()
        detail = snapshot.execute(f"""SELECT COUNT(*),COALESCE(SUM(CAST(l.total_cost_usd AS REAL)),0),
            COALESCE(SUM({fresh('l')}),0),COALESCE(SUM(l.output_tokens),0),
            COALESCE(SUM(l.cache_creation_tokens),0),COALESCE(SUM(l.cache_read_tokens),0)
            FROM proxy_request_logs l WHERE l.app_type='codex' AND l.created_at BETWEEN ? AND ? AND {effective}""",
            (int(start.timestamp()), int(end.timestamp()))).fetchone()
        first = start.date() + (dt.timedelta(days=1) if (start.hour, start.minute, start.second) != (0, 0, 0) else dt.timedelta())
        last = end.date() - (dt.timedelta() if (end.hour, end.minute) == (23, 59) else dt.timedelta(days=1))
        rollup = snapshot.execute(f"""SELECT COALESCE(SUM(r.request_count),0),COALESCE(SUM(CAST(r.total_cost_usd AS REAL)),0),
            COALESCE(SUM({fresh('r')}),0),COALESCE(SUM(r.output_tokens),0),
            COALESCE(SUM(r.cache_creation_tokens),0),COALESCE(SUM(r.cache_read_tokens),0)
            FROM usage_daily_rollups r WHERE app_type='codex' AND date BETWEEN ? AND ?""",
            (first.isoformat(), last.isoformat())).fetchone()
        count, cost, f, o, w, h = [a + b for a, b in zip(detail, rollup)]
        hit_rate = h / (f + w + h) if f + w + h else 0
        assert actual["totalRequests"] == count, (preset, "requests")
        assert actual["realTotalTokens"] == f + o + w + h, (preset, "tokens")
        assert math.isclose(actual["storedCostUSD"], cost, rel_tol=0, abs_tol=1e-6), (preset, "cost")
        assert math.isclose(actual["cacheHitRate"], hit_rate, rel_tol=0, abs_tol=1e-12), (preset, "hit rate")
        print(f"通过 {preset}: {count:,} 次请求，${cost:.6f}，{f+o+w+h:,} Tokens，缓存命中率 {hit_rate:.4%}")
    snapshot.close()
