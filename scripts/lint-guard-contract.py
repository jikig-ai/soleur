#!/usr/bin/env python3
"""Guard Contract completeness gate (plan/SKILL.md §2.12, deepen-plan §4.11).

The class this exists to catch: **a guard whose WINDOW, CHOKEPOINT or IDENTIFIER
SET is narrower than the property it names.** The preflight Check 10 work
(merged 2026-08-10) absorbed five adversarial review rounds and ~20 findings that
all reduced to that one class — a mount-set closure assertion scoped to one array
while three other code paths also injected mounts; a parity floor counting
iterations rather than distinct shapes; a suppression grep anchored on rebindable
identifiers; and an anti-vacuity gate with no floor on its own dispatch.

Those were not five discoveries. They were one enumeration nobody performed.

The plan-time countermeasure is the Guard Contract: per guard, (1) the property
in one sentence, (2) the ASSEMBLY the property quantifies over, and (3) a
mutation matrix of >= 3 edits that must go RED. Members drift; assembly is
structural. Field (2) is the one whose absence cost the five rounds.

This gate's OWN first version reproduced four instances of that class, all found
by review and all now fixtured:

  - it swept `plans/*.md` NON-recursively, so a plan one directory deeper was
    never checked (one such plan exists in the repo today);
  - it matched the section heading by exact string equality, so
    `## Guard Contract (3 guards)` silently exempted the whole file;
  - it read only the FIRST Guard Contract section;
  - it counted rows in ANY markdown table in the entry, so an Assembly written
    as a 3-row table satisfied the mutation-matrix floor with no matrix present;
  - and it exited 0 having examined nothing.

Scope
-----
With no path arguments, walks `<repo-root>/knowledge-base/project/plans/**.md`
RECURSIVELY, excluding any path with an `archive/` component. Fenced code blocks
are masked out before parsing, so a template pasted into a ```markdown fence is
not mistaken for a real entry (and a `## ` line inside a fence does not truncate
the section).

A file with no Guard Contract heading is SKIPPED — the contract is required only
when the deliverable includes a guard, and that judgement is the plan author's
(deepen-plan §4.11 Step 1 is the check for absence).

Exit codes: 0 PASS, 1 one or more FAIL, 2 argument/IO error.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Tolerant of trailing text and of runs of whitespace: an exact-equality match
# let `## Guard Contract (3 guards)` exempt an entire file.
SECTION_RE = re.compile(r"^##\s+Guard\s+Contract\b")
NEXT_H2_RE = re.compile(r"^##\s+\S")
ENTRY_RE = re.compile(r"^###\s+Guard\b(.*)$")
# Any heading level OR indentation that mentions Guard but is not a clean `###`.
# Previously these folded into the preceding entry, hiding their own missing
# fields AND inflating that entry's matrix row count.
MISLEVELLED_RE = re.compile(r"^(?:\s+###|#{1,2}#?#\s*Guard\b|\s+#{2,6}\s*Guard\b)")
BAD_LEVEL_RE = re.compile(r"^(?:\s+#{3}\s+Guard\b|#{4,6}\s+Guard\b|#{1,2}\s+Guard\s+\d)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")

# Boundary detection must OVER-match and name matching must not: one regex doing
# both is what let `**Mutation matrix (3 rows):**` fail to terminate the
# preceding field, so a literal `TBD` Assembly swallowed it and passed.
BOUNDARY_RE = re.compile(r"^(?:\*\*\*|\*\*|__)\S")
FIELD_RE = re.compile(r"^(?:\*\*\*|\*\*|__)(?P<name>[^*_]+?)(?P<punct>[.:]?)(?:\*\*\*|\*\*|__)(?P<rest>.*)$")

TABLE_ROW_RE = re.compile(r"^\s*\|")
TABLE_SEP_RE = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
MIN_MUTATION_ROWS = 3

PLACEHOLDERS = {
    "tbd", "tbc", "todo", "fixme", "wip", "xxx", "n/a", "na", "none",
    "placeholder", "<placeholder>", "-", "...", "?", "see above", "see below",
    "pending",
}
ANGLE_PLACEHOLDER_RE = re.compile(r"^<[^>]+>$")


def is_placeholder(text: str) -> bool:
    """True when a field's value carries no information.

    Judged on the FIRST meaningful line, not the whole concatenation: an author
    who writes `**Assembly.** TBD` followed by any prose sentence otherwise
    defeats the check, because the joined value stops matching a placeholder
    token.
    """
    lines = [l.strip() for l in text.splitlines()]
    meaningful = [l for l in lines if l]
    if not meaningful:
        return True
    first = meaningful[0].strip("*_`").strip().rstrip(".").lower()
    return first in PLACEHOLDERS or bool(ANGLE_PLACEHOLDER_RE.match(meaningful[0].strip()))


def mask_fences(lines: list[str]) -> list[bool]:
    """True for each line that sits INSIDE a fenced code block."""
    inside = False
    mask: list[bool] = []
    for line in lines:
        if FENCE_RE.match(line):
            mask.append(True)          # the fence marker itself is not content
            inside = not inside
            continue
        mask.append(inside)
    return mask


def extract_sections(lines: list[str], fenced: list[bool]) -> list[list[tuple[int, str]]]:
    """Every `## Guard Contract` body, as (index, line) pairs. Fenced lines are
    excluded, so a `## ` inside a code block cannot truncate a section."""
    sections: list[list[tuple[int, str]]] = []
    i = 0
    n = len(lines)
    while i < n:
        if not fenced[i] and SECTION_RE.match(lines[i]):
            body: list[tuple[int, str]] = []
            j = i + 1
            while j < n:
                if not fenced[j] and NEXT_H2_RE.match(lines[j]):
                    break
                body.append((j, lines[j]))
                j += 1
            sections.append(body)
            i = j
            continue
        i += 1
    return sections


def split_entries(
    body: list[tuple[int, str]], fenced: list[bool], failures: list[str], where: str
) -> list[tuple[str, list[str]]]:
    entries: list[tuple[str, list[str]]] = []
    label: str | None = None
    current: list[str] = []
    for idx, line in body:
        if fenced[idx]:
            continue
        if BAD_LEVEL_RE.match(line):  # MUT:level
            failures.append(  # MUT:level
                f"{where}: guard entry at the wrong heading level or indentation: "  # MUT:level
                f"{line.strip()!r} — use a top-level '### Guard <n> — <name>'"  # MUT:level
            )  # MUT:level
            continue  # MUT:level
        m = ENTRY_RE.match(line)
        if m:
            if label is not None:
                entries.append((label, current))
            label = line.strip().lstrip("#").strip()
            current = []
        elif label is not None:
            current.append(line)
    if label is not None:
        entries.append((label, current))
    return entries


def field_span(entry_lines: list[str], name: str) -> str | None:
    """Value of a `**<name>**` field: same-line remainder plus following lines up
    to the next BOLD BOUNDARY or heading. Table rows no longer terminate the span
    unless content has already been collected, so an Assembly written as a table
    is not read as empty."""
    target = name.lower()
    collected: list[str] = []
    capturing = False
    for line in entry_lines:
        stripped = line.strip()
        if BOUNDARY_RE.match(stripped):
            m = FIELD_RE.match(stripped)
            found = m.group("name").strip().lower() if m else None
            if capturing:
                break
            if found == target:
                capturing = True
                collected.append(m.group("rest") if m else "")
                continue
        if capturing:
            if stripped.startswith("###"):
                break
            collected.append(line)
    if not capturing:
        return None
    return "\n".join(collected)


def count_matrix_rows(entry_lines: list[str]) -> int:
    """Data rows in the MUTATION MATRIX table specifically.

    Scoped to the span following the `**Mutation matrix**` field. Counting every
    table in the entry meant an Assembly written as a 3-row table satisfied the
    floor with no matrix present at all — and `seen_header` was sticky across
    tables, so a second table's header row counted as data too.
    """
    span = field_span(entry_lines, "Mutation matrix")
    if span is None:
        return 0
    rows = 0
    seen_header = False
    for line in span.splitlines():
        if not TABLE_ROW_RE.match(line):
            if line.strip():
                seen_header = False  # a non-table line ends the current table
            continue
        if TABLE_SEP_RE.match(line):
            seen_header = True
            continue
        if not seen_header:
            continue
        if line.strip().strip("|").strip():
            rows += 1
    return rows


def check_file(path: Path, rel: str, failures: list[str]) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"lint-guard-contract: cannot read {path}: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc

    lines = text.splitlines()
    fenced = mask_fences(lines)
    sections = extract_sections(lines, fenced)
    if not sections:
        return 0

    total_entries = 0
    for body in sections:
        entries = split_entries(body, fenced, failures, rel)
        if not entries:  # MUT:floor
            failures.append(  # MUT:floor
                f"{rel}: 'Guard Contract' section present but no guard entries "  # MUT:floor
                f"(expected one or more '### Guard <n> — <name>' subsections)"  # MUT:floor
            )  # MUT:floor
            continue  # MUT:floor
        total_entries += len(entries)

        # EVERY entry, never the first.
        for label, entry_lines in entries:
            where = f"{rel}: {label}"

            prop = field_span(entry_lines, "Property")
            if prop is None:
                failures.append(f"{where}: missing '**Property.**' field")
            if prop is not None and is_placeholder(prop):
                failures.append(f"{where}: '**Property.**' is a placeholder")

            assembly = field_span(entry_lines, "Assembly")
            if assembly is None:  # MUT:assembly
                failures.append(  # MUT:assembly
                    f"{where}: missing '**Assembly.**' field — enumerate every code "  # MUT:assembly
                    f"path, array and file the property quantifies over"  # MUT:assembly
                )  # MUT:assembly
            if assembly is not None and is_placeholder(assembly):  # MUT:placeholder
                failures.append(  # MUT:placeholder
                    f"{where}: '**Assembly.**' is a placeholder — members drift, "  # MUT:placeholder
                    f"assembly is structural"  # MUT:placeholder
                )  # MUT:placeholder

            rows = count_matrix_rows(entry_lines)
            if rows < MIN_MUTATION_ROWS:  # MUT:matrix
                failures.append(  # MUT:matrix
                    f"{where}: mutation matrix has {rows} row(s), needs "  # MUT:matrix
                    f">= {MIN_MUTATION_ROWS}"  # MUT:matrix
                )  # MUT:matrix

    return total_entries


def find_plan_files(root: Path) -> list[Path]:
    """Every plan `.md` under plans/, RECURSIVELY, excluding archive/."""
    base = root / "knowledge-base" / "project" / "plans"
    if not base.is_dir():
        return []
    return sorted(
        p for p in base.rglob("*.md")
        if "archive" not in p.relative_to(base).parts and not p.is_symlink()
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="lint-guard-contract",
        description="Validate 'Guard Contract' sections in plan files.",
    )
    parser.add_argument("--repo-root", default=".", help="repository root")
    parser.add_argument("paths", nargs="*", help="specific files to check")
    args = parser.parse_args(argv)

    root = Path(args.repo_root).resolve()
    if not root.is_dir():
        print(f"lint-guard-contract: --repo-root not a directory: {root}", file=sys.stderr)
        return 2

    sweep = not args.paths
    if args.paths:
        targets = []
        for p in args.paths:
            t = Path(p) if Path(p).is_absolute() else root / p
            try:
                t.resolve().relative_to(root)
            except ValueError:
                print(f"lint-guard-contract: path escapes --repo-root: {t}", file=sys.stderr)
                return 2
            if not t.is_file():
                print(f"lint-guard-contract: no such file: {t}", file=sys.stderr)
                return 2
            targets.append(t)
    else:
        targets = find_plan_files(root)

    failures: list[str] = []
    entries_checked = 0
    files_with_contract = 0
    for target in targets:
        rel = target.relative_to(root).as_posix() if target.is_absolute() else str(target)
        n = check_file(target, rel, failures)
        if n:
            files_with_contract += 1
        entries_checked += n

    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)

    print(
        f"lint-guard-contract: scanned {len(targets)} plan file(s), "
        f"{files_with_contract} with a Guard Contract, "
        f"{entries_checked} guard entr{'y' if entries_checked == 1 else 'ies'}"
    )

    # Anti-vacuity floor on this gate's OWN dispatch. A sweep that examined
    # nothing must never report success — that is the fourth instance from the
    # originating evidence, and the first version of this gate reproduced it.
    if sweep and not targets:  # MUT:dispatchfloor
        print(  # MUT:dispatchfloor
            "FAIL: scanned 0 plan files — the walk found nothing, which is a "  # MUT:dispatchfloor
            "harness/config defect, not a clean run",  # MUT:dispatchfloor
            file=sys.stderr,  # MUT:dispatchfloor
        )  # MUT:dispatchfloor
        return 1  # MUT:dispatchfloor

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
