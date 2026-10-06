#!/usr/bin/env bash
#
# Structural + behavioral + mutation gate for .github/workflows/web2-luks-rebirth.yml (#9372): the dispatch-only,
# single-use workflow that converts the live web-2 standby to LUKS-at-boot by rebirthing its empty volume.
#
# THE PROPERTY (Guard 3): no write is reachable under plan_only; the escrow preflight precedes every Terraform command and
# every Hetzner call; the destructive steps run only after the `pre` plan was graded and in the order
# delete -> state rm -> post plan -> apply -> readiness -> recovery check -> reboot; the constants, the concurrency
# literals, the environment and the five-target set are the ones the other appliers use; and no plan file is uploaded.
#
# Structural rows PARSE the YAML (a grep would match the prose). Behavioral rows EXECUTE the extracted step bodies under
# `bash --noprofile --norc -e` (GitHub's shell for a step without a shell: key, no pipefail), against doppler/terraform
# shims and the REAL gate library, so the gate's call site and its return code are exercised, not just its source. The
# mutation battery then applies one edit per row to a COPY of the workflow and requires the battery to go red.
# shellcheck disable=SC2319,SC2034
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF_REAL="$REPO/.github/workflows/web2-luks-rebirth.yml"
SCRIPT_REAL="$REPO/scripts/web2-rebirth.sh"
FIX="$REPO/tests/scripts/fixtures/web-host-rebirth"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[[ -f "$WF_REAL" ]] || { echo "FAIL - the rebirth workflow is missing"; exit 1; }

cat > "$TMP/wfq.py" <<'PY'
import json, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
cmd = sys.argv[2]
job = wf["jobs"]["rebirth"]
if cmd == "steps":
    print(json.dumps([{"name": s.get("name", ""), "if": s.get("if"), "run": s.get("run"), "env": s.get("env"), "wd": s.get("working-directory"),
                       "shell": s.get("shell"), "uses": s.get("uses"), "timeout": s.get("timeout-minutes"), "cont": s.get("continue-on-error")} for s in job["steps"]]))
elif cmd == "top":
    on = wf.get("on", wf.get(True))
    print(json.dumps({"on": on, "concurrency": wf.get("concurrency"), "permissions": wf.get("permissions"), "env": wf.get("env"),
                      "job_if": job.get("if"), "job_env": job.get("environment"), "job_conc": job.get("concurrency"), "job_timeout": job.get("timeout-minutes"),
                      "jobs": list(wf["jobs"].keys())}))
elif cmd == "body":
    name = sys.argv[3]
    for s in job["steps"]:
        if s.get("name", "").startswith(name):
            print(s.get("run", ""))
            break
    else:
        sys.exit(3)
PY

