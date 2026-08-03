#!/usr/bin/env python3
"""Lint AGENTS.md `[hook-enforced: ...]` and `[skill-enforced: ...]` tags.

For each `[hook-enforced: <hook>]` tag, asserts the first whitespace-split
token resolves to either a path under `.claude/hooks/`, `scripts/`, or
`plugins/soleur/hooks/`, or is the literal `lefthook` whose second token
appears in `lefthook.yml` as a command run target.

For each `[skill-enforced: ...]` tag, resolves every unit in the body. The
corpus vocabulary (#7172) is:

    `,`             independent units      `plan Phase 1.8, brainstorm ...`
    `/`             skill list, one anchor `plan/work/ship gates`
    ` + `           enforcer segments      `plan Phase 2.8 + iac-guard.sh`
    `<name>.<ext>`  file enforcer          `components.test.ts SYMBOL`
    `hook <x>`      hook namespace
    `review-agent <x>`  agent namespace

Skill anchors resolve under a tolerant matcher (#3684): literal substring →
`Phase X.Y` ↔ `### X.Y` → strip leading `Phase X.Y` prefix → hyphen↔space →
agent-file fallback. A `/` list need resolve in only ONE member.

Non-vacuity: counts are incremented at the resolution sites and floored per
dimension against MIN_CHECKS, so "the scan did nothing" cannot present as
"everything resolved" (#7172).

Companion to `scripts/lint-rule-ids.py`. Wired into `lefthook.yml` at
pre-commit and into `scripts/test-all.sh` (`-live` + `-unit`) for CI.

Usage:
    python3 scripts/lint-agents-enforcement-tags.py [AGENTS.md ...]

Exit codes:
    0  all tags resolve
    1  one or more tags name a missing hook script, skill, or unresolvable anchor
    2  argument or I/O error
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# Calibrated non-vacuity ratchet, derived from a green run against the real
# corpus (not from a number anyone expected). A FLOOR, never equality: new
# rules raise these freely, and only a DROP is a finding.
MIN_CHECKS = {"hook_checks": 10, "skill_units": 30, "anchor_checks": 28}
CORPUS_FILENAME = "AGENTS.rules.md"

HOOK_TAG_RE = re.compile(r"\[hook-enforced: ([^\]]+)\]")
# Whole-body capture. The corpus grammar is richer than one-skill-one-anchor
# (#7172): `/` joins a skill list, ` + ` joins enforcer segments, and a
# file-form token names a test/lib file instead of a skill dir. Parsing is
# done in `classify_segment`, not in the regex.
SKILL_TAG_RE = re.compile(r"\[skill-enforced: ([^\]]+)\]")
# Phase prefix used by both Phase-normalization variants (#3684).
PHASE_RE = re.compile(r"Phase\s+(\d+(?:\.\d+)*)")
PHASE_PREFIX_RE = re.compile(r"^Phase\s+\d+(?:\.\d+)*\s+")

# The ONLY thing that must be exempt is the `> **Tag legend.**` block, whose
# tag bodies are the literal ellipsis — it documents the syntax, it does not
# name an enforcer.
#
# An earlier revision of this fix exempted whole LINES instead (`^- `, the
# rule-body shape). That was far broader than the problem: `main` scanned
# every line, so restricting to body lines silently STOPPED checking
# blockquote, indented-sub-bullet and prose lines. A fabricated
# `[hook-enforced: totally-fake-hook.sh]` on an indented sub-bullet then
# passed this gate AND the ADR-092 hash gate (which also ignores those
# lines) while still rendering to a session-loaded agent as a real
# enforcement claim. Exempting the ellipsis body keeps the legend quiet
# without opening those three line shapes.
ELLIPSIS_BODY_RE = re.compile(r"^(?:…|\.{3})$")

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
# Keywords that select a non-skill resolver. Honoured in EVERY position — a
# keyword recognised only in a trailing ` + ` segment silently degraded to a
# bare-substring anchor in head position, which is how
# `plan/work/ship review-agent + hook …` resolved on the word "review-agent"
# appearing once in unrelated prose (see classify_segment).
SEGMENT_KEYWORDS = ("hook", "review-agent")
# Glob metacharacters. `Path.rglob` treats these as PATTERN syntax, so an
# unfiltered token like `*` or `??????????` used to resolve to "some agent
# exists" — a wildcard is not the claim a tag makes.
#
# DEFENSE-IN-DEPTH, stated honestly: this guard is no longer the load-bearing
# one at either call site. `AGENT_SLUG_RE` rejects metachars on SHAPE before
# the rglob, and the file resolver uses `is_file()`, which treats `*` as a
# literal character rather than a pattern. Deleting this line therefore does
# NOT red the suite — so do not read its presence as the thing that closes
# the hole; the slug shape and `is_file()` semantics are.
GLOB_METACHARS = "*?["

# Per-skill SKILL.md content cache (avoids re-reading the same file across the
# 40-tag corpus). Keyed by absolute path. Lifetime: one `main()`
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
    if ".." in token or any(c in token for c in GLOB_METACHARS):
        return False
    if "/" in token:
        # `Path("/repo") / "/etc/passwd"` is `/etc/passwd` — pathlib DISCARDS
        # the left operand on an absolute right operand, so a leading `/`
        # escaped the repo entirely and `[hook-enforced: /etc/passwd]`
        # resolved. Confine to the repo root explicitly.
        candidate = (root / token).resolve()
        try:
            candidate.relative_to(root.resolve())
        except ValueError:
            return False
        return candidate.is_file()
    for d in HOOK_SEARCH_DIRS:
        if (root / d / token).is_file():
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

    The matcher is intentionally permissive — the rule corpus uses
    several notations across heading prefixes, mid-prose
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


def is_file_form(token: str) -> bool:
    """Return True if `token` names a file rather than a skill directory.

    `workflow-fidelity.ts`, `components.test.ts` — the enforcer is a lib or
    test file. Skill slugs never carry an extension, so the check is exact.
    """
    return token.endswith(FILE_FORM_EXTS)


AGENT_SLUG_RE = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)+$")


def resolve_agent_name(name: str, root: Path) -> bool:
    """Resolve a `review-agent <name>` segment.

    An agent may live in this repo (`plugins/soleur/agents/**/<name>.md`) or
    be supplied by an installed sibling plugin — `silent-failure-hunter` is a
    `pr-review-toolkit` agent, so it has no file here and is not a soleur
    manifest entry. The repo still REFERENCES it by name, and that reference
    is the strongest signal available without reading another plugin's tree.

    Two properties keep that from degenerating into "any substring":

      * the token must be a kebab-case slug of >= 2 segments, so the
        one-letter probes that used to resolve (`a`, `e`) are rejected on
        SHAPE before any search;
      * the search is whole-token, so a name may not resolve by landing
        inside a longer word.
    """
    if "/" in name or ".." in name or any(c in name for c in GLOB_METACHARS):
        return False
    if not AGENT_SLUG_RE.match(name):
        return False
    agents_root = root / "plugins" / "soleur" / "agents"
    if agents_root.exists():
        for _ in agents_root.rglob(f"{name}.md"):
            return True
    token = re.compile(rf"(?<![a-z0-9-]){re.escape(name)}(?![a-z0-9-])")
    haystacks = []
    manifest = root / "plugins" / "soleur" / ".claude-plugin" / "agents.manifest.json"
    if manifest.is_file():
        haystacks.append(manifest)
    if agents_root.exists():
        haystacks.extend(sorted(agents_root.rglob("*.md")))
    for h in haystacks:
        try:
            if token.search(h.read_text(encoding="utf-8")):
                return True
        except OSError:
            continue
    return False


def resolve_file_enforcer(token: str, symbol: str, root: Path) -> bool:
    """Resolve a file-form enforcer, optionally requiring a symbol inside it.

    `components.test.ts AUTONOMOUS_LOOP_SKILLS` must find the file AND the
    symbol — a file that no longer defines the named constant is drift the
    gate should catch, exactly like an unresolvable anchor.
    """
    if "/" in token or ".." in token or any(c in token for c in GLOB_METACHARS):
        return False
    for d in FILE_SEARCH_DIRS:
        candidate = root / d / token
        if candidate.is_file() and not candidate.is_symlink():
            if not symbol:
                return True
            try:
                text = candidate.read_text(encoding="utf-8")
            except OSError:
                return False
            # Require the symbol on a NON-COMMENT line. A raw `in` is
            # satisfied by the comment that documents the symbol, which is
            # the `cq-assert-anchor-not-bare-token` class: the moment a task
            # needs both "assert X" and "document X", they collide.
            for line in text.splitlines():
                stripped = line.lstrip()
                if stripped.startswith(("#", "//", "*", "/*")):
                    continue
                if symbol in line:
                    return True
            return False
    return False


def skill_exists(slug: str, root: Path) -> bool:
    """Return True if `slug` names a real skill directory."""
    if "/" in slug or ".." in slug:
        return False
    return (root / "plugins" / "soleur" / "skills" / slug / "SKILL.md").exists()


SLUG_LIST_RE = re.compile(r"[a-z][a-z0-9-]*(?:/[a-z][a-z0-9-]*)*")


def classify_segment(seg: str):
    """Classify ONE segment into a resolution unit. Position-independent.

    Ordered, closed, and terminal in `malformed` — a segment that matches no
    rule is an ERROR, never a silently re-interpreted anchor.

    Position independence is the correctness property, not a style choice.
    The previous revision recognised `hook` / `review-agent` only in a
    trailing ` + ` segment, so in head position they fell through to "this is
    an anchor string" and were resolved by bare substring. That is how
    `AGENTS.rules.md`'s `plan/work/ship review-agent + hook …` passed: the
    word "review-agent" occurs once in `plan/SKILL.md`, in prose about an
    unrelated postmortem, and the agent it names was never checked to exist.

    Equally load-bearing: a keyword with NO operand (`… + hook`) is malformed,
    not an anchor. Previously it fell through and resolved because the four
    letters "hook" appear somewhere in the skill body.
    """
    parts = seg.split(None, 1)
    head = parts[0]
    tail = parts[1].strip() if len(parts) > 1 else ""

    if head in SEGMENT_KEYWORDS:
        if not tail:
            return "malformed", seg, ""
        kind = "hook" if head == "hook" else "agent"
        return kind, tail.split()[0], ""
    if is_file_form(head):
        return "file", head, tail
    if SLUG_LIST_RE.fullmatch(head):
        return "skills", head.split("/"), tail
    return "malformed", seg, ""


def iter_skill_checks(body: str):
    """Yield resolution units from a `[skill-enforced: ...]` tag body.

    The corpus vocabulary (#7172) — every shape below appears on `main`
    naming an enforcer that genuinely exists:

      * `,`   separates independent units      — `plan §1.8, brainstorm …`
      * `/`   joins a SKILL LIST sharing one anchor — `plan/work/ship gates`
      * ` + ` joins ENFORCER SEGMENTS  — `plan Phase 2.8 + iac-plan-write-guard.sh`
      * `<name>.<ext>` marks a FILE enforcer  — `components.test.ts SYMBOL`
      * `hook <script>` / `review-agent <name>` select those namespaces

    Yielded units: ("skills", [slug, ...], anchor) | ("file", token, symbol)
    | ("hook", token, "") | ("agent", name, "") | ("malformed", fragment, "").

    Takes no `root`: parsing is a pure function of the string. The earlier
    revision consulted the filesystem mid-parse (`skill_exists(...)`), so a
    fragment's GRAMMAR depended on which skills happened to exist on disk.
    """
    for frag in body.split(","):
        for seg in frag.split(" + "):
            seg = seg.strip()
            if seg:
                yield classify_segment(seg)


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
) -> tuple[list[str], dict[str, int]]:
    """Return (error messages, counts-of-work-ACTUALLY-PERFORMED).

    The counts are incremented at the resolution sites themselves, not
    re-derived by a second regex pass in `main()`. That decoupling was a
    real defect: `main()` counted tags with its own `findall` and floored
    THOSE, so truncating this loop yielded
    `OK: all 10 hook + 30 skill + 0 anchor parity check(s) resolve` at
    exit 0 with the whole suite green — #7172's own failure quote, one
    indirection later. A floor is only worth what it counts.
    """
    errors: list[str] = []
    counts = {"hook_checks": 0, "skill_units": 0, "anchor_checks": 0}
    text = agents_md.read_text(encoding="utf-8")

    lefthook_path = root / "lefthook.yml"
    lefthook_text = lefthook_path.read_text(encoding="utf-8") if lefthook_path.exists() else ""

    for line_num, line in enumerate(text.splitlines(), start=1):
        for match in HOOK_TAG_RE.finditer(line):
            content = match.group(1).strip()
            # The `> **Tag legend.**` block documents the SYNTAX; its bodies
            # are the literal ellipsis and name no enforcer.
            if ELLIPSIS_BODY_RE.match(content):
                continue
            counts["hook_checks"] += 1
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
            if ELLIPSIS_BODY_RE.match(body):
                continue
            counts["skill_units"] += 1
            # Resolution across every comma / slash / plus unit (#3684, #7172).
            for kind, value, extra in iter_skill_checks(body):
                if kind == "skills" and extra:
                    # Count ONLY real anchor resolutions. The previous
                    # counter incremented once per unit of any kind — file,
                    # hook, agent, malformed and no-anchor units included —
                    # so "38 anchor parity checks" over-reported the 31 that
                    # were actually anchor resolutions.
                    counts["anchor_checks"] += 1

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

    return errors, counts


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
        # pointer line may legitimately carry a tag; the floor below is
        # asserted PER DIMENSION, so a 0-tag AGENTS.md alone still trips.
        default=["AGENTS.md", "AGENTS.rules.md"],
        help=(
            "AGENTS files to lint "
            "(default: AGENTS.md AGENTS.rules.md, resolved from CWD)"
        ),
    )
    args = parser.parse_args(argv)

    total_errors = 0
    totals = {"hook_checks": 0, "skill_units": 0, "anchor_checks": 0}
    skill_cache: dict[Path, str] = {}
    seen: set[Path] = set()
    for f in args.files:
        path = Path(f)
        if not path.is_file():
            print(f"ERROR: {f} not found", file=sys.stderr)
            return 2
        # Duplicate arguments would double every count and could satisfy the
        # floor from one file counted twice.
        if path.resolve() in seen:
            continue
        seen.add(path.resolve())
        root = repo_root_for(path)
        try:
            errs, counts = lint(path, root, skill_cache)
        except (OSError, UnicodeDecodeError) as exc:
            print(f"ERROR: cannot read {f}: {exc}", file=sys.stderr)
            return 2
        for e in errs:
            print(e, file=sys.stderr)
        total_errors += len(errs)
        for k in totals:
            totals[k] += counts[k]

    if total_errors:
        print(
            f"\n::error::FAIL: {total_errors} unresolved enforcement tag(s)"
            if os.environ.get("GITHUB_ACTIONS")
            else f"\nFAIL: {total_errors} unresolved enforcement tag(s)",
            file=sys.stderr,
        )
        return 1

    # VACUITY FLOOR — asserted on WORK PERFORMED, per dimension.
    #
    # Two properties are load-bearing and both were missing in the first cut:
    #
    # 1. The counts come from lint() itself, not from a second regex pass in
    #    main(). A floor over a separately-derived number does not constrain
    #    the scan: truncating lint()'s loop printed
    #    "10 hook + 30 skill + 0 anchor" at exit 0 with a green suite.
    # 2. Each dimension is floored SEPARATELY. A sum-based floor let a whole
    #    dimension collapse — "0 hook + 30 skill" and "10 hook + 0 skill"
    #    both exited 0, i.e. the exact "all 0 hook + 0 skill" sentence this
    #    gate exists to make impossible, half at a time.
    #
    # The minimums are a calibrated ratchet, not `> 0`, mirroring
    # MIN_ASSERTIONS=84 in plugins/soleur/test/net-issue-flow.test.sh and the
    # "refusing to emit a vacuous snapshot" guard in lint-rule-bodies.py.
    # They may RISE freely; a DROP is a deliberate act that must be argued in
    # a PR, because a silent 30 -> 3 degradation is invisible to a `> 0` test.
    # The calibrated ratchet is a property of the CORPUS, so it applies only
    # when the corpus is in the scanned set. A synthetic fixture (the unit
    # suite) is floored at "> 0" instead — still non-vacuous, but not held to
    # the real corpus's cardinality. This is scoping, not a bypass: there is
    # no flag an author can pass to weaken the corpus run.
    scanning_corpus = any(p.name == CORPUS_FILENAME for p in seen)
    floors = MIN_CHECKS if scanning_corpus else {}
    if not scanning_corpus and sum(totals.values()) == 0:
        floors = {"skill_units": 1}

    for dim, floor in floors.items():
        if totals[dim] < floor:
            prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") else ""
            print(
                f"{prefix}FAIL: {dim} = {totals[dim]}, below the calibrated "
                f"floor of {floor}, across {len(seen)} file(s): "
                f"{', '.join(args.files)}.\n"
                "  A gate that checks (almost) nothing is indistinguishable "
                "from a gate that passes.\n"
                "  Fix: point the linter at the file that holds the rule "
                "bodies (AGENTS.rules.md). If the corpus legitimately "
                "shrank, lower MIN_CHECKS in the same PR and say why.",
                file=sys.stderr,
            )
            return 1

    print(
        f"OK: {totals['hook_checks']} hook + {totals['skill_units']} skill "
        f"tag(s) resolved via {totals['anchor_checks']} anchor check(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
