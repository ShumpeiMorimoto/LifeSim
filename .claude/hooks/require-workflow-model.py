import json
import re
import sys
from pathlib import Path

data = json.load(sys.stdin)
tool_input = data.get("tool_input") or {}

script = tool_input.get("script") or ""
script_path = tool_input.get("scriptPath")
if not script and script_path:
    try:
        script = Path(script_path).read_text(encoding="utf-8")
    except OSError:
        script = ""

# Named workflows ({name: ...}) resolve elsewhere — nothing to check here
if script and re.search(r"\bagent\s*\(", script):
    if not re.search(r"\bmodel\s*:", script):
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            "Workflow rejected: script spawns agent() without any "
                            "`model:` override (token economy rule). Set model: "
                            "'sonnet' (implementation/research) or 'haiku' "
                            "(mechanical) in agent() opts; omit only for stages "
                            "that deliberately need the main model."
                        ),
                    }
                }
            )
        )
sys.exit(0)
