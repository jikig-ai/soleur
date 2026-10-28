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
# manifest-inspect positive control, helper invocation, timeout 45) and for
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
      TMPDIR="$RUNNER_TEMP_FIXTURE" \
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
assert_out_re() { # name extended-regex
  if grep -qE -- "$2" "$LAST_OUT"; then pass "$1"
  else fail "$1" "output lacks /$2/ — $(tail -5 "$LAST_OUT" 2>/dev/null | tr '\n' '|')"; fi
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

# Drive a verdict helper on a designed-fail too — a neutered assert_* that
# greens unconditionally must be caught here, not ride the row count.
LAST_OUT="$TMP/selftest.out"; printf 'clean\n' > "$LAST_OUT"
{ assert_out_lacks selftest-assert 'toomanyrequests'; } >/dev/null
if (( PASS != 2 )); then
  printf '[FATAL] instrument self-test: assert_out_lacks passed a forbidden token (PASS=%s)\n' "$PASS" >&2
  exit 1
fi
LAST_OUT=/dev/null; { assert_out_has selftest-assert-fail 'never-present'; } >/dev/null
if (( FAIL != 2 )); then
  printf '[FATAL] instrument self-test: assert_out_has failed to fail (FAIL=%s)\n' "$FAIL" >&2
  exit 1
fi
# The self-test rows are instrument, not coverage: reset so the floor and
# the final verdict count real rows only.
PASS=0
FAIL=0

STUB_CALLS="$TMP/stub-calls"
assert_fixture_dir "$STUB_CALLS"
: > "$STUB_CALLS"
# The helper's log dir is rooted inside $TMP so suite runs leave nothing
# behind in /tmp (and failure tails stay inspectable under the trap).
RUNNER_TEMP_FIXTURE="$TMP/runner-temp"
assert_fixture_dir "$RUNNER_TEMP_FIXTURE"
mkdir -p "$RUNNER_TEMP_FIXTURE"

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
# The token is emitted MIXED-CASE: dropping `grep -i`'s -i must red this row.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'n=$(wc -l < "$STUB_CALLS" | tr -d " ")' \
  'if [[ "$n" == "1" ]]; then' \
  '  echo "TooManyRequests: retry-after: 1s" >&2' \
  '  exit 1' \
  'fi' \
  'echo "manifest unknown: deterministic" >&2' \
  'exit 1' \
  > "$BIN/fake-stale-sig"

# fake-sig-above-tail — the signature appears, then >40 non-signature lines:
# the helper classifies on the TAIL (~40 lines) of the attempt's log only, so
# a signature that "recovered" mid-attempt must NOT retry. calls==1 is the
# assertion; a whole-log grep regression greens nothing here.
{ printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  'echo "Error response from daemon: toomanyrequests: retry-after: 1s" >&2' \
  'i=0; while (( i < 60 )); do echo "noise line $i" >&2; i=$((i+1)); done' \
  'echo "denied: requested access to the resource is denied" >&2' \
  'exit 1' \
  > "$BIN/fake-sig-above-tail"; }

chmod +x "$BIN/fake-ok" "$BIN/fake-throttle-then-ok" "$BIN/fake-non-sig" \
         "$BIN/fake-rc2" "$BIN/fake-always-throttle" "$BIN/fake-decoy" \
         "$BIN/fake-stale-sig" "$BIN/fake-sig-above-tail"

echo "=== Guard 1a: workflow + helper wiring ==="

# Slice the rls-fuzz job block (2-indent key under jobs:) so `packages: read`
# is asserted on THIS job, not satisfied by any other block in the file.
JOB_BLOCK=$(awk '
  /^  rls-fuzz:/ { inf=1 }
  inf && /^  [a-zA-Z0-9_-]+:/ && !/^  rls-fuzz:/ { inf=0 }
  inf && /^[a-zA-Z0-9_-]+:/ && !/^  / { inf=0 }
  inf { print }
' "$WORKFLOW")

if grep -qE '^[[:space:]]+contents: read([[:space:]#]|$)' <<<"$JOB_BLOCK"; then pass "wiring:job-contents-read"
else fail "wiring:job-contents-read" "rls-fuzz job block lacks a contents: read key"; fi
if grep -qE '^[[:space:]]+packages: read([[:space:]#]|$)' <<<"$JOB_BLOCK"; then pass "wiring:job-packages-read"
else fail "wiring:job-packages-read" "rls-fuzz job block lacks a packages: read key"; fi
if grep -qE '^[[:space:]]+timeout-minutes: 45([[:space:]#]|$)' <<<"$JOB_BLOCK"; then pass "wiring:timeout-45"
else fail "wiring:timeout-45" "rls-fuzz job block lacks timeout-minutes: 45"; fi

# The workflow-level permissions block stays contents: read only (the
# packages grant is job-scoped).
TOP_PERM=$(awk '/^permissions:/{getline; print; exit}' "$WORKFLOW")
if [[ "$TOP_PERM" == "  contents: read" ]]; then pass "wiring:top-perm-unchanged"
else fail "wiring:top-perm-unchanged" "top-level permissions: block no longer 'contents: read' (got: $TOP_PERM)"; fi

LOGIN_SHA='docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9'
# Every LN_* is anchored on a YAML key shape (`uses:`/`run:` in key position)
# — a comment quoting the same string cannot corrupt the ordering asserts.
LN_CHECKOUT=$(grep -nE '^[[:space:]]+- uses: actions/checkout@' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
LN_LOGIN=$(grep -nE "^[[:space:]]+uses: ${LOGIN_SHA}" "$WORKFLOW" | head -1 | cut -d: -f1 || true)
LN_START=$(grep -nE '^[[:space:]]+run:.*ghcr-pull-with-retry\.sh.*supabase-local\.sh start' "$WORKFLOW" | head -1 | cut -d: -f1 || true)

if [[ -n "$LN_LOGIN" ]]; then pass "wiring:login-sha-pinned"
else fail "wiring:login-sha-pinned" "no uses: line pins the full docker/login-action SHA"; fi
if [[ -n "$LN_CHECKOUT" && -n "$LN_LOGIN" && "$LN_CHECKOUT" -lt "$LN_LOGIN" ]]; then pass "wiring:login-after-checkout"
else fail "wiring:login-after-checkout" "checkout=$LN_CHECKOUT login=$LN_LOGIN"; fi
if [[ -n "$LN_START" ]]; then pass "wiring:start-invokes-helper"
else fail "wiring:start-invokes-helper" "no step invokes ghcr-pull-with-retry.sh"; fi
if [[ -n "$LN_LOGIN" && -n "$LN_START" && "$LN_LOGIN" -lt "$LN_START" ]]; then pass "wiring:login-before-start"
else fail "wiring:login-before-start" "login=$LN_LOGIN start=$LN_START"; fi

# No manifest probe may be reintroduced: EVERY registry (ghcr and ECR alike)
# throttles even single manifest calls on a shared runner IP — measured
# across runs 40525753531/40561028313/40572250940/40573437435/40574945720/
# 40575928811. A probe is pure failure surface; the pre-pull loop is the
# control (cache-hit = zero requests, miss = ECR-then-ghcr per image).
if grep -qE 'docker manifest inspect' "$WORKFLOW"; then fail "wiring:no-probe" "a manifest probe crept back in — it cannot beat a shared-IP bucket"
else pass "wiring:no-probe"; fi

# Only login carries the same-repo `if:` gate (fork PRs must never receive a
# usable GITHUB_TOKEN in the daemon config).
FORK_GATE='github.event.pull_request.head.repo.full_name == github.repository'
if grep -qF "$FORK_GATE" "$WORKFLOW"; then pass "wiring:fork-gate-present"
else fail "wiring:fork-gate-present" "no same-repo if: gate on the login step"; fi
FORK_GATE_LINES=$(grep -cF "$FORK_GATE" "$WORKFLOW" || true)
if [[ "$FORK_GATE_LINES" -eq 1 ]]; then pass "wiring:fork-gate-login-only"
else fail "wiring:fork-gate-login-only" "fork gate on $FORK_GATE_LINES step(s), expected exactly 1 (login only)"; fi

# The start step keeps ./scripts/supabase-local.sh start as the wrapped argv
# and keeps working-directory: apps/web-platform — asserted inside the start
# step's own block so a same-string elsewhere cannot satisfy it.
if [[ -n "$LN_START" ]]; then
  START_BLOCK=$(awk -v s="$LN_START" 'NR>s && /^[[:space:]]+- /{exit} NR>=s{print}' "$WORKFLOW")
  START_HEAD=$(awk -v s="$LN_START" -v n="$((LN_START - 3))" 'NR>=n && NR<=s{print}' "$WORKFLOW")
  if grep -qF 'ghcr-pull-with-retry.sh" ./scripts/supabase-local.sh start' <<<"$START_BLOCK"; then pass "wiring:start-argv"
  else fail "wiring:start-argv" "start step does not wrap ./scripts/supabase-local.sh start in the helper"; fi
  if grep -qF 'working-directory: apps/web-platform' <<<"$START_HEAD"; then pass "wiring:start-workdir"
  else fail "wiring:start-workdir" "start step lacks working-directory: apps/web-platform"; fi
  if grep -qE '^[[:space:]]+(if|continue-on-error):' <<<"$START_BLOCK"; then fail "wiring:start-no-skip" "start step carries an if:/continue-on-error: skip key"
  else pass "wiring:start-no-skip"; fi
else
  fail "wiring:start-argv" "no start step"; fail "wiring:start-workdir" "no start step"; fail "wiring:start-no-skip" "no start step"
fi

# No `logout:` key anywhere in the login step (the default logout:true post
# phase must survive — a GITHUB_TOKEN must not persist in daemon config).
# Anchored on the YAML-key shape — a comment mentioning the key cannot match
# a line that begins `logout:` in key position.
if [[ -n "$LN_LOGIN" ]]; then
  # Slice the login step from its `uses:` line to the next step boundary —
  # a fixed line window lets a `logout:` key placed deeper in `with:` escape.
  LOGIN_BLOCK=$(awk -v s="$LN_LOGIN" 'NR>s && /^[[:space:]]+- /{exit} NR>=s{print}' "$WORKFLOW")
  if grep -qE '^[[:space:]]+logout:' <<<"$LOGIN_BLOCK"; then fail "wiring:no-logout-key" "login step carries a logout: key"
  else pass "wiring:no-logout-key"; fi
  # The login step's inputs ARE the authenticated path — retargeting the
  # registry or dropping the token silently keeps login+probe green while
  # pulls stay anonymous.
  if grep -qE '^[[:space:]]+registry: ghcr\.io([[:space:]#]|$)' <<<"$LOGIN_BLOCK"; then pass "wiring:login-registry"
  else fail "wiring:login-registry" "login step does not target registry: ghcr.io"; fi
  if grep -qF 'password: ${{ secrets.GITHUB_TOKEN }}' <<<"$LOGIN_BLOCK"; then pass "wiring:login-token"
  else fail "wiring:login-token" "login step does not supply the GITHUB_TOKEN"; fi
else
  fail "wiring:no-logout-key" "no login step to check"
  fail "wiring:login-registry" "no login step to check"
  fail "wiring:login-token" "no login step to check"
fi

# The image set is never repointed and no channel acquires images outside the
# authenticated wrapper: no registry override, no implicit-pull verbs, no
# auth-stripping verbs, no elevated trigger, no silent-backoff override.
assert_wf_lacks "wiring:no-registry-override" 'SUPABASE_INTERNAL_IMAGE_REGISTRY='
assert_wf_lacks "wiring:no-docker-pull" 'docker pull'
assert_wf_lacks "wiring:no-docker-save" 'docker save'
assert_wf_lacks "wiring:no-docker-load" 'docker load'
assert_wf_lacks "wiring:no-docker-run" 'docker run'
assert_wf_lacks "wiring:no-docker-create" 'docker create'
assert_wf_lacks "wiring:no-docker-compose" 'docker compose'
assert_wf_lacks "wiring:no-docker-logout" 'docker logout'
assert_wf_lacks "wiring:no-docker-config-redirect" 'DOCKER_CONFIG'
assert_wf_lacks "wiring:no-pr-target" 'pull_request_target'
assert_wf_lacks "wiring:no-continue-on-error" 'continue-on-error'
assert_wf_lacks "wiring:no-sleeps-override" 'GHCR_PULL_RETRY_SLEEPS'

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
# The default backoff itself (20 45) is what paces the throttle on the real
# runner — the suite only ever exercises the "0 0" override.
if [[ -f "$HELPER" ]] && grep -qF 'GHCR_PULL_RETRY_SLEEPS:-20 45' "$HELPER"; then pass "wiring:helper-sleeps-default"
else fail "wiring:helper-sleeps-default" "helper default backoff is not '20 45'"; fi

# The wrapped argv is opaque to this suite — pin its two load-bearing lines:
# the propagated `exit "$start_rc"` (a remap to `exit 2` makes EVERY failure
# unretryable) and no credential-path strip on the exec (`HOME=`/`DOCKER_CONFIG=`
# prefixes would drop the auth the login just wrote).
SUPA_LOCAL="$REPO_ROOT/apps/web-platform/scripts/supabase-local.sh"
if grep -qF 'exit "$start_rc"' "$SUPA_LOCAL"; then pass "wiring:supa-rc-propagated"
else fail "wiring:supa-rc-propagated" "supabase-local.sh no longer exits the start rc verbatim"; fi
if grep -qE '(DOCKER_CONFIG|HOME)=[^ ]' "$SUPA_LOCAL"; then fail "wiring:supa-no-cred-strip" "supabase-local.sh prefixes an env credential-path override"
else pass "wiring:supa-no-cred-strip"; fi

# run-all's floor must equal the post-addition suite count (16 on main + this
# suite = 17) or the new guard is itself silently deletable. Whole-line
# anchor: `MIN_SUITES=170` must not satisfy it.
if grep -qxF 'MIN_SUITES=17' "$RUN_ALL"; then pass "wiring:min-suites-17"
else fail "wiring:min-suites-17" "run-all.sh MIN_SUITES is not 17"; fi

# The workflow's own pull_request.paths must list the helper and this suite —
# a helper-only edit otherwise never exercises the live wiring (the wrapped
# supabase-local.sh is listed; the wrapper must be too).
PATHS_BLOCK=$(awk '/^    paths:/{inf=1} inf && /^  [a-zA-Z_]+:/{inf=0} inf{print}' "$WORKFLOW")
if grep -qF '.github/scripts/ghcr-pull-with-retry.sh' <<<"$PATHS_BLOCK"; then pass "wiring:paths-helper"
else fail "wiring:paths-helper" "pull_request.paths omits the retry helper"; fi
if grep -qF '.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh' <<<"$PATHS_BLOCK"; then pass "wiring:paths-suite"
else fail "wiring:paths-suite" "pull_request.paths omits this suite"; fi
if grep -qF 'apps/web-platform/supabase/config.toml' <<<"$PATHS_BLOCK"; then pass "wiring:paths-config-toml"
else fail "wiring:paths-config-toml" "pull_request.paths omits supabase/config.toml (image repoints)"; fi

# --- Pre-pull wiring (measured run 40525753531 — the whole-command retry
# could not win against the shared org bucket; serial per-image pulls can).

PREPULL="$REPO_ROOT/.github/scripts/supabase-pre-pull-images.sh"
if [[ -f "$PREPULL" ]]; then pass "wiring:prepull-exists"
else fail "wiring:prepull-exists" "$PREPULL absent"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'ghcr-pull-with-retry.sh' "$PREPULL"; then pass "wiring:prepull-via-helper"
else fail "wiring:prepull-via-helper" "pre-pull does not route pulls through the retry helper"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'docker pull' "$PREPULL"; then pass "wiring:prepull-docker-pull"
else fail "wiring:prepull-docker-pull" "pre-pull does not docker pull"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'supabase/[a-z0-9-]+:' "$PREPULL"; then pass "wiring:prepull-ghcr-anchored"
else fail "wiring:prepull-ghcr-anchored" "pre-pull extraction is not anchored on supabase/ refs"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'strings "$SUPABASE_BIN"' "$PREPULL"; then pass "wiring:prepull-binary-strings"
else fail "wiring:prepull-binary-strings" "pre-pull does not extract refs from the CLI binary"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'MIN_IMAGES' "$PREPULL"; then pass "wiring:prepull-floor"
else fail "wiring:prepull-floor" "pre-pull lacks the extraction floor"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'public.ecr.aws/' "$PREPULL"; then pass "wiring:prepull-ecr-first"
else fail "wiring:prepull-ecr-first" "pre-pull does not try the ECR mirror first"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'SUPABASE_IMG_CACHE_DIR' "$PREPULL" && \
   grep -qF 'docker load' "$PREPULL" && grep -qF 'docker save' "$PREPULL"; then pass "wiring:prepull-cache"
else fail "wiring:prepull-cache" "pre-pull lacks the cache restore/save path"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'docker image inspect' "$PREPULL"; then pass "wiring:prepull-inspect"
else fail "wiring:prepull-inspect" "pre-pull lacks the cached-image skip"; fi

# #11386 latch + partial-save wiring: the ECR-dead latch (env-tunable
# threshold, once-only ::warning::, per-image skip marker), the save built
# from the inspect-verified present subset, and the fast compressor.
if [[ -f "$PREPULL" ]] && grep -qF 'SUPABASE_ECR_DEAD_AFTER' "$PREPULL"; then pass "wiring:prepull-latch-env"
else fail "wiring:prepull-latch-env" "pre-pull lacks the SUPABASE_ECR_DEAD_AFTER latch threshold"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'ecr skipped (latch)' "$PREPULL"; then pass "wiring:prepull-latch-skip"
else fail "wiring:prepull-latch-skip" "pre-pull lacks the latch-skip marker"; fi
if [[ -f "$PREPULL" ]] && grep -qF '::warning::ecr latch' "$PREPULL"; then pass "wiring:prepull-latch-warn"
else fail "wiring:prepull-latch-warn" "pre-pull lacks the once-only latch ::warning::"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'present_refs' "$PREPULL"; then pass "wiring:prepull-partial-save"
else fail "wiring:prepull-partial-save" "pre-pull does not save the inspect-verified present subset"; fi
if [[ -f "$PREPULL" ]] && grep -qF 'pigz -1' "$PREPULL" && grep -qF 'gzip -1' "$PREPULL"; then pass "wiring:prepull-fastcompress"
else fail "wiring:prepull-fastcompress" "pre-pull lacks the pigz -1 / gzip -1 fast tar write"; fi
if [[ -f "$PREPULL" ]] && grep -qF '| gzip >' "$PREPULL"; then fail "wiring:prepull-no-default-gzip" "pre-pull still pipes to bare gzip (default level)"
else pass "wiring:prepull-no-default-gzip"; fi

LN_PREPULL=$(grep -nE '^[[:space:]]+run:.*supabase-pre-pull-images\.sh' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
LN_CLI=$(grep -nE '^[[:space:]]+- name: Install Supabase CLI' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
if [[ -n "$LN_PREPULL" ]]; then pass "wiring:prepull-step-present"
else fail "wiring:prepull-step-present" "no step invokes supabase-pre-pull-images.sh"; fi
if [[ -n "$LN_CLI" && -n "$LN_PREPULL" && -n "$LN_START" && "$LN_CLI" -lt "$LN_PREPULL" && "$LN_PREPULL" -lt "$LN_START" ]]; then
  pass "wiring:prepull-order"
else fail "wiring:prepull-order" "cli=$LN_CLI prepull=$LN_PREPULL start=$LN_START"; fi

# The pre-pull step is credential-free — it must NOT sit behind the fork gate
# (forks need it most) and must not silently degrade.
if [[ -n "$LN_PREPULL" ]]; then
  PREPULL_BLOCK=$(awk -v s="$LN_PREPULL" 'NR>s && /^[[:space:]]+- /{exit} NR>=s{print}' "$WORKFLOW")
  PREPULL_HEAD=$(awk -v s="$LN_PREPULL" -v n="$((LN_PREPULL - 8))" 'NR>=n && NR<=s{print}' "$WORKFLOW")
  if grep -qE '^[[:space:]]+(if|continue-on-error):' <<<"$PREPULL_BLOCK"; then fail "wiring:prepull-no-skip" "pre-pull step carries an if:/continue-on-error: key"
  else pass "wiring:prepull-no-skip"; fi
  if grep -qF 'working-directory: apps/web-platform' <<<"$PREPULL_HEAD"; then pass "wiring:prepull-workdir"
  else fail "wiring:prepull-workdir" "pre-pull step lacks working-directory: apps/web-platform"; fi
else
  fail "wiring:prepull-no-skip" "no pre-pull step"; fail "wiring:prepull-workdir" "no pre-pull step"
fi
if grep -qF '.github/scripts/supabase-pre-pull-images.sh' <<<"$PATHS_BLOCK"; then pass "wiring:paths-prepull"
else fail "wiring:paths-prepull" "pull_request.paths omits the pre-pull script"; fi

# The image tarball restore sits between CLI install and pre-pull, pinned
# to a full actions/cache SHA like the other action pins in this workflow.
LN_CACHE=$(grep -nE '^[[:space:]]+uses: actions/cache@' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
if [[ -n "$LN_CACHE" ]]; then pass "wiring:cache-step-present"
else fail "wiring:cache-step-present" "no actions/cache step restores the image tarball"; fi
if grep -qE '^[[:space:]]+uses: actions/cache@[0-9a-f]{40}' "$WORKFLOW"; then pass "wiring:cache-sha-pinned"
else fail "wiring:cache-sha-pinned" "actions/cache is not pinned to a full SHA"; fi
if [[ -n "$LN_CACHE" && -n "$LN_CLI" && -n "$LN_PREPULL" && "$LN_CLI" -lt "$LN_CACHE" && "$LN_CACHE" -lt "$LN_PREPULL" ]]; then pass "wiring:cache-order"
else fail "wiring:cache-order" "cli=$LN_CLI cache=$LN_CACHE prepull=$LN_PREPULL"; fi
if grep -qF 'path: ${{ runner.temp }}/supabase-img-cache' "$WORKFLOW"; then pass "wiring:cache-path"
else fail "wiring:cache-path" "cache path is missing or moved off runner.temp"; fi
if grep -qF 'key: supabase-imgs-' "$WORKFLOW" && grep -qF "hashFiles('.github/scripts/supabase-pre-pull-images.sh'" "$WORKFLOW"; then pass "wiring:cache-key"
else fail "wiring:cache-key" "cache key lacks the supabase-imgs- prefix or the script/config hash"; fi
if grep -qF 'restore-keys: supabase-imgs-' "$WORKFLOW"; then pass "wiring:cache-restore-keys"
else fail "wiring:cache-restore-keys" "no restore-keys fallback for stale-but-useful caches"; fi
if grep -qF 'SUPABASE_IMG_CACHE_DIR: ${{ runner.temp }}/supabase-img-cache' "$WORKFLOW"; then pass "wiring:cache-env"
else fail "wiring:cache-env" "pre-pull step is not wired to the cache path"; fi

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
# The annotation must NAME the measured line — a bare 'toomanyrequests'
# substring is satisfied by the stub's own tee'd stderr.
assert_out_re "b:throttle-then-ok-warn-line" '^::warning::.*toomanyrequests'
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
assert_out_re "b:exhaust-error-line" '^::error::.*toomanyrequests'
# Exhaustion re-emits the failing log's tail (~200 lines): the daemon line
# appears once per tee'd attempt (3) plus once in the re-emitted tail (4) —
# annotations are excluded since they themselves quote the signature line.
reemit_count=$(grep -vE '^::' "$LAST_OUT" | grep -cF 'Error response from daemon' || true)
if [[ "$reemit_count" == "4" ]]; then pass "b:exhaust-reemit"
else fail "b:exhaust-reemit" "non-annotation 'Error response from daemon' count=$reemit_count, expected 4"; fi

run_helper decoy fake-decoy
assert_rc "b:decoy-rc" 1
assert_calls "b:decoy-calls" 1
assert_out_has "b:decoy-error" '::error::'

run_helper stale-sig fake-stale-sig
assert_rc "b:stale-sig-rc" 1
assert_calls "b:stale-sig-calls" 2
assert_out_has "b:stale-sig-error" '::error::'
assert_out_count "b:stale-sig-warn-count" '::warning::' 1

run_helper sig-above-tail fake-sig-above-tail
assert_rc "b:sig-above-tail-rc" 1
assert_calls "b:sig-above-tail-calls" 1
assert_out_lacks "b:sig-above-tail-no-warning" '::warning::'

# The real invocation is TWO argv words (script + `start`) — a `"$@"`→`"$*"`
# mangling would collapse them into one nonexistent command.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo x >> "${STUB_CALLS:?unset}"' \
  '[[ "$#" == "2" && "$1" == "first" && "$2" == "second" ]] || exit 9' \
  'exit 0' \
  > "$BIN/fake-two-arg"
chmod +x "$BIN/fake-two-arg"
run_helper two-arg fake-two-arg first second
assert_rc "b:two-arg-rc" 0
assert_calls "b:two-arg-calls" 1

echo "=== Guard 1c: pre-pull behavior (fake binary + stubbed docker) ==="

# A fake CLI binary: `strings` extracts the printable refs embedded in it —
# 10 refs clears the MIN_IMAGES=8 floor; glue-shaped refs prove the
# version-shape cutter; noise lines prove only anchored supabase/ refs pull.
FAKE_BIN_DIR="$TMP/fake-bin"
assert_fixture_dir "$FAKE_BIN_DIR"
mkdir -p "$FAKE_BIN_DIR"
{
  printf '#!/bin/sh\n'
  printf 'binary noise one\n'
  n=0
  for i in a b c d e f g h i j; do
    n=$((n+1))
    printf 'supabase/img-%s:1.%d.0\n' "$i" "$n"
  done
  printf 'supabase/edge:v9.9.9password_verification_attemptfailed\n'
  printf 'supabase/old:3.0.1failed\n'
  printf 'supabase/postgres:orioledb-failed\n'
  printf 'other-org/not-counted:1.0\n'
  printf 'supabase/template-no-tag:%%s\n'
  printf 'more noise\n'
} > "$FAKE_BIN_DIR/supabase"
chmod +x "$FAKE_BIN_DIR/supabase"

# docker stub: logs `<verb> <argv>` lines to $STUB_CALLS; DOCKER_MODE picks
# the behavior arm (ok | throttle-once | always | ecr-fail | cached |
# half-cached | load-fail | ecr-throttle-ghcr-ok | ecr-flap | partial-fail).
# Successful `pull`s append `pulled <ref>` records (distinct from `pull `
# lines so pull_count is unaffected) and `tag` records `pulled <dst>` — the
# pull-tracked `image inspect` default arm answers present iff the queried
# ref was pulled/tagged, which is what lets the partial-save rows assert the
# save argv against the INSPECTED subset rather than the intended set.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "$*" >> "${STUB_CALLS:?unset}"' \
  'verb="$1"' \
  'n=$(grep -c "^pull " "$STUB_CALLS" || true)' \
  'case "$verb" in' \
  '  image) case "${DOCKER_MODE:-ok}" in' \
  '    cached) exit 0 ;;' \
  '    half-cached) [[ "$*" == *img-a:* || "$*" == *img-b:* || "$*" == *img-c:* ]] && exit 0 || exit 1 ;;' \
  '    *) grep -qF "pulled ${3:-}" "$STUB_CALLS" && exit 0 || exit 1 ;;' \
  '  esac ;;' \
  '  load) [[ "${DOCKER_MODE:-ok}" == "load-fail" ]] && exit 1 || exit 0 ;;' \
  '  pull) case "${DOCKER_MODE:-ok}" in' \
  '    throttle-once) if [[ "$n" == "1" ]]; then echo "toomanyrequests: retry-after: 1s" >&2; exit 1; fi ;;' \
  '    always) echo "toomanyrequests: retry-after: 1s" >&2; exit 1 ;;' \
  '    ecr-fail) [[ "$*" == *public.ecr.aws* ]] && { echo "name unknown" >&2; exit 1; } ;;' \
  '    ecr-throttle-ghcr-ok) [[ "$*" == *public.ecr.aws* ]] && { echo "toomanyrequests: retry-after: 1s" >&2; exit 1; } ;;' \
  '    ecr-flap) if [[ "$*" == *public.ecr.aws* ]]; then' \
  '      if [[ "$*" == *img-b:* ]]; then echo "name unknown" >&2; exit 1;' \
  '      elif [[ "$*" == *img-a:* || "$*" == *img-c:* || "$*" == *img-d:* ]]; then echo "toomanyrequests: retry-after: 1s" >&2; exit 1; fi' \
  '    fi ;;' \
  '    partial-fail) [[ "$*" == *img-a:* ]] && { echo "toomanyrequests: retry-after: 1s" >&2; exit 1; } ;;' \
  '  esac' \
  '  echo "pulled ${2:-}" >> "$STUB_CALLS" ;;' \
  '  tag) echo "pulled ${3:-}" >> "$STUB_CALLS" ;;' \
  'esac' \
  'exit 0' \
  > "$BIN/docker"
chmod +x "$BIN/docker"

ORIG_PATH="$PATH"
run_prepull() { # name path-prefix [docker-mode]
  local name="$1" pfx="$2" mode="${3:-ok}"
  LAST_OUT="$TMP/$name.out"
  LAST_CACHE="$TMP/$name-cache"
  : > "$STUB_CALLS"
  env STUB_CALLS="$STUB_CALLS" GHCR_PULL_RETRY_SLEEPS="0 0" \
      TMPDIR="$RUNNER_TEMP_FIXTURE" DOCKER_MODE="$mode" \
      SUPABASE_IMG_CACHE_DIR="$LAST_CACHE" \
      PATH="$pfx:$ORIG_PATH" \
      bash "$PREPULL" > "$LAST_OUT" 2>&1
  LAST_RC=$?
}
# Pre-seed a nonempty cache tarball so the script's `[[ -s ... ]]` passes.
seed_cache() { mkdir -p "$1"; printf 'fake-tar\n' > "$1/images.tar.gz"; }

pull_count() { grep -c '^pull ' "$STUB_CALLS" || true; }
tag_count() { grep -c '^tag ' "$STUB_CALLS" || true; }

# Happy path: 12 extracted refs — each pulls from the ECR mirror then tags
# onto the ghcr ref: 12 pulls + 12 tags, rc 0.
run_prepull pp-ok "$FAKE_BIN_DIR:$BIN" ok
assert_rc "c:happy-rc" 0
if [[ "$(pull_count)" == 12 ]]; then pass "c:happy-pulls"; else fail "c:happy-pulls" "pulls=$(pull_count) want 12"; fi
if [[ "$(tag_count)" == 12 ]]; then pass "c:happy-tags"; else fail "c:happy-tags" "tags=$(tag_count) want 12"; fi
assert_out_has "c:happy-echo" 'pre-pull: 12 images'
# Serial order preserved: pull argv lines hit the ECR mirror; the tag lands
# each on the ghcr ref the CLI will look for.
if grep -qF 'pull public.ecr.aws/supabase/img-a:1.1.0' "$STUB_CALLS" && \
   grep -qF 'pull public.ecr.aws/supabase/img-j:1.10.0' "$STUB_CALLS"; then pass "c:happy-args"
else fail "c:happy-args" "pull argv missing ECR refs — $(cat "$STUB_CALLS" | tr '\n' '|')"; fi
if grep -qF 'tag public.ecr.aws/supabase/img-a:1.1.0 ghcr.io/supabase/img-a:1.1.0' "$STUB_CALLS"; then pass "c:happy-tag-ref"
else fail "c:happy-tag-ref" "ecr image not retagged to the ghcr ref"; fi
assert_out_has "c:happy-ecr-echo" 'via ecr mirror'
# The foreign-org ref and the %-templated ref must NOT be pulled.
if grep -qF 'other-org' "$STUB_CALLS"; then fail "c:happy-anchor" "extraction leaked a non-supabase ref"; else pass "c:happy-anchor"; fi
if grep -qF 'template-no-tag' "$STUB_CALLS"; then fail "c:happy-tag-required" "extraction pulled an untagged/template ref"; else pass "c:happy-tag-required"; fi
# Glue-cut: `v9.9.9password_...` pulls as `v9.9.9`, `3.0.1failed` as `3.0.1`,
# and `orioledb-failed` never reaches a pull.
if grep -qF 'pull public.ecr.aws/supabase/edge:v9.9.9' "$STUB_CALLS"; then pass "c:glue-cut-v"
else fail "c:glue-cut-v" "glued version tag not cut — $(cat "$STUB_CALLS" | tr '\n' '|')"; fi
if grep -qF 'pull public.ecr.aws/supabase/old:3.0.1' "$STUB_CALLS"; then pass "c:glue-cut-failed"
else fail "c:glue-cut-failed" "glued 'failed' suffix not cut"; fi
if grep -qF 'orioledb' "$STUB_CALLS"; then fail "c:orioledb-excluded" "non-version tag pulled"; else pass "c:orioledb-excluded"; fi

# Throttle on the first pull retried by the helper: N+1 pulls, rc 0, warning.
run_prepull pp-retry "$FAKE_BIN_DIR:$BIN" throttle-once
assert_rc "c:retry-rc" 0
if [[ "$(pull_count)" == 13 ]]; then pass "c:retry-pulls"; else fail "c:retry-pulls" "pulls=$(pull_count) want 13"; fi
assert_out_re "c:retry-warn" '^::warning::.*toomanyrequests'

# ECR miss falls back to ghcr per image: deterministic failure skips retry.
run_prepull pp-ecrfail "$FAKE_BIN_DIR:$BIN" ecr-fail
assert_rc "c:ecrfail-rc" 0
if [[ "$(grep -c '^pull public\.ecr\.aws/' "$STUB_CALLS" || true)" == 12 ]]; then pass "c:ecrfail-ecr"
else fail "c:ecrfail-ecr" "ecr tries=$(grep -c '^pull public\.ecr\.aws/' "$STUB_CALLS") want 12"; fi
if [[ "$(grep -c '^pull ghcr\.io/' "$STUB_CALLS" || true)" == 12 ]]; then pass "c:ecrfail-ghcr"
else fail "c:ecrfail-ghcr" "ghcr fallbacks=$(grep -c '^pull ghcr\.io/' "$STUB_CALLS") want 12"; fi
if [[ "$(tag_count)" == 0 ]]; then pass "c:ecrfail-no-tags"; else fail "c:ecrfail-no-tags" "tagged without an ecr image"; fi
assert_out_has "c:ecrfail-echo" 'via ghcr'

# Cache write: after pulls the set is saved for the cache action's post-job.
run_prepull pp-save "$FAKE_BIN_DIR:$BIN" ok
assert_rc "c:save-rc" 0
if grep -qE '^save (ghcr\.io/supabase/[^ ]+ ?)+$' "$STUB_CALLS"; then pass "c:save-argv"
else fail "c:save-argv" "docker save argv missing ghcr refs — $(cat "$STUB_CALLS" | tr '\n' '|')"; fi
assert_out_has "c:save-echo" 'pre-pull: wrote'

# Full cache hit: `docker load` + every `image inspect` true → zero pulls.
LAST_CACHE="$TMP/pp-hit-cache"; seed_cache "$LAST_CACHE"
run_prepull pp-hit "$FAKE_BIN_DIR:$BIN" cached
assert_rc "c:hit-rc" 0
if [[ "$(pull_count)" == 0 ]]; then pass "c:hit-no-pulls"; else fail "c:hit-no-pulls" "pulls=$(pull_count) want 0"; fi
assert_out_has "c:hit-echo" 'cache hit'

# Partial cache: restored images skip pulls; the rest pull.
LAST_CACHE="$TMP/pp-partial-cache"; seed_cache "$LAST_CACHE"
run_prepull pp-partial "$FAKE_BIN_DIR:$BIN" half-cached
assert_rc "c:partial-rc" 0
if [[ "$(pull_count)" == 9 ]]; then pass "c:partial-pulls"; else fail "c:partial-pulls" "pulls=$(pull_count) want 9"; fi
assert_out_re "c:partial-echo" 'cache restore gave 3/12'
assert_out_has "c:partial-skip" 'already cached'

# Corrupt cache: `docker load` fails → falls through to the full pull set.
LAST_CACHE="$TMP/pp-loadfail-cache"; seed_cache "$LAST_CACHE"
run_prepull pp-loadfail "$FAKE_BIN_DIR:$BIN" load-fail
assert_rc "c:loadfail-rc" 0
if [[ "$(pull_count)" == 12 ]]; then pass "c:loadfail-pulls"; else fail "c:loadfail-pulls" "pulls=$(pull_count) want 12"; fi
assert_out_has "c:loadfail-echo" 'no usable image cache'

# Extraction floor: 3 refs < 8 fails loudly, docker never invoked.
FEW_BIN_DIR="$TMP/few-bin"
assert_fixture_dir "$FEW_BIN_DIR"
mkdir -p "$FEW_BIN_DIR"
{ printf '#!/bin/sh\n'; printf 'ghcr.io/supabase/only-one:1.0\n'; printf 'ghcr.io/supabase/only-two:2.0\n'; printf 'ghcr.io/supabase/only-three:3.0\n'; } > "$FEW_BIN_DIR/supabase"
chmod +x "$FEW_BIN_DIR/supabase"
run_prepull pp-floor "$FEW_BIN_DIR:$BIN" ok
assert_rc "c:floor-rc" 2
assert_calls "c:floor-no-pulls" 0
assert_out_re "c:floor-error" '^::error::.*expected >= 8'

# Exhausted pulls are best-effort (#11386): the loop walks ALL images —
# img-a/img-b burn 3 ECR + 3 ghcr each (the latch trips after img-b's ECR
# exhaustion), the other 10 refs skip ECR and burn 3 ghcr each: 42 pulls,
# rc 1, every ref named unfetched, and NOTHING is present so no save runs.
run_prepull pp-exhaust "$FAKE_BIN_DIR:$BIN" always
assert_rc "c:exhaust-rc" 1
if [[ "$(pull_count)" == 42 ]]; then pass "c:exhaust-pulls"; else fail "c:exhaust-pulls" "pulls=$(pull_count) want 42"; fi
assert_out_re "c:exhaust-error" '^::error::.*toomanyrequests'
assert_out_has "c:exhaust-unfetched" 'unpulled'
assert_out_has "c:exhaust-unfetched-set" 'img-j'
if grep -qE '^save ' "$STUB_CALLS"; then fail "c:exhaust-no-save" "docker save attempted with zero present refs"; else pass "c:exhaust-no-save"; fi

# ECR-dead latch (#11386): img-a/img-b exhaust the ECR retry budget with a
# throttle tail each (3+3 pulls); the latch then trips ONCE and the other 10
# refs go straight to ghcr — ECR pulls == 6, ghcr pulls == 12, rc 0, exactly
# one latch ::warning::, and the skip marker prints for each remaining image.
run_prepull pp-latch "$FAKE_BIN_DIR:$BIN" ecr-throttle-ghcr-ok
assert_rc "c:latch-rc" 0
if [[ "$(grep -c '^pull public\.ecr\.aws/' "$STUB_CALLS" || true)" == 6 ]]; then pass "c:latch-ecr-pulls"
else fail "c:latch-ecr-pulls" "ecr pulls=$(grep -c '^pull public\.ecr\.aws/' "$STUB_CALLS") want 6 — latch did not cap the dead tax"; fi
if [[ "$(grep -c '^pull ghcr\.io/' "$STUB_CALLS" || true)" == 12 ]]; then pass "c:latch-ghcr-pulls"
else fail "c:latch-ghcr-pulls" "ghcr pulls=$(grep -c '^pull ghcr\.io/' "$STUB_CALLS") want 12"; fi
assert_out_count "c:latch-warn-once" '::warning::ecr latch' 1
assert_out_count "c:latch-skip-lines" 'ecr skipped (latch)' 10
assert_out_has "c:latch-saves" 'pre-pull: wrote'

# Latch reset on a deterministic answer (refs pull in `sort -u` order —
# edge, img-a..img-j, old): edge serves ECR cleanly (pull 1), img-a
# throttles (counter 1, pulls 3), img-b answers `name unknown` (counter
# RESETS to 0 — a deterministic reply is evidence the registry RESPONDS,
# against saturation; pull 1), img-c/img-d throttle again (counter 1 then 2
# → latch; pulls 3+3). ECR pulls == 11; img-e..img-j + old skip (7 images).
# If a deterministic failure were COUNTED as throttle the latch would trip
# at img-b (pulls == 5); if it merely preserved the count, at img-c (== 8).
run_prepull pp-flap "$FAKE_BIN_DIR:$BIN" ecr-flap
assert_rc "c:flap-rc" 0
if [[ "$(grep -c '^pull public\.ecr\.aws/' "$STUB_CALLS" || true)" == 11 ]]; then pass "c:flap-ecr-pulls"
else fail "c:flap-ecr-pulls" "ecr pulls=$(grep -c '^pull public\.ecr\.aws/' "$STUB_CALLS") want 11 — deterministic answer did not reset the streak"; fi
if [[ "$(grep -c '^pull ghcr\.io/' "$STUB_CALLS" || true)" == 11 ]]; then pass "c:flap-ghcr-pulls"
else fail "c:flap-ghcr-pulls" "ghcr pulls=$(grep -c '^pull ghcr\.io/' "$STUB_CALLS") want 11"; fi
assert_out_count "c:flap-warn-once" '::warning::ecr latch' 1
assert_out_count "c:flap-skip-lines" 'ecr skipped (latch)' 7

# Partial save on a failed pull: img-a throttles on BOTH registries; the
# other 11 pull via ECR. rc 1 with the unfetched ref named, and exactly one
# `docker save` whose argv carries every PRESENT ref and never the absent
# one — the partial tar still warms the next run via the post-action save.
run_prepull pp-partial-fail "$FAKE_BIN_DIR:$BIN" partial-fail
assert_rc "c:partialfail-rc" 1
assert_out_re "c:partialfail-error" '^::error::.*img-a'
SAVE_LINES=$(grep -cE '^save ' "$STUB_CALLS" || true)
if [[ "$SAVE_LINES" == 1 ]]; then pass "c:partialfail-save-once"
else fail "c:partialfail-save-once" "docker save invocations=$SAVE_LINES, want 1"; fi
SAVE_ARGV=$(grep -E '^save ' "$STUB_CALLS" | head -1 || true)
if grep -qF 'ghcr.io/supabase/img-b:1.2.0' <<<"$SAVE_ARGV" && \
   grep -qF 'ghcr.io/supabase/img-j:1.10.0' <<<"$SAVE_ARGV"; then pass "c:partialfail-save-present"
else fail "c:partialfail-save-present" "save argv missing present refs — $SAVE_ARGV"; fi
if grep -qF 'img-a' <<<"$SAVE_ARGV"; then fail "c:partialfail-save-absent" "save argv carries the unfetched img-a ref — docker save would die on it"
else pass "c:partialfail-save-absent"; fi

# Missing CLI fails loudly instead of extracting nothing.
NO_BIN_DIR="$TMP/no-bin"
assert_fixture_dir "$NO_BIN_DIR"
mkdir -p "$NO_BIN_DIR"
run_prepull pp-nobin "$NO_BIN_DIR:$BIN" ok
assert_rc "c:nobin-rc" 2
assert_out_re "c:nobin-error" '^::error::.*not on PATH'

# ---------------------------------------------------------------------------
# Floor + verdict. The bound is a literal adjacent to the if (ADR-193); the
# report is printf + exit 1, never routed through the helpers it backstops.
# ---------------------------------------------------------------------------

MIN_ASSERTIONS=163
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
