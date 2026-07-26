# Observability Checklist

Production issues are only debuggable if the code emits enough signal. Scan for gaps in logging, metrics, tracing, and error reporting.

## What to scan for

### 1. Log level misuse
- **`logger.error` for expected conditions** — e.g., "user not found" on a lookup. Floods alert systems.
- **`logger.info` for noisy debug output** — inflates log volume and cost
- **`logger.debug` for actual errors** — hides real problems
- **`print()` in production code** — bypasses log routing, no level, no structure
- **No logger at all** — silent failures

**Detection**: grep for `print(`, `console.log(`, `logger.error(` in non-error paths.

### 2. Missing context in logs
Logs that say "error occurred" without saying *what* or *where*:

**Bad**:
```python
except Exception:
    logger.error("Failed")
```

**Good**:
```python
except Exception as e:
    logger.error(f"Failed to process trade {trade_id} for {ticker}: {e}", exc_info=True)
```

**Check for**:
- `exc_info=True` or equivalent stack trace on exception logs
- Correlation IDs / request IDs in request-scoped logs
- User/tenant IDs for multi-tenant systems
- Operation identifiers (trade_id, order_id, run_date)

### 3. Structured vs unstructured logs
- If the project uses a structured logger (JSON), check for `f"{}" "string formatting"` that bypasses the structure
- Mixed `logger.info("user=" + user_id)` and `logger.info("event", user_id=user_id)` inconsistency
- Sensitive data in logs (passwords, tokens, full PII)

### 4. Silent failures
- Empty `except:` blocks (see code-quality-checklist)
- `try:` blocks that only catch and `pass`
- Promises/futures without error handlers
- Background threads with no error reporting
- Fire-and-forget async calls without `.catch()`
- **Loops that `continue` without categorized skip logging** — see code-quality-checklist "Silent skips in loops". The summary log at the end of a loop must distinguish "processed N", "expected-pending N", and "input-missing N" so that a stalled pipeline is obvious from the log alone, not "0 evaluated, exit 0".

**Detection**: grep for `except.*:\s*pass`, `.catch(() => {})`, empty error handlers, and `continue$` without a preceding `logger` call.

### 5. Missing metrics at critical points
Key metrics to check are emitted:
- **Latency**: time from request to response for external calls
- **Error rate**: counted by endpoint/operation
- **Throughput**: requests per second
- **Business metrics**: orders placed, trades synced, predictions made
- **Resource metrics**: cache hit rate, queue depth, connection pool usage

If the project has metrics infrastructure (Prometheus, StatsD, CloudWatch), check that new endpoints/features emit relevant metrics.

### 6. No tracing on distributed / async paths
- Background jobs that fire off without a trace ID
- Request handlers that spawn threads/workers without propagating context
- Cross-service calls without trace propagation headers (`traceparent`, `b3`)

### 7. Error reporting gaps
- Errors logged but not sent to Sentry/Rollbar/etc when project has error tracking
- Errors caught at wrong layer (swallowed deep, never reach the reporting boundary)
- User-facing errors that don't correlate with backend logs (no request ID returned)

### 8. Debuggability of failures
Questions to ask for each new feature:
- "If this breaks in production at 3am, what do I need to debug it?"
- "Does the log tell me *which* user/trade/ticker caused the error?"
- "Can I correlate a user complaint to a log line?"
- "If this silently produces wrong output, would I ever notice?"

### 9. Alerting hygiene
- New critical paths without alert rules (if project has alerting config in repo)
- Alert thresholds hardcoded in code instead of config
- Alerts that fire on expected conditions (noise → ignored)

### 10. Health checks
- Service with no `/health` endpoint
- Health check that always returns 200 without checking dependencies
- Health check that does expensive work on every call

## Detection strategies

1. **grep all exception handlers** → verify each logs with context
2. **grep `print(` and `console.log(`** in non-test, non-CLI code → should be logger
3. **grep `logger.error(`** → verify each is a genuine error, not an expected condition
4. **Check new endpoints/handlers** → do they emit the same metrics as existing ones?
5. **Read the startup / shutdown code** → are lifecycle events logged?

## Questions to ask

- "If this fails at 3am, what signal tells me?"
- "Would this log line let me find the affected user?"
- "Is there a metric that would page someone if this stopped working?"
- "Could an attacker hide an attack inside the normal log noise?"
- "Are secrets ever written to logs?"

## Output format

```markdown
## Observability findings

### P1 - Silent failures
- `engine/sbi_sync.py:87` — `except: pass` swallows all errors, no log
- `routers/trades.py:102` — async task spawned without error handler

### P2 - Missing context
- `routers/predict.py:45` — logs "prediction failed" without ticker or error detail
- `ml/train_lgbm.py:312` — exception caught, only type logged, no traceback

### P2 - Log level misuse
- `routers/notes.py:34` — `logger.error` for "note not found" (expected case, should be info or warn)

### P3 - Missing metrics
- New endpoint `/api/intraday/backtest` has no latency metric, unlike peers
```
