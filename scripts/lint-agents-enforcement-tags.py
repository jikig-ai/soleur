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
# Whole-body capture. The corpus grammar is richer than one-skill-one-anchor
# (#7172): `/` joins a skill list, ` + ` joins enforcer segments, and a
# file-form token names a test/lib file instead of a skill dir. Parsing is
# done in `iter_skill_pairs`, not in the regex.
SKILL_TAG_RE = re.compile(r"\[skill-enforced: ([^\]]+)\]")
# Per-pair re-parser for comma-split fragments under a multi-pair tag.
SKILL_PAIR_RE = re.compile(r"^\s*([a-z][a-z0-9-]*)\s+(.+?)\s*$")
# Phase prefix used by both Phase-normalization variants (#3684).
PHASE_RE = re.compile(r"Phase\s+(\d+(?:\.\d+)*)")
PHASE_PREFIX_RE = re.compile(r"^Phase\s+\d+(?:\.\d+)*\s+")
# `§1.8` -> `### 1.8`, mirroring the Phase X.Y variant (#7172).
SECTION_SIGN_RE = re.compile(r"§\s*(\d+(?:\.\d+)*)")

# A REAL rule body line: `- ` at column 0. Everything else in the corpus
# (blockquote prose, the `> **Tag legend.**` block, headings, indented
# sub-bullets) is documentation ABOUT the tags, not a tag. Without this the
# legend's own `[hook-enforced: …]` is linted as if it named a hook script
# — the 13th "failure" on main, introduced by the PR that wrote the legend.
# Mirrors the body-line discipline in scripts/lint-rule-bodies.py.
BODY_LINE_RE = re.compile(r"^- ")

HOOK_SEARCH_DIRS = (
    ".claude/hooks",
    "scripts",
    "plugins/soleur/hooks",
)

# Directories searched for a file-form enforcer (`workflow-fidelity.ts`,
# `components.test.ts SYMBOL`). These tags are CORRECT — they name the
# surface that actually enforces the rule — but the enforcer is a lib/test
# file, not a skill directory, so the skill-dir resolver cannot see them.
FILE_SEARCH_DIRS = (
    "plugins/soleur/test",
    "plugins/soleur/lib",
    "plugins/soleur/scripts",
    "scripts",
    ".claude/hooks",
    "plugins/soleur/hooks",
)

FILE_FORM_EXTS = (".ts", ".tsx", ".js", ".mjs", ".py", ".sh")
# Segment keywords that select a non-skill resolver inside a ` + ` chain.
SEGMENT_KEYWORDS = ("hook", "review-agent")

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

    The matcher is intentionally permissive — the 14-pair rule-corpus
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

    section_normalized = SECTION_SIGN_RE.sub(r"### \1", anchor)
    if section_normalized != anchor and section_normalized in content:
        return True

    if "-" in anchor and not any(c.isdigit() for c in anchor):
        agents_root = root / "plugins" / "soleur" / "agents"
        if agents_root.exists():
            for _ in agents_root.rglob(f"{anchor}.md"):
                return True

    return False


def is_file_form(token: str) -> bool:
    """Return True if `token` names a file rather than a skill directory.

    `workflow-fidelity.ts`, `components.test.ts` — the enforcer is a lib or
    test file. Skill slugs never carry an extension, so the check is exact.
    """
    return token.endswith(FILE_FORM_EXTS)


def resolve_file_enforcer(token: str, symbol: str, root: Path) -> bool:
    """Resolve a file-form enforcer, optionally requiring a symbol inside it.

    `components.test.ts AUTONOMOUS_LOOP_SKILLS` must find the file AND the
    symbol — a file that no longer defines the named constant is drift the
    gate should catch, exactly like an unresolvable anchor.
    """
    if "/" in token or ".." in token:
        return False
    for d in FILE_SEARCH_DIRS:
        candidate = root / d / token
        if candidate.is_file():
            if not symbol:
                return True
            try:
                return symbol in candidate.read_text(encoding="utf-8")
            except OSError:
                return False
    return False