battery() {
  local wf="$1" n=0 steps top
  if ! steps="$(python3 "$TMP/wfq.py" "$wf" steps 2>/dev/null)" || ! top="$(python3 "$TMP/wfq.py" "$wf" top 2>/dev/null)"; then
    printf 'FAILED S0 the workflow does not parse (a parse error is not a mutation kill)\nRAN 0\n'; return
  fi
  chk() { n=$((n + 1)); [[ "$2" -eq 0 ]] || printf 'FAILED %s\n' "$1"; }
  jqs() { jq -r "$1" <<<"$steps"; }
  jqt() { jq -r "$1" <<<"$top"; }
  idx() { jq -r --arg p "$1" '[to_entries[] | select(.value.name | startswith($p)) | .key] | first // -1' <<<"$steps"; }

  # ---- structural
  chk "S1 the only trigger is workflow_dispatch" "$([[ "$(jqt '.on | keys | join(",")')" == "workflow_dispatch" ]]; echo $?)"
  chk "S2 one job, five inputs, plan_only is a boolean defaulting to true" "$([[ "$(jqt '.jobs | length')" == 1 && "$(jqt '.on.workflow_dispatch.inputs | length')" == 5 && "$(jqt '.on.workflow_dispatch.inputs.plan_only.default')" == true && "$(jqt '.on.workflow_dispatch.inputs.plan_only.type')" == boolean ]]; echo $?)"
  chk "S2b the required inputs are required" "$([[ "$(jqt '[.on.workflow_dispatch.inputs.confirm.required, .on.workflow_dispatch.inputs.expected_volume_id.required, .on.workflow_dispatch.inputs.image_tag.required, .on.workflow_dispatch.inputs.reason.required] | all')" == true ]]; echo $?)"
  chk "S3 the workflow serializes on the state's literal and never cancels" "$([[ "$(jqt '.concurrency.group')" == terraform-apply-web-platform-host && "$(jqt '.concurrency["cancel-in-progress"]')" == false ]]; echo $?)"
  chk "S4 the job carries web-1-swap, the reviewer environment and the main-only guard" "$([[ "$(jqt '.job_conc.group')" == web-1-swap && "$(jqt '.job_conc["cancel-in-progress"]')" == false && "$(jqt '.job_env')" == web-platform-infra-apply && "$(jqt '.job_if')" == *"refs/heads/main"* ]]; echo $?)"
  chk "S5 permissions are exactly contents/actions/packages read" "$([[ "$(jqt '.permissions | to_entries | map("\(.key)=\(.value)") | sort | join(",")')" == "actions=read,contents=read,packages=read" ]]; echo $?)"
  chk "S6 the Terraform version is pinned and equal in both variables" "$([[ "$(jqt '.env.TERRAFORM_VERSION')" == "$(jqt '.env.TF_VAR_terraform_version')" && "$(jqt '.env.TERRAFORM_VERSION')" =~ ^[0-9.]+$ && "$(jqt '.env.INFRA_DIR')" == apps/web-platform/infra ]]; echo $?)"
  local script_pin; script_pin="$(sed -nE 's/^PINNED_VOLUME_ID="([0-9]+)".*/\1/p' "$SCRIPT_REAL" | head -1)"
  chk "S7 the physical-id pin is the same constant in the workflow and the script" "$([[ -n "$script_pin" && "$(jqt '.env.PINNED_VOLUME_ID')" == "$script_pin" && "$script_pin" == 106466179 ]]; echo $?)"
  chk "S8 the job timeout is bounded" "$([[ "$(jqt '.job_timeout')" =~ ^[0-9]+$ && "$(jqt '.job_timeout')" -ge 1 && "$(jqt '.job_timeout')" -le 60 ]]; echo $?)"

  local pf; pf="$(idx 'Escrow readiness preflight')"
  chk "S9 the escrow preflight is exactly the pinned one-liner with a 2-minute bound, DOPPLER_TOKEN only and no condition" "$([[ "$pf" -ge 0 && "$(jq -r --argjson i "$pf" '.[$i].run | rtrimstr("\n")' <<<"$steps")" == "bash scripts/web-host-escrow-preflight.sh" && "$(jq -r --argjson i "$pf" '.[$i].timeout' <<<"$steps")" == 2 && "$(jq -r --argjson i "$pf" '.[$i].if' <<<"$steps")" == null && "$(jq -r --argjson i "$pf" '.[$i].env | keys | join(",")' <<<"$steps")" == DOPPLER_TOKEN && "$(jq -r --argjson i "$pf" '.[$i].wd' <<<"$steps")" == null && "$(jq -r --argjson i "$pf" '.[$i].shell' <<<"$steps")" == null && "$(jq -r --argjson i "$pf" '.[$i].cont' <<<"$steps")" == null ]]; echo $?)"
  local first_tf
  first_tf="$(jq -r '[to_entries[] | select((.value.run // "") | test("(^|[^A-Za-z0-9_-])terraform +(init|plan|apply|state|console|show|output)|web2-rebirth|api\\.hetzner|curl "))] | first | .key // -1' <<<"$steps")"
  chk "S10 the preflight precedes every Terraform command, script call and API call" "$([[ "$pf" -ge 0 && "$first_tf" -gt "$pf" ]]; echo $?)"

  local ic ip ipre ds sr ipost ia ir ir2 irb ifl iin
  ic="$(idx 'Classify state')"; ifl="$(idx 'Flip precondition')"; ipre="$(idx 'Terraform plan `pre`')"; ds="$(idx 'Delete the empty plaintext volume')"
  sr="$(idx 'Forget the volume')"; ipost="$(idx 'Terraform plan `post`')"; ia="$(idx 'Terraform apply')"; ir="$(idx 'Wait for the fresh-boot readiness row')"
  ir2="$(idx 'Birth-time recovery check')"; irb="$(idx 'Issue the hcloud reboot')"; iin="$(idx 'Install cryptsetup')"
  chk "S11 the steps run in the contracted order" "$([[ "$ic" -gt 0 && "$ifl" -gt "$ic" && "$ipre" -gt "$ifl" && "$iin" -gt "$ipre" && "$ds" -gt "$iin" && "$sr" -gt "$ds" && "$ipost" -gt "$sr" && "$ia" -gt "$ipost" && "$ir" -gt "$ia" && "$ir2" -gt "$ir" && "$irb" -gt "$ir2" ]]; echo $?)"
  # EVERY step with a run body is either on the read-only list or on the write list, so a NEW step cannot slip in unclassified; every
  # write step's `if:` equals one of two exact spellings (a substring test lets `always() && env.APPLY == 'yes'` through).
  local F1 RO WR unclassified badif
  F1="\${{ env.APPLY == 'yes' }}"
  RO='["Validate dispatch inputs","Verify required secrets","Extract backend credentials","Escrow readiness preflight","Terraform init","Generate ephemeral SSH","Assert runner is amd64","Resolve the image digest","Coherence preflight","Classify state","Emptiness evidence","Never-pooled evidence","Flip precondition","Terraform plan `pre`","Remove plan files","Name the heal window","Dispatch summary"]'
  WR="$(jq -cn --arg f1 "$F1" '{"Install cryptsetup":$f1,"Delete the empty plaintext volume":$f1,"Forget the volume":$f1,"Terraform plan `post`":$f1,"Terraform apply":$f1,"Wait for the fresh-boot readiness row":$f1,"Birth-time recovery check":$f1,"Issue the hcloud reboot":$f1}')"
  unclassified="$(jq -r --argjson ro "$RO" --argjson wr "$WR" '[.[] | select(.run != null) | .name as $n | select((([$ro[]] + ($wr | keys)) | any(. as $p | $n | startswith($p))) | not) | .name] | join(" | ")' <<<"$steps")" || unclassified="JQ-ERROR"
  chk "S12 every step with a run body is classified read-only or write (an unclassified step: ${unclassified})" "$([[ -z "$unclassified" ]]; echo $?)"
  badif="$(jq -r --argjson wr "$WR" '[.[] | select(.run != null) | . as $s | ($wr | to_entries[] | select(.key as $k | $s.name | startswith($k))) as $m | select($s.if != $m.value) | "\($s.name) -> \($s.if)"] | join(" | ")' <<<"$steps")" || badif="JQ-ERROR"
  chk "S12c every write step's if: equals its exact spelling (no substring pass): ${badif}" "$([[ -z "$badif" ]]; echo $?)"
  # POSITIVE CONTROL for S12c: the same filter over a steps array whose reboot step has NO if: must report it (a filter that errors or
  # matches nothing would make S12c green forever; this is how the first draft of it failed open).
  local bad_ctl
  bad_ctl="$(jq -r --argjson wr "$WR" '[.[] | select(.run != null) | . as $s | ($wr | to_entries[] | select(.key as $k | $s.name | startswith($k))) as $m | select($s.if != $m.value) | "\($s.name) -> \($s.if)"] | join(" | ")' <<<'[{"name":"Issue the hcloud reboot (x)","run":"echo","if":null},{"name":"Terraform apply (x)","run":"echo","if":"${{ always() && env.APPLY == '"'"'yes'"'"' }}"}]')" || bad_ctl=""
  chk "S12c-control the exact-if filter reports a missing if: and a widened if: (it can fail)" "$([[ "$bad_ctl" == *"Issue the hcloud reboot"* && "$bad_ctl" == *"Terraform apply"* ]]; echo $?)"
  chk "S12d every write step on the list EXISTS (a guard over a missing step is vacuous)" "$([[ "$(jq -r --argjson wr "$WR" '[.[] | .name as $n | select($wr | keys | any(. as $p | $n | startswith($p)))] | length' <<<"$steps")" -eq 8 ]]; echo $?)"
  chk "S12e no run body swallows a failure with || true, except the cleanup step and the digest resolve (its shape check follows)" "$([[ "$(jq -r '[.[] | select(((.name | startswith("Remove plan files")) or (.name | startswith("Resolve the image digest"))) | not) | select((.run // "") | test("\\|\\| *true"))] | length' <<<"$steps")" == 0 ]]; echo $?)"
  local EV; EV="\${{ steps.classify.outputs.verdict == 'proceed' || steps.classify.outputs.verdict == 'heal:detach_done' }}"
  chk "S12f the emptiness step and the pre plan run exactly in the proceed and detach-done windows" "$([[ "$(jq -r --arg ev "$EV" '[.[] | select((.name | startswith("Emptiness evidence")) or (.name | startswith("Terraform plan `pre`"))) | select(.if == $ev)] | length' <<<"$steps")" == 2 ]]; echo $?)"
  chk "S12f2 the never-pooled step has NO condition (it runs for every verdict: the delete AND the reboot need its proof)" "$([[ "$(jq -r '[.[] | select(.name | startswith("Never-pooled evidence"))][0] | .if' <<<"$steps")" == null ]]; echo $?)"
  chk "S12g the delete step receives each evidence step's OWN output (a skipped step leaves it empty, and the script refuses)" "$([[ "$(jq -r --argjson i "$ds" '.[$i].env | "\(.EMPTINESS)|\(.NEVER_POOLED)|\(.PRE_PLAN)|\(.VERDICT)|\(.FLIP)"' <<<"$steps")" == "\${{ steps.emptiness.outputs.verdict }}|\${{ steps.pooled.outputs.verdict }}|\${{ steps.preplan.outputs.graded }}|\${{ steps.classify.outputs.verdict }}|\${{ steps.flip.outputs.met }}" ]]; echo $?)"
  local apply_run; apply_run="$(jq -r --argjson i "$ia" '.[$i].run' <<<"$steps")"
  chk "S12h the apply step applies exactly the graded post plan file, interactively approved by nothing else (no -auto-approve, one apply)" "$([[ "$apply_run" == *"terraform apply -no-color -input=false tfplan-post"* && "$apply_run" != *auto-approve* && "$(grep -o 'terraform apply -' <<<"$apply_run" | wc -l | tr -d ' ')" == 1 ]]; echo $?)"
  chk "S12i the plans write tfplan-pre and tfplan-post and show exactly those files" "$([[ "$(jq -r --argjson i "$ipre" '.[$i].run' <<<"$steps")" == *"-out=tfplan-pre"* && "$(jq -r --argjson i "$ipre" '.[$i].run' <<<"$steps")" == *"terraform show -json tfplan-pre > tfplan-pre.json"* && "$(jq -r --argjson i "$ipost" '.[$i].run' <<<"$steps")" == *"-out=tfplan-post"* && "$(jq -r --argjson i "$ipost" '.[$i].run' <<<"$steps")" == *"terraform show -json tfplan-post > tfplan-post.json"* ]]; echo $?)"
  chk "S12j the job exports the classifier verdict as an output" "$([[ "$(python3 - "$wf" <<'PY2'
import sys, yaml
print(yaml.safe_load(open(sys.argv[1]))["jobs"]["rebirth"].get("outputs", {}).get("verdict", ""))
PY2
)" == *"steps.classify.outputs.verdict"* ]]; echo $?)"
  chk "S12k the pin step strips a leading v before the resolver (it prepends one itself)" "$([[ "$(jqs '[.[] | select(.name | startswith("Resolve the image digest"))][0].run')" == *'${IMAGE_TAG_INPUT#v}'* ]]; echo $?)"
  chk "S12l the cleanup removes Terraform's timestamped state backups too" "$([[ "$(jqs '[.[] | select(.name | startswith("Remove plan files"))][0].run')" == *'./terraform.tfstate.*.backup'* ]]; echo $?)"
  local pre_lit req_lit
  pre_lit="$(jq -r --argjson i "$ipre" '.[$i].run' <<<"$steps" | sed -nE "s/.*printf 'graded=([a-z]+)\\\\n'.*/\1/p" | head -1)"
  req_lit="$(sed -nE 's/.*\[\[ "\$\{PRE_PLAN:-\}" == ([a-z]+) \]\].*/\1/p' "$SCRIPT_REAL" | head -1)"
  chk "S12m the literal the pre-plan step EXPORTS equals the literal delete-volume REQUIRES (they disagreed once: ${pre_lit} vs ${req_lit})" "$([[ -n "$pre_lit" && "$pre_lit" == "$req_lit" ]]; echo $?)"
  local pool_lit req_pool met_lit req_met
  pool_lit="$(jq -r '[.[] | select(.name | startswith("Never-pooled evidence"))][0].run' <<<"$steps" | sed -nE "s/.*printf 'verdict=([a-z]+)\\\\n'.*/\1/p" | head -1)"
  req_pool="$(sed -nE 's/.*\[\[ "\$\{NEVER_POOLED:-\}" == ([a-z]+) \]\].*/\1/p' "$SCRIPT_REAL" | sort -u | tr '\n' ' ')"
  met_lit="$(sed -nE 's/.*echo "flip precondition: MET"; out met ([a-z]+);.*/\1/p' "$SCRIPT_REAL" | head -1)"
  req_met="$(sed -nE 's/.*\[\[ "\$\{FLIP:-\}" == ([a-z]+) \]\].*/\1/p' "$SCRIPT_REAL" | head -1)"
  chk "S12m2 the never-pooled literal the step EXPORTS (${pool_lit}) is the one the script requires of NEVER_POOLED (${req_pool})" "$([[ -n "$pool_lit" && "$req_pool" == "$pool_lit " ]]; echo $?)"
  chk "S12m3 the flip literal the script EXPORTS (${met_lit}) is the one delete-volume requires of FLIP (${req_met})" "$([[ -n "$met_lit" && "$met_lit" == "$req_met" ]]; echo $?)"
  chk "S12n no run body talks to Hetzner or the hcloud CLI directly (every Hetzner call is inside a classified script)" "$([[ "$(jq -r '[.[] | select((.run // "") | test("curl |api\\.hetzner\\.cloud|(^|[^A-Za-z0-9_-])hcloud +"))] | length' <<<"$steps")" == 0 ]]; echo $?)"
  chk "S12o the only Terraform verbs in a run body are init, plan, apply, show and console (state surgery lives in the script)" "$([[ "$(jq -r '[.[] | (.run // "") | scan("(?:^|[^A-Za-z0-9_-])terraform +(?:-[^ ]+ +)*([a-z]+)") | .[0]] | map(select(. != "init" and . != "plan" and . != "apply" and . != "show" and . != "console")) | length' <<<"$steps")" == 0 ]]; echo $?)"
  chk "S12p no run body swallows a failure with || true, || exit 0, || echo, || : or | cat (cleanup and the digest resolve excepted)" "$([[ "$(jq -r '[.[] | select(((.name | startswith("Remove plan files")) or (.name | startswith("Resolve the image digest"))) | not) | select((.run // "") | test("\\|\\| *(true|exit 0|echo|:)|\\| *cat( |$)|; *true( |$)"))] | length' <<<"$steps")" == 0 ]]; echo $?)"
  chk "S12q the only third-party or local actions are checkout, setup-terraform and the credential loader (a new uses: step is unclassified)" "$([[ "$(jq -r '[.[] | select(.uses != null) | .uses | select((startswith("actions/checkout@") or startswith("hashicorp/setup-terraform@") or . == "./.github/actions/infra-credentials") | not)] | length' <<<"$steps")" == 0 ]]; echo $?)"
  chk "S12r the readiness step calls ready-poll and the reboot step calls reboot (a swapped subcommand would reboot early)" "$([[ "$(jq -r --argjson i "$ir" '.[$i].run' <<<"$steps")" == *"web2-rebirth.sh ready-poll"* && "$(jq -r --argjson i "$irb" '.[$i].run' <<<"$steps")" == *"web2-rebirth.sh reboot"* ]]; echo $?)"
  chk "S12s the emptiness step's detached-mode switch is exactly the detach-done verdict (not a constant)" "$([[ "$(jq -r '[.[] | select(.name | startswith("Emptiness evidence"))][0].env.W2R_DETACHED' <<<"$steps")" == "\${{ steps.classify.outputs.verdict == 'heal:detach_done' && '1' || '0' }}" ]]; echo $?)"
  chk "S12t the reboot step receives the never-pooled proof" "$([[ "$(jq -r --argjson i "$irb" '.[$i].env.NEVER_POOLED' <<<"$steps")" == "\${{ steps.pooled.outputs.verdict }}" ]]; echo $?)"
  chk "S12u the main-only guard is exactly github.ref == refs/heads/main" "$([[ "$(jqt '.job_if')" == "\${{ github.ref == 'refs/heads/main' }}" ]]; echo $?)"
  chk "S12v the preflights that gate the destructive path are present and fail closed (empty WANT hash, digest shape, SENTRY_DSN read and non-empty)" "$([[ "$(jqs '[.[] | select(.name | startswith("Coherence preflight"))][0].run')" == *'-z "$WANT"'* && "$(jqs '[.[] | select(.name | startswith("Coherence preflight"))][0].run')" == *host-image-coherence-preflight.sh* && "$(jqs '[.[] | select(.name | startswith("Resolve the image digest"))][0].run')" == *'sha256:[0-9a-f]{64}'* && "$(jqs '[.[] | select(.name | startswith("Extract backend credentials"))][0].run')" == *'-z "$DSN"'* && "$(jqs '[.[] | select(.name | startswith("Extract backend credentials"))][0].run')" == *'dsn_rc'* ]]; echo $?)"
  chk "S12w the resume plan drops -replace and the post plan keeps it otherwise (the gate's resume mode would refuse a replace anyway)" "$([[ "$(jq -r --argjson i "$ipost" '.[$i].run' <<<"$steps")" == *'if [[ "$VERDICT" == "resume:post_apply" ]]; then MODE=resume; REPLACE=(); fi'* ]]; echo $?)"
  chk "S12b the write steps exist (a guard over an empty set is vacuous)" "$([[ "$(jq -r '[.[] | select(((.run // "") | test("web2-rebirth\\.sh (delete-volume|state-rm|reboot|ready-poll)|terraform apply")))] | length' <<<"$steps")" -ge 4 ]]; echo $?)"
  local tg_pre tg_post
  tg_pre="$(jq -r --argjson i "$ipre" '.[$i].run' <<<"$steps" | grep -oE "(-target|-replace)='[^']+'" | LC_ALL=C sort | tr '\n' ' ')"
  tg_post="$(jq -r --argjson i "$ipost" '.[$i].run' <<<"$steps" | grep -oE "(-target|-replace)='[^']+'" | LC_ALL=C sort | tr '\n' ' ')"
  chk "S13 both plans carry exactly the same five targets plus one replace of the server" "$([[ "$tg_pre" == "$tg_post" && "$(wc -w <<<"$tg_pre")" -eq 6 && "$tg_pre" == *"-replace='hcloud_server.web[\"web-2\"]'"* && "$tg_pre" == *"-target='hcloud_firewall_attachment.web'"* && "$tg_pre" == *"-target='hcloud_volume.workspaces[\"web-2\"]'"* && "$tg_pre" == *"-target='hcloud_volume_attachment.workspaces[\"web-2\"]'"* && "$tg_pre" == *"-target='hcloud_server_network.web[\"web-2\"]'"* && "$tg_pre" == *"-target='hcloud_server.web[\"web-2\"]'"* && "$tg_pre" != *web-1* ]]; echo $?)"
  chk "S14 the plan gate is called with the right mode at both plans" "$([[ "$(jq -r --argjson i "$ipre" '.[$i].run' <<<"$steps")" == *"if ! web_host_rebirth_gate pre tfplan-pre.json web-2"* && "$(jq -r --argjson i "$ipost" '.[$i].run' <<<"$steps")" == *'if ! web_host_rebirth_gate "$MODE" tfplan-post.json web-2'* ]]; echo $?)"
  chk "S15 the classifier runs with APPLY and the delete and state-rm steps receive its verdict" "$([[ "$(jq -r --argjson i "$ic" '.[$i].run' <<<"$steps")" == *'web2-rebirth.sh classify "$APPLY"'* && "$(jq -r --argjson i "$ds" '.[$i].env.VERDICT' <<<"$steps")" == *steps.classify.outputs.verdict* && "$(jq -r --argjson i "$sr" '.[$i].env.VERDICT' <<<"$steps")" == *steps.classify.outputs.verdict* ]]; echo $?)"
  chk "S16 no plan file is uploaded and no artifact step exists" "$([[ "$(jqs '[.[] | select((.uses // "") | test("upload-artifact|cache"))] | length')" == 0 ]]; echo $?)"
  chk "S17 no xtrace, no insecure curl, no token in a command line" "$(! grep -nE '(^|[^[:alnum:]_])set -[a-z]*x|-k |--insecure|Bearer \$' "$wf" | grep -v '^[0-9]*:\s*#' | grep -q .; echo $?)"
  chk "S18 the cleanup step runs always and removes the plan files" "$([[ "$(jq -r '[.[] | select(.name | startswith("Remove plan files"))][0] | "\(.if)|\(.run)"' <<<"$steps")" == "always()|"*tfplan-pre*tfplan-post* ]]; echo $?)"
  chk "S19 the typed confirm and the image-tag shape are validated by the first step" "$([[ "$(jq -r '.[0].run' <<<"$steps")" == *'"REBIRTH-web-2-LUKS"'* && "$(jq -r '.[0].run' <<<"$steps")" == *'PINNED_VOLUME_ID'* ]]; echo $?)"
  chk "S20 the flip precondition runs for every dispatch (plan_only reports it, apply refuses)" "$([[ "$(jq -r --argjson i "$ifl" '.[$i].if' <<<"$steps")" == null && "$(jq -r --argjson i "$ifl" '.[$i].run' <<<"$steps")" == *'flip-precondition "$APPLY"'* ]]; echo $?)"
  chk "S21 the never-pooled step binds the marker token to that one step only" "$([[ "$(jqs '[.[] | select((.env // {}) | tostring | contains("DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER"))] | length')" == 1 ]]; echo $?)"
  chk "S21b the marker token name occurs ONCE in the whole file outside comments (not at workflow/job env, not in another step's run text)" "$([[ "$(grep -v '^[[:space:]]*#' "$wf" | grep -c 'DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER')" == 1 && "$(jqs '[.[] | select((.name | startswith("Never-pooled evidence")))][0].env | keys | join(",")')" == "DOPPLER_TOKEN" ]]; echo $?)"

  chk "S22 no step is continue-on-error (a failed step must be a red run)" "$([[ "$(jqs '[.[] | select(.cont != null and .cont != false)] | length')" == 0 ]]; echo $?)"

  # ---- parity: the literals this operation restates must equal their authorities (a drifted copy is a wrong target)
  local FORGET="$REPO/.github/workflows/workspaces-plaintext-forget.yml" GATE="$REPO/tests/scripts/lib/web-host-rebirth-gate.sh" SERVER_TF="$REPO/apps/web-platform/infra/server.tf"
  local pp="$TMP/parity.$BASHPID.py"
  cat > "$pp" <<'PY3'
