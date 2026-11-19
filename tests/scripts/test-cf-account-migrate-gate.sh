#!/usr/bin/env bash
# Suite for tests/scripts/lib/cf-account-migrate-gate.sh (#12931 Guard 1).
#
# The oracle is independent of the gate's own data where it matters: the valid redirects-dns
# fixture's expected counts (8 creates, 29 imports) and a sample of addresses are literals here,
# so a gate whose allow-set silently shrank cannot also shrink this suite's expectations.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/lib/cf-account-migrate-gate.sh"
PREAMBLE="$HERE/lib/plan-gate-preamble.sh"
IMPORTS="$HERE/../../apps/web-platform/infra/cf-account-migration-imports.tf"
# Exported: the mutation rows source a COPY of the gate from $TMP, whose own path cannot locate it.
export CFAM_IMPORTS_FILE="$IMPORTS"
export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d -t cf-acct-gate-test.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s (rc=%s)\n%s\n' "$1" "${2:-?}" "${3:-}" | head -c 4000; printf '\n'; }

# Instrument self-test: both helpers must move their counter, or every verdict below is decorative.
_p0=$passes; _f0=$fails
pass "instrument probe" >/dev/null; fail "instrument probe" 0 "" >/dev/null
if [[ $passes -ne $((_p0 + 1)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FAIL INSTRUMENT: pass()/fail() do not move their counters\n'; exit 1
fi
passes=$_p0; fails=$_f0

if [[ ! -f "$GATE" ]]; then printf 'FAIL: gate missing at %s\n' "$GATE"; exit 1; fi
# shellcheck source=/dev/null
source "$PREAMBLE"
# shellcheck source=/dev/null
source "$GATE"
# shellcheck source=/dev/null
source "$HERE/lib/gate-suite-harness.sh"
gate_harness_selftest || exit 1

NZ=951ce525552201ec6c696b24251abed7
NA=66d4f93f7397f196544e9fe84c3557c2
OZ=5af02a2f394e9ba6e0ea23c381a26b67
OA=4d5ba6f096b2686fbdd404167dd4e125

check() { local n="$1"; shift; gate_check "$n" cf_account_migrate_gate "$@"; }
# check() decides most rows, so it gets its own self-test (G1): a probe whose expectation
# cannot hold must add exactly one failure and no pass. Unwound afterwards.
_ck_p=$passes; _ck_f=$fails
_cfam_ck_probe() { return 0; }
_cfam_saved_gate="$(declare -f cf_account_migrate_gate)"
cf_account_migrate_gate() { _cfam_ck_probe; }
check "check() self-test probe" 1 "never-printed-needle" >/dev/null
eval "$_cfam_saved_gate"; unset -f _cfam_ck_probe
if [[ $passes -ne $_ck_p || $fails -ne $((_ck_f + 1)) ]]; then
  printf 'FAIL INSTRUMENT: check() did not record a failing row as exactly one failure\n'; exit 1
fi
passes=$_ck_p; fails=$_ck_f

# ── build the valid redirects-dns fixture from the committed imports file ──────────────────
# Imports: every `to`/`id` pair in the imports file whose block uses the plain import set.
imports_tsv="$TMP/imports.tsv"
awk '
  /^import \{/ {inblk=1; to=""; id=""; set=""; next}
  inblk && /for_each/ {set=($0 ~ /cf_migration_import_app_set/) ? "app" : "main"}
  inblk && /^[[:space:]]*to[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/,""); to=$0}
  inblk && /^[[:space:]]*id[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*"/,""); sub(/".*/,""); id=$0}
  inblk && /^\}/ {if (set=="main") print to "\t" id; inblk=0}
' "$IMPORTS" > "$imports_tsv"
n_imports="$(wc -l < "$imports_tsv" | tr -d ' ')"
if [[ "$n_imports" -eq 29 ]]; then pass "imports file carries 29 redirects-dns imports (26 records + project + 2 domains)"; else fail "imports file import count" "$n_imports" "want 29"; fi
if grep -q 'cloudflare_record.app' "$imports_tsv"; then fail "cloudflare_record.app must not be a redirects-dns import" 1 ""; else pass "cloudflare_record.app is not in the redirects-dns import set"; fi

CREATES='cloudflare_ruleset.allowlist_ai_crawlers cloudflare_ruleset.seo_config_settings cloudflare_ruleset.seo_page_redirects cloudflare_ruleset.seo_response_headers cloudflare_ruleset.bulk_redirects cloudflare_list.legal_redirects cloudflare_list.www_canonical doppler_secret.cf_zone_id_prd'

entry_create() { # <address>
  local a="$1" t="${1%%.*}" after
  case "$t" in
    cloudflare_list|cloudflare_pages_project|cloudflare_pages_domain) after="{\"account_id\":\"$NA\"}" ;;
    cloudflare_ruleset) if [[ "$a" == *bulk_redirects ]]; then after="{\"account_id\":\"$NA\",\"zone_id\":null}"; else after="{\"zone_id\":\"$NZ\",\"account_id\":null}"; fi ;;
    cloudflare_*) after="{\"zone_id\":\"$NZ\"}" ;;
    *) after='{}' ;;
  esac
  jq -nc --arg a "$a" --arg t "$t" --argjson after "$after" '{address:$a,mode:"managed",type:$t,change:{actions:["create"],before:null,after:$after}}'
}
entry_import() { # <address> <id>
  local a="$1" t="${1%%.*}" after
  case "$t" in
    cloudflare_pages_project|cloudflare_pages_domain) after="{\"account_id\":\"$NA\"}" ;;
    *) after="{\"zone_id\":\"$NZ\"}" ;;
  esac
  jq -nc --arg a "$a" --arg t "$t" --arg id "$2" --argjson after "$after" '{address:$a,mode:"managed",type:$t,change:{actions:["no-op"],importing:{id:$id},before:$after,after:$after}}'
}
build_redirects() { # <out-file> [extra-json-entries...]
  local out="$1"; shift
  {
    for a in $CREATES; do entry_create "$a"; done
    while IFS=$'\t' read -r a id; do entry_import "$a" "$id"; done < "$imports_tsv"
    for e in "$@"; do printf '%s\n' "$e"; done
  } | jq -sc '{format_version:"1.2",resource_changes:.}' > "$out"
}
mutate_plan() { # <in> <out> <jq-filter>
  jq -c "$3" "$1" > "$2"
}

