#!/usr/bin/env bash
# Suite for apps/web-platform/infra/scripts/cf-account-migration-complete.sh (#12931 Guard 3,
# CTO ruling L79): the migration-in-progress predicate the infra-credentials loader runs as its
# last step.
#
# Three layers, all offline against synthesized fixtures (cq-test-fixtures-synthesized-only):
#   A. the evaluator on local raw-tfstate fixtures (complete, every incomplete class, unreadable);
#   B. the scope decision (gated / exempt workflow / exempt job / the web-2 exception);
#   C. the --from-r2 wrapper end to end, under a stub `aws` and a stub `doppler` that REFUSE any
#      call they were not told to expect (exit 64), so a dropped `-c prd_terraform` or a credential
#      in argv cannot pass by accident.
# Then mutation rows: each seds a COPY of the script, proves the copy differs, and re-runs the
# named row against it. The row must go RED, for the reason it names.
#
# The required address set is DERIVED from tests/scripts/lib/cf-account-migrate-gate.sh, the one
# list; a literal sample below stops a silently shrunk gate from shrinking this suite with it.
#
# Run: bash apps/web-platform/infra/cf-account-migration-complete.test.sh
#
# SC2016: the single-quoted jq programs and eval'd row bodies expand later, on purpose.
# SC2329: the row functions are invoked indirectly, through check / mut_row.
# shellcheck disable=SC2016,SC2329
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$HERE/scripts/cf-account-migration-complete.sh"
GATE="$REPO/tests/scripts/lib/cf-account-migrate-gate.sh"

PASS=0
FAIL=0
CASES=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
# Every verdict goes through ok()/no(): CASES moves at the CALL SITE, so a neutered pass()/fail()
# shows up as PASS+FAIL != CASES at the bottom.
ok() { CASES=$((CASES + 1)); pass "$1"; }
no() { CASES=$((CASES + 1)); fail "$1"; }
check() { if "${@:2}"; then ok "$1"; else no "$1"; fi; }

# Instrument self-test: drive both verdicts once, require all three counters to move, unwind.
_pc_p=$PASS; _pc_f=$FAIL; _pc_c=$CASES
ok "instrument self-test" >/dev/null
no "instrument self-test" >/dev/null
if (( PASS != _pc_p + 1 || FAIL != _pc_f + 1 || CASES != _pc_c + 2 )); then
  printf '[FATAL] instrument self-test: pass()/fail() did not move their counters (PASS %d->%d, FAIL %d->%d, CASES %d->%d)\n' \
    "$_pc_p" "$PASS" "$_pc_f" "$FAIL" "$_pc_c" "$CASES" >&2
  exit 2
fi
PASS=$_pc_p; FAIL=$_pc_f; CASES=$_pc_c
# check() decides most rows, so it gets its own self-test (C1): a false probe must add one
# failure, a true one one pass, each one case. Unwound afterwards.
check "check() self-test false probe" false >/dev/null
check "check() self-test true probe" true >/dev/null
if (( PASS != _pc_p + 1 || FAIL != _pc_f + 1 || CASES != _pc_c + 2 )); then
  printf '[FATAL] instrument self-test: check() did not map a probe to its verdict\n' >&2
  exit 2
fi
PASS=$_pc_p; FAIL=$_pc_f; CASES=$_pc_c

