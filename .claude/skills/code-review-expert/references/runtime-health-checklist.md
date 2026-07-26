# Runtime Health Checklist

Static review reads what code SAYS. Runtime health checks see what code IS DOING in the actual deployed/local state. Bugs that only manifest from data drift, silent pipeline failures, or external-service changes will never be caught by reading source files alone.

This checklist exists because of past blind spots:
- A scheduled pipeline silently stopped updating data for a week (bug masked by stale outputs)
- 425 parquet files were saved with the wrong column shape; readers failed silently and downstream returned empty results
- An external login flow added a new popup that broke automation; nothing in the code changed

None of these would be caught by linting, typing, tests, or doc reviews. Run the checks below explicitly during full reviews.

## When to run

- Always in `full` mode (Phase 3g)
- Skip in `quick` mode unless the diff touches a critical path (auth, money, scheduled jobs, ingestion, scraping)
- If a check would take > 30s to run, ask the user whether to include it

## Categories

### 1. Production data freshness

For each data directory the project depends on, check the most recent file modification time and the latest **internal** date inside the data:

```bash
# File mtime — when the writer last touched the file
ls -lt data/raw/*.parquet | head -5

# Internal date — what the data actually covers (the last row's date)
# This gap reveals "writer ran but produced no fresh rows" silent failures
```

