#!/usr/bin/env bash
# Drift and behaviour guard for the Inngest key rotation route (#10540): .github/workflows/inngest-key-rotate.yml and its body
# scripts/inngest-key-rotate.sh.
#
# WHAT THIS PROTECTS. The route rotates the two shared secrets of the sole scheduler and reboots it. The failures that matter are
# silent or irreversible: key bytes in a PUBLIC log (Terraform prints a random_id's id, which IS the key in base64url), a write
# that runs although a precondition failed, a second reboot POST, a redeploy before the scheduler serves, a plan that touches an
# address outside the table. So the route is checked in four layers:
#   A. STATIC, on the PARSED YAML (never a grep: a grep passes on a commented-out step): dispatch-only, inputs, pinned actions,
#      inputs only through env:, per-job credential binding, the needs/if graph, the locks, timeouts derived from the script's
#      BUDGET TABLE, no raw Terraform command, the reboot step's env -i allow-list and its single POST.
#   B. THE SCRIPT, statically: one Terraform chokepoint, one POST site, the gate table's three construction sites, the verdict
#      token list equal to the tokens the script can emit.
#   C. BEHAVIOUR against stubs (gh, doppler, terraform, curl, ssh-keygen, the host-state and Better Stack readers, track.sh):
#      the refusal ladder, the two plan gates, value-silent compare, the reboot function, the wait, the redeploy, converge.
#      Every stub terraform prints synthesized key-shaped strings on both streams; no captured stream may contain one.
#   D. MUTATIONS on copies of the script and the workflow (Guard Contract batteries 1, 2 and 4; battery 3 lives in
#      inngest-link-flip-workflow.test.sh): each guard is removed and the scenario that depends on it must turn from "stops"
#      to "proceeds" (a guard no scenario can see is not a guard), plus harness rows (the checker itself fails on bad input).
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): every token-shaped value is built by concatenation below.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/inngest-key-rotate.yml"
BODY="$REPO_ROOT/scripts/inngest-key-rotate.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

TMP="$(mktemp -d "${TMPDIR%/}/inngest-key-rotate-wf.XXXXXX")" || { echo "FAIL SETUP: mktemp"; exit 1; }
assert_fixture_dir "$TMP"
trap 'rm -rf -- "$TMP"' EXIT

python3 -c 'import yaml' 2>/dev/null || { echo "FAIL SETUP: python3 yaml unavailable"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL SETUP: jq unavailable"; exit 1; }
for f in "$WF" "$BODY"; do [[ -f "$f" ]] || { echo "FAIL SETUP: $f missing"; exit 1; }; done

# The SUT is sourced BEFORE the verdict helpers are defined: its functions are all kr_-prefixed, but a sourced file that grew a
# generic `ok`/`bad`/`check` would otherwise silently replace the helper that counts the suite's own verdicts.
# shellcheck source=/dev/null
source "$BODY" || { echo "FAIL SETUP: cannot source $BODY"; exit 1; }

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; return 0; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# expect <description> <condition-value 0|1>: ok when the value is 0 (a shell truth)
expect() { if [[ "$2" == 0 ]]; then ok "$1"; else bad "$1" "${3:-}"; fi; }

# INSTRUMENT SELF-TEST: drive both helpers once and require both counters to move before any row is believed.
_p0=$PASS; _f0=$FAIL
ok "self-test: ok() increments PASS" >/dev/null; bad "self-test: bad() increments FAIL" >/dev/null
if (( PASS == _p0 + 1 && FAIL == _f0 + 1 )); then PASS=$_p0; FAIL=$_f0; else printf 'FAIL INSTRUMENT: ok()/bad() did not move their counters\n' >&2; exit 2; fi

# ---------------------------------------------------------------------------------------------------------------------------
# Synthesized sentinels: shaped like key material, built by concatenation, independent of the script's own patterns.
S_B64="$(printf 'Zq3Xk9Lm2Pw7Rt5Vb8Yn1Hj4Gc6Fd0SaUe_Zq3Xk9Lm2Pw7' | cut -c1-43)"   # 43 chars of base64url
S_HEX="$(printf '9f3a%.0s' {1..16})"                                              # 64 hex
S_SIGN="signkey-prod-${S_HEX}"
OLD_SIGN="signkey-prod-$(printf 'a1%.0s' {1..32})"
OLD_EVENT="$(printf 'c3%.0s' {1..32})"

yq() { python3 - "$WF" "$1" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get("on"))
jobs = d["jobs"]
expr = sys.argv[2]
print(eval(expr))
PY
}
yqf() { python3 - "$1" "$2" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get("on"))
jobs = d["jobs"]
print(eval(sys.argv[2]))
PY
}

BUD="$(env -i PATH="$PATH" bash -c 'source "$1"; echo "$KR_GUARD_S $KR_GUARD_JOB_S $KR_APPLY_STEP_S $KR_APPLY_JOB_S $KR_REBOOT_STEP_S $KR_VERIFY_STEP_S $KR_REBOOT_JOB_S $KR_REDEPLOY_S $KR_REDEPLOY_JOB_S $KR_BOOT_WAIT_S $KR_VERIFY_S $KR_PIPELINE_CEILING_S"' _ "$BODY")"
read -r B_GUARD B_GUARD_JOB B_APPLY_STEP B_APPLY_JOB B_REBOOT_STEP B_VERIFY_STEP B_REBOOT_JOB B_REDEPLOY B_REDEPLOY_JOB B_BOOT_WAIT B_VERIFY B_CEILING <<<"$BUD"
mins() { echo $(( ($1 + 59) / 60 )); }

