#!/usr/bin/env bash
# Guard 1 (the probe's own guard) - arm-token-revisit-12229.sh exits 5 while ANY of the three
# arm-token members is in config, exits 2 only when NONE is, exits 3 when a file cannot be read,
# and can never exit 0 or 1.
#
# PROPERTY. Members: the line `-target=doppler_service_token.inngest_arm_write` and the line
# `-target=github_actions_secret.doppler_token_inngest_arm` (both in the apply workflow) and the
# declaration `resource "doppler_service_token" "inngest_arm_write"` (in the .tf file). A probe that
# stops at the first member is the defect this suite exists to catch (removing the -target lines
# alone does not revoke, so the declaration is a member too). Comments are not members.
#
# The probe reads two tracked files and holds no credential. The suite drives it with synthesized
# fixtures through the test-only env override of the two file paths (the sweeper runs probes under
# env -i, so the override is unset in production).
#
# MUTANTS (each is applied to a copy of the probe and must turn this suite RED):
#   M1 exit-5 branch replaced by exit 2        M2 probe checks only the token -target line
#   M3 probe checks only the two -target lines M4 probe can exit 0
#   M5 unreadable file mapped to exit 2        M6 exit-2 branch removed (falls through to 5)
#   M7 (suite dispatch) a case-count floor catches an emptied case list, enforced below.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/arm-token-revisit-12229.sh"

pass=0; fail=0
FAILURES=()
ok()  { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
bad() { fail=$((fail + 1)); FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

# Instrument self-test (reported with printf+exit, never through the helpers it guards).
_p=$pass; _f=$fail
ok "instrument: ok() moves the pass counter" >/dev/null
bad "instrument: bad() moves the fail counter" >/dev/null
if [ "$pass" -ne $((_p + 1)) ] || [ "$fail" -ne $((_f + 1)) ]; then
  printf '[FATAL] instrument self-test: helpers did not move the counters\n' >&2; exit 1
fi
pass=$_p; fail=$_f; FAILURES=()

D="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
trap 'rm -rf "$D"' EXIT
export TMPDIR="$D"

TGT1='              -target=doppler_service_token.inngest_arm_write \'
TGT2='              -target=github_actions_secret.doppler_token_inngest_arm \'
DECL='resource "doppler_service_token" "inngest_arm_write" {'

mkfix() { # name wf-lines tf-lines  (each a newline-joined string, may be empty)
  local n="$1" wf="$2" tf="$3"
  mkdir -p "$D/$n"
  printf '%s\n' "name: apply" "steps:" "  - run: |" "      terraform apply \\" > "$D/$n/wf.yml"
  [ -n "$wf" ] && printf '%b\n' "$wf" >> "$D/$n/wf.yml"
  printf '%s\n' "              -target=other_resource.keep \\" >> "$D/$n/wf.yml"
  printf '%s\n' "# tf" > "$D/$n/arm.tf"
  [ -n "$tf" ] && printf '%b\n' "$tf" >> "$D/$n/arm.tf"
  return 0
}

run_probe() { # probe name -> sets RC, OUT
  local pr="$1" n="$2"
  OUT="$(env -i PATH="$PATH" TMPDIR="$D" ARM_TOKEN_REVISIT_WORKFLOW="$D/$n/wf.yml" ARM_TOKEN_REVISIT_TF="$D/$n/arm.tf" bash "$pr" 2>&1)"
  RC=$?
}

expect() { # label probe name want-rc
  run_probe "$2" "$3"
  if [ "$RC" -eq "$4" ]; then ok "$1 -> rc $RC"; else bad "$1 -> rc $RC (want $4)"; fi
}

# Case list. Counted by a floor below, so deleting a case reddens the suite.
CASES=0
case_all() {
  CASES=$((CASES + 1))
  mkfix all "$TGT1\n$TGT2" "$DECL"; expect "all three members present" "$PROBE" all 5
}
case_only_target() {
  CASES=$((CASES + 1))
  mkfix only_t1 "$TGT1" ""; expect "only the token -target line" "$PROBE" only_t1 5
  mkfix only_t2 "$TGT2" ""; expect "only the secret -target line" "$PROBE" only_t2 5
}
case_only_decl() {
  CASES=$((CASES + 1))
  mkfix only_decl "" "$DECL"; expect "only the resource declaration" "$PROBE" only_decl 5
}
case_none() {
  CASES=$((CASES + 1))
  mkfix none "" ""; expect "none present (targets gone)" "$PROBE" none 2
  grep -qi 'targets gone' <<<"$OUT" && ok "targets-gone wording printed" || bad "targets-gone wording missing: $OUT"
}
case_comment_only() {
  CASES=$((CASES + 1))
  mkfix commented "  # -target=doppler_service_token.inngest_arm_write \\\\\n  # -target=github_actions_secret.doppler_token_inngest_arm \\\\" "# resource \"doppler_service_token\" \"inngest_arm_write\" {"
  expect "only commented-out occurrences are not members" "$PROBE" commented 2
}
case_non_canonical() {
  CASES=$((CASES + 1))
  mkfix order "$TGT2  # note\n$TGT1" ""; expect "reordered targets with a trailing comment" "$PROBE" order 5
  mkfix crlf "" ""; printf '%s\r\n' "$TGT1" >> "$D/crlf/wf.yml"; expect "CRLF line endings" "$PROBE" crlf 5
}
case_unreadable() {
  CASES=$((CASES + 1))
  mkfix unr_wf "" ""; rm -f "$D/unr_wf/wf.yml"; expect "unreadable workflow file" "$PROBE" unr_wf 3
  mkfix unr_tf "" ""; rm -f "$D/unr_tf/arm.tf"; expect "unreadable tf file" "$PROBE" unr_tf 3
}
case_exit_set() {
  CASES=$((CASES + 1))
  local seen="" n pr="$PROBE"
  for n in all only_t1 only_t2 only_decl none commented order crlf unr_wf unr_tf; do
    run_probe "$pr" "$n"; seen="$seen $RC"
  done
  local bad_rc
  bad_rc="$(for r in $seen; do case "$r" in 2|3|5) : ;; *) echo "$r" ;; esac; done)"
  [ -z "$bad_rc" ] && ok "exit set over the fixture matrix is within {2,3,5}" || bad "probe exited outside {2,3,5}: $bad_rc"
}
case_mode() {
  CASES=$((CASES + 1))
  local m
  m="$(git -C "$HERE" ls-files -s -- arm-token-revisit-12229.sh 2>/dev/null | awk '{print $1}')"
  if [ -z "$m" ]; then
    [ -x "$PROBE" ] && ok "probe is executable (untracked checkout)" || bad "probe is not executable"
  else
    [ "$m" = 100755 ] && ok "probe is committed with mode 100755" || bad "probe mode is $m, want 100755"
  fi
}

run_all_cases() {
  case_all; case_only_target; case_only_decl; case_none; case_comment_only
  case_non_canonical; case_unreadable; case_exit_set; case_mode
}

if [ ! -f "$PROBE" ]; then
  bad "probe missing: $PROBE"
else
  run_all_cases
fi

# --- mutants: each is a copy of the probe with one edit; the case list must go RED --------------
mutate() { # name sed-expression
  local name="$1" expr="$2" mp="$D/mut-$1.sh"
  cp "$PROBE" "$mp"; sed -E -i "$expr" "$mp"
  if cmp -s "$PROBE" "$mp"; then bad "mutation $name did not land"; return; fi
  local before_fail=$fail before_pass=$pass
  # run the discriminating cases against the mutant, in a subshell-free way using the same helpers
  local killed=0 n
  for n in all only_t1 only_t2 only_decl none unr_wf; do
    run_probe "$mp" "$n"
    case "$n" in
      all|only_t1|only_t2|only_decl) [ "$RC" -eq 5 ] || killed=1 ;;
      none) [ "$RC" -eq 2 ] || killed=1 ;;
      unr_wf) [ "$RC" -eq 3 ] || killed=1 ;;
    esac
    case "$RC" in 2|3|5) : ;; *) killed=1 ;; esac
  done
  fail=$before_fail; pass=$before_pass
  [ "$killed" -eq 1 ] && ok "mutant $name is killed" || bad "mutant $name SURVIVED"
}

