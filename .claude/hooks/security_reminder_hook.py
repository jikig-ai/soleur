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
import os
import re
import sys
from datetime import datetime, timezone
from fnmatch import fnmatch

try:
    import fcntl  # POSIX-only; absent on Windows. Guard for platform portability.
except ImportError:  # pragma: no cover - platform fallback
    fcntl = None  # type: ignore[assignment]

# schema mirror: .claude/hooks/lib/incidents.sh (keep in sync)
SCHEMA_VERSION = 1

# os.path.realpath canonicalizes through symlinks so the python emitter
# and the bash emitter (incidents.sh uses `cd -P && pwd -P`) resolve to
# the SAME inode when `.claude/` is symlinked into the project. `flock`
# is per-inode — divergent paths produce disjoint locks and torn writes.
_HOOK_DIR = os.path.dirname(os.path.realpath(__file__))


def _incidents_repo_root() -> str:
    """Mirror of incidents.sh _incidents_repo_root — honors the same env var."""
    override = os.environ.get("INCIDENTS_REPO_ROOT", "")
    if override:
        return os.path.realpath(override)
    # From .claude/hooks/, the repo root is two dirs up.
    return os.path.realpath(os.path.join(_HOOK_DIR, "..", ".."))


def emit_incident(rule_id: str, event_type: str, prefix: str, cmd: str = "") -> None:
    """Append one JSONL rule-incident line; fire-and-forget.

    Interlocks with the bash emitter via advisory fcntl.flock on the same
    inode — both writers use LOCK_EX against .claude/.rule-incidents.jsonl,
    so concurrent writes queue rather than interleave. The flock is
    load-bearing: regular-file O_APPEND atomicity holds only up to the
    filesystem block size for a single write(2) syscall, not PIPE_BUF
    (which only applies to pipes). `cmd` is truncated to 1024 bytes to
    keep any single line comfortably within that boundary.
    """
    if not rule_id or not event_type:
        return
    try:
        repo_root = _incidents_repo_root()
        path = os.path.join(repo_root, ".claude", ".rule-incidents.jsonl")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        record = {
            "schema": SCHEMA_VERSION,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "rule_id": rule_id,
            "event_type": event_type,
            "rule_text_prefix": prefix,
            "command_snippet": (cmd or "")[:1024],
        }
        line = (json.dumps(record, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
        # Mode 0o600 (owner rw only): command_snippet can carry PR body text
        # or gh invocation arguments — operator-only readable avoids leaking
        # those into shared-host scenarios. CodeQL py/overly-permissive-file.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            if fcntl is not None:
                fcntl.flock(fd, fcntl.LOCK_EX)
            try:
                # Short-write defense: loop until the whole payload lands.
                view = memoryview(line)
                while view:
                    n = os.write(fd, bytes(view))
                    if n <= 0:
                        break
                    view = view[n:]
            finally:
                if fcntl is not None:
                    fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
    except Exception:
        # Fire-and-forget: never let a telemetry failure block the hook.
        pass

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

        emit_incident(
            "hr-in-github-actions-run-blocks-never-use",
            "deny",
            "In GitHub Actions `run:` blocks, never use heredocs",
            sink,
        )

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
