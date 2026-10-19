#!/usr/bin/env bash
# Drift and behaviour guard for the Inngest link flip (#10136): .github/workflows/inngest-link-flip.yml and its body
# scripts/inngest-link-flip.sh.
#
# WHAT THIS PROTECTS. The flip changes which URL the whole web tier dials the scheduler on, and the failure that
# matters is silent: a workflow that promotes the flag after a canary that did not pass, a "revert" step that exits
# red and hides the original failure, a lease that lapsed mid-deploy and was promoted anyway, a workflow that grew a
# Doppler or Terraform credential. So the file is checked in two layers:
#   A. STATIC, on the PARSED YAML (never a grep: a grep passes on a commented-out step): dispatch-only, least
#      privilege, pinned actions, inputs through env, the revert step's exact `if`, no credential beyond the deploy
#      webhook, and the script's own shape (every network call bounded, no `eval`, no `-k`/`--insecure`).
#   B. BEHAVIOURAL, by running the script against stubbed gh/curl/sleep and a stubbed redeploy driver (track.sh): the happy
#      path orders pending -> redeploy -> handshake -> `1`; a failed or DEGRADED fleet redeploy, a lapsed lease, a failed
#      handshake, a busy deploy lane and a failed flag job each stop BEFORE the promotion (the real track.sh is also driven
#      once on an `ok_peer_fanout_degraded` frame); `started=true` is written only after the guards and before the first
#      flag write; `off` takes no idle guard; revert always exits 0; the secret never reaches the output.
#   C. MUTATIONS on copies of the script: each guard is deleted and the scenario that depends on it must turn from
#      "stops" to "promotes" (a guard no scenario can see is not a guard). The Tier-B job gets the same treatment: its plan
#      step is EXECUTED against stub doppler/terraform (the requested value must reach terraform through the process
#      environment even when Doppler injects a different inherited one), and mutated copies of that step must turn red.
# Fixtures are synthesized: the "secrets" below are throwaway alphanumerics that exist only in this process.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/inngest-link-flip.yml"
BODY="$REPO_ROOT/scripts/inngest-link-flip.sh"
APPLY_WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; return 0; }
check() { # desc, then a command that must succeed
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

python3 -c 'import yaml' 2>/dev/null || { echo "FAIL SETUP: python3 yaml unavailable"; exit 1; }
for f in "$WF" "$BODY" "$APPLY_WF"; do [[ -f "$f" ]] || { echo "FAIL SETUP: $f missing"; exit 1; }; done

printf '\n=== A. static: the workflow ===\n'
yq() { python3 - "$WF" "$1" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True, d.get("on"))
job = d["jobs"]["flip"]
steps = job["steps"]
expr = sys.argv[2]
print(eval(expr))
PY
}
[[ "$(yq 'sorted(on.keys())')" == "['workflow_dispatch']" ]] && ok "A1 dispatch-only: no push, pull_request or schedule trigger" || bad "A1 triggers: $(yq 'sorted(on.keys())')"
[[ "$(yq 'sorted(d["permissions"].items())')" == "[('actions', 'write'), ('contents', 'read')]" ]] && ok "A2 permissions are exactly contents:read + actions:write" || bad "A2 permissions: $(yq 'd["permissions"]')"
[[ "$(yq 'd["concurrency"]["group"]+"|"+str(d["concurrency"]["cancel-in-progress"])')" == "inngest-link-flip|False" ]] && ok "A3 concurrency group inngest-link-flip, never cancel-in-progress" || bad "A3 concurrency"
[[ "$(yq 'job["timeout-minutes"] <= 360')" == True ]] && ok "A4 the job has a bounded timeout-minutes (below GitHub's 360 ceiling; A62 pins it to the script's budget table)" || bad "A4 timeout"
WANT_A5="(failure() || cancelled()) && inputs.action == 'flip' && steps.flip.outputs.started == 'true'"
[[ "$(yq 'next(s.get("if") for s in steps if "Revert" in s.get("name",""))')" == "$WANT_A5" ]] && ok "A5 the revert step runs on exactly (failure() || cancelled()) on a flip whose first flag write was attempted" || bad "A5 revert if: $(yq '[s.get("if") for s in steps]')"
[[ "$(yq 'sum(1 for s in steps if "Revert" in s.get("name",""))')" == 1 ]] && ok "A6 exactly one revert step (a later same-named step cannot shadow it)" || bad "A6 revert count"
[[ "$(yq 'all(len(s["uses"].split("@")[1].split(" ")[0]) == 40 for s in steps if "uses" in s)')" == True ]] && ok "A7 every action is pinned to a 40-hex SHA" || bad "A7 unpinned action"
[[ "$(yq 'sorted(set(__import__("re").findall(r"secrets\.([A-Z0-9_]+)", open(sys.argv[1]).read())))')" == "['CF_ACCESS_CLIENT_ID', 'CF_ACCESS_CLIENT_SECRET', 'WEBHOOK_DEPLOY_SECRET']" ]] && ok "A8 the only secrets are the deploy webhook trio (no Doppler, Terraform or cloud credential)" || bad "A8 secrets: $(grep -o 'secrets\.[A-Z0-9_]*' "$WF" | sort -u | tr '\n' ' ')"
[[ "$(yq 'any("${{ inputs" in s.get("run","") or "${{ secrets" in s.get("run","") for s in steps)')" == False ]] && ok "A9 no input or secret is interpolated into a run: script (all via env:)" || bad "A9 expression interpolated into run:"
WANT_A10="['bash scripts/inngest-link-flip.sh \"\$ACTION\"']"
[[ "$(yq '[s["run"].strip() for s in steps if "Run the flip" in s.get("name","")]')" == "$WANT_A10" ]] && ok "A10 the flip step calls the script with the action from env" || bad "A10 flip step: $(yq '[s["run"].strip() for s in steps if "Run the flip" in s.get("name","")]')"
[[ "$(yq '[s["run"].strip() for s in steps if "Revert" in s.get("name","")]')" == "['bash scripts/inngest-link-flip.sh revert']" ]] && ok "A11 the revert step calls the script's revert subcommand" || bad "A11 revert step"
check "A12 no terraform, doppler or ssh command in the workflow text" bash -c "! grep -Eq '(^|[^-a-z_])(terraform|doppler|ssh) ' < <(grep -v '^ *#' '$WF')"
[[ "$(yq 'on["workflow_dispatch"]["inputs"]["action"]["options"]')" == "['flip', 'off']" ]] && ok "A13 the action input is exactly {flip, off} (off quoted: YAML 1.1 reads a bare off as false)" || bad "A13 options"
# A14 DRIVES the typo-guard step's shell (a grep for the token is satisfied by the input description and the header
# comment, so the guard could be deleted with the row green).
python3 - "$WF" "$TMP/typo-guard.sh" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
run = next(s["run"] for s in d["jobs"]["flip"]["steps"] if s.get("name") == "Typo-guard")
open(sys.argv[2], "w").write(run)
PY
guard_rc() { ACTION="$1" CONFIRM="$2" bash "$TMP/typo-guard.sh" >/dev/null 2>&1; echo $?; }
[[ -s "$TMP/typo-guard.sh" && "$(guard_rc flip FLIP-INNGEST-LINK)" == 0 && "$(guard_rc flip '')" != 0 && "$(guard_rc flip flip-inngest-link)" != 0 \
   && "$(guard_rc off '')" == 0 && "$(guard_rc bogus '')" != 0 ]] \
  && ok "A14 the typo-guard step, executed: flip needs exactly FLIP-INNGEST-LINK, off needs nothing, anything else is refused" || bad "A14 typo-guard behaviour"
sed 's/\[\[ "\$CONFIRM" == "FLIP-INNGEST-LINK" \]\] ||/true ||/' "$TMP/typo-guard.sh" > "$TMP/typo-guard-mut.sh"
if cmp -s "$TMP/typo-guard.sh" "$TMP/typo-guard-mut.sh"; then bad "A14m the typo-guard mutation matched nothing"
else [[ "$(ACTION=flip CONFIRM= bash "$TMP/typo-guard-mut.sh" >/dev/null 2>&1; echo $?)" == 0 ]] && ok "A14m with the CONFIRM comparison removed the unconfirmed flip is accepted (so A14 can see the guard)" || bad "A14m"; fi
[[ "$(yq '[s.get("id") for s in steps if "Run the flip" in s.get("name","")]')" == "['flip']" ]] && ok "A22 the flip step has id: flip (the revert step's gate reads steps.flip.outputs.started)" || bad "A22 flip step id"
[[ "$(yq 'job.get("env", {}).get("WEB_HOST_PRIVATE_IPS")')" == "10.0.1.10,10.0.1.11" ]] && ok "A23 the job pins the fan-out roster WEB_HOST_PRIVATE_IPS (web-hosts-fanout-parity.test.sh compares it with var.web_hosts)" || bad "A23 roster: $(yq 'job.get("env")')"
# A24 evaluates the revert step's `if:` for the cases that matter, so the string cannot be right and the gate wrong.
revert_if_eval() { # failed cancelled action started -> True|False
  python3 - "$WF" "$1" "$2" "$3" "$4" <<'PY'
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
expr = next(s["if"] for s in d["jobs"]["flip"]["steps"] if "Revert" in s.get("name", ""))
py = expr.replace("failure()", "F").replace("cancelled()", "C").replace("inputs.action", "A") \
         .replace("steps.flip.outputs.started", "S").replace("||", " or ").replace("&&", " and ")
if re.sub(r"\b(F|C|A|S|or|and)\b|==|[()\s]|'[a-z]*'", "", py):
    print("UNEVALUABLE"); sys.exit(0)
print(eval(py, {"__builtins__": {}}, {"F": sys.argv[2] == "1", "C": sys.argv[3] == "1", "A": sys.argv[4], "S": sys.argv[5]}))
PY
}
rg_rows="$(revert_if_eval 1 0 flip true; revert_if_eval 0 1 flip true; revert_if_eval 1 0 flip ""; revert_if_eval 1 0 off ""; revert_if_eval 1 0 off true; revert_if_eval 0 0 flip true)"
rg_rows="$(printf '%s ' $rg_rows)"
[[ "$rg_rows" == "True True False False False False " ]] && ok "A24 revert fires only for a failed/cancelled flip that started; not for a guard refusal, a failed off, or success" || bad "A24 revert gate evaluates to: $rg_rows"

printf '\n=== A. static: the dispatch target and the script ===\n'
check "A15 the Tier-B job this flow dispatches exists with its option and input" python3 - "$APPLY_WF" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert "inngest_link_flag" in d["jobs"]
on = d.get(True, d.get("on"))
assert "inngest-link-flag" in on["workflow_dispatch"]["inputs"]["apply_target"]["options"]
assert "inngest_link_value" in on["workflow_dispatch"]["inputs"]
PY
check "A16 the script dispatches that exact workflow, target and input name" bash -c "grep -q 'FLIP_APPLY_WORKFLOW=\"apply-web-platform-infra.yml\"' '$BODY' && grep -q 'apply_target=inngest-link-flag' '$BODY' && grep -q 'inngest_link_value=' '$BODY'"
check "A17 the script's lease constant matches the resolver's 30 minutes" grep -q '^FLIP_LEASE_S=1800$' "$BODY"
check "A18 no eval, no insecure/-k curl, no credential in an argument list" bash -c "! grep -Eq '\\beval\\b|--insecure| -k |-H .?(Authorization|X-Signature)' < <(grep -v '^ *#' '$BODY')"
check "A19 every network call is bounded: both webhook curls carry --max-time, gh run watch has a timeout, track.sh gets REDEPLOY_TIMEOUT_S" bash -c "[ \"\$(grep -v '^ *#' '$BODY' | grep -c -- '--max-time')\" -ge 2 ] && grep -q 'timeout \"\$FLIP_WATCH_TIMEOUT_S\" gh run watch' '$BODY' && grep -q 'REDEPLOY_TIMEOUT_S=\"\$FLIP_REDEPLOY_TIMEOUT_S\"' '$BODY'"
check "A25 the redeploy is delegated to track.sh; no private deploy/poll loop and no peer literal remains in the script" bash -c "grep -q 'dispatch-web-redeploy/track.sh' '$BODY' && ! grep -Eq 'FLIP_PEERS|\bflip_redeploy\b|hooks/deploy\"|FLIP_POLL_MAX' < <(grep -v '^ *#' '$BODY')"
# A60-A64: the budget table. One table in the script; the workflow's timeouts are derived from it and the redeploy budget
# equals the pipeline's own ceiling (ci-deploy-wrapper.sh hard-kills ci-deploy.sh at 4800 s).
BUD="$(env -i PATH="$PATH" bash -c 'source "$1"; echo "$FLIP_REDEPLOY_TIMEOUT_S $FLIP_IN_FLIGHT_CEILING_S $FLIP_REVERT_BUDGET_S $FLIP_JOB_BUDGET_S $FLIP_LEASE_MARGIN_S $FLIP_LEASE_S"' _ "$BODY")"
read -r BUD_REDEPLOY BUD_CEILING BUD_REVERT BUD_JOB BUD_MARGIN BUD_LEASE <<<"$BUD"
REVERT_MIN="$(yq 'next(s["timeout-minutes"] for s in steps if "Revert" in s.get("name",""))')"
JOB_MIN="$(yq 'job["timeout-minutes"]')"
FLIP_STEP_MIN="$(yq 'next(s["timeout-minutes"] for s in steps if s.get("name") == "Run the flip")')"
read -r BUD_STEP <<<"$(env -i PATH="$PATH" bash -c 'source "$1"; echo "$FLIP_STEP_BUDGET_S"' _ "$BODY")"
[[ "$BUD_REDEPLOY" == 4800 && "$BUD_CEILING" == 4800 ]] && grep -Eq 'timeout --signal=TERM --kill-after=[0-9]+s 4800s ' "$REPO_ROOT/apps/web-platform/infra/ci-deploy-wrapper.sh" \
  && ok "A60 the redeploy budget and the in-flight ceiling both equal the pipeline's 4800 s wall clock (ci-deploy-wrapper.sh)" || bad "A60 redeploy=$BUD_REDEPLOY ceiling=$BUD_CEILING"
[[ "$REVERT_MIN" =~ ^[0-9]+$ && "$REVERT_MIN" == $(( (BUD_REVERT + 59) / 60 )) ]] && ok "A61 the revert step's timeout-minutes ($REVERT_MIN) is the budget table's FLIP_REVERT_BUDGET_S (${BUD_REVERT} s) rounded up: an off apply plus a redeploy bounded by the 4800 s ceiling" || bad "A61 revert minutes=$REVERT_MIN budget=$BUD_REVERT"
[[ "$JOB_MIN" =~ ^[0-9]+$ && "$JOB_MIN" == $(( (BUD_JOB + 59) / 60 )) && "$JOB_MIN" -le 360 ]] && ok "A62 the job's timeout-minutes ($JOB_MIN) is FLIP_JOB_BUDGET_S (${BUD_JOB} s) rounded up (the flip step's budget plus the revert step's plus the slack) and under GitHub's 360" || bad "A62 job minutes=$JOB_MIN budget=$BUD_JOB"
[[ "$BUD_MARGIN" -ge 600 && "$BUD_MARGIN" -lt "$BUD_LEASE" ]] && ok "A63 the web-2 lease margin is at least 600 s and below the lease" || bad "A63 margin=$BUD_MARGIN lease=$BUD_LEASE"
[[ "$FLIP_STEP_MIN" =~ ^[0-9]+$ && "$FLIP_STEP_MIN" == $(( (BUD_STEP + 59) / 60 )) ]] && ok "A64 the Run-the-flip step has its OWN timeout-minutes ($FLIP_STEP_MIN) = FLIP_STEP_BUDGET_S (${BUD_STEP} s) rounded up, so a hung flip is cut before the revert's window is spent" || bad "A64 flip step minutes=$FLIP_STEP_MIN budget=$BUD_STEP"
check "A20 the script parses clean (bash -n)" bash -n "$BODY"
if command -v shellcheck >/dev/null 2>&1; then check "A21 shellcheck is clean" shellcheck "$BODY"; else ok "A21 shellcheck not installed; skipped"; fi

printf '\n=== B. behaviour against stubs ===\n'
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
make_stubs() { # dir
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/bin" "$d/state"
  printf '1000000000\n' > "$d/state/now"
  cat > "$d/bin/advance" <<'SH'
#!/usr/bin/env bash
s="$(cat "$STUB/state/now")"; echo $((s + ${1:-5} + ${ADVANCE_EXTRA:-0})) > "$STUB/state/now"
SH
  cat > "$d/bin/nowcmd" <<'SH'
#!/usr/bin/env bash
cat "$STUB/state/now"
SH
  cat > "$d/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB/gh.log"
case "$1 $2" in
  "workflow run")
    echo "dispatch started=$(grep -c '^started=true$' "$GITHUB_OUTPUT" 2>/dev/null || true)" >> "$STUB/order.log"
    exit "${GH_RUN_RC:-0}" ;;
  "run list")
    case "$*" in
      *"-q length"*) cat "$STUB/state/busy" 2>/dev/null || echo 0 ;;
      *)
        # An EARLIER flip's green run (older than the dispatch) and/or a recent run whose flag job was skipped come first.
        [[ -f "$STUB/state/stale_old" ]] && echo "4141 $(date -u -d "@$(( $(cat "$STUB/state/now") - 3600 ))" +%Y-%m-%dT%H:%M:%SZ)"
        [[ -f "$STUB/state/first_recent" ]] && echo "4143 $(date -u -d "@$(cat "$STUB/state/now")" +%Y-%m-%dT%H:%M:%SZ)"
        echo "4242 $(date -u -d "@$(cat "$STUB/state/now")" +%Y-%m-%dT%H:%M:%SZ)" ;;
    esac ;;
  "run view") if [[ "$3" == 4143 ]]; then cat "$STUB/state/first_recent"; else echo success; fi ;;
  "run watch")
    echo "$3" >> "$STUB/watched.log"
    n=$(( $(cat "$STUB/state/watchn" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/state/watchn"
    rc="$(sed -n "${n}p" "$STUB/state/watch_rcs" 2>/dev/null)"; exit "${rc:-0}" ;;
esac
SH
  cat > "$d/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; method=GET; url=""; wfmt=""; cfg=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;; -X) method="$2"; shift ;; -w) wfmt="$2"; shift ;;
    --config) cfg=1; shift ;; --max-time|-d|-H) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
[[ "$cfg" == 1 ]] && cat > "$STUB/state/curl_config.$$"   # the credential channel: consumed, never logged
echo "curl $method $url" >> "$STUB/curl.log"
now="$(cat "$STUB/state/now")"
body=""; code=200
case "$url" in
  */health) body='{"version":"1.2.3"}' ;;
  */hooks/deploy) code="${DEPLOY_CODE:-202}"; echo posted > "$STUB/state/posted"; echo 0 > "$STUB/state/polls" ;;
  */hooks/deploy-status)
    if [[ -f "$STUB/state/posted" ]]; then
      n=$(( $(cat "$STUB/state/polls") + 1 )); echo "$n" > "$STUB/state/polls"
      if (( n < 2 )); then body="{\"component\":\"web-platform\",\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":$now}"
      else body="${TERMINAL_FRAME:-{\"component\":\"web-platform\",\"exit_code\":0,\"reason\":\"ok\",\"tag\":\"v1.2.3\",\"start_ts\":$now\}}"; fi
    else
      body="${IDLE_FRAME:-{\"component\":\"web-platform\",\"exit_code\":0,\"reason\":\"ok\",\"tag\":\"v1.2.2\",\"start_ts\":$((now - 90000))\}}"
    fi ;;
  */hooks/inngest-tls-handshake) code="${HANDSHAKE_CODE:-200}"; echo handshake >> "$STUB/order.log"
    # The REAL body of inngest-registry-probe.sh tls_handshake (one line of fixed tokens and numeric curl exit codes).
    body="${HANDSHAKE_BODY-inngest-tls-handshake verified=200 verified_rc=0 unverified=fail unverified_rc=60 result=pass}" ;;