[[ -f "$SCRIPT" ]] || { printf '[FATAL] script missing: %s\n' "$SCRIPT" >&2; exit 2; }
[[ -f "$GATE" ]] || { printf '[FATAL] gate library missing: %s\n' "$GATE" >&2; exit 2; }
REAL_JQ="$(command -v jq)" || { printf '[FATAL] need jq\n' >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR%/}/cfam-test.XXXXXXXX")"
case "$WORK" in /*/*) ;; *) printf '[FATAL] bad work dir %s\n' "$WORK" >&2; exit 2 ;; esac
trap 'rm -rf "$WORK"' EXIT

NZ=951ce525552201ec6c696b24251abed7
NA=66d4f93f7397f196544e9fe84c3557c2
OZ=5af02a2f394e9ba6e0ea23c381a26b67
OA=4d5ba6f096b2686fbdd404167dd4e125
TUN="cloudflare_zero_trust_tunnel_cloudflared.web"
# A synthesized attribute value the script must never echo.
SENTINEL="SENTINEL-ATTR-not-a-real-value-0001"

# ── the required set, derived from the gate (never re-typed) ───────────────────────────────
REQ="$WORK/required.json"
(
  # shellcheck source=/dev/null
  source "$GATE"
  { while IFS= read -r ph; do cf_account_migrate_phase_spec "$ph"; done < <(cf_account_migrate_phases); } \
    | jq -s 'map(keys_unsorted) | add | unique'
) > "$REQ" || { printf '[FATAL] could not derive the required set from %s\n' "$GATE" >&2; exit 2; }
N_REQ="$(jq length "$REQ")"
mapfile -t REQ_ADDRS < <(jq -r '.[]' "$REQ")
if (( N_REQ >= 40 )) && jq -e 'index("cloudflare_record.www") and index("cloudflare_ruleset.bulk_redirects") and index("doppler_secret.cf_api_token_dns_edit") and index("cloudflare_pages_project.docs")' "$REQ" >/dev/null; then
  ok "required set derived from the gate: ${N_REQ} addresses, literal sample present"
else
  no "required set derived from the gate looks shrunk (n=${N_REQ})"
fi

# ── fixtures ───────────────────────────────────────────────────────────────────────────────
# The complete state: every required address (cloudflare_* on the new zone), the tunnel on the new
# account, an R2 bucket on the OLD account (must stay legal), a non-Cloudflare resource, an indexed
# cloudflare_record, a module resource, and a DATA source carrying the old zone (data is not state
# we migrate). Every cloudflare instance carries the sentinel attribute.
COMPLETE="$WORK/complete.json"
jq -n --slurpfile r "$REQ" --arg nz "$NZ" --arg na "$NA" --arg oz "$OZ" --arg oa "$OA" --arg s "$SENTINEL" '
  def res($t; $n; $attrs): {mode: "managed", type: $t, name: $n, provider: "provider[\"registry.terraform.io/x/y\"]", instances: [{schema_version: 0, attributes: $attrs}]};
  {version: 4, terraform_version: "1.10.5", serial: 7, lineage: "fixture-lineage", outputs: {},
   resources: (
     [ $r[0][] | split(".") as $p
       | res($p[0]; $p[1]; (if ($p[0] | startswith("cloudflare_")) then {zone_id: $nz, account_id: $na, content: $s} else {name: "x"} end)) ]
     + [ res("cloudflare_zero_trust_tunnel_cloudflared"; "web"; {account_id: $na, name: "web", content: $s}),
         res("cloudflare_r2_bucket"; "terraform_state_privileged"; {account_id: $oa, name: "b", content: $s}),
         res("hcloud_server"; "web"; {name: "web-9"}),
         {mode: "managed", type: "cloudflare_record", name: "indexed", instances: [
           {index_key: "a", attributes: {zone_id: $nz, content: $s}}, {index_key: "b", attributes: {zone_id: $nz, content: $s}}]},
         ({module: "module.edge"} + res("cloudflare_ruleset"; "mod"; {zone_id: $nz, content: $s})),
         {mode: "data", type: "cloudflare_zone", name: "legacy", instances: [{attributes: {zone_id: $oz, account_id: $oa}}]} ])}' > "$COMPLETE"

# mut_state <out> <jq filter> — derive a fixture from the complete one.
mut_state() { jq "$2" "$COMPLETE" > "$1"; }

# run_eval <script> <out-prefix> [args...] — sets RC; stdout+stderr in <prefix>.out
run_eval() {
  local s="$1" pre="$2"; shift 2
  env -i PATH="$(dirname "$REAL_JQ"):/usr/bin:/bin" HOME="$WORK" TMPDIR="$WORK" \
    bash "$s" "$@" > "$pre.out" 2>&1
  RC=$?
}
has() { grep -qF -- "$2" "$1.out"; }
no_leak() { ! grep -qF -- "$SENTINEL" "$1.out" && ! grep -qF -- "$OZ" "$1.out" && ! grep -qF -- "$NA" "$1.out"; }

# ── A. evaluator rows (each a function of the script, so mutation rows can re-run it) ────────
row_complete_passes() { run_eval "$1" "$WORK/a1" "$COMPLETE"; [[ $RC -eq 0 ]] && has "$WORK/a1" "verdict=cf-account-migration-complete mode=full"; }
row_old_zone_refused() {
  mut_state "$WORK/a2.json" '(.resources[] | select(.type=="cloudflare_record" and .name=="www") | .instances[0].attributes.zone_id) = "'"$OZ"'"'
  run_eval "$1" "$WORK/a2" "$WORK/a2.json"
  [[ $RC -eq 1 ]] && has "$WORK/a2" "old-id cloudflare_record.www" && has "$WORK/a2" "verdict=cf-account-migration-in-progress" && has "$WORK/a2" "::error" && has "$WORK/a2" "runbooks/cloudflare-account-migration.md"
}
row_old_account_refused() {
  mut_state "$WORK/a3.json" '(.resources[] | select(.type=="cloudflare_pages_project") | .instances[0].attributes.account_id) = "'"$OA"'"'
  run_eval "$1" "$WORK/a3" "$WORK/a3.json"
  [[ $RC -eq 1 ]] && has "$WORK/a3" "old-id cloudflare_pages_project.docs"
}
row_old_indexed_named() {
  mut_state "$WORK/a4.json" '(.resources[] | select(.name=="indexed") | .instances[1].attributes.zone_id) = "'"$OZ"'"'
  run_eval "$1" "$WORK/a4" "$WORK/a4.json"
  [[ $RC -eq 1 ]] && has "$WORK/a4" 'old-id cloudflare_record.indexed["b"]' && ! has "$WORK/a4" 'cloudflare_record.indexed["a"]'
}
row_old_module_named() {
  mut_state "$WORK/a5.json" '(.resources[] | select(.module=="module.edge") | .instances[0].attributes.zone_id) = "'"$OZ"'"'
  run_eval "$1" "$WORK/a5" "$WORK/a5.json"
  [[ $RC -eq 1 ]] && has "$WORK/a5" "old-id module.edge.cloudflare_ruleset.mod"
}
row_third_zone_refused() {
  mut_state "$WORK/a24.json" '(.resources[] | select(.type=="cloudflare_record" and .name=="www") | .instances[0].attributes.zone_id) = "0123456789abcdef0123456789abcdef"'
  run_eval "$1" "$WORK/a24" "$WORK/a24.json"
  [[ $RC -eq 1 ]] && has "$WORK/a24" "unknown-id cloudflare_record.www" && ! has "$WORK/a24" "old-id"
}
row_third_account_refused() {
  mut_state "$WORK/a25.json" '(.resources[] | select(.type=="cloudflare_pages_project") | .instances[0].attributes.account_id) = "fedcba9876543210fedcba9876543210"'
  run_eval "$1" "$WORK/a25" "$WORK/a25.json"
  [[ $RC -eq 1 ]] && has "$WORK/a25" "unknown-id cloudflare_pages_project.docs"
}
row_unbound_ids_pass() {
  # null, absent and "" all mean "not bound to an id": an account-level object carries no zone.
  mut_state "$WORK/a26.json" '(.resources[] | select(.type=="cloudflare_pages_project") | .instances[0].attributes.zone_id) = ""
    | (.resources[] | select(.type=="cloudflare_list" and .name=="www_canonical") | .instances[0].attributes) |= del(.zone_id)
    | (.resources[] | select(.type=="cloudflare_record" and .name=="dmarc") | .instances[0].attributes.account_id) = null'
  run_eval "$1" "$WORK/a26" "$WORK/a26.json"
  [[ $RC -eq 0 ]] && has "$WORK/a26" "verdict=cf-account-migration-complete mode=full"
}
row_r2_old_passes() {
  mut_state "$WORK/a6.json" '.resources += [{mode:"managed",type:"cloudflare_r2_custom_domain",name:"x",instances:[{attributes:{zone_id:"'"$OZ"'",account_id:"'"$OA"'"}}]}]'
  run_eval "$1" "$WORK/a6" "$WORK/a6.json"
  [[ $RC -eq 0 ]] && ! has "$WORK/a6" "old-id"
}
row_tunnel_absent_refused() {
  mut_state "$WORK/a7.json" '.resources |= map(select(.type != "cloudflare_zero_trust_tunnel_cloudflared"))'
  run_eval "$1" "$WORK/a7" "$WORK/a7.json"
  [[ $RC -eq 1 ]] && has "$WORK/a7" "tunnel-absent $TUN"
}
row_tunnel_old_refused() {
  mut_state "$WORK/a8.json" '(.resources[] | select(.type=="cloudflare_zero_trust_tunnel_cloudflared") | .instances[0].attributes.account_id) = "'"$OA"'"'
  run_eval "$1" "$WORK/a8" "$WORK/a8.json"
  [[ $RC -eq 1 ]] && has "$WORK/a8" "tunnel-not-on-new-account $TUN"
}
row_tunnel_noattrs_refused() {
  mut_state "$WORK/a9.json" '(.resources[] | select(.type=="cloudflare_zero_trust_tunnel_cloudflared") | .instances[0]) |= del(.attributes)'
  run_eval "$1" "$WORK/a9" "$WORK/a9.json"
  [[ $RC -eq 1 ]] && has "$WORK/a9" "tunnel-not-on-new-account $TUN"
}
row_empty_state_refused() {
  jq -n '{version: 4, serial: 1, resources: []}' > "$WORK/a10.json"
  run_eval "$1" "$WORK/a10" "$WORK/a10.json"
  [[ $RC -eq 1 ]] && has "$WORK/a10" "no-cloudflare-resources" && has "$WORK/a10" "tunnel-absent"
}
row_zero_cloudflare_refused() {
  mut_state "$WORK/a11.json" '.resources |= map(select(.type | startswith("cloudflare_") | not))'
  run_eval "$1" "$WORK/a11" "$WORK/a11.json"
  [[ $RC -eq 1 ]] && has "$WORK/a11" "no-cloudflare-resources"
}
row_non_json_unreadable() {
  printf 'not json {' > "$WORK/a12.json"
  run_eval "$1" "$WORK/a12" "$WORK/a12.json"
  [[ $RC -eq 2 ]] && has "$WORK/a12" "verdict=cf-account-migration-state-unreadable reason=not-json"
}
row_version_unreadable() {
  mut_state "$WORK/a13.json" '.version = 3'
  run_eval "$1" "$WORK/a13" "$WORK/a13.json"
  [[ $RC -eq 2 ]] && has "$WORK/a13" "reason=state-version"
}
row_web2_tunnel_only_passes() {
  # Everything but the tunnel is old or missing: web2-replace mode still passes.
  mut_state "$WORK/a14.json" '(.resources[] | select(.type=="cloudflare_record") | .instances[].attributes.zone_id) = "'"$OZ"'" | .resources |= map(select(.type != "cloudflare_ruleset"))'
  run_eval "$1" "$WORK/a14" --mode web2-replace "$WORK/a14.json"
  [[ $RC -eq 0 ]] && has "$WORK/a14" "verdict=cf-account-migration-complete mode=web2-replace"
}
row_web2_tunnel_old_refused() {
  mut_state "$WORK/a15.json" '(.resources[] | select(.type=="cloudflare_zero_trust_tunnel_cloudflared") | .instances[0].attributes.account_id) = "'"$OA"'"'
  run_eval "$1" "$WORK/a15" --mode web2-replace "$WORK/a15.json"
  [[ $RC -eq 1 ]] && has "$WORK/a15" "tunnel-not-on-new-account" && has "$WORK/a15" "mode=web2-replace"
}
# Q6: an import-class cloudflare_record in state with no usable `content` was never normalized.
WWW_SEL='.resources[] | select(.type=="cloudflare_record" and .name=="www") | .instances[0].attributes.content'
row_unnorm_null() {
  mut_state "$WORK/a28.json" "($WWW_SEL) = null"
  run_eval "$1" "$WORK/a28" "$WORK/a28.json"
  [[ $RC -eq 1 ]] && has "$WORK/a28" "unnormalized cloudflare_record.www" && has "$WORK/a28" "verdict=cf-account-migration-in-progress"
}
row_unnorm_empty() {
  mut_state "$WORK/a29.json" "($WWW_SEL) = \"\""
  run_eval "$1" "$WORK/a29" "$WORK/a29.json"
  [[ $RC -eq 1 ]] && has "$WORK/a29" "unnormalized cloudflare_record.www"
}
row_unnorm_nonstring() {
  mut_state "$WORK/a30.json" "($WWW_SEL) = 5"
  run_eval "$1" "$WORK/a30" "$WORK/a30.json"
  [[ $RC -eq 1 ]] && has "$WORK/a30" "unnormalized cloudflare_record.www"
}
# An import that is not a record, a create-class ruleset and a record outside the spec: all ignored.
row_unnorm_out_of_scope() {
  mut_state "$WORK/a31.json" '(.resources[] | select((.type=="cloudflare_pages_project" and .name=="docs") or (.type=="cloudflare_ruleset" and .name=="bulk_redirects") or (.type=="cloudflare_record" and .name=="indexed")) | .instances[].attributes.content) = null'
  run_eval "$1" "$WORK/a31" "$WORK/a31.json"
  [[ $RC -eq 0 ]] && has "$WORK/a31" "verdict=cf-account-migration-complete mode=full" && ! has "$WORK/a31" "unnormalized"
}
# The real spec has no non-import cloudflare_record, so a library copy flips one to create.
CLASSLIB="$WORK/classlib"
mkdir -p "$CLASSLIB/apps/web-platform/infra/scripts" "$CLASSLIB/tests/scripts/lib"
cp "$REPO/tests/scripts/lib/plan-gate-preamble.sh" "$CLASSLIB/tests/scripts/lib/"
sed 's/"cloudflare_record\.www": "import"/"cloudflare_record.www": "create"/' "$GATE" > "$CLASSLIB/tests/scripts/lib/cf-account-migrate-gate.sh"
row_unnorm_non_import_class() {
  cmp -s "$GATE" "$CLASSLIB/tests/scripts/lib/cf-account-migrate-gate.sh" && return 1
  cp "$1" "$CLASSLIB/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
  mut_state "$WORK/a32.json" "($WWW_SEL) = null"
  run_eval "$CLASSLIB/apps/web-platform/infra/scripts/cf-account-migration-complete.sh" "$WORK/a32" "$WORK/a32.json"
  [[ $RC -eq 0 ]] && has "$WORK/a32" "verdict=cf-account-migration-complete mode=full" && ! has "$WORK/a32" "unnormalized"
}
# run_eval_recs <script> <prefix> <mode> <state> <body>: evaluate with cfam_required_records replaced.
run_eval_recs() {
  env -i PATH="$(dirname "$REAL_JQ"):/usr/bin:/bin" HOME="$WORK" TMPDIR="$WORK" \
    bash -c 'source "$1"; _cfam_load_gate || exit $?; eval "cfam_required_records() { $4; }"; cfam_evaluate "$2" "$3"' _ "$1" "$3" "$4" "$5" > "$2.out" 2>&1
  RC=$?
}
row_recs_fail() {
  run_eval_recs "$1" "$WORK/a33" full "$COMPLETE" 'return 1'
  [[ $RC -eq 2 ]] && has "$WORK/a33" "verdict=cf-account-migration-state-unreadable reason=required-set-unavailable"
}
row_recs_empty() {
  run_eval_recs "$1" "$WORK/a34" full "$COMPLETE" 'echo "[]"'
  [[ $RC -eq 2 ]] && has "$WORK/a34" "verdict=cf-account-migration-state-unreadable reason=required-set-empty"
}
row_recs_not_array() {
  run_eval_recs "$1" "$WORK/a35" full "$COMPLETE" 'echo "\"x\""'
  [[ $RC -eq 2 ]] && has "$WORK/a35" "verdict=cf-account-migration-state-unreadable reason=required-set-empty"
}
row_web2_null_content() {
  mut_state "$WORK/a36.json" "($WWW_SEL) = null"
  run_eval "$1" "$WORK/a36" --mode web2-replace "$WORK/a36.json"
  [[ $RC -eq 0 ]] && has "$WORK/a36" "verdict=cf-account-migration-complete mode=web2-replace" && ! has "$WORK/a36" "unnormalized"
}
row_web2_recs_fail() {
  run_eval_recs "$1" "$WORK/a37" web2-replace "$COMPLETE" 'return 1'
  [[ $RC -eq 0 ]] && has "$WORK/a37" "verdict=cf-account-migration-complete mode=web2-replace"
}

check "A1 complete state passes (R2 on the old account, data source on the old zone, module + indexed resources)" row_complete_passes "$SCRIPT"
check "A2 old zone id on a cloudflare_record refuses and names it" row_old_zone_refused "$SCRIPT"
check "A3 old account id on cloudflare_pages_project refuses and names it" row_old_account_refused "$SCRIPT"
check "A4 an old id on one instance of an indexed resource names that instance only" row_old_indexed_named "$SCRIPT"
check "A5 an old id inside a module is caught (address carries the module path)" row_old_module_named "$SCRIPT"
check "A6 any cloudflare_r2_* on the old ids is excepted" row_r2_old_passes "$SCRIPT"
check "A24 a third zone id (neither old nor new) refuses as unknown-id (allowlist, not an old-id denylist)" row_third_zone_refused "$SCRIPT"
check "A25 a third account id refuses as unknown-id" row_third_account_refused "$SCRIPT"
check "A26 a null, absent or empty zone_id / account_id is unbound and passes" row_unbound_ids_pass "$SCRIPT"
check "A7 tunnel absent refuses" row_tunnel_absent_refused "$SCRIPT"
check "A8 tunnel on the old account refuses" row_tunnel_old_refused "$SCRIPT"
check "A9 tunnel instance without attributes refuses" row_tunnel_noattrs_refused "$SCRIPT"
check "A10 empty state refuses (incomplete, not 'nothing old found')" row_empty_state_refused "$SCRIPT"
check "A11 zero cloudflare_* resources refuses" row_zero_cloudflare_refused "$SCRIPT"
check "A12 non-JSON is unreadable (rc 2)" row_non_json_unreadable "$SCRIPT"
check "A13 version != 4 is unreadable (rc 2)" row_version_unreadable "$SCRIPT"
check "A14 web2-replace passes with the tunnel new and everything else old or missing" row_web2_tunnel_only_passes "$SCRIPT"
check "A15 web2-replace refuses with the tunnel on the old account" row_web2_tunnel_old_refused "$SCRIPT"
check "A28 an import record with null content refuses as unnormalized" row_unnorm_null "$SCRIPT"
check "A29 an import record with empty-string content refuses as unnormalized" row_unnorm_empty "$SCRIPT"
check "A30 an import record with non-string content refuses as unnormalized" row_unnorm_nonstring "$SCRIPT"
check "A31 null content on a non-record import, a create-class ruleset or a record outside the spec is ignored" row_unnorm_out_of_scope "$SCRIPT"
check "A32 null content on a cloudflare_record whose spec class is not import is ignored" row_unnorm_non_import_class "$SCRIPT"
check "A33 a failed record list is unreadable (rc 2)" row_recs_fail "$SCRIPT"
check "A34 an empty record list is unreadable (rc 2)" row_recs_empty "$SCRIPT"
check "A35 a record list that is not an array is unreadable (rc 2)" row_recs_not_array "$SCRIPT"
check "A36 web2-replace ignores null content on an import record" row_web2_null_content "$SCRIPT"
check "A37 web2-replace never reads the record list, so its failure changes nothing" row_web2_recs_fail "$SCRIPT"

# A16: EVERY required address, removed one at a time, refuses and names it.
miss_ok=0; miss_bad=()
for a in "${REQ_ADDRS[@]}"; do
  t="${a%%.*}" n="${a#*.}"
  jq --arg t "$t" --arg n "$n" '.resources |= map(select((.type == $t and .name == $n and (.module // "") == "") | not))' "$COMPLETE" > "$WORK/m.json"
  run_eval "$SCRIPT" "$WORK/m" "$WORK/m.json"
  if [[ $RC -eq 1 ]] && has "$WORK/m" "missing $a"; then miss_ok=$((miss_ok + 1)); else miss_bad+=("$a(rc=$RC)"); fi
done
if (( miss_ok == N_REQ && ${#miss_bad[@]} == 0 )); then
  ok "A16 each of the ${N_REQ} required addresses, when absent, refuses and is named"
else
  no "A16 missing-address rows: ${miss_ok}/${N_REQ} caught; not caught: ${miss_bad[*]:0:5}"
fi
row_missing_refused() {
  mut_state "$WORK/a16.json" '.resources |= map(select((.type == "cloudflare_record" and .name == "spf_root") | not))'
  run_eval "$1" "$WORK/a16" "$WORK/a16.json"
  [[ $RC -eq 1 ]] && has "$WORK/a16" "missing cloudflare_record.spf_root"
}
check "A16b a removed required address (row form, for the mutation table) refuses" row_missing_refused "$SCRIPT"
# A38: EVERY import-class record, from the script's own list (pinned at 26), nulled one at a time.
row_unnorm_every_record() {
  local recs a
  recs="$(env -i PATH="$(dirname "$REAL_JQ"):/usr/bin:/bin" HOME="$WORK" TMPDIR="$WORK" \
    bash -c 'source "$1"; _cfam_load_gate || exit $?; cfam_required_records' _ "$1" | jq -r '.[]')" || return 1
  [[ "$(grep -c . <<<"$recs")" -eq 26 ]] || return 1
  while IFS= read -r a; do
    jq --arg t "${a%%.*}" --arg n "${a#*.}" \
      '(.resources[] | select(.type == $t and .name == $n and (.module // "") == "") | .instances[0].attributes.content) = null' \
      "$COMPLETE" > "$WORK/a38.json"
    run_eval "$1" "$WORK/a38" "$WORK/a38.json"
    [[ $RC -eq 1 ]] && grep -qE -- "unnormalized ${a//./\\.}( |\$)" "$WORK/a38.out" || return 1
  done <<<"$recs"
}
check "A38 each of the 26 import-class records, with null content, refuses as unnormalized and is named" row_unnorm_every_record "$SCRIPT"
# A17: an address present with ZERO instances is not "in state".
mut_state "$WORK/a17.json" '(.resources[] | select(.type=="cloudflare_record" and .name=="dmarc") | .instances) = []'
run_eval "$SCRIPT" "$WORK/a17" "$WORK/a17.json"
check "A17 a required address with zero instances counts as missing" eval '[[ $RC -eq 1 ]] && has "$WORK/a17" "missing cloudflare_record.dmarc"'

# A18: output hygiene — no attribute value and no id ever printed, on pass or refuse.
leak=0
for pre in a1 a2 a3 a4 a8 a10 a14 a15 a24 a28 a29 a30; do no_leak "$WORK/$pre" || leak=1; done
if [[ $leak -eq 0 ]]; then ok "A18 no attribute value or id appears in any verdict output"; else no "A18 an attribute value or id leaked into a verdict output"; fi

# A19-A21: unreadable / usage
run_eval "$SCRIPT" "$WORK/a19" "$WORK/does-not-exist.json"
check "A19 missing state file is unreadable (rc 2)" eval '[[ $RC -eq 2 ]] && has "$WORK/a19" "reason=state-file-unreadable"'
: > "$WORK/a20.json"; run_eval "$SCRIPT" "$WORK/a20" "$WORK/a20.json"
check "A20 empty (0-byte) state file is unreadable (rc 2)" eval '[[ $RC -eq 2 ]] && has "$WORK/a20" "state-unreadable"'
run_eval "$SCRIPT" "$WORK/a21" --mode partial "$COMPLETE"
check "A21 an unknown --mode is a usage error (rc 2)" eval '[[ $RC -eq 2 ]]'
run_eval "$SCRIPT" "$WORK/a22"
check "A22 no arguments is a usage error (rc 2)" eval '[[ $RC -eq 2 ]]'
mut_state "$WORK/a23.json" '.resources = {}'
run_eval "$SCRIPT" "$WORK/a23" "$WORK/a23.json"
check "A23 a non-array resources member is unreadable (rc 2)" eval '[[ $RC -eq 2 ]] && has "$WORK/a23" "reason=no-resources-array"'
# A27: the gate library is loaded once and its four ids shape-checked. A tree whose library names
# a malformed OLD zone id is unusable (rc 2), never evaluated against the state.
BADLIB="$WORK/badlib"
mkdir -p "$BADLIB/apps/web-platform/infra/scripts" "$BADLIB/tests/scripts/lib"
cp "$REPO/tests/scripts/lib/plan-gate-preamble.sh" "$BADLIB/tests/scripts/lib/"
sed 's/^CFAM_OLD_ZONE_ID=.*/CFAM_OLD_ZONE_ID="not-an-id"/' "$GATE" > "$BADLIB/tests/scripts/lib/cf-account-migrate-gate.sh"
row_bad_lib_unusable() {
  cp "$1" "$BADLIB/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
  run_eval "$BADLIB/apps/web-platform/infra/scripts/cf-account-migration-complete.sh" "$WORK/a27" "$COMPLETE"
  [[ $RC -eq 2 ]] && has "$WORK/a27" "reason=gate-library-unusable" && has "$WORK/a27" "(CFAM_OLD_ZONE_ID)"
}
if cmp -s "$GATE" "$BADLIB/tests/scripts/lib/cf-account-migrate-gate.sh"; then no "A27 fixture: the library copy did not change"
else check "A27 a gate library with a malformed OLD zone id is unusable (rc 2) and names it" row_bad_lib_unusable "$SCRIPT"; fi

