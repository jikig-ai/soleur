#!/usr/bin/env bash
# cf-account-state-migrate.test.sh — Guard 2 battery for
# scripts/cf-account-state-migrate.sh (#12931, plan "### Guard 2").
#
# HARNESS
# - `terraform` and `aws` are PATH-shimmed stubs in a mktemp sandbox. Both
#   append every invocation to one calls.log, so call ORDER is observable.
# - The terraform stub serves `state pull` / `show -json` from fixtures keyed by
#   a state counter; `state rm` really strips the addresses and bumps the
#   serial, so the next show reflects the write. Unexpected subcommands exit 64.
# - Script-level guards are proven load-bearing against sed mutants of a
#   PRISTINE COPY: each mutant must differ from pristine (cmp), must still parse
#   (bash -n), and the same check must be GREEN on pristine and RED on the
#   mutant, for the named reason (WHY), not merely rc != 0.
# - Fixtures are synthesized. Only the OLD ids are real; they are literals
#   here, checked against the script (never read out of it).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT="$SCRIPT_DIR/scripts/cf-account-state-migrate.sh"
LIB="$REPO/tests/scripts/lib/cf-account-migrate-gate.sh"
[[ -x "$SUT" ]] || { printf '[FATAL] not executable: %s\n' "$SUT" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

# The legacy ids are literals here, never read out of the library the script sources: a typo
# there then reds this suite instead of agreeing with it (#12931 review, SM1).
OZ="5af02a2f394e9ba6e0ea23c381a26b67"
OA="4d5ba6f096b2686fbdd404167dd4e125"
grep -qx "CFAM_OLD_ZONE_ID=\"$OZ\"" "$LIB" && grep -qx "CFAM_OLD_ACCOUNT_ID=\"$OA\"" "$LIB" \
  || { printf '[FATAL] OLD ids in the gate library differ from the legacy account literals\n' >&2; exit 1; }
NZ="11111111111111111111111111111111"
NA="22222222222222222222222222222222"
UNK="99999999999999999999999999999999"
SENTINEL="SENTINEL-STATE-VALUE-DO-NOT-PRINT"

SBX="$(mktemp -d -t cf-state-migrate.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SBX"' EXIT INT TERM HUP
# The script sources the gate library by its own relative path, so the pristine copy and every
# mutant sit at the script's depth in a mirror tree whose tests/ is the real one.
MUT_DIR="$SBX/tree/apps/web-platform/infra/scripts"
mkdir -p "$SBX/bin" "$SBX/runs" "$MUT_DIR" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
ln -s "$REPO/tests" "$SBX/tree/tests" || { printf '[FATAL] ln failed\n' >&2; exit 2; }
PRISTINE="$MUT_DIR/pristine.sh"
cp "$SUT" "$PRISTINE" || { printf '[FATAL] cp failed\n' >&2; exit 2; }

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi; }

# INSTRUMENT SELF-TEST: drive both arms of the wrapper once and refuse to
# continue unless both counters moved.
_p0=$PASS; _f0=$FAIL; _c0=$CASES
verdict 0 "instrument self-test: the PASS arm records"
verdict 1 "instrument self-test: the FAIL arm records (EXPECTED, subtracted below)"
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) || "$CASES" -ne $((_c0 + 2)) ]]; then
  printf '[FATAL] instrument self-test: verdict did not route both arms\n' >&2; exit 2
fi
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); CASES=$((CASES - 2))

# ---------------------------------------------------------------------------
# STUBS
# ---------------------------------------------------------------------------
cat >"$SBX/bin/terraform" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
n="$(cat "$D/counter")"
mode() { if [[ -f "$D/mode.$1" ]]; then cat "$D/mode.$1"; else printf 'normal'; fi; }
log() { printf '%s\n' "$*" >>"$D/calls.log"; }
case "${1:-}|${2:-}|$#" in
  "state|pull|2")
    log "terraform state pull"
    case "$(mode pull)" in
      fail) exit 1 ;;
      empty) exit 0 ;;
      noserial) printf '{"version":4}\n'; exit 0 ;;
    esac
    cat "$D/pull.$n.json" ;;
  "show|-json|2")
    log "terraform show -json"
    cat "$D/show.$n.json" ;;
  state\|rm\|*)
    shift 2
    m="$(mode rm)"
    [[ "$m" == ignore ]] && exit 0
    k=$(( $(cat "$D/rm_count") + 1 )); printf '%s' "$k" >"$D/rm_count"
    log "terraform state rm argc=$#"
    printf '%s\n' "$@" >"$D/rm_args.$k"
    if [[ "$m" == fail ]]; then printf 'Error: simulated state rm failure\n'; exit 1; fi
    nx=$((n + 1)); delta=1; [[ "$m" == double ]] && delta=2
    if [[ "$m" == stale ]]; then
      cp "$D/show.$n.json" "$D/show.$nx.json"
    else
      jq '
        def strip: (if has("resources") then .resources |= map(select(.address as $x | any($ARGS.positional[]; . == $x) | not)) else . end)
                 | (if has("child_modules") then .child_modules |= map(strip) else . end);
        .values.root_module |= strip' --args "$@" <"$D/show.$n.json" >"$D/show.$nx.json" || exit 70
    fi
    jq --argjson d "$delta" '.serial += $d' "$D/pull.$n.json" >"$D/pull.$nx.json" || exit 70
    printf '%s' "$nx" >"$D/counter"
    for a in "$@"; do printf 'Removed %s\n' "$a"; done
    c=$#; [[ "$m" == short ]] && c=$((c - 1))
    printf 'Successfully removed %d resource instance(s).\n' "$c" ;;
  *)
    log "terraform UNEXPECTED $*"
    exit 64 ;;
