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
# #12937 (Guard 2 of the zone-move plan; Ruled by CTO agent, 2026-11-23): the same gate covers the three policies
# (deploy / ci_ssh / registry_push) on their EXISTING addresses, each against its own committed token reference. A ROUTINE
# apply admits only a no-op or an acknowledged in-place update in the committed shape: rows H* (a create is refused, an
# acked update passes), R* the refusals (each asserting UNWEDGE), C* the committed-id read from tunnel.tf, MG* the mutation
# proof that each R row reds when its guard leaves the filter, and Q*/MQ* the static policy parity over tunnel.tf. The first
# create on the new account is the `tunnel` phase of cf-account-migrate (ADR-329), which runs its own gate.
#
# ACCESS FAMILY (the class, not one shape per round). Plan layer: every non-no-op change to a
# `cloudflare_(zero_trust_)access_(policy|application)` entry, in any module, is refused with no ack unless its
# address is in the filter's `access_family_table` (rows SP*); a gated app is an ackable change only as an in-place
# update in its committed zone-scoped shape (rows A*). Static layer: the table's keys equal the resource /
# `removed { from }` blocks of that family in apps/web-platform/infra/**/*.tf (Q12, one source: the static row
# evaluates the jq def itself). RESIDUALS this suite does NOT cover:
#   - while a ci_ssh / registry_push token is unknown (its replace), the plan cannot see an extra LITERAL id beside
#     the reference; static Q2/Q3 are the only defence there;
#   - the migration's tunnel-phase create is not judged by this gate at all (it never calls deploy_policy_gate);
#   - other Access types (groups, identity providers, organization, mTLS) and a tunnel ingress hostname or
#     DNS record that reaches an origin with no Access app at all;
#   - policy `require` / `exclude` / `session_duration` (they only narrow, or shorten a session);
#   - a module sourced from outside apps/web-platform/infra is not read statically (the plan layer still
#     refuses it: its address is not in the table).
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

MIN_ASSERTIONS=215
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
check_not() { local label="$1"; shift; if "$@"; then bad "$label"; else ok "$label"; fi; }
# INSTRUMENT SELF-TEST: drive both verdict helpers once; refuse to continue unless both counters moved.
ok  "instrument self-test (ok records)"
bad "instrument self-test (bad records) - EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
PASS=0; FAIL=0

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
# A non-nil UUID: the nil placeholder (FILL-AT-PHASE-3.1) is UUID-shaped and must not pass.
p_locals_uuid()   { grep -oE "$UUID_RE" <<<"$(eff "$1" | tr -d '\n' | grep -oE 'locals[[:space:]]*\{[[:space:]]*deploy_service_token_ids[[:space:]]*=[[:space:]]*\[[^]]*\]')" | grep -qvxF '"00000000-0000-0000-0000-000000000000"'; }
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
check     "S7: OWNER — local.deploy_service_token_ids holds at least one non-nil UUID (CI cannot know the live id; this fails while it is empty or the nil placeholder)" p_locals_uuid "$TF"

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
check     "F1: an id swap with no committed ids bound is a change AND unsafe (fail-closed; R5 / R5d judge it against the committed list)" test "$(cnt "$SBX/idswap.json" deploy_policy_changes)/$(cnt "$SBX/idswap.json" deploy_policy_unsafe)" = "1/1"
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
mtf m_noprecond 's = s.replace("precondition {\n      condition     = length(local.deploy_service_token_ids) >", "unused_block {\n      condition     = length(local.deploy_service_token_ids) >", 1)' || bad "M-landing: m_noprecond"
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

# #12937: the gate reads `$policy_counts` (the filter re-run with the committed deploy ids bound as $ids, via
# deploy_policy_counts over tunnel.tf), never the destroy guard's id-less `$counts` (G10/G11 above pin the call).
check     "G12: the gate counters come from deploy_policy_counts over THIS root's tunnel.tf and the real filter, before the gate call" bash -c '
  w="$(grep -vE "^[[:space:]]*#" "$1")"
  c="$(grep -nF "policy_counts=\"\$(deploy_policy_counts tfplan.json \"\${GITHUB_WORKSPACE}/apps/web-platform/infra/tunnel.tf\" \"\${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter-web-platform.jq\")\" || exit 1" <<<"$w" | head -1 | cut -d: -f1)"
  g="$(grep -nF "deploy_policy_gate \"\$policy_counts\"" <<<"$w" | head -1 | cut -d: -f1)"
  [[ -n "$c" && -n "$g" && "$c" -lt "$g" ]]' _ "$WF"

# ── #12937 Guard 2: the three gated policies flow through the SAME gate ──────────────────────────────────────────────────
# Each policy is judged against its OWN committed token reference: the deploy one against the id list committed in
# tunnel.tf (bound as --argjson ids), ci_ssh / registry_push against their configuration reference (their token id is
# unknown while the token is replaced). Synthesized plans only (cq-test-fixtures-synthesized-only). Every RED row that
# refuses also asserts the UNWEDGE line (CTO Amendment 3).
IDS='["00000000-0000-4000-8000-0000000000a1"]'
# The three zone-scoped policy creates in provider 4.52.7's shape (synthetic ids). A token created or replaced in the same
# apply leaves service_token ABSENT from `after` and wholly unknown in `after_unknown`.
REAL="$ROOT/tests/scripts/fixtures/tfplan-access-policy-create.json"
# The three zone-scoped app creates in the same provider's shape (synthetic zone / domain / name).
APP="$ROOT/tests/scripts/fixtures/tfplan-access-app-create.json"
# apps_add <deploy-actions> <ssh-actions> <registry-actions>: stdin plan + the three app entries (a non-create has before = after)
apps_add() {
  jq -c --slurpfile app "$APP" --argjson ad "$1" --argjson as "$2" --argjson ar "$3" '
    def ent($addr; $acts): ($app[0].resource_changes[] | select(.address == $addr)) | .change.actions = $acts
      | .change.before = (if $acts == ["create"] then null else .change.after end);
    .resource_changes += [ent("cloudflare_zero_trust_access_application.deploy"; $ad),
      ent("cloudflare_zero_trust_access_application.ssh"; $as),
      ent("cloudflare_zero_trust_access_application.registry"; $ar)]'
}
# pol_plan <deploy-actions> <ssh-actions> <registry-actions> -> the three real-shape policy entries at [0] deploy, [1] ci_ssh,
# [2] registry_push + their configuration. A non-create ci_ssh / registry entry has its token in state: its id is known.
pol_plan() {
  jq -c --slurpfile real "$REAL" --argjson ad "$1" --argjson as "$2" --argjson ar "$3" '
    def ent($addr; $acts; $tok):
      ($real[0].resource_changes[] | select(.address == $addr))
      | .change.actions = $acts
      | if $acts == ["create"] or $tok == null then .
        else .change.after.include[0].service_token = [$tok] | .change.after_unknown.include[0].service_token = [false] end
      | .change.before = (if $acts == ["create"] then null else .change.after end);
    .resource_changes = [
      ent("cloudflare_zero_trust_access_policy.deploy_service_token"; $ad; null),
      ent("cloudflare_zero_trust_access_policy.ci_ssh_service_token"; $as; "00000000-0000-4000-8000-0000000000b1"),
      ent("cloudflare_zero_trust_access_policy.registry_push_service_token"; $ar; "00000000-0000-4000-8000-0000000000b2")]
    | .configuration = $real[0].configuration' "$FIX"
}
NOOP='["no-op"]'; CRE='["create"]'; UPD='["update"]'
# scnt <plan-file> <key> [filter] -> the counter computed WITH the committed ids bound (as the workflow does)
scnt() { jq --argjson ids "$IDS" -f "${3:-$FILTER}" "$1" | jq -r --arg k "$2" '.[$k]'; }
# sgate <plan-file> <message> [filter] -> rc of the REAL gate on the (real or mutant) filter's counters; output kept
sgate() { local c; c="$(jq -c --argjson ids "$IDS" -f "${3:-$FILTER}" "$1")"; deploy_policy_gate "$c" "$2" >"$SBX/sgate.out" 2>&1; }
# sred <label> <plan-file> <message>: the gate REFUSES, and the refusal carries the UNWEDGE line
sred() { if sgate "$2" "$3"; then bad "$1 (the gate passed)"; elif grep -qF '::error::UNWEDGE:' "$SBX/sgate.out"; then ok "$1"; else bad "$1 (refused without the UNWEDGE line)"; fi; }
sp()  { pol_plan "$@" > "$SBX/sp.json"; }
spm() { pol_plan "$1" "$2" "$3" | jq -c "$4" > "$SBX/sp.json"; }   # pol_plan + one jq edit

