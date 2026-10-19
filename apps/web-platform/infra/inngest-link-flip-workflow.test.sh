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
#      "stops" to "promotes" (a guard no scenario can see is not a guard).
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
[[ "$(yq 'job["timeout-minutes"] <= 180')" == True ]] && ok "A4 the job has a bounded timeout-minutes" || bad "A4 timeout"
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
check "A14 the flip needs the FLIP-INNGEST-LINK typo-guard before any call" grep -q 'FLIP-INNGEST-LINK' "$WF"
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
check "A20 the script parses clean (bash -n)" bash -n "$BODY"
if command -v shellcheck >/dev/null 2>&1; then check "A21 shellcheck is clean" shellcheck "$BODY"; else ok "A21 shellcheck not installed; skipped"; fi

# A26-A31: the Tier-B job's blast-radius gate, run as jq against synthesized plan JSON. `off` must plan EXACTLY ONE delete of
# the flag: a zero-change plan (the source-key delete failed silently and the flag is still live) must FAIL, or the flip
# script would report "flag removed" over a live flag.
GATE_JQ="$(python3 - "$APPLY_WF" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
run = next(s["run"] for s in d["jobs"]["inngest_link_flag"]["steps"] if "blast-radius" in s.get("run", ""))
a = run.index("jq -e --arg v \"$LINK_VALUE\" '") + len("jq -e --arg v \"$LINK_VALUE\" '")
print(run[a:run.index("' >/dev/null", a)])
PY
)"
plan() { # <action-json>... -> a plan whose resource_changes carry those (address:action) pairs
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
[[ "$(gate off)" == 1 ]] && ok "A27 gate: off with a ZERO-change plan FAILS (the silent-delete-failure case)" || bad "A27"
[[ "$(gate off "$FLAG=no-op")" == 1 ]] && ok "A27b gate: off with a no-op flag resource FAILS" || bad "A27b"
[[ "$(gate off "$FLAG=delete" "doppler_secret.other[0]=delete")" == 1 ]] && ok "A28 gate: off that also deletes another address FAILS" || bad "A28"
[[ "$(gate off "$FLAG=create")" == 1 ]] && ok "A28b gate: off that plans a create FAILS" || bad "A28b"
[[ "$(gate 1 "$FLAG=update")" == 0 && "$(gate pending:1000000000 "$FLAG=create")" == 0 ]] && ok "A29 gate: 1 and pending:<epoch> pass on update / create of the flag" || bad "A29"
[[ "$(gate 1 "$FLAG=delete")" == 1 && "$(gate 1 "$FLAG=update" "doppler_secret.other[0]=update")" == 1 ]] && ok "A30 gate: a non-off value fails on a delete or on any other changed address" || bad "A30"

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
      *) echo "4242 $(date -u -d "@$(cat "$STUB/state/now")" +%Y-%m-%dT%H:%M:%SZ)" ;;
    esac ;;
  "run view") echo success ;;
  "run watch")
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
  */hooks/inngest-tls-handshake) code="${HANDSHAKE_CODE:-200}"; body='{"verified":1}'; echo handshake >> "$STUB/order.log" ;;
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
    WEB_HOST_PRIVATE_IPS="10.0.1.10,10.0.1.11" GITHUB_OUTPUT="$d/github_output" FLIP_TRACK="$d/bin/track-stub" \
    FLIP_SLEEP="$d/bin/advance" FLIP_NOW="$d/bin/nowcmd" FLIP_WATCH_TIMEOUT_S=20 "$@" \
    bash "$script" "$mode" 2>&1)"; RC=$?
}
fresh() { local d="$TMP/$1"; assert_fixture_dir "$d"; rm -rf "$d"; make_stubs "$d"; printf '%s' "$d"; }
dispatched() { if [[ -f "$1/gh.log" ]]; then grep -c 'workflow run' "$1/gh.log" || true; else echo 0; fi; }
values() { grep -o 'inngest_link_value=[^ ]*' "$1/gh.log" 2>/dev/null | sed 's/inngest_link_value=//; s/pending:[0-9]*/pending/' | tr '\n' ' '; }
tracked() { if [[ -f "$1/track.log" ]]; then grep -c '^track ' "$1/track.log" || true; else echo 0; fi; }
started() { if [[ -f "$1/github_output" ]]; then grep -c '^started=true$' "$1/github_output" || true; else echo 0; fi; }
order() { if [[ -f "$1/order.log" ]]; then tr '\n' ' ' < "$1/order.log"; fi; }

