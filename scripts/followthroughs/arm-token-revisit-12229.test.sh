#!/usr/bin/env bash
# Guard 1 (the probe's own guard) - arm-token-revisit-12229.sh exits 5 while ANY of the three
# arm-token members is in config, exits 2 only when NONE is, exits 3 when a file cannot be read
# (missing, empty, or not a regular file), and can never exit 0 or 1.
#
# PROPERTY. Members: a non-comment line carrying `-target=doppler_service_token.inngest_arm_write`
# and one carrying `-target=github_actions_secret.doppler_token_inngest_arm` (both in the apply
# workflow), and the declaration `resource "doppler_service_token" "inngest_arm_write"` (in the .tf
# file). A probe that stops at the first member is the defect this suite exists to catch (removing
# the -target lines alone does not revoke, so the declaration is a member too). Comments are not
# members; a longer name (..._v2) is not a member.
#
# The probe reads two tracked files and holds no credential. The suite drives it with synthesized
# fixtures through the test-only env override of the two file paths (the sweeper runs probes under
# env -i, so the override is unset in production), and once against the REAL tree.
#
# MUTANTS (each is applied to a copy of the probe and must turn the discriminating cases RED):
#   M1 exit-5 branch replaced by exit 2        M2 members 2 and 3 disabled
#   M3 member 3 disabled                       M4 probe can exit 0
#   M5 unreadable file mapped to exit 2        M6 exit-2 branch replaced by exit 5
# Floors: the case count and the assertion count are exact-minimum floors reported with printf+exit.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/arm-token-revisit-12229.sh"

