#!/usr/bin/env bash
# P1b guard (#7708): an operand that is neither provably absolute nor guarded.
#
# The sibling suite `fixture-dir-operand-assert.test.sh` asks whether an operand can be EMPTY.
# This one asks whether it can be RELATIVE, or be rooted at `/` by an empty parent. The rules are
# separate on purpose: only `git -C ""` widens silently, `rm -rf ""` is a no-op and `mv a ""`
# errors, so folding them would let one rule's verdict speak for a failure mode it never measured.
#
# ANTI-VACUITY. Every arm here exists because a cheaper version of it was defeated, on this repo,
# by a change that kept the arm green:
#   * counters alone are DIRECTION-BLIND — `passes + fails == asserted` conserves the total, so
#     moving a verdict between buckets is free. The append-only VERDICT_LOG is the independent
#     observable the accounting reconciles against, and row L drives `fail()` rather than reading
#     its body, because any "the source contains string X" check is defeated by preserving X.
#   * a floor on SITES alone is satisfiable by NARROWING the corpus, so FILES carries its own floor.
#   * a scanner that stops looking reports SITES=0, which a shrink-only ratchet reads as progress,
#     so the live count is pinned by EQUALITY to the baseline sum, not by `<=`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCANNER="$SCRIPT_DIR/lib/fixture-scan.py"
BASELINE="$SCRIPT_DIR/fixture-relative-assert.baseline.txt"

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }
[[ -f "$SCANNER" ]] || { echo "FATAL: scanner missing at $SCANNER" >&2; exit 2; }

if [[ "${1:-}" == "--write-baseline" ]]; then
  hdr="$(mktemp)" || exit 2
  grep -E '^#|^[[:space:]]*$' "$BASELINE" > "$hdr"
  { cat "$hdr"
    python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" 2>/dev/null \
      | grep 'operand not provably absolute' \
      | sed -E 's/^([^:]+):.*/\1/' | sort | uniq -c | awk '{printf "%s\t%s\n", $1, $2}' | sort -k2
  } > "$BASELINE"
  rm -f "$hdr"
  echo "baseline rewritten: $BASELINE"
  exit 0
fi

TMP_ROOT=$(mktemp -d -t fixturerel.XXXXXXXX) || { echo "FATAL: no scratch root" >&2; exit 2; }
: "${TMP_ROOT:?scratch root is empty; rm -rf <empty> would target the caller tree}"
trap 'rm -rf "$TMP_ROOT"' EXIT

passes=0; fails=0; asserted=0
VERDICT_LOG="$TMP_ROOT/verdicts.txt"; : > "$VERDICT_LOG"
pass() { echo "  PASS: $1"; echo "PASS" >> "$VERDICT_LOG"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; echo "FAIL" >> "$VERDICT_LOG"; fails=$((fails + 1)); }
ck()   { asserted=$((asserted + 1)); }

scan_sites() { python3 "$SCANNER" --rule relative "$@" 2>/dev/null | sed -n 's/^SITES=//p'; }

# --- A. The live corpus against the shrink-only baseline ------------------------------------------
echo "A. live corpus vs baseline"

