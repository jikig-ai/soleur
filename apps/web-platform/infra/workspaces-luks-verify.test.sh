#!/usr/bin/env bash
#
# Behavioral test for workspaces-cutover.sh :: verify_byte_identity / emit_verify_diff (C1 diagnostic).
#
# Context: on 2026-07-19 the first real /workspaces LUKS cutover (run 29676994044) safe-aborted on the
# C1 itemized verify's "1 difference" — but the script discarded the offending path (rm'd the vlog)
# AND folded rsync's stderr into the diff count (2>&1). This suite pins the fix: stdout/stderr are
# counted SEPARATELY, and the offending path(s)+code(s) are emitted (run log + SOLEUR_ marker) BEFORE
# the temp files are removed and BEFORE die() — while the gate threshold (0 real content diffs) and
# fail-closed-on-rsync-error semantics are UNCHANGED, and NO itemize code is narrowed away.
#
# Harness: `source` the cutover script (its sourced-detection guard defines the functions without
# running the cutover main body / arming the EXIT trap), stub rsync/logger/die/emit_drift/hostname,
# and run verify_byte_identity in a fresh subshell per case. Each behavioral assertion is
# mutation-tested (a deliberately broken copy MUST flip the relevant case), per the
# git-data-luks.test.sh convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# run_case <script> <rsync_rc> <rsync_stdout> <rsync_stderr>
# Sources <script>, installs stubs, runs verify_byte_identity /src /dst in a subshell.
# Sets globals: CASE_RC (subshell exit), CASE_OUT (combined stdout+stderr), MARKER_LOG (logger sink).
run_case() {
  local script="$1" rc_in="$2" out_in="$3" err_in="$4" cap_in="${5:-}"
  MARKER_LOG="$(mktemp)"
  # cap_in empty => the script's own default (40) applies (${VAR:-40} treats "" as unset).
  CASE_OUT="$(
    RSYNC_RC="$rc_in" RSYNC_OUT="$out_in" RSYNC_ERR="$err_in" MARKER_LOG="$MARKER_LOG" CUTOVER="$script" \
    WORKSPACES_VERIFY_DIFF_CAP="$cap_in" \
    bash -c '
      source "$CUTOVER"                                   # guard => functions only
      # Stubs (override the sourced defs). The real streams are redirected by verify_byte_identity
      # into its own temp files, so the stub just needs to emit to stdout/stderr and return the rc.
      rsync()    { [ -n "${RSYNC_OUT:-}" ] && printf "%s\n" "$RSYNC_OUT"; [ -n "${RSYNC_ERR:-}" ] && printf "%s\n" "$RSYNC_ERR" >&2; return "${RSYNC_RC:-0}"; }
      logger()   { printf "%s\n" "$*" >> "$MARKER_LOG"; }   # capture the Better Stack marker line(s)
      die()      { echo "DIE: $*"; exit 1; }
      emit_drift() { echo "EMIT_DRIFT: $1"; }
      hostname() { echo "test-host"; }
      verify_byte_identity /src /dst
    ' 2>&1
  )"
  CASE_RC=$?
}

