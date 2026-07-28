#!/usr/bin/env python3
"""Lint AGENTS.{md,rules.md} for budget breaches.

Two commit-blocking assertions:

1. **B_ALWAYS budget.** `B_ALWAYS = len(AGENTS.md bytes) + len(AGENTS.rules.md bytes)`
   must stay <= 46000. >= 44000 warns to stderr (exit 0). > 46000 rejects (exit 1).
2. **Per-rule body cap.** Each rule body line (`^- ` under a `## <SECTION>` whose
   stripped heading is in the shared `SECTIONS` set) must be <= 600 UTF-8 bytes.
   Pointer-index lines in AGENTS.md are short by construction and are not
   special-cased — they pass the cap on size, not on shape.

Exit codes:
    0  all assertions pass (may include WARN-tier stderr line)
    1  one or more rejects fired
    2  AGENTS.md or AGENTS.rules.md missing on disk

Usage:
    python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md

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

# Shared frontmatter-strip contract (issue #5999, ADR-094). The rule corpus
# carries OPTIONAL leading YAML frontmatter (last_reviewed / review_cadence) that
# the session loader STRIPS before injecting into context. B_ALWAYS must measure
# the LOADED bytes (what the agent actually sees), not the on-disk bytes — so we
# strip the corpus frontmatter here with the byte-identical twin of the loader's
# strip. AGENTS.md is loaded raw via the harness `@`-import (unstrippable) and is
# NOT stripped. See scripts/lib/frontmatter-strip/SPEC.md.
_FM_STRIP_DIR = str(Path(__file__).parent / "lib" / "frontmatter-strip")
if _FM_STRIP_DIR not in sys.path:
    sys.path.insert(0, _FM_STRIP_DIR)
from strip import strip_frontmatter  # noqa: E402

# Rule-line shape. MIRRORED in .claude/hooks/session-rules-loader.sh's over-strip
# guard (`grep -cE '^- .*\[id: '`) — both count the same lines so the loader's
# RAW-injection guard and this lint's fail-hard agree on "the strip dropped a
# rule". If this shape ever changes (e.g. `*` bullets, tighter id charset),
# change BOTH sites in lockstep.
_RULE_LINE_RE = re.compile(r"^- .*\[id: ")


def _rule_line_count(text: str) -> int:
    """Count `- …[id: …]` rule-body lines. A correct frontmatter strip removes
    only `key: value` YAML and leaves this count invariant."""
    return sum(1 for ln in text.splitlines() if _RULE_LINE_RE.match(ln))

# Re-baselined 23000 -> 46000 by ADR-150, when the three change-class sidecars
# collapsed into one unconditionally-loaded corpus.
#
# READ THIS BEFORE CONCLUDING THE BUDGET GOT LOOSER: it did not. The number rose
# because the MEASUREMENT got honest. The old 23000 counted AGENTS.md + the one
# sidecar that loaded every session, and ignored the other two — but ~70% of
# sessions were multi-class and already injected all three (43,680 B measured),
# so the old ceiling described 53% of reality and gated only the minority path.
# B_ALWAYS now measures what every session actually loads (~42,547 B), which is
# ~1,133 B LESS than what that 70% majority was already carrying (43,680 B).
# Re-derive rather than trusting this comment: it is a restatement, and this file
# is the authority — `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`.
#
# The old comment derived 23000 as "floor + small headroom", where the floor was
# the hr-* and compliance-tier bodies pinned to core. Those pins are gone (the
# corpus is unconditional, so residency is not a choice) and the margin here is
# NOT derived from anything: it is a ratchet against unreviewed growth, not an
# external limit, and the size of the margin is a judgment call. There is no
# harness ceiling behind these numbers — the phrase "harness ceiling" used to
# appear in this file's own WARN string and nowhere else in the repo.
B_ALWAYS_WARN = 44000
B_ALWAYS_REJECT = 46000
PER_RULE_CAP = 600

# The two entries are NOT interchangeable and must stay two files. AGENTS.md is
# a slug-only pointer index re-rendered EVERY TURN; AGENTS.rules.md holds the
# bodies and is injected ONCE per session by the SessionStart hook. Merging them
# (ADR-150 option C-ii) would put ~37 kB of bodies on every turn instead of ~5 kB
# of pointers — the one "simplification" that makes things dramatically worse.
ALWAYS_LOADED = ("AGENTS.md", "AGENTS.rules.md")

SECTION_HEADING_RE = re.compile(r"^## (.+?)\s*$")


def file_bytes(path: Path) -> int:
    """Return UTF-8 byte length of `path`. Matches `wc -c` semantics."""
    return len(path.read_bytes())


def find_always_loaded_paths(paths: list[Path]) -> tuple[Path | None, Path | None]:
    """Pick the AGENTS.md and AGENTS.rules.md path out of the positional list,
    matched by basename.

    Lefthook passes the staged file set, which may be a subset of the always-
    loaded pair. The caller pads from disk before invoking; here we just
    identify which entry is which.
    """
    index: Path | None = None
    corpus: Path | None = None
    for p in paths:
        if p.name == "AGENTS.md":
            index = p
        elif p.name == "AGENTS.rules.md":
            corpus = p
    return index, corpus


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
    index_path, corpus_path = find_always_loaded_paths(paths)

    if index_path is None or not index_path.exists():
        print("ERROR: AGENTS.md missing — refusing to compute B_ALWAYS", file=sys.stderr)
        return 2
    if corpus_path is None or not corpus_path.exists():
        print(
            "ERROR: AGENTS.rules.md missing — refusing to compute B_ALWAYS",
            file=sys.stderr,
        )
        return 2

    b_index = file_bytes(index_path)

    # Measure LOADED core bytes: strip the leading YAML frontmatter (matching the
    # session loader) before counting. Over-strip guard (fail-hard, not shrink):
    # if the strip removed any `- …[id: …]` rule line, the frontmatter was
    # malformed (e.g. unterminated `---`) and consumed body — ERROR rather than
    # report a falsely-low B_ALWAYS that would mask a governance-blackout regression.
    corpus_text = corpus_path.read_text(encoding="utf-8")
    stripped_corpus = strip_frontmatter(corpus_text)
    raw_rules = _rule_line_count(corpus_text)
    stripped_rules = _rule_line_count(stripped_corpus)
    if stripped_rules != raw_rules:
        print(
            f"ERROR: AGENTS.rules.md frontmatter-strip removed "
            f"{raw_rules - stripped_rules} rule line(s) — malformed frontmatter "
            f"(unterminated '---'?). Refusing to report a falsely-low B_ALWAYS. "
            f"Fix the frontmatter so only 'key: value' lines sit between the "
            f"leading '---' delimiters.",
            file=sys.stderr,
        )
        return 1
    b_corpus = len(stripped_corpus.encode("utf-8"))
    b_always = b_index + b_corpus

    reject = False

    # The "demote a wg-* rule to a conditional sidecar" rung is gone with the
    # sidecars (ADR-150) — there is nowhere to demote to. Per #6794 the retirement
    # rung is not currently actionable either (the rules_unused_over_8w metric is
    # a per-worktree fragmentation under-count), so trimming prose is the honest
    # first move.
    remediation = (
        "Trim rule prose, or retire a rule via scripts/retired-rule-ids.txt."
    )

    if b_always > B_ALWAYS_REJECT:
        print(
            f"[REJECT] B_ALWAYS={b_always} > {B_ALWAYS_REJECT} "
            f"(AGENTS.md={b_index} + AGENTS.rules.md={b_corpus}). {remediation}",
            file=sys.stderr,
        )
        reject = True
    elif b_always >= B_ALWAYS_WARN:
        print(
            f"[WARN] B_ALWAYS={b_always} >= {B_ALWAYS_WARN} "
            f"(AGENTS.md={b_index} + AGENTS.rules.md={b_corpus}). "
            f"Approaching the {B_ALWAYS_REJECT}-byte ratchet (a self-imposed "
            f"guard against unreviewed growth, not an external limit). "
            f"{remediation}",
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
        default=[Path("AGENTS.md"), Path("AGENTS.rules.md")],
        help="AGENTS corpus paths (default: the index plus the rule corpus).",
    )
    args = parser.parse_args(argv)

    return lint(args.files)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
