#!/usr/bin/env python3
"""Lint AGENTS.md for rule-id coverage and uniqueness.

Fails (exit 1) if any rule under a tagged section is missing `[id: <slug>]`,
or if any id is duplicated. Optionally also flags removed IDs by diffing
against HEAD (git must be reachable).

Retired-ids allowlist: pass `--retired-file <path>` to supply a list of ids
that have been retired from AGENTS.md. Retired ids are excluded from the
"removed id" check, and re-introducing a retired id as an active rule fails
the linter. `hr-*` retirements additionally require the id to be listed in
`HR_RETIREMENT_ALLOWLIST` below. See scripts/retired-rule-ids.txt for format.

Usage:
    python scripts/lint-rule-ids.py [--retired-file <path>] [AGENTS.md ...]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

SECTIONS = {"Hard Rules", "Workflow Gates", "Code Quality",
            "Review & Feedback", "Passive Domain Routing", "Communication"}
ID_RE = re.compile(r"\[id: ([a-z0-9-]+)\]")
RID_RE = re.compile(r"^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$")

# hr-* retirement guard (#2871). Adding an id here is the review signal.
# Entries were grandfathered from PR #2865 (discoverability-litmus pass).
# See knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
HR_RETIREMENT_ALLOWLIST = frozenset({
    "hr-before-running-git-commands-on-a",
    "hr-never-use-sleep-2-seconds-in-foreground",
    # Tier 2 migration (2026-04-24): body moved to skill/agent/reference file.
    "hr-when-playwright-mcp-hits-an-auth-wall",
    "hr-never-fake-git-author",
    "hr-in-github-actions-run-blocks-never-use",
    "hr-github-actions-workflow-notifications",
})


def load_retired_ids(retired_file: Path) -> set[str]:
    """Parse retired-rule-ids.txt. Lines: `<id> | <date> | <pr> | <breadcrumb>`.

    Comments (`#`) and blank lines are skipped. Only the first `|`-delimited
    field (the id) is extracted; format/date validation is intentionally
    not enforced here (append-only file, reviewed in PRs).
    """
    retired: set[str] = set()
    # utf-8-sig strips file-level BOM at decode. Per-line BOM/invisibles are
    # caught by RID_RE below (they won't match `[a-z0-9-]`).
    for line in retired_file.read_text(encoding="utf-8-sig").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        rid = stripped.split("|", 1)[0].strip()
        if not rid:
            continue
        if not RID_RE.match(rid):
            raise ValueError(
                f"malformed retired id in {retired_file}: {rid!r} "
                f"(must match {RID_RE.pattern})"
            )
        retired.add(rid)
    return retired


def lint(path: Path, retired_ids: set[str]) -> int:
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

    current_ids = set(rid for rid, _ in ids_seen)

    # Reintroduction check: id in retired allowlist AND active in AGENTS.md.
    # Retired ids must stay retired per cq-rule-ids-are-immutable.
    reintroduced = retired_ids & current_ids
    if reintroduced:
        errors.append(
            f"{path}: retired id(s) reintroduced as active rules: "
            f"{sorted(reintroduced)}. Retired ids may not be reused; "
            "remove from scripts/retired-rule-ids.txt or choose a new id."
        )

    # Removed-id diff check: hard-fail when an id present at HEAD is absent
    # from the working copy AND not in the retired allowlist.
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
        removed = head_ids - current_ids - retired_ids
        if removed:
            errors.append(
                f"{path}: removed id(s) detected: {sorted(removed)}. "
                "Add to scripts/retired-rule-ids.txt to retire."
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
    parser = argparse.ArgumentParser(
        description="Lint AGENTS.md rule-id coverage, uniqueness, and retirement.",
    )
    parser.add_argument(
        "--retired-file",
        type=Path,
        default=None,
        help="Path to retired-rule-ids.txt allowlist (optional).",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Paths to lint (default: AGENTS.md).",
    )
    args = parser.parse_args()

    retired_ids: set[str] = set()
    if args.retired_file is not None:
        if not args.retired_file.exists():
            print(
                f"ERROR: --retired-file {args.retired_file} not found",
                file=sys.stderr,
            )
            return 2
        try:
            retired_ids = load_retired_ids(args.retired_file)
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            return 2

        # hr-* retirement guard: retiring a hard-rule requires editing this
        # script (HR_RETIREMENT_ALLOWLIST above), not a quiet allowlist
        # append. See issue #2871.
        hr_retired = sorted(
            r for r in retired_ids
            if r.startswith("hr-") and r not in HR_RETIREMENT_ALLOWLIST
        )
        if hr_retired:
            print(
                f"ERROR: hard-rule(s) cannot be retired via {args.retired_file}: "
                f"{hr_retired}\n"
                "Hard-rules (hr-*) are security-critical and are linter-blocked "
                "from retirement.\n"
                "To retire one, add the id to HR_RETIREMENT_ALLOWLIST in "
                "scripts/lint-rule-ids.py in the same PR.",
                file=sys.stderr,
            )
            return 1

    paths = args.paths or [Path("AGENTS.md")]
    rc = 0
    for p in paths:
        if not p.exists():
            print(f"ERROR: {p} not found", file=sys.stderr)
            return 2
        rc |= lint(p, retired_ids)
    return rc


if __name__ == "__main__":
    sys.exit(main())
