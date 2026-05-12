#!/usr/bin/env python3
"""Lint AGENTS.md `[hook-enforced: ...]` and `[skill-enforced: ...]` tags.

For each `[hook-enforced: <hook>]` tag, asserts the first whitespace-split
token resolves to either a path under `.claude/hooks/`, `scripts/`, or
`plugins/soleur/hooks/`, or is the literal `lefthook` whose second token
appears in `lefthook.yml` as a command run target.

For each `[skill-enforced: <skill> <rest>]` tag, asserts
`plugins/soleur/skills/<skill>/SKILL.md` exists. Phase notation (`Phase X`,
`step X`, `Check X`, `Route-Learning-to-Definition`, agent name) is
deliberately NOT verified by default — the existing tags use multiple
notations and a strict match would couple AGENTS.md formatting to skill
heading style. Pass `--check-anchors` to opt into per-segment anchor
substring verification (issue #3684).

Anchor parser contract for `[skill-enforced: <s1> <a1>, <s2> <a2>, ...]`:
the comma-separated list lets one tag enforce N (skill, anchor) pairs. For
the FIRST segment, the skill name is the regex's group(1) (the leading
identifier). For each subsequent segment, the first whitespace-delimited
token is the skill name, the rest forms the anchor substring.

Anchor segments MUST NOT contain commas. If a future anchor needs a comma,
switch the segment delimiter to `;` (and update both the parser and the
AGENTS tag-style guidance in cq-agents-md-tier-gate's body).

Allowlist: `scripts/agents-anchor-ignore.txt` (one entry per line:
`<skill> <anchor>` OR `# comment` OR blank). Allowlisted segments skip the
grep check. Every `<skill>` in the allowlist must resolve to a real
`plugins/soleur/skills/<skill>/SKILL.md` — otherwise the allowlist itself
is silent rot.

Companion to `scripts/lint-rule-ids.py`. Wired into `lefthook.yml` at
pre-commit time on AGENTS.md changes.

Usage:
    python3 scripts/lint-agents-enforcement-tags.py [AGENTS.md ...]
    python3 scripts/lint-agents-enforcement-tags.py --check-anchors AGENTS.md ...

Exit codes:
    0  all tags resolve
    1  one or more tags name a missing hook script, skill directory, or
       (with --check-anchors) a missing anchor substring
    2  argument or I/O error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HOOK_TAG_RE = re.compile(r"\[hook-enforced: ([^\]]+)\]")
SKILL_TAG_RE = re.compile(r"\[skill-enforced: ([a-z][a-z0-9-]*)([^\]]*)\]")
SKILL_NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")

HOOK_SEARCH_DIRS = (
    ".claude/hooks",
    "scripts",
    "plugins/soleur/hooks",
)

ALLOWLIST_REL_PATH = Path("scripts/agents-anchor-ignore.txt")


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


def parse_skill_segments(first_skill: str, rest: str) -> list[tuple[str, str]]:
    """Parse a `[skill-enforced: <s1> <a1>, <s2> <a2>, ...]` tag body into
    per-segment `(skill, anchor)` pairs.

    `first_skill` is the regex's group(1) (e.g. `plan`).
    `rest` is the regex's group(2) (e.g. ` Phase 2.6, deepen-plan Phase 4.6`).

    Returns an empty list for tags with no anchor content (just `[skill-enforced: foo]`).
    """
    segments: list[tuple[str, str]] = []
    raw = rest.strip()
    if not raw:
        return segments

    parts = [p.strip() for p in raw.split(",")]
    # First segment uses first_skill as the skill; the segment text is the anchor.
    if parts:
        first_anchor = parts[0].strip()
        if first_anchor:
            segments.append((first_skill, first_anchor))
        elif len(parts) > 1:
            # Malformed: the first segment has no anchor but subsequent
            # segments exist (e.g. `[skill-enforced: plan , compound step 8]`).
            # Emit an empty-anchor placeholder for first_skill so the caller
            # can report it instead of silently dropping it.
            segments.append((first_skill, ""))
        for part in parts[1:]:
            tokens = part.split(None, 1)
            if not tokens:
                continue
            skill = tokens[0]
            anchor = tokens[1].strip() if len(tokens) > 1 else ""
            if skill and SKILL_NAME_RE.match(skill):
                segments.append((skill, anchor))
            else:
                # Bad segment shape — record as a (skill="", anchor=part) so the
                # caller can report it with file context.
                segments.append(("", part))
    return segments


def load_allowlist(root: Path) -> tuple[set[tuple[str, str]], list[str]]:
    """Return (allowlist_set, validation_errors).

    allowlist_set: set of (skill, anchor) pairs to skip in --check-anchors.
    validation_errors: list of error messages for malformed entries or
                       entries naming a non-existent skill.
    """
    allowlist: set[tuple[str, str]] = set()
    errors: list[str] = []
    path = root / ALLOWLIST_REL_PATH
    if not path.is_file():
        return allowlist, errors

    for line_num, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tokens = line.split(None, 1)
        if len(tokens) < 2:
            errors.append(
                f"{path}:{line_num}: malformed allowlist entry "
                f"(expected `<skill> <anchor>`): {line!r}"
            )
            continue
        skill, anchor = tokens[0], tokens[1].strip()
        if re.search(r"\s#\s", anchor):
            errors.append(
                f"{path}:{line_num}: inline `# ...` comments are not "
                f"supported in allowlist anchors (the parser would treat "
                f"the `#` and trailing prose as part of the anchor body, "
                f"silently widening the allowlist). Move the rationale to "
                f"a preceding standalone `# ...` line. Offending entry: "
                f"{line!r}"
            )
            continue
        if not SKILL_NAME_RE.match(skill):
            errors.append(
                f"{path}:{line_num}: invalid skill name {skill!r} "
                f"(expected lowercase-with-hyphens)"
            )
            continue
        skill_md = root / "plugins" / "soleur" / "skills" / skill / "SKILL.md"
        if not skill_md.exists():
            errors.append(
                f"{path}:{line_num}: allowlist names skill {skill!r} but "
                f"{skill_md.relative_to(root)} does not exist"
            )
            continue
        allowlist.add((skill, anchor))
    return allowlist, errors


def anchor_resolves(skill: str, anchor: str, root: Path) -> bool:
    """Return True if `anchor` appears as a literal substring in the named
    skill's SKILL.md. Mirrors `grep -F` semantics.
    """
    skill_md = root / "plugins" / "soleur" / "skills" / skill / "SKILL.md"
    if not skill_md.is_file():
        return False
    try:
        body = skill_md.read_text(encoding="utf-8")
    except OSError:
        return False
    return anchor in body


def lint(agents_md: Path, root: Path, *, check_anchors: bool,
         allowlist: set[tuple[str, str]]) -> list[str]:
    """Return a list of error messages. Empty list = pass."""
    errors: list[str] = []
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
                        f"{agents_md}:{line_num}: [hook-enforced: lefthook {rest}] "
                        f"— no matching command in lefthook.yml"
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
            first_skill = match.group(1).strip()
            rest = match.group(2)
            skill_md = root / "plugins" / "soleur" / "skills" / first_skill / "SKILL.md"
            if not skill_md.exists():
                errors.append(
                    f"{agents_md}:{line_num}: ERROR: [skill-enforced: {first_skill} ...] "
                    f"— SKILL.md not found at {skill_md.relative_to(root)}. "
                    f"Fix: create the skill, update the tag, or retire the rule."
                )
                continue

            if not check_anchors:
                continue

            for skill, anchor in parse_skill_segments(first_skill, rest):
                if not skill:
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: malformed segment "
                        f"in [skill-enforced: ...]: {anchor!r} "
                        f"(expected `<skill> <anchor>` after comma)"
                    )
                    continue
                seg_skill_md = root / "plugins" / "soleur" / "skills" / skill / "SKILL.md"
                if not seg_skill_md.exists():
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [skill-enforced: ... {skill} ...] "
                        f"— SKILL.md not found at {seg_skill_md.relative_to(root)}. "
                        f"Fix: create the skill, update the tag, or retire the rule."
                    )
                    continue
                if not anchor:
                    # Tag like `[skill-enforced: foo]` with no anchor body —
                    # nothing to verify in --check-anchors mode.
                    continue
                if (skill, anchor) in allowlist:
                    continue
                if not anchor_resolves(skill, anchor, root):
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [skill-enforced: ... {skill} {anchor}] "
                        f"— anchor substring not found in plugins/soleur/skills/{skill}/SKILL.md. "
                        f"Fix options: (a) update the tag to a verbatim substring of the "
                        f"skill body (preferred); (b) rename the anchor in the skill; "
                        f"(c) append a new line to scripts/agents-anchor-ignore.txt in "
                        f"the format `<skill> <anchor>` (split on FIRST whitespace; "
                        f"inline `# ...` comments NOT supported — put rationale on a "
                        f"preceding standalone `# ...` line). For this entry, the line "
                        f"would be: `{skill} {anchor}`."
                    )

    return errors


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
    parser.add_argument(
        "--check-anchors",
        action="store_true",
        help="Verify each [skill-enforced: <skill> <anchor>] anchor is a "
             "verbatim substring of the named skill's SKILL.md "
             "(consults scripts/agents-anchor-ignore.txt for legitimate trims)",
    )
    args = parser.parse_args(argv)

    total_errors = 0
    total_tags = 0
    allowlist_cache: dict[Path, set[tuple[str, str]]] = {}
    for f in args.files:
        path = Path(f)
        if not path.is_file():
            print(f"ERROR: {f} not found", file=sys.stderr)
            return 2
        root = repo_root_for(path)
        # Load + validate the allowlist once per repo root, then cache the
        # parsed (skill, anchor) set for reuse across subsequent AGENTS files
        # (the on-disk file does not change mid-invocation, so re-reading it
        # per AGENTS file is wasted I/O).
        if root not in allowlist_cache:
            allowlist, allowlist_errs = load_allowlist(root)
            for e in allowlist_errs:
                print(e, file=sys.stderr)
                total_errors += 1
            allowlist_cache[root] = allowlist
        allowlist = allowlist_cache[root]
        text = path.read_text(encoding="utf-8")
        total_tags += len(HOOK_TAG_RE.findall(text)) + len(SKILL_TAG_RE.findall(text))
        errs = lint(path, root, check_anchors=args.check_anchors, allowlist=allowlist)
        for e in errs:
            print(e, file=sys.stderr)
        total_errors += len(errs)

    if total_errors:
        print(
            f"\nFAIL: {total_errors} unresolved enforcement tag(s)",
            file=sys.stderr,
        )
        return 1
    print(f"OK: all {total_tags} enforcement tag(s) resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
