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

[[ -f "$GUARD"    ]] || { echo "::error::guard not found: $GUARD" >&2; exit 2; }
[[ -f "$DELEGATE" ]] || { echo "::error::delegate not found: $DELEGATE" >&2; exit 2; }

# ---------------------------------------------------------------------------------------
# Build a synthetic corpus. Every setup command is checked: a harness that fails to SET UP
# must abort, never continue -- otherwise the next case runs against the previous case's
# mutation and reports a verdict about the SUT produced by a harness that could not copy a
# file.
# ---------------------------------------------------------------------------------------
mkcorpus() {
  local d
  d="$(mktemp -d -t llr-suite.XXXXXXXX)" || return 2
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
if printf '%s' "$_out" | grep -q 'article-30-register.md' \
   && printf '%s' "$_out" | grep -q 'compliance-posture.md'; then
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
echo
echo "passed: $((checks - fails)) failed: $fails total: $checks"

MIN_ASSERTIONS=33
if [[ $checks -lt $MIN_ASSERTIONS ]]; then
  printf '::error::lint-legal-registers.test.sh: only %d assertion(s) ran, expected >= %d\n' \
    "$checks" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fails -eq 0 ]] || exit 1
echo "=== lint-legal-registers.test.sh: all assertions passed ==="