# A create is the migration's tunnel phase; on a routine apply it is unsafe, with or without the ack.
sp "$CRE" "$CRE" "$CRE"; cp "$SBX/sp.json" "$SBX/pol-create-all.json"
sred      "H1 RED: a routine-apply create of all three gated policies is refused even with the ack (UNWEDGE)" "$SBX/pol-create-all.json" "$ACK"
check     "H1b: ... counted as 3 changes, 3 unsafe (the gate did see it)" test "$(scnt "$SBX/pol-create-all.json" deploy_policy_changes)/$(scnt "$SBX/pol-create-all.json" deploy_policy_unsafe)" = "3/3"
sp "$CRE" "$NOOP" "$NOOP"
sred      "H2 RED: a routine-apply create of the deploy policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
sred      "R1 RED: the same create WITHOUT an own-line [ack-deploy-policy] is refused (UNWEDGE)" "$SBX/sp.json" "merge: re-home the tunnel"
sp "$NOOP" "$CRE" "$NOOP"
sred      "H3 RED: a routine-apply create of the ci_ssh policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
sred      "R1c RED: the ci_ssh create without the ack is refused (UNWEDGE)" "$SBX/sp.json" "merge"
sp "$NOOP" "$NOOP" "$CRE"
sred      "H4 RED: a routine-apply create of the registry_push policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
sred      "R1d RED: the registry_push create without the ack is refused (UNWEDGE)" "$SBX/sp.json" "merge"
sp "$NOOP" "$NOOP" "$NOOP"
check     "H5 GREEN: a plan leaving all three policies unchanged passes with no ack" sgate "$SBX/sp.json" ""
check     "H5b: ... at 0 changes / 0 unsafe" test "$(scnt "$SBX/sp.json" deploy_policy_changes)/$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "0/0"
# Gate dispatch (Guard 2 row 4): ONE selector covers every address, so an update at each of the three counts once each.
sp "$UPD" "$UPD" "$UPD"; cp "$SBX/sp.json" "$SBX/pol-upd-all.json"
check     "H6 GREEN: an acknowledged in-place update of all three, each on its committed reference, passes" sgate "$SBX/pol-upd-all.json" "$ACK"
sred      "H6c RED: ... and is refused without the ack (UNWEDGE)" "$SBX/pol-upd-all.json" "merge"
check     "R4: the selector matched all three addresses: 3 changes, 0 unsafe in one synthetic plan" test "$(scnt "$SBX/pol-upd-all.json" deploy_policy_changes)/$(scnt "$SBX/pol-upd-all.json" deploy_policy_unsafe)" = "3/0"
# The real shape of a token replaced in the same apply: the policy updates in place with its service_token wholly unknown.
spm "$NOOP" "$UPD" "$UPD" '(.resource_changes[1,2].change) |= (.after.include[0] |= del(.service_token) | .after_unknown.include[0].service_token = true)'; cp "$SBX/sp.json" "$SBX/pol-upd-unk.json"
check     "H7 GREEN: an acknowledged update whose ci_ssh / registry_push token id is unknown (the token is replaced) passes" sgate "$SBX/pol-upd-unk.json" "$ACK"
check     "H7b: ... at 2 changes / 0 unsafe" test "$(scnt "$SBX/pol-upd-unk.json" deploy_policy_changes)/$(scnt "$SBX/pol-upd-unk.json" deploy_policy_unsafe)" = "2/0"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[0].change.after.include) += [{"service_token":["00000000-0000-4000-8000-0000000000a2"]}]'
sred      "R2 RED: a deploy policy update with TWO include blocks is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
check     "R2b: ... counted as unsafe" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[0].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000ff"]'
sred      "R5 RED: an update of the deploy include to an id that is NOT the committed list is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
sp "$UPD" "$NOOP" "$NOOP"
sred      "R5c RED: an in-place update of the deploy policy (committed id) without the ack is refused (UNWEDGE)" "$SBX/sp.json" "merge"
check     "R5d GREEN: the same update WITH the ack passes (an id rotation PR)" sgate "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[1].change.actions) = ["create","delete"]'
sred      "R6 RED: a replace of the ci_ssh policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[2].change.actions) = ["delete"]'
sred      "R6b RED: a delete of the registry_push policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[0].change) |= (.actions = ["forget"] | .after = null)'
sred      "R6c RED: a forget of the deploy policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
# CFG_SSH / CFG_REG: jq paths to a policy's configuration entry, by address (for edits)
CFG_SSH='(.configuration.root_module.resources[] | select(.address == "cloudflare_zero_trust_access_policy.ci_ssh_service_token"))'
CFG_REG='(.configuration.root_module.resources[] | select(.address == "cloudflare_zero_trust_access_policy.registry_push_service_token"))'
XWIRE="($CFG_SSH.expressions.include[0].service_token.references) = [\"cloudflare_zero_trust_access_service_token.registry_push.id\",\"cloudflare_zero_trust_access_service_token.registry_push\"]"
spm "$NOOP" "$UPD" "$NOOP" "$XWIRE"
sred      "R7 RED: a ci_ssh policy whose include references the REGISTRY token is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$UPD" "($CFG_REG.expressions.include[0].service_token) = {\"constant_value\":[\"00000000-0000-4000-8000-0000000000a3\"]}"
sred      "R7b RED: a registry_push policy whose include is a literal, not its token reference, is refused (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$UPD" 'del(.configuration)'
sred      "R7c RED: a plan with no configuration section cannot bind the reference, so the update is refused (fail-closed)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[1].change.after.include[0].any_valid_service_token) = true'
sred      "R8 RED: any_valid_service_token on the ci_ssh policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[0].change.after.include[0].everyone) = true'
sred      "R8b RED: everyone on the deploy policy is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
r9() { local c; c="$(jq -c -f "$FILTER" "$SBX/pol-upd-all.json")"; deploy_policy_gate "$c" "$ACK" >/dev/null 2>&1; }
check_not "R9 RED: without the committed ids bound (a caller that forgot --argjson ids) the deploy update is refused" r9

