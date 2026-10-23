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

MIN_ASSERTIONS=51
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
check_not() { local label="$1"; shift; if "$@"; then bad "$label"; else ok "$label"; fi; }

UUID_RE='"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"'
SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT

# ── source predicates over the EFFECTIVE text of a tunnel.tf copy (arg 1) ─────────────────────────────────────────────
eff() { strip_comments "$1"; }
p_no_resource()   { ! eff "$1" | grep -qE '^resource[[:space:]]+"cloudflare_zero_trust_access_service_token"[[:space:]]+"deploy"'; }
p_removed()       { eff "$1" | tr -d '\n' | grep -qE 'removed[[:space:]]*\{[[:space:]]*from[[:space:]]*=[[:space:]]*cloudflare_zero_trust_access_service_token\.deploy[[:space:]]*lifecycle[[:space:]]*\{[[:space:]]*destroy[[:space:]]*=[[:space:]]*false[[:space:]]*\}'; }
p_policy_local()  { block_of "$1" cloudflare_zero_trust_access_policy deploy_service_token | tr -d '\n' | grep -qE 'include[[:space:]]*\{[[:space:]]*service_token[[:space:]]*=[[:space:]]*local\.deploy_service_token_ids[[:space:]]*\}'; }
p_precondition()  { local b; b="$(block_of "$1" cloudflare_zero_trust_access_policy deploy_service_token)"; grep -qE '^[[:space:]]+precondition[[:space:]]*\{' <<<"$b" && grep -qF 'length(local.deploy_service_token_ids) > 0' <<<"$b" && grep -qF '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$b"; }
p_no_outputs()    { ! eff "$1" | grep -qE '^output[[:space:]]+"access_service_token_client_(id|secret)"'; }
p_no_client_ref() { ! eff "$1" | grep -qE 'access_service_token\.deploy\.client_'; }
p_locals_uuid()   { eff "$1" | tr -d '\n' | grep -oE 'locals[[:space:]]*\{[[:space:]]*deploy_service_token_ids[[:space:]]*=[[:space:]]*\[[^]]*\]' | grep -qE "$UUID_RE"; }
p_locals_once()   { [[ "$(eff "$1" | grep -cE '^[[:space:]]*deploy_service_token_ids[[:space:]]*=')" == "1" ]]; }
# no `variable "deploy_service_token_ids"` in ANY .tf of the root dir (arg 1), and no override/JSON config that could re-add one
p_no_variable()   { local f; for f in "$1"/*.tf; do if eff "$f" | grep -qE '^variable[[:space:]]+"deploy_service_token_ids"'; then return 1; fi; done; [[ "$(p_b4_no_override_files "$1")" == "1" ]]; }

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
  w="$(grep -vE "^[[:space:]]*#" "$1")"; a="$(grep -n "deploy_policy_gate \"\$counts\" \"\$HEAD_MSG\" || exit 1" <<<"$w" | head -1 | cut -d: -f1)"; d="$(grep -n "^[[:space:]]*destroy_count=" <<<"$w" | head -1 | cut -d: -f1)"
  [[ -n "$a" && -n "$d" && "$a" -lt "$d" ]] && grep -qF "tests/scripts/lib/deploy-policy-gate.sh" <<<"$w"' _ "$WF"

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
mtf m_uuid 's = s.replace("deploy_service_token_ids = []", "deploy_service_token_ids = [\"00000000-0000-4000-8000-000000000001\"]", 1)' || bad "M-landing: m_uuid"
check     "M6: a UUID in the local satisfies S7 (the positive control: S7 can pass)" p_locals_uuid "$SBX/m_uuid.tf"
mtf m_baduuid 's = s.replace("deploy_service_token_ids = []", "deploy_service_token_ids = [\"not-a-uuid\"]", 1)' || bad "M-landing: m_baduuid"
check_not "M7: a non-UUID entry fails S7" p_locals_uuid "$SBX/m_baduuid.tf"
mkdir -p "$SBX/rootcopy"; cp "$INFRA"/*.tf "$SBX/rootcopy/"
printf 'variable "deploy_service_token_ids" {\n  type    = list(string)\n  default = ["x"]\n}\n' > "$SBX/rootcopy/zz-extra.tf"
check_not "M8: a variable of that name added in another root file fails S6b" p_no_variable "$SBX/rootcopy"
rm -f "$SBX/rootcopy/zz-extra.tf"; : > "$SBX/rootcopy/extra_override.tf"
check_not "M9: an override file in the root fails S6b" p_no_variable "$SBX/rootcopy"
sed -E 's/^([[:space:]]*)-target=cloudflare_zero_trust_access_service_token\.deploy/\1# -target=cloudflare_zero_trust_access_service_token.deploy/' "$WF" > "$SBX/wf-commented.yml"
m10() { ! cmp -s "$WF" "$SBX/wf-commented.yml" && ! grep -vE "^[[:space:]]*#" "$SBX/wf-commented.yml" | grep -E "^[[:space:]]*-target=cloudflare_zero_trust_access_service_token\.deploy" >/dev/null; }
check     "M10: commenting out the -target line (the mutation landed) leaves no non-comment -target line, so T1 fails" m10

# ── dispatch: the assertions above must have RUN (a deleted call site is otherwise a silent green) ───────────────────────
echo ""
echo "=== deploy-access-token-forget: $PASS passed, $FAIL failed ==="
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  printf '  FAIL assertion floor: %d assertions ran, the floor is %d — assertions were deleted or skipped\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
