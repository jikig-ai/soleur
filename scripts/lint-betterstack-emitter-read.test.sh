#!/usr/bin/env bash
# Mutation battery for scripts/lint-betterstack-emitter-read.sh (#8875) — the NON-VACUITY
# core. Drives the ACTUAL guard (never a re-implementation) over git-init'd mktemp fixture
# trees, asserting BOTH directions so every check can fail:
#
#   GREEN-EMITTER    jq select(.SYSLOG_IDENTIFIER == ...) reader          -> exit 0
#   GREEN-SOURCED    reader sourcing scripts/lib/bs-emitter-row.sh        -> exit 0
#   GREEN-ALLOW      raw --grep reader with a reasoned allowlist entry    -> exit 0
#   RED-UNCLASSIFIED raw --grep reader, empty allowlist                   -> exit 1, names the file
#   RED-COMMENT-DEF  def name lives only in a comment                     -> exit 1 (the strip is load-bearing)
#   RED-STALE        allowlist entry whose file no longer invokes         -> exit 1 STALE
#   RED-STALE-COMMENT allowlisted file whose only reference is a comment  -> exit 1 STALE
#   RED-BARE-REASON  allowlist entry with an empty reason                 -> exit 1 BARE-REASON
#   RED-SEAM         a file reaching the transport via bs_absence_query_script
#                    (never names betterstack-query.sh)                    -> exit 1 UNCLASSIFIED
#   GREEN-SEAM       the same file allowlisted                            -> exit 0
#   COMMENT-ONLY     .ts `//` + .sh `#` mentions                          -> exit 0 (mention != invocation)
#   DISPATCH-DISC    guard COPY with the discovery needle neutered        -> exit 0 over a RED fixture
#   DISPATCH-CLASS   guard COPY with the emitter classifier neutered      -> exit 1 over a GREEN fixture
#   MUST-FIND        copy-in-fixture "production" run missing a member    -> exit 1 MUST-FIND-MISSING
#   MUST-FIND-OK     fixture carrying every member (allowlisted)          -> exit 0
#   FLOOR            EMITTER_READ_MIN_POP above the live count            -> exit 2, [FATAL] diagnostic
#   EMPTY            an empty fixture tree                                -> exit 0 (floor is prod-keyed)
#   LIVE             the real tree, no args                               -> exit 0, population >= floor
#
# Fixture trees are REAL git repos (`git init` + `git add`) because the guard's producer is
# `git ls-files` — the discovery mechanism under test is the production one, not a stub.
# The allowlist seam (EMITTER_READ_ALLOW_FILE, tab-separated `path<TAB>reason` per line)
# replaces the embedded map per fixture so each row controls its own exemptions.
#
# ADR-193 accounting: `n_checks` moves at the ONE call site (check()), never inside
# pass()/fail(); conservation and the MIN_CHECKS floor are reported with printf + exit 1,
# never through the verdict helpers.
#
# Tempfile ownership (satisfies lint-trap-tempfile-ownership rule (c)): the trap owns ONLY
# the mktemp dir this script created.

set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

SANDBOX="$(mktemp -d -t emitter-read-test.XXXXXXXX)" || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/lint-betterstack-emitter-read.sh"

