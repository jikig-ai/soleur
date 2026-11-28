#!/usr/bin/env bash
# Suite for tests/scripts/lib/cf-account-migrate-gate.sh (#12931 Guard 1).
#
# The oracle is independent of the gate's own data where it matters: the valid redirects-dns
# fixture's expected counts (8 creates, 29 imports) and a sample of addresses are literals here,
# so a gate whose allow-set silently shrank cannot also shrink this suite's expectations.
#
# ONE SOURCE (contract, the sources_lib / defines_lib_fn / reassigns_lib_var rows): each consumer
# carries its reviewed source line(s) as whole lines (the forget's backslash continuation pinned to
# the line after it; the job's path binding followed by its source line with only comments and one
# reviewed seam strip between), re-types none of the library's literals, names none of the library's
# CFAM_* constants bare after its source line (no reassignment in any form), makes every R2 call
# through cfam_r2_aws, and DEFINES none of the library's function names, at the start of a line or
# after a separator or group opener (a consumer-side redefinition would shadow the bytes under test).
# RESIDUALS (review): a reviewed source line inside a dead branch (`if false; then` … `fi`) still reads
# as sourcing; a definition or assignment made through eval of a built string, an alias or a sourced
# third file is not seen.
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
# check() decides most rows, so it gets its own self-test: a probe whose expectation
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
bad_lit="$(awk -F'\t' -v nz="$NZ" -v na="$NA" 'index($2, nz "/") != 1 && index($2, na "/") != 1 {print $1}' "$imports_tsv")"
if [[ -z "$bad_lit" ]]; then pass "every committed import literal starts with the NEW zone or account id"; else fail "import literals not on the new zone/account" 1 "$bad_lit"; fi
if grep -q 'cloudflare_record.app' "$imports_tsv"; then fail "cloudflare_record.app must not be a redirects-dns import" 1 ""; else pass "cloudflare_record.app is not in the redirects-dns import set"; fi

CREATES='cloudflare_ruleset.allowlist_ai_crawlers cloudflare_ruleset.seo_config_settings cloudflare_ruleset.seo_page_redirects cloudflare_ruleset.seo_response_headers cloudflare_ruleset.bulk_redirects cloudflare_list.legal_redirects cloudflare_list.www_canonical doppler_secret.cf_zone_id_prd'

entry_create() { # <address>
  local a="$1" t="${1%%.*}" after
  case "$t" in
    cloudflare_list|cloudflare_pages_project|cloudflare_pages_domain) after="{\"account_id\":\"$NA\"}" ;;
    cloudflare_ruleset) if [[ "$a" == *bulk_redirects ]]; then after="{\"account_id\":\"$NA\",\"zone_id\":null}"; else after="{\"zone_id\":\"$NZ\",\"account_id\":null}"; fi ;;
    cloudflare_*) after="{\"zone_id\":\"$NZ\"}" ;;
    doppler_secret) after="{\"project\":\"soleur\",\"config\":\"prd\",\"name\":\"CF_ZONE_ID\",\"value\":\"$NZ\"}" ;;   # the runtime's zone id: the NEW one
    *) after='{}' ;;
  esac
  jq -nc --arg a "$a" --arg t "$t" --argjson after "$after" '{address:$a,mode:"managed",type:$t,change:{actions:["create"],before:null,after:$after}}'
}
entry_import() { # <address> <id>
  local a="$1" t="${1%%.*}" after
  case "$t" in
    cloudflare_pages_project|cloudflare_pages_domain) after="{\"account_id\":\"$NA\"}" ;;
    *) after="{\"zone_id\":\"$NZ\",\"id\":\"${2##*/}\"}" ;;   # a pinned no-op carries its record id (ruling U5)
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

# U1-U5: a fix-forward re-dispatch may plan a create-class rule as ["update"] (CTO ruling
# 2026-11-20), but only for an address already in the pre-plan state whose `before`
# carries the NEW id; a first apply (address absent from state) and an old-id `before` stay refused.
SCS="cloudflare_ruleset.seo_config_settings"
mutate_plan "$VALID" "$TMP/u1.json" '(.resource_changes[] | select(.address=="'"$SCS"'") | .change) |= (.actions=["update"] | .before={zone_id:"'"$NZ"'",account_id:null})'
printf '{"values":{"root_module":{"resources":[{"address":"%s","values":{"id":"r1","zone_id":"%s"}}]}}}' "$SCS" "$NZ" > "$TMP/u-state.json"
printf '{"values":{"root_module":{"resources":[{"address":"cloudflare_ruleset.seo_page_redirects","values":{"id":"r2","zone_id":"%s"}}]}}}' "$NZ" > "$TMP/u-state-other.json"
check "U1: an in-state create-class rule planned as an update on the NEW zone passes" 0 "verdict=PASS creates=7 imports=29 destroys=0" redirects-dns "$TMP/u1.json" "$TMP/u-state.json"
check "U2: the same update for an address absent from the pre-plan state is refused" 1 "$SCS (class create) planned as an update" redirects-dns "$TMP/u1.json" "$TMP/u-state-other.json"
check "U3: the same update with no pre-plan state is refused" 1 "$SCS (class create) planned as an update" redirects-dns "$TMP/u1.json"
mutate_plan "$TMP/u1.json" "$TMP/u4.json" '(.resource_changes[] | select(.address=="'"$SCS"'") | .change.before.zone_id) = "'"$OZ"'"'
check "U4: an in-state update whose before carries the OLD zone is refused" 1 "$SCS (class create) planned as an update" redirects-dns "$TMP/u4.json" "$TMP/u-state.json"
mutate_plan "$VALID" "$TMP/u5.json" '(.resource_changes[] | select(.address=="'"$SCS"'") | .change) |= (.actions=["delete","create"] | .before={zone_id:"'"$NZ"'"})'
check "U5: an in-state create-class replace is refused" 1 "$SCS (class create) planned with actions" redirects-dns "$TMP/u5.json" "$TMP/u-state.json"
# The in-state update the gate admits is printed on its own line (a rehearsal shows which rule a
# fix would overwrite); a first apply prints none, and the verdict line keeps its format.
ISU="cf_account_migrate_gate: in-state-update $SCS"
isu_out="$(cf_account_migrate_gate redirects-dns "$TMP/u1.json" "$TMP/u-state.json" 2>&1)"; isu_rc=$?
if [[ "$isu_rc" -eq 0 ]] && grep -qxF -- "$ISU" <<<"$isu_out" \
   && grep -qxF -- "cf_account_migrate_gate: phase=redirects-dns verdict=PASS creates=7 imports=29 destroys=0" <<<"$isu_out"; then
  pass "U1b: the admitted in-state update prints its own in-state-update line beside an unchanged PASS line"
else fail "U1b: no in-state-update line for U1" "$isu_rc" "$isu_out"; fi
isu_first="$(cf_account_migrate_gate redirects-dns "$VALID" 2>&1)"; isu_first_rc=$?
if [[ "$isu_first_rc" -eq 0 ]] && ! grep -qF -- 'in-state-update' <<<"$isu_first"; then
  pass "U1c: a first-apply plan prints no in-state-update line"
else fail "U1c: a first-apply plan printed an in-state-update line" "$isu_first_rc" "$isu_first"; fi
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's#^  \[\[ -z "\$admitted" \]\] || printf .*$#  :#' "$GATE" > "$TMP/isu-mut.sh"
isu_mut="$(bash -c 'source "$1"; source "$2"; cf_account_migrate_gate redirects-dns "$3" "$4"' _ "$PREAMBLE" "$TMP/isu-mut.sh" "$TMP/u1.json" "$TMP/u-state.json" 2>&1)"
if cmp -s "$TMP/isu-mut.sh" "$GATE"; then fail "M-isu: the mutation did not land" 1 ""
elif grep -qF -- 'verdict=PASS creates=7' <<<"$isu_mut" && ! grep -qxF -- "$ISU" <<<"$isu_mut"; then pass "M-isu: dropping the print loses U1b's in-state-update line (RED)"
else fail "M-isu: the in-state-update line survived its print being dropped" 1 "$isu_mut"; fi
# U1d: a REFUSE prints no in-state-update line, even for an update the arm admitted (nothing is
# applied, so nothing would be overwritten); its REFUSE and verdict lines are what is printed.
mutate_plan "$TMP/u1.json" "$TMP/u1d.json" '.resource_changes += [{address:"cloudflare_record.app",mode:"managed",type:"cloudflare_record",change:{actions:["delete"],before:{zone_id:"'"$NZ"'"},after:null}}]'
isu_ref_run() { bash -c 'source "$1"; source "$2"; cf_account_migrate_gate redirects-dns "$3" "$4"' _ "$PREAMBLE" "$1" "$TMP/u1d.json" "$TMP/u-state.json" 2>&1; }
isu_ref="$(isu_ref_run "$GATE")"; isu_ref_rc=$?
if [[ "$isu_ref_rc" -eq 1 ]] && ! grep -qF -- 'in-state-update' <<<"$isu_ref" \
   && grep -qxF -- "REFUSE destroys or forgets cloudflare_record.app (actions [\"delete\"])" <<<"$isu_ref" \
   && grep -qE -- '^cf_account_migrate_gate: phase=redirects-dns verdict=REFUSE ' <<<"$isu_ref"; then
  pass "U1d: a REFUSE beside an admitted in-state update prints its REFUSE lines and verdict, no in-state-update line"
else fail "U1d: a REFUSE printed an in-state-update line (or lost its REFUSE lines)" "$isu_ref_rc" "$isu_ref"; fi
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's#^    printf .%s. "\$violations"$#&\n    [[ -z "$admitted" ]] || printf "%s\\n" "$admitted"#' "$GATE" > "$TMP/isu-ref-mut.sh"
isu_ref_mut="$(isu_ref_run "$TMP/isu-ref-mut.sh")"
if cmp -s "$TMP/isu-ref-mut.sh" "$GATE"; then fail "M-isu-refuse: the mutation did not land" 1 ""
elif grep -qxF -- "$ISU" <<<"$isu_ref_mut"; then pass "M-isu-refuse: printing admitted updates on a REFUSE is caught by U1d (RED)"
else fail "M-isu-refuse: the REFUSE-branch print was not seen" 1 "$isu_ref_mut"; fi
# B1-B3: each sub-condition of the before-id check owns one shape of a wrong `before` (an in-state
# address, so only this arm can refuse it).
mutate_plan "$TMP/u1.json" "$TMP/b1.json" '(.resource_changes[] | select(.address=="'"$SCS"'") | .change.before) = {zone_id:"'"$NZ"'",account_id:"'"$OA"'"}'
check "B1: an in-state update whose before carries the NEW zone and the OLD account is refused" 1 "$SCS (class create) planned as an update" redirects-dns "$TMP/b1.json" "$TMP/u-state.json"
mutate_plan "$TMP/u1.json" "$TMP/b2.json" '(.resource_changes[] | select(.address=="'"$SCS"'") | .change.before) = {zone_id:"'"$OZ"'",account_id:"'"$NA"'"}'
check "B2: an in-state update whose before carries the OLD zone and the NEW account is refused" 1 "$SCS (class create) planned as an update" redirects-dns "$TMP/b2.json" "$TMP/u-state.json"
mutate_plan "$TMP/u1.json" "$TMP/b3.json" '(.resource_changes[] | select(.address=="'"$SCS"'") | .change.before) = {}'
check "B3: an in-state update whose before carries no id at all is refused" 1 "$SCS (class create) planned as an update" redirects-dns "$TMP/b3.json" "$TMP/u-state.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
gate_mutate_and_check "M-before-none: dropping the no-id clause admits B3" \
  's/(\$bz == null and \$ba == null) or //' cf_account_migrate_gate redirects-dns "$TMP/b3.json" "$TMP/u-state.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
gate_mutate_and_check "M-before-zone: dropping the wrong-zone clause admits B2" \
  's/ or (\$bz != null and \$bz != \$unz)//' cf_account_migrate_gate redirects-dns "$TMP/b2.json" "$TMP/u-state.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
gate_mutate_and_check "M-before-account: dropping the wrong-account clause admits B1" \
  's/ or (\$ba != null and \$ba != \$una)//' cf_account_migrate_gate redirects-dns "$TMP/b1.json" "$TMP/u-state.json"

# Row 1: a delete of cloudflare_record.app.
mutate_plan "$VALID" "$TMP/r1.json" '.resource_changes += [{address:"cloudflare_record.app",mode:"managed",type:"cloudflare_record",change:{actions:["delete"],before:{zone_id:"'"$NZ"'"},after:null}}]'
check "row 1: a delete is refused" 1 "REFUSE" redirects-dns "$TMP/r1.json"

# Row 2: unknown phase; zero resource_changes.
check "row 2a: unknown phase refused" 1 "unknown phase" no-such-phase "$VALID"
mk_plan "$TMP/r2b.json" '[]'
check "row 2b: empty plan refused" 1 "zero resource_changes" redirects-dns "$TMP/r2b.json"

# Row 3: a second ruleset create on the OLD zone (in-set address, wrong id).
mutate_plan "$VALID" "$TMP/r3.json" '(.resource_changes[] | select(.address=="cloudflare_ruleset.seo_page_redirects") | .change.after.zone_id) = "'"$OZ"'"'
check "row 3: an in-set create carrying the OLD zone id is refused" 1 "not the new" redirects-dns "$TMP/r3.json"
mutate_plan "$VALID" "$TMP/r3b.json" '(.resource_changes[] | select(.address=="cloudflare_list.legal_redirects") | .change.after.account_id) = "'"$OA"'"'
check "row 3b: an in-set list create carrying the OLD account id is refused" 1 "not the new" redirects-dns "$TMP/r3b.json"
mutate_plan "$VALID" "$TMP/r3c.json" '(.resource_changes[] | select(.address=="cloudflare_ruleset.seo_page_redirects") | .change.after.zone_id) = "0123456789abcdef0123456789abcdef"'
check "row 3c: an unknown third zone id is refused" 1 "not the new" redirects-dns "$TMP/r3c.json"
# An id that is absent, null, false or known only after apply is NOT the new id (both shapes:
# a zone-bound ruleset and an account-bound list).
SPR="cloudflare_ruleset.seo_page_redirects"; LGL="cloudflare_list.legal_redirects"
set_after() { # <out> <address> <after-jq> [<after_unknown-jq>]
  local u="${4:-}"; [[ -n "$u" ]] || u='{}'
  mutate_plan "$VALID" "$1" "(.resource_changes[] | select(.address==\"$2\") | .change) |= (.after = $3 | .after_unknown = $u)"
}
set_after "$TMP/r3d.json" "$SPR" '{}'
check "row 3d: an in-set zone create with zone_id ABSENT is refused" 1 "$SPR carries an id that is not the new" redirects-dns "$TMP/r3d.json"
set_after "$TMP/r3e.json" "$SPR" '{zone_id:null,account_id:null}'
check "row 3e: an in-set zone create with zone_id null is refused" 1 "$SPR carries an id that is not the new" redirects-dns "$TMP/r3e.json"
set_after "$TMP/r3f.json" "$SPR" '{zone_id:false}'
check "row 3f: an in-set zone create with zone_id false is refused" 1 "$SPR carries an id that is not the new" redirects-dns "$TMP/r3f.json"
set_after "$TMP/r3g.json" "$SPR" '{}' '{zone_id:true}'
check "row 3g: an in-set zone create whose zone_id is known only after apply is refused" 1 "known only after apply" redirects-dns "$TMP/r3g.json"
# Synthetic: the unknown marker refuses on its own, even beside a new-looking value.
set_after "$TMP/r3g2.json" "$SPR" "{zone_id:\"$NZ\"}" '{zone_id:true}'
check "row 3g2: an after_unknown id marker is refused on its own" 1 "known only after apply" redirects-dns "$TMP/r3g2.json"
set_after "$TMP/r3h.json" "$LGL" '{}'
check "row 3h: an in-set account create with account_id ABSENT is refused" 1 "$LGL carries an id that is not the new" redirects-dns "$TMP/r3h.json"
set_after "$TMP/r3i.json" "$LGL" '{account_id:null}' '{account_id:true}'
check "row 3i: an in-set account create whose account_id is known only after apply is refused" 1 "known only after apply" redirects-dns "$TMP/r3i.json"
# A non-Cloudflare allow-set address must not republish an OLD id (the job's check_ids and the
# variables.tf validations stop it upstream; this is the gate's own refusal).
# DOPP <value-jq>: the zone-id secret's planned `after` with every fixed attribute right but the value.
DOPP() { printf '{project:"soleur",config:"prd",name:"CF_ZONE_ID",value:%s}' "$1"; }
set_after "$TMP/r3j.json" doppler_secret.cf_zone_id_prd "$(DOPP "\"$OZ\"")"
check "row 3j: doppler_secret.cf_zone_id_prd planned with the OLD zone id is refused" 1 "republishes an OLD zone/account id" redirects-dns "$TMP/r3j.json"
# U6: an OLD id inside a longer string (a URL) is still a republish; U7: a typo'd class in the
# spec refuses the phase rather than grading that address as nothing.
set_after "$TMP/u6.json" doppler_secret.cf_zone_id_prd "$(DOPP "\"https://api.cloudflare.com/client/v4/zones/$OZ/x\"")"
check "U6: a non-Cloudflare value carrying the OLD zone id inside a URL is refused" 1 "republishes an OLD zone/account id" redirects-dns "$TMP/u6.json"
u7_rc=0
u7_out="$(cf_account_migrate_phase_spec() { printf '{"%s":"creat"}' "$SCS"; }; cf_account_migrate_gate redirects-dns "$VALID" 2>&1)" || u7_rc=$?
if [[ "$u7_rc" -eq 1 ]] && grep -qF "declares an unknown class (${SCS}=creat)" <<<"$u7_out"; then pass "U7: a spec class outside create/import/mutable/replace refuses the phase"
else fail "U7: unknown spec class not refused" "$u7_rc" "$u7_out"; fi
# U8: an address written twice in the spec heredoc (the last value would win silently) refuses the
# phase. The duplicate repeats an existing line, so with the count check removed the copy passes.
sed 's|^  "cloudflare_ruleset.seo_config_settings": "create",$|&\n  "cloudflare_ruleset.seo_config_settings": "create",|' "$GATE" > "$TMP/dup.sh"
dup_run() { bash -c 'source "$1"; source "$2"; cf_account_migrate_gate redirects-dns "$3"' _ "$PREAMBLE" "$1" "$VALID" 2>&1; }
dup_out="$(dup_run "$TMP/dup.sh")"; dup_rc=$?
if cmp -s "$TMP/dup.sh" "$GATE"; then fail "U8: the duplicate-key fixture did not land" 1 ""
elif [[ "$dup_rc" -eq 1 ]] && grep -qF -- "declares an address more than once (38 keys, 37 distinct)" <<<"$dup_out"; then
  pass "U8: a spec naming an address twice refuses the phase"
else fail "U8: a duplicate spec key was not refused" "$dup_rc" "$dup_out"; fi
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's#\[\[ "\$n_raw" -eq "\$n_obj" \]\] ||#true ||#' "$TMP/dup.sh" > "$TMP/dup-mut.sh"
dup_mut_out="$(dup_run "$TMP/dup-mut.sh")"; dup_mut_rc=$?
if cmp -s "$TMP/dup-mut.sh" "$TMP/dup.sh"; then fail "M-dup: the mutation did not land" 1 ""
elif [[ "$dup_mut_rc" -eq 0 ]]; then pass "M-dup: without the key-count check the duplicated spec passes (the check is load-bearing)"
else fail "M-dup: removing the key-count check did not admit the duplicate" "$dup_mut_rc" "$dup_mut_out"; fi
# U9: a nested value in the spec refuses the phase as an unknown class (the spec must be flat), and
# is NOT misreported as a duplicate key (the class check runs first; the key count counts a nested
# value once).
NEST_CLS='declares an unknown class (cloudflare_ruleset.seo_config_settings={"class":"create"})'
sed 's|^  "cloudflare_ruleset.seo_config_settings": "create",$|  "cloudflare_ruleset.seo_config_settings": {"class": "create"},|' "$GATE" > "$TMP/nest.sh"
nest_out="$(dup_run "$TMP/nest.sh")"; nest_rc=$?
if cmp -s "$TMP/nest.sh" "$GATE"; then fail "U9: the nested-value fixture did not land" 1 ""
elif [[ "$nest_rc" -eq 1 ]] && grep -qF -- "$NEST_CLS" <<<"$nest_out" && ! grep -qF -- 'more than once' <<<"$nest_out"; then
  pass "U9: a spec with a nested value refuses the phase as an unknown class, never as a duplicate"
else fail "U9: a nested spec value was not refused as an unknown class (or was misreported)" "$nest_rc" "$nest_out"; fi
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's#^  \[\[ -z "\$v" \]\] || { echo "cf_account_migrate_gate: REFUSE — phase \${phase} declares an unknown class#  true || { echo "x#' "$TMP/nest.sh" > "$TMP/nest-mut.sh"
nest_mut_out="$(dup_run "$TMP/nest-mut.sh")"; nest_mut_rc=$?
if cmp -s "$TMP/nest-mut.sh" "$TMP/nest.sh"; then fail "M-class: the mutation did not land" 1 ""
elif [[ "$nest_mut_rc" -eq 0 ]]; then pass "M-class: without the class check the nested spec passes (the class check is the sole guard; nothing else misreports it)"
else fail "M-class: neutering the class check did not admit the nested spec" "$nest_mut_rc" "$nest_mut_out"; fi
# U10: a key written twice whose FIRST copy is nested and last is a valid class: the parsed object
# holds only the valid copy, so only the key count can see the shadowed one.
sed 's|^  "cloudflare_ruleset.seo_config_settings": "create",$|  "cloudflare_ruleset.seo_config_settings": {"class": "replace"},\n&|' "$GATE" > "$TMP/dupnest.sh"
dupnest_out="$(dup_run "$TMP/dupnest.sh")"; dupnest_rc=$?
if cmp -s "$TMP/dupnest.sh" "$GATE"; then fail "U10: the nested-duplicate fixture did not land" 1 ""
elif [[ "$dupnest_rc" -eq 1 ]] && grep -qF -- "declares an address more than once (38 keys, 37 distinct)" <<<"$dupnest_out"; then
  pass "U10: a key whose shadowed first copy is nested refuses the phase as a duplicate"
