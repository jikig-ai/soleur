#!/usr/bin/env bash
# Drift-guard for the fresh-host POST-CONTAINER egress-enforcement probe (#5933 item 3).
#
# Locks the load-bearing invariants of cron-egress-enforce-probe.sh + its boot wiring:
#   1. The probe ships positive AND negative in-container enforcement probes (an inert
#      ruleset that `nft -f` accepts cannot fake the negative — #5046 threat).
#   2. The negative probe uses the errexit-safe `if docker exec … ; then … exit 1; fi`
#      shape (NOT a bare `&&`, which `set -e` skips) — cron-egress-postapply-assert.sh
#      §77-89 precedent.
#   3. The Sentry envelope is byte-compatible with soleur-host-bootstrap.sh emit_fail
#      (tags stage / failed_file / host_id) PLUS a probe_result tag that discriminates
#      every root-cause hypothesis in one event (#5933 §2.9.2 blind-surface).
#   4. Delivery lockstep: the probe is in server.tf host_script_files, the Dockerfile
#      COPY set, and soleur-host-bootstrap.sh's 0755 install + assert loops.
#   5. cloud-init invokes the probe AFTER the app container starts and FAIL-CLOSED
#      poweroffs on a non-enforcing host.
#
# Run: bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh
# Registered in .github/workflows/infra-validation.yml.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/cron-egress-enforce-probe.sh"
SERVER_TF="$SCRIPT_DIR/server.tf"
DOCKERFILE="$SCRIPT_DIR/../Dockerfile"
BOOTSTRAP="$SCRIPT_DIR/soleur-host-bootstrap.sh"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"

PASS=0
FAIL=0
CASES=0   # moved by the assert wrappers below, never inside the verdict helpers (accounting identity at the bottom)
# Verdict helpers: they move only the verdict counters.
_pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
_fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
# Instrument self-test (printf + exit, never through the helpers it checks): drive a wrapper on a case that
# MUST fail and one that MUST pass and require the matching verdict counter to move. An always-pass
# wrapper (`... || true`) leaves every row green; only this sees it.
_selftest() { # <label> <fail-arm-command...> -- <pass-arm-command...>
  local label="$1" p0=$PASS f0=$FAIL c0=$CASES; shift
  local -a fa=() pa=(); local seen=false w
  for w in "$@"; do if [[ "$w" == "--" ]]; then seen=true; elif [[ "$seen" == true ]]; then pa+=("$w"); else fa+=("$w"); fi; done
  "${fa[@]}" >/dev/null
  if [[ "$FAIL" -ne $((f0 + 1)) || "$PASS" -ne "$p0" ]]; then
    printf '[FATAL] instrument self-test: %s did not record a FAIL for a case that must fail\n' "$label" >&2; exit 1
  fi
  "${pa[@]}" >/dev/null
  if [[ "$PASS" -ne $((p0 + 1)) || "$FAIL" -ne $((f0 + 1)) ]]; then
    printf '[FATAL] instrument self-test: %s did not record a PASS for a case that must pass\n' "$label" >&2; exit 1
  fi
  PASS=$p0; FAIL=$f0; CASES=$c0
}

assert_grep() {
  local description="$1" pattern="$2" file="$3"
  CASES=$((CASES + 1))
  if grep -qE -- "$pattern" "$file"; then
    _pass "$description"
  else
    _fail "$description (pattern not found in $(basename "$file"): $pattern)"
  fi
}
assert_cmd() {
  local description="$1"; shift
  CASES=$((CASES + 1))
  if "$@" >/dev/null 2>&1; then
    _pass "$description"
  else
    _fail "$description ($*)"
  fi
}
_selftest "assert_grep" assert_grep st "no-such-pattern-xyzzy" "$PROBE" -- assert_grep st '^#!' "$PROBE"
_selftest "assert_cmd" assert_cmd st false -- assert_cmd st true

echo "--- fresh-host egress-enforcement probe drift-guard (#5933) ---"

echo "-- probe script exists + parses --"
assert_cmd "exists: cron-egress-enforce-probe.sh" test -f "$PROBE"
assert_cmd "probe parses (bash -n)" bash -n "$PROBE"
# set -e must be present so the structure/positive `if !` guards actually abort.
assert_grep "probe owns errexit (set -e)" '^set -e' "$PROBE"