import re, sys
forget = open(sys.argv[1]).read(); mine = open(sys.argv[2]).read()
def fn(text, name):
    m = re.search(r'^[ \t]*' + name + r'\(\) \{\n(.*?)^[ \t]*\}\n', text, re.S | re.M)
    return None if not m else re.sub(r'\s+', ' ', m.group(1)).strip()
bad = []
for name in ("errcode", "fail"):
    a, b = fn(forget, name), fn(mine, name)
    if a is None or b is None or a != b: bad.append(name + "()")
curl = "curl -sS --max-time 15 --config - -X \"$1\" \"${extra[@]}\" -o \"$HBODY\" -w '%{http_code}' \"https://api.hetzner.cloud/v1$2\""
# The orchestrator's copy is the forget workflow's line plus the transport confinement the shell-trace lint demands of a credentialed curl
# (--disable FIRST, --noproxy '*'): equal in every other byte.
hard = curl.replace("curl -sS", "curl --disable --noproxy '*' -sS", 1)
if curl not in forget or hard not in mine: bad.append("curl line")
def const(text, pat):
    m = re.search(pat, text, re.M); return m.group(1) if m else None
pairs = [("WEB1_SERVER_ID", r'^\s*WEB1_SERVER_ID: "(\d+)"', r'^WEB1_SERVER_ID="(\d+)"'),
         ("LUKS_VOLUME_ID", r'^\s*LUKS_VOLUME_ID: "(\d+)"', r'^LUKS_VOLUME_ID="(\d+)"'),
         ("WEB1_SERVER_NAME", r'^\s*WEB1_SERVER_NAME: (\S+)', r'^WEB1_SERVER_NAME="([^"]+)"')]