D="$(fresh happy)"; run_script "$D" "$BODY" flip
[[ "$RC" == 0 ]] && ok "B1 happy path exits 0" || bad "B1 rc=$RC" "$OUT"
[[ "$(values "$D")" == "pending 1 " ]] && ok "B2 the flag moves pending:<epoch> then 1, in that order, exactly twice" || bad "B2 values='$(values "$D")'"
[[ "$(order "$D")" == "dispatch started=1 track handshake dispatch started=1 " ]] && ok "B3 order: pending dispatch, then the track.sh redeploy, then the handshake, then the promotion" || bad "B3 order='$(order "$D")'"
[[ "$(started "$D")" == 1 ]] && ok "B4 started=true is written exactly once, and BEFORE the first flag dispatch (the stub gh saw it already set)" || bad "B4 started=$(started "$D") order='$(order "$D")'"
grep -q 'inngest_link_value=pending:1000000' "$D/gh.log" && ok "B5 the lease epoch is the dispatch-time clock" || bad "B5 epoch" "$(cat "$D/gh.log")"
[[ "$(cat "$D/track.log" 2>/dev/null)" == "track peers=10.0.1.10,10.0.1.11 timeout=2400 secret=set" ]] && ok "B6 track.sh is handed both peers, a bounded REDEPLOY_TIMEOUT_S and the secret under the name it reads (WEBHOOK_DEPLOY_SECRET)" || bad "B6 track env: $(cat "$D/track.log" 2>/dev/null)"
[[ "$OUT" != *"$SECRET_W"* && "$OUT" != *"$SECRET_ID"* && "$OUT" != *"$SECRET_SECRET"* ]] && ok "B7 no credential reaches the output" || bad "B7 credential leaked"
grep -rq "$SECRET_W" "$D/gh.log" "$D/curl.log" "$D/track.log" 2>/dev/null && bad "B8 a credential reached a logged argument list" || ok "B8 no credential on any gh, curl or track argument list or log"
[[ "$OUT" == *"NOT VERIFIED"*"web-2"* && "$OUT" == *"resolved"* ]] && ok "B8b the final line states what was NOT verified (web-2's own swap, the resolved scheme)" || bad "B8b final line" "$OUT"

D="$(fresh canary-fail)"; run_script "$D" "$BODY" flip TRACK_RC=1 TRACK_VERDICT=redeploy_terminal_failure
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"did not confirm a clean swap"* ]] && ok "B9 a failed canary/swap (track.sh exit 1) stops the run, names the failure and the flag is NEVER promoted to 1" || bad "B9 rc=$RC values='$(values "$D")'" "$OUT"
[[ "$(started "$D")" == 1 ]] && ok "B9b a failure AFTER the first flag write leaves started=true set (so the revert step runs)" || bad "B9b started=$(started "$D")"

D="$(fresh degraded)"; run_script "$D" "$BODY" flip TRACK_RC=1 TRACK_VERDICT=redeploy_peer_fanout_degraded
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$(tracked "$D")" == 1 ]] && ok "B9c a DEGRADED fleet redeploy (web-2 did not take the swap; track.sh exits non-zero) never reaches flip_apply_flag 1" || bad "B9c rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh degraded-real)"; run_script "$D" "$BODY" flip FLIP_TRACK="$REPO_ROOT/.github/actions/dispatch-web-redeploy/track.sh" REDEPLOY_POLL_INTERVAL_S=1 \
  TERMINAL_FRAME='{"component":"web-platform","exit_code":0,"reason":"ok_peer_fanout_degraded","tag":"v1.2.3","start_ts":1000000000}'
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"redeploy_peer_fanout_degraded"* ]] && ok "B9d the REAL track.sh on an exit_code 0 / ok_peer_fanout_degraded frame fails the flip (the frame the old inline loop accepted); no promotion" || bad "B9d rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh ok-real)"; run_script "$D" "$BODY" flip FLIP_TRACK="$REPO_ROOT/.github/actions/dispatch-web-redeploy/track.sh" REDEPLOY_POLL_INTERVAL_S=1
[[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "B9e the REAL track.sh on a clean ok frame lets the flip promote (non-vacuity of B9d)" || bad "B9e rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh lease)"; run_script "$D" "$BODY" flip TRACK_ADVANCE=2000
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"lease"* ]] && ok "B10 a deploy that outlives the 30-minute lease is NOT promoted" || bad "B10 rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh handshake)"; run_script "$D" "$BODY" flip HANDSHAKE_CODE=500
[[ "$RC" != 0 && "$(values "$D")" == "pending " ]] && ok "B11 a failed handshake probe stops before the promotion" || bad "B11 rc=$RC values='$(values "$D")'"

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
D="$(fresh off-fail)"; run_script "$D" "$BODY" off TRACK_RC=1
[[ "$RC" != 0 && "$OUT" != *"OFF: "* ]] && ok "B16d a failed redeploy after off exits non-zero and never prints the OFF summary" || bad "B16d rc=$RC" "$OUT"