esac
if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
[[ -n "$wfmt" ]] && printf '%s' "$code"
exit 0
SH
  # The redeploy driver (track.sh) stub: records the env contract it was handed (never the secret itself), advances the
  # clock when asked, and exits with TRACK_RC.
  cat > "$d/bin/track-stub" <<'SH'
#!/usr/bin/env bash
echo "track peers=${WEB_HOST_PRIVATE_IPS-unset} timeout=${REDEPLOY_TIMEOUT_S-unset} secret=${WEBHOOK_DEPLOY_SECRET:+set}" >> "$STUB/track.log"
echo track >> "$STUB/order.log"
[[ -n "${TRACK_ADVANCE:-}" ]] && "$STUB/bin/advance" "$TRACK_ADVANCE"
echo "stub track verdict=${TRACK_VERDICT:-ok}"
exit "${TRACK_RC:-0}"
SH
  chmod +x "$d/bin/"*
}

SECRET_W="WhSecretAAAA1111"; SECRET_ID="cfidBBBB2222"; SECRET_SECRET="cfsecCCCC3333"
run_script() { # dir script mode [env assignments...] -> rc in $RC, output in $OUT
  local d="$1" script="$2" mode="$3"; shift 3
  OUT="$(env -i PATH="$d/bin:/usr/local/bin:/usr/bin:/bin" HOME="$d" TMPDIR="$d" RUNNER_TEMP="$d" STUB="$d" \
    GITHUB_WORKSPACE="$REPO_ROOT" GH_TOKEN=x GITHUB_RUN_ID=77 \
    WEBHOOK_DEPLOY_SECRET="$SECRET_W" CF_ACCESS_CLIENT_ID="$SECRET_ID" CF_ACCESS_CLIENT_SECRET="$SECRET_SECRET" \
    WEB_HOST_PRIVATE_IPS="10.0.1.10,10.0.1.11" GITHUB_OUTPUT="$d/github_output" GITHUB_STEP_SUMMARY="$d/summary.md" FLIP_TRACK="$d/bin/track-stub" \
    FLIP_SLEEP="$d/bin/advance" FLIP_NOW="$d/bin/nowcmd" FLIP_WATCH_TIMEOUT_S=20 "$@" \
    bash "$script" "$mode" 2>&1)"; RC=$?
}
fresh() { local d="$TMP/$1"; assert_fixture_dir "$d"; rm -rf "$d"; make_stubs "$d"; printf '%s' "$d"; }
dispatched() { if [[ -f "$1/gh.log" ]]; then grep -c 'workflow run' "$1/gh.log" || true; else echo 0; fi; }
values() { grep -o 'inngest_link_value=[^ ]*' "$1/gh.log" 2>/dev/null | sed 's/inngest_link_value=//; s/pending:[0-9]*/pending/' | tr '\n' ' '; }
tracked() { if [[ -f "$1/track.log" ]]; then grep -c '^track ' "$1/track.log" || true; else echo 0; fi; }
started() { if [[ -f "$1/github_output" ]]; then grep -c '^started=true$' "$1/github_output" || true; else echo 0; fi; }
order() { if [[ -f "$1/order.log" ]]; then tr '\n' ' ' < "$1/order.log"; fi; }

