# Project-Specific Checklist — Stock Trade Logger

This file captures the anti-patterns and runtime checks that are unique to **this** codebase. Generic checks live in the other reference files; only Stock Trade Logger conventions and known landmines belong here.

When reviewing a different project, **do not load this file**. Either remove the Phase 3i bullet from `SKILL.md`, or copy this template and rewrite the entries against the new project's history.

---

## Anti-patterns from past incidents

Each entry is a rule the codebase learned the hard way. The "Why" line gives the context so a future reviewer can judge edge cases instead of mechanically applying the rule.

### A1. Raw parquet direct reads bypass the staleness fallback

**Rule**: Any production code that needs OHLCV / volume / price data for a JP or US ticker MUST go through `engine.market_data.fetch_historical_data` (or a wrapper that does), not `pd.read_parquet("data/raw/{ticker}.parquet")`.

**Why**: `daily_update --quick` only refreshes the top-100 liquidity bucket and rotates members in/out day-to-day. Tickers that drop out of the top 100 silently keep stale raw parquets for days or weeks. `fetch_historical_data` fronts a process-cache + Supabase cache + yfinance live fetch chain, so every caller benefits from the same staleness policy. Direct reads silently serve data that's days old.

**How to apply**:
- During quick reviews: grep `read_parquet.*data/raw` in any newly-touched file. Each hit is a P1 unless the call site is a CLI script that doesn't run inside the live server (training, backtesting, one-off analysis).
- During full reviews: grep the entire backend for the same pattern. Sample paper_trade.py, predict_lgbm.py, trade_advisor.py, and intraday/backtest_engine.py to confirm they use the wrapper.

**Detection:**
```bash
grep -rn "read_parquet.*data/raw" backend/ --include="*.py" | grep -v tests/
```

**Known acceptable exceptions** (do not flag):
- `ml/scripts/preprocess_universal_data.py` and other batch training scripts run from cron — they iterate the entire raw directory by design
- `tests/` — fixtures and assertions

### A2. Module-level dict cache without TTL

**Rule**: A module-level `_cache: dict = {"data": None}` style cache MUST track `loaded_at` (via `time.monotonic()`) and a `_TTL_SEC` constant. The TTL must be checked on every read, not just the first one.

**Why**: We hit a real incident where `_vix_cache` and `_global_cache` in `backend/ml/predict_lgbm.py` loaded the VIX value at server startup and served the same number for days, even after the underlying parquet had been updated. The frontend showed a stale VIX next to AI rankings until the server was restarted. The fix was to add a TTL with monotonic timestamps and an on-disk staleness check that falls back to a live yfinance fetch.

**How to apply**: any new `_cache` or process-level memo in backend code must have:
1. `loaded_at` timestamp stored alongside the data
2. Read path that compares `monotonic() - loaded_at` against a TTL constant
3. Fallback path when the on-disk source itself is stale (so a long-running server can recover after the writer falls behind)

See `backend/ml/predict_lgbm.py:_load_global_market_data` for the canonical pattern.

### A3. `daily_update --quick` top-100 problem

**Rule**: Any code that consumes "yesterday's screener picks" or "this week's paper trades" cannot assume the underlying raw data for those tickers is fresh. The picks rotate, and tickers that drop out of the top-100 stop receiving raw updates.

**Why**: paper_trade evaluation was failing for ~80% of pending picks because the picks' tickers were no longer in the daily collection set. The fix was a yfinance fallback in `evaluate_past()`.

**How to apply**: when reviewing any function that loads `data/raw/{ticker}.parquet` for a ticker that came from a stored list (paper_trade_log, historical alerts, ml_rankings rows older than today), require either (a) the staleness fallback from A1, or (b) an explicit comment `# only called for top-100 tickers` with a justification.

### A4. Supabase parallel upsert storms

**Rule**: When iterating over many tickers in a `ThreadPoolExecutor`, do not let each worker independently hit `stock_cache` (or any single Supabase table). Front the call site with the in-process cache from `engine/market_data.py`, and consider passing `force_refresh=False` so the cache layer can short-circuit.

**Why**: `/intraday/scan` was triggering Supabase 57014 statement timeouts because all 200+ workers were issuing parallel SELECT/UPSERT against `stock_cache`. The cache layer now has a process-level dict that absorbs the duplicate hits and the table pressure dropped to near-zero.

**How to apply**: any `ThreadPoolExecutor(max_workers > 4)` whose worker function eventually touches Supabase needs an in-process dedup layer.

### A5. Frontend calculator state must be persisted

**Rule**: Components in `frontend/components/trades/` and `frontend/components/lab/` that hold per-trade input state (entry, stop, target, calculator inputs) must persist that state to `localStorage`. Use one storage key for "settings" (capital, risk %, lot size) and a separate key for "prices" so the user can clear one without the other.

**Why**: `PositionSizeCalculator` was losing entry/stop/target on every tab switch because the parent component (`LabHome`) unmounts the sidebar when `mobileSection` changes. The state was useState-only.

**How to apply**: any new calculator/form component that the user enters numbers into and expects to come back to needs `localStorage.setItem` on change + `loadX()` on mount.

### A6. Silent skip in pipeline loops

**Rule**: Any loop that iterates over work items in `backend/ml/scripts/` and uses `continue` to skip items must categorize the skip reason and emit a summary log at the end. See code-quality-checklist for the pattern.

**Why**: `evaluate_past()` in paper_trade.py was silently skipping picks because the raw parquet was stale OR the calendar window was too narrow. The two cases require completely different fixes (re-collect data vs wait), but the user couldn't tell them apart from the log line `"Evaluation complete. 5/50 picks have actual returns."`.