else fail "U10: a nested shadowed duplicate was not refused" "$dupnest_rc" "$dupnest_out"; fi
# The previous count (depth-1 leaf events only) cannot see a nested copy: restoring it admits U10.
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's#select((length == 2 and (.\[0\] | length) == 1) or (length == 1 and (.\[0\] | length) == 2))#select(length == 2 and (.[0] | length) == 1)#' "$TMP/dupnest.sh" > "$TMP/dupnest-mut.sh"
dupnest_mut_out="$(dup_run "$TMP/dupnest-mut.sh")"; dupnest_mut_rc=$?
if cmp -s "$TMP/dupnest-mut.sh" "$TMP/dupnest.sh"; then fail "M-dup-nested: the mutation did not land" 1 ""
elif [[ "$dupnest_mut_rc" -eq 0 ]]; then pass "M-dup-nested: counting leaf events only admits U10 (the container-close count is load-bearing)"
else fail "M-dup-nested: the leaf-only count still refused U10" "$dupnest_mut_rc" "$dupnest_mut_out"; fi

set_after "$TMP/r3j2.json" doppler_secret.cf_zone_id_prd "$(DOPP "\"$NZ\"")"
check "row 3j2: doppler_secret.cf_zone_id_prd planned with the NEW zone id passes" 0 "verdict=PASS" redirects-dns "$TMP/r3j2.json"
# Z1-Z6: the runtime zone-id secret must plan exactly its table values (the NEW zone id and its
# fixed project, config and name), on a create or an update.
ZSEC="doppler_secret.cf_zone_id_prd"; THIRD="0123456789abcdef0123456789abcdef"
ZEXP="$ZSEC must plan its expected value"
set_after "$TMP/z1.json" "$ZSEC" "$(DOPP "\"$THIRD\"")"
check "Z1: $ZSEC created with a third 32-hex id (not old, not new) is refused" 1 "$ZEXP (value differs;" redirects-dns "$TMP/z1.json"
set_after "$TMP/z2.json" "$ZSEC" '{project:"soleur",config:"prd",name:"CF_ZONE_ID"}'
check "Z2: $ZSEC created with no value is refused" 1 "$ZEXP (value differs;" redirects-dns "$TMP/z2.json"
set_after "$TMP/z3.json" "$ZSEC" "$(DOPP "\"$NZ\"")" '{value:true}'
check "Z3: $ZSEC whose value is known only after apply is refused" 1 "$ZEXP (value known only after apply;" redirects-dns "$TMP/z3.json"
printf '{"values":{"root_module":{"resources":[{"address":"%s","values":{"id":"soleur.prd.CF_ZONE_ID","value":"%s"}}]}}}' "$ZSEC" "$NZ" > "$TMP/z-state.json"
mutate_plan "$TMP/z1.json" "$TMP/z4.json" '(.resource_changes[] | select(.address=="'"$ZSEC"'") | .change) |= (.actions=["update"] | .before={name:"CF_ZONE_ID",value:"'"$NZ"'"})'
check "Z4: an in-state update of $ZSEC to a third id is refused" 1 "$ZEXP (value differs;" redirects-dns "$TMP/z4.json" "$TMP/z-state.json"
set_after "$TMP/z6.json" "$ZSEC" "{project:\"soleur\",config:\"dev\",name:\"CF_ZONE_ID\",value:\"$NZ\"}"
check "Z6: $ZSEC planned into another Doppler config (dev) with the NEW id is refused" 1 "$ZEXP (config differs;" redirects-dns "$TMP/z6.json"
mutate_plan "$TMP/z4.json" "$TMP/z5.json" '(.resource_changes[] | select(.address=="'"$ZSEC"'") | .change.after.value) = "'"$NZ"'"'
check "Z5: an in-state update of $ZSEC to the NEW zone id passes" 0 "verdict=PASS" redirects-dns "$TMP/z5.json" "$TMP/z-state.json"

# Row 4: a create outside every allow-set.
mutate_plan "$VALID" "$TMP/r4.json" '.resource_changes += [{address:"cloudflare_load_balancer.app[0]",mode:"managed",type:"cloudflare_load_balancer",change:{actions:["create"],before:null,after:{zone_id:"'"$NZ"'"}}}]'
check "row 4: an out-of-set create is refused" 1 "outside the redirects-dns allow-set" redirects-dns "$TMP/r4.json"

# Row 5: an update on an R2 bucket.
mutate_plan "$VALID" "$TMP/r5.json" '.resource_changes += [{address:"cloudflare_r2_bucket.workspaces_luks_header",mode:"managed",type:"cloudflare_r2_bucket",change:{actions:["update"],before:{account_id:"'"$OA"'"},after:{account_id:"'"$NA"'"}}}]'
check "row 5: an R2 bucket update is refused" 1 "outside the redirects-dns allow-set" redirects-dns "$TMP/r5.json"
mutate_plan "$VALID" "$TMP/r5b.json" '.resource_changes += [{address:"cloudflare_r2_bucket.workspaces_luks_header",mode:"managed",type:"cloudflare_r2_bucket",change:{actions:["no-op"],before:{account_id:"'"$OA"'"},after:{account_id:"'"$OA"'"}}}]'
check "row 5b: an R2 bucket planned as no-op on the legacy account passes" 0 "verdict=PASS" redirects-dns "$TMP/r5b.json"
# The R2 carve-out is the whole cloudflare_r2_* family (the same predicate as the forget script and
# the completion predicate), not the bucket type alone.
mutate_plan "$VALID" "$TMP/r5c.json" '.resource_changes += [{address:"cloudflare_r2_bucket_cors.state",mode:"managed",type:"cloudflare_r2_bucket_cors",change:{actions:["no-op"],before:{account_id:"'"$OA"'"},after:{account_id:"'"$OA"'"}}}]'
check "row 5c: another cloudflare_r2_* type planned as no-op on the legacy account passes" 0 "verdict=PASS" redirects-dns "$TMP/r5c.json"
mutate_plan "$VALID" "$TMP/r5d.json" '.resource_changes += [{address:"cloudflare_r2_bucket_cors.state",mode:"managed",type:"cloudflare_r2_bucket_cors",change:{actions:["update"],before:{account_id:"'"$OA"'"},after:{account_id:"'"$OA"'"}}}]'
check "row 5d: a cloudflare_r2_* change outside the allow-set is still refused" 1 "outside the redirects-dns allow-set" redirects-dns "$TMP/r5d.json"

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
check "degraded: an empty actions array is refused" 1 "unclassifiable plan entry" redirects-dns "$TMP/d1.json"
printf 'not json' > "$TMP/d2.json"
check "degraded: an unparseable plan is refused" 1 "an unreadable plan is not evidence" redirects-dns "$TMP/d2.json"