printf '\n=== A. the Tier-B flag job (its real steps executed against stateful fake doppler/terraform) ===\n'
# ---- Tier-B job (apply-web-platform-infra.yml::inngest_link_flag) ----------------------------------------------------
# The job writes the SOURCE KEY INNGEST_LINK_TLS in soleur/prd_terraform FIRST (set for pending/1, deleted and verified gone
# for off), because MEASURED 2026-10-19 prd_terraform does NOT inherit a Terraform-written prd key created after the branch:
# without the key every UNTARGETED plan (drift detector, infra-validation, a full apply) sees var "" and proposes to DESTROY the
# live flag. It also hands its own plan TF_VAR_inngest_link_tls as an explicit `env` after `doppler run`, so it converges
# whether or not Doppler inherits. The fakes below model BOTH worlds (DOPPLER_INHERIT=0|1); the gate's jq is also run on
# synthesized plans (A26-A30).
python3 - "$APPLY_WF" "$TMP" <<'PY'
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1]))
job = d["jobs"]["inngest_link_flag"]
tmp = sys.argv[2]
steps = job["steps"]
names = [s.get("name", "") for s in steps]
plan = next(s for s in steps if "Terraform plan" in s.get("name", ""))
apply_ = next(s for s in steps if s.get("name") == "Terraform apply")
write = next(s for s in steps if "Validate" in s.get("name", ""))
open(tmp + "/tierb-plan.sh", "w").write(plan["run"])
open(tmp + "/tierb-apply.sh", "w").write(apply_["run"])
open(tmp + "/tierb-write.sh", "w").write(write["run"])
json.dump({"checkout": steps[0], "all_text": yaml.safe_dump(job), "write_env": write.get("env", {}),
           "order_ok": names.index(write["name"]) < names.index(plan["name"]) < names.index(apply_["name"]),
           "timeout": job["timeout-minutes"]}, open(tmp + "/tierb.json", "w"))
PY
tb() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$TMP/tierb.json" "$1"; }
GATE_JQ="$(python3 - "$TMP/tierb-plan.sh" <<'PY'
import sys
run = open(sys.argv[1]).read()
k = "jq -e --arg v \"$LINK_VALUE\" '"
a = run.index(k) + len(k)
print(run[a:run.index("' >/dev/null", a)])
PY
)"
plan() { # <address=action[,action]>... -> a plan whose resource_changes carry those (address:action) pairs
  python3 - "$@" <<'PY'
import json, sys
rc = []
for a in sys.argv[1:]:
    addr, act = a.rsplit("=", 1)
    rc.append({"address": addr, "change": {"actions": act.split(",")}})
print(json.dumps({"resource_changes": rc}))
PY
}
gate() { plan "${@:2}" | jq -e --arg v "$1" "$GATE_JQ" >/dev/null 2>&1; echo $?; }
FLAG='doppler_secret.inngest_link_tls[0]'
[[ -n "$GATE_JQ" ]] || bad "A26 could not extract the gate's jq program from the Tier-B job"
[[ "$(gate off "$FLAG=delete")" == 0 ]] && ok "A26 gate: off with exactly one delete of the flag passes" || bad "A26"
[[ "$(gate off)" == 0 ]] && ok "A27 gate: off with a ZERO-change plan PASSES (the flag is already absent: idempotent, the redeploy still follows)" || bad "A27"
[[ "$(gate off "$FLAG=no-op")" == 0 ]] && ok "A27b gate: off with a no-op flag resource passes (no change is planned)" || bad "A27b"
[[ "$(gate off "$FLAG=delete" "doppler_secret.other[0]=delete")" == 1 && "$(gate off "$FLAG=delete" "$FLAG=delete")" == 1 ]] && ok "A28 gate: off that also deletes another address, or deletes twice, FAILS" || bad "A28"
[[ "$(gate off "$FLAG=create")" == 1 && "$(gate off "$FLAG=update")" == 1 && "$(gate off "$FLAG=create,delete")" == 1 ]] && ok "A28b gate: off that plans a create, an update or a replace FAILS (off never changes anything but a delete)" || bad "A28b"
[[ "$(gate 1 "$FLAG=update")" == 0 && "$(gate 1 "$FLAG=create")" == 0 && "$(gate pending:1000000000 "$FLAG=create")" == 0 && "$(gate pending:1000000000 "$FLAG=update")" == 0 ]] && ok "A29 gate: 1 and pending:<epoch> pass on exactly one create or update of the flag" || bad "A29"
[[ "$(gate 1)" == 1 && "$(gate pending:1000000000)" == 1 && "$(gate 1 "$FLAG=no-op")" == 1 && "$(gate pending:1000000000 "$FLAG=no-op")" == 1 ]] && ok "A29b gate: a value (1 or pending) with a ZERO-change or no-op plan FAILS (the value did not land; reporting success would print FLIPPED over an unchanged flag)" || bad "A29b"
[[ "$(gate 1 "$FLAG=delete")" == 1 && "$(gate 1 "$FLAG=update" "doppler_secret.other[0]=update")" == 1 && "$(gate 1 "$FLAG=create,delete")" == 1 && "$(gate 1 "$FLAG=update" "$FLAG=update")" == 1 ]] && ok "A30 gate: a value fails on a delete, a replace, a second changed address or a duplicate" || bad "A30"

# A31-A33: static pins on the job.
[[ "$(tb 'd["order_ok"] and d["write_env"].get("DOPPLER_TOKEN") == "${{ secrets.DOPPLER_TOKEN_WRITE }}"')" == True ]] && grep -q 'secrets set INNGEST_LINK_TLS' "$TMP/tierb-write.sh" && grep -q 'secrets delete INNGEST_LINK_TLS' "$TMP/tierb-write.sh" \
  && ok "A31 the source-key step runs BEFORE the plan and the apply and holds the write-scoped token (DOPPLER_TOKEN_WRITE)" || bad "A31 source-key step"
python3 -c 'import re,sys; s=re.sub(r"\\\n\s*", " ", open(sys.argv[1]).read()); sys.exit(1 if re.search(r"secrets delete INNGEST_LINK_TLS[^\n]*\|\| true", s) else 0)' "$TMP/tierb-write.sh" && ok "A31b the source-key delete is never swallowed (no || true on it)" || bad "A31b a swallowed delete"
[[ "$(tb 'd["checkout"].get("with", {}).get("persist-credentials")')" == False ]] && ok "A32 the job's checkout sets persist-credentials: false (the Doppler write token is not a git credential; nothing in the job pushes or fetches over git)" || bad "A32 checkout credentials"
APPLY_LINE="$(grep -E '^[[:space:]]*terraform apply ' "$TMP/tierb-apply.sh" | sed 's/^[[:space:]]*//')"
[[ "$APPLY_LINE" == "terraform apply -no-color -input=false -auto-approve tfplan" ]] && ok "A33 the apply argv is exactly '-auto-approve tfplan': only the gated, saved plan is applied (no -target, -replace, -var, no re-plan)" || bad "A33 apply argv: '$APPLY_LINE'"
sed 's/ tfplan$//' "$TMP/tierb-apply.sh" > "$TMP/tierb-apply-mut.sh"
APPLY_MUT="$(grep -E '^[[:space:]]*terraform apply ' "$TMP/tierb-apply-mut.sh" | sed 's/^[[:space:]]*//')"
[[ "$APPLY_MUT" != "terraform apply -no-color -input=false -auto-approve tfplan" ]] && ok "A33m a mutated apply (the plan operand dropped, which re-plans untargeted and applies ALL drift) no longer equals the pinned argv" || bad "A33m"