VALID="$TMP/valid.json"
build_redirects "$VALID"
check "valid redirects-dns plan passes with derived counts" 0 "verdict=PASS creates=8 imports=29 destroys=0" redirects-dns "$VALID"

# H2: order-insensitive, and a data-source read rides along.
mutate_plan "$VALID" "$TMP/h2.json" '.resource_changes |= (reverse + [{address:"data.cloudflare_zone.x",mode:"data",type:"cloudflare_zone",change:{actions:["read"]}}])'
check "H2 reversed order + data read still passes" 0 "verdict=PASS" redirects-dns "$TMP/h2.json"

# Re-dispatch after success: creates become no-op, imports become plain no-op (already in state).
mutate_plan "$VALID" "$TMP/rerun.json" '.resource_changes |= map(.change.actions=["no-op"] | del(.change.importing))'
check "converged re-dispatch (all no-op) passes" 0 "verdict=PASS creates=0 imports=0" redirects-dns "$TMP/rerun.json"

# Row 1: a delete of cloudflare_record.app.
mutate_plan "$VALID" "$TMP/r1.json" '.resource_changes += [{address:"cloudflare_record.app",mode:"managed",type:"cloudflare_record",change:{actions:["delete"],before:{zone_id:"'"$NZ"'"},after:null}}]'
check "row 1: a delete is refused" 1 "REFUSE" redirects-dns "$TMP/r1.json"

# Row 2: unknown phase; zero resource_changes.
check "row 2a: unknown phase refused" 1 "unknown phase" no-such-phase "$VALID"
mk_plan "$TMP/r2b.json" '[]'
check "row 2b: empty plan refused" 1 "" redirects-dns "$TMP/r2b.json"

