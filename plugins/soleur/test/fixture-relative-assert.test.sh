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
# MUTATION MATRIX (Guard 1, #7708) -- executed in place against a pristine backup, with a GREEN
# unmutated control required first. Re-run in full after each review round. Observed:
#   control  unmutated                                            GREEN  46/46
#   R1       delete a verb family from the P1b assembly           RED
#   R3       rule function returns no rows at all                 RED
#   R5       narrow the corpus glob *.sh -> *.test.sh             RED    (FILES floor)
#   R7       re-widen the guard set with an emptiness-only form   RED    (section C2)
#   R8       unbound the guard window back to line 0              RED    (section C3)
#   R9       re-classify `-t` as a destination flag               RED    (the 783-row FP flood)
#   R10      widen _ROOT_SAFE with call-unresolved                RED    (section C9)
#   H1       neuter the failure counter                           RED    rc=2, ledger reconciliation
#   H4       point arm A at the baseline instead of live data     RED    (the independent-totals arm)
#
# H4 is the row that matters most: before the round-2 corrections it survived GREEN at 32/32.
# Section B proved `compare_rows` WORKS; nothing proved arm A calls it with LIVE data, so one
# argument swap turned the ratchet off while every arm stayed green.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCANNER="$SCRIPT_DIR/lib/fixture-scan.py"
BASELINE="$SCRIPT_DIR/fixture-relative-assert.baseline.txt"

# This suite is itself a tracked *.sh file, so it appears in the corpus it scans. `$(cd X && pwd)`
# prints an absolute path but yields EMPTY when the cd fails, which would root $BASELINE at `/`.
# Dogfooding the rule rather than baselining its author.
case "$SCRIPT_DIR" in
  "")      echo "FATAL: SCRIPT_DIR is empty; writes below would retarget" >&2; exit 2 ;;
  /|//|/.) echo "FATAL: SCRIPT_DIR resolves to the filesystem root; refusing" >&2; exit 2 ;;
  /*)      : ;;
  *)       echo "FATAL: SCRIPT_DIR is RELATIVE; refusing" >&2; exit 2 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }
[[ -f "$SCANNER" ]] || { echo "FATAL: scanner missing at $SCANNER" >&2; exit 2; }

if [[ "${1:-}" == "--write-baseline" ]]; then
  hdr="$(mktemp)" || exit 2
  grep -E '^#|^[[:space:]]*$' "$BASELINE" > "$hdr"
  # Refuse to write from a failed or truncated scan. Without this, a scanner that raised wrote a
  # HEADER-ONLY baseline and exited 0 -- destroying the ratchet through the exact recovery path
  # arm A's own failure message recommends.
  _wb="$(mktemp)" || exit 2
  if ! python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" > "$_wb" 2>&1; then
    echo "FATAL: scan failed; baseline NOT rewritten" >&2; sed 's/^/  /' "$_wb" >&2; exit 2
  fi
  _wf=$(sed -n 's/^FILES=//p' "$_wb"); _wr=$(grep -c 'operand not provably absolute' "$_wb" || true)
  if [[ -z "$_wf" || "$_wf" -lt 900 || "$_wr" -lt 1 ]]; then
    echo "FATAL: scan looks wrong (FILES=${_wf:-unset}, rows=$_wr); baseline NOT rewritten" >&2; exit 2
  fi
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

# A missing SITES= line is a SCANNER failure, not a rule verdict. Discarding stderr and rc made a
# transient failure byte-indistinguishable from mutation R3 ("rule returns no rows"), and the arms
# then reported it as "guard set widened unsoundly" -- a confident claim about code that never ran.
# Held in a variable so the literal pattern never appears in this file's own source: this suite is
# a tracked *.sh scanned by the rule it tests, and printf-built fixtures (unlike heredoc-built
# ones, whose bodies the scanner skips) would otherwise inject rows into the corpus it measures.
_RMRF="rm -rf"

scan_sites() {
  local _o _rc
  _o=$(python3 "$SCANNER" --rule relative "$@" 2>"$TMP_ROOT/scan.err"); _rc=$?
  local _n; _n=$(printf '%s\n' "$_o" | sed -n 's/^SITES=//p')
  if [[ "$_rc" -ne 0 || -z "$_n" ]]; then
    echo "FATAL: scanner did not report SITES for $* (rc=$_rc)" >&2
    sed 's/^/       /' "$TMP_ROOT/scan.err" >&2
    exit 2
  fi
  printf '%s\n' "$_n"
}

# --- A. The live corpus against the shrink-only baseline ------------------------------------------
echo "A. live corpus vs baseline"

# ONE scan of the corpus, reused by every arm below. The scanner walks 930 files and resolves
# binding chains through wrappers and sourced helpers, so a scan is seconds, not milliseconds.
SCAN_OUT="$TMP_ROOT/scan.txt"
python3 "$SCANNER" --rule relative --repo "$REPO_ROOT" > "$SCAN_OUT" 2>/dev/null

ck; FILES_SCANNED=$(sed -n 's/^FILES=//p' "$SCAN_OUT")
# A corpus floor, not just a site floor. Narrowing the glob to one app directory drops ~680 of the
# tracked files and would leave every site-count arm below green while coverage collapsed.
if [[ -z "${FILES_SCANNED:-}" || "$FILES_SCANNED" -lt 900 ]]; then
  fail "corpus floor: FILES=${FILES_SCANNED:-unset}, want >= 900 (measured 930)"
else
  pass "corpus floor: FILES=$FILES_SCANNED >= 900"
fi

# The comparison is ROW BY ROW. Enforcing only the SUM is direction-blind on the row axis: a
# compensating edit (one file 19 -> 0, another +19) conserves the total and passes. That is the
# same defect the verdict ledger exists to fix for passes/fails, and it was left in the artifact
# that actually holds the ratchet. Measured: a 19-site swing on a real file was invisible.
live_rows() {
  grep 'operand not provably absolute' "$SCAN_OUT" \
    | sed -E 's/^([^:]+):.*/\1/' | sort | uniq -c | awk '{printf "%s\t%s\n", $1, $2}' | LC_ALL=C sort -k2
}
baseline_rows() { grep -vE '^#|^[[:space:]]*$' "$BASELINE" | LC_ALL=C sort -k2; }