# The stateful fakes. soleur/prd and soleur/prd_terraform are directories of key files; DOPPLER_INHERIT=1 makes prd_terraform's
# view also show prd's keys (the world the repo once assumed); DOPPLER_INHERIT=0 is the MEASURED world. The fake terraform
# keeps the flag resource's state, plans from the TF_VAR it was handed (count 0 when empty), and its apply writes/removes the
# prd secret the way doppler_secret.inngest_link_tls does.
make_tb_fakes() { # dir
  local d="$1"; assert_fixture_dir "$d"; mkdir -p "$d/bin" "$d/dop/prd" "$d/dop/prd_terraform"
  printf 'x' > "$d/dop/prd_terraform/AWS_ACCESS_KEY_ID"
  cat > "$d/bin/doppler" <<'SH'
#!/usr/bin/env bash
echo "doppler $*" >> "$STUB/doppler.log"
in=""; if [[ "$1 $2" == "secrets set" ]]; then in="$(cat)"; fi
cfg=""; args=("$@"); i=0
while (( i < ${#args[@]} )); do [[ "${args[i]}" == -c ]] && cfg="${args[i+1]}"; i=$((i + 1)); done
view() { { ls "$STUB/dop/$cfg" 2>/dev/null; [[ "$cfg" == prd_terraform && "${DOPPLER_INHERIT:-0}" == 1 ]] && ls "$STUB/dop/prd" 2>/dev/null; } | sort -u; }
val() { if [[ -f "$STUB/dop/$cfg/$1" ]]; then cat "$STUB/dop/$cfg/$1"; elif [[ "$cfg" == prd_terraform && "${DOPPLER_INHERIT:-0}" == 1 && -f "$STUB/dop/prd/$1" ]]; then cat "$STUB/dop/prd/$1"; else return 1; fi; }
case "$1 $2" in
  "secrets --only-names") [[ "${DOPPLER_LIST_FAIL:-0}" == 1 ]] && exit 1; view ;;
  "secrets get") val "$3" ;;
  "secrets set") [[ "${DOPPLER_SET_FAIL:-0}" == 1 ]] && exit 1; printf '%s' "$in" > "$STUB/dop/$cfg/$3" ;;
  "secrets delete") [[ "${DOPPLER_DELETE_FAIL:-0}" == 1 ]] && exit 1; [[ "${DOPPLER_DELETE_NOOP:-0}" == 1 ]] || rm -f "$STUB/dop/$cfg/$3" ;;
  "run "*)
    while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done; shift
    for n in $(view); do v="$(val "$n")"; export "TF_VAR_$(tr 'A-Z' 'a-z' <<<"$n")=$v"; done
    exec "$@" ;;
esac
SH
  assert_fixture_dir "$d"
  cat > "$d/bin/terraform" <<'SH'
#!/usr/bin/env bash
echo "terraform $*" >> "$STUB/tf.log"
case "$1" in
  plan)
    var="${TF_VAR_inngest_link_tls-}"; cur=""; [[ -f "$STUB/tfstate" ]] && cur="$(cat "$STUB/tfstate")"; act=""
    if [[ -z "$var" ]]; then [[ -f "$STUB/tfstate" ]] && act=delete
    elif [[ ! -f "$STUB/tfstate" ]]; then act=create
    elif [[ "$cur" != "$var" ]]; then act=update; fi
    echo "TFVAR=[$var] ACT=[$act] TARGET=[$(grep -c -- '-target=' <<<"$*" || true)]" >> "$STUB/tf.log"
    printf '%s' "$var" > "$STUB/plan.value"
    if [[ -n "$act" ]]; then printf '{"resource_changes":[{"address":"doppler_secret.inngest_link_tls[0]","change":{"actions":["%s"]}}]}' "$act" > "$STUB/plan.json"; else printf '{"resource_changes":[]}' > "$STUB/plan.json"; fi
    : > tfplan ;;
  show) cat "$STUB/plan.json" ;;
  apply)
    act="$(jq -r '.resource_changes[0].change.actions[0] // ""' "$STUB/plan.json")"
    case "$act" in
      create|update) cp "$STUB/plan.value" "$STUB/tfstate"; cp "$STUB/plan.value" "$STUB/dop/prd/INNGEST_LINK_TLS" ;;
      delete) rm -f "$STUB/tfstate" "$STUB/dop/prd/INNGEST_LINK_TLS" ;;
    esac ;;
esac
SH
  chmod +x "$d/bin/"*
}
tb_env() { # dir -> runs "$@" with the job's environment in dir
  local d="$1"; shift
  ( cd "$d" && env -i PATH="$d/bin:/usr/local/bin:/usr/bin:/bin" HOME="$d" STUB="$d" RUNNER_TEMP="$d" CI_SSH_PUB=/x/key.pub REASON_RAW="flip test" DOPPLER_TOKEN=tok \
      GITHUB_SERVER_URL=https://example.invalid GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_OUTPUT="$d/out" GITHUB_STEP_SUMMARY="$d/summary" "$@" 2>&1 )
}
run_tb_job() { # dir value [write-script] [plan-script] [apply-script] [env assignments...] -> TB_RC, TB_OUT, TB_STAGE; stops at the first failing step like Actions
  local d="$1" value="$2" ws="${3:-$TMP/tierb-write.sh}" ps="${4:-$TMP/tierb-plan.sh}" as="${5:-$TMP/tierb-apply.sh}"; shift 5 2>/dev/null || shift $#
  assert_fixture_dir "$d"; : > "$d/out"; : > "$d/summary"; TB_OUT=""; TB_RC=0; TB_STAGE=done
  local stage script o
  for stage in write plan apply; do
    case "$stage" in write) script="$ws" ;; plan) script="$ps" ;; apply) script="$as" ;; esac
    o="$(tb_env "$d" LINK_VALUE="$value" DOPPLER_INHERIT="${DOPPLER_INHERIT:-0}" "$@" bash "$script")"; TB_RC=$?
    TB_OUT+="$o"$'\n'
    if (( TB_RC != 0 )); then TB_STAGE=$stage; return 0; fi
  done
}
untargeted_changes() { # dir -> the number of changes an UNTARGETED plan (drift detector, full apply) would see; reads the config as prd_terraform
  local d="$1"
  tb_env "$d" DOPPLER_INHERIT="${DOPPLER_INHERIT:-0}" "$d/bin/doppler" run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -out=tfplan-full >/dev/null
  jq '.resource_changes | length' "$d/plan.json"
}
prdt() { cat "$1/dop/prd_terraform/INNGEST_LINK_TLS" 2>/dev/null || echo ABSENT; }
prdv() { cat "$1/dop/prd/INNGEST_LINK_TLS" 2>/dev/null || echo ABSENT; }
sumres() { grep -o 'Flag result: [a-z_]*' "$1/summary" 2>/dev/null | tail -1 | sed 's/Flag result: //'; }

# --- the MEASURED world: no inheritance ---
D="$(fresh tb-noinh)"; make_tb_fakes "$D"; export DOPPLER_INHERIT=0
PEND="pending:$(date +%s)"
run_tb_job "$D" "$PEND"
[[ "$TB_RC" == 0 && "$(prdt "$D")" == "$PEND" && "$(prdv "$D")" == "$PEND" && "$(sumres "$D")" == applied && "$(untargeted_changes "$D")" == 0 ]] \
  && ok "A34 no inheritance, pending: the source key holds the value in prd_terraform, the apply wrote prd, and the UNTARGETED plan view sees zero changes" || bad "A34 rc=$TB_RC stage=$TB_STAGE prdt=$(prdt "$D") prd=$(prdv "$D")" "$TB_OUT"
run_tb_job "$D" 1
[[ "$TB_RC" == 0 && "$(prdt "$D")" == 1 && "$(prdv "$D")" == 1 && "$(untargeted_changes "$D")" == 0 ]] && ok "A35 no inheritance, 1 after pending: key and secret both read 1 and the untargeted view is clean" || bad "A35 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"
grep -q 'TFVAR=\[1\]' "$D/tf.log" && ok "A35b the plan was handed the explicit variable (1)" || bad "A35b" "$(cat "$D/tf.log")"
run_tb_job "$D" off
[[ "$TB_RC" == 0 && "$(prdt "$D")" == ABSENT && "$(prdv "$D")" == ABSENT && "$(sumres "$D")" == removed && "$(untargeted_changes "$D")" == 0 ]] \
  && ok "A36 no inheritance, off: the source key AND the prd secret are gone, result=removed, and the untargeted view still sees zero changes (no destroy, no re-create)" || bad "A36 rc=$TB_RC stage=$TB_STAGE prdt=$(prdt "$D") prd=$(prdv "$D")" "$TB_OUT"
grep -q 'TFVAR=\[\]' "$D/tf.log" && ok "A36b the off plan was handed an EMPTY explicit variable" || bad "A36b" "$(cat "$D/tf.log")"
run_tb_job "$D" off
[[ "$TB_RC" == 0 && "$(sumres "$D")" == already_absent && "$(untargeted_changes "$D")" == 0 ]] && ok "A37 off after off: the job passes with result=already_absent (idempotent)" || bad "A37 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"

D="$(fresh tb-zero)"; make_tb_fakes "$D"; printf '%s' "$PEND" > "$D/tfstate"; printf '%s' "$PEND" > "$D/dop/prd/INNGEST_LINK_TLS"
run_tb_job "$D" "$PEND"
[[ "$TB_RC" != 0 && "$TB_STAGE" == plan && "$TB_OUT" == *"blast-radius gate"* ]] && ok "A38 a value that is already in force plans zero changes and the job FAILS at the gate (the value did not land)" || bad "A38 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"