# ── deploy_policy_counts / deploy_policy_committed_ids: the ids come from the committed tunnel.tf line ────────────────────
# C1-C2b test the reader on tunnel.tf with the nil placeholder filled (a no-op once minted); Q8 judges the committed value.
NIL_ID='00000000-0000-0000-0000-000000000000'
TF_FILLED="$SBX/tunnel-filled.tf"; sed "s/\"$NIL_ID\"/\"00000000-0000-4000-8000-0000000000a1\"/" "$TF" > "$TF_FILLED"
c1() { local o; o="$(deploy_policy_committed_ids "$TF_FILLED" 2>/dev/null)" && jq -e 'type == "array" and length > 0' <<<"$o" >/dev/null; }
check     "C1: deploy_policy_committed_ids reads ONE UUID list from tunnel.tf (the line the precondition also reads; placeholder filled)" c1
c2() {
  local ids c; ids="$(deploy_policy_committed_ids "$TF_FILLED" 2>/dev/null)" || return 1
  pol_plan "$UPD" "$NOOP" "$NOOP" | jq --argjson ids "$ids" '(.resource_changes[0].change.after.include[0].service_token) = $ids' > "$SBX/c2.json"
  c="$(deploy_policy_counts "$SBX/c2.json" "$TF_FILLED" "$FILTER" 2>/dev/null)" || return 1
  [[ "$(jq -r .deploy_policy_unsafe <<<"$c")/$(jq -r .deploy_policy_changes <<<"$c")" == "0/1" ]]
}
check     "C2: deploy_policy_counts binds the committed ids, so an update to the committed list is counted and not unsafe" c2
c2b() { pol_plan "$UPD" "$NOOP" "$NOOP" | jq '(.resource_changes[0].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000ee"]' > "$SBX/c2b.json"; [[ "$(deploy_policy_counts "$SBX/c2b.json" "$TF_FILLED" "$FILTER" 2>/dev/null | jq -r .deploy_policy_unsafe)" == "1" ]]; }
check     "C2b: ... and a planned id that is not the committed one is unsafe through the same helper" c2b
cids() { deploy_policy_committed_ids "$1" >/dev/null 2>&1; }
printf 'locals {\n  deploy_service_token_ids = ["00000000-0000-4000-8000-0000000000a1"] # trailing note\n}\n' > "$SBX/ids-ok.tf"
check     "C3: a trailing # comment on the committed line is allowed" cids "$SBX/ids-ok.tf"
printf 'locals {\n  # deploy_service_token_ids = ["00000000-0000-4000-8000-0000000000a1"]\n}\n' > "$SBX/ids-commented.tf"
check_not "C4: a commented-out declaration is no declaration (fail-closed)" cids "$SBX/ids-commented.tf"
printf '  deploy_service_token_ids = ["00000000-0000-4000-8000-0000000000a1"]\n  deploy_service_token_ids = ["00000000-0000-4000-8000-0000000000a2"]\n' > "$SBX/ids-twice.tf"
check_not "C5: two declarations are refused" cids "$SBX/ids-twice.tf"
printf '  deploy_service_token_ids = ["not-a-uuid"]\n' > "$SBX/ids-bad.tf"
check_not "C6: a non-UUID entry is refused" cids "$SBX/ids-bad.tf"
printf '  deploy_service_token_ids = ["%s"] # FILL-AT-PHASE-3.1\n' "$NIL_ID" > "$SBX/ids-nil.tf"
c6b() { ! deploy_policy_committed_ids "$SBX/ids-nil.tf" >"$SBX/c6b.out" 2>&1 && grep -qF 'placeholder deploy token id still committed (FILL-AT-PHASE-3.1)' "$SBX/c6b.out"; }
check     "C6b: the nil-UUID placeholder is refused, with the FILL-AT-PHASE-3.1 message" c6b
printf '  deploy_service_token_ids = []\n' > "$SBX/ids-empty.tf"
check_not "C7: an empty list is refused" cids "$SBX/ids-empty.tf"
printf '  deploy_service_token_ids = var.x\n' > "$SBX/ids-var.tf"
check_not "C8: a non-literal expression is refused" cids "$SBX/ids-var.tf"
check_not "C9: deploy_policy_counts refuses when the ids cannot be read" deploy_policy_counts "$SBX/pol-create-all.json" "$SBX/ids-bad.tf" "$FILTER"

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
# Drops the selector from deploy_policy_changes only (dropping the table itself trips the allowlist counter instead).
mfilter f_nosel 's = s.replace("         | select(IN(.address; access_gated_addrs[]))\n         | select(.change.actions != [\"no-op\"]) ]", "         | select(false) ]", 1)' || bad "M-landing: f_nosel"
sp "$UPD" "$NOOP" "$NOOP"
check     "MG1: with the gated addresses dropped from the selector, R5c's un-acked update would PASS (R5c depends on the selector)" sgate "$SBX/sp.json" "merge" "$SBX/f_nosel.jq"
check_not "MG1b: ... and R4's three-address count would not hold" test "$(scnt "$SBX/pol-upd-all.json" deploy_policy_changes "$SBX/f_nosel.jq")" = "3"
mfilter f_noref 's = s.replace("    elif (access_policy_ref_ok($plan; .address) | not) then true\n", "", 1)' || bad "M-landing: f_noref"
spm "$NOOP" "$UPD" "$NOOP" "$XWIRE"
check     "MG2: without the reference binding, R7's cross-wired ci_ssh policy would PASS" sgate "$SBX/sp.json" "$ACK" "$SBX/f_noref.jq"
mfilter f_noids 's = s.replace("      or (($inc[0].service_token? // null) != $ids)\n", "", 1)' || bad "M-landing: f_noids"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[0].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000ff"]'
check     "MG3: without the id-equality check, R5's wrong-id update would PASS" sgate "$SBX/sp.json" "$ACK" "$SBX/f_noids.jq"
mfilter f_noinc 's = s.replace("    elif ($inc | type) != \"array\" or ($inc | length) != 1 or ($inc[0] | type) != \"object\" then true\n", "", 1)' || bad "M-landing: f_noinc"
spm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[1].change.after.include) += [{"service_token":[null]}]'
check     "MG4: without the one-include check, a ci_ssh update with two include blocks would PASS" sgate "$SBX/sp.json" "$ACK" "$SBX/f_noinc.jq"
check_not "MG4b: ... and the real filter refuses that same plan" sgate "$SBX/sp.json" "$ACK"
mfilter f_nodel 's = s.replace("    elif $act != [\"update\"] then true\n", "", 1)' || bad "M-landing: f_nodel"
spm "$NOOP" "$NOOP" "$NOOP" '(.resource_changes[2].change.actions) = ["delete"]'
check     "MG5: without the update-only rule, R6b's registry_push delete would PASS with the ack" sgate "$SBX/sp.json" "$ACK" "$SBX/f_nodel.jq"
sp "$NOOP" "$CRE" "$NOOP"; jq -c '(.resource_changes[1].change.after.include[0].service_token) = ["00000000-0000-4000-8000-0000000000b1"] | (.resource_changes[1].change.after_unknown.include[0].service_token) = [false]' "$SBX/sp.json" > "$SBX/pol-create-known.json"
check     "MG5b: ... and so would a create in the committed shape (H3 depends on the same rule)" sgate "$SBX/pol-create-known.json" "$ACK" "$SBX/f_nodel.jq"
check_not "MG5c: ... which the real filter refuses" sgate "$SBX/pol-create-known.json" "$ACK"
# Harness row: feeding a plan with no updates (the canonical forget fixture) to the update rows must red them.
check_not "MG6: the forget fixture (one no-op policy) does not satisfy R4's 3/0 count" test "$(scnt "$FIX" deploy_policy_changes)/$(scnt "$FIX" deploy_policy_unsafe)" = "3/0"

# ── the real provider shape, include allowlist, decision, and policies outside the table ─────────────────────────────
p5() { jq -e '[.resource_changes[] | select(.address | test("(ci_ssh|registry_push)_service_token$")) | .change
  | (.after.include[0] | has("service_token") | not) and (.after_unknown.include[0].service_token == true)] == [true, true]' "$REAL" >/dev/null; }