echo "-- enforcement probe invariants --"
# Positive: an allowlisted host reachable from inside the container, WITH --retry 3 so a
# transient hiccup does not trigger a destructive poweroff (availability call — retry does
# not weaken security).
assert_grep "positive probe (allowlisted host from container)" \
  'docker exec "\$CONTAINER" curl .* https://api\.github\.com' "$PROBE"
assert_grep "positive probe retries transient failures (--retry, avoids destructive false poweroff)" \
  'curl .*--retry 3 https://api\.github\.com' "$PROBE"
# Negative MUST capture the curl exit code (errexit-safe `|| neg_rc=$?`) and discriminate:
# only exit 28 (nftables DROP → timeout) is "enforcing"; exit 0 is inert; anything else is
# INCONCLUSIVE → fail-closed. A bare `if curl; then FAIL` would treat EVERY non-zero curl
# exit (DNS/refused/docker-infra) as "dropped" → false enforcing pass on an inert ruleset
# coincident with a transient failure (security-sentinel P2).
assert_grep "negative probe captures curl exit code (errexit-safe)" \
  'docker exec "\$CONTAINER" curl .* https://example\.com \|\| neg_rc=' "$PROBE"
assert_grep "negative probe treats reachable (exit 0) as INERT" 'neg_rc" -eq 0' "$PROBE"
assert_grep "negative probe treats non-timeout (!= 28) as INCONCLUSIVE → fail-closed" 'neg_rc" -ne 28' "$PROBE"
# Negative probe MUST stay single-shot (a --retry on it would mask a real open path).
if grep -qE 'https://example\.com .*--retry' "$PROBE" || grep -cE -- '--retry.* https://example\.com' >/dev/null "$PROBE"; then
  CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: negative probe must NOT --retry (would mask a real open egress path)"
else
  CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: negative probe is single-shot (no --retry)"
fi
# Both enforcement sentinels + the structure/absent/inconclusive sentinels must be present so
# the failing hypothesis is named (SSH-free diagnosis).
for sentinel in egress-probe-positive egress-probe-negative egress-probe-negative-inconclusive docker-user-jump firewall-not-active container-absent; do
  assert_grep "ASSERT-FAILED sentinel for $sentinel" "ASSERT-FAILED: $sentinel" "$PROBE"
done
# Unanticipated-abort observability: a trap emits a signal even on a set -e abort no explicit
# branch caught, and the clean-success path disarms it so a healthy boot emits nothing.
assert_grep "trap emit_fail EXIT armed (catches unanticipated set -e abort)" 'trap emit_fail EXIT' "$PROBE"
assert_grep "trap disarmed on clean success (no false fatal on exit 0)" 'trap - EXIT   # disarm' "$PROBE"

echo "-- Sentry envelope parity with soleur-host-bootstrap.sh emit_fail --"
# The probe reuses the bootstrap emit_fail envelope (stage/failed_file/host_id) + probe_result.
for tag in '"stage":"%s"' '"failed_file":"cron-egress-enforce-probe.sh"' '"host_id":"%s"' '"probe_result":"%s"'; do
  if grep -qF -- "$tag" "$PROBE"; then
    CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: Sentry tag present: $tag"
  else
    CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: Sentry tag missing: $tag"
  fi
done
assert_grep "probe_result discriminates hypotheses (negative_fail — the exfil hole)" \
  'PROBE_RESULT=negative_fail' "$PROBE"
assert_grep "probe_result discriminates hypotheses (positive_fail — over-blocking)" \
  'PROBE_RESULT=positive_fail' "$PROBE"

echo "-- Sentry TRANSPORT parity with soleur-host-bootstrap.sh emit_fail (drift guard) --"
# The tag-schema check above locks WHAT tags are sent; this locks that the TRANSPORT (DSN
# parse + store endpoint + auth header) is byte-identical to the bootstrap emit_fail, so a
# Sentry endpoint / DSN-format migration in the bootstrap cannot silently drift this inline
# copy — a silent observability loss on a fail-closed path (code-quality 3.1 / arch Lens 4).
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if grep -qF -- "$line" "$PROBE" && grep -qF -- "$line" "$BOOTSTRAP"; then
    CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: transport line byte-identical in probe + bootstrap: $(printf '%.40s' "$line")…"
  else
    CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: emit transport drift between probe and bootstrap: $line"
  fi
done <<'TRANSPORT'
      KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
      SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
      PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
      curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
