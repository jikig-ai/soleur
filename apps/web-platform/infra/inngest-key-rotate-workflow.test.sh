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
#   W. THE WORKFLOW AS A PROGRAM: every job's `if:` is EVALUATED per mode and per failure scenario with a real expression evaluator
#      (the job matrix is asserted as a table, so a swapped output or an `always() ||` cannot hide in a substring), the permissions,
#      checkout credentials, per-step env and the two `env -i` allow-lists are asserted as EXACT closed sets, the POST/admit/verify
#      lines are EXECUTED against a stub, and each rule has a mutation row that reds it. The doppler and gh fakes are strict about
#      their argv (project, config, issue number, workflow): an unmodelled call exits 64 and the refusal log must stay empty.
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

BUD="$(env -i PATH="$PATH" bash -c 'source "$1"; echo "$KR_GUARD_S $KR_GUARD_JOB_S $KR_APPLY_STEP_S $KR_APPLY_JOB_S $KR_REBOOT_STEP_S $KR_VERIFY_STEP_S $KR_REBOOT_JOB_S $KR_REDEPLOY_S $KR_REDEPLOY_JOB_S $KR_BOOT_WAIT_S $KR_VERIFY_S $KR_PIPELINE_CEILING_S $KR_REDEPLOY_STEP_S $KR_ADMIT_S $KR_NOTIFY_S $KR_NOTIFY_JOB_S $KR_STEP_SLACK_S $KR_FINAL_MARGIN_S $KR_CONVERGE_MAX_AGE_S"' _ "$BODY")"
read -r B_GUARD B_GUARD_JOB B_APPLY_STEP B_APPLY_JOB B_REBOOT_STEP B_VERIFY_STEP B_REBOOT_JOB B_REDEPLOY B_REDEPLOY_JOB B_BOOT_WAIT B_VERIFY B_CEILING B_REDEPLOY_STEP B_ADMIT B_NOTIFY B_NOTIFY_JOB B_SLACK B_MARGIN B_MAXAGE <<<"$BUD"
mins() { echo $(( ($1 + 59) / 60 )); }

printf '\n=== A. static: the workflow (parsed YAML) ===\n'
[[ "$(yq 'sorted(k for k in on.keys())')" == "['push', 'workflow_dispatch']" ]] && ok "A1 triggers are exactly workflow_dispatch plus a registration push" || bad "A1 triggers: $(yq 'sorted(on.keys())')"
[[ "$(yq 'on["push"]["paths"]')" == "['.github/workflows/inngest-key-rotate.yml']" && "$(yq 'on["push"]["branches"]')" == "['main']" ]] && ok "A2 the push trigger is main-only and scoped to this file alone (it only registers the workflow)" || bad "A2 push scope"
[[ "$(yq 'sorted(j for j in jobs if "if" not in jobs[j])')" == "[]" ]] && ok "A3 every job carries an if: (its truth per mode and per failure scenario is EVALUATED in section W, not matched as text)" || bad "A3 job without if"
[[ "$(yq 'sorted(jobs.keys())')" == "['apply1', 'apply2', 'guard', 'notify', 'reboot', 'redeploy']" ]] && ok "A4 the jobs are exactly guard, apply1, reboot, apply2, redeploy, notify" || bad "A4 jobs: $(yq 'sorted(jobs.keys())')"
[[ "$(yq 'sorted(on["workflow_dispatch"]["inputs"].keys())')" == "['confirm', 'keys', 'mode', 'quiet_window', 'reason', 'rotated_at']" ]] && ok "A5 the inputs are mode, keys, confirm, reason, rotated_at, quiet_window" || bad "A5 inputs"
[[ "$(yq '[("default" in on["workflow_dispatch"]["inputs"][k], on["workflow_dispatch"]["inputs"][k]["required"]) for k in ("mode","keys")]')" == "[(False, True), (False, True)]" ]] && ok "A6 mode and keys are required with NO default (the owner's go names them)" || bad "A6 mode/keys defaults"
[[ "$(yq 'on["workflow_dispatch"]["inputs"]["mode"]["options"]')" == "['plan', 'rotate', 'converge']" && "$(yq 'on["workflow_dispatch"]["inputs"]["keys"]["options"]')" == "['signing', 'event', 'both']" ]] && ok "A7 mode is {plan, rotate, converge} (plan first) and keys is {signing, event, both}" || bad "A7 options"
[[ "$(yq 'on["workflow_dispatch"]["inputs"]["quiet_window"]["type"] + str(on["workflow_dispatch"]["inputs"]["quiet_window"]["default"])')" == "booleanFalse" ]] && ok "A8 quiet_window is a boolean that defaults to false" || bad "A8 quiet_window"
[[ "$(yq 'd["run-name"]')" == 'inngest-key-rotate ${{ inputs.mode }} ${{ inputs.keys }}' ]] && ok "A9 run-name carries the mode and keys (the link-flip guard and converge derive from it)" || bad "A9 run-name: $(yq 'd["run-name"]')"
[[ "$(yq 'd["concurrency"]["group"] + "|" + str(d["concurrency"]["cancel-in-progress"])')" == "inngest-key-rotate|False" ]] && ok "A10 workflow-level group inngest-key-rotate, never cancel-in-progress" || bad "A10 concurrency"
[[ "$(yq 'str(jobs["apply1"]["concurrency"]["group"]) + "|" + str(jobs["apply2"]["concurrency"]["group"]) + "|" + str(jobs["reboot"]["concurrency"]["group"])')" == "terraform-apply-web-platform-host|terraform-apply-web-platform-host|deploy-inngest-restart" ]] && ok "A11 the Terraform jobs hold terraform-apply-web-platform-host and the reboot job holds the shared deploy-inngest-restart mutex" || bad "A11 job groups"
[[ "$(yq 'all(j.get("concurrency", {}).get("cancel-in-progress") in (None, False) for j in jobs.values())')" == True && "$(yq '"concurrency" in jobs["notify"]')" == False ]] && ok "A12 no job group cancels in progress, and the notify job has NO concurrency group (it must never be the replaced one)" || bad "A12 job cancel-in-progress / notify group"
[[ "$(yq 'd["permissions"]')" == "{'contents': 'read'}" ]] && ok "A13 workflow permissions are contents:read; each job widens only what it needs" || bad "A13 permissions"
[[ "$(yq '[jobs[j]["permissions"].get("issues") for j in ("guard","apply1","reboot","apply2","redeploy","notify")]')" == "['read', 'write', 'write', 'write', 'write', 'write']" ]] && ok "A14 only the write jobs and notify hold issues:write (the guard only reads); the exact permission sets are asserted in section W" || bad "A14 issues scope"
[[ "$(yq 'all(len(s["uses"].split("@")[1].split(" ")[0]) == 40 for j in jobs.values() for s in j["steps"] if "uses" in s and not s["uses"].startswith("./"))')" == True ]] && ok "A15 every remote action is pinned to a 40-hex SHA" || bad "A15 unpinned action"
[[ "$(yq 'sorted(set(s["uses"].split("@")[0] for j in jobs.values() for s in j["steps"] if "uses" in s))')" == "['./.github/actions/infra-credentials', 'DopplerHQ/cli-action', 'actions/checkout', 'hashicorp/setup-terraform']" ]] && ok "A16 the action set is checkout, setup-terraform, the pinned Doppler CLI action and the credential loader" || bad "A16 action set: $(yq 'sorted(set(s["uses"].split("@")[0] for j in jobs.values() for s in j["steps"] if "uses" in s))')"
[[ "$(yq 'any(__import__("re").search(r"\$\{\{", s.get("run","")) for j in jobs.values() for s in j["steps"])')" == False ]] && ok "A17 no expression of any kind (inputs, secrets, needs, github, steps, env) is interpolated into a run: body, spaced or not: everything arrives through env:" || bad "A17 expression in run:"
[[ "$(yq 'any("${{" in str(j.get("if","")) and "inputs." in str(j.get("if","")) for j in jobs.values())')" == False ]] && ok "A18 no job condition reads a dispatch input (conditions read the guard's validated outputs)" || bad "A18 input in if:"
[[ "$(yq '[s.get("run","").strip() for s in jobs["guard"]["steps"] if s.get("id") == "guard"]')" == "['bash scripts/inngest-key-rotate.sh guard']" ]] && ok "A19 the guard step is exactly: bash scripts/inngest-key-rotate.sh guard" || bad "A19 guard run"
[[ "$(yq '[s["run"].strip() for s in jobs["apply1"]["steps"] if "run" in s]')" == "['bash scripts/inngest-key-rotate.sh apply1']" && "$(yq '[s["run"].strip() for s in jobs["apply2"]["steps"] if "run" in s]')" == "['bash scripts/inngest-key-rotate.sh apply2']" && "$(yq '[s["run"].strip() for s in jobs["redeploy"]["steps"] if "run" in s]')" == "['bash scripts/inngest-key-rotate.sh redeploy']" ]] && ok "A20 apply1, apply2 and redeploy each run exactly one script subcommand and nothing else" || bad "A20 run bodies"
check "A21 no terraform, doppler, curl or gh command in the workflow text (the script is the only caller), including at the end of a line" bash -c "! grep -Eq '(^|[^-a-zA-Z_/])(terraform|doppler|curl|gh)( |\$)' < <(grep -v '^ *#' '$WF' | grep -v 'description:')"
check "A22 nothing is uploaded (no upload-artifact or cache step: a public repo's artifacts are readable by any account)" bash -c "! grep -Eq 'upload-artifact|actions/cache|step-summary-upload' '$WF'"
check "A23 the workflow never names the standalone restart workflow or the restart verb (that lever cannot reach 10.0.1.40)" bash -c "! grep -Eiq 'restart-inngest-server|restart inngest' '$WF' '$BODY'"
check "A24 no test seam (KR_*) is set anywhere in the workflow" bash -c "! grep -Eq 'KR_(SLEEP|NOW|HZ_BASE|TRACK|HOST_STATE|BS_QUERY|INFRA_DIR)' '$WF'"
[[ "$(yq '[jobs[j].get("environment") for j in ("guard","apply1","reboot","apply2","redeploy","notify")]')" == "[None, 'infra-privileged', 'infra-privileged', 'infra-privileged', None, None]" ]] && ok "A25 apply1, reboot and apply2 run in the Tier-B environment infra-privileged; the guard, the redeploy and notify hold no Tier-B credential" || bad "A25 environments"
[[ "$(yq '[sum(1 for s in jobs[j]["steps"] if s.get("uses","").startswith("./.github/actions/infra-credentials")) for j in ("guard","apply1","reboot","apply2","redeploy","notify")]')" == "[0, 1, 1, 1, 0, 0]" ]] && ok "A26 the credential loader runs in exactly the three Tier-B jobs (each declares the Tier-B environment, census G1j)" || bad "A26 loader"
SECRETS_OF() { yq "sorted(set(__import__('re').findall(r'secrets\\.([A-Z0-9_]+)', __import__('json').dumps(jobs['$1']))))"; }
[[ "$(SECRETS_OF guard)" == "['BETTERSTACK_QUERY_HOST', 'BETTERSTACK_QUERY_PASSWORD', 'BETTERSTACK_QUERY_USERNAME', 'DOPPLER_TOKEN']" ]] && ok "A27 guard credentials: the Tier-A Doppler token and the Better Stack read pair only (the Hetzner token it uses is READ-ONLY, fetched by the script)" || bad "A27 guard secrets: $(SECRETS_OF guard)"
[[ "$(SECRETS_OF apply1)" == "['DOPPLER_TOKEN', 'DOPPLER_TOKEN_INFRA_PRIVILEGED']" && "$(SECRETS_OF apply2)" == "['DOPPLER_TOKEN', 'DOPPLER_TOKEN_INFRA_PRIVILEGED']" ]] && ok "A28 apply1 and apply2 hold the Tier-B loader token and the Tier-A Doppler token only (no webhook or Better Stack credential)" || bad "A28 apply secrets"
[[ "$(SECRETS_OF reboot)" == "['BETTERSTACK_QUERY_HOST', 'BETTERSTACK_QUERY_PASSWORD', 'BETTERSTACK_QUERY_USERNAME', 'DOPPLER_TOKEN', 'DOPPLER_TOKEN_INFRA_PRIVILEGED']" ]] && ok "A29 reboot holds the loader tokens and the Better Stack pair (the write token arrives only through the loader's HCLOUD_TOKEN)" || bad "A29 reboot secrets: $(SECRETS_OF reboot)"
[[ "$(SECRETS_OF redeploy)" == "['CF_ACCESS_CLIENT_ID', 'CF_ACCESS_CLIENT_SECRET', 'WEBHOOK_DEPLOY_SECRET']" && "$(SECRETS_OF notify)" == "[]" ]] && ok "A30 redeploy holds the deploy webhook trio only; notify holds no secret" || bad "A30 redeploy/notify secrets: $(SECRETS_OF redeploy) $(SECRETS_OF notify)"
[[ "$(yq 'len(__import__("re").findall(r"secrets(?!\.[A-Z][A-Z0-9_]*\b)", __import__("json").dumps(d)))')" == 0 ]] && ok "A30b every use of the secrets context is the dotted form secrets.NAME: no secrets['X'], no toJSON(secrets), no secrets as a value (the A27-A30 scans read the dotted form only)" || bad "A30b non-dotted secrets access"
[[ "$(yq 'jobs["redeploy"]["env"]["WEB_HOST_PRIVATE_IPS"]')" == "10.0.1.10,10.0.1.11" ]] && ok "A31 the redeploy pins the fan-out roster literal WEB_HOST_PRIVATE_IPS (web-hosts-fanout-parity.test.sh compares it with var.web_hosts)" || bad "A31 roster"

# The needs graph (Guard 4), STRUCTURE only: what each job's if: says is EVALUATED per mode in section W (a substring match on the
# condition passes `always() || (...)` and a swapped output). graph_violations <workflow-file>: space-separated violated properties.
graph_violations() {
  python3 - "$1" <<'PY'
import sys, yaml
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
if "apply1" not in closure("reboot"): bad.append("reboot:before-apply1")
if "reboot" not in closure("apply2"): bad.append("apply2:before-reboot")
if "apply2" not in closure("redeploy") or "reboot" not in closure("redeploy"): bad.append("redeploy:before-apply2")
if sorted(needs("notify")) != ["apply1", "apply2", "guard", "reboot", "redeploy"]: bad.append("notify:needs")
print(" ".join(bad))
PY
}
[[ -z "$(graph_violations "$WF")" ]] && ok "A32 every write job needs the guard (directly and transitively); reboot needs apply1, apply2 needs reboot, redeploy needs apply2 and reboot; notify needs every job (the conditions are evaluated in section W)" || bad "A32 graph" "$(graph_violations "$WF")"

# Timeouts derive from the script's BUDGET TABLE (rounded up to minutes).
[[ "$(yq 'jobs["guard"]["timeout-minutes"]')" == "$(mins "$B_GUARD_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["guard"]["steps"] if s.get("id") == "guard")')" == "$(mins "$B_GUARD")" ]] && ok "A33 guard: job $(mins "$B_GUARD_JOB") min and step $(mins "$B_GUARD") min equal the budget table (KR_GUARD_JOB_S, KR_GUARD_S)" || bad "A33 guard timeouts"
[[ "$(yq 'jobs["apply1"]["timeout-minutes"]')" == "$(mins "$B_APPLY_JOB")" && "$(yq 'jobs["apply2"]["timeout-minutes"]')" == "$(mins "$B_APPLY_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["apply1"]["steps"] if "run" in s)')" == "$(mins "$B_APPLY_STEP")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["apply2"]["steps"] if "run" in s)')" == "$(mins "$B_APPLY_STEP")" ]] && ok "A34 apply1/apply2: job $(mins "$B_APPLY_JOB") min and step $(mins "$B_APPLY_STEP") min equal KR_APPLY_JOB_S / KR_APPLY_STEP_S" || bad "A34 apply timeouts"
[[ "$(yq 'jobs["reboot"]["timeout-minutes"]')" == "$(mins "$B_REBOOT_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["reboot"]["steps"] if s.get("id") == "admit")')" == "$(mins "$B_ADMIT")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["reboot"]["steps"] if s.get("id") == "post")')" == "$(mins "$B_REBOOT_STEP")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')" == "$(mins "$B_VERIFY_STEP")" ]] && ok "A35 reboot: job $(mins "$B_REBOOT_JOB") min, admit step $(mins "$B_ADMIT") min, POST step $(mins "$B_REBOOT_STEP") min, verify step $(mins "$B_VERIFY_STEP") min equal the budget table" || bad "A35 reboot timeouts"
[[ "$(yq 'jobs["redeploy"]["timeout-minutes"]')" == "$(mins "$B_REDEPLOY_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["redeploy"]["steps"] if "run" in s)')" == "$(mins "$B_REDEPLOY_STEP")" && "$B_REDEPLOY_STEP" == $((B_REDEPLOY + B_SLACK)) && "$B_REDEPLOY" == "$B_CEILING" && "$B_CEILING" == 4800 ]] && ok "A36 redeploy: the budget is the pipeline's 4800 s ceiling (ci-deploy-wrapper.sh), the STEP timeout is the ceiling plus the step slack ($(mins "$B_REDEPLOY_STEP") min: the Actions step never dies at the instant track.sh gives up) and the job ceiling is derived from the step" || bad "A36 redeploy timeouts"
[[ "$(yq 'jobs["notify"]["timeout-minutes"]')" == "$(mins "$B_NOTIFY_JOB")" && "$(yq 'next(s["timeout-minutes"] for s in jobs["notify"]["steps"] if "run" in s)')" == "$(mins "$B_NOTIFY")" ]] && ok "A36b notify: job $(mins "$B_NOTIFY_JOB") min and step $(mins "$B_NOTIFY") min equal KR_NOTIFY_JOB_S / KR_NOTIFY_S" || bad "A36b notify timeouts"
check "A37 the pipeline ceiling the budget quotes (KR_PIPELINE_CEILING_S=$B_CEILING, which KR_REDEPLOY_S is wired to) is the wrapper's real kill time" grep -Eq "timeout --signal=TERM --kill-after=[0-9]+s ${B_CEILING}s " "$REPO_ROOT/apps/web-platform/infra/ci-deploy-wrapper.sh"
check "A37b KR_REDEPLOY_S is wired to KR_PIPELINE_CEILING_S (one value, not two literals)" grep -Fxq 'KR_REDEPLOY_S=$KR_PIPELINE_CEILING_S' "$BODY"
[[ "$B_BOOT_WAIT" == 600 && "$B_VERIFY" == 900 && "$B_BOOT_WAIT" -lt "$B_VERIFY" ]] && ok "A38 the new-boot wait is 10 minutes and sits inside the 15-minute verify window" || bad "A38 wait budget $B_BOOT_WAIT/$B_VERIFY"
[[ "$B_MAXAGE" == 86400 && "$B_MARGIN" -lt "$B_SLACK" && $((B_VERIFY_STEP - B_MARGIN)) -gt "$B_VERIFY" ]] && ok "A38b the converge source bound is 24 h (86400 s, the boundary D52 tests) and the verify loop keeps a ${B_MARGIN}s final margin inside the step slack, leaving the whole 15-minute window" || bad "A38b budget: maxage=$B_MAXAGE margin=$B_MARGIN slack=$B_SLACK"
[[ "$(yq 'all(isinstance(s.get("timeout-minutes"), int) for j in jobs.values() for s in j["steps"] if "run" in s or s.get("uses","").startswith("./"))')" == True ]] && ok "A39 every run and loader step carries its own timeout-minutes" || bad "A39 step timeout"

# The reboot job: env -i allow-list on every step after the loader; the write token in the POST step only; ONE POST.
RB_POST_RUN="$(yq 'next(s["run"] for s in jobs["reboot"]["steps"] if s.get("id") == "post")')"
RB_VERIFY_RUN="$(yq 'next(s["run"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')"
RB_ADMIT_RUN="$(yq 'next(s["run"] for s in jobs["reboot"]["steps"] if s.get("id") == "admit")')"
[[ "$RB_POST_RUN" == *"exec env -i "* && "$RB_VERIFY_RUN" == *"exec env -i "* && "$RB_ADMIT_RUN" == *"exec env -i "* ]] && ok "A40 all three reboot-job run steps (admit, POST, verify) start with exec env -i (the loader's other Tier-B values never reach a child)" || bad "A40 env -i"
[[ "$RB_POST_RUN" == *'HCLOUD_TOKEN="$HCLOUD_TOKEN"'* && "$RB_VERIFY_RUN" != *HCLOUD_TOKEN* && "$RB_ADMIT_RUN" != *HCLOUD_TOKEN* && "$RB_POST_RUN" != *BETTERSTACK* ]] && ok "A41 the Hetzner write token is in the POST step's allow-list only; the admit and verify steps have none and the POST step has no Better Stack pair" || bad "A41 token binding"
[[ "$RB_POST_RUN" != *DOPPLER_TOKEN* && "$RB_VERIFY_RUN" != *DOPPLER_TOKEN* && "$RB_POST_RUN" != *AWS_* && "$RB_VERIFY_RUN" != *AWS_* && "$RB_ADMIT_RUN" != *AWS_* && "$RB_ADMIT_RUN" != *DOPPLER_TOKEN_TF* ]] && ok "A42 neither the POST nor the verify step allow-lists a Doppler token or the Terraform backend pair; the admit step allow-lists the Tier-A DOPPLER_TOKEN only (never DOPPLER_TOKEN_TF or AWS_*)" || bad "A42 allow-list"
[[ "$(yq 'sum(1 for s in jobs["reboot"]["steps"] if "run" in s and "reboot" in s["run"].split("inngest-key-rotate.sh")[-1])')" == 1 ]] && ok "A43 exactly one reboot-job step invokes the POST subcommand" || bad "A43 post step count"
[[ "$(yq 'jobs["reboot"]["steps"][-1].get("id")')" == "verify" && "$(yq '[s.get("id") for s in jobs["reboot"]["steps"] if s.get("id")]')" == "['admit', 'post', 'verify']" && "$(yq 'next(s.get("if") for s in jobs["reboot"]["steps"] if s.get("id") == "post")')" == "\${{ steps.admit.outputs.reboot_post == 'true' }}" && "$(yq 'sum(1 for s in jobs["reboot"]["steps"] if s.get("id") in ("admit", "verify") and "if" in s)')" == 0 ]] && ok "A44 the order is loader, admit, POST, verify; the POST runs only when the ADMIT step (not the guard) says a POST is needed; admit and verify carry no condition of their own, so a failed admit skips the POST and the verify" || bad "A44 post/verify order"
[[ "$(yq 'next(s["env"]["EFF_POST_EPOCH"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')" == '${{ steps.post.outputs.post_epoch }}' && "$(yq 'next(s["env"]["EFF_BOOT_PRE"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')" == '${{ steps.admit.outputs.boot_pre }}' && "$(yq 'next(s["env"]["EFF_VERIFY_AFTER"] for s in jobs["reboot"]["steps"] if s.get("id") == "verify")')" == '${{ steps.admit.outputs.verify_after }}' ]] && ok "A45 the verify step reads the POST time from the POST step and boot_pre / verify_after from the ADMIT step (a guard-time boot_pre is stale after an approval wait)" || bad "A45 verify inputs"

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
check "B7 kr_tf sends BOTH streams to files and unsets TF_LOG, TF_LOG_PATH, TF_LOG_CORE and TF_LOG_PROVIDER" bash -c "grep -q 'env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER' < <(grep -A8 '^kr_tf()' '$BODY') && grep -q '> \"\$KR_TMP/tf-\${name}.out\" 2> \"\$KR_TMP/tf-\${name}.err\"' < <(grep -A8 '^kr_tf()' '$BODY')"
check "B8 kr_tf runs doppler run --preserve-env (the loader's Tier-B values win) with --name-transformer tf-var" bash -c "grep -q 'doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var' < <(grep -A10 '^kr_tf()' '$BODY')"
check "B9 no Terraform stream is ever printed: no cat/head/tail/tee/echo of a tf-*.out or tf-*.err file" bash -c "! grep -Eq '(cat|head|tail|tee|printf|echo|sed|grep|less|more)[^|;]*tf-[a-z0-9\${}_-]*\\.(out|err)' < <(grep -v '^ *#' '$BODY' | grep -v 'kr_tf()' | grep -v 'show-' )"
check "B10 the plan JSON is read only by jq (kr_gate) and never by a shell redirect into the log" bash -c "grep -qx '[1-9]' < <(grep -c 'tf-show-' '$BODY')"
# secret_reads_of <file>: every `doppler secrets get|download` line that is NOT one of the three exact call forms (the link flag, the
# read-only Hetzner token, and the copy read whose ONLY consumer is `| sha256sum | cut -c1-64`). A line that merely mentions sha256sum
# (e.g. `... | tee /dev/stderr | sha256sum`) is not the exact form and is reported.
secret_reads_of() {
  grep -v '^ *#' "$1" | grep -E 'doppler secrets (get|download)' \
    | grep -Fv 'doppler secrets get INNGEST_LINK_TLS --plain -p soleur -c prd_terraform 2>/dev/null)" || v="__unreadable__"' \
    | grep -Fv 'doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform 2>/dev/null)" || t=""' \
    | grep -Fv 'doppler secrets get "$name" --plain -p "$proj" -c "$KR_COPY_CONFIG" 2>/dev/null | sha256sum | cut -c1-64)" || return 1' || true
}
SECRET_READS="$(secret_reads_of "$BODY")"
printf '%s\n' '  h="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" doppler secrets get "$name" --plain -p "$proj" -c "$KR_COPY_CONFIG" 2>/dev/null | tee /dev/stderr | sha256sum | cut -c1-64)" || return 1' > "$TMP/secretread-tee.sh"
[[ -z "$SECRET_READS" && "$(grep -v '^ *#' "$BODY" | grep -cE 'doppler secrets get')" == 3 ]] && ok "B11 every doppler secrets get is one of the three EXACT forms (the link flag, the read-only Hetzner token, the copy read whose only consumer is | sha256sum | cut -c1-64) (the names listing reads names, never a value); no key value is ever captured" || bad "B11 unexpected secret read" "$SECRET_READS"
[[ -n "$(secret_reads_of "$TMP/secretread-tee.sh")" ]] && ok "B11b (harness) a secret read piped through tee /dev/stderr before sha256sum IS flagged (a line that merely contains sha256sum is not exempt)" || bad "B11b tee line not flagged"
BC_N="$(grep -v '^ *#' "$BODY" | grep -c 'bc_curl inngest-key-rotate')"
HZ_VERBS="$(grep -v '^ *#' "$BODY" | grep -Eo '\bkr_hz [A-Z]+' | awk '{print $2}' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
[[ "$BC_N" == 1 && "$(grep -v '^ *#' "$BODY" | grep -c -- '-X ')" == 1 && "$(grep -v '^ *#' "$BODY" | grep -c -- '-X "$method"')" == 1 && "$HZ_VERBS" == " 3 GET; 1 POST;" ]] && ok "B12 exactly ONE bc_curl in the script (kr_hz, with a variable method), exactly one -X, and the Hetzner callers use GET ($HZ_VERBS) plus exactly ONE POST; no DELETE, PUT or PATCH exists" || bad "B12 hetzner request sites: bc_curl=$BC_N verbs=$HZ_VERBS"
check "B12b the one POST is inside kr_reboot_post, whose only caller is the reboot subcommand" bash -c "grep -q 'kr_hz POST' < <(grep -A8 '^kr_reboot_post()' '$BODY')"
check "B13 the reboot POST latch is set before the request" bash -c "grep -q . < <(grep -n 'KR_POSTED=1' < <(grep -A8 '^kr_reboot_post()' '$BODY') | head -1) && awk '/^kr_reboot_post\\(\\)/{f=1} f&&/KR_POSTED=1/{a=NR} f&&/kr_hz POST/{b=NR} END{exit !(a<b)}' '$BODY'"
check "B14 no hard reset: no reset/poweroff/poweron/power_off action path is requested" bash -c "! grep -Eiq 'actions/(reset|poweroff|poweron|power_off|rebuild|shutdown)' < <(grep -v '^ *#' '$BODY')"
check "B15 every Hetzner request goes through bearer-curl.sh (bc_curl); no curl command with a token argument" bash -c "grep -q 'bc_curl inngest-key-rotate' '$BODY' && [ \"\$(grep -v '^ *#' '$BODY' | grep -c ' curl ')\" = 0 ]"
# The gate table's three construction sites.
[[ "$(code_only "$BODY" | grep -c -- "-target=")" == 1 && "$(code_only "$BODY" | grep -c -- "-replace=")" == 1 ]] && ok "B16 the -target and -replace flags are each built in exactly one place (from the gate table)" || bad "B16 flag construction sites"
check "B17 no resource address literal outside the gate table (random_id., doppler_secret., hcloud_ appear only in table rows)" bash -c "! grep -Eq '(random_id|doppler_secret|hcloud_[a-z]+|terraform_data|tls_[a-z]+)\\.[a-z_]+' < <(grep -v '^ *#' '$BODY' | grep -v \"^  'A|\\|^  'B|\")"
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

# B24 an owner-supplied free-text value is shape-checked BEFORE it reaches date -d (kr_epoch): in kr_chk_converge_source the anchored
# regex on rotated_at precedes the kr_epoch of it.
KR_LN_RE="$(grep -n -F '[[ ! "$given" =~ ^[0-9]{4}' "$BODY" | head -1 | cut -d: -f1)"; KR_LN_EP="$(grep -n -F 'ge="$(kr_epoch "$given")"' "$BODY" | head -1 | cut -d: -f1)"
[[ -n "$KR_LN_RE" && -n "$KR_LN_EP" && "$KR_LN_RE" -lt "$KR_LN_EP" && "$(grep -c 'kr_epoch "$given"' "$BODY")" == 1 ]] && ok "B24 the anchored regex check on rotated_at (line $KR_LN_RE) runs before kr_epoch of it (line $KR_LN_EP), and kr_epoch of the free text is called once" || bad "B24 order: regex line '$KR_LN_RE' kr_epoch line '$KR_LN_EP'"
# B25 the test seams are refused under GITHUB_ACTIONS (functional rows in section D2); the loader's whole-project export must not redirect a command
check "B25 the seam refusal names every KR_ seam the workflow must never set, under GITHUB_ACTIONS" bash -c "grep -q 'for _kr_seam in KR_SLEEP KR_NOW KR_HZ_BASE KR_TRACK KR_HOST_STATE KR_BS_QUERY KR_INFRA_DIR' '$BODY' && grep -q 'GITHUB_ACTIONS:-}\" == true' '$BODY'"
# B28 cross-file parity: the owner-ask probe, the script and the workflow speak one vocabulary.
PROBE="$REPO_ROOT/scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh"
WF_INPUTS="$(yq 'sorted(on["workflow_dispatch"]["inputs"].keys())' | tr -d "[]',")"
probe_flags="$(grep -E '^(PLAN|ROTATE|CONVERGE)_LINE=' "$PROBE" | grep -Eo ' -f [a-z_]+=' | awk '{print $2}' | tr -d '=' | sort -u | tr '\n' ' ')"
script_flags="$(grep -E '^kr_converge_cmd|gh workflow run %s' "$BODY" | grep -Eo ' -f [a-z_]+=' | awk '{print $2}' | tr -d '=' | sort -u | tr '\n' ' ')"
unknown_flags="$(for f in $probe_flags $script_flags; do grep -qw "$f" <<<"$WF_INPUTS" || printf '%s ' "$f"; done)"
[[ -n "$probe_flags" && -n "$script_flags" && -z "$unknown_flags" ]] && ok "B28a every -f input the probe's three dispatch lines ($probe_flags) and the script's converge command ($script_flags) pass is a real workflow_dispatch input" || bad "B28a dispatch flags not in the workflow inputs: $unknown_flags"
[[ "$(sed -n 's/^SOAK=\([0-9]*\)$/\1/p' "$PROBE")" == "$(sed -n 's/^KR_SOAK_ISSUE=\([0-9]*\)$/\1/p' "$BODY")" ]] && ok "B28b the probe's SOAK tracker number is the script's KR_SOAK_ISSUE" || bad "B28b soak number"
PROBE_TOK="$(comm -12 <(tail -n +2 <<<"$(env -i PATH="$PATH" bash "$BODY" --print-contract)" | sort -u) <(grep -Eo '[a-z][a-z0-9]*(_[a-z0-9]+)+' "$PROBE" | sort -u) | tr '\n' ' ')"
WFTXT_TOK="$(comm -12 <(tail -n +2 <<<"$(env -i PATH="$PATH" bash "$BODY" --print-contract)" | sort -u) <(grep -Eo '[a-z][a-z0-9]*(_[a-z0-9]+)+' "$WF" | sort -u) | tr '\n' ' ')"
[[ "$PROBE_TOK" == "plan_blocked plan_ok " && "$WFTXT_TOK" == "" ]] && ok "B28c the verdict tokens the probe names are exactly plan_ok and plan_blocked, both in the contract; the workflow text names no verdict token (it only calls the script)" || bad "B28c token parity: probe='$PROBE_TOK' workflow='$WFTXT_TOK'"
PROBE_RECIPE="$(sed -n 's/^VERDICT_LINE="\(.*\)"$/\1/p' "$PROBE")"
[[ -n "$PROBE_RECIPE" && "$PROBE_RECIPE" == "$(unset GITHUB_RUN_ID; kr_verdict_recipe)" ]] && ok "B28d the verdict-reading recipe the probe prints is the one the stop sentence prints (modulo the run id)" || bad "B28d recipe drift: '$PROBE_RECIPE' vs '$(unset GITHUB_RUN_ID; kr_verdict_recipe)'"

printf '\n=== C0. --print-contract: offline, no credentials, fast ===\n'
T0=$SECONDS
PC_OUT="$(env -i PATH=/usr/bin:/bin bash "$BODY" --print-contract 2>&1)"; PC_RC=$?
PC_T=$((SECONDS - T0))
[[ "$PC_RC" == 0 && "$(head -1 <<<"$PC_OUT")" == "inngest-key-rotate verdict-tokens" ]] && ok "C0.1 --print-contract prints the 'inngest-key-rotate verdict-tokens' header and exits 0 with an empty environment" || bad "C0.1 rc=$PC_RC head='$(head -1 <<<"$PC_OUT")'"
[[ "$PC_T" -lt 15 ]] && ok "C0.2 --print-contract returns in ${PC_T}s (preflight Check 10 allows 15 s)" || bad "C0.2 slow: ${PC_T}s"
[[ "$(tail -n +2 <<<"$PC_OUT" | grep -c .)" -ge 30 && "$(tail -n +2 <<<"$PC_OUT" | grep -Evc '^[a-z][a-z0-9]*(_[a-z0-9]+)+$')" == 0 ]] && ok "C0.3 the list is one token per line, each snake_case" || bad "C0.3 list shape"
for t in plan_ok plan_blocked admit_ok converge_stale job_cancelled plan_gate_refused host_silent host_not_serving rerun_refused link_flag_pending soak_open reboot_refused_second_post converge_source_missing; do
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
# STRICT: every modelled call is matched on its WHOLE argv (verb, name, -p project, -c config) and on the token class of the call
# (Tier-A reads carry DOPPLER_TOKEN=dp.fixture, the copy reads carry the Terraform token). Anything else is refused with exit 64 and
# logged to refusals.log, which the suite requires to be empty for every non-mutant scenario.
echo "doppler $*" >> "$STUB/doppler.log"
refuse() { echo "doppler REFUSED: $*" >> "$STUB/refusals.log"; exit 64; }
if [[ "$1" == run ]]; then
  [[ "$*" == "run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- "* ]] || refuse "$@"
  shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift
  exec "$@"
fi
tierA() { [[ "${DOPPLER_TOKEN:-}" == dp.fixture ]] || refuse "tier-A call with token class '${DOPPLER_TOKEN:-}': $*"; }
tierTF() { [[ -n "${DOPPLER_TOKEN:-}" && "${DOPPLER_TOKEN:-}" != dp.fixture ]] || refuse "copy call with the tier-A token: $*"; }
names_of() { # project -> the secret names the project lists
  local w="$1"
  [[ -f "$STUB/state/names_${w}_rc" ]] && exit "$(cat "$STUB/state/names_${w}_rc")"
  echo OTHER
  [[ -f "$STUB/state/copy_${w}_signing" ]] && echo INNGEST_SIGNING_KEY
  [[ -f "$STUB/state/copy_${w}_event" ]] && echo INNGEST_EVENT_KEY
  exit 0
}
case "$*" in
  "secrets --only-names -p soleur -c prd_terraform")
    tierA; [[ -f "$STUB/state/names_rc" ]] && exit "$(cat "$STUB/state/names_rc")"
    cat "$STUB/state/names"; exit 0 ;;
  "secrets get INNGEST_LINK_TLS --plain -p soleur -c prd_terraform")
    tierA; [[ -f "$STUB/state/link" ]] && { cat "$STUB/state/link"; exit 0; }; exit 1 ;;
  "secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform")
    tierA; [[ -f "$STUB/state/hz_ro" ]] && { cat "$STUB/state/hz_ro"; exit 0; }; exit 1 ;;
  "secrets --only-names -p soleur-inngest -c prd") tierTF; names_of host ;;
  "secrets --only-names -p soleur -c prd") tierTF; names_of app ;;
  "secrets get INNGEST_SIGNING_KEY --plain -p soleur-inngest -c prd") tierTF; w=host; k=signing ;;
  "secrets get INNGEST_SIGNING_KEY --plain -p soleur -c prd") tierTF; w=app; k=signing ;;
  "secrets get INNGEST_EVENT_KEY --plain -p soleur-inngest -c prd") tierTF; w=host; k=event ;;
  "secrets get INNGEST_EVENT_KEY --plain -p soleur -c prd") tierTF; w=app; k=event ;;
  *) refuse "$@" ;;