# ── zone-rest ──────────────────────────────────────────────────────────────────────────────
DNS_EDIT_ID="soleur.prd.CF_API_TOKEN_DNS_EDIT"
zr_plan() { # <out> <replace-reason> <before-id>
  jq -nc --arg nz "$NZ" --arg na "$NA" --arg reason "$2" --arg bid "$3" '{format_version:"1.2",resource_changes:[
    {address:"cloudflare_zone_settings_override.soleur_ai",mode:"managed",type:"cloudflare_zone_settings_override",change:{actions:["create"],before:null,after:{zone_id:$nz}}},
    {address:"cloudflare_bot_management.soleur_ai",mode:"managed",type:"cloudflare_bot_management",change:{actions:["create"],before:null,after:{zone_id:$nz}}},
    {address:"github_actions_secret.cloudflare_api_token_pages",mode:"managed",type:"github_actions_secret",change:{actions:["update"],before:{},after:{repository:"soleur",secret_name:"CLOUDFLARE_API_TOKEN_PAGES",plaintext_value:"SYNTH-PAGES-TOKEN"}}},
    {address:"github_actions_secret.cloudflare_account_id_pages",mode:"managed",type:"github_actions_secret",change:{actions:["update"],before:{},after:{repository:"soleur",secret_name:"CLOUDFLARE_ACCOUNT_ID_PAGES",plaintext_value:$na}}},
    {address:"doppler_secret.cf_api_token_dns_edit",mode:"managed",type:"doppler_secret",action_reason:$reason,change:{actions:["delete","create"],before:{id:$bid},after:{project:"soleur",config:"prd",name:"CF_API_TOKEN_DNS_EDIT",visibility:"masked",value:"SYNTH-DNS-EDIT-TOKEN"}}}
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
# G2: a BARE delete of the declared replace target, carrying replace_by_request and the right
# physical id. The destroy arm exempts the replace set and the reason/physid arms are satisfied,
# so only the class arm's replace clause refuses it (M-replace-class below).
jq -c '(.resource_changes[] | select(.address=="doppler_secret.cf_api_token_dns_edit") | .change.actions) = ["delete"]' "$TMP/zr.json" > "$TMP/zrg2.json"
check "row G2: a bare delete of the declared replace target (replace_by_request, right id) is refused" 1 "(class replace) planned with actions [\"delete\"]" zone-rest "$TMP/zrg2.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="doppler_secret.cf_api_token_dns_edit") | .change.actions) = ["create","delete"]' "$TMP/zr.json" > "$TMP/zrcbd.json"
# A name-keyed replace planned create-first would delete the key it had just written (D36).
check "row 9d: the declared replace planned create-before-destroy is refused" 1 "(class replace) planned with actions [\"create\",\"delete\"]" zone-rest "$TMP/zrcbd.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="github_actions_secret.cloudflare_account_id_pages") | .change.after) = {secret_name:"CLOUDFLARE_ACCOUNT_ID_PAGES",plaintext_value:"'"$OA"'"}' "$TMP/zr.json" > "$TMP/zrold.json"
check "zone-rest: a github secret republishing the OLD account id is refused" 1 "github_actions_secret.cloudflare_account_id_pages republishes an OLD" zone-rest "$TMP/zrold.json" "$TMP/zr-state.json"
# The token-valued Pages secret's VALUE is outside the expected-values table, so the old-id check alone sees it.
jq -c '(.resource_changes[] | select(.address=="github_actions_secret.cloudflare_api_token_pages") | .change.after.plaintext_value) = "x-'"$OA"'"' "$TMP/zr.json" > "$TMP/zrold-tok.json"
check "zone-rest: the token-valued Pages secret carrying the OLD account id is refused" 1 "github_actions_secret.cloudflare_api_token_pages republishes an OLD" zone-rest "$TMP/zrold-tok.json" "$TMP/zr-state.json"
# P1-P3: the Pages account-id secret must plan exactly its table values (the NEW account id).
GAP="github_actions_secret.cloudflare_account_id_pages"; GEXP="$GAP must plan its expected value"
jq -c '(.resource_changes[] | select(.address=="'"$GAP"'") | .change.after.plaintext_value) = "0123456789abcdef0123456789abcdef"' "$TMP/zr.json" > "$TMP/g1.json"
check "P1: $GAP planned with a third 32-hex account id is refused" 1 "$GEXP (plaintext_value differs;" zone-rest "$TMP/g1.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="'"$GAP"'") | .change) |= (.after = {repository:"soleur",secret_name:"CLOUDFLARE_ACCOUNT_ID_PAGES"} | .after_unknown = {plaintext_value:true})' "$TMP/zr.json" > "$TMP/g2.json"
check "P2: $GAP whose plaintext_value is known only after apply is refused" 1 "$GEXP (plaintext_value known only after apply;" zone-rest "$TMP/g2.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="'"$GAP"'") | .change) |= (.actions = ["no-op"] | .after.plaintext_value = "0123456789abcdef0123456789abcdef")' "$TMP/zr.json" > "$TMP/g3.json"
check "P3: $GAP planned as a no-op on a third account id is still graded and refused" 1 "$GEXP (plaintext_value differs; actions [\"no-op\"])" zone-rest "$TMP/g3.json" "$TMP/zr-state.json"
# T1-T3: the two token-valued members' DESTINATION attributes are graded (their value is not): the
# Pages token published to another repository, or the dns-edit token's replace written into another
# Doppler config (the replace's delete half would remove prd's CF_API_TOKEN_DNS_EDIT), is refused.
GTP="github_actions_secret.cloudflare_api_token_pages"; DNE="doppler_secret.cf_api_token_dns_edit"
jq -c '(.resource_changes[] | select(.address=="'"$GTP"'") | .change.after.repository) = "elsewhere"' "$TMP/zr.json" > "$TMP/t1.json"
check "T1: $GTP published to another repository is refused" 1 "$GTP must plan its expected value (repository differs; actions [\"update\"])" zone-rest "$TMP/t1.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="'"$DNE"'") | .change.after.config) = "dev"' "$TMP/zr.json" > "$TMP/t2.json"
check "T2: $DNE replaced into another Doppler config (dev) is refused" 1 "$DNE must plan its expected value (config differs; actions [\"delete\",\"create\"])" zone-rest "$TMP/t2.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="'"$DNE"'" or .address=="'"$GTP"'") | .change.after) |= (if has("value") then .value = "SYNTH-OTHER" else .plaintext_value = "SYNTH-OTHER" end)' "$TMP/zr.json" > "$TMP/t3.json"
check "T3: a token-valued member's value is not graded (any synthesized token passes)" 0 "verdict=PASS" zone-rest "$TMP/t3.json" "$TMP/zr-state.json"
gate_mutate_and_check "M-want-pages-token: dropping the $GTP table entry admits T1" \
  '/^    + {"github_actions_secret.cloudflare_api_token_pages": /d' cf_account_migrate_gate zone-rest "$TMP/t1.json" "$TMP/zr-state.json"
gate_mutate_and_check "M-want-dns-edit: dropping the $DNE table entry admits T2" \
  '/^    + {"doppler_secret.cf_api_token_dns_edit": /d' cf_account_migrate_gate zone-rest "$TMP/t2.json" "$TMP/zr-state.json"

# EXPECTED VALUES closed set: every non-Cloudflare spec member is a table member; exactly the
# token-valued members (a literal here, independent of the gate) are in the table WITHOUT a value
# attribute, and every other member carries one; every table member is in a spec.
# random_id.tunnel_secret has no value attribute at all; the two registry secrets follow a token.
TOKEN_VALUED=" doppler_secret.cf_api_token_dns_edit github_actions_secret.cloudflare_api_token_pages doppler_secret.registry_push_access_token_id doppler_secret.registry_push_access_token_secret random_id.tunnel_secret "
noncf_unclassified() { # <gate-file>: "unclassified|orphan|token-graded|value-ungraded <addr>" lines; empty when closed
  # shellcheck disable=SC2016 # expanded by the child bash
  bash -c 'source "$1"; source "$2"; tok="$3"
    want="$(_cfam_expected_values)" || { echo "table-unreadable"; exit 0; }
    all="$(while IFS= read -r ph; do cf_account_migrate_phase_spec "$ph" | jq -r "keys[]"; done < <(cf_account_migrate_phases) | sort -u)"
    while IFS= read -r a; do
      [[ "$a" == cloudflare_* ]] && continue
      jq -e --arg a "$a" "has(\$a)" <<<"$want" >/dev/null || { printf "unclassified %s\n" "$a"; continue; }
      hv="$(jq -r --arg a "$a" ".[\$a] | has(\"value\") or has(\"plaintext_value\")" <<<"$want")"
      if [[ "$tok" == *" $a "* ]]; then [[ "$hv" == false ]] || printf "token-graded %s\n" "$a"
      else [[ "$hv" == true ]] || printf "value-ungraded %s\n" "$a"; fi
    done <<<"$all"
    while IFS= read -r a; do grep -qxF -- "$a" <<<"$all" || printf "orphan %s\n" "$a"; done < <(jq -r "keys[]" <<<"$want")' _ "$PREAMBLE" "$1" "$TOKEN_VALUED"
}
ncu="$(noncf_unclassified "$GATE")"
n_want="$(bash -c 'source "$1"; source "$2"; _cfam_expected_values | jq length' _ "$PREAMBLE" "$GATE")"
if [[ -z "$ncu" && "$n_want" == 7 ]]; then pass "expected values: the table holds 7 members, each in a spec; every non-Cloudflare spec member is in it, the 5 with no gradable value without one"
else fail "expected values: the closed set is broken (table size ${n_want})" 1 "$ncu"; fi
sed 's|^  "github_actions_secret.cloudflare_api_token_pages": "mutable",$|&\n  "doppler_secret.some_new_id": "mutable",|' "$GATE" > "$TMP/ncu-mut.sh"
ncu_mut="$(noncf_unclassified "$TMP/ncu-mut.sh")"
if cmp -s "$TMP/ncu-mut.sh" "$GATE"; then fail "M-ncu: the mutation did not land" 1 ""
elif [[ "$ncu_mut" == "unclassified doppler_secret.some_new_id" ]]; then pass "M-ncu: a new non-Cloudflare spec member outside the table is caught (RED)"
else fail "M-ncu: a new unclassified non-Cloudflare member was not seen" 1 "$ncu_mut"; fi
# Being in the token list no longer exempts a member from the table (it must be in both).
sed '/^    + {"doppler_secret.cf_api_token_dns_edit": /d' "$GATE" > "$TMP/ncu-tok.sh"
ncu_tok="$(noncf_unclassified "$TMP/ncu-tok.sh")"
if cmp -s "$TMP/ncu-tok.sh" "$GATE"; then fail "M-ncu-token: the mutation did not land" 1 ""
elif [[ "$ncu_tok" == "unclassified doppler_secret.cf_api_token_dns_edit" ]]; then pass "M-ncu-token: a token-valued member dropped from the table is caught (RED; the token list is not an exemption)"
else fail "M-ncu-token: a token-valued member outside the table was not seen" 1 "$ncu_tok"; fi
# The table's attributes ARE the .tf block's constant attributes (both directions): each table
# member's resource block, read from the root, sets exactly the table's non-value attributes to the
# table's literals, and its only non-literal attribute is the value (var.*), which the table grades as
# the NEW id or, for a token-valued member, leaves out.
INFRA="$HERE/../../apps/web-platform/infra"
tf_table_parity() { # <gate-file> <infra-dir>: one line per drift; empty when the table equals the .tf
  local want a typ nm blk lit
  want="$(bash -c 'source "$1"; source "$2"; _cfam_expected_values' _ "$PREAMBLE" "$1")" || { echo "table-unreadable"; return; }
  while IFS= read -r a; do
    typ="${a%%.*}"; nm="${a#*.}"
    # Depth-1 `name = value` lines of the one block `resource "<typ>" "<nm>" {` (nested blocks skipped).
    blk="$(cat "$2"/*.tf | awk -v h="resource \"$typ\" \"$nm\" {" '
      $0 == h {n++; d = 1; next}
      d > 0 { line = $0; o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line)
              if (d == 1 && $0 ~ /^[[:space:]]*[a-z_]+[[:space:]]*=/) { sub(/^[[:space:]]*/, ""); print }
              d += o - c }
      END { if (n != 1) print "BLOCKS " n }')"
    if grep -q '^BLOCKS ' <<<"$blk"; then echo "$a: $(grep '^BLOCKS ' <<<"$blk") resource blocks (want 1)"; continue; fi
    # A literal is a quoted string or a bare integer (random_id's byte_length).
    lit="$(sed -nE -e 's/^([a-z_]+)[[:space:]]*=[[:space:]]*"([^"]*)"[[:space:]]*$/\1\t\2/p' \
      -e 's/^([a-z_]+)[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$/\1\t\2/p' <<<"$blk" | sort)"
    [[ "$lit" == "$(jq -r --arg a "$a" '.[$a] | to_entries[] | select(.key != "value" and .key != "plaintext_value") | "\(.key)\t\(.value)"' <<<"$want" | sort)" ]] \
      || echo "$a: .tf literals [$(tr '\t\n' '= ' <<<"$lit")] differ from the table"
    # At most one non-literal attribute, the value; a member with no value attribute has none.
    [[ "$(sed -nE -e '/^[a-z_]+[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*$/d' -e '/^[a-z_]+[[:space:]]*=[[:space:]]*[0-9]+[[:space:]]*$/d' \
        -e 's/^([a-z_]+)[[:space:]]*=.*/\1/p' <<<"$blk" | tr '\n' ' ')" =~ ^((value|plaintext_value)\ )?$ ]] \
      || echo "$a: a non-literal attribute other than the one value"
  done < <(jq -r 'keys[]' <<<"$want")
}
tfp="$(tf_table_parity "$GATE" "$INFRA")"
if [[ -z "$tfp" ]]; then pass "expected values: each table member's attributes equal its .tf block's literals (value aside)"
else fail "expected values: the table drifted from the .tf blocks" 1 "$tfp"; fi
mkdir -p "$TMP/tfp"; for f in "$INFRA"/*.tf; do ln -s "$f" "$TMP/tfp/$(basename "$f")"; done
rm "$TMP/tfp/cf-cert-reissue-token.tf"
sed '/^resource "doppler_secret" "cf_api_token_dns_edit" {$/,/^}/s/^  config     = "prd"$/  config     = "dev"/' "$INFRA/cf-cert-reissue-token.tf" > "$TMP/tfp/cf-cert-reissue-token.tf"
tfp_mut="$(tf_table_parity "$GATE" "$TMP/tfp")"
if cmp -s "$TMP/tfp/cf-cert-reissue-token.tf" "$INFRA/cf-cert-reissue-token.tf"; then fail "M-tf-parity: the mutation did not land" 1 ""
elif [[ "$tfp_mut" == "doppler_secret.cf_api_token_dns_edit: .tf literals"*"differ from the table" ]]; then pass "M-tf-parity: a .tf edit of a table member's destination (config dev) is caught (RED)"
else fail "M-tf-parity: a .tf destination edit was not seen" 1 "$tfp_mut"; fi

# ── tunnel ─────────────────────────────────────────────────────────────────────────────────
# The expected counts are literals (14 creates, 1 import, the replace's one delete half), so a
# spec that shrank cannot shrink this oracle with it.
TUN_UUID="11111111-2222-4333-8444-555555555555"
TUN_RND="SYNTHrandomPhysicalIdNotARealSecret"
TUN_POL="cloudflare_zero_trust_access_policy.deploy_service_token"
TUN_APP_ID="$NZ/f21d6911cdacb1e109ae31bcfb440e7d"
TUN_APP="cloudflare_zero_trust_access_application"
TUN_TOK="cloudflare_zero_trust_access_service_token"
TUN_POL_SSH="cloudflare_zero_trust_access_policy.ci_ssh_service_token"
TUN_POL_REG="cloudflare_zero_trust_access_policy.registry_push_service_token"
# The Access members carry the shape a real provider 4.52.7 plan of this slice has (measured offline
# with synthetic credentials): a zone-scoped app plans account_id known-after-apply, and a policy whose
# token is created by the same plan has its whole service_token list unknown.
tun_plan() { # <out>
  jq -n --argjson spec "$(cf_account_migrate_phase_spec tunnel)" --arg nz "$NZ" --arg na "$NA" --arg u "$TUN_UUID" \
    --arg r "$TUN_RND" --arg pol "$TUN_POL" --arg app "$TUN_APP_ID" --arg psh "$TUN_POL_SSH" --arg prg "$TUN_POL_REG" \
    --arg ta "$TUN_APP" --arg tt "$TUN_TOK" '
    def ids($t): if ($t | test("tunnel_cloudflared|access_service_token|notification_policy")) then {account_id: $na} else {zone_id: $nz} end;
    def reg($a): {project: "soleur", config: "prd", visibility: "masked",
                  name: (if ($a | endswith("_id")) then "REGISTRY_PUSH_ACCESS_TOKEN_ID" else "REGISTRY_PUSH_ACCESS_TOKEN_SECRET" end)};
    def inc0: {any_valid_service_token: null, auth_context: [], auth_method: null, azure: [], certificate: null, common_name: null,
               common_names: null, device_posture: null, email: null, email_domain: null, email_list: null, everyone: null,
               external_evaluation: [], geo: null, github: [], group: null, gsuite: [], ip: null, ip_list: null,
               login_method: null, okta: [], saml: []};
    def blocks: {auth_context: [], azure: [], external_evaluation: [], github: [], gsuite: [], okta: [], saml: []};
    def appv: {($ta + ".deploy"): {domain: "deploy.soleur.ai", session_duration: "24h"},
               ($ta + ".ssh"): {domain: "ssh.soleur.ai", session_duration: "15m"},
               ($ta + ".registry"): {domain: "registry.soleur.ai", session_duration: "15m"}};
    def polv: {($pol): {app: ($ta + ".deploy"), tok: ["local.deploy_service_token_ids"]},
               ($psh): {app: ($ta + ".ssh"), tok: [($tt + ".ci_ssh.id"), ($tt + ".ci_ssh")]},
               ($prg): {app: ($ta + ".registry"), tok: [($tt + ".registry_push.id"), ($tt + ".registry_push")]}};
    def created($a; $t):
      if appv[$a] != null then {actions: ["create"], before: null, after: (ids($t) + appv[$a] + {type: "self_hosted"}),
                                after_unknown: {account_id: true, id: true}}
      elif $a == $pol then {actions: ["create"], before: null,
                            after: (ids($t) + {decision: "non_identity", include: [inc0 + {service_token: [$u]}]}),
                            after_unknown: {application_id: true, id: true, include: [blocks + {service_token: [false]}]}}
      elif polv[$a] != null then {actions: ["create"], before: null,
                            after: (ids($t) + {decision: "non_identity", include: [inc0]}),
                            after_unknown: {application_id: true, id: true, include: [blocks + {service_token: true}]}}
      elif ($a | test("^cloudflare_record[.](deploy|ssh|registry)$")) then {actions: ["create"], before: null,
        after: (ids($t) + {name: ($a | split(".")[1]), type: "CNAME", proxied: true, ttl: 1}),
        after_unknown: {content: true, hostname: true, id: true}}
      elif $a == "cloudflare_zero_trust_tunnel_cloudflared_config.web" then {actions: ["create"], before: null,
        after: (ids($t) + {config: [{ingress_rule: [
                   {hostname: "deploy.soleur.ai", service: "http://10.0.1.12:9000"},
                   {hostname: "ssh.soleur.ai", service: "ssh://10.0.1.12:22"},
                   {hostname: "registry.soleur.ai", service: "tcp://10.0.1.30:5000"},
                   {hostname: null, service: "http_status:404"}]}]}), after_unknown: {tunnel_id: true, id: true}}
      else {actions: ["create"], before: null, after: ids($t)} end;
    {format_version: "1.2",
     configuration: {root_module: {resources: ([polv | to_entries[] | {address: .key, expressions: {
       application_id: {references: [(.value.app + ".id"), .value.app]},
       decision: {constant_value: "non_identity"},
       include: [{service_token: {references: .value.tok}}]}}] + [("deploy", "ssh", "registry") | {address: ("cloudflare_record." + .), expressions: {content: {references:
       ["cloudflare_zero_trust_tunnel_cloudflared.web.id", "cloudflare_zero_trust_tunnel_cloudflared.web"]}}}] + [{"doppler_secret.registry_push_access_token_id": "client_id", "doppler_secret.registry_push_access_token_secret": "client_secret"}
       | to_entries[] | {address: .key, expressions: {value: {references:
           [("cloudflare_zero_trust_access_service_token.registry_push." + .value), "cloudflare_zero_trust_access_service_token.registry_push"]}}}])}},
     resource_changes: [$spec | to_entries[] | .key as $a | .value as $c | ($a | split(".")[0]) as $t
       | {address: $a, mode: "managed", type: $t, change: (
           if $c == "create" then created($a; $t)
           elif $c == "import" then {actions: ["no-op"], importing: {id: $app}, before: (ids($t) + {id: ($app | split("/") | last)}), after: (ids($t) + {id: ($app | split("/") | last)})}
           elif $c == "mutable" then {actions: ["update"], before: reg($a), after: reg($a), after_unknown: {value: true}}
           else {actions: ["delete", "create"], before: {id: $r}, after: {byte_length: 32}} end)}
         + (if $c == "replace" then {action_reason: "replace_by_request"} else {} end)]}' >"$1"
}
tun_state() { # <out> <random id>
  jq -nc --arg id "$2" '{values:{root_module:{resources:[{address:"random_id.tunnel_secret",mode:"managed",type:"random_id",values:{id:$id}}]}}}' >"$1"
}
tun_plan "$TMP/tun.json"; tun_state "$TMP/tun-state.json" "$TUN_RND"
tun_mut() { jq -c "$1" "$TMP/tun.json" >"$TMP/tm.json"; } # <jq filter>: the mutated plan is $TMP/tm.json
tpol() { printf '(.resource_changes[] | select(.address=="%s") | .change.after) |= (%s)' "$TUN_POL" "$1"; }

check "tunnel: the valid plan passes (14 creates, 1 import, the random_id replace's delete half)" 0 \
  "verdict=PASS creates=14 imports=1 destroys=1" tunnel "$TMP/tun.json" "$TMP/tun-state.json"
tg="$(cf_account_migrate_targets tunnel)"; rp="$(cf_account_migrate_replaces tunnel)"
if [[ "$(grep -c '^-target=' <<<"$tg")" -eq 18 && "$rp" == "-replace=random_id.tunnel_secret" ]]; then
  pass "tunnel: 18 -target args and exactly one -replace (random_id; the registry secrets update in place)"
else fail "tunnel: -target/-replace generation" 1 "$tg / $rp"; fi
if [[ "$(cf_account_migrate_phase_tokens tunnel)" == cf_api_token ]]; then pass "tunnel: its provider token list is cf_api_token"; else fail "tunnel: token list" 1 ""; fi
if [[ "$(_cfam_import_literals tunnel | jq -r '.["cloudflare_record.app"]')" == "$TUN_APP_ID" ]] \
   && [[ "$(_cfam_import_literals redirects-dns | jq -r '.["cloudflare_record.app"] // "absent"')" == absent ]] \
   && [[ "$(_cfam_import_literals | jq -r '.["cloudflare_record.app"] // "absent"')" == absent ]]; then
  pass "the app-record import literal is visible to the tunnel phase only"
else fail "the app-record literal leaked outside the tunnel phase" 1 ""; fi
jq -c '.resource_changes += [{address:"cloudflare_record.app",mode:"managed",type:"cloudflare_record",change:{actions:["no-op"],importing:{id:"'"$TUN_APP_ID"'"},before:{zone_id:"'"$NZ"'"},after:{zone_id:"'"$NZ"'"}}}]' "$VALID" >"$TMP/app-rd.json"
check "redirects-dns: importing the app record is refused even with the committed id" 1 "cloudflare_record.app is outside the redirects-dns allow-set" redirects-dns "$TMP/app-rd.json"
tun_mut '(.resource_changes[] | select(.address=="cloudflare_record.app") | .change) = {actions:["create"],before:null,after:{zone_id:"'"$NZ"'"}}'
check "tunnel: the app record planned as a create (import switched off) is refused" 1 "cloudflare_record.app (class import) planned with actions" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_mut '(.resource_changes[] | select(.address=="cloudflare_record.ssh") | .change) |= (.actions = ["update"] | .before = .after)'
check "tunnel: a created CNAME planned as an update is refused (only a plain create is exempt)" 1 "cloudflare_record.ssh is a cloudflare_record change outside import-normalize" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
for act in '["delete"]' '["delete","create"]'; do
  tun_mut '(.resource_changes[] | select(.address=="cloudflare_record.ssh") | .change) |= (.actions = '"$act"' | .before = .after)'
  check "tunnel: a created CNAME planned as $act is refused as a record change (the exemption is a plain create only)" 1 "cloudflare_record.ssh is a cloudflare_record change outside import-normalize" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
done
tun_mut '(.resource_changes[] | select(.address=="cloudflare_record.app") | .change.actions) = ["update"]'
check "tunnel: an app import that writes is refused" 1 "not a pure no-op import" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_mut '(.resource_changes[] | select(.address=="doppler_secret.registry_push_access_token_secret") | .change.actions) = ["delete","create"]'
check "tunnel: a registry secret planned as a replace is refused (it updates in place)" 1 "REFUSE destroys or forgets doppler_secret.registry_push_access_token_secret" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_mut '(.resource_changes[] | select(.address=="doppler_secret.registry_push_access_token_id") | .change.after.config) = "dev"'
check "tunnel: a registry secret written to another Doppler config is refused" 1 "doppler_secret.registry_push_access_token_id must plan its expected value (config differs" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_mut '(.resource_changes[] | select(.address=="random_id.tunnel_secret") | .change.after.byte_length) = 16'
check "tunnel: a tunnel secret of another length is refused" 1 "random_id.tunnel_secret must plan its expected value (byte_length differs" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_mut 'del(.resource_changes[] | select(.address=="random_id.tunnel_secret") | .action_reason)'
check "tunnel: a random_id replace without replace_by_request is refused" 1 "random_id.tunnel_secret is a declared -replace" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_mut '(.resource_changes[] | select(.address=="cloudflare_record.ssh") | .change.actions) = ["delete"]'
check "tunnel: a delete of a created member is refused" 1 "REFUSE destroys or forgets cloudflare_record.ssh" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tun_state "$TMP/tun-state-other.json" "SYNTHotherPhysicalId"
tun_out="$(cf_account_migrate_gate tunnel "$TMP/tun.json" "$TMP/tun-state-other.json" 2>&1)"; tun_rc=$?
if [[ "$tun_rc" -eq 1 && "$tun_out" == *"random_id.tunnel_secret replace targets a physical id"* && "$tun_out" != *"$TUN_RND"* && "$tun_out" != *SYNTHotherPhysicalId* ]]; then
  pass "tunnel: a random_id physical-id mismatch refuses and prints neither id (the id IS the secret)"
else fail "tunnel: the random_id refusal printed an id or did not refuse" "$tun_rc" "$tun_out"; fi
check "zone-rest: a non-random replace mismatch still names the ids" 1 "soleur.prd.SOMETHING_ELSE" zone-rest "$TMP/zr9c.json" "$TMP/zr-state.json"

# tset <address> <jq on .change> / tcfg <address> <jq on .expressions>: one property changed, alone.
tset() { jq -c --arg a "$1" "(.resource_changes[] | select(.address == \$a) | .change) |= ($2)" "$TMP/tun.json" >"$TMP/tm.json"; }
tcfg() { jq -c --arg a "$1" "(.configuration.root_module.resources[] | select(.address == \$a) | .expressions) |= ($2)" "$TMP/tun.json" >"$TMP/tm.json"; }
tchk() { check "$1" "${3:-1}" "$2" tunnel "$TMP/tm.json" "$TMP/tun-state.json"; } # <row> <needle> [<rc>]

# B1: a zone-scoped Access app plans account_id known-after-apply. Admitted for those three
# addresses in this phase only, with zone_id still required to be the NEW zone.
check "B1-green: the three zone-scoped apps with a known-after-apply account_id pass" 0 "verdict=PASS" tunnel "$TMP/tun.json" "$TMP/tun-state.json"
tset "$TUN_APP.ssh" '.actions = ["no-op"] | .before = .after | .after.account_id = "" | del(.after_unknown)'
tchk "B1-green-redispatch: an app in state whose account_id reads empty passes" "verdict=PASS" 0
tset "$TUN_APP.ssh" '.after.zone_id = null | .after_unknown.zone_id = true'
tchk "B1-red-zone-unknown: an app whose zone_id is known only after apply is refused" "$TUN_APP.ssh carries an id that is not the new"
tset "$TUN_APP.ssh" '.after.account_id = "'"$OA"'" | del(.after_unknown.account_id)'
tchk "B1-red-old-account: an app planned on the OLD account is refused" "$TUN_APP.ssh carries an id that is not the new"
tset "$TUN_POL_SSH" '.after_unknown.account_id = true'
tchk "B1-red-other-address-policy: a known-after-apply account_id on a policy is refused" "$TUN_POL_SSH carries an id that is not the new"
tset "cloudflare_record.ssh" '.after_unknown.account_id = true'
tchk "B1-red-other-address-record: a known-after-apply account_id on a record is refused" "cloudflare_record.ssh carries an id that is not the new"
gate_mutate_and_check "M-B1-address: dropping the address limit admits that record" \
  's/ and (\.address as \$x | \$zoned | index(\$x) != null)) as \$za/) as $za/' cf_account_migrate_gate tunnel "$TMP/tm.json" "$TMP/tun-state.json"
jq -c '(.resource_changes[] | select(.address=="cloudflare_bot_management.soleur_ai") | .change.after_unknown) = {account_id: true}' "$TMP/zr.json" >"$TMP/zr-acct.json"
check "B1-red-other-phase: a known-after-apply account_id in zone-rest is refused" 1 "cloudflare_bot_management.soleur_ai carries an id that is not the new" zone-rest "$TMP/zr-acct.json" "$TMP/zr-state.json"
gate_mutate_and_check "M-B1-phase: dropping the phase and address limits admits the zone-rest plan" \
  's/(\$phase == "tunnel" and \$z == \$nz and (\.address as \$x | \$zoned | index(\$x) != null)) as \$za/(true) as $za/' \
  cf_account_migrate_gate zone-rest "$TMP/zr-acct.json" "$TMP/zr-state.json"

# B2: each policy's content, one violated property per row.
check "B2-green: the three policies and three apps as committed pass" 0 "verdict=PASS creates=14" tunnel "$TMP/tun.json" "$TMP/tun-state.json"
OTHER_UUID="99999999-2222-4333-8444-555555555555"
for pa in "$TUN_POL" "$TUN_POL_SSH" "$TUN_POL_REG"; do
  s="${pa##*.}"
  tset "$pa" '.after.decision = "bypass"'; tchk "B2-$s-decision-bypass: refused" "$pa must plan decision non_identity"
  tset "$pa" '.after.decision = "allow"'; tchk "B2-$s-decision-allow: refused" "$pa must plan decision non_identity"
  tset "$pa" '.after.decision = null | .after_unknown.decision = true'; tchk "B2-$s-decision-unknown: refused" "$pa must plan decision non_identity"
  tset "$pa" '.after.include += [.after.include[0]]'; tchk "B2-$s-two-includes: refused" "$pa must plan exactly one include block"
  tset "$pa" '.after.include = []'; tchk "B2-$s-no-include: refused" "$pa must plan exactly one include block"
  tset "$pa" '.after.include[0].everyone = true'; tchk "B2-$s-everyone: refused" "$pa include carries another rule (everyone)"
  tset "$pa" '.after.include[0].any_valid_service_token = true'; tchk "B2-$s-any-valid-token: refused" "$pa include carries another rule (any_valid_service_token)"
  tset "$pa" '.after.include[0].email = ["someone@example.invalid"]'; tchk "B2-$s-email: refused" "$pa include carries another rule (email)"
  tset "$pa" '.after_unknown.include[0].email_domain = true'; tchk "B2-$s-selector-unknown: refused" "$pa include carries another rule (email_domain, known only after apply)"
  tcfg "$pa" '.include[0].everyone = {constant_value: true}'; tchk "B2-$s-config-extra-selector: refused" "$pa configuration include must hold only service_token"
  tcfg "$pa" '.include += [.include[0]]'; tchk "B2-$s-config-two-includes: refused" "$pa configuration include must hold only service_token"
  tcfg "$pa" '.include[0].service_token = {references: ["'"$TUN_TOK"'.other.id", "'"$TUN_TOK"'.other"]}'; tchk "B2-$s-foreign-token-ref: refused" "$pa include is not its own committed token reference"
  tcfg "$pa" '.include[0].service_token = {constant_value: ["'"$OTHER_UUID"'"]}'; tchk "B2-$s-literal-token: refused" "$pa include is not its own committed token reference"
  tcfg "$pa" '.application_id.references = ["'"$TUN_APP"'.other.id", "'"$TUN_APP"'.other"]'; tchk "B2-$s-foreign-app: refused" "$pa application_id does not reference"
  tun_mut 'del(.resource_changes[] | select(.address=="'"$pa"'"))'; tchk "B2-$s-absent: refused" "$pa must appear exactly once"
done
tcfg "$TUN_POL_REG" '.include[0].service_token = {references: ["'"$TUN_TOK"'.ci_ssh.id", "'"$TUN_TOK"'.ci_ssh"]}'
tchk "B2-registry-uses-ssh-token: refused" "$TUN_POL_REG include is not its own committed token reference"
tun_mut 'del(.configuration)'; tchk "B2-no-configuration: refused (absence is not proof)" "configuration include must hold only service_token"
tset "$TUN_POL" '.after.include[0].service_token += ["'"$OTHER_UUID"'"] | .after_unknown.include[0].service_token = [false, false]'
tchk "B2-deploy-two-tokens: refused" "$TUN_POL include must hold exactly one service token"
tset "$TUN_POL" '.after.include[0].service_token = ["00000000-0000-0000-0000-000000000000"]'
tchk "B2-deploy-nil-placeholder: refused" "$TUN_POL include service token is not a non-nil UUID"
tset "$TUN_POL" 'del(.after.include[0].service_token) | .after_unknown.include[0].service_token = true'
tchk "B2-deploy-token-unknown: refused (a committed constant is always known)" "$TUN_POL include must hold exactly one service token"
for pa in "$TUN_POL_SSH" "$TUN_POL_REG"; do
  s="${pa##*.}"
  tset "$pa" '.after.include[0].service_token = ["00000000-0000-0000-0000-000000000000"] | .after_unknown.include[0].service_token = [false]'
  tchk "B2-$s-redispatch-nil: refused" "$pa include service token is not a non-nil UUID"
  tset "$pa" '.after.include[0].service_token = ["'"$TUN_UUID"'", "'"$OTHER_UUID"'"] | .after_unknown.include[0].service_token = [false, false]'
  tchk "B2-$s-redispatch-two-tokens: refused" "$pa include must hold exactly one service token"
  tset "$pa" '.actions = ["no-op"] | .after.include[0].service_token = ["'"$TUN_UUID"'"] | .after_unknown.include[0].service_token = [false]'
  tchk "B2-$s-redispatch-green: one known UUID passes" "verdict=PASS" 0
done

# B2: each registry-push Doppler secret takes its value from the registry_push token, so a plan
# cannot put another token (the CI-SSH secret, say) into the prd runtime config.
for spec in id:client_id secret:client_secret; do
  ra="doppler_secret.registry_push_access_token_${spec%%:*}"
  tcfg "$ra" '.value.references = ["'"$TUN_TOK"'.ci_ssh.'"${spec#*:}"'", "'"$TUN_TOK"'.ci_ssh"]'; tchk "B2-reg-$spec-other-token: refused" "$ra value is not $TUN_TOK.registry_push.${spec#*:}"
  tcfg "$ra" 'del(.value)'; tchk "B2-reg-$spec-no-reference: refused" "$ra value is not $TUN_TOK.registry_push.${spec#*:}"
done

# B2: the tunnel config routes exactly the three gated hosts, in order, then the 404 catch-all, each
# to its own scheme (security review 2026-11-25). Another hostname or service reaches the origin.
TCF="cloudflare_zero_trust_tunnel_cloudflared_config.web"
tset "$TCF" '.after.config[0].ingress_rule |= [.[0], {hostname: "admin.soleur.ai", service: "http://10.0.1.12:8080"}] + .[1:]'
tchk "B2-ingress-extra-host: an extra hostname rule is refused" "$TCF must route exactly deploy., ssh. and registry.soleur.ai, then the catch-all"
tset "$TCF" '.after.config[0].ingress_rule |= [.[1], .[0]] + .[2:]'
tchk "B2-ingress-order: a reordered rule list is refused" "$TCF must route exactly deploy., ssh. and registry.soleur.ai, then the catch-all"
tset "$TCF" '.after.config[0].ingress_rule[3].service = "ssh://10.0.1.12:22"'
tchk "B2-ingress-catch-all: a catch-all that is not http_status:404 is refused" "$TCF ingress rule 4 must use http_status:404"
tset "$TCF" '.after.config[0].ingress_rule[0].service = "ssh://10.0.1.12:22"'
tchk "B2-ingress-scheme: deploy. on another scheme is refused" "$TCF ingress rule 1 must use http://"
tset "$TCF" '.after.config[0].ingress_rule[2].service = null | .after_unknown.config = [{ingress_rule: [{}, {}, {service: true}, {}]}]'
tchk "B2-ingress-unknown: a service known only after apply is refused" "$TCF ingress is known only after apply"
tset "$TCF" '.after.config = []'
tchk "B2-ingress-missing: a config with no ingress rules is refused" "$TCF must plan one config block"

# B2: each gated host is a proxied CNAME to this tunnel (security review 2026-11-25): an unproxied
# record, another type or another target would serve the origin with no Access app in front.
for n in deploy ssh registry; do
  ra="cloudflare_record.$n"
  tset "$ra" '.after.proxied = false'; tchk "B2-cname-$n-unproxied: refused" "$ra must plan a proxied CNAME $n to the tunnel (proxied"
  tset "$ra" '.after.type = "A" | .after.content = "135.181.45.178" | del(.after_unknown.content)'; tchk "B2-cname-$n-type: refused" "$ra must plan a proxied CNAME $n to the tunnel (type"
  tset "$ra" '.after.name = "admin"'; tchk "B2-cname-$n-name: refused" "$ra must plan a proxied CNAME $n to the tunnel (name"
  tset "$ra" '.after.content = "origin.example.com" | del(.after_unknown.content)'; tchk "B2-cname-$n-target: refused" "$ra must plan a proxied CNAME $n to the tunnel (content"
  tset "$ra" '.after.content = "0b1c2d3e-aaaa-bbbb-cccc-0123456789ab.cfargotunnel.com" | del(.after_unknown.content)'; tchk "B2-cname-$n-known-tunnel: a known tunnel target passes (re-dispatch)" "verdict=PASS" 0
  tcfg "$ra" '.content.references = ["var.origin_host"]'; tchk "B2-cname-$n-unknown-elsewhere: an unknown target that is not the tunnel is refused" "$ra must plan a proxied CNAME $n to the tunnel (content"
done

# B2: the three Access apps, one violated pin per row.
for spec in deploy:24h ssh:15m registry:15m; do
  n="${spec%%:*}"; aa="$TUN_APP.$n"
  tset "$aa" '.after.domain = "other.soleur.ai"'; tchk "B2-app-$n-domain: refused" "$aa must plan its Access pin (domain differs"
  tset "$aa" '.after.domain = null | .after_unknown.domain = true'; tchk "B2-app-$n-domain-unknown: refused" "$aa must plan its Access pin (domain known only after apply"
  tset "$aa" '.after.type = "bookmark"'; tchk "B2-app-$n-type: refused" "$aa must plan its Access pin (type differs"
  tset "$aa" '.after.session_duration = "720h"'; tchk "B2-app-$n-session: refused" "$aa must plan its Access pin (session_duration differs"
  tset "$aa" '.after.zone_id = "'"$OZ"'"'; tchk "B2-app-$n-zone: refused" "$aa must plan its Access pin (zone_id differs"
  # The routine gate's access_app_keys tail: each must plan blank, known or unknown (security review
  # 2026-11-25). Any one of them can open the host while domain/type/session/zone stay pinned.
  for kv in 'policies:["'"$OTHER_UUID"'"]' 'options_preflight_bypass:true' 'self_hosted_domains:["deploy.soleur.ai"]' \
            'destinations:[{"type":"public","uri":"'"${n}"'.soleur.ai/hooks/x"}]' 'cors_headers:[{"allow_all_origins":true}]'; do
    k="${kv%%:*}"; v="${kv#*:}"
    tset "$aa" ".after.$k = $v"; tchk "B2-app-$n-$k: refused" "$aa must leave $k unset"
    tset "$aa" ".after.$k = null | .after_unknown.$k = true"; tchk "B2-app-$n-$k-unknown: refused" "$aa must leave $k unset (known only after apply)"
  done
done
tset "$TUN_APP.deploy" '.after.policies = ["'"$OTHER_UUID"'"] | .after.destinations = [{"type":"public","uri":"deploy.soleur.ai/hooks/x"}] | .after.options_preflight_bypass = true | .after.cors_headers = [{"allow_all_origins":true}]'
tchk "B2-app-reported-plan: an app with a foreign policy, a path destination, preflight bypass and open CORS is refused" "$TUN_APP.deploy must leave policies unset"

# B2: Terraform collapses a list holding one unknown element to wholly unknown (measured on provider
# 4.52.7), so `[token.id, "<another uuid>"]` plans exactly like `[token.id]`. Only the committed
# source can show the extra grantee, so the gate reads the include blocks of tunnel.tf.
SRCT="$TMP/src-tree"; mkdir -p "$SRCT/infra"
cp "$IMPORTS" "$SRCT/infra/cf-account-migration-imports.tf"; cp "$GATE" "$SRCT/gate.sh"
src_gate() { CFAM_IMPORTS_FILE="$SRCT/infra/cf-account-migration-imports.tf" bash -c "source '$PREAMBLE'; source '$SRCT/gate.sh'; cf_account_migrate_gate tunnel '$TMP/tun.json' '$TMP/tun-state.json'" 2>&1; }
cp "$INFRA/tunnel.tf" "$SRCT/infra/tunnel.tf"
src_out="$(src_gate)"; src_rc=$?
if [[ "$src_rc" -eq 0 ]]; then pass "B2-source-green: the committed tunnel.tf include blocks pass"; else fail "B2-source-green" "$src_rc" "$src_out"; fi
src_row() { # <row> <address> <sed expression over tunnel.tf>
  local out rc
  sed "$3" "$INFRA/tunnel.tf" >"$SRCT/infra/tunnel.tf"
  if cmp -s "$SRCT/infra/tunnel.tf" "$INFRA/tunnel.tf"; then fail "$1: the mutation did not land" 1 ""; return; fi
  out="$(src_gate)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"REFUSE $2 committed include is not exactly its own token reference"* && "$out" != *"$OTHER_UUID"* ]]; then pass "$1: refused"
  else fail "$1" "$rc" "$out"; fi
}
src_row "B2-source-ci_ssh-extra-literal" "$TUN_POL_SSH" "s/service_token = \[$TUN_TOK\.ci_ssh\.id\]/service_token = [$TUN_TOK.ci_ssh.id, \"$OTHER_UUID\"]/"
src_row "B2-source-registry-extra-literal" "$TUN_POL_REG" "s/service_token = \[$TUN_TOK\.registry_push\.id\]/service_token = [$TUN_TOK.registry_push.id, \"$OTHER_UUID\"]/"
src_row "B2-source-deploy-concat" "$TUN_POL" "s/service_token = local\.deploy_service_token_ids/service_token = concat(local.deploy_service_token_ids, [\"$OTHER_UUID\"])/"
src_row "B2-source-second-include" "$TUN_POL_SSH" "s/^    service_token = \[$TUN_TOK\.ci_ssh\.id\]/&\n  }\n\n  include {\n    everyone = true/"
src_row "B2-source-extra-selector" "$TUN_POL_REG" "s/^    service_token = \[$TUN_TOK\.registry_push\.id\]/&\n    everyone = true/"
src_row "B2-source-dynamic-include" "$TUN_POL" 's/^  include {$/  dynamic "include" {\n    for_each = [1]\n    content {\n      everyone = true\n    }\n  }\n  include {/'
rm -f "$SRCT/infra/tunnel.tf"
src_out="$(src_gate)"; src_rc=$?
if [[ "$src_rc" -eq 1 && "$src_out" == *"committed tunnel.tf is not readable"* ]]; then pass "B2-source-unreadable: refused"
else fail "B2-source-unreadable" "$src_rc" "$src_out"; fi

tun_mut "$(tpol '.decision = "bypass" | .include[0].everyone = true')"
check "B2-reported-plan: decision bypass with everyone = true is refused" 1 "$TUN_POL must plan decision non_identity" tunnel "$TMP/tm.json" "$TMP/tun-state.json"
gate_mutate_and_check "M-B2-policy: dropping the tunnel Access check admits that plan" \
  's|^  if \[\[ "\$phase" == tunnel \]\]; then$|  if false; then|' cf_account_migrate_gate tunnel "$TMP/tm.json" "$TMP/tun-state.json"
tset "$TUN_APP.deploy" '.after.session_duration = "720h"'
gate_mutate_and_check "M-B2-app: dropping the tunnel Access check admits an app with another session" \
  's|^  if \[\[ "\$phase" == tunnel \]\]; then$|  if false; then|' cf_account_migrate_gate tunnel "$TMP/tm.json" "$TMP/tun-state.json"
# A tunnel plan over an entry the redirects-dns forget did not remove stays refused.
tset "$TUN_APP.ssh" '.actions = ["update"] | .before = {zone_id: "'"$OZ"'"}'
tchk "B3-red-unforgotten: an update of an entry still on the OLD zone is refused" "$TUN_APP.ssh (class create) planned as an update"
if [[ "$(cf_account_migrate_deploy_token_id "$TMP/tun.json")" == "$TUN_UUID" ]]; then pass "deploy_token_id: prints the one planned UUID"; else fail "deploy_token_id: wrong id" 1 ""; fi
tun_mut "$(tpol '.include[0].service_token = ["00000000-0000-0000-0000-000000000000"]')"
if cf_account_migrate_deploy_token_id "$TMP/tm.json" >/dev/null 2>&1; then fail "deploy_token_id: accepted the nil UUID" 0 ""; else pass "deploy_token_id: refuses the nil UUID"; fi
tun_mut "$(tpol '.include[0].service_token += ["99999999-2222-4333-8444-555555555555"]')"
if cf_account_migrate_deploy_token_id "$TMP/tm.json" >/dev/null 2>&1; then fail "deploy_token_id: accepted two tokens" 0 ""; else pass "deploy_token_id: refuses two tokens"; fi

# The live verdict: 8040h to expiry is inside the band, the far edges are not.
TV_NOW=1800000000
tv_body() { # <name> <hours to expiry> [<id>]
  jq -nc --arg id "${3:-$TUN_UUID}" --arg n "$1" --argjson e "$((TV_NOW + $2 * 3600))" \
    '{success:true,result:{id:$id,name:$n,expires_at:($e|todate),client_id:"SYNTH-CLIENT-ID-NOT-PRINTED"}}'
}
tv() { # <label> <want> <body>
  local got rc=0
  got="$(cf_account_migrate_deploy_token_verdict "$TUN_UUID" "$TV_NOW" <<<"$3")" || rc=$?
  if [[ "$got" == "$2" && ( "$2" == ok && "$rc" -eq 0 || "$2" != ok && "$rc" -eq 1 ) && "$got" != *SYNTH* ]]; then pass "deploy-token verdict: $1 -> $2"
  else fail "deploy-token verdict: $1" "$rc" "got [$got], want [$2]"; fi
}
tv "8760h, the right name" ok "$(tv_body github-actions-deploy 8760)"
tv "8040h (the mint preceded the merge by a month)" ok "$(tv_body github-actions-deploy 8040)"
tv "fractional-second expiry" ok "$(tv_body github-actions-deploy 8760 | jq -c '.result.expires_at |= sub("Z$"; ".123456Z")')"
tv "another token name" name-differs "$(tv_body github-actions-ci-ssh 8760)"
tv "another token id" id-differs "$(tv_body github-actions-deploy 8760 99999999-2222-4333-8444-555555555555)"
tv "a 30-day token" expiry-out-of-window "$(tv_body github-actions-deploy 720)"
tv "a ten-year token" expiry-out-of-window "$(tv_body github-actions-deploy 87600)"
tv "an expired token" expiry-out-of-window "$(tv_body github-actions-deploy -1)"
# The band's edges are inclusive: pinned on both sides so neither bound can drift unnoticed.
tv "exactly the 8016h floor" ok "$(tv_body github-actions-deploy 8016)"
tv "one hour under the floor (8015h)" expiry-out-of-window "$(tv_body github-actions-deploy 8015)"
tv "exactly the 8761h ceiling" ok "$(tv_body github-actions-deploy 8761)"
tv "one hour over the ceiling (8762h)" expiry-out-of-window "$(tv_body github-actions-deploy 8762)"
tv "no expiry" expiry-absent "$(tv_body github-actions-deploy 8760 | jq -c 'del(.result.expires_at)')"
tv "an unparseable expiry" expiry-unparseable "$(tv_body github-actions-deploy 8760 | jq -c '.result.expires_at = "soon"')"
tv "success false" body-not-success '{"success":false,"result":null}'
tv "not JSON" body-unparseable 'not-json'

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
# neuter <anchor>: a sed expression that turns the one `v="$(jq` opener on the line matching
# <anchor> into `v="$(: jq`, so that check yields no violation lines (each anchor is unique).
# shellcheck disable=SC2016 # a sed expression over literal gate text
neuter() { printf '/%s/s|v="\\$(jq|v="$(: jq|' "$1"; }
# Layered: a delete of an in-set create-class address is also off-class, so neutering the destroy
# arm must hand the refusal to the class arm, never to PASS.
mutate_plan "$VALID" "$TMP/r1c.json" '(.resource_changes[] | select(.address=="cloudflare_list.www_canonical") | .change.actions) = ["delete"]'
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_layered "M-forget: the destroy arm owns a delete refusal; neutered it hands off to the class arm" \
  "$(neuter '^  v="\$(jq -r --argjson spec "\$spec" .\.resource_changes\[\] | select((\.mode')" \
  "destroys or forgets" "planned with actions" cf_account_migrate_gate redirects-dns "$TMP/r1c.json"
# Sole guard: a replace of a mutable secret is refused only by the class arm since the destroy arm
# exempts nothing but the declared replace set.
jq -c '(.resource_changes[] | select(.address=="github_actions_secret.cloudflare_account_id_pages") | .change.actions) = ["delete","create"]' "$TMP/zr.json" > "$TMP/zrrep.json"
check "zone-rest: a replace of a mutable secret is refused" 1 "REFUSE" zone-rest "$TMP/zrrep.json" "$TMP/zr-state.json"
jq -c '(.resource_changes[] | select(.address=="github_actions_secret.cloudflare_account_id_pages") | .change.actions) = ["create","create"]' "$TMP/zr.json" > "$TMP/zrcc.json"
check "zone-rest: a mutable planned [create,create] is refused (exact match, not containment)" 1 "(class mutable) planned with actions" zone-rest "$TMP/zrcc.json" "$TMP/zr-state.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-id: neutering the new-id check admits row 3" \
  "$(neuter '--arg nz "\$CFAM_NEW_ZONE_ID"')" cf_account_migrate_gate redirects-dns "$TMP/r3.json"
# The pre-review id check defaulted an absent id to the new one; restoring that reads row 3d as a pass.
# shellcheck disable=SC2016 # sed expressions match literal gate text
gate_mutate_and_check "M-id-absent: dropping the 'at least one NEW id' clause admits an absent zone_id (row 3d)" \
  's|        or (\$z != \$nz and \$a != \$na))|        )|' cf_account_migrate_gate redirects-dns "$TMP/r3d.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
gate_mutate_and_check "M-id-unknown: dropping the after_unknown clause admits row 3g2" \
  's|^        (\$u.zone_id == true) or (\$u.account_id == true)$|        false|' cf_account_migrate_gate redirects-dns "$TMP/r3g2.json"
# The zone-id secret check also refuses row 3j, so on 3j this arm is layered; on the github secret
# (zone-rest) it is the sole guard.
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_layered "M-noncf-old: the old-id check owns row 3j; neutered it hands off to the expected-values check" \
  "$(neuter '--arg oz "\$CFAM_OLD_ZONE_ID"')" "republishes an OLD" "must plan its expected value" cf_account_migrate_gate redirects-dns "$TMP/r3j.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-noncf-old-gh: neutering the non-Cloudflare old-id check admits the token-valued github secret carrying the OLD account" \
  "$(neuter '--arg oz "\$CFAM_OLD_ZONE_ID"')" cf_account_migrate_gate zone-rest "$TMP/zrold-tok.json" "$TMP/zr-state.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-zsec: neutering the expected-values check admits Z1 (a third id)" \
  "$(neuter '--argjson want "\$want"')" cf_account_migrate_gate redirects-dns "$TMP/z1.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-zsec-update: neutering the expected-values check admits Z4 (an in-state update to a third id)" \
  "$(neuter '--argjson want "\$want"')" cf_account_migrate_gate redirects-dns "$TMP/z4.json" "$TMP/z-state.json"
# One mutant per table member: deleting its `+` line admits that member's wrong value.
gate_mutate_and_check "M-want-doppler: dropping the $ZSEC table entry admits Z1" \
  '/^    + {"doppler_secret.cf_zone_id_prd": /d' cf_account_migrate_gate redirects-dns "$TMP/z1.json"
gate_mutate_and_check "M-want-pages: dropping the $GAP table entry admits P1" \
  '/^    + {"github_actions_secret.cloudflare_account_id_pages": /d' cf_account_migrate_gate zone-rest "$TMP/g1.json" "$TMP/zr-state.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gate_mutate_and_check "M-want-noop: grading creates and updates only admits P3 (a no-op on a third account)" \
  's/^    | select(\.change\.after != null) | (\.change\.after_unknown/    | select(.change.after != null and .change.actions != ["no-op"]) | (.change.after_unknown/' cf_account_migrate_gate zone-rest "$TMP/g3.json" "$TMP/zr-state.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
gate_mutate_and_check "M-replace-class (G2): neutering the replace clause admits a bare delete of the replace target" \
  's|(\$cls == "replace" and .change.actions != \["delete","create"\])|($cls == "replace" and false)|' \
  cf_account_migrate_gate zone-rest "$TMP/zrg2.json" "$TMP/zr-state.json"
gate_mutate_and_check "M-replace-order (D36): accepting create-before-destroy again admits row 9d" \
  's|(\$cls == "replace" and .change.actions != \["delete","create"\])|($cls == "replace" and .change.actions != ["delete","create"] and .change.actions != ["create","delete"])|' \
  cf_account_migrate_gate zone-rest "$TMP/zrcbd.json" "$TMP/zr-state.json"
# Inverse direction: narrowing the R2 carve-out back to the bucket type must REFUSE row 5c.
r2m="$TMP/mutated-r2.sh"
sed 's/select(.type | startswith("cloudflare_r2_") | not)/select(.type != "cloudflare_r2_bucket")/' "$GATE" > "$r2m"
r2out="$(bash -c "source '$PREAMBLE'; source '$r2m'; cf_account_migrate_gate redirects-dns '$TMP/r5c.json'" 2>&1)"; r2rc=$?
if cmp -s "$r2m" "$GATE"; then fail "M-r2-prefix: the mutation did not land" 1 ""
elif [[ "$r2rc" -eq 1 && "$r2out" == *"cloudflare_r2_bucket_cors.state carries an id that is not the new"* ]]; then
  pass "M-r2-prefix: narrowing the R2 carve-out to the bucket type refuses row 5c (the prefix is load-bearing)"
else fail "M-r2-prefix: narrowing the R2 carve-out did not change row 5c" "$r2rc" "$r2out"; fi
# The imports-file seam: in a tree where the committed imports file is reachable, an override
# naming another file is ignored, so a forged literal cannot rubber-stamp row 10's id.
SEAM="$TMP/seam-tree"; mkdir -p "$SEAM/tests/scripts/lib" "$SEAM/apps/web-platform/infra" "$SEAM/forged"
cp "$GATE" "$PREAMBLE" "$SEAM/tests/scripts/lib/"
cp "$IMPORTS" "$SEAM/apps/web-platform/infra/cf-account-migration-imports.tf"
first_id="$(head -1 "$imports_tsv" | cut -f2)"
sed "s|\"${first_id}\"|\"${NZ}/ffffffffffffffffffffffffffffffff\"|" "$IMPORTS" > "$SEAM/forged/imports.tf"
# Row 10 with the record's own id moved to the forged one too, so a honoured forgery satisfies the pin.
mutate_plan "$TMP/r10.json" "$TMP/r10-seam.json" '(.resource_changes[] | select(.address=="'"$first_import"'") | .change) |= (.before.id = "ffffffffffffffffffffffffffffffff" | .after.id = "ffffffffffffffffffffffffffffffff")'
seam_run() { # <gate-copy>: grade row 10 with CFAM_IMPORTS_FILE pointing at the forged file
  CFAM_IMPORTS_FILE="$SEAM/forged/imports.tf" bash -c "source '$PREAMBLE'; source '$1'; cf_account_migrate_gate redirects-dns '$TMP/r10-seam.json'" 2>&1
}
seam_out="$(seam_run "$SEAM/tests/scripts/lib/cf-account-migrate-gate.sh")"; seam_rc=$?
if cmp -s "$SEAM/forged/imports.tf" "$IMPORTS"; then fail "imports seam: the forged file equals the committed one (fixture did not land)" 1 ""
elif [[ "$seam_rc" -eq 1 && "$seam_out" == *"differs from the committed literal"* && "$seam_out" == *"ignoring CFAM_IMPORTS_FILE"* ]]; then
  pass "imports seam: an override naming a forged imports file is ignored where the committed file is reachable"
else fail "imports seam: a forged imports file was honoured" "$seam_rc" "$seam_out"; fi
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's|^if \[\[ -n "\${CFAM_IMPORTS_FILE:-}" && -e |if false \&\& [[ -e |' "$SEAM/tests/scripts/lib/cf-account-migrate-gate.sh" > "$SEAM/tests/scripts/lib/seam-mut.sh"
seam_mut_out="$(seam_run "$SEAM/tests/scripts/lib/seam-mut.sh")"; seam_mut_rc=$?
if cmp -s "$SEAM/tests/scripts/lib/seam-mut.sh" "$GATE"; then fail "M-imports-seam: the mutation did not land" 1 ""
elif [[ "$seam_mut_rc" -eq 0 ]]; then pass "M-imports-seam: without the guard the forged literal passes row 10 (the guard is load-bearing)"
else fail "M-imports-seam: removing the guard did not admit the forged literal" "$seam_mut_rc" "$seam_mut_out"; fi
# A non-record import has no other guard. On a record the outside-import-normalize check also refuses.
mutate_plan "$VALID" "$TMP/r9p.json" '(.resource_changes[] | select(.address=="cloudflare_pages_project.docs") | .change.actions) = ["update"]'
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-pure: neutering the pure-import check admits a Pages import planned as an update" \
  "$(neuter '^  v="\$(jq -r .\.resource_changes\[\] | select(\.change\.importing != null)')" cf_account_migrate_gate redirects-dns "$TMP/r9p.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_layered "M-pure-record: the pure-import check owns row 9; neutered it hands off to the record-change check" \
  "$(neuter '^  v="\$(jq -r .\.resource_changes\[\] | select(\.change\.importing != null)')" \
  "not a pure no-op import" "is a cloudflare_record change outside import-normalize" cf_account_migrate_gate redirects-dns "$TMP/r9.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-literal: neutering the literal check admits row 10" \
  "$(neuter '--argjson lit "\$literals"')" cf_account_migrate_gate redirects-dns "$TMP/r10.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-missing: neutering the presence check admits row 11" \
  "$(neuter 'as \$have$')" cf_account_migrate_gate redirects-dns "$TMP/r11.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-reason: neutering the replace_by_request check admits row 9b" \
  "$(neuter '^    v="\$(jq .*select(\$spec\[\.address\] == "replace")$')" cf_account_migrate_gate zone-rest "$TMP/zr9b.json" "$TMP/zr-state.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-physid: neutering the physical-id check admits row 9c" \
  "$(neuter '--slurpfile st')" cf_account_migrate_gate zone-rest "$TMP/zr9c.json" "$TMP/zr-state.json"
# shellcheck disable=SC2016 # sed anchors match literal gate text
gate_mutate_and_check "M-update: neutering the in-state update check admits U2 (an update of an address not in state)" \
  "$(neuter '--slurpfile pst')" cf_account_migrate_gate redirects-dns "$TMP/u1.json" "$TMP/u-state-other.json"
# Each neuter anchor lands on exactly one opener (a non-unique anchor would neuter two checks and
# could pass a row for the wrong arm's reason).
n_bad=""
# shellcheck disable=SC2016 # sed anchors match literal gate text
for a in '^  v="\$(jq -r --argjson spec "\$spec" .\.resource_changes\[\] | select((\.mode' '--arg nz "\$CFAM_NEW_ZONE_ID"' \
  '--arg oz "\$CFAM_OLD_ZONE_ID"' '^  v="\$(jq -r .\.resource_changes\[\] | select(\.change\.importing != null)' \
  '--argjson lit "\$literals"' 'as \$have$' '^    v="\$(jq .*select(\$spec\[\.address\] == "replace")$' '--slurpfile st' \
  '--slurpfile pst' '--argjson want "\$want"'; do
  sed "$(neuter "$a")" "$GATE" > "$TMP/neuter.sh"
  [[ "$(diff "$GATE" "$TMP/neuter.sh" | grep -c '^>')" -eq 1 ]] || n_bad+=" [$a]"
done
if [[ -z "$n_bad" ]]; then pass "neuter: each of the 10 mutation anchors rewrites exactly one check opener"
else fail "neuter: anchors that do not land on exactly one opener:$n_bad" 1 ""; fi
gate_mutate_layered "M-preamble: the gate INVOKES the readable assert (not merely sources it)" \
  's|^  plan_gate_assert_readable .*|  :|' "an unreadable plan is not evidence" "unclassifiable plan entry" cf_account_migrate_gate redirects-dns "$TMP/d2.json"
gate_mutate_layered "M-classify: the gate INVOKES the classifiable assert; neutered, the eval-fail arm still refuses" \
  's|^  plan_gate_assert_classifiable .*|  :|' "unclassifiable plan entry" "REFUSE" cf_account_migrate_gate redirects-dns "$TMP/d1.json"
gate_mutate_and_check "M-evalfail: the jq-error refusal is load-bearing (a check that cannot evaluate must not read as no violations)" \
  's|_cfam_eval_fail; return 1;|:;|g' cf_account_migrate_gate zone-rest "$TMP/zr9c-badstate.json" "$TMP/zr-badstate.json"

# ── one source: the job, the state forget and the predicate read the shared constants here ──
# The literals are this suite's own (an oracle independent of the library), so a typo in the
# library reds here; a consumer that re-types one, or keeps its own serial reader, reds below.
if [[ "$CFAM_OLD_ZONE_ID" == "$OZ" && "$CFAM_OLD_ACCOUNT_ID" == "$OA" && "$CFAM_STATE_BUCKET" == soleur-terraform-state \
      && "$CFAM_BACKUP_PREFIX" == web-platform/backups/ && "$CFAM_R2_ENDPOINT" == "https://$OA.r2.cloudflarestorage.com" ]] \
   && printf '{"serial":7}' > "$TMP/ser.json" && [[ "$(cfam_serial_of "$TMP/ser.json")" == 7 ]] \
   && printf '{"serial":"7"}' > "$TMP/ser.json" && ! cfam_serial_of "$TMP/ser.json" >/dev/null; then
  pass "one source: the library holds the OLD ids, bucket, backup prefix, legacy R2 endpoint and a numeric-only serial reader"
else fail "one source: a shared constant or cfam_serial_of is wrong" 1 ""; fi
CONSUMER_DIR="$HERE/../../apps/web-platform/infra/scripts"
# own_copies <file>: code lines (full-line comments dropped) that re-type a shared literal or a
# serial reader, or run `aws s3…` outside cfam_r2_aws; "no-shared-call" when it never uses it.
own_copies() {
  local code; code="$(grep -vE '^[[:space:]]*#' "$1")"
  grep -nE "${OZ}|${OA}|${NZ}|${NA}|soleur-terraform-state|web-platform/backups/|\.serial \| type|(^|[^_[:alnum:]-])aws s3(api)? " <<<"$code"
  grep -q 'cfam_r2_aws s3' <<<"$code" || echo "no-shared-call"
}
# sources_lib <file>: the file carries one of the three reviewed source forms, as whole lines (and,
# where the path is a variable, the exact line that binds it). A filename in an assignment, an
# echo, `true || source …` or `: source …` is not one of them, so it is not loading the library.
# A consumer that changes its source line updates the matching pair here, in review.
# shellcheck disable=SC2016,SC1003 # literal consumer source text, never expanded here
{
  SRC_JOB_LIB='  local lib="$GITHUB_WORKSPACE/tests/scripts/lib"'
  SRC_JOB="  source \"\$lib/cf-account-migrate-gate.sh\" || { printf '%s: cannot source the phase gate\\n' \"\$P\" >&2; exit 2; }"
  SRC_FORGET='source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../tests/scripts/lib/cf-account-migrate-gate.sh" \'
  SRC_FORGET_NEXT="  || { printf 'cf-state-migrate verdict=abort reason=gate-library-unusable\\n'; exit 1; }"
  SRC_PRED_LIB='readonly CFAM_GATE_LIB="${CFAM_SELF_DIR}/../../../../tests/scripts/lib/cf-account-migrate-gate.sh"'
  SRC_PRED='  { declare -F cf_account_migrate_phase_spec >/dev/null || source "$CFAM_GATE_LIB"; } || bad="unloadable"'
}
# next_line_is <file> <line> <next>: <line> is a whole line and the line right after it is exactly <next>
# (a backslash continuation joins them, so the pair is the statement).
next_line_is() { A="$2" B="$3" awk 'p && $0 == ENVIRON["B"] {f = 1} {p = ($0 == ENVIRON["A"])} END {exit !f}' "$1"; }
# follows_within <file> <line> <next> <allowed...>: <next> follows <line>, and every line between them
# is a full-line comment or one of the exact <allowed> lines (so nothing rebinds the path in between,
# and both sit in the same function body).
follows_within() {
  local f="$1" a="$2" b="$3"; shift 3
  A="$a" B="$b" ALLOW="$(printf '%s\n' "$@")" awk '
    BEGIN { n = split(ENVIRON["ALLOW"], al, "\n"); for (i = 1; i <= n; i++) if (al[i] != "") ok[al[i]] = 1 }
    on && $0 == ENVIRON["B"] { f = 1; on = 0; next }
    on && !($0 ~ /^[[:space:]]*#/ || ($0 in ok)) { on = 0 }
    $0 == ENVIRON["A"] { on = 1 }
    END { exit !f }' "$f"
}
# The one line the job runs between its lib binding and its source line (a seam strip, before sourcing).
SRC_JOB_BETWEEN='  unset CFAM_IMPORTS_FILE'
sources_lib() {
  follows_within "$1" "$SRC_JOB_LIB" "$SRC_JOB" "$SRC_JOB_BETWEEN" && return 0
  next_line_is "$1" "$SRC_FORGET" "$SRC_FORGET_NEXT" && return 0
  grep -qxF -- "$SRC_PRED_LIB" "$1" && grep -qxF -- "$SRC_PRED" "$1"
}
# The library's function names: every definition `name()` / `name ()` / `name(){` / `function name`,
# at column 0 (the library defines all its functions there). The count is exact (review).
LIB_FNS="$(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)[[:space:]]*(\{.*)?$/\1/p; s/^function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$GATE" | sort -u)"
LIB_FN_COUNT=21
# A definition may follow a command separator or a group opener on the same line (`:; f() {`,
# `true && f() {`, `{ f() {`, `then f() {`), not only the start of the line.
FN_PFX='(^|[;&|{(!]|(^|[[:space:]])(then|do|else|elif|time)[[:space:]])[[:space:]]*'
defines_lib_fn() { # <file>: each line of <file> that defines a library function name, in any bash form
  local fn
  while IFS= read -r fn; do
    grep -nE -- "${FN_PFX}(function[[:space:]]+${fn}([[:space:]]*\(\))?([[:space:]]|\{|$)|${fn}[[:space:]]*\(\))" "$1"
  done <<<"$LIB_FNS"
}
if [[ "$(grep -c . <<<"$LIB_FNS")" -eq "$LIB_FN_COUNT" && "$(defines_lib_fn "$GATE" | wc -l)" -eq "$LIB_FN_COUNT" ]] \
   && grep -qxF -- cf_account_migrate_phase_spec <<<"$LIB_FNS" && grep -qxF -- cfam_r2_aws <<<"$LIB_FNS"; then
  pass "one source: the library's function-name list is derived (exactly $LIB_FN_COUNT names, each found once by defines_lib_fn in the library itself)"
else fail "one source: the library's function names were not derived exactly ($(grep -c . <<<"$LIB_FNS"), want $LIB_FN_COUNT)" 1 "$LIB_FNS"; fi
sed 's/^cfam_serial_of() { /cfam_serial_of(){ /' "$GATE" > "$TMP/nospace.sh"
nospace_fns="$(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)[[:space:]]*(\{.*)?$/\1/p; s/^function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$TMP/nospace.sh" | sort -u)"
if cmp -s "$TMP/nospace.sh" "$GATE"; then fail "M-fn-nospace: the mutation did not land" 1 ""
elif [[ "$nospace_fns" == "$LIB_FNS" ]]; then pass "M-fn-nospace: a library function written name(){ is still derived"
else fail "M-fn-nospace: a name(){ definition dropped out of the derived list" 1 "$nospace_fns"; fi
# The library's constants (every CFAM_* it assigns). A consumer must not reassign one AFTER its source
# line: that would re-point what the bytes under test read (the gate's new-id check, check_ids, the
# forget's ids). Any bare mention of the name after the source line that is not an expansion ($N,
# ${N…}) is refused (assignment, declare/export/readonly/local, printf -v, read, unset, a nameref),
# except one reviewed line: the predicate's indirect shape check of the four ids.
LIB_VARS="$(sed -nE 's/^[[:space:]]*(CFAM_[A-Z0-9_]+)=.*/\1/p' "$GATE" | sort -u)"
LIB_VAR_COUNT=14
LIB_VAR_OK='  for v in CFAM_NEW_ZONE_ID CFAM_NEW_ACCOUNT_ID CFAM_OLD_ZONE_ID CFAM_OLD_ACCOUNT_ID; do'
if [[ "$(grep -c . <<<"$LIB_VARS")" -eq "$LIB_VAR_COUNT" ]] && grep -qxF CFAM_NEW_ZONE_ID <<<"$LIB_VARS" && grep -qxF CFAM_R2_ENDPOINT <<<"$LIB_VARS"; then
  pass "one source: the library's constant names are derived (exactly $LIB_VAR_COUNT, CFAM_NEW_ZONE_ID and CFAM_R2_ENDPOINT among them)"
else fail "one source: the library's constant names were not derived exactly" 1 "$LIB_VARS"; fi
reassigns_lib_var() { # <file> <source-line>: lines after <source-line> that name a library constant bare
  local v
  while IFS= read -r v; do
    SRC="$2" OKL="$LIB_VAR_OK" V="$v" awk '
      after && !/^[[:space:]]*#/ && $0 != ENVIRON["OKL"] {
        l = $0; gsub("[$][{]?[!#]?" ENVIRON["V"], "", l)
        if (l ~ ("(^|[^A-Za-z0-9_])" ENVIRON["V"] "([^A-Za-z0-9_]|$)")) print NR ": " $0 }
      $0 == ENVIRON["SRC"] { after = 1 }' "$1"
  done <<<"$LIB_VARS"
}
src_line_of() { case "$1" in cf-account-migrate-job.sh) printf '%s' "$SRC_JOB" ;; cf-account-state-migrate.sh) printf '%s' "$SRC_FORGET" ;; *) printf '%s' "$SRC_PRED" ;; esac; }
for c in cf-account-migrate-job.sh cf-account-state-migrate.sh cf-account-migration-complete.sh; do
  if sources_lib "$CONSUMER_DIR/$c" && [[ -z "$(own_copies "$CONSUMER_DIR/$c")" && -z "$(defines_lib_fn "$CONSUMER_DIR/$c")" \
       && -z "$(reassigns_lib_var "$CONSUMER_DIR/$c" "$(src_line_of "$c")")" ]]; then
    pass "one source: $c sources this library, re-types none of its ids, bucket, prefix, endpoint or serial reader, reassigns none of its constants, defines none of its functions, and makes every R2 call through cfam_r2_aws"
  else fail "one source: $c keeps its own copy (or does not source the library)" 1 "$(own_copies "$CONSUMER_DIR/$c"; defines_lib_fn "$CONSUMER_DIR/$c"; reassigns_lib_var "$CONSUMER_DIR/$c" "$(src_line_of "$c")")"; fi
