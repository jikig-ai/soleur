#!/usr/bin/env bash
# Fixture tests for the #10868 GHCR-resilience wiring in
# .github/workflows/rls-authz-fuzz.yml and the retry helper it invokes,
# .github/scripts/ghcr-pull-with-retry.sh.
#
# WHY THIS SUITE EXISTS. The failure mode it guards (GHCR anonymous-bucket
# saturation killing `supabase start`'s image pulls before the fuzz suite
# exists) only manifests under shared-egress load on a live runner, so a
# silent removal of the login/retry wiring would never reproduce in review.
# Two arms: (a) wiring — greps the workflow for the authenticated-pull path
# (packages: read, pinned docker/login-action, ordering, no `logout:` key,
# manifest-inspect positive control, helper invocation, timeout 30) and for
# the helper's load-bearing tokens; (b) behavior — PATH-stubbed fake commands
# classify retry/no-retry/exhaustion against the helper's OWN contract
# (toomanyrequests-signature-only, rc!=2 exclusion, fresh per-attempt log,
# ::warning::/::error:: annotations, rc propagation).
#
# MIN_ASSERTIONS is the suite's own anti-vacuity floor: a suite whose asserts
# were deleted can never green itself. The floor is the green run's exact
# count — raise it when adding rows, never lower it silently.
set -uo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/rls-authz-fuzz.yml"
HELPER="$REPO_ROOT/.github/scripts/ghcr-pull-with-retry.sh"
RUN_ALL="$REPO_ROOT/.github/scripts/test/run-all.sh"

# Canonical copy — fixture-dir-operand-assert.test.sh asserts every inline
# definition is byte-identical to plugins/soleur/test/test-helpers.sh.
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

TMP=$(mktemp -d)
assert_fixture_dir "$TMP"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# Instrument self-test (ADR-193): drive both verdict helpers once each and
# refuse unless both counters moved — a neutered pass()/fail() dies HERE,
# before any real row, never silently at the floor.
{ pass selftest-pass; fail selftest-fail "instrument probe"; } >/dev/null
if (( PASS != 1 || FAIL != 1 )); then
  printf '[FATAL] instrument self-test: pass()/fail() counters did not move (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL" >&2
  exit 1
fi
# The two self-test rows are instrument, not coverage: reset so the floor and
# the final verdict count real rows only.
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Run helper for the behavioral arm.
# ---------------------------------------------------------------------------

BIN="$TMP/bin"
assert_fixture_dir "$BIN"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

# run_helper <name> [extra-env ...] -- invokes $HELPER "$@" with the stub
# counter env wired. stdout+stderr -> $TMP/<name>.out; rc -> LAST_RC.
# GHCR_PULL_RETRY_SLEEPS=0 0 keeps every retry arm wall-clock-free; sleep is
# also PATH-stubbed below so a missing override can never stall the suite.
run_helper() {
  local name="$1"; shift
  LAST_OUT="$TMP/$name.out"
  : > "$STUB_CALLS"
  env STUB_CALLS="$STUB_CALLS" GHCR_PULL_RETRY_SLEEPS="0 0" \
      bash "$HELPER" "$@" > "$LAST_OUT" 2>&1
  LAST_RC=$?
}

assert_rc() { # name expected-rc
  if [[ "$LAST_RC" == "$2" ]]; then pass "$1"
  else fail "$1" "expected rc=$2, got $LAST_RC — $(tail -5 "$LAST_OUT" 2>/dev/null | tr '\n' '|')"; fi
}
assert_calls() { # name expected-count
  local got
  got=$(wc -l < "$STUB_CALLS" | tr -d ' ')
  if [[ "$got" == "$2" ]]; then pass "$1"
  else fail "$1" "stub invocations=$got, expected $2 — $(tail -5 "$LAST_OUT" 2>/dev/null | tr '\n' '|')"; fi
}
assert_out_has() { # name needle (fixed string)
  if grep -qF -- "$2" "$LAST_OUT"; then pass "$1"
  else fail "$1" "output lacks '$2' — $(tail -5 "$LAST_OUT" 2>/dev/null | tr '\n' '|')"; fi
}
assert_out_lacks() { # name needle (fixed string)
  if grep -qF -- "$2" "$LAST_OUT"; then fail "$1" "output carries forbidden '$2'"
  else pass "$1"; fi
}
assert_out_count() { # name needle expected-count
  local got
  got=$(grep -cF -- "$2" "$LAST_OUT" 2>/dev/null || true)
  if [[ "$got" == "$3" ]]; then pass "$1"
  else fail "$1" "'$2' count=$got, expected $3"; fi
}
assert_wf_has() { # name needle (fixed string, against the workflow file)
  if grep -qF -- "$2" "$WORKFLOW"; then pass "$1"
  else fail "$1" "workflow lacks '$2'"; fi
}
assert_wf_lacks() { # name needle (fixed string)
  if grep -qF -- "$2" "$WORKFLOW"; then fail "$1" "workflow carries forbidden '$2'"
  else pass "$1"; fi
}