pass=0; fail=0
FAILURES=()
ok()  { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
bad() { fail=$((fail + 1)); FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

D="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
trap 'chmod -R u+rwx "$D" 2>/dev/null; rm -rf "$D"' EXIT
export TMPDIR="$D"

TGT1='              -target=doppler_service_token.inngest_arm_write \'
TGT2='              -target=github_actions_secret.doppler_token_inngest_arm \'
DECL='resource "doppler_service_token" "inngest_arm_write" {'
NL=$'\n'

mkfix() { # name wf-lines tf-lines  (each a newline-joined string, may be empty)
  local n="$1" wf="$2" tf="$3"
  mkdir -p "$D/$n"
  printf '%s\n' "name: apply" "steps:" "  - run: |" "      terraform apply \\" > "$D/$n/wf.yml"
  [ -n "$wf" ] && printf '%s\n' "$wf" >> "$D/$n/wf.yml"
  printf '%s\n' "              -target=other_resource.keep \\" >> "$D/$n/wf.yml"
  printf '%s\n' "# tf" > "$D/$n/arm.tf"
  [ -n "$tf" ] && printf '%s\n' "$tf" >> "$D/$n/arm.tf"
  return 0
}

run_probe() { # probe name -> sets RC, OUT   (name "REAL" = the real tree)
  local pr="$1" n="$2"
  if [ "$n" = REAL ]; then
    OUT="$(env -i PATH="$PATH" TMPDIR="$D" bash "$pr" 2>&1)"
  else
    OUT="$(env -i PATH="$PATH" TMPDIR="$D" ARM_TOKEN_REVISIT_WORKFLOW="$D/$n/wf.yml" ARM_TOKEN_REVISIT_TF="$D/$n/arm.tf" bash "$pr" 2>&1)"
  fi
  RC=$?
}

expect() { # label probe name want-rc [want-word]
  run_probe "$2" "$3"
  if [ "$RC" -ne "$4" ]; then bad "$1 -> rc $RC (want $4)"; return; fi
  if [ -n "${5:-}" ] && ! grep -qF -- "$5" <<<"$OUT"; then bad "$1 -> rc $RC but wording lacks '$5'"; return; fi
  ok "$1 -> rc $RC"
}

# Instrument self-test: expect() itself must be able to reject (known-negative) and accept
# (known-positive). Reported with printf+exit, never through the helpers it guards.
_p=$pass; _f=$fail
mkfix ctrl "" ""
expect "ctrl-positive" "$PROBE" ctrl 2 >/dev/null
expect "ctrl-negative (deliberately wrong want)" "$PROBE" ctrl 5 >/dev/null
expect "ctrl-wrong-word (rc right, wording wrong)" "$PROBE" ctrl 2 "NOPE-NOT-IN-OUTPUT" >/dev/null
if [ "$pass" -ne $((_p + 1)) ] || [ "$fail" -ne $((_f + 2)) ]; then
  printf '[FATAL] instrument self-test: expect() did not accept, reject on rc and reject on wording (pass %s->%s fail %s->%s)\n' "$_p" "$pass" "$_f" "$fail" >&2
  exit 1
fi
pass=$_p; fail=$_f; FAILURES=()

CASES=0
case_all() {
  CASES=$((CASES + 1))
  mkfix all "$TGT1$NL$TGT2" "$DECL"; expect "all three members present" "$PROBE" all 5 "ACTION REQUIRED"
  grep -qF 'token -target line: 1, secret -target line: 1, resource declaration: 1' <<<"$OUT" \
    && ok "all-three fixture matched each member separately" || bad "all-three fixture did not match all members: $OUT"
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
  mkfix none "" ""; expect "none present (targets gone)" "$PROBE" none 2 "targets gone"
  mkfix commented "  # -target=doppler_service_token.inngest_arm_write \\$NL  # -target=github_actions_secret.doppler_token_inngest_arm \\" "# resource \"doppler_service_token\" \"inngest_arm_write\" {"
  expect "only commented-out occurrences are not members" "$PROBE" commented 2
  mkfix decoy "              -target=doppler_service_token.inngest_arm_write_v2 \\$NL              -target=github_actions_secret.doppler_token_inngest_arm_v2 \\" 'resource "doppler_service_token" "inngest_arm_write_v2" {'
  expect "longer names (..._v2) are not members" "$PROBE" decoy 2
}
case_shapes() {
  CASES=$((CASES + 1))
  mkfix order "$TGT2  # note" ""; expect "a target line with a trailing comment still counts" "$PROBE" order 5
  mkfix crlf "" ""; printf '%s\r\n' "$TGT1" >> "$D/crlf/wf.yml"; expect "CRLF line endings" "$PROBE" crlf 5
  mkfix noslash "              -target=doppler_service_token.inngest_arm_write" ""; expect "line ending without a backslash" "$PROBE" noslash 5
  mkfix inline "terraform apply -target=doppler_service_token.inngest_arm_write -target=other.x" ""; expect "target inline on one command line" "$PROBE" inline 5
  mkfix quoted "              -target=\"github_actions_secret.doppler_token_inngest_arm\" \\" ""; expect "quoted target form" "$PROBE" quoted 5
  mkfix spaced "              -target github_actions_secret.doppler_token_inngest_arm \\" ""; expect "space-separated target form" "$PROBE" spaced 5
  mkfix dspace "              -target  github_actions_secret.doppler_token_inngest_arm \\" ""; expect "two spaces after -target" "$PROBE" dspace 5
  mkfix tabsep "              -target"$'\t'"github_actions_secret.doppler_token_inngest_arm \\" ""; expect "tab after -target" "$PROBE" tabsep 5
  mkfix cont "              -target \\$NL                doppler_service_token.inngest_arm_write \\" ""; expect "-target and its name on separate continued lines" "$PROBE" cont 5
  mkfix arr "ARGS=(-target=doppler_service_token.inngest_arm_write)" ""; expect "bash array form" "$PROBE" arr 5
  mkfix semi "terraform apply -target=github_actions_secret.doppler_token_inngest_arm; true" ""; expect "target ended by a semicolon" "$PROBE" semi 5
  mkfix sq "terraform apply -target='github_actions_secret.doppler_token_inngest_arm'" ""; expect "single-quoted target" "$PROBE" sq 5
}
case_unreadable() {
  CASES=$((CASES + 1))
  mkfix unr_wf "" ""; rm -f "$D/unr_wf/wf.yml"; expect "missing workflow file" "$PROBE" unr_wf 3 "CANNOT ESTABLISH"
  mkfix unr_tf "" ""; rm -f "$D/unr_tf/arm.tf"; expect "missing tf file" "$PROBE" unr_tf 3 "CANNOT ESTABLISH"
  mkfix empty_wf "" ""; : > "$D/empty_wf/wf.yml"; expect "empty workflow file is not 'targets gone'" "$PROBE" empty_wf 3
  mkfix empty_tf "" ""; : > "$D/empty_tf/arm.tf"; expect "empty tf file is not 'targets gone'" "$PROBE" empty_tf 3
  mkfix dir_tf "" ""; rm -f "$D/dir_tf/arm.tf"; mkdir "$D/dir_tf/arm.tf"; expect "tf path is a directory" "$PROBE" dir_tf 3
  if [ "$(id -u)" -ne 0 ]; then
    mkfix perm_wf "" ""; chmod 000 "$D/perm_wf/wf.yml"; expect "unreadable (mode 000) workflow file" "$PROBE" perm_wf 3
  else
    ok "mode-000 case skipped under root (counted so the floor is stable)"
  fi
}
case_real_tree() {
  CASES=$((CASES + 1))
  # The probe against the real tracked files. Valid only while the token is in config; the whole
  # suite is retired with the token (see the RETIREMENT note in the probe).
  expect "real tree: token still in config" "$PROBE" REAL 5 "ACTION REQUIRED"
  grep -qF 'token -target line: 1, secret -target line: 1, resource declaration: 1' <<<"$OUT" \
    && ok "real tree: each of the three members matched on its real line" || bad "real tree: member counts differ: $OUT"
}
case_exit_set() {
  CASES=$((CASES + 1))
  local n bad_rc=""
  for n in all only_t1 only_t2 only_decl none commented decoy order crlf noslash inline quoted spaced dspace tabsep cont arr semi sq unr_wf unr_tf empty_wf empty_tf dir_tf REAL; do
    run_probe "$PROBE" "$n"
    case "$RC" in 2|3|5) : ;; *) bad_rc="$bad_rc $n=$RC" ;; esac
  done
  [ -z "$bad_rc" ] && ok "exit set over the fixture matrix is within {2,3,5}" || bad "probe exited outside {2,3,5}:$bad_rc"
}
case_xtrace() {
  CASES=$((CASES + 1))
  OUT="$(env -i PATH="$PATH" TMPDIR="$D" bash -x "$PROBE" 2>&1)"; RC=$?
  [ "$RC" -eq 78 ] && ok "xtrace refusal exits 78" || bad "xtrace run exited $RC (want 78)"
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

if [ ! -f "$PROBE" ]; then
  bad "probe missing: $PROBE"
else
  case_all; case_only_target; case_only_decl; case_none; case_shapes
  case_unreadable; case_real_tree; case_xtrace; case_exit_set; case_mode
fi

# --- mutants: each is a copy of the probe with one edit; the discriminating cases must go RED ----
grade() { # probe-copy -> prints 1 when ANY discriminating case misbehaves (killed), else 0
  local mp="$1" killed=0 n
  for n in all only_t1 only_t2 only_decl none unr_wf; do
    run_probe "$mp" "$n"
    case "$n" in
      all|only_t1|only_t2|only_decl) [ "$RC" -eq 5 ] || killed=1 ;;
      none) [ "$RC" -eq 2 ] || killed=1 ;;
      unr_wf) [ "$RC" -eq 3 ] || killed=1 ;;
    esac
    case "$RC" in 2|3|5) : ;; *) killed=1 ;; esac
  done
  printf '%s' "$killed"
}
mutate() { # name sed-expression
  local name="$1" expr="$2" mp="$D/mut-$1.sh"
  cp "$PROBE" "$mp"; sed -E -i "$expr" "$mp"
  if cmp -s "$PROBE" "$mp"; then bad "mutation $name did not land"; return; fi
  [ "$(grade "$mp")" = 1 ] && ok "mutant $name is killed" || bad "mutant $name SURVIVED"
}

