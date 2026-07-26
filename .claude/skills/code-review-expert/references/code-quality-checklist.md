# Code Quality Checklist

## Error Handling

### Anti-patterns to Flag

- **Swallowed exceptions**: Empty catch blocks or catch with only logging
  ```javascript
  try { ... } catch (e) { }  // Silent failure
  try { ... } catch (e) { console.log(e) }  // Log and forget
  ```
- **Overly broad catch**: Catching `Exception`/`Error` base class instead of specific types
- **Error information leakage**: Stack traces or internal details exposed to users
- **Missing error handling**: No try-catch around fallible operations (I/O, network, parsing)
- **Async error handling**: Unhandled promise rejections, missing `.catch()`, no error boundary

### Best Practices to Check

- [ ] Errors are caught at appropriate boundaries
- [ ] Error messages are user-friendly (no internal details exposed)
- [ ] Errors are logged with sufficient context for debugging
- [ ] Async errors are properly propagated or handled
- [ ] Fallback behavior is defined for recoverable errors
- [ ] Critical errors trigger alerts/monitoring

### Questions to Ask
- "What happens when this operation fails?"
- "Will the caller know something went wrong?"
- "Is there enough context to debug this error?"

---

## Performance & Caching

### CPU-Intensive Operations

- **Expensive operations in hot paths**: Regex compilation, JSON parsing, crypto in loops
- **Blocking main thread**: Sync I/O, heavy computation without worker/async
- **Unnecessary recomputation**: Same calculation done multiple times
- **Missing memoization**: Pure functions called repeatedly with same inputs

### Database & I/O

- **N+1 queries**: Loop that makes a query per item instead of batch
  ```javascript
  // Bad: N+1
  for (const id of ids) {
    const user = await db.query(`SELECT * FROM users WHERE id = ?`, id)
  }
  // Good: Batch
  const users = await db.query(`SELECT * FROM users WHERE id IN (?)`, ids)
  ```
- **Missing indexes**: Queries on unindexed columns
- **Over-fetching**: SELECT * when only few columns needed
- **No pagination**: Loading entire dataset into memory

### Caching Issues

- **Missing cache for expensive operations**: Repeated API calls, DB queries, computations
- **Cache without TTL**: Stale data served indefinitely
- **Cache without invalidation strategy**: Data updated but cache not cleared
- **Cache key collisions**: Insufficient key uniqueness
- **Caching user-specific data globally**: Security/privacy issue

### Memory

- **Unbounded collections**: Arrays/maps that grow without limit
- **Large object retention**: Holding references preventing GC
- **String concatenation in loops**: Use StringBuilder/join instead
- **Loading large files entirely**: Use streaming instead

### Questions to Ask
- "What's the time complexity of this operation?"
- "How does this behave with 10x/100x data?"
- "Is this result cacheable? Should it be?"
- "Can this be batched instead of one-by-one?"

---

## Boundary Conditions

### Null/Undefined Handling

- **Missing null checks**: Accessing properties on potentially null objects
- **Truthy/falsy confusion**: `if (value)` when `0` or `""` are valid
- **Optional chaining overuse**: `a?.b?.c?.d` hiding structural issues
- **Null vs undefined inconsistency**: Mixed usage without clear convention

### Empty Collections

- **Empty array not handled**: Code assumes array has items
- **Empty object edge case**: `for...in` or `Object.keys` on empty object
- **First/last element access**: `arr[0]` or `arr[arr.length-1]` without length check

### Numeric Boundaries

- **Division by zero**: Missing check before division
- **Integer overflow**: Large numbers exceeding safe integer range
- **Floating point comparison**: Using `===` instead of epsilon comparison
- **Negative values**: Index or count that shouldn't be negative
- **Off-by-one errors**: Loop bounds, array slicing, pagination

### String Boundaries

- **Empty string**: Not handled as edge case
- **Whitespace-only string**: Passes truthy check but is effectively empty
- **Very long strings**: No length limits causing memory/display issues
- **Unicode edge cases**: Emoji, RTL text, combining characters

### Common Patterns to Flag

```javascript
// Dangerous: no null check
const name = user.profile.name

// Dangerous: array access without check
const first = items[0]

// Dangerous: division without check
const avg = total / count

// Dangerous: truthy check excludes valid values
if (value) { ... }  // fails for 0, "", false
```

### Questions to Ask
- "What if this is null/undefined?"
- "What if this collection is empty?"
- "What's the valid range for this number?"
- "What happens at the boundaries (0, -1, MAX_INT)?"

---

## Duplication & Dead Code

### Duplicate logic across files
- Same constant defined in multiple modules (flag with `hardcoding-checklist.md`)
- Similar functions differing only by a small parameter — candidate for parameterization
- Copy-pasted error handling blocks that should be a decorator/utility
- Same API call wrapped in different helpers

**Detection**: For any non-trivial block of code (> 5 lines), grep for similar structure in other files.

### Sibling function inconsistency (the silent killer)

When two functions do the SAME job but one was updated and the other wasn't.

**Anti-pattern examples:**

1. **Two writers, one updated, one stale**
   ```python
   def update_single_ticker(ticker):           # used by daily_update --quick
       df = yf.download(ticker)
       df.to_parquet(path)                     # ← saves MultiIndex (stale)

   def run_collection(mode):                   # used by daily_update --weekly
       df = yf.download(ticker)
       if isinstance(df.columns, pd.MultiIndex):
           df.columns = df.columns.get_level_values(0)
       df.to_parquet(path)                     # ← saves flat (correct)
   ```
   The two writers save the SAME artifact in DIFFERENT formats. Readers that work with one fail on the other.

