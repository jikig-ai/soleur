#!/usr/bin/env python3
"""Lint AGENTS.md `[hook-enforced: ...]` and `[skill-enforced: ...]` tags.

For each `[hook-enforced: <hook>]` tag, asserts the first whitespace-split
token resolves to either a path under `.claude/hooks/`, `scripts/`, or
`plugins/soleur/hooks/`, or is the literal `lefthook` whose second token
appears in `lefthook.yml` as a command run target.

For each `[skill-enforced: <skill> <anchor>, <skill2> <anchor2>, ...]` tag,
asserts `plugins/soleur/skills/<skill>/SKILL.md` exists AND the `<anchor>`
token resolves under a tolerant matcher (#3684): literal substring →
`Phase X.Y` ↔ `### X.Y` normalization → strip leading `Phase X.Y` prefix →
hyphen↔space → agent-file fallback at `plugins/soleur/agents/**/<anchor>.md`.
Comma-separated multi-pair tags are split and each pair validated independently.

Companion to `scripts/lint-rule-ids.py`. Wired into `lefthook.yml` at
pre-commit time on AGENTS.md changes.

Usage:
    python3 scripts/lint-agents-enforcement-tags.py [AGENTS.md ...]

Exit codes:
    0  all tags resolve
    1  one or more tags name a missing hook script, skill, or unresolvable anchor
    2  argument or I/O error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HOOK_TAG_RE = re.compile(r"\[hook-enforced: ([^\]]+)\]")
SKILL_TAG_RE = re.compile(r"\[skill-enforced: ([a-z][a-z0-9-]*)([^\]]*)\]")
# Per-pair re-parser for comma-split fragments under a multi-pair tag.
SKILL_PAIR_RE = re.compile(r"^\s*([a-z][a-z0-9-]*)\s+(.+?)\s*$")
# Phase prefix used by both Phase-normalization variants (#3684).
PHASE_RE = re.compile(r"Phase\s+(\d+(?:\.\d+)*)")
PHASE_PREFIX_RE = re.compile(r"^Phase\s+\d+(?:\.\d+)*\s+")

HOOK_SEARCH_DIRS = (
    ".claude/hooks",
    "scripts",
    "plugins/soleur/hooks",
)

# Per-skill SKILL.md content cache (avoids re-reading the same file across the
# 14-tag / 21-pair corpus). Keyed by absolute path. Lifetime: one `main()`
# invocation, shared across all input files for repeat-read avoidance —
# `main()` builds a fresh dict at the top of each run and passes it through
# to every `lint()` call.


def repo_root_for(path: Path) -> Path:
    """Return the closest ancestor that contains `.git` or is a worktree.

    AGENTS.md is always at the repo root in this codebase. We walk up from
    the file path so the lint works whether invoked from a worktree, the
    bare repo root, or a CI checkout.
    """
    for ancestor in [path.resolve(), *path.resolve().parents]:
        if (ancestor / ".git").exists() or (ancestor / "AGENTS.md").exists():
            return ancestor
    return Path.cwd()


def hook_resolves(token: str, root: Path) -> bool:
    """Return True if `token` names a real hook script.

    Two forms accepted:
      * Bare name (e.g. `worktree-write-guard.sh`) → searched under
        HOOK_SEARCH_DIRS.
      * Path-form with `/` (e.g. `.github/workflows/secret-scan.yml`) →
        resolved verbatim from repo root. `..` is rejected to keep tags
        from escaping the repo.
    """
    if ".." in token:
        return False
    if "/" in token:
        return (root / token).is_file()
    for d in HOOK_SEARCH_DIRS:
        if (root / d / token).exists():
            return True
    return False


def resolve_anchor(
    skill: str,
    anchor: str,
    root: Path,
    skill_cache: dict[Path, str],
) -> bool:
    """Return True if `anchor` resolves under the tolerant matcher (TR3, #3684).

    Variants tried in order:
      0. Literal substring of `anchor` in SKILL.md content.
      1. `Phase X.Y` → `### X.Y` normalization, substring of result.
      2. Strip leading `Phase X.Y ` prefix, substring of remainder
         (matches anchors like `work Phase 0 Type-widening cross-consumer grep`
         where SKILL.md has the remainder under a different heading).
      3. Hyphen↔space on full anchor (matches `Route-Learning-to-Definition`
         ↔ `Route Learning to Definition`).
      4. Agent-file fallback: anchor contains a hyphen, no digit, and
         `plugins/soleur/agents/**/<anchor>.md` exists.

    The matcher is intentionally permissive — the 14-pair AGENTS.core.md
    corpus uses five notations across heading prefixes, mid-prose
    references, and agent names. A strict heading-only matcher would
    couple AGENTS rule wording to SKILL.md heading style and force
    cosmetic edits when one or the other is refactored.
    """
    # Defense-in-depth: reject path-traversal-shaped anchors before the
    # rglob fallback. Pathlib treats `/` and `..` as literal pattern tokens
    # (no upward traversal) but explicit rejection makes the surface obvious
    # and survives a future pathlib semantic change.
    if "/" in anchor or ".." in anchor:
        return False

    skill_md = root / "plugins" / "soleur" / "skills" / skill / "SKILL.md"
    if not skill_md.exists():
        return False
    content = skill_cache.get(skill_md)
    if content is None:
        content = skill_md.read_text(encoding="utf-8")
        skill_cache[skill_md] = content

    if anchor in content:
        return True

    phase_normalized = PHASE_RE.sub(r"### \1", anchor)
    if phase_normalized != anchor and phase_normalized in content:
        return True

    # Variant 2 (strip leading `Phase X.Y `): tighten to require the stripped
    # remainder to appear adjacent to a heading marker (`###`, `**`, `## `) or
    # at the start of a bullet body (`- `). Bare substring match was overly
    # permissive — a remainder like "exit" could resolve to any "exit" in
    # prose. Real anchors in the 14-tag corpus always land on a bold label
    # (`**TDD Gate**`), heading (`### 1.4`), or self-referencing tag literal
    # (`work Phase 2 exit` appears in `[skill-enforced: work Phase 2 exit]`
    # tags inside work/SKILL.md).
    stripped = PHASE_PREFIX_RE.sub("", anchor)
    if stripped != anchor:
        for prefix in ("**", "### ", "## ", "#### ", "- ", "[skill-enforced: "):
            if f"{prefix}{stripped}" in content:
                return True
            spaced = stripped.replace("-", " ")
            if spaced != stripped and f"{prefix}{spaced}" in content:
                return True

    if "-" in anchor:
        spaced = anchor.replace("-", " ")
        if spaced in content:
            return True

    if "-" in anchor and not any(c.isdigit() for c in anchor):
        agents_root = root / "plugins" / "soleur" / "agents"
        if agents_root.exists():
            for _ in agents_root.rglob(f"{anchor}.md"):
                return True

    return False


def iter_skill_pairs(skill: str, rest: str):
    """Yield (skill, anchor, malformed?) tuples from a `[skill-enforced: ...]`
    tag body.

    The regex captures the first `(skill, rest)` split. `rest` may carry
    additional comma-separated `<skill> <anchor>` pairs (TR4). The first
    fragment of `rest` is the anchor for the regex-captured `skill`;
    subsequent fragments re-parse via SKILL_PAIR_RE.

    Yields `(skill, anchor, None)` on success and `(None, fragment, "malformed")`
    on a fragment that doesn't parse — the caller surfaces these as errors
    instead of silently dropping them, mirroring `cq-silent-fallback-must-mirror-to-sentry`.
    """
    fragments = [f.strip() for f in rest.split(",") if f.strip()]
    if not fragments:
        return
    # First fragment: the anchor belongs to the regex-captured `skill`.
    yield skill, fragments[0], None
    for frag in fragments[1:]:
        m = SKILL_PAIR_RE.match(frag)
        if m:
            yield m.group(1), m.group(2).strip(), None
        else:
            yield None, frag, "malformed"


def lefthook_command_known(rest: str, lefthook_text: str) -> bool:
    """Return True if the trailing tokens of a `lefthook X` tag appear in
    lefthook.yml as a command run target.

    `rest` is everything after the `lefthook` literal — typically a path
    like `lint-rule-ids.py` or a script reference. We do a substring match
    against the file because lefthook command bodies vary in shape (single
    `run:` line vs multi-line bash, `python3 scripts/...` vs `bash ...`).
    """
    for token in rest.split():
        if token in lefthook_text:
            return True
    return False


def lint(
    agents_md: Path,
    root: Path,
    skill_cache: dict[Path, str],
) -> tuple[list[str], int]:
    """Return (error messages, anchor-pair count). Empty list = pass."""
    errors: list[str] = []
    anchor_pairs_checked = 0
    text = agents_md.read_text(encoding="utf-8")

    lefthook_path = root / "lefthook.yml"
    lefthook_text = lefthook_path.read_text(encoding="utf-8") if lefthook_path.exists() else ""

    for line_num, line in enumerate(text.splitlines(), start=1):
        for match in HOOK_TAG_RE.finditer(line):
            content = match.group(1).strip()
            tokens = content.split()
            if not tokens:
                errors.append(
                    f"{agents_md}:{line_num}: empty [hook-enforced: ...] tag"
                )
                continue
            first = tokens[0]
            if first == "lefthook":
                rest = " ".join(tokens[1:])
                if not lefthook_command_known(rest, lefthook_text):
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [hook-enforced: lefthook {rest}] "
                        f"— no matching command in lefthook.yml. "
                        f"Fix: register the command under pre-commit: in lefthook.yml, "
                        f"update the tag, or retire the rule."
                    )
            else:
                if not hook_resolves(first, root):
                    searched = ", ".join(HOOK_SEARCH_DIRS)
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [hook-enforced: {first}] "
                        f"— hook script not found in any of: {searched}. "
                        f"Fix: add the script, update the tag, or retire the rule "
                        f"(see cq-rule-ids-are-immutable)."
                    )

        for match in SKILL_TAG_RE.finditer(line):
            skill = match.group(1).strip()
            rest = match.group(2)
            skill_md = root / "plugins" / "soleur" / "skills" / skill / "SKILL.md"
            if not skill_md.exists():
                errors.append(
                    f"{agents_md}:{line_num}: ERROR: [skill-enforced: {skill} ...] "
                    f"— SKILL.md not found at {skill_md.relative_to(root)}. "
                    f"Fix: create the skill, update the tag, or retire the rule."
                )
                continue
            # Anchor-parity check across every comma-split pair (#3684, TR3+TR4).
            for pair_skill, anchor, parse_state in iter_skill_pairs(skill, rest):
                if parse_state == "malformed":
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [skill-enforced: ... "
                        f"{anchor}] — fragment does not match `<skill> <anchor>` "
                        f"shape. Fix: re-author the comma-separated pair so it "
                        f"starts with a lowercase skill slug followed by an anchor."
                    )
                    continue
                anchor_pairs_checked += 1
                pair_skill_md = (
                    root / "plugins" / "soleur" / "skills" / pair_skill / "SKILL.md"
                )
                if not pair_skill_md.exists():
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [skill-enforced: ... "
                        f"{pair_skill} {anchor}] — SKILL.md not found at "
                        f"{pair_skill_md.relative_to(root)}. "
                        f"Fix: create the skill, update the tag, or retire the rule."
                    )
                    continue
                if not resolve_anchor(pair_skill, anchor, root, skill_cache):
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [skill-enforced: "
                        f"{pair_skill} {anchor}] — anchor not resolvable in "
                        f"plugins/soleur/skills/{pair_skill}/SKILL.md under any "
                        f"tolerant variant. "
                        f"Fix: align the tag wording to the SKILL.md heading, "
                        f"or update the heading."
                    )

    return errors, anchor_pairs_checked


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Lint AGENTS.md enforcement tags",
    )
    parser.add_argument(
        "files",
        nargs="*",
        default=["AGENTS.md"],
        help="AGENTS.md files to lint (default: AGENTS.md in CWD)",
    )
    args = parser.parse_args(argv)

    total_errors = 0
    total_hook_tags = 0
    total_skill_tags = 0
    total_anchor_pairs = 0
    skill_cache: dict[Path, str] = {}
    for f in args.files:
        path = Path(f)
        if not path.is_file():
            print(f"ERROR: {f} not found", file=sys.stderr)
            return 2
        root = repo_root_for(path)
        text = path.read_text(encoding="utf-8")
        total_hook_tags += len(HOOK_TAG_RE.findall(text))
        total_skill_tags += len(SKILL_TAG_RE.findall(text))
        errs, pairs = lint(path, root, skill_cache)
        for e in errs:
            print(e, file=sys.stderr)
        total_errors += len(errs)
        total_anchor_pairs += pairs

    if total_errors:
        print(
            f"\nFAIL: {total_errors} unresolved enforcement tag(s)",
            file=sys.stderr,
        )
        return 1
    print(
        f"OK: all {total_hook_tags} hook + {total_skill_tags} skill + "
        f"{total_anchor_pairs} anchor parity check(s) resolve"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