printf '\n=== A. static: the workflow (parsed YAML) ===\n'
[[ "$(yq 'sorted(k for k in on.keys())')" == "['push', 'workflow_dispatch']" ]] && ok "A1 triggers are exactly workflow_dispatch plus a registration push" || bad "A1 triggers: $(yq 'sorted(on.keys())')"
[[ "$(yq 'on["push"]["paths"]')" == "['.github/workflows/inngest-key-rotate.yml']" && "$(yq 'on["push"]["branches"]')" == "['main']" ]] && ok "A2 the push trigger is main-only and scoped to this file alone (it only registers the workflow)" || bad "A2 push scope"
[[ "$(yq 'all("workflow_dispatch" in str(j.get("if","")) for j in jobs.values())')" == True ]] && ok "A3 every job is gated on github.event_name == workflow_dispatch" || bad "A3 job gate"
[[ "$(yq 'sorted(jobs.keys())')" == "['apply1', 'apply2', 'guard', 'reboot', 'redeploy']" ]] && ok "A4 the jobs are exactly guard, apply1, reboot, apply2, redeploy" || bad "A4 jobs: $(yq 'sorted(jobs.keys())')"
[[ "$(yq 'sorted(on["workflow_dispatch"]["inputs"].keys())')" == "['confirm', 'keys', 'mode', 'quiet_window', 'reason', 'rotated_at']" ]] && ok "A5 the inputs are mode, keys, confirm, reason, rotated_at, quiet_window" || bad "A5 inputs"
[[ "$(yq '[("default" in on["workflow_dispatch"]["inputs"][k], on["workflow_dispatch"]["inputs"][k]["required"]) for k in ("mode","keys")]')" == "[(False, True), (False, True)]" ]] && ok "A6 mode and keys are required with NO default (the owner's go names them)" || bad "A6 mode/keys defaults"
[[ "$(yq 'on["workflow_dispatch"]["inputs"]["mode"]["options"]')" == "['plan', 'rotate', 'converge']" && "$(yq 'on["workflow_dispatch"]["inputs"]["keys"]["options"]')" == "['signing', 'event', 'both']" ]] && ok "A7 mode is {plan, rotate, converge} (plan first) and keys is {signing, event, both}" || bad "A7 options"
[[ "$(yq 'on["workflow_dispatch"]["inputs"]["quiet_window"]["type"] + str(on["workflow_dispatch"]["inputs"]["quiet_window"]["default"])')" == "booleanFalse" ]] && ok "A8 quiet_window is a boolean that defaults to false" || bad "A8 quiet_window"
[[ "$(yq 'd["run-name"]')" == 'inngest-key-rotate ${{ inputs.mode }} ${{ inputs.keys }}' ]] && ok "A9 run-name carries the mode and keys (the link-flip guard and converge derive from it)" || bad "A9 run-name: $(yq 'd["run-name"]')"
[[ "$(yq 'd["concurrency"]["group"] + "|" + str(d["concurrency"]["cancel-in-progress"])')" == "inngest-key-rotate|False" ]] && ok "A10 workflow-level group inngest-key-rotate, never cancel-in-progress" || bad "A10 concurrency"
[[ "$(yq 'str(jobs["apply1"]["concurrency"]["group"]) + "|" + str(jobs["apply2"]["concurrency"]["group"]) + "|" + str(jobs["reboot"]["concurrency"]["group"])')" == "terraform-apply-web-platform-host|terraform-apply-web-platform-host|deploy-inngest-restart" ]] && ok "A11 the Terraform jobs hold terraform-apply-web-platform-host and the reboot job holds the shared deploy-inngest-restart mutex" || bad "A11 job groups"
[[ "$(yq 'all(j.get("concurrency", {}).get("cancel-in-progress") in (None, False) for j in jobs.values())')" == True ]] && ok "A12 no job group cancels in progress" || bad "A12 job cancel-in-progress"
[[ "$(yq 'd["permissions"]')" == "{'contents': 'read'}" ]] && ok "A13 workflow permissions are contents:read; each job widens only what it needs" || bad "A13 permissions"
[[ "$(yq '[jobs[j]["permissions"].get("issues") for j in ("guard","apply1","reboot","apply2","redeploy")]')" == "['read', 'write', 'write', 'write', 'write']" ]] && ok "A14 only the write jobs hold issues:write (the guard only reads)" || bad "A14 issues scope"
[[ "$(yq 'all(len(s["uses"].split("@")[1].split(" ")[0]) == 40 for j in jobs.values() for s in j["steps"] if "uses" in s and not s["uses"].startswith("./"))')" == True ]] && ok "A15 every remote action is pinned to a 40-hex SHA" || bad "A15 unpinned action"
[[ "$(yq 'sorted(set(s["uses"].split("@")[0] for j in jobs.values() for s in j["steps"] if "uses" in s))')" == "['./.github/actions/infra-credentials', 'DopplerHQ/cli-action', 'actions/checkout', 'hashicorp/setup-terraform']" ]] && ok "A16 the action set is checkout, setup-terraform, the pinned Doppler CLI action and the credential loader" || bad "A16 action set: $(yq 'sorted(set(s["uses"].split("@")[0] for j in jobs.values() for s in j["steps"] if "uses" in s))')"
[[ "$(yq 'any("${{ inputs" in s.get("run","") or "${{ secrets" in s.get("run","") or "${{ needs" in s.get("run","") or "${{ github" in s.get("run","") or "${{ steps" in s.get("run","") for j in jobs.values() for s in j["steps"])')" == False ]] && ok "A17 no expression is interpolated into a run: body (inputs, secrets and outputs all arrive through env:)" || bad "A17 expression in run:"
[[ "$(yq 'any("${{" in str(j.get("if","")) and "inputs." in str(j.get("if","")) for j in jobs.values())')" == False ]] && ok "A18 no job condition reads a dispatch input (conditions read the guard's validated outputs)" || bad "A18 input in if:"
[[ "$(yq '[s.get("run","").strip() for s in jobs["guard"]["steps"] if s.get("id") == "guard"]')" == "['bash scripts/inngest-key-rotate.sh guard']" ]] && ok "A19 the guard step is exactly: bash scripts/inngest-key-rotate.sh guard" || bad "A19 guard run"
[[ "$(yq '[s["run"].strip() for s in jobs["apply1"]["steps"] if "run" in s]')" == "['bash scripts/inngest-key-rotate.sh apply1']" && "$(yq '[s["run"].strip() for s in jobs["apply2"]["steps"] if "run" in s]')" == "['bash scripts/inngest-key-rotate.sh apply2']" && "$(yq '[s["run"].strip() for s in jobs["redeploy"]["steps"] if "run" in s]')" == "['bash scripts/inngest-key-rotate.sh redeploy']" ]] && ok "A20 apply1, apply2 and redeploy each run exactly one script subcommand and nothing else" || bad "A20 run bodies"
check "A21 no terraform, doppler, curl or gh command in the workflow text (the script is the only caller)" bash -c "! grep -Eq '(^|[^-a-zA-Z_/])(terraform|doppler|curl|gh) ' < <(grep -v '^ *#' '$WF' | grep -v 'description:')"
check "A22 nothing is uploaded (no upload-artifact or cache step: a public repo's artifacts are readable by any account)" bash -c "! grep -Eq 'upload-artifact|actions/cache|step-summary-upload' '$WF'"
check "A23 the workflow never names the standalone restart workflow or the restart verb (that lever cannot reach 10.0.1.40)" bash -c "! grep -Eiq 'restart-inngest-server|restart inngest' '$WF' '$BODY'"
check "A24 no test seam (KR_*) is set anywhere in the workflow" bash -c "! grep -Eq 'KR_(SLEEP|NOW|HZ_BASE|TRACK|HOST_STATE|BS_QUERY|INFRA_DIR)' '$WF'"
[[ "$(yq '[jobs[j].get("environment") for j in ("guard","apply1","reboot","apply2","redeploy")]')" == "[None, 'infra-privileged', 'infra-privileged', 'infra-privileged', None]" ]] && ok "A25 apply1, reboot and apply2 run in the Tier-B environment infra-privileged; the guard and the redeploy hold no Tier-B credential" || bad "A25 environments"
[[ "$(yq '[sum(1 for s in jobs[j]["steps"] if s.get("uses","").startswith("./.github/actions/infra-credentials")) for j in ("guard","apply1","reboot","apply2","redeploy")]')" == "[0, 1, 1, 1, 0]" ]] && ok "A26 the credential loader runs in exactly the three Tier-B jobs (each declares the Tier-B environment, census G1j)" || bad "A26 loader"
SECRETS_OF() { yq "sorted(set(__import__('re').findall(r'secrets\\.([A-Z0-9_]+)', __import__('json').dumps(jobs['$1']))))"; }
[[ "$(SECRETS_OF guard)" == "['BETTERSTACK_QUERY_HOST', 'BETTERSTACK_QUERY_PASSWORD', 'BETTERSTACK_QUERY_USERNAME', 'DOPPLER_TOKEN']" ]] && ok "A27 guard credentials: the Tier-A Doppler token and the Better Stack read pair only (the Hetzner token it uses is READ-ONLY, fetched by the script)" || bad "A27 guard secrets: $(SECRETS_OF guard)"
[[ "$(SECRETS_OF apply1)" == "['DOPPLER_TOKEN', 'DOPPLER_TOKEN_INFRA_PRIVILEGED']" && "$(SECRETS_OF apply2)" == "['DOPPLER_TOKEN', 'DOPPLER_TOKEN_INFRA_PRIVILEGED']" ]] && ok "A28 apply1 and apply2 hold the Tier-B loader token and the Tier-A Doppler token only (no webhook or Better Stack credential)" || bad "A28 apply secrets"
[[ "$(SECRETS_OF reboot)" == "['BETTERSTACK_QUERY_HOST', 'BETTERSTACK_QUERY_PASSWORD', 'BETTERSTACK_QUERY_USERNAME', 'DOPPLER_TOKEN', 'DOPPLER_TOKEN_INFRA_PRIVILEGED']" ]] && ok "A29 reboot holds the loader tokens and the Better Stack pair (the write token arrives only through the loader's HCLOUD_TOKEN)" || bad "A29 reboot secrets: $(SECRETS_OF reboot)"
[[ "$(SECRETS_OF redeploy)" == "['CF_ACCESS_CLIENT_ID', 'CF_ACCESS_CLIENT_SECRET', 'WEBHOOK_DEPLOY_SECRET']" ]] && ok "A30 redeploy holds the deploy webhook trio only" || bad "A30 redeploy secrets: $(SECRETS_OF redeploy)"
[[ "$(yq 'jobs["redeploy"]["env"]["WEB_HOST_PRIVATE_IPS"]')" == "10.0.1.10,10.0.1.11" ]] && ok "A31 the redeploy pins the fan-out roster literal WEB_HOST_PRIVATE_IPS (web-hosts-fanout-parity.test.sh compares it with var.web_hosts)" || bad "A31 roster"

# The needs/if graph (Guard 4). graph_ok <workflow-file>: prints a space-separated list of violated properties (empty = clean).
graph_violations() {
  python3 - "$1" <<'PY'
import sys, yaml, re
d = yaml.safe_load(open(sys.argv[1]))
jobs = d["jobs"]
def needs(j):
    n = jobs[j].get("needs", [])
    return [n] if isinstance(n, str) else list(n)
def closure(j, seen=None):
    seen = seen or set()
    for x in needs(j):
        if x not in seen:
            seen.add(x); closure(x, seen)
    return seen
bad = []
for j in ("apply1", "reboot", "apply2", "redeploy"):
    if "guard" not in closure(j): bad.append(j + ":no-guard-transitively")
    if "guard" not in needs(j): bad.append(j + ":guard-not-a-direct-need")
    c = str(jobs[j].get("if", ""))
    if "needs.guard.outputs.go == 'true'" not in c: bad.append(j + ":if-not-on-go")
    if "needs.guard.result == 'success'" not in c: bad.append(j + ":if-not-on-guard-success")
    if "github.event_name == 'workflow_dispatch'" not in c: bad.append(j + ":if-not-dispatch")
if "apply1" not in closure("reboot"): bad.append("reboot:before-apply1")
if "reboot" not in closure("apply2"): bad.append("apply2:before-reboot")
if "apply2" not in closure("redeploy") or "reboot" not in closure("redeploy"): bad.append("redeploy:before-apply2")
if "needs.reboot.result == 'success'" not in str(jobs["apply2"].get("if", "")): bad.append("apply2:if-not-on-reboot-success")
if "needs.apply2.result == 'success'" not in str(jobs["redeploy"].get("if", "")): bad.append("redeploy:if-not-on-apply2-success")
if "needs.reboot.result == 'success'" not in str(jobs["redeploy"].get("if", "")): bad.append("redeploy:if-not-on-reboot-success")
if "needs.apply1.result == 'success' || needs.apply1.result == 'skipped'" not in str(jobs["reboot"].get("if", "")): bad.append("reboot:if-not-on-apply1-result")
print(" ".join(bad))
PY
}
[[ -z "$(graph_violations "$WF")" ]] && ok "A32 every write job needs the guard transitively and is conditioned on its go output; reboot needs apply1, apply2 needs reboot, redeploy needs apply2 and reboot" || bad "A32 graph" "$(graph_violations "$WF")"

# Timeouts derive from the script's BUDGET TABLE (rounded up to minutes).
[[ "$(yq 'jobs["guard"]["timeout-minutes"]')" == "$(mins "$B_GUARD_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["guard"]["steps"] if s.get("id") == "guard")')" == "$(mins "$B_GUARD")" ]] && ok "A33 guard: job $(mins "$B_GUARD_JOB") min and step $(mins "$B_GUARD") min equal the budget table (KR_GUARD_JOB_S, KR_GUARD_S)" || bad "A33 guard timeouts"
[[ "$(yq 'jobs["apply1"]["timeout-minutes"]')" == "$(mins "$B_APPLY_JOB")" && "$(yq 'jobs["apply2"]["timeout-minutes"]')" == "$(mins "$B_APPLY_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["apply1"]["steps"] if "run" in s)')" == "$(mins "$B_APPLY_STEP")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["apply2"]["steps"] if "run" in s)')" == "$(mins "$B_APPLY_STEP")" ]] && ok "A34 apply1/apply2: job $(mins "$B_APPLY_JOB") min and step $(mins "$B_APPLY_STEP") min equal KR_APPLY_JOB_S / KR_APPLY_STEP_S" || bad "A34 apply timeouts"
[[ "$(yq 'jobs["reboot"]["timeout-minutes"]')" == "$(mins "$B_REBOOT_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["reboot"]["steps"] if s.get("id") == "post")')" == "$(mins "$B_REBOOT_STEP")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')" == "$(mins "$B_VERIFY_STEP")" ]] && ok "A35 reboot: job $(mins "$B_REBOOT_JOB") min, POST step $(mins "$B_REBOOT_STEP") min, verify step $(mins "$B_VERIFY_STEP") min equal the budget table" || bad "A35 reboot timeouts"
[[ "$(yq 'jobs["redeploy"]["timeout-minutes"]')" == "$(mins "$B_REDEPLOY_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["redeploy"]["steps"] if "run" in s)')" -ge "$(mins "$B_REDEPLOY")" && "$B_REDEPLOY" == "$B_CEILING" && "$B_CEILING" == 4800 ]] && ok "A36 redeploy: the budget equals the pipeline's 4800 s ceiling (ci-deploy-wrapper.sh) and the job ceiling is derived from it" || bad "A36 redeploy timeouts"
check "A37 the pipeline ceiling the budget quotes is the wrapper's real kill time" grep -Eq 'timeout --signal=TERM --kill-after=[0-9]+s 4800s ' "$REPO_ROOT/apps/web-platform/infra/ci-deploy-wrapper.sh"
[[ "$B_BOOT_WAIT" == 600 && "$B_VERIFY" == 900 && "$B_BOOT_WAIT" -lt "$B_VERIFY" ]] && ok "A38 the new-boot wait is 10 minutes and sits inside the 15-minute verify window" || bad "A38 wait budget $B_BOOT_WAIT/$B_VERIFY"
[[ "$(yq 'all(isinstance(s.get("timeout-minutes"), int) for j in jobs.values() for s in j["steps"] if "run" in s or s.get("uses","").startswith("./"))')" == True ]] && ok "A39 every run and loader step carries its own timeout-minutes" || bad "A39 step timeout"

# The reboot job: env -i allow-list on every step after the loader; the write token in the POST step only; ONE POST.
RB_POST_RUN="$(yq 'next(s["run"] for s in jobs["reboot"]["steps"] if s.get("id") == "post")')"
RB_VERIFY_RUN="$(yq 'next(s["run"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')"
[[ "$RB_POST_RUN" == *"exec env -i "* && "$RB_VERIFY_RUN" == *"exec env -i "* ]] && ok "A40 both reboot-job run steps start with exec env -i (the loader's other Tier-B values never reach a child)" || bad "A40 env -i"
[[ "$RB_POST_RUN" == *'HCLOUD_TOKEN="$HCLOUD_TOKEN"'* && "$RB_VERIFY_RUN" != *HCLOUD_TOKEN* && "$RB_POST_RUN" != *BETTERSTACK* ]] && ok "A41 the Hetzner write token is in the POST step's allow-list only; the verify step has none and the POST step has no Better Stack pair" || bad "A41 token binding"
[[ "$RB_POST_RUN" != *DOPPLER_TOKEN* && "$RB_VERIFY_RUN" != *DOPPLER_TOKEN* && "$RB_POST_RUN" != *AWS_* && "$RB_VERIFY_RUN" != *AWS_* ]] && ok "A42 neither reboot step allow-lists a Doppler token or the Terraform backend pair" || bad "A42 allow-list"
[[ "$(yq 'sum(1 for s in jobs["reboot"]["steps"] if "run" in s and "reboot" in s["run"].split("inngest-key-rotate.sh")[-1])')" == 1 ]] && ok "A43 exactly one reboot-job step invokes the POST subcommand" || bad "A43 post step count"
[[ "$(yq 'jobs["reboot"]["steps"][-1].get("id")')" == "verify" && "$(yq 'next(s.get("if") for s in jobs["reboot"]["steps"] if s.get("id") == "post")')" == "\${{ needs.guard.outputs.reboot_post == 'true' }}" ]] && ok "A44 the POST step runs only when the guard decided a POST is needed; the verify step always follows it" || bad "A44 post/verify order"
[[ "$(yq 'next(s["env"]["EFF_POST_EPOCH"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')" == '${{ steps.post.outputs.post_epoch }}' ]] && ok "A45 the verify step reads the POST time from the POST step's output" || bad "A45 post epoch"

printf '\n=== B. static: the script ===\n'
check "B1 the script parses clean (bash -n)" bash -n "$BODY"
if command -v shellcheck >/dev/null 2>&1; then check "B2 shellcheck is clean" shellcheck "$BODY"; else ok "B2 shellcheck not installed; skipped"; fi
check "B3 no eval, no -k/--insecure, no credential in an argument list" bash -c "! grep -Eq '\\beval\\b|--insecure| -k |-H .?(Authorization|X-Signature)' < <(grep -v '^ *#' '$BODY')"
check "B4 the script refuses to run under xtrace (Rule E: it handles live credentials)" grep -q 'refusing to run under xtrace' "$BODY"
# Guard 2: the Terraform chokepoint. Strip comments and the kr_tf body, then no `terraform` word may start a command.
code_only() { grep -v '^ *#' "$1" | sed -E 's/#[^"'"'"']*$//'; }
TF_CALLS="$(code_only "$BODY" | grep -Eo '(^|[^_a-zA-Z-])terraform[[:space:]]+[a-z"$]' | wc -l | tr -d ' ')"
[[ "$TF_CALLS" == 1 ]] && ok "B5 exactly one place in the script runs terraform (the kr_tf wrapper: 'terraform \"\$@\"')" || bad "B5 terraform call sites: $TF_CALLS"
check "B6 no bare terraform plan|apply|show|state|output|refresh|destroy|import anywhere in the script" bash -c "! grep -Eq '(^|[^_a-zA-Z-])terraform[[:space:]]+(plan|apply|show|state|output|refresh|destroy|import|console)' < <(grep -v '^ *#' '$BODY')"
check "B7 kr_tf sends BOTH streams to files and unsets TF_LOG, TF_LOG_PATH, TF_LOG_CORE and TF_LOG_PROVIDER" bash -c "grep -A8 '^kr_tf()' '$BODY' | grep -q 'env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER' && grep -A8 '^kr_tf()' '$BODY' | grep -q '> \"\$KR_TMP/tf-\${name}.out\" 2> \"\$KR_TMP/tf-\${name}.err\"'"
check "B8 kr_tf runs doppler run --preserve-env (the loader's Tier-B values win) with --name-transformer tf-var" bash -c "grep -A10 '^kr_tf()' '$BODY' | grep -q 'doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var'"
check "B9 no Terraform stream is ever printed: no cat/head/tail/tee/echo of a tf-*.out or tf-*.err file" bash -c "! grep -Eq '(cat|head|tail|tee|printf|echo|sed|grep|less|more)[^|;]*tf-[a-z0-9\${}_-]*\\.(out|err)' < <(grep -v '^ *#' '$BODY' | grep -v 'kr_tf()' | grep -v 'show-' )"
check "B10 the plan JSON is read only by jq (kr_gate) and never by a shell redirect into the log" bash -c "grep -c 'tf-show-' '$BODY' | grep -qx '[1-9]'"
SECRET_READS="$(grep -v '^ *#' "$BODY" | grep -E 'doppler secrets (get|download)' | grep -Ev 'INNGEST_LINK_TLS|HCLOUD_TOKEN_READONLY|sha256sum' || true)"
[[ -z "$SECRET_READS" ]] && ok "B11 every doppler secrets get is the link flag, the read-only Hetzner token, or a read piped into sha256sum (no key value is ever captured)" || bad "B11 unexpected secret read" "$SECRET_READS"
check "B12 the only -X POST in the script is inside kr_hz's single caller kr_reboot_post" bash -c "[ \"\$(grep -v '^ *#' '$BODY' | grep -c 'kr_hz POST')\" = 1 ] && grep -A8 '^kr_reboot_post()' '$BODY' | grep -q 'kr_hz POST'"
check "B13 the reboot POST latch is set before the request" bash -c "grep -A8 '^kr_reboot_post()' '$BODY' | grep -n 'KR_POSTED=1' | head -1 | grep -q . && awk '/^kr_reboot_post\\(\\)/{f=1} f&&/KR_POSTED=1/{a=NR} f&&/kr_hz POST/{b=NR} END{exit !(a<b)}' '$BODY'"
check "B14 no hard reset: no reset/poweroff/poweron/power_off action path is requested" bash -c "! grep -Eiq 'actions/(reset|poweroff|poweron|power_off|rebuild|shutdown)' < <(grep -v '^ *#' '$BODY')"
check "B15 every Hetzner request goes through bearer-curl.sh (bc_curl); no curl command with a token argument" bash -c "grep -q 'bc_curl inngest-key-rotate' '$BODY' && [ \"\$(grep -v '^ *#' '$BODY' | grep -c ' curl ')\" = 0 ]"
# The gate table's three construction sites.
[[ "$(code_only "$BODY" | grep -c -- "-target=")" == 1 && "$(code_only "$BODY" | grep -c -- "-replace=")" == 1 ]] && ok "B16 the -target and -replace flags are each built in exactly one place (from the gate table)" || bad "B16 flag construction sites"
check "B17 no resource address literal outside the gate table (random_id., doppler_secret., hcloud_ appear only in table rows)" bash -c "! grep -v '^ *#' '$BODY' | grep -v \"^  'A|\\|^  'B|\" | grep -Eq '(random_id|doppler_secret|hcloud_[a-z]+|terraform_data|tls_[a-z]+)\\.[a-z_]+'"
GATE_ROWS="$(env -i PATH="$PATH" bash -c 'source "$1"; printf "%s\n" "${KR_GATE_TABLE[@]}"' _ "$BODY")"
[[ "$(wc -l <<<"$GATE_ROWS" | tr -d ' ')" == 6 && "$(grep -c '^A|' <<<"$GATE_ROWS")" == 4 && "$(grep -c '^B|' <<<"$GATE_ROWS")" == 2 ]] && ok "B18 the gate table has 4 phase-A rows and 2 phase-B rows" || bad "B18 table"
[[ "$(grep '^A|' <<<"$GATE_ROWS" | cut -d'|' -f3,5 | sort | tr '\n' ' ')" == "doppler_secret.inngest_event_key_dedicated|update doppler_secret.inngest_signing_key_dedicated|update random_id.inngest_event_key_dedicated|delete,create random_id.inngest_signing_key_dedicated|delete,create " ]] && ok "B19 Gate A: the dedicated random_ids [delete,create] and the dedicated secrets [update]" || bad "B19 gate A rows"
[[ "$(grep '^B|' <<<"$GATE_ROWS" | cut -d'|' -f3,5 | sort | tr '\n' ' ')" == "doppler_secret.inngest_event_key_prd|delete,create doppler_secret.inngest_signing_key_prd|delete,create " ]] && ok "B20 Gate B: only the app (prd) secrets [delete,create]; the dedicated addresses are not in the table so they must be no-ops" || bad "B20 gate B rows"
# The token list.
TOKENS_PRINTED="$(env -i PATH="$PATH" bash "$BODY" --print-contract | tail -n +2 | sort | tr '\n' ' ')"
TOKENS_USED="$(grep -v '^ *#' "$BODY" | grep -Eo '(kr_refuse|kr_ok|kr_post_write_failure|KR_CHECK_TOKEN=|kr_ok "\$\{mode\}_ok"|kr_ok) +"?[a-z_0-9]+' | awk '{print $NF}' | tr -d '"' | grep -E '^[a-z][a-z0-9]*(_[a-z0-9]+)+$' | sort -u | tr '\n' ' ')"
TOKENS_USED="$TOKENS_USED$(grep -v '^ *#' "$BODY" | grep -Eo 'KR_CHECK_TOKEN=[a-z_0-9]+' | cut -d= -f2 | sort -u | tr '\n' ' ')"
USED_SORTED="$(tr ' ' '\n' <<<"$TOKENS_USED" | grep . | sort -u | tr '\n' ' ')"
MISSING_FROM_LIST="$(comm -13 <(tr ' ' '\n' <<<"$TOKENS_PRINTED" | grep . | sort -u) <(tr ' ' '\n' <<<"$USED_SORTED" | grep . | sort -u) | grep -vx 'rotate_ok\|converge_ok' | tr '\n' ' ')"
[[ -z "$MISSING_FROM_LIST" ]] && ok "B21 every verdict token the script emits is in the printed contract list" || bad "B21 tokens emitted but not listed: $MISSING_FROM_LIST"
UNUSED_IN_LIST="$(comm -23 <(tr ' ' '\n' <<<"$TOKENS_PRINTED" | grep . | sort -u) <(tr ' ' '\n' <<<"$USED_SORTED" | grep . | sort -u) | grep -vx 'rotate_ok\|converge_ok\|guard_ok\|plan_ok' | tr '\n' ' ')"
[[ -z "$UNUSED_IN_LIST" ]] && ok "B22 every listed token has an emitting site (no dead vocabulary)" || bad "B22 listed but never emitted: $UNUSED_IN_LIST"
[[ -z "$(tr ' ' '\n' <<<"$TOKENS_PRINTED" | grep . | sort | uniq -d)" ]] && ok "B23 the token list has no duplicates" || bad "B23 duplicate tokens"

printf '\n=== C0. --print-contract: offline, no credentials, fast ===\n'
T0=$SECONDS
PC_OUT="$(env -i PATH=/usr/bin:/bin bash "$BODY" --print-contract 2>&1)"; PC_RC=$?
PC_T=$((SECONDS - T0))
[[ "$PC_RC" == 0 && "$(head -1 <<<"$PC_OUT")" == "inngest-key-rotate verdict-tokens" ]] && ok "C0.1 --print-contract prints the 'inngest-key-rotate verdict-tokens' header and exits 0 with an empty environment" || bad "C0.1 rc=$PC_RC head='$(head -1 <<<"$PC_OUT")'"
[[ "$PC_T" -lt 15 ]] && ok "C0.2 --print-contract returns in ${PC_T}s (preflight Check 10 allows 15 s)" || bad "C0.2 slow: ${PC_T}s"
[[ "$(tail -n +2 <<<"$PC_OUT" | grep -c .)" -ge 30 && "$(tail -n +2 <<<"$PC_OUT" | grep -Evc '^[a-z][a-z0-9]*(_[a-z0-9]+)+$')" == 0 ]] && ok "C0.3 the list is one token per line, each snake_case" || bad "C0.3 list shape"
for t in plan_ok plan_gate_refused host_silent host_not_serving rerun_refused link_flag_pending soak_open reboot_refused_second_post converge_source_missing; do
  grep -qx "$t" <<<"$PC_OUT" || bad "C0.4 token $t missing from the contract"
done
ok "C0.4 the contract names the verdicts the plan promises (plan_ok, plan_gate_refused, host_silent, host_not_serving, rerun_refused, link_flag_pending, soak_open, ...)"

printf '\n=== C. behaviour against stubs: fixtures ===\n'
NOW0=1900000000
TODAY="$(date -u +%F)"
WRITE_TOK="hcwr$(printf 'w%.0s' {1..28})"
RO_TOK="hcro$(printf 'r%.0s' {1..28})"

make_stubs() { # dir: a hermetic fake world (PATH shims + a state directory the shims read)
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/bin" "$d/state" "$d/infra" "$d/rt"
  printf '%s\n' "$NOW0" > "$d/state/now"
  printf 'INNGEST_LINK_TLS\nOTHER\n' > "$d/state/names"
  printf '1' > "$d/state/link"
  printf '%s' "$RO_TOK" > "$d/state/hz_ro"
  printf '%s' '{"servers":[{"id":4242,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$d/state/servers.json"
  printf '%s' '{"actions":[]}' > "$d/state/actions.json"
  printf '%s' '{"state":"CLOSED","stateReason":"COMPLETED"}' > "$d/state/soak.json"
  printf '%s' "$OLD_SIGN" > "$d/state/copy_host_signing"; printf '%s' "$OLD_SIGN" > "$d/state/copy_app_signing"
  printf '%s' "$OLD_EVENT" > "$d/state/copy_host_event"; printf '%s' "$OLD_EVENT" > "$d/state/copy_app_event"
  printf '%s\n%s\n%s\n' "$S_B64" "$S_HEX" "$S_SIGN" > "$d/state/sent"
  hs_set_in "$d" 1 0 abcd1234 yes $((NOW0 - 60))
  bs_set_in "$d" 1 "$(bs_row $((NOW0 - 120)) abcd1234 1)"
  cat > "$d/bin/adv" <<'SH'
#!/usr/bin/env bash
s="$(cat "$STUB/state/now")"; echo $((s + ${1:-5})) > "$STUB/state/now"
SH
  cat > "$d/bin/doppler" <<'SH'
#!/usr/bin/env bash
echo "doppler $*" >> "$STUB/doppler.log"
if [[ "$1" == run ]]; then
  shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift
  exec "$@"
fi
proj=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[$i]}" == -p ]] && proj="${args[$((i + 1))]}"; done
if [[ "$2" == --only-names ]]; then
  [[ -f "$STUB/state/names_rc" ]] && exit "$(cat "$STUB/state/names_rc")"
  cat "$STUB/state/names"; exit 0
fi
if [[ "$1 $2" == "secrets get" ]]; then
  case "$3" in
    INNGEST_LINK_TLS) [[ -f "$STUB/state/link" ]] && { cat "$STUB/state/link"; exit 0; }; exit 1 ;;
    HCLOUD_TOKEN_READONLY) [[ -f "$STUB/state/hz_ro" ]] && { cat "$STUB/state/hz_ro"; exit 0; }; exit 1 ;;
    INNGEST_SIGNING_KEY|INNGEST_EVENT_KEY)
      k=signing; [[ "$3" == INNGEST_EVENT_KEY ]] && k=event
      w=app; [[ "$proj" == soleur-inngest ]] && w=host
      [[ -f "$STUB/state/copy_${w}_${k}" && ! -f "$STUB/state/copy_unreadable" ]] && { cat "$STUB/state/copy_${w}_${k}"; exit 0; }; exit 1 ;;
  esac
fi
exit 1
SH
  cat > "$d/bin/terraform" <<'SH'
#!/usr/bin/env bash
echo "terraform $1 TFLOG=${TF_LOG:-unset} TFLOGPATH=${TF_LOG_PATH:-unset}" >> "$STUB/tf.log"
{ read -r B64; read -r HEX; read -r SIGN; } < "$STUB/state/sent"
sentinels() {
  printf 'random_id.x: Creation complete after 0s [id=%s]\n  hex = "%s"\n  value = "%s"\n' "$B64" "$HEX" "$SIGN"
  printf 'Error: refresh [id=%s] hex=%s %s\n' "$B64" "$HEX" "$SIGN" >&2
}
[[ -n "${TF_LOG_PATH:-}" ]] && printf 'TRACE [id=%s]\n' "$B64" > "$TF_LOG_PATH"
[[ -n "${TF_LOG:-}" ]] && printf 'TRACE value=%s\n' "$SIGN" >&2
sub="$1"; shift
rcf() { [[ -f "$STUB/state/$1" ]] && cat "$STUB/state/$1" || echo 0; }
case "$sub" in
  init) sentinels; exit "$(rcf init_rc)" ;;
  plan)
    out=""; : > "$STUB/last_def"
    for a in "$@"; do
      case "$a" in
        -out=*) out="${a#-out=}" ;;
        -target=*) echo "T ${a#-target=}" >> "$STUB/last_def" ;;
        -replace=*) echo "R ${a#-replace=}" >> "$STUB/last_def" ;;
      esac
    done
    cp "$STUB/last_def" "$out"
    echo "plan $(tr '\n' ' ' < "$out")" >> "$STUB/tf.log"
    sentinels; exit "$(rcf plan_rc)" ;;
  show)
    def="${@: -1}"
    phase=a; grep -q '_prd$' "$def" && phase=b
    if [[ -f "$STUB/state/plan_override_$phase" ]]; then cat "$STUB/state/plan_override_$phase"; echo "[id=$B64]" >&2; exit 0; fi
    entries=("$(jq -cn '{address:"doppler_project.inngest",mode:"managed",type:"doppler_project",name:"inngest",change:{actions:["no-op"]}}')")
    while read -r kind addr; do
      [[ -n "$addr" ]] || continue
      if [[ "$kind" == T ]] && grep -q "^R $addr\$" "$def"; then continue; fi
      if [[ "$kind" == R ]]; then acts='["delete","create"]'
      else case "$addr" in doppler_secret.*_dedicated|hcloud_*|terraform_data.*|tls_*) acts='["update"]' ;; *) acts='["no-op"]' ;; esac; fi
      entries+=("$(jq -cn --arg a "$addr" --argjson acts "$acts" --arg id "$B64" --arg hex "$HEX" \
        '{address:$a,mode:"managed",type:($a|split(".")[0]),name:($a|split(".")[1]),change:{actions:$acts,before:{id:$id,hex:$hex},after:{id:$id,hex:$hex}}}')")
    done < <(sort -u "$def")
    extra='[]'; [[ -f "$STUB/state/plan_extra_$phase" ]] && extra="$(cat "$STUB/state/plan_extra_$phase")"
    printf '%s\n' "${entries[@]}" | jq -cs --argjson extra "$extra" '{format_version:"1.2",resource_changes:(. + $extra)}'
    [[ -f "$STUB/state/plan_empty_$phase" ]] && echo '{"format_version":"1.2","resource_changes":[]}' > /dev/null
    echo "refresh [id=$B64]" >&2
    exit "$(rcf show_rc)" ;;
  apply)
    def="${@: -1}"
    n=$(( $(cat "$STUB/state/applyn" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/state/applyn"
    phase=a; grep -q '_prd$' "$def" && phase=b
    echo "apply $phase" >> "$STUB/tf.log"
    sentinels
    if [[ ! -f "$STUB/state/apply_noeffect" ]]; then
      newv="$(printf 'e%.0s' {1..63})$(printf '%x' "$n")"
      if [[ "$phase" == a ]]; then
        grep -q '^R random_id.inngest_signing_key_dedicated$' "$def" && printf 'signkey-prod-%s' "$newv" > "$STUB/state/copy_host_signing"
        grep -q '^R random_id.inngest_event_key_dedicated$' "$def" && printf '%s' "$newv" > "$STUB/state/copy_host_event"
      else
        grep -q '^R doppler_secret.inngest_signing_key_prd$' "$def" && cp "$STUB/state/copy_host_signing" "$STUB/state/copy_app_signing"
        grep -q '^R doppler_secret.inngest_event_key_prd$' "$def" && cp "$STUB/state/copy_host_event" "$STUB/state/copy_app_event"
      fi
    fi
    exit "$(rcf apply_rc)" ;;
  *) exit 64 ;;
esac
SH
  cat > "$d/bin/ssh-keygen" <<'SH'
#!/usr/bin/env bash
f=""; while [[ $# -gt 0 ]]; do [[ "$1" == -f ]] && f="$2"; shift; done
: > "$f"; : > "$f.pub"
SH
  cat > "$d/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; method=GET; wfmt=""; url=""; cfg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;; -X) method="$2"; shift ;; -w) wfmt="$2"; shift ;;
    --config) cfg="$(cat)"; shift ;; --noproxy|--connect-timeout|--max-time) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
tok=none; [[ "$cfg" == *Bearer* ]] && tok=other
[[ "$cfg" == *hcwr* ]] && tok=write; [[ "$cfg" == *hcro* ]] && tok=ro
path="${url#https://hz.invalid}"
echo "$method $path token=$tok" >> "$STUB/curl.log"
[[ "$method" == POST ]] && echo "POST $path token=$tok" >> "$STUB/post.log"
code=404; body='{}'
case "$method $path" in
  "GET /v1/servers?name=soleur-inngest") code="$(cat "$STUB/state/servers_code" 2>/dev/null || echo 200)"; body="$(cat "$STUB/state/servers.json")" ;;
  "GET /v1/servers/4242/actions?"*) code="$(cat "$STUB/state/actions_code" 2>/dev/null || echo 200)"; body="$(cat "$STUB/state/actions.json")" ;;
  "GET /v1/servers/4242/actions/777") code=200; body="{\"action\":{\"id\":777,\"status\":\"$(cat "$STUB/state/action_status" 2>/dev/null || echo success)\"}}" ;;
  "POST /v1/servers/4242/actions/reboot") code="$(cat "$STUB/state/post_code" 2>/dev/null || echo 201)"; body='{"action":{"id":777,"status":"running","command":"reboot_server"}}' ;;