esac
[[ -f "$STUB/state/copy_${w}_${k}" && ! -f "$STUB/state/copy_unreadable" ]] && { cat "$STUB/state/copy_${w}_${k}"; exit 0; }
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
    [[ -f "$STUB/state/apply_makes_unreadable" ]] && touch "$STUB/state/copy_unreadable"
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
  "GET /v1/servers/9999/actions?"*) code=200; body='{"actions":[]}' ;;
  "GET /v1/servers/4242/actions?"*) code="$(cat "$STUB/state/actions_code" 2>/dev/null || echo 200)"; body="$(cat "$STUB/state/actions.json")" ;;
  "GET /v1/servers/4242/actions/777") code=200; body="{\"action\":{\"id\":777,\"status\":\"$(cat "$STUB/state/action_status" 2>/dev/null || echo success)\"}}"
    [[ -f "$STUB/state/get_adv" ]] && "$STUB/bin/adv" "$(cat "$STUB/state/get_adv")" ;;
  "POST /v1/servers/4242/actions/reboot") code="$(cat "$STUB/state/post_code" 2>/dev/null || echo 201)"; body='{"action":{"id":777,"status":"running","command":"reboot_server"}}' ;;
  *) echo "curl REFUSED: $method $path" >> "$STUB/refusals.log"; exit 64 ;;
esac
[[ -n "$out" ]] && printf '%s' "$body" > "$out"
[[ "$wfmt" == *http_code* ]] && printf '%s' "$code"
exit 0
SH
  cat > "$d/bin/gh" <<'SH'
#!/usr/bin/env bash
# STRICT: the issue number, --repo, the workflow name and the status of every modelled call are matched; anything else is refused
# with exit 64 and logged to refusals.log (required empty for every non-mutant scenario).
echo "gh $*" >> "$STUB/gh.log"
refuse() { echo "gh REFUSED: $*" >> "$STUB/refusals.log"; exit 64; }
arg_after() { local k="$1" prev=""; shift; for a in "$@"; do [[ "$prev" == "$k" ]] && { printf '%s' "$a"; return 0; }; prev="$a"; done; return 1; }
[[ "$(arg_after --repo "$@")" == acme/repo ]] || refuse "$@"
case "$1 $2" in
  "issue view")
    [[ "$3" == 11215 && "$*" == *"--json state,stateReason"* ]] || refuse "$@"
    [[ -f "$STUB/state/soak_rc" ]] && exit "$(cat "$STUB/state/soak_rc")"; cat "$STUB/state/soak.json" ;;
  "issue list")
    [[ "$(arg_after --label "$@")" == action-required && "$(arg_after --limit "$@")" == 100 && "$(arg_after --json "$@")" == title ]] || refuse "$@"
    case "$(arg_after --state "$@")" in open|all) ;; *) refuse "$@" ;; esac
    cat "$STUB/state/issues.json" 2>/dev/null || echo '[]' ;;
  "issue create")
    [[ "$(arg_after --label "$@")" == action-required ]] || refuse "$@"
    t="$(arg_after --title "$@")"; echo "$t" >> "$STUB/issues_created.log"; echo "https://github.example/acme/repo/issues/1" ;;
  "run list")
    [[ -f "$STUB/state/runlist_rc" ]] && exit "$(cat "$STUB/state/runlist_rc")"
    wf="$(arg_after --workflow "$@")"
    case "$*" in
      *"--json databaseId,displayTitle,event"*)
        [[ "$wf" == inngest-key-rotate.yml && "$(arg_after --limit "$@")" == 200 ]] || refuse "$@"
        cat "$STUB/state/krruns.json" 2>/dev/null || echo '[]' ;;
      *"--json databaseId"*)
        st="$(arg_after --status "$@")"
        case "$wf" in apply-web-platform-infra.yml|inngest-link-flip.yml|cutover-inngest.yml|deploy-inngest-image.yml|web-platform-release.yml|inngest-key-rotate.yml) ;; *) refuse "$@" ;; esac
        case "$st" in in_progress|queued|waiting) ;; *) refuse "$@" ;; esac
        cat "$STUB/state/inflight_${wf}_${st}.json" 2>/dev/null || echo '[]' ;;
      *) refuse "$@" ;;
    esac ;;
  "run view")
    [[ "$3" =~ ^[0-9]+$ && "$*" == *"--json jobs"* ]] || refuse "$@"
    cat "$STUB/state/jobs_$3.json" 2>/dev/null || exit 1 ;;
  *) refuse "$@" ;;
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
if [[ -f "$STUB/state/hs_adv" ]]; then # a slow read: it takes hs_adv seconds of the fake clock but never longer than its timeout cap
  adv_n="$(cat "$STUB/state/hs_adv")"; cap_n="$(cat "$STUB/state/last_cap" 2>/dev/null || echo 99999)"
  "$STUB/bin/adv" "$(( adv_n < cap_n ? adv_n : cap_n ))"