TRANSPORT

echo "-- probe-pair lockstep with sibling cron-egress-postapply-assert.sh (arch Lens 4) --"
# Both the fresh-host probe and the web-1 SSH-provisioner probe use the SAME positive
# (allowlisted) + negative (non-allowlisted) hosts; a change to one canary must move both,
# else one path proves a stale invariant.
SIBLING="$SCRIPT_DIR/cron-egress-postapply-assert.sh"
for host in api.github.com example.com; do
  if grep -qF "https://$host" "$PROBE" && grep -qF "https://$host" "$SIBLING"; then
    CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: probe host https://$host shared by probe + sibling"
  else
    CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: probe host https://$host drift between probe and sibling cron-egress-postapply-assert.sh"
  fi
done

echo "-- delivery lockstep (baked set / Dockerfile / bootstrap) --"
# Scope to the host_script_files array (mirrors journald-config.test.sh) so an
# SSH-provisioner reference cannot satisfy it.
assert_cmd "baked set includes cron-egress-enforce-probe.sh (host_script_files array)" \
  bash -c "awk '/host_script_files = \[/,/^  \]/' '$SERVER_TF' | grep -cF -- '\"cron-egress-enforce-probe.sh\"' >/dev/null"
assert_grep "Dockerfile bakes cron-egress-enforce-probe.sh" '/app/infra/cron-egress-enforce-probe\.sh' "$DOCKERFILE"
# bootstrap installs it at 0755 AND asserts it executable (both loops carry the name).
INSTALL_HITS="$(grep -c 'cron-egress-enforce-probe\.sh' "$BOOTSTRAP")"
if [[ "$INSTALL_HITS" -ge 2 ]]; then
  CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: bootstrap references the probe in both install + assert loops ($INSTALL_HITS hits)"
else
  CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: bootstrap must carry the probe in BOTH the 0755 install and the test -x assert loop (got $INSTALL_HITS)"
fi

echo "-- cloud-init boot wiring (post-container + fail-closed) --"
assert_grep "cloud-init invokes the probe" '/usr/local/bin/cron-egress-enforce-probe\.sh' "$CLOUD_INIT"
assert_grep "cloud-init fail-closed poweroff on non-enforcing host" 'poweroff -f' "$CLOUD_INIT"
assert_grep "probe invocation is fail-closed (if ! probe; then … poweroff)" \
  'if ! /usr/local/bin/cron-egress-enforce-probe\.sh; then' "$CLOUD_INIT"