check     "P5: the policy fixture keeps the provider's shape: ci_ssh / registry_push service_token absent from after, wholly unknown" p5
spm "$NOOP" "$NOOP" "$UPD" "($CFG_REG.expressions.include[0].service_token.references) = [\"cloudflare_zero_trust_access_service_token.ci_ssh.id\",\"cloudflare_zero_trust_access_service_token.ci_ssh\"]"
sred      "R7d RED: a registry_push policy update cross-wired to ci_ssh.id is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
check     "R7e: ... counted as unsafe (1)" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
spm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[1].change.after.include[0].ip) = ["0.0.0.0/0"]'; cp "$SBX/sp.json" "$SBX/inc-ip.json"
sred      "R11 RED: an ip include beside the ci_ssh token is refused even with the ack (UNWEDGE)" "$SBX/inc-ip.json" "$ACK"
spm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[0].change.after.include[0].email_domain) = ["example.com"]'
sred      "R11b RED: an email_domain include beside the deploy ids is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$NOOP" "$UPD" '(.resource_changes[2].change.after.include[0].certificate) = true'
sred      "R11c RED: certificate = true on the registry_push include is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[1].change.after_unknown.include[0].ip) = true'
sred      "R11d RED: an include key other than service_token that is unknown at plan time is refused (UNWEDGE)" "$SBX/sp.json" "$ACK"
spm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[1].change.after.decision) = "bypass"'; cp "$SBX/sp.json" "$SBX/dec-bypass.json"
sred      "R12 RED: decision bypass on the ci_ssh policy is refused even with the ack (UNWEDGE)" "$SBX/dec-bypass.json" "$ACK"
spm "$UPD" "$NOOP" "$NOOP" 'del(.resource_changes[0].change.after.decision) | (.resource_changes[0].change.after_unknown.decision) = true'
sred      "R12b RED: a decision unknown at plan time is refused (UNWEDGE)" "$SBX/sp.json" "$ACK"
mfilter f_nounk 's = s.replace("    elif (($unk[0].service_token? // false) == true) then false\n", "", 1)' || bad "M-landing: f_nounk"
check_not "MG7: without the unknown-token arm, H7's real-shape token-replace update is refused with the ack" sgate "$SBX/pol-upd-unk.json" "$ACK" "$SBX/f_nounk.jq"
check     "MG7b: ... because ci_ssh and registry_push read as unsafe (2)" test "$(scnt "$SBX/pol-upd-unk.json" deploy_policy_unsafe "$SBX/f_nounk.jq")" = "2"
mfilter f_noallow 's = s.replace("    elif ($inc[0] | to_entries | any(.key != \"service_token\" and (.value | deploy_policy_blank | not))) then true\n", "", 1)' || bad "M-landing: f_noallow"
check     "MG8: without the include allowlist, R11's ip include would PASS with the ack" sgate "$SBX/inc-ip.json" "$ACK" "$SBX/f_noallow.jq"
mfilter f_nodec 's = s.replace("    elif ((.change.after // {}).decision? // null) != \"non_identity\" then true\n", "", 1)' || bad "M-landing: f_nodec"
check     "MG9: without the decision check, R12's bypass would PASS with the ack" sgate "$SBX/dec-bypass.json" "$ACK" "$SBX/f_nodec.jq"
# stray <address> <application_id-expression-json|null>: a NEW bypass + everyone policy at <address> (real ci_ssh shape) with
# its configuration entry; null leaves application_id out (a reusable policy). A module address gets no root configuration.
stray() {
  jq -c --arg addr "$1" --argjson app "$2" '
    ($addr | capture("^(?<m>(module\\.[^.]+\\.)*)(?<t>[^.]+)\\.(?<n>.+)$")) as $p
    | (.resource_changes[] | select(.address == "cloudflare_zero_trust_access_policy.ci_ssh_service_token")) as $t
    | (.configuration.root_module.resources[] | select(.address == "cloudflare_zero_trust_access_policy.ci_ssh_service_token")) as $c
    | .resource_changes += [$t | .address = $addr | .type = $p.t | .name = $p.n | .change.actions = ["create"]
        | .change.after.decision = "bypass" | .change.after.include[0].everyone = true | .change.after_unknown.include[0] |= del(.service_token)]
    | if $p.m != "" then . else .configuration.root_module.resources += [$c | .address = $addr | .type = $p.t | .name = $p.n
        | .expressions.include = [{"everyone": {"constant_value": true}}]
        | if $app == null then .expressions |= del(.application_id) else .expressions.application_id = $app end] end'
}
refs() { printf '{"references":["cloudflare_zero_trust_access_application.%s.id","cloudflare_zero_trust_access_application.%s"]}' "$1" "$1"; }
ZTP=cloudflare_zero_trust_access_policy
pol_plan "$NOOP" "$NOOP" "$NOOP" > "$SBX/pol-noop.json"
stray "$ZTP.deploy_open" "$(refs deploy)" < "$SBX/pol-noop.json" > "$SBX/stray-deploy.json"
check     "S8: a NEW policy outside the table on deploy is unsafe (1) at 0 table changes" test "$(scnt "$SBX/stray-deploy.json" deploy_policy_changes)/$(scnt "$SBX/stray-deploy.json" deploy_policy_unsafe)" = "0/1"
sred      "S8c RED: ... and the gate refuses it WITH the ack (UNWEDGE)" "$SBX/stray-deploy.json" "$ACK"
stray "$ZTP.ssh_open" '{"references":["cloudflare_zero_trust_access_application.ssh.id"]}' < "$SBX/pol-noop.json" > "$SBX/stray-ssh.json"
check     "S8d: a stray on ssh referenced by .id alone is unsafe too" test "$(scnt "$SBX/stray-ssh.json" deploy_policy_unsafe)" = "1"
stray "$ZTP.reg_open" "$(refs registry)" < "$SBX/pol-noop.json" > "$SBX/stray-reg.json"
check     "S8e: a stray on registry is unsafe" test "$(scnt "$SBX/stray-reg.json" deploy_policy_unsafe)" = "1"
stray "$ZTP.ssh_second" "$(refs ssh)" < "$SBX/pol-noop.json" | jq -c '(.resource_changes[-1].change.after.decision) = "non_identity" | (.resource_changes[-1].change.after.include[0].everyone) = null' > "$SBX/stray-second.json"
check     "S8f: a NEW non_identity policy on the ssh app is outside the table too (1 unsafe)" test "$(scnt "$SBX/stray-second.json" deploy_policy_unsafe)" = "1"
jq -c '(.resource_changes[-1].change.actions) = ["no-op"]' "$SBX/stray-deploy.json" > "$SBX/stray-noop.json"
check     "S8g: the counter judges changes only: an unchanged stray already in state counts 0 (static Q12 owns its block)" test "$(scnt "$SBX/stray-noop.json" deploy_policy_unsafe)" = "0"
# The five security-review sibling shapes, each refused by the allowlist whatever binds it to the host.
stray "cloudflare_access_policy.deploy_open" "$(refs deploy)" < "$SBX/pol-noop.json" > "$SBX/sp1.json"
sred      "SP1 RED: the legacy type name cloudflare_access_policy on deploy is refused even with the ack (UNWEDGE)" "$SBX/sp1.json" "$ACK"
stray "$ZTP.via_local" '{"references":["local.deploy_app.id","local.deploy_app"]}' < "$SBX/pol-noop.json" > "$SBX/sp2.json"
sred      "SP2 RED: a policy whose application_id is a local is refused even with the ack (UNWEDGE)" "$SBX/sp2.json" "$ACK"
stray "$ZTP.via_literal" '{"constant_value":"00000000000000000000000000000abc"}' < "$SBX/pol-noop.json" > "$SBX/sp3.json"
sred      "SP3 RED: a policy whose application_id is a literal app id is refused even with the ack (UNWEDGE)" "$SBX/sp3.json" "$ACK"
HOOKS_APP='{"address":"cloudflare_zero_trust_access_application.deploy_hooks","mode":"managed","type":"cloudflare_zero_trust_access_application","name":"deploy_hooks"}'
jq -c --slurpfile app "$APP" --argjson h "$HOOKS_APP" '.resource_changes += [($app[0].resource_changes[0] | . + $h | .change.after.domain = "deploy.example.com/hooks")]' "$SBX/pol-noop.json" > "$SBX/sp4-app.json"
check     "SP4b: a NEW app on a more specific path of deploy. is unsafe on its own (1)" test "$(scnt "$SBX/sp4-app.json" deploy_policy_unsafe)" = "1"
stray "$ZTP.hooks_open" "$(refs deploy_hooks)" < "$SBX/sp4-app.json" > "$SBX/sp4.json"
check     "SP4: ... and with its bypass + everyone policy both are unsafe (2)" test "$(scnt "$SBX/sp4.json" deploy_policy_unsafe)" = "2"
sred      "SP4c RED: ... and the gate refuses it even with the ack (UNWEDGE)" "$SBX/sp4.json" "$ACK"
stray "$ZTP.reusable" null < "$SBX/pol-noop.json" > "$SBX/sp5-pol.json"
check     "SP5b: a reusable policy (no application_id) is unsafe on its own (1)" test "$(scnt "$SBX/sp5-pol.json" deploy_policy_unsafe)" = "1"
apps_add "$UPD" "$NOOP" "$NOOP" < "$SBX/sp5-pol.json" | jq -c '(.resource_changes[-3].change) |= (del(.after.policies) | .after_unknown.policies = true)' > "$SBX/sp5.json"
check     "SP5: ... and attached through deploy's policies both are unsafe (2)" test "$(scnt "$SBX/sp5.json" deploy_policy_unsafe)" = "2"
sred      "SP5c RED: ... and the gate refuses it even with the ack (UNWEDGE)" "$SBX/sp5.json" "$ACK"
stray "module.m.$ZTP.deploy_service_token" null < "$SBX/pol-noop.json" > "$SBX/sp6.json"
check     "SP6: a policy in a MODULE, even under a table name, is unsafe (1)" test "$(scnt "$SBX/sp6.json" deploy_policy_unsafe)" = "1"
stray "$ZTP.ci_ssh_service_token[1]" "$(refs ssh)" < "$SBX/pol-noop.json" > "$SBX/sp6b.json"
check     "SP6b: an indexed sibling of a table address is unsafe (1)" test "$(scnt "$SBX/sp6b.json" deploy_policy_unsafe)" = "1"
fam() { jq -c --arg a "$1" --argjson acts "$2" '($a | split(".")) as $p | .resource_changes += [{"address":$a,"mode":"managed","type":$p[0],"name":$p[1],"change":{"actions":$acts,"before":{"domain":"deploy.example.com"},"after":(if $acts == ["forget"] then null else {"domain":"deploy.example.com"} end),"after_unknown":{}}}]' "$SBX/pol-noop.json"; }
fam cloudflare_zero_trust_access_application.deploy '["delete","create"]' > "$SBX/sp7.json"
check     "SP7: a replace (re-create) of a gated app is unsafe (1)" test "$(scnt "$SBX/sp7.json" deploy_policy_unsafe)" = "1"
fam "$ZTP.ci_ssh_service_token" '["update"]' > "$SBX/sp7b.json"
check     "SP7b: an in-place update of a gated policy that plans no include is unsafe (1)" test "$(scnt "$SBX/sp7b.json" deploy_policy_unsafe)" = "1"
fam cloudflare_zero_trust_access_application.ssh '["forget"]' > "$SBX/sp7c.json"
check     "SP7c: a planned forget of a gated app is unsafe (1): only the migration's state step removes one" test "$(scnt "$SBX/sp7c.json" deploy_policy_unsafe)" = "1"
jq -c '.resource_changes += [{"address":"data.cloudflare_zero_trust_access_application.x","mode":"data","type":"cloudflare_zero_trust_access_application","name":"x","change":{"actions":["read"],"before":null,"after":{}}}]' "$SBX/pol-noop.json" > "$SBX/sp8.json"
check     "SP8: a data-source read of the family is not a change (0)" test "$(scnt "$SBX/sp8.json" deploy_policy_unsafe)" = "0"
mfilter f_noallowlist 's = s.replace("      + access_family_unsafe\n", "\n", 1)' || bad "M-landing: f_noallowlist"
check     "MG10: without the allowlist counter, S8's bypass-everyone policy on deploy would PASS with no ack" sgate "$SBX/stray-deploy.json" "" "$SBX/f_noallowlist.jq"
check     "MG10b: ... and SP1's legacy-type policy would PASS with no ack" sgate "$SBX/sp1.json" "" "$SBX/f_noallowlist.jq"