D="$(fresh guard-refusal)"; run_script "$D" "$BODY" flip IDLE_FRAME="{\"component\":\"web-platform\",\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
[[ "$RC" != 0 && "$(started "$D")" == 0 && "$(dispatched "$D")" == 0 ]] && ok "B21 an idle-guard refusal writes no started output, so no revert (no off dispatch, no redeploy) can follow" || bad "B21 rc=$RC started=$(started "$D")"
D="$(fresh no-peers)"; run_script "$D" "$BODY" flip WEB_HOST_PRIVATE_IPS=
[[ "$RC" != 0 && "$(started "$D")" == 0 && "$(dispatched "$D")" == 0 && "$(tracked "$D")" == 0 ]] && ok "B22 an empty fan-out roster is refused before anything is written or dispatched (a one-host redeploy is a mixed fleet)" || bad "B22 rc=$RC"

D="$(fresh revert)"; printf '1\n1\n' > "$D/state/watch_rcs"; run_script "$D" "$BODY" revert
[[ "$RC" == 0 && "$(values "$D")" == "off " && "$(tracked "$D")" == 1 ]] && ok "B17 revert exits 0 even when its own flag job fails, and it did try off and the redeploy" || bad "B17 rc=$RC values='$(values "$D")'" "$OUT"
D="$(fresh revert-nogh)"; GH_RUN_RC=1 run_script "$D" "$BODY" revert GH_RUN_RC=1
[[ "$RC" == 0 ]] && ok "B18 revert exits 0 when the dispatch itself is refused" || bad "B18 rc=$RC"

D="$(fresh badvalue)"; ( source "$BODY"; PATH="$D/bin:$PATH" STUB="$D"; flip_apply_flag 'pending:abc' ) >/dev/null 2>&1; rcv=$?
[[ "$rcv" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B19 a flag value outside {off, 1, pending:<epoch>} is refused before any call" || bad "B19 rc=$rcv"
D="$(fresh nomode)"; run_script "$D" "$BODY" bogus
[[ "$RC" == 64 ]] && ok "B20 an unknown subcommand exits 64" || bad "B20 rc=$RC"

printf '\n=== C. mutations (each guard removed; the scenario that needs it must now promote) ===\n'
mutate() { # name sed-expression -> $TMP/mut-<name>.sh ; asserts it landed
  sed "$2" "$BODY" > "$TMP/mut-$1.sh"
  if cmp -s "$TMP/mut-$1.sh" "$BODY"; then bad "C-$1 the mutation matched nothing (the script's shape drifted)"; return 1; fi
}
if mutate lease 's/  if (( done_at > t0 + FLIP_LEASE_S )); then/  if false; then/'; then
  D="$(fresh m-lease)"; run_script "$D" "$TMP/mut-lease.sh" flip ADVANCE_EXTRA=900
  [[ "$RC" == 0 && "$(values "$D")" == "pending 1 " ]] && ok "C1 without the lease check a lapsed lease IS promoted (so B10 can see the guard)" || bad "C1 rc=$RC values='$(values "$D")'"
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
FLOOR=68
if (( PASS + FAIL < FLOOR )); then
  printf 'FAIL ANTI-VACUITY: %d assertions ran, floor is %d\n' $((PASS + FAIL)) "$FLOOR" >&2
  exit 1
fi
exit $(( FAIL > 0 ))