fi
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
[[ -f "$f.jsonl" ]] && cat "$f.jsonl"
exit "$rc"
SH
  real_timeout="$(PATH=/usr/bin:/bin command -v timeout)"; real_jq="$(PATH=/usr/bin:/bin:/usr/local/bin command -v jq)"
  printf '#!/usr/bin/env bash\necho "$(cat "$STUB/state/now") $*" | cut -c1-140 >> "$STUB/timeout.log"\n[[ "$1" =~ ^[0-9]+$ ]] && echo "$1" > "$STUB/state/last_cap"\nexec %s "$@"\n' "$real_timeout" > "$d/bin/timeout"
  printf '#!/usr/bin/env bash\n[[ -f "$STUB/state/jq_fail_tls" && "$*" == *SOLEUR_INNGEST_BOOT_STAGE* ]] && exit 5\nexec %s "$@"\n' "$real_jq" > "$d/bin/jq"
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
cp "$D/gh_output" "$TMP/gout-rotate"
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
fresh; refuse_row D7a "run_attempt=10 (the comparison is exactly 1, not a prefix glob)" rerun_refused "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=10
fresh; refuse_row D7c "run_attempt empty (an unset attempt is not attempt 1: no default)" rerun_refused "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=
fresh; refuse_row D7d "run_attempt=0" rerun_refused "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=0
[[ ! -e "$D/doppler.log" && ! -e "$D/curl.log" && ! -e "$D/gh.log" ]] && ok "D7b a refusal on run_attempt reads nothing (cheap checks run before any read)" || bad "D7b reads happened before the refusal"
fresh; refuse_row D8 "a confirm with the wrong date" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=ROTATE-INNGEST-BOTH-2001-01-01"
fresh; refuse_row D8a "a confirm with the right date and a trailing -X (the comparison is exact, not a prefix glob)" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=ROTATE-INNGEST-BOTH-$TODAY-X"
fresh; refuse_row D8b "a lower-case confirm (the comparison is case-sensitive)" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=rotate-inngest-both-$TODAY"
fresh; refuse_row D8c "a confirm with a trailing space" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM=ROTATE-INNGEST-BOTH-$TODAY "
fresh; refuse_row D8d "an empty confirm on rotate" confirm_mismatch "${G_ROTATE[@]}" "INPUT_CONFIRM="
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
[[ "$(out_of "$D" plan_block)" == "link_flag_is_1:link_flag_pending" ]] && ok "D34a the guard hands the FIRST failing admission check to the plan aggregate: link_flag_is_1:link_flag_pending (the attempt, confirm and attestation failures are not in it)" || bad "D34a plan_block='$(out_of "$D" plan_block)'"
[[ "$ALL" == *"link_flag_is_1=false"* && "$ALL" == *"soak_closed_completed=false"* && "$ALL" == *"quiet_window_attested=false"* && "$ALL" == *"run_attempt_is_1=false"* && "$ALL" == *"confirm_ok=false"* && "$ALL" == *"no_run_in_flight=true"* ]] && ok "D35 plan reports each check as a boolean (link_flag_is_1, soak_closed_completed, quiet_window_attested, run_attempt_is_1, confirm_ok, ...)" || bad "D35 booleans" "$ALL"
fresh; run_script guard "${G_PLAN[@]}" GITHUB_RUN_ATTEMPT=2 INPUT_QUIET_WINDOW=false
[[ "$RC" == 0 && "$(out_of "$D" plan_block)" == "" && "$ALL" == *"run_attempt_is_1=false"* ]] && ok "D35a a plan whose ONLY failures are the owner-supplied attempt / confirm / attestation has no block (plan_ok stays reachable for the rehearsal)" || bad "D35a plan_block='$(out_of "$D" plan_block)'"
fresh; printf '%s' '{"state":"OPEN","stateReason":null}' > "$D/state/soak.json"; run_script guard "${G_PLAN[@]}"
[[ "$RC" == 0 && "$(out_of "$D" plan_block)" == "soak_closed_completed:soak_open" ]] && ok "D35b a plan with only the soak open names soak_closed_completed:soak_open" || bad "D35b plan_block='$(out_of "$D" plan_block)'"
fresh; hs_set_in "$D" 1 0 abcd1234 no $((NOW0 - 60)); run_script guard "${G_PLAN[@]}"
[[ "$RC" == 0 && "$(out_of "$D" plan_block)" == "host_serving_pre_reboot:host_not_serving_pre" ]] && ok "D35c a plan whose host reads NOT SERVING names host_serving_pre_reboot:host_not_serving_pre" || bad "D35c plan_block='$(out_of "$D" plan_block)'"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_cutover-inngest.yml_queued.json"; printf 'pending:1700000000' > "$D/state/link"; run_script guard "${G_PLAN[@]}"
[[ "$RC" == 0 && "$(out_of "$D" plan_block)" == "link_flag_is_1:link_flag_pending" ]] && ok "D35d with the link flag AND a run in flight both wrong the FIRST (ladder order) is the one named" || bad "D35d plan_block='$(out_of "$D" plan_block)'"
fresh; run_script guard "${G_PLAN[@]}"
[[ "$RC" == 0 && "$(out_of "$D" plan_block)" == "" ]] && cp "$D/gh_output" "$TMP/gout-plan" && ok "D35e a plan with every admission check passing has an EMPTY plan_block" || bad "D35e plan_block='$(out_of "$D" plan_block)'"
fresh; run_script guard "${G_PLAN[@]}" INPUT_MODE=bogus
[[ "$RC" != 0 && "$(verdict_of)" == inputs_invalid ]] && ok "D36 plan still refuses malformed inputs" || bad "D36 plan inputs"

printf '\n=== D. guard: converge derivation ===\n'
RUNS_JSON='[{"databaseId":9001,"displayTitle":"inngest-key-rotate converge both","event":"workflow_dispatch"},{"databaseId":8500,"displayTitle":"inngest-key-rotate converge both","event":"workflow_dispatch"},{"databaseId":8002,"displayTitle":"inngest-key-rotate plan both","event":"workflow_dispatch"},{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]'
conv_fixture() { # rotated_at-epoch: a rotate run whose apply1 succeeded then; a converge run and a plan run in between (never sources)
  printf '%s' "$RUNS_JSON" > "$D/state/krruns.json"
  printf '{"jobs":[{"name":"guard","conclusion":"success","completedAt":"%s"},{"name":"apply1","conclusion":"success","completedAt":"%s"}]}' "$(iso_of $(($1 - 600)))" "$(iso_of "$1")" > "$D/state/jobs_8001.json"
  printf '{"jobs":[{"name":"apply1","conclusion":"success","completedAt":"%s"}]}' "$(iso_of $(($1 + 99999)))" > "$D/state/jobs_8002.json"
}
hz_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S+00:00; }
ROT=$((NOW0 - 3600))
OLDB="$(bs_row $((NOW0 - 7200)) abcd1234 1)"; CURB="$(bs_row $((NOW0 - 300)) abcd1234 1)"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"
run_script guard "${G_CONVERGE[@]}"
cp "$D/gh_output" "$TMP/gout-converge"
[[ "$RC" == 0 && "$(out_of "$D" run_apply1)" == false && "$(out_of "$D" rotated_at)" == "$ROT" && "$(out_of "$D" reboot_post)" == true && "$(out_of "$D" boot_pre)" == abcd1234 && "$(out_of "$D" verify_after)" == "" && "$(out_of "$D" run_apply2)" == true && "$(out_of "$D" run_redeploy)" == true ]] \
  && ok "D37 converge derives rotated_at from the newest rotate run's successful apply1, skips apply1, and POSTs once when the newest boot began BEFORE rotated_at (boot_pre is that boot, verify_after empty)" || bad "D37 converge rc=$RC" "$OUT"
[[ "$(nlog "$D/gh.log" 'run view 8500')" == 0 && "$(nlog "$D/gh.log" 'run view 8002')" == 0 && "$(nlog "$D/gh.log" 'run view 8001')" == 1 && "$(nlog "$D/gh.log" 'run view 9001')" == 0 ]] && ok "D37b a converge-titled run (8500), a plan run (8002) and the run's own id are skipped: exactly ONE run view, of the newest rotate run" || bad "D37b runs viewed" "$(grep 'run view' "$D/gh.log")"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1800)) beef5678 1)" "$(bs_row $((NOW0 - 300)) beef5678 1)"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" boot_pre)" == "-" && "$(out_of "$D" verify_after)" == "$((NOW0 - 1800))" ]] && ok "D38 (case a) the newest boot's first row is later than rotated_at: no POST, boot_pre '-', and verify_after is that first row's epoch" || bad "D38 booted-after" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"running\",\"finished\":null}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" boot_pre)" == abcd1234 && "$(out_of "$D" verify_after)" == "" ]] && ok "D39 (case b) a Hetzner reboot action RUNNING: no POST, and boot_pre is the CURRENT newest boot (never '-': verify must see a different boot_id)" || bad "D39 running action" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"success\",\"finished\":\"$(hz_iso $((NOW0 - 120)))\"}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" boot_pre)" == abcd1234 ]] && ok "D40 (case b) a reboot action that finished 2 minutes ago (inside the boot wait; +00:00 timestamp form): no POST, boot_pre the current boot" || bad "D40 finished action" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"success\",\"finished\":\"$(iso_of $((NOW0 - 2000)))\"}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == true && "$(out_of "$D" boot_pre)" == abcd1234 ]] && ok "D41 a reboot action that SUCCEEDED long ago (after rotated_at) with NO new boot is host_silent, not progress: the POST is allowed" || bad "D41 old successful action" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reset_server\",\"status\":\"success\",\"finished\":\"$(iso_of $((NOW0 - 60)))\"},{\"id\":4,\"command\":\"reboot_server\",\"status\":\"error\",\"finished\":\"$(iso_of $((NOW0 - 90)))\"}]}" > "$D/state/actions.json"
run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == true ]] && ok "D41b a recent reset_server action and a recent FAILED reboot action are ignored: they are not a soft reboot in progress" || bad "D41b other actions counted" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"running\",\"finished\":null}]}" > "$D/state/actions.json"
refuse_row D41c "a reboot in progress but no readable boot_id (a new boot could not be told from the old)" host_state_unreadable "${G_CONVERGE[@]}"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1; run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == true && "$(out_of "$D" boot_pre)" == "-" ]] && ok "D41d no reboot in progress and no readable rows at all (host down): the POST is allowed, boot_pre '-'" || bad "D41d silent host" "$OUT"
fresh; refuse_row D42 "converge with no earlier run at all" converge_source_missing "${G_CONVERGE[@]}"
fresh; printf '%s' '[{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]' > "$D/state/krruns.json"
printf '{"jobs":[{"name":"guard","conclusion":"failure","completedAt":"%s"}]}' "$(iso_of "$ROT")" > "$D/state/jobs_8001.json"
refuse_row D43 "a guard-refused run (no apply1 job) is not a resumable source" converge_source_missing "${G_CONVERGE[@]}"
fresh; printf '%s' '[{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]' > "$D/state/krruns.json"
printf '{"jobs":[{"name":"apply1","conclusion":"failure","completedAt":"%s"}]}' "$(iso_of "$ROT")" > "$D/state/jobs_8001.json"
refuse_row D44 "a run whose apply1 FAILED is not a source (converge never mints a key; a failed first apply is re-dispatched as rotate)" converge_source_missing "${G_CONVERGE[@]}"
[[ "$ALL" == *"re-dispatch rotate with a fresh go; do not run converge"* ]] && ok "D44b the converge_source_missing refusal tells the owner to re-dispatch rotate with a fresh go and NOT to run converge" || bad "D44b detail" "$OUT"
fresh; conv_fixture "$ROT"; refuse_row D45 "converge keys=signing against a both rotation" converge_mismatch "${G_CONVERGE[@]}" INPUT_KEYS=signing "INPUT_CONFIRM=CONVERGE-INNGEST-SIGNING-$TODAY"
fresh; conv_fixture "$ROT"; refuse_row D46 "an owner-supplied rotated_at that disagrees with the run (a cross-check only)" converge_mismatch "${G_CONVERGE[@]}" "INPUT_ROTATED_AT=$(iso_of $((ROT - 7200)))"
fresh; conv_fixture "$ROT"; run_script guard "${G_CONVERGE[@]}" "INPUT_ROTATED_AT=$(iso_of $((ROT + 30)))"
[[ "$RC" == 0 ]] && ok "D47 an owner-supplied rotated_at that agrees (within 10 minutes) is accepted" || bad "D47 agreeing rotated_at" "$OUT"
fresh; conv_fixture "$ROT"; refuse_row D48 "run_attempt=2 on converge" rerun_refused "${G_CONVERGE[@]}" GITHUB_RUN_ATTEMPT=2
fresh; conv_fixture "$ROT"; printf 'pending:1700000000' > "$D/state/link"; refuse_row D49 "converge refuses while the link flag is not 1" link_flag_pending "${G_CONVERGE[@]}"
fresh; conv_fixture "$ROT"; run_script guard "${G_CONVERGE[@]}"
[[ "$(nlog "$D/gh.log" 'run view 9001')" == 0 ]] && ok "D50 the converge derivation never reads its own run" || bad "D50 own run read"
# the source bound (CTO ruling fork 2 ii): the FIRST rotate run decides; an older successful rotation is never walked to; an old source is stale
fresh; printf '%s' '[{"databaseId":8100,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"},{"databaseId":8001,"displayTitle":"inngest-key-rotate rotate both","event":"workflow_dispatch"}]' > "$D/state/krruns.json"
printf '{"jobs":[{"name":"apply1","conclusion":"failure","completedAt":"%s"}]}' "$(iso_of "$ROT")" > "$D/state/jobs_8100.json"
printf '{"jobs":[{"name":"apply1","conclusion":"success","completedAt":"%s"}]}' "$(iso_of $((ROT - 5000)))" > "$D/state/jobs_8001.json"
refuse_row D51 "the newest rotate run failed its first apply and an OLDER rotation succeeded: converge refuses, it never walks back to the older one" converge_source_missing "${G_CONVERGE[@]}"
[[ "$(nlog "$D/gh.log" 'run view 8001')" == 0 ]] && ok "D51b ...and the older run is never even read" || bad "D51b older run read"
fresh; conv_fixture $((NOW0 - 90000)); refuse_row D52 "a rotation that finished more than 24 hours ago is converge_stale" converge_stale "${G_CONVERGE[@]}"
fresh; conv_fixture $((NOW0 - 86400)); bs_set_in "$D" 1 "$OLDB" "$CURB"; run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 ]] && ok "D52b a rotation that finished exactly KR_CONVERGE_MAX_AGE_S (86400 s) ago is still accepted" || bad "D52b boundary" "$OUT"
fresh; conv_fixture $((NOW0 - 86401)); refuse_row D52c "one second past the limit is converge_stale" converge_stale "${G_CONVERGE[@]}"
fresh; conv_fixture "$ROT"; refuse_row D53 "a rotated_at input that is not a UTC time of the exact form is converge_mismatch (shape-checked before date -d)" converge_mismatch "${G_CONVERGE[@]}" "INPUT_ROTATED_AT=tomorrow"
fresh; conv_fixture "$ROT"; refuse_row D53b "a rotated_at carrying a command substitution is refused by shape and runs nothing" converge_mismatch "${G_CONVERGE[@]}" "INPUT_ROTATED_AT=\$(touch $D/pwned)"
[[ ! -e "$D/pwned" ]] && ok "D53c ...the substitution did not execute" || bad "D53c command substitution executed"

printf '\n=== D2. the test seams are refused under GITHUB_ACTIONS ===\n'
seam_refusal() { # <seam> -> "<rc> <FAIL SETUP seen>"
  local out rc
  out="$(env -i PATH="$PATH" GITHUB_ACTIONS=true "$1=/bin/true" bash "$BODY" --print-contract 2>&1)"; rc=$?
  printf '%s %s' "$rc" "$([[ "$out" == *"[FAIL SETUP]"*"$1"* ]] && echo seen || echo unseen)"
}
SEAM_BAD=""
for sm in KR_SLEEP KR_NOW KR_HZ_BASE KR_TRACK KR_HOST_STATE KR_BS_QUERY KR_INFRA_DIR; do
  [[ "$(seam_refusal "$sm")" == "78 seen" ]] || SEAM_BAD="$SEAM_BAD $sm($(seam_refusal "$sm"))"
done
[[ -z "$SEAM_BAD" ]] && ok "D2.1 each of the seven KR_ test seams (KR_NOW, KR_SLEEP are executed words) makes the script exit 78 with [FAIL SETUP] under GITHUB_ACTIONS=true" || bad "D2.1 seams not refused:$SEAM_BAD"
SC_OK="$(env -i PATH="$PATH" GITHUB_ACTIONS=true bash "$BODY" --print-contract 2>&1 | head -1)"; SC_OFF="$(env -i PATH="$PATH" KR_NOW=/bin/true bash "$BODY" --print-contract 2>&1 | head -1)"
[[ "$SC_OK" == "inngest-key-rotate verdict-tokens" && "$SC_OFF" == "inngest-key-rotate verdict-tokens" ]] && ok "D2.2 (controls) GITHUB_ACTIONS=true with no seam runs, and a seam outside GITHUB_ACTIONS (the suite's own use) runs" || bad "D2.2 controls: '$SC_OK' '$SC_OFF'"

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

fresh; run_script apply1 "${APPLY_PLAN[@]}" EFF_PLAN_BLOCK=link_flag_is_1:link_flag_pending
[[ "$RC" != 0 && "$(verdict_of)" == plan_blocked && "$OUT" == *"check link_flag_is_1 is false (link_flag_pending)"* && "$(nlog "$D/tf.log" '^terraform plan')" == 2 && "$(nlog "$D/tf.log" '^apply')" == 0 && "$OUT" != *"verdict=plan_ok"* ]] && ok "F6a the plan aggregate: both Terraform gates passed but the guard recorded a failed admission check: verdict=plan_blocked naming the first failing check, NOT plan_ok, exit non-zero, nothing applied" || bad "F6a rc=$RC" "$OUT"
fresh; run_script apply1 "${APPLY_PLAN[@]}" EFF_PLAN_BLOCK='x y;z'
[[ "$RC" != 0 && "$(verdict_of)" == plan_blocked && "$OUT" == *"check unknown is false"* ]] && ok "F6b a malformed plan_block value is still plan_blocked (never plan_ok)" || bad "F6b rc=$RC" "$OUT"
fresh; run_script apply1 "${APPLY_PLAN[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" == 0 && "$(verdict_of)" == plan_ok ]] && ok "F6c a plan re-run (run_attempt=2) is allowed: plan writes nothing" || bad "F6c rc=$RC" "$OUT"
fresh; printf '%s' '[{"address":"doppler_secret.inngest_redis_password_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_a"
run_script apply1 "${APPLY_PLAN[@]}" EFF_PLAN_BLOCK=link_flag_is_1:link_flag_pending
[[ "$RC" != 0 && "$(verdict_of)" == plan_gate_refused ]] && ok "F6d a Terraform gate refusal outranks the admission block (the gate verdict is printed, never plan_ok)" || bad "F6d rc=$RC" "$OUT"

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
REDISPATCH="Re-dispatch rotate with a fresh go; do not run converge. Until then an unrelated host restart loads the new dedicated key while the app holds the old."
[[ "$RC" != 0 && "$(verdict_of)" == apply_failed && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"$REDISPATCH"* && "$ALL" != *"-f mode=converge"* && "$ALL" == *"A rotate needs the owner's own per-command go"* ]] && [[ "$(wc -l < "$D/issues_created.log")" == 1 && "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 ]] \
  && ok "F19 a FAILED phase-1 apply prints ONE stop sentence that says re-dispatch rotate with a fresh go and do NOT run converge (nothing rebooted; converge has no source to resume), files one action-required issue, leaks nothing" || bad "F19 rc=$RC" "$OUT"
[[ "$ALL" == *"gh run view 9001 --log | grep 'inngest-key-rotate verdict='"* ]] && ok "F19b the stop sentence carries the one-line recipe for reading the verdict (gh run view <id> --log | grep 'inngest-key-rotate verdict=')" || bad "F19b recipe" "$OUT"
grep -q -- '--label action-required' "$D/gh.log" && ok "F20 the issue is filed with the action-required label" || bad "F20 label"
fresh; touch "$D/state/apply_noeffect"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == value_unchanged && "$ALL" == *"new_differs_from_prior=false"* && "$ALL" == *"$REDISPATCH"* && "$ALL" != *"-f mode=converge"* ]] && ok "F21 an apply after which the dedicated copy is unchanged fails as value_unchanged, with the re-dispatch (not converge) sentence" || bad "F21 rc=$RC" "$OUT"
fresh; touch "$D/state/apply_makes_unreadable"; run_script apply1 "${APPLY_ROT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copy_unreadable && "$ALL" == *"$REDISPATCH"* && "$ALL" != *"-f mode=converge"* && -s "$D/issues_created.log" ]] && ok "F21b a dedicated copy that cannot be read AFTER the apply is copy_unreadable with the re-dispatch (not converge) sentence and one issue" || bad "F21b rc=$RC" "$OUT"
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
[[ "$ALL" == *"-f reason='converge after inngest-key-rotate run 9001'"* && "$ALL" == *"-f confirm=CONVERGE-INNGEST-BOTH-YYYY-MM-DD"* && "$ALL" == *"replace YYYY-MM-DD in the confirm with the UTC date of that dispatch, today is $TODAY UTC"* ]] && ok "F32a the converge command single-quotes its reason like the runbook and the probe, and says the confirm needs the UTC date of the DISPATCH (a placeholder plus today's date, never a stale date)" || bad "F32a converge command text" "$ALL"
[[ "$RC" != 0 && "$(verdict_of)" == apply_failed && "$ALL" == *"mode=converge"* && -s "$D/issues_created.log" ]] && ok "F32 a failed phase-2 apply prints the stop sentence with the converge command and files the issue" || bad "F32"
fresh; after_phase1; touch "$D/state/apply_noeffect"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copies_differ && "$ALL" == *"copies_equal=false"* ]] && ok "F33 phase 2 after which the copies still differ fails as copies_differ (boolean only)" || bad "F33"
fresh; after_phase1; printf '[{"databaseId":7}]' > "$D/state/inflight_inngest-link-flip.yml_in_progress.json"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_in_flight && ! -e "$D/tf.log" ]] && ok "F34 apply2 re-runs the in-flight refusal first (an inngest-link-flip run stops it)" || bad "F34"