# ── B. scope decisions ─────────────────────────────────────────────────────────────────────
scope_of() { # <script> <workflow-file> <job> <event> <web_host_key>
  env -i PATH="$(dirname "$REAL_JQ"):/usr/bin:/bin" \
    CFAM_WORKFLOW_REF="${2:+example-org/example-repo/.github/workflows/$2@refs/heads/main}" \
    CFAM_JOB="$3" CFAM_EVENT_NAME="$4" CFAM_WEB_HOST_KEY="$5" \
    bash -c 'source "$1"; cfam_scope' _ "$1" 2>/dev/null
}
row_scope() { [[ "$(scope_of "$1" "$2" "$3" "$4" "$5")" == "$6" ]]; }
row_scope_web1_refused() { row_scope "$1" apply-web-platform-infra.yml web_host_replace workflow_dispatch web-1 "gated full"; }
row_scope_web2_excepted() { row_scope "$1" apply-web-platform-infra.yml web_host_replace workflow_dispatch web-2 "gated web2-replace"; }
row_scope_unknown_job_gated() { row_scope "$1" apply-web-platform-infra.yml a_brand_new_job push "" "gated full"; }
row_scope_exempt_workflow() { row_scope "$1" scheduled-terraform-drift.yml drift-check schedule "" "exempt-workflow scheduled-terraform-drift.yml"; }
row_scope_exempt_job() { row_scope "$1" apply-web-platform-infra.yml entrypoint_audit workflow_dispatch "" "exempt-job entrypoint_audit"; }
row_scope_new_workflow_gated() { row_scope "$1" new-planner.yml plan push "" "gated full"; }