STUB_CALLS="$TMP/stub-calls"
assert_fixture_dir "$STUB_CALLS"
: > "$STUB_CALLS"

# sleep — the helper's backoff is real wall-clock time inside a required
# merge-queue gate; nothing here needs a real sleep.
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$BIN/sleep"
chmod +x "$BIN/sleep"

# ---------------------------------------------------------------------------
# PATH-stubbed commands for the behavioral arm. Each appends one line to
# $STUB_CALLS per invocation so the suite can count attempts.
# ---------------------------------------------------------------------------

# fake-ok — canonical happy path: succeeds on the first attempt.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'echo "stub: stack started"' \
  'exit 0' \
  > "$BIN/fake-ok"

# fake-throttle-then-ok — throttles on attempt 1, succeeds on attempt 2.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'n=$(wc -l < "$STUB_CALLS" | tr -d " ")' \
  'if [[ "$n" == "1" ]]; then' \
  '  echo "Error response from daemon: toomanyrequests: retry-after: 862.061us, allowed: 44000/minute" >&2' \
  '  exit 1' \
  'fi' \
  'echo "stub: started on retry"' \
  'exit 0' \
  > "$BIN/fake-throttle-then-ok"

# fake-non-sig — fails with NO throttle signature: must exit on attempt 1.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'echo "supabase start failed: migration apply error" >&2' \
  'exit 1' \
  > "$BIN/fake-non-sig"

# fake-rc2 — exits 2 WITH the throttle token in output: the rc!=2 exclusion
# must dominate the signature match (the wrapper's deterministic class).
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'echo "toomanyrequests: retry-after: 1s" >&2' \
  'exit 2' \
  > "$BIN/fake-rc2"

# fake-always-throttle — signature on every attempt: exhausts at the bound.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'echo "Error response from daemon: toomanyrequests: retry-after: 1s, allowed: 44000/minute" >&2' \
  'exit 1' \
  > "$BIN/fake-always-throttle"

# fake-decoy — carries the decoy tokens that fire on non-throttle failures
# (Retrying after / failed to pull docker image) but NOT the signature: the
# gate must not retry it.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'echo "Retrying after 4s" >&2' \
  'echo "failed to pull docker image" >&2' \
  'exit 1' \
  > "$BIN/fake-decoy"

# fake-stale-sig — throttle on attempt 1 (retried), a clean non-signature
# failure on attempt 2: attempt 2 must classify on ITS OWN fresh log and exit
# immediately, not inherit attempt 1's signature. calls==2 is the assertion.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'n=$(wc -l < "$STUB_CALLS" | tr -d " ")' \
  'if [[ "$n" == "1" ]]; then' \
  '  echo "toomanyrequests: retry-after: 1s" >&2' \
  '  exit 1' \
  'fi' \
  'echo "manifest unknown: deterministic" >&2' \
  'exit 1' \
  > "$BIN/fake-stale-sig"

chmod +x "$BIN/fake-ok" "$BIN/fake-throttle-then-ok" "$BIN/fake-non-sig" \
         "$BIN/fake-rc2" "$BIN/fake-always-throttle" "$BIN/fake-decoy" \
         "$BIN/fake-stale-sig"

echo "=== Guard 1a: workflow + helper wiring ==="

