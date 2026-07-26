"""PreToolUse hook: サブエージェント呼び出しに model 指定とルールフッターを強制する。

CLAUDE.md「モデルの使い分け」を文章だけでなく機械的に担保するためのもの。
方針は dev-docs/LIFE_SIM_DEV_PLAN.md 付録E。
"""

import json
import sys

RULES_SENTINEL = "[AGENT-RULES v1]"
RULES_FOOTER = """[AGENT-RULES v1]
- 長時間コマンドはBashのrun_in_backgroundを使わず、フォアグラウンドでtimeoutを伸ばして完走させる。完了を確認する前にターンを終えない
- 最終メッセージ=完全な成果物レポート。「待機する」「後で確認する」で終えるのは禁止
- git commit / push 禁止
- 実行時にOpenAIを呼ぶコードを書かない（恒久ルール）"""

data = json.load(sys.stdin)
tool_input = data.get("tool_input") or {}

problems = []
if not tool_input.get("model"):
    problems.append(
        "explicit `model` is required (token economy rule / DEV_PLAN 付録E): "
        "sonnet for storylet drafting, CPK part implementation, research and "
        "routine implementation; haiku for mechanical fixes and searches; "
        "opus only for state-model / schema design, foreshadowing design, "
        "storylet screening, and simulation-result interpretation"
    )
if RULES_SENTINEL not in (tool_input.get("prompt") or ""):
    problems.append(
        "prompt must include the standard rules footer VERBATIM (append at the end):\n"
        + RULES_FOOTER
    )

if problems:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "Agent call rejected: "
                    + "\n\n".join(problems),
                }
            }
        )
    )
sys.exit(0)