check "B1 apply-web-platform-infra.yml / apply is gated (full)" row_scope "$SCRIPT" apply-web-platform-infra.yml apply push "" "gated full"
check "B2 apply-deploy-pipeline-fix.yml / apply is gated (full)" row_scope "$SCRIPT" apply-deploy-pipeline-fix.yml apply workflow_dispatch "" "gated full"
check "B3 cf-lb-overlay.yml / staging_record is gated (no exempt jobs outside apply-web-platform-infra.yml)" row_scope "$SCRIPT" cf-lb-overlay.yml staging_record workflow_dispatch "" "gated full"
check "B4 scheduled-terraform-drift.yml is exempt" row_scope_exempt_workflow "$SCRIPT"
check "B5 cf-account-migrate.yml is exempt" row_scope "$SCRIPT" cf-account-migrate.yml cf_account_migrate workflow_dispatch "" "exempt-workflow cf-account-migrate.yml"
check "B6 infra-validation.yml (not a loader caller, not named) is gated by default" row_scope "$SCRIPT" infra-validation.yml plan pull_request "" "gated full"
for j in entrypoint_audit registry_pull_path_gate registry_store_restore; do
  check "B7 exempt job ${j} in apply-web-platform-infra.yml passes through" row_scope "$SCRIPT" apply-web-platform-infra.yml "$j" workflow_dispatch "" "exempt-job ${j}"
