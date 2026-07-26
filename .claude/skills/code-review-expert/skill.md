---
name: code-review-expert
description: "Expert code review with a senior engineer lens. Detects security, SOLID, quality, testing, observability, API contract, DB/migration, hardcoding, dead code, structure, dependency, documentation, and runtime health issues (data drift, helper saturation, sibling function inconsistency). Supports diff-only (quick) and project-wide (full) modes."
---
# Code Review Expert

## Overview

Perform a structured review of the codebase. **Default to review-only output** unless the user asks to implement changes.

## Review modes

Before starting, decide the scope:

| Mode | When to use | What's covered |
|------|-------------|----------------|
| **quick** | User asks to review a PR, commit, or "my changes". Working tree has unstaged changes. | Only the git diff + files it touches |
| **full** | User asks for "full review", "project review", "全体レビュー", or mode is not clear and the project is small enough (< 200 files). | Entire project: diff + hardcoding scan + cleanup scan + cross-file consistency |

**If the user's intent is unclear, ASK which mode they want before starting.** Do not silently default to quick — many issues live outside the diff.

After completing a quick review, **always offer a full review as a follow-up**: "This was a diff-only review. Want me to also scan the full project for hardcoded values, dead code, and duplicates? (y/n)"

## Severity levels

| Level  | Name     | Description                                                      | Action                             |
| ------ | -------- | ---------------------------------------------------------------- | ---------------------------------- |
| **P0** | Critical | Security vulnerability, data loss risk, correctness bug          | Must block merge                   |
| **P1** | High     | Logic error, significant SOLID violation, performance regression | Should fix before merge            |
| **P2** | Medium   | Code smell, maintainability concern, minor SOLID violation       | Fix in this PR or create follow-up |
| **P3** | Low      | Style, naming, minor suggestion, hard coding                     | Optional improvement               |

## Workflow

### Phase 1 — Preflight context (always)

- Run `git status -sb`, `git diff --stat`, `git diff` to scope changes.
- Read `CLAUDE.md` or equivalent project docs to understand architecture, conventions, and anything marked `(legacy)` / `(deprecated)`.
- **Enumerate ALL documentation files** with `find . -name "*.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.venv/*"`. Do NOT assume docs live only in `README.md` and `CLAUDE.md` — projects often have `dev-docs/`, `docs/`, `wiki/`, `backend/ml/README.md`, etc. Missing this step is a known cause of doc drift slipping past review.
- Identify entry points, ownership boundaries, and critical paths (auth, payments, data writes, network).

**Edge cases:**
- **No changes** AND mode is quick: ask the user if they want to review staged changes, a commit range, or switch to full mode.
- **Large diff (>500 lines)**: review in batches by module/feature area.
- **Mixed concerns**: group findings by logical feature, not file order.

### Phase 2 — Diff review (quick + full)

**2a) SOLID + architecture smells** — load `references/solid-checklist.md`

**2b) Security and reliability** — load `references/security-checklist.md`
- Authentication/authorization gaps
- Injection, XSS, SSRF, path traversal
- Secret leakage
- Race conditions, TOCTOU

**2c) Code quality** — load `references/code-quality-checklist.md`
- Error handling (swallowed exceptions, broad catches)
- Performance (N+1 queries, missing memoization, sync I/O in async)
- Boundary conditions (null, empty, division by zero)
- Duplication & dead code
- Cross-file consistency

**2d) Testing quality** — load `references/testing-quality-checklist.md`
- Critical paths untested (money, auth, migrations)
- Mock overuse / weak assertions
- Flaky patterns (sleep, datetime.now, shared state)
- Missing error-path / edge-case coverage

**2e) Observability** — load `references/observability-checklist.md`
- Silent failures, empty except, log level misuse
- Missing context in logs (no request ID, no operation ID)
- Missing metrics at critical points
- Secrets leaked in logs

**2f) API contract (if diff touches routers/handlers/schemas)** — load `references/api-contract-checklist.md`
- Breaking changes (removed/renamed fields, type changes)
- Silent behavior changes (defaults, sort order)
- Auth/validation consistency with peer endpoints
- OpenAPI / frontend type drift

**2g) Database & migrations (if diff touches SQL, migrations, or DB queries)** — load `references/db-migration-checklist.md`
- Destructive operations without plan
- Missing indexes on new query paths
- Transaction boundaries, concurrency controls
- Long-running migrations against live DB

**2h) Removal candidates (diff scope)** — load `references/removal-plan.md`
- Anything removed/added that hints at broader cleanup opportunities

### Phase 3 — Project-wide scans (full mode only)

**This phase catches what Phase 2 misses.** Linters and diff-based reviews consistently miss these categories — scan the whole project explicitly.

#### Agent budget rule (CRITICAL)