# Slice the rls-fuzz job block (2-indent key under jobs:) so `packages: read`
# is asserted on THIS job, not satisfied by any other block in the file.
JOB_BLOCK=$(awk '
  /^  rls-fuzz:/ { inf=1 }
  inf && /^  [a-zA-Z0-9_-]+:/ && !/^  rls-fuzz:/ { inf=0 }
  inf { print }
' "$WORKFLOW")

if grep -qF 'contents: read' <<<"$JOB_BLOCK"; then pass "wiring:job-contents-read"
else fail "wiring:job-contents-read" "rls-fuzz job block lacks contents: read"; fi
if grep -qF 'packages: read' <<<"$JOB_BLOCK"; then pass "wiring:job-packages-read"
else fail "wiring:job-packages-read" "rls-fuzz job block lacks packages: read"; fi
if grep -qF 'timeout-minutes: 30' <<<"$JOB_BLOCK"; then pass "wiring:timeout-30"
else fail "wiring:timeout-30" "rls-fuzz job block lacks timeout-minutes: 30"; fi

# The workflow-level permissions block stays contents: read only (the
# packages grant is job-scoped).
TOP_PERM=$(awk '/^permissions:/{getline; print; exit}' "$WORKFLOW")
if [[ "$TOP_PERM" == "  contents: read" ]]; then pass "wiring:top-perm-unchanged"
else fail "wiring:top-perm-unchanged" "top-level permissions: block no longer 'contents: read' (got: $TOP_PERM)"; fi

LOGIN_SHA='docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9'
LN_CHECKOUT=$(grep -n 'actions/checkout@' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
LN_LOGIN=$(grep -n "$LOGIN_SHA" "$WORKFLOW" | head -1 | cut -d: -f1 || true)
LN_PROBE=$(grep -n 'docker manifest inspect ghcr.io/supabase/postgres' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
LN_START=$(grep -n 'ghcr-pull-with-retry.sh' "$WORKFLOW" | head -1 | cut -d: -f1 || true)

if [[ -n "$LN_LOGIN" ]]; then pass "wiring:login-sha-pinned"
else fail "wiring:login-sha-pinned" "no uses: line pins the full docker/login-action SHA"; fi
if [[ -n "$LN_CHECKOUT" && -n "$LN_LOGIN" && "$LN_CHECKOUT" -lt "$LN_LOGIN" ]]; then pass "wiring:login-after-checkout"
else fail "wiring:login-after-checkout" "checkout=$LN_CHECKOUT login=$LN_LOGIN"; fi
if [[ -n "$LN_PROBE" ]]; then pass "wiring:manifest-probe-present"
else fail "wiring:manifest-probe-present" "no docker manifest inspect positive-control step"; fi
if [[ -n "$LN_START" ]]; then pass "wiring:start-invokes-helper"
else fail "wiring:start-invokes-helper" "no step invokes ghcr-pull-with-retry.sh"; fi
if [[ -n "$LN_LOGIN" && -n "$LN_START" && "$LN_LOGIN" -lt "$LN_START" ]]; then pass "wiring:login-before-start"
else fail "wiring:login-before-start" "login=$LN_LOGIN start=$LN_START"; fi
if [[ -n "$LN_LOGIN" && -n "$LN_PROBE" && -n "$LN_START" && "$LN_LOGIN" -lt "$LN_PROBE" && "$LN_PROBE" -lt "$LN_START" ]]; then
  pass "wiring:probe-between-login-start"
else fail "wiring:probe-between-login-start" "login=$LN_LOGIN probe=$LN_PROBE start=$LN_START"; fi

# The start step keeps ./scripts/supabase-local.sh start as the wrapped argv
# and keeps working-directory: apps/web-platform.
assert_wf_has "wiring:start-argv" 'ghcr-pull-with-retry.sh" ./scripts/supabase-local.sh start'
assert_wf_has "wiring:start-workdir" 'working-directory: apps/web-platform'

# No `logout:` key anywhere in the login step (the default logout:true post
# phase must survive — a GITHUB_TOKEN must not persist in daemon config).
# Anchored on the YAML-key shape — a comment mentioning the key cannot match
# a line that begins `logout:` in key position.
if [[ -n "$LN_LOGIN" ]]; then
  LOGIN_BLOCK=$(sed -n "${LN_LOGIN},$((LN_LOGIN + 8))p" "$WORKFLOW")
  if grep -qE '^[[:space:]]+logout:' <<<"$LOGIN_BLOCK"; then fail "wiring:no-logout-key" "login step carries a logout: key"
  else pass "wiring:no-logout-key"; fi
else
  fail "wiring:no-logout-key" "no login step to check"
fi

# The image set is never repointed: no registry override, no docker
# pull/tag/save/load added to the workflow.
assert_wf_lacks "wiring:no-registry-override" 'SUPABASE_INTERNAL_IMAGE_REGISTRY='
assert_wf_lacks "wiring:no-docker-pull" 'docker pull'
assert_wf_lacks "wiring:no-docker-save" 'docker save'
assert_wf_lacks "wiring:no-docker-load" 'docker load'

# Helper load-bearing tokens (spec-flow P1-1/P1-4 + CTO ruling).
if [[ -f "$HELPER" ]]; then pass "wiring:helper-exists"
else fail "wiring:helper-exists" "$HELPER absent"; fi
if [[ -f "$HELPER" ]] && grep -qF '2>&1' "$HELPER"; then pass "wiring:helper-stderr-merge"
else fail "wiring:helper-stderr-merge" "helper lacks the 2>&1 combined-output merge"; fi
if [[ -f "$HELPER" ]] && grep -qF '${PIPESTATUS[0]}' "$HELPER"; then pass "wiring:helper-pipestatus"
else fail "wiring:helper-pipestatus" "helper reads no PIPESTATUS[0] — rc would be tee's"; fi
if [[ -f "$HELPER" ]] && grep -qi 'toomanyrequests' "$HELPER"; then pass "wiring:helper-signature"
else fail "wiring:helper-signature" "helper lacks the toomanyrequests signature"; fi
if [[ -f "$HELPER" ]] && grep -qF 'GHCR_PULL_RETRY_SLEEPS' "$HELPER"; then pass "wiring:helper-sleeps-env"
else fail "wiring:helper-sleeps-env" "helper lacks the GHCR_PULL_RETRY_SLEEPS override"; fi

# run-all's floor must equal the post-addition suite count (16 on main + this
# suite = 17) or the new guard is itself silently deletable.
if grep -q 'MIN_SUITES=17' "$RUN_ALL"; then pass "wiring:min-suites-17"
else fail "wiring:min-suites-17" "run-all.sh MIN_SUITES is not 17"; fi

echo "=== Guard 1b: helper behavior over PATH-stubbed commands ==="

run_helper ok fake-ok
assert_rc "b:happy-rc" 0
assert_calls "b:happy-calls" 1
assert_out_lacks "b:happy-no-warning" '::warning::'
assert_out_lacks "b:happy-no-error" '::error::'

run_helper throttle-ok fake-throttle-then-ok
assert_rc "b:throttle-then-ok-rc" 0
assert_calls "b:throttle-then-ok-calls" 2
assert_out_has "b:throttle-then-ok-warning" '::warning::'
assert_out_has "b:throttle-then-ok-warn-line" 'toomanyrequests'
assert_out_count "b:throttle-then-ok-warn-count" '::warning::' 1
assert_out_lacks "b:throttle-then-ok-no-error" '::error::'

run_helper non-sig fake-non-sig
assert_rc "b:non-sig-rc" 1
assert_calls "b:non-sig-calls" 1
assert_out_has "b:non-sig-error" '::error::'
assert_out_lacks "b:non-sig-no-warning" '::warning::'

run_helper rc2 fake-rc2
assert_rc "b:rc2-rc" 2
assert_calls "b:rc2-calls" 1
assert_out_lacks "b:rc2-no-warning" '::warning::'

run_helper always-throttle fake-always-throttle
assert_rc "b:exhaust-rc" 1
assert_calls "b:exhaust-calls" 3
assert_out_count "b:exhaust-warn-count" '::warning::' 2
assert_out_has "b:exhaust-error" '::error::'
assert_out_has "b:exhaust-error-line" 'toomanyrequests'

run_helper decoy fake-decoy
assert_rc "b:decoy-rc" 1
assert_calls "b:decoy-calls" 1
assert_out_has "b:decoy-error" '::error::'

run_helper stale-sig fake-stale-sig
assert_rc "b:stale-sig-rc" 1
assert_calls "b:stale-sig-calls" 2
assert_out_has "b:stale-sig-error" '::error::'
assert_out_count "b:stale-sig-warn-count" '::warning::' 1

# ---------------------------------------------------------------------------
# Floor + verdict. The bound is a literal adjacent to the if (ADR-193); the
# report is printf + exit 1, never routed through the helpers it backstops.
# ---------------------------------------------------------------------------

MIN_ASSERTIONS=49
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: %d assertion(s) ran, expected >= %d — a deleted guard row must not green this suite\n' "$((PASS + FAIL))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

if (( FAIL > 0 )); then
  echo "$FAIL failed"
  exit 1
fi
echo "0 failed"
exit 0
