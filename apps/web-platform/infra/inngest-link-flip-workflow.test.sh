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
#   B. BEHAVIOURAL, by running the script against stubbed gh/curl/sleep: the happy path orders pending -> redeploy ->
#      handshake -> `1`; a failed canary, a lapsed lease, a failed handshake, a busy deploy lane and a failed flag job
#      each stop BEFORE the promotion; revert always exits 0; the secret never reaches the output.
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
[[ "$(yq '[s.get("if") for s in steps if "Revert" in s.get("name","")]')" == "['failure() || cancelled()']" ]] && ok "A5 the revert step runs on exactly failure() || cancelled()" || bad "A5 revert if: $(yq '[s.get("if") for s in steps]')"
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
check "A19 every network call is bounded: three --max-time curls and a timeout around gh run watch" bash -c "[ \"\$(grep -v '^ *#' '$BODY' | grep -c -- '--max-time')\" -ge 3 ] && grep -q 'timeout \"\$FLIP_WATCH_TIMEOUT_S\" gh run watch' '$BODY'"
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
  "workflow run") exit "${GH_RUN_RC:-0}" ;;
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
      if (( n < 2 )); then body="{\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":$now}"
      else body="${TERMINAL_FRAME:-{\"exit_code\":0,\"reason\":\"ok\",\"tag\":\"v1.2.3\",\"start_ts\":$now\}}"; fi
    else
      body="${IDLE_FRAME:-{\"exit_code\":0,\"reason\":\"ok\",\"tag\":\"v1.2.2\",\"start_ts\":$((now - 90000))\}}"
    fi ;;
  */hooks/inngest-tls-handshake) code="${HANDSHAKE_CODE:-200}"; body='{"verified":1}' ;;
esac
if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
[[ -n "$wfmt" ]] && printf '%s' "$code"
exit 0
SH
  chmod +x "$d/bin/"*
}

SECRET_W="WhSecretAAAA1111"; SECRET_ID="cfidBBBB2222"; SECRET_SECRET="cfsecCCCC3333"
run_script() { # dir script mode [env assignments...] -> rc in $RC, output in $OUT
  local d="$1" script="$2" mode="$3"; shift 3
  OUT="$(env -i PATH="$d/bin:/usr/local/bin:/usr/bin:/bin" HOME="$d" TMPDIR="$d" RUNNER_TEMP="$d" STUB="$d" \
    GITHUB_WORKSPACE="$REPO_ROOT" GH_TOKEN=x GITHUB_RUN_ID=77 \
    WEBHOOK_SECRET="$SECRET_W" CF_ACCESS_CLIENT_ID="$SECRET_ID" CF_ACCESS_CLIENT_SECRET="$SECRET_SECRET" \
    FLIP_SLEEP="$d/bin/advance" FLIP_NOW="$d/bin/nowcmd" FLIP_WATCH_TIMEOUT_S=20 FLIP_POLL_MAX=40 "$@" \
    bash "$script" "$mode" 2>&1)"; RC=$?
}
fresh() { local d="$TMP/$1"; assert_fixture_dir "$d"; rm -rf "$d"; make_stubs "$d"; printf '%s' "$d"; }
dispatched() { if [[ -f "$1/gh.log" ]]; then grep -c 'workflow run' "$1/gh.log" || true; else echo 0; fi; }
values() { grep -o 'inngest_link_value=[^ ]*' "$1/gh.log" 2>/dev/null | sed 's/inngest_link_value=//; s/pending:[0-9]*/pending/' | tr '\n' ' '; }
posted() { if [[ -f "$1/curl.log" ]]; then grep -c 'POST' "$1/curl.log" || true; else echo 0; fi; }

D="$(fresh happy)"; run_script "$D" "$BODY" flip
[[ "$RC" == 0 ]] && ok "B1 happy path exits 0" || bad "B1 rc=$RC" "$OUT"
[[ "$(values "$D")" == "pending 1 " ]] && ok "B2 the flag moves pending:<epoch> then 1, in that order, exactly twice" || bad "B2 values='$(values "$D")'"
first_line="$(grep -n 'pending:' "$D/gh.log" | head -1 | cut -d: -f1)"; post_line="$(grep -n 'POST' "$D/curl.log" | head -1 | cut -d: -f1)"
[[ -n "$first_line" && -n "$post_line" ]] && ok "B3 the deploy is POSTed (after the pending dispatch)" || bad "B3 order"
hs_line="$(grep -n 'inngest-tls-handshake' "$D/curl.log" | head -1 | cut -d: -f1)"
[[ -n "$hs_line" && "$hs_line" -gt "$post_line" ]] && ok "B4 the handshake probe runs after the deploy and before the promotion" || bad "B4 handshake order hs=$hs_line post=$post_line"
grep -q 'inngest_link_value=pending:1000000' "$D/gh.log" && ok "B5 the lease epoch is the dispatch-time clock" || bad "B5 epoch" "$(cat "$D/gh.log")"
check "B6 the deploy payload names the running version and both peers" grep -q 'POST https://deploy.soleur.ai/hooks/deploy$' "$D/curl.log"
[[ "$OUT" != *"$SECRET_W"* && "$OUT" != *"$SECRET_ID"* && "$OUT" != *"$SECRET_SECRET"* ]] && ok "B7 no credential reaches the output" || bad "B7 credential leaked"
grep -rq "$SECRET_W" "$D/gh.log" "$D/curl.log" 2>/dev/null && bad "B8 a credential reached a logged argument list" || ok "B8 no credential on any gh or curl argument list"

