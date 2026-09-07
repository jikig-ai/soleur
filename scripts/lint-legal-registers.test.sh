#!/usr/bin/env bash
# lint-legal-registers.test.sh -- behavioural suite for the legal-register integrity guard.
#
# EVERY CASE DRIVES THE REAL SCRIPT against a synthesized corpus in a sandbox. Fixtures are
# synthesized per cq-test-fixtures-synthesized-only and are NOT copies of the live legal
# artifacts: a fixture that copies a live legal document rots into a second, unversioned copy
# of it, and a guard that only ever validated the real file cannot be shown to discriminate.
#
# The must-PASS fixture below is deliberately NOT the live register -- it differs in permitted
# ways (different dates, different synthetic paths), so a guard that happened to hard-code the
# real corpus would fail it.
#
# TMPDIR is defaulted here because a DIRECT invocation of this suite -- the documented inner
# loop while editing the guard -- inherits the bare /tmp, a machine-global tmpfs shared by
# parallel worktrees. scripts/test-all.sh sets /var/tmp; a direct run does not.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$SRC_ROOT/scripts/lint-legal-registers.sh"
DELEGATE="$SRC_ROOT/scripts/tenant-dpa-register-guard.sh"

fails=0; checks=0
pass() { checks=$((checks + 1)); echo "[ok] $1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

# INSTRUMENT SELF-TEST (ADR-193): drive both helpers once and refuse to continue unless both
# counters moved. A suite whose only gate is a failure counter can exit 0 having asserted
# nothing.
_b=$checks
{ pass x; fail x; } >/dev/null 2>&1
[[ $checks -eq $((_b + 2)) && $fails -eq 1 ]] || { echo "::error::instrument self-test failed" >&2; exit 2; }
fails=0; checks=$_b

# One owning sandbox root, removed on exit (ADR-129 rule (c)). Each case allocates INSIDE it
# rather than calling `mktemp -d` at top level, so N cases leak zero directories even when the
# suite dies mid-case. Guarded so the trap can never expand to a bare `rm -rf ""`.
SANDBOX_ROOT="$(mktemp -d -t llr-suite-root.XXXXXXXX)" \
  || { echo "::error::mktemp -d failed" >&2; exit 2; }
cleanup_sandbox() { [[ -n "${SANDBOX_ROOT:-}" && -d "$SANDBOX_ROOT" ]] && rm -rf "$SANDBOX_ROOT"; return 0; }
trap cleanup_sandbox EXIT INT TERM

[[ -f "$GUARD"    ]] || { echo "::error::guard not found: $GUARD" >&2; exit 2; }
[[ -f "$DELEGATE" ]] || { echo "::error::delegate not found: $DELEGATE" >&2; exit 2; }

# ---------------------------------------------------------------------------------------
# Build a synthetic corpus. Every setup command is checked: a harness that fails to SET UP
# must abort, never continue -- otherwise the next case runs against the previous case's
# mutation and reports a verdict about the SUT produced by a harness that could not copy a
# file.
# ---------------------------------------------------------------------------------------
# $1=dir  $2=register row block (already pipe-delimited)  $3=roster JSON
ccla_fixture() {
  mkdir -p "$1/knowledge-base/legal" "$1/apps/cla-evidence/roster" || return 2
  {
    printf -- '---\ntitle: "synthetic CCLA register"\n---\n\n'
    printf -- '# Synthetic Corporate CLA Register\n\n## Register\n\n'
    printf -- '| Record ref | Organisation legal name | CCLA version hash | Instrument hash | Signatory on file | Authorized from | Withdrawn at |\n'
    printf -- '|---|---|---|---|---|---|---|\n'
    printf -- '%s\n' "$2"
    printf -- '\n## Notes\n\nNo markers here.\n'
  } > "$1/knowledge-base/legal/ccla-register.md" || return 2
  printf -- '%s\n' "$3" > "$1/apps/cla-evidence/roster/ccla-roster.json" || return 2
}

mkcorpus() {
  local d
  d="$(mktemp -d "$SANDBOX_ROOT/case.XXXXXXXX")" || return 2
  mkdir -p "$d/scripts" "$d/knowledge-base/legal/audits" \
           "$d/knowledge-base/engineering/operations/post-mortems" || return 2
  cp "$GUARD" "$d/scripts/lint-legal-registers.sh" || return 2
  cp "$DELEGATE" "$d/scripts/tenant-dpa-register-guard.sh" || return 2

  # Two synthetic determinations, one synthetic exclusion.
  printf -- '---\ntitle: "synthetic determination A"\n---\n\nAssessed against Art. 4(12); no breach.\n' \
    > "$d/knowledge-base/legal/audits/2099-01-01-syn-determination-a.md" || return 2
  printf -- '---\ntitle: "synthetic determination B"\n---\n\nArt. 33(5) record; Art. 33 not engaged.\n' \
    > "$d/knowledge-base/legal/audits/2099-01-02-syn-determination-b.md" || return 2
  printf -- '---\ntitle: "synthetic non-determination"\n---\n\nMentions Art. 33 only to check a catalog.\n' \
    > "$d/knowledge-base/legal/audits/2099-01-03-syn-excluded.md" || return 2
  printf -- '---\ntitle: "synthetic non-determination B"\n---\n\nCites Art. 4(12) about a planned change.\n' \
    > "$d/knowledge-base/legal/audits/2099-01-04-syn-excluded-b.md" || return 2
  # OUT of (c)'s reach BY CONSTRUCTION. The corpus previously pointed OUT_OF_SCOPE_ROW at an
  # audits/ file the producer matched, so the assertion written for "the one row (c) cannot
  # see" was fixtured on a row it could: deleting it reddened via (c), and replacing the
  # assertion with `if true` left the suite green.
  printf -- '---\ntitle: "synthetic out-of-scope post-mortem"\n---\n\nArt. 4(12) assessed; no breach.\n' \
    > "$d/knowledge-base/engineering/operations/post-mortems/2099-01-05-syn-postmortem.md" || return 2

  # The CCLA register and the public coverage map, both in their EMPTY state --
  # which is the live state today, and the state block (f) must report as
  # "not yet exercised" rather than as a verified agreement.
  mkdir -p "$d/apps/cla-evidence/roster" || return 2
  ccla_fixture "$d" '| (none yet) | | | | | | |' '{"schema_version":"1.0","organizations":[]}' || return 2

  # The three other register files the token scan requires.
  for f in article-30-register article-30-2-register compliance-posture; do
    printf -- '---\ntitle: "synthetic %s"\n---\n\nNo markers here.\n' "$f" \
      > "$d/knowledge-base/legal/$f.md" || return 2
  done

  cat > "$d/knowledge-base/legal/breach-register.md" <<'BR' || return 2
---
title: "synthetic breach register"
controller: "Synthetic SARL"
---

## Index of determinations

| Date | Event | Determination | Canonical source |
|---|---|---|---|
| 2099-01-01 | synthetic event A | no breach | `knowledge-base/legal/audits/2099-01-01-syn-determination-a.md` |
| 2099-01-02 | synthetic event B | no breach | `knowledge-base/legal/audits/2099-01-02-syn-determination-b.md` |
| 2099-01-05 | synthetic out-of-scope event | no breach | `knowledge-base/engineering/operations/post-mortems/2099-01-05-syn-postmortem.md` |

## Excluded records

| File | Reason |
|---|---|
| `knowledge-base/legal/audits/2099-01-03-syn-excluded.md` | synthetic exclusion (#7717) |
| `knowledge-base/legal/audits/2099-01-04-syn-excluded-b.md` | synthetic exclusion B (#7717) |
BR

  # Point the guard at the synthetic corpus: swap the waiver list and the out-of-scope row.
  python3 - "$d/scripts/lint-legal-registers.sh" <<'PY' || return 2
import io, re, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
s = re.sub(r'NOT_TRANSCRIBED=\(\n(?:.*\n)*?\)',
           'NOT_TRANSCRIBED=(\n  "knowledge-base/legal/audits/2099-01-03-syn-excluded.md | synthetic exclusion reason (#7717)"\n  "knowledge-base/legal/audits/2099-01-04-syn-excluded-b.md | synthetic exclusion reason B (#7717)"\n)',
           s, count=1)
_b = s
s = re.sub(r'OUT_OF_SCOPE_ROW="[^"]*"',
           'OUT_OF_SCOPE_ROW="knowledge-base/engineering/operations/post-mortems/2099-01-05-syn-postmortem.md"',
           s, count=1)
assert s != _b, "OUT_OF_SCOPE_ROW rewrite did not land"
io.open(p, "w", encoding="utf-8").write(s)
PY
  ( cd "$d" && git init -q -b main . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm fixture ) >/dev/null 2>&1 || return 2
  printf '%s' "$d"
}

run_in() { ( cd "$1" && bash scripts/lint-legal-registers.sh >/dev/null 2>&1 ); echo $?; }

expect() { # name expected_rc dir
  local got; got="$(run_in "$3")"
  if [[ "$got" == "$2" ]]; then pass "$1 (rc=$got)"; else fail "$1: expected rc=$2, got rc=$got"; fi
}
expect_nonzero() { # name dir
  local got; got="$(run_in "$2")"
  if [[ "$got" != "0" ]]; then pass "$1 (rc=$got)"; else fail "$1: expected non-zero, got 0"; fi
}
# NOTE: an earlier revision defined a `mutated()` landing-checker here that was never called,
# and could not have worked -- mkcorpus did not git-init the sandbox, so `git show :<path>`
# errored, `diff -q` always differed, and it would have reported "mutated" for every input
# including an unmutated one. A green instrument that cannot report red is what the rest of
# this suite exists to prevent, so it is deleted rather than left as reassurance. Landing is
# asserted inline in the python rewrites instead.

# --- must-PASS baseline -------------------------------------------------------------------
D="$(mkcorpus)" || { echo "::error::corpus setup failed" >&2; exit 2; }
expect "baseline: synthetic corpus is clean" 0 "$D"

# --- (a) token class ----------------------------------------------------------------------
for tok in "__TBD_X__" "TBD" "TODO" "XXX" "FIXME"; do
  D="$(mkcorpus)" || exit 2
  printf '\nA standalone %s marker.\n' "$tok" >> "$D/knowledge-base/legal/breach-register.md" || exit 2
  expect "(a) standalone '$tok' in a register is caught" 1 "$D"
done

D="$(mkcorpus)" || exit 2
printf '\nDocumenting the `__TBD_X__` and `TODO` convention.\n' >> "$D/knowledge-base/legal/breach-register.md" || exit 2
expect "(a) inline-code markers are exempt (a corpus may document its own convention)" 0 "$D"

D="$(mkcorpus)" || exit 2
printf '\nA bare TODO in a NON-register legal file.\n' >> "$D/knowledge-base/legal/audits/2099-01-03-syn-excluded.md" || exit 2
expect "(a) audits/ is a working-document tree and is NOT token-scanned" 0 "$D"

# --- (b) pointer resolution ---------------------------------------------------------------
D="$(mkcorpus)" || exit 2
sed -i 's|2099-01-02-syn-determination-b.md|2099-01-02-GONE.md|' "$D/knowledge-base/legal/breach-register.md" || exit 2
expect "(b) a canonical-source pointer that does not resolve is caught" 1 "$D"

D="$(mkcorpus)" || exit 2
sed -i 's|2099-01-01-syn-determination-a.md`|2099-01-01-GONE-A.md`|; s|2099-01-02-syn-determination-b.md`|2099-01-02-GONE-B.md`|' \
  "$D/knowledge-base/legal/breach-register.md" || exit 2
n="$( cd "$D" && bash scripts/lint-legal-registers.sh 2>&1 | grep -c '(b) breach-register cites' )"
if [[ "$n" == "2" ]]; then pass "(b) the walk does not stop at the first broken pointer (flagged $n)"
else fail "(b) walk stopped early: expected 2 flagged rows, got $n"; fi

D="$(mkcorpus)" || exit 2
python3 -c "
import io,sys,re
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
io.open(p,'w',encoding='utf-8').write(re.sub(r'(?m)^\| 2099-.*\n','',s))" "$D/knowledge-base/legal/breach-register.md" || exit 2
expect_nonzero "(b) a header-only table refuses rather than reporting zero rows" "$D"

D="$(mkcorpus)" || exit 2
sed -i '/^| 2099-01-01 /d' "$D/knowledge-base/legal/breach-register.md" || exit 2
expect "(b) removing the out-of-producer-scope row is caught" 1 "$D"

# --- (c) declared-set integrity -----------------------------------------------------------
D="$(mkcorpus)" || exit 2
printf -- '---\ntitle: t\n---\nArt. 4(12) assessed.\n' > "$D/knowledge-base/legal/audits/2099-02-01-syn-new.md" || exit 2
expect "(c) a new determination-shaped file, neither indexed nor waived, is caught" 1 "$D"

D="$(mkcorpus)" || exit 2
sed -i '/2099-01-03-syn-excluded.md | synthetic exclusion reason/d' "$D/scripts/lint-legal-registers.sh" || exit 2
expect "(c) removing a waiver while its file stands is caught" 1 "$D"

D="$(mkcorpus)" || exit 2
sed -i 's|synthetic exclusion reason (#7717)|synthetic exclusion reason|' "$D/scripts/lint-legal-registers.sh" || exit 2
expect "(c) a waiver with no citing issue REFUSES (fail-closed)" 2 "$D"

D="$(mkcorpus)" || exit 2
sed -i 's|`knowledge-base/legal/audits/2099-01-02-syn-determination-b.md` |`knowledge-base/legal/audits/2099-01-03-syn-excluded.md` |' \
  "$D/knowledge-base/legal/breach-register.md" || exit 2
expect "(c) a file both indexed and waived is caught (the sets are disjoint)" 1 "$D"

D="$(mkcorpus)" || exit 2
sed -i "s|DETERMINATION_PATTERN='[^']*'|DETERMINATION_PATTERN='ZZZ_NO_MATCH_ZZZ'|" "$D/scripts/lint-legal-registers.sh" || exit 2
expect "(c) a producer that reaches nothing refuses rather than reporting a clean sweep" 2 "$D"

# --- (d) the two waiver copies agree ------------------------------------------------------
# The waiver set exists twice by design (machine-readable array + regulator-facing table), so
# the risk is silent divergence. Both directions are fixtured: without the opposite-direction
# row, a matcher that only ever checks one side would pass.
D="$(mkcorpus)" || exit 2
python3 - "$D/knowledge-base/legal/breach-register.md" <<'PY2' || exit 2
import io, re, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
s2 = re.sub(r'(?m)^\| `knowledge-base/legal/audits/2099-01-03-syn-excluded\.md`.*\n', '', s)
assert s2 != s, "anchor"
io.open(p, "w", encoding="utf-8").write(s2)
PY2
expect "(d) a waiver dropped from the REGISTER only is caught" 1 "$D"

D="$(mkcorpus)" || exit 2
sed -i '/2099-01-03-syn-excluded.md | synthetic exclusion reason/d' "$D/scripts/lint-legal-registers.sh" || exit 2
expect "(d) a waiver dropped from the SCRIPT only is caught (opposite direction)" 1 "$D"

# (d) must read the FILE COLUMN, not the section. A section-wide grep also reads the free-text
# reason cells, so deleting a row while any surviving reason cross-references its path left (d)
# green -- measured, and not contrived: a live reason cell already cross-references "the row
# above".
D="$(mkcorpus)" || exit 2
python3 - "$D/knowledge-base/legal/breach-register.md" <<'PY6' || exit 2
import io, re, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
tgt = "2099-01-04-syn-excluded-b.md"
s2 = re.sub(r'(?m)^\| `knowledge-base/legal/audits/' + re.escape(tgt) + r'`.*\n', '', s)
assert s2 != s, "row delete did not land"
a = "| `knowledge-base/legal/audits/2099-01-03-syn-excluded.md` |"
i = s2.index(a); e = s2.index("\n", i); row = s2[i:e]
s3 = s2[:i] + row.rstrip(" |") + " ; see also `knowledge-base/legal/audits/" + tgt + "` |" + s2[e:]
assert s3 != s2, "prose insert did not land"
io.open(p, "w", encoding="utf-8").write(s3)
PY6
expect "(d) a path in a REASON cell cannot stand in for a deleted File-column row" 1 "$D"

D="$(mkcorpus)" || exit 2
python3 - "$D/knowledge-base/legal/breach-register.md" <<'PY3' || exit 2
import io, re, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(re.sub(r'(?m)^\| `knowledge-base/legal/audits/.*\n', '', s))
PY3
expect "(d) an EMPTY §Excluded records table REFUSES rather than comparing equal to an empty array" 2 "$D"

# --- (b) containment, symlinks and tracked-ness ------------------------------------------
# `-f` alone was three fail-opens: a traversal, a symlink out of the tree, and an untracked file
# all satisfied it while none can be produced to a regulator.
D="$(mkcorpus)" || exit 2
sed -i 's|`knowledge-base/legal/audits/2099-01-02-syn-determination-b.md`|`../../../../../../etc/hostname`|' \
  "$D/knowledge-base/legal/breach-register.md" || exit 2
expect "(b) a canonical source escaping the repo via .. is rejected" 1 "$D"

D="$(mkcorpus)" || exit 2
ln -sf /etc/hostname "$D/knowledge-base/legal/audits/2099-01-02-syn-determination-b.md" || exit 2
( cd "$D" && git add -A && git commit -qm symlink ) >/dev/null 2>&1 || exit 2
expect "(b) a canonical source that is a SYMLINK is rejected" 1 "$D"

D="$(mkcorpus)" || exit 2
( cd "$D" && git rm -q --cached knowledge-base/legal/audits/2099-01-02-syn-determination-b.md \
    && git commit -qm untrack ) >/dev/null 2>&1 || exit 2
expect "(b) an UNTRACKED canonical source is rejected (local and CI must agree)" 1 "$D"

# --- (c) the producer walks audits/ recursively -------------------------------------------
# A bash `*` glob does not descend, so one mkdir removed coverage with no signal: `produced`
# stopped growing while the floor stayed satisfied by the top-level files.
D="$(mkcorpus)" || exit 2
mkdir -p "$D/knowledge-base/legal/audits/archive" || exit 2
printf -- '---\ntitle: t\n---\nArt. 4(12) assessed; no breach.\n' \
  > "$D/knowledge-base/legal/audits/archive/2099-01-06-syn-sub.md" || exit 2
( cd "$D" && git add -A && git commit -qm sub ) >/dev/null 2>&1 || exit 2
expect "(c) a determination in an audits/ SUBDIRECTORY is caught (producer is recursive)" 1 "$D"

# --- (a) every register is sampled, not just breach-register ------------------------------
# All eight (a) fixtures appended to breach-register.md, so 3 of the 4 REGISTER_FILES were never
# sampled: shrinking the array to one member left the suite green, because the
# scanned==declared self-check pins CONSISTENCY and not CARDINALITY.
for _reg in article-30-register article-30-2-register compliance-posture; do
  D="$(mkcorpus)" || exit 2
  printf '\nA standalone TODO marker.\n' >> "$D/knowledge-base/legal/$_reg.md" || exit 2
  expect "(a) a marker in $_reg.md is caught" 1 "$D"
done

D="$(mkcorpus)" || exit 2
printf '\nA standalone TODO marker.\n' >> "$D/knowledge-base/legal/article-30-register.md" || exit 2
printf '\nA standalone XXX marker.\n' >> "$D/knowledge-base/legal/compliance-posture.md" || exit 2
_out="$( cd "$D" && bash scripts/lint-legal-registers.sh 2>&1 )"
# Herestrings, not pipes: same pipefail/SIGPIPE early-match flake as the block
# (f) arm below. Pre-existing shape, corrected here because it is the identical
# defect in the same file.
if grep -q 'article-30-register.md' <<<"$_out" \
   && grep -q 'compliance-posture.md' <<<"$_out"; then
  pass "(a) markers in TWO registers are BOTH reported (no break-after-first-hit)"
else
  fail "(a) a two-register failure did not name both files"
fi

# --- (c) disjointness, ADDITIVE ------------------------------------------------------------
# Redirecting a row cannot test this: it reds because the DONOR row's file becomes uncovered.
# Adding a row for an already-waived file is the real case, and it passed clean before the
# check was moved out of the producer loop.
D="$(mkcorpus)" || exit 2
python3 - "$D/knowledge-base/legal/breach-register.md" <<'PY4' || exit 2
import io, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
old = "| 2099-01-05 | synthetic out-of-scope event"
assert s.count(old) == 1, "anchor"
s = s.replace(old, "| 2099-01-03 | synthetic overlap | no breach | `knowledge-base/legal/audits/2099-01-03-syn-excluded.md` |\n" + old, 1)
io.open(p, "w", encoding="utf-8").write(s)
PY4
expect "(c) a file BOTH indexed and waived is caught (additive, not redirected)" 1 "$D"

# --- the guard's own operands -------------------------------------------------------------
D="$(mkcorpus)" || exit 2
sed -i 's|^REPO_ROOT="\$(cd .*|REPO_ROOT=""|' "$D/scripts/lint-legal-registers.sh" || exit 2
expect "operand: a degenerate REPO_ROOT refuses instead of matching everything" 2 "$D"

D="$(mkcorpus)" || exit 2
python3 -c "
import io,sys,re
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
s2=re.sub(r'(?m)^(\s*)pass \"\(a\).*\$', r'\1:', s); assert s2!=s
io.open(p,'w',encoding='utf-8').write(s2)" "$D/scripts/lint-legal-registers.sh" || exit 2
expect "floor: dropping an assertion reds even with zero failures" 1 "$D"

# --- advisory flag ------------------------------------------------------------------------
D="$(mkcorpus)" || exit 2
printf '\nA standalone TODO marker.\n' >> "$D/knowledge-base/legal/breach-register.md" || exit 2
r="$( cd "$D" && bash scripts/lint-legal-registers.sh --advisory >/dev/null 2>&1; echo $? )"
if [[ "$r" == "0" ]]; then pass "--advisory downgrades a finding to non-blocking (rc=0)"
else fail "--advisory should exit 0 on a finding, got rc=$r"; fi
r="$( cd "$D" && bash scripts/lint-legal-registers.sh --advisory 2>&1 | grep -c '::warning::' )"
if [[ "$r" -ge 1 ]]; then pass "--advisory still REPORTS the finding as a warning"
else fail "--advisory suppressed the finding entirely"; fi

D="$(mkcorpus)" || exit 2
sed -i "s|DETERMINATION_PATTERN='[^']*'|DETERMINATION_PATTERN='ZZZ_NO_MATCH_ZZZ'|" "$D/scripts/lint-legal-registers.sh" || exit 2
r="$( cd "$D" && bash scripts/lint-legal-registers.sh --advisory >/dev/null 2>&1; echo $? )"
if [[ "$r" == "2" ]]; then pass "--advisory does NOT downgrade a fail-closed refusal (rc=2)"
else fail "--advisory swallowed a refusal: expected rc=2, got $r"; fi

# --- the live corpus ----------------------------------------------------------------------
r="$( cd "$SRC_ROOT" && bash scripts/lint-legal-registers.sh >/dev/null 2>&1; echo $? )"
if [[ "$r" == "0" ]]; then pass "live corpus passes the guard"
else fail "live corpus does not pass the guard (rc=$r)"; fi


# ---------------------------------------------------------------------------------------
# Block (f): the CCLA register <-> coverage map join (#7909 / P11).
#
# Every case below drives the join with REAL ROWS. The live corpus exercises only
# the empty state, so without these the check would run against real data for the
# first time on the day it actually matters.
# ---------------------------------------------------------------------------------------
HASH_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
HASH_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
roster_one() { # $1=record_ref $2=hash
  printf '{"schema_version":"1.0","organizations":[{"legal_name":"Synthetic SARL","record_ref":"%s","signed_at":"2099-01-01T00:00:00Z","cla_doc":{"path":"docs/legal/corporate-cla.md","git_sha":"deadbee","content_sha256":"%s"},"executed_instrument_sha256":"%s","representatives":[]}]}' \
    "$1" "$HASH_A" "$2"
}

D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "| CCLA-0001 | Synthetic SARL | $HASH_A | $HASH_A | yes | 2099-01-01 | |" "$(roster_one CCLA-0001 "$HASH_A")"
r="$(run_in "$D")"
if [[ "$r" == "0" ]]; then pass "(f) a joined pair whose Instrument hash AGREES passes"
else fail "(f) an agreeing joined pair was rejected (rc=$r)"; fi

D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "| CCLA-0001 | Synthetic SARL | $HASH_A | $HASH_A | yes | 2099-01-01 | |" "$(roster_one CCLA-0001 "$HASH_B")"
r="$(run_in "$D")"
if [[ "$r" == "1" ]]; then pass "(f) a joined pair whose Instrument hash DISAGREES is rejected"
else fail "(f) a disagreeing Instrument hash was accepted (rc=$r)"; fi

# THE ASYMMETRY, and the arm most likely to be got wrong. A register row with no
# roster row is the ORDINARY interim state: the register row is written when the
# instrument is executed, and the roster row cannot be written until a designated
# representative signs the Individual CLA, often months later. A symmetric check
# would red here, and both operator escapes from a red required check (delete the
# register row, or fabricate a roster row) damage a legal record.
D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "| CCLA-0002 | Later SARL | $HASH_A | $HASH_B | yes | 2099-02-01 | |" '{"schema_version":"1.0","organizations":[]}'
r="$(run_in "$D")"
if [[ "$r" == "0" ]]; then pass "(f) a register row with NO roster row is ACCEPTED (register is legitimately a superset)"
else fail "(f) the asymmetry was violated: a register row awaiting its roster row was rejected (rc=$r)"; fi

D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "| CCLA-0001 | Synthetic SARL | $HASH_A | $HASH_A | yes | 2099-01-01 | |" "$(roster_one CCLA-0009 "$HASH_A")"
r="$(run_in "$D")"
if [[ "$r" == "1" ]]; then pass "(f) a coverage-map record_ref absent from the register is rejected"
else fail "(f) a roster row with no register row was accepted (rc=$r)"; fi

# record_ref integrity BEFORE the hash check: a duplicated or malformed ref
# produces an EMPTY join, which would otherwise pass in exactly the scenario the
# check exists for.
D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "$(printf '| CCLA-0001 | A SARL | %s | %s | yes | 2099-01-01 | |\n| CCLA-0001 | B SARL | %s | %s | yes | 2099-01-02 | |' "$HASH_A" "$HASH_A" "$HASH_A" "$HASH_B")" "$(roster_one CCLA-0001 "$HASH_A")"
r="$(run_in "$D")"
if [[ "$r" == "1" ]]; then pass "(f) a DUPLICATED register Record ref is rejected (the join would otherwise be ambiguous)"
else fail "(f) a duplicated Record ref was accepted (rc=$r)"; fi

D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "| NOT-A-REF | Synthetic SARL | $HASH_A | $HASH_A | yes | 2099-01-01 | |" '{"schema_version":"1.0","organizations":[]}'
r="$(run_in "$D")"
if [[ "$r" == "1" ]]; then pass "(f) a MALFORMED register Record ref is rejected"
else fail "(f) a malformed Record ref was accepted (rc=$r)"; fi

D="$(mkcorpus)" || exit 2
ccla_fixture "$D" "| CCLA-0001 | Synthetic SARL | $HASH_A | not-64-hex | yes | 2099-01-01 | |" '{"schema_version":"1.0","organizations":[]}'
r="$(run_in "$D")"
if [[ "$r" == "1" ]]; then pass "(f) a register Instrument hash that is not 64 lowercase hex is rejected"
else fail "(f) a malformed Instrument hash was accepted (rc=$r)"; fi

# The empty state must report itself as UNEXERCISED, not as agreement. A silent
# pass here is the vacuity this block was written to avoid.
D="$(mkcorpus)" || exit 2
# MATERIALISED, not piped. Under `set -o pipefail` a `producer | grep -q` FLAKES
# to a false negative when the match is early: `grep -q` closes the pipe on the
# first hit, the producer takes SIGPIPE (141), and pipefail makes the pipeline
# non-zero -- so the `if` takes the ELSE branch even though grep matched.
# Measured here: 1 spurious failure in 4 runs of an unchanged tree.
_empty_out="$( cd "$D" && bash scripts/lint-legal-registers.sh 2>&1 || true )"
if grep -q 'NOT YET EXERCISED' <<<"$_empty_out"; then
  pass "(f) the empty state says NOT YET EXERCISED rather than reporting a verified agreement"
else
  fail "(f) the empty state did not distinguish itself from a verified agreement"
fi

# ---------------------------------------------------------------------------------------
echo
echo "passed: $((checks - fails)) failed: $fails total: $checks"

MIN_ASSERTIONS=44  # 34 -> 44: block (f)'s register/roster join arms (#7909)
if [[ $checks -lt $MIN_ASSERTIONS ]]; then
  printf '::error::lint-legal-registers.test.sh: only %d assertion(s) ran, expected >= %d\n' \
    "$checks" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fails -eq 0 ]] || exit 1
echo "=== lint-legal-registers.test.sh: all assertions passed ==="