**How to apply**: any new `for item in items:` block in the ml pipeline needs `skip_reasons: defaultdict(int)` tracking and a summary at the end.

### A7. Dead `/ml/...` endpoints with no consumer

**Rule**: Before adding a new endpoint to `backend/routers/ml.py`, verify there is at least one frontend consumer planned. Before keeping an existing endpoint, verify it's still used by grep against `frontend/`.

**Why**: `/ml/backtest-stats` had been in `routers/ml.py` for months serving `{"status": "not_available"}` because the script that was supposed to populate `backtest_stats.json` never existed. No frontend consumed it.

**How to apply**: full reviews should run `grep -rn "/ml/{endpoint}" frontend/` for every route in `routers/ml.py` and flag the orphans.

---

## Project-specific runtime checks (Phase 3g extension)

These augment the generic runtime-health checks with checks that are specific to the data pipeline of this project.

### R1. AI ranking freshness

```python
# Should be today's date or yesterday's
from database import get_supabase
db = get_supabase()
r = db.table("ml_rankings").select("run_date").order("run_date", desc=True).limit(1).execute()
print(r.data[0]["run_date"] if r.data else "EMPTY")
```
**Red flag**: `run_date` more than 2 days behind today → daily pipeline broken or `rank_tickers.py` failing silently.

### R2. JP price data freshness

```bash
ls -lt backend/data/raw/*.T.parquet | head -3
```
And:
```python
import pandas as pd
df = pd.read_parquet("backend/data/raw/9984.T.parquet")
print(df.index[-1])  # should be most recent trading day
```
**Red flag**: most recent date older than 2 trading days → JP collection broken.

### R3. US price data freshness (for cascade)

```python
import pandas as pd
df = pd.read_parquet("backend/data/raw_us/AAPL.parquet")
print(df.index[-1])  # US is ~1 day behind JP
```
**Red flag**: more than 7 days old → weekly pipeline never fired or US collection broken.

### R4. VIX cache freshness

```python
import pandas as pd
df = pd.read_parquet("backend/data/vix_levels.parquet")
print(df.index[-1], df["VIX_Close"].iloc[-1])
```
**Red flag**: more than 24h since last entry → JP daily collection broken (VIX is a side-effect of `collect_universal_data`).

### R5. Paper trade evaluation health

```python
import pandas as pd
df = pd.read_parquet("backend/data/paper_trade_log.parquet")
total = len(df)
filled = df["actual_ret_5d"].notna().sum()
old_unfilled = df[(df["actual_ret_5d"].isna()) & (pd.Timestamp.now() - pd.to_datetime(df["date"]) > pd.Timedelta(days=10))]
print(f"Filled: {filled}/{total}, old unfilled: {len(old_unfilled)}")
```
**Red flag**: more than 5 picks pending with `pick_date < today - 10 days` → `evaluate_past()` is failing silently. Check whether raw data fallback is actually working.

### R6. Scheduled task LastRun (Windows)

```bash
schtasks //Query //TN "StockTradeLogger_Daily" //V //FO LIST | grep -E "Last Run|Last Result"
schtasks //Query //TN "StockTradeLogger_Weekly" //V //FO LIST | grep -E "Last Run|Last Result"
```
**Red flag**: `Last Run = 11/30/1999` (epoch sentinel) → task is registered but has never fired. **Always check this in addition to "is registered".**

### R7. Supabase ml_paper_trades and ml_screener_results consistency

```python
db = get_supabase()
for tbl in ["ml_rankings", "ml_screener_results", "ml_paper_trades"]:
    r = db.table(tbl).select("*").order("run_date" if tbl != "ml_paper_trades" else "date", desc=True).limit(1).execute()
    print(tbl, r.data[0] if r.data else "EMPTY")
```
**Red flag**: any table more than 2 days behind today.

---

## Files that need extra attention

These files are landmines because they touch multiple concerns or have been the source of past bugs. Reviews that touch them should pull in the relevant rule above.

| File | Why it needs care | Apply rule |
|------|------------------|------------|
| `backend/engine/market_data.py` | Sole source of truth for the data-access layer; cache TTL bugs cascade everywhere | A2, A4 |
| `backend/ml/predict_lgbm.py` | Holds process caches that long-running servers depend on | A1, A2 |
| `backend/ml/scripts/paper_trade.py` | Pipeline loop that historically skipped silently | A1, A3, A6 |
| `backend/ml/trade_advisor.py` | Feeds raw price data into the LLM; stale prices = stale advice | A1 |
| `backend/intraday/backtest_engine.py` | Reads raw parquet directly inside the candle pipeline | A1 |
| `backend/routers/ml.py` | Multiple endpoints; some have been dead code | A7 |
| `backend/routers/intraday.py` | Spawns ThreadPoolExecutor with high parallelism against Supabase | A4 |
| `frontend/components/trades/PositionSizeCalculator.jsx` | Per-trade state lost on remount | A5 |
| `frontend/components/lab/LabHome.jsx` | Mobile section switches unmount sidebar children | A5 |

---

## How to use this file in a review

1. During Phase 3i (full reviews), load this file alongside the generic checklists.
2. For each anti-pattern (A1–A7), run the detection grep and flag any new violations introduced by the diff.
3. For each runtime check (R1–R7), execute the snippet and flag stale results as P1.
4. Cross-reference the "Files that need extra attention" table — if the diff touches one of those files, every linked rule must be considered.

When reporting findings, **cite the rule ID** (e.g. "A1: raw parquet direct read at predict_lgbm.py:372") so the user can trace the rationale back to this file.