# ── the gated apps: an ackable change only as an in-place update in the committed zone-scoped shape (APP fixture) ────────
p_app_fx() { jq -e '[.resource_changes[].change | (.after | .zone_id == "z" and .policies == null and .options_preflight_bypass == false and .self_hosted_domains == null and .destinations == [] and .cors_headers == []) and .after_unknown.account_id == true] == [true, true, true]' "$APP" >/dev/null; }
check     "A0: the app fixture keeps the provider's zone-scoped create shape (zone known, account unknown, policies/self_hosted_domains null, preflight false, [] blocks)" p_app_fx
sp "$CRE" "$CRE" "$CRE"; apps_add "$CRE" "$CRE" "$CRE" < "$SBX/sp.json" > "$SBX/merge-first.json"
check     "A1: a routine-apply first create (3 apps + 3 policies) counts 6 changes / 6 unsafe" test "$(scnt "$SBX/merge-first.json" deploy_policy_changes)/$(scnt "$SBX/merge-first.json" deploy_policy_unsafe)" = "6/6"
sred      "A1b RED: ... refused WITH [ack-deploy-policy]: the first create is the migration's tunnel phase (UNWEDGE)" "$SBX/merge-first.json" "$ACK"
sred      "A1c RED: ... and refused without it (UNWEDGE)" "$SBX/merge-first.json" "merge"
# apm <deploy> <ssh> <registry> <jq-edit>: the no-op policies + the three apps; apps sit at [-3] deploy, [-2] ssh, [-1] registry
apm() { apps_add "$1" "$2" "$3" < "$SBX/pol-noop.json" | jq -c "$4" > "$SBX/sp.json"; }
apm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[-3].change.after.options_preflight_bypass, .resource_changes[-3].change.before.options_preflight_bypass) = true'; cp "$SBX/sp.json" "$SBX/app-preflight.json"
sred      "A2 RED: a deploy app update holding options_preflight_bypass = true is refused even with the ack (UNWEDGE)" "$SBX/app-preflight.json" "$ACK"
apm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[-3].change.after.session_duration) = "12h"'; cp "$SBX/sp.json" "$SBX/app-dur.json"
check     "A3: an in-place session_duration update of the deploy app is an ackable change (1/0)" test "$(scnt "$SBX/app-dur.json" deploy_policy_changes)/$(scnt "$SBX/app-dur.json" deploy_policy_unsafe)" = "1/0"
check     "A3a GREEN: ... and passes with the ack" sgate "$SBX/app-dur.json" "$ACK"
sred      "A3b RED: ... refused without the ack (UNWEDGE)" "$SBX/app-dur.json" "merge"
apm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[-3].change.after.domain) = "deploy.example.org"'; cp "$SBX/sp.json" "$SBX/app-dom.json"
sred      "A4 RED: a domain change on the deploy app is refused even with the ack (UNWEDGE)" "$SBX/app-dom.json" "$ACK"
apm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[-2].change.after.domain) = "deploy.example.com"'
sred      "A4b RED: an ssh app update onto another host is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
apm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[-3].change.after.domain) = "deploy.example.com/hooks"'
sred      "A4c RED: a deploy app update onto a path is refused even with the ack (UNWEDGE)" "$SBX/sp.json" "$ACK"
apm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[-3].change) |= (del(.after.policies) | .after_unknown.policies = true)'; cp "$SBX/sp.json" "$SBX/app-polunk.json"
sred      "A5 RED: policies unknown at plan time on the deploy app is refused even with the ack (UNWEDGE)" "$SBX/app-polunk.json" "$ACK"
while IFS='|' read -r k v; do
  apm "$NOOP" "$NOOP" "$UPD" "(.resource_changes[-1].change.after.$k) = $v"
  check   "A6/$k: a registry app update setting $k is unsafe (1)" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
done <<'ROWS'
policies|["p"]
self_hosted_domains|["registry.example.com"]
destinations|[{"uri":"registry.example.com/x"}]
cors_headers|[{"allow_all_origins":true}]
type|"ssh"
ROWS
for acts in '["create"]' '["delete"]' '["forget"]' '["create","delete"]'; do
  apm "$NOOP" "$acts" "$NOOP" '.'
  check   "A7/$acts: ssh app $acts is unsafe (the host would sit behind the tunnel ungated)" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