done
check "B8 an exempt job NAME inside another gated workflow is still gated" row_scope "$SCRIPT" apply-deploy-pipeline-fix.yml entrypoint_audit workflow_dispatch "" "gated full"
check "B9 a job missing from the exempt list in a gated workflow is gated (deny by default)" row_scope_unknown_job_gated "$SCRIPT"
check "B10 web_host_replace web-2 on workflow_dispatch takes the web2-replace exception" row_scope_web2_excepted "$SCRIPT"
check "B11 web_host_replace web-1 is refused the exception (full)" row_scope_web1_refused "$SCRIPT"
check "B12 web-2 on a non-dispatch event is not excepted" row_scope "$SCRIPT" apply-web-platform-infra.yml web_host_replace push web-2 "gated full"
check "B13 web-2 on a different job (web_host_create) is not excepted" row_scope "$SCRIPT" apply-web-platform-infra.yml web_host_create workflow_dispatch web-2 "gated full"
check "B14 an empty workflow_ref is gated (deny by default)" row_scope "$SCRIPT" "" apply push "" "gated full"
check "B15 a workflow_ref with a nested path is gated (deny by default)" row_scope "$SCRIPT" "sub/apply-web-platform-infra.yml" apply push "" "gated full"
check "B16 web-2 exception key match is exact (web-2x is not web-2)" row_scope "$SCRIPT" apply-web-platform-infra.yml web_host_replace workflow_dispatch web-2x "gated full"
check "B17 a workflow nobody named (new-planner.yml) is gated (deny by default, D1)" row_scope_new_workflow_gated "$SCRIPT"
for w in key-rotate.yml inngest-key-rotate.yml cf-lb-overlay.yaml apply-web-platform-infra-v2.yml; do
  check "B18 ${w} is gated (full)" row_scope "$SCRIPT" "$w" rotate workflow_dispatch "" "gated full"
done
EXEMPT_NAMES="$(env -i PATH="$(dirname "$REAL_JQ"):/usr/bin:/bin" bash -c 'source "$1"; printf "%s\n" "${CFAM_EXEMPT_WORKFLOWS[@]}"' _ "$SCRIPT")"
n_ex=0; bad_ex=""
while IFS= read -r w; do
  [[ -n "$w" ]] || continue
  n_ex=$((n_ex + 1))
  [[ "$(scope_of "$SCRIPT" "$w" any workflow_dispatch "")" == "exempt-workflow $w" ]] || bad_ex+=" $w"
done <<<"$EXEMPT_NAMES"
check "B19 each of the ${n_ex} named exempt workflows is exempt, the list holds both plan-only ones" \
  eval '[[ -z "$bad_ex" && $n_ex -ge 10 ]] && grep -qx cf-account-migrate.yml <<<"$EXEMPT_NAMES" && grep -qx scheduled-terraform-drift.yml <<<"$EXEMPT_NAMES"'