# ORDERING: the probe must run AFTER the app container starts (the terminal `docker run`'s
# final image arg). #6122 replaced the bare `${image_name}` arg with the ref the seed block
# resolved, `"$(cat /run/soleur-image-ref)"` (#8036 1d dropped its `|| echo` GHCR fallback: the
# seed block's `exit 1` guarantees the sentinel exists before any reader). The run arg
# is the only line that STARTS with the quoted `cat` (the pull/create sites prefix it with
# `docker pull`/`docker create`). Probe line number MUST be greater.
CONTAINER_LINE="$(grep -nE '^\s*"\$\(cat /run/soleur-image-ref' "$CLOUD_INIT" | tail -1 | cut -d: -f1)"
PROBE_LINE="$(grep -nE 'if ! /usr/local/bin/cron-egress-enforce-probe\.sh' "$CLOUD_INIT" | sed -n '1p' | cut -d: -f1)"
if [[ -n "$CONTAINER_LINE" && -n "$PROBE_LINE" && "$PROBE_LINE" -gt "$CONTAINER_LINE" ]]; then
  CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: probe runs AFTER the app container starts (container=$CONTAINER_LINE < probe=$PROBE_LINE)"
else
  CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: probe must be invoked after the docker run \${image_name} line (container=$CONTAINER_LINE probe=$PROBE_LINE)"
fi

# This asserts the SHELL SEMANTICS the probe's fail branches rely on (emit-name-then-halt
# under set -e) — NOT probe content; the probe-content guards are the assert_grep checks
# above. It is a fixed-truth guard against a future refactor that would let a fail branch
# fall through to a clean exit.
echo "-- shell-semantics guard: an ASSERT-FAILED branch emits + halts under set -e --"
SENTINEL_OUT="$(bash -c 'set -e; if true; then echo "ASSERT-FAILED: egress-probe-negative"; exit 1; fi; echo SHOULD-NOT-REACH' 2>&1 || true)"
if echo "$SENTINEL_OUT" | grep -cF 'ASSERT-FAILED: egress-probe-negative' >/dev/null && ! echo "$SENTINEL_OUT" | grep -cF 'SHOULD-NOT-REACH' >/dev/null; then
  CASES=$((CASES + 1)); PASS=$((PASS + 1)); echo "  PASS: an ASSERT-FAILED branch emits name and halts (fail-branch shell semantics intact)"
else
  CASES=$((CASES + 1)); FAIL=$((FAIL + 1)); echo "  FAIL: ASSERT-FAILED branch did not emit+halt as expected (got: $SENTINEL_OUT)"
fi

# --- #7797 hardening: xtrace refusal (the probe ACQUIRES a live DSN via `doppler secrets get`) ----
# Behavioural: the REAL probe runs against PATH stubs, so a refusal is observed rather than grepped.
# Unconditional on purpose: a `${VAR:+x}` hatch would be open by construction since the credential is
# acquired at runtime. The empty call log below proves the refusal precedes every probe step AND the
# `trap emit_fail EXIT` (an armed trap would call the doppler stub on exit).
echo "-- xtrace refusal (#7797) --"
# shellcheck disable=SC2034  # consumed by check() conditions via eval
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_BIN="$(command -v env || true)"; BASH_BIN="$(command -v bash || true)"; TIMEOUT_BIN="$(command -v timeout || true)"
STUBS="$(mktemp -d)"; trap 'rm -rf "$STUBS"' EXIT
STUB_CALLS="$STUBS/calls"
GWTOK_DIR="$STUBS/gwtok"; mkdir -p "$GWTOK_DIR"
mk_stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
LOGLINE='printf "%s\t%s\n" "$(basename "$0")" "$*" >> "$STUB_CALLS"'
mk_stub docker "$LOGLINE
case \"\$1\" in
  ps) if [ -n \"\${STUB_PS_NAMES+x}\" ]; then printf '%s\n' \"\$STUB_PS_NAMES\"; else printf '%s\n' soleur-web-platform soleur-egress-gw; fi ;;
  inspect) echo '172.18.0.9' ;;
  exec) case \"\$*\" in *169.254.169.254*) exit \"\${STUB_GW_DENY_RC:-7}\" ;; *api.github.com*) case \"\$*\" in *--proxy*) printf '%s' \"\${STUB_GW_ALLOW_CODE:-200}\" ;; esac; exit 0 ;; *example.com*) exit 28 ;; esac; echo \"REFUSED docker \$*\" >> \"\$STUB_CALLS\"; exit 64 ;;
  *) echo \"REFUSED docker \$*\" >> \"\$STUB_CALLS\"; exit 64 ;;