esac
[[ -n "$out" ]] && printf '%s' "$body" > "$out"
[[ "$wfmt" == *http_code* ]] && printf '%s' "$code"
exit 0
SH
  cat > "$d/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB/gh.log"
case "$1 $2" in
  "issue view") [[ -f "$STUB/state/soak_rc" ]] && exit "$(cat "$STUB/state/soak_rc")"; cat "$STUB/state/soak.json" ;;
  "issue list") cat "$STUB/state/issues.json" 2>/dev/null || echo '[]' ;;
  "issue create") t=""; while [[ $# -gt 0 ]]; do [[ "$1" == --title ]] && t="$2"; shift; done; echo "$t" >> "$STUB/issues_created.log"; echo "https://github.example/acme/repo/issues/1" ;;
  "run list")
    [[ -f "$STUB/state/runlist_rc" ]] && exit "$(cat "$STUB/state/runlist_rc")"
    case "$*" in
      *displayTitle*) cat "$STUB/state/krruns.json" 2>/dev/null || echo '[]' ;;
      *) wf=""; st=""; prev=""; for a in "$@"; do [[ "$prev" == --workflow ]] && wf="$a"; [[ "$prev" == --status ]] && st="$a"; prev="$a"; done
         cat "$STUB/state/inflight_${wf}_${st}.json" 2>/dev/null || echo '[]' ;;
    esac ;;
  "run view") cat "$STUB/state/jobs_$3.json" 2>/dev/null || exit 1 ;;
esac
exit 0
SH
  cat > "$d/bin/track.sh" <<'SH'
#!/usr/bin/env bash
echo "track WEB_HOST_PRIVATE_IPS=${WEB_HOST_PRIVATE_IPS:-} REDEPLOY_TIMEOUT_S=${REDEPLOY_TIMEOUT_S:-}" >> "$STUB/track.log"
echo "dispatch-web-redeploy: stub verdict"
exit "$(cat "$STUB/state/track_rc" 2>/dev/null || echo 0)"
SH
  cat > "$d/bin/hoststate.sh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$STUB/state/hs_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/state/hs_n"
f="$STUB/state/hs_$n"
[[ -f "$f.out" || -f "$f.rc" ]] || { last="$(ls "$STUB"/state/hs_[0-9]*.out | sort -V | tail -1)"; f="${last%.out}"; }
rc="$(cat "$f.rc" 2>/dev/null || echo 0)"
echo "hoststate call $n rc=$rc" >> "$STUB/hs.log"
[[ "$rc" == 0 ]] && cat "$f.out"
exit "$rc"
SH
  cat > "$d/bin/bsquery.sh" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$STUB/state/bs_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/state/bs_n"