[[ "$ALL" == *"run converge once the release finishes"* && -s "$D/issues_created.log" && "$ALL" == *"STOP: do not retry"* ]] && ok "F34b an in-flight refusal AFTER phase 1 landed is a post-write failure: the stop sentence ('run converge once the release finishes') and one issue, not 'nothing was written'" || bad "F34b post-write in-flight" "$OUT"
# the absent app secret (CTO ruling fork 2 iii): the destroy half of a phase 2 -replace ran and the create did not
PRD_RECOVERY="$(pj "doppler_secret.inngest_signing_key_prd=create;nobefore" "doppler_secret.inngest_event_key_prd=create;nobefore")"
fresh; after_phase1; rm -f "$D/state/copy_app_signing" "$D/state/copy_app_event"; printf '%s' "$PRD_RECOVERY" > "$D/state/plan_override_b"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply2_ok && "$(nlog "$D/tf.log" '^apply b')" == 1 && "$(nlog "$D/tf.log" '^terraform plan')" == 1 ]] && cmp -s "$D/state/copy_host_signing" "$D/state/copy_app_signing" && ok "F35 apply2 with the app secrets ABSENT reaches Gate B, plans the documented bare create, applies once and ends with both copies equal (recovery is reachable)" || bad "F35 rc=$RC" "$OUT"
fresh; after_phase1; rm -f "$D/state/copy_app_signing" "$D/state/copy_app_event"; printf '1' > "$D/state/names_app_rc"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copy_unreadable && ! -e "$D/tf.log" && -s "$D/issues_created.log" ]] && ok "F35b ...but when the NAME LISTING itself fails the app secret is not known to be absent: copy_unreadable, no Terraform call, one issue" || bad "F35b rc=$RC" "$OUT"
fresh; after_phase1; touch "$D/state/copy_unreadable"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copy_unreadable && ! -e "$D/tf.log" ]] && ok "F35c a PRESENT but unreadable copy (the dedicated copy included) stays copy_unreadable" || bad "F35c rc=$RC" "$OUT"
fresh; after_phase1; rm -f "$D/state/copy_host_signing"; rm -f "$D/state/copy_app_signing"; run_script apply2 EFF_MODE=rotate EFF_KEYS=signing "${A_ENV[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copy_unreadable && ! -e "$D/tf.log" ]] && ok "F35d an unreadable DEDICATED copy is copy_unreadable even when the app copy is absent too (only an absent APP copy means 'differs')" || bad "F35d rc=$RC" "$OUT"
fresh; after_phase1; rm -f "$D/state/copy_app_event"; printf '%s' "$(pj "$P_S" "doppler_secret.inngest_event_key_prd=create;nobefore")" > "$D/state/plan_override_b"; run_script apply2 EFF_MODE=converge EFF_KEYS=both "${A_ENV[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == apply2_ok ]] && grep -q 'plan .*doppler_secret.inngest_event_key_prd' "$D/tf.log" && ok "F35e converge with only the event app secret absent (signing differs normally) plans both and recovers" || bad "F35e rc=$RC" "$OUT"
# the attempt check (CTO ruling fork 3): a Re-run of failed jobs reuses the first attempt's guard outputs
fresh; run_script apply1 "${APPLY_ROT[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && ! -e "$D/tf.log" && ! -e "$D/issues_created.log" ]] && ok "F36 apply1 (rotate) refuses run_attempt=2 as rerun_refused BEFORE any Terraform call (nothing written, so no issue)" || bad "F36 rc=$RC" "$OUT"
fresh; after_phase1; run_script apply2 "${APPLY_2[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && ! -e "$D/tf.log" && -s "$D/issues_created.log" && "$ALL" == *"Re-run failed jobs is refused by every write job"* ]] && ok "F36b apply2 refuses run_attempt=2 as rerun_refused after phase 1: no Terraform call, the stop sentence and one issue" || bad "F36b rc=$RC" "$OUT"
fresh; after_phase1; run_script apply2 "${APPLY_2[@]}" GITHUB_RUN_ATTEMPT=10
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused ]] && ok "F36c apply2 refuses run_attempt=10 too (exactly 1, not a prefix)" || bad "F36c rc=$RC" "$OUT"
fresh; after_phase1; run_script apply2 "${APPLY_2[@]}" GITHUB_RUN_ATTEMPT=
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused ]] && ok "F36d apply2 refuses an EMPTY run_attempt (no default of 1)" || bad "F36d rc=$RC" "$OUT"
# the other post-write refusals file the stop sentence and the issue
fresh; after_phase1; run_script apply2 EFF_MODE=rotate EFF_KEYS=both AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY= DOPPLER_TOKEN=dp.fixture DOPPLER_TOKEN_TF=dp.tffixture
[[ "$RC" != 0 && "$(verdict_of)" == credential_absent && -s "$D/issues_created.log" && "$ALL" == *"STOP: do not retry"* ]] && ok "F37 apply2 with no Terraform backend pair is credential_absent as a post-write failure (stop sentence and issue)" || bad "F37 rc=$RC" "$OUT"
fresh; after_phase1; printf '1' > "$D/state/plan_rc"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == terraform_failed && -s "$D/issues_created.log" && "$ALL" == *"-f mode=converge"* ]] && ok "F37b a failed phase-2 plan is terraform_failed as a post-write failure: the converge command and one issue" || bad "F37b rc=$RC" "$OUT"
fresh; after_phase1; touch "$D/state/apply_noeffect"; printf '%s' '[{"address":"doppler_secret.inngest_signing_key_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_b"; run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == plan_gate_refused && -s "$D/issues_created.log" ]] && ok "F37c a Gate B refusal in apply2 files the stop sentence and one issue (phase 1 already landed)" || bad "F37c rc=$RC" "$OUT"

printf '\n=== G. reboot: the one POST ===\n'
RB=(EFF_MODE=rotate EFF_KEYS=both EFF_SERVER_ID=4242 EFF_REBOOT_POST=true HCLOUD_TOKEN="$WRITE_TOK")
fresh; run_script reboot "${RB[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok && "$(npost)" == 1 && "$(out_of "$D" post_epoch)" == "$NOW0" ]] && ok "G1 the reboot step makes exactly ONE POST, polls the action to success and records the POST time" || bad "G1 rc=$RC posts=$(npost)" "$OUT"
grep -qx 'POST /v1/servers/4242/actions/reboot token=write' "$D/post.log" && [[ "$(nlog "$D/curl.log" 'token=ro')" == 0 ]] && ok "G2 the POST carries the WRITE token (and the reboot step never uses the read-only one)" || bad "G2 token class" "$(cat "$D/curl.log")"
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL" | grep -v 'add-mask'))" == 0 && "$ALL" != *"$WRITE_TOK"*$'\n'*"$WRITE_TOK"* ]] && ok "G3 no key-shaped string in the reboot step's streams" || bad "G3 sentinel"
[[ "$OUT" == *"::add-mask::$WRITE_TOK"* ]] && ok "G3b the reboot step masks the Hetzner write token (::add-mask:: with the token itself, so the runner masks it everywhere)" || bad "G3b token not masked"
fresh; run_script reboot "${RB[@]}" EFF_REBOOT_POST=false
[[ "$RC" == 0 && ! -e "$D/curl.log" ]] && ok "G4 EFF_REBOOT_POST=false (converge: a reboot already ran or the boot is newer than rotated_at) makes no Hetzner call at all" || bad "G4"
fresh; printf '500' > "$D/state/post_code"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == reboot_post_failed && "$(npost)" == 1 && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"mode=converge"* && -s "$D/issues_created.log" ]] && ok "G5 a failed POST is not retried (1 POST), prints the stop sentence with the converge command and files the issue" || bad "G5 rc=$RC posts=$(npost)" "$OUT"
fresh; printf 'error' > "$D/state/action_status"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == reboot_action_failed && "$(npost)" == 1 ]] && ok "G6 a Hetzner action that ends in error is reboot_action_failed (one POST)" || bad "G6"
fresh; printf 'running' > "$D/state/action_status"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == reboot_action_failed && "$(npost)" == 1 && $(( $(cat "$D/state/now") - NOW0 )) -le 330 ]] && ok "G7 an action that never finishes is bounded (the 300 s action budget) and fails without a second POST" || bad "G7 elapsed=$(( $(cat "$D/state/now") - NOW0 ))"
fresh; printf 'running' > "$D/state/action_status"; printf '25' > "$D/state/get_adv"; run_script reboot "${RB[@]}"; EL=$(( $(cat "$D/state/now") - NOW0 ))
[[ "$RC" != 0 && "$(verdict_of)" == reboot_action_failed && "$(npost)" == 1 && "$EL" -le 340 && "$EL" -ge 300 ]] && ok "G7b the action poll is TIME-bounded: with each status read taking 25 s a never-finishing action ends at the 300 s budget (elapsed ${EL}s), not after 30 polls x 35 s (> the 10-minute step)" || bad "G7b elapsed=$EL" "$OUT"
fresh; run_script reboot "${RB[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && "$(npost)" == 0 && -s "$D/issues_created.log" && "$ALL" == *"STOP: do not retry"* ]] && ok "G7c the reboot step refuses run_attempt=2 (Re-run failed jobs) as rerun_refused: no POST, the stop sentence and one issue" || bad "G7c rc=$RC" "$OUT"
fresh; run_script reboot "${RB[@]}" GITHUB_RUN_ATTEMPT=10
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && "$(npost)" == 0 ]] && ok "G7d ...and run_attempt=10 (exactly 1)" || bad "G7d rc=$RC" "$OUT"
fresh; run_script reboot "${RB[@]}" GITHUB_RUN_ATTEMPT= EFF_REBOOT_POST=false
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && "$(npost)" == 0 ]] && ok "G7e ...and an empty run_attempt, even when this run would make no POST (the check precedes the no-POST exit)" || bad "G7e rc=$RC" "$OUT"
fresh; printf '%s' '{"servers":[{"id":9999,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$D/state/servers.json"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_not_unique && "$(npost)" == 0 && -s "$D/issues_created.log" && "$ALL" == *"STOP: do not retry"* ]] && ok "G8 the reboot step re-resolves the server by name AND IP and refuses when the id differs from the guard's (no POST); phase 1 already landed, so it ends with the stop sentence and one issue" || bad "G8"
fresh; run_script reboot "${RB[@]}" HCLOUD_TOKEN=
[[ "$RC" != 0 && "$(verdict_of)" == credential_absent && "$(npost)" == 0 && -s "$D/issues_created.log" ]] && ok "G9 an empty HCLOUD_TOKEN is credential_absent (no POST), as a post-write failure (one issue)" || bad "G9"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_deploy-inngest-image.yml_in_progress.json"; run_script reboot "${RB[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_in_flight && "$(npost)" == 0 && -s "$D/issues_created.log" && "$ALL" == *"run converge once the release finishes"* ]] && ok "G10 the reboot step re-runs the in-flight refusal first (a deploy-inngest-image run stops it) and, because phase 1 landed, ends with the stop sentence 'run converge once the release finishes' and one issue" || bad "G10"
fresh; run_script reboot "${RB[@]}" EFF_SERVER_ID=abc
[[ "$RC" != 0 && "$(npost)" == 0 && ! -e "$D/issues_created.log" ]] && ok "G11 a non-numeric server id is refused (an argument-misuse check: a plain refusal, no issue)" || bad "G11"
fresh; run_script reboot "${RB[@]}" EFF_MODE=plan
[[ "$RC" != 0 && "$(npost)" == 0 && ! -e "$D/issues_created.log" ]] && ok "G12 the reboot step refuses mode=plan (argument misuse: a plain refusal)" || bad "G12"
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
[[ "$(kr_sentinel_hits <(printf '%s' "$ALL"))" == 0 && "$OUT" != *"abcd1234"* && "$OUT" != *"beef5678"* && "$(out_of "$D" boot_new)" == beef5678 && "$(out_of "$D" verified_at)" =~ ^[0-9]+$ ]] && ok "G17 verify prints booleans only (no boot_id or host text in the log or summary); the MEASURED new boot_id (8 hex, non-secret) and the time verify passed leave only through the job outputs, for the evidence block" || bad "G17 host text leaked" "$ALL"
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

# verify: the final poll's fault decides host_read_failed (a transient early fault does not), the read class is the REAL one
fresh; hs_set_in "$D" 1 4 x yes 0; printf '1' > "$D/state/bs_1.rc"; : > "$D/state/bs_1.jsonl"; bs_set_in "$D" 2 "$OLDROW"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_silent && "$ALL" != *"says nothing about the host"* ]] && ok "G30 one transient read fault on the FIRST poll followed by clean polls that see only silence is host_silent: host_read_failed gates on the FINAL poll's fault, not a sticky earlier one" || bad "G30 sticky fault: verdict=$(verdict_of)" "$OUT"
fresh; hs_set_in "$D" 1 6 x yes 0; printf '22' > "$D/state/bs_1.rc"; printf 'CLUSTER_DOESNT_EXIST: the connection does not cover this source' > "$D/state/bs_1.jsonl"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_read_failed && "$ALL" == *"class source-not-in-connection"* && "$ALL" != *"CLUSTER_DOESNT_EXIST"* ]] && ok "G31 an rc=22 Better Stack failure is classified from the response BODY (stdout), not stderr: class source-not-in-connection, and the body itself is never printed" || bad "G31 rc=22 body class" "$ALL"
fresh; hs_set_in "$D" 1 6 x yes 0; bs_set_in "$D" 1 "$OLDROW"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_read_failed && "$ALL" == *"class host-state-exit-6"* ]] && ok "G32 a failed HOST-STATE read is named as such (class host-state-exit-6); it never borrows a stale Better Stack read code" || bad "G32 stale class" "$ALL"
fresh; hs_set_in "$D" 1 4 x yes 0; bs_set_in "$D" 1 "$OLDROW"; : > "$D/state/jq_fail_tls"
run_script verify "${VF[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_read_failed ]] && ok "G33 a tls-health result jq could not parse is a failed READ (host_read_failed), never 'no rows' (host_silent)" || bad "G33 jq failure read as silence: $(verdict_of)" "$OUT"
fresh; hs_set_in "$D" 1 4 x yes 0; bs_set_in "$D" 1 "$OLDROW"
run_script verify "${VF[@]}"
[[ "$(verdict_of)" == host_silent ]] && ok "G33b (control) with a healthy jq the same silence IS host_silent" || bad "G33b"
# verify: the loop is bounded by the step (every read capped at the time left; the step ends before its timeout)
fresh; hs_set_in "$D" 1 0 beef5678 no $((NOW0 + 200)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 150)) beef5678 1)"; printf '200' > "$D/state/hs_adv"
run_script verify "${VF[@]}"; EL=$(( $(cat "$D/state/now") - NOW0 ))
CAP_VIOL="$(awk -v end=$((NOW0 + B_VERIFY_STEP - B_MARGIN)) '/hoststate.sh|bsquery.sh/ { if ($1 + $2 > end + 1) n++ } END { print n + 0 }' "$D/timeout.log")"
CAP_HIT="$(awk '/hoststate.sh/ { if ($2 < 240) n++ } END { print n + 0 }' "$D/timeout.log")"
[[ "$RC" != 0 && "$(verdict_of)" == host_not_serving && "$CAP_VIOL" == 0 && "$CAP_HIT" -ge 1 && "$EL" -le $((B_VERIFY_STEP - B_MARGIN + 5)) ]] && ok "G34 slow reads (200 s each) cannot outlive the verify step: every read is capped at the time left (the last host read ran with a cap below 240 s), no read ends past the step minus the ${B_MARGIN}s margin, and the verdict is printed (elapsed ${EL}s of ${B_VERIFY_STEP}s)" || bad "G34 viol=$CAP_VIOL hit=$CAP_HIT elapsed=$EL rc=$RC verdict=$(verdict_of)" "$(cat "$D/timeout.log" | tail -5)"
# verify: no POST this run. verify_after (converge case a) replaces rotated_at; the old boot's rows do not pass (case b)
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 - 300)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 200)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_VERIFY_AFTER=$((NOW0 - 100))" "EFF_ROTATED_AT=$((NOW0 - 3600))" "${BSV[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_silent ]] && ok "G35 converge verify_after: rows EARLIER than verify_after do not count even though they are later than rotated_at" || bad "G35 verify_after ignored: $(verdict_of)" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 - 40)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 50)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_VERIFY_AFTER=$((NOW0 - 100))" "EFF_ROTATED_AT=$((NOW0 - 3600))" "${BSV[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok ]] && ok "G35b ...and rows after verify_after pass" || bad "G35b" "$OUT"
fresh; hs_set_in "$D" 1 0 abcd1234 yes $((NOW0 - 40)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1000)) abcd1234 1)" "$(bs_row $((NOW0 - 50)) abcd1234 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=abcd1234 "EFF_ROTATED_AT=$((NOW0 - 3600))" "${BSV[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == host_silent ]] && ok "G36 converge with a reboot in progress (boot_pre = the current boot): the OLD boot's rows, all later than rotated_at, do NOT pass verify" || bad "G36 old-boot rows passed: $(verdict_of)" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 - 40)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1000)) abcd1234 1)" "$(bs_row $((NOW0 - 50)) beef5678 1)"
run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=abcd1234 "EFF_ROTATED_AT=$((NOW0 - 3600))" "${BSV[@]}"
[[ "$RC" == 0 ]] && ok "G36b ...and the new boot's rows do" || bad "G36b" "$OUT"
fresh; run_script verify "${VF[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && -s "$D/issues_created.log" && ! -e "$D/hs.log" ]] && ok "G37 verify refuses run_attempt=2 before it reads anything (rerun_refused, the stop sentence, one issue)" || bad "G37 rc=$RC" "$OUT"
fresh; run_script verify "${VF[@]}" BETTERSTACK_QUERY_PASSWORD=
[[ "$RC" != 0 && "$(verdict_of)" == credential_absent && -s "$D/issues_created.log" ]] && ok "G37b verify's credential refusal is a post-write failure (one issue)" || bad "G37b" "$OUT"

printf '\n=== G2. admit: the read-only re-admission before the POST ===\n'
ADM=(EFF_MODE=rotate EFF_KEYS=both EFF_SERVER_ID=4242 EFF_REBOOT_POST=true DOPPLER_TOKEN=dp.fixture "${BSV[@]}")
fresh; run_script admit "${ADM[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == admit_ok && "$(out_of "$D" boot_pre)" == abcd1234 && "$(out_of "$D" reboot_post)" == true && "$(out_of "$D" verify_after)" == "" && "$(npost)" == 0 && "$(nlog "$D/curl.log" 'token=write')" == 0 && "$(nlog "$D/curl.log" 'token=ro')" -ge 1 ]] && ok "G2.1 admit (rotate) re-reads the link flag, the runs in flight, the single server and the host with the READ-ONLY token only, emits boot_pre and reboot_post=true, and makes no POST" || bad "G2.1 rc=$RC" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 - 60)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 120)) beef5678 1)"
run_script admit "${ADM[@]}"
[[ "$RC" == 0 && "$(out_of "$D" boot_pre)" == beef5678 ]] && ok "G2.2 boot_pre comes from the ADMIT read: the host restarted after the guard (guard-time abcd1234) and admit reports the boot it sees NOW (beef5678), so a stale guard-time boot_pre can never cause a false pass" || bad "G2.2 boot_pre=$(out_of "$D" boot_pre)" "$OUT"
admit_refused() { # id desc token
  local id="$1" desc="$2" tok="$3"
  if [[ "$RC" != 0 && "$(verdict_of)" == "$tok" && "$(npost)" == 0 && -z "$(out_of "$D" boot_pre)" && -z "$(out_of "$D" reboot_post)" && -s "$D/issues_created.log" && "$ALL" == *"STOP: do not retry"* ]]; then ok "$id $desc -> verdict=$tok before the POST: no boot_pre / reboot_post output (the POST step is skipped), the stop sentence and one issue"; else bad "$id $desc" "rc=$RC verdict=$(verdict_of) want=$tok"; fi
}
fresh; printf 'pending:1700000000' > "$D/state/link"; run_script admit "${ADM[@]}"; admit_refused G2.3 "the link flag no longer 1 (a flip started during the approval wait)" link_flag_pending
fresh; printf 'OTHER\n' > "$D/state/names"; run_script admit "${ADM[@]}"; admit_refused G2.3b "the link flag removed" link_flag_unset
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_web-platform-release.yml_queued.json"; run_script admit "${ADM[@]}"; admit_refused G2.4 "a web-platform-release run queued during the approval wait" run_in_flight
fresh; printf '%s' '{"servers":[{"id":9999,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$D/state/servers.json"; run_script admit "${ADM[@]}"; admit_refused G2.5 "a server id that differs from the guard's" host_not_unique
fresh; hs_set_in "$D" 1 0 abcd1234 no $((NOW0 - 60)); run_script admit "${ADM[@]}"; admit_refused G2.6 "the host reads NOT SERVING at admit" host_not_serving_pre
fresh; hs_set_in "$D" 1 6 abcd1234 yes $((NOW0 - 60)); run_script admit "${ADM[@]}"; admit_refused G2.6b "the host-state read fails at admit" host_state_unreadable
fresh; run_script admit "${ADM[@]}" GITHUB_RUN_ATTEMPT=2; admit_refused G2.7 "run_attempt=2" rerun_refused
fresh; run_script admit "${ADM[@]}" BETTERSTACK_QUERY_PASSWORD=; admit_refused G2.8 "a Better Stack credential missing" credential_absent
fresh; rm -f "$D/state/hz_ro"; run_script admit "${ADM[@]}"; admit_refused G2.8b "the read-only Hetzner token unreadable" credential_absent
fresh; run_script admit "${ADM[@]}" EFF_MODE=plan
[[ "$RC" != 0 && "$(verdict_of)" == internal_error && ! -e "$D/issues_created.log" ]] && ok "G2.9 admit refuses mode=plan (argument misuse: a plain refusal)" || bad "G2.9"
# converge: admit re-runs the converge host decision and may only turn the guard's reboot_post from true to false
ADMC=(EFF_MODE=converge EFF_KEYS=both EFF_SERVER_ID=4242 "EFF_ROTATED_AT=$((NOW0 - 3600))" DOPPLER_TOKEN=dp.fixture "${BSV[@]}")
fresh; bs_set_in "$D" 1 "$(bs_row $((NOW0 - 1800)) beef5678 1)" "$(bs_row $((NOW0 - 300)) beef5678 1)"; run_script admit "${ADMC[@]}" EFF_REBOOT_POST=true
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" verify_after)" == "$((NOW0 - 1800))" && "$(out_of "$D" boot_pre)" == "-" ]] && ok "G2.10 converge: the guard said POST but the host restarted onto the new key during the approval wait: admit turns reboot_post true -> false and emits verify_after" || bad "G2.10 rc=$RC" "$OUT"
fresh; bs_set_in "$D" 1 "$OLDB" "$CURB"; run_script admit "${ADMC[@]}" EFF_REBOOT_POST=false
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" boot_pre)" == abcd1234 ]] && ok "G2.11 converge: the guard said NO POST and the fresh read would allow one: admit NEVER turns false into true (reboot_post stays false; the fresh boot_pre is used)" || bad "G2.11 rc=$RC" "$OUT"
fresh; bs_set_in "$D" 1 "$OLDB" "$CURB"; run_script admit "${ADMC[@]}" EFF_REBOOT_POST=true
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == true && "$(out_of "$D" boot_pre)" == abcd1234 ]] && ok "G2.12 converge: guard and fresh read agree on a POST: reboot_post stays true with the fresh boot_pre" || bad "G2.12 rc=$RC" "$OUT"
fresh; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"running\",\"finished\":null}]}" > "$D/state/actions.json"; run_script admit "${ADMC[@]}" EFF_REBOOT_POST=true
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false && "$(out_of "$D" boot_pre)" == abcd1234 ]] && ok "G2.13 converge: a reboot action started during the approval wait turns reboot_post to false (a second POST is never issued)" || bad "G2.13 rc=$RC" "$OUT"