done
# A consumer that redefines a library function (any bash form, on its own line or after a separator) is caught.
for form in 'cf_account_migrate_phase_spec() { printf "{}"; }' 'function cfam_r2_aws { :; }' ':; cfam_r2_aws() { :; }' \
            "true && cf_account_migrate_phase_spec() { printf '{}'; }" '{ cfam_r2_aws() { :; }; }' 'cfam_r2_aws(){ :; }' \
            'if true; then cfam_serial_of() { echo 7; }; fi'; do
  { cat "$CONSUMER_DIR/cf-account-migration-complete.sh"; printf '%s\n' "$form"; } > "$TMP/redef.sh"
  if [[ -n "$(defines_lib_fn "$TMP/redef.sh")" ]]; then pass "M-redef: a consumer defining [$form] is caught (RED)"
  else fail "M-redef: a consumer defining [$form] was not seen" 1 ""; fi
done
# A consumer that reassigns a library constant after sourcing is caught (two forms); the job's
# seam strip BEFORE its source line is not (the real-tree row above).
for form in 'CFAM_NEW_ZONE_ID="0123456789abcdef0123456789abcdef"' 'printf -v CFAM_OLD_ACCOUNT_ID %s x'; do
  sed "s/^readonly P=\"cf-state-migrate\"\$/&\n$form/" "$CONSUMER_DIR/cf-account-state-migrate.sh" > "$TMP/reassign.sh"
  if cmp -s "$TMP/reassign.sh" "$CONSUMER_DIR/cf-account-state-migrate.sh"; then fail "M-reassign: the mutation [$form] did not land" 1 ""
  elif [[ -n "$(reassigns_lib_var "$TMP/reassign.sh" "$SRC_FORGET")" ]]; then pass "M-reassign: a state forget that runs [$form] after sourcing is caught (RED)"
  else fail "M-reassign: [$form] after sourcing was not seen" 1 ""; fi
