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
            "Review & Feedback", "Passive Domain Routing", "Communication",
            "Compliance Tier"}
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


# A pointer line has structure: `- [id: <slug>] (optional bracket tags)* → <class>$`
# anchored at end-of-line. Rule bodies that quote `→` in prose do not match
# because the body continues past the arrow with further prose.
POINTER_LINE_RE = re.compile(
    r"^- \[id: [a-z0-9-]+\](?:\s+\[[^\]]+\])*\s+→\s+(core|docs-only|rest)\s*$"
)


def collect_ids(path: Path) -> tuple[list[tuple[str, int]], list[str]]:
    """Collect (id, line) tuples plus structural errors for a single file.

    Errors include missing-id lines, invalid-id-format lines, and duplicates
    within this single file. Cross-file checks (orphan pointer/body, removed-id)
    live in lint_union.
    """
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

    counts = Counter(rid for rid, _ in ids_seen)
    for rid, n in counts.items():
        if n > 1:
            where = [str(ln) for r, ln in ids_seen if r == rid]
            errors.append(f"{path}: duplicate id '{rid}' on lines {','.join(where)}")
    for rid, ln in ids_seen:
        if not RID_RE.match(rid):
            errors.append(f"{path}:{ln}: invalid id format: {rid}")
    return ids_seen, errors


def is_pointer_line(line: str) -> bool:
    """A pointer is the full-line shape `- [id: <slug>] (tags)? → <class>`.

    Body lines that quote `→` in prose continue past the arrow with more
    text, so the end-of-line anchor in POINTER_LINE_RE rejects them.
    """
    return bool(POINTER_LINE_RE.match(line))


def collect_residency_metadata(path: Path) -> tuple[set[str], set[str]]:
    """Return (compliance_tier_ids, hr_ids) found as bodies in `path`.

    Used by `lint_union` to enforce the invariant that every
    `[compliance-tier]`-tagged rule AND every `hr-*` rule lives in
    `AGENTS.core.md`. Per CPO sign-off on PR #3496, demoting an `hr-*`
    out of core is a single-user-incident-class regression; until the
    workflow is hardened, this linter is the canonical enforcer.
    """
    compliance_ids: set[str] = set()
    hr_ids: set[str] = set()
    if not path.exists():
        return compliance_ids, hr_ids
    in_section = False
    for line in path.read_text().splitlines():
        m = re.match(r"^## (.+?)\s*$", line)
        if m:
            in_section = m.group(1).strip() in SECTIONS
            continue
        if not in_section or not line.startswith("- ") or is_pointer_line(line):
            continue
        id_match = ID_RE.search(line)
        if not id_match:
            continue
        rid = id_match.group(1)
        if rid.startswith("hr-"):
            hr_ids.add(rid)
        if "[compliance-tier]" in line:
            compliance_ids.add(rid)
    return compliance_ids, hr_ids


def collect_ids_typed(path: Path) -> tuple[set[str], set[str], list[str]]:
    """Split ids in a file into (pointer_ids, body_ids, errors).

    Pointer lines (slug-only `- [id: x] → core`) populate pointer_ids.
    Full-body lines populate body_ids. A single file may contain only one
    type in practice (index = pointers, sidecars = bodies), but the
    classifier is per-line for robustness.
    """
    content = path.read_text()
    lines = content.splitlines()
    errors: list[str] = []
    in_section = False
    pointer_ids: set[str] = set()
    body_ids: set[str] = set()
    seen_locations: dict[str, list[int]] = {}

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
        rid = match.group(1)
        if not RID_RE.match(rid):
            errors.append(f"{path}:{i}: invalid id format: {rid}")
            continue
        seen_locations.setdefault(rid, []).append(i)
        if is_pointer_line(line):
            pointer_ids.add(rid)
        else:
            body_ids.add(rid)
    # Per-file duplicates: an id appearing twice in the same file is an error
    # regardless of pointer/body kind.
    for rid, lns in seen_locations.items():
        if len(lns) > 1:
            errors.append(
                f"{path}: duplicate id '{rid}' on lines {','.join(str(x) for x in lns)}"
            )
    return pointer_ids, body_ids, errors


