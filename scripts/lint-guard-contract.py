#!/usr/bin/env python3
"""Guard Contract completeness gate (plan/SKILL.md §2.12, deepen-plan §4.11).

The class this exists to catch: **a guard whose WINDOW, CHOKEPOINT or IDENTIFIER
SET is narrower than the property it names.** The preflight Check 10 execution-
boundary work (merged 2026-08-10) absorbed five adversarial review rounds and
~20 findings that all reduced to that one class — a mount-set closure assertion
scoped to one array while three other code paths also injected mounts; a parity
floor counting iterations rather than distinct shapes; a suppression grep
anchored on rebindable identifiers; and an anti-vacuity gate with no floor on
its own dispatch.

Those were not five discoveries. They were one enumeration nobody performed.

The plan-time countermeasure is the Guard Contract: per guard, (1) the property
in one sentence, (2) the ASSEMBLY the property quantifies over — every code
path, array and file that contributes — and (3) a mutation matrix of >= 3 edits
that must go RED, derivable from the design. Members drift; assembly is
structural. Field (2) is the one whose absence cost the five rounds.

This lint resolves that contract mechanically. `review/SKILL.md` states the
disposition for a recurring documented class: a mechanical gate, not another
learning.

Scope
-----
With no path arguments, sweeps `<repo-root>/knowledge-base/project/plans/*.md`
NON-RECURSIVELY, so `plans/archive/` is excluded by construction rather than by
a filter that could drift. With path arguments, checks exactly those files.

A file with no `## Guard Contract` heading is SKIPPED — the contract is required
only when the deliverable includes a guard, gate, lint, drift-check or
anti-vacuity control, and that judgement is the plan author's.

Checks
------
  a. Zero-entry floor: a `## Guard Contract` heading with no `### Guard` entry
     FAILs. A heading alone must never read as compliance.
  b. Property present and non-placeholder, for EVERY entry.
  c. Assembly present and non-placeholder, for EVERY entry.
  d. Mutation matrix carries >= 3 data rows, for EVERY entry.

Every per-entry check quantifies over ALL entries, never the first — the
first-member degradation is itself an instance of the class this gate exists to
catch.

Exit codes: 0 PASS (or a graceful skip), 1 one or more FAIL, 2 argument/IO error.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SECTION_HEADING = "## Guard Contract"
ENTRY_RE = re.compile(r"^###\s+Guard\b(.*)$")
NEXT_H2_RE = re.compile(r"^##\s+\S")
# The trailing `[.:]?` is load-bearing: entries write `**Assembly.**` but
# `**Mutation matrix:**`. Without tolerating the colon, the matrix heading is not
# recognised as a field boundary and the PRECEDING field's value swallows it —
# which makes a `**Assembly.** TBD` read as non-placeholder because the captured
# value is "TBD\n\n**Mutation matrix:**".
FIELD_RE = re.compile(r"^\*\*(?P<name>[A-Za-z][A-Za-z ]*)[.:]?\*\*(?P<rest>.*)$")
TABLE_ROW_RE = re.compile(r"^\s*\|")
TABLE_SEP_RE = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
MIN_MUTATION_ROWS = 3

PLACEHOLDERS = {"tbd", "todo", "n/a", "na", "placeholder", "<placeholder>", "-", "..."}


def is_placeholder(text: str) -> bool:
    """True when the field value carries no information."""
    stripped = text.strip().strip("*_`").strip()
    if not stripped:
        return True
    return stripped.rstrip(".").lower() in PLACEHOLDERS


def extract_section(lines: list[str]) -> list[str] | None:
    """Return the `## Guard Contract` body, or None when the heading is absent."""
    start = None
    for i, line in enumerate(lines):
        if line.strip() == SECTION_HEADING:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if NEXT_H2_RE.match(lines[j]):
            end = j
            break
    return lines[start:end]


def split_entries(body: list[str]) -> list[tuple[str, list[str]]]:
    """Split a Guard Contract body into (label, lines) per `### Guard ...` entry."""
    entries: list[tuple[str, list[str]]] = []
    current_label: str | None = None
    current: list[str] = []
    for line in body:
        m = ENTRY_RE.match(line)
        if m:
            if current_label is not None:
                entries.append((current_label, current))
            current_label = line.strip().lstrip("#").strip()
            current = []
        elif current_label is not None:
            current.append(line)
    if current_label is not None:
        entries.append((current_label, current))
    return entries


def field_value(entry_lines: list[str], name: str) -> str | None:
    """Value of a `**<name>.**` field: same-line remainder plus following lines
    up to the next bolded field, table, or heading. None when absent."""
    target = name.lower()
    collected: list[str] = []
    capturing = False
    for line in entry_lines:
        m = FIELD_RE.match(line.strip())
        if m:
            found = m.group("name").strip().lower()
            if capturing:
                break
            if found == target:
                capturing = True
                collected.append(m.group("rest"))
                continue
        if capturing:
            if line.strip().startswith("###") or TABLE_ROW_RE.match(line):
                break
            collected.append(line)
    if not capturing:
        return None
    return "\n".join(collected)


def count_matrix_rows(entry_lines: list[str]) -> int:
    """Data rows in the entry's markdown table (header and separator excluded)."""
    rows = 0
    seen_header = False
    for line in entry_lines:
        if not TABLE_ROW_RE.match(line):
            continue
        if TABLE_SEP_RE.match(line):
            seen_header = True
            continue
        if not seen_header:
            continue
        if line.strip().strip("|").strip():
            rows += 1
    return rows