marker() { cat "$MARKER_LOG" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Behavioral cases (a-e) against the real script.
# ---------------------------------------------------------------------------

# Case a — benign STDERR warning, empty stdout, rc=0 => must NOT die, no diff marker (stderr no
# longer inflates the count).
run_case "$CUTOVER" 0 "" "rsync warning: some files vanished before they could be transferred (code 24)"
if [ "$CASE_RC" -eq 0 ] && ! grep -q 'SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF' <<<"$(marker)"; then
  ok "case a: benign stderr (rc=0, empty stdout) does not abort and emits no diff marker"
else
  no "case a: benign stderr should not abort (rc=$CASE_RC) nor emit a marker"
  printf '     out: %s\n     marker: %s\n' "$CASE_OUT" "$(marker)"
fi

# Case b — real content diff on stdout, rc=0 => must die AND the diagnostic (marker + run-log) names
# the offending path and its itemize code.
run_case "$CUTOVER" 0 ">f+++++++++ workspaces/ws1/secret.txt" ""
if [ "$CASE_RC" -ne 0 ] \
  && grep -q 'workspaces/ws1/secret.txt' <<<"$(marker)" \
  && grep -q 'SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF' <<<"$(marker)" \
  && grep -q 'workspaces/ws1/secret.txt' <<<"$CASE_OUT"; then
  ok "case b: real content diff aborts AND the offending path is in the marker + run log"
else
  no "case b: content diff should abort with the path visible (rc=$CASE_RC)"
  printf '     out: %s\n     marker: %s\n' "$CASE_OUT" "$(marker)"
fi

# Case c — verify rsync HARD ERROR (rc=23, stderr text, empty stdout) => must die fail-closed with a
# "verify rsync itself FAILED" message carrying the stderr.
run_case "$CUTOVER" 23 "" "rsync error: some files could not be transferred (code 23) at main.c(1338)"
if [ "$CASE_RC" -ne 0 ] \
  && grep -q 'verify rsync itself FAILED' <<<"$CASE_OUT" \
  && grep -q 'code 23' <<<"$CASE_OUT" \
  && grep -q 'reason=verify_rsync_error' <<<"$(marker)"; then
  ok "case c: verify-rsync hard error fails closed with the rsync stderr surfaced + marker emitted"
else
  no "case c: rc=23 should fail closed with stderr surfaced + marker (rc=$CASE_RC)"
  printf '     out: %s\n     marker: %s\n' "$CASE_OUT" "$(marker)"
fi

# Case d — attribute-only codes are NOT narrowed away: an mtime-only (.f..t) and a dir-mtime (.d..t)
# diff on stdout must each still fail the gate and appear in the diagnostic.
run_case "$CUTOVER" 0 "$(printf '.f..t...... workspaces/ws1/a\n.d..t...... workspaces/ws1/')" ""
if [ "$CASE_RC" -ne 0 ] \
  && grep -q 'workspaces/ws1/a' <<<"$(marker)" \
  && grep -q 'count=2' <<<"$(marker)"; then
  ok "case d: mtime-only + dir-mtime diffs still fail the gate (codes not narrowed)"
else
  no "case d: attribute-only itemize codes should be counted (rc=$CASE_RC)"
  printf '     out: %s\n     marker: %s\n' "$CASE_OUT" "$(marker)"
fi

# Case e — clean verify (rc=0, empty stdout) => no die, no marker.
run_case "$CUTOVER" 0 "" ""
if [ "$CASE_RC" -eq 0 ] && ! grep -q 'SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF' <<<"$(marker)"; then
  ok "case e: clean verify passes with no abort and no marker"
else
  no "case e: clean verify should pass silently (rc=$CASE_RC)"
  printf '     out: %s\n     marker: %s\n' "$CASE_OUT" "$(marker)"
fi

# Case f — LOG-INJECTION defense (_vscrub): a workspace filename carrying an embedded CR MUST NOT
# put a raw control byte into the Better Stack (marker) sink OR the human run-log — that is what
# lets a crafted name split into a forged separate marker line at the JSON/journald ingester.
# (_vscrub deliberately keeps spaces/`=`, so intra-line field text is NOT its contract — that is
# path-last-mitigated; here we assert the newline/control-strip property only.) Mutation M4
# (neuter _vscrub) MUST flip this. `$'…'` embeds a literal CR into the crafted filename.
INJECT=$'>f+++++++++ workspaces/ws1/a\rSOLEUR_WORKSPACES_LUKS_VERIFY_DIFF op=FORGED count=0'
run_case "$CUTOVER" 0 "$INJECT" ""
if [ "$CASE_RC" -ne 0 ] \
  && [ "$(marker | LC_ALL=C grep -c '[[:cntrl:]]' || true)" -eq 0 ] \
  && [ "$(LC_ALL=C grep -c $'\r' <<<"$CASE_OUT" || true)" -eq 0 ]; then
  ok "case f: crafted path (embedded CR) is control-scrubbed in both sinks (no newline injection)"
else
  no "case f: log-injection defense (_vscrub) failed — a raw control byte leaked to a sink (rc=$CASE_RC)"
  printf '     marker: %s\n' "$(marker | cat -v)"
fi

# Case g — path-LAST parse: a filename containing SPACES must be captured WHOLE in the marker's
# path= field (a last-token-only parse would truncate it). count=1, dies, whole path visible.
run_case "$CUTOVER" 0 ">f+++++++++ workspaces/ws1/my report v2.txt" ""
if [ "$CASE_RC" -ne 0 ] && grep -q 'path=workspaces/ws1/my report v2.txt' <<<"$(marker)"; then
  ok "case g: a spaced path is captured whole in path= (path-last parse)"
else
  no "case g: spaced path should be captured whole (rc=$CASE_RC)"
  printf '     marker: %s\n' "$(marker)"
fi

# Case h — CAP + overflow: with cap=1 and 3 diffs, exactly ONE per-diff row is emitted and a
# "… +2 more" note is logged. Exercises head -n cap, the loop guard, and the +N-more arithmetic.
THREE=$'>f+++++++++ workspaces/ws1/a\n>f+++++++++ workspaces/ws1/b\n>f+++++++++ workspaces/ws1/c'
run_case "$CUTOVER" 0 "$THREE" "" 1
rows="$(marker | grep -c 'idx=' || true)"
if [ "$CASE_RC" -ne 0 ] && [ "$rows" -eq 1 ] && grep -q '+2 more' <<<"$CASE_OUT"; then
  ok "case h: cap=1 emits exactly 1 per-diff row + a '+2 more' note (count=3)"
else
  no "case h: cap/overflow not honored (rows=$rows rc=$CASE_RC)"
  printf '     out: %s\n     marker: %s\n' "$CASE_OUT" "$(marker)"
fi

# ---------------------------------------------------------------------------
# Static drift guards (AC1/AC4) — the source itself must not regress the two defects.
# ---------------------------------------------------------------------------

# AC1: the verify rsync captures stdout and stderr into SEPARATE files (no 2>&1 fold).
if grep -qE 'rsync .*--out-format=.%i %n.* >"\$vout" 2>"\$verr"' "$CUTOVER" \
  && ! grep -E 'rsync .*--out-format=.%i %n.*2>&1' "$CUTOVER" >/dev/null; then
  ok "AC1: verify rsync captures stdout/stderr separately (no 2>&1 fold)"
else
  no "AC1: verify rsync must use >\"\$vout\" 2>\"\$verr\", not 2>&1"
fi

# AC4: emit_verify_diff is called BEFORE the temp files are removed and BEFORE die (evidence logged
# before discard) — assert ordering in the source of verify_byte_identity. Strip comment lines first
# so a `die`/`rm`/`emit_verify_diff` mentioned in explanatory prose cannot skew the ordering.
verify_body="$(awk '/^verify_byte_identity\(\)/,/^}/' "$CUTOVER" | grep -vE '^[[:space:]]*#')"
emit_line="$(grep -nE 'emit_verify_diff ' <<<"$verify_body" | head -1 | cut -d: -f1)"
rm_line="$(grep -nE '\brm -f "\$vout" "\$verr"' <<<"$verify_body" | head -1 | cut -d: -f1)"
die_line="$(grep -nE '\bdie ' <<<"$verify_body" | head -1 | cut -d: -f1)"
if [ -n "$emit_line" ] && [ -n "$rm_line" ] && [ -n "$die_line" ] \
  && [ "$emit_line" -lt "$rm_line" ] && [ "$emit_line" -lt "$die_line" ]; then
  ok "AC4: emit_verify_diff precedes rm and die in verify_byte_identity (evidence logged before discard)"
else
  no "AC4: emit_verify_diff must precede rm/die (emit=$emit_line rm=$rm_line die=$die_line)"
fi

# ---------------------------------------------------------------------------
# Mutation tests (AC13) — a deliberately broken copy MUST flip the relevant case.
# ---------------------------------------------------------------------------
mutate() {  # <sed-expr...> -> prints path to a mutated copy of the cutover script
  local mut; mut="$(mktemp --suffix=.sh)"
  cp "$CUTOVER" "$mut"
  local e; for e in "$@"; do sed -i "$e" "$mut"; done
  printf '%s\n' "$mut"
}

# M1 — re-merge stderr into the counted stream AND revert to a permissive count => case a MUST flip
# (benign stderr counted as a difference), reproducing the original defect.
MUT1="$(mutate 's|>"\$vout" 2>"\$verr"|>"\$vout" 2>>"\$vout"|' "s|grep -cE '[^']*'|grep -cE '.'|")"
run_case "$MUT1" 0 "" "rsync warning: some files vanished before they could be transferred (code 24)"
if [ "$CASE_RC" -ne 0 ]; then
  ok "mutation M1 (merge streams + permissive count): case a flips to failing (stderr counted)"