# Row 3: a second ruleset create on the OLD zone (in-set address, wrong id).
mutate_plan "$VALID" "$TMP/r3.json" '(.resource_changes[] | select(.address=="cloudflare_ruleset.seo_page_redirects") | .change.after.zone_id) = "'"$OZ"'"'
check "row 3: an in-set create carrying the OLD zone id is refused" 1 "not the new" redirects-dns "$TMP/r3.json"
mutate_plan "$VALID" "$TMP/r3b.json" '(.resource_changes[] | select(.address=="cloudflare_list.legal_redirects") | .change.after.account_id) = "'"$OA"'"'
check "row 3b: an in-set list create carrying the OLD account id is refused" 1 "not the new" redirects-dns "$TMP/r3b.json"
mutate_plan "$VALID" "$TMP/r3c.json" '(.resource_changes[] | select(.address=="cloudflare_ruleset.seo_page_redirects") | .change.after.zone_id) = "0123456789abcdef0123456789abcdef"'
check "row 3c: an unknown third zone id is refused" 1 "not the new" redirects-dns "$TMP/r3c.json"

# Row 4: a create outside every allow-set.
mutate_plan "$VALID" "$TMP/r4.json" '.resource_changes += [{address:"cloudflare_load_balancer.app[0]",mode:"managed",type:"cloudflare_load_balancer",change:{actions:["create"],before:null,after:{zone_id:"'"$NZ"'"}}}]'
check "row 4: an out-of-set create is refused" 1 "outside the redirects-dns allow-set" redirects-dns "$TMP/r4.json"

# Row 5: an update on an R2 bucket.
mutate_plan "$VALID" "$TMP/r5.json" '.resource_changes += [{address:"cloudflare_r2_bucket.workspaces_luks_header",mode:"managed",type:"cloudflare_r2_bucket",change:{actions:["update"],before:{account_id:"'"$OA"'"},after:{account_id:"'"$NA"'"}}}]'
check "row 5: an R2 bucket update is refused" 1 "outside the redirects-dns allow-set" redirects-dns "$TMP/r5.json"
mutate_plan "$VALID" "$TMP/r5b.json" '.resource_changes += [{address:"cloudflare_r2_bucket.workspaces_luks_header",mode:"managed",type:"cloudflare_r2_bucket",change:{actions:["no-op"],before:{account_id:"'"$OA"'"},after:{account_id:"'"$OA"'"}}}]'
check "row 5b: an R2 bucket planned as no-op on the legacy account passes" 0 "verdict=PASS" redirects-dns "$TMP/r5b.json"

# Row 8: forget.
mutate_plan "$VALID" "$TMP/r8.json" '(.resource_changes[] | select(.address=="cloudflare_list.www_canonical") | .change.actions) = ["forget"]'
check "row 8: a forget is refused" 1 "REFUSE" redirects-dns "$TMP/r8.json"

# Row 9: an import that is not a pure no-op.
first_import="$(head -1 "$imports_tsv" | cut -f1)"
mutate_plan "$VALID" "$TMP/r9.json" '(.resource_changes[] | select(.address=="'"$first_import"'") | .change.actions) = ["update"]'
check "row 9: an import planned with an update is refused" 1 "not a pure no-op import" redirects-dns "$TMP/r9.json"
mutate_plan "$VALID" "$TMP/r9x.json" '(.resource_changes[] | select(.address=="'"$first_import"'") | .change.actions) = ["delete","create"]'
check "row 9x: an import planned as a replace is refused" 1 "REFUSE" redirects-dns "$TMP/r9x.json"

# Row 10: an import id differing from the committed literal.
mutate_plan "$VALID" "$TMP/r10.json" '(.resource_changes[] | select(.address=="'"$first_import"'") | .change.importing.id) = "'"$NZ"'/ffffffffffffffffffffffffffffffff"'
check "row 10: an import id that differs from the committed literal is refused" 1 "differs from the committed literal" redirects-dns "$TMP/r10.json"