**Red flags:**
- Files with mtime > 7 days old when a daily pipeline is supposed to run
- Internal dates lagging mtime (writer ran but didn't fetch new data)
- Inconsistent freshness across files (some updated, some stuck)
- Empty files (size < expected baseline)

**Examples to check:**
- `backend/data/raw/*.parquet` — daily price data
- `backend/data/screener_results.json` — daily screener output
- `backend/data/paper_trade_log.parquet` — daily picks
- `backend/data/sentiment/*.parquet` — weekly news
- Cache tables in DB

### 2. Production data shape verification

For each source-of-truth data file, sample 1-2 files and verify the shape matches what readers expect:

```python
# Check columns, dtypes, index
df = pd.read_parquet(sample_file)
assert list(df.columns) == EXPECTED_COLUMNS
assert not isinstance(df.columns, pd.MultiIndex)  # common drift after lib upgrades
assert df.index.dtype == expected_dtype
```

**Red flags:**
- MultiIndex columns when readers use `columns=['col1']` projection
- Different column names across same-purpose files
- Mix of legacy and new schemas in the same directory
- Type changes (int → float, string → category)

**How to detect quickly:**
```bash
# For Parquet, parquet-tools or pyarrow
python -c "import pyarrow.parquet as pq; print(pq.read_schema('data/raw/SAMPLE.parquet'))"
```

### 3. Writer / Reader pair audit (schema AND staleness)

For every persisted artifact, identify:
- The function(s) that **write** it
- The function(s) that **read** it
- Whether they agree on schema
- **Whether all readers handle staleness consistently**

**Common drift sources:**
- Two writers exist; one is updated, the other still saves the old format
- Writer was updated; readers were not
- Reader uses `columns=[...]` projection that depends on a flat schema; writer started saving MultiIndex
- **Sibling reader inconsistency**: 5 places read `data/raw/*.parquet`; 1 has a "if file is older than 2 days, fall through to live fetch" path, the other 4 use whatever's on disk → some endpoints surface stale prices, others don't, depending on which call site the user hits

**Detection:**
```bash
# Find all to_parquet/save calls
grep -rn "to_parquet\|json.dump\|pickle.dump" backend/

# For each artifact, find the matching read calls
grep -rn "read_parquet.*data/raw\|json.load" backend/
```

For each pair, ask:
1. Is there exactly one writer? If multiple, do they agree?
2. Does the reader make assumptions (columns subset, dtype, index name) that the writer doesn't enforce?
3. What happens if the writer's library is upgraded? Will the reader still work?
4. **Do ALL readers check freshness, or only some? If only some, the others will silently serve stale data when the writer falls behind.** The fix is usually to centralize reads through a shared loader (e.g. `engine/market_data.fetch_historical_data`) that owns the staleness policy.

**Anti-pattern to flag**: any non-test file that calls `pd.read_parquet(<raw_data_path>)` directly. These should go through the project's data-access layer so the freshness check is applied uniformly.

### 4. Helper call-site completeness

Helper functions like `_dismiss_*`, `_cleanup_*`, `_normalize_*`, `_validate_*` exist for a reason. Find every place that **should** call them:

```bash
# Find the helper definition
grep -n "def _dismiss_passkey" backend/

# Find ALL call sites
grep -rn "_dismiss_passkey" backend/
```

**Red flags:**
- Helper exists but only called in 1 of N places where it's needed
- Helper is called AFTER the action that needs it (wrong order)
- Helper is called once outside a loop when it should be inside

**Concrete pattern to check:**
- Browser automation: any "dismiss popup" helper must be called at every wait/poll point, not just once at the end
- Cleanup helpers: must run in `finally` blocks
- Validation helpers: must run before persistence, not after

### 5. Critical path smoke test

For the project's top 3-5 user-facing flows, manually invoke each and check the output:

**Example flows for this kind of project:**
- Sync external data (SBI sync → CSV → DB upsert)
- Run daily pipeline (data collection → preprocess → train → screen → paper trade)
- Hit each API endpoint with a sample request and verify non-empty response
- Render the main UI page and check for empty states

**What to look for:**
- Endpoint returns 200 but body is `{"daytrade": [], "swing": []}`
- Pipeline exits 0 but no files were written
- DB query returns rows but all NULL in critical columns
- UI loads but a section is blank

**The "200 OK + empty body" anti-pattern is the most dangerous** — every other check passes but the user sees nothing.

### 6. External integration drift

List every external service the project touches, then ask "when was this last verified to work?":

| Integration | Last verified | How to verify |
|-------------|---------------|---------------|
| SBI auto-sync | ? | `uv run python -m engine.sbi_sync` |
| yfinance | ? | `uv run python -c "import yfinance; print(yfinance.download('9984.T', period='5d'))"` |
| OpenAI sentiment | ? | sample 1 article |
| Supabase | ? | `SELECT NOW()` |
| Claude CLI | ? | `claude --version` |

**Red flags:**
- Integration not verified in > 30 days
- Integration relies on HTML/CSS selectors of a third-party site (very fragile)
- API library is pinned to an old version

### 7. Recent log inspection

Read the most recent application logs / scheduled job output:

```bash
# If the project has a log file
tail -200 logs/daily_update.log | grep -iE "error|warn|fail"

# If using systemd / cron
journalctl --since "7 days ago" -u myservice

# If GitHub Actions
gh run list --limit 10
```

**Red flags:**
- Same warning repeated daily but never escalated
- Errors marked as "non-fatal" that have been happening for weeks
- Scheduled jobs that "succeeded" but processed 0 items
- Long-running jobs that suddenly drop to fast completion (often indicates skipped work)

### 8. Background task / cron verification

If the project has scheduled jobs:

- **Is the task registered AND has it actually fired?** "Registered" is not the same as "running". A task created today with a weekly trigger may not run for up to 7 days; in that window it looks healthy in `Get-ScheduledTask` but has produced nothing.
- Was the last scheduled run successful?
- How long did it take vs the historical average?
- Did it produce the expected number of output files / rows / events?

```bash
# Windows: check Last Run Time + Last Result, not just registration
schtasks //Query //TN "TaskName" //V //FO LIST | grep -E "Last Run|Last Result|Next Run"
# Last Run = "11/30/1999" (or similar epoch sentinel) → task has NEVER fired
# Last Result = 0x0 → success; anything else → failure code

# Linux/macOS cron equivalent
grep CRON /var/log/syslog | tail -20
systemctl list-timers --all
journalctl -u <service> --since "7 days ago"

# Number of files modified by the last run
find data/raw -mtime -1 | wc -l    # should match expected ticker count
```

**Anti-pattern to flag**: a recently re-registered task whose `Last Run = never`. Reviewers (and humans) often see "task is registered, schedule looks correct" and stop there — but the task has produced zero work since registration. Always check `Last Run`, not just registration.

### 9. Database integrity spot checks

For each critical table:
- Row count today vs 7 days ago
- Latest `updated_at` / `created_at`
- Any `NULL` in columns that should be NOT NULL
- Foreign key references that point to deleted parents

### 10. Cache validity

If the project has caches (file, in-memory, Redis):
- Cache hit rate (if measured)
- Are cache TTLs honored, or stuck forever?
- Is cache invalidation triggered on writes?

**Specific anti-patterns to flag in static review:**

1. **Module-level dict cache without TTL** — the classic "load once, serve forever" bug:
   ```python
   _cache: dict = {"data": None}

   def get_thing():
       if _cache["data"] is not None:   # BUG: never expires
           return _cache["data"]
       _cache["data"] = expensive_load()
       return _cache["data"]
   ```
   In a long-running server process this means the value loaded at startup is served for the lifetime of the process. Fix: store `loaded_at` alongside `data` and compare against a `_TTL_SEC` constant using `time.monotonic()`.

2. **Cache populated but never invalidated on write** — the writer side updates the underlying source but doesn't bust the cache. Reads continue to return the pre-write value.

3. **TTL only checked on cache HIT, not cache MISS** — variant where the cache has a TTL field but the freshness check is skipped on the first load of a process.

4. **Disk cache without staleness check** — code reads `cache.parquet` and uses it without comparing mtime. If the underlying writer has stopped running, the cache becomes load-bearing forever.

**Detection:**
```bash
# Find module-level dict caches
grep -rn "^_.*cache.*[:=].*dict\|^_.*cache.*[:=].*{" backend/

# Find any cache reads — manually verify each has a TTL guard
grep -rn "cache\[.*data" backend/

# Find disk-cache reads without mtime comparison
grep -rn "read_parquet.*cache" backend/
```

### 11. Dockerfile / system ABI dependencies

Python wheels often link against system shared libraries (`.so` / `.dll`). These are NOT installed by `pip` / `uv` — they must be present in the OS image. Slim base images (`python:3.12-slim`, `alpine`) deliberately omit them.

Symptom: deploy fails at import time (not at build time) with:
```
OSError: lib<something>.so.<n>: cannot open shared object file: No such file or directory
```

**For each Python dependency that has a native component, verify the matching system package is installed in the Dockerfile.**

#### Common ABI dependency map

| Python package | Required system package(s) | Symptom if missing |
|----------------|---------------------------|---------------------|
| `lightgbm` | `libgomp1` | `libgomp.so.1: cannot open shared object file` |
| `xgboost` | `libgomp1` | same |
| `catboost` | `libgomp1` | same |
| `scikit-learn` (some ops) | `libgomp1` | same (only on parallel paths) |
| `opencv-python` (cv2) | `libgl1`, `libglib2.0-0` | `libGL.so.1: cannot open shared object file` |
| `lxml` (some wheels) | `libxml2`, `libxslt1.1` | linker error at install or import |
| `pyodbc` | `unixodbc`, `unixodbc-dev` | `libodbc.so.2: cannot open shared object file` |
| `psycopg2` (non-binary) | `libpq-dev`, `gcc` | build fails at install |
| `weasyprint` | `libcairo2`, `libpango-1.0-0`, `libgdk-pixbuf2.0-0`, `libffi-dev` | runtime errors |
| `pyaudio` | `portaudio19-dev` | build fails at install |
| `pdf2image` | `poppler-utils` | `Unable to get page count. Is poppler installed?` |
| `tesseract` (`pytesseract`) | `tesseract-ocr` | `tesseract is not installed` |
| `playwright` (Chromium runtime) | many — use `playwright install-deps` | many libnss/libxkb errors |
| `pycurl` | `libcurl4-openssl-dev` | build fails |
| `cryptography` (older versions) | `libssl-dev`, `libffi-dev` | build fails |
| `cairocffi`, `pycairo` | `libcairo2` | runtime errors |
| `mysqlclient` | `default-libmysqlclient-dev` | build fails |
| `pdfminer.six` (older) | `poppler-utils` | runtime errors |
| `numba` (LLVM JIT) | usually OK in slim, but `llvmlite` may need `llvm-<n>-dev` for some envs | varies |

#### Detection strategy

1. **List native deps in pyproject.toml / requirements.txt**:
   ```bash
   grep -E "lightgbm|xgboost|opencv|lxml|pyodbc|weasyprint|playwright" pyproject.toml
   ```

2. **For each native dep, grep the Dockerfile for the matching `apt-get install`**:
   ```bash
   grep -E "libgomp1|libgl1|libxml2|unixodbc" Dockerfile
   ```

3. **If a native dep exists with no matching system package** → **finding** (P0 if production, P1 if dev).

4. **Test in a clean container**:
   ```bash
   docker build -t app-test .
   docker run --rm app-test python -c "import lightgbm; print('ok')"
   ```
   Run this for each native module the app imports. Catches the issue before deploy.

#### Why static review misses this

- `pip install lightgbm` succeeds even without `libgomp1` (it just installs the wheel)
- The error only fires on **first import**, not at install time
- Local dev machines (Windows / macOS / full Linux) usually have these libs system-wide
- Lint, typecheck, unit tests, and even `pytest` may all pass — they only fail when the actual ML import path is exercised on the slim image
- CI test images often differ from production deploy images

#### Fix template

```dockerfile
FROM python:3.12-slim

# System libraries required by Python wheels
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libgomp1 \
        # add more here as native deps are added
    && rm -rf /var/lib/apt/lists/*

RUN pip install uv
COPY pyproject.toml uv.lock* ./
RUN uv sync --no-dev
...
```

Always combine `apt-get update` and `install` in a single `RUN` (cache layer correctness) and clean `/var/lib/apt/lists/*` to keep image small.

#### Multi-stage builds caveat

If using multi-stage builds, the system libraries must be installed in the **runtime stage**, not just the build stage:

```dockerfile
# Stage 1: build (may have full toolchain)
FROM python:3.12 AS builder
...

# Stage 2: runtime (slim) — STILL needs libgomp1!
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app /app
```

Forgetting this is a very common bug.

---

## Detection strategy

For a full review, do these in order:

1. **`find . -mtime -7 -type f`** in data dirs → spot stale pipelines first
2. **`pq.read_schema` on 1 sample per data dir** → spot shape drift
3. **grep helper definitions, then grep all call sites** → spot incomplete adoption
4. **For each writer, find readers; for each reader, find writers** → spot pair drift
5. **Run 1 sample query against each major API endpoint** → catch empty-result regressions
6. **`tail -200` of any log file present** → catch slow drift / silent failures

Each step should take < 2 minutes. If a step would take longer, ask the user whether to include it.

## Output format

```markdown
## Runtime Health Findings

### P0 - Pipeline broken
- `data/raw/*.parquet` — 425/2002 files have MultiIndex columns; manager.py reader fails silently → screener returns 0 results
- `data/raw/*.parquet` — last update mtime is 7 days ago; daily_update has been failing silently

### P1 - Helper not called everywhere needed
- `_dismiss_passkey` exists but is only called in `_dismiss_notices` (which runs AFTER login). Should also be called inside the login polling loop.

### P2 - External integration not verified
- SBI sync hasn't been run in 14 days; SBI may have changed UI
- Last successful daily_update: 2026-03-31

### P3 - Stale data freshness vs file mtime
- `paper_trade_log.parquet` mtime is today, but `actual_ret_5d` is None for all rows (evaluator can't find raw data)
```

## What this checklist does NOT catch

Be honest in the Coverage declaration:
- It does not run a full integration test suite
- It does not catch bugs that need a specific user action to trigger
- It does not catch race conditions that only manifest under load
- It does not catch security issues that require an attacker
- It samples data files; rare-shape outliers may slip through
- It cannot predict future drift (e.g., yfinance will change something next month)

These need a real test suite + monitoring + alerting. Code review can only sample reality.