passes=0
fails=0
n_checks=0
declare -a FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok  %s\n' "$1"; }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf '  FAIL %s\n' "$1" >&2; }
# check <0|nonzero> <pass-msg> <fail-msg> — the ONE call site of pass()/fail().
check() { n_checks=$((n_checks + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$3"; fi; }

# Instrument self-test: drive both arms, require all three counters to move, reset.
check 0 "instrument self-test (pass arm)" "instrument self-test pass arm did not pass"
check 1 "" "instrument self-test (fail arm)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 || "$n_checks" -ne 2 ]]; then
  printf '[FATAL] instrument self-test: passes=%s fails=%s n_checks=%s\n' "$passes" "$fails" "$n_checks" >&2
  exit 1
fi
passes=0; fails=0; n_checks=0; FAILURES=()

printf '%s\n' "lint-betterstack-emitter-read.test.sh: mutation battery over fixture git trees"

# mk_tree <name> -> prints the fixture root (a git repo whose ls-files = `git add -A` output)
mk_tree() {
  local t="$SANDBOX/$1"
  mkdir -p "$t"
  git -C "$t" init -q >/dev/null 2>&1
  printf '%s' "$t"
}
seed() { git -C "$1" add -A >/dev/null 2>&1; }

EMPTY_ALLOW="$SANDBOX/empty.allow"
: > "$EMPTY_ALLOW"

# write_allow <file> <path> <reason> — appends one tab-separated entry
write_allow() { printf '%s\t%s\n' "$2" "$3" >> "$1"; }

# run_guard <tree> [allowfile] [guardbin] — sets GUARD_RC / GUARD_OUT. The third arg exists
# so the DISPATCH rows can run a mutated COPY of the guard without re-implementing the seam.
run_guard() {
  GUARD_OUT="$(EMITTER_READ_ALLOW_FILE="${2:-$EMPTY_ALLOW}" bash "${3:-$GUARD}" "$1" 2>&1)"
  GUARD_RC=$?
}

contains() { # $1 = needle, $2 = haystack (default GUARD_OUT)
  [[ "${2:-$GUARD_OUT}" == *"$1"* ]]
}

# --- GREEN-EMITTER: a jq field-select reader --------------------------------------------
T="$(mk_tree green_emitter)"
mkdir -p "$T/scripts"
cat > "$T/scripts/reader.sh" <<'EOF'
#!/usr/bin/env bash
rows="$(bash scripts/betterstack-query.sh --since 1h --grep MARKER \
  | jq -r '.raw | fromjson | select(.SYSLOG_IDENTIFIER == "my-emitter") | .message')"
EOF
seed "$T"
run_guard "$T"
(( GUARD_RC == 0 )); check $? "GREEN-EMITTER jq field-select reader -> exit 0" "GREEN-EMITTER expected exit 0, got $GUARD_RC: $GUARD_OUT"
contains 'OK-EMITTER scripts/reader.sh'; check $? "GREEN-EMITTER verdict is OK-EMITTER" "GREEN-EMITTER missing OK-EMITTER verdict: $GUARD_OUT"

# --- GREEN-SOURCED: a reader that sources the emitter-def lib ---------------------------
T="$(mk_tree green_sourced)"
mkdir -p "$T/scripts/lib"
cat > "$T/scripts/reader.sh" <<'EOF'
#!/usr/bin/env bash
_ber_lib="${BS_EMITTER_ROW_LIB:-scripts/lib/bs-emitter-row.sh}"
source "$_ber_lib" || exit 2
rows="$(bash scripts/betterstack-query.sh --since 1h --grep MARKER \
  | jq -r "$BS_EMITTER_ROW_JQ"' .raw | fromjson | select(bs_emitter_row("my-emitter")) | .message')"
EOF
seed "$T"
run_guard "$T"
(( GUARD_RC == 0 )); check $? "GREEN-SOURCED sourced-def reader -> exit 0" "GREEN-SOURCED expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- GREEN-ALLOW: a raw reader carrying a reasoned allowlist entry -----------------------
T="$(mk_tree green_allow)"
mkdir -p "$T/scripts"
cat > "$T/scripts/hinty.sh" <<'EOF'
#!/usr/bin/env bash
echo "reproduce: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep MARKER"
EOF
ALLOWF="$SANDBOX/green-allow.txt"
write_allow "$ALLOWF" "scripts/hinty.sh" "hint-only: operator-facing recipe text"
seed "$T"
run_guard "$T" "$ALLOWF"
(( GUARD_RC == 0 )); check $? "GREEN-ALLOW reasoned allowlist entry -> exit 0" "GREEN-ALLOW expected exit 0, got $GUARD_RC: $GUARD_OUT"
contains 'OK-ALLOWLISTED scripts/hinty.sh'; check $? "GREEN-ALLOW verdict is OK-ALLOWLISTED" "GREEN-ALLOW missing OK-ALLOWLISTED verdict: $GUARD_OUT"

# --- RED-UNCLASSIFIED: a raw --grep reader, empty allowlist ------------------------------
T="$(mk_tree red_raw)"
mkdir -p "$T/scripts"
cat > "$T/scripts/raw-reader.sh" <<'EOF'
#!/usr/bin/env bash
rows="$(bash scripts/betterstack-query.sh --since 1h --grep MARKER | grep -c .)"
EOF
seed "$T"
run_guard "$T"
(( GUARD_RC == 1 )); check $? "RED-UNCLASSIFIED raw --grep reader -> exit 1" "RED-UNCLASSIFIED expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'UNCLASSIFIED scripts/raw-reader.sh'; check $? "RED-UNCLASSIFIED names the offender" "RED-UNCLASSIFIED did not name the file: $GUARD_OUT"

# --- RED-COMMENT-DEF: the def name only inside a comment is NOT a use --------------------
T="$(mk_tree red_comment_def)"
mkdir -p "$T/scripts"
cat > "$T/scripts/almost.sh" <<'EOF'
#!/usr/bin/env bash
# rows are graded with select(bs_emitter_row($e)) — or so a reader might claim
rows="$(bash scripts/betterstack-query.sh --since 1h --grep MARKER | grep -c .)"
EOF
seed "$T"
run_guard "$T"
(( GUARD_RC == 1 )); check $? "RED-COMMENT-DEF def named only in a comment -> exit 1" "RED-COMMENT-DEF expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'UNCLASSIFIED scripts/almost.sh'; check $? "RED-COMMENT-DEF names the offender" "RED-COMMENT-DEF did not name the file: $GUARD_OUT"

# --- RED-STALE: an allowlist entry whose file no longer invokes --------------------------
T="$(mk_tree red_stale)"
mkdir -p "$T/scripts"
cat > "$T/scripts/other.sh" <<'EOF'
#!/usr/bin/env bash
echo "nothing to do with the warehouse"
EOF
ALLOWF="$SANDBOX/stale.txt"
write_allow "$ALLOWF" "scripts/gone-reader.sh" "was a raw reader; the call site was removed"
seed "$T"
run_guard "$T" "$ALLOWF"
(( GUARD_RC == 1 )); check $? "RED-STALE dead allowlist entry -> exit 1" "RED-STALE expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'STALE scripts/gone-reader.sh'; check $? "RED-STALE names the entry" "RED-STALE did not name the entry: $GUARD_OUT"

# --- RED-STALE-COMMENT: an allowlisted file whose only reference is now a comment --------
T="$(mk_tree red_stale_comment)"
mkdir -p "$T/scripts"
cat > "$T/scripts/retired.sh" <<'EOF'
#!/usr/bin/env bash
# used to run: bash scripts/betterstack-query.sh --since 1h --grep MARKER
echo "retired"
EOF
ALLOWF="$SANDBOX/stale-comment.txt"
write_allow "$ALLOWF" "scripts/retired.sh" "was a reader"
seed "$T"
run_guard "$T" "$ALLOWF"
(( GUARD_RC == 1 )); check $? "RED-STALE-COMMENT comment-only allowlisted file -> exit 1" "RED-STALE-COMMENT expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'STALE scripts/retired.sh'; check $? "RED-STALE-COMMENT names the entry" "RED-STALE-COMMENT did not name the entry: $GUARD_OUT"

# --- RED-BARE-REASON: an allowlist entry carrying an empty reason ------------------------
T="$(mk_tree red_bare)"
mkdir -p "$T/scripts"
cat > "$T/scripts/raw.sh" <<'EOF'
#!/usr/bin/env bash
rows="$(bash scripts/betterstack-query.sh --since 1h --grep MARKER | grep -c .)"
EOF
ALLOWF="$SANDBOX/bare.txt"
write_allow "$ALLOWF" "scripts/raw.sh" ""
seed "$T"
run_guard "$T" "$ALLOWF"
(( GUARD_RC == 1 )); check $? "RED-BARE-REASON empty reason -> exit 1" "RED-BARE-REASON expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'BARE-REASON scripts/raw.sh'; check $? "RED-BARE-REASON names the entry" "RED-BARE-REASON did not name the entry: $GUARD_OUT"

# --- RED-SEAM: a file reaching the transport via the seam, never naming the script -------
T="$(mk_tree red_seam)"
mkdir -p "$T/scripts"
cat > "$T/scripts/seam-user.sh" <<'EOF'
#!/usr/bin/env bash
reader="$(bs_absence_query_script)"
out="$(bash "$reader" --since 1h --grep MARKER)"
EOF
seed "$T"
run_guard "$T"
(( GUARD_RC == 1 )); check $? "RED-SEAM seam-mediated reader -> exit 1 (seam IS discovery)" "RED-SEAM expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'UNCLASSIFIED scripts/seam-user.sh'; check $? "RED-SEAM names the offender" "RED-SEAM did not name the file: $GUARD_OUT"

# --- GREEN-SEAM: the same file allowlisted ----------------------------------------------
ALLOWF="$SANDBOX/seam.txt"
write_allow "$ALLOWF" "scripts/seam-user.sh" "transport-resolver consumer; selection lives in the caller's SQL"
run_guard "$T" "$ALLOWF"
(( GUARD_RC == 0 )); check $? "GREEN-SEAM allowlisted seam reader -> exit 0" "GREEN-SEAM expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- COMMENT-ONLY: .ts `//` and .sh `#` mentions never enter the population --------------
T="$(mk_tree comment_only)"
mkdir -p "$T/apps" "$T/scripts"
cat > "$T/apps/marker.ts" <<'EOF'
// Read back via `scripts/betterstack-query.sh --grep SOLEUR_X --since 1d`.
export const marker = "SOLEUR_X";
/* and in a block comment: betterstack-query.sh --grep OTHER */
EOF
cat > "$T/scripts/doc.sh" <<'EOF'
#!/usr/bin/env bash
# scripts/betterstack-query.sh --grep MARKER is the reproduce recipe
echo "ok"
EOF
seed "$T"
run_guard "$T"
(( GUARD_RC == 0 )); check $? "COMMENT-ONLY .ts// and .sh# mentions -> exit 0 (never discovered)" "COMMENT-ONLY expected exit 0, got $GUARD_RC: $GUARD_OUT"
contains 'clean (2 file(s) walked, 0 discovered'; check $? "COMMENT-ONLY reports 0 discovered" "COMMENT-ONLY discovery count wrong: $GUARD_OUT"

# --- DISPATCH-DISC: a guard COPY with the discovery needle neutered goes green over the
#     RED fixture — proving the grep is the mechanism and nothing else vouches for it. -----
MUT="$SANDBOX/guard-no-needle.sh"
# Assemble the sed expression without a literal doubled-angle token (the guard-vacuity-floor
# blanker treats it as a heredoc opener even in comments/strings).
sed 's|grep -E -- "\$INV_NAME" "\$WORK/code"|true|' "$GUARD" > "$MUT"
if cmp -s "$GUARD" "$MUT"; then
  check 1 "" "DISPATCH-DISC mutation did NOT land (the discovery-grep line changed?) — the row would be vacuous"
else
  run_guard "$SANDBOX/red_raw" "$EMPTY_ALLOW" "$MUT"
  (( GUARD_RC == 0 )); check $? "DISPATCH-DISC neutered discovery -> exit 0 over an unclassified fixture (the grep is the mechanism)" "DISPATCH-DISC expected exit 0 on the mutant, got $GUARD_RC: $GUARD_OUT"
fi

# --- DISPATCH-CLASS: a COPY with the emitter classifier neutered reds the GREEN fixture --
MUT2="$SANDBOX/guard-no-classifier.sh"
sed 's|grep -qE -- "\$EMITTER_RE" "\$WORK/code"|false|' "$GUARD" > "$MUT2"
if cmp -s "$GUARD" "$MUT2"; then
  check 1 "" "DISPATCH-CLASS mutation did NOT land (the classifier line changed?) — the row would be vacuous"
else
  GUARD_OUT="$(EMITTER_READ_ALLOW_FILE="$EMPTY_ALLOW" bash "$MUT2" "$SANDBOX/green_emitter" 2>&1)"; GUARD_RC=$?
  (( GUARD_RC == 1 )); check $? "DISPATCH-CLASS neutered classifier -> exit 1 over an emitter fixture" "DISPATCH-CLASS expected exit 1 on the mutant, got $GUARD_RC: $GUARD_OUT"
  contains 'UNCLASSIFIED scripts/reader.sh'; check $? "DISPATCH-CLASS names the now-unclassified emitter reader" "DISPATCH-CLASS missing UNCLASSIFIED: $GUARD_OUT"
fi

# --- MUST-FIND rows: a copy of the guard living INSIDE a fixture tree is "production" for
#     that tree (the guard derives its repo root from its own location) — so the must-find
#     list and the population floor are live. Floor is silenced via the test override. -----
MUSTS=(
  "scripts/betterstack-query.sh"
  "scripts/betterstack-assert-absence.sh"
  "scripts/cutover-inngest.sh"
  "scripts/inngest-host-state.sh"
  "scripts/inngest-probe-heartbeat-feeder.sh"
  "scripts/check-deploy-script-parity.sh"
  "scripts/zot-restart-loop-alarm.sh"
  "scripts/zot-disk-sample.sh"
  "scripts/lib/betterstack-absence.sh"
  "scripts/lib/git-data-boot-signal-poll.sh"
  "scripts/registry-replace-preflight.sh"
  "scripts/probe-inngest-524-count.sh"
  "scripts/followthroughs/inngest-provision-unit-8562.sh"
  "scripts/followthroughs/zot-fill-rate-7341.sh"
  ".github/workflows/scheduled-inngest-health.yml"
  ".github/workflows/git-data-cutover.yml"
  ".github/workflows/inngest-config-drift.yml"
)
# Missing member -> exit 1 naming it.
T="$(mk_tree red_mustfind)"
mkdir -p "$T/scripts"
cp "$GUARD" "$T/scripts/lint-betterstack-emitter-read.sh"
ALLOWF="$SANDBOX/mustfind-empty.txt"; : > "$ALLOWF"
seed "$T"
GUARD_OUT="$(EMITTER_READ_ALLOW_FILE="$ALLOWF" EMITTER_READ_MIN_POP=0 bash "$T/scripts/lint-betterstack-emitter-read.sh" "$T" 2>&1)"; GUARD_RC=$?
(( GUARD_RC == 1 )); check $? "MUST-FIND missing member -> exit 1" "MUST-FIND expected exit 1, got $GUARD_RC: $GUARD_OUT"
contains 'MUST-FIND-MISSING scripts/betterstack-query.sh'; check $? "MUST-FIND names the missing member" "MUST-FIND did not name it: $GUARD_OUT"

# Every member present (each a discovered, allowlisted file) -> exit 0.
T="$(mk_tree green_mustfind)"
mkdir -p "$T/scripts" "$T/scripts/lib" "$T/scripts/followthroughs" "$T/.github/workflows"
cp "$GUARD" "$T/scripts/lint-betterstack-emitter-read.sh"
ALLOWF="$SANDBOX/mustfind-full.txt"; : > "$ALLOWF"
for mf in "${MUSTS[@]}"; do
  mkdir -p "$T/$(dirname "$mf")"
  printf '#!/usr/bin/env bash\nrows="$(bash scripts/betterstack-query.sh --since 1h --grep MARKER | grep -c .)"\n' > "$T/$mf"
  write_allow "$ALLOWF" "$mf" "fixture member"
done
seed "$T"
GUARD_OUT="$(EMITTER_READ_ALLOW_FILE="$ALLOWF" EMITTER_READ_MIN_POP=0 bash "$T/scripts/lint-betterstack-emitter-read.sh" "$T" 2>&1)"; GUARD_RC=$?
(( GUARD_RC == 0 )); check $? "MUST-FIND all members present (allowlisted) -> exit 0" "MUST-FIND full fixture expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- FLOOR: forcing the population floor above the live count -> exit 2 + [FATAL] --------
FLOOR_OUT="$(EMITTER_READ_MIN_POP=100000 bash "$GUARD" 2>&1)"; FLOOR_RC=$?
(( FLOOR_RC == 2 )); check $? "FLOOR breach on the real tree -> exit 2" "FLOOR breach expected exit 2, got $FLOOR_RC: $FLOOR_OUT"
contains '[FATAL]' "$FLOOR_OUT"; check $? "FLOOR breach emits the [FATAL] diagnostic" "FLOOR breach missing diagnostic: $FLOOR_OUT"
contains 'discovered only' "$FLOOR_OUT"; check $? "FLOOR diagnostic names the population measure" "FLOOR diagnostic unhelpful: $FLOOR_OUT"

# --- EMPTY: an empty fixture tree -> exit 0 (the floor keys on the resolved tree) --------
T="$(mk_tree empty)"
seed "$T"
run_guard "$T"
(( GUARD_RC == 0 )); check $? "EMPTY fixture tree -> exit 0 (sandbox floor exemption pinned)" "EMPTY expected exit 0, got $GUARD_RC: $GUARD_OUT"

# --- LIVE: the real tree -> exit 0 and a population at/above the floor -------------------
LIVE_OUT="$(bash "$GUARD" 2>&1)"; LIVE_RC=$?
(( LIVE_RC == 0 )); check $? "LIVE real tree -> exit 0" "LIVE expected exit 0, got $LIVE_RC: $LIVE_OUT"
n_live="$(printf '%s\n' "$LIVE_OUT" | grep -oE '[0-9]+ discovered' | grep -oE '^[0-9]+' | head -1)"
if [[ "$n_live" =~ ^[0-9]+$ ]] && [[ "$n_live" -ge 40 ]]; then check 0 "LIVE population is $n_live (>= 40, the floor)" ""; else check 1 "" "LIVE population unparseable or below floor: '$n_live' ($LIVE_OUT)"; fi

# =======================================================================================
# ADR-193 accounting — reported directly, never through pass()/fail().
# =======================================================================================
MIN_CHECKS=26
if [[ "$n_checks" -lt "$MIN_CHECKS" ]]; then
  printf '[FATAL] emitter-read mutation battery ran only %s check(s) — expected at least %s; a block was skipped\n' "$n_checks" "$MIN_CHECKS" >&2
  exit 1
fi
if (( passes + fails != n_checks )); then
  printf '[FATAL] conservation broke: passes=%s fails=%s n_checks=%s\n' "$passes" "$fails" "$n_checks" >&2
  exit 1
fi
if (( fails > 0 )); then
  printf 'emitter-read battery: %s check(s) ran, %s FAILED\n' "$n_checks" "$fails" >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
printf 'emitter-read battery: clean — %s check(s), all green\n' "$n_checks"
exit 0