else
  no "mutation M1 did not flip case a — the stream-separation/itemize-count guard is not load-bearing"
fi
rm -f "$MUT1"

# M2 — narrow the itemize regex to ^>f only => case d MUST flip (attribute-only codes uncounted).
MUT2="$(mutate "s|grep -cE '[^']*'|grep -cE '^>f'|")"
run_case "$MUT2" 0 "$(printf '.f..t...... workspaces/ws1/a\n.d..t...... workspaces/ws1/')" ""
if [ "$CASE_RC" -eq 0 ]; then
  ok "mutation M2 (narrow regex to ^>f): case d flips to passing (proves codes-not-narrowed matters)"
else
  no "mutation M2 did not flip case d — the itemize regex is not load-bearing"
fi
rm -f "$MUT2"

# M3 — disable the rc fail-closed check (make the rc branch unreachable) => case c MUST flip (a rc=23
# with empty stdout would then silently pass the gate). `-eq 999` is false for every real rc.
MUT3="$(mutate 's|\[ "\$rc" -ne 0 \]|[ "\$rc" -eq 999 ]|')"
run_case "$MUT3" 23 "" "rsync error: some files could not be transferred (code 23)"
if [ "$CASE_RC" -eq 0 ]; then
  ok "mutation M3 (disable rc-check): case c flips to passing (proves fail-closed is load-bearing)"