for n, pf, pm in pairs:
    a, b = const(forget, pf), const(mine, pm)
    if a is None or a != b: bad.append(n)
print(",".join(bad) if bad else "equal")
PY3
  if [[ -f "$FORGET" ]]; then
    chk "S30 the Hetzner helpers (errcode, fail, the curl line) and the web-1 constants equal the forget workflow's copies" "$([[ "$(python3 "$pp" "$FORGET" "$SCRIPT_REAL")" == equal ]]; echo $?)"
  else
    # The forget workflow is single-use and is deleted by its own closing PR; the constants then have no second copy to drift from.
    chk "S30 (forget workflow retired: nothing to compare against)" 0
  fi
  local sname slabel
  sname="$(sed -nE 's/^PINNED_VOLUME_NAME="([^"]+)".*/\1/p' "$SCRIPT_REAL" | head -1)"
  slabel="$(sed -nE 's/^VOLUME_LABEL_APP="([^"]+)".*/\1/p' "$SCRIPT_REAL" | head -1)"
  chk "S31 the volume name literal equals the gate's template and server.tf's name for web-2" "$([[ "$sname" == soleur-web-platform-data-web-2 && "$(grep -c 'soleur-web-platform-data-\\(\$k)' "$GATE")" -ge 1 && "$(grep -c '"soleur-web-platform-data-${each.key}"' "$SERVER_TF")" -ge 1 ]]; echo $?)"
  chk "S32 the volume label literal equals the gate's constant and server.tf's label" "$([[ "$slabel" == "$(sed -nE 's/^_WEB_HOST_REBIRTH_VOLUME_LABEL_APP="([^"]+)".*/\1/p' "$GATE")" && -n "$slabel" && "$(awk '/resource "hcloud_volume" "workspaces"/{f=1} f&&/app +=/{print; exit}' "$SERVER_TF")" == *"\"$slabel\""* ]]; echo $?)"

  # ---- behavioral: the extracted step bodies run under GitHub's production shell
  local sb="$TMP/sb.$RANDOM"; mkdir -p "$sb/apps/web-platform/infra" "$sb/tests/scripts/lib" "$sb/bin" "$sb/scripts"
  cp "$REPO/tests/scripts/lib/web-host-rebirth-gate.sh" "$REPO/tests/scripts/lib/plan-gate-preamble.sh" "$sb/tests/scripts/lib/"
  cat > "$sb/tests/scripts/lib/stock-preflight-gate.sh" <<'SH'
stock_preflight_gate() { [[ -z "${STOCK_FAIL:-}" ]]; }
SH
  cat > "$sb/bin/doppler" <<'SH'
#!/usr/bin/env bash
# doppler run ... -- <cmd...>: run the command after `--`
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done; shift; exec "$@"
SH
  cat > "$sb/bin/terraform" <<'SH'
#!/usr/bin/env bash
case "$1" in
  plan) for a in "$@"; do case "$a" in -out=*) : > "${a#-out=}" ;; esac; done; echo "terraform plan stub"; exit "${PLAN_RC:-0}" ;;
  show) cat "${FIXTURE:?}" ;;
  apply) echo "$*" > "${APPLY_ARGS:?}"; exit "${APPLY_RC:-0}" ;;
  *) echo "unexpected terraform $*" >&2; exit 9 ;;
