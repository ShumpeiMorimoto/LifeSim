# Dependencies Checklist

Dependencies are a silent attack surface and a source of invisible bloat. Scan the declared manifest against reality.

## What to scan for

### 1. Declared but unused
Packages in `pyproject.toml` / `package.json` / `go.mod` / etc. that no source file imports.

**Detection**:
```bash
# Python
for dep in $(extract deps from pyproject.toml); do
  grep -rq "import $dep\|from $dep" backend/ || echo "UNUSED: $dep"
done
```

Large unused deps matter most:
- `torch` (~2GB) in a project no longer doing deep learning
- `playwright` / `puppeteer` in a project that removed browser automation
- `selenium` replaced by another tool but not removed
- Heavy data libs (`pandas`, `numpy`) if only used in removed scripts

### 2. Used but not declared
Reverse check — imports that don't map to any declared dependency. These work by accident via transitive deps and break when the transitive dep is updated.

**Detection**: grep imports, compare against manifest.

### 3. Outdated with known CVEs
If the project ecosystem has a vuln scanner:
- Python: `pip-audit`, `safety`
- JS: `npm audit`, `yarn audit`, `pnpm audit`
- Go: `govulncheck`
- Rust: `cargo audit`

Flag **critical / high** CVEs as P0/P1. Note **medium / low** for follow-up.

### 4. Lockfile integrity
- `requirements.txt` without a lock → not reproducible
- `package.json` without `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml`
- Lockfile not committed to git
- Lockfile out of sync with manifest (manifest says `^1.0`, lock has `0.5`)
- Multiple lockfiles (npm + yarn) → ambiguous install

### 5. Version pinning strategy
- **Libraries**: should pin to compatible range (`^1.2.0` / `~=1.2`)
- **Applications**: should pin exactly or use lockfile
- Mixing `latest`, `*`, and specific versions → fragile
- No pin at all → works today, broken tomorrow

### 6. Dev vs production deps
- Dev-only tools in production deps (test runners, linters, type checkers bundled into runtime)
- Production deps in dev section → breaks deploy
- `devDependencies` used in production code paths

### 7. Duplicate / overlapping deps
Multiple libraries doing the same thing:
- `axios` + `fetch` + `got` → pick one
- `moment` + `dayjs` + `date-fns` → pick one
- `lodash` + native methods doing the same thing
- Multiple HTTP clients, multiple ORMs, multiple test frameworks

### 8. License compatibility
- GPL dep in a proprietary product (contamination)
- Commercial-license dep without a license key in the manifest
- License changes between versions (some libraries went source-available)

Check `LICENSE` files of major deps if legal constraints apply.

### 9. Maintenance health
For critical deps:
- Last commit > 2 years ago → unmaintained risk
- Open CVE with no fix → security risk
- Single maintainer, no successor → bus factor
- Forks / successors exist → migration candidate

### 10. Install-time surprises
- Post-install scripts (`postinstall` in npm) → supply chain risk
- Native modules requiring compilation (`gcc`, `rustc`) → CI/deploy friction
- Download of binary blobs during install → not reproducible
- Deps that phone home

### 11. Bundle / image size impact
- Heavy deps in frontend without code splitting
- Large deps pulled into Docker image but only used in a subcommand
- Dev-only deps bloating production image

## Detection strategies

1. **Parse manifest** (`pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`)
2. **grep imports** across source — build a set of actually-used packages
3. **Set difference** — declared \ used = unused; used \ declared = missing
4. **Run audit tools** if available
5. **Check lockfile modification time** vs manifest — drift indicator
6. **Check dev/prod split** in the manifest structure

## Questions to ask

- "If I removed this dep, what would break?"
- "Is this dep doing something the standard library can do?"
- "When was this dep last updated? By whom?"
- "Are there known CVEs for this version?"
- "Do we have two deps doing the same thing?"
- "What's the transitive dep count? (each indirect dep is also a risk)"

## Output format

```markdown
## Dependency findings

### P0 - CVEs
- `package-x@1.2.3` — CVE-2024-XXXX (critical), upgrade to 1.2.5

### P1 - Unused deps (size impact)
- `torch` in pyproject.toml — no imports in source, ~2GB venv savings
- `playwright` — only used in deleted sbi_sync code

### P1 - Missing lockfile
- No `package-lock.json` committed

### P2 - Overlapping deps
- Project uses both `axios` and native `fetch` — pick one
- `moment` and `dayjs` both present

### P3 - Dev/prod split
- `pytest` listed under main deps instead of dev
```
