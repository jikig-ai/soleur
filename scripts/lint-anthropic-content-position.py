#!/usr/bin/env python3
"""Refuse a reader that selects an Anthropic content block by POSITION (#8392).

A model swap changes response block ORDERING: `claude-sonnet-5` has run adaptive
thinking by default since #5849, so the first block is a thinking block and the
text follows it. Every reader that indexed a fixed position silently returned ""
for ten weeks while the model answer was billed and discarded.

Why this is a CI lint and not a line in the model-launch audit: the audit's census
runs only in its hand-run `audit` mode — `--detect` (the sole scheduled caller,
.github/workflows/rule-audit.yml) and `--fix` (the mode that PERFORMS the model
swap) both return before it. "Never index a fixed content position" is a standing
code invariant, not a launch-checklist item, so it belongs on the rail that runs
on every PR. Registered twice in scripts/test-all.sh (fixture suite + live scan)
per the convention its own comment records: "this one was registered once, which
made it decoration."

Exit 0 clean, 1 on findings, 2 if the scan itself could not run — a detector that
cannot tell "clean" from "could not look" is the defect this file exists to stop.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# A content array indexed by a literal, `.at(N)`, or `content.length - 1`.
POSITIONAL = re.compile(
    r"""\.content\s*\??\s*(?:\.\s*)?           # .content / .content? / .content?.
        (?:
            \[\s*(?:\d+|[\w$.]+\.length\s*-\s*\d+)\s*\]            # [0] / [x.y.length-1]
          | at\(\s*-?\d+\s*\)                                      # .at(0)
        )""",
    re.VERBOSE,
)
# The jq spelling, in shell.
POSITIONAL_JQ = re.compile(r"\.content\s*\[\s*-?\d+\s*\]")

EXTENSIONS = (".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs", ".sh", ".bash", ".py", ".yml", ".yaml")

# Paths whose `content[0]` is a DIFFERENT type — our own MCP ToolResponse, fixtures,
# and this file plus its suite (both carry the pattern as data).
EXEMPT = re.compile(
    r"(^|/)(node_modules|\.git|\.next|archive|spike)/"
    r"|(^|/)knowledge-base/"
    r"|\.test\.|\.spec\.|(^|/)tests?/|(^|/)__tests__/"
    r"|(^|/)scripts/lint-anthropic-content-position\.py$"
)

# A file is only in scope if it plausibly handles an Anthropic Messages response.
IN_SCOPE = re.compile(r"api\.anthropic\.com|@anthropic-ai/sdk|anthropic-version|\.content\b")


def tracked_files(root: Path) -> list[Path]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"lint-anthropic-content-position: could not enumerate files under {root}: {exc}", file=sys.stderr)
        sys.exit(2)
    names = [n for n in out.split("\0") if n]
    if not names:
        print(f"lint-anthropic-content-position: git ls-files returned NOTHING under {root} — refusing to report clean.", file=sys.stderr)
        sys.exit(2)
    return [root / n for n in names if n.endswith(EXTENSIONS) and not EXEMPT.search(n)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=None)
    args = ap.parse_args()
    root = Path(args.root) if args.root else Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
    )

    findings: list[str] = []
    scanned = 0
    for path in tracked_files(root):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not IN_SCOPE.search(text):
            continue
        scanned += 1
        for n, line in enumerate(text.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith(("//", "#", "*")):
                continue
            if POSITIONAL.search(line) or POSITIONAL_JQ.search(line):
                findings.append(f"{path.relative_to(root)}:{n}: selects an Anthropic content block by POSITION\n    {stripped[:160]}")

    if findings:
        print(f"[REJECT] lint-anthropic-content-position: {len(findings)} finding(s) across {scanned} scanned file(s).", file=sys.stderr)
        for f in findings:
            print(f"  {f}", file=sys.stderr)
        print("  fix: select by block TYPE — `content.find((b) => b.type === \"text\")`,", file=sys.stderr)
        print("       or in jq `first(.content[] | select(.type == \"text\") | .text)`.", file=sys.stderr)
        return 1

    # Name the scope. An unqualified "no positional readers" would be a claim about
    # the CLASS from a scan of two SPELLINGS: an aliased binding
    # (`const c = msg.content; c[c.length - 1]`) is invisible here by construction,
    # and one such reader exists today (agent-runner.ts, type-guarded and
    # deliberately last-block for streaming partials — not this defect).
    print(
        f"[OK] lint-anthropic-content-position: {scanned} Anthropic-response file(s) scanned; "
        "no reader indexes `.content` by a literal position, `.at(N)`, or `.length - N`. "
        "Aliased-binding reads are out of scope for this scan."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