done
for idv in "OLD_ZONE_ID=$OZ" "NEW_ZONE_ID_COPY=$NZ" "NEW_ACCOUNT_ID_COPY=$NA"; do
  sed "s/^set -uo pipefail\$/&\nreadonly ${idv%%=*}=\"${idv#*=}\"/" "$CONSUMER_DIR/cf-account-state-migrate.sh" > "$TMP/own-copy.sh"
  if cmp -s "$TMP/own-copy.sh" "$CONSUMER_DIR/cf-account-state-migrate.sh"; then fail "M-own-copy ${idv%%=*}: the mutation did not land" 1 ""
  elif [[ -n "$(own_copies "$TMP/own-copy.sh")" ]]; then pass "M-own-copy: a state forget that re-types an id literal (${idv%%=*}) is caught (RED)"
  else fail "M-own-copy: a re-typed id literal (${idv%%=*}) was not seen" 1 ""; fi
done
sed 's/ || source "\$CFAM_GATE_LIB"; }/; }/' "$CONSUMER_DIR/cf-account-migration-complete.sh" > "$TMP/no-source.sh"
if cmp -s "$TMP/no-source.sh" "$CONSUMER_DIR/cf-account-migration-complete.sh"; then fail "M-no-source: the mutation did not land" 1 ""
elif ! sources_lib "$TMP/no-source.sh"; then pass "M-no-source: a predicate that names the library but never sources it is caught (RED)"
else fail "M-no-source: a predicate that never sources the library still reads as sourcing it" 1 ""; fi
# Each consumer's reviewed source line turned into a shape that loads nothing must read as NOT
# sourcing the library (the previous token-level match accepted all three).
src_mut() { # <kind> <consumer> <sed-expr>: the mutated consumer must NOT read as sourcing the library
  local out="$TMP/src-$1.sh"
  sed "$3" "$CONSUMER_DIR/$2" > "$out"
  if cmp -s "$out" "$CONSUMER_DIR/$2"; then fail "M-src-$1: the mutation did not land on $2" 1 ""
  elif ! sources_lib "$out"; then pass "M-src-$1: $2 whose source line becomes a $1 form is caught (RED)"
  else fail "M-src-$1: $2 with a $1 source form still reads as sourcing the library" 1 "$(grep -n 'cf-account-migrate-gate\|CFAM_GATE_LIB' "$out")"; fi
}
# shellcheck disable=SC2016 # sed expressions match literal consumer text
src_mut true-or cf-account-migrate-job.sh 's#^  source "\$lib/cf-account-migrate-gate.sh" #  true || source "$lib/cf-account-migrate-gate.sh" #'
# shellcheck disable=SC2016 # sed expressions match literal consumer text
src_mut colon cf-account-state-migrate.sh 's#^source "\$(cd #: source "$(cd #'
# shellcheck disable=SC2016 # sed expressions match literal consumer text
src_mut echo cf-account-migration-complete.sh 's#|| source "\$CFAM_GATE_LIB"; }#|| echo source "$CFAM_GATE_LIB"; }#'
# The forget's continuation line is part of its source statement: swallowing the failure or dropping
# the line (which joins `source …` to the next statement as arguments) is not the reviewed form.
src_mut cont-swallowed cf-account-state-migrate.sh "s#^  || { printf 'cf-state-migrate verdict=abort reason=gate-library-unusable.n'; exit 1; }\$#  || :#"
src_mut cont-dropped cf-account-state-migrate.sh "/^  || { printf 'cf-state-migrate verdict=abort reason=gate-library-unusable/d"
# The job's path binding must be the one in effect at its source line: a rebinding between them is not
# the reviewed form.
src_mut rebind cf-account-migrate-job.sh 's#^  unset CFAM_IMPORTS_FILE$#&\n  lib=/var/empty#'
sed 's/^    cfam_r2_aws s3 cp /    aws s3 cp /' "$CONSUMER_DIR/cf-account-migration-complete.sh" > "$TMP/bare-aws.sh"
if cmp -s "$TMP/bare-aws.sh" "$CONSUMER_DIR/cf-account-migration-complete.sh"; then fail "M-bare-aws: the mutation did not land" 1 ""
elif [[ -n "$(own_copies "$TMP/bare-aws.sh")" ]]; then pass "M-bare-aws: a predicate copy made with a bare aws call is caught (RED)"
else fail "M-bare-aws: a bare aws call was not seen" 1 ""; fi

# ── cfam_r2_aws: the one R2 call shape, under a hostile R2_ENDPOINT and IMDS setting ─────────
mkdir -p "$TMP/r2bin"
cat > "$TMP/r2bin/aws" <<'STUB'
#!/usr/bin/env bash
printf 'argv %s\n' "$*" >> "$R2_LOG"
printf 'env region=%s req=%s resp=%s imds-off=%s\n' "${AWS_DEFAULT_REGION:-unset}" "${AWS_REQUEST_CHECKSUM_CALCULATION:-unset}" \
  "${AWS_RESPONSE_CHECKSUM_VALIDATION:-unset}" "${AWS_EC2_METADATA_DISABLED:-unset}" >> "$R2_LOG"
STUB
cat > "$TMP/r2bin/timeout" <<'STUB'
#!/usr/bin/env bash
printf 'timeout %s\n' "$1" >> "$R2_LOG"; shift; exec "$@"
STUB
chmod +x "$TMP/r2bin/aws" "$TMP/r2bin/timeout"
# r2_shape <lib>: empty when the lib's cfam_r2_aws makes the pinned call; else the first broken property.
r2_shape() {
  : > "$TMP/r2.log"
  R2_LOG="$TMP/r2.log" PATH="$TMP/r2bin:$PATH" R2_ENDPOINT=https://r2.invalid AWS_EC2_METADATA_DISABLED=false \
    bash -c 'source "$1"; source "$2"; cfam_r2_aws s3 cp a b --only-show-errors' _ "$PREAMBLE" "$1" >/dev/null 2>&1
  grep -qxF "argv s3 cp a b --only-show-errors --endpoint-url https://$OA.r2.cloudflarestorage.com" "$TMP/r2.log" || { echo endpoint; return; }
  grep -qx 'env region=auto req=when_required resp=when_required imds-off=true' "$TMP/r2.log" || { echo env-prefix; return; }
  grep -qx 'timeout 60' "$TMP/r2.log" || echo unbounded
}
r2_got="$(r2_shape "$GATE")"
if [[ -z "$r2_got" ]]; then pass "cfam_r2_aws: the pinned endpoint (R2_ENDPOINT ignored), the R2 env prefix with IMDS off, a 60 s bound"
else fail "cfam_r2_aws call shape broken ($r2_got)" 1 "$(cat "$TMP/r2.log")"; fi
r2_mut() { # <label> <sed-expr> <want>: the mutated library must break exactly <want>
  local got
  sed "$2" "$GATE" > "$TMP/r2-mut.sh"
  if cmp -s "$TMP/r2-mut.sh" "$GATE"; then fail "$1: the mutation did not land" 1 ""; return; fi
  got="$(r2_shape "$TMP/r2-mut.sh")"
  if [[ "$got" == "$3" ]]; then pass "$1: RED ($got)"; else fail "$1: wanted RED for $3" 1 "got '$got'"; fi
}
# shellcheck disable=SC2016 # sed expressions match literal library text
r2_mut "M-r2-endpoint: the endpoint taken from R2_ENDPOINT" 's|--endpoint-url "\$CFAM_R2_ENDPOINT"|--endpoint-url "${R2_ENDPOINT:-$CFAM_R2_ENDPOINT}"|' endpoint
r2_mut "M-r2-imds: AWS_EC2_METADATA_DISABLED dropped" 's| AWS_EC2_METADATA_DISABLED=true||' env-prefix
r2_mut "M-r2-region: AWS_DEFAULT_REGION dropped" 's|^  timeout 60 env AWS_DEFAULT_REGION=auto |  timeout 60 env |' env-prefix
r2_mut "M-r2-bound: the 60 s bound dropped" 's|^  timeout 60 env |  env |' unbounded