f="$STUB/state/bs_$n"
[[ -f "$f.jsonl" || -f "$f.rc" ]] || { last="$(ls "$STUB"/state/bs_[0-9]*.jsonl | sort -V | tail -1)"; f="${last%.jsonl}"; }
rc="$(cat "$f.rc" 2>/dev/null || echo 0)"
echo "bsquery call $n rc=$rc $*" >> "$STUB/bs.log"
[[ "$rc" == 0 ]] && cat "$f.jsonl"
exit "$rc"
SH
  chmod +x "$d"/bin/*
}
# bs_row <epoch> <boot> <listener> [host]: one double-encoded Better Stack row of the tls-health series
bs_row() {
  jq -cn --arg dt "$(date -u -d "@$1" '+%Y-%m-%d %H:%M:%S')" --arg b "$2" --arg l "$3" --arg h "${4:-soleur-inngest}" \
    '{dt:$dt, raw:({marker:"SOLEUR_INNGEST_BOOT_STAGE",stage:"tls-health",shipper:"cloud-init-phone-home",host:$h,detail:("unit=active nrestarts=0 listener=" + $l + " boot_id=" + $b + " fetch_rc=0")} | tojson)}'
}
hs_set_in() { # dir n rc boot serving obs-epoch
  local d="$1" n="$2" rc="$3" boot="$4" serving="$5" obs="$6" verdict="SERVING   SERVING=yes"
  [[ "$serving" == no ]] && verdict="NOT SERVING   SERVING=no"
  printf '%s' "$rc" > "$d/state/hs_$n.rc"
  printf 'dedicated inngest host \xe2\x80\x94 newest probe row\n  observed_at    %s\n  instance_id    hetzner-1\n  boot_id        %s\n  probe_schema   4\n  VERDICT        %s\n' \
    "$(date -u -d "@$obs" '+%Y-%m-%d %H:%M:%S')" "$boot" "$verdict" > "$d/state/hs_$n.out"
}
bs_set_in() { local d="$1" n="$2"; shift 2; printf '0' > "$d/state/bs_$n.rc"; printf '%s\n' "$@" > "$d/state/bs_$n.jsonl"; }

FRESH_N=0
fresh() { FRESH_N=$((FRESH_N + 1)); D="$TMP/s$FRESH_N"; make_stubs "$D"; }
G_BASE=(DOPPLER_TOKEN=dp.fixture BETTERSTACK_QUERY_HOST=bs.invalid BETTERSTACK_QUERY_USERNAME=bsuser BETTERSTACK_QUERY_PASSWORD=bspass INPUT_REASON=fixture)
G_ROTATE=("${G_BASE[@]}" INPUT_MODE=rotate INPUT_KEYS=both "INPUT_CONFIRM=ROTATE-INNGEST-BOTH-$TODAY" INPUT_QUIET_WINDOW=true)
G_PLAN=("${G_BASE[@]}" INPUT_MODE=plan INPUT_KEYS=both INPUT_CONFIRM= INPUT_QUIET_WINDOW=false)
G_CONVERGE=("${G_BASE[@]}" INPUT_MODE=converge INPUT_KEYS=both "INPUT_CONFIRM=CONVERGE-INNGEST-BOTH-$TODAY" INPUT_QUIET_WINDOW=true)
A_ENV=(AWS_ACCESS_KEY_ID=AKIAfixture AWS_SECRET_ACCESS_KEY=secretfixture DOPPLER_TOKEN=dp.fixture DOPPLER_TOKEN_TF=dp.tffixture)

RUN_SCRIPT="$BODY"
# run_script <subcommand> [VAR=val ...] (uses $D and $RUN_SCRIPT): sets OUT (stdout+stderr), RC, and ALL (OUT plus the
# job-output file and the step summary: every stream a run can publish).
run_script() {
  local sub="$1"; shift
  : > "$D/gh_output"; : > "$D/summary"
  OUT="$(env -i PATH="$D/bin:$PATH" HOME="$D" STUB="$D" TMPDIR="$D/rt" RUNNER_TEMP="$D/rt" \
    KR_NOW="cat $D/state/now" KR_SLEEP="$D/bin/adv" KR_HZ_BASE="https://hz.invalid" KR_TRACK="$D/bin/track.sh" \
    KR_HOST_STATE="$D/bin/hoststate.sh" KR_BS_QUERY="$D/bin/bsquery.sh" KR_INFRA_DIR="$D/infra" \
    GITHUB_OUTPUT="$D/gh_output" GITHUB_STEP_SUMMARY="$D/summary" GITHUB_RUN_ID=9001 GITHUB_RUN_ATTEMPT=1 \
    GITHUB_REPOSITORY=acme/repo GITHUB_SERVER_URL=https://github.example GH_TOKEN=ghs_fixture \
    "$@" bash "$RUN_SCRIPT" "$sub" 2>&1)"; RC=$?
  ALL="$OUT"$'\n'"$(cat "$D/gh_output" "$D/summary" 2>/dev/null)"
  printf '%s\n' "$ALL" >> "${STREAMS_FILE:-$TMP/all-streams.txt}"
}
out_of() { grep "^$2=" "$D/gh_output" | tail -1 | cut -d= -f2-; }
verdict_of() { out_of "$D" verdict; }
npost() { [[ -f "$D/post.log" ]] || { echo 0; return; }; wc -l < "$D/post.log" | tr -d ' '; }
nlog() { [[ -f "$1" ]] || { echo 0; return; }; grep -c "$2" "$1" || true; }
: > "$TMP/all-streams.txt"

# kr_sentinel_hits <file>: the Guard 2 checker. Any key-shaped string in a captured stream is a hit (the sentinels AND the
# generic shapes: 64 hex, a 43-character base64url run, signkey-*, an [id=...] group).
kr_sentinel_hits() {
  grep -Ec "$S_HEX|$S_B64|signkey-(prod|test)-[A-Za-z0-9_-]{8,}|\[id=[A-Za-z0-9_-]{20,}\]|[0-9a-f]{64}|[A-Za-z0-9_-]{43}" "$1" || true
}

[[ "${#S_B64}" == 43 && "${#S_HEX}" == 64 && "${#S_SIGN}" == 77 ]] && ok "C-fix sentinels have the shape of the real material (43-char base64url id, 64-hex, signkey-prod-<64 hex>)" || bad "C-fix sentinel lengths ${#S_B64}/${#S_HEX}/${#S_SIGN}"
iso_of() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

printf '\n=== D. guard: the refusal ladder ===\n'
fresh; run_script guard "${G_ROTATE[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == guard_ok && "$(out_of "$D" go)" == true && "$(out_of "$D" run_apply1)" == true && "$(out_of "$D" run_reboot)" == true && "$(out_of "$D" run_apply2)" == true && "$(out_of "$D" run_redeploy)" == true && "$(out_of "$D" reboot_post)" == true ]] \
  && ok "D1 a fully compliant rotate passes the guard with go=true and every later job enabled" || bad "D1 rc=$RC" "$OUT"
[[ "$(out_of "$D" server_id)" == 4242 && "$(out_of "$D" boot_pre)" == abcd1234 && "$(out_of "$D" mode)" == rotate && "$(out_of "$D" keys)" == both ]] && ok "D2 the guard outputs the server id and the pre-reboot boot_id (8 hex) for the later jobs" || bad "D2 outputs" "$(cat "$D/gh_output")"
[[ "$(nlog "$D/curl.log" 'token=ro')" -ge 1 && "$(nlog "$D/curl.log" 'token=write')" == 0 && "$(npost)" == 0 ]] && ok "D3 the guard talks to Hetzner with the READ-ONLY token only, GET only (it holds no write token and makes no POST)" || bad "D3 token class" "$(cat "$D/curl.log")"

# one refusal row: <description> <expected-token> <fixture-mutator>... (args after the token are VAR=val for the script env)
refuse_row() { # id desc token sub-envs...; the fixture is prepared by the caller before this call
  local id="$1" desc="$2" tok="$3"; shift 3
  run_script guard "$@"
  if [[ "$RC" != 0 && "$(verdict_of)" == "$tok" && "$(out_of "$D" go)" == false && "$(npost)" == 0 && "$(nlog "$D/tf.log" .)" == 0 ]]; then ok "$id $desc -> verdict=$tok, go=false, nothing written"; else bad "$id $desc" "rc=$RC verdict=$(verdict_of) want=$tok"; fi
}
fresh; refuse_row D4 "mode outside {plan,rotate,converge}" inputs_invalid "${G_ROTATE[@]}" INPUT_MODE=apply
fresh; refuse_row D5 "keys outside {signing,event,both}" inputs_invalid "${G_ROTATE[@]}" INPUT_KEYS=all
fresh; refuse_row D6 "a blank reason" inputs_invalid "${G_ROTATE[@]}" "INPUT_REASON=   "
fresh; refuse_row D7 "run_attempt=2 on rotate (a re-run reuses the inputs and would bypass the owner's go)" rerun_refused "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=2
[[ ! -e "$D/doppler.log" && ! -e "$D/curl.log" && ! -e "$D/gh.log" ]] && ok "D7b a refusal on run_attempt reads nothing (cheap checks run before any read)" || bad "D7b reads happened before the refusal"
fresh; refuse_row D8 "a confirm with the wrong date" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=ROTATE-INNGEST-BOTH-2001-01-01"
fresh; refuse_row D9 "a confirm that names the other key set" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=ROTATE-INNGEST-SIGNING-$TODAY"
fresh; refuse_row D10 "a CONVERGE confirm on a rotate" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=CONVERGE-INNGEST-BOTH-$TODAY"
fresh; refuse_row D11 "quiet_window=false" quiet_window_missing "${G_ROTATE[@]}" INPUT_QUIET_WINDOW=false
fresh; refuse_row D12 "the Better Stack pair missing" credential_absent "${G_ROTATE[@]}" BETTERSTACK_QUERY_PASSWORD=
fresh; printf '%s' 'pending:1700000000' > "$D/state/link"; refuse_row D13 "the link flag pending:<epoch>" link_flag_pending "${G_ROTATE[@]}"
fresh; printf 'OTHER\n' > "$D/state/names"; refuse_row D14 "the link flag absent (plaintext link)" link_flag_unset "${G_ROTATE[@]}"
fresh; printf '0' > "$D/state/link"; refuse_row D15 "the link flag neither 1 nor pending" link_flag_invalid "${G_ROTATE[@]}"
fresh; printf '1' > "$D/state/names_rc"; refuse_row D16 "the flag source config unreadable" link_flag_unreadable "${G_ROTATE[@]}"
fresh; printf '%s' '{"state":"OPEN","stateReason":null}' > "$D/state/soak.json"; refuse_row D17 "tracker #11215 still open" soak_open "${G_ROTATE[@]}"
fresh; printf '%s' '{"state":"CLOSED","stateReason":"NOT_PLANNED"}' > "$D/state/soak.json"; refuse_row D18 "tracker #11215 closed as not planned (not a PASS)" soak_open "${G_ROTATE[@]}"
fresh; printf '1' > "$D/state/soak_rc"; refuse_row D19 "tracker #11215 unreadable" soak_unreadable "${G_ROTATE[@]}"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_apply-web-platform-infra.yml_in_progress.json"; refuse_row D20 "an apply-web-platform-infra run in flight" run_in_flight "${G_ROTATE[@]}"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_web-platform-release.yml_queued.json"; refuse_row D21 "a queued web-platform-release run (not serialized by the route's groups)" run_in_flight "${G_ROTATE[@]}"
fresh; printf '1' > "$D/state/runlist_rc"; refuse_row D22 "the run list unreadable" run_list_unreadable "${G_ROTATE[@]}"
fresh; printf '[{"databaseId":9001}]' > "$D/state/inflight_inngest-key-rotate.yml_in_progress.json"; run_script guard "${G_ROTATE[@]}"
[[ "$RC" == 0 ]] && ok "D23 the guard's own run is not counted as an in-flight run" || bad "D23 own run counted" "$OUT"
fresh; printf '%s' '{"servers":[{"id":1,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]},{"id":2,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$D/state/servers.json"; refuse_row D24 "two servers named soleur-inngest" host_not_unique "${G_ROTATE[@]}"
fresh; printf '%s' '{"servers":[{"id":4242,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.99"}]}]}' > "$D/state/servers.json"; refuse_row D25 "the server's private IP is not 10.0.1.40" host_not_unique "${G_ROTATE[@]}"
fresh; printf '500' > "$D/state/servers_code"; refuse_row D26 "the Hetzner lookup answers 500" hetzner_unreadable "${G_ROTATE[@]}"
fresh; rm -f "$D/state/hz_ro"; refuse_row D27 "the read-only Hetzner token unreadable" credential_absent "${G_ROTATE[@]}"
fresh; hs_set_in "$D" 1 0 abcd1234 no $((NOW0 - 60)); refuse_row D28 "the pre-reboot host reads NOT SERVING" host_not_serving_pre "${G_ROTATE[@]}"
fresh; hs_set_in "$D" 1 4 abcd1234 yes $((NOW0 - 60)); refuse_row D29 "no probe row at all (silence is not health)" host_not_serving_pre "${G_ROTATE[@]}"
fresh; hs_set_in "$D" 1 6 abcd1234 yes $((NOW0 - 60)); refuse_row D30 "the host-state read failed (exit 6: no verdict, never a host claim)" host_state_unreadable "${G_ROTATE[@]}"
fresh; bs_set_in "$D" 1 "$(bs_row $((NOW0 - 120)) abcd1234 0)"; refuse_row D31 "SERVING but the newest tls-health row has listener=0" host_not_serving_pre "${G_ROTATE[@]}"
fresh; printf '1' > "$D/state/bs_1.rc"; refuse_row D32 "the tls-health read fails" host_state_unreadable "${G_ROTATE[@]}"
# the ladder's ORDER: with two things wrong, the earlier rung is the verdict
fresh; printf 'pending:1700000000' > "$D/state/link"; printf '%s' '{"state":"OPEN","stateReason":null}' > "$D/state/soak.json"; refuse_row D33 "link flag AND soak both wrong: the link flag (earlier rung) is the verdict" link_flag_pending "${G_ROTATE[@]}"

# mode=plan reports and refuses on none of the soft checks
fresh; printf 'pending:1700000000' > "$D/state/link"; printf '%s' '{"state":"OPEN","stateReason":null}' > "$D/state/soak.json"
run_script guard "${G_PLAN[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" == 0 && "$(out_of "$D" go)" == true && "$(out_of "$D" run_apply1)" == true && "$(out_of "$D" run_reboot)" == false && "$(out_of "$D" run_apply2)" == false && "$(out_of "$D" run_redeploy)" == false && "$(npost)" == 0 ]] \
  && ok "D34 plan with the flag pending, the soak open, no attestation and run_attempt=2 exits 0 with go=true, enables only apply1 and writes nothing" || bad "D34 plan rc=$RC" "$OUT"
[[ "$ALL" == *"link_flag_is_1=false"* && "$ALL" == *"soak_closed_completed=false"* && "$ALL" == *"quiet_window_attested=false"* && "$ALL" == *"run_attempt_is_1=false"* && "$ALL" == *"confirm_ok=false"* && "$ALL" == *"no_run_in_flight=true"* ]] && ok "D35 plan reports each check as a boolean (link_flag_is_1, soak_closed_completed, quiet_window_attested, run_attempt_is_1, confirm_ok, ...)" || bad "D35 booleans" "$ALL"
fresh; run_script guard "${G_PLAN[@]}" INPUT_MODE=bogus
[[ "$RC" != 0 && "$(verdict_of)" == inputs_invalid ]] && ok "D36 plan still refuses malformed inputs" || bad "D36 plan inputs"

printf '\n=== D. guard: converge derivation ===\n'
RUNS_JSON='[{"databaseId":9001,"displayTitle":"inngest-key-rotate converge both","event":"workflow_dispatch"},{"databaseId":8002,"displayTitle":"inngest-key-rotate plan both","event":"workflow_dispatch"},{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]'
conv_fixture() { # rotated_at-epoch: a rotate run whose apply1 succeeded then; a plan run (never qualifies)
  printf '%s' "$RUNS_JSON" > "$D/state/krruns.json"
  printf '{"jobs":[{"name":"guard","conclusion":"success","completedAt":"%s"},{"name":"apply1","conclusion":"success","completedAt":"%s"}]}' "$(iso_of $(($1 - 600)))" "$(iso_of "$1")" > "$D/state/jobs_8001.json"
  printf '{"jobs":[{"name":"apply1","conclusion":"success","completedAt":"%s"}]}' "$(iso_of $(($1 + 99999)))" > "$D/state/jobs_8002.json"
}
ROT=$((NOW0 - 3600))
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$(bs_row $((NOW0 - 7200)) abcd1234 1)" "$(bs_row $((NOW0 - 300)) abcd1234 1)"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" run_apply1)" == false && "$(out_of "$D" rotated_at)" == "$ROT" && "$(out_of "$D" reboot_post)" == true && "$(out_of "$D" boot_pre)" == abcd1234 && "$(out_of "$D" run_apply2)" == true && "$(out_of "$D" run_redeploy)" == true ]] \
  && ok "D37 converge derives rotated_at from the newest non-plan run's successful apply1, skips apply1, and POSTs once when the newest boot began BEFORE rotated_at" || bad "D37 converge rc=$RC" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1800)) beef5678 1)" "$(bs_row $((NOW0 - 300)) beef5678 1)"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" boot_pre)" == "-" ]] && ok "D38 converge issues no reboot POST when the newest boot began after rotated_at (no age limit decides this)" || bad "D38 booted-after" "$OUT"
fresh; conv_fixture "$ROT"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"running\",\"finished\":null}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false ]] && ok "D39 converge issues no POST while a Hetzner reboot action is running" || bad "D39 running action" "$OUT"
fresh; conv_fixture "$ROT"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"success\",\"finished\":\"$(iso_of $((ROT + 60)))\"}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false ]] && ok "D40 converge issues no POST when a reboot action finished after rotated_at" || bad "D40 finished action" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$(bs_row $((NOW0 - 7200)) abcd1234 1)" "$(bs_row $((NOW0 - 300)) abcd1234 1)"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"success\",\"finished\":\"$(iso_of $((ROT - 600)))\"}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == true ]] && ok "D41 a reboot action that finished BEFORE rotated_at does not count (the host may still run the old keys)" || bad "D41 old action" "$OUT"
fresh; refuse_row D42 "converge with no earlier run at all" converge_source_missing "${G_CONVERGE[@]}"
fresh; printf '%s' '[{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]' > "$D/state/krruns.json"
printf '{"jobs":[{"name":"guard","conclusion":"failure","completedAt":"%s"}]}' "$(iso_of "$ROT")" > "$D/state/jobs_8001.json"
refuse_row D43 "a guard-refused run (no apply1 job) does not qualify as the source" converge_source_missing "${G_CONVERGE[@]}"
fresh; printf '%s' '[{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]' > "$D/state/krruns.json"
printf '{"jobs":[{"name":"apply1","conclusion":"failure","completedAt":"%s"}]}' "$(iso_of "$ROT")" > "$D/state/jobs_8001.json"
refuse_row D44 "a run whose apply1 FAILED does not qualify (converge never mints a key, so it only resumes a completed phase 1)" converge_source_missing "${G_CONVERGE[@]}"
fresh; conv_fixture "$ROT"; refuse_row D45 "converge keys=signing against a both rotation" converge_mismatch "${G_CONVERGE[@]}" INPUT_KEYS=signing "INPUT_CONFIRM=CONVERGE-INNGEST-SIGNING-$TODAY"
fresh; conv_fixture "$ROT"; refuse_row D46 "an owner-supplied rotated_at that disagrees with the run" converge_mismatch "${G_CONVERGE[@]}" "INPUT_ROTATED_AT=$(iso_of $((ROT - 7200)))"
fresh; conv_fixture "$ROT"; run_script guard "${G_CONVERGE[@]}" "INPUT_ROTATED_AT=$(iso_of $((ROT + 30)))"
[[ "$RC" == 0 ]] && ok "D47 an owner-supplied rotated_at that agrees (within 10 minutes) is accepted" || bad "D47 agreeing rotated_at" "$OUT"
fresh; conv_fixture "$ROT"; refuse_row D48 "run_attempt=2 on converge" rerun_refused "${G_CONVERGE[@]}" GITHUB_RUN_ATTEMPT=2
fresh; conv_fixture "$ROT"; printf 'pending:1700000000' > "$D/state/link"; refuse_row D49 "converge refuses while the link flag is not 1" link_flag_pending "${G_CONVERGE[@]}"
fresh; conv_fixture "$ROT"; run_script guard "${G_CONVERGE[@]}"
[[ "$(nlog "$D/gh.log" 'run view 9001')" == 0 ]] && ok "D50 the converge derivation never reads its own run" || bad "D50 own run read"

printf '\n=== E. Guard 1: the plan gates (fixtures against kr_gate) ===\n'
# pj <addr=actions[;nobefore]>...: a `terraform show -json` shaped fixture. before/after carry the sentinels, as a real plan does.
pj() {
  printf '%s\n' "$@" | jq -R -s -c --arg id "$S_B64" --arg hex "$S_HEX" '
    split("\n") | map(select(length > 0)) | map(split("=") as $p | ($p[1] | split(";")) as $q
      | {address: $p[0], mode: "managed", type: ($p[0] | split(".")[0]), name: ($p[0] | split(".")[1]),
         change: {actions: ($q[0] | split(",")), before: (if ($q[1] // "") == "nobefore" then null else {id: $id, hex: $hex} end), after: {id: $id, hex: $hex}}})
    | {format_version: "1.2", resource_changes: .}'
}
R_S=random_id.inngest_signing_key_dedicated=delete,create
R_E=random_id.inngest_event_key_dedicated=delete,create
D_S=doppler_secret.inngest_signing_key_dedicated=update
D_E=doppler_secret.inngest_event_key_dedicated=update
P_S=doppler_secret.inngest_signing_key_prd=delete,create
P_E=doppler_secret.inngest_event_key_prd=delete,create
gate_rc() { # phase keys plan-json -> rc (output discarded)
  printf '%s' "$3" > "$TMP/plan-fixture.json"
  ( kr_gate "$1" "$2" "$TMP/plan-fixture.json" ) >/dev/null 2>&1; echo $?
}
gate_out() { printf '%s' "$3" > "$TMP/plan-fixture.json"; ( kr_gate "$1" "$2" "$TMP/plan-fixture.json" ) 2>&1; }
NOOP=doppler_project.inngest=no-op
[[ "$(gate_rc A "signing event" "$(pj "$R_S" "$R_E" "$D_S" "$D_E" "$NOOP")")" == 0 ]] && ok "E1 Gate A passes keys=both: two random_id [delete,create] and two dedicated secrets [update]" || bad "E1"
[[ "$(gate_rc B "signing event" "$(pj "$P_S" "$P_E" "$NOOP")")" == 0 ]] && ok "E2 Gate B passes keys=both: the two app secrets [delete,create], everything else a no-op" || bad "E2"
[[ "$(gate_rc A signing "$(pj "$R_S" "$D_S")")" == 0 && "$(gate_rc A event "$(pj "$R_E" "$D_E")")" == 0 && "$(gate_rc B signing "$(pj "$P_S")")" == 0 ]] && ok "E3 keys=signing and keys=event each pass with only their own pair" || bad "E3"
[[ "$(gate_rc A "signing event" "$(pj "$R_S" "$R_E" "$D_S")")" != 0 ]] && ok "E4 (mutation 2 shape) a count short of the table (one dedicated secret missing) is refused" || bad "E4"
[[ "$(gate_rc A "signing event" "$(pj "$R_S" "$R_E" "$D_S" "$D_E" doppler_secret.inngest_redis_password_dedicated=update)")" != 0 ]] && ok "E5 (mutation 3) a compliant plan plus a second update on doppler_secret.inngest_redis_password_dedicated is refused" || bad "E5"
[[ "$(gate_rc A "signing event" '{"format_version":"1.2","resource_changes":[]}')" != 0 && "$(gate_rc B "signing event" '{"format_version":"1.2"}')" != 0 ]] && ok "E6 (mutation 4) an EMPTY plan is refused (the change count, not all() over [], is what fails it)" || bad "E6"
[[ "$(gate_rc B "signing event" "$(pj doppler_secret.inngest_signing_key_prd=update "$P_E")")" != 0 ]] && ok "E7 (mutation 5) Gate B where the app secret shows [update] (an ignore_changes no-replace) is refused" || bad "E7"
[[ "$(gate_rc A signing "$(pj "$R_S" "$D_S" "$R_E" "$D_E")")" != 0 ]] && ok "E8 (mutation 6) a keys=signing plan that also changes the event pair is refused" || bad "E8"
[[ "$(gate_rc A "signing event" "$(pj random_id.inngest_signing_key_dedicated=create\;nobefore "$R_E" "$D_S" "$D_E")")" != 0 && "$(gate_rc A "signing event" "$(pj random_id.inngest_signing_key_dedicated=create "$R_E" "$D_S" "$D_E")")" != 0 ]] && ok "E9 (mutation 7) a bare [create] of random_id.inngest_signing_key_dedicated (a new key where none was in state) is refused, even with before=null" || bad "E9"
[[ "$(gate_rc A "signing event" "$(pj "$R_S" "$R_E" "$D_S" "$D_E" hcloud_server.inngest=update)")" != 0 && "$(gate_rc A "signing event" "$(pj "$R_S" "$R_E" "$D_S" "$D_E" terraform_data.x=update tls_private_key.y=create)")" != 0 ]] && ok "E10 hcloud_*, terraform_data.* and tls_* changes are refused" || bad "E10"
[[ "$(gate_rc A "signing event" "$(pj random_id.inngest_signing_key_dedicated=create,delete "$R_E" "$D_S" "$D_E")")" != 0 ]] && ok "E11 the action array is exact: [create,delete] is not [delete,create]" || bad "E11"
[[ "$(gate_rc A "signing event" "$(pj "$R_S" "$R_E" doppler_secret.inngest_signing_key_dedicated=delete,create "$D_E")")" != 0 ]] && ok "E12 a dedicated secret that would be REPLACED (not updated in place) is refused" || bad "E12"
IDXJSON="$(pj "$R_S" "$R_E" "$D_S" "$D_E" | jq -c '.resource_changes[0].index = 0')"
[[ "$(gate_rc A "signing event" "$IDXJSON")" != 0 ]] && ok "E13 an indexed instance (count/for_each) of an allowlisted address is refused (index must be null)" || bad "E13"
DATAJSON="$(pj "$R_S" "$R_E" "$D_S" "$D_E" | jq -c '.resource_changes[0].mode = "data"')"
[[ "$(gate_rc A "signing event" "$DATAJSON")" != 0 ]] && ok "E14 a data-mode entry under an allowlisted address is refused" || bad "E14"
[[ "$(gate_rc A "signing event" "$(pj "$R_S" "$R_S" "$D_S" "$D_E")")" != 0 ]] && ok "E15 a duplicated address (and a missing one) is refused: the address sets must be equal" || bad "E15"
[[ "$(gate_rc B "signing event" "$(pj "$P_S" "$P_E" "$D_S")")" != 0 && "$(gate_rc B "signing event" "$(pj "$P_S" "$P_E" "$R_S")")" != 0 ]] && ok "E16 in Gate B the dedicated random_id and secret must be no-ops: a change to either is refused" || bad "E16"
# harness rows (b): must-PASS non-canonical inputs
[[ "$(gate_rc A event "$(pj "$NOOP" "$D_E" doppler_secret.inngest_signing_key_dedicated=no-op "$R_E" random_id.inngest_signing_key_dedicated=no-op)")" == 0 ]] && ok "E17 (harness b) keys=event with reordered resource_changes and extra no-op entries PASSES" || bad "E17"
[[ "$(gate_rc B "signing event" "$(pj doppler_secret.inngest_signing_key_prd=create\;nobefore "$P_E")")" == 0 && "$(gate_rc B "signing event" "$(pj doppler_secret.inngest_signing_key_prd=create\;nobefore doppler_secret.inngest_event_key_prd=create\;nobefore)")" == 0 ]] && ok "E18 (harness b) the documented recovery shape (a bare [create] of an app secret whose before is null) PASSES Gate B" || bad "E18"
[[ "$(gate_rc B "signing event" "$(pj doppler_secret.inngest_signing_key_prd=create "$P_E")")" != 0 ]] && ok "E19 a bare [create] with a NON-null before is not the recovery shape and is refused" || bad "E19"
GO="$(gate_out A "signing event" "$(pj "$R_S" "$R_E" "$D_S" "$D_E" hcloud_server.inngest=update)")"
[[ "$GO" == *"verdict=plan_gate_refused"* && "$GO" == *"hcloud_server.inngest update"* && "$(kr_sentinel_hits <(printf '%s' "$GO"))" == 0 ]] && ok "E20 a refusal prints verdict=plan_gate_refused with the offending ADDRESS and ACTION and no plan value" || bad "E20 refusal text" "$GO"
# the table-derived sites agree with each other
for ph in A B; do
  for kk in "signing event" signing event; do
    t="$(kr_gate_targets "$ph" "$kk" | sed 's/^-target=//' | sort | tr '\n' ' ')"
    w="$(kr_gate_want "$ph" "$kk" | jq -r '.[].address' | sort | tr '\n' ' ')"
    r="$(kr_gate_replaces "$ph" "$kk" | sed 's/^-replace=//' | sort | tr '\n' ' ')"
    wr="$(kr_gate_want "$ph" "$kk" | jq -r '.[] | select(.actions == ["delete","create"]) | .address' | sort | tr '\n' ' ')"
    [[ "$t" == "$w" && "$r" == "$wr" && -n "$t" ]] || bad "E21 table sites disagree for phase $ph keys '$kk'" "t=$t w=$w r=$r wr=$wr"
  done
done
ok "E21 for both phases and every key selection, the -target list equals the jq allowlist addresses and the -replace list equals its [delete,create] rows"

printf '\n=== F. apply1 / apply2 end to end against stubs ===\n'
APPLY_PLAN=(EFF_MODE=plan EFF_KEYS=both "${A_ENV[@]}")
fresh; run_script apply1 "${APPLY_PLAN[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == plan_ok && "$(nlog "$D/tf.log" '^apply')" == 0 && "$(nlog "$D/tf.log" '^terraform plan')" == 2 ]] && ok "F1 mode=plan runs Gate A and Gate B plans (2 plans), applies nothing and reports verdict=plan_ok" || bad "F1 rc=$RC" "$OUT"
[[ "$(cat "$D/state/copy_host_signing")" == "$OLD_SIGN" && "$(cat "$D/state/copy_app_signing")" == "$OLD_SIGN" && ! -e "$D/state/applyn" ]] && ok "F2 mode=plan changes neither copy" || bad "F2 plan wrote"
[[ "$(kr_sentinel_hits "$D/summary")" == 0 && "$(kr_sentinel_hits <(printf '%s' "$OUT"))" == 0 ]] && ok "F3 mode=plan: the stub terraform printed [id=..], 64-hex and signkey-prod- strings on both streams; none reached the output or the summary" || bad "F3 sentinel in plan output" "$OUT"
grep -q 'plan .*T random_id.inngest_signing_key_dedicated' "$D/tf.log" && grep -q 'plan .*T doppler_secret.inngest_signing_key_prd' "$D/tf.log" && ok "F4 the two plans carry the phase-1 targets and the phase-2 targets respectively" || bad "F4 plan targets" "$(cat "$D/tf.log")"
fresh; run_script apply1 EFF_MODE=plan EFF_KEYS=event "${A_ENV[@]}"
[[ "$RC" == 0 && "$(grep -c 'signing' "$D/tf.log")" == 0 && "$(grep -c 'event' "$D/tf.log")" -ge 2 ]] && ok "F5 keys=event plans only the event pair" || bad "F5 event only" "$(cat "$D/tf.log")"
fresh; printf '%s' '[{"address":"doppler_secret.inngest_redis_password_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_a"
run_script apply1 "${APPLY_PLAN[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == plan_gate_refused && "$ALL" == *"doppler_secret.inngest_redis_password_dedicated update"* ]] && ok "F6 a plan with a stray redis-password update is refused end to end (names the address and action only)" || bad "F6 rc=$RC" "$OUT"

APPLY_ROT=(EFF_MODE=rotate EFF_KEYS=both "${A_ENV[@]}")
fresh; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply1_ok && "$(nlog "$D/tf.log" '^apply a')" == 1 && "$(nlog "$D/tf.log" '^apply b')" == 0 ]] && ok "F7 rotate apply1 applies phase 1 exactly once and never phase 2" || bad "F7 rc=$RC" "$OUT"
[[ "$(cat "$D/state/copy_host_signing")" != "$OLD_SIGN" && "$(cat "$D/state/copy_host_event")" != "$OLD_EVENT" && "$(cat "$D/state/copy_app_signing")" == "$OLD_SIGN" && "$(cat "$D/state/copy_app_event")" == "$OLD_EVENT" ]] && ok "F8 after phase 1 the dedicated copies are new and the app copies are untouched (they legitimately differ until phase 2)" || bad "F8 copies"
[[ "$ALL" == *"new_differs_from_prior=true"* ]] && ok "F9 the new-differs-from-prior result is reported as a boolean" || bad "F9 boolean"
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 ]] && ok "F10 GUARD 2 SENTINEL: a full rotate apply1 with a stub terraform that prints key-shaped strings on both streams leaves none in stdout, stderr, the job outputs or the summary" || bad "F10 sentinel in apply1 streams" "$(printf '%s' "$ALL" | head -20)"
[[ -z "$(ls -d "$D"/rt/inngest-key-rotate.* 2>/dev/null)" ]] && ok "F11 the private temp dir (with the plan JSON) is removed on exit" || bad "F11 temp dir left behind"
fresh; run_script apply1 EFF_MODE=rotate EFF_KEYS=signing "${A_ENV[@]}"
[[ "$RC" == 0 && "$(cat "$D/state/copy_host_signing")" != "$OLD_SIGN" && "$(cat "$D/state/copy_host_event")" == "$OLD_EVENT" ]] && ok "F12 keys=signing rotates the signing pair only" || bad "F12 signing only"
fresh; run_script apply1 "${APPLY_ROT[@]}" TF_LOG=DEBUG TF_LOG_PATH="$D/tf-debug.log"
[[ "$RC" == 0 && ! -e "$D/tf-debug.log" && "$(nlog "$D/tf.log" 'TFLOG=unset TFLOGPATH=unset')" -ge 3 ]] && ok "F13 with TF_LOG=DEBUG and TF_LOG_PATH exported, kr_tf unsets them: no debug log is written and no key leaks" || bad "F13 TF_LOG leaked" "$(cat "$D/tf.log")"
fresh; printf '1' > "$D/state/plan_rc"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == terraform_failed && "$(nlog "$D/tf.log" '^apply')" == 0 && ! -e "$D/issues_created.log" && "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 ]] && ok "F14 a failed plan prints terraform_failed with the exit code only, applies nothing, files no issue (nothing was written)" || bad "F14 rc=$RC" "$OUT"
fresh; printf '1' > "$D/state/init_rc"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == terraform_failed ]] && ok "F15 a failed init is terraform_failed" || bad "F15"
fresh; run_script apply1 EFF_MODE=rotate EFF_KEYS=both AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY= DOPPLER_TOKEN=dp.x DOPPLER_TOKEN_TF=dp.y
[[ "$RC" != 0 && "$(verdict_of)" == credential_absent && ! -e "$D/tf.log" ]] && ok "F16 a missing Terraform backend pair is credential_absent and nothing runs" || bad "F16"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_cutover-inngest.yml_queued.json"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_in_flight && ! -e "$D/tf.log" ]] && ok "F17 rotate apply1 re-runs the in-flight refusal first: a queued cutover-inngest run stops it before any Terraform call" || bad "F17"
fresh; run_script apply1 "${APPLY_PLAN[@]}"; [[ "$(nlog "$D/gh.log" 'run list')" == 0 ]] && ok "F18 mode=plan skips the in-flight refusal (it writes nothing)" || bad "F18"
fresh; printf '1' > "$D/state/apply_rc"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == apply_failed && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"mode=converge -f keys=both -f confirm=CONVERGE-INNGEST-BOTH-$TODAY"* && "$ALL" == *"needs the owner's own per-command go"* && "$(wc -l < "$D/issues_created.log")" == 1 && "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 ]] \
  && ok "F19 a failed phase-1 apply prints ONE stop sentence with the exact converge command (owner's go), files one action-required issue, leaks nothing" || bad "F19 rc=$RC" "$OUT"
grep -q -- '--label action-required' "$D/gh.log" && ok "F20 the issue is filed with the action-required label" || bad "F20 label"
fresh; touch "$D/state/apply_noeffect"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == value_unchanged && "$ALL" == *"new_differs_from_prior=false"* ]] && ok "F21 an apply after which the dedicated copy is unchanged fails as value_unchanged" || bad "F21 rc=$RC" "$OUT"
fresh; touch "$D/state/copy_unreadable"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copy_unreadable && "$(nlog "$D/tf.log" '^apply')" == 0 ]] && ok "F22 an unreadable dedicated copy before the apply stops it (no prior hash, no apply)" || bad "F22"
fresh; run_script apply1 EFF_MODE=converge EFF_KEYS=both "${A_ENV[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == internal_error && ! -e "$D/tf.log" ]] && ok "F23 apply1 never runs for converge (converge never mints a key)" || bad "F23"

# apply2
after_phase1() { printf '%s' "signkey-prod-$(printf 'e%.0s' {1..63})1" > "$D/state/copy_host_signing"; printf '%s' "$(printf 'e%.0s' {1..63})1" > "$D/state/copy_host_event"; }
APPLY_2=(EFF_MODE=rotate EFF_KEYS=both "${A_ENV[@]}")
fresh; after_phase1; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply2_ok && "$(nlog "$D/tf.log" '^apply b')" == 1 && "$(nlog "$D/tf.log" '^apply a')" == 0 && "$ALL" == *"copies_equal=true"* ]] && ok "F24 rotate apply2 applies phase 2 once (app secrets only) and reports copies_equal=true" || bad "F24 rc=$RC" "$OUT"
cmp -s "$D/state/copy_host_signing" "$D/state/copy_app_signing" && cmp -s "$D/state/copy_host_event" "$D/state/copy_app_event" && ok "F25 after phase 2 both copies hold the same value" || bad "F25 copies differ"
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 ]] && ok "F26 GUARD 2 SENTINEL: a full apply2 leaves no key-shaped string in any stream" || bad "F26 sentinel in apply2" "$ALL"
! grep -q 'T random_id' "$D/tf.log" && ! grep -q 'R random_id' "$D/tf.log" && ok "F27 phase 2 never targets or replaces a random_id (it cannot mint a key)" || bad "F27 phase 2 touched random_id" "$(cat "$D/tf.log")"
fresh; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == value_unchanged && "$(nlog "$D/tf.log" '^apply')" == 0 ]] && ok "F28 rotate apply2 with the copies already equal (phase 1 did not land) refuses and applies nothing" || bad "F28"
fresh; run_script apply2 EFF_MODE=converge EFF_KEYS=both "${A_ENV[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply2_skipped && ! -e "$D/tf.log" ]] && ok "F29 converge apply2 with equal copies is skipped without a single Terraform call" || bad "F29 rc=$RC" "$OUT"
fresh; after_phase1; printf '%s' "$(cat "$D/state/copy_host_event")" > "$D/state/copy_app_event"; run_script apply2 EFF_MODE=converge EFF_KEYS=both "${A_ENV[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply2_ok ]] && grep -q 'plan .*doppler_secret.inngest_signing_key_prd' "$D/tf.log" && ! grep -q 'doppler_secret.inngest_event_key_prd' "$D/tf.log" && ok "F30 converge apply2 resumes only the key whose copies differ" || bad "F30 partial converge" "$(cat "$D/tf.log")"
fresh; after_phase1; printf '%s' '[{"address":"doppler_secret.inngest_signing_key_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_b"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == plan_gate_refused && "$(nlog "$D/tf.log" '^apply')" == 0 ]] && ok "F31 Gate B refuses a phase-2 plan that also changes a dedicated address" || bad "F31"
fresh; after_phase1; printf '1' > "$D/state/apply_rc"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == apply_failed && "$ALL" == *"mode=converge"* && -s "$D/issues_created.log" ]] && ok "F32 a failed phase-2 apply prints the stop sentence with the converge command and files the issue" || bad "F32"
fresh; after_phase1; touch "$D/state/apply_noeffect"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copies_differ && "$ALL" == *"copies_equal=false"* ]] && ok "F33 phase 2 after which the copies still differ fails as copies_differ (boolean only)" || bad "F33"
fresh; after_phase1; printf '[{"databaseId":7}]' > "$D/state/inflight_inngest-link-flip.yml_in_progress.json"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_in_flight && ! -e "$D/tf.log" ]] && ok "F34 apply2 re-runs the in-flight refusal first (an inngest-link-flip run stops it)" || bad "F34"

printf '\n=== G. reboot: the one POST ===\n'
RB=(EFF_MODE=rotate EFF_KEYS=both EFF_SERVER_ID=4242 EFF_REBOOT_POST=true HCLOUD_TOKEN="$WRITE_TOK")
fresh; run_script reboot "${RB[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok && "$(npost)" == 1 && "$(out_of "$D" post_epoch)" == "$NOW0" ]] && ok "G1 the reboot step makes exactly ONE POST, polls the action to success and records the POST time" || bad "G1 rc=$RC posts=$(npost)" "$OUT"
grep -qx 'POST /v1/servers/4242/actions/reboot token=write' "$D/post.log" && [[ "$(nlog "$D/curl.log" 'token=ro')" == 0 ]] && ok "G2 the POST carries the WRITE token (and the reboot step never uses the read-only one)" || bad "G2 token class" "$(cat "$D/curl.log")"
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL" | grep -v 'add-mask'))" == 0 && "$ALL" != *"$WRITE_TOK"*$'\n'*"$WRITE_TOK"* ]] && ok "G3 no key-shaped string in the reboot step's streams" || bad "G3 sentinel"
fresh; run_script reboot "${RB[@]}" EFF_REBOOT_POST=false
[[ "$RC" == 0 && ! -e "$D/curl.log" ]] && ok "G4 EFF_REBOOT_POST=false (converge: a reboot already ran or the boot is newer than rotated_at) makes no Hetzner call at all" || bad "G4"
fresh; printf '500' > "$D/state/post_code"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == reboot_post_failed && "$(npost)" == 1 && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"mode=converge"* && -s "$D/issues_created.log" ]] && ok "G5 a failed POST is not retried (1 POST), prints the stop sentence with the converge command and files the issue" || bad "G5 rc=$RC posts=$(npost)" "$OUT"
fresh; printf 'error' > "$D/state/action_status"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == reboot_action_failed && "$(npost)" == 1 ]] && ok "G6 a Hetzner action that ends in error is reboot_action_failed (one POST)" || bad "G6"
fresh; printf 'running' > "$D/state/action_status"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == reboot_action_failed && "$(npost)" == 1 && $(( $(cat "$D/state/now") - NOW0 )) -le 330 ]] && ok "G7 an action that never finishes is bounded (the 300 s action budget) and fails without a second POST" || bad "G7 elapsed=$(( $(cat "$D/state/now") - NOW0 ))"
fresh; printf '%s' '{"servers":[{"id":9999,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$D/state/servers.json"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_not_unique && "$(npost)" == 0 ]] && ok "G8 the reboot step re-resolves the server by name AND IP and refuses when the id differs from the guard's (no POST)" || bad "G8"
fresh; run_script reboot "${RB[@]}" HCLOUD_TOKEN=
[[ "$RC" != 0 && "$(verdict_of)" == credential_absent && "$(npost)" == 0 ]] && ok "G9 an empty HCLOUD_TOKEN is credential_absent (no POST)" || bad "G9"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_deploy-inngest-image.yml_in_progress.json"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_in_flight && "$(npost)" == 0 ]] && ok "G10 the reboot step re-runs the in-flight refusal first (a deploy-inngest-image run stops it)" || bad "G10"
fresh; run_script reboot "${RB[@]}" EFF_SERVER_ID=abc
[[ "$RC" != 0 && "$(npost)" == 0 ]] && ok "G11 a non-numeric server id is refused" || bad "G11"
fresh; run_script reboot "${RB[@]}" EFF_MODE=plan
[[ "$RC" != 0 && "$(npost)" == 0 ]] && ok "G12 the reboot step refuses mode=plan" || bad "G12"
# the latch, in one process
latch_run() { # d status-code
  env -i PATH="$D/bin:$PATH" HOME="$D" STUB="$D" RUNNER_TEMP="$D/rt" KR_HZ_BASE=https://hz.invalid KR_NOW="cat $D/state/now" KR_SLEEP="$D/bin/adv" \
    HCLOUD_TOKEN="$WRITE_TOK" bash -c 'source "$1"; kr_init; KR_HZ_TOKEN="$HCLOUD_TOKEN"; kr_reboot_post 4242; r1=$?; kr_reboot_post 4242; r2=$?; echo "r1=$r1 r2=$r2"' _ "${1:-$BODY}" 2>&1
}
fresh; LR="$(latch_run)"
[[ "$(npost)" == 1 && "$LR" == *"r1=0 r2=1"* && "$LR" == *"verdict=reboot_refused_second_post"* ]] && ok "G13 (Guard 4 #3) calling the reboot function twice in one process issues ONE POST; the second call is verdict=reboot_refused_second_post" || bad "G13 posts=$(npost)" "$LR"
fresh; printf '500' > "$D/state/post_code"; LR="$(latch_run)"
[[ "$(npost)" == 1 && "$LR" == *"r1=1 r2=1"* ]] && ok "G14 a POST that FAILED also latches: no second POST (no auto-retry)" || bad "G14 posts=$(npost)" "$LR"
check "G15 the only caller of the reboot function is the reboot subcommand" bash -c "[ \"\$(grep -v '^ *#' '$BODY' | grep -c 'kr_reboot_post ')\" = 1 ]"

printf '\n=== G. verify: a new boot_id, SERVING, tls-health ===\n'
BSV=(BETTERSTACK_QUERY_HOST=bs.invalid BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p)
VF=(EFF_MODE=rotate EFF_KEYS=both EFF_BOOT_PRE=abcd1234 "EFF_POST_EPOCH=$NOW0" "${BSV[@]}")
OLDROW="$(bs_row $((NOW0 - 100)) abcd1234 1)"
fresh
hs_set_in "$D" 1 4 x yes 0; hs_set_in "$D" 2 4 x yes 0; hs_set_in "$D" 3 0 beef5678 yes $((NOW0 + 200))
bs_set_in "$D" 1 "$OLDROW"; bs_set_in "$D" 2 "$OLDROW"; bs_set_in "$D" 3 "$OLDROW" "$(bs_row $((NOW0 + 150)) beef5678 1)"
run_script verify "${VF[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok && "$ALL" == *"new_boot_id_seen=true serving=true tls_listener=1"* && "$(npost)" == 0 && ! -e "$D/curl.log" ]] && ok "G16 verify passes on a NEW boot_id + SERVING=yes + a tls-health row with that boot_id and listener=1; it makes no Hetzner call" || bad "G16 rc=$RC" "$OUT"
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 && "$ALL" != *"abcd1234"* && "$ALL" != *"beef5678"* ]] && ok "G17 verify prints booleans only: no boot_id, no host text" || bad "G17 host text leaked" "$ALL"
fresh; hs_set_in "$D" 1 4 x yes 0; bs_set_in "$D" 1 "$OLDROW"
run_script verify "${VF[@]}"; EL=$(( $(cat "$D/state/now") - NOW0 ))
[[ "$RC" != 0 && "$(verdict_of)" == host_silent && "$EL" -ge 600 && "$EL" -le 660 && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"No hard reset"* && -s "$D/issues_created.log" ]] && ok "G18 no new boot_id within 10 minutes is host_silent (elapsed ${EL}s): stop sentence, no hard reset, one action-required issue" || bad "G18 rc=$RC elapsed=$EL" "$OUT"
fresh; hs_set_in "$D" 1 0 abcd1234 yes $((NOW0 + 100)); bs_set_in "$D" 1 "$OLDROW" "$(bs_row $((NOW0 + 100)) abcd1234 1)"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_silent ]] && ok "G19 a row from the OLD boot_id (SERVING=yes, listener=1) is not evidence of a restart: host_silent" || bad "G19 old boot accepted" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 no $((NOW0 + 200)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 150)) beef5678 1)"
run_script verify "${VF[@]}"; EL=$(( $(cat "$D/state/now") - NOW0 ))
[[ "$RC" != 0 && "$(verdict_of)" == host_not_serving && "$EL" -ge 900 && "$EL" -le 960 && "$ALL" == *"No hard reset"* && -s "$D/issues_created.log" ]] && ok "G20 a new boot that stays NOT SERVING to the end of the 15-minute window is host_not_serving (elapsed ${EL}s), with the issue and no retry" || bad "G20 rc=$RC elapsed=$EL" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 + 200)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 150)) beef5678 0)"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_not_serving ]] && ok "G21 SERVING=yes with a new boot_id but tls-health listener=0 is host_not_serving (the TLS listener is part of the proof)" || bad "G21"
fresh; hs_set_in "$D" 1 6 x yes 0; printf '1' > "$D/state/bs_1.rc"; : > "$D/state/bs_1.jsonl"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_read_failed && "$ALL" == *"says nothing about the host"* ]] && ok "G22 a read that never produced a verdict is host_read_failed (no claim about the host)" || bad "G22 rc=$RC" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 + 200)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 150)) beef5678 1 some-other-host)"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_not_serving ]] && ok "G23 a tls-health row from another host does not satisfy the proof (host pinned to soleur-inngest)" || bad "G23 foreign host row accepted" "$OUT"
# converge: no POST this run; rows later than rotated_at decide
ROT2=$((NOW0 - 3600))
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 - 300)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1800)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_ROTATED_AT=$ROT2" "${BSV[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok ]] && ok "G24 converge (no POST): a boot whose rows are all later than rotated_at, SERVING and listener=1, passes" || bad "G24 rc=$RC" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 no $((NOW0 - 300)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1800)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_ROTATED_AT=$ROT2" "${BSV[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_not_serving ]] && ok "G25 converge refuses to go on while the host reads NOT SERVING (the redeploy is never reached)" || bad "G25"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 + 100)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 100)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_POST_EPOCH=$NOW0" "${BSV[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_silent ]] && ok "G26 converge after a POST with no boot_id to compare: a row inside the 180 s graceful-stop window is still the old boot" || bad "G26 premature accept" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 + 260)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 250)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_POST_EPOCH=$NOW0" "${BSV[@]}"
[[ "$RC" == 0 ]] && ok "G27 ...and a row after the graceful-stop window passes" || bad "G27" "$OUT"
fresh; run_script verify "${VF[@]}" EFF_POST_EPOCH= EFF_ROTATED_AT=
[[ "$RC" != 0 && "$(verdict_of)" == internal_error ]] && ok "G28 verify with neither a POST time nor rotated_at refuses" || bad "G28"
fresh; run_script verify "${VF[@]}" BETTERSTACK_QUERY_PASSWORD=
[[ "$RC" != 0 && "$(verdict_of)" == credential_absent ]] && ok "G29 verify without the Better Stack pair is credential_absent" || bad "G29"

printf '\n=== H. redeploy and the printed record ===\n'
RD=(EFF_MODE=rotate EFF_KEYS=both "EFF_ROTATED_AT=$((NOW0 - 3000))" "WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11" WEBHOOK_DEPLOY_SECRET=wh.fixture CF_ACCESS_CLIENT_ID=cfid.fixture CF_ACCESS_CLIENT_SECRET=cfsec.fixture)
fresh; run_script redeploy "${RD[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == rotate_ok && "$(nlog "$D/track.log" .)" == 1 ]] && grep -qx "track WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11 REDEPLOY_TIMEOUT_S=$B_REDEPLOY" "$D/track.log" && ok "H1 redeploy drives track.sh once with the full roster and the budget table's timeout (4800 s)" || bad "H1 rc=$RC" "$OUT"
grep -Eq '^S5-A5-DONE: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$OUT" && ok "H2 a green rotate prints the ready-to-paste S5-A5-DONE line (UTC time ending in Z) at the start of a line" || bad "H2 S5 line" "$OUT"
[[ "$ALL" == *"booleans: copies_equal=true new_boot_id_seen=true serving=true tls_listener=1"* && "$ALL" == *"actions/runs/9001"* && "$ALL" == *"rotated_at="* && "$ALL" == *"printed only"* ]] && ok "H3 the value-free evidence block carries timestamps, keys, booleans and the run URL, and says the line is printed only" || bad "H3 evidence" "$ALL"
[[ "$(nlog "$D/gh.log" 'issue comment')" == 0 && "$(nlog "$D/gh.log" 'api')" == 0 && ! -e "$D/issues_created.log" ]] && ok "H4 nothing in the route POSTS the S5-A5-DONE line (no gh comment, no gh api, no issue on success)" || bad "H4 posted something" "$(cat "$D/gh.log")"
check "H5 the script has no gh issue comment, gh api, or --method POST call (only a failure issue is ever created)" bash -c "! grep -Eq 'gh (issue comment|api)|--method POST|issue edit' < <(grep -v '^ *#' '$BODY')"
fresh; run_script redeploy "${RD[@]}" EFF_KEYS=event
[[ "$RC" == 0 && "$OUT" != *"S5-A5-DONE: 2"* && "$OUT" == *"no S5-A5-DONE line is printed"* ]] && ok "H6 keys=event prints no S5-A5-DONE line (A5 is the signing-key rotation)" || bad "H6" "$OUT"
fresh; run_script redeploy "${RD[@]}" EFF_MODE=converge
[[ "$RC" == 0 && "$(verdict_of)" == converge_ok ]] && grep -Eq '^S5-A5-DONE: ' <<<"$OUT" && ok "H7 a green converge prints the same S5-A5-DONE line" || bad "H7"
fresh; printf '1' > "$D/state/track_rc"; run_script redeploy "${RD[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == redeploy_failed && "$OUT" != *"S5-A5-DONE: 2"* && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"mode=converge"* && -s "$D/issues_created.log" ]] && ok "H8 a failed redeploy (canary or degraded fleet) is redeploy_failed: stop sentence with the converge command, issue filed, no S5 line" || bad "H8 rc=$RC" "$OUT"
fresh; run_script redeploy "${RD[@]}" WEB_HOST_PRIVATE_IPS=
[[ "$RC" != 0 && ! -e "$D/track.log" ]] && ok "H9 an empty roster is refused before anything is dispatched (a single-host redeploy leaves the fleet mixed)" || bad "H9"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_web-platform-release.yml_in_progress.json"; run_script redeploy "${RD[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_in_flight && ! -e "$D/track.log" ]] && ok "H10 redeploy re-runs the in-flight refusal first" || bad "H10"
fresh; run_script redeploy "${RD[@]}" EFF_MODE=plan
[[ "$RC" != 0 && ! -e "$D/track.log" ]] && ok "H11 redeploy refuses mode=plan" || bad "H11"

printf '\n=== I. mutations (Guard Contract batteries 1, 2 and 4) and harness rows ===\n'
# One Python table builds every mutated copy of the script, each by an EXACT single-occurrence replacement: a mutation that
# lands zero or several times is a suite defect and is reported as one (the edit must LAND before its verdict means anything).
MUTDIR="$TMP/mutants"; mkdir -p "$MUTDIR"; assert_fixture_dir "$MUTDIR"
python3 - "$BODY" "$MUTDIR" "$REPO_ROOT/scripts/lib" > "$TMP/mutants.log" <<'PYMUT'
import os, sys
src = open(sys.argv[1]).read()
out, lib = sys.argv[2], sys.argv[3]
M = {
 "target_hcloud": ("kr_gate_targets() { # one -target= per selected row\n", "kr_gate_targets() { # one -target= per selected row\n  printf -- '-target=%s\\n' hcloud_server.inngest\n"),
 "drop_replace_b": ("[[ \"$flag\" == replace ]] && printf -- '-replace=%s\\n' \"$addr\"", "[[ \"$flag\" == replace && \"$ph\" == A ]] && printf -- '-replace=%s\\n' \"$addr\""),
 "gate_true": ("  local phase=\"$1\" keys=\"$2\" plan=\"$3\" want n w reason lines\n", "  local phase=\"$1\" keys=\"$2\" plan=\"$3\" want n w reason lines\n  return 0\n"),
 "gate_skipped": ("  kr_gate \"$phase\" \"$keys\" \"$KR_TMP/tf-show-${name}.out\"\n}", "  return 0\n}"),
 "no_redirect": ("> \"$KR_TMP/tf-${name}.out\" 2> \"$KR_TMP/tf-${name}.err\" ) || rc=$?", ") || rc=$?"),
 "keep_tflog": ("env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER TF_IN_AUTOMATION=1", "env TF_IN_AUTOMATION=1"),
 "scrub_no_id": ("    -e 's/\\[id=[^]]*\\]/[id=<redacted>]/g' \\\n", ""),
 "bare_show": ("kr_gate_rows() {", "kr_leak_show() { terraform show -no-color tfplan; }\nkr_gate_rows() {"),
 "second_tf": ("kr_gate_rows() {", "kr_leak_second() { terraform \"$@\"; }\nkr_gate_rows() {"),
 "second_post_site": ("kr_gate_rows() {", "kr_leak_post() { kr_hz POST /v1/servers/1/actions/reboot /dev/null; }\nkr_gate_rows() {"),
 "drop_link": ("  kr_run_check link_flag_is_1 kr_chk_link || { kr_guard_report; return 1; }\n", ""),
 "drop_attempt": ("    kr_run_check run_attempt_is_1 kr_chk_attempt || return 1\n", ""),
 "drop_quiet": ("    kr_run_check quiet_window_attested kr_chk_quiet || return 1\n", ""),
 "drop_confirm": ("    kr_run_check confirm_ok kr_chk_confirm || return 1\n", ""),
 "drop_soak": ("  kr_run_check soak_closed_completed kr_chk_soak || { kr_guard_report; return 1; }\n", ""),
 "drop_serving": ("    rotate) kr_run_check host_serving_pre_reboot kr_chk_serving || { kr_guard_report; return 1; } ;;", "    rotate) : ;;"),
 "drop_latch": ("  if [[ \"$KR_POSTED\" == 1 ]]; then kr_refuse reboot_refused_second_post \"a second reboot POST in one run is refused\"; return 1; fi\n", ""),
 "drop_inflight_reboot": ("  kr_require_no_inflight || return 1\n  kr_resolve_server || {", "  kr_resolve_server || {"),
 "old_boot_ok": (("      [[ \"$pre\" == - || \"$boot\" != \"$pre\" ]] || continue\n", ""), ("( \"$pre\" == - || \"$KR_HS_BOOT\" != \"$pre\" ) && ", "")),
 "no_listener": ("if [[ -n \"$KR_NEWBOOT\" && \"$KR_SERVE\" == yes && \"$KR_LISTEN\" == 1 ]]; then", "if [[ -n \"$KR_NEWBOOT\" && \"$KR_SERVE\" == yes ]]; then"),
 "no_valuecheck": ("    if [[ \"$now_h\" == \"${prior[$k]}\" ]]; then", "    if false; then"),
 "redeploy_ignored": ("  if ! WEB_HOST_PRIVATE_IPS=\"$WEB_HOST_PRIVATE_IPS\" REDEPLOY_TIMEOUT_S=\"$KR_REDEPLOY_S\" bash \"$KR_TRACK\"; then", "  WEB_HOST_PRIVATE_IPS=\"$WEB_HOST_PRIVATE_IPS\" REDEPLOY_TIMEOUT_S=\"$KR_REDEPLOY_S\" bash \"$KR_TRACK\"; if [[ 1 == 2 ]]; then"),
 "drop_host_unique": ("  [[ \"$KR_SERVER_ID\" == \"$sid\" ]] || { kr_refuse host_not_unique", "  [[ 1 == 1 ]] || { kr_refuse host_not_unique"),
}
for name, spec in M.items():
    pairs = spec if isinstance(spec[0], tuple) else (spec,)
    mut, landed = src, True
    for old, new in pairs:
        if mut.count(old) != 1:
            print("NOLAND %s count=%d" % (name, mut.count(old))); landed = False; break
        mut = mut.replace(old, new)
    if not landed: continue
    d = os.path.join(out, name, "scripts"); os.makedirs(d, exist_ok=True)
    try: os.symlink(lib, os.path.join(d, "lib"))
    except FileExistsError: pass
    open(os.path.join(d, "inngest-key-rotate.sh"), "w").write(mut)
    print("LANDED %s" % name)
PYMUT
LANDED_N="$(find "$MUTDIR" -name inngest-key-rotate.sh | wc -l | tr -d ' ')"
[[ "$LANDED_N" == 23 ]] && ok "I0 all 23 script mutations landed exactly once (a mutation that matches nothing proves nothing)" || bad "I0 only $LANDED_N of 23 mutations landed"
mpath() { echo "$MUTDIR/$1/scripts/inngest-key-rotate.sh"; }
with_script() { local m; m="$(mpath "$1")"; shift; RUN_SCRIPT="$m"; "$@"; RUN_SCRIPT="$BODY"; }
for md in "$MUTDIR"/*/; do m="$(basename "$md")"; bash -n "$(mpath "$m")" 2>/dev/null || bad "I0b mutant $m does not parse (a syntax error would make every scenario 'fail closed' vacuously)"; done
ok "I0b every mutated copy still parses (so a RED/GREEN flip is the guard's doing, not a syntax error's)"
STREAMS_FILE="$TMP/mut-streams.txt"; : > "$STREAMS_FILE"

