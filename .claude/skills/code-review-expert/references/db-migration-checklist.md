# Database & Migration Checklist

Database changes affect production data — bugs here are hard or impossible to reverse. Apply extra scrutiny.

## What to scan for

### 1. Destructive operations
- `DROP TABLE`, `DROP COLUMN` without backup
- `DELETE` without `WHERE` (or with `WHERE 1=1`)
- `TRUNCATE` in migration code
- `ALTER TABLE ... DROP CONSTRAINT` that removes invariants
- Data-loss operations run before a verification step

**Rule**: Any destructive migration should have a "dry run" or "verify" phase first.

### 2. Non-reversible migrations
- Migrations without a `down` / rollback step
- Migrations that transform data in-place without keeping the original
- Schema changes mixed with data changes in one migration (hard to rollback one without the other)

### 3. Long-running migrations against live DB
- `ALTER TABLE` on a large table without `CONCURRENTLY` / online-migration strategy
- Adding an index on a hot table without `CONCURRENTLY`
- Backfill migrations that lock the table
- Missing batching for large updates (`UPDATE ... WHERE id BETWEEN ...`)

**Rule of thumb**: If it touches > 10k rows, it needs batching + a plan.

### 4. Breaking schema changes without a multi-step plan
Breaking changes to a running service need a multi-deploy choreography:

1. **Deploy 1**: Add new column/table (nullable / backward compatible)
2. **Backfill**: Populate new column
3. **Deploy 2**: Application writes to both old and new
4. **Deploy 3**: Application reads from new only
5. **Deploy 4**: Drop old column

Single-step destructive migrations = outage risk. Scan for multi-deploy sequences when breaking changes appear.

### 5. Missing indexes
- New query on a column with no index → table scan at scale
- Foreign key without index → slow joins + lock escalation
- Sort/filter columns in critical queries without covering index
- Unique constraint implied but not enforced at DB level

**Detection**: For each new `WHERE`, `JOIN`, `ORDER BY` clause → check if the columns are indexed.

### 6. N+1 and over-fetching (app-level)
Already covered in `code-quality-checklist.md`, but DB-specific smells:
- ORM relationships loaded lazily in loops (`for x in xs: x.related`)
- `SELECT *` when only a few columns needed
- Fetching parent + children separately when a JOIN would work
- Pagination that loads the full dataset into memory before slicing

### 7. Transaction boundaries
- Multiple related writes without a transaction → partial failure leaves inconsistent state
- Long transactions holding locks → contention
- Transactions that call external services (HTTP, queue) → deadlock risk if the external call hangs
- Autocommit behavior assumed but not guaranteed
- Missing isolation level for read-modify-write patterns

### 8. Concurrency controls
- Read-modify-write without optimistic locking (`updated_at` / `version` column check)
- Missing `SELECT FOR UPDATE` where needed
- Unique constraint violations handled poorly (crash instead of graceful duplicate detection)
- Race conditions in "check then insert" patterns

### 9. Connection pool health
- Operations that hold a connection for a long time (file upload, external HTTP)
- Connection leaks (not returned to pool on error)
- Pool size not sized for expected concurrency
- Long-running migrations competing with app traffic for connections

### 10. Data validation at DB vs app layer
- App enforces format (e.g., email regex) but DB has no constraint → bad data can leak in via direct DB writes
- DB has constraint but app error messages don't explain it → bad UX on violation
- Constraints defined in one but not the other → inconsistent enforcement

### 11. Sensitive data handling
- PII stored in plain text where encryption is expected
- Passwords not hashed (or weak hash)
- Soft delete vs hard delete policy not followed consistently
- Audit log missing for sensitive operations
- Backup/export includes data that should be masked

### 12. Migration file hygiene
- Migrations edited after being applied to production (breaks reproducibility)
- Migration numbering conflicts (two developers, same number)
- Empty migrations committed by mistake
- Migrations that depend on application code that may change

## Detection strategies

1. **List migration files** changed in the diff
2. **grep for dangerous SQL**: `DROP`, `DELETE FROM.*WHERE 1`, `TRUNCATE`, `ALTER.*DROP`
3. **For each new query**: check columns used in `WHERE`/`JOIN`/`ORDER BY` against the schema's indexes
4. **For each new write path**: verify it's inside a transaction and handles errors
5. **Check for `SELECT *`** in production code
6. **Check migration reversibility**: does each have a down step?

## Questions to ask

- "If this migration ran against 10M rows, what happens?"
- "Can this migration be rolled back safely?"
- "Is there a multi-step deploy plan for this schema change?"
- "Is this column indexed for the way we query it?"
- "What happens if two requests hit this write path simultaneously?"
- "Would a partial failure leave the data in a consistent state?"

## Output format

```markdown
## Database findings

### P0 - Destructive without plan
- `migrations/20260401_drop_old_cols.sql` — drops columns still read by frontend
- `scripts/cleanup.py:45` — `DELETE FROM trades` with no WHERE

### P1 - Missing indexes
- `routers/trades.py:44` — new query on `trades.ticker`, not indexed for this access pattern
- New join path in `portfolio.py:78` — FK missing index on child side

### P1 - Transaction gaps
- `routers/sync.py:30` — writes trades + updates cache in separate statements, no transaction

### P2 - Long-running migration
- `migrations/backfill_predictions.py` — updates all rows at once, no batching

### P3 - Soft delete inconsistency
- Some endpoints honor `deleted_at`, others don't
```
