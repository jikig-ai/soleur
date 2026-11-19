#!/usr/bin/env bash
# cf-account-migrate-job.test.sh — battery for scripts/cf-account-migrate-job.sh, the body of
# .github/workflows/cf-account-migrate.yml (#12931, CTO L24/L43/L79).
#
# HARNESS
# - terraform, doppler, gh, aws, curl and ssh-keygen are PATH stubs; every call is appended to one
#   calls.log, so call ORDER is observable. The REAL phase gate and the REAL state-forget script run.
# - The terraform stub keeps two state stores: "remote" (the case dir) and "local" (rehearsal.tfstate
#   in a cwd whose backend_override.tf declares backend "local"). Log lines carry the store label,
#   so a rehearsal that wrote the remote store is visible, not inferred.
# - Plans served by the stub are built from the gate's own phase spec and the committed imports
#   file, so a PASS fixture tracks the one list; the -target/-replace checks compare argv with the
#   gate functions' output.
# - Refusals are proven load-bearing with sed mutants of a PRISTINE COPY: each mutant must differ
#   (cmp), parse (bash -n), and turn a check that is GREEN on pristine RED for the named reason.
# - Fixtures are synthesized; the OLD ids are derived from the state-forget script.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SUT="$HERE/scripts/cf-account-migrate-job.sh"
MIGRATE="$HERE/scripts/cf-account-state-migrate.sh"
[[ -f "$SUT" && -x "$MIGRATE" ]] || { printf '[FATAL] script under test missing\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

OZ="$(sed -n 's/^readonly OLD_ZONE_ID="\([0-9a-f]*\)"$/\1/p' "$MIGRATE")"
OA="$(sed -n 's/^readonly OLD_ACCOUNT_ID="\([0-9a-f]*\)"$/\1/p' "$MIGRATE")"
[[ "$OZ" =~ ^[0-9a-f]{32}$ && "$OA" =~ ^[0-9a-f]{32}$ ]] || { printf '[FATAL] cannot derive OLD ids\n' >&2; exit 2; }
SENTINEL="SENTINEL-SECRET-VALUE-DO-NOT-PRINT"

# shellcheck source=/dev/null
source "$REPO/tests/scripts/lib/cf-account-migrate-gate.sh" || { printf '[FATAL] cannot source the gate\n' >&2; exit 2; }
NZ="$CFAM_NEW_ZONE_ID"; NA="$CFAM_NEW_ACCOUNT_ID"

SBX="$(mktemp -d -t cf-migrate-job.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SBX"' EXIT INT TERM HUP
mkdir -p "$SBX/bin" "$SBX/runs" "$SBX/mut" || exit 2
PRISTINE="$SBX/pristine.sh"
cp "$SUT" "$PRISTINE" || exit 2

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"
  if [[ -n "${LAST_D:-}" && -f "$LAST_D/out.txt" ]]; then
    printf '    rc=%s; last output of %s:\n' "$(cat "$LAST_D/rc" 2>/dev/null)" "${LAST_D##*/}"
    tail -n 12 "$LAST_D/out.txt" "$LAST_D/err.txt" | sed 's/^/      /'
  fi
}
verdict() { CASES=$((CASES + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi; }

# INSTRUMENT SELF-TEST: both arms must move their counters, or every verdict below is decorative.
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
if [[ -f backend_override.tf ]] && grep -q 'backend "local"' backend_override.tf; then L=local; S="$PWD/rehearsal.tfstate"
else L=remote; S="$D/remote.tfstate"; fi
log() { printf 'terraform[%s] %s\n' "$L" "$*" >>"$D/calls.log"; }
mode() { if [[ -f "$D/mode.$1" ]]; then cat "$D/mode.$1"; else printf '0'; fi; }
case "${1:-}" in
  init)
    log "init dotterraform=$([[ -e .terraform ]] && echo yes || echo no)"; exit 0 ;;
  state)
    case "${2:-}" in
      pull) log "state pull"; cat "$S" ;;
      rm)
        shift 2; log "state rm argc=$#"
        jq --args '.serial += 1 | .show.values.root_module.resources |= map(select(.address as $x | any($ARGS.positional[]; . == $x) | not))' "$@" <"$S" >"$S.new" || exit 70
        mv "$S.new" "$S"
        for a in "$@"; do printf 'Removed %s\n' "$a"; done
        printf 'Successfully removed %d resource instance(s).\n' "$#" ;;
      *) log "UNEXPECTED $*"; exit 64 ;;
    esac ;;
  show)
    if [[ "$#" -eq 2 && "$2" == -json ]]; then log "show -json state"; jq '.show' "$S"
    elif [[ "$#" -eq 3 && "$2" == -json ]]; then log "show -json tfplan"; cat "$D/plan.json"
    else log "UNEXPECTED $*"; exit 64; fi ;;
  plan)
    shift; log "plan"; : >"$D/plan_args.$L"
    for a in "$@"; do
      printf '%s\n' "$a" >>"$D/plan_args.$L"
      [[ "$a" == -out=* ]] && : >"${a#-out=}"
    done
    printf 'Plan: stub\n'; exit "$(mode plan)" ;;
  apply) shift; log "apply $*"; exit "$(mode apply)" ;;
  *) log "UNEXPECTED $*"; exit 64 ;;