D="$(fresh canary-fail)"; run_script "$D" "$BODY" flip TERMINAL_FRAME='{"exit_code":3,"reason":"canary_failed","tag":"v1.2.3","start_ts":1000000010}'
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"canary or the swap failed"* ]] && ok "B9 a failed canary stops the run, names the failure and the flag is NEVER promoted to 1" || bad "B9 rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh lease)"; run_script "$D" "$BODY" flip ADVANCE_EXTRA=900
[[ "$RC" != 0 && "$(values "$D")" == "pending " && "$OUT" == *"lease"* ]] && ok "B10 a deploy that outlives the 30-minute lease is NOT promoted" || bad "B10 rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh handshake)"; run_script "$D" "$BODY" flip HANDSHAKE_CODE=500
[[ "$RC" != 0 && "$(values "$D")" == "pending " ]] && ok "B11 a failed handshake probe stops before the promotion" || bad "B11 rc=$RC values='$(values "$D")'"

D="$(fresh deploy-busy)"; run_script "$D" "$BODY" flip IDLE_FRAME="{\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
[[ "$RC" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B12 a deploy already running blocks the flip before any dispatch" || bad "B12 rc=$RC dispatched=$(dispatched "$D")"

D="$(fresh apply-busy)"; echo 1 > "$D/state/busy"; run_script "$D" "$BODY" flip
[[ "$RC" != 0 && "$(dispatched "$D")" == 0 ]] && ok "B13 an apply in flight blocks the flip before any dispatch" || bad "B13 rc=$RC dispatched=$(dispatched "$D")"

D="$(fresh flag-job-fails)"; printf '1\n' > "$D/state/watch_rcs"; run_script "$D" "$BODY" flip
[[ "$RC" != 0 && "$(posted "$D")" == 0 && "$(values "$D")" == "pending " ]] && ok "B14 a failed flag job stops the run before any deploy is POSTed" || bad "B14 rc=$RC posted=$(posted "$D")"

D="$(fresh deploy-rejected)"; run_script "$D" "$BODY" flip DEPLOY_CODE=401
[[ "$RC" != 0 && "$(values "$D")" == "pending " ]] && ok "B15 a rejected deploy webhook stops the run" || bad "B15 rc=$RC"

D="$(fresh off)"; run_script "$D" "$BODY" off
[[ "$RC" == 0 && "$(values "$D")" == "off " && "$(posted "$D")" -ge 1 ]] && ok "B16 off applies the flag-absent baseline then redeploys" || bad "B16 rc=$RC values='$(values "$D")'" "$OUT"

D="$(fresh revert)"; printf '1\n1\n' > "$D/state/watch_rcs"; run_script "$D" "$BODY" revert
[[ "$RC" == 0 && "$(values "$D")" == "off " ]] && ok "B17 revert exits 0 even when its own flag job fails, and it did try off" || bad "B17 rc=$RC values='$(values "$D")'" "$OUT"
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
if mutate guard 's/^  flip_load_bearer; flip_guard_idle$/  flip_load_bearer/'; then
  D="$(fresh m-guard)"; run_script "$D" "$TMP/mut-guard.sh" flip IDLE_FRAME="{\"exit_code\":-1,\"reason\":\"running\",\"tag\":\"v1.2.3\",\"start_ts\":999999990}"
  [[ "$(dispatched "$D")" -ge 1 ]] && ok "C4 without the idle guard the flip dispatches behind a running deploy (so B12 can see the guard)" || bad "C4 dispatched=$(dispatched "$D")"
fi
if mutate watch 's/  timeout "\$FLIP_WATCH_TIMEOUT_S" gh run watch "\$id" --exit-status --interval 10 >\/dev\/null \\/  timeout "$FLIP_WATCH_TIMEOUT_S" gh run watch "$id" --interval 10 >\/dev\/null || true; true \\/'; then
  D="$(fresh m-watch)"; printf '1\n' > "$D/state/watch_rcs"; run_script "$D" "$TMP/mut-watch.sh" flip
  [[ "$(posted "$D")" -ge 1 ]] && ok "C5 without --exit-status a failed flag job is ignored and the deploy proceeds (so B14 can see the guard)" || bad "C5 posted=$(posted "$D")" "$OUT"
fi

printf '\n=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
FLOOR=45
if (( PASS + FAIL < FLOOR )); then
  printf 'FAIL ANTI-VACUITY: %d assertions ran, floor is %d\n' $((PASS + FAIL)) "$FLOOR" >&2
  exit 1
fi
exit $(( FAIL > 0 ))