# Row 11: one expected import missing.
mutate_plan "$VALID" "$TMP/r11.json" 'del(.resource_changes[] | select(.address=="'"$first_import"'"))'
check "row 11: a missing expected address is refused" 1 "missing from the plan" redirects-dns "$TMP/r11.json"
# An import of an address the phase classes as create (e.g. a probe-found entrypoint never committed).
mutate_plan "$VALID" "$TMP/r11b.json" '(.resource_changes[] | select(.address=="cloudflare_ruleset.seo_page_redirects") | .change) |= (.actions=["no-op"] | .importing={id:"zone/'"$NZ"'/abc"})'
check "row 11b: an import with no committed literal is refused" 1 "differs from the committed literal" redirects-dns "$TMP/r11b.json"

# Degraded shapes the preamble owns.
mutate_plan "$VALID" "$TMP/d1.json" '.resource_changes += [{address:"x.y",mode:"managed",type:"x",change:{actions:[],before:{id:1},after:null}}]'
check "degraded: an empty actions array is refused" 1 "" redirects-dns "$TMP/d1.json"
printf 'not json' > "$TMP/d2.json"
check "degraded: an unparseable plan is refused" 1 "" redirects-dns "$TMP/d2.json"

# ── zone-rest ──────────────────────────────────────────────────────────────────────────────
DNS_EDIT_ID="soleur.prd.CF_API_TOKEN_DNS_EDIT"
zr_plan() { # <out> <replace-reason> <before-id>
  jq -nc --arg nz "$NZ" --arg reason "$2" --arg bid "$3" '{format_version:"1.2",resource_changes:[
    {address:"cloudflare_zone_settings_override.soleur_ai",mode:"managed",type:"cloudflare_zone_settings_override",change:{actions:["create"],before:null,after:{zone_id:$nz}}},
    {address:"cloudflare_bot_management.soleur_ai",mode:"managed",type:"cloudflare_bot_management",change:{actions:["create"],before:null,after:{zone_id:$nz}}},
    {address:"github_actions_secret.cloudflare_api_token_pages",mode:"managed",type:"github_actions_secret",change:{actions:["update"],before:{},after:{}}},
    {address:"github_actions_secret.cloudflare_account_id_pages",mode:"managed",type:"github_actions_secret",change:{actions:["update"],before:{},after:{}}},
    {address:"doppler_secret.cf_api_token_dns_edit",mode:"managed",type:"doppler_secret",action_reason:$reason,change:{actions:["delete","create"],before:{id:$bid},after:{}}}
  ]}' > "$1"
}
zr_state() { # <out> <id>
  jq -nc --arg id "$2" '{values:{root_module:{resources:[{address:"doppler_secret.cf_api_token_dns_edit",mode:"managed",type:"doppler_secret",values:{id:$id}}]}}}' > "$1"
}
zr_state "$TMP/zr-state.json" "$DNS_EDIT_ID"
zr_plan "$TMP/zr.json" replace_by_request "$DNS_EDIT_ID"
check "zone-rest valid plan passes" 0 "verdict=PASS creates=2 imports=0 destroys=1" zone-rest "$TMP/zr.json" "$TMP/zr-state.json"
# Row 9b: the declared replace planned without replace_by_request (the -replace flag was dropped).
zr_plan "$TMP/zr9b.json" "" "$DNS_EDIT_ID"
check "row 9b: a declared replace without replace_by_request is refused" 1 "replace_by_request" zone-rest "$TMP/zr9b.json" "$TMP/zr-state.json"
jq -c 'del(.resource_changes[] | select(.address=="doppler_secret.cf_api_token_dns_edit"))' "$TMP/zr.json" > "$TMP/zr9b2.json"
check "row 9b-2: a declared replace absent from the plan is refused" 1 "missing from the plan" zone-rest "$TMP/zr9b2.json" "$TMP/zr-state.json"
# Row 9c: the replace target's before id differs from pre-plan state.
zr_plan "$TMP/zr9c.json" replace_by_request "soleur.prd.SOMETHING_ELSE"
check "row 9c: a replace whose before id differs from pre-plan state is refused" 1 "physical id" zone-rest "$TMP/zr9c.json" "$TMP/zr-state.json"
check "row 9c-2: a replace phase graded without pre-plan state is refused" 1 "pre-plan state" zone-rest "$TMP/zr.json"
# A state entry whose .values is a string makes the physical-id query raise: that must refuse, not pass.
printf '{"values":{"root_module":{"resources":[{"address":"doppler_secret.cf_api_token_dns_edit","values":"not-an-object"}]}}}' > "$TMP/zr-badstate.json"
cp "$TMP/zr.json" "$TMP/zr9c-badstate.json"
check "row 9c-3: a pre-plan state the physical-id check cannot evaluate is refused" 1 "could not be evaluated" zone-rest "$TMP/zr9c-badstate.json" "$TMP/zr-badstate.json"
# A delete of a github secret outside a replace stays refused.
jq -c '(.resource_changes[] | select(.address=="github_actions_secret.cloudflare_api_token_pages") | .change.actions) = ["delete"]' "$TMP/zr.json" > "$TMP/zrdel.json"
check "zone-rest: a bare delete of a mutable secret is refused" 1 "REFUSE" zone-rest "$TMP/zrdel.json" "$TMP/zr-state.json"