# Extracted so section B can DRIVE it rather than reason about a proxy.
compare_rows() { diff <(baseline_rows) <(printf '%s\n' "$1" | sed '/^$/d'); }

ck; LIVE_ROWS=$(live_rows)
ACK_TOTAL=$(baseline_rows | awk -F'\t' '{s+=$1} END {print s+0}')
SITES_LIVE=$(sed -n 's/^SITES=//p' "$SCAN_OUT")
if ! ROWDIFF=$(compare_rows "$LIVE_ROWS"); then
  fail "baseline rows differ from live (regenerate with --write-baseline in the same commit as the fix):"
  printf '%s\n' "$ROWDIFF" | head -12 | sed 's/^/      /'
else
  pass "every baseline row matches live, row by row ($ACK_TOTAL sites over $(baseline_rows | wc -l | tr -d ' ') files)"
fi

# The git -C family must remain SCANNED. Deleting it from _REL_FAMILIES would drop its rows and
# a sum-based arm would read that as progress; the row diff above catches the row loss, and this
# arm names the family so the failure says which one vanished.
ck; GITC=$(grep -c '(git-C,' "$SCAN_OUT")
if [[ "$GITC" -lt 1 ]]; then
  fail "git -C family reports 0 sites -- it was dropped from _REL_FAMILIES, not fixed"
else
  pass "git -C family is still scanned ($GITC sites)"
fi

echo "  (corpus: ${FILES_SCANNED} files, ${SITES_LIVE} sites)"

# --- B. The ratchet is enforced, not merely documented --------------------------------------------
echo "B. ratchet enforcement"
# This arm used to build a synthetic +1 file and assert arithmetic on it, never touching the
# comparison it claimed to police. Measured: disable the comparison and introduce real row drift
# and section B stayed GREEN. It now DRIVES compare_rows, the way row L drives fail().
ck; B_DRIFTED=$(printf '%s\n' "$LIVE_ROWS" | awk -F'\t' 'NR==1{printf "%s\t%s\n", ($1+1), $2; next} {print}')
if compare_rows "$B_DRIFTED" >/dev/null 2>&1; then
  fail "compare_rows accepted a drifted row set -- the ratchet does not enforce"