# ---- Guard 1 (plan gates) ----
fresh; with_script target_hcloud run_script apply1 "${APPLY_PLAN[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == plan_gate_refused && "$ALL" == *"hcloud_server.inngest update"* ]] && ok "I1 (G1 #1) adding hcloud_server.inngest to the target list only (not the table) turns the plan RED: the gate refuses and names it" || bad "I1 rc=$RC" "$OUT"
fresh; after_phase1; with_script drop_replace_b run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == plan_gate_refused && "$(nlog "$D/tf.log" '^apply')" == 0 ]] && ok "I2 (G1 #2) dropping the -replace for the app secrets makes Gate B see a no-op and refuse (count short), nothing applied" || bad "I2 rc=$RC" "$OUT"
fresh; printf '%s' '[{"address":"doppler_secret.inngest_redis_password_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_a"
with_script gate_true run_script apply1 "${APPLY_PLAN[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == plan_ok ]] && ok "I3 (G1 harness a) with the gate call replaced by true, the stray-update plan that F6 refuses is ACCEPTED (so F6 can see the gate)" || bad "I3 rc=$RC" "$OUT"
fresh; after_phase1; printf '%s' '[{"address":"doppler_secret.inngest_signing_key_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_b"
with_script gate_skipped run_script apply2 "${APPLY_2[@]}"
[[ "$(nlog "$D/tf.log" '^apply b')" == 1 ]] && ok "I4 without the gate a phase-2 plan that also changes a dedicated address IS applied (so F31 can see the gate)" || bad "I4 apply count $(nlog "$D/tf.log" '^apply')"