ck; FILES_SCANNED=$(python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" 2>/dev/null | sed -n 's/^FILES=//p')
# A corpus floor, not just a site floor. Narrowing the glob to one app directory drops ~680 of the
# tracked files and would leave every site-count arm below green while coverage collapsed.
if [[ -z "${FILES_SCANNED:-}" || "$FILES_SCANNED" -lt 850 ]]; then
  fail "corpus floor: FILES=${FILES_SCANNED:-unset}, want >= 850 (measured 925)"
else
  pass "corpus floor: FILES=$FILES_SCANNED >= 850"
fi

ck; SITES_LIVE=$(python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" 2>/dev/null | sed -n 's/^SITES=//p')
ACK_TOTAL=$(grep -vE '^#|^[[:space:]]*$' "$BASELINE" | awk -F'\t' '{s+=$1} END {print s+0}')
# EQUALITY, not `<=`. A detector that stopped looking reports fewer sites, which `<=` reads as
# progress and waves through. A genuine shrink is expected to update the baseline in the same
# commit as the source edit that earned it.
if [[ "${SITES_LIVE:-unset}" != "$ACK_TOTAL" ]]; then
  fail "live SITES=${SITES_LIVE:-unset} != baseline total $ACK_TOTAL (shrink? regenerate with --write-baseline in the same commit as the fix)"
else
  pass "live SITES == baseline total ($ACK_TOTAL)"
fi

# A named holder, so a change that zeroes one file cannot hide inside an unchanged grand total.
ck; NAMED_FILE=".github/scripts/test/fixtures-validate-infra-templates.sh"
NAMED_WANT=$(awk -F'\t' -v f="$NAMED_FILE" '$2==f {print $1}' "$BASELINE")
NAMED_GOT=$(python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" 2>/dev/null \
  | grep -cE "^${NAMED_FILE}:[0-9]+:")
if [[ -z "$NAMED_WANT" || "$NAMED_GOT" != "$NAMED_WANT" ]]; then
  fail "named holder $NAMED_FILE: got $NAMED_GOT, baseline says ${NAMED_WANT:-<absent>}"
else
  pass "named holder pinned: $NAMED_FILE = $NAMED_GOT"
fi

# The git -C family was remediated inline in #7708 and must STAY at zero; a regression there is a
# new unguarded site in the one family whose empty-operand cousin writes into the caller's repo.
ck; GITC=$(python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" 2>/dev/null | grep -c '(git-C,')
if [[ "$GITC" -ne 0 ]]; then
  fail "git -C family regressed: $GITC site(s); it was burned to 0 and is not grandfathered"
else
  pass "git -C family still at 0 (remediated inline, not grandfathered)"
fi
echo "  (corpus: ${FILES_SCANNED} files, ${SITES_LIVE} sites)"

# --- B. The ratchet is enforced, not merely documented --------------------------------------------
echo "B. ratchet enforcement"
ck; B_TMP="$TMP_ROOT/b"; mkdir -p "$B_TMP"
grep -vE '^#|^[[:space:]]*$' "$BASELINE" | awk -F'\t' '{printf "%s\t%s\n", ($1+1), $2}' > "$B_TMP/risen.txt"
RISEN=$(awk -F'\t' '{s+=$1} END {print s+0}' "$B_TMP/risen.txt")
if [[ "$RISEN" -le "$ACK_TOTAL" ]]; then
  fail "ratchet arm is inert: a per-row +1 did not raise the total"
else
  pass "a risen baseline is arithmetically detectable ($ACK_TOTAL -> $RISEN)"
fi

# --- C. Must-FAIL fixtures. Each is the canonical shape of one family. -----------------------------
echo "C. synthetic must-FAIL (the rule fires)"
C="$TMP_ROOT/c"; mkdir -p "$C"

cat > "$C/rel_gitc.sh" <<'EOF'
setup() {
  local root="$1"
  local work="$root/repo"
  git -C "$work" commit -m x
}
EOF
ck; n=$(scan_sites "$C/rel_gitc.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "git -C with a positional-rooted operand is reported" \
  || fail "git -C with a positional-rooted operand was MISSED (SITES=${n:-unset})"

cat > "$C/rel_rm.sh" <<'EOF'
cleanup() {
  local base="$1"
  rm -rf "$base/scratch"
}
EOF
ck; n=$(scan_sites "$C/rel_rm.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "rm -rf with a positional-rooted operand is reported" \
  || fail "rm -rf with a positional-rooted operand was MISSED (SITES=${n:-unset})"

cat > "$C/rel_redir.sh" <<'EOF'
emit() {
  local out="$1"
  echo hello > "$out/log.txt"
}
EOF
ck; n=$(scan_sites "$C/rel_redir.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "redirection into a positional-rooted target is reported" \
  || fail "redirection into a positional-rooted target was MISSED (SITES=${n:-unset})"

cat > "$C/rel_mv.sh" <<'EOF'
stage() {
  local dest="$1"
  mv payload "$dest/payload"
}
EOF
ck; n=$(scan_sites "$C/rel_mv.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "mv into a positional-rooted destination is reported" \
  || fail "mv into a positional-rooted destination was MISSED (SITES=${n:-unset})"

# --- D. Must-PASS fixtures. Each would be a false positive, and each is a way the rule could
#        become noise-that-nobody-reads rather than a guard. -----------------------------------------
echo "D. synthetic must-PASS (the rule stays quiet)"
D="$TMP_ROOT/d"; mkdir -p "$D"

cat > "$D/mktemp_bare.sh" <<'EOF'
run() {
  local d
  d=$(mktemp -d)
  rm -rf "$d/scratch"
  git -C "$d" commit -m x
}
EOF
ck; n=$(scan_sites "$D/mktemp_bare.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "a bare mktemp -d root is not reported" \
  || fail "false positive on a bare mktemp -d root (SITES=${n:-unset})"

cat > "$D/wrapper_oneline.sh" <<'EOF'
newroot() { local d; d=$(mktemp -d); echo "$d"; }
run() {
  R=$(newroot)
  rm -rf "$R/scratch"
}
EOF
ck; n=$(scan_sites "$D/wrapper_oneline.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "a ONE-LINE mktemp wrapper resolves (the range(hi,lo,-1) regression)" \
  || fail "one-line wrapper not resolved (SITES=${n:-unset}) -- the empty-range bug is back"

cat > "$D/guarded_positional.sh" <<'EOF'
assert_fixture_dir() {
  case "${1-}" in
    "") exit 2 ;;
    /*) : ;;
    *)  exit 2 ;;
  esac
}
run() {
  local root="$1"
  assert_fixture_dir "$root"
  rm -rf "$root/scratch"
}
EOF
ck; n=$(scan_sites "$D/guarded_positional.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "an assert_fixture_dir on the operand clears the site" \
  || fail "false positive despite an assertion on the operand (SITES=${n:-unset})"

cat > "$D/ci_sink.sh" <<'EOF'
emit() {
  echo "key=value" >> "$GITHUB_OUTPUT"
  echo "## summary" >> "$GITHUB_STEP_SUMMARY"
}
EOF
ck; n=$(scan_sites "$D/ci_sink.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "CI plumbing sinks are excluded by name" \
  || fail "false positive on CI plumbing sinks (SITES=${n:-unset})"

# --- E. The two resolver bugs that made sites look SAFE. Both are pinned in the FAIL direction. ----
echo "E. resolver regressions (both were false-NEGATIVE bugs)"
E="$TMP_ROOT/e"; mkdir -p "$E"

# A path-bearing mktemp TEMPLATE inherits its prefix exactly as -p does. Classifying it absolute
# silently cleared 114 rm -rf and 153 redirect sites.
cat > "$E/template_inherits.sh" <<'EOF'
run() {
  local root="$1"
  D=$(mktemp -d "$root/case.XXXXXX")
  rm -rf "$D/scratch"
}
EOF
ck; n=$(scan_sites "$E/template_inherits.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a path-bearing mktemp template is NOT treated as absolute" \
  || fail "mktemp -d \"\$root/c.XXXXXX\" read as absolute (SITES=${n:-unset}) -- inheritance bug is back"

cat > "$E/mktemp_p_inherits.sh" <<'EOF'
run() {
  local root="$1"
  D=$(mktemp -d -p "$root")
  rm -rf "$D/scratch"
}
EOF
ck; n=$(scan_sites "$E/mktemp_p_inherits.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "mktemp -d -p \$root is NOT treated as absolute" \
  || fail "mktemp -p read as absolute (SITES=${n:-unset})"

# --- F. P1a is untouched by this rule (#7708 freezes scan_operand) ---------------------------------
echo "F. P1a isolation"
ck; P1A_BASE="$SCRIPT_DIR/fixture-dir-operand-assert.baseline.txt"
P1A_ACK=$(grep -vE '^#|^[[:space:]]*$' "$P1A_BASE" | awk -F'\t' '{s+=$1} END {print s+0}')
P1A_LIVE=$(python3 "$SCANNER" --rule operand --repo "$REPO_ROOT" 2>/dev/null | sed -n 's/^SITES=//p')
if [[ "${P1A_LIVE:-unset}" != "$P1A_ACK" ]]; then
  fail "P1a moved: live=${P1A_LIVE:-unset} baseline=$P1A_ACK -- this rule must not change scan_operand"
else
  pass "P1a still equals its own baseline ($P1A_ACK)"
fi

ck; if python3 "$SCANNER" --rule bogus --repo "$REPO_ROOT" >/dev/null 2>&1; then
  fail "an unknown --rule was accepted; the rule-validation tuple is not enforcing"
else
  pass "an unknown --rule is rejected"
fi

# --- L. The ledger arm. Drives fail() rather than reading it. --------------------------------------
echo "L. verdict accounting"
ck; _p0=$passes; _f0=$fails; _lines0=$(wc -l < "$VERDICT_LOG")
fail "SELF-TEST (expected; retracted immediately)"
_moved_f=$((fails - _f0)); _moved_p=$((passes - _p0))
_lines1=$(wc -l < "$VERDICT_LOG")
# undo the self-test in BOTH the counters and the ledger
fails=$_f0
sed -i '$d' "$VERDICT_LOG"
if [[ "$_moved_f" -eq 1 && "$_moved_p" -eq 0 && $((_lines1 - _lines0)) -eq 1 ]]; then
  pass "fail() moves fails and only fails, and appends exactly one ledger row"
else
  echo "  FAIL: fail() accounting is wrong (fails+=$_moved_f passes+=$_moved_p ledger+=$((_lines1 - _lines0)))"
  fails=$((fails + 1)); echo "FAIL" >> "$VERDICT_LOG"
fi

# Reconcile the append-only ledger against BOTH counters before trusting either.
LEDGER_PASS=$(grep -c '^PASS$' "$VERDICT_LOG" || true)
LEDGER_FAIL=$(grep -c '^FAIL$' "$VERDICT_LOG" || true)
if [[ "$LEDGER_PASS" -ne "$passes" || "$LEDGER_FAIL" -ne "$fails" ]]; then
  echo "FATAL: ledger disagrees with counters (ledger P/F = $LEDGER_PASS/$LEDGER_FAIL; counters = $passes/$fails)" >&2
  exit 2
fi
if [[ $((passes + fails)) -ne "$asserted" ]]; then
  echo "FATAL: verdicts ($((passes + fails))) != assertions counted ($asserted)" >&2
  exit 2
fi

MIN_ASSERTIONS=16
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $asserted assertions executed, floor is $MIN_ASSERTIONS -- arms were removed" >&2
  exit 2
fi

echo
echo "fixture-relative-assert.test.sh: $passes passed, $fails failed, $asserted assertion(s) executed (floor $MIN_ASSERTIONS)"
[[ "$fails" -eq 0 ]] || exit 1
exit 0