done
# The zone-scoped pin: the apps take var.cf_zone_id, so a planned zone that moves, is unknown or is absent is off-shape.
apm "$UPD" "$NOOP" "$NOOP" '(.resource_changes[-3].change.after.zone_id) = "y"'
check     "A8: a zone_id change on the deploy app is unsafe (1)" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
apm "$NOOP" "$UPD" "$NOOP" '(.resource_changes[-2].change) |= (del(.after.zone_id) | .after_unknown.zone_id = true)'
check     "A8b: a zone_id unknown at plan time on the ssh app is unsafe (1)" test "$(scnt "$SBX/sp.json" deploy_policy_unsafe)" = "1"
apm "$NOOP" "$NOOP" "$UPD" '(.resource_changes[-1].change.after.zone_id, .resource_changes[-1].change.before.zone_id) = null'; cp "$SBX/sp.json" "$SBX/app-nozone.json"
check     "A8c: a registry app with no zone_id (account-scoped) is unsafe (1)" test "$(scnt "$SBX/app-nozone.json" deploy_policy_unsafe)" = "1"
mfilter f_nozone 's = s.replace("    elif ($a.zone_id | type) != \"string\" or $a.zone_id == \"\" then true\n", "", 1)' || bad "M-landing: f_nozone"
check     "MA6: without the zone-scoped arm, A8c's account-scoped app would PASS with the ack" sgate "$SBX/app-nozone.json" "$ACK" "$SBX/f_nozone.jq"
mfilter f_noappshape 's = s.replace("\n        or ($role == \"gated_app\" and access_app_unsafe)) ]", ") ]", 1)' || bad "M-landing: f_noappshape"
check     "MA1: without the app shape arm, A2's preflight bypass would PASS with the ack" sgate "$SBX/app-preflight.json" "$ACK" "$SBX/f_noappshape.jq"
mfilter f_noappsel 's = s.replace("def access_gated_addrs: access_policy_addrs + access_gated_apps;", "def access_gated_addrs: access_policy_addrs;", 1)' || bad "M-landing: f_noappsel"
check     "MA2: without the apps in the changes selector, A3's update would PASS with no ack" sgate "$SBX/app-dur.json" "merge" "$SBX/f_noappsel.jq"
mfilter f_noappeq 's = s.replace("    elif any(access_app_keys[]; . as $k | $a[$k] != $b[$k]?) then true\n", "", 1)' || bad "M-landing: f_noappeq"
check     "MA3: without the update-equality arm, A4's domain change would PASS with the ack" sgate "$SBX/app-dom.json" "$ACK" "$SBX/f_noappeq.jq"
mfilter f_noappblank 's = s.replace("    elif any(access_app_keys[3:][]; . as $k | $a[$k] | deploy_policy_blank | not) then true\n", "", 1)' || bad "M-landing: f_noappblank"
check     "MA4: without the blank-keys arm, A2's preflight bypass would PASS with the ack" sgate "$SBX/app-preflight.json" "$ACK" "$SBX/f_noappblank.jq"
mfilter f_noappunk 's = s.replace("    elif any(access_app_keys[]; . as $k | $u[$k] | deploy_policy_has_true) then true\n", "", 1)' || bad "M-landing: f_noappunk"
check     "MA5: without the unknown arm, A5's unknown policies would PASS with the ack" sgate "$SBX/app-polunk.json" "$ACK" "$SBX/f_noappunk.jq"