esac
STUB
cat >"$SBX/bin/aws" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
printf 'aws %s\n' "$*" >>"$D/calls.log"
printf 'aws-env region=%s req=%s resp=%s imds-off=%s\n' "${AWS_DEFAULT_REGION:-unset}" \
  "${AWS_REQUEST_CHECKSUM_CALCULATION:-unset}" "${AWS_RESPONSE_CHECKSUM_VALIDATION:-unset}" \
  "${AWS_EC2_METADATA_DISABLED:-unset}" >>"$D/calls.log"
[[ "${1:-} ${2:-}" == "s3 cp" ]] || exit 64
[[ -s "${3:-}" ]] && jq -r '.serial' "$3" >"$D/aws_src_serial" 2>/dev/null
if [[ -f "$D/mode.aws" ]]; then exit "$(cat "$D/mode.aws")"; fi
exit 0
STUB
# timeout shim: records the bound, then runs the command (no real clock in the suite). A
# simulated timeout is the aws stub exiting 124, which is what timeout(1) itself returns.
cat >"$SBX/bin/timeout" <<'STUB'
#!/usr/bin/env bash
printf 'timeout %s %s\n' "${1:-}" "${2:-}" >>"${STUB_DIR:?}/calls.log"
shift
exec "$@"
STUB
chmod +x "$SBX/bin/terraform" "$SBX/bin/aws" "$SBX/bin/timeout"

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------
new_run() { # <label> -> prints a fresh run dir
  local d
  d="$(mktemp -d "$SBX/runs/${1//[^A-Za-z0-9._-]/_}.XXXXXX")" || return 1
  mkdir -p "$d/tf" "$d/runner" || return 1
  printf '0' >"$d/counter"; printf '0' >"$d/rm_count"; : >"$d/calls.log"
  printf '%s' "$d"
}

# fx <dir> <serial>, stdin lines: root|child|<address>|<type>|<zone>|<account>[|<mode>]
# zone/account: an id, "null", or "absent" (key omitted).
fx() {
  local d="$1" serial="$2" where addr type z a m
  : >"$d/root.jsonl"; : >"$d/child.jsonl"
  while IFS='|' read -r where addr type z a m; do
    [[ -n "$where" ]] || continue
    jq -nc --arg a "$addr" --arg t "$type" --arg z "$z" --arg c "$a" --arg m "${m:-managed}" --arg s "$SENTINEL" '
      def v($x): if $x == "null" then null else $x end;
      {address: $a, mode: $m, type: $t, name: "n",
       provider_name: "registry.terraform.io/cloudflare/cloudflare",
       values: ({secret_sentinel: $s}
                + (if $z == "absent" then {} else {zone_id: v($z)} end)
                + (if $c == "absent" then {} else {account_id: v($c)} end))}' >>"$d/$where.jsonl"
  done
  jq -n --slurpfile r "$d/root.jsonl" --slurpfile c "$d/child.jsonl" '
    {format_version: "1.0", terraform_version: "1.9.0",
     values: {root_module: ({resources: $r}
       + (if ($c | length) > 0 then {child_modules: [{address: "module.edge", resources: $c}]} else {} end))}}' >"$d/show.0.json"
  jq -n --argjson s "$serial" --arg x "$SENTINEL" \
    '{version: 4, terraform_version: "1.9.0", serial: $s, lineage: "00000000-0000-0000-0000-fakelineage00", outputs: {}, resources: [], sentinel: $x}' >"$d/pull.0.json"
}

# H1 mixed state: old-zone and old-account entries (root and child module),
# entries already imported under the NEW ids, an R2 bucket on the OLD account,
# a data source and a non-cloudflare resource.
H1_RM='cloudflare_list.allow
cloudflare_record.apex
cloudflare_record.multi["with space"]
cloudflare_record.x["a"]
cloudflare_ruleset.waf
module.edge.cloudflare_zero_trust_access_application.app
module.edge.cloudflare_zero_trust_access_service_token.t'
setup_mixed() {
  fx "$1" 41 <<EOF
root|cloudflare_record.apex|cloudflare_record|$OZ|absent
root|cloudflare_record.x["a"]|cloudflare_record|$OZ|absent
root|cloudflare_record.multi["with space"]|cloudflare_record|$OZ|absent
root|cloudflare_ruleset.waf|cloudflare_ruleset|$OZ|null
root|cloudflare_list.allow|cloudflare_list|absent|$OA
root|cloudflare_record.new_one|cloudflare_record|$NZ|absent
root|cloudflare_list.new_list|cloudflare_list|null|$NA
root|cloudflare_r2_bucket.state|cloudflare_r2_bucket|absent|$OA
root|data.cloudflare_zone.z|cloudflare_zone|$OZ|absent|data
root|hcloud_server.web["web-9"]|hcloud_server|absent|absent
child|module.edge.cloudflare_zero_trust_access_application.app|cloudflare_zero_trust_access_application|$OZ|absent
child|module.edge.cloudflare_zero_trust_access_service_token.t|cloudflare_zero_trust_access_service_token|absent|$OA
EOF
}
setup_2c() {
  fx "$1" 7 <<EOF
root|cloudflare_ruleset.zone_waf|cloudflare_ruleset|$OZ|absent
root|cloudflare_ruleset.zone_cache|cloudflare_ruleset|$OZ|null
root|cloudflare_list.ips|cloudflare_list|absent|$OA
root|cloudflare_list.hosts|cloudflare_list|null|$OA
EOF
}
setup_empty_obj() { setup_mixed "$1"; printf '{}\n' >"$1/show.0.json"; }
# D10: the state after a committed forget: R2 (never forgotten) plus non-Cloudflare entries.
setup_no_cf() {
  fx "$1" 3 <<EOF
root|cloudflare_r2_bucket.state|cloudflare_r2_bucket|absent|$OA
root|hcloud_server.web["web-9"]|hcloud_server|absent|absent
root|data.cloudflare_zone.z|cloudflare_zone|$OZ|absent|data
EOF
}
# No managed cloudflare_* at all (not even R2): an empty or foreign state.
setup_no_cf_at_all() {
  fx "$1" 3 <<EOF
root|hcloud_server.web["web-9"]|hcloud_server|absent|absent
root|data.cloudflare_zone.z|cloudflare_zone|$OZ|absent|data
EOF
}
setup_garbage() { setup_mixed "$1"; printf 'not json {\n' >"$1/show.0.json"; }
setup_both_null() {
  fx "$1" 5 <<EOF
root|cloudflare_record.apex|cloudflare_record|$OZ|absent
root|cloudflare_zone_settings_override.s|cloudflare_zone_settings_override|null|null
EOF
}
setup_unknown_second() {
  fx "$1" 5 <<EOF
root|cloudflare_record.apex|cloudflare_record|$OZ|absent
root|cloudflare_record.stray|cloudflare_record|$UNK|absent
root|cloudflare_list.allow|cloudflare_list|absent|$OA
EOF
}
setup_mixed_ids() {
  fx "$1" 5 <<EOF
root|cloudflare_record.apex|cloudflare_record|$OZ|absent
root|cloudflare_load_balancer.lb|cloudflare_load_balancer|$OZ|$NA
EOF
}
setup_r2_old() {
  fx "$1" 9 <<EOF
root|cloudflare_record.apex|cloudflare_record|$OZ|absent
root|cloudflare_r2_bucket.luks|cloudflare_r2_bucket|absent|$OA
EOF
}
# Another cloudflare_r2_* type on the legacy account (the carve-out is the whole family).
setup_r2_family() {
  fx "$1" 9 <<EOF
root|cloudflare_record.apex|cloudflare_record|$OZ|absent
root|cloudflare_r2_bucket.luks|cloudflare_r2_bucket|absent|$OA
root|cloudflare_r2_bucket_cors.luks|cloudflare_r2_bucket_cors|absent|$OA
EOF
}
with_mode() { printf '%s' "$3" >"$1/mode.$2"; }
setup_aws_fail()   { setup_mixed "$1"; with_mode "$1" aws 1; }
setup_aws_timeout() { setup_mixed "$1"; with_mode "$1" aws 124; }
setup_norunner()   { setup_mixed "$1"; : >"$1/norunner"; }
setup_pull_fail()  { setup_mixed "$1"; with_mode "$1" pull fail; }
setup_pull_empty() { setup_mixed "$1"; with_mode "$1" pull empty; }
setup_pull_noser() { setup_mixed "$1"; with_mode "$1" pull noserial; }
setup_double()     { setup_mixed "$1"; with_mode "$1" rm double; }
setup_short()      { setup_mixed "$1"; with_mode "$1" rm short; }
setup_stale()      { setup_mixed "$1"; with_mode "$1" rm stale; }
setup_rm_fail()    { setup_mixed "$1"; with_mode "$1" rm fail; }
setup_ignore()     { setup_mixed "$1"; with_mode "$1" rm ignore; }

# run_sut <dir> <script> [args...]: default args when none given; an argument
# "__D__" becomes <dir>/given-backups; <dir>/noendpoint leaves R2_ENDPOINT unset. Otherwise
# R2_ENDPOINT is a HOSTILE value: the script must ignore it for its pinned literal.
run_sut() {
  local d="$1" s="$2" x; shift 2
  [[ $# -gt 0 ]] || set -- --new-zone "$NZ" --new-account "$NA"
  local -a args=() envs=(PATH="$SBX/bin:$PATH" STUB_DIR="$d")
  # <dir>/norunner: no RUNNER_TEMP, TMPDIR=<dir>/tmp (the script's mktemp fallback lands there).
  if [[ -f "$d/norunner" ]]; then mkdir -p "$d/tmp"; envs+=(TMPDIR="$d/tmp"); else envs+=(RUNNER_TEMP="$d/runner"); fi
  for x in "$@"; do [[ "$x" == __D__ ]] && x="$d/given-backups"; args+=("$x"); done
  [[ -f "$d/noendpoint" ]] || envs+=(R2_ENDPOINT="https://r2.invalid")
  (cd "$d/tf" && env -u R2_ENDPOINT -u RUNNER_TEMP "${envs[@]}" bash "$s" "${args[@]}") \
    >"$d/out.txt" 2>"$d/err.txt"
  printf '%s' "$?" >"$d/rc"
}

# ---------------------------------------------------------------------------
# CHECKS: return 0 when the property holds; on failure set WHY.
# ---------------------------------------------------------------------------
WHY=""
rc_of() { cat "$1/rc"; }
rm_calls() { grep -c '^terraform state rm' "$1/calls.log"; }
first_line() { grep -n -m1 -E "$2" "$1/calls.log" | cut -d: -f1; }

chk_single_rm() {
  local n; n="$(rm_calls "$1")"
  [[ "$n" -eq 1 ]] || { WHY="rm-call-count:$n"; return 1; }
}
chk_no_rm() {
  local n; n="$(rm_calls "$1")"
  [[ "$n" -eq 0 ]] || { WHY="rm-called:$n"; return 1; }
}
chk_no_leak() {
  if grep -q "$SENTINEL" "$1/out.txt" "$1/err.txt"; then WHY="state-value-printed"; return 1; fi
}
chk_no_unexpected() {
  if grep -q 'UNEXPECTED' "$1/calls.log"; then WHY="unexpected-subcommand"; return 1; fi
}
final_show() { printf '%s/show.%s.json' "$1" "$(cat "$1/counter")"; }

# H1: exactly the old entries are forgotten, in one call, nothing else moves.
chk_h1() {
  local d="$1" got
  chk_single_rm "$d" || return 1
  [[ "$(rc_of "$d")" == 0 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  grep -qx 'cf-state-migrate verdict=ok removed=7 skipped=2' "$d/out.txt" || { WHY="verdict-line"; return 1; }
  got="$(sort "$d/rm_args.1")"
  [[ "$got" == "$H1_RM" ]] || { WHY="rm-args"; return 1; }
  got="$(jq -r 'def mods: ., (.child_modules[]? | mods);
    [.values.root_module | mods | .resources[]? | .address] | unique | join(",")' "$(final_show "$d")")"
  [[ "$got" == 'cloudflare_list.new_list,cloudflare_r2_bucket.state,cloudflare_record.new_one,data.cloudflare_zone.z,hcloud_server.web["web-9"]' ]] \
    || { WHY="final-state:$got"; return 1; }
  chk_no_leak "$d" || return 1
  chk_no_unexpected "$d" || return 1
}

chk_r2_kept() {
  local d="$1" f
  for f in "$d"/rm_args.*; do
    [[ -e "$f" ]] || continue
    if grep -q '^cloudflare_r2_bucket\.' "$f"; then WHY="r2-forgotten"; return 1; fi
  done
  jq -e '[.values.root_module.resources[] | select(.type == "cloudflare_r2_bucket")] | length == 1' \
    "$(final_show "$d")" >/dev/null || { WHY="r2-missing-from-state"; return 1; }
}

chk_r2_family_kept() {
  local d="$1"
  [[ "$(rc_of "$d")" == 0 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  if grep -q '^cloudflare_r2_' "$d/rm_args.1" 2>/dev/null; then WHY="r2-forgotten"; return 1; fi
  grep -qx 'cf-state-migrate verdict=ok removed=1 skipped=0' "$d/out.txt" || { WHY="verdict-line"; return 1; }
}

# chk_abort <dir> <reason>: refused, nothing removed, no state rm call.
chk_abort() {
  local d="$1" r="$2"
  [[ "$(rc_of "$d")" == 1 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  grep -qx "cf-state-migrate verdict=abort reason=$r" "$d/out.txt" || { WHY="reason:$(grep -o 'reason=.*' "$d/out.txt" | head -n1)"; return 1; }
  chk_no_rm "$d" || return 1
  [[ "$(cat "$d/counter")" == 0 ]] || { WHY="state-changed"; return 1; }
  chk_no_leak "$d" || return 1
}
chk_abort_zero()    { chk_abort "$1" zero-candidates; }
chk_abort_garbage() { chk_abort "$1" show-unparseable; }
chk_abort_null()    { chk_abort "$1" unclassifiable; }
chk_abort_unknown() { chk_abort "$1" unknown-id; }
chk_abort_mixed()   { chk_abort "$1" mixed-ids; }
chk_abort_r2()      { chk_abort "$1" r2-in-rm-set; }
chk_abort_upload()  { chk_abort "$1" backup-upload-failed; }
chk_abort_upload_timeout() { chk_abort "$1" backup-upload-timeout; }
chk_abort_backup()  { chk_abort "$1" backup-failed; }

# D10: nothing to forget in a populated state -> ok removed=0, and NO backup (no pull, no aws).
chk_r2_only_ok() {
  local d="$1"
  [[ "$(rc_of "$d")" == 0 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  grep -qx 'cf-state-migrate verdict=ok removed=0 skipped=0' "$d/out.txt" || { WHY="verdict-line"; return 1; }
  if grep -qE '^aws|^terraform state pull' "$d/calls.log"; then WHY="backup-taken"; return 1; fi
  chk_no_rm "$d" || return 1
  [[ "$(cat "$d/counter")" == 0 ]] || { WHY="state-changed"; return 1; }
  chk_no_leak "$d" || return 1
}

# The mktemp fallback (no RUNNER_TEMP, no --backup-dir) holds a full-state copy: gone on exit.
chk_fallback_cleaned() {
  local d="$1" left
  [[ "$(rc_of "$d")" == 0 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  grep -q '^aws s3 cp ' "$d/calls.log" || { WHY="no-upload"; return 1; }
  left="$(find "$d/tmp" -name 'pre-cf-account-migration-*.tfstate' | wc -l)"
  [[ "$left" -eq 0 ]] || { WHY="fallback-left:$left"; return 1; }
}

# chk_post_fail <dir> <reason>: the write ran; the failure is loud and names the backup.
chk_post_fail() {
  local d="$1" r="$2"
  [[ "$(rc_of "$d")" == 1 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  grep -qx "cf-state-migrate verdict=abort reason=$r" "$d/out.txt" || { WHY="reason:$(grep -o 'reason=.*' "$d/out.txt" | head -n1)"; return 1; }
  grep -q 'PARTIALLY MIGRATED' "$d/err.txt" || { WHY="not-loud"; return 1; }
  grep -q 's3://soleur-terraform-state/web-platform/backups/pre-cf-account-migration-' "$d/err.txt" || { WHY="backup-not-named"; return 1; }
  # The uploaded object is the backup; the local file is deleted with the job's work dir.
  if grep -qE 'local copy|runner/cf-migrate/pre-cf-account-migration-' "$d/err.txt"; then WHY="names-local-copy"; return 1; fi
  if grep -q 'verdict=ok' "$d/out.txt"; then WHY="ok-printed"; return 1; fi
  chk_no_leak "$d" || return 1
}
chk_post_serial() { chk_post_fail "$1" serial-delta; }
chk_post_count()  { chk_post_fail "$1" rm-count-mismatch; }
chk_post_stale()  { chk_post_fail "$1" old-id-remains; }
chk_post_rmfail() { chk_post_fail "$1" state-rm-failed; }

# Row 5: the backup upload is observed BEFORE the state rm call.
chk_backup_first() {
  local d="$1" up rmn
  up="$(first_line "$d" '^aws s3 cp ')"; rmn="$(first_line "$d" '^terraform state rm')"
  [[ -n "$rmn" ]] || { WHY="no-rm-call"; return 1; }
  [[ -n "$up" && "$up" -lt "$rmn" ]] || { WHY="rm-before-backup"; return 1; }
  [[ "$(first_line "$d" '^terraform state pull')" -lt "$rmn" ]] || { WHY="rm-before-pull"; return 1; }
  [[ "$(cat "$d/aws_src_serial" 2>/dev/null)" == 41 ]] || { WHY="backup-not-pre-migration"; return 1; }
  grep -qE '^aws s3 cp [^ ]+/pre-cf-account-migration-[0-9]{8}T[0-9]{6}Z\.tfstate s3://soleur-terraform-state/web-platform/backups/pre-cf-account-migration-[0-9]{8}T[0-9]{6}Z\.tfstate ' "$d/calls.log" \
    || { WHY="upload-target"; return 1; }
}

# The upload goes to the PINNED legacy-account endpoint whatever R2_ENDPOINT says (run_sut
# sets it to https://r2.invalid), under the shared R2 env prefix and a 60 s bound: the gate
# library's cfam_r2_aws, whose own mutation rows live in tests/scripts/test-cf-account-migrate-gate.sh.
R2_PIN="https://${OA}.r2.cloudflarestorage.com"
chk_r2_call_shape() {
  local d="$1"
  grep -qF -- "--endpoint-url $R2_PIN" "$d/calls.log" || { WHY="endpoint-not-pinned"; return 1; }
  if grep -q 'r2\.invalid' "$d/calls.log"; then WHY="env-endpoint-used"; return 1; fi
  grep -qx 'aws-env region=auto req=when_required resp=when_required imds-off=true' "$d/calls.log" || { WHY="aws-env-prefix"; return 1; }
  grep -qx 'timeout 60 env' "$d/calls.log" || { WHY="no-timeout"; return 1; }
}

# Rehearsal: no aws call at all, backup only under the given dir, mode 600.
chk_rehearsal() {
  local d="$1" dir="$2" f
  if grep -q '^aws' "$d/calls.log"; then WHY="aws-called"; return 1; fi
  [[ "$(rc_of "$d")" == 0 ]] || { WHY="rc:$(rc_of "$d")"; return 1; }
  mapfile -t f < <(find "$dir" -type f -name 'pre-cf-account-migration-*.tfstate')
  [[ "${#f[@]}" -eq 1 ]] || { WHY="backup-count:${#f[@]}"; return 1; }
  [[ "$(jq -r .serial "${f[0]}")" == 41 ]] || { WHY="backup-serial"; return 1; }
  [[ "$(stat -c %a "${f[0]}")" == 600 ]] || { WHY="backup-mode:$(stat -c %a "${f[0]}")"; return 1; }
  chk_single_rm "$d" || return 1
  chk_no_leak "$d" || return 1
}
chk_rehearsal_dir()    { chk_rehearsal "$1" "$1/given-backups"; }
chk_rehearsal_runner() { chk_rehearsal "$1" "$1/runner/cf-migrate"; }

# ---------------------------------------------------------------------------
# SCORING
# ---------------------------------------------------------------------------
# run_case <label> <script> <setup> [args...] -> prints run dir
run_case() {
  local label="$1" s="$2" setup="$3" d; shift 3
  d="$(new_run "$label")" || return 1
  "$setup" "$d"
  run_sut "$d" "$s" "$@"
  printf '%s' "$d"
}
# green <label> <check> <setup> [args...]: pristine must satisfy the check.
LAST_D=""
green() {
  local label="$1" chk="$2" setup="$3" d; shift 3
  d="$(run_case "$label" "$PRISTINE" "$setup" "$@")"; LAST_D="$d"
  WHY=""
  if "$chk" "$d"; then verdict 0 "$label"; else verdict 1 "$label (WHY=$WHY)"; fi
}
# mk_mutant <name> <sed-expr...>: copy pristine, apply, require it landed and parses.
mk_mutant() {
  local name="$1" m="$MUT_DIR/mut-$1.sh" e; shift
  cp "$PRISTINE" "$m" || return 1
  for e in "$@"; do sed -i -e "$e" "$m" || return 1; done
  if cmp -s "$PRISTINE" "$m"; then printf '[FATAL] mutant %s did not land\n' "$name" >&2; exit 2; fi
  bash -n "$m" || { printf '[FATAL] mutant %s does not parse\n' "$name" >&2; exit 2; }
  printf '%s' "$m"
}
# red <label> <mutant> <check> <why-regex> <setup> [args...]: the check that is
# GREEN on pristine must go RED on the mutant, for the named reason.
red() {
  local label="$1" mut="$2" chk="$3" why="$4" setup="$5" d; shift 5
  d="$(run_case "$label" "$mut" "$setup" "$@")"
  WHY=""
  if "$chk" "$d"; then verdict 1 "$label: mutant survived ($chk stayed GREEN)"; return; fi
  if [[ "$WHY" =~ $why ]]; then verdict 0 "$label: RED as required (WHY=$WHY)"
  else verdict 1 "$label: RED for the wrong reason (WHY=$WHY, wanted /$why/)"; fi
}

printf 'cf-account-state-migrate: Guard 2 battery\n'

# Pristine copy is byte-identical to the script under test.
cmp -s "$SUT" "$PRISTINE"; verdict "$?" "pristine copy equals the script under test"

# --- Unmutated control first: a red baseline voids every row below. ---------
printf '\n[control / H1] mixed state, pristine script\n'
d="$(run_case control "$PRISTINE" setup_mixed)"; WHY=""
if ! chk_h1 "$d"; then
  printf '[FATAL] unmutated control is RED (WHY=%s); every row below would be void\n' "$WHY" >&2
  sed -n '1,40p' "$d/out.txt" "$d/err.txt" >&2
  exit 1
fi
verdict 0 "H1: old-zone/old-account entries (root + child module) rm, NEW-id entries skip, R2/data/non-cf untouched, one call"
grep -qx 'cf-state-migrate address=cloudflare_record.new_one action=skip' "$d/out.txt"
verdict "$?" "H1: an already-imported NEW-zone entry prints action=skip"
grep -qx 'cf-state-migrate address=module.edge.cloudflare_zero_trust_access_service_token.t action=rm' "$d/out.txt"
verdict "$?" "H1: a child-module old-account entry prints action=rm"
r=1; ! grep -q 'cloudflare_r2_bucket\|data\.cloudflare_zone\|hcloud_server' "$d/out.txt" && r=0
verdict "$r" "H1: R2 bucket, data source and non-cloudflare resources are not candidates"
r=1; grep -qxF 'cloudflare_record.x["a"]' "$d/rm_args.1" && grep -qxF 'cloudflare_record.multi["with space"]' "$d/rm_args.1" && r=0
verdict "$r" "for_each addresses reach state rm as single intact argv entries"
r=1; [[ "$(grep -c '' "$d/rm_args.1")" -eq 7 ]] && r=0
verdict "$r" "state rm received exactly 7 argv entries (no word-splitting)"
chk_backup_first "$d"; verdict "$?" "row 5 control: backup pull and upload precede the state rm call"
green "row 2c: zone-only rulesets and account-only lists, both OLD, are all rm" chk_single_rm setup_2c
grep -qx 'cf-state-migrate verdict=ok removed=4 skipped=0' "$LAST_D/out.txt"
verdict "$?" "row 2c: verdict=ok removed=4 skipped=0"

# --- H2: a stub that swallows state rm must turn the H1 check RED. -----------
printf '\n[H2] call recorder is load-bearing\n'
d="$(run_case "H2" "$PRISTINE" setup_ignore)"; WHY=""
if chk_h1 "$d"; then verdict 1 "H2: H1 check stayed GREEN with a stub that ignores state rm"
elif [[ "$WHY" =~ ^rm-call-count:0$ ]]; then verdict 0 "H2: H1 check RED via the call recorder (WHY=$WHY)"
else verdict 1 "H2: RED for the wrong reason (WHY=$WHY)"; fi
r=1; [[ "$(rc_of "$d")" == 1 ]] && grep -qx 'cf-state-migrate verdict=abort reason=rm-count-mismatch' "$d/out.txt" && r=0
verdict "$r" "H2: the script itself also refuses a state rm that reports no removal"

# --- Row 1: R2 bucket. -------------------------------------------------------
printf '\n[row 1] R2 buckets are never forgotten\n'
green "row 1 control: R2 bucket on the OLD account is not a candidate and survives" chk_r2_kept setup_r2_old
M1A="$(mk_mutant r2-filter 's#^               and ((.type // "") | startswith("cloudflare_r2_") | not)) \]$#               ) ]#')"
green_mut() { # <label> <mutant> <check> <setup>: a mutant another guard must still catch
  local d; d="$(run_case "$1" "$2" "$4")"; WHY=""
  if "$3" "$d"; then verdict 0 "$1"; else verdict 1 "$1 (WHY=$WHY)"; fi
}
green_mut "row 1: classifier bug lets R2 into the candidate set -> defense aborts, 0 removed" "$M1A" chk_abort_r2 setup_r2_old
M1B="$(mk_mutant r2-filter-and-defense 's#^               and ((.type // "") | startswith("cloudflare_r2_") | not)) \]$#               ) ]#' 's/|| abort r2-in-rm-set/|| true/')"
red "row 1 mutant: filter and defense both removed" "$M1B" chk_r2_kept '^r2-forgotten$' setup_r2_old
green "row 1b: another cloudflare_r2_* type on the legacy account is not a candidate" chk_r2_family_kept setup_r2_family
# shellcheck disable=SC2016 # sed expressions match literal script text
M1C="$(mk_mutant r2-bucket-only 's#startswith("cloudflare_r2_") | not)) \]$#. != "cloudflare_r2_bucket")) ]#' 's/\[\[ "$type" != cloudflare_r2_\* \]\]/[[ "$type" != cloudflare_r2_bucket ]]/')"
red "row 1b mutant: the carve-out narrowed back to the bucket type" "$M1C" chk_r2_family_kept '^r2-forgotten$' setup_r2_family

# --- Row 2: 0 checked. -------------------------------------------------------
printf '\n[row 2] zero candidates refused\n'
green "row 2: show -json returns {} -> abort zero-candidates" chk_abort_zero setup_empty_obj
green "row 2: no managed cloudflare_* at all (not even R2) -> abort zero-candidates" chk_abort_zero setup_no_cf_at_all
green "row 2: unparseable show -json -> abort show-unparseable" chk_abort_garbage setup_garbage
# D10: after a committed forget the state holds R2 plus non-Cloudflare entries only. A
# re-dispatch must reach the plan: ok removed=0, and no backup and no state rm.
green "row 2 (D10): R2 plus non-Cloudflare only -> ok removed=0, no backup, no state rm" chk_r2_only_ok setup_no_cf
# shellcheck disable=SC2016 # sed expressions match literal script text
M2="$(mk_mutant zero-witness 's/    if (( n_r2 >= 1 )); then/    if true; then/')"
red "row 2 mutant: the R2 witness dropped (empty reads as ok)" "$M2" chk_abort_zero '^rc:0$' setup_no_cf_at_all
M2E="$(mk_mutant zero-refusal 's/^    abort zero-candidates /    return 0 # /')"
red "row 2 mutant: the zero-candidate refusal removed" "$M2E" chk_abort_zero '^rc:0$' setup_empty_obj
M2W="$(mk_mutant zero-always-abort 's/^      return 0$/      abort zero-candidates "x"/')"
red "row 2 (D10) mutant: zero candidates always abort (the pre-ruling deadlock)" "$M2W" chk_r2_only_ok '^rc:1$' setup_no_cf
M2O="$(mk_mutant backup-before-read '/^take_backup$/d' 's/^read_candidates$/take_backup\nread_candidates/')"
red "row 2 (D10) mutant: backup taken before the remove set is known" "$M2O" chk_r2_only_ok '^backup-taken$' setup_no_cf

# --- Row 2b: both ids null. --------------------------------------------------
printf '\n[row 2b] unclassifiable entry\n'
green "row 2b: entry with zone_id and account_id both null -> abort before any write" chk_abort_null setup_both_null
M2B="$(mk_mutant null-abort 's/abort unclassifiable/true/')"
red "row 2b mutant: both-null abort removed" "$M2B" chk_abort_null '^rc:' setup_both_null

# --- Row 2d: one write, serial +1. -------------------------------------------
printf '\n[row 2d] single state rm, serial +1\n'
green "row 2d: serial jumps by 2 -> loud failure naming the backup" chk_post_serial setup_double
# shellcheck disable=SC2016 # sed expressions match literal script text
M2D_LOOP="$(mk_mutant per-address-loop \
  's/rm_out="$(terraform state rm "${RM_ADDRS\[@\]}" 2>&1)"; rm_rc=$?/for _a in "${RM_ADDRS[@]}"; do rm_out="$(terraform state rm "$_a" 2>\&1)"; rm_rc=$?; done/')"
red "row 2d mutant: per-address state rm loop" "$M2D_LOOP" chk_single_rm '^rm-call-count:7$' setup_mixed
M2D_SER="$(mk_mutant serial-check 's/post_write_fail serial-delta/true/')"
red "row 2d mutant: serial delta check removed" "$M2D_SER" chk_post_serial '^rc:0$' setup_double

# --- Row 3: classify everything before any write. ----------------------------
printf '\n[row 3] unknown id anywhere aborts with 0 removed\n'
green "row 3: first entry OLD zone, second an unknown zone -> abort, no state rm call" chk_abort_unknown setup_unknown_second
green "row 3: one OLD and one NEW id on the same entry -> abort mixed-ids" chk_abort_mixed setup_mixed_ids
M3="$(mk_mutant unknown-abort 's/abort unknown-id/true/')"
red "row 3 mutant: unknown-id abort removed" "$M3" chk_abort_unknown '^rc:0$' setup_unknown_second

# --- Row 4: backup must succeed first. ---------------------------------------
printf '\n[row 4] backup failure removes nothing\n'
green "row 4: aws s3 cp exits 1 -> abort, 0 removed" chk_abort_upload setup_aws_fail
green "row 4: state pull fails -> abort, 0 removed" chk_abort_backup setup_pull_fail
green "row 4: state pull empty -> abort, 0 removed" chk_abort_backup setup_pull_empty
green "row 4: state pull without numeric serial -> abort, 0 removed" chk_abort_backup setup_pull_noser
# shellcheck disable=SC2016 # sed expressions match literal script text
M4="$(mk_mutant upload-check 's/^  elif \[\[ "$rc" -ne 0 \]\]; then$/  elif false; then/')"
red "row 4 mutant: upload failure ignored" "$M4" chk_abort_upload '^rc:0$' setup_aws_fail
green "row 4: aws s3 cp times out (rc 124) -> abort backup-upload-timeout, 0 removed" chk_abort_upload_timeout setup_aws_timeout
# shellcheck disable=SC2016 # sed expressions match literal script text
M4T="$(mk_mutant upload-timeout 's/^  if \[\[ "$rc" -eq 124 \]\]; then$/  if false; then/')"
red "row 4 mutant: the rc 124 arm removed (a timeout is mis-named)" "$M4T" chk_abort_upload_timeout '^reason:reason=backup-upload-failed$' setup_aws_timeout

# --- Row 5: order. -----------------------------------------------------------
printf '\n[row 5] backup precedes state rm (observed call order)\n'
M5="$(mk_mutant reorder '/^take_backup$/d' 's/^apply_rm$/apply_rm\ntake_backup/')"
red "row 5 mutant: state rm moved before the backup" "$M5" chk_backup_first '^rm-before-backup$' setup_mixed
green "row 5b: the upload uses the pinned endpoint (R2_ENDPOINT ignored), the shared R2 env and a 60 s bound" chk_r2_call_shape setup_mixed
M5B="$(mk_mutant r2-bypass 's/^  cfam_r2_aws s3 cp /  aws s3 cp /')"
red "row 5b mutant: the upload bypasses the shared R2 call" "$M5B" chk_r2_call_shape '^endpoint-not-pinned$' setup_mixed

# --- Row 6: idempotent re-run. -----------------------------------------------
printf '\n[row 6] re-run after a complete migration\n'
d="$(run_case "row 6" "$PRISTINE" setup_mixed)"
run_sut "$d" "$PRISTINE"
r=1; [[ "$(rc_of "$d")" == 0 ]] && grep -qx 'cf-state-migrate verdict=ok removed=0 skipped=2' "$d/out.txt" && r=0
verdict "$r" "row 6: second run exits 0 with verdict=ok removed=0 skipped=2"
r=1; [[ "$(rm_calls "$d")" -eq 1 ]] && r=0
verdict "$r" "row 6: the second run makes no state rm call"
r=1; [[ "$(grep -c '^aws s3 cp ' "$d/calls.log")" -eq 1 ]] && r=0
verdict "$r" "row 6 (D10): the second run uploads no backup (one aws s3 cp across both runs)"

# --- Row 7: removed count and re-list. ---------------------------------------
printf '\n[row 7] post-write verification\n'
green "row 7: state rm reports fewer removals than the rm set -> loud failure" chk_post_count setup_short
green "row 7: post-rm re-list still shows an old-id entry -> loud failure" chk_post_stale setup_stale
green "state rm exits non-zero -> loud failure" chk_post_rmfail setup_rm_fail
M7A="$(mk_mutant count-check 's/post_write_fail rm-count-mismatch/true/')"
red "row 7 mutant: removed-count check removed" "$M7A" chk_post_count '^rc:0$' setup_short
M7B="$(mk_mutant relist-check 's/post_write_fail old-id-remains/true/')"
red "row 7 mutant: post-rm re-list check removed" "$M7B" chk_post_stale '^rc:0$' setup_stale
# shellcheck disable=SC2016 # sed expressions match literal script text
M7C="$(mk_mutant local-copy-named 's/^  BACKUP_LOCATION="$uri"$/  BACKUP_LOCATION="$uri (local copy $BACKUP_FILE)"/')"
red "row 7 mutant: the failure message names the deleted local copy" "$M7C" chk_post_serial '^names-local-copy$' setup_double

# --- mktemp fallback cleanup -----------------------------------------------
printf '\n[fallback] the mktemp backup dir is removed on exit\n'
green "fallback: no RUNNER_TEMP, no --backup-dir -> uploaded, and the mktemp copy is gone" chk_fallback_cleaned setup_norunner
# shellcheck disable=SC2016 # sed expressions match literal script text
MF="$(mk_mutant fallback-kept 's/^  if \[\[ -n "$FALLBACK_DIR" && -d "$FALLBACK_DIR" \]\]; then rm -rf "$FALLBACK_DIR"; fi$/  :/')"
red "fallback mutant: the mktemp dir is not registered for cleanup" "$MF" chk_fallback_cleaned '^fallback-left:1$' setup_norunner

# --- the OLD ids are the gate library's (one copy, shared with the job and the predicate) ----
printf '\n[one source] the script classifies by the library it sources\n'
LT="$SBX/libtree"
mkdir -p "$LT/apps/web-platform/infra/scripts" "$LT/tests/scripts/lib" || exit 2
cp "$PRISTINE" "$LT/apps/web-platform/infra/scripts/cf-account-state-migrate.sh" || exit 2
cp "$REPO/tests/scripts/lib/plan-gate-preamble.sh" "$LT/tests/scripts/lib/" || exit 2
sed "s/^CFAM_OLD_ZONE_ID=\"$OZ\"$/CFAM_OLD_ZONE_ID=\"$UNK\"/" "$LIB" >"$LT/tests/scripts/lib/cf-account-migrate-gate.sh"
if cmp -s "$LIB" "$LT/tests/scripts/lib/cf-account-migrate-gate.sh"; then printf '[FATAL] library copy did not change\n' >&2; exit 2; fi
green_mut "one source: a library naming another OLD zone makes the fixture's OLD-zone entries unknown-id, 0 removed" \
  "$LT/apps/web-platform/infra/scripts/cf-account-state-migrate.sh" chk_abort_unknown setup_2c

# --- Rehearsal. --------------------------------------------------------------
printf '\n[rehearsal] no aws call, local backup only\n'
rehearsal_dir_setup() { setup_mixed "$1"; : >"$1/noendpoint"; }
green "rehearsal --backup-dir: no aws call, one 0600 backup of the pre-migration state in that dir" \
  chk_rehearsal_dir rehearsal_dir_setup --new-zone "$NZ" --new-account "$NA" --rehearsal --backup-dir "__D__"
green "rehearsal without --backup-dir: backup under \$RUNNER_TEMP/cf-migrate" \
  chk_rehearsal_runner rehearsal_dir_setup --new-zone "$NZ" --new-account "$NA" --rehearsal
# shellcheck disable=SC2016 # sed expression matches literal script text
MR="$(mk_mutant rehearsal-upload 's/if \[\[ "$REHEARSAL" -eq 1 \]\]; then/if false; then/')"
red "rehearsal mutant: rehearsal branch skipped" "$MR" chk_rehearsal_runner '^aws-called$' setup_mixed \
  --new-zone "$NZ" --new-account "$NA" --rehearsal

# --- Invalid args exit 2 before touching terraform. --------------------------
printf '\n[args] invalid arguments\n'
bad_args() { # <label> [args...]
  local label="$1" d; shift
  d="$(new_run args)"; setup_mixed "$d"
  run_sut "$d" "$PRISTINE" "$@"
  r=1; [[ "$(rc_of "$d")" == 2 && ! -s "$d/calls.log" ]] && grep -q 'verdict=abort reason=usage' "$d/out.txt" && r=0
  verdict "$r" "args: $label -> exit 2, no terraform/aws call"
}
bad_args "unknown flag" --new-zone "$NZ" --new-account "$NA" --force
bad_args "missing --new-account" --new-zone "$NZ"
bad_args "missing value for --new-account" --new-zone "$NZ" --new-account
bad_args "33-char zone id" --new-zone "${NZ}a" --new-account "$NA"
bad_args "uppercase hex zone" --new-zone "ABCDEF0123456789ABCDEF0123456789" --new-account "$NA"
bad_args "31-char zone id" --new-zone "${NZ:1}" --new-account "$NA"
bad_args "new zone equals OLD zone" --new-zone "$OZ" --new-account "$NA"
bad_args "new account equals OLD account" --new-zone "$NZ" --new-account "$OA"
d="$(new_run args-noendpoint)"; setup_mixed "$d"; : >"$d/noendpoint"
run_sut "$d" "$PRISTINE"; WHY=""
r=1; [[ "$(rc_of "$d")" == 0 ]] && chk_r2_call_shape "$d" && r=0
verdict "$r" "args: non-rehearsal without R2_ENDPOINT uploads to the pinned endpoint ($WHY)"

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR: printf + exit 1, never this suite's own fail.
# ---------------------------------------------------------------------------
printf '\n'
EXPECTED_CASES=67
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] %d case(s) ran, expected exactly %d (a case was skipped, deleted or added without bumping the floor)\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$((PASS + FAIL))" -ne "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d != CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
printf 'cf-account-state-migrate: %d passed, %d failed (%d cases)\n' "$PASS" "$FAIL" "$CASES"
[[ "$FAIL" -eq 0 ]] || exit 1
