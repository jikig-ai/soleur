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
  steps="$(python3 "$TMP/wfq.py" "$wf" steps)"; top="$(python3 "$TMP/wfq.py" "$wf" top)"
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
  chk "S8 the job timeout is bounded" "$([[ "$(jqt '.job_timeout')" -le 60 ]]; echo $?)"

  local pf; pf="$(idx 'Escrow readiness preflight')"
  chk "S9 the escrow preflight is exactly the pinned one-liner with a 2-minute bound, DOPPLER_TOKEN only and no condition" "$([[ "$pf" -ge 0 && "$(jq -r --argjson i "$pf" '.[$i].run | rtrimstr("\n")' <<<"$steps")" == "bash scripts/web-host-escrow-preflight.sh" && "$(jq -r --argjson i "$pf" '.[$i].timeout' <<<"$steps")" == 2 && "$(jq -r --argjson i "$pf" '.[$i].if' <<<"$steps")" == null && "$(jq -r --argjson i "$pf" '.[$i].env | keys | join(",")' <<<"$steps")" == DOPPLER_TOKEN && "$(jq -r --argjson i "$pf" '.[$i].wd' <<<"$steps")" == null && "$(jq -r --argjson i "$pf" '.[$i].shell' <<<"$steps")" == null && "$(jq -r --argjson i "$pf" '.[$i].cont' <<<"$steps")" == null ]]; echo $?)"
  local first_tf
  first_tf="$(jq -r '[to_entries[] | select((.value.run // "") | test("(^|[^A-Za-z0-9_-])terraform +(init|plan|apply|state|console|show|output)|web2-rebirth|api\\.hetzner|curl "))] | first | .key // -1' <<<"$steps")"
  chk "S10 the preflight precedes every Terraform command, script call and API call" "$([[ "$pf" -ge 0 && "$first_tf" -gt "$pf" ]]; echo $?)"

  local ic ip ipre ds sr ipost ia ir ir2 irb ifl
  ic="$(idx 'Classify state')"; ifl="$(idx 'Flip precondition')"; ipre="$(idx 'Terraform plan `pre`')"; ds="$(idx 'Delete the empty plaintext volume')"
  sr="$(idx 'Forget the volume')"; ipost="$(idx 'Terraform plan `post`')"; ia="$(idx 'Terraform apply')"; ir="$(idx 'Wait for the fresh-boot readiness row')"
  ir2="$(idx 'Birth-time recovery check')"; irb="$(idx 'Issue the hcloud reboot')"
  chk "S11 the steps run in the contracted order" "$([[ "$ic" -gt 0 && "$ifl" -gt "$ic" && "$ipre" -gt "$ifl" && "$ds" -gt "$ipre" && "$sr" -gt "$ds" && "$ipost" -gt "$sr" && "$ia" -gt "$ipost" && "$ir" -gt "$ia" && "$ir2" -gt "$ir" && "$irb" -gt "$ir2" ]]; echo $?)"
  local wr
  wr="$(jq -r '[.[] | select(((.run // "") | test("web2-rebirth\\.sh (delete-volume|state-rm|reboot|ready-poll)|terraform apply|web2-rebirth-recovery-check|apt-get install")) or (.name | startswith("Stamp run anchor")) or (.name | startswith("Terraform plan `post`")))] | map(select((.if // "") | contains("env.APPLY == '"'"'yes'"'"'") | not)) | map(.name) | join(" | ")' <<<"$steps")"
  chk "S12 every write step is gated on APPLY (no write is reachable under plan_only): ${wr}" "$([[ -z "$wr" ]]; echo $?)"
  chk "S12b the write steps exist (a guard over an empty set is vacuous)" "$([[ "$(jq -r '[.[] | select(((.run // "") | test("web2-rebirth\\.sh (delete-volume|state-rm|reboot|ready-poll)|terraform apply")))] | length' <<<"$steps")" -ge 5 ]]; echo $?)"
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

  chk "S22 no step is continue-on-error (a failed step must be a red run)" "$([[ "$(jqs '[.[] | select(.cont != null and .cont != false)] | length')" == 0 ]]; echo $?)"

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
  chk "B1 a valid plan_only dispatch passes and APPLY=no" "$([[ "$RC" -eq 0 && "$(cat "$sb/gh_env")" == "APPLY=no" ]]; echo $?)"
  runstep 'Validate dispatch inputs' . CONFIRM_RAW=REBIRTH-web-2-LUKS VOLUME_RAW=106466179 IMAGE_TAG_RAW=3.1.2 PLAN_ONLY_RAW=false REASON_RAW=why
  chk "B2 plan_only=false passes and APPLY=yes (and a tag without the v is accepted)" "$([[ "$RC" -eq 0 && "$(cat "$sb/gh_env")" == "APPLY=yes" ]]; echo $?)"
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
  jq '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after) += {"format":"ext4"}' "$FIX/post.json" > "$sb/post.bad.json"
  runstep 'Terraform plan `post`' apps/web-platform/infra FIXTURE="$sb/post.bad.json" WEB2_SID=1001 VERDICT=proceed
  chk "B17 a post plan that creates a formatted volume fails the step" "$([[ "$RC" -ne 0 && "$OUT" != *"post plan graded"* ]]; echo $?)"
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
[[ "$ran" -ge 42 ]] || { echo "FAIL - assertion floor: ran ${ran} < 42"; fails=$((fails + 1)); }