esac
SH
  chmod +x "$sb/bin/"*
  runstep() { # <step-name-prefix> <cwd-rel> [ENV=VAL ...]  -> sets RC, OUT
    local name="$1" cwd="$2"; shift 2
    python3 "$TMP/wfq.py" "$wf" body "$name" > "$sb/step.sh" 2>/dev/null || { RC=99; OUT="no such step: $name"; return; }
    : > "$sb/gh_env"; : > "$sb/gh_out"
    OUT="$(cd "$sb/$cwd" && env -i PATH="$sb/bin:/usr/bin:/bin" HOME="$sb" GITHUB_WORKSPACE="$sb" GITHUB_ENV="$sb/gh_env" GITHUB_OUTPUT="$sb/gh_out" \
      RUNNER_TEMP="$sb" PINNED_VOLUME_ID=106466179 PINNED="ghcr.io/x@sha256:abc" CI_SSH_PUB=/tmp/k.pub HCLOUD_TOKEN=tok DOPPLER_TOKEN=d WEB2_SID=1001 "$@" \
      bash --noprofile --norc -e "$sb/step.sh" 2>&1)"; RC=$?
  }
  # validate step
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW=v3.1.2 PLAN_ONLY_RAW=true REASON_RAW=why
  chk "B1 a valid plan_only dispatch passes and APPLY=no" "$([[ "$RC" -eq 0 && "$(grep -c '^APPLY=no$' "$sb/gh_env")" == 1 && "$(grep -c '^STARTED_AT=' "$sb/gh_env")" == 1 ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW=3.1.2 PLAN_ONLY_RAW=false REASON_RAW=why
  chk "B2 plan_only=false passes and APPLY=yes (and a tag without the v is accepted)" "$([[ "$RC" -eq 0 && "$(grep -c '^APPLY=yes$' "$sb/gh_env")" == 1 ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-1-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW=v3.1.2 PLAN_ONLY_RAW=true REASON_RAW=why
  chk "B3 a wrong typed confirm is refused and nothing is exported" "$([[ "$RC" -ne 0 && ! -s "$sb/gh_env" ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106443278 IMAGE_TAG_RAW=v3.1.2 PLAN_ONLY_RAW=true REASON_RAW=why
  chk "B4 a volume id that is not the pin (web-1's LUKS volume) is refused" "$([[ "$RC" -ne 0 && ! -s "$sb/gh_env" ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW='latest' PLAN_ONLY_RAW=true REASON_RAW=why
  chk "B5 a non-semver image tag is refused" "$([[ "$RC" -ne 0 ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW='v1.2.3; id' PLAN_ONLY_RAW=true REASON_RAW=why
  chk "B6 an injection-shaped image tag is refused" "$([[ "$RC" -ne 0 ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW=v3.1.2 PLAN_ONLY_RAW=true REASON_RAW=
  chk "B7 an empty reason is refused" "$([[ "$RC" -ne 0 ]]; echo $?)"
  # emptiness step: the verdict is exported AND the exit code is propagated
  printf '#!/usr/bin/env bash\necho "RED reason=not_empty max_used_bytes=5"\nexit 1\n' > "$sb/scripts/web2-rebirth-emptiness.sh"
  runstep 'Emptiness evidence' .
  chk "B8 a RED emptiness verdict fails the step and is exported" "$([[ "$RC" -ne 0 && "$(cat "$sb/gh_out")" == verdict=RED* ]]; echo $?)"
  printf '#!/usr/bin/env bash\necho "PASS hours=168"\nexit 0\n' > "$sb/scripts/web2-rebirth-emptiness.sh"
  runstep 'Emptiness evidence' .
  chk "B9 a PASS emptiness verdict passes the step" "$([[ "$RC" -eq 0 && "$(cat "$sb/gh_out")" == "verdict=PASS hours=168" ]]; echo $?)"
  # pre plan: the gate's rc is honored
  runstep 'Terraform plan `pre`' apps/web-platform/infra FIXTURE="$FIX/pre.json" WEB2_SID=1001
  chk "B10 the canonical pre plan passes the wired gate" "$([[ "$RC" -eq 0 && "$OUT" == *"pre plan graded"* ]]; echo $?)"
  jq '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.actions) = ["delete"]' "$FIX/pre.json" > "$sb/pre.bad.json"
  runstep 'Terraform plan `pre`' apps/web-platform/infra FIXTURE="$sb/pre.bad.json" WEB2_SID=1001
  chk "B11 a pre plan that deletes the volume fails the step and never reaches the success line" "$([[ "$RC" -ne 0 && "$OUT" != *"pre plan graded"* && "$OUT" == *"REFUSED the pre plan"* ]]; echo $?)"
  runstep 'Terraform plan `pre`' apps/web-platform/infra FIXTURE="$FIX/pre.json" WEB2_SID=4242
  chk "B12 a captured server id that differs from the plan's is refused (the pin is wired)" "$([[ "$RC" -ne 0 && "$OUT" != *"pre plan graded"* ]]; echo $?)"
  runstep 'Terraform plan `pre`' apps/web-platform/infra FIXTURE="$FIX/pre.json" WEB2_SID=1001 STOCK_FAIL=1
  chk "B13 a failed stock preflight fails the step" "$([[ "$RC" -ne 0 && "$OUT" != *"pre plan graded"* ]]; echo $?)"
  runstep 'Terraform plan `pre`' apps/web-platform/infra FIXTURE="$FIX/pre.json" WEB2_SID=1001 PLAN_RC=1
  chk "B14 a failed terraform plan fails the step" "$([[ "$RC" -ne 0 ]]; echo $?)"
  # post plan: the mode follows the verdict
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$FIX/post.json" WEB2_SID=1001 VERDICT=proceed
  chk "B15 the canonical post plan passes in mode post" "$([[ "$RC" -eq 0 && "$OUT" == *"post plan graded (post)"* ]]; echo $?)"
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$FIX/post.json" WEB2_SID=1001 VERDICT=heal:volume_created
  chk "B16 heal:volume_created grades in mode post-heal (so a create-volume plan is refused there)" "$([[ "$RC" -ne 0 && "$OUT" == *"REFUSED the post-heal plan"* ]]; echo $?)"
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$FIX/resume.json" WEB2_SID=2002 VERDICT=resume:post_apply
  chk "B15b the resume plan (adds only, no replace) passes in mode resume, with no stock preflight" "$([[ "$RC" -eq 0 && "$OUT" == *"post plan graded (resume)"* ]]; echo $?)"
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$FIX/resume.json" WEB2_SID=2002 VERDICT=resume:post_apply STOCK_FAIL=1
  chk "B15d the stock preflight is NOT run on a resume (a failing one would block a read-only resume)" "$([[ "$RC" -eq 0 && "$OUT" == *"post plan graded (resume)"* ]]; echo $?)"
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$FIX/post.json" WEB2_SID=2002 VERDICT=resume:post_apply
  chk "B15c a replace plan is REFUSED on a resume (the rebirth plan must never run twice)" "$([[ "$RC" -ne 0 && "$OUT" == *"REFUSED the resume plan"* ]]; echo $?)"
  jq '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after) += {"format":"ext4"}' "$FIX/post.json" > "$sb/post.bad.json"
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$sb/post.bad.json" WEB2_SID=1001 VERDICT=proceed
  chk "B17 a post plan that creates a formatted volume fails the step" "$([[ "$RC" -ne 0 && "$OUT" != *"post plan graded"* ]]; echo $?)"
  # apply step: applies exactly tfplan-post; a failing apply fails the step
  runstep 'Terraform apply' apps/web-platform/infra APPLY_ARGS="$sb/apply.args"
  chk "B19 the apply step applies exactly tfplan-post (the graded plan) and nothing else" "$([[ "$RC" -eq 0 && "$(cat "$sb/apply.args")" == "apply -no-color -input=false tfplan-post" ]]; echo $?)"
  runstep 'Terraform apply' apps/web-platform/infra APPLY_ARGS="$sb/apply.args" APPLY_RC=1
  chk "B20 a failed apply fails the step and says the window heals on re-dispatch" "$([[ "$RC" -ne 0 && "$OUT" == *"Re-dispatch with the same inputs"* ]]; echo $?)"
  # ready and recovery steps: the stub scripts' output is captured AND their exit code propagates
  mkdir -p "$sb/scripts"
  printf '#!/usr/bin/env bash\necho "ready: GREEN boot_id=x age_s=5 luks_arm=formatted"\nexit 0\n' > "$sb/scripts/web2-rebirth.sh"
  runstep 'Wait for the fresh-boot readiness row' .
  chk "B21 a passing readiness poll exports its line" "$([[ "$RC" -eq 0 && "$(cat "$sb/gh_out")" == line=ready:\ GREEN* ]]; echo $?)"
  printf '#!/usr/bin/env bash\necho "attempt 1: RED reason=ready_escrow"\nexit 1\n' > "$sb/scripts/web2-rebirth.sh"
  runstep 'Wait for the fresh-boot readiness row' .
  chk "B22 a failing readiness poll fails the step (the exit code is propagated, not swallowed by the capture)" "$([[ "$RC" -ne 0 ]]; echo $?)"
  printf '#!/usr/bin/env bash\necho "::add-mask::SECRETPASSPHRASE"\necho "web2-rebirth-recovery-check: PASS birth-time consistency check; restore NOT exercised"\nprintf "escrow object: key=k size_bytes=1 etag=e;escrow checks: single_object=yes\\n" > "$W2_FACTS_FILE"\nexit 0\n' > "$sb/scripts/web2-rebirth-recovery-check.sh"
  runstep 'Birth-time recovery check' . TF_VAR_doppler_token_tf=dp.pt.x
  chk "B23 a passing recovery check exports the escrow facts (read from W2_FACTS_FILE)" "$([[ "$RC" -eq 0 && "$(cat "$sb/gh_out")" == facts=escrow\ object:* ]]; echo $?)"
  chk "B23b the recovery step never writes the script's stdout (the ::add-mask:: lines) to disk" "$([[ -z "$(grep -rlF SECRETPASSPHRASE "$sb" --include='*' 2>/dev/null | grep -v '/scripts/')" && ! -e "$sb/recovery.out" ]]; echo $?)"
  printf '#!/usr/bin/env bash\necho "::error::boom"\nexit 1\n' > "$sb/scripts/web2-rebirth-recovery-check.sh"
  runstep 'Birth-time recovery check' . TF_VAR_doppler_token_tf=dp.pt.x
  chk "B24 a failing recovery check fails the step" "$([[ "$RC" -ne 0 ]]; echo $?)"
  runstep 'Birth-time recovery check' .
  chk "B25 a missing provider token refuses the recovery check before any call" "$([[ "$RC" -ne 0 && "$OUT" == *TF_VAR_doppler_token_tf* ]]; echo $?)"
  # the resolver takes the BARE version: the stripped form works and the unstripped one is the bug the strip prevents
  chk "B26 the real tag resolver accepts the stripped version" "$([[ "$(bash "$REPO/apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh" 3.1.2 2>/dev/null)" == v3.1.2 ]]; echo $?)"
  chk "B27 the real tag resolver rejects a v-prefixed input (the burned-dispatch bug the strip closes)" "$(bash "$REPO/apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh" v3.1.2 >/dev/null 2>&1; [[ $? -ne 0 ]]; echo $?)"
  # cleanup step
  touch "$sb/apps/web-platform/infra/tfplan-pre" "$sb/apps/web-platform/infra/tfplan-post.json" "$sb/apps/web-platform/infra/terraform.tfstate.backup"
  runstep 'Remove plan files' apps/web-platform/infra
  chk "B18 the cleanup removes plan files and any state backup" "$([[ "$RC" -eq 0 && ! -e "$sb/apps/web-platform/infra/tfplan-pre" && ! -e "$sb/apps/web-platform/infra/terraform.tfstate.backup" ]]; echo $?)"
  printf 'RAN %s\n' "$n"
}