# ── #12937 static policy parity over tunnel.tf: each gated policy is bound to its own app and its own token ───────────────
# p_gated_policy <tf> <policy-name> <app-name> <include-ERE>: zone-scoped (var.cf_zone_id, no account_id), application_id = its
# OWN app, exactly one include holding only its own token, no any_valid_service_token / everyone anywhere in the block.
p_gated_policy() {
  local b; b="$(block_of "$1" cloudflare_zero_trust_access_policy "$2" | tr -d '\n')"
  [[ -n "$b" ]] || return 1
  grep -qE "(^|[^_a-z])zone_id[[:space:]]*=[[:space:]]*var\.cf_zone_id" <<<"$b" || return 1
  if grep -qE '(^|[^_a-z])account_id[[:space:]]*=' <<<"$b"; then return 1; fi
  grep -qE "application_id[[:space:]]*=[[:space:]]*cloudflare_zero_trust_access_application\.$3\.id" <<<"$b" || return 1
  [[ "$(grep -oE 'include[[:space:]]*\{' <<<"$b" | wc -l)" -eq 1 ]] || return 1
  grep -qE "include[[:space:]]*\{[[:space:]]*service_token[[:space:]]*=[[:space:]]*$4[[:space:]]*\}" <<<"$b" || return 1
  grep -qE 'decision[[:space:]]*=[[:space:]]*"non_identity"' <<<"$b" || return 1
  [[ "$(grep -oE 'decision[[:space:]]*=' <<<"$b" | wc -l)" -eq 1 ]] || return 1
  ! grep -qE 'any_valid_service_token|everyone' <<<"$b"
}
p_gated_app() { # <tf> <app-name> <host> <duration>
  local b d='\.\$\{var\.app_domain_base\}"'; b="$(block_of "$1" cloudflare_zero_trust_access_application "$2" | tr -d '\n')"
  [[ -n "$b" ]] || return 1
  grep -qE "(^|[^_a-z])zone_id[[:space:]]*=[[:space:]]*var\.cf_zone_id" <<<"$b" || return 1
  if grep -qE '(^|[^_a-z])account_id[[:space:]]*=' <<<"$b"; then return 1; fi
  grep -qE "(^|[^_a-z])domain[[:space:]]*=[[:space:]]*\"$3$d" <<<"$b" || return 1
  grep -qE "session_duration[[:space:]]*=[[:space:]]*\"$4\"" <<<"$b" || return 1
  grep -qE 'type[[:space:]]*=[[:space:]]*"self_hosted"' <<<"$b" || return 1
  [[ "$(grep -oE '(^|[^_a-z])type[[:space:]]*=' <<<"$b" | wc -l)" -eq 1 ]] || return 1
  if grep -qE '(^|[^_])policies[[:space:]]*=' <<<"$b"; then return 1; fi
  # gate-shaping keys the committed apps never set (an OPTIONS bypass, extra hosts, destinations, CORS)
  if grep -qE '(^|[^_a-z])(options_preflight_bypass|self_hosted_domains|destinations|cors_headers)[[:space:]]*(=|\{)' <<<"$b"; then return 1; fi
  return 0
}
p_gated_precond() { local b; b="$(block_of "$1" cloudflare_zero_trust_access_policy deploy_service_token)"; grep -qF 'length(local.deploy_service_token_ids) > 0' <<<"$b" && grep -qF '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$b" && grep -qF "&& id != \"$NIL_ID\"" <<<"$b"; }
INC_DEPLOY='local\.deploy_service_token_ids'
INC_SSH='\[cloudflare_zero_trust_access_service_token\.ci_ssh\.id\]'
INC_REG='\[cloudflare_zero_trust_access_service_token\.registry_push\.id\]'
check     "Q1: deploy_service_token is zone-scoped, non_identity, bound to the deploy app and to local.deploy_service_token_ids only" p_gated_policy "$TF" deploy_service_token deploy "$INC_DEPLOY"
check     "Q2: ci_ssh_service_token is zone-scoped, bound to the ssh app and to the ci_ssh token only" p_gated_policy "$TF" ci_ssh_service_token ssh "$INC_SSH"
check     "Q3: registry_push_service_token is zone-scoped, bound to the registry app and to the registry_push token only" p_gated_policy "$TF" registry_push_service_token registry "$INC_REG"
check     "Q4: the deploy app is zone-scoped, self_hosted, deploy.<base>, 24h" p_gated_app "$TF" deploy deploy 24h
check     "Q5: the ssh app is zone-scoped, self_hosted, ssh.<base>, 15m" p_gated_app "$TF" ssh ssh 15m
check     "Q6: the registry app is zone-scoped, self_hosted, registry.<base>, 15m" p_gated_app "$TF" registry registry 15m
check     "Q7: the deploy policy's UUID precondition reads its own local and refuses the nil placeholder" p_gated_precond "$TF"
# OWNER (draft state): RED until the minted deploy token id replaces the nil placeholder (CI cannot know the live id).
if grep -qF "\"$NIL_ID\"" <<<"$(eff "$TF" | grep -E '^[[:space:]]*deploy_service_token_ids[[:space:]]*=')"; then
  bad "Q8: placeholder deploy token id still committed (FILL-AT-PHASE-3.1)"
else
  check   "Q8: the committed deploy id list is a UUID list holding a minted id" cids "$TF"
fi
mtf q_xwire 's = s.replace("service_token = [cloudflare_zero_trust_access_service_token.ci_ssh.id]", "service_token = [cloudflare_zero_trust_access_service_token.registry_push.id]", 1)' || bad "M-landing: q_xwire"
check_not "MQ1: a ci_ssh policy cross-wired to the registry token fails Q2" p_gated_policy "$SBX/q_xwire.tf" ci_ssh_service_token ssh "$INC_SSH"
mtf q_any 's = s.replace("service_token = [cloudflare_zero_trust_access_service_token.registry_push.id]\n  }", "service_token = [cloudflare_zero_trust_access_service_token.registry_push.id]\n    any_valid_service_token = true\n  }", 1)' || bad "M-landing: q_any"
check_not "MQ2: any_valid_service_token in the registry policy fails Q3" p_gated_policy "$SBX/q_any.tf" registry_push_service_token registry "$INC_REG"
mtf q_twoinc 's = s.replace("service_token = local.deploy_service_token_ids\n  }", "service_token = local.deploy_service_token_ids\n  }\n  include {\n    everyone = true\n  }", 1)' || bad "M-landing: q_twoinc"
check_not "MQ3: a second include block on the deploy policy fails Q1" p_gated_policy "$SBX/q_twoinc.tf" deploy_service_token deploy "$INC_DEPLOY"
mtf q_app 's = s.replace("application_id = cloudflare_zero_trust_access_application.ssh.id", "application_id = cloudflare_zero_trust_access_application.deploy.id", 1)' || bad "M-landing: q_app"
check_not "MQ4: the ci_ssh policy pointed at the deploy app fails Q2" p_gated_policy "$SBX/q_app.tf" ci_ssh_service_token ssh "$INC_SSH"
mtf q_dur 's = s.replace("session_duration = \"15m\"", "session_duration = \"24h\"", 1)' || bad "M-landing: q_dur"
check_not "MQ5: a 24h session on the ssh app fails Q5" p_gated_app "$SBX/q_dur.tf" ssh ssh 15m
mtf q_zone 's = s.replace("resource \"cloudflare_zero_trust_access_policy\" \"registry_push_service_token\" {\n  zone_id        = var.cf_zone_id", "resource \"cloudflare_zero_trust_access_policy\" \"registry_push_service_token\" {\n  account_id     = var.cf_account_id", 1)' || bad "M-landing: q_zone"
check_not "MQ6: an account-scoped registry policy (app/policy scope mismatch) fails Q3" p_gated_policy "$SBX/q_zone.tf" registry_push_service_token registry "$INC_REG"
mtf q_appacct 's = s.replace("resource \"cloudflare_zero_trust_access_application\" \"deploy\" {\n  zone_id          = var.cf_zone_id", "resource \"cloudflare_zero_trust_access_application\" \"deploy\" {\n  account_id       = var.cf_account_id", 1)' || bad "M-landing: q_appacct"
check_not "MQ6b: an account-scoped deploy app fails Q4" p_gated_app "$SBX/q_appacct.tf" deploy deploy 24h
mtf q_noprecond 's = s.replace("length(local.deploy_service_token_ids) > 0", "true", 1)' || bad "M-landing: q_noprecond"
check_not "MQ7: dropping the UUID precondition fails Q7" p_gated_precond "$SBX/q_noprecond.tf"

# Q12: ONE table. The filter's access_family_table (evaluated by jq, so the static side reads what the gate reads) must
# list exactly the Access app/policy addresses declared in apps/web-platform/infra/**/*.tf: every `resource` block of the
# family (any type alias, quoted or bare labels, any directory) and every `removed { from = ... }` of it (a teardown keeps
# its row until the forget applies). Sorted WITH duplicates, so a module block reusing a table name is an extra row.
table_keys() { jq -rn "$(sed -n '/^def access_family_table: {$/,/^};$/p' "$1") access_family_table | keys[]" | LC_ALL=C sort; }
tf_access_family() { # <infra-dir>
  local f
  while IFS= read -r f; do
    eff "$f" | sed -nE 's/^[[:space:]]*resource[[:space:]]+"?(cloudflare_(zero_trust_)?access_(policy|application))"?[[:space:]]+"?([A-Za-z0-9_-]+)"?.*/\1.\4/p'
    eff "$f" | tr -d '\n' | grep -oE 'removed[[:space:]]*\{[[:space:]]*from[[:space:]]*=[[:space:]]*cloudflare_(zero_trust_)?access_(policy|application)\.[A-Za-z0-9_-]+' | sed -E 's/.*=[[:space:]]*//' || true
  done < <(find -H "$1" -name .terraform -prune -o -type f -name '*.tf' -print | LC_ALL=C sort)
}
p_table_eq() { # <infra-dir> <filter>
  local t d; t="$(table_keys "$2")" || return 1; d="$(tf_access_family "$1" | LC_ALL=C sort)"
  [[ -n "$t" && "$t" == "$d" ]]
}
p_no_tfjson() { ! find -H "$1" -name .terraform -prune -o -type f -name '*.tf.json' -print | xargs -r grep -lE 'access_(policy|application)' | grep . >/dev/null; }
p_table_roles() { # the table's gated_policy rows are exactly the per-address policy checks' keys
  local defs; defs="$(sed -n '/^def access_policy_refs: {$/,/^};$/p;/^def access_family_table: {$/,/^};$/p' "$1")"
  jq -en "$defs ([access_family_table | to_entries[] | select(.value == \"gated_policy\") | .key] | sort) == (access_policy_refs | keys) and (access_family_table | length) > 0" >/dev/null
}
check     "Q12: the filter's access_family_table equals the Access app/policy blocks in apps/web-platform/infra/**/*.tf" p_table_eq "$INFRA" "$FILTER"
check     "Q12b: no *.tf.json under the root declares an Access app or policy (the static read is HCL only)" p_no_tfjson "$INFRA"
check     "Q12c: the table's gated_policy rows are exactly access_policy_refs (one list, two roles)" p_table_roles "$FILTER"
# q12tree <name> -> a copy of every .tf under the root, same layout, in $SBX/<name>
q12tree() { rm -rf "${SBX:?}/$1"; (cd "$INFRA" && find . -name .terraform -prune -o -type f -name '*.tf' -print | while IFS= read -r f; do mkdir -p "$SBX/$1/$(dirname "$f")"; cp "$f" "$SBX/$1/$f"; done); }
POL_BYPASS='  zone_id        = var.cf_zone_id\n  name           = "x"\n  decision       = "bypass"\n  precedence     = 2\n\n  include {\n    everyone = true\n  }\n'
q12tree q12ctl
check     "MQ12-ctl: the copied tree satisfies Q12 (the mutants below start from a green control)" p_table_eq "$SBX/q12ctl" "$FILTER"
q12row() { # <label> <relative-file> <hcl>
  q12tree q12m; printf '%b' "$3" > "$SBX/q12m/$2"
  check_not "$1" p_table_eq "$SBX/q12m" "$FILTER"
}
q12row "MQ12a (SP1): a legacy-type cloudflare_access_policy block on deploy fails Q12" zz-extra.tf "resource \"cloudflare_access_policy\" \"deploy_open\" {\n  application_id = cloudflare_zero_trust_access_application.deploy.id\n$POL_BYPASS}\n"
q12row "MQ12b (SP2): a policy bound through a local fails Q12" zz-extra.tf "locals {\n  deploy_app = cloudflare_zero_trust_access_application.deploy\n}\nresource \"cloudflare_zero_trust_access_policy\" \"via_local\" {\n  application_id = local.deploy_app.id\n$POL_BYPASS}\n"
q12row "MQ12c (SP3): a policy bound to a literal app id fails Q12" zz-extra.tf "resource \"cloudflare_zero_trust_access_policy\" \"via_literal\" {\n  application_id = \"00000000000000000000000000000abc\"\n$POL_BYPASS}\n"
q12row "MQ12d (SP4): a NEW app on deploy.<base>/hooks fails Q12" zz-extra.tf "resource \"cloudflare_zero_trust_access_application\" \"deploy_hooks\" {\n  zone_id = var.cf_zone_id\n  name    = \"x\"\n  domain  = \"deploy.\${var.app_domain_base}/hooks\"\n  type    = \"self_hosted\"\n}\n"
q12row "MQ12e (SP5): a reusable policy (no application_id) fails Q12" zz-extra.tf "resource \"cloudflare_zero_trust_access_policy\" \"reusable\" {\n$POL_BYPASS}\n"
q12row "MQ12f: a policy in a module directory fails Q12 (the read recurses)" modules/git-data-userdata/zz-extra.tf "resource \"cloudflare_zero_trust_access_policy\" \"deploy_service_token\" {\n$POL_BYPASS}\n"
q12row "MQ12g: a bare-label resource block fails Q12" zz-extra.tf "resource cloudflare_zero_trust_access_policy bare {\n$POL_BYPASS}\n"
q12tree q12rm; python3 -c 'import sys; p = sys.argv[1]; s = open(p).read(); a = s.index("resource \"cloudflare_zero_trust_access_policy\" \"registry_push_service_token\" {"); b = s.index("\n}\n", a) + 3; open(p, "w").write(s[:a] + "removed {\n  from = cloudflare_zero_trust_access_policy.registry_push_service_token\n\n  lifecycle {\n    destroy = false\n  }\n}\n" + s[b:])' "$SBX/q12rm/tunnel.tf"
check     "MQ12h GREEN: a gated block turned into removed { from } keeps Q12 green (the teardown path)" p_table_eq "$SBX/q12rm" "$FILTER"
mfilter f_tabrow 's = s.replace("  \"cloudflare_zero_trust_access_application.registry\": \"gated_app\",\n", "", 1)' || bad "M-landing: f_tabrow"
check_not "MQ12i: a table row dropped from the filter fails Q12" p_table_eq "$INFRA" "$SBX/f_tabrow.jq"
mfilter f_tabrole 's = s.replace("\"cloudflare_zero_trust_access_policy.ci_ssh_service_token\": \"gated_policy\"", "\"cloudflare_zero_trust_access_policy.ci_ssh_service_token\": \"gated_app\"", 1)' || bad "M-landing: f_tabrole"
check_not "MQ12j: a gated policy mislabelled as an app in the table fails Q12c" p_table_roles "$SBX/f_tabrole.jq"

# Q10: each CNAME waits for its own Access policy, so a failed Access create leaves the host unrouted.
DNS="$INFRA/dns.tf"
p_rec_dep() { # <dns.tf> <record> <policy>
  local b; b="$(block_of "$1" cloudflare_record "$2" | tr -d '\n')"
  grep -qE "depends_on[[:space:]]*=[[:space:]]*\[[[:space:]]*cloudflare_zero_trust_access_policy\.$3[[:space:]]*\]" <<<"$b"
}
check     "Q10a: cloudflare_record.deploy depends on deploy_service_token" p_rec_dep "$DNS" deploy deploy_service_token
check     "Q10b: cloudflare_record.ssh depends on ci_ssh_service_token" p_rec_dep "$DNS" ssh ci_ssh_service_token
check     "Q10c: cloudflare_record.registry depends on registry_push_service_token" p_rec_dep "$DNS" registry registry_push_service_token
python3 -c 'import sys; s = open(sys.argv[1]).read(); t = s.replace("\n  depends_on = [cloudflare_zero_trust_access_policy.ci_ssh_service_token]\n", "\n", 1); assert t != s; open(sys.argv[2], "w").write(t)' "$DNS" "$SBX/dns-nodep.tf" || bad "M-landing: dns-nodep"
check_not "MQ10: dropping the ssh record's depends_on fails Q10b" p_rec_dep "$SBX/dns-nodep.tf" ssh ci_ssh_service_token

# Q11: neither registry Doppler secret can write an empty token value over prd.
p_dop_nonempty() { # <tf> <secret-name> <attr>
  local b; b="$(block_of "$1" doppler_secret "$2" | tr -d '\n')"
  grep -qE "precondition[[:space:]]*\{[[:space:]]*condition[[:space:]]*=[[:space:]]*(nonsensitive\()?cloudflare_zero_trust_access_service_token\.registry_push\.$3[[:space:]]*!=[[:space:]]*\"\"" <<<"$b"
}
check     "Q11a: doppler_secret.registry_push_access_token_id refuses an empty client_id" p_dop_nonempty "$TF" registry_push_access_token_id client_id
check     "Q11b: doppler_secret.registry_push_access_token_secret refuses an empty client_secret" p_dop_nonempty "$TF" registry_push_access_token_secret client_secret
mtf q_dop 's = s.replace("nonsensitive(cloudflare_zero_trust_access_service_token.registry_push.client_secret != \"\")", "true", 1)' || bad "M-landing: q_dop"
check_not "MQ11: dropping the client_secret precondition fails Q11b" p_dop_nonempty "$SBX/q_dop.tf" registry_push_access_token_secret client_secret
mtf q_dec 's = s.replace("ssh.id\n  name           = \"Allow GitHub Actions CI SSH\"\n  decision       = \"non_identity\"", "ssh.id\n  name           = \"Allow GitHub Actions CI SSH\"\n  decision       = \"bypass\"", 1)' || bad "M-landing: q_dec"
check_not "MQ12: decision bypass on the ci_ssh policy fails Q2" p_gated_policy "$SBX/q_dec.tf" ci_ssh_service_token ssh "$INC_SSH"
mtf q_type 's = s.replace("domain  = \"registry.${var.app_domain_base}\"\n  type    = \"self_hosted\"", "domain  = \"registry.${var.app_domain_base}\"\n  type    = \"ssh\"", 1)' || bad "M-landing: q_type"
check_not "MQ13: a non-self_hosted registry app fails Q6" p_gated_app "$SBX/q_type.tf" registry registry 15m
mtf q_nilok 's = s.replace(" && id != \"00000000-0000-0000-0000-000000000000\"", "", 1)' || bad "M-landing: q_nilok"
check_not "MQ14: a precondition that accepts the nil placeholder fails Q7" p_gated_precond "$SBX/q_nilok.tf"

for k in options_preflight_bypass self_hosted_domains destinations cors_headers; do
  case "$k" in destinations|cors_headers) v="$k {\n    uri = \"x\"\n  }" ;; options_preflight_bypass) v="$k = true" ;; *) v="$k = [\"x\"]" ;; esac
  mtf "q_app_$k" "s = s.replace('  session_duration = \"24h\"\n}\n\n# The deploy Access service token', '  session_duration = \"24h\"\n  $v\n}\n\n# The deploy Access service token', 1)" || bad "M-landing: q_app_$k"
  check_not "MQ15/$k: setting $k on the deploy app fails Q4" p_gated_app "$SBX/q_app_$k.tf" deploy deploy 24h
