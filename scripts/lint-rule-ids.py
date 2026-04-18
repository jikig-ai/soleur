#!/usr/bin/env python3
"""Lint AGENTS.md for rule-id coverage and uniqueness.

Fails (exit 1) if any rule under a tagged section is missing `[id: <slug>]`,
or if any id is duplicated. Optionally also flags removed IDs by diffing
against HEAD (git must be reachable).

Usage:
    python scripts/lint-rule-ids.py [AGENTS.md]
"""

from __future__ import annotations

import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

SECTIONS = {"Hard Rules", "Workflow Gates", "Code Quality",
            "Review & Feedback", "Passive Domain Routing", "Communication"}
ID_RE = re.compile(r"\[id: ([a-z0-9-]+)\]")


def lint(path: Path) -> int:
    content = path.read_text()
    lines = content.splitlines()
    errors: list[str] = []
    in_section = False

    ids_seen: list[tuple[str, int]] = []
    for i, line in enumerate(lines, start=1):
        m = re.match(r"^## (.+?)\s*$", line)
        if m:
            in_section = m.group(1).strip() in SECTIONS
            continue
        if not in_section or not line.startswith("- "):
            continue
        match = ID_RE.search(line)
        if not match:
            errors.append(f"{path}:{i}: rule missing [id: ...] tag: {line[:80]!r}")
            continue
        ids_seen.append((match.group(1), i))

    # Duplicates
    counts = Counter(rid for rid, _ in ids_seen)
    for rid, n in counts.items():
        if n > 1:
            where = [str(ln) for r, ln in ids_seen if r == rid]
            errors.append(f"{path}: duplicate id '{rid}' on lines {','.join(where)}")

    # ID format
    for rid, ln in ids_seen:
        if not re.match(r"^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$", rid):
            errors.append(f"{path}:{ln}: invalid id format: {rid}")

    # Removed-id diff check: hard-fail (exit 1) when an id present at HEAD
    # is absent from the working copy. Appending to `errors` below triggers
    # the exit-1 path at the end of this function — there is no "warn only"
    # path for this check.
    #
    # Format drift guard: the rule_id regex above (ID_RE) is mirrored in
    # scripts/rule-prune.sh as _RULE_ID_RE. Bash ERE and Python `re` differ
    # in syntax, so the two definitions are kept in sync manually.
    try:
        head = subprocess.run(
            ["git", "show", f"HEAD:{path}"],
            capture_output=True, text=True, check=True,
        ).stdout
        head_ids = set(m.group(1) for m in ID_RE.finditer(head))
        current_ids = set(rid for rid, _ in ids_seen)
        removed = head_ids - current_ids
        if removed:
            errors.append(
                f"{path}: removed id(s) detected: {sorted(removed)}. "
                "Rewording is fine; removing an id requires deprecation."
            )
    except subprocess.CalledProcessError:
        # File not in HEAD yet — skip diff check
        pass

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    return 0


def main() -> int:
    paths = [Path(p) for p in sys.argv[1:]] or [Path("AGENTS.md")]
    rc = 0
    for p in paths:
        if not p.exists():
            print(f"ERROR: {p} not found", file=sys.stderr)
            return 2
        rc |= lint(p)
    return rc


if __name__ == "__main__":
    sys.exit(main())