if [ -f "$PROBE" ]; then
  mkfix all "$TGT1\n$TGT2" "$DECL"; mkfix only_t1 "$TGT1" ""; mkfix only_t2 "$TGT2" ""
  mkfix only_decl "" "$DECL"; mkfix none "" ""; mkfix unr_wf "" ""; rm -f "$D/unr_wf/wf.yml"
  mutate M1 's/^([[:space:]]*)exit 5$/\1exit 2/'
  mutate M2 's/m2=1/m2=0/; s/m3=1/m3=0/'
  mutate M3 's/m3=1/m3=0/'
  mutate M4 's/^([[:space:]]*)exit 2$/\1exit 0/'
  mutate M5 's/^([[:space:]]*)exit 3$/\1exit 2/'
  mutate M6 's/^([[:space:]]*)exit 2$/\1exit 5/'
fi

# --- anti-vacuity floors (reported with printf + exit, not through the helpers) ------------------
EXPECTED_CASES=9
if [ "$CASES" -lt "$EXPECTED_CASES" ]; then
  printf '[FATAL] case-count floor: ran %s cases, want >= %s (a case was deleted or the list was emptied)\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
MIN_ASSERTIONS=18
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: %s passed, want >= %s\n' "$pass" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n%s passed, %s failed (%s cases)\n' "$pass" "$fail" "$CASES"
if [ "$fail" -gt 0 ] || [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILURES:\n'; printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
exit 0
