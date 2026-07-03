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
# Positive: an allowlisted host reachable from inside the container.
assert_grep "positive probe (allowlisted host from container)" \
  'docker exec "\$CONTAINER" curl .* https://api\.github\.com' "$PROBE"
# Negative MUST use `if docker exec … ; then … exit 1; fi` — a bare `&&` is errexit-exempt
# and would silently skip the check (cron-egress-postapply-assert.sh precedent).
assert_grep "negative probe uses if/then/exit-1 (not bare &&)" \
  'if docker exec "\$CONTAINER" curl .* https://example\.com; then' "$PROBE"
# Both enforcement sentinels + the structure/absent sentinels must be present so the
# failing hypothesis is named (SSH-free diagnosis).
for sentinel in egress-probe-positive egress-probe-negative docker-user-jump firewall-not-active container-absent; do
  assert_grep "ASSERT-FAILED sentinel for $sentinel" "ASSERT-FAILED: $sentinel" "$PROBE"
done

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

echo "-- non-vacuity: the negative-probe pattern emits + halts under set -e --"
SENTINEL_OUT="$(bash -c 'set -e; if true; then echo "ASSERT-FAILED: egress-probe-negative"; exit 1; fi; echo SHOULD-NOT-REACH' 2>&1 || true)"
if echo "$SENTINEL_OUT" | grep -qF 'ASSERT-FAILED: egress-probe-negative' && ! echo "$SENTINEL_OUT" | grep -qF 'SHOULD-NOT-REACH'; then
  PASS=$((PASS + 1)); echo "  PASS: negative-probe if/then/exit-1 emits name and halts (non-vacuous)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: negative-probe pattern did not emit+halt as expected (got: $SENTINEL_OUT)"
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