# ── C. the --from-r2 wrapper, end to end under stubs ──────────────────────────────────────
mkdir -p "$WORK/bin"
cat > "$WORK/bin/aws" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_CALLS:?}"
if [[ "${AWS_ACCESS_KEY_ID:-}" != "${STUB_EXPECT_KEY_ID:-}" || "${AWS_SECRET_ACCESS_KEY:-}" != "${STUB_EXPECT_SECRET:-}" || -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  echo "MISS: aws auth" >> "$STUB_CALLS"; exit 254
fi
if [[ "${AWS_DEFAULT_REGION:-}" != auto || "${AWS_REQUEST_CHECKSUM_CALCULATION:-}" != when_required \
      || "${AWS_RESPONSE_CHECKSUM_VALIDATION:-}" != when_required || "${AWS_EC2_METADATA_DISABLED:-}" != true ]]; then
  echo "MISS: aws R2 env prefix" >> "$STUB_CALLS"; exit 64
fi
if [[ $# -ne 7 || "$1 $2 $3" != "s3 cp s3://soleur-terraform-state/web-platform/terraform.tfstate" \
      || "$5" != "--only-show-errors" || "$6 $7" != "--endpoint-url https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com" ]]; then
  echo "MISS: aws $*" >> "$STUB_CALLS"; exit 64
fi
case "${STUB_AWS_MODE:-copy}" in
  copy) cp "${STUB_STATE:?}" "$4" ;;
  fail) exit 1 ;;
  timeout) exit 124 ;;
  empty) : ;;
esac
STUB
cat > "$WORK/bin/doppler" <<'STUB'
#!/usr/bin/env bash
set -u
printf 'doppler %s\n' "$*" >> "${STUB_CALLS:?}"
[[ "${STUB_DOPPLER_MODE:-}" == timeout ]] && exit 124
if [[ "${DOPPLER_TOKEN:-}" != "${STUB_EXPECT_LEGACY_TOKEN:-dp.st.LEGACY-FIXTURE}" ]]; then
  echo "Doppler Error: Invalid Auth token (unauthorized)" >&2; exit 1
fi
case "$*" in
  "secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform") printf '%s' "${STUB_LEGACY_ID:-}"; exit 0 ;;
  "secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform") printf '%s' "${STUB_LEGACY_SECRET:-}"; exit 0 ;;
esac
echo "MISS: doppler $*" >> "$STUB_CALLS"; exit 64
STUB
chmod +x "$WORK/bin/aws" "$WORK/bin/doppler"

TB_ID="fixture-tierb-key-id-0001"; TB_SEC="fixture-tierb-secret-0001"
LG_ID="fixture-legacy-key-id-0001"; LG_SEC="fixture-legacy-secret-0001"

# run_wrap <script> <prefix> <state> <workflow> <job> <event> <key> [VAR=VAL...] — sets RC
run_wrap() {
  local s="$1" pre="$2" st="$3" wf="$4" job="$5" ev="$6" key="$7"; shift 7
  mkdir -p "$pre.rt"; : > "$pre.calls"
  env -i PATH="$WORK/bin:$(dirname "$REAL_JQ"):/usr/bin:/bin" HOME="$WORK" TMPDIR="$WORK" \
    RUNNER_TEMP="$pre.rt" STUB_CALLS="$pre.calls" STUB_STATE="$st" \
    CFAM_WORKFLOW_REF="example-org/example-repo/.github/workflows/${wf}@refs/heads/main" \
    CFAM_JOB="$job" CFAM_EVENT_NAME="$ev" CFAM_WEB_HOST_KEY="$key" \
    "$@" bash "$s" --from-r2 > "$pre.out" 2>&1
  RC=$?
}
TIERB=(TF_STATE_AWS_ACCESS_KEY_ID="$TB_ID" TF_STATE_AWS_SECRET_ACCESS_KEY="$TB_SEC" STUB_EXPECT_KEY_ID="$TB_ID" STUB_EXPECT_SECRET="$TB_SEC")
LEGACY=(CFAM_DOPPLER_TOKEN_LEGACY="dp.st.LEGACY-FIXTURE" STUB_LEGACY_ID="$LG_ID" STUB_LEGACY_SECRET="$LG_SEC" STUB_EXPECT_KEY_ID="$LG_ID" STUB_EXPECT_SECRET="$LG_SEC")
no_miss() { ! grep -q '^MISS' "$1.calls"; }
creds_not_in_argv() { ! grep -qE "$TB_ID|$TB_SEC|$LG_ID|$LG_SEC" "$1.calls"; }
creds_only_masked() { ! grep -qE "$TB_ID|$TB_SEC|$LG_ID|$LG_SEC" < <(grep -vE '^::add-mask::' "$1.out"); }
rt_clean() { [[ -z "$(ls -A "$1.rt")" ]]; }

mut_state "$WORK/c-inprog.json" '(.resources[] | select(.type=="cloudflare_record" and .name=="www") | .instances[0].attributes.zone_id) = "'"$OZ"'"'
mut_state "$WORK/c-tunold.json" '(.resources[] | select(.type=="cloudflare_zero_trust_tunnel_cloudflared") | .instances[0].attributes.account_id) = "'"$OA"'" | (.resources[] | select(.type=="cloudflare_record" and .name=="www") | .instances[0].attributes.zone_id) = "'"$OZ"'"'

row_wrap_exempt_passthrough() {
  run_wrap "$1" "$WORK/c1" "$WORK/c-inprog.json" scheduled-terraform-drift.yml drift-check schedule ""
  [[ $RC -eq 0 ]] && [[ ! -s "$WORK/c1.calls" ]] && has "$WORK/c1" "scope=exempt-workflow"
}
row_wrap_tierb_complete() {
  run_wrap "$1" "$WORK/c2" "$COMPLETE" apply-web-platform-infra.yml apply push "" "${TIERB[@]}"
  [[ $RC -eq 0 ]] && has "$WORK/c2" "verdict=cf-account-migration-complete" && no_miss "$WORK/c2" && creds_not_in_argv "$WORK/c2" && creds_only_masked "$WORK/c2" && rt_clean "$WORK/c2"
}
row_wrap_legacy_creds() {
  run_wrap "$1" "$WORK/c3" "$COMPLETE" apply-deploy-pipeline-fix.yml apply workflow_dispatch "" "${LEGACY[@]}"
  [[ $RC -eq 0 ]] && has "$WORK/c3" "verdict=cf-account-migration-complete" && no_miss "$WORK/c3" \
    && has "$WORK/c3" "::add-mask::$LG_ID" && has "$WORK/c3" "::add-mask::$LG_SEC" \
    && grep -qF "doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform" "$WORK/c3.calls" \
    && creds_not_in_argv "$WORK/c3" && creds_only_masked "$WORK/c3"
}
row_wrap_copy_failure() {
  run_wrap "$1" "$WORK/c4" "$COMPLETE" apply-web-platform-infra.yml apply push "" "${TIERB[@]}" STUB_AWS_MODE=fail
  [[ $RC -eq 2 ]] && has "$WORK/c4" "verdict=cf-account-migration-state-unreadable reason=copy-failed" && rt_clean "$WORK/c4"
}
row_wrap_copy_timeout() {
  run_wrap "$1" "$WORK/c15" "$COMPLETE" apply-web-platform-infra.yml apply push "" "${TIERB[@]}" STUB_AWS_MODE=timeout
  [[ $RC -eq 2 ]] && has "$WORK/c15" "verdict=cf-account-migration-state-unreadable reason=copy-timeout" && no_miss "$WORK/c15"
}
row_wrap_doppler_timeout() {
  run_wrap "$1" "$WORK/c16" "$COMPLETE" apply-web-platform-infra.yml apply push "" "${LEGACY[@]}" STUB_DOPPLER_MODE=timeout
  [[ $RC -eq 2 ]] && has "$WORK/c16" "reason=no-credentials-legacy_read_timeout" && ! grep -q "s3 cp" "$WORK/c16.calls"
}
row_wrap_web1_refused() {
  run_wrap "$1" "$WORK/c5" "$WORK/c-inprog.json" apply-web-platform-infra.yml web_host_replace workflow_dispatch web-1 "${TIERB[@]}"
  [[ $RC -eq 1 ]] && has "$WORK/c5" "scope=gated mode=full" && has "$WORK/c5" "verdict=cf-account-migration-in-progress"
}
row_wrap_web2_tunnel_old_refused() {
  run_wrap "$1" "$WORK/c6" "$WORK/c-tunold.json" apply-web-platform-infra.yml web_host_replace workflow_dispatch web-2 "${TIERB[@]}"
  [[ $RC -eq 1 ]] && has "$WORK/c6" "mode=web2-replace" && has "$WORK/c6" "tunnel-not-on-new-account"
}
row_wrap_gated_unlisted_job() {
  run_wrap "$1" "$WORK/c7" "$WORK/c-inprog.json" apply-web-platform-infra.yml a_brand_new_job push "" "${TIERB[@]}"
  [[ $RC -eq 1 ]] && has "$WORK/c7" "verdict=cf-account-migration-in-progress"
}