# ── import-normalize (CTO ruling 2026-11-22): the one admitted update shape ──────────────────
# The fixture carries the key set measured with Terraform 1.10.5 and provider 4.52.7. Each record's
# name, type, ttl, proxied and priority come from its dns.tf block; `content` stays synthesized.
# A hand-written {zone_id} stub would not exercise the comparator.
NORM="$TMP/norm.json"; NLIVE="$TMP/norm-live.json"
NR="cloudflare_record.dkim_resend"; NR2="cloudflare_record.spf_send"; MXR="cloudflare_record.mx_send"
DNS_TF="$HERE/../../apps/web-platform/infra/dns.tf"
# record_shapes: JSON {label: {name, type, ttl, proxied, priority}}, one per cloudflare_record block.
record_shapes() {
  awk '
    /^resource "cloudflare_record" "/ { split($0, p, "\""); r = p[4]; n = ""; t = ""; ttl = ""; px = "false"; pr = "null"; next }
    r != "" && /^}/ { printf "%s\t%s\t%s\t%s\t%s\t%s\n", r, n, t, ttl, px, pr; r = ""; next }
    r != "" && $2 == "=" {
      v = $3; gsub(/"/, "", v)
      if ($1 == "name") n = v; else if ($1 == "type") t = v; else if ($1 == "ttl") ttl = v
      else if ($1 == "proxied") px = v; else if ($1 == "priority") pr = v }
  ' "$DNS_TF" | jq -Rn '[inputs | split("\t")
    | {(.[0]): {name:.[1], type:.[2], ttl:(.[3] | tonumber), proxied:(.[4] == "true"), priority:(.[5] | fromjson)}}] | add'
}
jq -c --arg nz "$NZ" --argjson shapes "$(record_shapes)" '.resource_changes |= map(if .type == "cloudflare_record" then
    (.change.importing.id | split("/")[1]) as $id | (.address | split(".")[1]) as $l | $shapes[$l] as $s
    | {id:$id, zone_id:$nz, name:$s.name,
       hostname:(if $s.name == "soleur.ai" then $s.name else $s.name + ".soleur.ai" end),
       type:$s.type, content:null, value:null, ttl:$s.ttl,
       proxied:$s.proxied, proxiable:false, priority:$s.priority, comment:"", tags:[], data:[], metadata:{},
       created_on:"2026-11-19T00:00:00Z", modified_on:"2026-11-19T00:00:00Z", timeouts:null, allow_overwrite:null} as $b
    | .change = {actions:["update"], importing:.change.importing, before:$b,
                 after:($b + {allow_overwrite:false, content:("synthetic-" + $l)}), after_unknown:{}}
  else . end)' "$VALID" > "$NORM"
# The literals are this suite's own count of dns.tf, so a fixture that lost a shape cannot pass quietly.
shape_counts="$(jq -r '[.resource_changes[] | select(.type == "cloudflare_record") | .change.after] as $r
  | [($r | map(select(.name | type == "string" and length > 0)) | length),
     ($r | map(select(.name == "soleur.ai")) | length),
     ($r | map(select(.type == "MX" and (.priority | type) == "number")) | length),
     ($r | map(select(.priority == 20)) | length),
     ($r | map(select(.type == "NS")) | length),
     ($r | map(select(.type == "CNAME" and .proxied == true)) | length),
     ($r | map(select(.name != "soleur.ai" and (.name | contains(".")))) | length),
     ($r | map(select(.ttl == 60)) | length)] | join(" ")' "$NORM")"
if [[ "$shape_counts" == "26 6 6 1 2 2 11 2" ]]; then pass "F5: the fixture holds the dns.tf shapes (26 named, 6 apex, 6 MX with priority, one at 20, 2 NS, 2 proxied CNAME, 11 dotted, 2 at ttl 60)"
else fail "F5: the fixture lost a real record shape" 1 "$shape_counts"; fi
live_of() { # <plan> <out>: a live read that equals each record's planned `after`
  jq -c '[.resource_changes[] | select(.type == "cloudflare_record") | .change.after as $x
    | {(.address): {status:"ok", result:{id:$x.id, zone_id:$x.zone_id, type:$x.type, name:$x.hostname, content:$x.content,
        ttl:$x.ttl, proxied:$x.proxied, priority:$x.priority, comment:null, tags:$x.tags, settings:{}}}}] | add' "$1" > "$2"
}
live_of "$NORM" "$NLIVE"
n_nr="$(jq '[.resource_changes[] | select(.type == "cloudflare_record")] | length' "$NORM")"
if [[ "$n_nr" -eq 26 ]]; then pass "import-normalize fixture holds 26 records"; else fail "import-normalize fixture record count" "$n_nr" "want 26"; fi
# Retry state: every record in state on its pinned id.
jq -c '{values:{root_module:{resources:[.resource_changes[] | select(.type == "cloudflare_record")
  | {address, mode:"managed", type, values:{id:.change.before.id}}]}}}' "$NORM" > "$TMP/norm-state.json"
nf() { printf '(.resource_changes[] | select(.address=="%s") | .change)' "$1"; }

norm_admits() { # <gate-file> [<live>]: empty when the canonical plan passes with 26 import-normalize lines and no in-state-update
  local o rc live="${2:-$NLIVE}"
  o="$(bash -c 'source "$1"; source "$2"; cf_account_migrate_gate redirects-dns "$3" "" "$4"' _ "$PREAMBLE" "$1" "$NORM" "$live" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || { echo "rc=$rc"; return; }
  [[ "$(grep -c '^cf_account_migrate_gate: import-normalize cloudflare_record\.' <<<"$o")" -eq 26 ]] || { echo "lines"; return; }
  ! grep -qF 'in-state-update' <<<"$o" || { echo "in-state-update"; return; }
  grep -qxF 'cf_account_migrate_gate: phase=redirects-dns verdict=PASS creates=8 imports=29 destroys=0' <<<"$o" || echo "verdict"
}
na="$(norm_admits "$GATE")"
if [[ -z "$na" ]]; then pass "N1: 26 measured-shape updates with a matching live read pass, 26 import-normalize lines, no in-state-update"
else fail "N1: the canonical import-normalize plan did not pass" 1 "$na"; fi
# The same shape as a retry (importing null) is bound to the pre-plan state id.
jq -c '.resource_changes |= map(if .type == "cloudflare_record" then .change.importing = null else . end)' "$NORM" > "$TMP/n-retry.json"
check "N2: the retry shape (importing null) passes when before.id and the state id equal the pin" 0 "verdict=PASS creates=8 imports=3 destroys=0" redirects-dns "$TMP/n-retry.json" "$TMP/norm-state.json" "$NLIVE"
# H2: a retry plan mixing written records (no-op) with unwritten ones (update).
jq -c --arg r "$NR" '.resource_changes |= map(if .address == $r then .change.actions = ["no-op"] | .change.before = .change.after else . end)' "$TMP/n-retry.json" > "$TMP/n-mixed.json"
check "N3: a retry mixing no-op and update records passes" 0 "verdict=PASS" redirects-dns "$TMP/n-mixed.json" "$TMP/norm-state.json" "$NLIVE"
for cv in 'del(.comment)' '.comment = null' '.comment = ""'; do
  jq -c --arg r "$NR" "(.[\$r].result) |= ($cv)" "$NLIVE" > "$TMP/n-c.json"
  check "N4: an empty live comment read as [$cv] passes" 0 "verdict=PASS" redirects-dns "$NORM" "" "$TMP/n-c.json"
done

# Off-shape: the live read follows the plan, so only the shape can refuse.
nrow() { # <label> <needle> <plan-filter> [<state>]
  jq -c "$3" "$NORM" > "$TMP/nr.json"; live_of "$TMP/nr.json" "$TMP/nr-live.json"
  check "$1" 1 "$2" redirects-dns "$TMP/nr.json" "${4:-}" "$TMP/nr-live.json"
}
PURE="not a pure no-op import"
for k in 'ttl = 300' 'proxied = true' 'name = "other"'; do
  nrow "S1: an extra changed key ($k) is refused" "$NR is $PURE" "$(nf "$NR").after.$k"
done
nrow "S2: allow_overwrite to true is refused" "$NR is $PURE" "$(nf "$NR").after.allow_overwrite = true"
nrow "S3: a non-null before.allow_overwrite is refused" "$NR is $PURE" "$(nf "$NR").before.allow_overwrite = false"
nrow "S4: a non-null before.content (real drift) is refused" "$NR is $PURE" "$(nf "$NR").before.content = \"old\""
for v in null '""' 7; do
  nrow "S5: after.content of $v is refused" "$NR is $PURE" "$(nf "$NR").after.content = $v"
done
nrow "S6: after_unknown true at top level is refused" "$NR is $PURE" "$(nf "$NR").after_unknown = {content:true}"
nrow "S7: after_unknown true nested is refused" "$NR is $PURE" "$(nf "$NR").after_unknown = {data:{x:true}}"
nrow "S8: a non-record import planned update (Pages) is refused" "cloudflare_pages_project.docs is $PURE" "$(nf cloudflare_pages_project.docs).actions = [\"update\"]"
nrow "S9: a record planned as a replace is refused" "$NR" "$(nf "$NR").actions = [\"delete\",\"create\"]"
nrow "S10: a wrong import literal is refused" "differs from the committed literal" "$(nf "$NR").importing.id = \"$NZ/ffffffffffffffffffffffffffffffff\""
nrow "S11: an import whose before.id is off the pin is refused" "$NR is $PURE" "$(nf "$NR").before.id = \"ffffffffffffffffffffffffffffffff\" | $(nf "$NR").after.id = \"ffffffffffffffffffffffffffffffff\""
RET='.resource_changes |= map(if .type == "cloudflare_record" then .change.importing = null else . end)'
CLS="$NR (class import) planned with actions"
nrow "S12: a retry whose before.id is off the pin is refused" "$CLS" "$RET | $(nf "$NR").before.id = \"ffffffffffffffffffffffffffffffff\" | $(nf "$NR").after.id = \"ffffffffffffffffffffffffffffffff\"" "$TMP/norm-state.json"
jq -c --arg r "$NR" '.values.root_module.resources |= map(select(.address != $r))' "$TMP/norm-state.json" > "$TMP/n-state-less.json"
nrow "S13: a retry absent from the pre-plan state is refused" "$CLS" "$RET" "$TMP/n-state-less.json"
nrow "S14: a retry with no state file is refused" "$CLS" "$RET"
# Row 9's stub fixture stays off-shape whatever the live read says.
live_of "$TMP/r9.json" "$TMP/r9-live.json"
check "S15: row 9's stub update is refused even beside a matching live read" 1 "$PURE" redirects-dns "$TMP/r9.json" "" "$TMP/r9-live.json"

# Pins come from the committed literals, and the zone segment must be the new zone.
pins_out="$(cf_account_migrate_record_pins redirects-dns)"; pins_rc=$?
if [[ "$pins_rc" -eq 0 && "$(grep -cE '^cloudflare_record\.[a-z0-9_]+'$'\t''[0-9a-f]{32}$' <<<"$pins_out")" -eq 26 && "$(grep -c . <<<"$pins_out")" -eq 26 ]]; then
  pass "P1: the pin list is 26 address/record-id lines"
else fail "P1: the pin list is wrong" "$pins_rc" "$pins_out"; fi
if [[ -z "$(cf_account_migrate_record_pins zone-rest)" ]]; then pass "P2: zone-rest has no record pins"; else fail "P2: zone-rest has record pins" 1 ""; fi
# CTO ruling 2026-11-25 (D9 amended for cf_migration_import_app): with no validation, what keeps a
# Doppler CF_MIGRATION_IMPORT_APP key from importing the app record in a routine apply is the
# migration-complete check, which needs cloudflare_record.app as an import-class tunnel member.
if [[ "$(cf_account_migrate_phase_spec tunnel | jq -r '.["cloudflare_record.app"]')" == import ]]; then
  pass "D9a: cloudflare_record.app stays import class in the tunnel spec (the complete check's hold on routine applies)"
else fail "D9a: cloudflare_record.app is no longer import class in the tunnel spec" 1 ""; fi
pins_t="$(cf_account_migrate_record_pins tunnel)"; pins_t_rc=$?
if [[ "$pins_t_rc" -eq 0 && "$pins_t" == "cloudflare_record.app"$'\t'"f21d6911cdacb1e109ae31bcfb440e7d" ]]; then
  pass "P3: the tunnel pin list is the app record's import block alone"
else fail "P3: the tunnel pin list is wrong" "$pins_t_rc" "$pins_t"; fi
# Three levels deep, so the library's ../../.. lookup stays inside $TMP wherever TMPDIR is and the
# forged override below is always honoured.
pin_lib="$TMP/pin-lib/x/y/z"; mkdir -p "$pin_lib"; cp "$GATE" "$PREAMBLE" "$pin_lib/"
first_rid="$(jq -r --arg r "$NR" '.resource_changes[] | select(.address == $r) | .change.before.id' "$NORM")"
second_rid="$(jq -r --arg r "$NR2" '.resource_changes[] | select(.address == $r) | .change.before.id' "$NORM")"
pins_with() { # <imports-file> [<library-copy>]
  CFAM_IMPORTS_FILE="$1" bash -c 'source "$1"; source "$2"; cf_account_migrate_record_pins redirects-dns' _ "$pin_lib/plan-gate-preamble.sh" "${2:-$pin_lib/cf-account-migrate-gate.sh}" 2>&1
}
sed "s|\"$NZ/$first_rid\"|\"$OZ/$first_rid\"|" "$IMPORTS" > "$TMP/forged-zone.tf"
pz="$(pins_with "$TMP/forged-zone.tf")"; pz_rc=$?
if cmp -s "$TMP/forged-zone.tf" "$IMPORTS"; then fail "P3: the forged zone did not land" 1 ""
elif [[ "$pz_rc" -ne 0 && "$pz" != *"ignoring CFAM_IMPORTS_FILE"* ]]; then pass "P3: a literal whose zone segment is not the new zone fails the pin list"
else fail "P3: a foreign-zone literal produced pins, or the override was ignored" "$pz_rc" "$pz"; fi
sed "/\"$NZ\/$first_rid\"/d" "$IMPORTS" > "$TMP/forged-short.tf"
ps="$(pins_with "$TMP/forged-short.tf")"; ps_rc=$?
if cmp -s "$TMP/forged-short.tf" "$IMPORTS"; then fail "P4: the short list did not land" 1 ""
elif [[ "$ps_rc" -ne 0 && "$ps" != *"ignoring CFAM_IMPORTS_FILE"* ]]; then pass "P4: a pin list shorter than the spec's record count fails"
else fail "P4: a short pin list was accepted, or the override was ignored" "$ps_rc" "$ps"; fi
# U4: one record id pinned to two addresses. F11: a pin that is not 32 hex characters.
sed "s|\"$NZ/$second_rid\"|\"$NZ/$first_rid\"|" "$IMPORTS" > "$TMP/forged-dup.tf"
pd="$(pins_with "$TMP/forged-dup.tf")"; pd_rc=$?
if cmp -s "$TMP/forged-dup.tf" "$IMPORTS"; then fail "P5: the duplicate pin did not land" 1 ""
elif [[ "$pd_rc" -ne 0 && "$pd" != *"ignoring CFAM_IMPORTS_FILE"* ]]; then pass "P5 (U4): one record id pinned to two addresses fails the pin list"
else fail "P5 (U4): a duplicate pin was accepted" "$pd_rc" "$pd"; fi
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed '/or (\$pins | map(split("\\t")\[1\]) | unique | length) != (\$pins | length)$/d' "$GATE" > "$pin_lib/m-unique.sh"
pdm="$(pins_with "$TMP/forged-dup.tf" "$pin_lib/m-unique.sh")"; pdm_rc=$?
if cmp -s "$pin_lib/m-unique.sh" "$GATE"; then fail "M-U4: the mutation did not land" 1 ""
elif [[ "$pdm_rc" -eq 0 && "$(grep -c . <<<"$pdm")" -eq 26 ]]; then pass "M-U4: without the uniqueness clause the duplicate pin yields 26 pins (RED for P5)"
else fail "M-U4: removing the uniqueness clause did not admit the duplicate" "$pdm_rc" "$pdm"; fi
sed "s|\"$NZ/$first_rid\"|\"$NZ/${first_rid:0:31}g\"|" "$IMPORTS" > "$TMP/forged-hex.tf"
ph="$(pins_with "$TMP/forged-hex.tf")"; ph_rc=$?
if cmp -s "$TMP/forged-hex.tf" "$IMPORTS"; then fail "P6: the non-hex pin did not land" 1 ""
elif [[ "$ph_rc" -ne 0 && "$ph" != *"ignoring CFAM_IMPORTS_FILE"* ]]; then pass "P6: a pin literal that is not 32 hex characters fails the pin list"
else fail "P6: a non-hex pin was accepted" "$ph_rc" "$ph"; fi
sed 's/test("^\[0-9a-f\]{32}\$")/test("^[0-9a-z]{32}$")/' "$GATE" > "$pin_lib/m-hex.sh"
phm="$(pins_with "$TMP/forged-hex.tf" "$pin_lib/m-hex.sh")"; phm_rc=$?
if cmp -s "$pin_lib/m-hex.sh" "$GATE"; then fail "M-pin-hex: the mutation did not land" 1 ""
elif [[ "$phm_rc" -eq 0 ]]; then pass "M-pin-hex: a looser pin pattern admits the non-hex literal (RED for P6)"
else fail "M-pin-hex: the looser pattern did not admit the literal" "$phm_rc" "$phm"; fi

# Live refusals: the plan is canonical, so only the live read can refuse.
lrow() { # <label> <tokens> <live-filter on the record's entry> [<address>, default the first record]
  local r="${4:-$NR}"
  jq -c --arg r "$r" "(.[\$r]) |= ($3)" "$NLIVE" > "$TMP/lr.json"
  check "$1" 1 "REFUSE $r differs from the live record ($2)" redirects-dns "$NORM" "" "$TMP/lr.json"
}
lrow "L1: live type differs"     "type"     '.result.type = "CNAME"'
lrow "L2: live name differs"     "name"     '.result.name = "other.soleur.ai"'
lrow "L3: live content differs"  "content"  '.result.content = "other"'
lrow "L4: live ttl differs"      "ttl"      '.result.ttl = 300'
lrow "L5: live proxied differs"  "proxied"  '.result.proxied = true'
lrow "L6: live priority differs" "priority" '.result.priority = 10'
lrow "L7: a non-empty live comment differs" "comment" '.result.comment = "note"'
lrow "L8: a false live comment differs" "comment" '.result.comment = false'
lrow "L9: live tags differ" "tags" '.result.tags = ["t"]'
lrow "L10: omitted live tags differ and name the field" "tags,tags:absent" 'del(.result.tags)'
lrow "L11: a non-CNAME record's live settings flatten_cname=false differ" "settings,settings:only-flatten-false" '.result.settings = {flatten_cname:false}'
lrow "L12: other live settings differ" "settings,settings:other" '.result.settings = {ipv4_only:true}'
lrow "L13: a false live settings differs" "settings,settings:other" '.result.settings = false'
lrow "L14: a live content ending in a dot differs" "content" '.result.content += "."'
lrow "L15: a quoted live content differs and says so" "content,content:quoted-equal" '.result.content = ("\"" + .result.content + "\"")'
lrow "L16: a 404 reads notfound" "notfound" '{status:"notfound"}'
UNREAD="REFUSE $NR live record unreadable"
urow() { # <label> <live-filter on the first record's entry>
  jq -c --arg r "$NR" "(.[\$r]) |= ($2)" "$NLIVE" > "$TMP/lr.json"
  check "$1" 1 "$UNREAD" redirects-dns "$NORM" "" "$TMP/lr.json"
}
urow "L17: a failed read reads unreadable" '{status:"unreadable"}'
urow "L18: an entry with no status is unreadable" 'del(.status)'
urow "L19: an entry with an unknown status is unreadable" '.status = "stale"'
urow "L20: an ok entry with a non-object result is unreadable" '.result = "x"'
jq -c --arg r "$NR" 'del(.[$r])' "$NLIVE" > "$TMP/l-missing.json"
check "L21: a record missing from the live read refuses" 1 "$UNREAD" redirects-dns "$NORM" "" "$TMP/l-missing.json"
check "L22: no live read admits nothing" 1 "$NR is $PURE" redirects-dns "$NORM"
# A trailing dot on BOTH sides is still refused (suppressContent hides that change from refresh).
jq -c "$(nf "$NR").after.content = \"dotted.\"" "$NORM" > "$TMP/l-dot.json"; live_of "$TMP/l-dot.json" "$TMP/l-dot-live.json"
check "L23: a trailing dot on both plan and live is refused" 1 "REFUSE $NR differs from the live record (content)" redirects-dns "$TMP/l-dot.json" "" "$TMP/l-dot-live.json"
# after.hostname comes from the same API read, so it must also follow from after.name.
jq -c "$(nf "$NR").before.hostname = \"x.soleur.ai\" | $(nf "$NR").after.hostname = \"x.soleur.ai\"" "$NORM" > "$TMP/l-host.json"; live_of "$TMP/l-host.json" "$TMP/l-host-live.json"
check "L24: after.hostname not derived from after.name is refused" 1 "REFUSE $NR differs from the live record (name)" redirects-dns "$TMP/l-host.json" "" "$TMP/l-host-live.json"
jq -c "$(nf "$NR").before += {name:\"evilsoleur.ai\",hostname:\"evilsoleur.ai\"} | $(nf "$NR").after += {name:\"evilsoleur.ai\",hostname:\"evilsoleur.ai\"}" "$NORM" > "$TMP/l-evil.json"; live_of "$TMP/l-evil.json" "$TMP/l-evil-live.json"
check "L25: a hostname of evilsoleur.ai is not in the zone" 1 "REFUSE $NR differs from the live record (name)" redirects-dns "$TMP/l-evil.json" "" "$TMP/l-evil-live.json"
# A drifted record that plans no-op still blocks the whole phase.
jq -c --arg r "$NR" '(.[$r].result.content) = "drifted"' "$NLIVE" > "$TMP/l-drift.json"
check "L26: a drifted no-op record beside admitted updates refuses" 1 "REFUSE $NR differs from the live record (content)" redirects-dns "$TMP/n-mixed.json" "$TMP/norm-state.json" "$TMP/l-drift.json"
# A compliant first record with an off-shape second.
nrow "L27: a compliant first record with an off-shape second refuses" "$NR2 is $PURE" "$(nf "$NR2").after.ttl = 300"
# A refusal names fields only: no planned or live value reaches the output.
jq -c --arg r "$NR" '(.[$r].result.content) = "SYNTH-LIVE-VALUE"' "$NLIVE" > "$TMP/l-val.json"
lv_out="$(cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/l-val.json" 2>&1)"
if ! grep -qE 'SYNTH-LIVE-VALUE|synthetic-' <<<"$lv_out"; then pass "L28: a live refusal prints no record value"; else fail "L28: a record value reached the output" 1 "$lv_out"; fi