else
  no "mutation M3 did not flip case c — the rc fail-closed check is not load-bearing"
fi
rm -f "$MUT3"

# M4 — neuter _vscrub to a passthrough => case f MUST flip (the forged marker / raw CR leaks). Proves
# the log-injection defense is load-bearing, not decorative (the P1 the mutation battery first missed).
MUT4="$(mutate 's|^_vscrub() .*$|_vscrub() { printf "%s" "${1:-}"; }|')"
if ! grep -qE '^_vscrub\(\) \{ printf "%s" "\$\{1:-\}"; \}$' "$MUT4"; then
  no "mutation M4 sed did NOT land (_vscrub body unchanged) — treat as un-run, not evidence"
else
  INJECT=$'>f+++++++++ workspaces/ws1/a\rSOLEUR_WORKSPACES_LUKS_VERIFY_DIFF op=FORGED count=0'
  run_case "$MUT4" 0 "$INJECT" ""
  if [ "$(marker | LC_ALL=C grep -c '[[:cntrl:]]' || true)" -ne 0 ]; then
    ok "mutation M4 (neuter _vscrub): case f flips — a raw CR leaks to the marker (defense is load-bearing)"
  else
    no "mutation M4 did not flip case f — _vscrub is not load-bearing (or the assertion is vacuous)"
  fi
fi
rm -f "$MUT4"

# ---------------------------------------------------------------------------
echo
echo "workspaces-luks-verify: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