check "C1 exempt workflow passes through without touching aws or doppler" row_wrap_exempt_passthrough "$SCRIPT"
check "C2 Tier-B TF_STATE_AWS_* pair: copied via env (never argv), complete -> rc 0, work dir removed" row_wrap_tierb_complete "$SCRIPT"
check "C3 legacy path: AWS_* read from prd_terraform with the legacy token, masked, complete -> rc 0" row_wrap_legacy_creds "$SCRIPT"
check "C4 copy failure fails closed (rc 2, reason=copy-failed), work dir removed" row_wrap_copy_failure "$SCRIPT"
run_wrap "$SCRIPT" "$WORK/c8" "$COMPLETE" apply-web-platform-infra.yml apply push "" "${TIERB[@]}" STUB_AWS_MODE=empty
check "C5 a copy that exits 0 but writes nothing fails closed (rc 2)" eval '[[ $RC -eq 2 ]] && has "$WORK/c8" "reason=copy-failed"'
run_wrap "$SCRIPT" "$WORK/c9" "$COMPLETE" apply-web-platform-infra.yml apply push ""
check "C6 no credential at all fails closed (rc 2) and never calls aws" eval '[[ $RC -eq 2 ]] && has "$WORK/c9" "reason=no-credentials-none" && ! grep -q "s3 cp" "$WORK/c9.calls"'
run_wrap "$SCRIPT" "$WORK/c10" "$COMPLETE" apply-web-platform-infra.yml apply push "" TF_STATE_AWS_ACCESS_KEY_ID="$TB_ID"
check "C7 a half-set Tier-B pair fails closed (rc 2)" eval '[[ $RC -eq 2 ]] && has "$WORK/c10" "reason=no-credentials-tier_b_half_set"'
run_wrap "$SCRIPT" "$WORK/c11" "$COMPLETE" apply-web-platform-infra.yml apply push "" CFAM_DOPPLER_TOKEN_LEGACY="dp.st.WRONG" STUB_LEGACY_ID="$LG_ID" STUB_LEGACY_SECRET="$LG_SEC"
check "C8 a rejected legacy token fails closed (rc 2) and never calls aws" eval '[[ $RC -eq 2 ]] && has "$WORK/c11" "reason=no-credentials-legacy_read_failed" && ! grep -q "s3 cp" "$WORK/c11.calls"'
check "C9 web_host_replace web-1 is refused while the migration is in progress" row_wrap_web1_refused "$SCRIPT"
check "C10 web_host_replace web-2 is refused while the tunnel is on the old account" row_wrap_web2_tunnel_old_refused "$SCRIPT"
run_wrap "$SCRIPT" "$WORK/c12" "$WORK/c-inprog.json" apply-web-platform-infra.yml web_host_replace workflow_dispatch web-2 "${TIERB[@]}"
check "C11 web_host_replace web-2 proceeds once the tunnel is new, even with other entries old" eval '[[ $RC -eq 0 ]] && has "$WORK/c12" "mode=web2-replace"'
check "C12 a gated-workflow job missing from the exempt list is gated" row_wrap_gated_unlisted_job "$SCRIPT"
check "C15 an aws copy that times out (rc 124) fails closed with reason=copy-timeout" row_wrap_copy_timeout "$SCRIPT"
check "C16 a Doppler read that times out (rc 124) fails closed with a named reason, no aws call" row_wrap_doppler_timeout "$SCRIPT"
run_wrap "$SCRIPT" "$WORK/c13" "$COMPLETE" apply-web-platform-infra.yml entrypoint_audit workflow_dispatch ""
check "C13 exempt job passes through with no credential and no aws call" eval '[[ $RC -eq 0 ]] && [[ ! -s "$WORK/c13.calls" ]]'
NOAWS_PATH="$WORK/nobin:$(dirname "$REAL_JQ"):/bin"
if PATH="$NOAWS_PATH" command -v aws >/dev/null 2>&1; then
  printf '  [skip] C14: an aws CLI sits beside jq or in /bin, so "aws missing" cannot be staged (floor allows this one skip)\n'
else
  run_wrap "$SCRIPT" "$WORK/c14" "$COMPLETE" apply-web-platform-infra.yml apply push "" "${TIERB[@]}" PATH="$NOAWS_PATH"
  check "C14 aws CLI absent fails closed (rc 2)" eval '[[ $RC -eq 2 ]] && has "$WORK/c14" "reason=aws-cli-missing"'
fi