# S2: a fourth argument must be a usable read, on any plan, including an all-no-op one.
ALLNOOP="$TMP/rerun.json"
for bad in "$TMP/no-such-file" ""; do
  check "U-live: an unusable fourth argument [${bad:-empty string}] refuses an all-no-op plan" 1 "the live read is missing or unusable" redirects-dns "$ALLNOOP" "" "$bad"
done
: > "$TMP/l-empty.json"; printf 'null' > "$TMP/l-null.json"; printf '{}' > "$TMP/l-obj.json"
for f in l-empty l-null l-obj; do
  check "U-live: a fourth argument holding $f refuses an all-no-op plan" 1 "the live read is missing or unusable" redirects-dns "$ALLNOOP" "" "$TMP/$f.json"
done
check "U-live: three arguments keep today's behaviour on an all-no-op plan" 0 "verdict=PASS" redirects-dns "$ALLNOOP"

# Collect: only a clean 200 for the pinned id is evidence.
coldir="$TMP/collect"; mkdir -p "$coldir"
while IFS=$'\t' read -r _ rid; do
  printf '{"success":true,"result":{"id":"%s","zone_id":"%s","type":"TXT"}}\n200' "$rid" "$NZ" > "$coldir/$rid"
done <<<"$pins_out"
col_st() { cf_account_migrate_live_collect redirects-dns "$coldir" | jq -r --arg r "$NR" '.[$r].status'; }
if [[ "$(cf_account_migrate_live_collect redirects-dns "$coldir" | jq '[.[] | select(.status == "ok")] | length')" -eq 26 ]]; then pass "C0: 26 clean responses collect as ok"
else fail "C0: clean responses did not collect" 1 ""; fi
crow() { # <label> <want-status> <raw response>
  local keep="$coldir/$first_rid.keep"; cp "$coldir/$first_rid" "$keep"
  printf '%b' "$3" > "$coldir/$first_rid"
  local got; got="$(col_st)"
  mv "$keep" "$coldir/$first_rid"
  if [[ "$got" == "$2" ]]; then pass "$1"; else fail "$1" 1 "got $got want $2"; fi
}
crow "C1: HTTP 200 with success:false is unreadable" unreadable "{\"success\":false,\"result\":{\"id\":\"$first_rid\"}}\n200"
crow "C2: a non-object result is unreadable" unreadable '{"success":true,"result":[]}\n200'
crow "C3: a result id off the pin is unreadable" unreadable '{"success":true,"result":{"id":"ffffffffffffffffffffffffffffffff"}}\n200'
crow "C4: a differing result.zone_id is unreadable" unreadable "{\"success\":true,\"result\":{\"id\":\"$first_rid\",\"zone_id\":\"$OZ\"}}\n200"
crow "C5: an unparseable body is unreadable" unreadable 'not json\n200'
crow "C6: a 404 is notfound" notfound '{"success":false}\n404'
crow "C7: a 429 is unreadable" unreadable '{"success":false}\n429'
crow "C8: a 500 is unreadable" unreadable 'oops\n500'
crow "C9: a response with no zone_id is ok" ok "{\"success\":true,\"result\":{\"id\":\"$first_rid\",\"type\":\"TXT\"}}\n200"
mv "$coldir/$first_rid" "$coldir/$first_rid.gone"
if [[ "$(col_st)" == unreadable ]]; then pass "C10: a record with no response file is unreadable"; else fail "C10: a missing response read as evidence" 1 "$(col_st)"; fi
mv "$coldir/$first_rid.gone" "$coldir/$first_rid"

# live_diff: the one entry point of the job's re-read.
ld_out="$(cf_account_migrate_live_diff redirects-dns "$NORM" "$NLIVE")"; ld_rc=$?
if [[ "$ld_rc" -eq 0 && -z "$ld_out" ]]; then pass "D1: live_diff is empty when all 26 match"; else fail "D1: live_diff on a clean read" "$ld_rc" "$ld_out"; fi
jq -c --arg a "$NR" --arg b "$NR2" '.[$a].result.ttl = 300 | .[$b] = {status:"notfound"}' "$NLIVE" > "$TMP/d2-live.json"
ld_two="$(cf_account_migrate_live_diff redirects-dns "$NORM" "$TMP/d2-live.json")"
if grep -qxF "$NR"$'\t'"ttl" <<<"$ld_two" && grep -qxF "$NR2"$'\t'"notfound" <<<"$ld_two" && [[ "$(grep -c . <<<"$ld_two")" -eq 2 ]]; then
  pass "D2: live_diff reports every differing record, by address and field"
else fail "D2: live_diff did not report both records" 1 "$ld_two"; fi
if cf_account_migrate_live_diff zone-rest "$NORM" "$NLIVE" >/dev/null 2>&1; then fail "D3: an empty pin list read as clean" 0 ""
else pass "D3: live_diff refuses an empty pin list"; fi
if cf_account_migrate_live_diff redirects-dns "$NORM" "$TMP/no-such-file" >/dev/null 2>&1; then fail "D4: a missing live file read as clean" 0 ""
else pass "D4: live_diff refuses a missing live file"; fi

# Guard 1 mutation matrix. Each mutant must let its bad fixture through.
gm() { gate_mutate_and_check "$@"; }
jq -c "$(nf "$NR").after.ttl = 300" "$NORM" > "$TMP/m-ttl.json"; live_of "$TMP/m-ttl.json" "$TMP/m-ttl-l.json"
gm "G1-1: dropping cfam_changed admits a ttl change" '/and cfam_changed == \["allow_overwrite","content"\]/d' cf_account_migrate_gate redirects-dns "$TMP/m-ttl.json" "" "$TMP/m-ttl-l.json"
jq -c "$(nf "$NR").before.content = \"old\"" "$NORM" > "$TMP/m-bc.json"; live_of "$TMP/m-bc.json" "$TMP/m-bc-l.json"
gm "G1-2: dropping the before.content clause admits real drift" '/and \.change\.before\.content == null$/d' cf_account_migrate_gate redirects-dns "$TMP/m-bc.json" "" "$TMP/m-bc-l.json"
jq -c "$(nf "$NR").after.allow_overwrite = true" "$NORM" > "$TMP/m-ao.json"; live_of "$TMP/m-ao.json" "$TMP/m-ao-l.json"
gm "G1-3: dropping the allow_overwrite clause admits true" '/and \.change\.before\.allow_overwrite == null and/d' cf_account_migrate_gate redirects-dns "$TMP/m-ao.json" "" "$TMP/m-ao-l.json"
jq -c "$(nf "$NR").after_unknown = {data:{x:true}}" "$NORM" > "$TMP/m-un.json"; live_of "$TMP/m-un.json" "$TMP/m-un-l.json"
gm "G1-4: a top-level unknown scan admits a nested unknown" 's/\[\.change\.after_unknown|\.\.|booleans|select(\.)\]/[.change.after_unknown[]|booleans|select(.)]/' cf_account_migrate_gate redirects-dns "$TMP/m-un.json" "" "$TMP/m-un-l.json"
jq -c "$(nf "$NR").before.id = \"ffffffffffffffffffffffffffffffff\" | $(nf "$NR").after.id = \"ffffffffffffffffffffffffffffffff\"" "$NORM" > "$TMP/m-pin.json"; cp "$NLIVE" "$TMP/m-pin-l.json"   # the read is of the pinned id
gm "G1-5: dropping the before.id pin admits an off-pin record" 's/== \$pin then empty else "pin" end/== $pin then empty else empty end/' cf_account_migrate_gate redirects-dns "$TMP/m-pin.json" "" "$TMP/m-pin-l.json"
gm "G1-6: dropping the state-id clause admits a retry absent from state" 's/then "state-id" else empty end/then empty else empty end/' cf_account_migrate_gate redirects-dns "$TMP/n-retry.json" "$TMP/n-state-less.json" "$NLIVE"
for fld in type name content ttl proxied priority; do
  case "$fld" in type) lf='.result.type = "CNAME"' ;; name) lf='.result.name = "other.soleur.ai"' ;; content) lf='.result.content = "other"' ;;
    ttl) lf='.result.ttl = 300' ;; proxied) lf='.result.proxied = true' ;; priority) lf='.result.priority = 10' ;; esac
  jq -c --arg r "$NR" "(.[\$r]) |= ($lf)" "$NLIVE" > "$TMP/m-f-$fld.json"
  gm "G1-7: neutering the $fld compare admits a differing $fld" "s/then \"$fld\" else empty end/then empty else empty end/" cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-f-$fld.json"
done
for fld in comment tags settings; do
  case "$fld" in comment) lf='.result.comment = "note"' ;; tags) lf='.result.tags = ["t"]' ;; settings) lf='.result.settings = {ipv4_only:true}' ;; esac
  jq -c --arg r "$NR" "(.[\$r]) |= ($lf)" "$NLIVE" > "$TMP/m-f-$fld.json"
  gm "G1-7: neutering the $fld compare admits a differing $fld" "s/else \"$fld\" end/else empty end/" cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-f-$fld.json"
done
jq -c --arg r "$NR" '.[$r].result.comment = false' "$NLIVE" > "$TMP/m-cf.json"
# shellcheck disable=SC2016 # sed expressions match literal jq text
gm "G1-8a: jq // on comment reads false as empty" 's/((\$r\.comment|cfam_empty) and (\$after\.comment|cfam_empty))/(($r.comment \/\/ "") == ($after.comment \/\/ ""))/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-cf.json"
jq -c --arg r "$NR" '.[$r].result.settings = false' "$NLIVE" > "$TMP/m-sf.json"
# shellcheck disable=SC2016 # sed expressions match literal jq text
gm "G1-8b: jq // on settings reads false as empty" 's/if \$r\.settings == null or \$r\.settings == {} then/if ($r.settings \/\/ {}) == {} then/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-sf.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gm "G1-9: admitting with no live read passes the canonical plan" 's/if (\$hl | not) or any/if any/' cf_account_migrate_gate redirects-dns "$NORM"
jq -c "$(nf "$NR2").after.ttl = 300" "$NORM" > "$TMP/m-second.json"; live_of "$TMP/m-second.json" "$TMP/m-second-l.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gm "G1-10: grading only the first record admits an off-shape second" 's/\[\.\[\] | select(\.action == \["update"\] and \.why == \[\]) | \.address\] end/(.[0].why as $w | [.[] | select(.action == ["update"] and $w == []) | .address]) end/' cf_account_migrate_gate redirects-dns "$TMP/m-second.json" "" "$TMP/m-second-l.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gm "G1-11: comparing only planned updates admits a drifted no-op" 's/live: (if \$hl then/live: (if $hl and .change.actions == ["update"] then/' cf_account_migrate_gate redirects-dns "$TMP/n-mixed.json" "$TMP/norm-state.json" "$TMP/l-drift.json"
sed 's/cf_account_migrate_gate: import-normalize /cf_account_migrate_gate: in-state-update /' "$GATE" > "$TMP/m-isu.sh"
if cmp -s "$TMP/m-isu.sh" "$GATE"; then fail "G1-12: the mutation did not land" 1 ""
elif [[ -n "$(norm_admits "$TMP/m-isu.sh")" ]]; then pass "G1-12: printing in-state-update for an admitted record is caught by N1"
else fail "G1-12: N1 did not see the wrong log line" 1 ""; fi
# shellcheck disable=SC2016 # sed expression matches literal jq text
gm "G1-15: dropping the hostname-name binding admits L24" '/or \$after\.hostname != (\$after\.name|cfam_fqdn)$/d' cf_account_migrate_gate redirects-dns "$TMP/l-host.json" "" "$TMP/l-host-live.json"
gm "G1-16: an undotted suffix admits evilsoleur.ai" 's/endswith("\.soleur\.ai")/endswith("soleur.ai")/' cf_account_migrate_gate redirects-dns "$TMP/l-evil.json" "" "$TMP/l-evil-live.json"
# shellcheck disable=SC2016 # sed expression matches literal jq text
gm "G1-17: dropping the trailing-dot refusal admits L23" '/or ((\$r\.content|type) == "string" and (\$r\.content|endswith(".")))$/d' cf_account_migrate_gate redirects-dns "$TMP/l-dot.json" "" "$TMP/l-dot-live.json"
jq -c --arg r "$NR" '(.[$r].result.content) |= ("\"" + . + "\"")' "$NLIVE" > "$TMP/m-q.json"
# shellcheck disable=SC2016 # sed expression matches literal jq text
gm "G1-18: letting a diagnostic decide admits a quoted content" 's/if \$r\.content != \$after\.content$/if ($r.content|cfam_unquote) != ($after.content|cfam_unquote)/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-q.json"
gm "G1-19: treating an unusable read as not supplied passes an all-no-op plan" \
  's/{ echo "cf_account_migrate_gate: REFUSE — the live read is missing or unusable"; return 1; }/{ has_live=false; live_json=""; }/' \
  cf_account_migrate_gate redirects-dns "$ALLNOOP" "" "$TMP/no-such-file"
jq -c --arg r "$NR" 'del(.[$r].status)' "$NLIVE" > "$TMP/m-st.json"
# shellcheck disable=SC2016 # sed expression matches literal jq text
gm "G1-20: comparing an entry with no status admits it" 's/elif \$entry\.status != "ok" or (\$entry\.result|type) != "object"/elif ($entry.result|type) != "object"/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-st.json"
# H1: a hand-written {zone_id} after cannot satisfy the admit path.
jq -c '.resource_changes |= map(if .type == "cloudflare_record" then .change.actions = ["update"] else . end)' "$VALID" > "$TMP/h1-stub.json"
live_of "$TMP/h1-stub.json" "$TMP/h1-stub-l.json"
check "G1-H1: an update built from the {zone_id} stub is refused" 1 "$PURE" redirects-dns "$TMP/h1-stub.json" "" "$TMP/h1-stub-l.json"

# gate_in <gate-file> <gate args...>: run a copy of the gate.
gate_in() { bash -c 'source "$1"; source "$2"; shift 2; cf_account_migrate_gate "$@"' _ "$PREAMBLE" "$@" 2>&1; }
# gm_lost <label> <sed> <needle> <gate args...>: the pristine gate prints <needle>, the mutant does not.
gm_lost() {
  local label="$1" ex="$2" needle="$3" base out; shift 3
  sed "$ex" "$GATE" > "$TMP/m-lost.sh"
  if cmp -s "$TMP/m-lost.sh" "$GATE"; then fail "$label: the mutation did not land" 1 ""; return; fi
  base="$(cf_account_migrate_gate "$@" 2>&1)"; out="$(gate_in "$TMP/m-lost.sh" "$@")"
  if [[ "$base" == *"$needle"* && "$out" != *"$needle"* ]]; then pass "$label (RED)"
  else fail "$label: wanted [$needle] in the pristine output only" 1 "$out"; fi
}
# gm_refuses <label> <sed> <gate args...>: the pristine gate passes this plan, the mutant refuses it.
gm_refuses() {
  local label="$1" ex="$2" base_rc=0 rc=0 out; shift 2
  sed "$ex" "$GATE" > "$TMP/m-refuses.sh"
  if cmp -s "$TMP/m-refuses.sh" "$GATE"; then fail "$label: the mutation did not land" 1 ""; return; fi
  cf_account_migrate_gate "$@" >/dev/null 2>&1 || base_rc=$?
  out="$(gate_in "$TMP/m-refuses.sh" "$@")" || rc=$?
  if [[ "$base_rc" -eq 0 && "$rc" -eq 1 ]]; then pass "$label (RED)"; else fail "$label" "$base_rc/$rc" "$out"; fi
}
# only_line <label> <line> <gate args...>: a REFUSE whose only REFUSE line is <line>, with nothing admitted.
only_line() {
  local label="$1" want="$2" out rc=0; shift 2
  out="$(cf_account_migrate_gate "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 && "$(grep -c '^REFUSE ' <<<"$out")" -eq 1 ]] && grep -qxF -- "$want" <<<"$out" \
     && ! grep -qE '^cf_account_migrate_gate: import-normalize cloudflare_record' <<<"$out"; then pass "$label"
  else fail "$label" "$rc" "$out"; fi
}

# R2: a read that is not clean names its own record only, and still admits nothing.
jq -c --arg r "$NR" '.[$r] = {status:"unreadable"}' "$NLIVE" > "$TMP/r2-one.json"
only_line "R2-1: one unreadable record prints one line, naming it" "$UNREAD" redirects-dns "$NORM" "" "$TMP/r2-one.json"
only_line "R2-2: the same on the retry shape" "$UNREAD" redirects-dns "$TMP/n-retry.json" "$TMP/norm-state.json" "$TMP/r2-one.json"
jq -c --arg r "$NR" '.[$r].result.ttl = 300' "$NLIVE" > "$TMP/r2-diff.json"
only_line "R2-3: one differing record prints one line, naming it" "REFUSE $NR differs from the live record (ttl)" redirects-dns "$NORM" "" "$TMP/r2-diff.json"
jq -c 'map_values({status:"unreadable"})' "$NLIVE" > "$TMP/r2-all.json"
r2_all="$(cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/r2-all.json" 2>&1)"; r2_all_rc=$?
if [[ "$r2_all_rc" -eq 1 && "$(grep -cE '^REFUSE cloudflare_record\.[a-z0-9_]+ live record unreadable$' <<<"$r2_all")" -eq 26 && "$(grep -c '^REFUSE ' <<<"$r2_all")" -eq 26 ]]; then
  pass "R2-4: an outage prints 26 unreadable lines and no difference"
else fail "R2-4: an all-unreadable read" "$r2_all_rc" "$r2_all"; fi
if ! grep -qF 'differs from the live record (unreadable)' <<<"$r2_all"; then pass "R2-5: the old differs-unreadable sentence is gone"
else fail "R2-5: an unreadable read still prints as a difference" 1 "$r2_all"; fi
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm_lost "M-R2-label: printing an unreadable read as a difference loses R2-1's line" \
    's/if \.live == \["unreadable"\] then "REFUSE \\(\.address) live record unreadable" else //; s/(\\(\.live | join(",")))" end/(\\(.live | join(",")))"/' \
    "$UNREAD" redirects-dns "$NORM" "" "$TMP/r2-one.json"
  sed 's/^  if \[\[ -n "\$live_v" \]\]; then$/  if false; then/' "$GATE" > "$TMP/m-r2-held.sh"
  r2_held="$(gate_in "$TMP/m-r2-held.sh" redirects-dns "$NORM" "" "$TMP/r2-one.json")"
  if cmp -s "$TMP/m-r2-held.sh" "$GATE"; then fail "M-R2-held: the mutation did not land" 1 ""
  elif [[ "$(grep -c '^REFUSE ' <<<"$r2_held")" -gt 1 ]]; then pass "M-R2-held: without the hold the other records are named again (RED for R2-1)"
  else fail "M-R2-held: the hold is not what limits the output" 1 "$r2_held"; fi
  # With its line gone the read still refuses, because the hold is built from that line.
  gate_mutate_layered "M-R2-line: the live line owns the refusal; neutered, the import arms still refuse" \
    's/live_v="\$(jq -r/live_v="$(: jq -r/' "$UNREAD" "$PURE" cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/r2-one.json"
  # The `any` clause is what keeps `norm` empty: drop it as well as the line and the plan passes.
  gm "M-R2-norm: admitting beside an unclean read passes once the live line is gone" \
    's/live_v="\$(jq -r/live_v="$(: jq -r/; s/if (\$hl | not) or any(\.\[\]; \.live != \[\]) then \[\]/if ($hl | not) then []/' \
    cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/r2-one.json"
}

# Q5, U1 and U2: each spec address appears once, as managed.
ONCE="must appear exactly once as a managed resource in the plan"
jq -c --arg r "$NR" '.resource_changes += [.resource_changes[] | select(.address == $r) | .change.after.allow_overwrite = true]' "$NORM" > "$TMP/q-twin.json"
check "Q5-U2: a compliant update with an off-shape twin at its address is refused" 1 "REFUSE $NR $ONCE" redirects-dns "$TMP/q-twin.json" "" "$NLIVE"
jq -c --arg r "$NR" '(.resource_changes[] | select(.address == $r) | .mode) = "data"' "$VALID" > "$TMP/q-data.json"
check "Q5-U1: a spec address planned in another mode is refused" 1 "REFUSE $NR $ONCE" redirects-dns "$TMP/q-data.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm "M-U2: dropping the count clause admits the twin" 's/select(length != 1 or ((/select(false or ((/' cf_account_migrate_gate redirects-dns "$TMP/q-twin.json" "" "$NLIVE"
  gm "M-U1: dropping the mode clause admits the other mode" 's/select(length != 1 or ((\.\[0\]\.mode \/\/ "managed") != "managed"))/select(length != 1)/' cf_account_migrate_gate redirects-dns "$TMP/q-data.json"
}

# Q5, U3: a record of another spec class cannot change. The copy reclasses one record as mutable, so
# only this check stands between it and an arbitrary update.
Q_REC="cloudflare_record.www"
sed "s/\"$Q_REC\": \"import\"/\"$Q_REC\": \"mutable\"/" "$GATE" > "$TMP/q-u3-gate.sh"
jq -c --arg r "$Q_REC" --arg z "$NZ" '(.resource_changes[] | select(.address == $r) | .change) = {actions:["update"], before:{zone_id:$z,id:"r"}, after:{zone_id:$z,id:"r",content:"changed"}, after_unknown:{}}' "$VALID" > "$TMP/q-u3.json"
q3_out="$(gate_in "$TMP/q-u3-gate.sh" redirects-dns "$TMP/q-u3.json")"; q3_rc=$?
if cmp -s "$TMP/q-u3-gate.sh" "$GATE"; then fail "Q5-U3: the reclass did not land" 1 ""
elif [[ "$q3_rc" -eq 1 ]] && grep -qxF -- "REFUSE $Q_REC is a cloudflare_record change outside import-normalize" <<<"$q3_out"; then pass "Q5-U3: a mutable-class record planned as an update is refused"
else fail "Q5-U3: a non-import record change was not refused" "$q3_rc" "$q3_out"; fi
GATE="$TMP/q-u3-gate.sh" gate_mutate_and_check "M-U3: dropping the record-change check admits it" \
  's/| select(\.type == "cloudflare_record" and \.change\.actions != \["no-op"\])/| select(false)/' cf_account_migrate_gate redirects-dns "$TMP/q-u3.json"

