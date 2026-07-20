#!/usr/bin/env python3
"""Hard-rule body-weakening gate (ADR-092, minimal v1).

Guards against a SILENTLY weakened `hr-*`/`wg-*` guardrail: any change or
deletion of a hard-rule / workflow-gate BODY line in AGENTS.{core,docs,rest}.md
is BLOCKED unless a per-change, hash-bound ack exists in the CODEOWNERS-owned
WORM file `.claude/rule-weakening-acks.txt`. The safe primitive is "add a new
rule" (new id) — always allowed; "revise/remove an existing rule body" is
human-gated.

Two modes:

  --write   Regenerate the committed sha256 body-hash manifest
            (.claude/rule-body-hashes.txt) over the current corpus. Run this
            after ANY intentional body edit, then record the matching ack.

  --check --base <ref>
            The CI gate. Re-derives sha256 over the working-tree sidecar bodies
            (TR1 — never trusts the committed manifest value), diffs each
            `hr-*`/`wg-*` body vs its state at <ref> (which MUST be the
            merge-base: `git merge-base origin/main HEAD`, NOT origin/main tip),
            and requires a matching ack for every changed or deleted body.
            Fail-closed: parse error / missing manifest / unresolvable base →
            non-zero.

Manifest integrity (AC6): `--check` recomputes every head body hash and compares
to the committed manifest; a hand-edited or stale manifest value that does not
match the body BLOCKS with a "run --write" message. A legitimate body change is
therefore a three-step workflow: (1) edit the body, (2) `--write` to regenerate
the manifest, (3) append the ack line whose sha256 equals the new body hash.

Ack format (append-only WORM; `#` comments + blank lines ignored):
    <id>|<sha256>|<date>|<PR>|<reason>
For a DELETION the sha256 field is the literal token `DELETED`.

Normalization (the deliberate resolution of the plan's Open Question): a body
line is normalized by collapsing all internal whitespace runs to a single space
and stripping the ends (`" ".join(line.split())`) BEFORE hashing, so a
trailing-whitespace / re-indent reformat is a no-op. Enforcement-tag ORDER is
NOT normalized — a tag reorder is treated as a body change (it is rare and a
harmless false-positive that merely costs a one-line ack), because a robust
tag-order normalizer over mid-prose tags risks the far worse false-NEGATIVE of
masking a real tag DROP (dropping `[compliance-tier]` IS a weakening the gate
must catch). Fail toward requiring an ack, never toward missing one.

Recursion invariant (ADR-092): this script, the manifest, the ack file, and the
CI wiring stay OUTSIDE the auto-editable set (`TARGET_ALLOW_RE` in
cron-compound-promote.ts). Enforced by an importing recursion test.

Usage:
    python3 scripts/lint-rule-bodies.py --write [--root <dir>]
    python3 scripts/lint-rule-bodies.py --check --base <ref> [--root <dir>] [--pr <n>]
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

_SCRIPTS_DIR = str(Path(__file__).parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _agents_md_sections import SECTIONS  # noqa: E402

SIDECARS = ("AGENTS.core.md", "AGENTS.docs.md", "AGENTS.rest.md")
SECTIONS_MODULE_REL = "scripts/_agents_md_sections.py"
# Manifest is a HASH-FIRST text file (`<sha256>  <id>` per line), NOT JSON keyed
# by id: a rule-id whose suffix is a secret-scanner keyword (`…-auth`, `…-key`,
# `…-token`) as a JSON key would put `"<keyword>": "<64-hex>"` on one line and
# trip gitleaks `generic-api-key`. Hash-first (no keyword before the hex) scans
# clean, and per-line records are collision-safe (two ids with an identical body
# hash stay distinct rows — a hash-as-JSON-key map would collide).
MANIFEST_REL = Path(".claude") / "rule-body-hashes.txt"
ACKS_REL = Path(".claude") / "rule-weakening-acks.txt"
MANIFEST_SCHEMA = 1

ID_RE = re.compile(r"\[id: ([a-z0-9-]+)\]")
# Pointer line: `- [id: x] (tags)? → <class>` anchored end-of-line. Sidecars
# hold bodies, but filter pointer-shaped lines defensively (mirrors
# lint-rule-ids.POINTER_LINE_RE).
POINTER_LINE_RE = re.compile(
    r"^- \[id: [a-z0-9-]+\](?:\s+\[[^\]]+\])*\s+→\s+(core|docs-only|rest)\s*$"
)
# Only hr-* and wg-* bodies are gated (plan: hard rules + workflow gates).
GATED_PREFIX_RE = re.compile(r"^(hr|wg)-")
# Enforcement tags whose presence escalates a changed body to a louder
# mandatory-human-review annotation (the ack is required regardless).
SECURITY_TAG_MARKERS = ("[compliance-tier]", "[hook-enforced", "[skill-enforced")
DELETED_TOKEN = "DELETED"


def _normalize(line: str) -> str:
    """Collapse all whitespace runs to single spaces and strip the ends."""
    return " ".join(line.split())


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _has_security_tag(raw_line: str) -> bool:
    return any(marker in raw_line for marker in SECURITY_TAG_MARKERS)


_SECTIONS_FROZENSET_RE = re.compile(r"SECTIONS\s*=\s*frozenset\(\{(.*?)\}\)", re.DOTALL)


def extract_sections(module_text: str) -> set[str]:
    """Extract the SECTIONS heading names from `_agents_md_sections.py` source.

    Regex over the `SECTIONS = frozenset({...})` literal rather than importing,
    so the BASE-side (`git show <base>:...`) version can be read without exec.
    """
    m = _SECTIONS_FROZENSET_RE.search(module_text)
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))


def parse_bodies(text: str, sections: frozenset[str] | set[str]) -> dict[str, str]:
    """Return {id: raw_body_line} for gated ids in one sidecar's text.

    A body line is a `- ` line under a `## <SECTION>` heading in `sections` that
    is not a pointer line and whose `[id: ...]` is `hr-*`/`wg-*`. `sections` is
    passed in (not the module global) so `cmd_check` can parse BOTH sides with
    the UNION of base-side and head-side section names — otherwise a PR that
    narrows `SECTIONS` in `_agents_md_sections.py` while weakening a body in the
    same diff would hide that body from the base parse too (the SECTIONS-oracle
    reward-hack — a silent false-negative). See ADR-092 Consequences.
    """
    bodies: dict[str, str] = {}
    in_section = False
    for line in text.splitlines():
        m = re.match(r"^## (.+?)\s*$", line)
        if m:
            in_section = m.group(1).strip() in sections
            continue
        if not in_section or not line.startswith("- ") or POINTER_LINE_RE.match(line):
            continue
        id_match = ID_RE.search(line)
        if not id_match:
            continue
        rid = id_match.group(1)
        if not GATED_PREFIX_RE.match(rid):
            continue
        bodies[rid] = line
    return bodies


def build_body_map(
    sidecar_texts: dict[str, str], sections: frozenset[str] | set[str]
) -> tuple[dict[str, str], list[str]]:
    """Union {id: raw_body_line} across all sidecars (SF-P2-9).

    Returns (merged, collisions). A gated id that appears in MORE THAN ONE
    sidecar is a `collision` — the pointer index is 1:1, so an id lives in
    exactly one sidecar. Callers fail-closed on any collision: last-file-wins
    would otherwise let a same-id decoy in a second sidecar mask a weakening of
    the real, runtime-loaded body (F1). `sidecar_texts` is ordered so the
    collision message names both hosts.
    """
    merged: dict[str, str] = {}
    origin: dict[str, str] = {}
    collisions: list[str] = []
    for name, text in sidecar_texts.items():
        for rid, raw in parse_bodies(text, sections).items():
            if rid in origin:
                collisions.append(f"{rid} (in {origin[rid]} and {name})")
            else:
                origin[rid] = name
            merged[rid] = raw
    return merged, sorted(collisions)


def hashes_for(body_map: dict[str, str]) -> dict[str, str]:
    return {rid: _sha256(_normalize(raw)) for rid, raw in body_map.items()}


def _read_worktree_sidecars(root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for name in SIDECARS:
        p = root / name
        out[name] = p.read_text() if p.exists() else ""
    return out


def _git_show(root: Path, ref: str, rel: str) -> str | None:
    """Return `git show <ref>:<rel>` text, or None if the path is absent there."""
    r = subprocess.run(
        ["git", "-C", str(root), "show", f"{ref}:{rel}"],
        capture_output=True, text=True,
    )
    return r.stdout if r.returncode == 0 else None


def _resolve_commit(root: Path, ref: str) -> str | None:
    r = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        capture_output=True, text=True,
    )
    out = r.stdout.strip()
    return out or None


def parse_acks(text: str) -> dict[str, set[str]]:
    """Parse ack-file text → {id: {hash_or_DELETED_token, ...}}.

    A valid ack is the full 5-field shape `<id>|<sha256>|<date>|<PR>|<reason>`
    with a NON-EMPTY reason — the ack is meant to be a reasoned, audit-logged
    act (ADR-092 §Decision-2). A short or reason-less line is ignored (not a
    valid ack) so it cannot satisfy the gate. `reason` captures everything after
    the 4th `|` (a reason may itself contain `|`).
    """
    acks: dict[str, set[str]] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split("|", 4)
        if len(parts) < 5:
            continue
        rid, token, reason = parts[0].strip(), parts[1].strip(), parts[4].strip()
        if not rid or not token or not reason:
            continue
        acks.setdefault(rid, set()).add(token)
    return acks


def load_acks(path: Path) -> dict[str, set[str]]:
    if not path.exists():
        return {}
    return parse_acks(path.read_text(encoding="utf-8-sig"))


_MANIFEST_SCHEMA_RE = re.compile(r"schema[= ](\d+)")


def render_manifest(hashes: dict[str, str]) -> str:
    """Render the hash-first text manifest (`<sha256>  <id>`, sorted by id)."""
    lines = [
        f"# rule-body hash manifest — schema {MANIFEST_SCHEMA} (ADR-092).",
        "# Format: <sha256>  <id>. Hash-FIRST on purpose — a rule-id keyword",
        "# suffix as a JSON key would trip gitleaks generic-api-key. Regenerate",
        "# with `python3 scripts/lint-rule-bodies.py --write`.",
    ]
    lines += [f"{h}  {rid}" for rid, h in sorted(hashes.items())]
    return "\n".join(lines) + "\n"


def parse_manifest(text: str) -> tuple[dict[str, str], bool]:
    """Parse the text manifest → ({id: sha256}, schema_ok). Raises ValueError on
    a malformed body line (fail-closed at the call site)."""
    hashes: dict[str, str] = {}
    schema_ok = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            m = _MANIFEST_SCHEMA_RE.search(stripped)
            if m and int(m.group(1)) == MANIFEST_SCHEMA:
                schema_ok = True
            continue
        if not stripped:
            continue
        parts = stripped.split()
        if len(parts) != 2:
            raise ValueError(f"malformed manifest line: {line!r}")
        h, rid = parts
        hashes[rid] = h
    return hashes, schema_ok


def _head_sections(root: Path) -> set[str]:
    """Head-side section names, read from the TREE UNDER CHECK (`root`), not the
    gate's install location — so a PR that narrows SECTIONS is seen as narrowed.
    Falls back to the imported module when `root` has no sections file."""
    p = root / SECTIONS_MODULE_REL
    if p.exists():
        s = extract_sections(p.read_text())
        if s:
            return s
    return set(SECTIONS)


def _base_sections(root: Path, base_commit: str) -> set[str]:
    text = _git_show(root, base_commit, SECTIONS_MODULE_REL)
    return extract_sections(text) if text is not None else set()


def cmd_write(root: Path, manifest_path: Path) -> int:
    body_map, collisions = build_body_map(_read_worktree_sidecars(root), _head_sections(root))
    if collisions:
        print(
            "ERROR: cross-sidecar duplicate gated id(s) — a rule body must live "
            f"in exactly one sidecar: {collisions}",
            file=sys.stderr,
        )
        return 2
    hashes = hashes_for(body_map)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(render_manifest(hashes))
    print(f"wrote {len(hashes)} rule-body hashes → {manifest_path}")
    return 0


def cmd_check(
    root: Path, base: str, manifest_path: Path, acks_path: Path, pr: str | None = None
) -> int:
    errors: list[str] = []
    pr_ref = pr or "<PR>"

    # Fail-closed: unresolvable base ref.
    base_commit = _resolve_commit(root, base)
    if base_commit is None:
        print(
            f"::error::rule-body-lint: cannot resolve base ref {base!r} "
            "(fail-closed). Pass `git merge-base origin/main HEAD`.",
            file=sys.stderr,
        )
        return 2

    # Fail-closed: missing / unparseable manifest.
    if not manifest_path.exists():
        print(
            f"::error::rule-body-lint: manifest {manifest_path} missing "
            "(fail-closed). Run `python3 scripts/lint-rule-bodies.py --write`.",
            file=sys.stderr,
        )
        return 2
    try:
        manifest_hashes, schema_ok = parse_manifest(manifest_path.read_text())
    except ValueError as e:
        print(f"::error::rule-body-lint: manifest parse error: {e}", file=sys.stderr)
        return 2
    if not schema_ok:
        print(
            f"::error::rule-body-lint: manifest missing/!= schema {MANIFEST_SCHEMA} "
            "(fail-closed). Run `python3 scripts/lint-rule-bodies.py --write`.",
            file=sys.stderr,
        )
        return 2

    # SECTIONS oracle: parse BOTH sides with the UNION of base-side and head-side
    # section names, so a PR that narrows `SECTIONS` in _agents_md_sections.py
    # while weakening a body in the same diff cannot hide that body from the base
    # parse (the SECTIONS-oracle reward-hack — a silent false-negative).
    sections = _head_sections(root) | _base_sections(root, base_commit)

    # Head (working-tree) state. Cross-sidecar duplicate id → fail-closed (F1:
    # last-file-wins would let a same-id decoy in a second sidecar mask a
    # weakening of the real, runtime-loaded body).
    head_bodies, head_collisions = build_body_map(_read_worktree_sidecars(root), sections)
    if head_collisions:
        print(
            "::error::rule-body-lint: cross-sidecar duplicate gated id(s) in head "
            f"(fail-closed; a rule body must live in exactly one sidecar): {head_collisions}",
            file=sys.stderr,
        )
        return 2
    head_hashes = hashes_for(head_bodies)

    # Manifest integrity (AC6, TR1): for every id present in BOTH head and the
    # committed manifest, the committed hash MUST equal the re-derived head hash
    # — a mismatch is a stale/tampered manifest (the gate never trusts the
    # committed value). Scoped to the intersection deliberately: an id in head
    # but NOT in the manifest is an ADDITIVE new rule (allowed) whose tamper-
    # anchor simply isn't recorded yet — requiring it here would let a sibling
    # PR that adds a rule (without this branch's manifest) false-block the NEXT
    # unrelated PR on `main` (the "all-members drift guard must rebase before
    # ship" class). Change/deletion detection is git-based (base map below), NOT
    # manifest-based, so an incomplete manifest never weakens the actual gate.
    # (Sibling-MODIFICATION transient: if a sibling PR changed an existing body on
    # main, a behind-branch PR's working tree carries the new body while its own
    # manifest carries the old hash → this fires on a rule that PR never touched.
    # Subsumed by strict_required_status_checks_policy=true, which forces the PR
    # to update-branch before merge and pulls main's regenerated manifest.)
    for rid, h in head_hashes.items():
        committed = manifest_hashes.get(rid)
        if committed is not None and committed != h:
            errors.append(
                f"::error::rule-body-lint: {rid} manifest hash stale/tampered "
                f"(committed {committed!r} != body {h}). "
                "Run `python3 scripts/lint-rule-bodies.py --write` to regenerate."
            )

    # Base state (unioned across all three sidecars at <base>, same section set).
    base_texts = {name: (_git_show(root, base_commit, name) or "") for name in SIDECARS}
    base_bodies, base_collisions = build_body_map(base_texts, sections)
    if base_collisions:
        print(
            "::error::rule-body-lint: cross-sidecar duplicate gated id(s) at base "
            f"(fail-closed): {base_collisions}",
            file=sys.stderr,
        )
        return 2
    base_hashes = hashes_for(base_bodies)

    # F2 (ack-replay): the ack must be NEWLY added in this diff (head ack set
    # minus the base ack set), so reverting a body to any PREVIOUSLY-acked form
    # cannot pass on a stale historical ack. `git show <base>:<ackfile>` gives
    # the base ack set; the working tree gives head.
    head_acks = load_acks(acks_path)
    base_ack_text = _git_show(root, base_commit, str(ACKS_REL))
    base_acks = parse_acks(base_ack_text) if base_ack_text is not None else {}

    def new_acks(rid: str) -> set[str]:
        return head_acks.get(rid, set()) - base_acks.get(rid, set())

    # Changed or deleted bodies present at base → require a matching per-change ack.
    for rid, base_raw in base_bodies.items():
        if rid not in head_bodies:
            # Deletion of a body under a (possibly retained-index) id.
            if _has_security_tag(base_raw):
                print(
                    f"::error::rule-body-lint: {rid} is a security-tagged rule being "
                    "DELETED — mandatory-human-review.",
                    file=sys.stderr,
                )
            if DELETED_TOKEN not in new_acks(rid):
                errors.append(
                    f"::error::rule-body-lint: {rid} body DELETED without an ack. "
                    f"Add `{rid}|DELETED|<date>|{pr_ref}|<reason>` to {ACKS_REL}."
                )
            continue
        if base_hashes[rid] != head_hashes[rid]:
            # Body changed under a stable id.
            if _has_security_tag(base_raw) or _has_security_tag(head_bodies[rid]):
                print(
                    f"::error::rule-body-lint: {rid} is a security-tagged rule "
                    "([compliance-tier]/[hook-enforced]/[skill-enforced]) being "
                    "changed — mandatory-human-review.",
                    file=sys.stderr,
                )
            if head_hashes[rid] not in new_acks(rid):
                errors.append(
                    f"::error::rule-body-lint: {rid} body changed without a matching "
                    f"ack. Add `{rid}|{head_hashes[rid]}|<date>|{pr_ref}|<reason>` to "
                    f"{ACKS_REL} (sha256 must equal the new body hash; the ack must be "
                    "added in THIS diff — a pre-existing historical ack does not count)."
                )

    # New security-tagged rule (additive) → loud annotation, NOT a block (AC5).
    for rid, raw in head_bodies.items():
        if rid not in base_bodies and _has_security_tag(raw):
            print(
                f"::warning::rule-body-lint: {rid} is a NEW security-tagged rule "
                "([compliance-tier]/[hook-enforced]/[skill-enforced]) — "
                "mandatory-human-review that it is not a toothless control.",
            )

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    print("rule-body-lint: OK (no un-acked hr-*/wg-* body changes)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Regenerate the manifest.")
    parser.add_argument("--check", action="store_true", help="Run the CI gate.")
    parser.add_argument("--base", default=None, help="Base git ref for --check (merge-base).")
    parser.add_argument("--root", type=Path, default=None, help="Repo root (default: script parent's parent).")
    parser.add_argument("--pr", default=None, help="PR number (informational).")
    args = parser.parse_args()

    root = (args.root or Path(__file__).resolve().parents[1]).resolve()
    manifest_path = root / MANIFEST_REL
    acks_path = root / ACKS_REL

    if args.write == args.check:
        print("ERROR: pass exactly one of --write or --check", file=sys.stderr)
        return 2
    if args.write:
        return cmd_write(root, manifest_path)
    if not args.base:
        print("ERROR: --check requires --base <ref>", file=sys.stderr)
        return 2
    return cmd_check(root, args.base, manifest_path, acks_path, args.pr)


if __name__ == "__main__":
    sys.exit(main())
