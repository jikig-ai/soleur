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

assert_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (pattern not found in $(basename "$file"): $pattern)"
  fi
}
assert_cmd() {
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description ($*)"
  fi
}

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
if grep -qE 'https://example\.com .*--retry' "$PROBE" || grep -qE '--retry.* https://example\.com' "$PROBE"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: negative probe must NOT --retry (would mask a real open egress path)"
else
  PASS=$((PASS + 1)); echo "  PASS: negative probe is single-shot (no --retry)"
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
    PASS=$((PASS + 1)); echo "  PASS: Sentry tag present: $tag"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: Sentry tag missing: $tag"
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
    PASS=$((PASS + 1)); echo "  PASS: transport line byte-identical in probe + bootstrap: $(printf '%.40s' "$line")…"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: emit transport drift between probe and bootstrap: $line"
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
    PASS=$((PASS + 1)); echo "  PASS: probe host https://$host shared by probe + sibling"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: probe host https://$host drift between probe and sibling cron-egress-postapply-assert.sh"
  fi
done

echo "-- delivery lockstep (baked set / Dockerfile / bootstrap) --"
# Scope to the host_script_files array (mirrors journald-config.test.sh) so an
# SSH-provisioner reference cannot satisfy it.
assert_cmd "baked set includes cron-egress-enforce-probe.sh (host_script_files array)" \
  bash -c "awk '/host_script_files = \[/,/^  \]/' '$SERVER_TF' | grep -qF -- '\"cron-egress-enforce-probe.sh\"'"
assert_grep "Dockerfile bakes cron-egress-enforce-probe.sh" '/app/infra/cron-egress-enforce-probe\.sh' "$DOCKERFILE"
# bootstrap installs it at 0755 AND asserts it executable (both loops carry the name).
INSTALL_HITS="$(grep -c 'cron-egress-enforce-probe\.sh' "$BOOTSTRAP")"
if [[ "$INSTALL_HITS" -ge 2 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: bootstrap references the probe in both install + assert loops ($INSTALL_HITS hits)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: bootstrap must carry the probe in BOTH the 0755 install and the test -x assert loop (got $INSTALL_HITS)"
fi

echo "-- cloud-init boot wiring (post-container + fail-closed) --"
assert_grep "cloud-init invokes the probe" '/usr/local/bin/cron-egress-enforce-probe\.sh' "$CLOUD_INIT"
assert_grep "cloud-init fail-closed poweroff on non-enforcing host" 'poweroff -f' "$CLOUD_INIT"
assert_grep "probe invocation is fail-closed (if ! probe; then … poweroff)" \
  'if ! /usr/local/bin/cron-egress-enforce-probe\.sh; then' "$CLOUD_INIT"
# ORDERING: the probe must run AFTER the app container starts (the `${image_name}` line
# is the last arg of the terminal `docker run`). Probe line number MUST be greater.
CONTAINER_LINE="$(grep -nE '^\s*\$\{image_name\}\s*$' "$CLOUD_INIT" | tail -1 | cut -d: -f1)"
PROBE_LINE="$(grep -nE 'if ! /usr/local/bin/cron-egress-enforce-probe\.sh' "$CLOUD_INIT" | head -1 | cut -d: -f1)"
if [[ -n "$CONTAINER_LINE" && -n "$PROBE_LINE" && "$PROBE_LINE" -gt "$CONTAINER_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: probe runs AFTER the app container starts (container=$CONTAINER_LINE < probe=$PROBE_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: probe must be invoked after the docker run \${image_name} line (container=$CONTAINER_LINE probe=$PROBE_LINE)"
fi

# This asserts the SHELL SEMANTICS the probe's fail branches rely on (emit-name-then-halt
# under set -e) — NOT probe content; the probe-content guards are the assert_grep checks
# above. It is a fixed-truth guard against a future refactor that would let a fail branch
# fall through to a clean exit.
echo "-- shell-semantics guard: an ASSERT-FAILED branch emits + halts under set -e --"
SENTINEL_OUT="$(bash -c 'set -e; if true; then echo "ASSERT-FAILED: egress-probe-negative"; exit 1; fi; echo SHOULD-NOT-REACH' 2>&1 || true)"
if echo "$SENTINEL_OUT" | grep -qF 'ASSERT-FAILED: egress-probe-negative' && ! echo "$SENTINEL_OUT" | grep -qF 'SHOULD-NOT-REACH'; then
  PASS=$((PASS + 1)); echo "  PASS: an ASSERT-FAILED branch emits name and halts (fail-branch shell semantics intact)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: ASSERT-FAILED branch did not emit+halt as expected (got: $SENTINEL_OUT)"
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
