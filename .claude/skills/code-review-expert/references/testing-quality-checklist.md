# Testing Quality Checklist

Tests that pass are not the same as tests that catch bugs. Scan for the quality of the test suite, not just its existence.

## What to scan for

### 1. Untested critical paths
For any change touching:
- **Money / PnL calculations**
- **Authentication / authorization**
- **Data migrations or destructive operations**
- **External API integrations**
- **Concurrency-sensitive code (locks, caches, queues)**

→ Verify a test exists. If the change modifies `engine/pnl.py` but no PnL test changed, that's a finding.

**Detection**: For each changed non-test file, check if a corresponding test file was also modified in the diff.

### 2. Mock overuse
Tests that mock so much they test nothing real:

- **Mocking the code under test** (mocking the function you're testing)
- **Mocking every dependency** including pure functions and simple data classes
- **Database mocks where an in-memory DB (SQLite, testcontainers) would be trivial** — mocks hide SQL errors and migration issues
- **HTTP mocks that never fail** — tests only verify the happy path

**Smell**: A test file with 10 `patch()` calls and 3 lines of assertions is almost certainly testing the mocks, not the code.

### 3. Missing or weak assertions
- Tests that run code but assert only `result is not None` or `not None` → tests existence, not correctness
- Tests without any `assert` at the end (just checks it doesn't raise)
- Snapshot tests without human-reviewed snapshots
- Assertions on implementation details (e.g., "was method X called?") instead of observable behavior

### 4. Flaky / time-dependent tests
- `time.sleep()` in tests → timing-dependent flake
- `datetime.now()` without freezing → tests pass today, fail tomorrow
- Tests that depend on test execution order
- Tests that share mutable state (class-level fixtures, globals)
- Random seeds not pinned

**Detection**: grep for `sleep`, `datetime.now`, `Date.now`, `random.` in test files.

### 5. Test isolation violations
- Tests that leak state into each other (files not cleaned up, DB rows not rolled back)
- Tests that require network access (should be mocked or skipped with marker)
- Tests that write to the real filesystem outside `tmp_path` / test fixtures
- Tests that require specific env vars without documenting it

### 6. Coverage blind spots
Areas typically missed even at high line-coverage %:
- **Error paths**: the `except` branches
- **Edge cases**: empty lists, zero values, negative numbers, very large inputs
- **Concurrent scenarios**: two requests racing
- **Malformed input**: what the frontend/API never sends but an attacker might
- **Timezone edge cases**: DST transitions, leap seconds, epoch boundaries
- **Numeric precision**: floating point drift, decimal rounding

**Questions to ask**: "Is there a test for what happens when this fails?" "Is there a test for the empty / zero / negative case?"

### 7. Test data quality
- Hardcoded dates that will become stale (`"2024-01-01"` in tests → may affect seasonal logic)
- Magic values that don't explain why they were chosen
- Test fixtures that drift from production data shape
- Fixtures shared across tests that create implicit coupling

### 8. Slow / expensive tests in the inner loop
- Unit tests that hit the real database or network → belong in integration suite
- Tests that rebuild heavy objects in every case → could use session-scoped fixtures
- Large data files loaded on every test

### 9. Tests asserting the wrong thing
- **Testing the mock**: `assert mock.call_count == 1` when you should assert the returned value
- **Testing logs instead of behavior**: `assert "error" in caplog.text`
- **Over-specified assertions**: asserting exact dict equality when only one field matters
- **Brittle UI snapshots**: snapshotting entire DOM trees that change with any styling tweak

### 10. Orphaned or broken tests
- Tests importing deleted modules (will fail at collection)
- Tests skipped with `@skip` indefinitely without a tracking issue
- Commented-out tests
- Tests with `xfail` or `expected failure` that have been passing for months

## Detection strategies

1. **For each non-test file changed in the diff**, grep for its test counterpart. Missing → finding.
2. **grep test files for anti-patterns**: `time.sleep`, `datetime.now()`, excessive `patch()`, `assert.*is not None` as the only assertion
3. **grep for `skip`, `xfail`, `TODO: fix test`** — track stale skips
4. **Read 2-3 representative test files** and ask: "Do these tests give me confidence the code works, or do they just test the mocks?"
5. **Check test:code ratio** — if src/ has 5000 lines and tests/ has 200 lines, that's a finding

## Questions to ask

- "If this business rule were broken, would a test catch it?"
- "Is this test verifying behavior users care about, or implementation details?"
- "What would I have to break to make this test fail?"
- "Can I delete this test and lose nothing?"
- "Is this test coupled to the code, or to the requirements?"

## Output format

```markdown
## Testing findings

### P1 - Critical paths untested
- `engine/pnl.py` — modified in diff, no corresponding test change
- `routers/auth.py:45` — new endpoint added, no auth test

### P2 - Weak tests
- `tests/test_portfolio.py:23` — mocks the calculate_portfolio function it's testing
- `tests/test_ml.py:87` — only assertion is `assert result is not None`

### P2 - Flaky patterns
- `tests/test_sync.py:12` — uses `time.sleep(5)`, should use explicit wait

### P3 - Stale test infra
- `tests/test_legacy.py` — all tests @skip for 6 months, remove or fix
```