D="$(fresh tb-delfail)"; make_tb_fakes "$D"; printf '1' > "$D/dop/prd_terraform/INNGEST_LINK_TLS"; printf '1' > "$D/tfstate"; printf '1' > "$D/dop/prd/INNGEST_LINK_TLS"
run_tb_job "$D" off "" "" "" DOPPLER_DELETE_FAIL=1
[[ "$TB_RC" != 0 && "$TB_STAGE" == write && ! -f "$D/tf.log" && "$(prdv "$D")" == 1 && "$TB_OUT" == *"failed"* ]] && ok "A39 off whose key delete FAILS stops at the write step: no plan, the prd secret untouched, a named error (not swallowed)" || bad "A39 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"
D="$(fresh tb-listfail)"; make_tb_fakes "$D"; printf '1' > "$D/dop/prd_terraform/INNGEST_LINK_TLS"
run_tb_job "$D" off "" "" "" DOPPLER_LIST_FAIL=1
[[ "$TB_RC" != 0 && "$TB_STAGE" == write && ! -f "$D/tf.log" ]] && ok "A40 off when the key listing itself fails refuses to guess (a failed listing is never read as absence)" || bad "A40 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"
D="$(fresh tb-setfail)"; make_tb_fakes "$D"
run_tb_job "$D" 1 "" "" "" DOPPLER_SET_FAIL=1
[[ "$TB_RC" != 0 && "$TB_STAGE" == write && ! -f "$D/tf.log" ]] && ok "A41 a value whose source-key write fails stops before any plan" || bad "A41 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"

# --- the world the repo once assumed: prd_terraform INHERITS prd ---
export DOPPLER_INHERIT=1
D="$(fresh tb-inh)"; make_tb_fakes "$D"
run_tb_job "$D" 1
run_tb_job "$D" off
[[ "$TB_RC" == 0 && "$(prdt "$D")" == ABSENT && "$(prdv "$D")" == ABSENT && "$(untargeted_changes "$D")" == 0 ]] && grep -q 'TFVAR=\[\]' "$D/tf.log" && [[ "$TB_OUT" == *"still visible"* ]] && ok "A42 inheritance, off after 1: the delete leaves the key visible (inherited), the explicit empty variable still plans the delete, and the apply converges both copies to absent" || bad "A42 rc=$TB_RC stage=$TB_STAGE prdt=$(prdt "$D") prd=$(prdv "$D")" "$TB_OUT"
D="$(fresh tb-inh-only)"; make_tb_fakes "$D"; printf '1' > "$D/tfstate"; printf '1' > "$D/dop/prd/INNGEST_LINK_TLS"
run_tb_job "$D" off
[[ "$TB_RC" == 0 && "$TB_OUT" == *"still visible"* && "$(prdv "$D")" == ABSENT && "$(untargeted_changes "$D")" == 0 ]] && ok "A43 inheritance with NO own key (prd only, value 1): off warns that the key stays visible, plans the delete from the explicit empty variable and converges" || bad "A43 rc=$TB_RC stage=$TB_STAGE prd=$(prdv "$D")" "$TB_OUT"
export DOPPLER_INHERIT=0
D="$(fresh tb-leftover)"; make_tb_fakes "$D"; printf '1' > "$D/dop/prd_terraform/INNGEST_LINK_TLS"; printf '1' > "$D/tfstate"; printf '1' > "$D/dop/prd/INNGEST_LINK_TLS"
run_tb_job "$D" off "" "" "" DOPPLER_DELETE_NOOP=1
[[ "$TB_RC" != 0 && "$TB_STAGE" == apply && "$TB_OUT" == *"still present in soleur/prd_terraform after the apply"* ]] && ok "A44 a delete that was accepted but left the key behind fails the job AFTER the apply (untargeted plans would re-create the flag), loudly" || bad "A44 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"

# --- mutations of the job's steps ---
mut_step() { # name python-replace-expr-file-script -> $TMP/tierb-<name>.sh ; asserts it landed
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
m = s.replace(old, new) if old in s else None
if m is None or m == s:
    sys.exit(1)
open(dst, "w").write(m)
PY
}
# A46-A50: the Tier-B gate tolerates a data-source `read` entry; both doppler runs carry the config and the transformer; the job timeout is
# read from the parsed job; the VALIDATE half of the write step is EXECUTED (hand dispatches bypass the flip script's own regex).
[[ "$(gate off "data.doppler_secrets.x=read")" == 0 && "$(gate 1 "$FLAG=update" "data.doppler_secrets.x=read")" == 0 && "$(gate 1 "data.doppler_secrets.x=read")" == 1 ]] && ok "A46 gate: a data-source read entry is tolerated (it is not a change), and does not stand in for the flag's own create/update" || bad "A46"
D="$(fresh tb-argv)"; make_tb_fakes "$D"; unset DOPPLER_INHERIT
run_tb_job "$D" 1
ARGV_N="$(grep -c '^doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- ' "$D/doppler.log" || true)"
[[ "$TB_RC" == 0 && "$ARGV_N" == 2 ]] && ok "A47 both the plan and the apply run under 'doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var' (2 runs)" || bad "A47 rc=$TB_RC runs=$ARGV_N" "$(cat "$D/doppler.log")"
if mut_step "$TMP/tierb-apply.sh" "$TMP/tierb-apply-m6.sh" '--name-transformer tf-var' '--name-transformer none'; then
  D="$(fresh tb-m6)"; make_tb_fakes "$D"; run_tb_job "$D" 1 "" "" "$TMP/tierb-apply-m6.sh"
  [[ "$(grep -c '^doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- ' "$D/doppler.log" || true)" == 1 ]] && ok "A47m an apply without the tf-var transformer drops the count to 1 (so A47 can see it)" || bad "A47m"
else bad "A47m the transformer mutation matched nothing"; fi
[[ "$(tb 'd["timeout"]')" == 15 ]] && ok "A48 the job timeout is read from the parsed job and is 15 minutes" || bad "A48 timeout=$(tb 'd["timeout"]')"
NOW="$(date +%s)"
vrc() { # value reason [script] -> rc of the write step (its validation; the fakes accept the key write that follows)
  local d="$TMP/tb-val"; assert_fixture_dir "$d"; rm -rf "$d"; make_stubs "$d"; make_tb_fakes "$d"
  tb_env "$d" LINK_VALUE="$1" REASON_RAW="$2" DOPPLER_INHERIT=0 bash "${3:-$TMP/tierb-write.sh}" >/dev/null; echo $?
}
[[ "$(vrc on 'r')" != 0 && "$(vrc pending:123 'r')" != 0 && "$(vrc "pending:$((NOW - 700))" 'r')" != 0 && "$(vrc "pending:$((NOW + 90))" 'r')" != 0 && "$(vrc 2 'r')" != 0 && "$(vrc ' 1' 'r')" != 0 ]] \
  && ok "A49 the validate step, executed, refuses 'on', a short epoch, an epoch 700 s old, an epoch 90 s ahead and other junk" || bad "A49 refusals"
[[ "$(vrc 1 '')" != 0 && "$(vrc 1 '   ')" != 0 ]] && ok "A49b an empty or blank reason is refused" || bad "A49b reason"
[[ "$(vrc 1 'r')" == 0 && "$(vrc "pending:$NOW" 'r')" == 0 && "$(vrc "pending:$((NOW - 500))" 'r')" == 0 && "$(vrc off 'r')" == 0 ]] && ok "A49c valid values pass (non-vacuity of A49): 1, pending:<now>, pending:<now-500>, off" || bad "A49c"
if mut_step "$TMP/tierb-write.sh" "$TMP/tierb-write-m7.sh" 'if [[ ! "$LINK_VALUE" =~ ^(off|1|pending:[0-9]{10})$ ]]; then' 'if false; then'; then
  [[ "$(vrc on 'r' "$TMP/tierb-write-m7.sh")" == 0 ]] && ok "A50m with the allowlist regex deleted a typo like 'on' is accepted and WRITTEN as the flag (so A49 can see the regex)" || bad "A50m regex"
else bad "A50m the regex mutation matched nothing"; fi
if mut_step "$TMP/tierb-write.sh" "$TMP/tierb-write-m8.sh" 'if (( 10#$ep > now + 60 || 10#$ep < now - 600 )); then' 'if false; then'; then
  [[ "$(vrc "pending:$((NOW - 700))" 'r' "$TMP/tierb-write-m8.sh")" == 0 && "$(vrc "pending:$((NOW + 90))" 'r' "$TMP/tierb-write-m8.sh")" == 0 ]] && ok "A50m2 with the epoch window deleted a stale or future epoch is accepted (so A49 can see the window)" || bad "A50m2 window"
else bad "A50m2 the window mutation matched nothing"; fi
if mut_step "$TMP/tierb-write.sh" "$TMP/tierb-write-m9.sh" 'if [[ -z "${REASON_RAW// /}" || -z "${DOPPLER_TOKEN:-}" ]]; then' 'if false; then'; then
  [[ "$(vrc 1 '' "$TMP/tierb-write-m9.sh")" == 0 ]] && ok "A50m3 with the reason check deleted an empty reason is accepted (so A49b can see the check)" || bad "A50m3 reason"
else bad "A50m3 the reason mutation matched nothing"; fi

# M1: the delete failure is swallowed -> A39 must go red.
if mut_step "$TMP/tierb-write.sh" "$TMP/tierb-write-m1.sh" '|| { echo "::error::deleting the source key INNGEST_LINK_TLS from soleur/prd_terraform failed. Nothing was planned or applied."; exit 1; }' '|| true'; then
  D="$(fresh tb-m1)"; make_tb_fakes "$D"; printf '1' > "$D/dop/prd_terraform/INNGEST_LINK_TLS"; printf '1' > "$D/tfstate"; printf '1' > "$D/dop/prd/INNGEST_LINK_TLS"
  run_tb_job "$D" off "$TMP/tierb-write-m1.sh" "" "" DOPPLER_DELETE_FAIL=1
  [[ "$TB_STAGE" != write ]] && ok "A45m1 with the delete failure swallowed the job runs on past the write step (so A39 can see the guard)" || bad "A45m1 stage=$TB_STAGE"