def lint_union(
    paths: list[Path],
    index_path: Path,
    retired_ids: set[str],
) -> int:
    """Cross-file lint: pointer↔body 1:1 across (index, sidecars) + sibling-
    aware removed-id check.

    `paths` is the union (may include `index_path`; deduped by resolved path).
    The index file contributes pointer ids; every other file contributes body
    ids. A working-set id is `pointer_ids ∪ body_ids_in_sidecars`.

    Removed-id check: an id present at HEAD:index_path that is NOT in
    `pointer_ids ∪ body_ids_in_sidecars` AND NOT in retired_ids is reported.
    Rules that moved out of AGENTS.md into a sidecar therefore do not trigger
    a false-positive removal.
    """
    # Dedupe by realpath
    seen_real: set[str] = set()
    deduped: list[Path] = []
    for p in paths:
        real = str(p.resolve())
        if real in seen_real:
            continue
        seen_real.add(real)
        deduped.append(p)

    errors: list[str] = []
    pointer_ids: set[str] = set()
    body_ids: set[str] = set()
    index_real = str(index_path.resolve())

    for p in deduped:
        if not p.exists():
            errors.append(f"ERROR: {p} not found")
            continue
        f_pointers, f_bodies, f_errors = collect_ids_typed(p)
        errors.extend(f_errors)
        if str(p.resolve()) == index_real:
            pointer_ids |= f_pointers
            # Sometimes the index is so thin that the linter sees a slug-only
            # line as a "body" (e.g. when the arrow is absent on a single line).
            # Treat any id in the index file as a pointer for the cross-file
            # validation — the index file's role is structural, not body-bearing.
            pointer_ids |= f_bodies
        else:
            body_ids |= f_bodies
            # Pointers inside a sidecar would be an authoring error (sidecar
            # is supposed to hold bodies). Surface them as errors.
            if f_pointers:
                errors.append(
                    f"{p}: pointer lines (with ` → `) found inside a sidecar — "
                    f"sidecars hold rule bodies, not pointers: {sorted(f_pointers)}"
                )

    # Cross-id validation: pointer↔body 1:1
    orphan_pointers = sorted(pointer_ids - body_ids)
    if orphan_pointers:
        errors.append(
            f"{index_path}: pointer(s) without matching body in any sidecar: "
            f"{orphan_pointers}. Either add the body to a sidecar or remove "
            "the pointer."
        )
    orphan_bodies = sorted(body_ids - pointer_ids)
    if orphan_bodies:
        # Identify which sidecars host the orphans for the error message
        offenders = []
        for p in deduped:
            if str(p.resolve()) == index_real or not p.exists():
                continue
            _, file_bodies, _ = collect_ids_typed(p)
            local_orphans = sorted(file_bodies & set(orphan_bodies))
            if local_orphans:
                offenders.append(f"{p}: {local_orphans}")
        errors.append(
            f"sidecar body(ies) without matching pointer in {index_path}: "
            + "; ".join(offenders)
            + ". Either add a pointer to the index or remove the body."
        )

    # Residency invariants (CPO sign-off PR #3496, condition #3):
    # 1. Every `[compliance-tier]`-tagged rule MUST live in AGENTS.core.md.
    # 2. Every `hr-*` rule MUST live in AGENTS.core.md.
    # The hook injects `core` on every session regardless of class; demoting
    # one of these into `docs-only` or `rest` produces a single-user-incident-
    # class gap (the rule would be absent from sessions whose change-class
    # doesn't fire the sidecar containing it).
    core_path = index_path.parent / "AGENTS.core.md"
    if core_path.exists():
        core_compliance, core_hr = collect_residency_metadata(core_path)
    else:
        core_compliance, core_hr = set(), set()
    for p in deduped:
        if str(p.resolve()) == index_real or not p.exists() or p.resolve() == core_path.resolve():
            continue
        side_compliance, side_hr = collect_residency_metadata(p)
        bad_compliance = sorted(side_compliance - core_compliance)
        if bad_compliance:
            errors.append(
                f"{p}: [compliance-tier] rule(s) outside AGENTS.core.md: "
                f"{bad_compliance}. These rules MUST be in core (loaded "
                "every session) — move the body to AGENTS.core.md."
            )
        bad_hr = sorted(side_hr - core_hr)
        if bad_hr:
            errors.append(
                f"{p}: hr-* rule(s) outside AGENTS.core.md: {bad_hr}. "
                "Hard Rules MUST be in core per CPO sign-off PR #3496 "
                "(condition #3) — move the body to AGENTS.core.md."
            )

    # Retired-id reintroduction check (union of pointers + bodies)
    current_ids = pointer_ids | body_ids
    reintroduced = retired_ids & current_ids
    if reintroduced:
        errors.append(
            f"retired id(s) reintroduced as active rules: {sorted(reintroduced)}. "
            "Retired ids may not be reused; remove from "
            "scripts/retired-rule-ids.txt or choose a new id."
        )

    # Sibling-aware removed-id check vs HEAD:<index_path>
    try:
        head = subprocess.run(
            ["git", "show", f"HEAD:{index_path}"],
            capture_output=True, text=True, check=True,
        ).stdout
        head_ids = set(m.group(1) for m in ID_RE.finditer(head))
        removed = head_ids - current_ids - retired_ids
        if removed:
            errors.append(
                f"{index_path}: removed id(s) detected: {sorted(removed)}. "
                "Add to scripts/retired-rule-ids.txt to retire."
            )
    except subprocess.CalledProcessError:
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
        "--index-file",
        type=Path,
        default=None,
        help=(
            "Path to the pointer-index file (e.g. AGENTS.md after the #3493 "
            "sidecar migration). When provided, the linter switches to "
            "cross-file mode: validates pointer↔body 1:1 across positional "
            "sidecar paths, sibling-aware removed-id detection."
        ),
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

    # Cross-file mode: when --index-file is provided, validate pointer↔body
    # 1:1 across the union of files (sidecar split per #3493).
    if args.index_file is not None:
        if not args.index_file.exists():
            print(f"ERROR: --index-file {args.index_file} not found", file=sys.stderr)
            return 2
        # Ensure index is among paths so its pointer ids are collected.
        union = list(paths)
        if args.index_file not in union:
            union.insert(0, args.index_file)
        return lint_union(union, args.index_file, retired_ids)

    # Legacy single-file mode (backward-compat).
    rc = 0
    for p in paths:
        if not p.exists():
            print(f"ERROR: {p} not found", file=sys.stderr)
            return 2
        rc |= lint(p, retired_ids)
    return rc


if __name__ == "__main__":
    sys.exit(main())
