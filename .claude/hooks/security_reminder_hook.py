#!/usr/bin/env python3
# PreToolUse hook: advise on GitHub Actions workflow-injection sinks.
# Fires only when the Edit's new_string introduces a known untrusted
# `${{ github.event.* }}` interpolation AND the file contains a `run:` block.
#
# Corresponding prose rule:
#   AGENTS.md hr-in-github-actions-run-blocks-never-use (indirect)
#   https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions
#
# Response contract (per Claude Code PreToolUse hook spec, same convention as
# .claude/hooks/worktree-write-guard.sh):
#   - Safe edit   -> exit 0, no stdout  (allow by default)
#   - Risky edit  -> exit 0, stdout JSON {hookSpecificOutput.permissionDecision: "deny", ...}
#   - Not an Edit -> exit 0, no stdout  (matcher should prevent this, defense-in-depth)
#   - Any error   -> exit 0, no stdout  (fail-open: advisory hook must never block unparseable input)
#
# Dependencies: Python 3 stdlib only (re, json, sys, fnmatch). If python3 is
# missing at runtime the hook exits 127 which Claude Code treats as a no-op.

import json
import re
import sys
from fnmatch import fnmatch

# Literal sink strings that must trigger the advisory when present alongside a
# `run:` directive in the same new_string.
LITERAL_SINKS = (
    "github.event.issue.title",
    "github.event.issue.body",
    "github.event.pull_request.title",
    "github.event.pull_request.body",
    "github.event.comment.body",
    "github.event.review.body",
    "github.event.review_comment.body",
    "github.event.head_commit.message",
    "github.event.head_commit.author.email",
    "github.event.head_commit.author.name",
    "github.event.pull_request.head.ref",
    "github.event.pull_request.head.label",
    "github.event.pull_request.head.repo.default_branch",
    "github.head_ref",
)

# Regex sinks cover wildcard / indexed path accesses.
# `commits[0].message`, `commits.something.message`, `pages[*].page_name`, etc.
REGEX_SINKS = (
    re.compile(r"github\.event\.commits(?:\[[^\]]+\]|\.[^}\s.]+)\.message"),
    re.compile(r"github\.event\.commits(?:\[[^\]]+\]|\.[^}\s.]+)\.author\.email"),
    re.compile(r"github\.event\.commits(?:\[[^\]]+\]|\.[^}\s.]+)\.author\.name"),
    re.compile(r"github\.event\.pages(?:\[[^\]]+\]|\.[^}\s.]+)\.page_name"),
)

# Match `run:` as a YAML key on any indentation level, including list-item
# form (`- run: ...`). Accepts an optional leading `-` so `      - run: |`
# matches as well as `      run: |`.
RUN_DIRECTIVE = re.compile(r"^\s*-?\s*run:", re.MULTILINE)

WORKFLOW_GLOBS = (".github/workflows/*.yml", ".github/workflows/*.yaml")


def find_sink(new_string: str) -> str | None:
    """Return the first matched sink literal or regex match, else None."""
    for literal in LITERAL_SINKS:
        if literal in new_string:
            return "${{ " + literal + " }}"
    for rx in REGEX_SINKS:
        match = rx.search(new_string)
        if match:
            return "${{ " + match.group(0) + " }}"
    return None


def is_workflow_file(path: str) -> bool:
    return any(fnmatch(path, pattern) for pattern in WORKFLOW_GLOBS)


def build_advisory(sink: str, file_path: str) -> str:
    return (
        f"Workflow-injection risk detected in new_string:\n"
        f"  - sink: {sink}\n"
        f"  - file: {file_path}\n\n"
        f"Untrusted ${{{{ github.event.* }}}} fields are interpolated into the shell verbatim.\n"
        f"Mitigation: assign the field to an env var first, then reference $VAR inside the\n"
        f"run: script. See:\n"
        f"  https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-an-intermediate-environment-variable\n\n"
        f"If this is intentional and already safe (e.g., the value is pinned to a known\n"
        f"allow-list upstream), acknowledge and re-run the Edit to proceed."
    )


def main() -> int:
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return 0
        payload = json.loads(raw)
    except Exception:
        # Fail-open: unparseable input must never block an edit.
        return 0

    try:
        tool_name = payload.get("tool_name", "")
        if tool_name != "Edit":
            return 0

        tool_input = payload.get("tool_input") or {}
        file_path = tool_input.get("file_path") or ""
        new_string = tool_input.get("new_string")
        if not file_path or not isinstance(new_string, str):
            return 0

        if not is_workflow_file(file_path):
            return 0

        sink = find_sink(new_string)
        if sink is None:
            return 0

        if not RUN_DIRECTIVE.search(new_string):
            # Sink present but no run: block in new_string — safe pattern (env var, etc.).
            return 0

        response = {
            "hookSpecificOutput": {
                "permissionDecision": "deny",
                "permissionDecisionReason": build_advisory(sink, file_path),
            }
        }
        sys.stdout.write(json.dumps(response))
        return 0
    except Exception:
        # Defensive fail-open on any unexpected error in our own logic.
        return 0


if __name__ == "__main__":
    sys.exit(main())
