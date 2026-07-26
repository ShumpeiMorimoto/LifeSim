#!/usr/bin/env bash
# PreToolUse hook: `git commit` 前にステージ済みファイルを走査し、
# 秘密情報が混入していればコミットをブロックする。
set -euo pipefail

input="$(cat)"
command="$(printf '%s' "$input" | python -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

case "$command" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

staged="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)"
if [ -z "$staged" ]; then
  exit 0
fi

declare -a findings=()

while IFS= read -r file; do
  [ -z "$file" ] && continue
  case "$file" in
    *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.lock) continue ;;
  esac

  blob="$(git show ":$file" 2>/dev/null || true)"
  [ -z "$blob" ] && continue

  # 資格情報の直書き
  if printf '%s' "$blob" | grep -nE '^[[:space:]]*(ANTHROPIC_API_KEY|API_SECRET_KEY|SECRET_KEY|RENDER_API_KEY|DATABASE_URL)[[:space:]]*=[[:space:]]*[^[:space:]"'\'']' >/dev/null; then
    findings+=("$file: hardcoded credential value (use .env, not committed files)")
  fi

  # 各社APIキーのパターン
  if printf '%s' "$blob" | grep -nE '(sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|rnd_[A-Za-z0-9]{20,})' >/dev/null; then
    findings+=("$file: API key pattern (Anthropic/AWS/OpenAI/GitHub/Render)")
  fi

  # 恒久ルール違反: 実行時OpenAI
  if printf '%s' "$blob" | grep -nE '^[[:space:]]*(import[[:space:]]+openai|from[[:space:]]+openai[[:space:]]+import)' >/dev/null; then
    findings+=("$file: OpenAI import — このプロジェクトはOpenAIを使わない（恒久ルール / CLAUDE.md）")
  fi
done <<< "$staged"

if [ "${#findings[@]}" -eq 0 ]; then
  exit 0
fi

reason="Secret-check hook blocked the commit:\n"
for f in "${findings[@]}"; do
  reason="${reason}  - ${f}\n"
done
reason="${reason}If a finding is a false positive, bypass with: git commit --no-verify (still subject to user review)."

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