fails=0; ran=0
report="$(battery "$WF_REAL" 2>&1)"
while IFS= read -r line; do
  case "$line" in FAILED*) fails=$((fails + 1)); printf 'FAIL - %s\n' "${line#FAILED }" ;; RAN*) ran="${line#RAN }" ;; *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;; esac
done <<<"$report"
printf 'real workflow: %s assertions, %s failed\n' "$ran" "$fails"
[[ "$ran" -ge 84 ]] || { echo "FAIL - assertion floor: ran ${ran} < 84"; fails=$((fails + 1)); }

# Mutants are independent (each works on its own copy of the workflow and its own sandbox), so up to MUT_JOBS run at once; every mutant
# writes its verdict line to its own file and the lines are counted once all have finished.
MUT_JOBS="${MUT_JOBS:-6}"; MUT_SEQ=0; mkdir -p "$TMP/mres"
_mutate_run() { # <idx> <label> <old> <new>
  local idx="$1" label="$2" old="$3" new="$4" copy="$TMP/mut.$BASHPID.yml" after
  cp "$WF_REAL" "$copy"
  if ! python3 - "$copy" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then echo "FAIL - mutation '${label}': the edit did not land exactly once (a mutant that lands nothing proves nothing)" > "$TMP/mres/$idx"; return; fi
  local bout; bout="$(battery "$copy" 2>&1)"
  if grep -q '^FAILED S0' <<<"$bout"; then echo "FAIL - mutation '${label}' broke the YAML: a parse error is not a kill" > "$TMP/mres/$idx"; rm -f "$copy"; return; fi
  after="$(grep -c '^FAILED' <<<"$bout")"
  if [[ "$after" -gt 0 ]]; then echo "ok   - mutation killed: ${label} (${after} rows red)" > "$TMP/mres/$idx"; else echo "FAIL - mutation SURVIVED: ${label}" > "$TMP/mres/$idx"; fi
  rm -f "$copy"
}
mutate() { # <label> <old> <new>
  MUT_SEQ=$((MUT_SEQ + 1))
  while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MUT_JOBS" ]]; do sleep 0.3; done
  _mutate_run "$MUT_SEQ" "$@" &
}
mutate "the APPLY guard is removed from the delete step" "        id: delete
        if: \${{ env.APPLY == 'yes' }}