mutate() { # <label> <old> <new>
  local label="$1" old="$2" new="$3" copy="$TMP/mut.yml" after
  cp "$WF_REAL" "$copy"
  if ! python3 - "$copy" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then echo "FAIL - mutation '${label}': the edit did not land exactly once (a mutant that lands nothing proves nothing)"; fails=$((fails + 1)); return; fi
  after="$(battery "$copy" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "ok   - mutation killed: ${label} (${after} rows red)"; else echo "FAIL - mutation SURVIVED: ${label}"; fails=$((fails + 1)); fi
}
mutate "the APPLY guard is removed from the delete step" "      - name: Delete the empty plaintext volume through the Hetzner API (detach first; pinned id re-asserted)
        if: \${{ env.APPLY == 'yes' }}
" "      - name: Delete the empty plaintext volume through the Hetzner API (detach first; pinned id re-asserted)
"
mutate "the APPLY guard is removed from the reboot step" "      - name: Issue the hcloud reboot (the reopen is graded later, never claimed here)
        if: \${{ env.APPLY == 'yes' }}
" "      - name: Issue the hcloud reboot (the reopen is graded later, never claimed here)
"
mutate "the APPLY guard is removed from the post plan" "      - name: Terraform plan \`post\` (graded; the raw volume is created) + stock preflight
        if: \${{ env.APPLY == 'yes' }}
" "      - name: Terraform plan \`post\` (graded; the raw volume is created) + stock preflight
"
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
mutate "the emptiness exit code is swallowed" '          exit "$rc"' '          exit 0'
mutate "the environment is swapped for the reviewer-less one" 'environment: web-platform-infra-apply' 'environment: infra-privileged'
mutate "the main-only guard is removed" "    if: \${{ github.ref == 'refs/heads/main' }}
" ''
mutate "the cleanup no longer runs always" "      - name: Remove plan files and any local state backup
        if: always()
" "      - name: Remove plan files and any local state backup
"
mutate "an artifact upload step is added" "      - name: Dispatch summary
        if: always()" "      - name: Upload plan
        uses: actions/upload-artifact@v4
        with:
          name: plan
          path: tfplan-post
      - name: Dispatch summary
        if: always()"
mutate "the pinned volume constant drifts" 'PINNED_VOLUME_ID: "106466179"' 'PINNED_VOLUME_ID: "106443278"'
mutate "the readiness wait is made non-fatal" "      - name: Wait for the fresh-boot readiness row (luks=1 luks_arm=formatted escrow=ok, newer than this run)
        if: \${{ env.APPLY == 'yes' }}" "      - name: Wait for the fresh-boot readiness row (luks=1 luks_arm=formatted escrow=ok, newer than this run)
        if: \${{ env.APPLY == 'yes' }}
        continue-on-error: true"

echo
if [[ "$fails" -gt 0 ]]; then echo "web2-luks-rebirth-workflow: ${fails} FAILED"; exit 1; fi
echo "web2-luks-rebirth-workflow: all rows and mutations passed"