else
  pass "compare_rows rejects a drifted row set (driven, not asserted about)"
fi

# Fed the BASELINE's own rows, not the live ones: this arm must prove compare_rows is not simply
# always-RED, and it must do so independently of whether the baseline is currently in sync (that
# is arm A's job, and duplicating it here makes one failure print twice).
# Independent of compare_rows entirely. Section B proves the FUNCTION works; it did not prove arm
# A calls it with LIVE data, and swapping arm A's argument to baseline_rows left the ratchet off at
# 32/32 green. These two totals come from different pipelines and must agree.
ck; _live_sum=$(printf '%s\n' "$LIVE_ROWS" | awk -F'\t' '{s+=$1} END {print s+0}')
_live_rows=$(printf '%s\n' "$LIVE_ROWS" | sed '/^$/d' | wc -l | tr -d ' ')
_base_rows=$(baseline_rows | wc -l | tr -d ' ')
if [[ "$_live_sum" != "$ACK_TOTAL" || "$_live_rows" != "$_base_rows" ]]; then
  fail "live totals disagree with the baseline: sites $_live_sum vs $ACK_TOTAL, rows $_live_rows vs $_base_rows"
else
  pass "live site total and row count both equal the baseline ($ACK_TOTAL over $_base_rows rows)"
fi

ck; if compare_rows "$(baseline_rows)" >/dev/null 2>&1; then
  pass "compare_rows accepts an identical row set (the arm is not simply always-RED)"
else
  fail "compare_rows rejected a row set identical to the baseline -- the comparison is broken"
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

# --- C2. THE GUARD AXIS. A widening that silences is the failure mode this rule is most exposed
#         to, and section D pins only the ROOT axis. Each row below is a guard that proves
#         NON-EMPTINESS and nothing about relativity; each must leave the site REPORTED.
#         Measured before this section existed: all four cleared it, 355 live rows among them.
echo "C2. weak guards must NOT clear a relativity finding"
C2="$TMP_ROOT/c2"; mkdir -p "$C2"
_weak_guard_case() {
  printf '#!/usr/bin/env bash\nsetup() {\n  local d="$1/repo"\n  %s\n  %s "$d"\n}\n' "$2" "$_RMRF" > "$C2/$1.sh"
  ck; n=$(scan_sites "$C2/$1.sh")
  if [[ "${n:-0}" -ge 1 ]]; then
    pass "weak guard [$2] does not clear a relative site"
  else
    fail "weak guard [$2] SILENCED a relative site (SITES=${n:-unset}) -- guard set widened unsoundly"
  fi
}
_weak_guard_case colonq ': "${d:?fixture dir is <empty>}"'
_weak_guard_case dashn  '[[ -n "$d" ]] || return 1'
_weak_guard_case noabort '[[ -f "$d" ]] && echo found'
_weak_guard_case catchall 'case "$d" in *) : ;; esac'
_weak_guard_case mkdirp 'mkdir -p "$d" || exit 1'