Phase 3 must stay within **10 agents total** across all sub-phases. Sub-agents must NEVER spawn their own sub-agents — one level of delegation only.

**How to stay within budget:**
- **Orphan file checks**: use a single `grep -rL "import MODULE\|from MODULE" backend/` command per candidate, NOT one agent per file. Batch candidates into a single agent that runs grep commands sequentially.
- **`scripts/bt_*` and other research/backtest scripts**: skip individual verification entirely. These are CLI-ONLY one-off scripts by convention — flag the directory count in the report and move on.
- **Hardcoding / magic numbers**: one agent covers all of 3a (grep for literals, URLs, duplicates). Do NOT split into separate agents for numbers, strings, paths, etc.
- **Cross-file consistency (3c)**: one agent covers naming + error handling + color system. Grep-based, not file-by-file inspection.
- If a sub-phase can be done with 2-3 grep commands, run them directly instead of spawning an agent.

**3a) Hardcoding scan** — load `references/hardcoding-checklist.md`
- Grep for numeric literals, URLs, paths, magic strings across the codebase
- **Critically**: detect the same literal defined in multiple files (duplication signal)
- Report with file:line + duplication count + suggested shared location

**3b) Cleanup scan** — load `references/cleanup-checklist.md`
- Orphaned files (not imported from anywhere)
- Legacy/deprecated code marked in docs or comments
- Unused dependencies in `pyproject.toml` / `package.json`
- Large binaries in git (> 5 MB, non-source)
- Duplicate/near-duplicate files from old refactors
- Tests importing deleted modules

**3c) Cross-file consistency sweep**
- Naming conventions (snake_case vs camelCase for same concept)
- Error handling patterns (all routes log? all endpoints auth?)
- Input validation (validated at one layer but not another?)
- Design system usage (hex colors bypassing theme variables?)

**3d) File & directory structure scan** — load `references/structure-checklist.md`
- Convention violations vs stated rules in CLAUDE.md / README.md
- Misplaced files (business logic in routers, components in lib/, etc.)
- Cross-layer imports that violate architecture
- Inconsistent grouping across similar features
- Orphan/empty directories, generated files mixed with source

**3e) Dependency health** — load `references/dependencies-checklist.md`
- Declared but unused deps (size/security impact)
- Used but not declared (transitive dep gamble)
- CVEs via `pip-audit` / `npm audit` / equivalent
- Lockfile integrity, dev/prod split, license compatibility
- Overlapping deps (two HTTP clients, two date libs)

**3f) Documentation consistency** — load `references/documentation-checklist.md`
- Stale references to deleted files / functions / scripts
- Architecture drift (docs describe old structure)
- Outdated commands (PowerShell-only, deprecated entry points)
- Stale benchmarks and undated performance numbers
- Missing sections for newly-added features (compare git log to doc mod times)
- Broken cross-references and TOC anchors
- **Scan ALL .md files enumerated in Phase 1**, not just `README.md` and `CLAUDE.md`

**3g) Runtime health** — load `references/runtime-health-checklist.md`
- Production data freshness (`find -mtime` on data dirs)
- Production data shape (sample 1-2 files per data dir for schema drift)
- Writer/reader pair audit (sibling functions producing different schemas AND inconsistent staleness handling)
- Helper call-site completeness (helpers exist but only called in 1 of N places)
- Critical path smoke test (each major user-facing flow returns non-empty)
- External integration drift (when was each third-party touchpoint last verified?)
- Recent log inspection (silent failures, "0 items processed" patterns)
- Module-level dict caches without TTL (the "load once, serve forever" bug)
- Scheduled task `Last Run` verification (registration ≠ execution)
- **This phase catches what static review CANNOT see**: data drift, pipeline silently stopped, external service changes, helper-not-called-in-loop bugs.
- Each check should be < 2 minutes. If a check would take longer, ask the user before running.

**3i) Project-specific patterns** — load `references/project-specific-checklist.md`
- This file captures anti-patterns learned the hard way *in this codebase*. It complements the generic checklists with rules tied to specific past incidents.
- Apply each rule (A1–A7) and runtime check (R1–R7) explicitly.
- Cross-reference the "Files that need extra attention" table — if the diff touches one of those files, every linked rule must be considered.
- **Skip this file when reviewing a different project.** Either remove this bullet or copy `references/project-specific-checklist.md` and rewrite it against the new project's history.

### Phase 4 — Report

Output format:

```markdown
## Code Review Summary

**Mode**: quick | full
**Files reviewed**: X files, Y lines changed (quick) or X files scanned (full)
**Overall assessment**: APPROVE / REQUEST_CHANGES / COMMENT

## Coverage declaration
- ✅ Scanned: security, SOLID, code quality, testing quality, observability
- ✅ Scanned (if applicable to diff): API contract, database & migrations
- ✅ Scanned (full mode only): hardcoding, dead code, cross-file consistency, file/directory structure, dependency health, documentation consistency, runtime health, project-specific anti-patterns (A1–A7) and runtime checks (R1–R7)
- ⚠️ Sampled but not exhaustive: runtime health checks sample data files and skim recent logs — rare-shape outliers and intermittent failures may slip through
- ⚠️ NOT scanned (require dedicated tooling): <list explicitly — e.g. "frontend accessibility", "i18n", "ML model correctness", "business logic correctness", "load/stress testing", "production monitoring drift", "long-running pipeline integration tests">
- ⚠️ Cannot detect by review alone (need real test suite + monitoring):
  - Race conditions only manifest under load
  - External services drifting in the future (e.g., third-party UI changes next month)
  - Bugs that need a specific user action sequence
  - Silent data corruption between scheduled runs
- Residual risks: <things that would need human judgment or domain expertise>

---

## Findings

### P0 — Critical
- **[file:line]** Title
  - What's wrong
  - Why it matters
  - Suggested fix

### P1 — High
...

### P2 — Medium
...

### P3 — Low
...

---

## Hardcoding findings (full mode)
| File:Line | Value | Duplicates | Should live in |
|-----------|-------|------------|----------------|
| ... | ... | ... | ... |

## Cleanup candidates (full mode)
### Tier 1: Safe to delete
- [file] — reason, size reclaimed
### Tier 2: Needs code changes first
- [file] — blockers, migration plan
### Tier 3: Investigate further
- [file] — uncertainty

---

## Next steps

I found X issues (P0: _, P1: _, P2: _, P3: _).

**How would you like to proceed?**
1. Fix all
2. Fix P0/P1 only
3. Fix specific items (specify)
4. No changes — review complete

[If quick mode was used:]
5. Also run a full project scan (hardcoding + cleanup + consistency)
```

## Important rules

1. **Coverage declaration is MANDATORY.** Always state what you scanned AND what you didn't. This prevents the user from thinking you checked something you didn't.

2. **Never claim "no issues" silently.** If a category is clean, say so explicitly: "Scanned for race conditions — none found."

3. **Quick mode must offer a full scan as a next step.** The user should always know that a diff-only review has blind spots.

4. **Do NOT implement changes until the user explicitly chooses an option.** This is a review-first workflow.

5. **Verify before recommending deletion.** For any file/dep flagged for removal, grep the entire codebase (including dynamic imports, CI configs, and docs) to confirm it's truly unused. Report verification steps taken.

6. **Don't trust linters alone for:**
   - Duplicate literals across files (linters are single-file)
   - Orphaned files (linters see "valid code", not "never imported")
   - Unused dependencies (package managers report declared, not used)
   - Cross-file inconsistencies (naming, error handling, auth)
   These require explicit grep-based scanning.

## Resources

### references/

| File                        | Purpose                                             |
| --------------------------- | --------------------------------------------------- |
| `solid-checklist.md`          | SOLID smell prompts and refactor heuristics         |
| `security-checklist.md`       | Web/app security and runtime risk checklist         |
| `code-quality-checklist.md`   | Errors, performance, boundaries, duplication, consistency |
| `testing-quality-checklist.md`| Test coverage gaps, mock overuse, flaky patterns, weak assertions |
| `observability-checklist.md`  | Log quality, silent failures, metrics, tracing, debuggability |
| `api-contract-checklist.md`   | Breaking changes, schema drift, auth/pagination consistency |
| `db-migration-checklist.md`   | Destructive ops, indexes, transactions, migration reversibility |
| `hardcoding-checklist.md`     | Magic numbers/strings, duplicated constants, cross-file scanning strategy |
| `cleanup-checklist.md`        | Orphaned files, legacy code, unused deps, safe deletion protocol |
| `structure-checklist.md`      | File/directory layout, convention violations, cross-layer imports, misplaced files |
| `dependencies-checklist.md`   | Unused/missing deps, CVEs, lockfile integrity, license/health |
| `documentation-checklist.md`  | Stale doc references, architecture drift, missing sections, terminology consistency |
| `runtime-health-checklist.md` | Data freshness, schema drift, writer/reader pairs (incl. staleness), helper saturation, smoke tests, log inspection, cache TTL bugs, scheduled-task LastRun |
| `project-specific-checklist.md` | **Stock Trade Logger only** — anti-patterns from past incidents (raw parquet direct reads, module-cache TTL bugs, top-100 problem, parallel Supabase, silent skips), runtime checks (R1–R7), and a "files needing extra attention" table |
| `removal-plan.md`             | Template for deletion candidates and follow-up plan |