esac"
mk_stub nft "$LOGLINE
if [ -n \"\${STUB_NFT_OUT+x}\" ]; then printf '%s\n' \"\$STUB_NFT_OUT\"; else printf '%s\n' 'chain DOCKER-USER {' '  jump SOLEUR-EGRESS' '  return' '}'; fi"
mk_stub systemctl "$LOGLINE
exit 0"
mk_stub sleep "exit 0"
mk_stub doppler "$LOGLINE
echo 'https://synthetickey@o0.ingest.invalid/42'"
mk_stub curl "$LOGLINE
exit 0"
printf 'set -x\n' > "$STUBS/xt.env"
# shellcheck disable=SC2034  # OUT is consumed by check() conditions via eval
RC=0; ERR=""; OUT=""
# run_probe <env words...> -- <bash flags...>: runs the real probe, resets the call log first.
run_probe() {
  local -a envw=() flags=(); local seen=false w
  for w in "$@"; do
    if [[ "$w" == "--" ]]; then seen=true; elif [[ "$seen" == true ]]; then flags+=("$w"); else envw+=("$w"); fi
  done
  : > "$STUB_CALLS"
  RC=0
  local has_tok=false; for w in "${envw[@]+"${envw[@]}"}"; do [[ "$w" == EGRESS_GW_TOKEN_DIR=* ]] && has_tok=true; done
  $has_tok || envw+=("EGRESS_GW_TOKEN_DIR=$GWTOK_DIR")
  # shellcheck disable=SC2034  # consumed by check() conditions via eval
  OUT="$("$ENV_BIN" -u BASH_ENV -u SHELLOPTS PATH="$STUBS:$PATH" STUB_CALLS="$STUB_CALLS" ${envw[@]+"${envw[@]}"} \
    "$TIMEOUT_BIN" 20 "$BASH_BIN" ${flags[@]+"${flags[@]}"} "$PROBE" 2>"$STUBS/err")" || RC=$?
  ERR="$(cat "$STUBS/err" 2>/dev/null || true)"
}
check() {  # check <description> <cond>   (eval'd; same shape as the other suites)
  CASES=$((CASES + 1))
  if eval "$2"; then _pass "$1"; else _fail "$1 (condition: $2)"; fi
}
_selftest "check" check st false -- check st true
for form in bash-x SHELLOPTS BASH_ENV; do
  case "$form" in
    bash-x)    run_probe -- -x ;;
    SHELLOPTS) run_probe SHELLOPTS=xtrace -- ;;
    BASH_ENV)  run_probe BASH_ENV="$STUBS/xt.env" -- ;;
  esac
  check "P-X1[$form] exits 78 (got rc=$RC; first stderr line: $(printf '%s' "$ERR" | sed -n '1p'))" '[[ "$RC" -eq 78 ]]'
  check "P-X1[$form] a NON-'+' stderr line carries the refusal message" \
    '[[ "$(grep -v "^+" <<<"$ERR" | grep -c "refusing to run under xtrace" || true)" -ge 1 ]]'
  check "P-X1[$form] no stub was called (refusal precedes every probe step and the EXIT trap)" '[[ ! -s "$STUB_CALLS" ]]'
  check "P-X1[$form] neither stream carries the DSN the doppler stub would print" '[[ "$OUT$ERR" != *synthetickey* ]]'
done
run_probe --
check "P-X1c untraced run is not refused: rc 0 and prints egress-enforce-ok (positive control)" \
  '[[ "$RC" -eq 0 && "$OUT" == *egress-enforce-ok* ]]'
check "P-X1c the clean-success path never acquires the DSN (doppler and curl on the host never called)" \
  '[[ "$(grep -c "^doppler" "$STUB_CALLS" || true)" -eq 0 && "$(grep -c "^curl" "$STUB_CALLS" || true)" -eq 0 ]]'
check "P-X1c the call log WORKS (instrument control): the healthy run logged docker and nft calls, so an empty log in P-X1 means the refusal, not a dead logger" \
  '[[ "$(grep -c "^docker" "$STUB_CALLS" || true)" -ge 1 && "$(grep -c "^nft" "$STUB_CALLS" || true)" -ge 1 ]]'
check "P-X1c no stub refused an unexpected argv" '[[ "$(grep -c "^REFUSED" "$STUB_CALLS" || true)" -eq 0 ]]'

# --- pass 2 (#9217): the converted predicates keep their discrimination -----------------------------
# The healthy run above only proves the happy path, which an always-true predicate also satisfies. These rows
# observe the discrimination: an exact-line container match, a missing jump, and a clean stdout. Row ids keep the
# plan's numbering (P2-1 and P2-5 were cut at plan review), and the container match is placed mid-list so a
# first-line-only or last-line-only reader (head -1, tail -1) cannot satisfy it.
echo "-- pass 2 (#9217): converted predicates keep their discrimination --"
run_probe $'STUB_PS_NAMES=soleur-web-platform-old\nsoleur-web-platform2' --
check "P2-2 near-miss container names are not the container: rc 1 and container-absent named" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: container-absent"* ]]'
check "P2-2 the readiness loop polled exactly 30 times before giving up (its retry bound is pinned)" \
  '[[ "$(grep -c "^docker.ps" "$STUB_CALLS" || true)" -eq 30 ]]'
run_probe $'STUB_PS_NAMES=other\nsoleur-web-platform\nsoleur-egress-gw\nnext' --
check "P2-3 the container found mid-list still passes (non-canonical must-pass control): rc 0 and egress-enforce-ok" \
  '[[ "$RC" -eq 0 && "$OUT" == *egress-enforce-ok* ]]'
run_probe STUB_NFT_OUT= --
check "P2-4 a DOCKER-USER chain with no SOLEUR-EGRESS jump fails the structure step: rc 1 and docker-user-jump named" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: docker-user-jump"* ]]'
check "P2-4 the structure step precedes the behavioural probes: no docker exec ran on the failing chain" \
  '[[ "$(grep -c "^docker.exec" "$STUB_CALLS" || true)" -eq 0 ]]'