# The two sound spellings must still clear, or the arm above is just "reject everything".
cat > "$C2/sound_assert.sh" <<'EOF'
setup() {
  local d="$1/repo"
  assert_fixture_dir "$d"
  rm -rf "$d"
}
EOF
ck; n=$(scan_sites "$C2/sound_assert.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "assert_fixture_dir (which refuses relative) still clears" \
  || fail "a SOUND guard no longer clears (SITES=${n:-unset}) -- the set is now reject-everything"

cat > "$C2/sound_case.sh" <<'EOF'
setup() {
  local d="$1/repo"
  case "$d" in
    "") exit 2 ;;
    /*) : ;;
    *)  exit 2 ;;
  esac
  rm -rf "$d"
}
EOF
# The inline `case` form was REMOVED from the recognised set: it was defeated four ways (an extra
# allow-arm, `exit` inside a double-quoted message, a catch-all before `/*)`, and an ignored return
# code). It must now REPORT, or the removal did not take.
ck; n=$(scan_sites "$C2/sound_case.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "an inline case guard is NOT recognised (removed: silenceable four ways)" \
  || fail "an inline case still clears a site (SITES=${n:-unset}) -- the heuristic is back"

# --- C3. THE WINDOW. A guard must be correlated to the site, not merely present in the file.
echo "C3. guard window is bounded and code-only"
C3="$TMP_ROOT/c3"; mkdir -p "$C3"
cat > "$C3/other_function.sh" <<'EOF'
check_mode() {
  local d="$1"
  assert_fixture_dir "$d"
}
setup() {
  local d="$1/repo"
  rm -rf "$d"
}
EOF
ck; n=$(scan_sites "$C3/other_function.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a guard in a DIFFERENT function does not clear this site" \
  || fail "cross-function silencing (SITES=${n:-unset}) -- the window is unbounded again"

cat > "$C3/quoted_token.sh" <<'EOF'
banner() {
  echo 'TODO: assert_fixture_dir "$d" was removed, restore it'
}
setup() {
  local d="$1/repo"
  rm -rf "$d"
}
EOF
ck; n=$(scan_sites "$C3/quoted_token.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "the assertion NAME inside a quoted string does not clear a site" \
  || fail "name-token silencing (SITES=${n:-unset}) -- the cdx() gap this scanner replaces"

# --- C4. The residue sub-classes the baseline header names. Section C pins positionals; these
#         pin the other two, so widening _ROOT_SAFE to swallow either is caught HERE and not only
#         by a count arm whose message tells the reader to regenerate.
echo "C4. residue sub-classes"
C4="$TMP_ROOT/c4"; mkdir -p "$C4"
cat > "$C4/never_bound.sh" <<'EOF'
cleanup() {
  rm -rf "$SCRATCH_ROOT/x"
}
EOF
ck; n=$(scan_sites "$C4/never_bound.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a never-bound global is reported" \
  || fail "never-bound global was cleared (SITES=${n:-unset})"

cat > "$C4/use_precedes_binding.sh" <<'EOF'
reset() {
  rm -rf "$WORK"
  WORK=$(mktemp -d)
}
EOF
ck; n=$(scan_sites "$C4/use_precedes_binding.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a use that PRECEDES its binding is reported" \
  || fail "use-before-binding was cleared by a later rebind (SITES=${n:-unset})"

# --- C5. The guard WINDOW. The top-level-guard widening was REMOVED; a guard outside the enclosing
#         function must never clear a use inside it. Both bypasses that killed the widening are
#         pinned here so re-adding it reddens.
echo "C5. a guard outside the enclosing function does not clear"
C5="$TMP_ROOT/c5"; mkdir -p "$C5"
cat > "$C5/helper_mutates.sh" <<'EOF'
ROOT=/abs/fixtures
assert_fixture_dir "$ROOT"
pick_target() { ROOT=$(cat target.txt); }
purge() {
  pick_target
  rm -rf "$ROOT/objects"
}
EOF
ck; n=$(scan_sites "$C5/helper_mutates.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a helper that mutates the global does not inherit the top-level guard" \
  || fail "helper-call mutation cleared by a stale top-level guard (SITES=${n:-unset})"

cat > "$C5/eval_rebind.sh" <<'EOF'
ROOT=$(cat cfg.txt)
assert_fixture_dir "$ROOT"
purge() {
  eval "ROOT=$(cat rel.txt)"
  rm -rf "$ROOT/objects"
}
EOF
ck; n=$(scan_sites "$C5/eval_rebind.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "an eval rebind does not inherit the top-level guard" \
  || fail "eval rebind cleared by a stale top-level guard (SITES=${n:-unset})"

# --- C6. `<<<` is a HERESTRING. Reading it as a heredoc opener made every following line count as
#         heredoc BODY, and both rules skipped it -- measured, 299 lines across 6 files.
echo "C6. a herestring does not blank the rest of the file"
C6="$TMP_ROOT/c6"; mkdir -p "$C6"
cat > "$C6/herestring.sh" <<'EOF'
run() {
  local d="$1/repo"
  grep -q x <<< "some text"
  rm -rf "$d"
}
EOF
ck; n=$(scan_sites "$C6/herestring.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a site AFTER a <<< herestring is still scanned" \
  || fail "a <<< herestring blanked the rest of the file (SITES=${n:-unset})"

cat > "$C6/real_heredoc.sh" <<'EOF'
run() {
  cat <<INNER
  rm -rf "$1/repo"
INNER
}
EOF
ck; n=$(scan_sites "$C6/real_heredoc.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "a real heredoc BODY is still skipped" \
  || fail "heredoc bodies are being scanned as code (SITES=${n:-unset})"

# --- C7. Wrapper resolution. Each row was a live FALSE NEGATIVE: the wrapper was credited with an
#         absolute root it does not produce.
echo "C7. wrapper roots are read correctly"
C7="$TMP_ROOT/c7"; mkdir -p "$C7"
cat > "$C7/quoted_template.sh" <<'EOF'
new_fx() { local base="$1"; mktemp -d "$base/fx.XXXXXX"; }
run() { local d; d=$(new_fx "$2"); rm -rf "$d/x"; }
EOF
ck; n=$(scan_sites "$C7/quoted_template.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a QUOTED path-bearing template is not read as absolute" \
  || fail "quoted template read as absolute (SITES=${n:-unset}) -- the two code paths disagree again"

cat > "$C7/last_is_assign.sh" <<'EOF'
mk() { cd relroot || return 1; d=$(mktemp -d); }
W=$(mk)
rm -rf "$W/objects"
EOF
ck; n=$(scan_sites "$C7/last_is_assign.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a wrapper whose mktemp output never reaches stdout is not credited" \
  || fail "wrapper emitting nothing read as mktemp-rooted (SITES=${n:-unset})"

cat > "$C7/comment_brace.sh" <<'EOF'
mk_rel() {
  # dir layout { see docs
  printf %s relroot
}
mk_abs() { local t; t=$(mktemp -d); echo "$t"; }
run() { local d; d=$(mk_rel); rm -rf "$d/x"; }
EOF
ck; n=$(scan_sites "$C7/comment_brace.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a brace inside a COMMENT does not run a function body to EOF" \
  || fail "comment brace extended the body and imported a later mktemp (SITES=${n:-unset})"

cat > "$C7/heredoc_brace.sh" <<'EOF'
mk_rel() {
  cat <<SH
{ nested
SH
  printf %s relroot
}
mk_abs() { local t; t=$(mktemp -d); echo "$t"; }
run() { local d; d=$(mk_rel); rm -rf "$d/x"; }
EOF
ck; n=$(scan_sites "$C7/heredoc_brace.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a brace inside a HEREDOC body does not run a function body to EOF" \
  || fail "heredoc brace extended the body and imported a later mktemp (SITES=${n:-unset})"

# --- C8. False-positive controls. A guard that reports everything is not read, and 46% of an
#         earlier revision of this baseline was noise of exactly these two shapes.
echo "C8. resolvable roots are NOT reported"
C8="$TMP_ROOT/c8"; mkdir -p "$C8"
cat > "$C8/three_hop.sh" <<'EOF'
export TMPDIR="${TMPDIR:-/var/tmp}"
ROOT=$(mktemp -d -t legal.XXXXXXXX) || exit 2
run() { d=$(mktemp -d "$ROOT/case-XXXXXXXX") || return 1; rm -rf "$d/x"; }
EOF
ck; n=$(scan_sites "$C8/three_hop.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "an inheriting mktemp whose PREFIX resolves absolute is not reported" \
  || fail "false positive: resolvable three-hop root reported (SITES=${n:-unset})"

cat > "$C8/redir_tok.sh" <<'EOF'
run() { t=$(mktemp 2>/dev/null); : > "$t"; }
EOF
ck; n=$(scan_sites "$C8/redir_tok.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "a redirection token is not mistaken for a template" \
  || fail "false positive: 2>/dev/null read as a template (SITES=${n:-unset})"

cat > "$C8/apostrophe.sh" <<'EOF'
run() {
  local d="$1/repo"
  echo "it's the fixture root"
  assert_fixture_dir "$d"
  echo "that's checked"
  rm -rf "$d"
}
EOF
ck; n=$(scan_sites "$C8/apostrophe.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "apostrophes in prose do not blank a real guard between them" \
  || fail "false positive: apostrophe pairing erased a guard (SITES=${n:-unset})"

# --- C9. The two residue root classes with no must-FAIL arm. 101 live sites could be silenced by
#         adding either to _ROOT_SAFE, reddening ONLY the arm that says "regenerate".
echo "C9. unpinned root classes"
C9="$TMP_ROOT/c9"; mkdir -p "$C9"
cat > "$C9/call_unresolved.sh" <<'EOF'
run() {
  local d
  d=$(some_helper_defined_elsewhere)
  rm -rf "$d/x"
}
EOF
ck; n=$(scan_sites "$C9/call_unresolved.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "an unresolvable wrapper call is reported" \
  || fail "call-unresolved was cleared (SITES=${n:-unset}) -- _ROOT_SAFE widened"

cat > "$C9/other_cmdsubst.sh" <<'EOF'
run() {
  local d
  d=$(git rev-parse --show-toplevel)
  rm -rf "$d/x"
}
EOF
ck; n=$(scan_sites "$C9/other_cmdsubst.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "an unrecognised command substitution root is reported" \
  || fail "other-cmdsubst was cleared (SITES=${n:-unset}) -- _ROOT_SAFE widened"

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

# NOTE: this fixture CALLS assert_fixture_dir but deliberately does not DEFINE it. The fixture is
# only ever scanned, never executed, so a body is unnecessary — and the sibling P1a suite asserts
# byte-equality across every tracked copy of that function, which a simplified copy here would
# break. The rule keys on the call, so the call is all this fixture needs.
cat > "$D/guarded_positional.sh" <<'EOF'
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

cat > "$D/same_line_binding.sh" <<'EOF'
run() {
  local T
  T=$(mktemp -d)
  L="$T/log"; : > "$L"
}
EOF
ck; n=$(scan_sites "$D/same_line_binding.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "a binding on the SAME line as the use resolves" \
  || fail "same-line binding read as never-bound (SITES=${n:-unset}) -- false positive"

# ...but the inclusive retry must not let an assignment resolve to ITSELF.
cat > "$D/self_reference.sh" <<'EOF'
run() {
  local r="$1"
  X="$X/sub"; : > "$X"
}
EOF
ck; n=$(scan_sites "$D/self_reference.sh"); [[ "${n:-0}" -ge 1 ]] \
  && pass "a self-referential binding does not resolve to itself" \
  || fail "X=\"\$X/sub\" resolved to itself (SITES=${n:-unset}) -- the inclusive retry is too loose"

cat > "$D/noncanonical_pass.sh" <<'EOF'
run() {
  local d
  d=$(mktemp -d) || return 1
  rm -rf "$d/scratch"
  echo x > "$d/out"
}
EOF
ck; n=$(scan_sites "$D/noncanonical_pass.sh"); [[ "${n:-1}" -eq 0 ]] \
  && pass "non-canonical must-PASS: a mktemp-rooted binding stays quiet (the || return 1 is incidental)" \
  || fail "false positive on a permitted binding+guard combination (SITES=${n:-unset})"

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

MIN_ASSERTIONS=46
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FATAL: only $asserted assertions executed, floor is $MIN_ASSERTIONS -- arms were removed" >&2
  exit 2
fi

echo
echo "fixture-relative-assert.test.sh: $passes passed, $fails failed, $asserted assertion(s) executed (floor $MIN_ASSERTIONS)"
# The ledger is APPEND-ONLY and is the authority. Reading `$fails` here re-read a mutable counter
# AFTER every reconciliation had already passed, so a single line inserted between them retracted
# real failures and the suite exited 0 while printing FAIL. That is the predecessor's symptom line
# for line; the reconciliations above are necessary but they are not the gate.
LEDGER_FAIL_FINAL=$(grep -c '^FAIL$' "$VERDICT_LOG" || true)
[[ "$LEDGER_FAIL_FINAL" -eq 0 && "$fails" -eq 0 ]] || exit 1
exit 0
