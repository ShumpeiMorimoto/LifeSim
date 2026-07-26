#!/usr/bin/env bash
# PreToolUse hook: `git commit` 前に、ステージ済みの .py へ ruff を、
# src/ が含まれるなら ty を走らせ、エラーがあればコミットをブロックする。
set -euo pipefail

input="$(cat)"
command="$(printf '%s' "$input" | python -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

case "$command" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

staged_py="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.py$' || true)"
if [ -z "$staged_py" ]; then
  exit 0
fi

declare -a findings=()

if command -v uv >/dev/null 2>&1; then
  ruff_out="$(uv run ruff check $staged_py 2>&1 || true)"
  if printf '%s' "$ruff_out" | grep -qE '^(error|[A-Za-z0-9_/.-]+\.py:)'; then
    findings+=("ruff failures:")
    findings+=("$ruff_out")
  fi

  if printf '%s' "$staged_py" | grep -q '^src/'; then
    ty_out="$(uv run ty check src 2>&1 || true)"
    if printf '%s' "$ty_out" | grep -qiE '^(error|[A-Za-z0-9_/.-]+\.py:.*error)'; then
      findings+=("ty failures:")
      findings+=("$ty_out")
    fi
  fi
fi

if [ "${#findings[@]}" -eq 0 ]; then
  exit 0
fi

reason="Lint hook blocked the commit:\n"
for f in "${findings[@]}"; do
  reason="${reason}${f}\n"
done
reason="${reason}Fix the issues, re-stage, and commit again. Bypass with --no-verify only if you know the failures are spurious."

python - "$reason" <<'PY'
import json, sys
reason = sys.argv[1].replace("\\n", "\n")
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
PY
exit 0
