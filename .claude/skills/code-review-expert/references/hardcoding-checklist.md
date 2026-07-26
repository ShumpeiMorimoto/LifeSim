# Hardcoding & Magic Values Checklist

Hardcoded values are a frequent source of bugs, maintenance burden, and duplication. Scan for them explicitly — they are rarely caught by language linters alone.

## What to scan for

### 1. Magic numbers
- Timeouts (e.g., `timeout=30`, `setInterval(..., 3000)`)
- Retry counts, batch sizes, cache TTLs
- ML/statistical thresholds (e.g., `if confidence > 0.7`)
- Pagination limits, window sizes
- Bounds and clamps (`min`, `max`, `clip`)

**Ask**: "If this value needed to change, how many files would I touch? Is the meaning obvious from the value?"

### 2. Magic strings
- URLs, hostnames, API endpoints
- File paths (absolute paths especially)
- Model names (`gpt-4o-mini`, `claude-sonnet`)
- Error codes, status identifiers
- Column names, table names, config keys
- Encoding names (`shift_jis`, `utf-8`)
- Regex patterns used in multiple places

### 3. Duplicated constants across files
**This is the most commonly missed category.** Search for the same literal in multiple files — it almost always indicates missing shared module.

Example pattern to catch:
```
fileA.py:  SBI_LOGIN_URL = "https://..."
fileB.py:  SBI_LOGIN_URL = "https://..."   # DUPLICATE — should be shared
```

**How to find**:
- Grep for the same string literal across all source files
- Check for the same constant name defined in multiple modules
- Look for SBI/API/model names that appear in >1 file

### 4. Environment-specific values hardcoded
- Windows paths (`C:\Users\...`) in cross-platform code
- Dev URLs (`localhost:5173`) without fallback
- Platform-specific commands

### 5. Color values / CSS in JS
- Hex colors (`#10b981`) in JSX/JS when a design system exists
- Inline style objects that bypass theme variables
- Tailwind classes with arbitrary values (`bg-[#f8fafc]`) when a semantic token exists

### 6. Values that should be config
- User agent strings
- Port numbers (default fallbacks OK, but document)
- Default model choices (should be env-configurable for experimentation)

## Scanning strategy

**Do NOT rely on reading files sequentially.** Use grep-based detection:

1. **Numeric literal scan**: grep for patterns like `= \d+`, `timeout=\d+`, `sleep\(\d+\)` — note any numeric literal > 5 that isn't obviously a dimension
2. **URL scan**: grep for `https://` — every URL outside env/config is a finding
3. **Duplicate constant scan**: for each suspicious literal, grep across ALL files to check for duplicates
4. **Color scan (frontend)**: grep for `#[0-9a-f]{3,8}` in .jsx/.js — flag if outside a theme/config file
5. **Path scan**: grep for `C:\\`, `/home/`, `/Users/` — flag any hardcoded absolute path

## When hardcoding is acceptable

- **Constants with obvious meaning** in a single well-named location (`MARKET_OPEN_MINUTE = 9 * 60`)
- **Type tags** used in discriminated unions (`type: "buy"`)
- **One-off UI strings** that have no reuse
- **Test fixtures** (tests should be self-documenting)
- **Language/framework conventions** (`@dataclass`, `export default`)

## Output format for findings

For each hardcoded value, report:
- **Where**: file:line
- **Value**: the literal
- **Duplication count**: how many other files contain the same literal
- **Suggested location**: which config file/module should own it
- **Why it matters**: what breaks if it changes or stays inconsistent