# ── D. mutation rows ───────────────────────────────────────────────────────────────────────
# A copy must sit at the same depth under a mirrored tree so its own relative path still finds
# the real gate library: $WORK/mut/<n>/apps/web-platform/infra/scripts/<script>, tests/ symlinked.
mutant() { # <name> <sed-expr> -> prints the mutant path, or "" when the sed did not land
  local d="$WORK/mut/$1"
  mkdir -p "$d/apps/web-platform/infra/scripts"
  ln -sfn "$REPO/tests" "$d/tests"
  sed -E "$2" "$SCRIPT" > "$d/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
  if cmp -s "$SCRIPT" "$d/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"; then printf ''; else printf '%s' "$d/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"; fi
}
mut_row() { # <label> <row-fn> <sed-expr>
  local m; m="$(mutant "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')" "$3")"
  if [[ -z "$m" ]]; then no "MUT $1: the mutation did not land (cmp identical)"; return; fi
  # Control: the mutant is still a working program (parses, and still refuses non-JSON), so the
  # row below goes red for the property it names, not because the sed broke the script.
  if ! bash -n "$m" 2>/dev/null || ! row_non_json_unreadable "$m"; then no "MUT $1: the mutant is not a working program (control failed)"; return; fi
  if "$2" "$m"; then no "MUT $1: SURVIVED ($2 stayed green)"; else ok "MUT $1: caught by $2"; fi
}
mut_row "R2 exception widened to every type"      row_r2_old_passes            's/startswith\("cloudflare_r2_"\) \| not/startswith("cloudflare_NOPE_") | not/g'
mut_row "new-zone comparison dropped"             row_old_zone_refused         's/\(\$z != null and \$z != \$nz\) or //'
mut_row "new-account comparison dropped"          row_old_account_refused      's/ or \(\$ac != null and \$ac != \$na\)//'
mut_row "allowlist reverted to an old-id denylist" row_third_zone_refused      's/select\(\(\$z != null and \$z != \$nz\) or \(\$ac != null and \$ac != \$na\)\)/select($z == $oz or $ac == $oa)/'
mut_row "empty string read as a bound id"         row_unbound_ids_pass         's/if \$v == "" then null else \$v end/$v/'
mut_row "copy timeout not named"                  row_wrap_copy_timeout        's/if \(\( rc == 124 \)\); then/if false; then/'
mut_row "doppler timeout not named"               row_wrap_doppler_timeout     's/if \(\( rc_id == 124 \|\| rc_sec == 124 \)\); then/if false; then/'
mut_row "copy bypasses the shared R2 call"        row_wrap_tierb_complete      's/^    cfam_r2_aws s3 cp /    aws s3 cp /'
mut_row "tunnel reasons dropped from full mode"   row_tunnel_absent_refused    's/^( *)\+ \$tun_reasons$/\1+ []/'
mut_row "tunnel account check dropped"            row_tunnel_old_refused       's/ or \.attributes\.account_id != \$na//'
mut_row "required-address check disarmed"         row_missing_refused          's/"missing " \+ \./empty/'
mut_row "zero-cloudflare guard dropped"           row_zero_cloudflare_refused  's/\["no-cloudflare-resources"\]/[]/'
mut_row "version check dropped"                   row_version_unreadable       's/\.version == 4/true/'
mut_row "gate library id shape check dropped"     row_bad_lib_unusable         's/\|\| bad\+=" \$v"/|| :/'
mut_row "web-2 exception accepts any key"         row_scope_web1_refused       's/"\$key" == "web-2"/"$key" == web-*/'
mut_row "web-2 exception dropped"                 row_scope_web2_excepted      's/printf .gated web2-replace\\n./printf '"'"'gated full\\n'"'"'/'
mut_row "deny-by-default inverted to exempt"      row_scope_unknown_job_gated  's/^  printf .gated full\\n.$/  printf '"'"'exempt-job %s\\n'"'"' "$job"/'
mut_row "exempt workflow list ignored (all gated)" row_wrap_exempt_passthrough 's/if \[\[ "\$wf" == "\$w" \]\]; then printf .exempt-workflow/if false; then printf '"'"'exempt-workflow/'
mut_row "every workflow treated as exempt"        row_scope_new_workflow_gated 's/for w in "\$\{CFAM_EXEMPT_WORKFLOWS\[@\]\}"; do/for w in "$wf"; do/'
mut_row "legacy read loses -c prd_terraform"      row_wrap_legacy_creds        's/ -p soleur -c prd_terraform/ -p soleur/g'
mut_row "legacy values not masked"                row_wrap_legacy_creds        's/printf .::add-mask::%s\\n. "\$ln"/:/'
mut_row "copy failure verdict masked"             row_wrap_copy_failure        's/if \(\( rc != 0 \)\) \|\| \[\[ ! -s "\$work\/state.json" \]\]; then/if false; then/'
mut_row "work dir trap removed"                   row_wrap_tierb_complete      's/^  trap "rm -rf .*$/  :/'
mut_row "key id echoed into the log"              row_wrap_tierb_complete      's/^  CFAM_KEY_ID="" CFAM_KEY_SECRET=""$/  echo "$CFAM_KEY_ID"; CFAM_KEY_ID="" CFAM_KEY_SECRET=""/'
mut_row "aws argv grows a credential"             row_wrap_tierb_complete      's/--only-show-errors \\$/--only-show-errors --profile "$CFAM_KEY_ID" \\/'
mut_row "unnormalized reason disarmed"            row_unnorm_null              's/"unnormalized " \+ iaddr\(\$a\)/empty/'
mut_row "null content accepted"                   row_unnorm_null              's/\(\.attributes\.content \| type\) != "string" or //'
mut_row "empty-string content accepted"           row_unnorm_empty             's/ or \.attributes\.content == ""//'
mut_row "non-string content accepted"             row_unnorm_nonstring         's/\(\.attributes\.content \| type\) != "string"/.attributes.content == null/'
mut_row "content check leaves the record list"    row_unnorm_out_of_scope      's/select\(\$recs \| index\(\$a\)\)/select(true)/'
mut_row "record list keeps non-record imports"    row_unnorm_out_of_scope      's/ and \(\.key \| startswith\("cloudflare_record\."\)\)//'
mut_row "record list keeps non-import classes"    row_unnorm_non_import_class  's/select\(\.value == "import" and /select(true and /'
mut_row "record list narrowed to two records"     row_unnorm_every_record      's/select\(\.value == "import" and \(\.key \| startswith\("cloudflare_record\."\)\)\)/select(.key == "cloudflare_record.www" or .key == "cloudflare_record.dkim_resend")/'
mut_row "content check reads two records only"    row_unnorm_every_record      's/select\(\$recs \| index\(\$a\)\)/select($recs[:2] | index($a))/'
mut_row "record-list failure ignored"            row_recs_fail                's/recs="\$\(cfam_required_records\)" \|\| \{[^}]*\}/recs="$(cfam_required_records)" || recs="[]"/'
mut_row "empty record list accepted"              row_recs_empty               's/type == "array" and length > 0/true/'
mut_row "non-array record list accepted"          row_recs_not_array           's/type == "array" and length > 0/length > 0/'
mut_row "record list read in web2-replace"        row_web2_recs_fail           's/if \[\[ "\$mode" == full \]\]; then/if true; then/'
# Full-only has two layers (recs stays [] outside full, and the jq branch), so this mutant removes both.
mut_row "content check runs in web2-replace"      row_web2_null_content        's/if \[\[ "\$mode" == full \]\]; then/if true; then/; s/if \$mode == "web2-replace" then \$tun_reasons\[\]/if false then $tun_reasons[]/'

# ── verdict ────────────────────────────────────────────────────────────────────────────────
printf '\ncf-account-migration-complete.test.sh: %s passed, %s failed (%s cases)\n' "$PASS" "$FAIL" "$CASES"
if (( PASS + FAIL != CASES )); then
  printf 'CONSERVATION FAILED: PASS(%s)+FAIL(%s) != CASES(%s) — a verdict was dropped or the helpers were neutered.\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
# 119 rows ran when measured (2026-11-24); C14 may skip on a host whose aws sits beside jq.
MIN_ASSERTIONS=118
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s assertions ran, floor is %s — rows were skipped, truncated, or the assertion machinery was neutered.\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