printf '\n=== H. redeploy and the printed record ===\n'
RD=(EFF_MODE=rotate EFF_KEYS=both "EFF_ROTATED_AT=$((NOW0 - 3000))" EFF_BOOT_PRE=abcd1234 EFF_BOOT_NEW=beef5678 "EFF_POST_EPOCH=$((NOW0 - 1500))" "EFF_VERIFIED_AT=$((NOW0 - 1400))" "WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11" WEBHOOK_DEPLOY_SECRET=wh.fixture CF_ACCESS_CLIENT_ID=cfid.fixture CF_ACCESS_CLIENT_SECRET=cfsec.fixture)
fresh; run_script redeploy "${RD[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == rotate_ok && "$(nlog "$D/track.log" .)" == 1 ]] && grep -qx "track WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11 REDEPLOY_TIMEOUT_S=$B_REDEPLOY" "$D/track.log" && ok "H1 redeploy drives track.sh once with the full roster and the budget table's timeout (4800 s)" || bad "H1 rc=$RC" "$OUT"
grep -Eq '^S5-A5-DONE: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$OUT" && ok "H2 a green rotate prints the ready-to-paste S5-A5-DONE line (UTC time ending in Z) at the start of a line" || bad "H2 S5 line" "$OUT"
[[ "$ALL" == *"booleans: copies_equal=true new_boot_id_seen=true serving=true tls_listener=1"* && "$ALL" == *"actions/runs/9001"* && "$ALL" == *"rotated_at="* && "$ALL" == *"printed only"* ]] && ok "H3 the value-free evidence block carries timestamps, keys, booleans and the run URL, and says the line is printed only" || bad "H3 evidence" "$ALL"
[[ "$ALL" == *"boot_id_pre=abcd1234 boot_id_new=beef5678"* && "$ALL" == *"reboot_requested_at=$(iso_of $((NOW0 - 1500))) host_verified_at=$(iso_of $((NOW0 - 1400)))"* ]] && ok "H3b the evidence block carries the MEASURED values the reboot job passed on: the pre and new boot_id (8 hex), the reboot request time and the time verify passed" || bad "H3b measured values missing" "$ALL"
fresh; run_script redeploy EFF_MODE=rotate EFF_KEYS=both "WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11" WEBHOOK_DEPLOY_SECRET=wh.fixture CF_ACCESS_CLIENT_ID=cfid.fixture CF_ACCESS_CLIENT_SECRET=cfsec.fixture
[[ "$RC" == 0 && "$ALL" == *"new_boot_id_seen=unknown serving=unknown tls_listener=unknown"* && "$ALL" == *"boot_id_pre=unknown boot_id_new=unknown"* && "$ALL" != *"new_boot_id_seen=true"* ]] && ok "H3c with no measured host evidence the block says unknown, never a literal true (a booleans line is only as true as what the reboot job measured)" || bad "H3c literal booleans" "$ALL"
fresh; run_script redeploy "${RD[@]}" EFF_BOOT_PRE=beef5678
[[ "$RC" == 0 && "$ALL" == *"new_boot_id_seen=unknown"* ]] && ok "H3d a new boot_id equal to the pre-reboot one is not 'new': new_boot_id_seen stays unknown" || bad "H3d" "$ALL"
fresh; run_script redeploy EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- EFF_BOOT_NEW=beef5678 "EFF_VERIFIED_AT=$((NOW0 - 100))" "WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11" WEBHOOK_DEPLOY_SECRET=wh.fixture CF_ACCESS_CLIENT_ID=cfid.fixture CF_ACCESS_CLIENT_SECRET=cfsec.fixture
[[ "$RC" == 0 && "$ALL" == *"reboot_requested_at=none (no reboot request this run)"* && "$ALL" == *"new_boot_id_seen=true"* ]] && ok "H3e a converge with no POST this run prints 'none' for the request time and true for a measured new boot" || bad "H3e" "$ALL"
[[ "$(nlog "$D/gh.log" 'issue comment')" == 0 && "$(nlog "$D/gh.log" 'api')" == 0 && ! -e "$D/issues_created.log" ]] && ok "H4 nothing in the route POSTS the S5-A5-DONE line (no gh comment, no gh api, no issue on success)" || bad "H4 posted something" "$(cat "$D/gh.log")"
check "H5 the script has no gh issue comment / edit, gh api, gh gist, gh release, gh pr comment|review|merge or --method POST call (only a failure issue is ever created)" bash -c "! grep -Eq 'gh (issue (comment|edit)|api|gist|release|pr (comment|review|merge))|--method POST' < <(grep -v '^ *#' '$BODY')"
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
[[ "$RC" != 0 && ! -e "$D/track.log" && ! -e "$D/issues_created.log" ]] && ok "H11 redeploy refuses mode=plan (argument misuse: a plain refusal)" || bad "H11"
fresh; run_script redeploy "${RD[@]}" WEB_HOST_PRIVATE_IPS=
[[ "$RC" != 0 && ! -e "$D/track.log" && -s "$D/issues_created.log" && "$ALL" == *"STOP: do not retry"* ]] && ok "H9b an empty roster is a post-write failure: nothing dispatched, the stop sentence and one issue (apply2 already wrote)" || bad "H9b rc=$RC" "$OUT"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_web-platform-release.yml_in_progress.json"; run_script redeploy "${RD[@]}"
[[ "$RC" != 0 && -s "$D/issues_created.log" && "$ALL" == *"run converge once the release finishes"* ]] && ok "H10b the redeploy's in-flight refusal files the stop sentence ('run converge once the release finishes') and one issue" || bad "H10b" "$OUT"
fresh; run_script redeploy "${RD[@]}" GITHUB_RUN_ATTEMPT=2
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && ! -e "$D/track.log" && -s "$D/issues_created.log" ]] && ok "H12 redeploy refuses run_attempt=2 (Re-run failed jobs): no track.sh call, the stop sentence and one issue" || bad "H12 rc=$RC" "$OUT"
fresh; run_script redeploy "${RD[@]}" GITHUB_RUN_ATTEMPT=10
[[ "$RC" != 0 && "$(verdict_of)" == rerun_refused && ! -e "$D/track.log" ]] && ok "H12b ...and run_attempt=10" || bad "H12b rc=$RC" "$OUT"
fresh; run_script redeploy "${RD[@]}"
TRACK_T="$(sed -n 's/.*REDEPLOY_TIMEOUT_S=\([0-9]*\)$/\1/p' "$D/track.log")"
[[ "$TRACK_T" == "$B_CEILING" && "$TRACK_T" == "$B_REDEPLOY" ]] && ok "H13 track.sh is given the pipeline ceiling ($B_CEILING s) through KR_REDEPLOY_S, which is wired to KR_PIPELINE_CEILING_S" || bad "H13 timeout handed to track.sh: $TRACK_T"

printf '\n=== N. notify: the last job ===\n'
NT=(EFF_MODE=rotate EFF_KEYS=both EFF_RESULT_APPLY1=success EFF_RESULT_REBOOT=success EFF_RESULT_APPLY2=cancelled EFF_RESULT_REDEPLOY=skipped)
fresh; run_script notify "${NT[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == job_cancelled && "$(wc -l < "$D/issues_created.log" 2>/dev/null | tr -d ' ')" == 1 && "$ALL" == *"STOP: do not retry"* && "$ALL" == *"-f mode=converge -f keys=both"* && "$ALL" == *"apply2=cancelled"* ]] && ok "N1 a CANCELLED apply2 after a successful phase 1 leaves exactly ONE action-required issue (job_cancelled) with the stop sentence and the converge command" || bad "N1 rc=$RC" "$OUT"
fresh; printf '[{"title":"inngest-key-rotate apply_failed (run 9001)"}]' > "$D/state/issues.json"; run_script notify "${NT[@]}"
[[ "$RC" == 0 && ! -e "$D/issues_created.log" ]] && ok "N2 when an issue marked with this run id already exists (a job's own stop sentence), notify files nothing" || bad "N2 rc=$RC" "$OUT"
fresh; printf '[{"title":"inngest-key-rotate apply_failed (run 9002)"}]' > "$D/state/issues.json"; run_script notify "${NT[@]}"
[[ "$RC" != 0 && "$(wc -l < "$D/issues_created.log" | tr -d ' ')" == 1 ]] && ok "N2b an issue for ANOTHER run id does not count" || bad "N2b rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=rotate EFF_KEYS=both EFF_RESULT_APPLY1=skipped EFF_RESULT_REBOOT=skipped EFF_RESULT_APPLY2=skipped EFF_RESULT_REDEPLOY=skipped
[[ "$RC" == 0 && ! -e "$D/issues_created.log" ]] && ok "N3 a rotate whose first write job never ran (apply1 skipped) wrote nothing: no issue" || bad "N3 rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=rotate EFF_KEYS=signing EFF_RESULT_APPLY1=cancelled EFF_RESULT_REBOOT=skipped EFF_RESULT_APPLY2=skipped EFF_RESULT_REDEPLOY=skipped
[[ "$RC" != 0 && "$(wc -l < "$D/issues_created.log" | tr -d ' ')" == 1 && "$ALL" == *"Re-dispatch rotate with a fresh go; do not run converge"* && "$ALL" != *"-f mode=converge"* ]] && ok "N4 a CANCELLED apply1 (the write may have landed) files one issue whose recovery is re-dispatching rotate, not converge" || bad "N4 rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=rotate EFF_KEYS=both EFF_RESULT_APPLY1=success EFF_RESULT_REBOOT=success EFF_RESULT_APPLY2=success EFF_RESULT_REDEPLOY=success
[[ "$RC" == 0 && ! -e "$D/issues_created.log" ]] && ok "N5 a green redeploy needs no notice (defensive: the job condition already excludes it)" || bad "N5 rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=converge EFF_KEYS=both EFF_RESULT_APPLY1=skipped EFF_RESULT_REBOOT=failure EFF_RESULT_APPLY2=skipped EFF_RESULT_REDEPLOY=skipped
[[ "$RC" != 0 && "$(wc -l < "$D/issues_created.log" | tr -d ' ')" == 1 && "$ALL" == *"-f mode=converge"* ]] && ok "N6 converge: a failed reboot job (no stop sentence filed) files one issue; in converge mode the write jobs are reboot and apply2 (apply1 is always skipped)" || bad "N6 rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=converge EFF_KEYS=both EFF_RESULT_APPLY1=skipped EFF_RESULT_REBOOT=skipped EFF_RESULT_APPLY2=skipped EFF_RESULT_REDEPLOY=skipped
[[ "$RC" == 0 && ! -e "$D/issues_created.log" ]] && ok "N7 converge with no write job started files nothing" || bad "N7 rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=rotate EFF_KEYS=both EFF_RESULT_APPLY1=success 'EFF_RESULT_REBOOT=success;rm' EFF_RESULT_APPLY2=failure EFF_RESULT_REDEPLOY=skipped
[[ "$RC" != 0 && "$ALL" == *"reboot=unknown"* && "$ALL" != *";rm"* ]] && ok "N8 a result outside {success, failure, cancelled, skipped} is printed as 'unknown', never echoed" || bad "N8 rc=$RC" "$OUT"
fresh; run_script notify EFF_MODE=plan EFF_KEYS=both EFF_RESULT_APPLY1=success EFF_RESULT_REBOOT=skipped EFF_RESULT_APPLY2=skipped EFF_RESULT_REDEPLOY=skipped
[[ "$RC" == 0 && ! -e "$D/issues_created.log" ]] && ok "N9 notify has nothing to report for mode=plan" || bad "N9 rc=$RC" "$OUT"