MUTANTS=0
if [ -f "$PROBE" ]; then
  # Grader controls: an unmutated copy must NOT be killed, and a copy that always exits outside the
  # contract set must be.
  cp "$PROBE" "$D/mut-ctrl.sh"
  [ "$(grade "$D/mut-ctrl.sh")" = 0 ] && ok "grader control: the unmutated probe survives the mutant loop" || bad "grader control: the unmutated probe was graded killed"
  cp "$PROBE" "$D/mut-ctrl99.sh"; printf '\nexit 99\n' | sed -i '/^exit 5$/r /dev/stdin' "$D/mut-ctrl99.sh" 2>/dev/null
  sed -E -i 's/^exit 5$/exit 99/' "$D/mut-ctrl99.sh"
  [ "$(grade "$D/mut-ctrl99.sh")" = 1 ] && ok "grader control: a probe exiting 99 is graded killed" || bad "grader control: a probe exiting 99 was not graded killed"
  mutate M1 's/^([[:space:]]*)exit 5$/\1exit 2/';        MUTANTS=$((MUTANTS + 1))
  mutate M2 's/m2=1/m2=0/; s/m3=1/m3=0/';                 MUTANTS=$((MUTANTS + 1))
  mutate M3 's/m3=1/m3=0/';                               MUTANTS=$((MUTANTS + 1))
  mutate M4 's/^([[:space:]]*)exit 2$/\1exit 0/';         MUTANTS=$((MUTANTS + 1))
  mutate M5 's/^([[:space:]]*)exit 3$/\1exit 2/';         MUTANTS=$((MUTANTS + 1))
  mutate M6 's/^([[:space:]]*)exit 2$/\1exit 5/';         MUTANTS=$((MUTANTS + 1))
fi

# --- anti-vacuity floors (reported with printf + exit, not through the helpers) ------------------
EXPECTED_CASES=10
if [ "$CASES" -lt "$EXPECTED_CASES" ]; then
  printf '[FATAL] case-count floor: ran %s cases, want >= %s (a case was deleted or the list was emptied)\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
EXPECTED_MUTANTS=6
if [ "$MUTANTS" -lt "$EXPECTED_MUTANTS" ]; then
  printf '[FATAL] mutant-count floor: ran %s mutants, want >= %s\n' "$MUTANTS" "$EXPECTED_MUTANTS" >&2
  exit 1
fi
MIN_ASSERTIONS=39
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: %s passed, want >= %s (an assertion was deleted)\n' "$pass" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n%s passed, %s failed (%s cases, %s mutants)\n' "$pass" "$fail" "$CASES" "$MUTANTS"
if [ "$fail" -gt 0 ] || [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILURES:\n'; printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
exit 0