esac
STUB
cat >"$SBX/bin/doppler" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
printf 'doppler %s\n' "${1:-}" >>"$D/calls.log"
[[ "${1:-}" == run ]] || exit 64
while [[ $# -gt 0 && "$1" != -- ]]; do shift; done
shift
export TF_VAR_cf_zone_id="${TF_VAR_cf_zone_id:-$(sed -n 1p "$D/ids")}"
export TF_VAR_cf_account_id="${TF_VAR_cf_account_id:-$(sed -n 2p "$D/ids")}"
exec "$@"
STUB
cat >"$SBX/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
wf=""; st=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in --workflow) wf="${args[$((i + 1))]}" ;; --status) st="${args[$((i + 1))]}" ;; esac
done
printf 'gh %s %s workflow=%s status=%s\n' "${1:-}" "${2:-}" "$wf" "$st" >>"$D/calls.log"
[[ "${1:-} ${2:-}" == "run list" && -n "$wf" && -n "$st" ]] || exit 64
[[ -f "$D/mode.gh" ]] && exit 1
if [[ -f "$D/gh.$wf.$st" ]]; then cat "$D/gh.$wf.$st"; else printf '0\n'; fi
STUB
cat >"$SBX/bin/aws" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
printf 'aws %s %s\n' "${1:-}" "${2:-}" >>"$D/calls.log"
case "${1:-} ${2:-}" in
  "s3api list-objects-v2")
    if [[ -s "$D/backups.keys" ]]; then jq -Rn '{Contents: [inputs | {Key: .}]}' <"$D/backups.keys"; fi ;;
  "s3 cp")
    k="${4#s3://}"; printf '%s\n' "${k#*/}" >>"$D/backups.keys" ;;
  *) exit 64 ;;