# ── -target / -replace generation from the single list ─────────────────────────────────────
tg="$(cf_account_migrate_targets redirects-dns)"
if [[ "$(grep -c '^-target=' <<<"$tg")" -eq 37 ]] && grep -qx -- '-target=doppler_secret.cf_zone_id_prd' <<<"$tg" && ! grep -q 'cloudflare_record.app$' <<<"$tg"; then
  pass "redirects-dns generates 37 -target args, includes the runtime zone id, excludes the app record"
else fail "redirects-dns -target generation" 1 "$tg"; fi
rp="$(cf_account_migrate_replaces zone-rest)"
if [[ "$rp" == "-replace=doppler_secret.cf_api_token_dns_edit" ]]; then pass "zone-rest generates exactly its one -replace"; else fail "zone-rest -replace generation" 1 "$rp"; fi
if [[ -z "$(cf_account_migrate_replaces redirects-dns)" ]]; then pass "redirects-dns declares no -replace"; else fail "redirects-dns -replace must be empty" 1 ""; fi
if cf_account_migrate_targets nope >/dev/null 2>&1; then fail "targets for an unknown phase must fail" 0 ""; else pass "targets for an unknown phase fail"; fi

# ── D3: cache_shared_binaries is in no phase; the routine apply still -targets it ─────────────
# A revoked /api/shared/<token> must not be edge-cached while the containers still purge against
# the OLD zone, so no migrate phase creates the ruleset: the Phase 3 step 6 manual-rerun does.
# phases_holding <gate-file> <address>: the phases whose spec names <address>, one per line.
phases_holding() {
  bash -c 'source "$1"; source "$2"; while IFS= read -r ph; do
      cf_account_migrate_phase_spec "$ph" | jq -e --arg a "$3" "has(\$a)" >/dev/null && printf "%s\n" "$ph"
    done < <(cf_account_migrate_phases); exit 0' _ "$PREAMBLE" "$1" "$2"
}
CSB="cloudflare_ruleset.cache_shared_binaries"
csb_in="$(phases_holding "$GATE" "$CSB")"; csb_rc=$?
if [[ "$csb_rc" -eq 0 && -z "$csb_in" ]]; then pass "D3: no phase spec contains $CSB"; else fail "D3: $CSB is in a phase spec" "$csb_rc" "$csb_in"; fi
APPLY_WF="$HERE/../../.github/workflows/apply-web-platform-infra.yml"
if grep -qE "^[[:space:]]+-target=${CSB//./\\.} \\\\\$" "$APPLY_WF"; then
  pass "D3: apply-web-platform-infra.yml still carries -target=$CSB (the manual-rerun creates it)"
else fail "D3: apply-web-platform-infra.yml lost -target=$CSB" 1 ""; fi
# Mutation: put it back into redirects-dns. The same check must name the phase (RED).
sed 's|^  "cloudflare_ruleset.allowlist_ai_crawlers": "create",$|&\n  "cloudflare_ruleset.cache_shared_binaries": "create",|' "$GATE" > "$TMP/d3-mut.sh"
d3_mut_in="$(phases_holding "$TMP/d3-mut.sh" "$CSB")"
if cmp -s "$TMP/d3-mut.sh" "$GATE"; then fail "D3 mutation: the sed did not land" 1 ""
elif [[ "$d3_mut_in" == "redirects-dns" ]]; then pass "D3 mutation: $CSB added back to redirects-dns is caught (RED)"
else fail "D3 mutation: $CSB added back to redirects-dns is not seen" 1 "$d3_mut_in"; fi