# ---- Guard 2 (no key material in a log) ----
fresh; with_script no_redirect run_script apply1 "${APPLY_PLAN[@]}"
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL"))" -ge 1 ]] && ok "I5 (G2 #1) removing the redirect on the Terraform call puts the sentinels in the output: the sentinel check goes RED" || bad "I5 no leak seen" "$OUT"
[[ "$(grep -v '^ *#' "$(mpath bare_show)" | grep -Eic '(^|[^_a-zA-Z-])terraform[[:space:]]+(plan|apply|show|state)' || true)" -ge 1 && "$(grep -v '^ *#' "$BODY" | grep -Eic '(^|[^_a-zA-Z-])terraform[[:space:]]+(plan|apply|show|state)' || true)" == 0 ]] && ok "I6 (G2 #2) a bare 'terraform show -no-color tfplan' is flagged by the static scan (and the real script has none)" || bad "I6"
[[ "$(grep -v '^ *#' "$(mpath second_tf)" | grep -Eo '(^|[^_a-zA-Z-])terraform[[:space:]]+[a-z"$]' | wc -l | tr -d ' ')" == 2 && "$TF_CALLS" == 1 ]] && ok "I7 (G2 #3) a second Terraform call site after the compliant one raises the call-site count from 1 to 2" || bad "I7"
fresh; with_script keep_tflog run_script apply1 "${APPLY_ROT[@]}" TF_LOG=DEBUG TF_LOG_PATH="$D/tf-debug.log"
[[ -e "$D/tf-debug.log" && "$(nlog "$D/tf.log" 'TFLOG=DEBUG')" -ge 1 ]] && ok "I8 (G2 #4) without the TF_LOG unset in kr_tf a TF_LOG=DEBUG run reaches terraform and writes a debug log (so F13 can see the unset)" || bad "I8 TF_LOG not leaked in mutant"
SC_BODY="$(printf 'refused: [id=%s] hex=%s %s upstream said Bearer abc123token' "Zq3Xk9Lm2Pw7Rt5Vb8Yn1" "$S_HEX" "$S_SIGN")"
scrub_with() { env -i PATH="$PATH" bash -c 'source "$1"; printf "%s" "$2" | kr_scrub' _ "$1" "$2"; }
SC_OUT="$(scrub_with "$BODY" "$SC_BODY")"
[[ "$SC_OUT" != *Zq3Xk9Lm2Pw7Rt5Vb8Yn1* && "$SC_OUT" != *"$S_HEX"* && "$SC_OUT" != *abc123token* && "$(kr_sentinel_hits <(printf '%s' "$SC_OUT"))" == 0 ]] && ok "I9 kr_scrub redacts an [id=...] group, a 64-hex run, a signkey- string and a Bearer value" || bad "I9 scrub leaked" "$SC_OUT"
[[ "$(scrub_with "$(mpath scrub_no_id)" "$SC_BODY")" == *Zq3Xk9Lm2Pw7Rt5Vb8Yn1* ]] && ok "I10 (G2 #6) dropping the [id=...] rule from kr_scrub lets a short key id through (an id below the generic 41-character rule is covered only by it): RED" || bad "I10 id rule not load-bearing"
SHA40="$(printf 'ab12%.0s' {1..10})"
SC2="$(scrub_with "$BODY" "sha $SHA40 see https://github.com/acme/repo/actions/runs/9001 ok")"
[[ "$SC2" == *"$SHA40"* && "$SC2" == *"actions/runs/9001"* ]] && ok "I11 (G2 harness b) a 40-hex git SHA and a run URL pass through kr_scrub unredacted" || bad "I11 over-redaction" "$SC2"
[[ "$(scrub_with "$BODY" 'x::error::y')" == "x: :error: :y" ]] && ok "I12 kr_scrub breaks '::' so a host or API body cannot smuggle a workflow command" || bad "I12 colon pairs"
[[ "$(scrub_with "$BODY" "$(printf 'a%.0s' {1..300})" | wc -c | tr -d ' ')" -le 200 ]] && ok "I13 kr_scrub caps its output at 200 characters" || bad "I13 cap"
# harness a: the sentinel checker is not vacuous
printf 'clean line\n' > "$TMP/clean.txt"; printf 'a leak %s here\n' "$S_SIGN" > "$TMP/seeded.txt"
[[ "$(kr_sentinel_hits "$TMP/clean.txt")" == 0 && "$(kr_sentinel_hits "$TMP/seeded.txt")" -ge 1 ]] && ok "I14 (G2 harness a) the sentinel checker reports 0 on a clean stream and >=1 on a stream seeded with a signkey string (replacing it with 'true' would blind F10/F26)" || bad "I14 checker vacuous"
check "I15 the generic shapes are checked as well as the sentinels: a seeded 64-hex run and a 43-char base64url run are hits" bash -c "printf '%s\n' '$S_HEX' > '$TMP/h1.txt'; printf '%s\n' '$S_B64' > '$TMP/h2.txt'; true"
[[ "$(kr_sentinel_hits "$TMP/h1.txt")" -ge 1 && "$(kr_sentinel_hits "$TMP/h2.txt")" -ge 1 ]] && ok "I15b ...and both are detected" || bad "I15b generic shapes undetected"
[[ "$(kr_sentinel_hits "$TMP/all-streams.txt")" == 0 ]] && ok "I16 (G2 #5) EVERY stream of EVERY scenario so far (guard, apply, reboot, verify, redeploy; $(wc -l < "$TMP/all-streams.txt") lines) holds no sentinel and no key-shaped string" || bad "I16 key-shaped string in the combined streams" "$(grep -nE "$S_HEX|$S_B64|signkey-|[0-9a-f]{64}" "$TMP/all-streams.txt" | head -3 | cut -c1-160)"

# ---- Guard 4 (the refusal ladder precedes every write) ----
fresh; printf 'pending:1700000000' > "$D/state/link"; with_script drop_link run_script guard "${G_ROTATE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I17 (G4 #2) without the link-flag rung a pending lease lets the guard say go=true (so D13 can see the rung)" || bad "I17"
fresh; with_script drop_attempt run_script guard "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I18 (G4 #4) without the run_attempt rung a re-run passes the guard (so D7 can see the rung)" || bad "I18"
fresh; with_script drop_quiet run_script guard "${G_ROTATE[@]}" INPUT_QUIET_WINDOW=false
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I19 (G4 #6a) without the quiet_window rung quiet_window=false passes" || bad "I19"
fresh; with_script drop_confirm run_script guard "${G_ROTATE[@]}" INPUT_CONFIRM=ROTATE-INNGEST-BOTH-2001-01-01
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I20 (G4 #6b) without the confirm rung a wrong-date confirm passes" || bad "I20"
fresh; printf '%s' '{"state":"OPEN","stateReason":null}' > "$D/state/soak.json"; with_script drop_soak run_script guard "${G_ROTATE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I21 (G4 #6c) without the soak rung an open tracker passes" || bad "I21"
fresh; hs_set_in "$D" 1 0 abcd1234 no $((NOW0 - 60)); with_script drop_serving run_script guard "${G_ROTATE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I22 without the pre-reboot SERVING rung a NOT SERVING host passes the rotate guard (so D28 can see it)" || bad "I22"
fresh; LR="$(latch_run "$(mpath drop_latch)")"
[[ "$(npost)" == 2 && "$LR" == *"r1=0 r2=0"* ]] && ok "I23 (G4 #3 / harness a) without the latch the second call issues a second POST: the POST-counter assertion of G13 turns RED (2 POSTs)" || bad "I23 posts=$(npost)" "$LR"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_deploy-inngest-image.yml_in_progress.json"; with_script drop_inflight_reboot run_script reboot "${RB[@]}"
[[ "$(npost)" == 1 ]] && ok "I24 without the in-flight refusal the reboot step POSTs although a deploy-inngest-image run is in flight (so G10 can see it)" || bad "I24 posts=$(npost)"
fresh; printf '%s' '{"servers":[{"id":9999,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$D/state/servers.json"; with_script drop_host_unique run_script reboot "${RB[@]}"
[[ "$(nlog "$D/post.log" '4242')" == 1 || "$(npost)" == 1 ]] && ok "I25 without the id re-check the reboot step POSTs to the id the guard supplied even though the lookup now names another (so G8 can see it)" || bad "I25"
fresh; hs_set_in "$D" 1 0 abcd1234 yes $((NOW0 + 100)); bs_set_in "$D" 1 "$OLDROW" "$(bs_row $((NOW0 + 100)) abcd1234 1)"; with_script old_boot_ok run_script verify "${VF[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok ]] && ok "I26 without the boot_id comparison the OLD boot's rows pass verify (so G19 can see it)" || bad "I26"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 + 200)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 150)) beef5678 0)"; with_script no_listener run_script verify "${VF[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok ]] && ok "I27 without the listener=1 conjunct a plaintext-only host passes verify (so G21 can see it)" || bad "I27"
fresh; touch "$D/state/apply_noeffect"; with_script no_valuecheck run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply1_ok ]] && ok "I28 without the new-differs-from-prior check an apply that changed nothing reports apply1_ok (so F21 can see it)" || bad "I28"
fresh; printf '1' > "$D/state/track_rc"; with_script redeploy_ignored run_script redeploy "${RD[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == rotate_ok ]] && ok "I29 if the track.sh verdict is ignored a failed or degraded fleet redeploy is reported green (so H8 can see the guard)" || bad "I29"
# the workflow graph
wf_mut() { # name python-statement: writes $TMP/wfm-<name>.yml
  python3 - "$WF" "$TMP/wfm-$1.yml" "$2" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
jobs = d["jobs"]
exec(sys.argv[3])
yaml.safe_dump(d, open(sys.argv[2], "w"))
PY
}
wf_mut noguard 'jobs["reboot"]["needs"] = ["apply1"]'
[[ "$(graph_violations "$TMP/wfm-noguard.yml")" == *"reboot:guard-not-a-direct-need"* ]] && ok "I30 (G4 #1) removing guard from the reboot job's needs is flagged by the graph check" || bad "I30" "$(graph_violations "$TMP/wfm-noguard.yml")"
wf_mut swap 'jobs["reboot"]["needs"] = ["guard"]; jobs["apply2"]["needs"] = ["guard", "apply1"]'
[[ "$(graph_violations "$TMP/wfm-swap.yml")" == *"reboot:before-apply1"* && "$(graph_violations "$TMP/wfm-swap.yml")" == *"apply2:before-reboot"* ]] && ok "I31 (G4 #5) letting apply2 run without the reboot (redeploy before SERVING) is flagged" || bad "I31" "$(graph_violations "$TMP/wfm-swap.yml")"
wf_mut redeploy 'jobs["redeploy"]["needs"] = ["guard", "apply1", "reboot"]'
[[ "$(graph_violations "$TMP/wfm-redeploy.yml")" == *"redeploy:before-apply2"* ]] && ok "I32 a redeploy that does not wait for apply2 is flagged" || bad "I32"
wf_mut nogo 'jobs["apply2"]["if"] = jobs["apply2"]["if"].replace("needs.guard.outputs.go == '"'"'true'"'"' && ", "")'
[[ "$(graph_violations "$TMP/wfm-nogo.yml")" == *"apply2:if-not-on-go"* ]] && ok "I33 an apply2 whose condition no longer reads the guard's go output is flagged" || bad "I33"
wf_mut noreboot 'jobs["apply2"]["if"] = jobs["apply2"]["if"].replace(" && needs.reboot.result == '"'"'success'"'"'", "")'
[[ "$(graph_violations "$TMP/wfm-noreboot.yml")" == *"apply2:if-not-on-reboot-success"* ]] && ok "I34 an apply2 whose condition no longer requires the reboot job to have SUCCEEDED is flagged" || bad "I34"
wf_mut dispatch 'jobs["redeploy"]["if"] = jobs["redeploy"]["if"].replace("github.event_name == '"'"'workflow_dispatch'"'"' && ", "")'
[[ "$(graph_violations "$TMP/wfm-dispatch.yml")" == *"redeploy:if-not-dispatch"* ]] && ok "I35 a write job that lost its workflow_dispatch gate (the push trigger could then run it) is flagged" || bad "I35"
# harness (b) must-PASS: the real workflow is clean, and so is the plan re-run
[[ -z "$(graph_violations "$WF")" ]] && ok "I36 (G4 harness b) the graph check reports nothing on the real workflow (it is not a checker that flags everything)" || bad "I36"
# the harness rows for the static scans: they must flag the mutants and pass the original
check "I37 the static scans are not vacuous: the original script has 0 bare terraform verbs and 1 call site, the mutants 1+ and 2" bash -c "[ '$TF_CALLS' = 1 ]"
check "I38 the second POST site is visible to the static check (B12): the mutant has 2, the original 1" bash -c "[ \"\$(grep -v '^ *#' '$(mpath second_post_site)' | grep -c 'kr_hz POST')\" = 2 ] && [ \"\$(grep -v '^ *#' '$BODY' | grep -c 'kr_hz POST')\" = 1 ]"
STREAMS_FILE=""

printf '\n=== K. cross-file drift ===\n'
GUARD_OUTS="$(yq 'sorted(jobs["guard"]["outputs"].keys())' | tr -d "[]',")"
SCRIPT_OUTS="$(sed -n '/^kr_cmd_guard()/,/^kr_chk_inflight_wrap/p' "$BODY" | grep -Eo 'kr_out [a-z_0-9]+' | awk '{print $2}' | sort -u | tr '\n' ' ')"
[[ "$(tr ' ' '\n' <<<"$GUARD_OUTS" | grep . | sort | tr '\n' ' ')" == "$SCRIPT_OUTS" ]] && ok "K1 the guard job's declared outputs are exactly the outputs the guard subcommand writes ($SCRIPT_OUTS)" || bad "K1 guard outputs drift" "workflow: $GUARD_OUTS script: $SCRIPT_OUTS"
WF_EFF="$(grep -Eo 'EFF_[A-Z_]+' "$WF" | sort -u | tr '\n' ' ')"
SC_EFF="$(grep -Eo 'EFF_[A-Z_]+' "$BODY" | sort -u | tr '\n' ' ')"
[[ "$WF_EFF" == "$SC_EFF" ]] && ok "K2 every EFF_* variable the workflow binds is one the script reads, and vice versa" || bad "K2 EFF_* drift" "workflow: $WF_EFF script: $SC_EFF"
WF_IN="$(grep -Eo 'INPUT_[A-Z_]+' "$WF" | sort -u | tr '\n' ' ')"
SC_IN="$(grep -Eo 'INPUT_[A-Z_]+' "$BODY" | sort -u | tr '\n' ' ')"
[[ "$WF_IN" == "$SC_IN" ]] && ok "K3 every INPUT_* variable the workflow binds is one the script reads, and vice versa" || bad "K3 INPUT_* drift" "workflow: $WF_IN script: $SC_IN"
RN="$(yq 'd["run-name"]')"; TITLE="$(sed -e 's/\${{ inputs.mode }}/rotate/' -e 's/\${{ inputs.keys }}/both/' <<<"$RN")"
RE="$(grep -Eo '\^inngest-key-rotate \(rotate\|converge\) \(signing\|event\|both\)\$' "$BODY" | head -1)"
[[ -n "$RE" && "$TITLE" =~ ^inngest-key-rotate\ (rotate|converge)\ (signing|event|both)$ ]] && ok "K4 the run-name renders as '$TITLE', which the converge derivation's title pattern (and the link flip's off-after-rotation check) matches" || bad "K4 run-name vs derivation pattern" "title=$TITLE re=$RE"
[[ "$(yq 'sorted(set(__import__("re").findall(r"needs\.guard\.outputs\.([a-z_0-9]+)", open(sys.argv[1]).read())))')" == "['boot_pre', 'go', 'keys', 'mode', 'reboot_post', 'rotated_at', 'run_apply1', 'run_apply2', 'run_reboot', 'run_redeploy', 'server_id']" ]] && ok "K5 every guard output the jobs read is declared by the guard job" || bad "K5 guard outputs read"

printf '\n=== J. final accounting ===\n'
[[ "$(kr_sentinel_hits "$TMP/all-streams.txt")" == 0 ]] && ok "J1 (G2 #5, final) after the whole suite, every captured stream of every non-mutant scenario ($(wc -l < "$TMP/all-streams.txt") lines) is free of key-shaped strings" || bad "J1 final sentinel"
[[ -z "$(ls -d "$TMP"/s*/rt/inngest-key-rotate.* 2>/dev/null)" ]] && ok "J2 no scenario left its private temp dir (and so no plan JSON) behind" || bad "J2 leftover temp dir"

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
FLOOR=267
if (( PASS + FAIL < FLOOR )); then
  printf 'FAIL ANTI-VACUITY: %d assertions ran, floor is %d\n' $((PASS + FAIL)) "$FLOOR" >&2
  exit 1
fi
if (( PASS + FAIL > FLOOR )); then
  printf 'FAIL FLOOR DRIFT: %d assertions ran but FLOOR is %d - set FLOOR=%d (the floor is the real count)\n' $((PASS + FAIL)) "$FLOOR" $((PASS + FAIL)) >&2
  exit 1
fi
exit $(( FAIL > 0 ))
