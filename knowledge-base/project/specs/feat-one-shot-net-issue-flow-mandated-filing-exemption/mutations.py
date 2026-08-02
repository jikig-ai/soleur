#!/usr/bin/env python3
"""Mutation definitions for the net-issue-flow mandated-filing exemption.

Each entry is (relative-path, old-substring, new-substring, test-to-run).
Applying asserts the anchor is present and that the write actually changed the
file — a mutation that silently matches nothing would otherwise let the suite
report a passing run as a surviving mutant, which is a claim about the SUT
produced by a harness that did nothing.

Patterns live in Python rather than being built through nested shell quoting;
the first draft of this battery reported 6 spurious BROKEN results purely from
escaping.
"""

from __future__ import annotations

import sys
from pathlib import Path

GATE = "plugins/soleur/skills/ship/scripts/net-issue-flow.sh"
TEST = "plugins/soleur/test/net-issue-flow.test.sh"
HOOK = ".claude/hooks/ship-net-issue-flow-gate.sh"
HOOK_TEST = ".claude/hooks/ship-net-issue-flow-gate.test.sh"

MUTATIONS: dict[str, tuple[str, str, str, str]] = {
    # --- headline -----------------------------------------------------------
    "M0 exemption deleted (NET ignores EXEMPT)": (
        GATE,
        "NET=$(( FILED - EXEMPT - CLOSING ))",
        "NET=$(( FILED - CLOSING ))",
        TEST,
    ),
    # --- derivation (FR1) ---------------------------------------------------
    # The derivation now shells out to the ack gate's OWN parser, so the
    # prefix/section/line-shape conjuncts are all enforced in one place. The
    # mutation that matters is reverting to a second, looser parser here.
    "M1 revert to a shell grep (a SECOND, looser parser)": (
        GATE,
        '| python3 "$REPO_ROOT/scripts/lint-rule-bodies.py" --emit-mandating-ids 2>/dev/null \\\n      || true)"',
        "| grep -F -- '[mandates-filing]' | grep -oE '\\[id: (hr|wg)-[a-z0-9-]+\\]' | sed -E 's/^\\[id: (.*)\\]$/\\1/' | sort -u || true)\"",
        TEST,
    ),
    "M1b drop the line-shape conjuncts in parse_bodies": (
        "scripts/lint-rule-bodies.py",
        'if not in_section or not line.startswith("- ") or POINTER_LINE_RE.match(line):',
        "if False:",
        TEST,
    ),
    "M2 drop the merge-base SHA guard": (
        GATE,
        'if [[ ! "$MB" =~ ^[0-9a-f]{7,40}$ ]]; then',
        "if false; then",
        TEST,
    ),
    "M3 read the WORKTREE corpus instead of merge-base": (
        GATE,
        'CORPUS_TEXT="$(git show "${MB}:AGENTS.rules.md" 2>/dev/null || true)"',
        'CORPUS_TEXT="$(cat AGENTS.rules.md 2>/dev/null || true)"',
        TEST,
    ),
    # In production `merge-base HEAD HEAD` == HEAD, letting a PR tag a rule and
    # exempt ITSELF in the same diff — the feature's central claim. A stub that
    # prefix-matched `merge-base*` could not tell this from the honest call.
    "M3c resolve merge-base against HEAD HEAD (same-PR self-grant)": (
        GATE,
        'MB="$(git merge-base origin/main HEAD 2>/dev/null || true)"',
        'MB="$(git merge-base HEAD HEAD 2>/dev/null || true)"',
        TEST,
    ),
    "M3b read the STAGED INDEX (bare :path)": (
        GATE,
        'CORPUS_TEXT="$(git show "${MB}:AGENTS.rules.md" 2>/dev/null || true)"',
        'CORPUS_TEXT="$(git show ":AGENTS.rules.md" 2>/dev/null || true)"',
        TEST,
    ),
    "M4 parser ignores the gated-SECTION conjunct": (
        "scripts/lint-rule-bodies.py",
        'if not in_section or not line.startswith("- ") or POINTER_LINE_RE.match(line):',
        'if not line.startswith("- ") or POINTER_LINE_RE.match(line):',
        TEST,
    ),
    # --- predicate (FR3) ----------------------------------------------------
    "M5 drop the \\r tolerance (CRLF bodies)": (
        GATE,
        r'test("^[ \t\r]*[Mm]andated-[Bb]y:[ \t\r]*[A-Za-z0-9-]+[ \t\r]*$")',
        r'test("^[ \t]*[Mm]andated-[Bb]y:[ \t]*[A-Za-z0-9-]+[ \t]*$")',
        TEST,
    ),
    "M6 accept multiple claim lines": (
        GATE,
        'elif ($c | length) > 1  then "multiple Mandated-By: claims"',
        'elif false then "unused"',
        TEST,
    ),
    "M7 drop the OPEN requirement": (
        GATE,
        'elif ($i.state // "") != "OPEN"',
        "elif false",
        TEST,
    ),
    "M8 drop the companion requirement": (
        GATE,
        'elif (($pb | test("(^|[^A-Za-z])(Tracks|Refs)[ \\t]+#" + ($i.number | tostring) + "([^0-9]|$)")) | not)',
        "elif false",
        TEST,
    ),
    "M8b CLOSING reads the RAW body again (fenced Closes buys NET credit)": (
        GATE,
        'CLOSING_NUMS="$(printf \'%s\\n\' "$PR_BODY_SCAN" \\',
        'CLOSING_NUMS="$(printf \'%s\\n\' "$PR_BODY" \\',
        TEST,
    ),
    "M8c exemption zeroes NET instead of subtracting": (
        GATE,
        "NET=$(( FILED - EXEMPT - CLOSING ))",
        'if [[ "$EXEMPT" -gt 0 ]]; then NET=0; else NET=$(( FILED - CLOSING )); fi',
        TEST,
    ),
    "M9 drop the companion right-boundary": (
        GATE,
        '"(^|[^A-Za-z])(Tracks|Refs)[ \\t]+#" + ($i.number | tostring) + "([^0-9]|$)"',
        '"(^|[^A-Za-z])(Tracks|Refs)[ \\t]+#" + ($i.number | tostring)',
        TEST,
    ),
    "M9b drop the companion LEFT boundary (BackRefs/ReTracks satisfy it)": (
        GATE,
        '"(^|[^A-Za-z])(Tracks|Refs)[ \\t]+#"',
        '"(Tracks|Refs)[ \\t]+#"',
        TEST,
    ),
    "M10 anchor the claim loosely (matches mid-prose)": (
        GATE,
        r'map(select(test("^[ \t\r]*[Mm]andated-[Bb]y:[ \t\r]*[A-Za-z0-9-]+[ \t\r]*$")))',
        r'map(select(test("[Mm]andated-[Bb]y:")))',
        TEST,
    ),
    "M11 membership test always true (any id qualifies)": (
        GATE,
        'elif ($ok | index($c[0])) == null',
        "elif false",
        TEST,
    ),
    # --- fence stripping (FR4) ---------------------------------------------
    # NOTE: the first draft of M12 replaced only the trailing
    # `if .inf then "" else ... end`, which leaves `.out` (already
    # fence-filtered) intact — so it was a duplicate of M13, not a
    # no-fence-strip mutation, and both SURVIVED for the same real reason:
    # nothing tested the unbalanced-fence arm. Disabling the fence DETECTOR is
    # the mutation that actually removes stripping.
    "M12 no fence-strip at all (fence detector disabled)": (
        GATE,
        'if ($l | test("^[ \\t]*```")) then .inf = (.inf | not)',
        "if false then .inf = (.inf | not)",
        TEST,
    ),
    "M13 unbalanced fence fails OPEN instead of closed": (
        GATE,
        '| if .inf then "" else (.out | join("\\n")) end;',
        '| (.out | join("\\n"));',
        TEST,
    ),
    # --- honest report (FR5) ------------------------------------------------
    "M14 Filing: silently reduced by exemptions": (
        GATE,
        """printf '  Filing:  %s  (%s)\\n' "$FILED" \"$(_fmt "$FILED_NUMS")\"""",
        """printf '  Filing:  %s  (%s)\\n' "$((FILED - EXEMPT))" \"$(_fmt "$FILED_NUMS")\"""",
        TEST,
    ),
    "M15 Exempt: line dropped from the report": (
        GATE,
        """printf '  Exempt:  %s  (%s)\\n' "$EXEMPT" \"$(_fmt_pairs "$EXEMPT_DETAIL")\"""",
        "true",
        TEST,
    ),
    "M16 Rejected: cause replaced by a generic string": (
        GATE,
        'REJECTED_DETAIL+="#${_num} (${_detail}); "',
        'REJECTED_DETAIL+="#${_num} (rejected); "',
        TEST,
    ),
    # Telemetry had NO axis in the first battery: silencing every emit left the
    # suite byte-identical, including the per-rule attribution that is the
    # feature's whole justification.
    "M16b silence ALL gate telemetry": (
        GATE,
        "_emit_as() {\n  if declare -F emit_incident >/dev/null 2>&1; then",
        "_emit_as() {\n  if false; then",
        TEST,
    ),
    "M16c attribution rides in the free-text prefix, not the rule_id": (
        GATE,
        '_emit_as "net-issue-flow-mandated-filing--${_detail}" bypass "exempt pr=${PR_NUMBER} issue=${_num}"',
        '_emit bypass "exempt rule=${_detail} pr=${PR_NUMBER} issue=${_num}"',
        TEST,
    ),
    "M16d collapse corpus-unreadable and zero-tagged into one id": (
        GATE,
        "_emit_as net-issue-flow-mandated-filing-zero-tagged warn",
        "_emit_as net-issue-flow-mandated-filing-corpus-unreadable warn",
        TEST,
    ),
    "M17 Mandating rules: count without the ids": (
        GATE,
        """printf '  Mandating rules: %s  (%s, merge-base %s)\\n' \\""",
        """printf '  Mandating rules: %s  (ids hidden%.0s, merge-base %s)\\n' \\""",
        TEST,
    ),
    # --- help text (FR8) ----------------------------------------------------
    "M18 revert the gate's override framing": (
        GATE,
        "This is the general escape hatch, NOT an architectural-pivot-only",
        "Override (legitimate architectural-pivot deferral) is for",
        TEST,
    ),
    "M19 drop the (d) mandated-filing option from the gate": (
        GATE,
        "printf '  (d) Mandated filing",
        "true '  (d) Mandated filing",
        TEST,
    ),
    "M19b drop the qualifying-rule enumeration": (
        GATE,
        """printf '      Rules that currently qualify:\\n'""",
        "true",
        TEST,
    ),
    "M19c drop the untagged-rule dead-end message": (
        GATE,
        "      unavailable to you — do not guess another id, it will be rejected.\\n",
        "      (nothing here).\\n",
        TEST,
    ),
    "M20 revert the hook's override framing": (
        HOOK,
        "This is the GENERAL hatch, not an",
        "This is a legitimate architectural-pivot deferral, not an",
        TEST,
    ),
    # --- anti-vacuity floor (TR6) ------------------------------------------
    "M21 delete a test case (floor must catch it)": (
        TEST,
        'neg "CLOSED issue"',
        'true "CLOSED issue"',
        TEST,
    ),
    # --- FR0 (hook) ---------------------------------------------------------
    "M22 timeout telemetry moved BELOW the early exit": (
        HOOK,
        """if [[ "$RC" -eq 124 ]]; then
  if declare -F emit_incident >/dev/null 2>&1; then
    emit_incident net-issue-flow-timeout warn "gate exceeded the 25s ceiling — failed open" 2>/dev/null || true
  fi
fi

[[ "$RC" -eq 1 ]] || exit 0""",
        """[[ "$RC" -eq 1 ]] || exit 0

if [[ "$RC" -eq 124 ]]; then
  if declare -F emit_incident >/dev/null 2>&1; then
    emit_incident net-issue-flow-timeout warn "gate exceeded the 25s ceiling — failed open" 2>/dev/null || true
  fi
fi""",
        HOOK_TEST,
    ),
    "M23 revert the ceiling to 8": (
        HOOK,
        "TO=(timeout 25)",
        "TO=(timeout 8)",
        HOOK_TEST,
    ),
    "M24 hardcode timeout (rc-127 dark tripwire)": (
        HOOK,
        """TO=()
command -v timeout >/dev/null 2>&1 && TO=(timeout 25)

OUT="$("${TO[@]+"${TO[@]}"}" bash "$GATE" 2>&1)\"""",
        """OUT="$(timeout 25 bash "$GATE" 2>&1)\"""",
        HOOK_TEST,
    ),
    "M25 timeout warn uses an uncounted event_type": (
        HOOK,
        'emit_incident net-issue-flow-timeout warn "gate exceeded',
        'emit_incident net-issue-flow-timeout transient "gate exceeded',
        HOOK_TEST,
    ),
}


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        for name in MUTATIONS:
            rel, _, _, testrel = MUTATIONS[name]
            print(f"{name}\t{rel}\t{testrel}")
        return 0

    if len(sys.argv) != 3:
        print("usage: mutations.py <sandbox-root> <mutation-name> | --list", file=sys.stderr)
        return 2

    root, name = Path(sys.argv[1]), sys.argv[2]
    if name not in MUTATIONS:
        print(f"unknown mutation: {name}", file=sys.stderr)
        return 2

    rel, old, new, _ = MUTATIONS[name]
    path = root / rel
    src = path.read_text()
    if src.count(old) < 1:
        print(f"ANCHOR ABSENT in {rel}: {old[:70]!r}", file=sys.stderr)
        return 3
    out = src.replace(old, new, 1)
    if out == src:
        print(f"NO-OP mutation in {rel}", file=sys.stderr)
        return 4
    path.write_text(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