else bad "A45m1 the swallow mutation matched nothing (the write step's shape drifted)"; fi
# M2: the source key is never written (the round-4 design) -> the untargeted view sees a DESTROY.
python3 - "$TMP/tierb-write.sh" "$TMP/tierb-write-m2.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = s.index("# The source key is written FIRST")
b = s.index("{\n  echo \"### inngest-link-flag dispatch\"")
open(sys.argv[2], "w").write(s[:a] + s[b:])
PY
D="$(fresh tb-m2)"; make_tb_fakes "$D"
run_tb_job "$D" "$PEND" "$TMP/tierb-write-m2.sh"
[[ "$TB_RC" == 0 && "$(untargeted_changes "$D")" != 0 ]] && ok "A45m2 without the source-key write an untargeted plan sees var '' against live state and proposes a change (the destroy this design exists to prevent), so A34 can see the write" || bad "A45m2 rc=$TB_RC changes=$(untargeted_changes "$D")" "$TB_OUT"
# M3: the post-apply absence check removed -> A44 must go red.
python3 - "$TMP/tierb-apply.sh" "$TMP/tierb-apply-m3.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = s.index("# `off` must leave NO source key behind")
open(sys.argv[2], "w").write(s[:a])
PY
D="$(fresh tb-m3)"; make_tb_fakes "$D"; printf '1' > "$D/dop/prd_terraform/INNGEST_LINK_TLS"; printf '1' > "$D/tfstate"; printf '1' > "$D/dop/prd/INNGEST_LINK_TLS"
run_tb_job "$D" off "" "" "$TMP/tierb-apply-m3.sh" DOPPLER_DELETE_NOOP=1
[[ "$TB_RC" == 0 ]] && ok "A45m3 without the post-apply check a leftover source key passes the job (so A44 can see the check)" || bad "A45m3 rc=$TB_RC stage=$TB_STAGE" "$TB_OUT"
# M4: the explicit env removed -> with an inherited-only key, off plans no delete and the prd secret survives (A43 must go red).
if mut_step "$TMP/tierb-plan.sh" "$TMP/tierb-plan-m4.sh" 'env "TF_VAR_inngest_link_tls=${TF_LINK}" \' 'env \'; then
  export DOPPLER_INHERIT=1
  D="$(fresh tb-m4)"; make_tb_fakes "$D"; printf '1' > "$D/tfstate"; printf '1' > "$D/dop/prd/INNGEST_LINK_TLS"
  run_tb_job "$D" off "" "$TMP/tierb-plan-m4.sh"
  [[ "$(prdv "$D")" == 1 ]] && ok "A45m4 without the explicit variable an inherited key survives an off (the prd secret stays 1), so A43 can see the env wrapper" || bad "A45m4 prd=$(prdv "$D") rc=$TB_RC stage=$TB_STAGE"
  export DOPPLER_INHERIT=0
else bad "A45m4 the env-wrapper mutation matched nothing (the plan step's shape drifted)"; fi
# M5: a value gate that tolerates a zero-change plan -> A38 must go red.
if mut_step "$TMP/tierb-plan.sh" "$TMP/tierb-plan-m5.sh" '(length == 1 and all(.[]; .change.actions == ["create"] or .change.actions == ["update"]))' '(length <= 1 and all(.[]; .change.actions == ["create"] or .change.actions == ["update"]))'; then
  D="$(fresh tb-m5)"; make_tb_fakes "$D"; printf '%s' "$PEND" > "$D/tfstate"; printf '%s' "$PEND" > "$D/dop/prd/INNGEST_LINK_TLS"
  run_tb_job "$D" "$PEND" "" "$TMP/tierb-plan-m5.sh"
  [[ "$TB_STAGE" != plan ]] && ok "A45m5 if a value tolerated a zero-change plan the gate would pass it (so A38 can see the gate)" || bad "A45m5 stage=$TB_STAGE"
else bad "A45m5 the zero-change mutation matched nothing (the gate's shape drifted)"; fi
unset DOPPLER_INHERIT

D="$(fresh happy)"; run_script "$D" "$BODY" flip
[[ "$RC" == 0 ]] && ok "B1 happy path exits 0" || bad "B1 rc=$RC" "$OUT"
[[ "$(values "$D")" == "pending 1 " ]] && ok "B2 the flag moves pending:<epoch> then 1, in that order, exactly twice" || bad "B2 values='$(values "$D")'"
[[ "$(order "$D")" == "dispatch started=1 track handshake dispatch started=1 " ]] && ok "B3 order: pending dispatch, then the track.sh redeploy, then the handshake, then the promotion" || bad "B3 order='$(order "$D")'"
[[ "$(started "$D")" == 1 ]] && ok "B4 started=true is written exactly once, and BEFORE the first flag dispatch (the stub gh saw it already set)" || bad "B4 started=$(started "$D") order='$(order "$D")'"
grep -q 'inngest_link_value=pending:1000000000 ' "$D/gh.log" && ok "B5 the lease epoch is EXACTLY the dispatch-time clock (the stub starts at 1000000000)" || bad "B5 epoch" "$(cat "$D/gh.log")"
[[ "$(cat "$D/track.log" 2>/dev/null)" == "track peers=10.0.1.10,10.0.1.11 timeout=4800 secret=set" ]] && ok "B6 track.sh is handed both peers, a bounded REDEPLOY_TIMEOUT_S and the secret under the name it reads (WEBHOOK_DEPLOY_SECRET)" || bad "B6 track env: $(cat "$D/track.log" 2>/dev/null)"
[[ "$OUT" != *"$SECRET_W"* && "$OUT" != *"$SECRET_ID"* && "$OUT" != *"$SECRET_SECRET"* ]] && ok "B7 no credential reaches the output" || bad "B7 credential leaked"
grep -rq "$SECRET_W" "$D/gh.log" "$D/curl.log" "$D/track.log" 2>/dev/null && bad "B8 a credential reached a logged argument list" || ok "B8 no credential on any gh, curl or track argument list or log"
[[ "$OUT" == *"NOT VERIFIED"*"web-2"* && "$OUT" == *"resolved"* ]] && ok "B8b the final line states what was NOT verified (web-2's own swap, the resolved scheme)" || bad "B8b final line" "$OUT"
FLIPPED_LINE="$(grep '^FLIPPED:' <<<"$OUT")"
[[ "$FLIPPED_LINE" == *"scripts/betterstack-query.sh --since 2001-09-09T01:46:40Z --grep 'class=resolved'"* && "$FLIPPED_LINE" == *"soleur-web-platform"* && "$FLIPPED_LINE" == *"soleur-web-2"* \
   && "$FLIPPED_LINE" == *"state=https_pending scheme=https"* && "$FLIPPED_LINE" == *'select(.SYSLOG_IDENTIFIER == "ci-deploy")'* ]] \
  && ok "B8c the FLIPPED line prints the Better Stack query for the ci-deploy resolved row of EACH host (since the flip start, both host names, the https_pending state to expect)" || bad "B8c FLIPPED line" "$FLIPPED_LINE"
grep -q '^verdict=flipped$' "$D/github_output" && grep -q '^t=10' "$D/github_output" && grep -q '^flag_run=4242$' "$D/github_output" && grep -q '^started=true$' "$D/github_output" \
  && ok "B8d the run appends t=, flag_run= and verdict=flipped to \$GITHUB_OUTPUT (and started=true is still there)" || bad "B8d outputs" "$(cat "$D/github_output")"
grep -q '| verdict | flipped |' "$D/summary.md" && grep -q 'NOT VERIFIED' "$D/summary.md" && grep -q 'pending=4242' "$D/summary.md" \
  && ok "B8e the run writes a \$GITHUB_STEP_SUMMARY block (verdict, T, the flag apply run ids, NOT VERIFIED)" || bad "B8e summary" "$(cat "$D/summary.md" 2>/dev/null)"

D="$(fresh canary-fail)"; run_script "$D" "$BODY" flip TRACK_RC=1 TRACK_VERDICT=redeploy_terminal_failure
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"did not confirm a clean swap"* ]] && ok "B9 a failed canary/swap (track.sh exit 1) stops the run, names the failure and the flag is NEVER promoted to 1" || bad "B9 rc=$RC values='$(values "$D")'" "$OUT"
[[ "$(started "$D")" == 1 ]] && ok "B9b a failure AFTER the first flag write leaves started=true set (so the revert step runs)" || bad "B9b started=$(started "$D")"
grep -q '^verdict=failed$' "$D/github_output" && ok "B9f a failed run emits verdict=failed (the EXIT hook runs on the failure path)" || bad "B9f verdict" "$(cat "$D/github_output")"

