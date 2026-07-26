# Cleanup & Dead Code Checklist

Most linters detect unused variables within a single file. They do NOT detect unused files, orphaned modules, legacy directories, or unused dependencies. Scan for these explicitly.

## Categories to scan

### 1. Orphaned files (never imported)
Python and JS files that exist on disk but are imported from nowhere.

**Detection**:
```bash
# For each Python file in src/, check if its module name appears in any import
for f in $(find backend -name "*.py"); do
  module=$(basename "$f" .py)
  count=$(grep -r "import $module\|from .*$module" --include="*.py" backend/ | wc -l)
  if [ "$count" -le 1 ]; then echo "ORPHAN: $f"; fi
done
```

For JS/TS:
```bash
# Grep for filename (without extension) across all source
grep -rn "from.*filename" frontend/src/ | ...
```

### 2. Legacy code marked in docs
Project docs (`CLAUDE.md`, `README.md`, comments) often mark code as `(legacy)` or `(deprecated)`. Grep for these markers:
```bash
grep -rn "legacy\|deprecated\|TODO.*remove\|FIXME.*remove" --include="*.py" --include="*.md" .
```

Anything marked legacy that's not actively used in production paths (e.g., daily pipeline, API routes) is a removal candidate.

### 3. Unused dependencies
Compare `pyproject.toml` / `package.json` against actual imports:

**Python**:
```bash
# Extract declared deps
grep '^\s*"' pyproject.toml | sed 's/.*"\([^"=>]*\).*/\1/'
# For each dep, check if it's imported
for dep in torch numpy ...; do
  if ! grep -rq "import $dep\|from $dep" backend/; then
    echo "UNUSED: $dep"
  fi
done
```

**JS**:
```bash
# Compare dependencies in package.json with actual imports
```

Large unused deps matter most (`torch` = ~2GB).

### 4. Empty / stub files
Files with < 10 lines that contain only imports or a single pass. Often leftover from refactors.

### 5. Generated / build artifacts committed to git
- `dist/`, `build/`, `.next/`, `out/`
- `*.pyc`, `__pycache__/`
- Coverage reports, test artifacts
- IDE files (`.vscode/`, `.idea/`) — usually fine in .gitignore

Check these aren't tracked:
```bash
git ls-files | grep -E "^(dist|build|__pycache__|\.next)/"
```

### 6. Large binary files in git
Model weights, datasets, images that should be in Git LFS or external storage:
```bash
git ls-files | xargs -I {} du -b {} 2>/dev/null | sort -rn | head -20
```

Flag anything > 5 MB that isn't clearly source code.

### 7. Duplicate / near-duplicate files
Two files that do the same thing, typically from a failed refactor or a legacy/v2 split:
- `predict_universal.py` vs `predict_lgbm.py` (when one is legacy)
- `old_foo.py` vs `foo.py`
- Similar file sizes, similar names, overlapping function names

### 8. Orphaned test files
Tests importing deleted modules — will fail at collection time:
```bash
grep -rn "from .* import" tests/ | while read line; do
  # Verify the imported module exists
done
```

### 9. Dead config / environment
- `.env.example` entries not used anywhere
- CI workflow steps running against deleted files
- Dockerfile COPY steps for removed directories

### 10. Unreferenced scripts
Scripts in `scripts/`, `bin/`, `tools/` directories that are never called by:
- CI/CD
- Main entry points
- Documentation
- Other scripts

## Safe deletion protocol

For each candidate, verify BEFORE deleting:

1. **Grep for all references** — filename, module name, class names, function names
2. **Check dynamic references** — `importlib`, `__import__`, reflection, string-based paths
3. **Check CI/CD config** — is it run by GitHub Actions? Cron? Docker?
4. **Check docs** — is it documented as part of the workflow?
5. **Check git history (30 days)** — recent modifications suggest it's live

If all clear → **Safe to delete**.
If any doubt → **Defer with plan** (see `removal-plan.md`).

## Output format

Group findings into tiers:

```markdown
### Tier 1: Safe to delete immediately
- [file] — reason, size
- ...

### Tier 2: Requires code changes first
- [file] — blockers (e.g., still imported by X), migration plan

### Tier 3: Investigate further
- [file] — uncertainty, what to check
```

Report total bytes/lines that would be reclaimed.