run_probe $'STUB_NFT_OUT=jump DOCKER-ISOLATION-STAGE-1\njump SOLEUR-INGRESS\ngoto SOLEUR-EGRESS' --
check "P2-4 a chain with other jumps but no SOLEUR-EGRESS jump still fails the structure step (the pattern is not shrunk)" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: docker-user-jump"* ]]'
run_probe --
check "P2-6 stdout carries no bare count line (every converted predicate discards the count it reads)" \
  '[[ "$(grep -cE "^[0-9]+$" <<<"$OUT" || true)" -eq 0 ]]'
check "P2-6 non-vacuity: that healthy run did print egress-enforce-ok" '[[ "$RC" -eq 0 && "$OUT" == *egress-enforce-ok* ]]'
check "P2-4 control: the healthy run does run docker exec (so the zero count above is the ordering, not a dead logger)" \
  '[[ "$(grep -c "^docker.exec" "$STUB_CALLS" || true)" -ge 1 ]]'

echo "-- pass 3 (#9534): the stage-4 gateway leg keeps its discrimination --"
# gw absent: app container up, no gateway — a named gw_absent, not a silent pass.
run_probe $'STUB_PS_NAMES=soleur-web-platform' --
check "P4-1 gw container absent fails named: rc 1 and egress-gw-absent" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: egress-gw-absent"* ]]'
# near-miss gw names are not the gateway (the grep -x on the second container is not shrunk).
run_probe $'STUB_PS_NAMES=soleur-web-platform\nsoleur-egress-gw-old\nxsoleur-egress-gw' --
check "P4-2 near-miss gw names are not the gateway: rc 1 and egress-gw-absent" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: egress-gw-absent"* ]]'
# token dir missing/unwritable fails before either CONNECT leg.
run_probe EGRESS_GW_TOKEN_DIR="$STUBS/gwtok-missing" --
check "P4-3 unwritable token dir fails named: rc 1 and egress-gw-token-dir" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: egress-gw-token-dir"* ]]'
# allow leg: a 407 from the proxy (auth refused) fails named rather than passing as 000-adjacent.
run_probe STUB_GW_ALLOW_CODE=407 --
check "P4-4 a 407 CONNECT fails the allow leg named: rc 1 and egress-gw-allow" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: egress-gw-allow"* ]]'
# deny leg: the metadata CONNECT succeeding (rc 0) means the deny ACL set is broken.
run_probe STUB_GW_DENY_RC=0 --
check "P4-5 a successful metadata CONNECT fails the deny leg named: rc 1 and egress-gw-deny" \
  '[[ "$RC" -eq 1 && "$OUT" == *"ASSERT-FAILED: egress-gw-deny"* ]]'
# instrument control: the healthy run exercised the new arms (inspect + exactly one metadata CONNECT).
run_probe --
check "P4-6 healthy run inspects the gw and runs the metadata deny leg once" \
  '[[ "$(grep -c "^docker.inspect" "$STUB_CALLS" || true)" -ge 1 && "$(grep -c "169.254.169.254" "$STUB_CALLS" || true)" -eq 1 ]]'
check "P4-6 non-vacuity: that healthy run printed both gw legs before egress-enforce-ok" \
  '[[ "$OUT" == *egress-gw-allow-ok* && "$OUT" == *egress-gw-deny-ok* && "$OUT" == *egress-enforce-ok* ]]'

echo "-- drawdown (#7797): not grandfathered in the credential-refusal baseline --"
check "P-L the probe's repo path is absent from the A/B/C baseline" \
  '[[ "$(grep -cxF "apps/web-platform/infra/cron-egress-enforce-probe.sh" "$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.baseline.txt")" -eq 0 ]]'
check "P-L non-vacuity: the baseline is readable and non-empty" '[[ -s "$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.baseline.txt" ]]'

# Accounting identity, then the anti-vacuity floor. Reported by printf + exit, never through the helpers they
# backstop (ADR-193); the case counter moves in the wrappers, not in _pass/_fail.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting identity: PASS(%d) + FAIL(%d) != CASES(%d). A call site recorded no verdict or more than one.\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
MIN_CASES=65
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity floor: only %d assertions ran; floor is %d\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