# Q5, U5: a pinned no-op carries the pin on both sides.
Q_OTHER="ffffffffffffffffffffffffffffffff"; NOOP_PIN="REFUSE $NR is a no-op on a record id other than its pin"
noop_side_rows() { # <base plan> <file tag> <label> <state>
  local side qf
  for side in both before after; do
    case "$side" in
      both) qf=".before.id = \"$Q_OTHER\" | .after.id = \"$Q_OTHER\"" ;;
      *) qf=".$side.id = \"$Q_OTHER\"" ;;
    esac
    jq -c "$(nf "$NR") |= ($qf)" "$1" > "$TMP/q-noop-$2$side.json"
    check "Q5-U5: $3 no-op whose $side id is off the pin is refused" 1 "$NOOP_PIN" redirects-dns "$TMP/q-noop-$2$side.json" "$4" "$NLIVE"
  done
}
noop_side_rows "$TMP/n-mixed.json" "" "a" "$TMP/norm-state.json"
# The first dispatch's shape: `importing` set, before equal to after, no state entry.
jq -c "$(nf "$NR") |= (.actions = [\"no-op\"] | .before = .after)" "$NORM" > "$TMP/q-noop-i.json"
check "Q5-U5i: an import-shaped no-op on its pin passes" 0 "verdict=PASS" redirects-dns "$TMP/q-noop-i.json" "" "$NLIVE"
noop_side_rows "$TMP/q-noop-i.json" "i-" "an import-shaped" ""
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm "M-U5: dropping the no-op binding admits it" 's/noop_id_ok: (\.change\.actions != \["no-op"\]/noop_id_ok: (true/' cf_account_migrate_gate redirects-dns "$TMP/q-noop-both.json" "$TMP/norm-state.json" "$NLIVE"
  gm "M-U5-import: exempting a planned import admits an off-pin no-op" 's/noop_id_ok: (\.change\.actions != \["no-op"\]/noop_id_ok: (.change.actions != ["no-op"] or .change.importing != null/' cf_account_migrate_gate redirects-dns "$TMP/q-noop-i-both.json" "" "$NLIVE"
  gm "M-U5-before: dropping the before clause admits an off-pin before" 's/or ((\.change\.before|type) == "object" and \.change\.before\.id == \$pin/or (true/' cf_account_migrate_gate redirects-dns "$TMP/q-noop-before.json" "$TMP/norm-state.json" "$NLIVE"
  gm "M-U5-after: dropping the after clause admits an off-pin after" 's/and (\.change\.after|type) == "object" and \.change\.after\.id == \$pin))/))/' cf_account_migrate_gate redirects-dns "$TMP/q-noop-after.json" "$TMP/norm-state.json" "$NLIVE"
}

# Q5, U6: a non-empty live `data` refuses.
lrow "Q5-U6: a non-empty live data differs" "data" '.result.data = {flags:1}'
jq -c --arg r "$NR" '.[$r].result.data = {flags:1}' "$NLIVE" > "$TMP/q-data-live.json"
gm "M-U6: dropping the data clause admits it" 's/else "data" end/else empty end/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/q-data-live.json"

# Q5, U7: the comparator binds the read to the pinned id and the new zone, at both call sites.
jq -c --arg r "$NR" --arg o "$Q_OTHER" '.[$r].result.id = $o' "$NLIVE" > "$TMP/q-id.json"
jq -c --arg r "$NR" --arg z "$OZ" '.[$r].result.zone_id = $z' "$NLIVE" > "$TMP/q-zone.json"
jq -c --arg r "$NR" 'del(.[$r].result.zone_id)' "$NLIVE" > "$TMP/q-nozone.json"
only_line "Q5-U7a: a read of another record id is unreadable" "$UNREAD" redirects-dns "$NORM" "" "$TMP/q-id.json"
only_line "Q5-U7b: a read from another zone is unreadable" "$UNREAD" redirects-dns "$NORM" "" "$TMP/q-zone.json"
jq -c --arg r "$NR" 'del(.[$r].result.id)' "$NLIVE" > "$TMP/q-noid.json"
only_line "Q5-U7e: a read with no id is unreadable (unlike zone_id, it may not be absent)" "$UNREAD" redirects-dns "$NORM" "" "$TMP/q-noid.json"
check "Q5-U7c: a read with no zone_id still passes" 0 "verdict=PASS" redirects-dns "$NORM" "" "$TMP/q-nozone.json"
for qf in id zone; do
  ld_q="$(cf_account_migrate_live_diff redirects-dns "$NORM" "$TMP/q-$qf.json")"
  if [[ "$ld_q" == "$NR"$'\t'"unreadable" ]]; then pass "Q5-U7d: live_diff binds the read's $qf too"
  else fail "Q5-U7d: live_diff did not bind the read's $qf" 1 "$ld_q"; fi
done
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm "M-U7-id: dropping the id clause admits another record's read" '/^    or \$entry\.result\.id != \$pin$/d' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/q-id.json"
  gm "M-U7-noid: filling a missing id with the pin admits the read" 's/^    or \$entry\.result\.id != \$pin$/    or ($entry.result.id \/\/ $pin) != $pin/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/q-noid.json"
  gm "M-U7-zone: dropping the zone clause admits another zone's read" 's/or (\$entry\.result\.zone_id != null and \$entry\.result\.zone_id != \$zone) then/then/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/q-zone.json"
  gm_refuses "M-U7-nozone: requiring a zone_id refuses a read that omits it" 's/(\$entry\.result\.zone_id != null and \$entry\.result\.zone_id != \$zone)/($entry.result.zone_id != $zone)/' redirects-dns "$NORM" "" "$TMP/q-nozone.json"
}

# F1: a record planned as a create, with a matching live read, must not reach `norm`.
jq -c "$(nf "$NR") |= (.actions = [\"create\"] | .importing = null | .before = null)" "$NORM" > "$TMP/f1.json"
live_of "$TMP/f1.json" "$TMP/f1-live.json"
check "F1: a record create beside a matching live read is refused" 1 "$NR (class import) planned with actions [\"create\"]" redirects-dns "$TMP/f1.json" "" "$TMP/f1-live.json"
gm "M-F1: admitting any non-no-op admits the create" 's/select(\.action == \["update"\] and \.why == \[\]) | \.address\] end/select(.action != ["no-op"] and .why == []) | .address] end/' cf_account_migrate_gate redirects-dns "$TMP/f1.json" "" "$TMP/f1-live.json"
# R2: beside another record's unreadable read, only a clean-shaped update goes unnamed.
jq -c --arg r "$NR2" '.[$r] = {status:"unreadable"}' "$NLIVE" > "$TMP/r2-two.json"
R2_CREATE="$NR (class import) planned with actions [\"create\"]"
check "R2-6: a record create beside another record's unreadable read is still named" 1 "$R2_CREATE" redirects-dns "$TMP/f1.json" "" "$TMP/r2-two.json"
check "R2-7: an off-shape update beside another record's unreadable read is still named" 1 "$NR is $PURE" redirects-dns "$TMP/m-ttl.json" "" "$TMP/r2-two.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm_lost "M-R2-action: holding back any non-no-op hides the create" \
    's/exempt="\$(jq -c .\[\.\[\] | select(\.action == \["update"\] and/exempt="$(jq -c \x27[.[] | select(.action != ["no-op"] and/' \
    "$R2_CREATE" redirects-dns "$TMP/f1.json" "" "$TMP/r2-two.json"
  gm_lost "M-R2-why: holding back an off-shape update hides it" \
    's/exempt="\$(jq -c .\[\.\[\] | select(\.action == \["update"\] and \.why == \[\])/exempt="$(jq -c \x27[.[] | select(.action == ["update"])/' \
    "$NR is $PURE" redirects-dns "$TMP/m-ttl.json" "" "$TMP/r2-two.json"
}

# F2: a 200 that omits a compared field is a difference. Priority uses an MX, whose plan sets one.
for fld in type name content ttl proxied priority; do
  rec="$NR"; [[ "$fld" != priority ]] || rec="$MXR"
  jq -c --arg r "$rec" --arg f "$fld" 'del(.[$r].result[$f])' "$NLIVE" > "$TMP/f2-$fld.json"
  check "F2: a live read omitting $fld refuses" 1 "REFUSE $rec differs from the live record ($fld)" redirects-dns "$NORM" "" "$TMP/f2-$fld.json"
  # shellcheck disable=SC2016 # a sed expression over literal gate text
  if [[ "$fld" == name ]]; then ex='s/or \$r\.name != \$after\.hostname$/or ($r.name != null and $r.name != $after.hostname)/'
  else ex="s/if \\\$r\\.$fld != \\\$after\\.$fld/if \$r.$fld != null and \$r.$fld != \$after.$fld/"; fi
  gm "M-F2-$fld: treating an omitted $fld as equal admits it" "$ex" cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/f2-$fld.json"
done

# F3: the same two fields with the value on the plan side.
jq -c "$(nf "$NR") |= (.before.comment = \"note\" | .after.comment = \"note\")" "$NORM" > "$TMP/f3-c.json"
jq -c "$(nf "$NR") |= (.before.tags = [\"t\"] | .after.tags = [\"t\"])" "$NORM" > "$TMP/f3-t.json"
check "F3: a planned comment with an empty live comment refuses" 1 "REFUSE $NR differs from the live record (comment)" redirects-dns "$TMP/f3-c.json" "" "$NLIVE"
check "F3: planned tags with empty live tags refuse" 1 "REFUSE $NR differs from the live record (tags)" redirects-dns "$TMP/f3-t.json" "" "$NLIVE"
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm "M-F3-comment: a one-way comment compare admits it" 's/((\$r\.comment|cfam_empty) and (\$after\.comment|cfam_empty))/($r.comment|cfam_empty)/' cf_account_migrate_gate redirects-dns "$TMP/f3-c.json" "" "$NLIVE"
  gm "M-F3-tags: a one-way tags compare admits it" 's/(\$r\.tags|unique) == (\$after\.tags|unique)/(($r.tags - $after.tags)|length) == 0/' cf_account_migrate_gate redirects-dns "$TMP/f3-t.json" "" "$NLIVE"
}

# F4: a retry whose pre-plan state holds another id for the address.
jq -c --arg r "$NR" --arg o "$Q_OTHER" '(.values.root_module.resources[] | select(.address == $r) | .values.id) = $o' "$TMP/norm-state.json" > "$TMP/n-state-other.json"
nrow "F4: a retry whose state holds another id is refused" "$CLS" "$RET" "$TMP/n-state-other.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gm "M-F4: checking presence instead of the id admits it" 's/\$sids\[\$ad\] != \$pin/$sids[$ad] == null/' cf_account_migrate_gate redirects-dns "$TMP/n-retry.json" "$TMP/n-state-other.json" "$NLIVE"

# F5: the apex name is admitted as itself. Dropping that arm refuses the six apex records.
# shellcheck disable=SC2016 # sed expression matches literal gate text
sed 's/def cfam_fqdn: if \. == "soleur\.ai" or endswith/def cfam_fqdn: if endswith/' "$GATE" > "$TMP/m-apex.sh"
if cmp -s "$TMP/m-apex.sh" "$GATE"; then fail "M-F5-apex: the mutation did not land" 1 ""
elif [[ -n "$(norm_admits "$TMP/m-apex.sh")" ]]; then pass "M-F5-apex: dropping the apex arm of cfam_fqdn refuses the real apex records (RED for N1)"
else fail "M-F5-apex: N1 did not see the apex arm go" 1 ""; fi

# F10: the not-admitted line names the reason.
naw="import-normalize not admitted for $NR"
nrow "F10-shape: the reason is shape" "$naw (shape)" "$(nf "$NR").before.content = \"old\""
nrow "F10-pin: the reason is pin" "$naw (pin)" "$(nf "$NR").before.id = \"$Q_OTHER\" | $(nf "$NR").after.id = \"$Q_OTHER\""
nrow "F10-state: the reason is state-id" "$naw (state-id)" "$RET" "$TMP/n-state-less.json"
jq -c "$(nf "$NR").before.content = \"old\"" "$NORM" > "$TMP/f10-s.json"; live_of "$TMP/f10-s.json" "$TMP/f10-s-l.json"
jq -c "$(nf "$NR").before.id = \"$Q_OTHER\" | $(nf "$NR").after.id = \"$Q_OTHER\"" "$NORM" > "$TMP/f10-p.json"
# shellcheck disable=SC2016 # sed expressions match literal gate text
{
  gm_lost "M-F10-print: never printing the line loses the reason" 's/^    \[\[ -z "\$norm_why" \]\] || printf .*$/    :/' "$naw (shape)" redirects-dns "$TMP/f10-s.json" "" "$TMP/f10-s-l.json"
  gm_lost "M-F10-shape: another label for shape loses it" 's/if cfam_norm_shape then empty else "shape" end/if cfam_norm_shape then empty else "pin" end/' "$naw (shape)" redirects-dns "$TMP/f10-s.json" "" "$TMP/f10-s-l.json"
  gm_lost "M-F10-pin: another label for pin loses it" 's/then empty else "pin" end/then empty else "shape" end/' "$naw (pin)" redirects-dns "$TMP/f10-p.json" "" "$NLIVE"
  gm_lost "M-F10-state: another label for state-id loses it" 's/then "state-id" else empty end/then "shape" else empty end/' "$naw (state-id)" redirects-dns "$TMP/n-retry.json" "$TMP/n-state-less.json" "$NLIVE"
}

# F11: the smaller survivors.
nrow "F11: an absent after_unknown is refused" "$NR is $PURE" "$(nf "$NR") |= del(.after_unknown)"
jq -c "$(nf "$NR") |= del(.after_unknown)" "$NORM" > "$TMP/f11-u.json"; live_of "$TMP/f11-u.json" "$TMP/f11-u-l.json"
gm "M-F11-unknown: dropping the type clause admits it" '/and (\.change\.after_unknown|type) == "object"$/d' cf_account_migrate_gate redirects-dns "$TMP/f11-u.json" "" "$TMP/f11-u-l.json"
nrow "F11: a key present only in before is refused" "$NR is $PURE" "$(nf "$NR") |= del(.after.proxiable)"
jq -c "$(nf "$NR") |= del(.after.proxiable)" "$NORM" > "$TMP/f11-k.json"; live_of "$TMP/f11-k.json" "$TMP/f11-k-l.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gm "M-F11-before: reading after-keys only admits it" 's/((\$c\.before|keys)+(\$c\.after|keys)|unique)/($c.after|keys)/' cf_account_migrate_gate redirects-dns "$TMP/f11-k.json" "" "$TMP/f11-k-l.json"
jq -c "$(nf "$NR") |= (.before.tags = [\"a\",\"b\"] | .after.tags = [\"a\",\"b\"])" "$NORM" > "$TMP/f11-t.json"
jq -c --arg r "$NR" '.[$r].result.tags = ["b","a"]' "$NLIVE" > "$TMP/f11-t-l.json"
check "F11: tags reordered by the API still pass" 0 "verdict=PASS" redirects-dns "$TMP/f11-t.json" "" "$TMP/f11-t-l.json"
# shellcheck disable=SC2016 # sed expression matches literal gate text
gm_refuses "M-F11-tags: an order-sensitive compare refuses the reorder" 's/(\$r\.tags|unique) == (\$after\.tags|unique)/$r.tags == $after.tags/' redirects-dns "$TMP/f11-t.json" "" "$TMP/f11-t-l.json"

# ── CNAME flatten_cname default (CTO ruling 2026-11-25, #13056) ─────────────────────────────
# The fixture's CNAMEs are exactly the six the redirects-dns rehearsal refused.
CNAMES="cloudflare_record.pages_apex cloudflare_record.protonmail_dkim_1 cloudflare_record.protonmail_dkim_2 cloudflare_record.protonmail_dkim_3 cloudflare_record.supabase_custom_domain cloudflare_record.www"
CN="cloudflare_record.www"
got_cn="$(jq -r '[.resource_changes[] | select(.type == "cloudflare_record" and .change.after.type == "CNAME") | .address] | sort | join(" ")' "$NORM")"
if [[ "$got_cn" == "$CNAMES" ]]; then pass "L11-fixture: the fixture's CNAME set is exactly the six rehearsal-refused records"
else fail "L11-fixture: the fixture's CNAME set drifted" 1 "$got_cn"; fi
# flat_live <out> <address...>: $NLIVE with each named record's live settings at {flatten_cname:false}.
flat_live() {
  local out="$1"; shift
  assert_fixture_dir "$out"
  jq -c --arg c "$*" '($c | split(" ")) as $cs | with_entries(if (.key | IN($cs[])) then .value.result.settings = {flatten_cname:false} else . end)' "$NLIVE" > "$out"
}
FLAT_ALL="$TMP/flat-all.json"; FLAT_MIX="$TMP/flat-mix.json"
# shellcheck disable=SC2086 # CNAMES is a word list
flat_live "$FLAT_ALL" $CNAMES
# Either outcome of the PATCH: three still at the default, three reset to {}.
flat_live "$FLAT_MIX" cloudflare_record.pages_apex cloudflare_record.protonmail_dkim_1 cloudflare_record.protonmail_dkim_2
n_set() { jq --argjson s "$2" '[.[] | select(.result.settings == $s)] | length' "$1"; }   # <live> <settings>: records holding exactly <settings>
# The fixtures are checked on their own, so a drifted fixture never reads as a gate refusal.
fx="$(n_set "$FLAT_ALL" '{"flatten_cname":false}')/$(n_set "$FLAT_MIX" '{"flatten_cname":false}')/$(n_set "$FLAT_MIX" '{}')"
if [[ "$fx" == "6/3/23" ]]; then pass "L11-fixture-flat: six CNAMEs at the default; the mixed read holds three at the default and the rest at {}"
else fail "L11-fixture-flat: the flatten fixtures drifted (want default/mixed-default/mixed-{} = 6/3/23)" 1 "$fx"; fi
na="$(norm_admits "$GATE" "$FLAT_ALL")"
if [[ -z "$na" ]]; then pass "L11b: all six CNAMEs at {flatten_cname:false} pass (the rehearsal's read)"
else fail "L11b: the gate refused the rehearsal's six-CNAME read" 1 "$na"; fi
lrow "L11c: a CNAME's flatten_cname=true differs" "settings,settings:other" '.result.settings = {flatten_cname:true}' "$CN"
lrow "L11d: a CNAME's flatten_cname=false with ipv4_only differs" "settings,settings:other" '.result.settings = {flatten_cname:false, ipv4_only:true}' "$CN"
lrow "L11d: a CNAME's flatten_cname=false with ipv6_only differs" "settings,settings:other" '.result.settings = {flatten_cname:false, ipv6_only:true}' "$CN"
lrow "L11d: a CNAME's flatten_cname=false with an unknown key differs" "settings,settings:other" '.result.settings = {flatten_cname:false, future_key:false}' "$CN"
lrow "L11e: a CNAME's flatten_cname string \"false\" differs" "settings,settings:other" '.result.settings = {flatten_cname:"false"}' "$CN"
lrow "L11f: a CNAME's flatten_cname null differs" "settings,settings:other" '.result.settings = {flatten_cname:null}' "$CN"
L11G_FILTER='.result.type = "CNAME" | .result.settings = {flatten_cname:false}'
lrow "L11g: a live CNAME with flatten_cname=false against a planned TXT differs on type and settings" "type,settings,settings:only-flatten-false" "$L11G_FILTER"
jq -c --arg r "$NR" "(.[\$r]) |= ($L11G_FILTER)" "$NLIVE" > "$TMP/l11g.json"
d6="$(cf_account_migrate_live_diff redirects-dns "$NORM" "$FLAT_MIX")"; d6_rc=$?
if [[ "$d6_rc" -eq 0 && -z "$d6" ]]; then pass "D6: a re-read with three CNAMEs at {flatten_cname:false} and the rest at {} (the PATCH reset) is clean"
else fail "D6: the re-read refused a mixed default read" "$d6_rc" "$d6"; fi
# A plan that carries `settings` (a later provider) is refused, never assumed equal to the live default.
jq -c "$(nf "$CN").after.settings = {flatten_cname:true}" "$NORM" > "$TMP/plan-settings.json"
D7_WANT="$(printf '%s\tsettings,settings:only-flatten-false' "$CN")"
d7="$(cf_account_migrate_live_diff redirects-dns "$TMP/plan-settings.json" "$FLAT_ALL")"
if [[ "$d7" == "$D7_WANT" ]]; then pass "D7: a planned settings block against a live default differs on settings"
else fail "D7: a planned settings block compared equal to the live default" 1 "$d7"; fi
# shellcheck disable=SC2016 # sed expression matches literal jq text
sed 's/elif \$after\.settings == null and \$r\.settings == /elif $r.settings == /' "$GATE" > "$TMP/m-flat-plan.sh"
mfp="$(bash -c 'source "$1"; source "$2"; cf_account_migrate_live_diff redirects-dns "$3" "$4"' _ "$PREAMBLE" "$TMP/m-flat-plan.sh" "$TMP/plan-settings.json" "$FLAT_ALL" 2>&1)"
if cmp -s "$TMP/m-flat-plan.sh" "$GATE"; then fail "M-flatten-plan: the mutation did not land" 1 ""
elif [[ -z "$mfp" ]]; then pass "M-flatten-plan: dropping the planned-settings clause admits D7's plan (RED)"
else fail "M-flatten-plan: the mutant still refused D7's plan" 1 "$mfp"; fi
jq -c --arg r "$NR" '.[$r].result.settings = {flatten_cname:false}' "$NLIVE" > "$TMP/m-flat-txt.json"
# The pristine gate must refuse this fixture (L11's case), or the mutant passing it proves nothing.
cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-flat-txt.json" >/dev/null 2>&1 && fail "M-flatten-guard: the pristine gate admits its own fixture" 0 ""
# shellcheck disable=SC2016 # sed expression matches literal jq text
gm "M-flatten-guard: dropping the CNAME type guard admits a TXT record's flatten_cname=false (L11)" \
  's/ and \$r\.type == "CNAME" and \$after\.type == "CNAME" then empty$/ then empty/' cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/m-flat-txt.json"
# Wording check, not a verdict check: the separate `type` compare refuses any type mismatch, so
# neither CNAME conjunct alone changes a verdict. What dropping the planned-type conjunct changes
# is the stop token: L11g loses `settings:only-flatten-false` and is refused on `type` alone.
# shellcheck disable=SC2016 # sed expression matches literal jq text
gate_mutate_layered "M-flatten-after: dropping the planned-type clause leaves L11g refused on type alone (wording)" \
  's/ and \$after\.type == "CNAME" then empty$/ then empty/' "(type,settings,settings:only-flatten-false)" \
  "REFUSE $NR differs from the live record (type)" cf_account_migrate_gate redirects-dns "$NORM" "" "$TMP/l11g.json"

# Anti-vacuity floor, reported outside pass()/fail() (ADR-193).
TOTAL=$((passes + fails))
if [[ "$TOTAL" -lt 549 ]]; then printf 'FAIL ANTI-VACUITY: only %s assertions ran (floor 549)\n' "$TOTAL"; exit 1; fi
printf '%s passed, %s failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