2. **Reader doesn't trust the writer**
   ```python
   # Writer (no schema guarantee)
   def save_features(df, path): df.to_parquet(path)

   # Reader (silently breaks if writer changes)
   df = pd.read_parquet(path, columns=['Close'])  # KeyError on MultiIndex
   ```

3. **Helper exists but is only called in one place**
   ```python
   def _dismiss_passkey(page): ...        # 80 lines of careful logic

   def login(page):
       fill_credentials()
       wait_for_dashboard()
       _dismiss_passkey(page)             # ← called here, after waiting

   def _wait_for_dashboard(page):
       for _ in range(60):
           if is_logged_in(page): return
           # ← _dismiss_passkey not called inside the loop!
           sleep(1)
   ```
   The helper is technically "used" but the place that actually NEEDS it doesn't call it.

**Detection strategy:**

1. **Pair audit**: For each `to_*` / `save_*` / `write_*` function, find ALL siblings doing the same thing. Diff them line-by-line.
2. **Reader-writer schema check**: For each `read_parquet(path, columns=[...])`, find the writer of that path and verify it produces flat columns.
3. **Helper saturation**: For each non-trivial helper function, grep all call sites. Ask: "Are there places that conceptually need this but don't call it?"
4. **Use the runtime-health-checklist**: writer/reader pair audit catches this in production data, not just code.

**Why this matters**: This pattern caused both the empty-screener bug (writer pair drift) and the SBI passkey bug (helper not called in polling loop) in past reviews. The static checklist alone missed both.

### Order-of-operation bugs in helpers

A helper function exists and is called, but the timing is wrong:

- Cleanup helper called in `try` instead of `finally` → leaks on error
- Validation called after persistence → invalid data already saved
- Dismiss/normalize helper called after the blocking operation → never reached
- Cache invalidation called before the write → next read returns stale data

**Question to ask for each helper call**: "If the next operation can fail or block, does this helper need to run BEFORE that operation, INSIDE its retry loop, or AFTER it?"

### Unused imports / variables
- Linters catch most, but they miss:
  - Imports that exist only for side effects (verify the side effect is intentional)
  - Variables assigned but only used in debug/log statements that are conditionally disabled
  - Type-only imports in languages without type-only import syntax

### Dead code paths
- `if False:` blocks, unreachable branches after `return`
- Legacy compatibility shims for removed dependencies
- Feature flag branches where the flag is permanently on/off

### Silent skips in loops (the invisible failure)

Loops that iterate over work items and silently skip the unhappy path are one of the most common ways pipelines die without anyone noticing — the script exits 0, the count printed at the end is "0 evaluated", and nobody investigates because there was no error.

**Anti-patterns to flag:**
```python
for item in items:
    if not _can_process(item):
        continue                # SILENT — no log, no count, no reason
    if not os.path.exists(path):
        continue                # SILENT
    if len(history) < HORIZON:
        continue                # SILENT
    process(item)
```

The bug is not the `continue` itself — it's that the reviewer (and the person reading logs months later) has **no way to tell whether the loop processed everything, processed nothing, or processed a partial set with silently-dropped items**.

**Required fix pattern:**
```python
skip_reasons: dict[str, int] = defaultdict(int)
processed = 0

for item in items:
    if not _can_process(item):
        skip_reasons["not_eligible"] += 1
        continue
    if not os.path.exists(path):
        skip_reasons["missing_input"] += 1
        continue
    if len(history) < HORIZON:
        skip_reasons["insufficient_history"] += 1
        continue
    process(item)
    processed += 1

logger.info(f"Processed {processed}/{len(items)} items")
for reason, count in skip_reasons.items():
    level = logger.warning if reason in {"missing_input"} else logger.info
    level(f"  Skipped {count}: {reason}")
```

The categories carry meaning:
- **info**: expected pending state ("not enough trading days have elapsed yet")
- **warning**: pipeline degradation ("input file missing — collector may be broken")
- **error**: data corruption ("schema mismatch")

**Detection:**
```bash
# Find continue statements without a preceding logger call
grep -B 2 -rn "continue$" backend/ | grep -v "logger\|log\."
```
Then manually check whether each `continue` is silent or logged.

**Why it matters in this kind of project**: pipelines that compute derived data (paper trading evaluations, training sets, daily rankings) often filter out items that aren't ready yet. Without categorized skip logging, "0 evaluated" looks identical to "everything is fine, just not enough time has passed" and "the entire pipeline is broken".

### Commented-out code
- Large blocks of commented code = should be deleted (git history preserves it)
- Single-line commented code = usually a TODO or debugging artifact

### Questions to Ask
- "Is this code reachable in production?"
- "When was the last time this branch was taken?"
- "Could git blame tell me when this became dead?"

---

## Cross-file Consistency

These issues require scanning multiple files simultaneously — a single-file review will miss them:

- **Inconsistent naming**: `user_id` in one file, `userId` in another for the same value
- **Inconsistent error handling**: some routes log errors, others swallow them silently
- **Inconsistent auth**: some endpoints check auth, others don't (see security checklist)
- **Inconsistent caching**: cache invalidation in one path but not the other
- **Inconsistent validation**: input validated in one layer but not another

**Detection strategy**: When reviewing a change to file A, grep for related files B, C that handle the same concept. Check if the change is consistent with them.
