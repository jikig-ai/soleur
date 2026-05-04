#!/usr/bin/env python3
"""Lint AGENTS.md `[hook-enforced: ...]` and `[skill-enforced: ...]` tags.

For each `[hook-enforced: <hook>]` tag, asserts the first whitespace-split
token resolves to either a path under `.claude/hooks/`, `scripts/`, or
`plugins/soleur/hooks/`, or is the literal `lefthook` whose second token
appears in `lefthook.yml` as a command run target.

For each `[skill-enforced: <skill> <rest>]` tag, asserts
`plugins/soleur/skills/<skill>/SKILL.md` exists. Phase notation (`Phase X`,
`step X`, `Check X`, `Route-Learning-to-Definition`, agent name) is
deliberately NOT verified — the 13 existing tags use 5 distinct notations
and a strict match would couple AGENTS.md formatting to skill heading style.

Companion to `scripts/lint-rule-ids.py`. Wired into `lefthook.yml` at
pre-commit time on AGENTS.md changes.

Usage:
    python3 scripts/lint-agents-enforcement-tags.py [AGENTS.md ...]

Exit codes:
    0  all tags resolve
    1  one or more tags name a missing hook script or skill directory
    2  argument or I/O error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HOOK_TAG_RE = re.compile(r"\[hook-enforced: ([^\]]+)\]")
SKILL_TAG_RE = re.compile(r"\[skill-enforced: ([a-z][a-z0-9-]*)([^\]]*)\]")

HOOK_SEARCH_DIRS = (
    ".claude/hooks",
    "scripts",
    "plugins/soleur/hooks",
)


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
    """Return True if `token` names a real hook script."""
    if "/" in token or ".." in token:
        return False
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


def lint(agents_md: Path, root: Path) -> list[str]:
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
            skill = match.group(1).strip()
            skill_md = root / "plugins" / "soleur" / "skills" / skill / "SKILL.md"
            if not skill_md.exists():
                errors.append(
                    f"{agents_md}:{line_num}: ERROR: [skill-enforced: {skill} ...] "
                    f"— SKILL.md not found at {skill_md.relative_to(root)}. "
                    f"Fix: create the skill, update the tag, or retire the rule."
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
    args = parser.parse_args(argv)

    total_errors = 0
    total_tags = 0
    for f in args.files:
        path = Path(f)
        if not path.is_file():
            print(f"ERROR: {f} not found", file=sys.stderr)
            return 2
        root = repo_root_for(path)
        text = path.read_text(encoding="utf-8")
        total_tags += len(HOOK_TAG_RE.findall(text)) + len(SKILL_TAG_RE.findall(text))
        errs = lint(path, root)
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