D="$(fresh degraded)"; run_script "$D" "$BODY" flip TRACK_RC=1 TRACK_VERDICT=redeploy_peer_fanout_degraded
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$(tracked "$D")" == 1 ]] && ok "B9c a DEGRADED fleet redeploy (web-2 did not take the swap; track.sh exits non-zero) never reaches flip_apply_flag 1" || bad "B9c rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh degraded-real)"; run_script "$D" "$BODY" flip FLIP_TRACK="$REPO_ROOT/.github/actions/dispatch-web-redeploy/track.sh" REDEPLOY_POLL_INTERVAL_S=1 \
  TERMINAL_FRAME='{"component":"web-platform","exit_code":0,"reason":"ok_peer_fanout_degraded","tag":"v1.2.3","start_ts":1000000000}'
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"redeploy_peer_fanout_degraded"* ]] && ok "B9d the REAL track.sh on an exit_code 0 / ok_peer_fanout_degraded frame fails the flip (the frame the old inline loop accepted); no promotion" || bad "B9d rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh ok-real)"; run_script "$D" "$BODY" flip FLIP_TRACK="$REPO_ROOT/.github/actions/dispatch-web-redeploy/track.sh" REDEPLOY_POLL_INTERVAL_S=1
[[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "B9e the REAL track.sh on a clean ok frame lets the flip promote (non-vacuity of B9d)" || bad "B9e rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh lease)"; run_script "$D" "$BODY" flip TRACK_ADVANCE=2000
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"lease"* ]] && ok "B10 a deploy that outlives the 30-minute lease is NOT promoted" || bad "B10 rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh lease-margin)"; run_script "$D" "$BODY" flip TRACK_ADVANCE=1300
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"kept for web-2"* ]] && ok "B10b a redeploy finishing 1300 s into the 1800 s lease (inside the 600 s web-2 margin) is NOT promoted, and the message says why" || bad "B10b rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh lease-inside)"; run_script "$D" "$BODY" flip TRACK_ADVANCE=1100
[[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "B10c a redeploy finishing 1100 s into the lease (outside the margin) IS promoted (non-vacuity of B10b)" || bad "B10c rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh lease-offset)"; run_script "$D" "$BODY" flip
LEASE_OFF="$(sed -n 's/^FLIPPED:.*= \([0-9]*\)\. NOT VERIFIED.*/\1/p' <<<"$OUT")"; LEASE_OFF=$(( LEASE_OFF - 1000000000 ))
D="$(fresh lease-edge-ok)"; run_script "$D" "$BODY" flip TRACK_ADVANCE=$(( 1200 - LEASE_OFF ))
[[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "B10d a redeploy finishing EXACTLY at lease minus margin (t0+1200) IS promoted (the boundary is inclusive)" || bad "B10d rc=$RC off=$LEASE_OFF values='$(values "$D")'" "$OUT"
D="$(fresh lease-edge-over)"; run_script "$D" "$BODY" flip TRACK_ADVANCE=$(( 1201 - LEASE_OFF ))
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"kept for web-2"* ]] && ok "B10e one second past lease minus margin (t0+1201) is refused" || bad "B10e rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh pending-slow)"; run_script "$D" "$BODY" flip ADVANCE_EXTRA=1200
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"pending apply returned at +12"* ]] && ok "B10f a PENDING apply that itself takes 1200 s spends the lease: the redeploy that follows is refused, and the message says when the apply returned" || bad "B10f rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh stale-running)"; run_script "$D" "$BODY" flip IDLE_FRAME='{"component":"web-platform","exit_code":-1,"reason":"running","tag":"v1.2.2","start_ts":999995000}'
[[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "B12b a stale running frame (exit_code -1, 5000 s old: past the wrapper's 4800 s hard kill) does NOT block a flip" || bad "B12b rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh stale-edge)"; run_script "$D" "$BODY" flip IDLE_FRAME='{"component":"web-platform","exit_code":-1,"reason":"running","tag":"v1.2.2","start_ts":999995201}'
[[ "$RC" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B12c a running frame 4799 s old still blocks (it can still be live)" || bad "B12c rc=$RC dispatched=$(dispatched "$D")"
D="$(fresh stale-edge2)"; run_script "$D" "$BODY" flip IDLE_FRAME='{"component":"web-platform","exit_code":-1,"reason":"running","tag":"v1.2.2","start_ts":999995200}'
[[ "$RC" == 0 ]] && ok "B12d a running frame exactly 4800 s old no longer blocks (the guard is strict)" || bad "B12d rc=$RC"

D="$(fresh handshake)"; run_script "$D" "$BODY" flip HANDSHAKE_CODE=500 "HANDSHAKE_BODY=inngest-tls-handshake verified=fail verified_rc=60 unverified=fail unverified_rc=60 result=fail"
[[ "$RC" != 0 && "$(values "$D")" == "pending " ]] && ok "B11 a failed handshake probe stops before the promotion" || bad "B11 rc=$RC values='$(values "$D")'"
[[ "$OUT" == *"::error::"*"HTTP 500"*"verified_rc=60"*"result=fail"* ]] && ok "B11b the ::error:: on a non-200 carries the hook's body (the REAL one-line token format), so a CA rejection (verified_rc=60) is readable without the host" || bad "B11b" "$OUT"
D="$(fresh handshake-fail200)"; run_script "$D" "$BODY" flip "HANDSHAKE_BODY=inngest-tls-handshake verified=200 verified_rc=0 unverified=ACCEPTED unverified_rc=0 result=fail"
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"unverified=ACCEPTED"* ]] && ok "B11c a 200 whose body says result=fail (the listener accepts an unverified client) is NOT a pass, and the body is printed" || bad "B11c rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh handshake-foreign)"; run_script "$D" "$BODY" flip 'HANDSHAKE_BODY={"registry_empty":false}'
[[ "$RC" != 0 && "$(values "$D")" == "pending " ]] && ok "B11d a 200 from a mis-routed hook (registry JSON, not the handshake line) is NOT a pass" || bad "B11d rc=$RC values='$(values "$D")'"
INJ="inngest-tls-handshake verified=fail"$'\r\n'"::error::pwned $(printf 'x%.0s' $(seq 1 600))"
D="$(fresh handshake-inject)"; run_script "$D" "$BODY" flip HANDSHAKE_CODE=500 "HANDSHAKE_BODY=$INJ"
PW="$(grep -c '^::error::pwned' <<<"$OUT" || true)"; BODYLEN="$(grep -o 'body: .*' <<<"$OUT" | head -1 | wc -c)"
[[ "$RC" != 0 && "$PW" == 0 && "$BODYLEN" -le 320 ]] && ok "B11e a hostile body cannot start a workflow command (no CR/LF, no colon) and is capped at 300 characters" || bad "B11e pw=$PW len=$BODYLEN" "$OUT"

D="$(fresh deploy-busy)"; run_script "$D" "$BODY" flip IDLE_FRAME="{\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
[[ "$RC" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B12 a deploy already running blocks the flip before any dispatch" || bad "B12 rc=$RC dispatched=$(dispatched "$D")"

D="$(fresh apply-busy)"; echo 1 > "$D/state/busy"; run_script "$D" "$BODY" flip
[[ "$RC" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B13 an apply in flight blocks the flip before any dispatch" || bad "B13 rc=$RC dispatched=$(dispatched "$D")"

D="$(fresh flag-job-fails)"; printf '1\n' > "$D/state/watch_rcs"; run_script "$D" "$BODY" flip
[[ "$RC" != 0 && "$(tracked "$D")" == 0 && "$(values "$D")" == "pending " ]] && ok "B14 a failed flag job stops the run before any redeploy is requested" || bad "B14 rc=$RC tracked=$(tracked "$D")"

D="$(fresh deploy-rejected)"; run_script "$D" "$BODY" flip TRACK_RC=1 TRACK_VERDICT=redeploy_dispatch_rejected
[[ "$RC" != 0 && "$(values "$D")" == "pending " ]] && ok "B15 a rejected deploy dispatch (track.sh exit 1) stops the run" || bad "B15 rc=$RC"

D="$(fresh off)"; run_script "$D" "$BODY" off
[[ "$RC" == 0 && "$(values "$D")" == "off " && "$(tracked "$D")" -ge 1 ]] && ok "B16 off applies the flag-absent baseline then redeploys" || bad "B16 rc=$RC values='$(values "$D")'" "$OUT"
[[ "$(started "$D")" == 0 ]] && ok "B16b off writes no started output (a failed off is not reverted)" || bad "B16b started=$(started "$D")"
D="$(fresh off-busy)"; echo 1 > "$D/state/busy"
run_script "$D" "$BODY" off IDLE_FRAME="{\"component\":\"web-platform\",\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
[[ "$RC" == 0 && "$(values "$D")" == "off " && "$(tracked "$D")" -ge 1 ]] && ok "B16c off proceeds with a deploy running AND an apply in flight (the release valve takes no idle guard)" || bad "B16c rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh off-off)"; run_script "$D" "$BODY" off; run_script "$D" "$BODY" off
[[ "$RC" == 0 && "$(values "$D")" == "off off " && "$(tracked "$D")" == 2 && "$OUT" == *"OFF: "* ]] && ok "B16e off after off: the second run applies the (idempotent) job again and STILL redeploys" || bad "B16e rc=$RC values='$(values "$D")' tracked=$(tracked "$D")" "$OUT"
grep -q '^verdict=off$' "$D/github_output" && ok "B16f a finished off emits verdict=off" || bad "B16f"
OFF_LINE="$(grep '^OFF:' <<<"$OUT")"
[[ "$OFF_LINE" == *"already absent"* && "$OFF_LINE" == *"state=http_default scheme=http"* && "$OFF_LINE" == *"scripts/betterstack-query.sh --since "* && "$OFF_LINE" == *"soleur-web-2"* ]] && ok "B16g the OFF line names the already-absent case and prints the resolved-row query with the http state to expect" || bad "B16g" "$OFF_LINE"
D="$(fresh off-fail)"; run_script "$D" "$BODY" off TRACK_RC=1
[[ "$RC" != 0 && "$OUT" != *"OFF: "* ]] && ok "B16d a failed redeploy after off exits non-zero and never prints the OFF summary" || bad "B16d rc=$RC" "$OUT"

D="$(fresh guard-refusal)"; run_script "$D" "$BODY" flip IDLE_FRAME="{\"component\":\"web-platform\",\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
[[ "$RC" != 0 && "$(started "$D")" == 0 && "$(dispatched "$D")" == 0 ]] && ok "B21 an idle-guard refusal writes no started output, so no revert (no off dispatch, no redeploy) can follow" || bad "B21 rc=$RC started=$(started "$D")"
grep -q '^verdict=refused$' "$D/github_output" && ok "B21b a guard refusal emits verdict=refused (nothing was written)" || bad "B21b" "$(cat "$D/github_output" 2>/dev/null)"
D="$(fresh no-peers)"; run_script "$D" "$BODY" flip WEB_HOST_PRIVATE_IPS=
[[ "$RC" != 0 && "$(started "$D")" == 0 && "$(dispatched "$D")" == 0 && "$(tracked "$D")" == 0 ]] && ok "B22 an empty fan-out roster is refused before anything is written or dispatched (a one-host redeploy is a mixed fleet)" || bad "B22 rc=$RC"

D="$(fresh revert)"; printf '1\n1\n' > "$D/state/watch_rcs"; run_script "$D" "$BODY" revert
[[ "$RC" == 0 && "$(values "$D")" == "off " && "$(tracked "$D")" == 1 ]] && ok "B17 revert exits 0 even when its own flag job fails, and it did try off and the redeploy" || bad "B17 rc=$RC values='$(values "$D")'" "$OUT"
[[ "$OUT" == *"REVERT-INCOMPLETE:"*"NOT VERIFIED"* ]] && grep -q '^verdict=revert_incomplete$' "$D/github_output" && ok "B17b a revert whose off apply failed ends with REVERT-INCOMPLETE, the NOT VERIFIED sentence and verdict=revert_incomplete" || bad "B17b" "$OUT"
D="$(fresh revert-ok)"; run_script "$D" "$BODY" revert
[[ "$RC" == 0 && "$OUT" == *"REVERTED:"* && "$OUT" != *"REVERT-INCOMPLETE"* && "$OUT" == *"NOT VERIFIED"*"web-2"* && "$OUT" == *"state=http_default scheme=http"* ]] && grep -q '^verdict=reverted$' "$D/github_output" \
  && ok "B17c a clean revert ends with REVERTED, the NOT VERIFIED sentence, the resolved-row query and verdict=reverted" || bad "B17c rc=$RC" "$OUT"
D="$(fresh revert-nogh)"; GH_RUN_RC=1 run_script "$D" "$BODY" revert GH_RUN_RC=1
[[ "$RC" == 0 && "$OUT" == *"REVERT-INCOMPLETE:"* ]] && ok "B18 revert exits 0 when the dispatch itself is refused (and says REVERT-INCOMPLETE)" || bad "B18 rc=$RC" "$OUT"

D="$(fresh stale-run)"; : > "$D/state/stale_old"; run_script "$D" "$BODY" flip
[[ "$RC" == 0 && "$(sort -u "$D/watched.log" | tr '\n' ' ')" == "4242 " ]] && ok "B23 a green run from an EARLIER flip inside the last 20 (created before the dispatch) is never watched: only OUR run is" || bad "B23 rc=$RC watched='$(tr '\n' ' ' < "$D/watched.log")'" "$OUT"
D="$(fresh skipped-run)"; echo skipped > "$D/state/first_recent"; run_script "$D" "$BODY" flip
[[ "$RC" == 0 && "$(sort -u "$D/watched.log" | tr '\n' ' ')" == "4242 " ]] && ok "B24 a recent run whose inngest_link_flag job was SKIPPED (another apply_target) is never watched" || bad "B24 rc=$RC watched='$(tr '\n' ' ' < "$D/watched.log")'" "$OUT"
D="$(fresh none-run)"; echo none > "$D/state/first_recent"; run_script "$D" "$BODY" flip
[[ "$RC" == 0 && "$(sort -u "$D/watched.log" | tr '\n' ' ')" == "4242 " ]] && ok "B24b a recent run with no inngest_link_flag job yet (queued behind the mutex) is not mistaken for ours" || bad "B24b rc=$RC" "$OUT"

D="$(fresh badvalue)"; ( source "$BODY"; PATH="$D/bin:$PATH" STUB="$D"; flip_apply_flag 'pending:abc' ) >/dev/null 2>&1; rcv=$?
[[ "$rcv" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B19 a flag value outside {off, 1, pending:<epoch>} is refused before any call" || bad "B19 rc=$rcv"
D="$(fresh nomode)"; run_script "$D" "$BODY" bogus
[[ "$RC" == 64 ]] && ok "B20 an unknown subcommand exits 64" || bad "B20 rc=$RC"

printf '\n=== C. mutations (each guard removed; the scenario that needs it must now promote) ===\n'
mutate() { # name sed-expression -> $TMP/mut-<name>.sh ; asserts it landed
  sed "$2" "$BODY" > "$TMP/mut-$1.sh"
  if cmp -s "$TMP/mut-$1.sh" "$BODY"; then bad "C-$1 the mutation matched nothing (the script's shape drifted)"; return 1; fi
}
if mutate lease 's/  if (( done_at > t0 + FLIP_LEASE_S - FLIP_LEASE_MARGIN_S )); then/  if false; then/'; then
  D="$(fresh m-lease)"; run_script "$D" "$TMP/mut-lease.sh" flip ADVANCE_EXTRA=900
  [[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "C1 without the lease check a lapsed lease IS promoted (so B10 can see the guard)" || bad "C1 rc=$RC values='$(values "$D")'"
fi
if mutate margin 's/  if (( done_at > t0 + FLIP_LEASE_S - FLIP_LEASE_MARGIN_S )); then/  if (( done_at > t0 + FLIP_LEASE_S )); then/'; then
  D="$(fresh m-margin)"; run_script "$D" "$TMP/mut-margin.sh" flip TRACK_ADVANCE=1300
  [[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "C10 without the web-2 margin a redeploy finishing inside it IS promoted (so B10b can see the margin)" || bad "C10 rc=$RC values='$(values "$D")'"
fi
if mutate stale 's/\[\[ "\$(date -u -d "\$created" +%s 2>\/dev\/null || echo 0)" -ge \$((t0 - 10)) \]\] || continue/:/'; then
  D="$(fresh m-stale)"; : > "$D/state/stale_old"; run_script "$D" "$TMP/mut-stale.sh" flip
  [[ "$(head -1 "$D/watched.log")" == 4141 ]] && ok "C11 without the creation-time filter the EARLIER flip's green run is the one watched (so B23 can see the filter)" || bad "C11 watched='$(tr '\n' ' ' < "$D/watched.log")'"
fi
if mutate skipped 's/\[\[ "\$cj" == none || "\$cj" == skipped \]\] \&\& continue/:/'; then
  D="$(fresh m-skipped)"; echo skipped > "$D/state/first_recent"; run_script "$D" "$TMP/mut-skipped.sh" flip
  [[ "$(head -1 "$D/watched.log")" == 4143 ]] && ok "C12 without the skipped/none filter a skipped run is the one watched (so B24 can see the filter)" || bad "C12 watched='$(tr '\n' ' ' < "$D/watched.log")'"
fi
if mutate hspass 's/ || "\$body" != \*" result=pass"\* \]\]; then/ ]]; then/'; then
  D="$(fresh m-hspass)"; run_script "$D" "$TMP/mut-hspass.sh" flip "HANDSHAKE_BODY=inngest-tls-handshake verified=200 verified_rc=0 unverified=ACCEPTED unverified_rc=0 result=fail"
  [[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "C13 without the result=pass check a 200 whose body says result=fail IS promoted (so B11c can see the check)" || bad "C13 rc=$RC values='$(values "$D")'"
fi
if mutate final 's/^    FLIP_VERDICT=reverted$/    FLIP_VERDICT=revert_incomplete/'; then
  D="$(fresh m-final)"; run_script "$D" "$TMP/mut-final.sh" revert
  grep -q '^verdict=reverted$' "$D/github_output" && bad "C14 the revert verdict mutation did not change the output" || ok "C14 a revert that never reaches its REVERTED verdict is visible in the output (so B17c can see it)"
fi
if mutate verify 's/^  flip_verify "\$t0" "\$FLIP_DONE_AT"$/  :/'; then
  D="$(fresh m-verify)"; run_script "$D" "$TMP/mut-verify.sh" flip HANDSHAKE_CODE=500
  [[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "C2 without flip_verify a failed handshake IS promoted (so B11 can see the guard)" || bad "C2 rc=$RC values='$(values "$D")'"
fi
if mutate guard 's/^  flip_load_bearer; flip_require_peers; flip_guard_idle$/  flip_load_bearer; flip_require_peers/'; then
  D="$(fresh m-guard)"; run_script "$D" "$TMP/mut-guard.sh" flip IDLE_FRAME="{\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
  [[ "$(dispatched "$D")" -ge 1 ]] && ok "C4 without the idle guard the flip dispatches behind a running deploy (so B12 can see the guard)" || bad "C4 dispatched=$(dispatched "$D")"
fi
if mutate watch 's/  timeout "\$FLIP_WATCH_TIMEOUT_S" gh run watch "\$id" --exit-status --interval 10 >\/dev\/null \\/  timeout "$FLIP_WATCH_TIMEOUT_S" gh run watch "$id" --interval 10 >\/dev\/null || true; true \\/'; then
  D="$(fresh m-watch)"; printf '1\n' > "$D/state/watch_rcs"; run_script "$D" "$TMP/mut-watch.sh" flip
  [[ "$(tracked "$D")" -ge 1 ]] && ok "C5 without --exit-status a failed flag job is ignored and the deploy proceeds (so B14 can see the guard)" || bad "C5 tracked=$(tracked "$D")" "$OUT"
fi
if mutate trackrc 's/^    || { flip_err "the fleet redeploy (track.sh).*$/    || true/'; then
  D="$(fresh m-trackrc)"; run_script "$D" "$TMP/mut-trackrc.sh" flip TRACK_RC=1 TRACK_VERDICT=redeploy_peer_fanout_degraded
  [[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "C6 if the track.sh verdict is ignored a degraded fleet redeploy IS promoted (so B9c can see the guard)" || bad "C6 rc=$RC values='$(values "$D")'"
fi
if mutate started 's/^  if \[\[ -n "\${GITHUB_OUTPUT:-}" \]\]; then printf .started=true.*$/  :/'; then
  D="$(fresh m-started)"; run_script "$D" "$TMP/mut-started.sh" flip
  [[ "$(started "$D")" == 0 ]] && ok "C7 without flip_mark_started no started output is written (so B4/B9b can see the marker)" || bad "C7 started=$(started "$D")"
fi
if mutate peers 's/^  flip_load_bearer; flip_require_peers; flip_guard_idle$/  flip_load_bearer; flip_guard_idle/'; then
  D="$(fresh m-peers)"; run_script "$D" "$TMP/mut-peers.sh" flip WEB_HOST_PRIVATE_IPS=
  [[ "$(tracked "$D")" -ge 1 ]] && ok "C8 without flip_require_peers an empty roster reaches track.sh (so B22 can see the guard)" || bad "C8 tracked=$(tracked "$D")"
fi
if mutate offguard 's/^  flip_load_bearer; flip_require_peers$/  flip_load_bearer; flip_require_peers; flip_guard_idle/'; then
  D="$(fresh m-offguard)"; echo 1 > "$D/state/busy"; run_script "$D" "$TMP/mut-offguard.sh" off
  [[ "$RC" != 0 && "$(dispatched "$D")" == 0 ]] && ok "C9 with an idle guard on off, a running apply blocks the release valve (so B16c can see its absence)" || bad "C9 rc=$RC dispatched=$(dispatched "$D")"
fi

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
FLOOR=140
if (( PASS + FAIL < FLOOR )); then
  printf 'FAIL ANTI-VACUITY: %d assertions ran, floor is %d\n' $((PASS + FAIL)) "$FLOOR" >&2
  exit 1
fi
if (( PASS + FAIL > FLOOR )); then
  printf 'FAIL FLOOR DRIFT: %d assertions ran but FLOOR is %d - set FLOOR=%d (the floor is the real count)\n' $((PASS + FAIL)) "$FLOOR" $((PASS + FAIL)) >&2
  exit 1
fi
exit $(( FAIL > 0 ))
