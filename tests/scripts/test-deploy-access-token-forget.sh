#!/usr/bin/env bash
#
# (#9294 G1, PR-2, ADR-241 D10) The deploy Access service token leaves Terraform state WITHOUT being destroyed, and the
# deploy webhook's Access policy keeps admitting the same token through a committed constant.
#
# PROPERTY. `cloudflare_zero_trust_access_service_token.deploy` is forgotten (`removed { destroy = false }`); the deploy
# application's policy admits `local.deploy_service_token_ids` (a `locals` constant, not a variable: a root variable is
# overridable through TF_VAR_* and the web-platform plan runs under `doppler run --name-transformer tf-var` against
# prd_terraform, Ruled by CTO agent 2026-10-23); the two sensitive outputs that carried the token's client_id/client_secret
# are gone. FORWARD-FIX ONLY: re-declaring the resource would mint a token no Doppler project holds.
#
# WHAT THIS PROVES (offline, no network): the EFFECTIVE (comment-stripped, all three HCL comment forms) source shape of
# tunnel.tf; the plan shape of a synthesized fixture through the REAL web-platform destroy-guard filter; the deploy-policy
# gate (tests/scripts/lib/deploy-policy-gate.sh) EXECUTED against synthesized counters and commit messages; and that the
# -target line the `removed` block needs is still in the workflow. Every source predicate is a function that mutants reuse.
# WHAT IT CANNOT PROVE: that the committed id equals the LIVE token id. CI cannot know the live id: S7 therefore FAILS while
# the constant is empty (the draft state; the owner commits the id read from the live state before merge) and the gate's
# deploy_policy_* counters judge the REAL plan after that.
#
# #12937 (Guard 2 of the zone-move plan; Ruled by CTO agent, 2026-11-19): the same gate covers the three Soleur-account
# policies (deploy / ci_ssh / registry_push `_soleur`), each against its own committed token reference. Rows H* are the
# single acknowledged creates the first merge apply needs (GREEN), R* the refusals (each asserting UNWEDGE), C* the
# committed-id read from tunnel.tf, MG* the mutation proof that each R row reds when its guard leaves the filter, and
# Q*/MQ* the static policy parity over tunnel.tf.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INFRA="$ROOT/apps/web-platform/infra"
TF="$INFRA/tunnel.tf"
WF="$ROOT/.github/workflows/apply-web-platform-infra.yml"
WF_DPF="$ROOT/.github/workflows/apply-deploy-pipeline-fix.yml"
FILTER="$ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq"
GATE="$ROOT/tests/scripts/lib/deploy-policy-gate.sh"
FIX="$ROOT/tests/scripts/fixtures/tfplan-deploy-access-token-forget.json"
# shellcheck source=lib/hcl-effective-text.sh
source "$ROOT/tests/scripts/lib/hcl-effective-text.sh"
# shellcheck source=lib/deploy-policy-gate.sh
source "$GATE"

MIN_ASSERTIONS=150
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
check_not() { local label="$1"; shift; if "$@"; then bad "$label"; else ok "$label"; fi; }

UUID_RE='"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"'
SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT

