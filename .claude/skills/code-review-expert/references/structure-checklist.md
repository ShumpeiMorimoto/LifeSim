# File & Directory Structure Checklist

Structural issues compound over time and are invisible to linters. Scan for them in full mode.

## What to scan for

### 1. Convention violations vs project docs
Compare actual structure against stated conventions in `CLAUDE.md`, `README.md`, or `CONTRIBUTING.md`:

- **Directory naming**: Does `components/chart/` follow the stated lowercase rule? Are there stray PascalCase folders?
- **File naming**: Does the project say "camelCase for hooks" — any snake_case hooks leaking in?
- **Layer separation**: Does the project say "routers/ for API, engine/ for logic" — any business logic leaking into routers?

**Detection**: Read the conventions section of CLAUDE.md first, then grep for violations.

### 2. Misplaced files
Files that exist in the wrong layer/directory for what they do:

- A React component in `lib/` (should be in `components/`)
- Business logic in a router file (should be in `engine/` or `services/`)
- Test fixtures inside production code
- Config constants in feature modules (should be centralized)
- SQL in Python source instead of `sql/` directory
- Schema/migration files outside their designated directory

**Detection**: For each file, ask "does this name match what the file actually does?"

### 3. Inconsistent grouping
Related code scattered across the tree:

- Feature A has `featureA/` with component + hook + style, but Feature B's files are scattered across `components/`, `hooks/`, `styles/`
- One router file has its helper inline; a similar router imports from a shared file
- Some ML scripts are in `ml/scripts/`, others drift into `ml/` root

**Detection**: Pick 3 similar features and compare their file layouts side by side.

### 4. Deep nesting / shallow nesting mismatch
- Directories with > 4 levels of nesting when the project is small — over-organized
- Flat directories with > 30 files of mixed concerns — under-organized
- Single-file directories that add no grouping value

### 5. Circular or cross-layer imports
Architecture violations that compile but break layering:

- `engine/` importing from `routers/` (engine should not depend on transport layer)
- `lib/` importing from `components/` (utilities shouldn't depend on UI)
- `backend/` importing from `frontend/` or vice versa
- Cross-feature imports when features should be isolated

**Detection**: For each layer, grep its imports — they should only point to same-layer or lower-layer modules.

### 6. Orphan directories
- Empty directories committed to git (usually leftover from moves)
- Directories containing only `__init__.py` or `index.js` with no real content
- Directories named after deleted features

### 7. Generated vs source conflation
- Build output committed alongside source (e.g., `dist/` files next to `src/` files)
- Generated schemas/types mixed with hand-written code without clear marking
- Snapshot files, fixtures not in a dedicated directory

### 8. Inconsistent test location
Pick one pattern; stick to it:
- `tests/` mirror of `src/` — OR
- `__tests__/` co-located with source — OR
- `*.test.js` alongside the source file

Mixed patterns = review finding.

### 9. Config file sprawl
- Multiple `.env.*` files with overlapping keys
- `config/` directory AND scattered config constants in modules
- Duplicate or near-duplicate config files from abandoned environments

### 10. Public vs internal boundary
- Package `__init__.py` or `index.js` that re-exports everything (no clear public API)
- Internal helpers that are accidentally exposed (no `_` prefix, no `internal/` segregation)
- Missing barrel exports where convention says to have them

## How to scan efficiently

1. **Read the convention docs first** (CLAUDE.md, README.md) — write down the rules
2. **Get a tree view**: `find . -type d -not -path "*/node_modules/*" -not -path "*/\.*"` — spot misplaced directories
3. **Get a file type distribution**: count files per extension per directory — spot mismatches (e.g., `.jsx` files in `lib/` which should be `.js`)
4. **Grep for cross-layer imports** to catch architecture violations
5. **Compare 2–3 similar features** to catch inconsistent grouping

## Questions to ask

- "Does this file's location match what it does?"
- "If I added a new feature tomorrow, where would it go? Is there a clear answer?"
- "Are there two places I could reasonably put a new utility? That's a smell."
- "Does the project's stated structure in CLAUDE.md match reality?"
- "Is there a pattern here, or did each feature pick its own layout?"

## Output format

```markdown
## Structure findings

### Convention violations
- `components/chart/tradeSidebar.jsx` — CLAUDE.md says components are PascalCase → should be `TradeSidebar.jsx`

### Misplaced files
- `backend/routers/portfolio.py:60-90` — cache logic should live in `engine/` or a dedicated `cache/` module

### Cross-layer imports
- `backend/engine/pnl.py:12` imports from `routers/` — violates layering

### Inconsistent grouping
- Feature X is colocated under `components/featureX/`, but Feature Y is scattered across `components/`, `hooks/`, `lib/`

### Structural suggestions
- Consider creating `backend/config/` for shared constants currently duplicated across modules
```