" "        id: delete
"
mutate "the APPLY guard is removed from the reboot step" "      - name: Issue the hcloud reboot (the reopen is graded later, never claimed here)
        if: \${{ env.APPLY == 'yes' }}
" "      - name: Issue the hcloud reboot (the reopen is graded later, never claimed here)
"
mutate "the APPLY guard is removed from the post plan" "      - name: Terraform plan \`post\` (graded; the raw volume is created, or on resume only missing siblings are added) + stock preflight
        if: \${{ env.APPLY == 'yes' }}
" "      - name: Terraform plan \`post\` (graded; the raw volume is created, or on resume only missing siblings are added) + stock preflight
"
mutate "the resume plan keeps -replace (a resume would replace the new host)" 'if [[ "$VERDICT" == "resume:post_apply" ]]; then MODE=resume; REPLACE=(); fi' 'if [[ "$VERDICT" == "resume:post_apply" ]]; then MODE=resume; fi'
mutate "the apply step gains a resume exclusion that skips a needed add" "      - name: Terraform apply (exactly the graded post plan)
        if: \${{ env.APPLY == 'yes' }}" "      - name: Terraform apply (exactly the graded post plan)
        if: \${{ env.APPLY == 'yes' && steps.classify.outputs.verdict != 'resume:post_apply' }}"
mutate "the delete step if: gains an always() (a substring check would pass)" "        id: delete
        if: \${{ env.APPLY == 'yes' }}" "        id: delete
        if: \${{ always() && env.APPLY == 'yes' }}"
mutate "the delete step loses the flip proof" '          FLIP: ${{ steps.flip.outputs.met }}' '          FLIP: met'
mutate "the pre plan exports a literal the script does not accept" "printf 'graded=graded\\n' >> \"\$GITHUB_OUTPUT\"" "printf 'graded=pre\\n' >> \"\$GITHUB_OUTPUT\""
mutate "the reboot step loses the never-pooled proof" '          NEVER_POOLED: ${{ steps.pooled.outputs.verdict }}
        run: bash scripts/web2-rebirth.sh reboot' '        run: bash scripts/web2-rebirth.sh reboot'
mutate "the resume plan grades in the wrong mode" 'then MODE=resume; REPLACE=(); fi' 'then MODE=post; REPLACE=(); fi'
mutate "the recovery step captures stdout to a file again" '          facts="${RUNNER_TEMP}/recovery-facts.txt"; rc=0' '          facts="${RUNNER_TEMP}/recovery-facts.txt"; rc=0; : > "${RUNNER_TEMP}/recovery.out"; echo ::add-mask::SECRETPASSPHRASE > "${RUNNER_TEMP}/recovery.out"'
mutate "the stock preflight runs on a resume too" '          if [[ "$MODE" != resume ]]; then
            HCLOUD_TOKEN=' '          if true; then
            HCLOUD_TOKEN='
mutate "the delete step swallows a failure" '        run: bash scripts/web2-rebirth.sh delete-volume' '        run: bash scripts/web2-rebirth.sh delete-volume || true'
mutate "the emptiness step never runs" "      - name: Emptiness evidence (7 days of Better Stack host_metrics, fail-closed)
        id: emptiness
        if: \${{ steps.classify.outputs.verdict == 'proceed' || steps.classify.outputs.verdict == 'heal:detach_done' }}" "      - name: Emptiness evidence (7 days of Better Stack host_metrics, fail-closed)
        id: emptiness
        if: false"
mutate "the never-pooled step never runs" "        id: pooled" "        id: pooled
        if: false"
mutate "the pre plan never runs" "        id: preplan
        if: \${{ steps.classify.outputs.verdict == 'proceed' || steps.classify.outputs.verdict == 'heal:detach_done' }}" "        id: preplan
        if: false"
mutate "the delete step no longer receives the emptiness proof" 'evidence step leaves its output empty.
          EMPTINESS: ${{ steps.emptiness.outputs.verdict }}
' 'evidence step leaves its output empty.
'
mutate "the delete step no longer receives the pre-plan proof" '
          PRE_PLAN: ${{ steps.preplan.outputs.graded }}' ''
mutate "the apply step gains -auto-approve" '            terraform apply -no-color -input=false tfplan-post; then' '            terraform apply -no-color -input=false -auto-approve tfplan-post; then'
mutate "the apply step applies the PRE plan" '            terraform apply -no-color -input=false tfplan-post; then' '            terraform apply -no-color -input=false tfplan-pre; then'
mutate "the apply failure no longer exits" '            echo "::error::terraform apply (rebirth of web-2) failed. The empty volume is already gone; web-2 is dark and standby-only. Re-dispatch with the same inputs: the classifier names the window and heals it."
            exit 1' '            echo "::error::terraform apply (rebirth of web-2) failed. The empty volume is already gone; web-2 is dark and standby-only. Re-dispatch with the same inputs: the classifier names the window and heals it."
            exit 0'
mutate "the pin step no longer strips the v" '"${IMAGE_TAG_INPUT#v}"' '"${IMAGE_TAG_INPUT}"'
mutate "the cryptsetup install step is not recognised (moved out of the classified set)" '      - name: Install cryptsetup (read-only header check)' '      - name: Fetch cryptsetup (read-only header check)'
mutate "the preflight gains a || true" 'run: bash scripts/web-host-escrow-preflight.sh' 'run: bash scripts/web-host-escrow-preflight.sh || true'
mutate "the pre-plan gate call is disabled" 'if ! web_host_rebirth_gate pre tfplan-pre.json web-2 "$WEB2_SID" "$PINNED_VOLUME_ID"; then' 'if false; then'
mutate "the post-plan mode no longer follows the verdict" '[[ "$VERDICT" == "heal:volume_created" ]] && MODE=post-heal' ':'
mutate "actions: read is dropped" '  actions: read
' ''
mutate "the job concurrency literal changes" 'group: web-1-swap' 'group: web-2-swap'
mutate "the workflow concurrency literal changes" 'group: terraform-apply-web-platform-host' 'group: web2-rebirth'
mutate "plan_only defaults to false" '        default: true' '        default: false'
mutate "a sixth target is added to the post plan" "              -target='hcloud_firewall_attachment.web' \\
              -var=\"ssh_key_path=\${CI_SSH_PUB}\" \\
              -var=\"image_name=\${PINNED}\"
          rc=\$?
          [[ \$rc -eq 0 ]] || { echo \"::error::terraform plan (post)" "              -target='hcloud_firewall_attachment.web' \\
              -target='hcloud_server.web[\"web-1\"]' \\
              -var=\"ssh_key_path=\${CI_SSH_PUB}\" \\
              -var=\"image_name=\${PINNED}\"
          rc=\$?
          [[ \$rc -eq 0 ]] || { echo \"::error::terraform plan (post)"
mutate "the typed confirm check is dropped" '[[ "$CONFIRM_RAW" == "REBIRTH-web-2-LUKS" ]] || { echo "::error::confirm must be exactly REBIRTH-web-2-LUKS"; exit 1; }' ':'
mutate "the volume pin check is dropped" '[[ "$VOLUME_RAW" == "$PINNED_VOLUME_ID" ]] || { echo "::error::expected_volume_id must equal the constant pin ${PINNED_VOLUME_ID}"; exit 1; }' ':'
mutate "the emptiness exit code is swallowed" '          exit "$rc"

      - name: Never-pooled' '          exit 0

      - name: Never-pooled'
mutate "the readiness poll exit code is swallowed" '          printf '"'"'line=%s\n'"'"' "$(grep -E '"'"'^ready:'"'"' "$out" | tail -n 1 | head -c 400)" >> "$GITHUB_OUTPUT"
          exit "$rc"' '          printf '"'"'line=%s\n'"'"' "$(grep -E '"'"'^ready:'"'"' "$out" | tail -n 1 | head -c 400)" >> "$GITHUB_OUTPUT"
          exit 0'
mutate "the recovery check exit code is swallowed" 'tr '"'"'\n'"'"' '"'"' '"'"')" >> "$GITHUB_OUTPUT"; fi
          exit "$rc"' 'tr '"'"'\n'"'"' '"'"' '"'"')" >> "$GITHUB_OUTPUT"; fi
          exit 0'
mutate "the environment is swapped for the reviewer-less one" 'environment: web-platform-infra-apply' 'environment: infra-privileged'
mutate "the main-only guard is removed" "    if: \${{ github.ref == 'refs/heads/main' }}
" ''
mutate "the cleanup no longer runs always" "      - name: Remove plan files and any local state backup
        if: always()
" "      - name: Remove plan files and any local state backup
"
mutate "the cleanup misses timestamped state backups" ' ./terraform.tfstate.*.backup' ''
mutate "an artifact upload step is added" "      - name: Dispatch summary
        if: always()" "      - name: Upload plan
        uses: actions/upload-artifact@v4
        with:
          name: plan
          path: tfplan-post
      - name: Dispatch summary
        if: always()"
mutate "an unclassified destructive step is added" "      - name: Dispatch summary
        if: always()" "      - name: Purge the other volume
        run: curl -X DELETE https://api.hetzner.cloud/v1/volumes/106443278
      - name: Dispatch summary
        if: always()"
mutate "the marker write token is bound at workflow level" '  PINNED_VOLUME_ID: "106466179"' '  PINNED_VOLUME_ID: "106466179"
  DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER: ${{ secrets.DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER }}'
mutate "the pinned volume constant drifts" 'PINNED_VOLUME_ID: "106466179"' 'PINNED_VOLUME_ID: "106443278"'
mutate "the readiness wait is made non-fatal" '        id: ready
        run: |' '        id: ready
        continue-on-error: true
        run: |'
mutate "the job stops exporting the verdict" '    outputs:
      verdict: ${{ steps.classify.outputs.verdict }}
' ''

wait
for f in "$TMP"/mres/*; do cat "$f"; grep -q '^FAIL' "$f" && fails=$((fails + 1)); done
[[ "$(find "$TMP/mres" -type f | wc -l | tr -d ' ')" -eq "$MUT_SEQ" ]] || { echo "FAIL - a mutant did not report ($(find "$TMP/mres" -type f | wc -l | tr -d ' ') of ${MUT_SEQ})"; fails=$((fails + 1)); }
echo
if [[ "$fails" -gt 0 ]]; then echo "web2-luks-rebirth-workflow: ${fails} FAILED"; exit 1; fi
echo "web2-luks-rebirth-workflow: all rows and mutations passed"