# ── source predicates over the EFFECTIVE text of a tunnel.tf copy (arg 1) ─────────────────────────────────────────────
eff() { strip_comments "$1"; }
p_no_resource()   { ! grep -qE '^resource[[:space:]]+"cloudflare_zero_trust_access_service_token"[[:space:]]+"deploy"' <<<"$(eff "$1")"; }
p_removed()       { grep -qE 'removed[[:space:]]*\{[[:space:]]*from[[:space:]]*=[[:space:]]*cloudflare_zero_trust_access_service_token\.deploy[[:space:]]*lifecycle[[:space:]]*\{[[:space:]]*destroy[[:space:]]*=[[:space:]]*false[[:space:]]*\}' <<<"$(eff "$1" | tr -d '\n')"; }
p_policy_local()  { grep -qE 'include[[:space:]]*\{[[:space:]]*service_token[[:space:]]*=[[:space:]]*local\.deploy_service_token_ids[[:space:]]*\}' <<<"$(block_of "$1" cloudflare_zero_trust_access_policy deploy_service_token | tr -d '\n')"; }
p_precondition()  { local b; b="$(block_of "$1" cloudflare_zero_trust_access_policy deploy_service_token)"; grep -qE '^[[:space:]]+precondition[[:space:]]*\{' <<<"$b" && grep -qF 'length(local.deploy_service_token_ids) > 0' <<<"$b" && grep -qF '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$b"; }
p_no_outputs()    { ! grep -qE '^output[[:space:]]+"access_service_token_client_(id|secret)"' <<<"$(eff "$1")"; }
p_no_client_ref() { ! grep -qE 'access_service_token\.deploy\.client_' <<<"$(eff "$1")"; }
p_locals_uuid()   { grep -qE "$UUID_RE" <<<"$(eff "$1" | tr -d '\n' | grep -oE 'locals[[:space:]]*\{[[:space:]]*deploy_service_token_ids[[:space:]]*=[[:space:]]*\[[^]]*\]')"; }
p_locals_once()   { [[ "$(eff "$1" | grep -cE '^[[:space:]]*deploy_service_token_ids[[:space:]]*=')" == "1" ]]; }
# no `variable "deploy_service_token_ids"` in ANY .tf of the root dir (arg 1), and no override/JSON config that could re-add one
p_no_variable()   { local f; for f in "$1"/*.tf; do if grep -qE '^variable[[:space:]]+"deploy_service_token_ids"' <<<"$(eff "$f")"; then return 1; fi; done; [[ "$(p_b4_no_override_files "$1")" == "1" ]]; }

echo "=== deploy Access token forget (G1, PR-2; #9294) ==="

check     "S1: the deploy token is not a declared resource any more (re-declaring it would mint a token no Doppler project holds)" p_no_resource "$TF"
check     "S2: a removed block forgets the deploy token with destroy = false (effective text, all three comment forms stripped)" p_removed "$TF"
check     "S3: the deploy policy admits local.deploy_service_token_ids inside its own resource block" p_policy_local "$TF"
check     "S4: the policy carries a precondition refusing an empty or non-UUID list" p_precondition "$TF"
check     "S5: no output block reads the deploy token (its client_id/client_secret sat in Tier-A-readable state)" p_no_outputs "$TF"
check     "S5b: nothing in tunnel.tf reads .client_ of the deploy token" p_no_client_ref "$TF"
check     "S6: the id list is declared exactly once, as a local (a variable is overridable from prd_terraform through tf-var)" p_locals_once "$TF"
check     "S6b: no variable of that name exists in any .tf of the root, and no override or JSON config could add one" p_no_variable "$INFRA"
# OWNER (draft state): the constant is empty until the live token id (read-only state read, id line only) is committed.
check     "S7: OWNER — local.deploy_service_token_ids holds at least one UUID-shaped id (CI cannot know the live id; this fails while it is empty)" p_locals_uuid "$TF"

# ── the -target line a removed block needs, on comment-stripped YAML ───────────────────────────────────────────────────
yaml_code() { grep -vE '^[[:space:]]*#' "$1"; }
# `>/dev/null`, not `grep -q`: under pipefail an early-exiting grep SIGPIPEs the 490 kB producer and the pipeline reads as failed.
t1() { yaml_code "$WF" | grep -E '^[[:space:]]*-target=cloudflare_zero_trust_access_service_token\.deploy[[:space:]]*\\?$' >/dev/null; }
t2() { ! grep -rhE -- '-replace[= ]+["'"'"']?[^ ]*access_service_token\.deploy' "$ROOT/.github" 2>/dev/null | grep -vE '^[[:space:]]*#' | grep . >/dev/null; }
t3() { ! yaml_code "$WF_DPF" | grep -E -- '-target=' | grep 'access_service_token' >/dev/null; }
check     "T1: apply-web-platform-infra.yml still targets the forgotten address, on a non-comment line" t1
check     "T2: no workflow replaces or destroys the deploy token (-replace would re-create it; never)" t2
check     "T3: apply-deploy-pipeline-fix.yml's -target list holds no Access token" t3

# ── plan shape of the fixture through the REAL filter ─────────────────────────────────────────────────────────────────
counts() { jq -f "$FILTER" "$1"; }
cnt()    { counts "$1" | jq -r --arg k "$2" '.[$k]'; }
p1() { jq -e '[.resource_changes[].change.actions] == [["forget"],["no-op"]]' "$FIX" >/dev/null; }
p2() { jq -e '(.resource_changes[] | select(.type == "cloudflare_zero_trust_access_policy") | .change) | .before.include == .after.include' "$FIX" >/dev/null; }
p3() { ! grep -qE 'client_(id|secret)"?[[:space:]]*:[[:space:]]*"[^"]' "$FIX"; }
check     "P1: the fixture holds exactly one forget (the token) and one no-op (the policy): no add, no delete, no update" p1
check     "P2: the policy include is unchanged across the plan (the same token id before and after)" p2
check     "P3: the fixture carries no client_secret / client_id value anywhere" p3
for k in resource_deletes nested_deletes host_creates reboot_updates deploy_policy_changes deploy_policy_unsafe access_token_stray_forgets; do
  check   "P4/$k: the real filter counts 0 for the forget fixture (the gate is not tripped)" test "$(cnt "$FIX" "$k")" = "0"
done
check     "P4/non_terraform_data_deletes: the filter counts the forget as 1, so apply-deploy-pipeline-fix.yml (which HALTs on it) would refuse to apply it" test "$(cnt "$FIX" non_terraform_data_deletes)" = "1"

# ── filter mutants: each deploy-policy counter must move on the shape it exists for ──────────────────────────────────────
mut() { local name="$1" expr="$2"; jq "$expr" "$FIX" > "$SBX/$name.json"; ! cmp -s "$FIX" "$SBX/$name.json"; }
mut idswap '(.resource_changes[1].change) |= (.actions = ["update"] | .after.include[0].service_token = ["00000000-0000-4000-8000-000000000099"])' || bad "M-landing: idswap did not land"
check     "F1: an id swap inside the single include block is an in-place change (changes=1), not unsafe" test "$(cnt "$SBX/idswap.json" deploy_policy_changes)/$(cnt "$SBX/idswap.json" deploy_policy_unsafe)" = "1/0"
mut empty '(.resource_changes[1].change) |= (.actions = ["update"] | .after.include[0].service_token = [])' || bad "M-landing: empty did not land"
check     "F2: an emptied service_token list is unsafe (the lockout shape)" test "$(cnt "$SBX/empty.json" deploy_policy_unsafe)" = "1"
mut noblock '(.resource_changes[1].change) |= (.actions = ["update"] | .after.include = [])' || bad "M-landing: noblock did not land"
check     "F3: an include with no block at all is unsafe" test "$(cnt "$SBX/noblock.json" deploy_policy_unsafe)" = "1"
mut polDelete '(.resource_changes[1].change) |= (.actions = ["delete"] | .after = null)' || bad "M-landing: polDelete did not land"
check     "F4: deleting the policy is unsafe" test "$(cnt "$SBX/polDelete.json" deploy_policy_unsafe)" = "1"
mut unknown '(.resource_changes[1].change) |= (.actions = ["update"] | .after_unknown = {"include": true})' || bad "M-landing: unknown did not land"
check     "F5: an include that is unknown at plan time is unsafe" test "$(cnt "$SBX/unknown.json" deploy_policy_unsafe)" = "1"
mut absent 'del(.resource_changes[1])' || bad "M-landing: absent did not land"
check     "F6: a plan without the policy entry counts as a change (the policy is always in the -target list)" test "$(cnt "$SBX/absent.json" deploy_policy_changes)" = "1"
mut stray '.resource_changes += [{"address":"cloudflare_zero_trust_access_service_token.ci_ssh","mode":"managed","type":"cloudflare_zero_trust_access_service_token","name":"ci_ssh","change":{"actions":["forget"],"before":{"name":"ci"},"after":null}}]' || bad "M-landing: stray did not land"
check     "F7: a forget of any other Access token is a stray forget" test "$(cnt "$SBX/stray.json" access_token_stray_forgets)" = "1"
mut delTok '(.resource_changes[0].change.actions) = ["delete"]' || bad "M-landing: delTok did not land"
check     "F8: the token DELETED instead of forgotten is counted as a resource delete" test "$(cnt "$SBX/delTok.json" resource_deletes)" -ge 1

# ── the gate, EXECUTED ───────────────────────────────────────────────────────────────────────────────────────────────────
gate() { # <changes> <unsafe> <stray> <message> -> rc
  local c; c="$(jq -nc --argjson a "$1" --argjson b "$2" --argjson s "$3" '{deploy_policy_changes:$a,deploy_policy_unsafe:$b,access_token_stray_forgets:$s}')"
  deploy_policy_gate "$c" "$4" >/dev/null 2>&1
}
ACK=$'merge: rotate\n[ack-deploy-policy]\n'
check     "G1: a clean plan (all counters 0) passes" gate 0 0 0 ""
check_not "G2: a changed policy without the ack is refused" gate 1 0 0 "merge: forget the token"
check     "G3: a changed policy WITH an own-line [ack-deploy-policy] passes (a rotation PR)" gate 1 0 0 "$ACK"
check_not "G4: [ack-destroy] does not stand in for the policy ack" gate 1 0 0 $'merge\n[ack-destroy]\n'
check_not "G5: the ack token inside prose on a longer line does not count" gate 1 0 0 "merge: do not add [ack-deploy-policy] here"
check_not "G6: an unsafe policy is refused even WITH the ack" gate 1 1 0 "$ACK"
check_not "G7: a stray Access-token forget is refused even WITH the ack" gate 0 0 1 "$ACK"
check_not "G8: a counter that is not a non-negative integer is refused (a jq failure must not read as 0)" deploy_policy_gate '{"deploy_policy_changes":"x","deploy_policy_unsafe":0,"access_token_stray_forgets":0}' ""
check_not "G9: a missing counter is refused" deploy_policy_gate '{"deploy_policy_changes":0,"deploy_policy_unsafe":0}' ""
check     "G10: the workflow sources the gate and calls it before the destroy_count sum, without [ack-destroy]" bash -c '
  w="$(grep -vE "^[[:space:]]*#" "$1")"; a="$(grep -nE "deploy_policy_gate \"\\\$policy_counts\" \"\\\$[A-Z_]+\" \|\| exit 1" <<<"$w" | head -1 | cut -d: -f1)"; d="$(grep -n "^[[:space:]]*destroy_count=" <<<"$w" | head -1 | cut -d: -f1)"
  [[ -n "$a" && -n "$d" && "$a" -lt "$d" ]] && grep -qF "tests/scripts/lib/deploy-policy-gate.sh" <<<"$w"' _ "$WF"
check     "G11: the gate input is fed from event.commits messages, not the tip alone (coalesced-merge ack)" bash -c '
  w="$(grep -vE "^[[:space:]]*#" "$1")"
  grep -qF "EVENT_MSGS_JSON: \${{ toJSON(github.event.commits.*.message) }}" <<<"$w" && grep -qF "deploy_policy_gate \"\$policy_counts\" \"\$ALL_MSGS\" || exit 1" <<<"$w"' _ "$WF"

# ── source mutants: every predicate above must be able to fail ─────────────────────────────────────────────────────────────
cp "$TF" "$SBX/orig.tf"
mtf() { # <name> <python-snippet editing s>
  python3 - "$TF" "$SBX/$1.tf" "$2" <<'PY'
import sys
s = open(sys.argv[1]).read(); old = s
exec(sys.argv[3])
assert s != old, "mutation did not land"
open(sys.argv[2], "w").write(s)
PY
}
mtf m_comment 's = s.replace("\nremoved {\n", "\n/* removed {\n", 1).replace("destroy = false\n  }\n}\n", "destroy = false\n  }\n} */\n", 1)' || bad "M-landing: m_comment"
check_not "M1: wrapping the removed block in a /* */ comment fails S2" p_removed "$SBX/m_comment.tf"
mtf m_noprecond 's = s.replace("precondition {", "unused_block {", 1)' || bad "M-landing: m_noprecond"
check_not "M2: deleting the policy precondition fails S4" p_precondition "$SBX/m_noprecond.tf"
mtf m_resource 's += "\nresource \"cloudflare_zero_trust_access_service_token\" \"deploy\" {\n  account_id = var.cf_account_id\n  name       = \"x\"\n}\n"' || bad "M-landing: m_resource"
check_not "M3: re-declaring the resource fails S1" p_no_resource "$SBX/m_resource.tf"
mtf m_output 's += "\noutput \"access_service_token_client_secret\" {\n  value = \"x\"\n}\n"' || bad "M-landing: m_output"
check_not "M4: re-adding a deploy-token output fails S5" p_no_outputs "$SBX/m_output.tf"
mtf m_ref 's = s.replace("local.deploy_service_token_ids\n  }\n\n  lifecycle", "local.deploy_service_token_ids == null ? [] : []\n  }\n\n  lifecycle", 1)' || bad "M-landing: m_ref"
check_not "M5: a policy include that is not exactly the local fails S3" p_policy_local "$SBX/m_ref.tf"
mtf m_uuid 'import re; s = re.sub(r"deploy_service_token_ids = \[[^]]*\]", "deploy_service_token_ids = [\"00000000-0000-4000-8000-000000000001\"]", s, count=1)' || bad "M-landing: m_uuid"
check     "M6: a UUID in the local satisfies S7 (the positive control: S7 can pass)" p_locals_uuid "$SBX/m_uuid.tf"
mtf m_baduuid 'import re; s = re.sub(r"deploy_service_token_ids = \[[^]]*\]", "deploy_service_token_ids = [\"not-a-uuid\"]", s, count=1)' || bad "M-landing: m_baduuid"
check_not "M7: a non-UUID entry fails S7" p_locals_uuid "$SBX/m_baduuid.tf"
mkdir -p "$SBX/rootcopy"; cp "$INFRA"/*.tf "$SBX/rootcopy/"
printf 'variable "deploy_service_token_ids" {\n  type    = list(string)\n  default = ["x"]\n}\n' > "$SBX/rootcopy/zz-extra.tf"
check_not "M8: a variable of that name added in another root file fails S6b" p_no_variable "$SBX/rootcopy"
rm -f "$SBX/rootcopy/zz-extra.tf"; : > "$SBX/rootcopy/extra_override.tf"
check_not "M9: an override file in the root fails S6b" p_no_variable "$SBX/rootcopy"
sed -E 's/^([[:space:]]*)-target=cloudflare_zero_trust_access_service_token\.deploy/\1# -target=cloudflare_zero_trust_access_service_token.deploy/' "$WF" > "$SBX/wf-commented.yml"
m10() { ! cmp -s "$WF" "$SBX/wf-commented.yml" && ! grep -vE "^[[:space:]]*#" "$SBX/wf-commented.yml" | grep -E "^[[:space:]]*-target=cloudflare_zero_trust_access_service_token\.deploy" >/dev/null; }
check     "M10: commenting out the -target line (the mutation landed) leaves no non-comment -target line, so T1 fails" m10

# #12937: the gate reads `$policy_counts` (the filter re-run with the committed _soleur deploy ids bound as $ids, via
# deploy_policy_counts over tunnel.tf), never the destroy guard's id-less `$counts` (G10/G11 above pin the call).
check     "G12: the gate counters come from deploy_policy_counts over THIS root's tunnel.tf and the real filter, before the gate call" bash -c '
  w="$(grep -vE "^[[:space:]]*#" "$1")"
  c="$(grep -nF "policy_counts=\"\$(deploy_policy_counts tfplan.json \"\${GITHUB_WORKSPACE}/apps/web-platform/infra/tunnel.tf\" \"\${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter-web-platform.jq\")\" || exit 1" <<<"$w" | head -1 | cut -d: -f1)"
  g="$(grep -nF "deploy_policy_gate \"\$policy_counts\"" <<<"$w" | head -1 | cut -d: -f1)"
  [[ -n "$c" && -n "$g" && "$c" -lt "$g" ]]' _ "$WF"

# ── #12937 Guard 2: the three Soleur-account policies flow through the SAME gate ─────────────────────────────────────────
# Each `_soleur` policy is judged against its OWN committed token reference: the deploy one against the id list committed
# in tunnel.tf (bound as --argjson ids), ci_ssh / registry_push against their configuration reference (their token id is
# unknown at plan time on the first create). Synthesized plans only (cq-test-fixtures-synthesized-only). Every RED row
# that refuses also asserts the UNWEDGE line (CTO Amendment 3); each policy's single acknowledged create has a GREEN row.
IDS='["00000000-0000-4000-8000-0000000000a1"]'
# The three policy creates as provider 4.52.7 plans them (terraform show -json, offline, synthetic ids). A token created in
# the same apply leaves service_token ABSENT from `after` and wholly unknown in `after_unknown`.
REAL="$ROOT/tests/scripts/fixtures/tfplan-access-policy-soleur-create.json"
# sol_plan <deploy-actions> <ssh-actions> <registry-actions> -> the old deploy policy no-op + the three real-shape _soleur
# entries + their configuration. A non-create ci_ssh / registry entry has its token already in state: its id is known.
sol_plan() {
  jq -c --slurpfile real "$REAL" --argjson ad "$1" --argjson as "$2" --argjson ar "$3" '
    def ent($addr; $acts; $tok):
      ($real[0].resource_changes[] | select(.address == $addr))
      | .change.actions = $acts
      | if $acts == ["create"] or $tok == null then .
        else .change.after.include[0].service_token = [$tok] | .change.after_unknown.include[0].service_token = [false] end
      | .change.before = (if $acts == ["create"] then null else .change.after end);
    .resource_changes = [.resource_changes[1],
      ent("cloudflare_zero_trust_access_policy.deploy_service_token_soleur"; $ad; null),
      ent("cloudflare_zero_trust_access_policy.ci_ssh_service_token_soleur"; $as; "00000000-0000-4000-8000-0000000000b1"),
      ent("cloudflare_zero_trust_access_policy.registry_push_service_token_soleur"; $ar; "00000000-0000-4000-8000-0000000000b2")]
    | .configuration = $real[0].configuration' "$FIX"
}
NOOP='["no-op"]'; CRE='["create"]'; UPD='["update"]'
# scnt <plan-file> <key> [filter] -> the counter computed WITH the committed ids bound (as the workflow does)
scnt() { jq --argjson ids "$IDS" -f "${3:-$FILTER}" "$1" | jq -r --arg k "$2" '.[$k]'; }
# sgate <plan-file> <message> [filter] -> rc of the REAL gate on the (real or mutant) filter's counters; output kept
sgate() { local c; c="$(jq -c --argjson ids "$IDS" -f "${3:-$FILTER}" "$1")"; deploy_policy_gate "$c" "$2" >"$SBX/sgate.out" 2>&1; }
# sred <label> <plan-file> <message>: the gate REFUSES, and the refusal carries the UNWEDGE line
sred() { if sgate "$2" "$3"; then bad "$1 (the gate passed)"; elif grep -qF '::error::UNWEDGE:' "$SBX/sgate.out"; then ok "$1"; else bad "$1 (refused without the UNWEDGE line)"; fi; }
sp()  { sol_plan "$@" > "$SBX/sp.json"; }
spm() { sol_plan "$1" "$2" "$3" | jq -c "$4" > "$SBX/sp.json"; }   # sol_plan + one jq edit

sp "$CRE" "$CRE" "$CRE"; cp "$SBX/sp.json" "$SBX/sol-create-all.json"
check     "H1 GREEN: the single acknowledged create of all three _soleur policies (the merge apply) passes" sgate "$SBX/sol-create-all.json" "$ACK"
check     "H1b: ... and it is counted as 3 changes, 0 unsafe (the gate did see it)" test "$(scnt "$SBX/sol-create-all.json" deploy_policy_changes)/$(scnt "$SBX/sol-create-all.json" deploy_policy_unsafe)" = "3/0"
sp "$CRE" "$NOOP" "$NOOP"
check     "H2 GREEN: the single acknowledged create of the deploy _soleur policy passes" sgate "$SBX/sp.json" "$ACK"
sred      "R1 RED: the same create WITHOUT an own-line [ack-deploy-policy] is refused (UNWEDGE)" "$SBX/sp.json" "merge: re-home the tunnel"
sp "$NOOP" "$CRE" "$NOOP"
check     "H3 GREEN: the single acknowledged create of the ci_ssh _soleur policy passes" sgate "$SBX/sp.json" "$ACK"
sred      "R1c RED: the ci_ssh create without the ack is refused (UNWEDGE)" "$SBX/sp.json" "merge"
sp "$NOOP" "$NOOP" "$CRE"
check     "H4 GREEN: the single acknowledged create of the registry_push _soleur policy passes" sgate "$SBX/sp.json" "$ACK"
sred      "R1d RED: the registry_push create without the ack is refused (UNWEDGE)" "$SBX/sp.json" "merge"
sp "$NOOP" "$NOOP" "$NOOP"
check     "H5 GREEN: a plan touching neither the old nor any _soleur policy passes with no ack" sgate "$SBX/sp.json" ""
check     "H5b: ... at 0 changes / 0 unsafe" test "$(scnt "$SBX/sp.json" deploy_policy_changes)/$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "0/0"
spm "$CRE" "$NOOP" "$NOOP" '(.resource_changes[1].change.after.include) += [{"service_token":["00000000-0000-4000-8000-0000000000a2"]}]'
sred      "R2 RED: a _soleur deploy create with TWO include blocks is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
check     "R2b: ... counted as unsafe" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
spm "$CRE" "$NOOP" "$NOOP" '(.resource_changes[0].change) |= (.actions = ["delete"] | .after = null)'
sred      "R3 RED: a correct _soleur create AND a delete of the old deploy policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[1].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000ff"]'
sred      "R5 RED: an update of the _soleur deploy include to an id that is NOT the committed list is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
sp "$UPD" "$NOOP" "$NOOP"
sred      "R5c RED: an in-place update of the _soleur deploy policy (committed id) without the ack is refused (UNWEDGE)" "$SBX/sp.json" "merge"
check     "R5d GREEN: the same update WITH the ack passes (an id rotation PR)" sgate "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[2].change.actions) = ["create","delete"]'
sred      "R6 RED: a replace of the _soleur ci_ssh policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[3].change.actions) = ["delete"]'
sred      "R6b RED: a delete of the _soleur registry_push policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
# CFG_SSH / CFG_REG: jq paths to a policy's configuration entry, by address (for edits)
CFG_SSH='(.configuration.root_module.resources[] | select(.address == "cloudflare_zero_trust_access_policy.ci_ssh_service_token_soleur"))'
CFG_REG='(.configuration.root_module.resources[] | select(.address == "cloudflare_zero_trust_access_policy.registry_push_service_token_soleur"))'
XWIRE="($CFG_SSH.expressions.include[0].service_token.references) = [\"cloudflare_zero_trust_access_service_token.registry_push_soleur.id\",\"cloudflare_zero_trust_access_service_token.registry_push_soleur\"]"
spm "$NOOP" "$CRE" "$NOOP" "$XWIRE"
sred      "R7 RED: a ci_ssh _soleur policy whose include references the REGISTRY token is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$CRE" "($CFG_REG.expressions.include[0].service_token) = {\"constant_value\":[\"00000000-0000-4000-8000-0000000000a3\"]}"
sred      "R7b RED: a registry_push _soleur policy whose include is a literal, not its token reference, is refused (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$CRE" 'del(.configuration)'
sred      "R7c RED: a plan with no configuration section cannot bind the reference, so the create is refused (fail-closed)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$CRE" "$NOOP" '(.resource_changes[2].change.after.include[0].any_valid_service_token) = true'
sred      "R8 RED: any_valid_service_token on a _soleur policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$CRE" "$NOOP" "$NOOP" '(.resource_changes[1].change.after.include[0].everyone) = true'
sred      "R8b RED: everyone on the _soleur deploy policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
r9() { local c; c="$(jq -c -f "$FILTER" "$SBX/sol-create-all.json")"; deploy_policy_gate "$c" "$ACK" >/dev/null 2>&1; }
check_not "R9 RED: without the committed ids bound (a caller that forgot --argjson ids) the _soleur deploy create is refused" r9
# Gate dispatch (Guard 2 row 4): ONE selector covers every address, so an update at each of the four counts once each.
spm "$UPD" "$UPD" "$UPD" '(.resource_changes[0].change.actions) = ["update"]'; cp "$SBX/sp.json" "$SBX/sol-upd-all.json"
check     "R4: the selector matched all four addresses (old + three _soleur): 4 changes in one synthetic plan" test "$(scnt "$SBX/sol-upd-all.json" deploy_policy_changes)" = "4"

# ── deploy_policy_counts / deploy_policy_committed_ids: the ids come from the committed tunnel.tf line ────────────────────
# C1-C2b test the reader on tunnel.tf with the nil placeholder filled (a no-op once minted); Q8 judges the committed value.
NIL_ID='00000000-0000-0000-0000-000000000000'
TF_FILLED="$SBX/tunnel-filled.tf"; sed "s/\"$NIL_ID\"/\"00000000-0000-4000-8000-0000000000a1\"/" "$TF" > "$TF_FILLED"
c1() { local o; o="$(deploy_policy_committed_ids "$TF_FILLED" 2>/dev/null)" && jq -e 'type == "array" and length > 0' <<<"$o" >/dev/null; }
check     "C1: deploy_policy_committed_ids reads ONE UUID list from tunnel.tf (the line the precondition also reads; placeholder filled)" c1
c2() {
  local ids c; ids="$(deploy_policy_committed_ids "$TF_FILLED" 2>/dev/null)" || return 1
  jq --argjson ids "$ids" '(.resource_changes[1].change.after.include[0].service_token) = $ids' "$SBX/sol-create-all.json" > "$SBX/c2.json"
  c="$(deploy_policy_counts "$SBX/c2.json" "$TF_FILLED" "$FILTER" 2>/dev/null)" || return 1
  [[ "$(jq -r .deploy_policy_unsafe <<<"$c")/$(jq -r .deploy_policy_changes <<<"$c")" == "0/3" ]]
}
check     "C2: deploy_policy_counts binds the committed ids, so the committed list's own create is counted and not unsafe" c2
c2b() { jq '(.resource_changes[1].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000ee"]' "$SBX/sol-create-all.json" > "$SBX/c2b.json"; [[ "$(deploy_policy_counts "$SBX/c2b.json" "$TF_FILLED" "$FILTER" 2>/dev/null | jq -r .deploy_policy_unsafe)" == "1" ]]; }
check     "C2b: ... and a planned id that is not the committed one is unsafe through the same helper" c2b
cids() { deploy_policy_committed_ids "$1" >/dev/null 2>&1; }
printf 'locals {\n  deploy_service_token_ids_soleur = ["00000000-0000-4000-8000-0000000000a1"] # trailing note\n}\n' > "$SBX/ids-ok.tf"
check     "C3: a trailing # comment on the committed line is allowed" cids "$SBX/ids-ok.tf"
printf 'locals {\n  # deploy_service_token_ids_soleur = ["00000000-0000-4000-8000-0000000000a1"]\n}\n' > "$SBX/ids-commented.tf"
check_not "C4: a commented-out declaration is no declaration (fail-closed)" cids "$SBX/ids-commented.tf"
printf '  deploy_service_token_ids_soleur = ["00000000-0000-4000-8000-0000000000a1"]\n  deploy_service_token_ids_soleur = ["00000000-0000-4000-8000-0000000000a2"]\n' > "$SBX/ids-twice.tf"
check_not "C5: two declarations are refused" cids "$SBX/ids-twice.tf"
printf '  deploy_service_token_ids_soleur = ["not-a-uuid"]\n' > "$SBX/ids-bad.tf"
check_not "C6: a non-UUID entry is refused" cids "$SBX/ids-bad.tf"
printf '  deploy_service_token_ids_soleur = ["%s"] # FILL-AT-PHASE-3.1\n' "$NIL_ID" > "$SBX/ids-nil.tf"
c6b() { ! deploy_policy_committed_ids "$SBX/ids-nil.tf" >"$SBX/c6b.out" 2>&1 && grep -qF 'placeholder deploy token id still committed (FILL-AT-PHASE-3.1)' "$SBX/c6b.out"; }
check     "C6b: the nil-UUID placeholder is refused, with the FILL-AT-PHASE-3.1 message" c6b
printf '  deploy_service_token_ids_soleur = []\n' > "$SBX/ids-empty.tf"
check_not "C7: an empty list is refused" cids "$SBX/ids-empty.tf"
printf '  deploy_service_token_ids_soleur = var.x\n' > "$SBX/ids-var.tf"
check_not "C8: a non-literal expression is refused" cids "$SBX/ids-var.tf"
check_not "C9: deploy_policy_counts refuses when the ids cannot be read" deploy_policy_counts "$SBX/sol-create-all.json" "$SBX/ids-bad.tf" "$FILTER"

# ── mutation proof: each Guard 2 row reds when its guard is removed from the REAL filter ────────────────────────────────
mfilter() { # <name> <python-snippet editing s>
  python3 - "$FILTER" "$SBX/$1.jq" "$2" <<'PY'
import sys
s = open(sys.argv[1]).read(); old = s
exec(sys.argv[3])
assert s != old, "mutation did not land"
open(sys.argv[2], "w").write(s)
PY
}
# Drops the selector from deploy_policy_changes only (dropping the table itself trips the stray-policy counter instead).
mfilter f_nosel 's = s.replace("         | select(IN(.address; deploy_policy_soleur_addrs[]))\n         | select(.change.actions != [\"no-op\"]) ]", "         | select(false) ]", 1)' || bad "M-landing: f_nosel"
sp "$CRE" "$NOOP" "$NOOP"
check     "MG1: with the _soleur addresses dropped from the selector, R1's un-acked create would PASS (R1 depends on the selector)" sgate "$SBX/sp.json" "merge" "$SBX/f_nosel.jq"
check_not "MG1b: ... and R4's four-address count would not hold" test "$(scnt "$SBX/sol-upd-all.json" deploy_policy_changes "$SBX/f_nosel.jq")" = "4"
mfilter f_noref 's = s.replace("    elif (deploy_policy_soleur_ref_ok($plan; .address) | not) then true\n", "", 1)' || bad "M-landing: f_noref"
spm "$NOOP" "$CRE" "$NOOP" "$XWIRE"
check     "MG2: without the reference binding, R7's cross-wired ci_ssh policy would PASS" sgate "$SBX/sp.json" "$ACK" "$SBX/f_noref.jq"
mfilter f_noids 's = s.replace("      or (($inc[0].service_token? // null) != $ids)\n", "", 1)' || bad "M-landing: f_noids"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[1].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000ff"]'
check     "MG3: without the id-equality check, R5's wrong-id update would PASS" sgate "$SBX/sp.json" "$ACK" "$SBX/f_noids.jq"
mfilter f_noinc 's = s.replace("    elif ($inc | length) != 1 or ($inc[0] | type) != \"object\" then true\n", "", 1)' || bad "M-landing: f_noinc"
spm "$NOOP" "$CRE" "$NOOP" '(.resource_changes[2].change.after.include) += [{"service_token":[null]}]'
check     "MG4: without the one-include check, a ci_ssh create with two include blocks would PASS" sgate "$SBX/sp.json" "$ACK" "$SBX/f_noinc.jq"
check_not "MG4b: ... and the real filter refuses that same plan" sgate "$SBX/sp.json" "$ACK"
mfilter f_nodel 's = s.replace("    elif ($act | any(. == \"delete\" or . == \"forget\")) then true\n", "", 1)' || bad "M-landing: f_nodel"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[3].change.actions) = ["delete"]'
check     "MG5: without the delete rule, R6b's registry_push delete would PASS with the ack" sgate "$SBX/sp.json" "$ACK" "$SBX/f_nodel.jq"
# Harness row: feeding a plan with no _soleur entries (the canonical forget fixture) to the create rows must red them.
check_not "MG6: the forget fixture (no _soleur entries) does not satisfy H1b's 3/0 count" test "$(scnt "$FIX" deploy_policy_changes)/$(scnt "$FIX" deploy_policy_unsafe)" = "3/0"

# ── the real provider shape, include allowlist, decision, and policies outside the table ─────────────────────────────
p5() { jq -e '[.resource_changes[] | select(.address | test("(ci_ssh|registry_push)_service_token_soleur$")) | .change
  | (.after.include[0] | has("service_token") | not) and (.after_unknown.include[0].service_token == true)] == [true, true]' "$REAL" >/dev/null; }
check     "P5: the captured fixture keeps the provider's shape: ci_ssh / registry_push service_token absent from after, wholly unknown" p5
check     "H6 GREEN: the captured plan alone (old policy absent, +1) counts 4 changes / 0 unsafe" test "$(scnt "$REAL" deploy_policy_changes)/$(scnt "$REAL" deploy_policy_unsafe)" = "4/0"
check     "H6b GREEN: the gate passes the captured plan with [ack-deploy-policy]" sgate "$REAL" "$ACK"
sred      "R1e RED: the captured plan without the ack is refused (UNWEDGE)" "$REAL" "merge"
spm "$NOOP" "$NOOP" "$CRE" "($CFG_REG.expressions.include[0].service_token.references) = [\"cloudflare_zero_trust_access_service_token.ci_ssh_soleur.id\",\"cloudflare_zero_trust_access_service_token.ci_ssh_soleur\"]"
sred      "R7d RED: a registry_push policy create cross-wired to ci_ssh_soleur.id is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
check     "R7e: ... counted as unsafe (1)" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
spm "$NOOP" "$CRE" "$NOOP" '(.resource_changes[2].change.after.include[0].ip) = ["0.0.0.0/0"]'; cp "$SBX/sp.json" "$SBX/inc-ip.json"
sred      "R11 RED: an ip include beside the ci_ssh token is refused even with the ack (UNWEDGE)" "$SBX/inc-ip.json" "$ACK"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[1].change.after.include[0].email_domain) = ["example.com"]'
sred      "R11b RED: an email_domain include beside the deploy ids is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$UPD" '(.resource_changes[3].change.after.include[0].certificate) = true'
sred      "R11c RED: certificate = true on the registry_push include is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$CRE" "$NOOP" '(.resource_changes[2].change.after_unknown.include[0].ip) = true'
sred      "R11d RED: an include key other than service_token that is unknown at plan time is refused (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[2].change.after.decision) = "bypass"'; cp "$SBX/sp.json" "$SBX/dec-bypass.json"
sred      "R12 RED: decision bypass on the ci_ssh policy is refused even with the ack (UNWEDGE)" "$SBX/dec-bypass.json" "$ACK"
spm "$CRE" "$NOOP" "$NOOP" 'del(.resource_changes[1].change.after.decision) | (.resource_changes[1].change.after_unknown.decision) = true'
sred      "R12b RED: a decision unknown at plan time is refused (UNWEDGE)" "$SBX/sp.json" "$ACK"
# stray <name> <app>: a NEW policy outside the table on <app>, bypass + everyone, with its configuration entry
stray() {
  jq -c --arg n "$1" --arg app "cloudflare_zero_trust_access_application.$2" '
    (.resource_changes[] | select(.address == "cloudflare_zero_trust_access_policy.ci_ssh_service_token_soleur")) as $t
    | (.configuration.root_module.resources[] | select(.address == "cloudflare_zero_trust_access_policy.ci_ssh_service_token_soleur")) as $c
    | .resource_changes += [$t | .address = "cloudflare_zero_trust_access_policy.\($n)" | .name = $n | .change.actions = ["create"]
        | .change.after.decision = "bypass" | .change.after.include[0].everyone = true | .change.after_unknown.include[0] |= del(.service_token)]
    | .configuration.root_module.resources += [$c | .address = "cloudflare_zero_trust_access_policy.\($n)" | .name = $n
        | .expressions.application_id.references = [$app + ".id", $app] | .expressions.include = [{"everyone": {"constant_value": true}}]]'
}
sol_plan "$NOOP" "$NOOP" "$NOOP" | stray deploy_open deploy_soleur > "$SBX/stray-deploy.json"
check     "S8: a NEW policy outside the table on deploy_soleur is unsafe (1) at 0 table changes" test "$(scnt "$SBX/stray-deploy.json" deploy_policy_changes)/$(scnt "$SBX/stray-deploy.json" deploy_policy_unsafe)" = "0/1"
sred      "S8b RED: ... and the gate refuses it with NO ack (UNWEDGE)" "$SBX/stray-deploy.json" ""
sred      "S8c RED: ... and WITH the ack (UNWEDGE)" "$SBX/stray-deploy.json" "$ACK"
sol_plan "$NOOP" "$NOOP" "$NOOP" | stray ssh_open ssh_soleur | jq -c '(.configuration.root_module.resources[-1].expressions.application_id.references) = ["cloudflare_zero_trust_access_application.ssh_soleur.id"]' > "$SBX/stray-ssh.json"
check     "S8d: a stray on ssh_soleur referenced by .id alone is unsafe too" test "$(scnt "$SBX/stray-ssh.json" deploy_policy_unsafe)" = "1"
sol_plan "$NOOP" "$NOOP" "$NOOP" | stray reg_open registry_soleur > "$SBX/stray-reg.json"
check     "S8e: a stray on registry_soleur is unsafe" test "$(scnt "$SBX/stray-reg.json" deploy_policy_unsafe)" = "1"
sol_plan "$NOOP" "$NOOP" "$NOOP" | stray ssh_old ssh | jq -c '(.resource_changes[-1].change.after.decision) = "non_identity" | (.resource_changes[-1].change.after.include[0].everyone) = null' > "$SBX/stray-old.json"
check     "S8f: a policy on an OLD app (ssh) is not a _soleur stray (0 unsafe)" test "$(scnt "$SBX/stray-old.json" deploy_policy_unsafe)" = "0"
jq -c '(.resource_changes[-1].change.actions) = ["no-op"]' "$SBX/stray-deploy.json" > "$SBX/stray-noop.json"
check     "S8g: the counter judges changes only: an unchanged stray already in state counts 0" test "$(scnt "$SBX/stray-noop.json" deploy_policy_unsafe)" = "0"
mfilter f_nounk 's = s.replace("    elif (($unk[0].service_token? // false) == true) then false\n", "", 1)' || bad "M-landing: f_nounk"
check_not "MG7: without the unknown-token arm, H1's real-shape create of all three is refused with the ack" sgate "$SBX/sol-create-all.json" "$ACK" "$SBX/f_nounk.jq"
check     "MG7b: ... because ci_ssh and registry_push read as unsafe (2)" test "$(scnt "$SBX/sol-create-all.json" deploy_policy_unsafe "$SBX/f_nounk.jq")" = "2"
mfilter f_noallow 's = s.replace("    elif ($inc[0] | to_entries | any(.key != \"service_token\" and (.value | deploy_policy_blank | not))) then true\n", "", 1)' || bad "M-landing: f_noallow"
check     "MG8: without the include allowlist, R11's ip include would PASS with the ack" sgate "$SBX/inc-ip.json" "$ACK" "$SBX/f_noallow.jq"
mfilter f_nodec 's = s.replace("    elif ((.change.after // {}).decision? // null) != \"non_identity\" then true\n", "", 1)' || bad "M-landing: f_nodec"
check     "MG9: without the decision check, R12's bypass would PASS with the ack" sgate "$SBX/dec-bypass.json" "$ACK" "$SBX/f_nodec.jq"
mfilter f_nostray 's = s.replace("      + deploy_policy_soleur_stray($plan)\n", "", 1)' || bad "M-landing: f_nostray"
check     "MG10: without the stray-policy counter, S8's bypass-everyone policy on deploy_soleur would PASS with no ack" sgate "$SBX/stray-deploy.json" "" "$SBX/f_nostray.jq"

# ── #12937 static policy parity over tunnel.tf: each _soleur policy is bound to its own app and its own token ───────────────
# p_sol_policy <tf> <policy-name> <app-name> <include-ERE>: account-scoped, application_id = its OWN _soleur app, exactly one
# include holding only its own token, no any_valid_service_token / everyone anywhere in the block.
p_sol_policy() {
  local b; b="$(block_of "$1" cloudflare_zero_trust_access_policy "$2" | tr -d '\n')"
  [[ -n "$b" ]] || return 1
  grep -qE "account_id[[:space:]]*=[[:space:]]*local\.cf_soleur_account_id" <<<"$b" || return 1
  grep -qE "application_id[[:space:]]*=[[:space:]]*cloudflare_zero_trust_access_application\.$3\.id" <<<"$b" || return 1
  [[ "$(grep -oE 'include[[:space:]]*\{' <<<"$b" | wc -l)" -eq 1 ]] || return 1
  grep -qE "include[[:space:]]*\{[[:space:]]*service_token[[:space:]]*=[[:space:]]*$4[[:space:]]*\}" <<<"$b" || return 1
  grep -qE 'decision[[:space:]]*=[[:space:]]*"non_identity"' <<<"$b" || return 1
  [[ "$(grep -oE 'decision[[:space:]]*=' <<<"$b" | wc -l)" -eq 1 ]] || return 1
  ! grep -qE 'any_valid_service_token|everyone' <<<"$b"
}
p_sol_app() { # <tf> <app-name> <host> <duration>
  local b; b="$(block_of "$1" cloudflare_zero_trust_access_application "$2" | tr -d '\n')"
  [[ -n "$b" ]] || return 1
  grep -qE "account_id[[:space:]]*=[[:space:]]*local\.cf_soleur_account_id" <<<"$b" || return 1
  grep -qF "domain           = \"$3.\${var.app_domain_base}\"" <<<"$b" || return 1
  grep -qE "session_duration[[:space:]]*=[[:space:]]*\"$4\"" <<<"$b" || return 1
  grep -qE 'type[[:space:]]*=[[:space:]]*"self_hosted"' <<<"$b" || return 1
  [[ "$(grep -oE '(^|[^_a-z])type[[:space:]]*=' <<<"$b" | wc -l)" -eq 1 ]] || return 1
  if grep -qE '(^|[^_])policies[[:space:]]*=' <<<"$b"; then return 1; fi
  return 0
}
p_sol_precond() { local b; b="$(block_of "$1" cloudflare_zero_trust_access_policy deploy_service_token_soleur)"; grep -qF 'length(local.deploy_service_token_ids_soleur) > 0' <<<"$b" && grep -qF '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$b" && grep -qF "&& id != \"$NIL_ID\"" <<<"$b"; }
INC_DEPLOY='local\.deploy_service_token_ids_soleur'
INC_SSH='\[cloudflare_zero_trust_access_service_token\.ci_ssh_soleur\.id\]'
INC_REG='\[cloudflare_zero_trust_access_service_token\.registry_push_soleur\.id\]'
check     "Q1: deploy_service_token_soleur is non_identity, bound to deploy_soleur and to local.deploy_service_token_ids_soleur only" p_sol_policy "$TF" deploy_service_token_soleur deploy_soleur "$INC_DEPLOY"
check     "Q2: ci_ssh_service_token_soleur is bound to ssh_soleur and to the ci_ssh_soleur token only" p_sol_policy "$TF" ci_ssh_service_token_soleur ssh_soleur "$INC_SSH"
check     "Q3: registry_push_service_token_soleur is bound to registry_soleur and to the registry_push_soleur token only" p_sol_policy "$TF" registry_push_service_token_soleur registry_soleur "$INC_REG"
check     "Q4: the deploy_soleur app is account-scoped, self_hosted, deploy.<base>, 24h" p_sol_app "$TF" deploy_soleur deploy 24h
check     "Q5: the ssh_soleur app is account-scoped, self_hosted, ssh.<base>, 15m" p_sol_app "$TF" ssh_soleur ssh 15m
check     "Q6: the registry_soleur app is account-scoped, self_hosted, registry.<base>, 15m" p_sol_app "$TF" registry_soleur registry 15m
check     "Q7: the _soleur deploy policy carries the same UUID precondition, over its own local, refusing the nil placeholder" p_sol_precond "$TF"
# OWNER (draft state): RED until the minted deploy token id replaces the nil placeholder (CI cannot know the live id).
if grep -qF "\"$NIL_ID\"" <<<"$(eff "$TF" | grep -E '^[[:space:]]*deploy_service_token_ids_soleur[[:space:]]*=')"; then
  bad "Q8: placeholder deploy token id still committed (FILL-AT-PHASE-3.1)"
else
  check   "Q8: the committed _soleur id list is a UUID list holding a minted id" cids "$TF"
fi
mtf q_xwire 's = s.replace("service_token = [cloudflare_zero_trust_access_service_token.ci_ssh_soleur.id]", "service_token = [cloudflare_zero_trust_access_service_token.registry_push_soleur.id]", 1)' || bad "M-landing: q_xwire"
check_not "MQ1: a ci_ssh policy cross-wired to the registry token fails Q2" p_sol_policy "$SBX/q_xwire.tf" ci_ssh_service_token_soleur ssh_soleur "$INC_SSH"
mtf q_any 's = s.replace("service_token = [cloudflare_zero_trust_access_service_token.registry_push_soleur.id]\n  }", "service_token = [cloudflare_zero_trust_access_service_token.registry_push_soleur.id]\n    any_valid_service_token = true\n  }", 1)' || bad "M-landing: q_any"
check_not "MQ2: any_valid_service_token in the registry policy fails Q3" p_sol_policy "$SBX/q_any.tf" registry_push_service_token_soleur registry_soleur "$INC_REG"
mtf q_twoinc 's = s.replace("service_token = local.deploy_service_token_ids_soleur\n  }", "service_token = local.deploy_service_token_ids_soleur\n  }\n  include {\n    everyone = true\n  }", 1)' || bad "M-landing: q_twoinc"
check_not "MQ3: a second include block on the deploy policy fails Q1" p_sol_policy "$SBX/q_twoinc.tf" deploy_service_token_soleur deploy_soleur "$INC_DEPLOY"
mtf q_app 's = s.replace("application_id = cloudflare_zero_trust_access_application.ssh_soleur.id", "application_id = cloudflare_zero_trust_access_application.ssh.id", 1)' || bad "M-landing: q_app"
check_not "MQ4: the ci_ssh policy pointed at the OLD ssh app fails Q2" p_sol_policy "$SBX/q_app.tf" ci_ssh_service_token_soleur ssh_soleur "$INC_SSH"
mtf q_dur 's = s.replace("domain           = \"ssh.${var.app_domain_base}\"\n  type             = \"self_hosted\"\n  session_duration = \"15m\"", "domain           = \"ssh.${var.app_domain_base}\"\n  type             = \"self_hosted\"\n  session_duration = \"24h\"", 1)' || bad "M-landing: q_dur"
check_not "MQ5: a 24h session on the ssh_soleur app fails Q5" p_sol_app "$SBX/q_dur.tf" ssh_soleur ssh 15m
mtf q_zone 's = s.replace("resource \"cloudflare_zero_trust_access_policy\" \"registry_push_service_token_soleur\" {\n  account_id     = local.cf_soleur_account_id", "resource \"cloudflare_zero_trust_access_policy\" \"registry_push_service_token_soleur\" {\n  zone_id        = var.cf_zone_id", 1)' || bad "M-landing: q_zone"
check_not "MQ6: a zone-scoped registry policy (app/policy scope mismatch) fails Q3" p_sol_policy "$SBX/q_zone.tf" registry_push_service_token_soleur registry_soleur "$INC_REG"
mtf q_noprecond 's = s.replace("length(local.deploy_service_token_ids_soleur) > 0", "true", 1)' || bad "M-landing: q_noprecond"
check_not "MQ7: dropping the _soleur UUID precondition fails Q7" p_sol_precond "$SBX/q_noprecond.tf"

# Q9: exactly ONE access policy block across the root references each _soleur app (a second one is a second gate).
p_one_policy_per_app() { # <infra-dir> <app-name>
  local f n c=0
  for f in "$1"/*.tf; do
    while read -r n; do
      [[ -n "$n" ]] || continue
      if grep -qE "cloudflare_zero_trust_access_application\.$2\.id" <<<"$(block_of "$f" cloudflare_zero_trust_access_policy "$n")"; then c=$((c + 1)); fi
    done < <(eff "$f" | sed -nE 's/^resource[[:space:]]+"cloudflare_zero_trust_access_policy"[[:space:]]+"([^"]+)".*/\1/p')
  done
  [[ "$c" -eq 1 ]]
}
for app in deploy_soleur ssh_soleur registry_soleur; do
  check   "Q9/$app: exactly one access policy block in apps/web-platform/infra/*.tf references $app" p_one_policy_per_app "$INFRA" "$app"
done
rm -rf "$SBX/rootq9"; mkdir -p "$SBX/rootq9"; cp "$INFRA"/*.tf "$SBX/rootq9/"
printf 'resource "cloudflare_zero_trust_access_policy" "deploy_open" {\n  account_id     = local.cf_soleur_account_id\n  application_id = cloudflare_zero_trust_access_application.deploy_soleur.id\n  name           = "x"\n  decision       = "bypass"\n  precedence     = 2\n\n  include {\n    everyone = true\n  }\n}\n' > "$SBX/rootq9/zz-extra.tf"
check_not "MQ9: a second policy on deploy_soleur in another root file fails Q9" p_one_policy_per_app "$SBX/rootq9" deploy_soleur

# Q10: each _soleur CNAME waits for its own Access policy, so a failed Access create leaves the host unrouted.
DNS="$INFRA/dns.tf"
p_rec_dep() { # <dns.tf> <record> <policy>
  local b; b="$(block_of "$1" cloudflare_record "$2" | tr -d '\n')"
  grep -qE "depends_on[[:space:]]*=[[:space:]]*\[[[:space:]]*cloudflare_zero_trust_access_policy\.$3[[:space:]]*\]" <<<"$b"
}
check     "Q10a: cloudflare_record.deploy_soleur depends on deploy_service_token_soleur" p_rec_dep "$DNS" deploy_soleur deploy_service_token_soleur
check     "Q10b: cloudflare_record.ssh_soleur depends on ci_ssh_service_token_soleur" p_rec_dep "$DNS" ssh_soleur ci_ssh_service_token_soleur
check     "Q10c: cloudflare_record.registry_soleur depends on registry_push_service_token_soleur" p_rec_dep "$DNS" registry_soleur registry_push_service_token_soleur
python3 -c 'import sys; s = open(sys.argv[1]).read(); t = s.replace("\n  depends_on = [cloudflare_zero_trust_access_policy.ci_ssh_service_token_soleur]\n", "\n", 1); assert t != s; open(sys.argv[2], "w").write(t)' "$DNS" "$SBX/dns-nodep.tf" || bad "M-landing: dns-nodep"
check_not "MQ10: dropping the ssh_soleur record's depends_on fails Q10b" p_rec_dep "$SBX/dns-nodep.tf" ssh_soleur ci_ssh_service_token_soleur

# Q11: neither registry Doppler secret can write an empty token value over prd.
p_dop_nonempty() { # <tf> <secret-name> <attr>
  local b; b="$(block_of "$1" doppler_secret "$2" | tr -d '\n')"
  grep -qE "precondition[[:space:]]*\{[[:space:]]*condition[[:space:]]*=[[:space:]]*(nonsensitive\()?cloudflare_zero_trust_access_service_token\.registry_push_soleur\.$3[[:space:]]*!=[[:space:]]*\"\"" <<<"$b"
}
check     "Q11a: doppler_secret.registry_push_access_token_id refuses an empty client_id" p_dop_nonempty "$TF" registry_push_access_token_id client_id
check     "Q11b: doppler_secret.registry_push_access_token_secret refuses an empty client_secret" p_dop_nonempty "$TF" registry_push_access_token_secret client_secret
mtf q_dop 's = s.replace("nonsensitive(cloudflare_zero_trust_access_service_token.registry_push_soleur.client_secret != \"\")", "true", 1)' || bad "M-landing: q_dop"
check_not "MQ11: dropping the client_secret precondition fails Q11b" p_dop_nonempty "$SBX/q_dop.tf" registry_push_access_token_secret client_secret
mtf q_dec 's = s.replace("ssh_soleur.id\n  name           = \"Allow GitHub Actions CI SSH\"\n  decision       = \"non_identity\"", "ssh_soleur.id\n  name           = \"Allow GitHub Actions CI SSH\"\n  decision       = \"bypass\"", 1)' || bad "M-landing: q_dec"
check_not "MQ12: decision bypass on the ci_ssh policy fails Q2" p_sol_policy "$SBX/q_dec.tf" ci_ssh_service_token_soleur ssh_soleur "$INC_SSH"
mtf q_type 's = s.replace("domain           = \"registry.${var.app_domain_base}\"\n  type             = \"self_hosted\"", "domain           = \"registry.${var.app_domain_base}\"\n  type             = \"ssh\"", 1)' || bad "M-landing: q_type"
check_not "MQ13: a non-self_hosted registry_soleur app fails Q6" p_sol_app "$SBX/q_type.tf" registry_soleur registry 15m
mtf q_nilok 's = s.replace(" && id != \"00000000-0000-0000-0000-000000000000\"", "", 1)' || bad "M-landing: q_nilok"
check_not "MQ14: a precondition that accepts the nil placeholder fails Q7" p_sol_precond "$SBX/q_nilok.tf"

# ── dispatch: the assertions above must have RUN (a deleted call site is otherwise a silent green) ───────────────────────
echo ""
echo "=== deploy-access-token-forget: $PASS passed, $FAIL failed ==="
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  printf '  FAIL assertion floor: %d assertions ran, the floor is %d — assertions were deleted or skipped\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