done

# C10: refusals reach the log through BOTH `$(...)` captures (the workflow captures deploy_policy_counts, which captures
# the id reader): they go to stderr, so stdout stays empty and the message is on stderr.
c10() { # <gate-lib>
  ( source "$1"; o=""; if o="$(deploy_policy_counts "$SBX/pol-create-all.json" "$SBX/ids-nil.tf" "$FILTER" 2>"$SBX/c10.err")"; then exit 1; fi
    if [[ -z "$o" ]] && grep -qF '::error::deploy policy guard: placeholder deploy token id still committed' "$SBX/c10.err"; then exit 0; fi
    exit 1 )
}
check     "C10: a deploy_policy_counts refusal inside \$(...) leaves stdout empty and prints its ::error:: on stderr" c10 "$GATE"
sed 's/" >&2$/"/' "$GATE" > "$SBX/gate-stdout.sh"
check_not "MC10: with the refusal echoes back on stdout (the mutation landed: $(cmp -s "$GATE" "$SBX/gate-stdout.sh" && echo NO || echo yes)), C10 fails" c10 "$SBX/gate-stdout.sh"

# ── dispatch: the assertions above must have RUN (a deleted call site is otherwise a silent green) ───────────────────────
echo ""
echo "=== deploy-access-token-forget: $PASS passed, $FAIL failed ==="
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  printf '  FAIL assertion floor: %d assertions ran, the floor is %d — assertions were deleted or skipped\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [[ "$FAIL" -ne 0 ]]; then
  printf '  FAIL verdict: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
exit 0