NONMUT_N="$FRESH_N"   # every scenario dir up to here ran the REAL script: their refusal logs must be empty (section J)
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
 "drop_attempt": ("  kr_run_check run_attempt_is_1 kr_chk_attempt || return 1\n", ""),
 "drop_quiet": ("  kr_run_check quiet_window_attested kr_chk_quiet || return 1\n", ""),
 "drop_confirm": ("  kr_run_check confirm_ok kr_chk_confirm || return 1\n", ""),
 "drop_soak": ("  kr_run_check soak_closed_completed kr_chk_soak || { kr_guard_report; return 1; }\n", ""),
 "drop_serving": ("    rotate|plan) kr_run_check host_serving_pre_reboot kr_chk_serving || { kr_guard_report; return 1; } ;;", "    rotate|plan) : ;;"),
 "drop_latch": ("  if [[ \"$KR_POSTED\" == 1 ]]; then kr_refuse reboot_refused_second_post \"a second reboot POST in one run is refused\"; return 1; fi\n", ""),
 "drop_inflight_reboot": ("  kr_require_no_inflight_post || return 1\n  kr_resolve_server || {", "  kr_resolve_server || {"),
 "old_boot_ok": (("      [[ \"$pre\" == - || \"$boot\" != \"$pre\" ]] || continue\n", ""), ("( \"$pre\" == - || \"$KR_HS_BOOT\" != \"$pre\" ) && ", "")),
 "no_listener": ("if [[ -n \"$KR_NEWBOOT\" && \"$KR_SERVE\" == yes && \"$KR_LISTEN\" == 1 ]]; then", "if [[ -n \"$KR_NEWBOOT\" && \"$KR_SERVE\" == yes ]]; then"),
 "no_valuecheck": ("    if [[ \"$now_h\" == \"${prior[$k]}\" ]]; then", "    if false; then"),
 "redeploy_ignored": ("  if ! WEB_HOST_PRIVATE_IPS=\"$WEB_HOST_PRIVATE_IPS\" REDEPLOY_TIMEOUT_S=\"$KR_REDEPLOY_S\" bash \"$KR_TRACK\"; then", "  WEB_HOST_PRIVATE_IPS=\"$WEB_HOST_PRIVATE_IPS\" REDEPLOY_TIMEOUT_S=\"$KR_REDEPLOY_S\" bash \"$KR_TRACK\"; if [[ 1 == 2 ]]; then"),
 "drop_host_unique": ("  [[ \"$KR_SERVER_ID\" == \"$sid\" ]] || { kr_post_write_failure host_not_unique", "  [[ 1 == 1 ]] || { kr_post_write_failure host_not_unique"),
 # ---- the CTO rulings (fork 2: converge / recovery; fork 3: attempt check and post-approval admission) and the review fixes
 "stop_converge": ("\"Phase 1 failed part-way.\" rotate", "\"Phase 1 failed part-way.\""),
 "src_walk": ("test(\"^inngest-key-rotate rotate (signing|event|both)$\"))]", "test(\"^inngest-key-rotate (rotate|converge) (signing|event|both)$\"))]"),
 "src_stale": ("  if (( now - KR_ROTATED_AT > KR_CONVERGE_MAX_AGE_S )); then", "  if false; then"),
 "recent_all": ("--argjson c \"$((now - KR_BOOT_WAIT_S))\"", "--argjson c 0"),
 "pre_dash": ("KR_VERIFY_AFTER=\"\"; KR_BOOT_PRE=\"${boot:--}\"", "KR_VERIFY_AFTER=\"\"; KR_BOOT_PRE=\"-\""),
 "after_off": ("  elif [[ \"${EFF_VERIFY_AFTER:-}\" =~ ^[0-9]+$ ]]; then", "  elif false; then"),
 "absent_app": ("    [[ \"$st\" == 1 ]] && return 1", "    :"),
 "inflight_pre_apply2": ("  klist=\"$(kr_keys_list \"$keys\")\"\n  kr_require_no_inflight_post || return 1\n  for k in", "  klist=\"$(kr_keys_list \"$keys\")\"\n  kr_require_no_inflight || return 1\n  for k in"),
 "inflight_pre_redeploy": ("  kr_require_first_attempt post || return 1\n  kr_require_no_inflight_post || return 1\n  [[ \"${WEB_HOST_PRIVATE_IPS:-}\"", "  kr_require_first_attempt post || return 1\n  kr_require_no_inflight || return 1\n  [[ \"${WEB_HOST_PRIVATE_IPS:-}\""),
 "attempt_apply1": ("  kr_require_first_attempt pre || return 1\n", ""),
 "attempt_reboot": ("reboot runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n  kr_require_first_attempt post || return 1\n", "reboot runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n"),
 "attempt_verify": ("verify runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n  kr_require_first_attempt post || return 1\n", "verify runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n"),
 "attempt_apply2": ("apply2 runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n  kr_require_first_attempt post || return 1\n", "apply2 runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n"),
 "attempt_redeploy": ("redeploy runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n  kr_require_first_attempt post || return 1\n", "redeploy runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n"),
 "attempt_admit": ("admit runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n  kr_require_first_attempt post || return 1\n", "admit runs for rotate and converge only\"; return 1; }\n  kr_init || return 1\n"),
 "attempt_glob": ("[[ \"${GITHUB_RUN_ATTEMPT:-}\" == 1 ]] && return 0;", "[[ \"${GITHUB_RUN_ATTEMPT:-}\" == 1* ]] && return 0;"),
 "attempt_default": ("[[ \"${GITHUB_RUN_ATTEMPT:-}\" == 1 ]] && return 0;", "[[ \"${GITHUB_RUN_ATTEMPT:-1}\" == 1 ]] && return 0;"),
 "confirm_glob": ("  [[ \"${INPUT_CONFIRM:-}\" == \"$want\" ]] && return 0", "  [[ \"${INPUT_CONFIRM:-}\" == \"$want\"* ]] && return 0"),
 "confirm_nocase": ("  [[ \"${INPUT_CONFIRM:-}\" == \"$want\" ]] && return 0", "  shopt -s nocasematch; [[ \"${INPUT_CONFIRM:-}\" == $want ]] && { shopt -u nocasematch; return 0; }; shopt -u nocasematch"),
 "admit_no_link": ("  kr_admit_do kr_chk_link || return 1\n", ""),
 "admit_no_inflight": ("  kr_admit_do kr_inflight_check || return 1\n", ""),
 "admit_no_server": ("  kr_admit_do kr_chk_same_server || return 1\n", ""),
 "admit_no_serving": ("    kr_admit_do kr_chk_serving || return 1\n", "    :\n"),
 "admit_false_to_true": ("    [[ \"$KR_REBOOT_POST\" == true ]] || post=false\n", "    post=\"$KR_REBOOT_POST\"\n"),
 "plan_agg_off": ("    if [[ -n \"$block\" ]]; then", "    if false; then"),
 "seam_off": ("if [[ \"${GITHUB_ACTIONS:-}\" == true ]]; then\n  for _kr_seam", "if false; then\n  for _kr_seam"),
 "epoch_first": ("  if [[ -n \"$given\" ]]; then\n    if [[ ! \"$given\" =~ ^[0-9]{4}", "  if [[ -n \"$given\" ]]; then\n    kr_epoch \"$given\" >/dev/null\n    if [[ ! \"$given\" =~ ^[0-9]{4}"),
 "classify_stderr": ("bs_read_classify \"$KR_BS_RC\" \"$KR_TMP/bs.out\"", "bs_read_classify \"$KR_BS_RC\" \"$KR_TMP/bs.err\""),
 "fault_sticky": (("    kr_poll_host \"$after\" \"$pre\"\n    now=\"$(kr_now)\"", "    kr_poll_host \"$after\" \"$pre\"; [[ \"$KR_READ_FAULT\" == 1 ]] && KR_STICKY=1\n    now=\"$(kr_now)\""), ("      if [[ \"$KR_READ_FAULT\" == 1 ]]; then\n        kr_post_write_failure host_read_failed \"no verdict: the last read failed", "      if [[ \"${KR_STICKY:-0}\" == 1 ]]; then\n        kr_post_write_failure host_read_failed \"no verdict: the last read failed")),
 "cap_off": ("timeout \"$(kr_cap 240)\" bash \"$KR_HOST_STATE\"", "timeout 240 bash \"$KR_HOST_STATE\""),
 "poll_count": ("    [[ \"$(kr_now)\" -lt \"$deadline\" ]] || break\n", "    [[ $((KR_I = ${KR_I:-0} + 1)) -lt 30 ]] || break\n"),
 "jq_rc_ignored": ("  if [[ \"$jrc\" != 0 ]]; then KR_BS_RC=65; : > \"$KR_TMP/tls.tsv\"; return 1; fi", "  :"),
 "evidence_literal": ("  url=\"${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0}\"\n  {\n    printf '### Evidence", "  seen=true; serving=true; listener=1\n  url=\"${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0}\"\n  {\n    printf '### Evidence"),
 "notify_no_marker": ("  if [[ \"$n\" != 0 ]]; then kr_log \"inngest-key-rotate: an action-required issue for this run already exists; not filing another\"; return 0; fi", "  :"),
 "notify_skipped_writes": ("    case \"$a1\" in success|failure|cancelled) wrote=1 ;; esac", "    case \"$a1\" in success|failure|cancelled|skipped) wrote=1 ;; esac"),
 "notify_green_files": ("  [[ \"$rd\" != success ]] || return 0\n", ""),
 "soak_issue": ("KR_SOAK_ISSUE=11215", "KR_SOAK_ISSUE=11216"),
 "link_names_dev": ("names=\"$(doppler secrets --only-names -p soleur -c prd_terraform 2>/dev/null)\"", "names=\"$(doppler secrets --only-names -p soleur -c dev 2>/dev/null)\""),
 "link_get_dev": ("v=\"$(doppler secrets get INNGEST_LINK_TLS --plain -p soleur -c prd_terraform 2>/dev/null)\"", "v=\"$(doppler secrets get INNGEST_LINK_TLS --plain -p soleur -c dev 2>/dev/null)\""),
 "ro_token_dev": ("t=\"$(doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform 2>/dev/null)\"", "t=\"$(doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c dev 2>/dev/null)\""),
 "copy_cfg_dev": ("KR_COPY_CONFIG=\"prd\"", "KR_COPY_CONFIG=\"dev\""),
 "copy_tier_a": ("h=\"$(DOPPLER_TOKEN=\"${DOPPLER_TOKEN_TF:-}\" doppler secrets get \"$name\"", "h=\"$(doppler secrets get \"$name\""),
 "inflight_drop_self": ("web-platform-release.yml inngest-key-rotate.yml)", "web-platform-release.yml)"),
 "reboot_nomask": ("  printf '::add-mask::%s\\n' \"$HCLOUD_TOKEN\"\n", ""),
 "gate_b_no_stop": ("kr_gate_plan B \"$bkeys\" b || { kr_post_write_stop \"$KR_VERDICT\" \"Phase 2 was refused before it applied anything: the dedicated copy is new and verified, the app copy is old or missing.\"; return 1; }", "kr_gate_plan B \"$bkeys\" b || return 1"),
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
[[ "$LANDED_N" == 68 && -z "$(grep NOLAND "$TMP/mutants.log")" ]] && ok "I0 all 68 script mutations landed exactly once (a mutation that matches nothing proves nothing)" || bad "I0 only $LANDED_N of 68 mutations landed" "$(grep NOLAND "$TMP/mutants.log")"
mpath() { echo "$MUTDIR/$1/scripts/inngest-key-rotate.sh"; }
with_script() { local m; m="$(mpath "$1")"; shift; RUN_SCRIPT="$m"; "$@"; RUN_SCRIPT="$BODY"; }
for md in "$MUTDIR"/*/; do m="$(basename "$md")"; bash -n "$(mpath "$m")" 2>/dev/null || bad "I0b mutant $m does not parse (a syntax error would make every scenario 'fail closed' vacuously)"; done
ok "I0b every mutated copy still parses (so a RED/GREEN flip is the guard's doing, not a syntax error's)"
# harness (a): the strict fakes REFUSE an unmodelled call (exit 64) and log it; otherwise "the refusal log is empty" proves nothing
fresh; PATH="$D/bin:$PATH" STUB="$D" doppler secrets get INNGEST_SIGNING_KEY --plain -p soleur -c dev >/dev/null 2>&1; R1=$?
PATH="$D/bin:$PATH" STUB="$D" DOPPLER_TOKEN=dp.fixture doppler secrets get INNGEST_LINK_TLS --plain -p soleur -c dev >/dev/null 2>&1; R2=$?
PATH="$D/bin:$PATH" STUB="$D" DOPPLER_TOKEN=dp.fixture doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c dev >/dev/null 2>&1; R3=$?
PATH="$D/bin:$PATH" STUB="$D" DOPPLER_TOKEN=dp.fixture doppler secrets get INNGEST_SIGNING_KEY --plain -p soleur -c prd >/dev/null 2>&1; R4=$?
PATH="$D/bin:$PATH" STUB="$D" gh issue view 11216 --repo acme/repo --json state,stateReason >/dev/null 2>&1; R5=$?
PATH="$D/bin:$PATH" STUB="$D" gh issue view 11215 --repo acme/other --json state,stateReason >/dev/null 2>&1; R6=$?
PATH="$D/bin:$PATH" STUB="$D" gh run list --repo acme/repo --workflow other.yml --status queued --limit 50 --json databaseId >/dev/null 2>&1; R7=$?
[[ "$R1 $R2 $R3 $R4 $R5 $R6 $R7" == "64 64 64 64 64 64 64" && "$(grep -c REFUSED "$D/refusals.log")" == 7 ]] && ok "I0c (harness) the strict fakes refuse (exit 64, logged) a copy read with a wrong config or the wrong token class, a link-flag or read-only-token read from -c dev, a wrong issue number, a wrong --repo and an unmodelled workflow: the empty-refusal-log assertion in section J can see a selector mutation" || bad "I0c strict fakes: $R1 $R2 $R3 $R4 $R5 $R6 $R7" "$(cat "$D/refusals.log")"
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
check "I15 the generic shapes are checked as well as the sentinels: a seeded 64-hex run and a 43-char base64url run are written (non-empty) for the detection check below" bash -c "printf '%s\n' '$S_HEX' > '$TMP/h1.txt' && printf '%s\n' '$S_B64' > '$TMP/h2.txt' && [ -s '$TMP/h1.txt' ] && [ -s '$TMP/h2.txt' ]"
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

# ---- the CTO rulings, the review fixes: each rule's mutation turns its scenario from "stops" to "proceeds" ----
fresh; printf '1' > "$D/state/apply_rc"; with_script stop_converge run_script apply1 "${APPLY_ROT[@]}"
[[ "$ALL" != *"$REDISPATCH"* && "$ALL" == *"-f mode=converge"* ]] && ok "I39 (fork 2 i) a stop sentence that names converge after a FAILED phase 1 is visible: F19 turns RED (the sentence loses the re-dispatch wording and gains the converge command)" || bad "I39" "$ALL"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; with_script src_walk run_script guard "${G_CONVERGE[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == run_list_unreadable ]] && ok "I40 (fork 2 ii) a source selector that admits converge-titled runs picks run 8500 (no jobs): D37/D37b turn RED" || bad "I40 rc=$RC verdict=$(verdict_of)" "$OUT"
fresh; conv_fixture $((NOW0 - 90000)); bs_set_in "$D" 1 "$OLDB" "$CURB"; with_script src_stale run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I41 (fork 2 ii) without the age bound a 25-hour-old rotation is accepted as the unfinished one (so D52 can see it)" || bad "I41 rc=$RC" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"success\",\"finished\":\"$(iso_of $((NOW0 - 2000)))\"}]}" > "$D/state/actions.json"
with_script recent_all run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == false ]] && ok "I42 (fork 2 ii) if ANY finished reboot action blocks the POST, a host that never restarted (host_silent) is never rebooted again: D41 turns RED" || bad "I42 rc=$RC" "$OUT"
fresh; conv_fixture "$ROT"; bs_set_in "$D" 1 "$OLDB" "$CURB"; printf '%s' "{\"actions\":[{\"id\":5,\"command\":\"reboot_server\",\"status\":\"running\",\"finished\":null}]}" > "$D/state/actions.json"
with_script pre_dash run_script guard "${G_CONVERGE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" boot_pre)" == "-" ]] && ok "I43 (fork 2 ii) a '-' boot_pre while a reboot is in progress would let the OLD boot's rows pass verify: D39 turns RED" || bad "I43" "$OUT"
fresh; hs_set_in "$D" 1 0 beef5678 yes $((NOW0 - 300)); bs_set_in "$D" 1 "$(bs_row $((NOW0 - 200)) beef5678 1)"
with_script after_off run_script verify EFF_MODE=converge EFF_KEYS=both EFF_BOOT_PRE=- "EFF_VERIFY_AFTER=$((NOW0 - 100))" "EFF_ROTATED_AT=$((NOW0 - 3600))" "${BSV[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == reboot_ok ]] && ok "I44 (fork 2 ii) if verify ignores verify_after and falls back to rotated_at, rows from before the new boot began pass (G35 turns RED)" || bad "I44" "$OUT"
fresh; after_phase1; rm -f "$D/state/copy_app_signing" "$D/state/copy_app_event"; printf '%s' "$PRD_RECOVERY" > "$D/state/plan_override_b"; with_script absent_app run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && "$(verdict_of)" == copy_unreadable ]] && ok "I45 (fork 2 iii) without the absent-vs-unreadable split an absent app secret is copy_unreadable and Gate B's recovery shape is unreachable (F35 turns RED)" || bad "I45 rc=$RC" "$OUT"
fresh; after_phase1; printf '[{"databaseId":7}]' > "$D/state/inflight_inngest-link-flip.yml_in_progress.json"; with_script inflight_pre_apply2 run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && ! -s "$D/issues_created.log" && "$ALL" != *"run converge once the release finishes"* ]] && ok "I46 (fork 2 iv) the pre-write in-flight refusal in apply2 says 'nothing was written' and files no issue (F34b turns RED)" || bad "I46" "$OUT"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_web-platform-release.yml_in_progress.json"; with_script inflight_pre_redeploy run_script redeploy "${RD[@]}"
[[ "$RC" != 0 && ! -s "$D/issues_created.log" ]] && ok "I47 (fork 2 iv) the pre-write in-flight refusal in redeploy files no issue (H10b turns RED)" || bad "I47" "$OUT"
for sub in apply1 reboot verify apply2 redeploy admit; do
  fresh; after_phase1
  case "$sub" in
    apply1) with_script attempt_apply1 run_script apply1 "${APPLY_ROT[@]}" GITHUB_RUN_ATTEMPT=2; PROCEEDED="$([[ -e "$D/tf.log" ]] && echo yes)" ;;
    reboot) with_script attempt_reboot run_script reboot "${RB[@]}" GITHUB_RUN_ATTEMPT=2; PROCEEDED="$([[ "$(npost)" == 1 ]] && echo yes)" ;;
    verify) hs_set_in "$D" 1 0 beef5678 yes $((NOW0 + 200)); bs_set_in "$D" 1 "$OLDROW" "$(bs_row $((NOW0 + 150)) beef5678 1)"; with_script attempt_verify run_script verify "${VF[@]}" GITHUB_RUN_ATTEMPT=2; PROCEEDED="$([[ "$RC" == 0 ]] && echo yes)" ;;
    apply2) with_script attempt_apply2 run_script apply2 "${APPLY_2[@]}" GITHUB_RUN_ATTEMPT=2; PROCEEDED="$([[ "$(nlog "$D/tf.log" '^apply b')" == 1 ]] && echo yes)" ;;
    redeploy) with_script attempt_redeploy run_script redeploy "${RD[@]}" GITHUB_RUN_ATTEMPT=2; PROCEEDED="$([[ -e "$D/track.log" ]] && echo yes)" ;;
    admit) with_script attempt_admit run_script admit "${ADM[@]}" GITHUB_RUN_ATTEMPT=2; PROCEEDED="$([[ "$RC" == 0 ]] && echo yes)" ;;
  esac
  [[ "$PROCEEDED" == yes ]] && ok "I48-$sub (fork 3) without the attempt check in $sub a Re-run of failed jobs (run_attempt=2) PROCEEDS with its write/read (so the $sub attempt row can see it)" || bad "I48-$sub the mutant did not proceed" "$OUT"
done
fresh; with_script attempt_glob run_script guard "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=10
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I49 an attempt comparison that is a prefix glob (== 1*) lets run_attempt=10 through (D7a turns RED)" || bad "I49"
fresh; with_script attempt_default run_script guard "${G_ROTATE[@]}" GITHUB_RUN_ATTEMPT=
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I50 an attempt that defaults to 1 when unset lets an empty run_attempt through (D7c turns RED)" || bad "I50"
fresh; with_script confirm_glob run_script guard "${G_ROTATE[@]}" "INPUT_CONFIRM=ROTATE-INNGEST-BOTH-$TODAY-X"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I51 a prefix-glob confirm comparison accepts a trailing suffix (D8a turns RED)" || bad "I51"
fresh; with_script confirm_nocase run_script guard "${G_ROTATE[@]}" "INPUT_CONFIRM=rotate-inngest-both-$TODAY"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I52 a case-insensitive confirm comparison accepts a lower-case confirm (D8b turns RED)" || bad "I52 rc=$RC" "$OUT"
fresh; printf 'pending:1700000000' > "$D/state/link"; with_script admit_no_link run_script admit "${ADM[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == admit_ok ]] && ok "I53 (fork 3) without the admit link-flag re-check a flag flipped during the approval wait is admitted (G2.3 turns RED)" || bad "I53"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_web-platform-release.yml_queued.json"; with_script admit_no_inflight run_script admit "${ADM[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == admit_ok ]] && ok "I54 (fork 3) without the admit in-flight re-check a release queued during the approval wait is admitted (G2.4 turns RED)" || bad "I54"
fresh; printf '%s' '{"servers":[{"id":9999,"name":"soleur-inngest","private_net":[{"ip":"10.0.1.40"}]}]}' > "$D/state/servers.json"; with_script admit_no_server run_script admit "${ADM[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == admit_ok ]] && ok "I55 (fork 3) without the admit server-identity re-check a changed server id is admitted (G2.5 turns RED)" || bad "I55"
fresh; hs_set_in "$D" 1 0 abcd1234 no $((NOW0 - 60)); with_script admit_no_serving run_script admit "${ADM[@]}"
[[ "$RC" == 0 && "$(verdict_of)" == admit_ok && "$(out_of "$D" boot_pre)" == "-" ]] && ok "I56 (fork 3) without the admit serving read a NOT SERVING host is admitted with no fresh boot_pre (G2.6 and G2.2 turn RED)" || bad "I56"
fresh; bs_set_in "$D" 1 "$OLDB" "$CURB"; with_script admit_false_to_true run_script admit "${ADMC[@]}" EFF_REBOOT_POST=false
[[ "$RC" == 0 && "$(out_of "$D" reboot_post)" == true ]] && ok "I57 (fork 3) if admit may turn the guard's reboot_post from false to true, a converge the guard decided NOT to POST would POST (G2.11 turns RED)" || bad "I57"
fresh; with_script plan_agg_off run_script apply1 "${APPLY_PLAN[@]}" EFF_PLAN_BLOCK=link_flag_is_1:link_flag_pending
[[ "$RC" == 0 && "$(verdict_of)" == plan_ok ]] && ok "I58 (A) without the plan aggregate a plan with a failed admission check ends verdict=plan_ok (F6a turns RED)" || bad "I58"
seam_with() { env -i PATH="$PATH" GITHUB_ACTIONS=true KR_NOW=/bin/true bash "$(mpath "$1")" --print-contract 2>&1 | head -1; }
[[ "$(seam_with seam_off)" == "inngest-key-rotate verdict-tokens" && "$(seam_with seam_off | head -c1)" != "[" ]] && ok "I59 (D) without the seam refusal KR_NOW under GITHUB_ACTIONS=true is accepted (D2.1 turns RED)" || bad "I59 seam still refused: $(seam_with seam_off)"
epoch_order_ok() { local a b; a="$(grep -n -F '[[ ! "$given" =~ ^[0-9]{4}' "$1" | head -1 | cut -d: -f1)"; b="$(grep -n -F 'kr_epoch "$given"' "$1" | head -1 | cut -d: -f1)"; [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]; }
epoch_order_ok "$BODY" && ! epoch_order_ok "$(mpath epoch_first)" && ok "I60 (D) kr_epoch of the free-text rotated_at before its shape check is flagged by the order check (B24 turns RED)" || bad "I60"
fresh; hs_set_in "$D" 1 6 x yes 0; printf '22' > "$D/state/bs_1.rc"; printf 'CLUSTER_DOESNT_EXIST' > "$D/state/bs_1.jsonl"; with_script classify_stderr run_script verify "${VF[@]}"
[[ "$ALL" == *"class other"* && "$ALL" != *"class source-not-in-connection"* ]] && ok "I61 (B) classifying from stderr instead of the response body reads CLUSTER_DOESNT_EXIST as 'other' (G31 turns RED)" || bad "I61" "$ALL"
fresh; hs_set_in "$D" 1 4 x yes 0; printf '1' > "$D/state/bs_1.rc"; : > "$D/state/bs_1.jsonl"; bs_set_in "$D" 2 "$OLDROW"; with_script fault_sticky run_script verify "${VF[@]}"
[[ "$(verdict_of)" == host_read_failed ]] && ok "I62 (C) a sticky fault flag turns one early transient fault into host_read_failed although the final poll saw clean silence (G30 turns RED)" || bad "I62: $(verdict_of)"
fresh; hs_set_in "$D" 1 0 beef5678 no $((NOW0 + 200)); bs_set_in "$D" 1 "$(bs_row $((NOW0 + 150)) beef5678 1)"; printf '200' > "$D/state/hs_adv"
with_script cap_off run_script verify "${VF[@]}"
CAP_VIOL2="$(awk -v end=$((NOW0 + B_VERIFY_STEP - B_MARGIN)) '/hoststate.sh|bsquery.sh/ { if ($1 + $2 > end + 1) n++ } END { print n + 0 }' "$D/timeout.log")"
[[ "$CAP_VIOL2" -ge 1 ]] && ok "I63 (C) with the read caps removed a read starts that cannot finish inside the verify step ($CAP_VIOL2 violation: G34 turns RED)" || bad "I63 no violation without the cap"
fresh; printf 'running' > "$D/state/action_status"; printf '25' > "$D/state/get_adv"; with_script poll_count run_script reboot "${RB[@]}"; EL=$(( $(cat "$D/state/now") - NOW0 ))
[[ "$EL" -gt 340 ]] && ok "I64 (C) a count-bounded action poll (30 polls x 35 s) overruns the 10-minute step (elapsed ${EL}s: G7b turns RED)" || bad "I64 elapsed=$EL"
fresh; hs_set_in "$D" 1 4 x yes 0; bs_set_in "$D" 1 "$OLDROW"; : > "$D/state/jq_fail_tls"; with_script jq_rc_ignored run_script verify "${VF[@]}"
[[ "$(verdict_of)" == host_silent ]] && ok "I65 (C) ignoring jq's exit status turns an unparseable tls-health result into 'no rows' = host_silent (G33 turns RED)" || bad "I65: $(verdict_of)"
fresh; with_script evidence_literal run_script redeploy EFF_MODE=rotate EFF_KEYS=both "WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11" WEBHOOK_DEPLOY_SECRET=wh.fixture CF_ACCESS_CLIENT_ID=cfid.fixture CF_ACCESS_CLIENT_SECRET=cfsec.fixture
[[ "$ALL" == *"new_boot_id_seen=true serving=true tls_listener=1"* ]] && ok "I66 (C) a literal-true evidence line prints true with no measured host evidence at all (H3c turns RED)" || bad "I66" "$ALL"
fresh; printf '[{"title":"inngest-key-rotate apply_failed (run 9001)"}]' > "$D/state/issues.json"; with_script notify_no_marker run_script notify "${NT[@]}"
[[ "$(wc -l < "$D/issues_created.log" 2>/dev/null | tr -d ' ')" == 1 ]] && ok "I67 without the run-id marker check notify files a SECOND issue for a run that already has one (N2 turns RED)" || bad "I67"
fresh; with_script notify_skipped_writes run_script notify EFF_MODE=rotate EFF_KEYS=both EFF_RESULT_APPLY1=skipped EFF_RESULT_REBOOT=skipped EFF_RESULT_APPLY2=skipped EFF_RESULT_REDEPLOY=skipped
[[ -s "$D/issues_created.log" ]] && ok "I68 counting a skipped apply1 as a write makes notify file an issue for a run that wrote nothing (N3 turns RED)" || bad "I68"
fresh; with_script notify_green_files run_script notify EFF_MODE=rotate EFF_KEYS=both EFF_RESULT_APPLY1=success EFF_RESULT_REBOOT=success EFF_RESULT_APPLY2=success EFF_RESULT_REDEPLOY=success
[[ -s "$D/issues_created.log" ]] && ok "I69 without the green-redeploy exit notify files an issue for a successful rotation (N5 turns RED)" || bad "I69"
fresh; after_phase1; touch "$D/state/apply_noeffect"; printf '%s' '[{"address":"doppler_secret.inngest_signing_key_dedicated","mode":"managed","change":{"actions":["update"]}}]' > "$D/state/plan_extra_b"; with_script gate_b_no_stop run_script apply2 "${APPLY_2[@]}"
[[ "$RC" != 0 && ! -s "$D/issues_created.log" ]] && ok "I70 a Gate B refusal in apply2 without the post-write stop leaves NO issue although phase 1 landed (F37c turns RED)" || bad "I70"
# selector mutations: the strict fakes refuse a wrong project / config / token class / issue number, so the read FAILS (exit 64, logged)
sel_red() { [[ "$RC" != 0 && -s "$D/refusals.log" ]]; }
fresh; with_script soak_issue run_script guard "${G_ROTATE[@]}"
sel_red && [[ "$(verdict_of)" == soak_unreadable ]] && ok "I71 reading tracker #11216 instead of #11215 is refused by the strict gh fake and the guard cannot pass (the fake keys on the issue number)" || bad "I71 rc=$RC verdict=$(verdict_of)"
fresh; with_script link_names_dev run_script guard "${G_ROTATE[@]}"
sel_red && [[ "$(verdict_of)" == link_flag_unreadable ]] && ok "I72 listing the link flag's names from -c dev is refused by the strict doppler fake" || bad "I72 rc=$RC verdict=$(verdict_of)"
fresh; with_script link_get_dev run_script guard "${G_ROTATE[@]}"
sel_red && [[ "$(verdict_of)" == link_flag_unreadable ]] && ok "I73 reading the link flag from -c dev is refused by the strict doppler fake" || bad "I73 rc=$RC verdict=$(verdict_of)"
fresh; with_script ro_token_dev run_script guard "${G_ROTATE[@]}"
sel_red && [[ "$(verdict_of)" == credential_absent ]] && ok "I74 reading the read-only Hetzner token from -c dev is refused by the strict doppler fake" || bad "I74 rc=$RC verdict=$(verdict_of)"
fresh; with_script copy_cfg_dev run_script apply1 "${APPLY_ROT[@]}"
sel_red && [[ "$(verdict_of)" == copy_unreadable ]] && ok "I75 reading the key copies from -c dev instead of -c prd is refused by the strict doppler fake" || bad "I75 rc=$RC verdict=$(verdict_of)"
fresh; with_script copy_tier_a run_script apply1 "${APPLY_ROT[@]}"
sel_red && [[ "$(verdict_of)" == copy_unreadable ]] && ok "I76 reading the key copies with the Tier-A token instead of the Terraform token is refused by the strict doppler fake" || bad "I76 rc=$RC verdict=$(verdict_of)"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_inngest-key-rotate.yml_in_progress.json"; with_script inflight_drop_self run_script guard "${G_ROTATE[@]}"
[[ "$RC" == 0 && "$(out_of "$D" go)" == true ]] && ok "I77 without inngest-key-rotate.yml in the in-flight list another rotation run in progress does not stop the guard (D-row below turns RED)" || bad "I77"
fresh; printf '[{"databaseId":7}]' > "$D/state/inflight_inngest-key-rotate.yml_in_progress.json"; refuse_row D23b "ANOTHER inngest-key-rotate run in flight (not the guard's own id)" run_in_flight "${G_ROTATE[@]}"
fresh; with_script reboot_nomask run_script reboot "${RB[@]}"
[[ "$OUT" != *"::add-mask::$WRITE_TOK"* ]] && ok "I78 without the add-mask line the Hetzner write token is not masked in the log (G3b turns RED)" || bad "I78"
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
# harness (b) must-PASS: the real workflow is clean, and so is the plan re-run
[[ -z "$(graph_violations "$WF")" ]] && ok "I36 (G4 harness b) the graph check reports nothing on the real workflow (it is not a checker that flags everything)" || bad "I36"
# the harness rows for the static scans: they must flag the mutants and pass the original
check "I37 the static scans are not vacuous: the original script has 0 bare terraform verbs and 1 call site, the mutants 1+ and 2" bash -c "[ '$TF_CALLS' = 1 ]"
check "I38 the second POST site is visible to the static check (B12): the mutant has 2, the original 1" bash -c "[ \"\$(grep -v '^ *#' '$(mpath second_post_site)' | grep -c 'kr_hz POST')\" = 2 ] && [ \"\$(grep -v '^ *#' '$BODY' | grep -c 'kr_hz POST')\" = 1 ]"
STREAMS_FILE=""

printf '\n=== K. cross-file drift ===\n'
GUARD_OUTS="$(yq 'sorted(jobs["guard"]["outputs"].keys())' | tr -d "[]',")"
SCRIPT_OUTS="$(sed -n '/^kr_cmd_guard()/,/^kr_cmd_apply1()/p' "$BODY" | grep -Eo 'kr_out [a-z_0-9]+' | awk '{print $2}' | sort -u | tr '\n' ' ')"
[[ "$(tr ' ' '\n' <<<"$GUARD_OUTS" | grep . | sort | tr '\n' ' ')" == "$SCRIPT_OUTS" ]] && ok "K1 the guard job's declared outputs are exactly the outputs the guard subcommand writes ($SCRIPT_OUTS)" || bad "K1 guard outputs drift" "workflow: $GUARD_OUTS script: $SCRIPT_OUTS"
WF_EFF="$(yq 'sorted(set(k for j in jobs.values() for s in j["steps"] for k in s.get("env", {}) if k.startswith("EFF_")))' | tr -d "[]'," | tr -s ' ' '\n' | sort | tr '\n' ' ')"
SC_EFF="$(grep -v '^ *#' "$BODY" | grep -Eo 'EFF_[A-Z0-9_]+' | sort -u | tr '\n' ' ')"
[[ "$WF_EFF" == "$SC_EFF" ]] && ok "K2 every EFF_* variable a workflow step binds in env: is one the script reads, and vice versa ($SC_EFF)" || bad "K2 EFF_* drift" "workflow: $WF_EFF script: $SC_EFF"
WF_IN="$(grep -Eo 'INPUT_[A-Z_]+' "$WF" | sort -u | tr '\n' ' ')"
SC_IN="$(grep -Eo 'INPUT_[A-Z_]+' "$BODY" | sort -u | tr '\n' ' ')"
[[ "$WF_IN" == "$SC_IN" ]] && ok "K3 every INPUT_* variable the workflow binds is one the script reads, and vice versa" || bad "K3 INPUT_* drift" "workflow: $WF_IN script: $SC_IN"
# K4: the run-name is the ONE source of the title the two consumers match. Render it for each mode and match the consumers' own regexes,
# extracted from their source (the link flip's off-after-rotation count, the converge derivation).
RN="$(yq 'd["run-name"]')"
render_title() { sed -e "s/\${{ inputs.mode }}/$1/" -e 's/${{ inputs.keys }}/both/' <<<"${RN_OVERRIDE:-$RN}"; }
FLIP_RE="$(grep -o 'test("^inngest-key-rotate plan[^"]*")' "$REPO_ROOT/scripts/inngest-link-flip.sh" | head -1 | sed -e 's/^test("//' -e 's/")$//')"
KR_RE="$(grep -o 'test("^inngest-key-rotate rotate[^"]*")' "$BODY" | head -1 | sed -e 's/^test("//' -e 's/")$//')"
title_matches() { jq -n -e --arg t "$1" --arg re "$2" '$t | test($re)' >/dev/null 2>&1 && echo yes || echo no; }
k4_rows() { for m in plan rotate converge; do printf '%s:flip=%s,kr=%s ' "$m" "$(title_matches "$(render_title $m)" "$FLIP_RE")" "$(title_matches "$(render_title $m)" "$KR_RE")"; done; }
K4_ROWS="$(k4_rows)"
[[ -n "$FLIP_RE" && -n "$KR_RE" && "$K4_ROWS" == "plan:flip=yes,kr=no rotate:flip=no,kr=yes converge:flip=no,kr=no " ]] && ok "K4 the REAL run-name rendered for each mode ('$(render_title plan)', ...) is matched by the link flip's plan regex only for plan (so rotate and converge runs count as rotations) and by the converge derivation's rotate regex only for rotate: $K4_ROWS" || bad "K4 run-name vs consumers" "flip='$FLIP_RE' kr='$KR_RE' rows=$K4_ROWS"
K4_MUT="$(RN_OVERRIDE='Inngest Key Rotate ${{ inputs.keys }} ${{ inputs.mode }}' k4_rows)"
[[ "$K4_MUT" != "$K4_ROWS" ]] && ok "K4b (mutation) a changed run-name (second word no longer the mode) changes what the two consumers match: K4 turns RED" || bad "K4b run-name mutation invisible: $K4_MUT"
# K5: every output a job reads from another job is declared by that job, and every step output it reads is written by that step's subcommand
K5_BAD="$(python3 - "$WF" "$BODY" <<'PY'
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1])); txt = open(sys.argv[1]).read(); body = open(sys.argv[2]).read()
jobs = d["jobs"]; bad = []
for j, k in re.findall(r"needs\.([a-z0-9]+)\.outputs\.([a-z_0-9]+)", txt):
    if k not in (jobs[j].get("outputs") or {}): bad.append("needs.%s.outputs.%s" % (j, k))
def kr_outs(start, end):
    m = re.search(r"^%s\(\) \{.*?^%s" % (start, end), body, re.S | re.M)
    return set(re.findall(r"kr_out ([a-z_0-9]+)", m.group(0))) if m else set()
written = {"guard": kr_outs("kr_cmd_guard", "kr_cmd_apply1"), "admit": kr_outs("kr_cmd_admit", "kr_cmd_reboot"),
           "post": kr_outs("kr_cmd_reboot", "# kr_poll_host"), "verify": kr_outs("kr_cmd_verify", "# APPLY 2")}
for sid, k in re.findall(r"steps\.([a-z]+)\.outputs\.([a-z_0-9]+)", txt):
    if k not in written.get(sid, set()): bad.append("steps.%s.outputs.%s" % (sid, k))
print(" ".join(sorted(set(bad))))
PY
)"
[[ -z "$K5_BAD" ]] && ok "K5 every needs.<job>.outputs.<x> the workflow reads is declared by that job, and every steps.<id>.outputs.<x> is written (kr_out) by that step's subcommand" || bad "K5 undeclared output read: $K5_BAD"

printf '\n=== W. the workflow as a program: evaluated job conditions, exact permissions / env / allow-lists, executed allow-lists ===\n'
cat > "$TMP/wfcheck.py" <<'PY'
# wfcheck.py <workflow.yml> <gout-dir> <expected-matrix-file|-> : prints one violation token per line (nothing = conformant);
# with expected "-" prints the job matrix instead. The job conditions are EVALUATED by a small GitHub-expression evaluator
# (|| && ! == != parentheses, string literals, contexts, always() / cancelled() / failure() / success()), never matched as text.
import re, sys, yaml
wf, gdir, expf = sys.argv[1], sys.argv[2], sys.argv[3]
d = yaml.safe_load(open(wf)); jobs = d["jobs"]; text = open(wf).read(); viol = []
ORDER = ["guard", "apply1", "reboot", "apply2", "redeploy", "notify"]
STATUS = {"always", "cancelled", "failure", "success"}

def tokenize(src):
    toks, i = [], 0
    while i < len(src):
        c = src[i]
        if c.isspace(): i += 1; continue
        if src[i:i+2] in ("&&", "||", "==", "!="): toks.append(src[i:i+2]); i += 2; continue
        if c in "()!": toks.append(c); i += 1; continue
        if c == "'": j = src.index("'", i + 1); toks.append(("s", src[i+1:j])); i = j + 1; continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_.\-]*", src[i:])
        if not m: raise ValueError("unexpected %r" % c)
        toks.append(("i", m.group(0))); i += len(m.group(0))
    return toks

class P:
    def __init__(s, toks, ctx): s.t, s.k, s.ctx, s.used = toks, 0, ctx, set()
    def peek(s): return s.t[s.k] if s.k < len(s.t) else None
    def eat(s): v = s.t[s.k]; s.k += 1; return v
    def parse(s):
        v = s.o()
        if s.peek() is not None: raise ValueError("trailing")
        return v
    def o(s):
        v = s.a()
        while s.peek() == "||": s.eat(); r = s.a(); v = v if v else r
        return v
    def a(s):
        v = s.e()
        while s.peek() == "&&": s.eat(); r = s.e(); v = r if v else v
        return v
    def e(s):
        v = s.u()
        if s.peek() in ("==", "!="):
            op = s.eat(); r = s.u(); eq = str(v).lower() == str(r).lower(); return eq if op == "==" else not eq
        return v
    def u(s):
        if s.peek() == "!": s.eat(); return not s.u()
        return s.p()
    def p(s):
        t = s.eat()
        if t == "(": v = s.o(); assert s.eat() == ")"; return v
        if isinstance(t, tuple) and t[0] == "s": return t[1]
        if isinstance(t, tuple) and t[0] == "i":
            if s.peek() == "(":
                s.eat(); assert s.eat() == ")"; s.used.add(t[1]); return s.ctx["fn"](t[1])
            return s.ctx["var"](t[1])
        raise ValueError("bad token %r" % (t,))

def run_matrix(scn):
    res = {}; outs = {}
    for j in ORDER:
        needs = jobs[j].get("needs", []); needs = [needs] if isinstance(needs, str) else list(needs)
        def var(name, _n=needs):
            if name == "github.event_name": return scn["event"]
            if name in ("true", "false"): return name == "true"
            m = re.fullmatch(r"needs\.([a-z0-9]+)\.result", name)
            if m: return res.get(m.group(1), "skipped")
            m = re.fullmatch(r"needs\.([a-z0-9]+)\.outputs\.([a-z_0-9]+)", name)
            if m: return outs.get(m.group(1), {}).get(m.group(2), "")
            raise ValueError("unknown context " + name)
        def fn(name, _n=needs):
            if name == "always": return True
            if name == "cancelled": return False
            if name == "success": return all(res.get(n) == "success" for n in _n)
            if name == "failure": return any(res.get(n) in ("failure",) for n in _n)
            raise ValueError("unknown function " + name)
        cond = jobs[j].get("if")
        try:
            if cond is None: ok, used = True, set()
            else:
                src = str(cond).strip()
                m = re.fullmatch(r"\$\{\{(.*)\}\}", src, re.S)
                p = P(tokenize(m.group(1) if m else src), {"var": var, "fn": fn}); ok = bool(p.parse()); used = p.used
        except Exception as e:
            viol.append("unevaluable:%s:%s" % (j, e)); ok, used = False, set()
        implicit = not (used & STATUS)
        if implicit and not all(res.get(n) == "success" for n in needs): ok = False
        if j == "guard" and scn.get("guard_result"): res[j] = scn["guard_result"] if ok else "skipped"
        else: res[j] = scn.get("force", {}).get(j, "success") if ok else "skipped"
        if j == "guard" and res[j] != "skipped": outs[j] = scn["gout"]
    return res

def gout(name):
    try: return dict(l.rstrip("\n").split("=", 1) for l in open("%s/%s" % (gdir, name)) if "=" in l)
    except OSError: return {}
SC = [
 ("plan", dict(event="workflow_dispatch", gout=gout("gout-plan"))),
 ("rotate", dict(event="workflow_dispatch", gout=gout("gout-rotate"))),
 ("converge", dict(event="workflow_dispatch", gout=gout("gout-converge"))),
 ("rotate/apply1-fails", dict(event="workflow_dispatch", gout=gout("gout-rotate"), force={"apply1": "failure"})),
 ("rotate/reboot-fails", dict(event="workflow_dispatch", gout=gout("gout-rotate"), force={"reboot": "failure"})),
 ("rotate/apply2-cancelled", dict(event="workflow_dispatch", gout=gout("gout-rotate"), force={"apply2": "cancelled"})),
 ("rotate/redeploy-fails", dict(event="workflow_dispatch", gout=gout("gout-rotate"), force={"redeploy": "failure"})),
 ("converge/reboot-fails", dict(event="workflow_dispatch", gout=gout("gout-converge"), force={"reboot": "failure"})),
 ("guard-refused", dict(event="workflow_dispatch", gout={"go": "false"}, guard_result="failure")),
 ("guard-ok-no-go", dict(event="workflow_dispatch", gout=dict(gout("gout-rotate"), go="false"))),
 ("guard-failed-late", dict(event="workflow_dispatch", gout=gout("gout-rotate"), guard_result="failure")),
 ("push", dict(event="push", gout={})),
]
table = []
for name, scn in SC:
    r = run_matrix(scn)
    table.append("%-24s %s" % (name, " ".join("%s=%s" % (j, r[j]) for j in ORDER)))
if expf == "-":
    print("\n".join(table)); sys.exit(0)
exp = open(expf).read().rstrip("\n").split("\n")
for got, want in zip(table, exp):
    if got != want: viol.append("matrix:" + got.split()[0])
if len(exp) != len(table): viol.append("matrix:rows")

# ---- exact permissions
RW = {"contents": "read", "actions": "read", "issues": "write"}
PERMS = {"guard": {"contents": "read", "actions": "read", "issues": "read"}, "apply1": RW, "reboot": RW, "apply2": RW, "redeploy": RW, "notify": {"issues": "write"}}
for j, want in PERMS.items():
    if jobs[j].get("permissions") != want: viol.append("perms:" + j)
if d.get("permissions") != {"contents": "read"}: viol.append("perms:workflow")
# ---- no continue-on-error, anywhere
if "continue-on-error" in text or any("continue-on-error" in j or any("continue-on-error" in s for s in j["steps"]) for j in jobs.values()): viol.append("continue-on-error")
# ---- every checkout drops its credentials
for j, jb in jobs.items():
    for s in jb["steps"]:
        if str(s.get("uses", "")).startswith("actions/checkout@") and (s.get("with") or {}).get("persist-credentials") is not False: viol.append("persist:" + j)
# ---- no expression in a run body; secrets only in the dotted form
for j, jb in jobs.items():
    for s in jb["steps"]:
        if "${{" in s.get("run", ""): viol.append("run-expr:" + j)
import json
if re.search(r"secrets(?!\.[A-Z][A-Z0-9_]*\b)", json.dumps(d)): viol.append("secrets-form")
# ---- the exact env of every run step, and the exact allow-list of every env -i step
G = lambda k: "${{ needs.guard.outputs.%s }}" % k
BS = {"BETTERSTACK_QUERY_HOST": "${{ secrets.BETTERSTACK_QUERY_HOST }}", "BETTERSTACK_QUERY_USERNAME": "${{ secrets.BETTERSTACK_QUERY_USERNAME }}", "BETTERSTACK_QUERY_PASSWORD": "${{ secrets.BETTERSTACK_QUERY_PASSWORD }}"}
TOK = "${{ github.token }}"; DP = "${{ secrets.DOPPLER_TOKEN }}"
ENV = {
 ("guard", "guard"): dict(INPUT_MODE="${{ inputs.mode }}", INPUT_KEYS="${{ inputs.keys }}", INPUT_CONFIRM="${{ inputs.confirm }}", INPUT_REASON="${{ inputs.reason }}", INPUT_ROTATED_AT="${{ inputs.rotated_at }}", INPUT_QUIET_WINDOW="${{ inputs.quiet_window }}", GH_TOKEN=TOK, DOPPLER_TOKEN=DP, **BS),
 ("apply1", "apply1"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), EFF_PLAN_BLOCK=G("plan_block"), GH_TOKEN=TOK, DOPPLER_TOKEN=DP),
 ("reboot", "admit"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), EFF_SERVER_ID=G("server_id"), EFF_ROTATED_AT=G("rotated_at"), EFF_REBOOT_POST=G("reboot_post"), GH_TOKEN=TOK, DOPPLER_TOKEN=DP, **BS),
 ("reboot", "reboot"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), EFF_SERVER_ID=G("server_id"), EFF_REBOOT_POST="${{ steps.admit.outputs.reboot_post }}", GH_TOKEN=TOK),
 ("reboot", "verify"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), EFF_BOOT_PRE="${{ steps.admit.outputs.boot_pre }}", EFF_VERIFY_AFTER="${{ steps.admit.outputs.verify_after }}", EFF_ROTATED_AT=G("rotated_at"), EFF_POST_EPOCH="${{ steps.post.outputs.post_epoch }}", GH_TOKEN=TOK, **BS),
 ("apply2", "apply2"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), GH_TOKEN=TOK, DOPPLER_TOKEN=DP),
 ("redeploy", "redeploy"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), EFF_ROTATED_AT=G("rotated_at"), EFF_BOOT_PRE="${{ needs.reboot.outputs.boot_pre }}", EFF_BOOT_NEW="${{ needs.reboot.outputs.boot_new }}", EFF_POST_EPOCH="${{ needs.reboot.outputs.post_epoch }}", EFF_VERIFIED_AT="${{ needs.reboot.outputs.verified_at }}", GH_TOKEN=TOK, WEBHOOK_DEPLOY_SECRET="${{ secrets.WEBHOOK_DEPLOY_SECRET }}", CF_ACCESS_CLIENT_ID="${{ secrets.CF_ACCESS_CLIENT_ID }}", CF_ACCESS_CLIENT_SECRET="${{ secrets.CF_ACCESS_CLIENT_SECRET }}"),
 ("notify", "notify"): dict(EFF_MODE=G("mode"), EFF_KEYS=G("keys"), EFF_RESULT_APPLY1="${{ needs.apply1.result }}", EFF_RESULT_REBOOT="${{ needs.reboot.result }}", EFF_RESULT_APPLY2="${{ needs.apply2.result }}", EFF_RESULT_REDEPLOY="${{ needs.redeploy.result }}", GH_TOKEN=TOK),
}
COMMON = "PATH HOME RUNNER_TEMP GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_REPOSITORY GITHUB_SERVER_URL GH_TOKEN".split()
ALLOW = {
 ("reboot", "admit"): set(COMMON + "DOPPLER_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD EFF_MODE EFF_KEYS EFF_SERVER_ID EFF_ROTATED_AT EFF_REBOOT_POST".split()),
 ("reboot", "reboot"): set(COMMON + "HCLOUD_TOKEN EFF_MODE EFF_KEYS EFF_SERVER_ID EFF_REBOOT_POST".split()),
 ("reboot", "verify"): set(COMMON + "BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD EFF_MODE EFF_KEYS EFF_BOOT_PRE EFF_VERIFY_AFTER EFF_ROTATED_AT EFF_POST_EPOCH".split()),
}
seen = set()
for j, jb in jobs.items():
    for s in jb["steps"]:
        if "run" not in s: continue
        sub = s["run"].strip().split("inngest-key-rotate.sh")[-1].strip()
        key = (j, sub); seen.add(key)
        if key not in ENV: viol.append("env:unknown-step:%s:%s" % key); continue
        if s.get("env") != ENV[key]: viol.append("env:%s:%s" % key)
        if key in ALLOW:
            names = set(re.findall(r'\b([A-Za-z][A-Za-z0-9_]*)="\$[A-Za-z{]', s["run"]))
            selfref = all(re.search(r'\b%s="\$%s"' % (n, n), s["run"]) for n in names if n not in ("PATH",)) 
            if names != ALLOW[key] or not selfref: viol.append("allow:%s:%s" % key)
if seen != set(ENV): viol.append("env:steps-missing")
# ---- the reboot job's steps carry no status function (a failed admit must skip the POST and the verify), the POST is driven by ADMIT
for s in jobs["reboot"]["steps"]:
    if re.search(r"\b(always|failure|cancelled|success)\s*\(", str(s.get("if", ""))): viol.append("stepif")
post = next(s for s in jobs["reboot"]["steps"] if s.get("id") == "post")
if post.get("if") != "${{ steps.admit.outputs.reboot_post == 'true' }}": viol.append("postif")
for j in ("notify",):
    if "concurrency" in jobs[j]: viol.append("notify-concurrency")
print("\n".join(sorted(set(viol))))
PY
cat > "$TMP/matrix.expected" <<'EOF'
plan                     guard=success apply1=success reboot=skipped apply2=skipped redeploy=skipped notify=skipped
rotate                   guard=success apply1=success reboot=success apply2=success redeploy=success notify=skipped
converge                 guard=success apply1=skipped reboot=success apply2=success redeploy=success notify=skipped
rotate/apply1-fails      guard=success apply1=failure reboot=skipped apply2=skipped redeploy=skipped notify=success
rotate/reboot-fails      guard=success apply1=success reboot=failure apply2=skipped redeploy=skipped notify=success
rotate/apply2-cancelled  guard=success apply1=success reboot=success apply2=cancelled redeploy=skipped notify=success
rotate/redeploy-fails    guard=success apply1=success reboot=success apply2=success redeploy=failure notify=success
converge/reboot-fails    guard=success apply1=skipped reboot=failure apply2=skipped redeploy=skipped notify=success
guard-refused            guard=failure apply1=skipped reboot=skipped apply2=skipped redeploy=skipped notify=skipped
guard-ok-no-go           guard=success apply1=skipped reboot=skipped apply2=skipped redeploy=skipped notify=skipped
guard-failed-late        guard=failure apply1=skipped reboot=skipped apply2=skipped redeploy=skipped notify=success
push                     guard=skipped apply1=skipped reboot=skipped apply2=skipped redeploy=skipped notify=skipped
EOF
wfviol() { python3 "$TMP/wfcheck.py" "$1" "$TMP" "$TMP/matrix.expected" 2>&1; }
MATRIX_NOW="$(python3 "$TMP/wfcheck.py" "$WF" "$TMP" - 2>&1)"
[[ "$(wfviol "$WF")" == "" ]] && ok "W1 the real workflow conforms: the evaluated job matrix equals the expected table, the permissions / checkout credentials / per-step env / env -i allow-lists are the exact closed sets, no continue-on-error, no expression in a run body, secrets only in the dotted form" || bad "W1 violations" "$(wfviol "$WF")"
[[ "$(cat "$TMP/matrix.expected")" == "$MATRIX_NOW" ]] && ok "W2 the job matrix (every job's if: EVALUATED per mode and per failure scenario) is: plan runs only guard and apply1; rotate runs all five; converge skips apply1; any failure or cancellation after the first write runs notify; a refused guard or a push runs nothing" || bad "W2 matrix" "$MATRIX_NOW"
[[ "$(grep -c 'continue-on-error' "$WF")" == 0 ]] && ok "W3 there is no continue-on-error anywhere in the workflow text" || bad "W3 continue-on-error"
# executed allow-lists: run each env -i step's own text against a stub script that dumps its environment
declare -A OUTER=([HOME]=/h [RUNNER_TEMP]=/rt [GITHUB_OUTPUT]=/o [GITHUB_STEP_SUMMARY]=/s [GITHUB_RUN_ID]=1 [GITHUB_RUN_ATTEMPT]=1 [GITHUB_REPOSITORY]=a/b [GITHUB_SERVER_URL]=https://x [HCLOUD_TOKEN]=T0 [GH_TOKEN]=g0 [DOPPLER_TOKEN]=d0
  [DOPPLER_TOKEN_TF]=tf0 [AWS_ACCESS_KEY_ID]=a0 [AWS_SECRET_ACCESS_KEY]=s0 [CF_API_TOKEN]=c0 [TF_VAR_doppler_token_tf]=v0 [BETTERSTACK_QUERY_HOST]=h0 [BETTERSTACK_QUERY_USERNAME]=u0 [BETTERSTACK_QUERY_PASSWORD]=p0
  [EFF_MODE]=rotate [EFF_KEYS]=both [EFF_SERVER_ID]=42 [EFF_ROTATED_AT]=2 [EFF_REBOOT_POST]=true [EFF_BOOT_PRE]=abcd1234 [EFF_VERIFY_AFTER]=3 [EFF_POST_EPOCH]=4)
allow_run() { # <workflow> <job> <subcommand>: the sorted NAME=VALUE lines of the child's environment
  local wf="$1" job="$2" sub="$3" d; d="$(mktemp -d "$TMP/allow.XXXXXX")"; mkdir -p "$d/scripts"
  python3 - "$wf" "$job" "$sub" "$d/step.sh" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
run = next(s["run"] for s in d["jobs"][sys.argv[2]]["steps"] if "run" in s and s["run"].strip().endswith("inngest-key-rotate.sh " + sys.argv[3]))
open(sys.argv[4], "w").write(run)
PY
  printf '#!/usr/bin/env bash\nenv -0 | tr "\\0" "\\n" | grep -vE "^(PWD|SHLVL|_)=" | sort\n' > "$d/scripts/inngest-key-rotate.sh"
  ( cd "$d" && env -i PATH="$PATH" HOME="${OUTER[HOME]}" RUNNER_TEMP="${OUTER[RUNNER_TEMP]}" GITHUB_OUTPUT="${OUTER[GITHUB_OUTPUT]}" GITHUB_STEP_SUMMARY="${OUTER[GITHUB_STEP_SUMMARY]}" GITHUB_RUN_ID=1 GITHUB_RUN_ATTEMPT=1 \
      GITHUB_REPOSITORY=a/b GITHUB_SERVER_URL=https://x HCLOUD_TOKEN=T0 GH_TOKEN=g0 DOPPLER_TOKEN=d0 DOPPLER_TOKEN_TF=tf0 AWS_ACCESS_KEY_ID=a0 AWS_SECRET_ACCESS_KEY=s0 CF_API_TOKEN=c0 TF_VAR_doppler_token_tf=v0 \
      BETTERSTACK_QUERY_HOST=h0 BETTERSTACK_QUERY_USERNAME=u0 BETTERSTACK_QUERY_PASSWORD=p0 EFF_MODE=rotate EFF_KEYS=both EFF_SERVER_ID=42 EFF_ROTATED_AT=2 EFF_REBOOT_POST=true EFF_BOOT_PRE=abcd1234 EFF_VERIFY_AFTER=3 EFF_POST_EPOCH=4 \
      bash step.sh 2>&1 )
}
expect_env() { # names... -> the NAME=VALUE lines the child must see
  local n; for n in "$@"; do printf '%s=%s\n' "$n" "$([[ "$n" == PATH ]] && echo "$PATH" || echo "${OUTER[$n]}")"; done | sort
}
COMMON_N="PATH HOME RUNNER_TEMP GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_REPOSITORY GITHUB_SERVER_URL GH_TOKEN"
ALLOW_POST="$COMMON_N HCLOUD_TOKEN EFF_MODE EFF_KEYS EFF_SERVER_ID EFF_REBOOT_POST"
ALLOW_ADMIT="$COMMON_N DOPPLER_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD EFF_MODE EFF_KEYS EFF_SERVER_ID EFF_ROTATED_AT EFF_REBOOT_POST"
ALLOW_VERIFY="$COMMON_N BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD EFF_MODE EFF_KEYS EFF_BOOT_PRE EFF_VERIFY_AFTER EFF_ROTATED_AT EFF_POST_EPOCH"
# shellcheck disable=SC2086
[[ "$(allow_run "$WF" reboot reboot)" == "$(expect_env $ALLOW_POST)" ]] && ok "W4 EXECUTING the POST step's own run: line, the child sees exactly the 15 allow-listed names with their values and none of CF_API_TOKEN, TF_VAR_*, DOPPLER_TOKEN*, AWS_*, BETTERSTACK_* (the Hetzner write token is here only)" || bad "W4 POST allow-list" "$(allow_run "$WF" reboot reboot | cut -d= -f1 | tr '\n' ' ')"
# shellcheck disable=SC2086
[[ "$(allow_run "$WF" reboot admit)" == "$(expect_env $ALLOW_ADMIT)" ]] && ok "W5 EXECUTING the admit step's run: line: the Tier-A DOPPLER_TOKEN and the Better Stack pair reach the child; HCLOUD_TOKEN, DOPPLER_TOKEN_TF, AWS_* and the other loader values do not" || bad "W5 admit allow-list" "$(allow_run "$WF" reboot admit | cut -d= -f1 | tr '\n' ' ')"
# shellcheck disable=SC2086
[[ "$(allow_run "$WF" reboot verify)" == "$(expect_env $ALLOW_VERIFY)" ]] && ok "W6 EXECUTING the verify step's run: line: only the Better Stack pair and the EFF_* inputs reach the child (no Hetzner token, no Doppler token)" || bad "W6 verify allow-list" "$(allow_run "$WF" reboot verify | cut -d= -f1 | tr '\n' ' ')"
[[ "$(allow_run "$WF" reboot reboot | grep -c '^GITHUB_RUN_ATTEMPT=')" == 1 && "$(allow_run "$WF" reboot admit | grep -c '^GITHUB_RUN_ATTEMPT=')" == 1 && "$(allow_run "$WF" reboot verify | grep -c '^GITHUB_RUN_ATTEMPT=')" == 1 ]] && ok "W7 GITHUB_RUN_ATTEMPT is in all three env -i allow-lists (without it the attempt check fails closed on attempt 1)" || bad "W7 attempt var"
# --- mutation rows (each parses the real workflow, edits it, and the conformance check must name the violation)
wfm() { # name python-statement (jobs, d in scope) -> $TMP/wfm-<name>.yml
  python3 - "$WF" "$TMP/wfm-$1.yml" "$2" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); jobs = d["jobs"]
exec(sys.argv[3])
yaml.safe_dump(d, open(sys.argv[2], "w"), width=100000)
PY
}
wfrow() { # id description name expected-token
  if [[ "$(wfviol "$TMP/wfm-$3.yml")" == *"$4"* ]]; then ok "$1 $2 -> $4"; else bad "$1 $2" "got: $(wfviol "$TMP/wfm-$3.yml" | tr '\n' ' ')"; fi
}
wfm if_always 'jobs["apply1"]["if"] = "${{ always() || (" + jobs["apply1"]["if"].strip()[4:-2].strip() + ") }}"'
wfrow WM1 "apply1 conditioned on always() || (...) runs after a refused guard (substring checks pass this; the evaluated matrix does not)" if_always "matrix:guard-refused"
wfm swap_outputs 'jobs["apply1"]["if"] = jobs["apply1"]["if"].replace("run_apply1", "run_reboot"); jobs["reboot"]["if"] = jobs["reboot"]["if"].replace("run_reboot", "run_apply1")'
wfrow WM2 "swapping run_apply1 and run_reboot between apply1 and reboot" swap_outputs "matrix:converge"
wfm no_apply1_status 'jobs["redeploy"]["if"] = jobs["redeploy"]["if"].replace(" && needs.apply2.result == '"'"'success'"'"'", "")'
wfrow WM3 "a redeploy that no longer requires apply2 to have SUCCEEDED runs after a cancelled apply2" no_apply1_status "matrix:rotate/apply2-cancelled"
wfm no_go 'jobs["apply1"]["if"] = jobs["apply1"]["if"].replace("needs.guard.outputs.go == '"'"'true'"'"' && ", "")'
wfrow WM4 "an apply1 whose condition no longer reads the guard's go output runs when the guard succeeded but said go=false" no_go "matrix:guard-ok-no-go"
wfm no_dispatch 'jobs["guard"]["if"] = "${{ true }}"'
wfrow WM5 "a guard that lost its workflow_dispatch gate runs on the registration push" no_dispatch "matrix:push"
wfm notify_noalways 'jobs["notify"]["if"] = jobs["notify"]["if"].replace("always() && ", "")'
wfrow WM6 "a notify job without always() never runs after a failed or cancelled job" notify_noalways "matrix:rotate/apply1-fails"
wfm notify_plan 'jobs["notify"]["if"] = jobs["notify"]["if"].replace(" && needs.guard.outputs.mode != '"'"'plan'"'"'", "")'
wfrow WM7 "a notify job that does not exclude mode=plan" notify_plan "matrix:plan"
wfm notify_green 'jobs["notify"]["if"] = jobs["notify"]["if"].replace(" && needs.redeploy.result != '"'"'success'"'"'", "")'
wfrow WM8 "a notify job that also runs after a green redeploy" notify_green "matrix:rotate"
wfm coe_job 'jobs["apply1"]["continue-on-error"] = True'
wfrow WM9 "continue-on-error on the apply1 JOB (reboot, apply2 and redeploy would proceed past a failed phase 1)" coe_job "continue-on-error"
wfm coe_step 'jobs["apply1"]["steps"][-1]["continue-on-error"] = True'
wfrow WM10 "continue-on-error on the apply1 STEP" coe_step "continue-on-error"
wfm perm_redeploy 'jobs["redeploy"]["permissions"]["contents"] = "write"'
wfrow WM11 "contents: write on the redeploy job" perm_redeploy "perms:redeploy"
wfm perm_reboot 'jobs["reboot"]["permissions"]["actions"] = "write"'
wfrow WM12 "actions: write on the reboot job" perm_reboot "perms:reboot"
wfm perm_notify 'jobs["notify"]["permissions"]["contents"] = "read"'
wfrow WM13 "notify holding more than issues: write" perm_notify "perms:notify"
wfm perm_guard 'jobs["guard"]["permissions"]["issues"] = "write"'
wfrow WM14 "issues: write on the read-only guard" perm_guard "perms:guard"
wfm persist 'next(s for s in jobs["reboot"]["steps"] if str(s.get("uses","")).startswith("actions/checkout"))["with"]["persist-credentials"] = True'
wfrow WM15 "persist-credentials: true on the reboot job's checkout (the write-token job)" persist "persist:reboot"
wfm persist_notify 'del next(s for s in jobs["notify"]["steps"] if str(s.get("uses","")).startswith("actions/checkout"))["with"]["persist-credentials"]'
wfrow WM16 "a checkout without persist-credentials: false" persist_notify "persist:notify"
wfm notify_conc 'jobs["notify"]["concurrency"] = {"group": "inngest-key-rotate-notify", "cancel-in-progress": False}'
wfrow WM17 "a concurrency group on notify (it could itself be replaced while pending)" notify_conc "notify-concurrency"
wfm run_expr 'next(s for s in jobs["apply1"]["steps"] if "run" in s)["run"] = "echo ${{inputs.mode}} && bash scripts/inngest-key-rotate.sh apply1"'
wfrow WM18 "an expression with NO space (\${{inputs.mode}}) interpolated into a run: body" run_expr "run-expr:apply1"
wfm secrets_bracket 'jobs["guard"]["steps"][-1]["env"]["DOPPLER_TOKEN"] = "${{ secrets['"'"'DOPPLER_TOKEN'"'"'] }}"'
wfrow WM19 "secrets['DOPPLER_TOKEN'] bracket access (invisible to the dotted-form scans)" secrets_bracket "secrets-form"
wfm secrets_json 'jobs["notify"]["steps"][-1]["env"]["LEAK"] = "${{ toJSON(secrets) }}"'
wfrow WM20 "toJSON(secrets) bound into a step env" secrets_json "secrets-form"
wfm env_apply2_dp 'del next(s for s in jobs["apply2"]["steps"] if "run" in s)["env"]["DOPPLER_TOKEN"]'
wfrow WM21 "apply2 without its DOPPLER_TOKEN env (the name survives elsewhere in the job)" env_apply2_dp "env:apply2:apply2"
wfm env_apply2_keys 'del next(s for s in jobs["apply2"]["steps"] if "run" in s)["env"]["EFF_KEYS"]'
wfrow WM22 "apply2 without its EFF_KEYS env" env_apply2_keys "env:apply2:apply2"
wfm env_redeploy_mode 'del next(s for s in jobs["redeploy"]["steps"] if "run" in s)["env"]["EFF_MODE"]'
wfrow WM23 "redeploy without its EFF_MODE env" env_redeploy_mode "env:redeploy:redeploy"
wfm verify_pre_guard 'next(s for s in jobs["reboot"]["steps"] if s.get("id") == "verify")["env"]["EFF_BOOT_PRE"] = "${{ needs.guard.outputs.boot_pre }}"'
wfrow WM24 "verify reading the guard's (stale) boot_pre instead of admit's" verify_pre_guard "env:reboot:verify"
wfm post_if_guard 'next(s for s in jobs["reboot"]["steps"] if s.get("id") == "post")["if"] = "${{ needs.guard.outputs.reboot_post == '"'"'true'"'"' }}"'
wfrow WM25 "a POST step driven by the guard's reboot_post instead of the admit step's" post_if_guard "postif"
wfm verify_always 'next(s for s in jobs["reboot"]["steps"] if s.get("id") == "verify")["if"] = "${{ always() }}"'
wfrow WM26 "a verify step that runs even when admit failed" verify_always "stepif"
wfm post_extra_cf 'next(s for s in jobs["reboot"]["steps"] if s.get("id") == "post")["run"] = next(s for s in jobs["reboot"]["steps"] if s.get("id") == "post")["run"].replace('"'"'GH_TOKEN="$GH_TOKEN" HCLOUD_TOKEN'"'"', '"'"'GH_TOKEN="$GH_TOKEN" CF_API_TOKEN="$CF_API_TOKEN" HCLOUD_TOKEN'"'"')'
wfrow WM27 "CF_API_TOKEN added to the POST step's env -i allow-list (static check)" post_extra_cf "allow:reboot:reboot"
# shellcheck disable=SC2086
[[ "$(allow_run "$TMP/wfm-post_extra_cf.yml" reboot reboot)" != "$(expect_env $ALLOW_POST)" ]] && ok "WM27b ...and EXECUTING the mutated line lets CF_API_TOKEN through to the child (the executed check sees it too)" || bad "WM27b executed mutant looked clean"
wfm post_extra_tf 'next(s for s in jobs["reboot"]["steps"] if s.get("id") == "post")["run"] = next(s for s in jobs["reboot"]["steps"] if s.get("id") == "post")["run"].replace('"'"'GH_TOKEN="$GH_TOKEN" HCLOUD_TOKEN'"'"', '"'"'GH_TOKEN="$GH_TOKEN" TF_VAR_doppler_token_tf="$TF_VAR_doppler_token_tf" HCLOUD_TOKEN'"'"')'
wfrow WM28 "TF_VAR_doppler_token_tf added to the POST step's allow-list" post_extra_tf "allow:reboot:reboot"
# shellcheck disable=SC2086
[[ "$(allow_run "$TMP/wfm-post_extra_tf.yml" reboot reboot)" != "$(expect_env $ALLOW_POST)" ]] && ok "WM28b ...executed: the Terraform provider token reaches the child" || bad "WM28b"
for pair in "reboot:EFF_SERVER_ID:$ALLOW_POST:post" "reboot:GITHUB_OUTPUT:$ALLOW_POST:post" "reboot:GITHUB_RUN_ATTEMPT:$ALLOW_POST:post" "reboot:GITHUB_RUN_ATTEMPT:$ALLOW_ADMIT:admit" "reboot:DOPPLER_TOKEN:$ALLOW_ADMIT:admit" "reboot:BETTERSTACK_QUERY_PASSWORD:$ALLOW_VERIFY:verify" "reboot:GITHUB_RUN_ATTEMPT:$ALLOW_VERIFY:verify"; do
  IFS=: read -r _ name allow sid <<<"$pair"
  mn="del_${sid}_${name}"
  wfm "$mn" "st = next(s for s in jobs['reboot']['steps'] if s.get('id') == '$sid'); st['run'] = st['run'].replace(' $name=\"\$$name\"', '')"
  sub="$sid"; [[ "$sid" == post ]] && sub=reboot
  # shellcheck disable=SC2086
  [[ "$(allow_run "$TMP/wfm-$mn.yml" reboot "$sub")" != "$(expect_env $allow)" && "$(wfviol "$TMP/wfm-$mn.yml")" == *"allow:reboot:$sub"* ]] && ok "WM29-$sid-$name deleting $name from the $sid step's allow-list is seen by the executed check AND the static check" || bad "WM29-$sid-$name deletion not detected" "$(wfviol "$TMP/wfm-$mn.yml" | tr '\n' ' ')"
done
a21_hits() { grep -Ec '(^|[^-a-zA-Z_/])(terraform|doppler|curl|gh)( |$)' < <(grep -v '^ *#' "$1" | grep -v 'description:') || true; }
printf '    steps:\n      - run: gh\n' > "$TMP/a21-eol.yml"; printf '    steps:\n      - run: echo ok\n' > "$TMP/a21-clean.yml"
[[ "$(a21_hits "$TMP/a21-eol.yml")" == 1 && "$(a21_hits "$TMP/a21-clean.yml")" == 0 && "$(a21_hits "$WF")" == 0 ]] && ok "WM30 (harness) the A21 scan flags a bare 'gh' at the end of a line (the trailing-space blind spot) and passes the real workflow" || bad "WM30 A21 scan"
H5_RE='gh (issue (comment|edit)|api|gist|release|pr (comment|review|merge))|--method POST'
printf 'gh gist create x\n' > "$TMP/h5-gist.sh"; printf 'gh release create v1\n' > "$TMP/h5-rel.sh"
[[ "$(grep -Ec "$H5_RE" "$TMP/h5-gist.sh")" == 1 && "$(grep -Ec "$H5_RE" "$TMP/h5-rel.sh")" == 1 && "$(grep -v '^ *#' "$BODY" | grep -Ec "$H5_RE")" == 0 ]] && ok "WM32 (harness) the H5 scan also bans gh gist and gh release, and the script has none" || bad "WM32 H5 scan"
# a second Hetzner request site, a mutating verb, a second -X
BC2="$TMP/bc2.sh"; { cat "$BODY"; printf '%s\n' "kr_leak() { bc_curl inngest-key-rotate 'Authorization:Bearer :KR_HZ_TOKEN' -- -sS -X POST https://api.hetzner.cloud/v1/servers/1/actions/poweroff; }"; } > "$BC2"
BD2="$TMP/bd2.sh"; { cat "$BODY"; printf '%s\n' 'kr_leak() { kr_hz DELETE /v1/servers/1 /dev/null; }'; } > "$BD2"
hz_sites() { echo "$(grep -v '^ *#' "$1" | grep -c 'bc_curl inngest-key-rotate') $(grep -v '^ *#' "$1" | grep -c -- '-X ') $(grep -v '^ *#' "$1" | grep -Eo '\bkr_hz [A-Z]+' | awk '{print $2}' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"; }
[[ "$(hz_sites "$BODY")" == "1 1  3 GET; 1 POST;" && "$(hz_sites "$BC2")" != "$(hz_sites "$BODY")" && "$(hz_sites "$BD2")" != "$(hz_sites "$BODY")" ]] && ok "WM33 (harness) the B12 site count changes for a SECOND bc_curl -X POST line and for a kr_hz DELETE (survivors of the old literal-string checks)" || bad "WM33 hz sites: $(hz_sites "$BODY") / $(hz_sites "$BC2") / $(hz_sites "$BD2")"

printf '\n=== J. final accounting ===\n'
[[ "$(kr_sentinel_hits "$TMP/all-streams.txt")" == 0 ]] && ok "J1 (G2 #5, final) after the whole suite, every captured stream of every non-mutant scenario ($(wc -l < "$TMP/all-streams.txt") lines) is free of key-shaped strings" || bad "J1 final sentinel"
REFUSED_ANY=""; for ((i = 1; i <= NONMUT_N; i++)); do [[ -s "$TMP/s$i/refusals.log" ]] && REFUSED_ANY="$REFUSED_ANY $i"; done
[[ -z "$REFUSED_ANY" && "$NONMUT_N" -ge 150 ]] && ok "J3 none of the $NONMUT_N scenarios that ran the REAL script made an unmodelled call: the strict doppler / gh / curl fakes' refusal logs are empty (every project, config, token class, issue number, workflow and URL the script used is one the fakes model)" || bad "J3 unmodelled calls in scenarios:$REFUSED_ANY" "$(cat "$TMP"/s"${REFUSED_ANY%% *}"/refusals.log 2>/dev/null | head -3)"
[[ -z "$(ls -d "$TMP"/s*/rt/inngest-key-rotate.* 2>/dev/null)" ]] && ok "J2 no scenario left its private temp dir (and so no plan JSON) behind" || bad "J2 leftover temp dir"

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
FLOOR=472
if (( PASS + FAIL < FLOOR )); then
  printf 'FAIL ANTI-VACUITY: %d assertions ran, floor is %d\n' $((PASS + FAIL)) "$FLOOR" >&2
  exit 1
fi
if (( PASS + FAIL > FLOOR )); then
  printf 'FAIL FLOOR DRIFT: %d assertions ran but FLOOR is %d - set FLOOR=%d (the floor is the real count)\n' $((PASS + FAIL)) "$FLOOR" $((PASS + FAIL)) >&2
  exit 1
fi
exit $(( FAIL > 0 ))
