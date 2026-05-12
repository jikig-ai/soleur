#!/usr/bin/env python3
"""Lint AGENTS.{md,core.md,docs.md,rest.md} for budget breaches.

Two commit-blocking assertions:

1. **B_ALWAYS budget.** `B_ALWAYS = len(AGENTS.md bytes) + len(AGENTS.core.md bytes)`
   must stay <= 22000. >= 20000 warns to stderr (exit 0). > 22000 rejects (exit 1).
2. **Per-rule body cap.** Each rule body line (`^- ` under a `## <SECTION>` whose
   stripped heading is in the shared `SECTIONS` set) must be <= 600 UTF-8 bytes.
   Pointer-index lines in AGENTS.md are short by construction and are not
   special-cased — they pass the cap on size, not on shape.

Exit codes:
    0  all assertions pass (may include WARN-tier stderr line)
    1  one or more rejects fired
    2  AGENTS.md or AGENTS.core.md missing on disk

Usage:
    python3 scripts/lint-agents-rule-budget.py \
        AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md

Companion to scripts/lint-rule-ids.py and scripts/lint-agents-enforcement-tags.py.
Wired into lefthook.yml at pre-commit time on AGENTS*.md changes.

Issue: #3684.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Self-bootstrap the script directory onto sys.path so `_agents_md_sections`
# resolves whether this script runs as a CLI tool (cwd may be anywhere) or
# via importlib in the test harness.
_SCRIPTS_DIR = str(Path(__file__).parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _agents_md_sections import SECTIONS

B_ALWAYS_WARN = 20000
B_ALWAYS_REJECT = 22000
PER_RULE_CAP = 600

ALWAYS_LOADED = ("AGENTS.md", "AGENTS.core.md")

SECTION_HEADING_RE = re.compile(r"^## (.+?)\s*$")


def file_bytes(path: Path) -> int:
    """Return UTF-8 byte length of `path`. Matches `wc -c` semantics."""
    return len(path.read_bytes())


def find_always_loaded_paths(paths: list[Path]) -> tuple[Path | None, Path | None]:
    """Pick the AGENTS.md and AGENTS.core.md path out of the positional list,
    matched by basename.

    Lefthook passes the staged file set, which may be a subset of the always-
    loaded pair. The caller pads from disk before invoking; here we just
    identify which entry is which.
    """
    index: Path | None = None
    core: Path | None = None
    for p in paths:
        if p.name == "AGENTS.md":
            index = p
        elif p.name == "AGENTS.core.md":
            core = p
    return index, core


def per_rule_violations(path: Path) -> list[tuple[int, int]]:
    """Return [(line_number, byte_length), ...] for rule body lines exceeding
    PER_RULE_CAP in `path`.

    A "rule body line" is `^- ` under a `## <SECTION>` whose stripped heading
    is in the shared SECTIONS set. Lines outside a SECTIONS heading are
    ignored. Multi-line continuations (e.g. fenced code blocks belonging to a
    bullet) are not counted toward the cap — the cap applies to the single
    `^- ` line as emitted, matching `compound step 8`'s `awk '{print length}'`
    semantic.
    """
    violations: list[tuple[int, int]] = []
    in_section = False
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        m = SECTION_HEADING_RE.match(line)
        if m:
            in_section = m.group(1).strip() in SECTIONS
            continue
        if not in_section or not line.startswith("- "):
            continue
        size = len(line.encode("utf-8"))
        if size > PER_RULE_CAP:
            violations.append((i, size))
    return violations


def lint(paths: list[Path]) -> int:
    index_path, core_path = find_always_loaded_paths(paths)

    if index_path is None or not index_path.exists():
        print("ERROR: AGENTS.md missing — refusing to compute B_ALWAYS", file=sys.stderr)
        return 2
    if core_path is None or not core_path.exists():
        print("ERROR: AGENTS.core.md missing — refusing to compute B_ALWAYS", file=sys.stderr)
        return 2

    b_index = file_bytes(index_path)
    b_core = file_bytes(core_path)
    b_always = b_index + b_core

    reject = False

    remediation = (
        "Retire a rule via scripts/retired-rule-ids.txt or demote a wg-* rule "
        "from AGENTS.core.md to AGENTS.rest.md."
    )

    if b_always > B_ALWAYS_REJECT:
        print(
            f"[REJECT] B_ALWAYS={b_always} > {B_ALWAYS_REJECT} "
            f"(AGENTS.md={b_index} + AGENTS.core.md={b_core}). {remediation}",
            file=sys.stderr,
        )
        reject = True
    elif b_always >= B_ALWAYS_WARN:
        print(
            f"[WARN] B_ALWAYS={b_always} >= {B_ALWAYS_WARN} "
            f"(AGENTS.md={b_index} + AGENTS.core.md={b_core}). "
            f"Approaching the {B_ALWAYS_REJECT}-byte harness ceiling. {remediation}",
            file=sys.stderr,
        )
    else:
        # Success status goes to stdout so log scrapers grepping stderr-only
        # for failures don't see [OK] as noise.
        print(f"[OK] B_ALWAYS={b_always}")

    for p in paths:
        if not p.exists():
            continue
        for line_no, size in per_rule_violations(p):
            print(
                f"{p}:{line_no}: ERROR: rule body exceeds {PER_RULE_CAP} B "
                f"(actual={size}). Move context to a learning file per "
                f"cq-agents-md-why-single-line.",
                file=sys.stderr,
            )
            reject = True

    return 1 if reject else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Lint AGENTS.{md,core.md,docs.md,rest.md} for B_ALWAYS and per-rule budget.",
    )
    parser.add_argument(
        "files",
        nargs="*",
        type=Path,
        default=[Path("AGENTS.md"), Path("AGENTS.core.md"),
                 Path("AGENTS.docs.md"), Path("AGENTS.rest.md")],
        help="AGENTS sidecar paths (default: the four canonical files).",
    )
    args = parser.parse_args(argv)

    return lint(args.files)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