esac
STUB
cat >"$SBX/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
url=""; ua=""; dump=0; prev=""
for a in "$@"; do
  [[ "$prev" == -A ]] && ua="$a"
  [[ "$prev" == -D ]] && dump=1
  [[ "$a" == https://* ]] && url="$a"
  prev="$a"
done
printf 'curl %s\n' "$url" >>"$D/calls.log"
if [[ -f "$D/mode.verify" ]]; then
  [[ "$dump" -eq 1 ]] && printf 'HTTP/2 200\r\n\r\n' || printf '500 '
  exit 0
fi
if [[ "$dump" -eq 1 ]]; then printf 'HTTP/2 200\r\nx-robots-tag: noindex\r\n\r\n'; exit 0; fi
case "$url" in
  https://www.soleur.ai/) printf '301 https://soleur.ai/' ;;
  https://soleur.ai/) [[ "$ua" == *GPTBot* ]] && printf '200 ' || printf '403 ' ;;
  https://soleur.ai/*) printf '301 https://soleur.ai/elsewhere/' ;;
  *) printf '404 ' ;;
esac
STUB
cat >"$SBX/bin/ssh-keygen" <<'STUB'
#!/usr/bin/env bash
f=""; prev=""
for a in "$@"; do [[ "$prev" == -f ]] && f="$a"; prev="$a"; done
[[ -n "$f" ]] || exit 64
: >"$f"; printf 'ssh-ed25519 AAAAstub test\n' >"$f.pub"
STUB
chmod +x "$SBX/bin/"*

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------
# build_plan <phase> <out>: a plan that satisfies the gate for <phase>, derived from the gate's spec.
build_plan() {
  local spec lit
  spec="$(cf_account_migrate_phase_spec "$1")" || return 1
  lit="$(_cfam_import_literals)" || return 1
  jq -n --argjson spec "$spec" --argjson lit "$lit" --arg s "$SENTINEL" '
    {format_version: "1.2", resource_changes: [
      $spec | to_entries[] | .key as $a | .value as $c
      | ({address: $a, mode: "managed", type: ($a | split(".")[0]), change: (
            if $c == "create" then {actions: ["create"], before: null, after: {value: $s}}
            elif $c == "import" then {actions: ["no-op"], importing: {id: $lit[$a]}, before: {}, after: {}}
            elif $c == "mutable" then {actions: ["update"], before: {}, after: {plaintext_value: $s}}
            else {actions: ["delete", "create"], before: {id: "tok-id-1"}, after: {value: $s}} end)}
         + (if $c == "replace" then {action_reason: "replace_by_request"} else {} end))
    ]}' >"$2"
}

# remote_state <file> <zone-for-record>: serial 7, two old-id candidates (unless migrated), an R2
# bucket and the replace target.
remote_state() {
  jq -n --arg z "$2" --arg a "$3" --arg oa "$OA" --arg s "$SENTINEL" '
    def r($addr; $t; $v): {address: $addr, mode: "managed", type: $t, name: "n", values: $v};
    {version: 4, serial: 7, lineage: "lin-1", show: {format_version: "1.0", values: {root_module: {resources: [
      r("cloudflare_record.dmarc"; "cloudflare_record"; {zone_id: $z, content: $s}),
      r("cloudflare_list.www_canonical"; "cloudflare_list"; {account_id: $a}),
      r("cloudflare_r2_bucket.luks"; "cloudflare_r2_bucket"; {account_id: $oa}),
      r("doppler_secret.cf_api_token_dns_edit"; "doppler_secret"; {id: "tok-id-1", value: $s})
    ]}}}}' >"$1"
}

LAST_D=""
# new_case <label> <phase> <rehearsal> -> sets LAST_D; a valid, converging case by default.
new_case() {
  local d
  d="$(mktemp -d "$SBX/runs/${1//[^A-Za-z0-9._-]/_}.XXXXXX")" || return 1
  mkdir -p "$d/root/.terraform" "$d/runner" || return 1
  printf 'terraform {}\n' >"$d/root/main.tf"; : >"$d/root/.terraform/marker"
  : >"$d/calls.log"; : >"$d/backups.keys"
  printf '%s\n%s\n' "$NZ" "$NA" >"$d/ids"
  remote_state "$d/remote.tfstate" "$OZ" "$OA"
  build_plan "$2" "$d/plan.json" || return 1
  printf '%s' "$2" >"$d/phase"; printf '%s' "$3" >"$d/rehearsal"; printf 'MIGRATE-CF-%s' "$2" >"$d/confirm"
  printf 'test %s' "$1" >"$d/reason"
  LAST_D="$d"
}

run_job() { # <dir> <script>
  local d="$1"
  env -u TF_VAR_cf_zone_id -u TF_VAR_cf_account_id \
    PATH="$SBX/bin:$PATH" STUB_DIR="$d" \
    MIGRATE_PHASE="$(cat "$d/phase")" CONFIRM="$(cat "$d/confirm")" REHEARSAL="$(cat "$d/rehearsal")" \
    REASON="$(cat "$d/reason")" GITHUB_WORKSPACE="$REPO" RUNNER_TEMP="$d/runner" INFRA_DIR="$d/root" \
    R2_ENDPOINT="https://r2.example.invalid" GH_TOKEN=stub GH_REPO=o/r DOPPLER_TOKEN=stub \
    GITHUB_STEP_SUMMARY="$d/summary.md" CFAM_VERIFY_TRIES=2 CFAM_VERIFY_SLEEP=0 \
    bash "$2" >"$d/out.txt" 2>"$d/err.txt"
  printf '%s' "$?" >"$d/rc"
}

rc_of() { cat "$1/rc"; }
calls() { grep -c -- "$2" "$1/calls.log"; }
line_no() { grep -n -m1 -- "$2" "$1/calls.log" | cut -d: -f1; }
refused_for() { [[ "$(rc_of "$1")" == 1 ]] && grep -q "verdict=refuse reason=$2\$" "$1/out.txt"; }

# argv_matches <dir> <label> <phase>: the plan's -target/-replace argv equals the gate's lists.
argv_matches() {
  local f="$1/plan_args.$2"
  [[ -s "$f" ]] || return 1
  diff <(grep '^-target=' "$f" | sort) <(cf_account_migrate_targets "$3" | sort) >/dev/null \
    && diff <(grep '^-replace=' "$f" | sort) <(cf_account_migrate_replaces "$3" | sort) >/dev/null
}

# ---------------------------------------------------------------------------
# CHECKS: each sets WHY on RED.
# ---------------------------------------------------------------------------
WHY=""
chk_refused_early() { # <dir> <reason>: refused before any terraform/doppler/aws call
  if ! refused_for "$1" "$2"; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  if grep -qE '^(terraform|doppler|aws)' "$1/calls.log"; then WHY="touched-infra"; return 1; fi
}
chk_bad_confirm() { chk_refused_early "$1" bad-confirm; }
chk_inflight() { chk_refused_early "$1" run-in-flight; }
chk_ids_refused() { # refused before init, any state write or plan
  if grep -q 'terraform\[remote\] state rm' "$1/calls.log"; then WHY="remote-state-rm"; return 1; fi
  if ! refused_for "$1" zone-id-not-new; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  if grep -q '^terraform' "$1/calls.log"; then WHY="terraform-called"; return 1; fi
}
chk_rehearsal_clean() { # PASS, no aws s3 cp, no apply, remote untouched, forget ran on the local copy
  if grep -q '^aws s3 cp' "$1/calls.log"; then WHY="aws-s3-cp"; return 1; fi
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="apply-called"; return 1; fi
  if [[ "$(jq -r .serial "$1/remote.tfstate")" != 7 ]]; then WHY="remote-serial"; return 1; fi
  if grep -q 'terraform\[remote\] state rm' "$1/calls.log"; then WHY="remote-state-rm"; return 1; fi
  if [[ "$(rc_of "$1")" != 0 ]]; then WHY="rc:$(rc_of "$1")"; return 1; fi
  grep -qx 'cf-account-migrate phase=[a-z-]* mode=rehearsal verdict=PASS applied=false' "$1/out.txt" || { WHY="no-pass-line"; return 1; }
}
chk_refuses_backup_write() {
  refused_for "$1" backup-written || { WHY="rc:$(rc_of "$1")"; return 1; }
}
chk_refuses_serial() {
  refused_for "$1" remote-serial-changed || { WHY="rc:$(rc_of "$1")"; return 1; }
}
chk_gate_blocks_apply() {
  if grep -q '^terraform\[remote\] apply' "$1/calls.log"; then WHY="apply-called"; return 1; fi
  refused_for "$1" gate-refused || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -q 'cf_account_migrate_gate: phase=redirects-dns verdict=REFUSE' "$1/out.txt" || { WHY="no-refuse-line"; return 1; }
}
chk_zone_rest_args() {
  argv_matches "$1" remote zone-rest || { WHY="argv-mismatch"; return 1; }
  grep -qx -- '-replace=doppler_secret.cf_api_token_dns_edit' "$1/plan_args.remote" || { WHY="no-replace"; return 1; }
}

# ---------------------------------------------------------------------------
# MUTANTS
# ---------------------------------------------------------------------------
mk_mutant() { # <name> <sed-expr>... -> prints the mutant path; aborts the suite on a vacuous mutant
  local name="$1" out="$SBX/mut/$1.sh" e; shift
  cp "$PRISTINE" "$out" || exit 2
  for e in "$@"; do sed -i -e "$e" "$out" || exit 2; done
  if cmp -s "$PRISTINE" "$out"; then printf '[FATAL] mutant %s is identical to pristine\n' "$name" >&2; exit 2; fi
  bash -n "$out" || { printf '[FATAL] mutant %s does not parse\n' "$name" >&2; exit 2; }
  printf '%s' "$out"
}
# red <label> <mutant> <check> <why-regex> <setup-fn>: GREEN on the base (pristine unless RED_BASE
# names an earlier mutant), RED on the mutant for <why>.
red() {
  local label="$1" mut="$2" chk="$3" why="$4" setup="$5" base="${RED_BASE:-$PRISTINE}"
  "$setup" base; run_job "$LAST_D" "$base"; WHY=""
  if ! "$chk" "$LAST_D"; then verdict 1 "$label: check is RED on the base (WHY=$WHY)"; return; fi
  "$setup" mutant; run_job "$LAST_D" "$mut"; WHY=""
  if "$chk" "$LAST_D"; then verdict 1 "$label: mutant survived ($chk stayed GREEN)"; return; fi
  if [[ "$WHY" =~ $why ]]; then verdict 0 "$label: RED as required (WHY=$WHY)"
  else verdict 1 "$label: RED for the wrong reason (WHY=$WHY, wanted /$why/)"; fi
}
green_mut() { # <label> <mutant> <check> <setup-fn>: another guard must still catch this mutant
  "$4" mutant; run_job "$LAST_D" "$2"; WHY=""
  if "$3" "$LAST_D"; then verdict 0 "$1"; else verdict 1 "$1 (WHY=$WHY)"; fi
}

setup_bad_confirm() { new_case "confirm-$1" redirects-dns true; printf 'MIGRATE-CF-zone-rest' >"$LAST_D/confirm"; }
setup_inflight() { new_case "inflight-$1" redirects-dns true; printf '1\n' >"$LAST_D/gh.apply-web-platform-infra.yml.waiting"; }
setup_old_ids() { new_case "oldids-$1" redirects-dns false; printf '%s\n%s\n' "$OZ" "$NA" >"$LAST_D/ids"; }
setup_rehearsal() { new_case "rehearsal-$1" redirects-dns true; }
setup_refuse_apply() {
  new_case "refuse-$1" redirects-dns false
  jq '.resource_changes += [{address: "cloudflare_record.app", mode: "managed", type: "cloudflare_record", change: {actions: ["delete"], before: {}, after: null}}]' \
    "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
}
setup_zone_rest_apply() { new_case "zrest-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; }

printf 'cf-account-migrate-job: battery\n'
cmp -s "$SUT" "$PRISTINE"; verdict "$?" "pristine copy equals the script under test"
for p in redirects-dns zone-rest; do
  remote_state "$SBX/fx.tfstate" "$NZ" "$NA" && jq .show "$SBX/fx.tfstate" >"$SBX/fx-state.json" \
    && build_plan "$p" "$SBX/fx.json" && cf_account_migrate_gate "$p" "$SBX/fx.json" "$SBX/fx-state.json" >/dev/null
  verdict "$?" "fixture: the derived $p plan passes the real gate (else every PASS row is void)"
done

# --- Input refusals -----------------------------------------------------------
printf '\n[inputs] refused before any infra call\n'
setup_bad_confirm c; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_bad_confirm "$LAST_D"; verdict "$?" "confirm for another phase -> reason=bad-confirm, no terraform/doppler/aws call ($WHY)"
new_case unknown redirects-dns true
printf 'tunnel' >"$LAST_D/phase"; printf 'MIGRATE-CF-tunnel' >"$LAST_D/confirm"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" unknown-phase; verdict "$?" "phase=tunnel (PR2) -> reason=unknown-phase ($WHY)"
new_case blank-reason redirects-dns true; printf '  ' >"$LAST_D/reason"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" no-reason; verdict "$?" "blank reason -> reason=no-reason ($WHY)"
new_case bad-rehearsal redirects-dns yes; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" bad-rehearsal; verdict "$?" "rehearsal=yes -> reason=bad-rehearsal ($WHY)"

# --- In-flight runs -------------------------------------------------------------
printf '\n[inflight] a queued/waiting/running run on any gated workflow refuses\n'
for spec in apply-web-platform-infra.yml:waiting apply-deploy-pipeline-fix.yml:queued cf-lb-overlay.yml:in_progress; do
  new_case "inflight-${spec%%:*}" redirects-dns true; printf '1\n' >"$LAST_D/gh.${spec%%:*}.${spec#*:}"
  run_job "$LAST_D" "$PRISTINE"; WHY=""
  chk_inflight "$LAST_D"; verdict "$?" "${spec#*:} run of ${spec%%:*} -> reason=run-in-flight ($WHY)"
done
new_case inflight-ghfail redirects-dns false; : >"$LAST_D/mode.gh"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" runs-unreadable; verdict "$?" "gh run list failure -> reason=runs-unreadable, fail closed ($WHY)"
new_case inflight-all redirects-dns true; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(calls "$LAST_D" '^gh run list')" -eq 15 ]] && r=0
verdict "$r" "the in-flight check reads 3 workflows x 5 live statuses (15 calls)"

# --- Id preflight ---------------------------------------------------------------
printf '\n[ids] Doppler must resolve the NEW ids before anything is written\n'
setup_old_ids x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_ids_refused "$LAST_D"; verdict "$?" "old zone id in Doppler -> reason=zone-id-not-new before init/forget ($WHY)"
new_case oldacct redirects-dns false; printf '%s\n%s\n' "$NZ" "$OA" >"$LAST_D/ids"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" account-id-not-new && ! grep -q '^terraform' "$LAST_D/calls.log" && r=0
verdict "$r" "old account id in Doppler -> reason=account-id-not-new before any terraform call"
r=1; ! grep -q "$OA" "$LAST_D/out.txt" "$LAST_D/err.txt" && r=0
verdict "$r" "the id preflight does not print the resolved ids"

# --- Rehearsal --------------------------------------------------------------------
printf '\n[rehearsal] local-backend scratch copy, nothing written\n'
setup_rehearsal x; run_job "$LAST_D" "$PRISTINE"; D_REH="$LAST_D"; WHY=""
chk_rehearsal_clean "$D_REH"; verdict "$?" "redirects-dns rehearsal: PASS, no aws s3 cp, no apply, remote serial 7 ($WHY)"
r=1; grep -q 'terraform\[local\] state rm argc=2' "$D_REH/calls.log" && r=0
verdict "$r" "rehearsal: the real state forget removed the 2 old-id entries from the LOCAL copy"
r=1; grep -qx 'cf-account-migrate rehearsal remote_serial=7 serial_unchanged=true backups_unchanged=true' "$D_REH/out.txt" && r=0
verdict "$r" "rehearsal: prints the serial/backups no-write assertion"
r=1; grep -q 'terraform\[local\] init dotterraform=no' "$D_REH/calls.log" && r=0
verdict "$r" "rehearsal: the scratch root is initialised without the copied .terraform"
argv_matches "$D_REH" local redirects-dns; verdict "$?" "rehearsal: plan -target/-replace argv equals the gate's redirects-dns lists"
r=1; [[ ! -e "$D_REH/plan_args.remote" ]] && r=0
verdict "$r" "rehearsal: no plan ran against the remote backend"
r=1; grep -q 'cf_account_migrate_gate: phase=redirects-dns verdict=PASS ' "$D_REH/out.txt" && r=0
verdict "$r" "rehearsal: prints the gate verdict line"
r=1; [[ ! -e "$D_REH/runner/cf-migrate" ]] && r=0
verdict "$r" "rehearsal: \$RUNNER_TEMP/cf-migrate removed on exit"
new_case reh-refuse redirects-dns true
jq '.resource_changes[0].change.actions = ["update"]' "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" rehearsal-refused && grep -q 'serial_unchanged=true' "$LAST_D/out.txt" \
  && ! grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "rehearsal + gate REFUSE: reason=rehearsal-refused, no-write assertion still ran, no apply"
new_case reh-zrest zone-rest true; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; chk_rehearsal_clean "$LAST_D" && ! grep -q 'state rm' "$LAST_D/calls.log" && argv_matches "$LAST_D" local zone-rest && r=0
verdict "$r" "zone-rest rehearsal: PASS, no state forget, -replace argv equals the gate's list ($WHY)"

# --- Apply --------------------------------------------------------------------------
printf '\n[apply] forget -> plan -> gate -> apply, only on PASS\n'
new_case apply redirects-dns false; run_job "$LAST_D" "$PRISTINE"; D_AP="$LAST_D"
r=1; [[ "$(rc_of "$D_AP")" == 0 ]] && grep -qx 'cf-account-migrate phase=redirects-dns mode=apply verdict=PASS applied=true' "$D_AP/out.txt" && r=0
verdict "$r" "redirects-dns apply: rc 0, verdict=PASS applied=true"
b="$(line_no "$D_AP" '^aws s3 cp')"; s="$(line_no "$D_AP" 'terraform\[remote\] state rm')"
p="$(line_no "$D_AP" 'terraform\[remote\] plan')"; g="$(line_no "$D_AP" 'show -json tfplan')"; a="$(line_no "$D_AP" 'terraform\[remote\] apply')"
r=1; [[ -n "$b" && -n "$s" && -n "$p" && -n "$g" && -n "$a" ]] && ((b < s && s < p && p < g && g < a)) && r=0
verdict "$r" "apply order: backup upload < state rm < plan < show tfplan < apply"
r=1; [[ "$(calls "$D_AP" 'terraform\[remote\] apply')" -eq 1 ]] && grep -q 'apply .*cf-migrate/tfplan$' "$D_AP/calls.log" && r=0
verdict "$r" "apply runs exactly once, on the graded tfplan"
argv_matches "$D_AP" remote redirects-dns; verdict "$?" "apply: plan -target/-replace argv equals the gate's redirects-dns lists"
r=1; grep -qx 'cf-account-migrate verify=redirects-dns verdict=ok' "$D_AP/out.txt" && r=0
verdict "$r" "apply: post-apply redirect/noindex/crawler probes pass"
r=1; ! grep -q "$SENTINEL" "$D_AP/out.txt" "$D_AP/err.txt" "$D_REH/out.txt" "$D_REH/err.txt" && r=0
verdict "$r" "no state or plan value reaches stdout/stderr (sentinel absent)"
setup_refuse_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_gate_blocks_apply "$LAST_D"; verdict "$?" "gate REFUSE blocks apply: reason=gate-refused, no apply call ($WHY)"
new_case planfail redirects-dns false; printf '1' >"$LAST_D/mode.plan"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" gate-refused && grep -q 'Guard 4' "$LAST_D/out.txt" && ! grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "plan failure (e.g. Guard 4 validation) surfaces an ::error:: naming Guard 4, no apply"
setup_zone_rest_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && chk_zone_rest_args "$LAST_D" && ! grep -qE 'state rm|^curl' "$LAST_D/calls.log" && r=0
verdict "$r" "zone-rest apply: no forget, no probes, -target/-replace argv equals the gate's lists, applied ($WHY)"
new_case verify-broken redirects-dns false; : >"$LAST_D/mode.verify"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" verify-failed && grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "probes failing after apply -> reason=verify-failed (the job goes red)"
new_case applyfail redirects-dns false; printf '1' >"$LAST_D/mode.apply"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" apply-failed && ! grep -q '^curl' "$LAST_D/calls.log" && r=0
verdict "$r" "terraform apply failure -> reason=apply-failed, no probes"
new_case rerun redirects-dns false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && grep -q 'cf-state-migrate verdict=ok removed=0' "$LAST_D/out.txt" && ! grep -q 'state rm' "$LAST_D/calls.log" && r=0
verdict "$r" "redirects-dns re-dispatch after migration: forget removes 0, apply proceeds"

# --- Mutations ------------------------------------------------------------------------
printf '\n[mutations] each refusal is load-bearing\n'
M1="$(mk_mutant confirm 's/|| refuse bad-confirm/|| true/')"
red "M1 confirm check removed" "$M1" chk_bad_confirm '^not-refused' setup_bad_confirm
M2="$(mk_mutant inflight 's/|| refuse run-in-flight/|| true/')"
red "M2 in-flight refusal removed" "$M2" chk_inflight '^not-refused' setup_inflight
M3="$(mk_mutant ids 's/^  check_ids$/  :/')"
red "M3 id preflight removed (forget would run on old ids)" "$M3" chk_ids_refused '^remote-state-rm$' setup_old_ids
# shellcheck disable=SC2016 # sed expressions match literal script text
M4="$(mk_mutant rehearsal-flag 's/state_migrate --rehearsal --backup-dir "$W\/backup"/state_migrate/')"
red "M4 rehearsal forget without --rehearsal" "$M4" chk_rehearsal_clean '^aws-s3-cp$' setup_rehearsal
green_mut "M4: the job's own no-new-backup assertion refuses it (reason=backup-written)" "$M4" chk_refuses_backup_write setup_rehearsal
# shellcheck disable=SC2016
M4B="$(mk_mutant rehearsal-flag-noassert 's/state_migrate --rehearsal --backup-dir "$W\/backup"/state_migrate/' 's/|| refuse backup-written/|| true/')"
RED_BASE="$M4" red "M4b: M4 plus the backups assertion removed" "$M4B" chk_refuses_backup_write '^rc:0$' setup_rehearsal
M5="$(mk_mutant no-override '/backend_override\.tf"$/d')"
red "M5 scratch root without the local-backend override" "$M5" chk_rehearsal_clean '^remote-serial$' setup_rehearsal
green_mut "M5: the job's own remote-serial assertion refuses it" "$M5" chk_refuses_serial setup_rehearsal
M5B="$(mk_mutant no-override-noassert '/backend_override\.tf"$/d' 's/|| refuse remote-serial-changed/|| true/')"
RED_BASE="$M5" red "M5b: M5 plus the serial assertion removed" "$M5B" chk_refuses_serial '^rc:0$' setup_rehearsal
M6="$(mk_mutant no-gate 's/plan_and_gate || refuse gate-refused/plan_and_gate || true/')"
red "M6 apply not conditioned on the gate" "$M6" chk_gate_blocks_apply '^apply-called$' setup_refuse_apply
# shellcheck disable=SC2016
M7="$(mk_mutant no-replace 's/ \${REPLACE_ARGS\[@\]+"\${REPLACE_ARGS\[@\]}"}//')"
red "M7 -replace args dropped" "$M7" chk_zone_rest_args '^argv-mismatch$' setup_zone_rest_apply
# shellcheck disable=SC2016
M8="$(mk_mutant always-apply 's/if \[\[ "$REHEARSAL" == true \]\]; then run_rehearsal; else run_apply; fi/run_apply/')"
red "M8 rehearsal dispatch routed to the apply path" "$M8" chk_rehearsal_clean '^(apply-called|aws-s3-cp|remote-state-rm)$' setup_rehearsal

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR: printf + exit 1, never this suite's own fail.
# ---------------------------------------------------------------------------
printf '\n'
EXPECTED_CASES=49
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] %d case(s) ran, expected exactly %d (a case was skipped, deleted or added without bumping the floor)\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$((PASS + FAIL))" -ne "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d != CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
printf 'cf-account-migrate-job: %d passed, %d failed (%d cases)\n' "$PASS" "$FAIL" "$CASES"
[[ "$FAIL" -eq 0 ]] || exit 1