def check_file(path: Path, failures: list[str]) -> int:
    """Check one file. Returns the number of guard entries examined."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise SystemExit(f"lint-guard-contract: cannot read {path}: {exc}") from exc

    body = extract_section(lines)
    if body is None:
        return 0

    entries = split_entries(body)
    if not entries:  # MUT:floor
        failures.append(  # MUT:floor
            f"{path}: '## Guard Contract' present but no guard entries "  # MUT:floor
            f"(expected one or more '### Guard <n> — <name>' subsections)"  # MUT:floor
        )  # MUT:floor
        return 0  # MUT:floor

    # Quantify over EVERY entry. A checker that stops at the first is the
    # first-member degradation this whole gate exists to catch.
    for label, entry_lines in entries:
        where = f"{path}: {label}"

        prop = field_value(entry_lines, "Property")
        if prop is None:
            failures.append(f"{where}: missing '**Property.**' field")
        elif is_placeholder(prop):
            failures.append(f"{where}: '**Property.**' is a placeholder")

        # Two INDEPENDENT `if`s, never `if/elif`: each is a separately-marked
        # mutation seam, and an `elif` chain cannot be deleted one arm at a time
        # without leaving a dangling clause.
        assembly = field_value(entry_lines, "Assembly")
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

    return len(entries)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="lint-guard-contract",
        description="Validate '## Guard Contract' sections in plan files.",
    )
    parser.add_argument("--repo-root", default=".", help="repository root")
    parser.add_argument("paths", nargs="*", help="specific files to check")
    args = parser.parse_args(argv)

    root = Path(args.repo_root).resolve()
    if not root.is_dir():
        print(f"lint-guard-contract: --repo-root not a directory: {root}", file=sys.stderr)
        return 2

    if args.paths:
        targets = [(root / p) if not Path(p).is_absolute() else Path(p) for p in args.paths]
        for t in targets:
            if not t.is_file():
                print(f"lint-guard-contract: no such file: {t}", file=sys.stderr)
                return 2
    else:
        # Non-recursive by construction: plans/archive/ is out of scope because
        # the glob cannot descend, not because a filter excludes it.
        targets = sorted((root / "knowledge-base" / "project" / "plans").glob("*.md"))

    failures: list[str] = []
    entries_checked = 0
    files_with_contract = 0
    for target in targets:
        n = check_file(target, failures)
        if n:
            files_with_contract += 1
        entries_checked += n

    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)

    print(
        f"lint-guard-contract: checked {len(targets)} plan file(s), "
        f"{files_with_contract} with a Guard Contract, "
        f"{entries_checked} guard entr{'y' if entries_checked == 1 else 'ies'}"
    )

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
