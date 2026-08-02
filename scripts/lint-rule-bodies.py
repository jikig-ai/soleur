#!/usr/bin/env python3
"""Hard-rule body-weakening gate (ADR-092, minimal v1).

Guards against a SILENTLY weakened `hr-*`/`wg-*` guardrail: any change or
deletion of a hard-rule / workflow-gate BODY line in AGENTS.rules.md
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

# ADR-151: one unconditional corpus. The tuple shape is retained (rather than a
# bare string) so the parse/union plumbing below stays list-driven and a future
# second corpus file needs no structural change.
SIDECARS = ("AGENTS.rules.md",)
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
# Pointer line: `- [id: x] (tags)?` anchored end-of-line (ADR-151 dropped the
# class arrow). The corpus holds bodies; pointer-shaped lines are filtered
# defensively so this parse mirrors lint-rule-ids.POINTER_LINE_RE.
#
# SE-13 asked whether this filter becomes a no-op once the arrow is gone. It does
# not, but the first answer recorded here was measured against a NON-VACUOUS base
# and was wrong for the base this very PR ships with. Corrected:
#   * with the filter, a body gutted to its bare slug VANISHES from the head map,
#     which reads as a DELETION — caught by the manifest-side deletion check
#     below, and (when the base map resolves) by the base-map deletion arm;
#   * with the filter NEUTERED, the id stays with a changed hash and trips the
#     manifest-integrity check instead.
# So both routes do block — but by DIFFERENT checks, and the filter suppresses the
# manifest-integrity one. Do not describe it as neutral, and do not lean on it as
# a control; the gutted-slug case is ultimately held by lint-rule-ids.py's
# orphan-pointer check, which is a different gate in a different file.
POINTER_LINE_RE = re.compile(r"^- \[id: [a-z0-9-]+\](?:\s+\[[^\]]+\])*\s*$")
# Only hr-* and wg-* bodies are gated (plan: hard rules + workflow gates).
GATED_PREFIX_RE = re.compile(r"^(hr|wg)-")
# Enforcement tags whose presence escalates a changed body to a louder
# mandatory-human-review annotation (the ack is required regardless).
#
# `[mandates-filing]` is not an enforcement tag like its siblings — it does not
# describe how THIS rule is enforced. It grants the rule's filings an exemption
# from a DIFFERENT gate (net-issue-flow), so adding or dropping it changes what
# that gate will let through. Dropping it is the dangerous direction and is
# silent otherwise: the exemption simply stops matching and the only visible
# symptom is a `Mandating rules: N` count nobody is watching. Listing it here
# makes both directions loud. See ADR-155.
SECURITY_TAG_MARKERS = (
    "[compliance-tier]",
    "[hook-enforced",
    "[skill-enforced",
    "[mandates-filing]",
)
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
) -> dict[str, str]:
    """Union {id: raw_body_line} across the corpus file(s).

    ADR-151 removed the cross-sidecar collision detector that used to live here.
    It existed for threat F1: with three sidecars, a same-id decoy in a second
    file could win a last-file-wins merge and mask a weakening of the real,
    runtime-loaded body. With ONE unconditional corpus there is no second file to
    host a decoy, so the check had no failing input left — the repo's anti-vacuity
    posture (SE-4) says delete such a gate rather than leave it green.

    A duplicate id WITHIN the corpus is still caught, by `lint-rule-ids.py`'s
    per-file duplicate check (`collect_ids_typed`).
    """
    merged: dict[str, str] = {}
    for text in sidecar_texts.values():
        merged.update(parse_bodies(text, sections))
    return merged


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


def cmd_snapshot_all(root: Path, names: list[str]) -> int:
    """Emit `<sha256>  <id>` for EVERY rule body, ignoring GATED_PREFIX_RE.

    `--check`'s manifest covers only `^(hr|wg)-` (74 of 101 today), so it can say
    nothing about the `cq-*`/`rf-*`/`pdr-*`/`cm-*` bodies. That is fine for the
    weakening gate — those were never gated — but it makes the manifest unusable
    as a MIGRATION proof, which is exactly when someone needs to show a corpus
    move changed no rule text.

    This mode exists so that proof is a re-runnable command rather than a number
    somebody once pasted into a PR description. It deliberately reuses this
    module's own `parse_bodies`/`_normalize`/`_sha256`, so it cannot drift from
    what the gate itself considers a body.

    Usage (prove a corpus move is lossless, entirely from git):

        BASE=$(git merge-base origin/main HEAD); D=$(mktemp -d); mkdir -p "$D/scripts"
        git show "$BASE:scripts/lint-rule-bodies.py" > "$D/scripts/lint-rule-bodies.py"
        cp scripts/_agents_md_sections.py "$D/scripts/"
        for f in <old corpus files>; do git show "$BASE:$f" > "$D/$f"; done
        python3 "$D/scripts/lint-rule-bodies.py" --snapshot-all --root "$D" <old files> > /tmp/base.txt
        python3 scripts/lint-rule-bodies.py      --snapshot-all <new files>          > /tmp/head.txt
        diff /tmp/base.txt /tmp/head.txt     # every differing id must be justified
    """
    global GATED_PREFIX_RE
    GATED_PREFIX_RE = re.compile(r"")  # zero-length match => admits every id
    sections = _head_sections(root)
    merged: dict[str, str] = {}
    for name in names:
        f = root / name
        if not f.exists():
            print(f"ERROR: {f} not found", file=sys.stderr)
            return 2
        merged.update(parse_bodies(f.read_text(), sections))
    if not merged:
        # A silent zero here would read exactly like "nothing changed".
        print("ERROR: parsed 0 rule bodies — refusing to emit a vacuous snapshot", file=sys.stderr)
        return 2
    for rid in sorted(merged):
        print(f"{_sha256(_normalize(merged[rid]))}  {rid}")
    print(f"snapshot: {len(merged)} rule bodies", file=sys.stderr)
    return 0


def cmd_write(root: Path, manifest_path: Path) -> int:
    body_map = build_body_map(_read_worktree_sidecars(root), _head_sections(root))
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

    # Head (working-tree) state. The cross-sidecar collision fail-closed is gone
    # with the sidecars themselves (ADR-151); see build_body_map.
    head_bodies = build_body_map(_read_worktree_sidecars(root), sections)
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

    # Base state (the corpus as of <base>, same section set).
    #
    # ADR-151 MIGRATION NOTE (SE-1): `SIDECARS` is head-side, so while the base
    # predates the corpus rename `git show <base>:AGENTS.rules.md` resolves to
    # nothing and this base map is EMPTY. CI's base is `git merge-base origin/main
    # HEAD`, so that is true for EVERY commit of the renaming PR, not just the one
    # that moves the file — the CHANGE arm of this gate is blind for the whole
    # branch. Two things carry the load in that state, and neither is this map:
    #   * MODIFICATION is caught by the manifest-integrity loop above (74 gated
    #     bodies, committed hashes, no git history involved).
    #   * DELETION is caught by the manifest-side deletion check above, which was
    #     added precisely because it was NOT caught here (measured).
    # The remaining uncovered surface is a weakened `cq-*`/`rf-*`/`pdr-*`/`cm-*`
    # body: `GATED_PREFIX_RE` never admitted those, so the migration's all-101
    # identity proof for them is a one-time recorded measurement, not a standing
    # automated control. Splitting the file move and this constant into different
    # commits would be worse — every gated body would then read as DELETED.
    base_texts = {name: (_git_show(root, base_commit, name) or "") for name in SIDECARS}
    base_bodies = build_body_map(base_texts, sections)
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

    # MANIFEST-SIDE DELETION CHECK (the reverse direction of the manifest-integrity loop).
    #
    # The intersection scoping above is right for MODIFICATION but structurally
    # blind to DELETION: a removed id is absent from `head_hashes`, so the loop
    # never visits it. Deletion detection was therefore carried entirely by the
    # git base map below — which is EMPTY whenever `git show <base>:` cannot
    # resolve the corpus (any rename of the corpus file, and every commit of the
    # PR that performs one, because CI's base is `git merge-base origin/main
    # HEAD`). In that state a `[compliance-tier]` hard rule could be deleted from
    # both the index and the corpus and BOTH linters exited 0 — measured on a
    # sandbox worktree of this branch, and blocked on `origin/main`, i.e. a hole
    # opened by the rename itself.
    #
    # The committed manifest is an independent, git-history-free record of which
    # gated ids existed, so checking it in the deleting direction closes the class
    # permanently rather than just for this migration. A legitimate retirement
    # regenerates the manifest via `--write` in the same commit, so this does not
    # false-fire on `scripts/retired-rule-ids.txt` flows.
    for rid in manifest_hashes:
        if rid in head_hashes:
            continue
        if DELETED_TOKEN in new_acks(rid):
            continue
        errors.append(
            f"::error::rule-body-lint: {rid} is recorded in "
            f"{MANIFEST_REL} but ABSENT from the corpus — a gated rule body was "
            "DELETED without a `<id>|DELETED|<date>|<PR>|<reason>` ack. If the "
            "removal is intentional, append the ack and re-run `--write`."
        )

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
                    "([compliance-tier]/[hook-enforced]/[skill-enforced]/[mandates-filing]) being "
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
                "([compliance-tier]/[hook-enforced]/[skill-enforced]/[mandates-filing]) — "
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
    parser.add_argument(
        "--snapshot-all",
        nargs="*",
        metavar="FILE",
        help="Emit `<sha256>  <id>` for EVERY rule body (ignores the hr/wg gate). "
             "Migration-proof helper; defaults to AGENTS.rules.md.",
    )
    parser.add_argument("--check", action="store_true", help="Run the CI gate.")
    parser.add_argument("--base", default=None, help="Base git ref for --check (merge-base).")
    parser.add_argument("--root", type=Path, default=None, help="Repo root (default: script parent's parent).")
    parser.add_argument("--pr", default=None, help="PR number (informational).")
    args = parser.parse_args()

    root = (args.root or Path(__file__).resolve().parents[1]).resolve()
    manifest_path = root / MANIFEST_REL
    acks_path = root / ACKS_REL

    # `--snapshot-all` is a read-only reporter, not a mode of the gate: it is
    # checked before the write/check XOR so it composes with neither.
    if args.snapshot_all is not None:
        if args.write or args.check:
            print(
                "ERROR: --snapshot-all does not combine with --write/--check",
                file=sys.stderr,
            )
            return 2
        return cmd_snapshot_all(root, list(args.snapshot_all) or list(SIDECARS))

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