# ── mutation rows: prove the gate's arms are load-bearing ──────────────────────────────────
# Layered: a delete of an in-set create-class address is also off-class, so neutering the destroy
# arm must hand the refusal to the class arm, never to PASS.
mutate_plan "$VALID" "$TMP/r1c.json" '(.resource_changes[] | select(.address=="cloudflare_list.www_canonical") | .change.actions) = ["delete"]'
gate_mutate_layered "M-forget: the destroy arm owns a delete refusal; neutered it hands off to the class arm" \
  's|_cfam_refuse_destroy=1|_cfam_refuse_destroy=0|' "destroys or forgets" "planned with actions" cf_account_migrate_gate redirects-dns "$TMP/r1c.json"
# Sole guard: a replace of a mutable secret is refused only by the class arm since the destroy arm
# exempts nothing but the declared replace set.
jq -c '(.resource_changes[] | select(.address=="github_actions_secret.cloudflare_account_id_pages") | .change.actions) = ["delete","create"]' "$TMP/zr.json" > "$TMP/zrrep.json"
check "zone-rest: a replace of a mutable secret is refused" 1 "REFUSE" zone-rest "$TMP/zrrep.json" "$TMP/zr-state.json"
gate_mutate_and_check "M-id: neutering the new-id check admits row 3" \
  's|_cfam_check_ids=1|_cfam_check_ids=0|' cf_account_migrate_gate redirects-dns "$TMP/r3.json"
gate_mutate_and_check "M-pure: neutering the pure-import check admits row 9" \
  's|_cfam_check_pure=1|_cfam_check_pure=0|' cf_account_migrate_gate redirects-dns "$TMP/r9.json"
gate_mutate_and_check "M-literal: neutering the literal check admits row 10" \
  's|_cfam_check_literal=1|_cfam_check_literal=0|' cf_account_migrate_gate redirects-dns "$TMP/r10.json"
gate_mutate_and_check "M-missing: neutering the presence check admits row 11" \
  's|_cfam_check_present=1|_cfam_check_present=0|' cf_account_migrate_gate redirects-dns "$TMP/r11.json"
gate_mutate_and_check "M-reason: neutering the replace_by_request check admits row 9b" \
  's|_cfam_check_reason=1|_cfam_check_reason=0|' cf_account_migrate_gate zone-rest "$TMP/zr9b.json" "$TMP/zr-state.json"
gate_mutate_and_check "M-physid: neutering the physical-id check admits row 9c" \
  's|_cfam_check_physid=1|_cfam_check_physid=0|' cf_account_migrate_gate zone-rest "$TMP/zr9c.json" "$TMP/zr-state.json"
gate_mutate_layered "M-preamble: the gate INVOKES the readable assert (not merely sources it)" \
  's|^  plan_gate_assert_readable .*|  :|' "an unreadable plan is not evidence" "unclassifiable plan entry" cf_account_migrate_gate redirects-dns "$TMP/d2.json"
gate_mutate_layered "M-classify: the gate INVOKES the classifiable assert; neutered, the eval-fail arm still refuses" \
  's|^  plan_gate_assert_classifiable .*|  :|' "unclassifiable plan entry" "REFUSE" cf_account_migrate_gate redirects-dns "$TMP/d1.json"
gate_mutate_and_check "M-evalfail: the jq-error refusal is load-bearing (a check that cannot evaluate must not read as no violations)" \
  's|_cfam_eval_fail; return 1;|:;|g' cf_account_migrate_gate zone-rest "$TMP/zr9c-badstate.json" "$TMP/zr-badstate.json"

# Anti-vacuity floor, reported outside pass()/fail() (ADR-193).
TOTAL=$((passes + fails))
if [[ "$TOTAL" -lt 47 ]]; then printf 'FAIL ANTI-VACUITY: only %s assertions ran (floor 47)\n' "$TOTAL"; exit 1; fi
printf '%s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