def resolve_agent_name(name: str, root: Path) -> bool:
    """Resolve a `review-agent <name>` segment.

    An agent may live in this repo (`plugins/soleur/agents/**/<name>.md`) or
    be supplied by an installed sibling plugin, in which case the repo still
    references it by name (agent manifests, cross-referencing agent bodies).
    Both count; a fabricated name resolves to neither and is rejected.
    """
    if "/" in name or ".." in name:
        return False
    agents_root = root / "plugins" / "soleur" / "agents"
    if not agents_root.exists():
        return False
    for _ in agents_root.rglob(f"{name}.md"):
        return True
    manifest = root / "plugins" / "soleur" / ".claude-plugin" / "agents.manifest.json"
    if manifest.is_file():
        try:
            if name in manifest.read_text(encoding="utf-8"):
                return True
        except OSError:
            return False
    return False


def skill_exists(slug: str, root: Path) -> bool:
    """Return True if `slug` names a real skill directory."""
    if "/" in slug or ".." in slug:
        return False
    return (root / "plugins" / "soleur" / "skills" / slug / "SKILL.md").exists()


def iter_skill_checks(body: str, root: Path):
    """Yield resolution units from a `[skill-enforced: ...]` tag body.

    The corpus vocabulary (#7172) is three-dimensional, and every shape below
    appears on `main` naming an enforcer that genuinely exists:

      * `,`  separates independent `<enforcer> <anchor>` pairs   (pre-existing)
      * `/`  joins a SKILL LIST sharing one anchor  — `plan/work/ship gates`
      * ` + ` joins ENFORCER SEGMENTS  — `plan Phase 2.8 + iac-plan-write-guard.sh`
      * a file extension marks a FILE enforcer — `components.test.ts SYMBOL`

    Yielded units:
      ("skills", [slug, ...], anchor)  anchor "" means "no anchor to check"
      ("file",   token, symbol)
      ("hook",   token)
      ("agent",  name)
      ("malformed", fragment)
    """
    for frag in (f.strip() for f in body.split(",")):
        if not frag:
            continue
        segments = [s.strip() for s in frag.split(" + ") if s.strip()]
        if not segments:
            continue

        head_parts = segments[0].split(None, 1)
        spec = head_parts[0]
        anchor = head_parts[1].strip() if len(head_parts) > 1 else ""

        # The skill list carried by this fragment; later segments that are
        # bare anchors resolve against it.
        skills: list[str] = []
        if is_file_form(spec):
            yield "file", spec, anchor
        elif re.fullmatch(r"[a-z][a-z0-9-]*(?:/[a-z][a-z0-9-]*)*", spec):
            skills = spec.split("/")
            yield "skills", skills, anchor
        else:
            yield "malformed", segments[0], ""
            continue

        for seg in segments[1:]:
            seg_parts = seg.split(None, 1)
            shead = seg_parts[0]
            stail = seg_parts[1].strip() if len(seg_parts) > 1 else ""
            if shead == "hook" and stail:
                yield "hook", stail.split()[0], ""
            elif shead == "review-agent" and stail:
                yield "agent", stail.split()[0], ""
            elif is_file_form(shead):
                yield "file", shead, stail
            elif skills and skill_exists(shead, root) and stail:
                # A new `<skill> <anchor>` pair joined by ` + `, e.g.
                # `brainstorm Phase 3.55 + plan Phase 2.5`.
                yield "skills", [shead], stail
            elif skills:
                # A bare descriptive segment — resolve against this
                # fragment's skill list.
                yield "skills", skills, seg
            else:
                yield "malformed", seg, ""


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
        # Only real rule bodies carry tags. Prose ABOUT the tag syntax (the
        # `> **Tag legend.**` blockquote) is documentation, not a claim to
        # resolve. See BODY_LINE_RE.
        if not BODY_LINE_RE.match(line):
            continue
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
            body = match.group(1).strip()
            # Resolution across every comma / slash / plus unit (#3684, #7172).
            for kind, value, extra in iter_skill_checks(body, root):
                anchor_pairs_checked += 1

                if kind == "malformed":
                    errors.append(
                        f"{agents_md}:{line_num}: ERROR: [skill-enforced: ... "
                        f"{value}] — fragment does not match any supported "
                        f"shape (`<skill> <anchor>`, `<skill>/<skill> <anchor>`, "
                        f"`<file>.<ext> <symbol>`). Fix: re-author the fragment."
                    )
                elif kind == "file":
                    if not resolve_file_enforcer(value, extra, root):
                        detail = f" defining `{extra}`" if extra else ""
                        errors.append(
                            f"{agents_md}:{line_num}: ERROR: [skill-enforced: "
                            f"{value}{' ' + extra if extra else ''}] — no file "
                            f"named `{value}`{detail} found under: "
                            f"{', '.join(FILE_SEARCH_DIRS)}. "
                            f"Fix: add the file, update the tag, or retire the rule."
                        )
                elif kind == "hook":
                    if not hook_resolves(value, root):
                        errors.append(
                            f"{agents_md}:{line_num}: ERROR: [skill-enforced: "
                            f"... hook {value}] — hook script not found in any "
                            f"of: {', '.join(HOOK_SEARCH_DIRS)}. "
                            f"Fix: add the script, update the tag, or retire the rule."
                        )
                elif kind == "agent":
                    if not resolve_agent_name(value, root):
                        errors.append(
                            f"{agents_md}:{line_num}: ERROR: [skill-enforced: "
                            f"... review-agent {value}] — no agent named "
                            f"`{value}` under plugins/soleur/agents/ and no "
                            f"reference in the agent manifest. "
                            f"Fix: update the tag or retire the rule."
                        )
                elif kind == "skills":
                    missing = [s for s in value if not skill_exists(s, root)]
                    if missing:
                        errors.append(
                            f"{agents_md}:{line_num}: ERROR: [skill-enforced: "
                            f"{'/'.join(value)} {extra}] — SKILL.md not found "
                            f"for: {', '.join(missing)}. "
                            f"Fix: create the skill, update the tag, or retire "
                            f"the rule."
                        )
                        continue
                    # An empty anchor is legitimate: the tag names only the
                    # enforcing skills, with no heading to pin.
                    if not extra:
                        continue
                    # A shared anchor need only resolve in ONE member — a
                    # cross-skill gate documents its contract in whichever
                    # skill owns it, not redundantly in all of them.
                    if not any(
                        resolve_anchor(s, extra, root, skill_cache) for s in value
                    ):
                        where = ", ".join(
                            f"plugins/soleur/skills/{s}/SKILL.md" for s in value
                        )
                        errors.append(
                            f"{agents_md}:{line_num}: ERROR: [skill-enforced: "
                            f"{'/'.join(value)} {extra}] — anchor not resolvable "
                            f"in any of: {where} under any tolerant variant. "
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
        # ADR-151 moved every rule BODY — and therefore every enforcement
        # tag — out of the pointer-only AGENTS.md and into AGENTS.rules.md.
        # A default of just AGENTS.md scanned a file with zero tags and
        # reported success (#7172). AGENTS.md stays in the list because a
        # pointer line may legitimately carry a tag; the vacuity floor below
        # is asserted over the SUM, so a 0-tag AGENTS.md alone still trips.
        default=["AGENTS.md", "AGENTS.rules.md"],
        help=(
            "AGENTS files to lint "
            "(default: AGENTS.md AGENTS.rules.md, resolved from CWD)"
        ),
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
        # Count over BODY lines only, so the reported totals describe exactly
        # what lint() resolved. Counting the raw text would re-introduce the
        # legend-blockquote miscount from the other direction.
        body = "\n".join(
            ln for ln in text.splitlines() if BODY_LINE_RE.match(ln)
        )
        total_hook_tags += len(HOOK_TAG_RE.findall(body))
        total_skill_tags += len(SKILL_TAG_RE.findall(body))
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

    # VACUITY FLOOR. "Every tag resolved" and "there were no tags" are the
    # same exit code without this check, and the second reads as safety —
    # which is exactly how this gate validated nothing from the ADR-151
    # corpus split until #7172. A cardinality floor is the only thing that
    # distinguishes them. Precedent: MIN_ASSERTIONS in
    # plugins/soleur/test/net-issue-flow.test.sh.
    if total_hook_tags + total_skill_tags == 0:
        print(
            "FAIL: scanned zero enforcement tags across "
            f"{len(args.files)} file(s): {', '.join(args.files)}.\n"
            "  A gate that checks nothing is indistinguishable from a gate "
            "that passes.\n"
            "  Fix: point the linter at the file that holds the rule bodies "
            "(AGENTS.rules.md).",
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
