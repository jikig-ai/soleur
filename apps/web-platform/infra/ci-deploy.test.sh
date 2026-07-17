#!/usr/bin/env bash
set -euo pipefail

# Tests for ci-deploy.sh forced command script.
# Tests validation logic by sourcing the script with mock docker/curl/logger/chown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/ci-deploy.sh"

PASS=0
FAIL=0
TOTAL=0

# Hardened PATH for all test subshells.
# Excludes ~/.local/bin (where real doppler lives) so missing mocks fail loudly
# rather than falling through to real commands.
readonly TEST_PATH_BASE="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Mock factories ---------------------------------------------------------
# All specialized mocks are driven by env vars. Tests set MOCK_DOCKER_MODE /
# MOCK_CURL_MODE before invoking a runner; the runner calls create_base_mocks
# which emits a single unified mock binary per command.
#
# MOCK_DOCKER_MODE values:
#   default        - echo abc123 on run, exit 0 otherwise (minimal)
#   trace          - emit DOCKER_TRACE:<subcmd> for each call; honor
#                    MOCK_DOCKER_PULL_FAIL / MOCK_DOCKER_RUN_FAIL_CANARY /
#                    MOCK_DOCKER_RUN_FAIL_PROD
#   apparmor-trace - emit DOCKER_RUN_ARGS:<args> and DOCKER_EXEC_ARGS:<args>
#   bwrap-trace    - emit DOCKER_EXEC:<args> and BWRAP_CANARY_CHECK marker on
#                    a successful bwrap exec
#   bwrap-fail     - like bwrap-trace but `docker exec ... bwrap ...` fails
#
# MOCK_CURL_MODE values:
#   default        - healthy endpoint (200 / OK); honor MOCK_CURL_CANARY_FAIL
#                    to fail the localhost:3001 canary probe

# #6497: capture what reaches journald when MOCK_LOGGER_CAPTURE_FILE is armed. The journald
# tag `ci-deploy` is shipped OFF-BOX to Better Stack by vector.toml (allowlisted, unscrubbed),
# so it is a real credential boundary — but the mock discarded everything, so no test could
# assert on it. Sentry had a full-sink purity assertion and journald had none; per
# 2026-07-09-sanitized-marker-alongside-raw-sibling-diagnostic-leaks-and-purity-test-scope, a
# purity assertion must cover the WHOLE sink. Default stays exit-0/no-capture so the 137
# pre-existing tests are untouched.
create_mock_logger() {
  cat > "$1/logger" << 'MOCK'
#!/bin/bash
if [[ -n "${MOCK_LOGGER_CAPTURE_FILE:-}" ]]; then
  printf '%s\n' "$*" >> "$MOCK_LOGGER_CAPTURE_FILE"
fi
exit 0
MOCK
  chmod +x "$1/logger"
}

create_mock_sudo() {
  cat > "$1/sudo" << 'MOCK'
#!/bin/bash
# Skip sudo flags (--preserve-env=..., -E, etc.)
while [[ "${1:-}" == -* ]]; do shift; done
cmd="$1"; shift
# Resolve absolute paths via PATH so mocks shadow system binaries.
if [[ "$cmd" == /* ]]; then
  base=$(basename "$cmd")
  resolved=$(type -P "$base" 2>/dev/null || true)
  if [[ -n "$resolved" ]]; then
    exec "$resolved" "$@"
  fi
fi
exec "$cmd" "$@"
MOCK
  chmod +x "$1/sudo"
}

create_mock_chown() {
  cat > "$1/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$1/chown"
}

create_mock_seq() {
  cat > "$1/seq" << 'MOCK'
#!/bin/bash
echo "1"
MOCK
  chmod +x "$1/seq"
}

create_mock_flock() {
  cat > "$1/flock" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_FLOCK_CONTENDED:-}" == "1" ]]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "$1/flock"
}

create_mock_systemctl() {
  cat > "$1/systemctl" << 'MOCK'
#!/bin/bash
# Verb-aware systemctl mock (#6178). The quiesce/enable verify helpers issue
# read-only `is-active`/`is-enabled` queries whose OUTPUT + exit code drive the
# quiesce/enable verdict, so a blanket exit-0 mock would mask them. Per-verb fail
# toggles let a test drive a TOLERATED stop/disable non-zero vs a GENUINE failure.
verb="$1"
case "$verb" in
  is-active)
    # `is-active [--quiet] <unit>`. Default: inactive (systemd exit 3). A test that
    # needs "unit still ACTIVE despite /health down" (arch P2-3) arms MOCK_SYSTEMCTL_ACTIVE=1.
    if [[ "${MOCK_SYSTEMCTL_ACTIVE:-}" == "1" ]]; then echo active; exit 0; fi
    echo inactive; exit 3
    ;;
  is-enabled)
    # Echo the unit's enabled-state; exit 0 iff enabled (systemd convention).
    # Default "disabled" (a clean quiesced unit). Tests override via
    # MOCK_SYSTEMCTL_ENABLED_STATE (e.g. static | enabled).
    state="${MOCK_SYSTEMCTL_ENABLED_STATE:-disabled}"
    echo "$state"
    case "$state" in enabled|enabled-runtime) exit 0 ;; *) exit 1 ;; esac
    ;;
  show)
    # `show -p ExecStart …` — no output (the durable-backend branch stays skipped
    # in tests, matching pre-#6178 blanket-mock behavior).
    exit 0
    ;;
  stop)    [[ "${MOCK_SYSTEMCTL_STOP_FAIL:-}" == "1" ]] && exit 1; exit 0 ;;
  disable) [[ "${MOCK_SYSTEMCTL_DISABLE_FAIL:-}" == "1" ]] && exit 1; exit 0 ;;
  enable)  [[ "${MOCK_SYSTEMCTL_ENABLE_FAIL:-}" == "1" ]] && exit 1; exit 0 ;;
  start)   [[ "${MOCK_SYSTEMCTL_START_FAIL:-}" == "1" ]] && exit 1; exit 0 ;;
esac
# restart + any other verb honor the legacy blanket fail toggle (existing tests).
if [[ "${MOCK_SYSTEMCTL_FAIL:-}" == "1" ]]; then
  exit 1
fi
exit 0
MOCK
  chmod +x "$1/systemctl"
}

create_mock_df() {
  cat > "$1/df" << 'MOCK'
#!/bin/bash
echo "Avail"
if [[ "${MOCK_DF_LOW:-}" == "1" ]]; then
  echo "1000000"
else
  echo "20000000"
fi
MOCK
  chmod +x "$1/df"
}

create_mock_doppler() {
  cat > "$1/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" && "${2:-}" == "get" ]]; then
  # #6005 ghcr_prelude_and_login: `secrets get <NAME> --plain` → bare per-name value.
  # A non-empty distinguishable value so the prelude exports (SENTRY_*, GHCR_*) are
  # observably set. MOCK_DOPPLER_GET_EMPTY simulates the pre-provisioning state
  # (credential not yet in Doppler) → empty value, prelude skips docker login.
  if [[ "${MOCK_DOPPLER_GET_EMPTY:-}" == "1" ]]; then exit 0; fi
  # #6122 zot dark-launch: ZOT_* are EMPTY by default (the merge-time dark state → the
  # unchanged GHCR pull path), so every legacy trace assertion stays single-pull. A test
  # arms MOCK_ZOT_CONFIGURED=1 to simulate the post-provisioning zot-primary state; then
  # ZOT_REGISTRY_URL resolves to the real private-net endpoint and the pull/login creds
  # are present.
  case "${3:-}" in
    ZOT_REGISTRY_URL)
      [[ "${MOCK_ZOT_CONFIGURED:-}" == "1" ]] && echo "10.0.1.30:5000"
      exit 0 ;;
    ZOT_PULL_USER|ZOT_PULL_TOKEN)
      [[ "${MOCK_ZOT_CONFIGURED:-}" == "1" ]] && echo "mock-${3}"
      exit 0 ;;
  esac
  echo "mock-${3:-VALUE}"
  exit 0
fi
if [[ "${1:-}" == "secrets" ]]; then
  echo "KEY=value"
  exit 0
fi
exit 0
MOCK
  chmod +x "$1/doppler"
}

# Unified docker mock. Behavior selected at runtime via MOCK_DOCKER_MODE env var.
# Writing one mock (not five) eliminates drift across test scenarios.
create_docker_mock() {
  cat > "$1/docker" << 'MOCK'
#!/bin/bash
mode="${MOCK_DOCKER_MODE:-default}"

# #5669 cron-drain in-flight probe: `docker exec soleur-web-platform pgrep -f
# claude`. Handled BEFORE the mode case so every swap-reaching test (trace AND
# default) gets a bounded drain — without this the generic `exec`→exit-0 path
# makes cron_in_flight loop until CRON_DRAIN_TIMEOUT. Default: NO claude in
# flight (exit 1) → zero-wait drain, no hang. Armed via MOCK_CRON_INFLIGHT_FILE
# (a countdown of remaining in-flight polls; decremented each call). The `bwrap`
# canary sandbox `docker exec` has no `pgrep` arg so it falls through untouched.
if [[ "${1:-}" == "exec" ]]; then
  for _a in "$@"; do
    if [[ "$_a" == "pgrep" ]]; then
      _f="${MOCK_CRON_INFLIGHT_FILE:-}"
      if [[ -n "$_f" && -f "$_f" ]]; then
        _n=$(cat "$_f" 2>/dev/null || echo 0)
        if [[ "$_n" =~ ^[0-9]+$ ]] && (( _n > 0 )); then
          echo $(( _n - 1 )) > "$_f"
          exit 0   # claude in flight
        fi
      fi
      exit 1       # no claude in flight (default)
    fi
  done
fi

# #5933 Item 4 image-verify handlers, BEFORE the mode case so they work in every
# mode and the app-run failure arming (canary/prod) cannot misfire on them.
#
# cosign verify runs as `docker run --rm <cosign-image> verify --offline ...` —
# detect the `verify` arg. Default: verify PASSES (exit 0). MOCK_COSIGN_VERIFY_FAIL
# simulates a signature failure (WARN mode must still NOT block the deploy).
if [[ "${1:-}" == "run" ]]; then
  for _a in "$@"; do
    if [[ "$_a" == "verify" ]]; then
      # #6005: capture the full cosign `docker run` argv + whether SENTRY_* were
      # already in the script env AT VERIFY TIME (proves the Phase-3 early Doppler
      # fetch ran before verify, so the WARN telemetry is not dark). ci-deploy.sh
      # discards the cosign container stdout (>/dev/null), so record to a file.
      if [[ -n "${MOCK_COSIGN_ARGS_FILE:-}" ]]; then
        printf 'COSIGN_VERIFY_ARGS:%s\n' "$*" >> "$MOCK_COSIGN_ARGS_FILE"
        printf 'SENTRY_AT_VERIFY:%s\n' "${SENTRY_INGEST_DOMAIN:-UNSET}" >> "$MOCK_COSIGN_ARGS_FILE"
      fi
      if [[ "${MOCK_COSIGN_VERIFY_FAIL:-}" == "1" ]]; then
        echo "Error: no matching signatures found" >&2
        exit 1
      fi
      exit 0
    fi
  done
fi
# `docker inspect --format '{{index .RepoDigests 0}}' <img>` resolves the pulled
# tag to its immutable digest. Return a synthetic digest ref unless the test arms
# MOCK_INSPECT_NO_DIGEST (exercises the inspect_failed WARN fallback). Scoped to
# the RepoDigests format so the inngest-case `-f '{{range .Config.Env}}'` inspect
# is untouched.
if [[ "${1:-}" == "inspect" ]]; then
  for _a in "$@"; do
    if [[ "$_a" == *"RepoDigests"* ]]; then
      if [[ "${MOCK_INSPECT_NO_DIGEST:-}" == "1" ]]; then
        echo ""
      else
        # #6122: verify_image_signature now reads the FULL RepoDigests list (range) and
        # selects the entry for the pulled registry. In the zot-primary state the local
        # image carries BOTH a zot and a GHCR RepoDigest; emit both so the registry-scoped
        # grep can pick the right one (zot ⇒ --allow-insecure-registry; ghcr ⇒ not).
        echo "ghcr.io/jikig-ai/soleur-web-platform@sha256:0000000000000000000000000000000000000000000000000000000000000000"
        [[ "${MOCK_ZOT_CONFIGURED:-}" == "1" ]] && \
          echo "10.0.1.30:5000/jikig-ai/soleur-web-platform@sha256:0000000000000000000000000000000000000000000000000000000000000000"
      fi
      exit 0
    fi
  done
fi

# §1A (#6090 recurrence): docker login handler. Records each authenticated-login
# attempt's USER (never the token) to MOCK_LOGIN_ARGS_FILE so a test can assert the
# ghcr_prelude re-fetch-on-FAILURE path retried with the Doppler credential. Fails the
# login iff the --password-stdin token equals MOCK_GHCR_LOGIN_FAIL_TOKEN (simulates a
# present-but-STALE baked GHCR token → registry 401), else succeeds. Runs BEFORE the
# mode case so it works in every mode; default (no fail-token armed) = login ok, matching
# the pre-existing fall-through behavior every legacy login relied on.
if [[ "${1:-}" == "login" ]]; then
  _lreg="${2:-}"; _luser=""; _stdin=0; _prev=""
  for _a in "$@"; do
    [[ "$_a" == "--password-stdin" ]] && _stdin=1
    [[ "$_prev" == "-u" ]] && _luser="$_a"
    _prev="$_a"
  done
  _ltok=""; [[ "$_stdin" == "1" ]] && _ltok="$(cat)"
  [[ -n "${MOCK_LOGIN_ARGS_FILE:-}" ]] && printf 'LOGIN:%s\n' "$_luser" >> "$MOCK_LOGIN_ARGS_FILE"
  # #6497: fail the ZOT login with a caller-supplied stderr so a test can exercise each
  # login_class enum member. Registry-scoped (never ghcr.io) so arming it cannot
  # perturb the GHCR legs the #6400/#6090 tests assert on.
  # MOCK_ZOT_LOGIN_FAIL_STDOUT arms the H-B-stdout hypothesis (the error text went to STDOUT,
  # which the old code discarded) and lets the leak canary cover the stdout stream too. Armed
  # independently of _STDERR: `stderr_chars=0 stdout_chars>0` is a distinct, load-bearing state.
  # MOCK_ZOT_LOGIN_FAIL_RC also ARMS the failure on its own, and that is load-bearing rather than
  # a convenience: the third state of the AC4 split is `stderr_chars=0 stdout_chars=0` (H-B-nowhere
  # / H-D — a login that fails SILENTLY), which is by definition undriveable through either text
  # var. With the arm gated only on the two text vars, the one hypothesis whose whole signature is
  # "no text anywhere" could not be tested at all.
  if [[ -n "${MOCK_ZOT_LOGIN_FAIL_STDERR:-}${MOCK_ZOT_LOGIN_FAIL_STDOUT:-}${MOCK_ZOT_LOGIN_FAIL_RC:-}" && "$_lreg" == "10.0.1.30:5000" ]]; then
    [[ -n "${MOCK_ZOT_LOGIN_FAIL_STDERR:-}" ]] && printf '%s\n' "${MOCK_ZOT_LOGIN_FAIL_STDERR}" >&2
    [[ -n "${MOCK_ZOT_LOGIN_FAIL_STDOUT:-}" ]] && printf '%s\n' "${MOCK_ZOT_LOGIN_FAIL_STDOUT}"
    exit "${MOCK_ZOT_LOGIN_FAIL_RC:-1}"
  fi
  # #6497: the GHCR arm was ASYMMETRIC — caller-supplied stderr for zot, a HARDCODED
  # `denied: authentication required` for ghcr — so no test could drive a GHCR login into any
  # class but authn_rejected. Made symmetric, and registry-scoped to ghcr.io for exactly the
  # reason the zot arm is scoped to zot: arming it must not perturb the OTHER registry's legs.
  # _RC arms on its own here for the same reason it does on the zot arm above — and the symmetry
  # is itself the point: this arm's ASYMMETRY with its sibling is the defect that already had to
  # be fixed here once, so a new capability that lands on only one side re-opens that class.
  if [[ -n "${MOCK_GHCR_LOGIN_FAIL_STDERR:-}${MOCK_GHCR_LOGIN_FAIL_STDOUT:-}${MOCK_GHCR_LOGIN_FAIL_RC:-}" && "$_lreg" == "ghcr.io" ]]; then
    [[ -n "${MOCK_GHCR_LOGIN_FAIL_STDERR:-}" ]] && printf '%s\n' "${MOCK_GHCR_LOGIN_FAIL_STDERR}" >&2
    [[ -n "${MOCK_GHCR_LOGIN_FAIL_STDOUT:-}" ]] && printf '%s\n' "${MOCK_GHCR_LOGIN_FAIL_STDOUT}"
    exit "${MOCK_GHCR_LOGIN_FAIL_RC:-1}"
  fi
  if [[ -n "${MOCK_GHCR_LOGIN_FAIL_TOKEN:-}" && "$_ltok" == "${MOCK_GHCR_LOGIN_FAIL_TOKEN}" ]]; then
    echo "denied: authentication required" >&2
    exit 1
  fi
  exit 0
fi

# #6497: `docker --version` is read by _login_hatch to emit `docker_ver`. The host's docker is
# NOT pinned (cloud-init.yml:428 installs docker-ce unpinned) and NOT observable in telemetry,
# so the instrument makes the host self-report. A fixed version here keeps the field assertable;
# MOCK_DOCKER_VERSION_FAIL=1 drives the docker-absent path (the field must degrade to `unknown`,
# never abort). Handled BEFORE the mode case so every mode gets it.
if [[ "${1:-}" == "--version" ]]; then
  [[ "${MOCK_DOCKER_VERSION_FAIL:-}" == "1" ]] && exit 127
  echo "Docker version ${MOCK_DOCKER_VERSION:-29.4.3}, build 055a478"
  exit 0
fi

# #6122: capture docker pull targets (MOCK_PULL_ARGS_FILE) so a test can assert WHICH
# registry was pulled, and simulate a zot-only pull failure (MOCK_ZOT_PULL_FAIL) to
# exercise the atomic GHCR fallback. Runs BEFORE the mode case so it works in default
# AND trace mode; falls through on success so the mode case still emits its trace.
if [[ "${1:-}" == "pull" ]]; then
  _pref="${2:-}"
  [[ -n "${MOCK_PULL_ARGS_FILE:-}" ]] && printf 'PULL:%s\n' "$_pref" >> "$MOCK_PULL_ARGS_FILE"
  if [[ "${MOCK_ZOT_PULL_FAIL:-}" == "1" && "$_pref" == 10.0.1.30:5000/* ]]; then
    echo "manifest unknown" >&2
    exit 1
  fi
  # #6400: simulate a login-ok/pull-DENY GHCR credential so the pull-site recovery
  # (_ghcr_pull_or_recover) can be exercised. MOCK_GHCR_PULL_DENY_ALWAYS=1 denies every
  # GHCR pull (recovery-miss / fail-open scenario); MOCK_GHCR_PULL_DENY_COUNT_FILE holds
  # an integer countdown decremented per GHCR pull — deny while >0, then succeed (the
  # login-ok/pull-deny→recovered scenario: count=1 ⇒ first pull denies, retry succeeds).
  if [[ "$_pref" == ghcr.io/* ]]; then
    if [[ "${MOCK_GHCR_PULL_DENY_ALWAYS:-}" == "1" ]]; then
      echo "denied: requested access to the resource is denied" >&2
      exit 1
    fi
    if [[ -n "${MOCK_GHCR_PULL_DENY_COUNT_FILE:-}" && -f "${MOCK_GHCR_PULL_DENY_COUNT_FILE}" ]]; then
      _dn=$(cat "$MOCK_GHCR_PULL_DENY_COUNT_FILE" 2>/dev/null || echo 0)
      if [[ "$_dn" =~ ^[0-9]+$ ]] && (( _dn > 0 )); then
        echo $(( _dn - 1 )) > "$MOCK_GHCR_PULL_DENY_COUNT_FILE"
        echo "denied: requested access to the resource is denied" >&2
        exit 1
      fi
    fi
    # #6525: simulate a TRANSIENT/network GHCR pull failure so the bounded transient-retry
    # loop in _ghcr_pull_or_recover can be exercised. TRANSIENT_COUNT_FILE is an integer
    # countdown — emit a network-class stderr while >0 (decrement each GHCR pull), then fall
    # through (a lower arm, or success). TRANSIENT_ALWAYS=1 emits transient on every GHCR pull
    # (the exhaust scenario). MANIFEST_ALWAYS=1 emits a manifest-unknown stderr (the no-retry
    # regression guard; also, composed with a TRANSIENT_COUNT_FILE=1, the GAP-7 transient→manifest
    # tail). The transient stderr string mirrors the fleet-real shape used at T-5B-5c (:3568).
    _T6525_TRANSIENT='read tcp 10.0.1.10:44444->140.82.112.34:443: read: connection reset by peer'
    if [[ -n "${MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE:-}" && -f "${MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE}" ]]; then
      _tn=$(cat "$MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE" 2>/dev/null || echo 0)
      if [[ "$_tn" =~ ^[0-9]+$ ]] && (( _tn > 0 )); then
        echo $(( _tn - 1 )) > "$MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE"
        echo "$_T6525_TRANSIENT" >&2
        exit 1
      fi
    fi
    if [[ "${MOCK_GHCR_PULL_TRANSIENT_ALWAYS:-}" == "1" ]]; then
      echo "$_T6525_TRANSIENT" >&2
      exit 1
    fi
    if [[ "${MOCK_GHCR_PULL_MANIFEST_ALWAYS:-}" == "1" ]]; then
      echo "manifest unknown: manifest unknown" >&2
      exit 1
    fi
  fi
fi

case "$mode" in
  trace)
    # `ps` is read by the ADR-027 pre-run assertion; the script greps stdout
    # for the container name, so the DOCKER_TRACE marker must not appear on
    # stdout for ps calls. Route the trace to stderr and emit name only when
    # explicitly armed.
    if [[ "${1:-}" == "ps" ]]; then
      echo "DOCKER_TRACE:ps" >&2
      if [[ "${MOCK_DOCKER_PS_PROD_RUNNING:-}" == "1" ]]; then
        echo "soleur-web-platform"
      fi
      exit 0
    fi
    echo "DOCKER_TRACE:$1"
    if [[ "${1:-}" == "pull" ]] && [[ "${MOCK_DOCKER_PULL_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    if [[ "${1:-}" == "run" ]]; then
      for arg in "$@"; do
        if [[ "$arg" == *"-canary" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_CANARY:-}" == "1" ]]; then
          exit 1
        fi
      done
      for arg in "$@"; do
        if [[ "$arg" == "soleur-web-platform" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_PROD:-}" == "1" ]]; then
          exit 1
        fi
      done
      echo "abc123"
    fi
    exit 0
    ;;
  apparmor-trace)
    if [[ "${1:-}" == "run" ]]; then
      echo "DOCKER_RUN_ARGS:$*"
      echo "abc123"
    fi
    if [[ "${1:-}" == "exec" ]]; then
      echo "DOCKER_EXEC_ARGS:$*"
    fi
    exit 0
    ;;
  bwrap-trace)
    if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
    if [[ "${1:-}" == "exec" ]]; then
      echo "DOCKER_EXEC:$*"
      for arg in "$@"; do
        if [[ "$arg" == *"bwrap"* ]]; then
          echo "BWRAP_CANARY_CHECK"
          exit 0
        fi
      done
    fi
    exit 0
    ;;
  bwrap-fail)
    if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
    if [[ "${1:-}" == "exec" ]]; then
      for arg in "$@"; do
        if [[ "$arg" == *"bwrap"* ]]; then
          echo "bwrap: No permissions to create new namespace" >&2
          exit 1
        fi
      done
    fi
    exit 0
    ;;
  default|*)
    if [[ "${1:-}" == "run" ]]; then
      for arg in "$@"; do
        if [[ "$arg" == *"-canary" ]] && [[ "${MOCK_DOCKER_RUN_FAIL_CANARY:-}" == "1" ]]; then
          exit 1
        fi
      done
      echo "abc123"
    fi
    if [[ "${1:-}" == "exec" ]]; then
      exit 0
    fi
    if [[ "${1:-}" == "ps" ]]; then
      # ADR-027 pre-run assertion mock — emit the leftover prod container name
      # only when the test explicitly arms this mode.
      if [[ "${MOCK_DOCKER_PS_PROD_RUNNING:-}" == "1" ]]; then
        echo "soleur-web-platform"
      fi
      exit 0
    fi
    exit 0
    ;;
esac
MOCK
  chmod +x "$1/docker"
}

# Unified curl mock. Behavior selected at runtime via env vars:
#   MOCK_CURL_CANARY_FAIL=1     /health probe fails (existing rollback path)
#   MOCK_CURL_LOGIN_5XX=1       /login returns 503 (canary rejects the swap)
#   MOCK_CURL_DASH_5XX=1        /dashboard returns 503
#   MOCK_CURL_DASH_ERROR_BODY=1 /dashboard returns 200 but body contains the
#                               error.tsx sentinel string
#   MOCK_CURL_LOGIN_EMPTY=1     /login returns 200 with empty body
create_curl_mock() {
  cat > "$1/curl" << 'MOCK'
#!/bin/bash
ARGS=("$@")
URL=""
OUTPUT_FILE=""
WANT_HTTP_CODE=0
for ((i=0; i<${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    -o) OUTPUT_FILE="${ARGS[$((i+1))]}" ;;
    -w)
      if [[ "${ARGS[$((i+1))]}" == *"http_code"* ]]; then WANT_HTTP_CODE=1; fi
      ;;
    http*) URL="${ARGS[$i]}" ;;
  esac
done

# #6400: capture Sentry store POST bodies so a test can assert the emitted event
# shape (op tag, level, recovery_stage) for pull_failure_event / pull_auth_recovery_event.
# The ci-deploy Sentry POST is `curl … -X POST https://…/store/ … -d "$payload"`.
if [[ "$URL" == *"/store/"* && -n "${MOCK_SENTRY_CAPTURE_FILE:-}" ]]; then
  _pl=""
  for ((j=0; j<${#ARGS[@]}; j++)); do
    [[ "${ARGS[$j]}" == "-d" ]] && _pl="${ARGS[$((j+1))]}"
  done
  printf '%s\n' "$_pl" >> "$MOCK_SENTRY_CAPTURE_FILE"
  exit 0
fi

# Legacy /health failure path used by existing rollback tests.
if [[ "${MOCK_CURL_CANARY_FAIL:-}" == "1" ]] && [[ "$URL" == *"localhost:3001/health"* ]]; then
  exit 1
fi

write_body() {
  if [[ -n "$OUTPUT_FILE" ]]; then printf '%s' "$1" > "$OUTPUT_FILE"; else printf '%s' "$1"; fi
}

# Per-route mock behavior. Order matters: 8288 must match before generic /health
# because the canary loop's curl -sf for /health does NOT pass -w.
case "$URL" in
  *"8288/v0/gql"*)
    # Cron-plan registry probe (#4650 AC9, #5520). Must match before 8288/health
    # so the substring routes here. Default: a function WITH a cron trigger
    # (healthy plan). Overrides simulate the two H9 failure modes.
    if [[ "${MOCK_CURL_INNGEST_FUNCTIONS_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    if [[ "${MOCK_CURL_INNGEST_FUNCTIONS_NOCRON:-}" == "1" ]]; then
      # H9b: registered but cron de-planned — only the event trigger survives.
      write_body '{"data":{"functions":[{"slug":"soleur-runtime-cron-community-monitor","triggers":[{"type":"EVENT","value":"cron/community-monitor.manual-trigger"}]}]}}'
      exit 0
    fi
    write_body '{"data":{"functions":[{"slug":"soleur-runtime-cron-community-monitor","triggers":[{"type":"CRON","value":"0 8 * * *"},{"type":"EVENT","value":"cron/community-monitor.manual-trigger"}]}]}}'
    exit 0
    ;;
  *"8288/health"*)
    # Counter-driven serve schedule (#6178 quiesce pessimism): serve 200 ONLY on the
    # probe numbers in MOCK_CURL_INNGEST_HEALTH_SERVE_ON (csv), fail otherwise. Lets a
    # test drive "fail on probe 1, serve on probe 2" to prove the quiesce verify keeps
    # probing (all-probes-must-fail) instead of early-returning quiesced on probe 1.
    if [[ -n "${MOCK_CURL_INNGEST_HEALTH_COUNTER:-}" ]]; then
      _n=$(cat "$MOCK_CURL_INNGEST_HEALTH_COUNTER" 2>/dev/null || echo 0); _n=$((_n + 1))
      printf '%s' "$_n" > "$MOCK_CURL_INNGEST_HEALTH_COUNTER"
      if [[ ",${MOCK_CURL_INNGEST_HEALTH_SERVE_ON:-}," == *",$_n,"* ]]; then
        write_body '{"status":200,"message":"OK"}'; exit 0
      fi
      exit 1
    fi
    if [[ "${MOCK_CURL_INNGEST_HEALTH_FAIL:-}" == "1" ]]; then
      exit 1
    fi
    write_body '{"status":200,"message":"OK"}'
    exit 0
    ;;
  *"/health"*)
    write_body "OK"
    if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
    exit 0
    ;;
  *"/login"*)
    if [[ "${MOCK_CURL_LOGIN_5XX:-}" == "1" ]]; then
      write_body ""
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "503"; fi
      exit 0
    fi
    if [[ "${MOCK_CURL_LOGIN_EMPTY:-}" == "1" ]]; then
      write_body ""
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
      exit 0
    fi
    write_body "<html><body>Sign in</body></html>"
    if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
    exit 0
    ;;
  *"/dashboard"*)
    if [[ "${MOCK_CURL_DASH_5XX:-}" == "1" ]]; then
      write_body ""
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "503"; fi
      exit 0
    fi
    if [[ "${MOCK_CURL_DASH_ERROR_BODY:-}" == "1" ]]; then
      # Structured marker from `components/error-boundary-view.tsx`. Replaces
      # the brittle copy-string sentinel — `data-error-boundary=` survives copy
      # edits and digest-populated renders.
      write_body '<html><body><div data-error-boundary="dashboard"><h2>Something went wrong</h2></div></body></html>'
      if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; fi
      exit 0
    fi
    # Default: middleware-redirected unauthenticated request.
    write_body ""
    if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "307"; fi
    exit 0
    ;;
esac

# Fallback for unmatched URLs (legacy callers without an URL arg).
if [[ "$WANT_HTTP_CODE" == "1" ]]; then echo "200"; exit 0; fi
write_body "OK"
exit 0
MOCK
  chmod +x "$1/curl"
}

# Layer 3 mock — passes by default; honors MOCK_LAYER3_FAIL=1 to simulate a
# malformed inlined JWT in the canary bundle.
create_mock_layer3() {
  cat > "$1/canary-bundle-claim-check.sh" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_LAYER3_FAIL:-}" == "1" ]]; then
  echo "canary-bundle-claim-check: simulated bad JWT" >&2
  exit 1
fi
exit 0
MOCK
  chmod +x "$1/canary-bundle-claim-check.sh"
}

# Shared mock scaffold: creates all common mock binaries in $MOCK_DIR.
# Docker/curl behavior is driven by MOCK_DOCKER_MODE / MOCK_CURL_MODE env vars
# (see factory docs above). Specialized overrides are rare after consolidation.
create_base_mocks() {
  local mock_dir="$1"
  create_mock_logger "$mock_dir"
  create_docker_mock "$mock_dir"
  create_curl_mock "$mock_dir"
  create_mock_sudo "$mock_dir"
  create_mock_chown "$mock_dir"
  create_mock_seq "$mock_dir"
  create_mock_flock "$mock_dir"
  create_mock_systemctl "$mock_dir"
  create_mock_df "$mock_dir"
  create_mock_doppler "$mock_dir"
  create_mock_layer3 "$mock_dir"
}

# Parse .reason and .exit_code out of a ci-deploy.state JSON file.
# Prefers jq; falls back to grep/sed so tests run without jq installed.
# Usage: read_state_reason_and_exit <state_file> <reason_var> <exit_var>
read_state_reason_and_exit() {
  local state_file="$1"
  local reason_var="$2"
  local exit_var="$3"
  local _reason _exit
  if command -v jq >/dev/null 2>&1; then
    _reason=$(jq -r '.reason // ""' "$state_file" 2>/dev/null || echo "<jq_parse_error>")
    _exit=$(jq -r '.exit_code // ""' "$state_file" 2>/dev/null || echo "<jq_parse_error>")
  else
    _reason=$(grep -oE '"reason":"[^"]*"' "$state_file" | sed 's/.*:"\(.*\)"/\1/')
    _exit=$(grep -oE '"exit_code":-?[0-9]+' "$state_file" | sed 's/.*://')
  fi
  printf -v "$reason_var" '%s' "$_reason"
  printf -v "$exit_var" '%s' "$_exit"
}

run_deploy() {
  # Run ci-deploy.sh in a subshell with SSH_ORIGINAL_COMMAND set.
  # Mock out docker, curl, logger, chown, flock so the script only tests validation logic.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    # CI_DEPLOY_STATE defaults to a per-run temp path unless the caller already set one.
    if [[ -z "${CI_DEPLOY_STATE:-}" ]]; then
      export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    fi
    create_base_mocks "$MOCK_DIR"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

assert_exit() {
  local description="$1"
  local expected_exit="$2"
  local cmd="${3:-}"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (expected exit $expected_exit, got $actual_exit)"
    echo "        output: $output"
  fi
}

assert_exit_contains() {
  local description="$1"
  local expected_exit="$2"
  local expected_text="$3"
  local cmd="${4:-}"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]] && printf '%s\n' "$output" | grep -qF "$expected_text"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (expected exit $expected_exit with '$expected_text')"
    echo "        actual exit: $actual_exit"
    echo "        output: $output"
  fi
}

run_deploy_traced() {
  # Like run_deploy but docker mock prints DOCKER_TRACE:<subcommand> markers to stdout.
  # Supports MOCK_DOCKER_PULL_FAIL, MOCK_DOCKER_RUN_FAIL_CANARY,
  # MOCK_DOCKER_RUN_FAIL_PROD, and MOCK_CURL_CANARY_FAIL env vars.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    if [[ -z "${CI_DEPLOY_STATE:-}" ]]; then
      export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    fi
    export MOCK_DOCKER_MODE="trace"
    create_base_mocks "$MOCK_DIR"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

echo "=== ci-deploy.sh tests ==="
echo ""

echo "--- Happy path ---"
assert_exit "web-platform deploy succeeds" 0 \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# PR-F follow-up (#3960): inngest component branch.
#
# The inngest branch in ci-deploy.sh now extracts the script + ENV vars from
# the OCI image and runs the script on the HOST (not in a container), because
# the Alpine base image lacks `systemctl`. The branch routes through:
#   docker pull → docker create → docker cp → docker inspect → docker rm → sudo
# Each of these is exercised below.
#
# Image mismatch: an attacker-style image suffix injection should be rejected.
assert_exit_contains "inngest: wrong image rejected" 1 "invalid image" \
  "deploy inngest ghcr.io/attacker/soleur-inngest-bootstrap v1.0.0"

# Branch routing in trace mode: verify the inngest branch actually invokes
# `docker pull` (the first observable docker call). Default mode exits 0
# unconditionally; trace mode emits DOCKER_TRACE:<subcmd> markers we can
# assert against. The branch routes pull → create → cp → inspect → rm → sudo,
# but the mock docker's trace output for `inspect` doesn't contain the ENV
# vars the script greps for (INNGEST_CLI_VERSION, INNGEST_CLI_SHA256), so
# the branch exits with "inngest_image_env_missing" after `cp`. The pull
# marker is reliable; a deeper test would need a richer docker-inspect mock.
assert_inngest_docker_trace() {
  local description="$1"
  local cmd="deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.0.0"
  TOTAL=$((TOTAL + 1))

  local output
  output=$(
    export MOCK_DOCKER_MODE="trace"
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    create_base_mocks "$MOCK_DIR"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1 || true
  )

  # The inngest branch's first observable docker call is `pull`. If we see
  # the trace marker, the branch routed correctly.
  if printf '%s' "$output" | grep -qF "DOCKER_TRACE:pull"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_TRACE:pull found)"
    echo "        output: $output"
  fi
}

assert_inngest_docker_trace "inngest deploy routes through docker pull (trace mode)"

echo ""
echo "--- Empty/missing command ---"
assert_exit_contains "empty command rejected" 1 "no command provided" ""

echo ""
echo "--- Field count validation ---"
assert_exit_contains "single word rejected" 1 "expected 4 fields, got 1" "whoami"

assert_exit_contains "two fields rejected" 1 "expected 4 fields, got 2" "deploy web-platform"

assert_exit_contains "three fields rejected" 1 "expected 4 fields, got 3" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform"

assert_exit_contains "five fields rejected (extra arg)" 1 "expected 4 fields, got 5" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0 extra-arg"

echo ""
echo "--- Action validation ---"
assert_exit_contains "unknown action rejected" 1 "unknown action" \
  "exec web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Component validation ---"
assert_exit_contains "unknown component rejected" 1 "unknown component" \
  "deploy unknown-svc ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Image allowlist (exact match, not prefix) ---"
assert_exit_contains "suffix injection rejected" 1 "invalid image" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-attacker-repo v1.0.0"

assert_exit_contains "arbitrary image rejected" 1 "invalid image" \
  "deploy web-platform evil-image:latest v1.0.0"

echo ""
echo "--- Tag format validation ---"
assert_exit_contains "latest tag rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform latest"

assert_exit_contains "tag without v prefix rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform 1.0.0"

assert_exit_contains "tag with extra suffix rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0-rc1"

echo ""
echo "--- Adversarial input (shell injection) ---"
assert_exit_contains "command substitution in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform $(whoami)'

assert_exit_contains "semicolon injection in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0;id'

assert_exit_contains "backtick injection in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform `whoami`'

assert_exit_contains "newline injection rejected" 1 "expected 4 fields" \
  $'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0\nwhoami'

assert_exit_contains "pipe injection in tag rejected" 1 "invalid tag format" \
  'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0|id'

echo ""
echo "--- Docker prune before pull ---"

assert_prune_before_pull() {
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy_traced "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  # Check that DOCKER_TRACE:image appears before DOCKER_TRACE:pull in output
  local prune_line pull_line
  prune_line=$(printf '%s\n' "$output" | { grep -n "DOCKER_TRACE:image" || true; } | head -1 | cut -d: -f1)
  pull_line=$(printf '%s\n' "$output" | { grep -n "DOCKER_TRACE:pull" || true; } | head -1 | cut -d: -f1)

  if [[ "$actual_exit" -eq 0 ]] && [[ -n "$prune_line" ]] && [[ -n "$pull_line" ]] && [[ "$prune_line" -lt "$pull_line" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (prune_line=$prune_line pull_line=$pull_line exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_prune_before_pull "web-platform: prune runs before pull" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Disk space pre-flight check ---"

assert_disk_space_rejection() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(export MOCK_DF_LOW=1; run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "insufficient disk space"; then
    PASS=$((PASS + 1))
    echo "  PASS: low disk space rejects deploy"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: low disk space rejects deploy (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_disk_space_rejection

echo ""
echo "--- Canary rollback (web-platform) ---"

assert_canary_trace_order() {
  # Verify canary deploy produces correct Docker trace ordering.
  local description="$1"
  local cmd="$2"
  local expected_order="$3"  # pipe-separated trace markers, e.g., "image|pull|stop|rm|run|stop|rm|run|stop|rm"
  local extra_env="${4:-}"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    eval "$extra_env"
    run_deploy_traced "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Extract ordered DOCKER_TRACE lines
  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  if [[ "$traces" == "$expected_order" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected traces: $expected_order"
    echo "        actual traces:   $traces"
    echo "        exit: $actual_exit"
  fi
}

# Canary success: prune → pull → stop(stale canary) → rm(stale canary) → run(canary) →
#   bwrap sandbox check (docker exec) → stop(canary) → rm(canary) [#5669 memory-dwell:
#   torn down BEFORE the drain] → stop(old) → rm(old) →
#   ps(ADR-027 single-replica assertion) → run(prod)
# (#5669/ADR-078: the post-success canary teardown was removed — the canary is now
#  torn down before the cron drain gate, so it no longer appears after run(prod).)
assert_canary_trace_order "canary success: correct docker trace order" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "image|pull|stop|rm|run|exec|stop|rm|stop|rm|ps|run"

# Canary failure / rollback: prune → pull → stop(stale) → rm(stale) → run(canary) →
#   logs(canary) → stop(canary) → rm(canary)
# Old container is NOT stopped or removed.
assert_canary_rollback() {
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_CURL_CANARY_FAIL=1
    run_deploy_traced "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # Expected: system|pull|stop|rm|run|stop|rm
  # (prune, pull, stale canary cleanup [stop, rm], canary run, canary stop, canary rm)
  # Note: docker logs is piped to logger so its trace marker is consumed.
  # Crucially: only 2 stop/rm pairs (stale cleanup + canary cleanup), NOT 3 (no old production stop/rm)
  local expected="image|pull|stop|rm|run|stop|rm"

  if [[ "$actual_exit" -eq 1 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected traces: $expected (exit 1)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_canary_rollback "canary failure: rollback preserves old container" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# Layered canary probe set (#3014): /health success alone is not enough — the
# probe must also exercise /login (public route) and /dashboard (auth-required)
# and reject any rendered body containing the error.tsx sentinel string. These
# tests cover the failure modes the legacy /health-only probe missed.
assert_canary_layered_rollback() {
  local description="$1"
  local fail_var="$2"  # e.g., MOCK_CURL_LOGIN_5XX
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export "$fail_var"=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # Expected on rollback (CANARY_HEALTHY=false): no swap to prod.
  # image|pull|stop|rm|run|stop|rm — same shape as the existing rollback test.
  local expected="image|pull|stop|rm|run|stop|rm"

  if [[ "$actual_exit" -eq 1 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected traces: $expected (exit 1)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_canary_layered_rollback \
  "layered canary: /login 5xx → rollback (no swap)" \
  "MOCK_CURL_LOGIN_5XX"

assert_canary_layered_rollback \
  "layered canary: /dashboard 5xx → rollback (no swap)" \
  "MOCK_CURL_DASH_5XX"

assert_canary_layered_rollback \
  "layered canary: /dashboard renders error.tsx sentinel in body → rollback" \
  "MOCK_CURL_DASH_ERROR_BODY"

assert_canary_layered_rollback \
  "layered canary: /login returns empty body → rollback" \
  "MOCK_CURL_LOGIN_EMPTY"

assert_canary_layered_rollback \
  "layered canary: Layer 3 JWT-claims check fails → rollback" \
  "MOCK_LAYER3_FAIL"

# Docker pull failure: no canary started
assert_pull_failure() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_PULL_FAIL=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # Should only have prune and pull (which fails), then script exits
  local expected="image|pull"

  if [[ "$actual_exit" -ne 0 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: docker pull failure: no canary started"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: docker pull failure: no canary started"
    echo "        expected traces: $expected (exit != 0)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_pull_failure

# #6396: pull_failure_event carries tags.host_id so a deploy-path `image pull failed` is host-
# attributable from Sentry alone (PR #6395 had to cross-reference the release aggregate JSON to
# pin it to web-2). Assert the wiring at the source, scoped to the pull_failure_event body: the
# payload builder must thread the readonly HOST_ID global (empty-safe) into the tags object.
# Runtime HOST_ID resolution is unit-tested (host-identity.test.ts) and its docker-run injection
# is proven by assert_soleur_host_id above; this guards the ONE remaining seam — host_id reaching
# the pull_failure_event Sentry payload. Body-scoped so an unrelated `host_id` (e.g. the other
# Sentry emits, which do NOT tag host_id) cannot satisfy it vacuously.
assert_pull_failure_host_id() {
  TOTAL=$((TOTAL + 1))
  local body
  body="$(awk '/^pull_failure_event\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
  if printf '%s' "$body" | grep -qE -- '--arg h "\$\{HOST_ID:-\}"' \
     && printf '%s' "$body" | grep -qE 'host_id: \$h'; then
    PASS=$((PASS + 1))
    echo "  PASS: pull_failure_event threads --arg h \"\${HOST_ID:-}\" into tags.host_id (#6396)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: pull_failure_event must pass --arg h \"\${HOST_ID:-}\" AND put host_id: \$h in tags (#6396)"
  fi
}

assert_pull_failure_host_id

# Canary crash on start: docker run fails for canary
assert_canary_crash() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_RUN_FAIL_CANARY=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # prune, pull, stale cleanup (stop, rm), canary run (fails) → script exits via set -e
  local expected="image|pull|stop|rm|run"

  if [[ "$actual_exit" -ne 0 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: canary crash on start: no health check, old untouched"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: canary crash on start: no health check, old untouched"
    echo "        expected traces: $expected (exit != 0)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_canary_crash

# Production start failure after canary success
assert_prod_start_failure() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_RUN_FAIL_PROD=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local traces
  traces=$(printf '%s\n' "$output" | grep "^DOCKER_TRACE:" | sed 's/DOCKER_TRACE://' | tr '\n' '|' | sed 's/|$//')

  # prune, pull, stale cleanup (stop, rm), canary run (ok), canary health ok,
  # bwrap sandbox check, #5669 pre-drain canary teardown (stop, rm), old stop,
  # old rm, ADR-027 ps assertion (empty in this mock mode), prod run (fails),
  # production_start_failed defensive canary teardown (stop, rm)
  local expected="image|pull|stop|rm|run|exec|stop|rm|stop|rm|ps|run|stop|rm"

  if [[ "$actual_exit" -ne 0 ]] && [[ "$traces" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: production start failure after canary success"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: production start failure after canary success"
    echo "        expected traces: $expected (exit != 0)"
    echo "        actual traces:   $traces (exit $actual_exit)"
  fi
}

assert_prod_start_failure

# Flock rejects concurrent deploy
assert_flock_rejection() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_FLOCK_CONTENDED=1
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "another deploy in progress"; then
    PASS=$((PASS + 1))
    echo "  PASS: flock rejects concurrent deploy"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: flock rejects concurrent deploy (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_flock_rejection

echo ""
echo "--- Doppler hardening (resolve_env_file) ---"

# Helper: run deploy with Doppler-specific environment controls.
# MOCK_DOPPLER_MISSING=1  -> doppler binary not in PATH
# MOCK_DOPPLER_TOKEN=""   -> DOPPLER_TOKEN unset
# MOCK_DOPPLER_FAIL=1     -> doppler secrets download fails
run_deploy_doppler() {
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"

    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    create_base_mocks "$MOCK_DIR"

    # Effective tool PATH: mocks first, then standard system dirs.
    local effective_path="$MOCK_DIR:$TEST_PATH_BASE"

    # Override: doppler mock with MOCK_DOPPLER_MISSING/MOCK_DOPPLER_FAIL support
    if [[ "${MOCK_DOPPLER_MISSING:-}" == "1" ]]; then
      rm -f "$MOCK_DIR/doppler"
      # ci-deploy.sh gates on `command -v doppler`. Removing the MOCK_DIR mock is
      # NOT enough on hosts that ALSO ship a system-wide doppler in a TEST_PATH_BASE
      # dir (e.g. /usr/bin/doppler on many dev boxes — NOT the CI runner): it leaks
      # past the removed mock, the real binary runs against the fake token, and the
      # "not installed" branch is never exercised (false FAIL, local-only). When we
      # detect such a leak, mirror the base dirs into a farm WITHOUT doppler so the
      # negative path is reachable everywhere. No-op on CI (no system doppler).
      if PATH="$TEST_PATH_BASE" command -v doppler >/dev/null 2>&1; then
        local _farm="$MOCK_DIR/nodoppler-bin"; mkdir -p "$_farm"
        local _d _f _b _oldifs="$IFS"; IFS=:
        for _d in $TEST_PATH_BASE; do
          [[ -d "$_d" ]] || continue
          for _f in "$_d"/*; do
            _b="${_f##*/}"
            [[ "$_b" == doppler ]] && continue
            [[ -e "$_farm/$_b" ]] || ln -s "$_f" "$_farm/$_b" 2>/dev/null || true
          done
        done
        IFS="$_oldifs"
        effective_path="$MOCK_DIR:$_farm"
      fi
    elif [[ "${MOCK_DOPPLER_FAIL:-}" == "1" ]]; then
      cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
echo "Doppler Error: mkdir /home/deploy/.doppler: read-only file system" >&2
exit 1
MOCK
      chmod +x "$MOCK_DIR/doppler"
    fi

    # Set DOPPLER_TOKEN unless explicitly empty
    if [[ "${MOCK_DOPPLER_TOKEN_UNSET:-}" != "1" ]]; then
      export DOPPLER_TOKEN="dp.st.prd.mock-token"
    else
      unset DOPPLER_TOKEN
    fi

    # MOCK_DIR mocks win over system tools; for MOCK_DOPPLER_MISSING on a host with
    # a system doppler, effective_path is a doppler-free farm (see above).
    export PATH="$effective_path"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

# Test: Doppler CLI not installed -> exit with error
assert_doppler_missing() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_MISSING=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "Doppler CLI not installed"; then
    PASS=$((PASS + 1))
    echo "  PASS: missing doppler CLI exits with error"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: missing doppler CLI exits with error (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_missing

# Test: DOPPLER_TOKEN not set -> exit with error
assert_doppler_token_missing() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_TOKEN_UNSET=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "DOPPLER_TOKEN environment variable not set"; then
    PASS=$((PASS + 1))
    echo "  PASS: missing DOPPLER_TOKEN exits with error"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: missing DOPPLER_TOKEN exits with error (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_token_missing

# Test: Doppler download fails -> exit with error (no .env fallback)
assert_doppler_download_fails() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_FAIL=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "Failed to download secrets from Doppler:"; then
    PASS=$((PASS + 1))
    echo "  PASS: doppler download failure exits with error"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: doppler download failure exits with error (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_download_fails

# Test: Doppler download fails -> error message includes actual Doppler error
assert_doppler_error_logged() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(
    export MOCK_DOPPLER_FAIL=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 1 ]] && printf '%s\n' "$output" | grep -qF "read-only file system"; then
    PASS=$((PASS + 1))
    echo "  PASS: doppler error message included in output"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: doppler error message included in output (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_error_logged

# Test: No fallback to /mnt/data/.env in any failure case
assert_no_env_fallback() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  # With Doppler missing, the old code would fall back to /mnt/data/.env
  # The new code must never reference /mnt/data/.env
  output=$(
    export MOCK_DOPPLER_MISSING=1
    run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if ! printf '%s\n' "$output" | grep -qF "/mnt/data/.env"; then
    PASS=$((PASS + 1))
    echo "  PASS: no fallback to /mnt/data/.env"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: no fallback to /mnt/data/.env (output references .env)"
    echo "        output: $output"
  fi
}

assert_no_env_fallback

# Test: Doppler works -> deploy succeeds
assert_doppler_success() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: doppler success deploys successfully"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: doppler success deploys successfully (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_doppler_success

# --- #5933 Item 4: image signature verify (WARN default; ENFORCE gate) ---------
# WARN mode (default) must NEVER block a healthy deploy on a verify failure —
# these two pass IDENTICALLY with or without the gate, so the ENFORCE test below
# is what proves the gate is actually load-bearing (WARN and ENFORCE diverge on
# the SAME MOCK_COSIGN_VERIFY_FAIL input).
assert_verify_warn_does_not_block() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(export MOCK_COSIGN_VERIFY_FAIL=1; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: WARN cosign verify FAIL does not block the deploy (#5933 Item 4)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: WARN cosign verify FAIL blocked the deploy (exit=$actual_exit)"; echo "        output: $output"
  fi
}
assert_verify_warn_does_not_block

assert_inspect_warn_does_not_block() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit
  output=$(export MOCK_INSPECT_NO_DIGEST=1; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: WARN inspect_failed (no RepoDigest) does not block the deploy (#5933 Item 4)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: WARN inspect_failed blocked the deploy (exit=$actual_exit)"; echo "        output: $output"
  fi
}
assert_inspect_warn_does_not_block

# ENFORCE mode MUST block the SAME verify failure (proves the gate is load-bearing,
# not vacuous) and keep the old container live via final_write_state 1.
assert_verify_enforce_blocks() {
  TOTAL=$((TOTAL + 1))
  local output actual_exit sf reason exitc
  sf=$(mktemp)
  output=$(export IMAGE_VERIFY_MODE=enforce MOCK_COSIGN_VERIFY_FAIL=1 CI_DEPLOY_STATE="$sf"; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && actual_exit=0 || actual_exit=$?
  read_state_reason_and_exit "$sf" reason exitc
  rm -f "$sf"
  if [[ "$actual_exit" -ne 0 && "$reason" == "cosign_verify_failed" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: ENFORCE cosign verify FAIL blocks the deploy (reason=$reason — gate is load-bearing)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: ENFORCE verify fail did not block as expected (exit=$actual_exit reason=$reason)"; echo "        output: $output"
  fi
}
assert_verify_enforce_blocks

# --- #6005 Design B′: cosign invocation shape + SENTRY-before-verify ordering -----
# The verify `docker run` MUST run `--network host` (host-egress .sig fetch, ADR-087),
# mount the deploy docker config :ro (private-pull auth) and the pinned trusted root
# :ro, and pass `--offline --trusted-root` (offline verify). SENTRY_* MUST already be
# in the script env at verify time (the Phase-3 early Doppler fetch ran first → the
# WARN telemetry is not dark, which is the whole point of this ENFORCE-prep issue).
assert_bprime_cosign_invocation() {
  TOTAL=$((TOTAL + 1))
  local argsfile args sentry ok=1
  argsfile=$(mktemp)
  ( export MOCK_COSIGN_ARGS_FILE="$argsfile"; run_deploy_doppler "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" >/dev/null 2>&1 ) || true
  args=$(grep '^COSIGN_VERIFY_ARGS:' "$argsfile" 2>/dev/null | head -1)
  sentry=$(grep '^SENTRY_AT_VERIFY:' "$argsfile" 2>/dev/null | head -1)
  rm -f "$argsfile"
  [[ -n "$args" ]] || ok=0
  printf '%s' "$args" | grep -qF -- '--network host' || ok=0
  printf '%s' "$args" | grep -qE -- '-v [^ ]+:/root/\.docker/config\.json:ro' || ok=0
  printf '%s' "$args" | grep -qE -- '-v [^ ]+:/etc/cosign/trusted_root\.json:ro' || ok=0
  printf '%s' "$args" | grep -qF -- '--offline' || ok=0
  printf '%s' "$args" | grep -qF -- '--trusted-root=/etc/cosign/trusted_root.json' || ok=0
  # SENTRY_* set at verify time (not the UNSET sentinel) — telemetry not dark.
  [[ -n "$sentry" && "$sentry" != "SENTRY_AT_VERIFY:UNSET" ]] || ok=0
  if [[ "$ok" == "1" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: B′ cosign run (--network host + config/trusted-root :ro mounts + --offline --trusted-root) and SENTRY set before verify (#6005)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: B′ cosign invocation/ordering (#6005)"; echo "        args: $args"; echo "        sentry: $sentry"
  fi
}
assert_bprime_cosign_invocation

# ADR-087 rejects widening the shared container egress allowlist — ghcr.io reach is
# confined to the ephemeral host-net verifier. Guard against a regression that adds
# ghcr.io back into cron-egress-allowlist.txt.
assert_no_ghcr_allowlist_widening() {
  TOTAL=$((TOTAL + 1))
  local allowlist
  allowlist="$(dirname "$DEPLOY_SCRIPT")/cron-egress-allowlist.txt"
  if [[ -f "$allowlist" ]] && grep -qiE '(^|[^a-z0-9.-])ghcr\.io' "$allowlist"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: ghcr.io must NOT be in cron-egress-allowlist.txt (ADR-087 host-net design) (#6005)"
  else
    PASS=$((PASS + 1)); echo "  PASS: ghcr.io absent from cron-egress-allowlist.txt (ADR-087 — no container allowlist widening) (#6005)"
  fi
}
assert_no_ghcr_allowlist_widening

# AC: the ENFORCE flip stays OUT OF SCOPE — the default MUST remain warn.
TOTAL=$((TOTAL + 1))
if grep -qE 'IMAGE_VERIFY_MODE:-warn' "$DEPLOY_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: IMAGE_VERIFY_MODE default is still 'warn' (no ENFORCE flip) (#6005)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: IMAGE_VERIFY_MODE default must remain 'warn' — ENFORCE flip is out of scope (#6005)"
fi

echo ""
echo "--- AppArmor profile on docker run ---"

assert_apparmor_profile() {
  # Verify that docker run commands include --security-opt apparmor=soleur-bwrap
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    run_deploy "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Check that all DOCKER_RUN_ARGS lines contain apparmor=soleur-bwrap
  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    echo "        output: $output"
    return
  fi

  local all_have_apparmor=true
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -qF "apparmor=soleur-bwrap"; then
      all_have_apparmor=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_apparmor" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing --security-opt apparmor=soleur-bwrap)"
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5
  fi
}

assert_apparmor_profile "web-platform: docker run has apparmor=soleur-bwrap" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- tmpfs /tmp on docker run (closes #2473) ---"

assert_tmpfs_flag() {
  # Verify every docker run line contains --tmpfs /tmp:…size=256m AND that
  # noexec is NOT on the tmpfs argument. The negative check locks the
  # regression class documented in Research Reconciliation row 5: Docker's
  # default --tmpfs set applies noexec, which silently breaks git credential
  # helpers in /tmp/git-cred-<uuid> (randomCredentialPath in github-app.ts,
  # consumed by workspace.ts / session-sync.ts / push-branch.ts).
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    run_deploy "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    echo "        output: $output"
    return
  fi

  local all_have_tmpfs=true
  local any_has_noexec=false
  while IFS= read -r line; do
    # Positive: --tmpfs /tmp:<opts with size=256m>
    if ! printf '%s\n' "$line" | grep -qE -- "--tmpfs /tmp:[^ ]*size=256m"; then
      all_have_tmpfs=false
    fi
    # Negative: no noexec on the /tmp tmpfs argument specifically.
    if printf '%s\n' "$line" | grep -qE -- "--tmpfs /tmp:[^ ]*noexec"; then
      any_has_noexec=true
    fi
  done <<< "$run_lines"

  if [[ "$all_have_tmpfs" == "true" ]] && [[ "$any_has_noexec" == "false" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    if [[ "$all_have_tmpfs" != "true" ]]; then
      echo "  FAIL: $description (missing --tmpfs /tmp:…size=256m on some docker run)"
    fi
    if [[ "$any_has_noexec" == "true" ]]; then
      echo "  FAIL: $description (tmpfs has noexec — breaks git credential helper)"
    fi
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5 | sed 's/^/    /'
  fi
}

assert_tmpfs_flag "web-platform: docker run has --tmpfs /tmp:size=256m without noexec" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- CRON_WORKSPACE_ROOT on docker run (#4684/#4689) ---"

assert_cron_workspace_root() {
  # Verify every docker run line carries -e CRON_WORKSPACE_ROOT=/workspaces.
  # Crons mkdtemp their ephemeral clone workspace under this root; in prod it
  # must be the roomy /mnt/data/workspaces volume, NOT the 256 MB /tmp tmpfs,
  # or a git clone of the ~100 MB soleur tree ENOSPCs. The assertion spans ALL
  # docker run lines (canary AND prod) — scoping it to one line would let a
  # canary/prod environment skew ship silently. (The `.cron` subdir isolation
  # was reverted in the #4886 follow-up — a deploy-critical-path mkdir on a full
  # volume deadlocked the deploy; cron-workspace-gc sweeps /workspaces directly,
  # guarded by the `soleur-` prefix. Dedicated-volume isolation deferred to #4891.)
  local description="$1"
  local cmd="$2"

  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    run_deploy "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    echo "        output: $output"
    return
  fi

  local all_have_root=true
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -qF -- "-e CRON_WORKSPACE_ROOT=/workspaces"; then
      all_have_root=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_root" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing -e CRON_WORKSPACE_ROOT=/workspaces)"
    echo "        docker run lines:"
    printf '%s\n' "$run_lines" | head -5 | sed 's/^/    /'
  fi
}

assert_cron_workspace_root "web-platform: docker run has -e CRON_WORKSPACE_ROOT=/workspaces" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- SOLEUR_HOST_ID on docker run (#5274 Phase 3, ADR-068) ---"

assert_soleur_host_id() {
  # Verify EVERY docker run line (canary AND prod) carries -e SOLEUR_HOST_ID=<id> —
  # the per-user worktree write-lease's placement authority (host-identity.ts). A
  # canary/prod skew (one host-id-tagged, one not) would let a lease-mismatch ship
  # silently once the git-data flag flips. Uses SOLEUR_HOST_ID_OVERRIDE so the id is
  # deterministic (the on-host metadata/machine-id resolution is unit-tested in
  # host-identity.test.ts; here we prove the INJECTION reaches both containers).
  local description="$1"
  local cmd="$2"
  local expected="host-under-test-42"

  TOTAL=$((TOTAL + 1))

  local output
  output=$(
    export MOCK_DOCKER_MODE="apparmor-trace"
    export SOLEUR_HOST_ID_OVERRIDE="$expected"
    run_deploy "$cmd" 2>&1
  ) || true

  local run_lines
  run_lines=$(printf '%s\n' "$output" | grep "^DOCKER_RUN_ARGS:" || true)

  if [[ -z "$run_lines" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (no DOCKER_RUN_ARGS lines found)"
    return
  fi

  local all_have_id=true
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -qF -- "-e SOLEUR_HOST_ID=${expected}"; then
      all_have_id=false
      break
    fi
  done <<< "$run_lines"

  if [[ "$all_have_id" == "true" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (docker run missing -e SOLEUR_HOST_ID=${expected})"
    printf '%s\n' "$run_lines" | head -5 | sed 's/^/    /'
  fi
}

assert_soleur_host_id "web-platform: docker run has -e SOLEUR_HOST_ID on both canary and prod" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Deploy fan-out loop-prevention (#5274 Phase 3, ADR-068) ---"
# The 2-host fan-out is loop-safe ONLY if the /hooks/deploy-peer hook does NOT
# receive the peer list — otherwise a forwarded deploy would re-fan (A->B->A...).
# The invariant lives in hooks.json.tmpl: /hooks/deploy passes SOLEUR_DEPLOY_PEERS,
# /hooks/deploy-peer does NOT. Parsed structurally (jq over each hook's
# pass-environment envnames) so a future edit that leaks peers into deploy-peer
# fails CI. Template exprs (${jsonencode(...)}) are neutralised to valid JSON first.
HOOKS_TMPL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks.json.tmpl"
if [[ -f "$HOOKS_TMPL" ]]; then
  rendered="$(sed -E 's/\$\{jsonencode\([^)]*\)\}/"REDACTED"/g' "$HOOKS_TMPL")"
  deploy_env="$(printf '%s' "$rendered" | jq -r '.[] | select(.id=="deploy") | (.["pass-environment-to-command"] // [])[].envname' 2>/dev/null)"
  peer_env="$(printf '%s' "$rendered" | jq -r '.[] | select(.id=="deploy-peer") | (.["pass-environment-to-command"] // [])[].envname' 2>/dev/null)"

  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$deploy_env" | grep -qx "SOLEUR_DEPLOY_PEERS"; then
    PASS=$((PASS + 1)); echo "  PASS: /hooks/deploy passes SOLEUR_DEPLOY_PEERS (fan-out trigger)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: /hooks/deploy is missing SOLEUR_DEPLOY_PEERS — fan-out would never fire"
  fi

  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$peer_env" | grep -qx "SOLEUR_DEPLOY_PEERS"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: /hooks/deploy-peer passes SOLEUR_DEPLOY_PEERS — a forwarded deploy would RE-FAN (loop)"
  else
    PASS=$((PASS + 1)); echo "  PASS: /hooks/deploy-peer does NOT pass SOLEUR_DEPLOY_PEERS (loop-prevented)"
  fi
else
  echo "  SKIP: hooks.json.tmpl not found at $HOOKS_TMPL"
fi

echo ""
echo "--- Bwrap canary sandbox check ---"

assert_bwrap_canary_check() {
  # Verify that a bwrap check runs against the canary container after health check.
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="bwrap-trace"
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "BWRAP_CANARY_CHECK"; then
    PASS=$((PASS + 1))
    echo "  PASS: bwrap canary sandbox check runs during deploy"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: bwrap canary sandbox check runs during deploy (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_bwrap_canary_check

assert_bwrap_canary_failure_rollback() {
  # Verify that bwrap check failure triggers canary rollback.
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="bwrap-fail"
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -ne 0 ]] && printf '%s\n' "$output" | grep -qiF "sandbox"; then
    PASS=$((PASS + 1))
    echo "  PASS: bwrap canary failure triggers rollback"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: bwrap canary failure triggers rollback (exit=$actual_exit)"
    echo "        output: $output"
  fi
}

assert_bwrap_canary_failure_rollback

echo ""
echo "--- Bwrap userns sysctl drift detector (non-blocking) ---"

assert_bwrap_userns_drift_detector_nonblocking() {
  # Follow-up to #4932/#4941: ci-deploy.sh must read the host sysctl
  # kernel.apparmor_restrict_unprivileged_userns after the prod container starts
  # and surface a drift WARN — but it must be NON-BLOCKING (detection only), so a
  # drift reading never rolls back a deploy the way the reverted #4932 gating
  # probe did. Source-level guard: the drift branch must use `logger`, and the
  # whole userns check must NOT call `final_write_state 1` or `exit` (anchored on
  # the unique message tokens; non-vacuous — neither token existed pre-#4941).
  TOTAL=$((TOTAL + 1))

  local block
  # Extract the userns check block: the logger lines from the first
  # BWRAP_USERNS_SYSCTL token through the trailing "Deploy succeeded".
  block=$(awk '/BWRAP_USERNS_SYSCTL/{f=1} f{print} /Deploy succeeded/{f=0}' "$DEPLOY_SCRIPT" 2>/dev/null)

  # `|| true`: grep -c exits 1 on zero matches, which would abort under set -e.
  local has_ok has_drift gates
  has_ok=$(printf '%s\n' "$block" | grep -cF "BWRAP_USERNS_SYSCTL_CHECK: ok" || true)
  has_drift=$(printf '%s\n' "$block" | grep -cF "BWRAP_USERNS_SYSCTL_DRIFT" || true)
  # Non-blocking: the block must not contain a failure-write or exit.
  gates=$(printf '%s\n' "$block" | grep -cE 'final_write_state 1|exit 1|exit 0' || true)

  if [[ "$has_ok" -ge 1 && "$has_drift" -ge 1 && "$gates" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: userns sysctl drift detector present and non-blocking"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: userns drift detector must be present and non-blocking (ok=$has_ok drift=$has_drift gating_calls=$gates)"
  fi
}

assert_bwrap_userns_drift_detector_nonblocking

echo ""
echo "--- Env file cleanup on all exit paths ---"

assert_env_file_cleanup() {
  local description="$1"
  local extra_env="${2:-}"

  TOTAL=$((TOTAL + 1))

  # Tracker dir survives both the deploy process and test subshell
  local tracker_dir
  tracker_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    export ENV_FILE_TRACKER="$tracker_dir/env_file_path"
    create_base_mocks "$MOCK_DIR"
    # Default docker mock already honors MOCK_DOCKER_RUN_FAIL_CANARY and returns
    # exit 0 for exec (the cleanup scenario never needs bwrap tracing).

    # Mock mktemp: create a real temp file but record its path to the tracker
    cat > "$MOCK_DIR/mktemp" << 'MOCK'
#!/bin/bash
tmpfile=$(/usr/bin/mktemp "$@")
if [[ -n "${ENV_FILE_TRACKER:-}" ]]; then
  echo "$tmpfile" > "$ENV_FILE_TRACKER"
fi
echo "$tmpfile"
MOCK
    chmod +x "$MOCK_DIR/mktemp"

    eval "$extra_env"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Check: does the env file still exist?
  if [[ -f "$tracker_dir/env_file_path" ]]; then
    local env_file_path
    env_file_path=$(cat "$tracker_dir/env_file_path")
    if [[ ! -f "$env_file_path" ]]; then
      PASS=$((PASS + 1))
      echo "  PASS: $description"
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL: $description (env file still exists: $env_file_path)"
      rm -f "$env_file_path"  # clean up leaked file
    fi
  else
    # No env file was ever created (e.g., failure before resolve_env_file)
    PASS=$((PASS + 1))
    echo "  PASS: $description (no env file created)"
  fi

  rm -rf "$tracker_dir"
}

assert_env_file_cleanup "canary crash cleans up env file" \
  "export MOCK_DOCKER_RUN_FAIL_CANARY=1"

assert_env_file_cleanup "successful deploy cleans up env file" ""

echo ""
echo "--- Deploy state file (#2185 observability) ---"

# assert_state_contains: runs deploy, then parses the state file written by ci-deploy.sh.
# Validates .exit_code and .reason via jq (falls back to grep if jq unavailable).
# Signature: assert_state_contains <description> <expected_reason> <expected_exit_code> [<cmd>] [<extra_env>] [<runner>]
#   <runner> defaults to run_deploy_traced. Pass run_deploy_doppler for scenarios
#   that need the restricted PATH + configurable doppler mock (doppler_* reasons).
assert_state_contains() {
  local description="$1"
  local expected_reason="$2"
  local expected_exit_code="$3"
  # Use ${4-default} (no colon) so an explicitly empty "" for cmd is preserved
  # -- needed to exercise the command_missing branch.
  local cmd="${4-deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0}"
  local extra_env="${5:-}"
  local runner="${6:-run_deploy_traced}"

  TOTAL=$((TOTAL + 1))

  # State file lives outside the per-run MOCK_DIR so we can read it after the subshell cleans up.
  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"

  local output actual_exit
  output=$(
    eval "$extra_env"
    export CI_DEPLOY_STATE="$state_file"
    "$runner" "$cmd" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

  if [[ "$actual_reason" == "$expected_reason" ]] && [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description (reason=$actual_reason exit_code=$actual_exit_code script_exit=$actual_exit)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        expected: reason=$expected_reason exit_code=$expected_exit_code"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
    echo "        output:   $output"
  fi

  rm -rf "$state_dir"
}

# Happy path -> reason="ok", exit_code=0
assert_state_contains "happy path writes reason=ok" "ok" "0"

# Low disk -> reason="insufficient_disk_space"
assert_state_contains "low disk writes reason=insufficient_disk_space" \
  "insufficient_disk_space" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DF_LOW=1"

# Flock contention -> reason="lock_contention"
assert_state_contains "flock contention writes reason=lock_contention" \
  "lock_contention" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_FLOCK_CONTENDED=1"

# Docker pull failure -> reason=image_pull_failed (#6005). The pull is now against a
# PRIVATE package (M2 SPOF), so a denial is caught explicitly and a scrubbed, no-SSH
# pull_failure_event fires before aborting — replacing the legacy "unhandled" EXIT-trap
# fallthrough (the #2202 follow-up this comment anticipated).
assert_state_contains "docker pull fail writes reason=image_pull_failed (#6005)" \
  "image_pull_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_PULL_FAIL=1"

# Canary container run crash -> unhandled via set -e. Today's behavior: docker run
# failures for the canary container fall through to the EXIT trap as "unhandled"
# (no explicit canary_crashed handler). When the follow-up adds a canary_crashed
# reason, this assertion will fail and force a single-direction update.
assert_state_contains "canary container run crash writes reason=unhandled" \
  "unhandled" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_RUN_FAIL_CANARY=1"

# Canary health probe failure -> reason=canary_health_failed (per-layer reason
# taxonomy added in #3014 — replaces the legacy generic canary_failed reason).
assert_state_contains "canary health failure writes reason=canary_health_failed" \
  "canary_health_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_CANARY_FAIL=1"

# Per-layer canary failure reasons — each layer fails independently and writes
# its own reason for incident attribution.
assert_state_contains "canary /login 5xx writes reason=canary_login_failed" \
  "canary_login_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_LOGIN_5XX=1"

assert_state_contains "canary /dashboard 5xx writes reason=canary_dashboard_5xx" \
  "canary_dashboard_5xx" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_DASH_5XX=1"

assert_state_contains "canary error-boundary marker in body writes reason=canary_error_boundary" \
  "canary_error_boundary" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_CURL_DASH_ERROR_BODY=1"

assert_state_contains "canary Layer 3 JWT-claims failure writes reason=canary_layer3_jwt_claims" \
  "canary_layer3_jwt_claims" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_LAYER3_FAIL=1"

# -- Command parsing reason coverage (#2202) --
# These validations run BEFORE flock and Doppler resolution, so run_deploy_traced
# (with its generic docker/doppler mocks) exercises them correctly.

# Empty SSH_ORIGINAL_COMMAND -> reason=command_missing
assert_state_contains "empty command writes reason=command_missing" \
  "command_missing" "1" \
  ""

# Wrong field count (not 4) -> reason=command_malformed
assert_state_contains "malformed command writes reason=command_malformed" \
  "command_malformed" "1" \
  "deploy"

# Unknown action verb -> reason=action_unknown
assert_state_contains "unknown action writes reason=action_unknown" \
  "action_unknown" "1" \
  "notify web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# Unknown component -> reason=component_unknown
assert_state_contains "unknown component writes reason=component_unknown" \
  "component_unknown" "1" \
  "deploy unknown-app ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

# Wrong image for component -> reason=image_mismatch
assert_state_contains "wrong image writes reason=image_mismatch" \
  "image_mismatch" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-attacker-repo v1.0.0"

# Malformed semver tag -> reason=tag_malformed
assert_state_contains "bad tag writes reason=tag_malformed" \
  "tag_malformed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform latest"

# -- Doppler reason coverage (#2202) --
# Doppler reasons require run_deploy_doppler (restricted PATH + configurable doppler mock);
# pass it as the 6th arg to assert_state_contains.

# Doppler binary absent -> reason=doppler_unavailable
assert_state_contains "missing doppler binary writes reason=doppler_unavailable" \
  "doppler_unavailable" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOPPLER_MISSING=1" \
  "run_deploy_doppler"

# DOPPLER_TOKEN unset -> reason=doppler_token_missing
assert_state_contains "unset DOPPLER_TOKEN writes reason=doppler_token_missing" \
  "doppler_token_missing" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOPPLER_TOKEN_UNSET=1" \
  "run_deploy_doppler"

# Doppler secrets download fails -> reason=doppler_fetch_failed
assert_state_contains "doppler fetch failure writes reason=doppler_fetch_failed" \
  "doppler_fetch_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOPPLER_FAIL=1" \
  "run_deploy_doppler"

# -- Bwrap sandbox verification failure (#2202) --
# canary_sandbox_failed is written when `docker exec soleur-web-platform-canary bwrap ...`
# fails after the canary is running and healthy. Needs a custom docker mock that accepts
# `run` and curl-health-check but fails on `exec ... bwrap`.
assert_canary_sandbox_failed_state() {
  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"

  local output actual_exit
  output=$(
    export CI_DEPLOY_STATE="$state_file"
    export MOCK_DOCKER_MODE="bwrap-fail"
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: canary_sandbox_failed writes reason (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

  if [[ "$actual_reason" == "canary_sandbox_failed" ]] && [[ "$actual_exit_code" == "1" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: bwrap sandbox failure writes reason=canary_sandbox_failed"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: bwrap sandbox failure writes reason=canary_sandbox_failed"
    echo "        expected: reason=canary_sandbox_failed exit_code=1"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
    echo "        output:   $output"
  fi

  rm -rf "$state_dir"
}

assert_canary_sandbox_failed_state

# Production container start failure (after canary passes) -> reason=production_start_failed
assert_state_contains "production start failure writes reason=production_start_failed" \
  "production_start_failed" "1" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" \
  "export MOCK_DOCKER_RUN_FAIL_PROD=1"

# Note: no_handler is unreachable without modifying ci-deploy.sh (requires a
# component allowlisted in ALLOWED_IMAGES but missing from the case statement).
# Skipped per #2202 scope.

# Issue #2199 fix 1: initial "running" write must happen AFTER command parsing,
# so tag/component are populated (not empty strings).
# We snapshot the state file mid-deploy by making `df` (called after the initial
# "running" write) copy the live state file to a side location before returning.
assert_initial_running_has_tag() {
  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"
  local snapshot="$state_dir/running.snapshot"

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    # Redirect the plugin-seed bind-mount under MOCK_DIR so the seed block can
    # mkdir/find/cp/sentinel-write without needing /mnt/data on the runner.
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    # #5669: keep the cron-drain lease + state writes off /mnt/data and /var/run
    # on the runner unless the caller pinned them (drain tests do).
    if [[ -z "${CRON_DEPLOY_LEASE_FILE:-}" ]]; then
      export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    fi
    if [[ -z "${CRON_DRAIN_STATE_FILE:-}" ]]; then
      export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    fi
    export CI_DEPLOY_STATE="$state_file"
    export RUNNING_SNAPSHOT="$snapshot"
    create_base_mocks "$MOCK_DIR"

    # df runs immediately after the initial "running" write_state; snapshot state here.
    cat > "$MOCK_DIR/df" << 'MOCK'
#!/bin/bash
if [[ -n "${RUNNING_SNAPSHOT:-}" ]] && [[ -f "${CI_DEPLOY_STATE:-}" ]]; then
  cp "$CI_DEPLOY_STATE" "$RUNNING_SNAPSHOT"
fi
echo "Avail"
echo "20000000"
MOCK
    chmod +x "$MOCK_DIR/df"

    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ ! -f "$snapshot" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: initial running state snapshot was not captured"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  local snap_reason snap_exit snap_tag snap_component
  if command -v jq >/dev/null 2>&1; then
    snap_reason=$(jq -r '.reason // ""' "$snapshot" 2>/dev/null)
    snap_exit=$(jq -r '.exit_code // ""' "$snapshot" 2>/dev/null)
    snap_tag=$(jq -r '.tag // ""' "$snapshot" 2>/dev/null)
    snap_component=$(jq -r '.component // ""' "$snapshot" 2>/dev/null)
  else
    snap_reason=$(grep -oE '"reason":"[^"]*"' "$snapshot" | sed 's/.*:"\(.*\)"/\1/')
    snap_exit=$(grep -oE '"exit_code":-?[0-9]+' "$snapshot" | sed 's/.*://')
    snap_tag=$(grep -oE '"tag":"[^"]*"' "$snapshot" | sed 's/.*:"\(.*\)"/\1/')
    snap_component=$(grep -oE '"component":"[^"]*"' "$snapshot" | sed 's/.*:"\(.*\)"/\1/')
  fi

  if [[ "$snap_reason" == "running" ]] && [[ "$snap_exit" == "-1" ]] && \
     [[ "$snap_tag" == "v1.0.0" ]] && [[ "$snap_component" == "web-platform" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: initial running state has populated tag/component (tag=$snap_tag component=$snap_component)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: initial running state has populated tag/component"
    echo "        expected: reason=running exit_code=-1 tag=v1.0.0 component=web-platform"
    echo "        actual:   reason=$snap_reason exit_code=$snap_exit tag=$snap_tag component=$snap_component"
    echo "        snapshot: $(cat "$snapshot")"
  fi

  rm -rf "$state_dir"
}

assert_initial_running_has_tag

# Issue #2199 fix 3: a stale ${STATE_FILE}.final sentinel from a prior SIGKILLed
# run must not suppress the current run's failure reason. We pre-create the
# sentinel, trigger a known failure (low disk), and verify the explicit reason
# is still written (not silently dropped by the EXIT trap's "unhandled" guard).
assert_stale_sentinel_cleared() {
  TOTAL=$((TOTAL + 1))

  local state_dir
  state_dir=$(mktemp -d)
  local state_file="$state_dir/ci-deploy.state"
  # Pre-create the stale sentinel as if a prior run was SIGKILLed.
  touch "${state_file}.final"

  local output actual_exit
  output=$(
    export CI_DEPLOY_STATE="$state_file"
    export MOCK_DF_LOW=1
    run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local actual_reason actual_exit_code
  if [[ ! -f "$state_file" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: stale sentinel test (state file was never written)"
    echo "        output: $output"
    rm -rf "$state_dir"
    return
  fi

  read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

  if [[ "$actual_reason" == "insufficient_disk_space" ]] && [[ "$actual_exit_code" == "1" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: stale sentinel cleared; new run's explicit reason is preserved"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: stale sentinel cleared; new run's explicit reason is preserved"
    echo "        expected: reason=insufficient_disk_space exit_code=1"
    echo "        actual:   reason=$actual_reason exit_code=$actual_exit_code"
    echo "        state:    $(cat "$state_file")"
  fi

  rm -rf "$state_dir"
}

assert_stale_sentinel_cleared

# ADR-027 — pre-`docker run` single-replica assertion. When a leftover
# soleur-web-platform container is still running after docker stop|| rm
# masked a failure (|| true), the script must abort with a clear,
# ADR-027-referencing error rather than letting docker run produce a
# cryptic "name already in use".
echo ""
echo "--- ADR-027 pre-run single-replica assertion ---"

assert_adr027_pre_run_assertion() {
  TOTAL=$((TOTAL + 1))

  local output actual_exit
  output=$(
    export MOCK_DOCKER_MODE="trace"
    export MOCK_DOCKER_PS_PROD_RUNNING=1
    run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Three invariants must hold:
  # 1. Exit non-zero (assertion fired).
  # 2. Output names ADR-027 (operator can grep the doc).
  # 3. The production docker-run trace must NOT appear after the assertion —
  #    without this, a regression that fired the assertion but still ran the
  #    `docker run -d --name soleur-web-platform` would pass invariants 1&2
  #    while corrupting the deploy. The canary trace uses a -canary suffix and
  #    is permitted; the bare prod-name run is what we forbid.
  local prod_run_lines
  prod_run_lines=$(
    printf '%s\n' "$output" \
      | awk '/ADR-027/{found=1} found' \
      | grep -E 'DOCKER_TRACE:run' \
      | grep -vE -- '-canary' \
      || true
  )

  if [[ "$actual_exit" -ne 0 ]] \
    && printf '%s\n' "$output" | grep -qF "ADR-027" \
    && [[ -z "$prod_run_lines" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: leftover soleur-web-platform aborts deploy with ADR-027 message (no prod docker-run after abort)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: leftover soleur-web-platform aborts deploy with ADR-027 message"
    echo "        expected: non-zero exit AND output contains 'ADR-027' AND no prod 'docker run' after abort"
    echo "        actual exit: $actual_exit"
    echo "        prod_run_after_abort: $prod_run_lines"
    echo "        output: $output"
  fi
}

assert_adr027_pre_run_assertion

# SIGTERM trap (#3704). The trap pattern in ci-deploy.sh writes terminal
# state (exit_code=124 reason=timeout) when SIGTERM is delivered to the
# script's bash AND bash can run the trap. The latter holds when bash is
# between commands, in `wait`, or in shell logic — NOT during a hung
# foreground command (bash queues the trap until the foreground command
# returns). For the hung-foreground case, the wall-clock fallback is
# ci-deploy-wrapper.sh's `--kill-after=20s`, which sends SIGKILL after the
# 20s grace; the bash dies, no trap fires, the state stays at "running"
# until the workflow's pre-rerun probe sees `elapsed > 900s` and falls
# through (degraded-permissive). This is documented in the plan's Risks
# section.
#
# Two assertions:
#   1. STATIC: ci-deploy.sh has `set -m` AND the canonical TERM/INT trap.
#   2. RUNTIME: the trap pattern, exercised in an isolated reproduction
#      (bash script in `sleep & wait $!`), writes the expected state file
#      and exits 124. Covers the trap's correctness contract without
#      depending on ci-deploy.sh's specific code path.
echo ""
echo "--- SIGTERM trap (#3704) ---"

assert_ci_deploy_has_trap_installed() {
  TOTAL=$((TOTAL + 1))
  local found_set_m found_trap
  found_set_m=$(grep -cE '^set -m\b' "$DEPLOY_SCRIPT" || true)
  # Canonical trap shape: final_write_state 124 "timeout" followed by
  # pkill -P $$ and exit 124, bound to TERM/INT. We don't pin every
  # token (set -m vs trap order can shift), just the load-bearing parts.
  found_trap=$(grep -cE 'trap .*final_write_state 124 "timeout".*pkill -TERM -P .*TERM INT' "$DEPLOY_SCRIPT" || true)
  if [[ "$found_set_m" -ge 1 ]] && [[ "$found_trap" -ge 1 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: ci-deploy.sh has 'set -m' and the canonical TERM/INT trap installed"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: trap-install static check (set -m matches: $found_set_m, trap matches: $found_trap)"
  fi
}

assert_ci_deploy_has_trap_installed

assert_trap_writes_timeout_state_in_isolation() {
  TOTAL=$((TOTAL + 1))
  local verdict
  verdict=$(
    set +e
    local mock_dir state_file repro pid i
    mock_dir=$(mktemp -d)
    state_file="$mock_dir/state"
    repro="$mock_dir/repro.sh"

    # Minimal reproduction of ci-deploy.sh's trap setup. Uses `sleep & wait`
    # so the TERM trap fires immediately (vs. foreground `sleep` which would
    # defer until the sleep returns — the production limitation called out
    # above). The trap line MUST be byte-identical to ci-deploy.sh's.
    cat > "$repro" <<REPRO
#!/usr/bin/env bash
set -euo pipefail
set -m
STATE_FILE="$state_file"
START_TS=\$(date +%s)
COMPONENT="web-platform"
IMAGE="test"
TAG="v1.0.0"
write_state() {
  local tmp
  tmp=\$(mktemp "\$STATE_FILE.XXXXXX") || return 0
  printf '{"start_ts":%d,"end_ts":%d,"exit_code":%d,"component":"%s","image":"%s","tag":"%s","reason":"%s"}\n' \\
    "\$START_TS" "\$(date +%s)" "\$1" "\$COMPONENT" "\$IMAGE" "\$TAG" "\$2" > "\$tmp"
  mv "\$tmp" "\$STATE_FILE"
}
final_write_state() {
  touch "\$STATE_FILE.final" 2>/dev/null || true
  write_state "\$1" "\$2"
}
trap 'final_write_state 124 "timeout"; trap - TERM INT; pkill -TERM -P \$\$ 2>/dev/null || true; exit 124' TERM INT
sleep 30 &
wait \$!
REPRO
    chmod +x "$repro"

    "$repro" &
    pid=$!

    # Let the script enter `wait` (interruptible builtin).
    sleep 0.3

    kill -TERM "$pid" 2>/dev/null || true

    # Wait up to 5s for the script to exit.
    for i in $(seq 1 50); do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "FAIL: repro script did not exit within 5s after SIGTERM"
      rm -rf "$mock_dir"
      return 0
    fi
    wait "$pid" 2>/dev/null
    local exit_rc=$?

    # Verify state file
    if [[ ! -f "$state_file" ]]; then
      echo "FAIL: state file not written by trap (exit_rc=$exit_rc)"
      rm -rf "$mock_dir"
      return 0
    fi

    local actual_reason actual_exit_code
    read_state_reason_and_exit "$state_file" actual_reason actual_exit_code

    # Verify no orphan sleep child (pkill -P $$ should have killed it).
    local orphan
    orphan=$(pgrep -P "$pid" 2>/dev/null || true)
    if [[ -n "$orphan" ]]; then
      kill -KILL $orphan 2>/dev/null || true
      echo "FAIL: orphan child PIDs survived pkill -P (pids: $orphan)"
      rm -rf "$mock_dir"
      return 0
    fi

    if [[ "$actual_reason" == "timeout" ]] && [[ "$actual_exit_code" == "124" ]] && [[ "$exit_rc" -eq 124 ]]; then
      echo "PASS: trap writes exit_code=124 reason=timeout, repro exits 124, no orphan children"
      rm -rf "$mock_dir"
      return 0
    else
      echo "FAIL: state/exit mismatch (expected reason=timeout exit_code=124 rc=124; got reason=$actual_reason exit_code=$actual_exit_code rc=$exit_rc)"
      rm -rf "$mock_dir"
      return 0
    fi
  )

  if [[ "$verdict" == PASS:* ]]; then
    PASS=$((PASS + 1))
    echo "  $verdict"
  else
    FAIL=$((FAIL + 1))
    echo "  $verdict"
  fi
}

assert_trap_writes_timeout_state_in_isolation

# --- Restart action tests (#4538) ---
echo ""
echo "--- Restart action ---"

# AC1: restart inngest succeeds with healthy server + registered functions
assert_state_contains "restart inngest succeeds" \
  "success" "0" \
  "restart inngest _ latest"

# AC2: restart of non-inngest component rejected
assert_state_contains "restart web-platform rejected" \
  "component_not_restartable" "1" \
  "restart web-platform _ latest"

# AC5(a): systemctl restart failure
assert_state_contains "restart inngest systemctl failure" \
  "inngest_restart_failed" "1" \
  "restart inngest _ latest" \
  "export MOCK_SYSTEMCTL_FAIL=1"

# AC5(b): restart with inngest health check failure
assert_state_contains "restart inngest health failure" \
  "inngest_health_failed" "1" \
  "restart inngest _ latest" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1"

# #4650 AC9, reframed #5159: the cron-plan check is now ADVISORY. A server that
# is /health-healthy but whose cron triggers are de-planned (H9b) no longer FAILS
# the deploy — a standalone inngest restart de-plans crons until a web-platform
# redeploy (modified:true sync) or the --poll-interval self-heal re-arms them, so
# failing the deploy on a de-planned registry would be a false negative. The
# Sentry cron monitors are the real safety net for persistent de-plans. The
# default mock returns a cron-triggered function, so the AC1 "restart inngest
# succeeds" test above exercises the cron-present path; this exercises the
# cron-absent path now resolving to `success`.
assert_state_contains "restart inngest succeeds when cron plan de-planned (advisory, #5159)" \
  "success" "0" \
  "restart inngest _ latest" \
  "export MOCK_CURL_INNGEST_FUNCTIONS_NOCRON=1"

# #4652 AC3: the `deploy inngest` SUCCESS path must gate on verify_inngest_health
# (the restart action already does — see the four restart tests above; the
# deploy path did NOT before #4652). verify_inngest_health's runtime behavior
# (healthy → success, /health-fail → inngest_health_failed, cron-deplaned →
# inngest_health_failed) is execution-tested via those restart-action tests.
# Driving the deploy-inngest path to its success branch would need a new
# docker-inspect ENV mode + a sudo-bootstrap stub (the existing trace test stops
# at inngest_image_env_missing) — out of scope here; instead assert the WIRING:
# in the deploy-inngest branch verify_inngest_health runs BEFORE the success
# state-write, with an inngest_health_failed branch between them.
# ORDERING DEPENDENCY: the `tail -1` anchors below assume the `deploy inngest`
# case arm appears AFTER the `restart inngest` arm in ci-deploy.sh (so the last
# verify_inngest_health / last inngest_health_failed belong to the deploy arm).
# That holds today; if the case arms are reordered, re-anchor these greps to the
# deploy-inngest block (e.g. via awk between the arm's case label and `;;`).
TOTAL=$((TOTAL + 1))
DI_VERIFY_LINE=$(grep -nE '^[[:space:]]*verify_inngest_health[[:space:]]*$' "$DEPLOY_SCRIPT" | tail -1 | cut -d: -f1)
DI_SUCCESS_LINE=$(grep -nE 'SUCCESS: inngest .* deployed' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1)
DI_FAIL_LINE=$(grep -nE 'final_write_state 1 "inngest_health_failed"' "$DEPLOY_SCRIPT" | tail -1 | cut -d: -f1)
if [[ -n "$DI_VERIFY_LINE" && -n "$DI_SUCCESS_LINE" && -n "$DI_FAIL_LINE" \
      && "$DI_VERIFY_LINE" -lt "$DI_FAIL_LINE" && "$DI_FAIL_LINE" -lt "$DI_SUCCESS_LINE" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: deploy inngest success path gates on verify_inngest_health (#4652 AC3 wiring)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: deploy inngest verify_inngest_health wiring (verify=$DI_VERIFY_LINE fail=$DI_FAIL_LINE success=$DI_SUCCESS_LINE)"
fi

# Existing deploy validation still rejects `deploy inngest restart latest`
# (image mismatch since "restart" != expected image)
assert_state_contains "deploy inngest restart latest rejected as image_mismatch" \
  "image_mismatch" "1" \
  "deploy inngest restart latest"

# --- Quiesce / enable action tests (#6178 — no-SSH web-host scheduler quiesce) ---
echo ""
echo "--- Quiesce / enable action (#6178) ---"

# AC-Q1: quiesce inngest succeeds → not-serving (health fails) AND not-enabled (default
# is-enabled=disabled) → reason quiesced, exit 0. The verify is the gate.
assert_state_contains "quiesce inngest succeeds (not-serving + not-enabled)" \
  "quiesced" "0" \
  "quiesce inngest _ _" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1"

# AC-Q2: already-stopped idempotency — the sudo stop exits non-zero (absent/already-down)
# but is TOLERATED; the verify (health down, unit disabled) still declares quiesced.
assert_state_contains "quiesce tolerates an already-stopped/absent unit (stop non-zero)" \
  "quiesced" "0" \
  "quiesce inngest _ _" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1 MOCK_SYSTEMCTL_STOP_FAIL=1"

# AC-Q3: BENIGN disable tolerance — disable exits non-zero on a unit with NO [Install]
# section (is-enabled → static). Tolerated → quiesced, exit 0.
assert_state_contains "quiesce tolerates a benign disable non-zero (is-enabled=static)" \
  "quiesced" "0" \
  "quiesce inngest _ _" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1 MOCK_SYSTEMCTL_DISABLE_FAIL=1 MOCK_SYSTEMCTL_ENABLED_STATE=static"

# AC-Q4: GENUINE disable failure fail-closed (data-integrity P1-A) — disable fails AND
# is-enabled still reports `enabled` (a unit WITH an [Install] section) → the serving-only
# verify would MISS this; the enabled-state assertion catches it → inngest_still_enabled, exit 1.
assert_state_contains "quiesce fails closed when the unit stays enabled (inngest_still_enabled)" \
  "inngest_still_enabled" "1" \
  "quiesce inngest _ _" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1 MOCK_SYSTEMCTL_DISABLE_FAIL=1 MOCK_SYSTEMCTL_ENABLED_STATE=enabled"

# AC-Q5: still-serving fail-closed — the default mock serves /health 200 → the goal
# state (not-serving) is unmet → inngest_still_serving, exit 1.
assert_state_contains "quiesce fails closed when inngest still serves (inngest_still_serving)" \
  "inngest_still_serving" "1" \
  "quiesce inngest _ _"

# AC-Q6: unit still ACTIVE despite /health down (arch P2-3) — a scheduler executing
# queued jobs can outlive /health; the is-active assertion catches it → inngest_still_serving.
assert_state_contains "quiesce fails closed when /health is down but the unit is still active" \
  "inngest_still_serving" "1" \
  "quiesce inngest _ _" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1 MOCK_SYSTEMCTL_ACTIVE=1"

# AC-Q7: non-inngest component rejected (mirror component_not_restartable).
assert_state_contains "quiesce web-platform rejected (component_not_quiescible)" \
  "component_not_quiescible" "1" \
  "quiesce web-platform _ _"

# AC-E1: enable inngest = enable + start + verify-serving-and-enabled → enabled, exit 0.
# Default mock: /health 200 (serving); is-enabled=enabled (re-enable confirmed).
assert_state_contains "enable inngest succeeds (enable + start + verify serving+enabled)" \
  "enabled" "0" \
  "enable inngest _ _" \
  "export MOCK_SYSTEMCTL_ENABLED_STATE=enabled"

# AC-E2: enable is idempotent — an already-enabled unit (enable exits 0) still verifies → enabled.
assert_state_contains "enable is idempotent on an already-enabled unit" \
  "enabled" "0" \
  "enable inngest _ _" \
  "export MOCK_SYSTEMCTL_ENABLED_STATE=enabled"

# AC-E3: start failure fail-closed → inngest_start_failed, exit 1.
assert_state_contains "enable fails closed when start fails (inngest_start_failed)" \
  "inngest_start_failed" "1" \
  "enable inngest _ _" \
  "export MOCK_SYSTEMCTL_START_FAIL=1 MOCK_SYSTEMCTL_ENABLED_STATE=enabled"

# AC-E4: enable failure fail-closed → inngest_enable_failed, exit 1.
assert_state_contains "enable fails closed when enable fails (inngest_enable_failed)" \
  "inngest_enable_failed" "1" \
  "enable inngest _ _" \
  "export MOCK_SYSTEMCTL_ENABLE_FAIL=1"

# AC-E5: started but not serving (health fails) → inngest_reenable_unverified, exit 1.
assert_state_contains "enable fails closed when serving is unverified (inngest_reenable_unverified)" \
  "inngest_reenable_unverified" "1" \
  "enable inngest _ _" \
  "export MOCK_CURL_INNGEST_HEALTH_FAIL=1 MOCK_SYSTEMCTL_ENABLED_STATE=enabled"

# AC-E6: served but unit not enabled after enable (is-enabled=disabled) → inngest_reenable_unverified.
assert_state_contains "enable fails closed when the unit is not enabled afterward" \
  "inngest_reenable_unverified" "1" \
  "enable inngest _ _" \
  "export MOCK_SYSTEMCTL_ENABLED_STATE=disabled"

# AC-E7: non-inngest component rejected.
assert_state_contains "enable web-platform rejected (component_not_enableable)" \
  "component_not_enableable" "1" \
  "enable web-platform _ _"

# AC-Q8: PESSIMISTIC not-serving (all probes must fail) — a return-on-first-failure impl
# would falsely read quiesced. Bespoke: use a REAL multi-count seq (the shared mock returns
# only "1") so the verify loop runs >1 probe; health FAILS on probe 1 then SERVES on probe 2.
# The correct all-probes-must-fail impl continues past the probe-1 failure, sees the probe-2
# serve, and declares still-serving. A naive early-return-on-first-failure would wrongly
# declare quiesced after probe 1.
run_quiesce_pessimism() {
  (
    export SSH_ORIGINAL_COMMAND="quiesce inngest _ _"
    MOCK_DIR=$(mktemp -d); trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    export CI_DEPLOY_STATE="$1"
    create_base_mocks "$MOCK_DIR"
    rm -f "$MOCK_DIR/seq"   # use the REAL multi-count seq, not the single-"1" mock
    # Small probe budget so the real multi-iteration loop stays fast.
    export QUIESCE_PROBE_ATTEMPTS=3 QUIESCE_PROBE_INTERVAL=0
    # Health: fail on probe 1, serve on probe 2 (counter file).
    export MOCK_CURL_INNGEST_HEALTH_COUNTER="$MOCK_DIR/hcount"
    export MOCK_CURL_INNGEST_HEALTH_SERVE_ON="2"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    bash "$DEPLOY_SCRIPT" >/dev/null 2>&1
  )
}
TOTAL=$((TOTAL + 1))
PESS_STATE=$(mktemp)
# shellcheck disable=SC2034  # PESS_RC captured only to swallow expected non-zero under set -e; asserted via state file
run_quiesce_pessimism "$PESS_STATE" && PESS_RC=0 || PESS_RC=$?
read_state_reason_and_exit "$PESS_STATE" PESS_REASON PESS_EXIT
if [[ "$PESS_REASON" == "inngest_still_serving" && "$PESS_EXIT" == "1" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: quiesce verify is PESSIMISTIC (a serve on probe 2 blocks quiesced) — reason=$PESS_REASON"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: quiesce pessimism (expected inngest_still_serving/1; got $PESS_REASON/$PESS_EXIT)"
  echo "        state: $(cat "$PESS_STATE")"
fi
rm -f "$PESS_STATE"

# Wiring guard: `restart` STAYS PURE — it must NEVER fold in an enable/re-enable (a
# post-cutover restart-inngest-server.yml on a web host would otherwise re-arm the
# deliberately-disabled scheduler → double-fire; Premise #3 + security regression guard).
TOTAL=$((TOTAL + 1))
# Scope to the restart handler ONLY (it now precedes the quiesce/enable handlers, which
# legitimately DO enable/disable). Range: the restart handler comment → the quiesce handler comment.
RESTART_BLOCK=$(awk '/^# --- Restart action handler/,/^# --- Quiesce action handler/' "$DEPLOY_SCRIPT")
# Non-vacuity guard: if either marker comment is renamed the awk range is empty and the
# purity grep below passes for the WRONG reason. Prove the block was actually captured —
# non-empty AND containing the restart handler's own `systemctl restart` — before trusting
# the enable/disable-absence assertion.
TOTAL=$((TOTAL + 1))
if [[ -n "$RESTART_BLOCK" ]] && printf '%s\n' "$RESTART_BLOCK" | grep -qE 'systemctl restart'; then
  PASS=$((PASS + 1))
  echo "  PASS: restart-purity guard captured a non-empty block containing 'systemctl restart' (awk range not vacuous)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: restart-purity awk range captured empty/wrong block (marker renamed?) — the purity grep would pass vacuously"
fi
if ! printf '%s\n' "$RESTART_BLOCK" | grep -qE 'systemctl (enable|disable)'; then
  PASS=$((PASS + 1))
  echo "  PASS: restart handler stays pure (no enable/disable folded in) — #6178 regression guard"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: restart handler must NOT enable/disable inngest (re-arm footgun; Premise #3)"
fi

# Regression guard for #5062: the long-running foreground docker children
# (prune/pull) MUST close the FD-200 advisory lock (`200>&-`) so an orphaned
# child (bash SIGKILLed mid-`docker pull`, TERM trap never dispatched) cannot
# hold the flock past ci-deploy.sh's death and block all future deploys. A
# source-grep gate — a future edit that drops `200>&-` re-introduces the
# 40-min-stuck-lock class the v0.116.1 PIR documented.
TOTAL=$((TOTAL + 1))
# NB: #6122 wrapped BOTH pulls in pull_image_with_fallback (zot-primary + atomic GHCR
# fallback), so the pull is no longer a single literal `docker pull "$IMAGE:$TAG"`. The
# load-bearing INVARIANT is unchanged: EVERY real `docker pull` command must close
# FD-200. Assert the invariant (no pull command line lacks `200>&-`) rather than a brittle
# literal ref shape — matches command lines only (`docker pull`, `if docker pull`,
# `if ! docker pull`), so the `\`docker pull\`` mention inside verify's comment is
# excluded by the `^[[:space:]]*` anchor. A future edit dropping `200>&-` on any pull
# re-introduces the 40-min-stuck-lock class the v0.116.1 PIR documented.
_bad_pull="$(grep -nE '^[[:space:]]*(if (! )?)?docker pull ' "$DEPLOY_SCRIPT" | grep -v '200>&-' || true)"
if [[ -z "$_bad_pull" ]] \
   && grep -qE '^[[:space:]]*(if (! )?)?docker pull ' "$DEPLOY_SCRIPT" \
   && grep -qE '^[[:space:]]*docker image prune -af 200>&-' "$DEPLOY_SCRIPT"; then
  PASS=$((PASS + 1))
  echo "  PASS: long-running docker children close FD-200 lock (200>&-) — #5062 guard"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: docker pull/prune must close FD-200 via '200>&-' (#5062) — an orphaned pull would hold the deploy lock"
  [[ -n "$_bad_pull" ]] && echo "        pull line(s) missing 200>&-: $_bad_pull"
fi

echo ""
echo "--- #6122 zot-primary pull + atomic GHCR fallback + Edge B ---"

# Runs a web-platform deploy with zot CONFIGURED (MOCK_ZOT_CONFIGURED) and capture files
# for docker pull targets + cosign args. Echoes nothing; the caller greps the files.
run_deploy_zot() {
  local pull_file="$1" cosign_file="$2" extra="${3:-}"
  (
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d); trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    export MOCK_ZOT_CONFIGURED=1
    export MOCK_PULL_ARGS_FILE="$pull_file"
    export MOCK_COSIGN_ARGS_FILE="$cosign_file"
    eval "$extra"
    create_base_mocks "$MOCK_DIR"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" >/dev/null 2>&1 || true
  )
}

# T-ZOT-1: zot live + zot pull ok → the zot ref is pulled (never GHCR) and cosign verify
# carries --allow-insecure-registry (Edge B — plain-HTTP zot .sig fetch).
assert_zot_primary() {
  TOTAL=$((TOTAL + 1))
  local pf cf; pf=$(mktemp); cf=$(mktemp)
  run_deploy_zot "$pf" "$cf" ""
  if grep -q '^PULL:10.0.1.30:5000/jikig-ai/soleur-web-platform:v1.0.0$' "$pf" \
     && ! grep -q '^PULL:ghcr.io' "$pf" \
     && grep -q -- '--allow-insecure-registry' "$cf" \
     && grep -q -- '--trusted-root=/etc/cosign/trusted_root.json' "$cf" \
     && grep -q -- '--certificate-identity-regexp' "$cf"; then
    PASS=$((PASS + 1)); echo "  PASS: zot-primary pulls the zot ref + cosign --allow-insecure-registry + unchanged trust root/identity (Edge B, Phase 4)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: zot-primary (pulls=[$(tr '\n' ' ' < "$pf")] cosign_has_insecure=$(grep -qc -- '--allow-insecure-registry' "$cf" && echo y || echo n))"
  fi
  rm -f "$pf" "$cf"
}
assert_zot_primary

# T-ZOT-2: zot live + zot pull FAILS → ATOMIC fallback pulls GHCR; cosign follows the
# GHCR RepoDigest with NO insecure flag (image + auth + sig move together).
assert_zot_fallback() {
  TOTAL=$((TOTAL + 1))
  local pf cf; pf=$(mktemp); cf=$(mktemp)
  run_deploy_zot "$pf" "$cf" "export MOCK_ZOT_PULL_FAIL=1"
  if grep -q '^PULL:10.0.1.30:5000/jikig-ai/soleur-web-platform:v1.0.0$' "$pf" \
     && grep -q '^PULL:ghcr.io/jikig-ai/soleur-web-platform:v1.0.0$' "$pf" \
     && ! grep -q -- '--allow-insecure-registry' "$cf" \
     && grep -q -- '--trusted-root=/etc/cosign/trusted_root.json' "$cf" \
     && grep -q -- '--certificate-identity-regexp' "$cf"; then
    PASS=$((PASS + 1)); echo "  PASS: zot pull failure → atomic GHCR fallback, no insecure flag, unchanged trust root/identity (Phase 4)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: zot fallback (pulls=[$(tr '\n' ' ' < "$pf")])"
  fi
  rm -f "$pf" "$cf"
}
assert_zot_fallback

# T-ZOT-3: zot DARK (default, unconfigured) → single GHCR pull, zot never attempted
# (strict no-op — the merge-time dark state until the operator provisions + backfills).
assert_zot_dark() {
  TOTAL=$((TOTAL + 1))
  local pf; pf=$(mktemp)
  (
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d); trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    export MOCK_PULL_ARGS_FILE="$pf"
    create_base_mocks "$MOCK_DIR"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" >/dev/null 2>&1 || true
  )
  if grep -q '^PULL:ghcr.io/jikig-ai/soleur-web-platform:v1.0.0$' "$pf" \
     && ! grep -q '^PULL:10.0.1.30:5000' "$pf"; then
    PASS=$((PASS + 1)); echo "  PASS: zot dark (unconfigured) → single GHCR pull, zot never attempted"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: zot dark (pulls=[$(tr '\n' ' ' < "$pf")])"
  fi
  rm -f "$pf"
}
assert_zot_dark

# --- #6122 Phase 4: cosign continuity (trust anchor unchanged) ---
# The zot migration must NOT alter the cosign trust anchor (ADR-096 G3 / task 4.2). Assert
# the pinned cosign image SHA (v3.1.1), the offline trusted-root flag, and the reusable-
# release identity regexp are still present verbatim — only --allow-insecure-registry is
# CONDITIONALLY added on the zot branch (proven by T-ZOT-1/T-ZOT-2 above, which also assert
# the trusted-root + identity flags ride BOTH the zot and the GHCR-fallback branch = 4.1).
TOTAL=$((TOTAL + 1))
if grep -qF 'ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870' "$DEPLOY_SCRIPT" \
   && grep -qF 'verify --offline' "$DEPLOY_SCRIPT" \
   && grep -qF -- '--trusted-root=/etc/cosign/trusted_root.json' "$DEPLOY_SCRIPT" \
   && grep -qF 'reusable-release' "$DEPLOY_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: cosign trust anchor unchanged (pinned v3.1.1 SHA + offline trusted-root + identity regexp) — Phase 4 continuity"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: cosign trust anchor drifted (Phase 4 continuity)"
fi

# #5145 / reframed #5159: the cron-plan loop owns its own (advisory) budget,
# distinct from the /health loop. Post-#5159 the cron-plan check is best-effort
# (crons re-arm async via redeploy or --poll-interval), so the budget is the
# narrower cron_max_attempts=10 rather than the old 40.
# Budget VALUES are runtime-untestable here: create_mock_seq collapses every
# loop to one iteration (that mock is what keeps this suite inside
# infra-validation.yml's 5-min job timeout — do not weaken it), so these are
# static source pins. Regression classes guarded:
#   - shared-budget collapse (cron loop reverting to $max_attempts)
#   - loop swap (the cron budget driving the FIRST loop instead of the second)
#   - curl-tail retune (--max-time 5 is the source of the drift guard's +5
#     term below; retuning it silently invalidates that arithmetic)
# The `seq` FORM pin is itself load-bearing: a C-style for ((...)) refactor
# would escape the seq mock and blow the 5-min CI timeout.
echo ""
echo "--- verify_inngest_health cron-plan budget (#5145) ---"
TOTAL=$((TOTAL + 1))
CRON_PIN_COUNT=$(grep -cE '^[[:space:]]*local cron_max_attempts=10\b' "$DEPLOY_SCRIPT" || true)
CRON_SEQ_COUNT=$(grep -cE 'seq 1 "\$cron_max_attempts"' "$DEPLOY_SCRIPT" || true)
HEALTH_SEQ_LINE=$(grep -nE 'seq 1 "\$max_attempts"' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1 || true)
CRON_SEQ_LINE=$(grep -nE 'seq 1 "\$cron_max_attempts"' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1 || true)
FUNCTIONS_CURL_LINE=$(grep -nE 'curl -sf --max-time 5 .*http://127\.0\.0\.1:8288/v0/gql' "$DEPLOY_SCRIPT" | head -1 | cut -d: -f1 || true)
# Probe pin scoped to the function region — a third `curl -sf --max-time 5`
# exists outside verify_inngest_health (the deploy-arm web-platform health
# probe), so a file-global count would be wrong.
VERIFY_FN_MAXTIME=$(awk '/^verify_inngest_health\(\) \{/,/^\}/' "$DEPLOY_SCRIPT" | grep -c 'curl -sf --max-time 5' || true)
if [[ "$CRON_PIN_COUNT" -eq 1 && "$CRON_SEQ_COUNT" -eq 1 \
      && -n "$HEALTH_SEQ_LINE" && -n "$CRON_SEQ_LINE" && -n "$FUNCTIONS_CURL_LINE" \
      && "$HEALTH_SEQ_LINE" -lt "$CRON_SEQ_LINE" && "$CRON_SEQ_LINE" -lt "$FUNCTIONS_CURL_LINE" \
      && "$VERIFY_FN_MAXTIME" -eq 2 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: cron-plan loop owns its pinned budget (cron_max_attempts=10 drives the second loop; both probes --max-time 5) — #5145"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: cron-budget pin (#5145) (pin=$CRON_PIN_COUNT seq_form=$CRON_SEQ_COUNT health_seq_line=$HEALTH_SEQ_LINE cron_seq_line=$CRON_SEQ_LINE functions_curl_line=$FUNCTIONS_CURL_LINE fn_maxtime=$VERIFY_FN_MAXTIME)"
fi

# #5145 cross-file drift guard: the restart workflow's client-side poll window
# must exceed ci-deploy.sh's server-side verify worst case, or the workflow
# times out on exactly the slow-resync case the wider budget tolerates.
# Values are extracted generically BY SHAPE (not pinned literals) so a
# legitimate retune re-runs the inequality with the new numbers instead of
# dying as "unparseable" — exact-value pinning is the assertion above's job.
# Server worst case (right side of the inequality):
#   (health_attempts + cron_attempts) * (interval + 5)
#     +5 = per-attempt `curl --max-time 5` tail (source: the --max-time pin
#          above; sleep-only arithmetic undercounts the true worst case ~2.6x)
#   +stop = TimeoutStopSec hung-stop budget the systemd restart can consume
#          BEFORE the verify starts — extracted by shape from the
#          inngest-server unit heredoc in inngest-bootstrap.sh (scoped: a
#          second TimeoutStopSec=30 exists in the vector unit)
#   +60  = webhook handoff/flock/client-curl margin
# Same invariant class as web-platform-release.yml's STATUS_POLL ==
# IN_FLIGHT_CEILING_S runtime assert.
TOTAL=$((TOTAL + 1))
RESTART_WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/restart-inngest-server.yml"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/inngest-bootstrap.sh"
# tail -1 on the digit runs: "${1:-10}" tokenizes to "1" then "10" — the
# DEFAULT is the last run, not the first.
DG_HEALTH=$(grep -oE '\$\{1:-[0-9]+\}' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' | tail -1 || true)
DG_INTERVAL=$(grep -oE '\$\{2:-[0-9]+\}' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' | tail -1 || true)
DG_CRON=$(grep -oE '^[[:space:]]*local cron_max_attempts=[0-9]+' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' || true)
DG_INNGEST_UNIT=$(awk '/Description=Inngest self-hosted server/,/^UNITEOF$/' "$BOOTSTRAP_SCRIPT")
DG_STOP=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -oE '^TimeoutStopSec=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
DG_MAX_POLLS=$(grep -oE 'MAX_POLLS=[0-9]+' "$RESTART_WORKFLOW" | head -1 | grep -oE '[0-9]+' || true)
DG_POLL_INTERVAL=$(grep -oE 'POLL_INTERVAL=[0-9]+' "$RESTART_WORKFLOW" | head -1 | grep -oE '[0-9]+' || true)
# Exactly-one assignment per extraction shape — a duplicate (or zero) match
# makes the head -1 extraction silently ambiguous (e.g. a future helper
# earlier in ci-deploy.sh with its own ${1:-N} default would hijack
# DG_HEALTH and shrink the inequality's right side without failing).
DG_HEALTH_COUNT=$(grep -cE '\$\{1:-[0-9]+\}' "$DEPLOY_SCRIPT" || true)
DG_INTERVAL_COUNT=$(grep -cE '\$\{2:-[0-9]+\}' "$DEPLOY_SCRIPT" || true)
DG_CRON_COUNT=$(grep -cE '^[[:space:]]*local cron_max_attempts=[0-9]+' "$DEPLOY_SCRIPT" || true)
DG_STOP_COUNT=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -cE '^TimeoutStopSec=[0-9]+' || true)
DG_MAX_POLLS_COUNT=$(grep -cE 'MAX_POLLS=[0-9]+' "$RESTART_WORKFLOW" || true)
DG_POLL_INTERVAL_COUNT=$(grep -cE 'POLL_INTERVAL=[0-9]+' "$RESTART_WORKFLOW" || true)
DG_OK=1
DG_WHY=""
# Validate BEFORE arithmetic: bash $((v * 5)) on an empty string evaluates to
# 0 silently and the inequality would pass for the wrong reason.
for pair in "health:$DG_HEALTH" "interval:$DG_INTERVAL" "cron:$DG_CRON" "stop:$DG_STOP" "max_polls:$DG_MAX_POLLS" "poll_interval:$DG_POLL_INTERVAL"; do
  if ! [[ "${pair#*:}" =~ ^[0-9]+$ ]]; then
    DG_OK=0
    DG_WHY="non-integer extraction: ${pair%%:*}"
  fi
done
for pair in "health:$DG_HEALTH_COUNT" "interval:$DG_INTERVAL_COUNT" "cron:$DG_CRON_COUNT" "stop:$DG_STOP_COUNT" "max_polls:$DG_MAX_POLLS_COUNT" "poll_interval:$DG_POLL_INTERVAL_COUNT"; do
  if [[ "$DG_OK" -eq 1 && "${pair#*:}" -ne 1 ]]; then
    DG_OK=0
    DG_WHY="expected exactly one assignment match for ${pair%%:*} (got ${pair#*:})"
  fi
done
DG_LEFT=""
DG_RIGHT=""
if [[ "$DG_OK" -eq 1 ]]; then
  DG_LEFT=$((DG_MAX_POLLS * DG_POLL_INTERVAL))
  DG_RIGHT=$(((DG_HEALTH + DG_CRON) * (DG_INTERVAL + 5) + DG_STOP + 60))
  if [[ "$DG_LEFT" -lt "$DG_RIGHT" ]]; then
    DG_OK=0
    DG_WHY="client window ${DG_LEFT}s < server worst case ${DG_RIGHT}s"
  fi
fi
if [[ "$DG_OK" -eq 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: restart workflow client window (${DG_LEFT}s) covers verify worst case (${DG_RIGHT}s) — #5145 drift guard"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: client/server budget drift guard (#5145): $DG_WHY (health=$DG_HEALTH interval=$DG_INTERVAL cron=$DG_CRON stop=$DG_STOP MAX_POLLS=$DG_MAX_POLLS POLL_INTERVAL=$DG_POLL_INTERVAL left=$DG_LEFT right=$DG_RIGHT; files: ci-deploy.sh, inngest-bootstrap.sh, .github/workflows/restart-inngest-server.yml)"
fi

# #6178 quiesce-web poll drift guard (sibling of the #5145 restart guard): the
# op=quiesce-web deploy-status poll window in cutover-inngest.yml must cover the host-side
# quiesce worst case: verify_inngest_quiesced attempts × (interval + 5 per-probe curl tail)
# + TimeoutStopSec (the systemd stop the webhook fires asynchronously can consume before the
# host writes `quiesced`) + a webhook/flock/client-curl margin. Extracted BY SHAPE (not
# pinned literals) — the distinct QMAX_POLLS/QPOLL_INTERVAL names in the quiesce-web arm keep
# this grep unambiguous vs the other polls in that workflow.
TOTAL=$((TOTAL + 1))
CUTOVER_WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/cutover-inngest.yml"
QDG_ATTEMPTS=$(grep -oE 'QUIESCE_PROBE_ATTEMPTS:-[0-9]+' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' || true)
QDG_INTERVAL=$(grep -oE 'QUIESCE_PROBE_INTERVAL:-[0-9]+' "$DEPLOY_SCRIPT" | head -1 | grep -oE '[0-9]+' || true)
QDG_STOP=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -oE '^TimeoutStopSec=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
QDG_MAX_POLLS=$(grep -oE 'QMAX_POLLS=[0-9]+' "$CUTOVER_WORKFLOW" | head -1 | grep -oE '[0-9]+' || true)
QDG_POLL_INTERVAL=$(grep -oE 'QPOLL_INTERVAL=[0-9]+' "$CUTOVER_WORKFLOW" | head -1 | grep -oE '[0-9]+' || true)
# Exactly-one-assignment guards so a duplicate/zero match can't silently skew the inequality.
QDG_ATTEMPTS_COUNT=$(grep -cE 'QUIESCE_PROBE_ATTEMPTS:-[0-9]+' "$DEPLOY_SCRIPT" || true)
QDG_INTERVAL_COUNT=$(grep -cE 'QUIESCE_PROBE_INTERVAL:-[0-9]+' "$DEPLOY_SCRIPT" || true)
QDG_MAX_POLLS_COUNT=$(grep -cE 'QMAX_POLLS=[0-9]+' "$CUTOVER_WORKFLOW" || true)
QDG_POLL_INTERVAL_COUNT=$(grep -cE 'QPOLL_INTERVAL=[0-9]+' "$CUTOVER_WORKFLOW" || true)
QDG_STOP_COUNT=$(printf '%s\n' "$DG_INNGEST_UNIT" | grep -cE '^TimeoutStopSec=[0-9]+' || true)
QDG_OK=1
QDG_WHY=""
for pair in "attempts:$QDG_ATTEMPTS" "interval:$QDG_INTERVAL" "stop:$QDG_STOP" "qmax:$QDG_MAX_POLLS" "qint:$QDG_POLL_INTERVAL"; do
  if ! [[ "${pair#*:}" =~ ^[0-9]+$ ]]; then QDG_OK=0; QDG_WHY="non-integer extraction: ${pair%%:*}"; fi
done
for pair in "attempts:$QDG_ATTEMPTS_COUNT" "interval:$QDG_INTERVAL_COUNT" "stop:$QDG_STOP_COUNT" "qmax:$QDG_MAX_POLLS_COUNT" "qint:$QDG_POLL_INTERVAL_COUNT"; do
  if [[ "$QDG_OK" -eq 1 && "${pair#*:}" -ne 1 ]]; then QDG_OK=0; QDG_WHY="expected exactly one match for ${pair%%:*} (got ${pair#*:})"; fi
done
QDG_LEFT=""; QDG_RIGHT=""
if [[ "$QDG_OK" -eq 1 ]]; then
  QDG_LEFT=$((QDG_MAX_POLLS * QDG_POLL_INTERVAL))
  QDG_RIGHT=$((QDG_ATTEMPTS * (QDG_INTERVAL + 5) + QDG_STOP + 60))
  if [[ "$QDG_LEFT" -lt "$QDG_RIGHT" ]]; then QDG_OK=0; QDG_WHY="quiesce-web poll window ${QDG_LEFT}s < host worst case ${QDG_RIGHT}s"; fi
fi
if [[ "$QDG_OK" -eq 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: op=quiesce-web poll window (${QDG_LEFT}s) covers host quiesce worst case (${QDG_RIGHT}s) — #6178 drift guard"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: quiesce-web poll drift guard (#6178): $QDG_WHY (attempts=$QDG_ATTEMPTS interval=$QDG_INTERVAL stop=$QDG_STOP QMAX_POLLS=$QDG_MAX_POLLS QPOLL_INTERVAL=$QDG_POLL_INTERVAL; files: ci-deploy.sh, inngest-bootstrap.sh, .github/workflows/cutover-inngest.yml)"
fi

echo ""
echo "--- Container memory caps (#5417 AC3) ---"

# Both docker-run blocks (canary --restart no, prod --restart unless-stopped)
# must carry --memory + --memory-swap + --init so a heavy-cron memory spike
# becomes a deterministic cgroup-OOM of the container instead of an arbitrary
# HOST-OOM victim. Source-grep gate (the AC3 verification shape): mutating any
# flag out of ci-deploy.sh fails this. Counts assert BOTH sites are covered.
TOTAL=$((TOTAL + 1))
MEM_FLAG_COUNT=$(grep -cE -- '--memory "\$(PROD|CANARY)_MEMORY_CAP"' "$DEPLOY_SCRIPT" || true)
SWAP_FLAG_COUNT=$(grep -cE -- '--memory-swap "\$(PROD|CANARY)_MEMORY_CAP"' "$DEPLOY_SCRIPT" || true)
INIT_FLAG_COUNT=$(grep -cE -- '^[[:space:]]+--init \\' "$DEPLOY_SCRIPT" || true)
# Both docker runs pass a COMPOSED NODE_OPTIONS (Doppler value + our cap appended
# so -e does not clobber an operator-set value — #5417 review). Assert both
# call-sites use the composed var AND that each composed var sets the heap cap.
NODE_OPT_COUNT=$(grep -cE -- '-e NODE_OPTIONS="\$(PROD|CANARY)_NODE_OPTIONS"' "$DEPLOY_SCRIPT" || true)
NODE_OPT_COMPOSE_COUNT=$(grep -cE -- '^[[:space:]]+(PROD|CANARY)_NODE_OPTIONS=.*--max-old-space-size=\$(PROD|CANARY)_NODE_MAX_OLD_SPACE_MB' "$DEPLOY_SCRIPT" || true)
CAP_CONST_COUNT=$(grep -cE '^readonly (PROD_MEMORY_CAP|CANARY_MEMORY_CAP|PROD_NODE_MAX_OLD_SPACE_MB|CANARY_NODE_MAX_OLD_SPACE_MB)=' "$DEPLOY_SCRIPT" || true)
if [[ "$MEM_FLAG_COUNT" -eq 2 && "$SWAP_FLAG_COUNT" -eq 2 && "$INIT_FLAG_COUNT" -eq 2 \
   && "$NODE_OPT_COUNT" -eq 2 && "$NODE_OPT_COMPOSE_COUNT" -eq 2 && "$CAP_CONST_COUNT" -eq 4 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: prod+canary docker run carry --memory/--memory-swap/--init from named caps; both set --max-old-space-size (appended to any Doppler NODE_OPTIONS) below the cap (#5417 AC1/AC3)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: memory-cap source gate (mem=$MEM_FLAG_COUNT/2 swap=$SWAP_FLAG_COUNT/2 init=$INIT_FLAG_COUNT/2 node_opt=$NODE_OPT_COUNT/2 compose=$NODE_OPT_COMPOSE_COUNT/2 consts=$CAP_CONST_COUNT/4; file: ci-deploy.sh)"
fi

echo ""
echo "--- #5547 Gap 1: existing-host deploy stages the durable Redis assets ---"
# The existing-host deploy path runs inngest-bootstrap.sh DIRECTLY on the host
# (the Alpine extract container has no systemctl), bypassing the OCI image
# ENTRYPOINT that stages /tmp/inngest-redis.* on the fresh-host cloud-init path.
# So ci-deploy.sh's `case "inngest")` MUST docker-cp the three Redis assets to
# the /tmp staging path itself, or inngest-bootstrap.sh's Redis-install guard
# (`[[ -f /tmp/inngest-redis.conf && ... ]]`) is always false → Redis never
# installed → the durable ExecStart crash-loops (#5547 Gap 1).
# Per-asset line-start greps (NOT a `grep -c >= 3`, which a WHY-comment naming
# inngest-redis would inflate — AC1).
TOTAL=$((TOTAL + 1))
G1_CONF=$(grep -cE '^[[:space:]]*docker cp .*inngest-redis\.conf' "$DEPLOY_SCRIPT" || true)
G1_SERVICE=$(grep -cE '^[[:space:]]*docker cp .*inngest-redis\.service' "$DEPLOY_SCRIPT" || true)
G1_BOOTSTRAP=$(grep -cE '^[[:space:]]*docker cp .*inngest-redis-bootstrap\.sh' "$DEPLOY_SCRIPT" || true)
if [[ "$G1_CONF" -ge 1 && "$G1_SERVICE" -ge 1 && "$G1_BOOTSTRAP" -ge 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: ci-deploy.sh stages inngest-redis.{conf,service} + inngest-redis-bootstrap.sh to /tmp (#5547 Gap 1 / AC1)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ci-deploy.sh must docker cp all three Redis assets in case inngest (conf=$G1_CONF service=$G1_SERVICE bootstrap=$G1_BOOTSTRAP; file: ci-deploy.sh / #5547 AC1)"
fi

echo ""
echo "--- #5547 Gap 3: verify_inngest_health degraded advisory + success_degraded_durability ---"
# Source-scoped (runtime-driving the deploy path is out of scope per the #4652
# AC3 wiring comment above). AC5 — verify_inngest_health emits a degraded
# ADVISORY (NOT return 1) via `logger -t "$LOG_TAG"` when the ExecStart lacks the
# durable sentinel (the SQLite-only fail-safe), while the durable FAIL branch
# (inngest-redis not active) still `return 1`. #5560: the "--redis-uri absent" FAIL
# branch was REMOVED — the postgres/redis URIs are env-delivered now, so the only
# durable-failure signal on argv is the sentinel + the redis-service-active check.
VIH_FN=$(awk '/^verify_inngest_health\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")
VIH_ADVISORY=$(printf '%s\n' "$VIH_FN" | grep -cE 'logger -t "\$LOG_TAG" "INNGEST_DURABLE: advisory' || true)
VIH_FAIL_NOT_ACTIVE=$(printf '%s\n' "$VIH_FN" | grep -cE 'INNGEST_DURABLE: FAIL .*not active' || true)
VIH_SENTINEL=$(printf '%s\n' "$VIH_FN" | grep -cF -- '--postgres-max-open-conns' || true)
# Negative: the removed --redis-uri-absent FAIL branch must NOT reappear (it would
# be dead code — redis-uri is never on argv after #5560).
VIH_FAIL_NO_REDIS=$(printf '%s\n' "$VIH_FN" | grep -cE 'INNGEST_DURABLE: FAIL .*--redis-uri absent' || true)
TOTAL=$((TOTAL + 1))
if [[ "$VIH_ADVISORY" -ge 1 && "$VIH_FAIL_NOT_ACTIVE" -ge 1 && "$VIH_SENTINEL" -ge 1 && "$VIH_FAIL_NO_REDIS" -eq 0 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: verify_inngest_health emits degraded advisory + redis-not-active FAIL, keys on --postgres-max-open-conns sentinel, no dead --redis-uri-absent branch (#5547 AC5 / #5560)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AC5 (advisory=$VIH_ADVISORY fail_not_active=$VIH_FAIL_NOT_ACTIVE sentinel=$VIH_SENTINEL dead_redis_branch=$VIH_FAIL_NO_REDIS; verify_inngest_health in ci-deploy.sh)"
fi

# AC5b — on a 0-exit bootstrap that left inngest on the SQLite-only ExecStart,
# the case "inngest") block writes final_write_state 0 "success_degraded_durability"
# (NOT plain "success") so /hooks/deploy-status .reason distinguishes a degraded
# deploy from a healthy durable one. Detection re-derives from the WRITTEN
# ExecStart via a case-local `inngest_exec_start=` (verify_inngest_health uses a
# `local exec_start=`, so this name is unique to the deploy arm).
G3_REASON=$(grep -cE 'final_write_state 0 "success_degraded_durability"' "$DEPLOY_SCRIPT" || true)
G3_DETECT=$(grep -cE 'inngest_exec_start=' "$DEPLOY_SCRIPT" || true)
TOTAL=$((TOTAL + 1))
if [[ "$G3_REASON" -ge 1 && "$G3_DETECT" -ge 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: case inngest writes success_degraded_durability on a degraded 0-exit deploy (#5547 AC5b)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AC5b (degraded_reason=$G3_REASON detect=$G3_DETECT; file: ci-deploy.sh)"
fi

echo ""
echo "--- Cron drain (#5669 / ADR-078) ---"

# This section drives real (mocked) deploys whose runners return non-zero on the
# negative paths (L2) and uses grep|head extractions that SIGPIPE under
# `set -o pipefail`; turn errexit/pipefail off for the section (each test below
# reports PASS/FAIL explicitly, so errexit adds no safety here).
set +e +o pipefail

# T6 (AC4c memory-dwell): inside the swap success branch the canary is
# stopped+removed BEFORE the `while cron_in_flight` drain loop, so the up-to-70min
# drain wait does not hold the 1536m canary resident on the 8GB host. Source-order
# assertion scoped to the swap block (the stale-canary cleanup in the canary-start
# block far above is a false match otherwise).
TOTAL=$((TOTAL + 1))
# `f &&` guards the exit rule so the same literal in the top-of-file comment does
# not terminate awk before the swap section begins.
SWAP_BLOCK=$(awk '/SUCCESS: swap canary to production/{f=1} f{print} f && /docker stop --time=12 soleur-web-platform/{exit}' "$DEPLOY_SCRIPT")
T6_CANARY=$(printf '%s\n' "$SWAP_BLOCK" | grep -nE 'docker stop soleur-web-platform-canary' | head -1 | cut -d: -f1)
T6_DRAIN=$(printf '%s\n' "$SWAP_BLOCK" | grep -nE 'while cron_in_flight' | head -1 | cut -d: -f1)
if [[ -n "$T6_CANARY" && -n "$T6_DRAIN" && "$T6_CANARY" -lt "$T6_DRAIN" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T6 canary torn down before the drain loop in the swap branch (memory-dwell fix)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T6 canary-before-drain ordering (canary=$T6_CANARY drain=$T6_DRAIN; file: ci-deploy.sh)"
fi

# T7 (AC4d probe own timeout): cron_in_flight wraps the pool-agnostic detection
# probe in its own `timeout "${CRON_DRAIN_PROBE_TIMEOUT}"` so a hung docker exec
# cannot extend the drain past the wall-clock (G5).
TOTAL=$((TOTAL + 1))
T7_FN=$(awk '/^cron_in_flight\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$DEPLOY_SCRIPT")
if printf '%s' "$T7_FN" | grep -qF 'timeout "${CRON_DRAIN_PROBE_TIMEOUT}"' \
   && printf '%s' "$T7_FN" | grep -qF 'pgrep -f "claude"'; then
  PASS=$((PASS + 1))
  echo "  PASS: T7 cron_in_flight is pool-agnostic (pgrep -f claude) with its own probe timeout"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T7 cron_in_flight probe shape (file: ci-deploy.sh)"
fi

# T9 (AC1): CRON_DRAIN_TIMEOUT default ≥ MAX per-function maxTurnDurationMs, so
# the longest cron (cron-growth-audit, 70min) survives the drain rather than being
# killed by the timeout. Re-derives the max from the actual function source — a
# future cron raising its ceiling above the drain default fails this gate.
TOTAL=$((TOTAL + 1))
FN_DIR="$(dirname "$DEPLOY_SCRIPT")/../server/inngest/functions"
T9_MAX_MIN=$(grep -rhoE 'MAX_TURN_DURATION_MS = [0-9]+ \* 60 \* 1000' "$FN_DIR" 2>/dev/null \
  | grep -oE '= [0-9]+ \*' | grep -oE '[0-9]+' | sort -n | tail -1)
T9_DRAIN_DEFAULT=$(grep -oE 'CRON_DRAIN_TIMEOUT:-[0-9]+' "$DEPLOY_SCRIPT" | grep -oE '[0-9]+$')
if [[ -n "$T9_MAX_MIN" && -n "$T9_DRAIN_DEFAULT" && "$T9_DRAIN_DEFAULT" -ge $(( T9_MAX_MIN * 60 )) ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T9 CRON_DRAIN_TIMEOUT default ${T9_DRAIN_DEFAULT}s ≥ max per-function ceiling ${T9_MAX_MIN}min ($(( T9_MAX_MIN * 60 ))s)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T9 drain default ${T9_DRAIN_DEFAULT}s < max ceiling ${T9_MAX_MIN}min (raise CRON_DRAIN_TIMEOUT)"
fi

# T-PARITY (#5669 cross-language drift guard): the lease basename is replicated in
# bash (ci-deploy.sh CRON_DEPLOY_LEASE_FILE default path) AND TypeScript
# (_cron-shared.ts DEPLOY_LEASE_BASENAME). The host writes the file and the
# container substrate reads it; a silent divergence reopens the start-race while
# both sides' own tests stay green. Assert they agree.
TOTAL=$((TOTAL + 1))
PARITY_SHARED="$(dirname "$DEPLOY_SCRIPT")/../server/inngest/functions/_cron-shared.ts"
BASH_LEASE_BASENAME=$(grep -oE 'CRON_DEPLOY_LEASE_FILE:-[^}]+' "$DEPLOY_SCRIPT" | sed -E 's#.*/##')
TS_LEASE_BASENAME=$(grep -oE 'DEPLOY_LEASE_BASENAME = "[^"]+"' "$PARITY_SHARED" | sed -E 's/.*"([^"]+)"/\1/')
if [[ -n "$BASH_LEASE_BASENAME" && "$BASH_LEASE_BASENAME" == "$TS_LEASE_BASENAME" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T-PARITY lease basename agrees across bash + TS ('$BASH_LEASE_BASENAME')"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T-PARITY lease basename drift (ci-deploy.sh='$BASH_LEASE_BASENAME' vs _cron-shared.ts='$TS_LEASE_BASENAME')"
fi

# T-WALLCLOCK (pattern review): the wrapper / IN_FLIGHT_CEILING_S wall-clock must
# stay >= CRON_DRAIN_TIMEOUT + overhead, else the wrapper SIGKILLs ci-deploy.sh
# mid-drain (killing the very cron the drain protects). T9 ties CRON_DRAIN_TIMEOUT
# UP to the cron ceiling; this ties it UNDER the wall-clock — so a future ceiling
# raise that lifts the drain default can't silently exceed the wrapper budget while
# T6/T9/wrapper-Test-6 all stay green.
TOTAL=$((TOTAL + 1))
WC_YML="$(dirname "$DEPLOY_SCRIPT")/../../../.github/workflows/web-platform-release.yml"
WC_CEILING=$(grep -oE 'IN_FLIGHT_CEILING_S:[[:space:]]*[0-9]+' "$WC_YML" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
WC_DRAIN=$(grep -oE 'CRON_DRAIN_TIMEOUT:-[0-9]+' "$DEPLOY_SCRIPT" | grep -oE '[0-9]+$')
WC_MARGIN=300
if [[ -n "$WC_CEILING" && -n "$WC_DRAIN" && $(( WC_CEILING - WC_DRAIN )) -ge "$WC_MARGIN" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T-WALLCLOCK IN_FLIGHT_CEILING_S ${WC_CEILING}s − CRON_DRAIN_TIMEOUT ${WC_DRAIN}s ≥ ${WC_MARGIN}s overhead"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T-WALLCLOCK wall-clock ${WC_CEILING}s − drain ${WC_DRAIN}s < ${WC_MARGIN}s margin (wrapper would SIGKILL mid-drain)"
fi

# T-LEASE-ORDER (test-design review): the lease MUST be written BEFORE the drain
# loop and the prod stop — that ordering is what closes the start-race (a new run
# launching claude into the about-to-die container while the loop drains). Source
# order: lease write < `while cron_in_flight` < `docker stop --time=12`.
TOTAL=$((TOTAL + 1))
LO_BLOCK=$(awk '/SUCCESS: swap canary to production/{f=1} f{print} f && /docker stop --time=12 soleur-web-platform/{exit}' "$DEPLOY_SCRIPT")
LO_LEASE=$(printf '%s\n' "$LO_BLOCK" | grep -nE ': > "\$CRON_DEPLOY_LEASE_FILE"' | head -1 | cut -d: -f1)
LO_DRAIN=$(printf '%s\n' "$LO_BLOCK" | grep -nE 'while cron_in_flight' | head -1 | cut -d: -f1)
if [[ -n "$LO_LEASE" && -n "$LO_DRAIN" && "$LO_LEASE" -lt "$LO_DRAIN" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T-LEASE-ORDER lease written (L$LO_LEASE) before drain loop (L$LO_DRAIN) — start-race closed"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T-LEASE-ORDER lease-write/drain ordering (lease=$LO_LEASE drain=$LO_DRAIN)"
fi

# T1 (AC1): with a cron in flight for N polls then gone, the drain loops until the
# probe goes false (counter drains to 0), does NOT time out, and clears the lease
# on success.
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
echo 3 > "$DTMP/inflight"
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" \
  MOCK_CRON_INFLIGHT_FILE="$DTMP/inflight" CRON_DRAIN_POLL=0
T1_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && T1_RC=0 || T1_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE MOCK_CRON_INFLIGHT_FILE CRON_DRAIN_POLL
T1_TIMED=$(jq -r '.cron_drain_timed_out' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
T1_LEFT=$(cat "$DTMP/inflight" 2>/dev/null || echo "MISSING")
T1_LEASE=$([[ -f "$DTMP/lease" ]] && echo yes || echo no)
if [[ "$T1_RC" -eq 0 && "$T1_TIMED" == "false" && "$T1_LEFT" == "0" && "$T1_LEASE" == "no" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T1 drain waited for in-flight cron (counter→0), no timeout, lease cleared on success"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T1 (rc=$T1_RC timed_out=$T1_TIMED inflight_left=$T1_LEFT lease_present=$T1_LEASE)"
fi
rm -rf "$DTMP"

# T3 (AC3 no-cron fast path): no claude in flight → zero-wait drain, immediate
# stop, no timeout, lease cleared.
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" CRON_DRAIN_POLL=0
T3_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && T3_RC=0 || T3_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE CRON_DRAIN_POLL
T3_TIMED=$(jq -r '.cron_drain_timed_out' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
T3_WAIT=$(jq -r '.cron_drain_wait_secs' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
# `^[0-9]+$` already excludes the never-reached -1 sentinel (no minus sign); the
# `-le 2` upper bound pins the no-cron FAST path (a single false probe, 0–1s of
# wall-clock tick) and excludes any real multi-second drain — without asserting a
# brittle exact 0 (the single docker-exec probe can cross a 1s boundary).
if [[ "$T3_RC" -eq 0 && "$T3_TIMED" == "false" && "$T3_WAIT" =~ ^[0-9]+$ && "$T3_WAIT" -le 2 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T3 no-cron deploy: zero-wait drain (${T3_WAIT}s), no timeout"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T3 (rc=$T3_RC timed_out=$T3_TIMED wait=$T3_WAIT)"
fi
rm -rf "$DTMP"

# T2 (AC2 bounded, not infinite): a cron that never finishes is killed once the
# drain passes CRON_DRAIN_TIMEOUT — the state records cron_drain_timed_out=true and
# the deploy still proceeds (a drain timeout must NOT fail the deploy under set -e).
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
echo 99 > "$DTMP/inflight"
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" \
  MOCK_CRON_INFLIGHT_FILE="$DTMP/inflight" CRON_DRAIN_TIMEOUT=0 CRON_DRAIN_POLL=0
T2_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && T2_RC=0 || T2_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE MOCK_CRON_INFLIGHT_FILE CRON_DRAIN_TIMEOUT CRON_DRAIN_POLL
T2_TIMED=$(jq -r '.cron_drain_timed_out' "$DTMP/state.json" 2>/dev/null || echo "MISSING")
if [[ "$T2_RC" -eq 0 && "$T2_TIMED" == "true" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: T2 drain timeout sets cron_drain_timed_out=true and does not fail the deploy"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: T2 (rc=$T2_RC timed_out=$T2_TIMED)"
fi
rm -rf "$DTMP"

# L2 (lease lifecycle): on a FAILED swap (new prod run fails), the lease is NOT
# cleared — it is left for the substrate's TTL fail-open backstop (CTO guardrail
# 2). Proves the lease was written (exists) and that clear is gated on swap
# success (T1 proves the success-clear).
TOTAL=$((TOTAL + 1))
DTMP=$(mktemp -d)
export CRON_DEPLOY_LEASE_FILE="$DTMP/lease" CRON_DRAIN_STATE_FILE="$DTMP/state.json" \
  CRON_DRAIN_POLL=0 MOCK_DOCKER_RUN_FAIL_PROD=1
L2_OUT=$(run_deploy_traced "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0" 2>&1) && L2_RC=0 || L2_RC=$?
unset CRON_DEPLOY_LEASE_FILE CRON_DRAIN_STATE_FILE CRON_DRAIN_POLL MOCK_DOCKER_RUN_FAIL_PROD
L2_LEASE=$([[ -f "$DTMP/lease" ]] && echo yes || echo no)
if [[ "$L2_RC" -ne 0 && "$L2_LEASE" == "yes" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: L2 lease written + retained on swap failure (TTL backstop, not cleared)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: L2 (rc=$L2_RC lease_present=$L2_LEASE; expected nonzero rc + lease retained)"
fi
rm -rf "$DTMP"

# --- §1A (#6090 recurrence): ghcr_prelude re-fetches Doppler creds + retries docker
# login on a baked-login FAILURE, not only when the baked value is EMPTY. Root cause of
# web-2's fsn1 warm-standby not serving (2026-07-13): the fresh host's baked GHCR read
# token in /etc/default/soleur-ghcr-read went STALE by deploy time; the EMPTY-only guard
# never re-fetched the valid current Doppler cred → `docker login` failed (non-fatal) →
# anonymous private pull → Sentry `image pull failed (auth_denied)` → image_pull_failed.
# Faithful repro: a PRESENT-but-stale baked token whose login 401s; the fix must retry
# with the Doppler cred (mock-GHCR_READ_USER). Under the pre-fix EMPTY-only code only ONE
# login (the stale baked one) is attempted → this asserts the SECOND (Doppler) login.
echo "--- §1A: baked-login failure → Doppler re-fetch + retry ---"
S1A_DIR=$(mktemp -d)
printf 'GHCR_READ_USER=baked-stale-user\nGHCR_READ_TOKEN=STALE_BAKED_TOKEN\n' > "$S1A_DIR/soleur-ghcr-read"
export SOLEUR_GHCR_READ_FILE="$S1A_DIR/soleur-ghcr-read"
export MOCK_GHCR_LOGIN_FAIL_TOKEN="STALE_BAKED_TOKEN"
export MOCK_LOGIN_ARGS_FILE="$S1A_DIR/logins.txt"
: > "$MOCK_LOGIN_ARGS_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 || true
TOTAL=$((TOTAL + 1))
if grep -q '^LOGIN:baked-stale-user$' "$MOCK_LOGIN_ARGS_FILE" \
   && grep -q '^LOGIN:mock-GHCR_READ_USER$' "$MOCK_LOGIN_ARGS_FILE"; then
  PASS=$((PASS + 1))
  echo "  PASS: baked-login failure triggers Doppler re-fetch + retry (stale baked login, then Doppler login)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: expected a Doppler re-fetch + retry login (LOGIN:mock-GHCR_READ_USER) after the stale baked login failed"
  echo "        logins captured:"; sed 's/^/          /' "$MOCK_LOGIN_ARGS_FILE"
fi
unset SOLEUR_GHCR_READ_FILE MOCK_GHCR_LOGIN_FAIL_TOKEN MOCK_LOGIN_ARGS_FILE
rm -rf "$S1A_DIR"

# --- #6400: recover at the GHCR PULL site on a login-ok/pull-deny credential ---
# Root cause: §1A recovers only on a docker LOGIN failure, but the production
# `image pull failed (auth_denied)` fires one step later at `docker pull` — a
# credential that logs in but cannot pull (a GitHub App token, or a revoked baked
# snapshot) bypasses §1A entirely. These assert the pull-site recovery in
# _ghcr_pull_or_recover: re-fetch the prd cred + relogin + retry the pull ONCE.

echo "--- #6400 AC1: GHCR login-ok/pull-deny → re-fetch + retry → recovered ---"
T6400=$(mktemp -d)
echo 1 > "$T6400/deny-count"   # first GHCR pull denies, retry (after relogin) succeeds
export MOCK_GHCR_PULL_DENY_COUNT_FILE="$T6400/deny-count"
export MOCK_PULL_ARGS_FILE="$T6400/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6400/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 || true
TOTAL=$((TOTAL + 1))
AC1_GHCR_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$AC1_GHCR_PULLS" -eq 2 ]] \
   && grep -q 'image pull recovered' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'image pull failed' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: recovered — 2 GHCR pulls (deny+retry), recovery event, no failure event"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC1 (ghcr_pulls=$AC1_GHCR_PULLS; expected 2 + recovery event, no failure event)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_DENY_COUNT_FILE MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6400"

echo "--- #6400 AC2: relogin ok but retry pull still denies → fail-open, pull_still_denied ---"
T6400=$(mktemp -d)
export MOCK_GHCR_PULL_DENY_ALWAYS=1   # both pulls deny (recovery miss)
export MOCK_PULL_ARGS_FILE="$T6400/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6400/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 && AC2_RC=0 || AC2_RC=$?
TOTAL=$((TOTAL + 1))
AC2_GHCR_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$AC2_RC" -ne 0 ]] && [[ "$AC2_GHCR_PULLS" -eq 2 ]] \
   && grep -q 'image pull failed' "$MOCK_SENTRY_CAPTURE_FILE" \
   && grep -q 'pull_still_denied' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'image pull recovered' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: fail-open — rc=$AC2_RC, 2 GHCR pulls, single failure event tagged pull_still_denied, no recovery event"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC2 (rc=$AC2_RC ghcr_pulls=$AC2_GHCR_PULLS; expected nonzero + 2 pulls + pull_still_denied)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_DENY_ALWAYS MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6400"

echo "--- #6400 AC14: relogin FAILS → retry pull NOT attempted (guards §1A dt='' return-0 bug) ---"
T6400=$(mktemp -d)
export MOCK_GHCR_PULL_DENY_ALWAYS=1
export MOCK_GHCR_LOGIN_FAIL_TOKEN="mock-GHCR_READ_TOKEN"   # the re-fetched prd token also fails login
export MOCK_PULL_ARGS_FILE="$T6400/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6400/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 || true
TOTAL=$((TOTAL + 1))
AC14_GHCR_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$AC14_GHCR_PULLS" -eq 1 ]] \
   && grep -q 'relogin_failed' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'image pull recovered' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: relogin failure → exactly 1 GHCR pull (no retry), failure tagged relogin_failed"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC14 (ghcr_pulls=$AC14_GHCR_PULLS; expected 1 + relogin_failed, no recovery)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_DENY_ALWAYS MOCK_GHCR_LOGIN_FAIL_TOKEN MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6400"

echo "--- #6400 AC4: recovery is GHCR-cred-scoped — does NOT fire on the zot leg ---"
T6400=$(mktemp -d)
export MOCK_ZOT_CONFIGURED=1 MOCK_ZOT_PULL_FAIL=1   # zot active, zot pull fails → atomic GHCR fallback
export MOCK_PULL_ARGS_FILE="$T6400/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6400/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 || true
TOTAL=$((TOTAL + 1))
# zot pull attempted (and failed) + GHCR fallback pulled once + NO recovery fired (GHCR
# cred was fine); the zot denial itself never triggers a GHCR re-fetch.
if grep -q '^PULL:10.0.1.30:5000/' "$MOCK_PULL_ARGS_FILE" \
   && grep -q '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" \
   && ! grep -q 'image pull recovered' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: zot-fail → GHCR fallback (unchanged); recovery did not fire on the zot leg"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC4"; echo "        pulls:"; sed 's/^/          /' "$MOCK_PULL_ARGS_FILE"
fi
unset MOCK_ZOT_CONFIGURED MOCK_ZOT_PULL_FAIL MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6400"

echo "--- #6400 AC3/AC6/AC13: single classifier, content-not-path, token hygiene, cosign continuity ---"
# AC3: ONE auth-denied regex, shared by the classifier + the recovery gate.
TOTAL=$((TOTAL + 1))
REGEX_COUNT=$(grep -cE 'unauthorized\|authentication required\|denied\|forbidden' "$DEPLOY_SCRIPT")
# _ghcr_pull_or_recover classifies stderr CONTENT (tail -c 400 "$perr"), not the path.
if [[ "$REGEX_COUNT" -eq 1 ]] \
   && grep -qE '_pull_result_is_auth_denied "\$\(tail -c 400 "\$perr"' "$DEPLOY_SCRIPT" \
   && grep -q 'pull_failure_event .* "\${RECOVERY_STAGE:-}"' "$DEPLOY_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: single regex; recovery gate classifies content; recovery_stage threaded to pull_failure_event"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC3 (regex_count=$REGEX_COUNT — expected 1 + content-classify + recovery_stage arg)"
fi
# AC6: token hygiene — the token reaches docker login via --password-stdin only, never argv;
# token is local + unset; recovery event payload is jq -n --arg with no raw stderr.
#
# #6497 moved the `docker login` INVOCATION out of this helper and into the shared
# _docker_login_capture (the three login sites now share one captured invocation, for the same
# reason they share one classifier: two drift). So the assertion follows the token to its new
# home rather than being deleted: the helper must hand the token to the capture helper and must
# never put it on a docker argv, and the CAPTURE helper is now where --password-stdin lives.
TOTAL=$((TOTAL + 1))
HELPER_BODY=$(awk '/^refetch_ghcr_and_relogin\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")
CAPTURE_BODY=$(awk '/^_docker_login_capture\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")
RECOV_BODY=$(awk '/^pull_auth_recovery_event\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")
if printf '%s' "$CAPTURE_BODY" | grep -q -- '--password-stdin' \
   && printf '%s' "$CAPTURE_BODY" | grep -qE 'printf .*"\$_tok" \| docker login' \
   && ! printf '%s' "$CAPTURE_BODY" | grep -qE 'docker login[^|]*\$_tok' \
   && printf '%s' "$HELPER_BODY" | grep -q 'local du="" dt=""' \
   && printf '%s' "$HELPER_BODY" | grep -qE '_docker_login_capture ghcr\.io "\$du" "\$dt"' \
   && ! printf '%s' "$HELPER_BODY" | grep -qE 'docker login[^|]*\$dt' \
   && printf '%s' "$RECOV_BODY" | grep -q 'jq -n --arg' \
   && ! printf '%s' "$RECOV_BODY" | grep -qE 'detail_raw|tail -c 400|\$perr'; then
  PASS=$((PASS + 1)); echo "  PASS: token via --password-stdin + local; recovery payload jq -n --arg, no raw stderr"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC6 token/stderr hygiene"
fi
# AC13: cosign continuity — the recovery relogin targets ghcr.io (the registry the
# cosign :ro $GHCR_DOCKER_CONFIG authenticates), so a recovered pull does not 401 the .sig.
#
# ANCHORED ON THE INVOCATION, not on the bare string `docker login ghcr.io`. #6497 added a
# `logger` line to this helper whose MESSAGE contains that exact substring — which left this
# assertion VACUOUSLY GREEN: it passed while matching a log string, with the property it exists
# to guard (the relogin actually targets ghcr.io) no longer verified by it. That is the same
# defect class this file has now shipped five times: a static assertion anchored on a bare token
# that a comment — or a log message — can also satisfy. Anchor on the call shape.
TOTAL=$((TOTAL + 1))
if printf '%s' "$HELPER_BODY" | grep -qE '_docker_login_capture ghcr\.io "\$du" "\$dt"'; then
  PASS=$((PASS + 1)); echo "  PASS: recovery relogin writes ghcr.io auth into the same \$GHCR_DOCKER_CONFIG (cosign continuity)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: AC13 — recovery relogin must target ghcr.io"
fi

# --- #6525: widen the GHCR retry beyond auth-denied to cover TRANSIENT/network stderr ----
# Root cause: _ghcr_pull_or_recover retried a failed GHCR pull ONLY when the stderr was
# auth-classified (_pull_result_is_auth_denied). A transient first-attempt failure (timeout,
# connection reset, EOF, no-such-host, ...) took the return-1 path with ZERO retries — the
# observed v0.216.1/.2 "first attempt fails, rerun succeeds" shape. The fix adds a shared
# _pull_result_is_transient predicate + a bounded, capped backoff loop; the both-registries
# fail-closed semantics and the entire #6400 auth-recovery branch stay byte-identical.

# T-6525-1..2: _pull_result_is_transient classifies the fleet's real transient stderr as
# transient (return 0) and does NOT swallow the higher-precedence auth/manifest classes
# (return non-zero). Sources the real predicate body (pure grep|printf, no deps — like
# _login_kw/_login_tok at T-5B-16) rather than re-running the deploy per fixture.
echo "--- #6525 T-6525-1..2: _pull_result_is_transient classifier (positive + negative) ---"
TOTAL=$((TOTAL + 1))
PT_BODY="$(awk '/^_pull_result_is_transient\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
PT_LIB=$(mktemp)
printf '%s\n' "$PT_BODY" > "$PT_LIB"
# shellcheck disable=SC1090
source "$PT_LIB" 2>/dev/null || true
# Positive fixtures — the fleet-real transient shapes (mirror :3555-3600) plus the deepen
# docker-stderr research additions (context deadline exceeded / registry 5xx / net-http
# client-timeout / DNS server-misbehaving).
PT_POS=(
  'read tcp 10.0.1.10:44444->140.82.112.34:443: read: connection reset by peer'
  'Get "https://ghcr.io/v2/": dial tcp 140.82.112.34:443: connect: network is unreachable'
  'Get "https://ghcr.io/v2/": EOF'
  'dial tcp: lookup ghcr.io: no such host'
  'dial tcp 140.82.112.34:443: connect: connection refused'
  'Get "https://ghcr.io/v2/": net/http: TLS handshake timeout'
  'Get "https://ghcr.io/v2/": read: i/o timeout'
  'temporary failure in name resolution'
  'Get "https://ghcr.io/v2/": context deadline exceeded'
  'received unexpected HTTP status: 503 Service Unavailable'
  'Get "https://ghcr.io/v2/": request canceled while waiting for connection'
  'dial tcp: lookup ghcr.io on 10.0.0.1:53: server misbehaving'
)
# Negative fixtures — auth (higher precedence, owned by _pull_result_is_auth_denied) and
# manifest (note `no such manifest` shares the `no such` prefix with the transient
# `no such host` — the predicate must anchor on the full token and NOT match manifest).
PT_NEG=(
  'denied: requested access to the resource is denied'
  'manifest unknown: manifest unknown'
  'manifest for ghcr.io/x:v1 not found: no such manifest'
)
PT_BAD=""
if ! declare -F _pull_result_is_transient >/dev/null; then
  FAIL=$((FAIL + 1)); echo "  FAIL: could not source _pull_result_is_transient (fixture error / function absent)"
else
  for _s in "${PT_POS[@]}"; do
    if ! _pull_result_is_transient "$_s"; then PT_BAD+=$'\n'"    positive NOT matched: $_s"; fi
  done
  for _s in "${PT_NEG[@]}"; do
    if _pull_result_is_transient "$_s"; then PT_BAD+=$'\n'"    negative WRONGLY matched: $_s"; fi
  done
  if [[ -z "$PT_BAD" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: all ${#PT_POS[@]} transient shapes matched; all ${#PT_NEG[@]} auth/manifest shapes rejected"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: classifier mismatch:$PT_BAD"
  fi
fi
rm -f "$PT_LIB"

# T-6525-3: transient retry RECOVERS — count=1 (first pull transient, retry succeeds),
# PULL_TRANSIENT_RETRY_SLEEPS="0 0" (no real sleep): 2 GHCR pulls, a transient_recovered
# breadcrumb (op:image-pull-recovery), NO pull_failure_event, overall success.
echo "--- #6525 T-6525-3: transient retry RECOVERS (count=1 → 2 pulls, transient_recovered) ---"
T6525=$(mktemp -d)
echo 1 > "$T6525/transient-count"
export MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE="$T6525/transient-count"
export PULL_TRANSIENT_RETRY_SLEEPS="0 0"
export MOCK_PULL_ARGS_FILE="$T6525/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6525/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 || true
TOTAL=$((TOTAL + 1))
T3_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$T3_PULLS" -eq 2 ]] \
   && grep -q 'image pull recovered (transient_recovered)' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'image pull failed' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: transient recovered — 2 GHCR pulls (blip+retry), transient_recovered event, no failure event"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: T-6525-3 (ghcr_pulls=$T3_PULLS; expected 2 + transient_recovered, no failure event)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE PULL_TRANSIENT_RETRY_SLEEPS MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6525"

# T-6525-4: transient retry EXHAUSTS — transient on every pull, PULL_TRANSIENT_RETRY_SLEEPS="0 0"
# (max=2): exactly 3 GHCR pulls (1 + 2 retries), pull_failure_event with pull_result=network
# AND recovery_stage=transient_exhausted, overall FAILURE (old container stays live — fail-closed),
# NO recovery event.
echo "--- #6525 T-6525-4: transient retry EXHAUSTS (3 pulls, network/transient_exhausted, fail-closed) ---"
T6525=$(mktemp -d)
export MOCK_GHCR_PULL_TRANSIENT_ALWAYS=1
export PULL_TRANSIENT_RETRY_SLEEPS="0 0"
export MOCK_PULL_ARGS_FILE="$T6525/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6525/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 && T4_RC=0 || T4_RC=$?
TOTAL=$((TOTAL + 1))
T4_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$T4_RC" -ne 0 ]] && [[ "$T4_PULLS" -eq 3 ]] \
   && grep -q 'image pull failed (network)' "$MOCK_SENTRY_CAPTURE_FILE" \
   && grep -q 'transient_exhausted' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'image pull recovered' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: exhausted — rc=$T4_RC, 3 GHCR pulls (1+2 retries), failure tagged network/transient_exhausted, no recovery"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: T-6525-4 (rc=$T4_RC ghcr_pulls=$T4_PULLS; expected nonzero + 3 pulls + network + transient_exhausted)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_TRANSIENT_ALWAYS PULL_TRANSIENT_RETRY_SLEEPS MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6525"

# T-6525-5: manifest/unknown stderr → exactly 1 GHCR pull (NO retry), pull_result=manifest_unknown,
# empty recovery_stage. Regression guard: we did NOT widen retries to the manifest class.
echo "--- #6525 T-6525-5: manifest stderr → exactly 1 pull, no retry (regression guard) ---"
T6525=$(mktemp -d)
export MOCK_GHCR_PULL_MANIFEST_ALWAYS=1
export PULL_TRANSIENT_RETRY_SLEEPS="0 0"
export MOCK_PULL_ARGS_FILE="$T6525/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6525/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 && T5_RC=0 || T5_RC=$?
TOTAL=$((TOTAL + 1))
T5_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$T5_RC" -ne 0 ]] && [[ "$T5_PULLS" -eq 1 ]] \
   && grep -q 'image pull failed (manifest_unknown)' "$MOCK_SENTRY_CAPTURE_FILE" \
   && grep -q '"recovery_stage": *""' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'transient_exhausted' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: manifest → 1 GHCR pull (no retry), manifest_unknown, empty recovery_stage"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: T-6525-5 (rc=$T5_RC ghcr_pulls=$T5_PULLS; expected nonzero + 1 pull + manifest_unknown + empty recovery_stage)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_MANIFEST_ALWAYS PULL_TRANSIENT_RETRY_SLEEPS MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6525"

# T-6525-6 (deepen GAP-7): a transient blip FOLLOWED BY a manifest failure — arm transient
# once, then manifest on the retry: exactly 2 GHCR pulls, terminal pull_result=manifest_unknown,
# and recovery_stage EMPTY (NOT transient_exhausted — the retries were not spent AND the
# terminal cause is manifest). Guards against polluting the transient_exhausted Sentry
# discriminator with manifest tails.
echo "--- #6525 T-6525-6 (GAP-7): transient→manifest tail → 2 pulls, manifest_unknown, empty recovery_stage ---"
T6525=$(mktemp -d)
echo 1 > "$T6525/transient-count"
export MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE="$T6525/transient-count"
export MOCK_GHCR_PULL_MANIFEST_ALWAYS=1
export PULL_TRANSIENT_RETRY_SLEEPS="0 0"
export MOCK_PULL_ARGS_FILE="$T6525/pulls.txt";  : > "$MOCK_PULL_ARGS_FILE"
export MOCK_SENTRY_CAPTURE_FILE="$T6525/sentry.txt"; : > "$MOCK_SENTRY_CAPTURE_FILE"
run_deploy "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v9.9.9" >/dev/null 2>&1 && T6_RC=0 || T6_RC=$?
TOTAL=$((TOTAL + 1))
T6_PULLS=$(grep -c '^PULL:ghcr.io/' "$MOCK_PULL_ARGS_FILE" 2>/dev/null || true)
if [[ "$T6_RC" -ne 0 ]] && [[ "$T6_PULLS" -eq 2 ]] \
   && grep -q 'image pull failed (manifest_unknown)' "$MOCK_SENTRY_CAPTURE_FILE" \
   && grep -q '"recovery_stage": *""' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'transient_exhausted' "$MOCK_SENTRY_CAPTURE_FILE" \
   && ! grep -q 'image pull recovered' "$MOCK_SENTRY_CAPTURE_FILE"; then
  PASS=$((PASS + 1)); echo "  PASS: transient→manifest tail — 2 pulls, manifest_unknown, empty recovery_stage (discriminator not polluted)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: T-6525-6 (rc=$T6_RC ghcr_pulls=$T6_PULLS; expected nonzero + 2 pulls + manifest_unknown + empty recovery_stage, no transient_exhausted/recovery)"
  echo "        sentry:"; sed 's/^/          /' "$MOCK_SENTRY_CAPTURE_FILE"
fi
unset MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE MOCK_GHCR_PULL_MANIFEST_ALWAYS PULL_TRANSIENT_RETRY_SLEEPS MOCK_PULL_ARGS_FILE MOCK_SENTRY_CAPTURE_FILE
rm -rf "$T6525"

# T-6525-7: single-source-of-truth wiring — _pull_result_is_transient is defined exactly ONCE,
# pull_failure_event's network arm CALLS it (not a second inline regex), mirroring the
# _pull_result_is_auth_denied shared-predicate guard at AC3 (:3419-3427). Anchored on the
# call shape + a distinctive regex token that must live ONLY in the predicate, per the file's
# own "anchor on the construct, not a bare token" discipline.
echo "--- #6525 T-6525-7: pull_failure_event network arm calls the shared _pull_result_is_transient ---"
TOTAL=$((TOTAL + 1))
# Anchored on the CALL shape + the DEFINITION, never a bare regex token a comment could also carry
# (the file's own "anchor on syntax, not a bare token" discipline). Three checks: (a) the predicate
# is defined exactly once; (b) pull_failure_event's body CALLS it; (c) pull_failure_event's body no
# longer carries the pre-#6525 inline network regex `timeout|timed out|temporary failure|...` — so
# the classification was REWIRED to the shared predicate, not duplicated (single source of truth).
TRANSIENT_DEF_COUNT=$(grep -cE '^_pull_result_is_transient\(\) \{' "$DEPLOY_SCRIPT")
PFE_BODY="$(awk '/^pull_failure_event\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
if [[ "$TRANSIENT_DEF_COUNT" -eq 1 ]] \
   && printf '%s' "$PFE_BODY" | grep -qE '_pull_result_is_transient "\$detail_raw"' \
   && ! printf '%s' "$PFE_BODY" | grep -qE "grep -qiE '[^']*timed out\|temporary failure\|no route"; then
  PASS=$((PASS + 1)); echo "  PASS: single _pull_result_is_transient definition; pull_failure_event calls the shared predicate (no inline network regex)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: T-6525-7 (transient_def=$TRANSIENT_DEF_COUNT; expected exactly 1 def + shared-predicate call + no inline network regex in pull_failure_event)"
fi

# --- #6497: zot login failure is DISCRIMINATING (WEB-PLATFORM-5B) -----------------------
# The gate discarded `docker login` stderr (`>/dev/null 2>&1`), so `login_failed` was one
# undifferentiated bucket for bad-credential / authz-denial / transport / TLS. These assert
# the stderr CONTENT classifies into a fixed enum, that 401 and 403 land in DIFFERENT
# buckets (the H3-vs-H4 discriminator this exists to provide), and that raw stderr never
# reaches the Sentry payload.

# Arms a zot-configured deploy whose ZOT login fails with a caller-supplied stderr, and
# captures the Sentry POST bodies. Echoes nothing; the caller greps the capture file.
# $3 (optional): a journald capture file. Armed only by the purity test — every other caller
# leaves it empty so the logger mock keeps its historic discard-everything behavior.
# $4 (optional): the login's STDOUT (#6497 H-B-stdout). $5 (optional): extra `VAR=value` env
# entries, space-separated, for the abort-injection + docker-absent legs.
run_deploy_zot_login_stderr() {
  local sentry_file="$1" zot_stderr="$2" logger_file="${3:-}" zot_stdout="${4:-}" extra_env="${5:-}"
  (
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d); trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    export MOCK_ZOT_CONFIGURED=1
    export MOCK_ZOT_LOGIN_FAIL_STDERR="$zot_stderr"
    [[ -n "$zot_stdout" ]] && export MOCK_ZOT_LOGIN_FAIL_STDOUT="$zot_stdout"
    export MOCK_SENTRY_CAPTURE_FILE="$sentry_file"
    [[ -n "$logger_file" ]] && export MOCK_LOGGER_CAPTURE_FILE="$logger_file"
    # shellcheck disable=SC2163
    if [[ -n "$extra_env" ]]; then for _kv in $extra_env; do export "${_kv?}"; done; fi
    create_base_mocks "$MOCK_DIR"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" >/dev/null 2>&1 || true
  )
}

# T-5B-1..5: each asserts the gate still emits login_failed AND that the specific class rides
# along. (This said "one case per login_class enum member" — false: these 5 cases cover 4 of the
# enum's 7 members. The other three ARE covered, elsewhere: authz_denied at T-5B-7, cred_store
# and server_error at T-5B-12, plus more transport shapes at T-5B-5b..5f. Coverage was fine; the
# claim was not — and an inaccurate comment about test coverage is the defect class this whole
# change exists to drain.)
# #6497: the tags are `login_class`/`login_http` (were `zot_login_class`/`zot_login_http`) — the
# classifier is registry-neutral now, so its tags are too, and `login_registry` says which.
assert_zot_login_class() {
  local label="$1" stderr="$2" want_class="$3" want_http="${4:-}"
  TOTAL=$((TOTAL + 1))
  local sf; sf=$(mktemp)
  run_deploy_zot_login_stderr "$sf" "$stderr"
  local ok=1
  grep -q 'zot gate degraded (login_failed)' "$sf" || ok=0
  grep -q "\"login_class\": *\"${want_class}\"" "$sf" || ok=0
  grep -q "\"login_registry\": *\"zot\"" "$sf" || ok=0
  if [[ -n "$want_http" ]]; then
    grep -q "\"login_http\": *\"${want_http}\"" "$sf" || ok=0
  fi
  if [[ "$ok" == "1" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: ${label} → login_class=${want_class}${want_http:+ http=$want_http}"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: ${label} — expected login_class=${want_class}${want_http:+ + login_http=$want_http}"
    echo "        sentry:"; sed 's/^/          /' "$sf"
  fi
  rm -f "$sf"
}

# The 401 fixture is byte-accurate — reproduced against the pinned zot (v2.1.2) with this
# repo's exact accessControl. Measured there: GET /v2/ (the ONLY request docker login makes)
# answers 200 or 401 and NEVER 403, even for a user with zero accessControl policies.
echo "--- #6497 T-5B-1..5: docker login stderr classifies into the login_class enum ---"
assert_zot_login_class "401 stale htpasswd (H3 — the live defect)" \
  'Error response from daemon: login attempt to http://10.0.1.30:5000/v2/ failed with status: 401 Unauthorized' \
  'authn_rejected' '401'
assert_zot_login_class "bare 401 shape with no status: prefix" \
  'Error response from daemon: Get "http://10.0.1.30:5000/v2/": unauthorized: authentication required' \
  'authn_rejected'
assert_zot_login_class "insecure-registries gap" \
  'Error response from daemon: Get "https://10.0.1.30:5000/v2/": http: server gave HTTP response to HTTPS client' \
  'tls_mismatch'
assert_zot_login_class "transport failure" \
  'Error response from daemon: Get "http://10.0.1.30:5000/v2/": dial tcp 10.0.1.30:5000: connect: connection refused' \
  'transport'
assert_zot_login_class "unrecognized stderr" \
  'Error response from daemon: something entirely unexpected happened' \
  'unclassified'

# T-5B-5b..5f: the transport shapes THIS fleet actually produces. `transport` is the arm most
# likely to fire in production — private-NIC convergence (#6415) yields `network is
# unreachable`; a zot OOM/restart (tracked as zot_oom_kills/zot_restarts on the same host)
# severs a live connection. Leaving these in `unclassified` would recreate the exact
# undifferentiated bucket #6497 exists to drain, on the fleet's most probable failures.
echo "--- #6497 T-5B-5b..5f: the transport shapes this fleet actually produces ---"
assert_zot_login_class "private NIC not up (#6415 class)" \
  'Error response from daemon: Get "http://10.0.1.30:5000/v2/": dial tcp 10.0.1.30:5000: connect: network is unreachable' \
  'transport'
assert_zot_login_class "zot OOM/restart mid-connection" \
  'Error response from daemon: Get "http://10.0.1.30:5000/v2/": read tcp 10.0.1.10:44444->10.0.1.30:5000: read: connection reset by peer' \
  'transport'
assert_zot_login_class "connection closed mid-flight" \
  'Error response from daemon: Get "http://10.0.1.30:5000/v2/": EOF' \
  'transport'
assert_zot_login_class "DNS failure" \
  'Error response from daemon: Get "http://registry.internal:5000/v2/": dial tcp: lookup registry.internal: no such host' \
  'transport'
# A socket-layer block (ICMP admin-prohibited -> EACCES) renders as "permission denied". This
# is the false positive a bare 'denied' in the authz arm would create: it is a NETWORK fault,
# and misfiling it as authz_denied sends the operator hunting an accessControl bug that does
# not exist.
assert_zot_login_class "socket blocked (permission denied is NOT authz)" \
  'Error response from daemon: Get "http://10.0.1.30:5000/v2/": dial tcp 10.0.1.30:5000: connect: permission denied' \
  'transport'
assert_zot_login_class "zot 5xx (OOM/restart window)" \
  'Error response from daemon: login attempt to http://10.0.1.30:5000/v2/ failed with status: 500 Internal Server Error' \
  'server_error' '500'

# T-5B-6 (task 1.2): the enum's whole purpose is discriminating power. A tls_mismatch that
# collapses into authn_rejected would send the operator hunting a credential bug that does
# not exist.
echo "--- #6497 T-5B-6: tls_mismatch must NOT classify as authn_rejected ---"
TOTAL=$((TOTAL + 1))
SF_TLS=$(mktemp)
run_deploy_zot_login_stderr "$SF_TLS" 'Error response from daemon: Get "https://10.0.1.30:5000/v2/": http: server gave HTTP response to HTTPS client'
if grep -q '"login_class": *"tls_mismatch"' "$SF_TLS" \
   && ! grep -q '"login_class": *"authn_rejected"' "$SF_TLS"; then
  PASS=$((PASS + 1)); echo "  PASS: tls_mismatch stays out of the authn_rejected bucket"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: tls_mismatch collapsed into authn_rejected (enum has no discriminating power)"
  echo "        sentry:"; sed 's/^/          /' "$SF_TLS"
fi
rm -f "$SF_TLS"

# T-5B-7: a DEFENSIVE tripwire, not the H3/H4 discriminator it was originally written as.
# Measured against the pinned zot: GET /v2/ (the only request docker login makes) never
# answers 403 — zot enforces accessControl at the MANIFEST endpoint, and a policy-less user
# still gets `Login Succeeded`. So this asserts only that IF a 403 ever appears here (a future
# zot, an interposed proxy), it is not silently read as an authentication failure. The arm
# matches a literal 403 ONLY; bare 'denied'/'forbidden' are deliberately unmatched because
# they have no true positive on this path and would steal `permission denied` (a socket
# error) from `transport` — see T-5B-5f.
echo "--- #6497 T-5B-7: a literal 403 must NOT be read as authn_rejected (defensive) ---"
TOTAL=$((TOTAL + 1))
SF_403=$(mktemp)
run_deploy_zot_login_stderr "$SF_403" 'Error response from daemon: login attempt to http://10.0.1.30:5000/v2/ failed with status: 403 Forbidden'
if grep -q '"login_class": *"authz_denied"' "$SF_403" \
   && ! grep -q '"login_class": *"authn_rejected"' "$SF_403"; then
  PASS=$((PASS + 1)); echo "  PASS: literal 403 → authz_denied, never authn_rejected"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: 403 collapsed into authn_rejected"
  echo "        sentry:"; sed 's/^/          /' "$SF_403"
fi
rm -f "$SF_403"

# T-5B-8 (task 1.3): payload hygiene. A registry error string can echo a username, so the
# enum is the ONLY thing that may cross the boundary — never the raw stderr.
echo "--- #6497 T-5B-8: raw docker login stderr never reaches the Sentry payload ---"
TOTAL=$((TOTAL + 1))
SF_HYG=$(mktemp)
run_deploy_zot_login_stderr "$SF_HYG" 'Error response from daemon: login attempt failed with status: 401 Unauthorized SENTINEL_LEAK_CANARY_zot-pull'
if grep -q '"login_class": *"authn_rejected"' "$SF_HYG" \
   && ! grep -q 'SENTINEL_LEAK_CANARY' "$SF_HYG"; then
  PASS=$((PASS + 1)); echo "  PASS: stderr classified to the enum; raw stderr absent from the payload"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: raw docker login stderr leaked into the Sentry payload"
  echo "        sentry:"; sed 's/^/          /' "$SF_HYG"
fi
rm -f "$SF_HYG"

# T-5B-8b: the OTHER sink. journald tag `ci-deploy` is allowlisted by vector.toml and shipped
# to Better Stack UNSCRUBBED, so it is a credential boundary exactly like the Sentry POST — but
# it had no purity assertion at all, because the logger mock discarded everything. A future
# edit appending $zdetail to the ZOT_GATE logger line would ship raw stderr off-box with the
# whole suite green. Asserts against the FULL journald capture, not a prefix (the scope half of
# 2026-07-09-sanitized-marker-alongside-raw-sibling-diagnostic-leaks-and-purity-test-scope).
echo "--- #6497 T-5B-8b: raw login stderr never reaches journald either ---"
TOTAL=$((TOTAL + 1))
JD=$(mktemp -d); SF_J="$JD/sentry.txt"; LG_J="$JD/logger.txt"; : > "$LG_J"
run_deploy_zot_login_stderr "$SF_J" 'Error response from daemon: login attempt failed with status: 401 Unauthorized SENTINEL_LEAK_CANARY_zot-pull' "$LG_J"
if grep -q 'ZOT_GATE' "$LG_J" \
   && grep -q 'class=authn_rejected' "$LG_J" \
   && ! grep -q 'SENTINEL_LEAK_CANARY' "$LG_J"; then
  PASS=$((PASS + 1)); echo "  PASS: journald carries the enum; raw stderr absent from the whole sink"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: journald purity — expected ZOT_GATE + class=authn_rejected, no canary"
  echo "        journald:"; sed 's/^/          /' "$LG_J" | head -20
fi
rm -rf "$JD"

# T-5B-9 (task 1.6): the 14 live WEB-PLATFORM-5B events carry no host attribution, so
# "which host" was unanswerable. Reuses the #6396 host_id precedent from pull_failure_event.
# Assert the WIRING at the source, body-scoped — mirroring assert_pull_failure_host_id (:1076)
# exactly rather than restating it, because that precedent already solved this problem and
# documented why.
#
# A runtime `grep '"host_id":'` over the payload is VACUOUS: jq always emits the key, so it
# matches `"host_id":""` and passes with attribution gutted (verified — `--arg h ""` left the
# first draft of this test green), leaving "which host" exactly as unanswerable as the 14 live
# WEB-PLATFORM-5B events it cites. But a runtime NON-EMPTY assert is the opposite error: it
# fails for a reason that is not a defect. resolve_host_id (:137) reads real host identity
# (IMDS / machine-id), which the mock environment cannot supply, so HOST_ID is legitimately
# empty in-suite and non-empty on a real host. Runtime resolution is unit-tested elsewhere
# (host-identity.test.ts); the ONE seam this needs to guard is host_id reaching THIS payload.
# Body-scoped so the sibling emits that also tag host_id (:562, :588, :715) cannot satisfy it.
echo "--- #6497 T-5B-9: zot_gate_degraded_event threads HOST_ID into its payload ---"
TOTAL=$((TOTAL + 1))
ZGD_BODY="$(awk '/^zot_gate_degraded_event\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
if [[ -n "$ZGD_BODY" ]] \
   && printf '%s' "$ZGD_BODY" | grep -qE -- '--arg h "\$\{HOST_ID:-\}"' \
   && printf '%s' "$ZGD_BODY" | grep -qE 'host_id: \$h'; then
  PASS=$((PASS + 1)); echo "  PASS: zot_gate_degraded_event threads --arg h \"\${HOST_ID:-}\" into tags.host_id"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: zot_gate_degraded_event must pass --arg h \"\${HOST_ID:-}\" AND put host_id: \$h in tags"
fi

# ---------------------------------------------------------------------------------------------
# #6497 T-5B-10..19 — the hatch: rc + stderr_chars + stdout_chars + kw + tok + docker_ver.
#
# Everything below asserts the ESCAPE HATCH, which is the half of this change that buys the datum.
# The classifier tests above assert the arms; these assert what happens when NO arm fires — the
# `unclassified` case that #6497 exists to drain — plus the fields that make a confidently-wrong
# arm visible in production telemetry.
#
# Each of these was proven RED by the AC9 mutation battery (Phase 3), not by being written before
# an implementation that already exists. The relevant mutation is named in each block's comment,
# because "this test would fail if the code were wrong" is a claim, and the mutation is its proof.
# ---------------------------------------------------------------------------------------------

# T-5B-10 (AC4, task 1.2): `unclassified` is not one state — it is three, and the whole point of
# the split is that the operator's NEXT ACTION differs per state:
#   stderr_chars>0                 -> the text exists and matched no arm  -> the remedy is an arm
#   stderr_chars=0 stdout_chars>0  -> H-B-stdout: the text went to stdout -> remedy: capture stdout
#   stderr_chars=0 stdout_chars=0  -> H-B-nowhere / H-D: no text anywhere -> `rc` is the only datum
# Asserting the three payloads DIFFER is the real invariant: `stderr_chars` ALONE cannot decide
# H-B, because H-B is a disjunction that `stderr_chars=0` merely RESTATES. Three identical
# payloads is today's behaviour and the defect (the plan's Enhancement Summary finding 2).
echo "--- #6497 T-5B-10: stderr_chars + stdout_chars split unclassified into three states ---"
TOTAL=$((TOTAL + 1))
T10D=$(mktemp -d)
# (a) unmatched non-empty stderr
run_deploy_zot_login_stderr "$T10D/s_a.txt" 'zqxjv totally unrecognized failure shape' "$T10D/l_a.txt"
# (b) H-B-stdout: nothing on stderr, text on stdout
run_deploy_zot_login_stderr "$T10D/s_b.txt" '' "$T10D/l_b.txt" 'zqxjv the error went to stdout instead'
# (c) H-B-nowhere: a SILENT failure — no stderr, no stdout, only an rc
run_deploy_zot_login_stderr "$T10D/s_c.txt" '' "$T10D/l_c.txt" '' 'MOCK_ZOT_LOGIN_FAIL_RC=1'
T10_A="$(grep -o 'class=unclassified.*' "$T10D/l_a.txt" 2>/dev/null | head -1)"
T10_B="$(grep -o 'class=unclassified.*' "$T10D/l_b.txt" 2>/dev/null | head -1)"
T10_C="$(grep -o 'class=unclassified.*' "$T10D/l_c.txt" 2>/dev/null | head -1)"
if [[ -n "$T10_A" && -n "$T10_B" && -n "$T10_C" ]] \
   && printf '%s' "$T10_A" | grep -qE 'stderr_chars=[1-9][0-9]*' \
   && printf '%s' "$T10_B" | grep -q 'stderr_chars=0' \
   && printf '%s' "$T10_B" | grep -qE 'stdout_chars=[1-9][0-9]*' \
   && printf '%s' "$T10_C" | grep -q 'stderr_chars=0' \
   && printf '%s' "$T10_C" | grep -q 'stdout_chars=0' \
   && [[ "$T10_A" != "$T10_B" && "$T10_B" != "$T10_C" && "$T10_A" != "$T10_C" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: the three unclassified states emit three DISTINCT payloads"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: the unclassified split collapsed — expected 3 distinct payloads"
  echo "        (a) stderr>0 : ${T10_A:-<no class= line>}"
  echo "        (b) stdout>0 : ${T10_B:-<no class= line>}"
  echo "        (c) silent   : ${T10_C:-<no class= line>}"
fi
rm -rf "$T10D"

# T-5B-11 (AC5): `stderr_chars` is the TRUE length. The precedent this file already carries
# (`tail -c 400`, :950) truncates, and a saturating length would make every large stderr
# indistinguishable at exactly the point the shape stops being guessable. Variable capture makes
# the true length structural — this pins that it stays so.
# AC9 mutation: replace ${#_e} with the tail -c 400 length -> saturates at 400 -> RED.
echo "--- #6497 T-5B-11: stderr_chars is the TRUE length, not the truncated one ---"
TOTAL=$((TOTAL + 1))
T11D=$(mktemp -d)
T11_LONG="zqxjv$(printf 'a%.0s' $(seq 1 600))"   # 605 chars, matches no arm, first token is the lot
run_deploy_zot_login_stderr "$T11D/s.txt" "$T11_LONG" "$T11D/l.txt"
T11_N="$(grep -o 'stderr_chars=[0-9]*' "$T11D/l.txt" 2>/dev/null | head -1 | cut -d= -f2)"
if [[ -n "$T11_N" && "$T11_N" -gt 400 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: stderr_chars=$T11_N — the true length, past the 400 truncation edge"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: stderr_chars=${T11_N:-<absent>} — expected >400 (saturation means a truncated length)"
fi
rm -rf "$T11D"

# T-5B-11b: the STDOUT counterpart. The AC9 battery mutated `stderr_chars` to a truncated length
# and caught it (M4) — and had NO counterpart on the stdout side, so `stdout_chars` was pinned
# only by T-5B-10's `>0 vs =0` split. A BOOLEAN implementation (`[[ -n "$o" ]] && echo 1 || echo
# 0`) satisfies every other assertion in this file: T-5B-10 (b) matches `[1-9][0-9]*` via "1" and
# (c) matches `0`. The two length fields are documented as a symmetric pair, so they are pinned
# as one.
echo "--- #6497 T-5B-11b: stdout_chars is a LENGTH, not a boolean ---"
TOTAL=$((TOTAL + 1))
T11BD=$(mktemp -d)
T11B_LONG="zqxjv$(printf 'b%.0s' $(seq 1 600))"   # 605 chars on STDOUT, nothing on stderr
run_deploy_zot_login_stderr "$T11BD/s.txt" '' "$T11BD/l.txt" "$T11B_LONG"
T11B_N="$(grep -o 'stdout_chars=[0-9]*' "$T11BD/l.txt" 2>/dev/null | head -1 | cut -d= -f2)"
if [[ -n "$T11B_N" && "$T11B_N" -gt 400 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: stdout_chars=$T11B_N — a real length; a boolean or a truncation would be <=1 or 400"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: stdout_chars=${T11B_N:-<absent>} — expected >400 (1 means a boolean; 400 means truncation)"
fi
rm -rf "$T11BD"

# T-5B-12 (AC6, task 1.4): the two arms that were CONFIDENTLY WRONG before this change. Both were
# landing in `transport` — which routes the operator to the network subsystem for a failure that
# is not on the network at all. These are precedence assertions, not matching assertions: the
# strings DO match `transport` too (`permission denied` / `timeout` are both bare terms in it), so
# the only thing keeping them out of it is arm ORDER.
# AC9 mutations 3.1/3.2: relocate the arm AFTER transport -> RED. That relocation is the proof
# these are testing order and not merely matching.
echo "--- #6497 T-5B-12: cred_store and server_error precede transport (order is load-bearing) ---"
assert_zot_login_class "cred-store EACCES (H-A/H-C — NOT a network fault)" \
  'error saving credentials: open /home/deploy/.docker/config.json123: permission denied' \
  'cred_store'
assert_zot_login_class "504 from an interposed proxy (NOT a client-side timeout)" \
  'Error response from daemon: login attempt to http://10.0.1.30:5000/v2/ failed with status: 504 Gateway Timeout' \
  'server_error' '504'

# T-5B-13 (task 1.3): `rc` rides every failed login. 125/126/127 (docker missing / not executable
# / not on PATH), 137 (OOM-killed mid-login) and 124 (timeout wrapper) are each actionable from
# this field ALONE — they are the states where there IS no stderr to classify, so without `rc`
# the H-B-nowhere row of T-5B-10 would be a dead end rather than a diagnosis.
echo "--- #6497 T-5B-13: rc rides the failed-login line (the only datum when there is no text) ---"
TOTAL=$((TOTAL + 1))
T13D=$(mktemp -d)
run_deploy_zot_login_stderr "$T13D/s.txt" '' "$T13D/l.txt" '' 'MOCK_ZOT_LOGIN_FAIL_RC=127'
if grep -q 'rc=127' "$T13D/l.txt" 2>/dev/null && grep -q 'class=unclassified' "$T13D/l.txt"; then
  PASS=$((PASS + 1)); echo "  PASS: rc=127 (docker absent) rides the line with no stderr to classify"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: expected rc=127 on the failed-login line"
  echo "        journald:"; sed 's/^/          /' "$T13D/l.txt" 2>/dev/null | head -5
fi
rm -rf "$T13D"

# T-5B-14 (AC3, task 1.5): the leak canary THROUGH THE UNCLASSIFIED PATH.
#
# LOAD-BEARING, and the reason this is a separate test from T-5B-8/8b rather than an extension of
# them: both existing canaries drive a 401, which classifies as `authn_rejected`. The hatch is the
# ONLY thing that touches the raw stderr, so a canary that never reaches the hatch cannot detect a
# hatch leak. T-5B-8/8b would stay GREEN while the hatch shipped raw stderr off-box. This fixture
# matches no arm, so the hatch actually runs on it.
#
# Asserts against the WHOLE journald capture, not a prefix: the `ci-deploy` tag is allowlisted in
# vector.toml and ships UNSCRUBBED to Better Stack, so it is a credential boundary exactly like
# the Sentry POST.
# AC9 mutation 3.3: swap tok Form B -> Form A raw passthrough -> the canary's first token is
# echoed -> RED.
echo "--- #6497 T-5B-14: the hatch cannot echo its input, asserted THROUGH the unclassified path ---"
TOTAL=$((TOTAL + 1))
T14D=$(mktemp -d)
# First token IS the canary, so a raw-first-token passthrough leaks it. The password shape is a
# synthesized fixture (cq-test-fixtures-synthesized-only), split so no contiguous token literal
# exists in this source file.
T14_CANARY="SENTINEL_LEAK_CANARY_hatch"
T14_SECRET="dckr_pat_""AAAAAAAAAAAAAAAAAAAAAAAAAAA"
run_deploy_zot_login_stderr "$T14D/s.txt" \
  "${T14_CANARY} zqxjv unrecognized shape for user deploy-bot password=${T14_SECRET}" \
  "$T14D/l.txt"
T14_OK=1
grep -q 'class=unclassified' "$T14D/l.txt" 2>/dev/null || T14_OK=0     # the hatch actually ran
grep -q 'kw= tok=other' "$T14D/l.txt" 2>/dev/null || T14_OK=0          # closed vocabulary held
grep -q "$T14_CANARY" "$T14D/l.txt" 2>/dev/null && T14_OK=0            # journald: no canary
grep -q "$T14_SECRET" "$T14D/l.txt" 2>/dev/null && T14_OK=0            # journald: no secret
grep -q "$T14_CANARY" "$T14D/s.txt" 2>/dev/null && T14_OK=0            # sentry: no canary
grep -q "$T14_SECRET" "$T14D/s.txt" 2>/dev/null && T14_OK=0            # sentry: no secret
if [[ "$T14_OK" == "1" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: hatch fired on the unclassified path; neither sink carries the canary or the secret"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: the hatch leaked its input (or never fired) on the unclassified path"
  echo "        journald:"; sed 's/^/          /' "$T14D/l.txt" 2>/dev/null | head -8
  echo "        sentry:";   sed 's/^/          /' "$T14D/s.txt" 2>/dev/null | head -8
fi
rm -rf "$T14D"

# T-5B-15 (AC3a, task 1.6): STRUCTURAL. T-5B-14 proves the emitters do not echo THIS input;
# this proves they CANNOT echo ANY input, which is a different and stronger claim that no finite
# set of fixtures can establish.
#
# THE ANCHOR IS A WHITELIST, NOT A BLACKLIST — and that is the whole point of this rewrite.
#
# The first draft asserted `grep -cE 'printf[^#]*\$'` == 0, i.e. "no printf line takes an
# expansion". It was comment-blind (good) but anchored on TODAY'S SYNTAX rather than on the
# PROPERTY, and review proved two ordinary implementations that echo their input and evade it:
#   *)  echo -n "$1" ;;                    <- the guard only knows the verb `printf`
#   *)  printf '%s' \                      <- grep is LINE-based; the expansion is on line 2
#         "$1" ;;
# Both are shapes a reasonable engineer might actually write next, which is the tell that the
# anchor was narrower than the claim (`cq-assert-anchor-not-bare-token` says "anchor on syntax" —
# today's syntax is a narrower thing than the syntax the property allows).
#
# Inverted: strip comments, then strip the ONE expansion these emitters are permitted (`${1:-}`
# in the `case` head), then assert NO `$` survives anywhere in either body. That is verb-blind
# (echo, print, cat, a variable-indirect call — all caught), line-boundary-blind (a continuation
# carrying `"$1"` still contains `$`), and comment-blind. It cannot be evaded by any emit
# mechanism, because the thing it forbids is the INPUT REACHING ANY LINE AT ALL.
echo "--- #6497 T-5B-15: the emitters contain NO expansion but \${1:-} (Form B, structurally) ---"
TOTAL=$((TOTAL + 1))
KW_BODY="$(awk '/^_login_kw\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
TOK_BODY="$(awk '/^_login_tok\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
# Strip trailing comments, then the permitted `${1:-}`; anything left holding a `$` is a channel
# from the input to the output.
_t15_residue() { printf '%s\n' "$1" | sed 's/#.*$//' | sed 's/\${1:-}//g' | grep -n '\$' || true; }
KW_RESIDUE="$(_t15_residue "$KW_BODY")"
TOK_RESIDUE="$(_t15_residue "$TOK_BODY")"
# Non-vacuity: an extraction that silently returns nothing would pass every assertion below.
if [[ -z "$KW_BODY" || -z "$TOK_BODY" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: could not extract _login_kw/_login_tok bodies (fixture error, not a code defect)"
elif [[ -z "$KW_RESIDUE" && -z "$TOK_RESIDUE" ]] \
  && [[ "$(printf '%s' "$KW_BODY"  | grep -cE '^[^#]*printf')" -gt 0 ]] \
  && [[ "$(printf '%s' "$TOK_BODY" | grep -cE '^[^#]*printf')" -gt 0 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: neither emitter body contains any expansion but \${1:-} — incapable of echoing, whatever the verb"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: an emitter body holds an expansion other than \${1:-} (Form A — it can echo its input)"
  [[ -n "$KW_RESIDUE"  ]] && { echo "        _login_kw:";  printf '%s\n' "$KW_RESIDUE"  | sed 's/^/          /'; }
  [[ -n "$TOK_RESIDUE" ]] && { echo "        _login_tok:"; printf '%s\n' "$TOK_RESIDUE" | sed 's/^/          /'; }
fi

# T-5B-16 (AC3b, task 1.7): FUZZ. Against a single fixture the closed-vocabulary claim is
# vacuous — one input proves one output. 200 high-entropy first tokens plus a hand-picked
# adversarial set (format specifiers, command substitution, quote/newline breakouts) is what makes
# the AC9 Form-A mutation reliably RED instead of coincidentally green.
#
# Sources the REAL function bodies rather than re-running the deploy 200+ times (~minutes each):
# the emitters are pure `case`/`printf` with no dependencies, so the extracted body IS the SUT.
echo "--- #6497 T-5B-16: tok is a member of the closed set for every input (200 fuzz + adversarial) ---"
TOTAL=$((TOTAL + 1))
T16_LIB=$(mktemp)
{ printf '%s\n' "$KW_BODY"; printf '%s\n' "$TOK_BODY"; } > "$T16_LIB"
# shellcheck disable=SC1090
source "$T16_LIB"
T16_BAD=""
T16_N=0
# Fixtures for the _login_kw arms, each carrying a credential canary in the same string — so an arm
# that splices its input emits the canary and fails the closed-form oracle.
#
# PROVENANCE, per entry — stated as an enumeration because the universal it replaces was FALSE.
# Most entries below are strings the /work Phase 0 battery measured out of a real `docker login`
# against a live registry:2. The exceptions, ALL of them:
#   - three the plan FALSIFIED (non-TTY / daemon-conn / credential-helper), kept as free kw probes;
#   - `some entirely novel shape no arm has ever seen …` — a SYNTHETIC no-match probe;
#   - `""` — the empty-input case.
# This array also does NOT enumerate `_login_kw`'s six INFERRED errno arms (#6565); T-5B-20 owns those.
#
# WHY THE ENUMERATION AND NOT A UNIVERSAL WITH A CARVE-OUT: this comment previously read "Every
# literal here is a string the /work Phase 0 battery measured … (except the three the plan
# FALSIFIED)". That universal was already false on main — the novel-shape probe and the empty
# fixture are neither measured nor falsified — and the #6565 round initially "fixed" it by asserting
# it "stays true", which made a passively stale comment into an ACTIVELY claimed one. A comment
# claiming more measurement than was done is the exact defect this instrument exists to drain;
# restating it here would have been this change reproducing its own bug. Enumerate, do not quantify.
# Synthesized secret shapes only, split so no contiguous token literal exists in this file
# (`cq-test-fixtures-synthesized-only` + GitHub push protection).
T16_KW_CANARY="SENTINEL_LEAK_CANARY_kw pw=dckr_pat_""BBBBBBBBBBBBBBBBBBBBBBBBBBB user=deploy-bot"
T16_KW_FIXTURES=(
  "error saving credentials: write /home/deploy/.docker/config.json: no space left on device ${T16_KW_CANARY}"
  "error saving credentials: exec: \"docker-credential-desktop\": executable file not found in \$PATH ${T16_KW_CANARY}"
  "error getting credentials - err: exit status 1, out: \`docker-credential-secretservice\` ${T16_KW_CANARY}"
  "error saving credentials: open /home/deploy/.docker/config.json: permission denied ${T16_KW_CANARY}"
  "error storing credentials - err: exit status 1 ${T16_KW_CANARY}"
  "error: cannot perform an interactive login from a non-TTY device ${T16_KW_CANARY}"
  "Cannot connect to the Docker daemon at unix:///var/run/docker.sock ${T16_KW_CANARY}"
  "credential helper is not installed ${T16_KW_CANARY}"
  "some entirely novel shape no arm has ever seen ${T16_KW_CANARY}"
  ""
)
if ! declare -F _login_tok >/dev/null || ! declare -F _login_kw >/dev/null; then
  FAIL=$((FAIL + 1)); echo "  FAIL: could not source the real emitters (fixture error, not a code defect)"
else
  # The oracle is DERIVED from the SUT, never hand-copied. A hand-written literal list is a
  # replicated literal with no parity test: add an arm to _login_tok (`refused*) printf
  # 'refused'`) and neither the 200 base64 randoms nor the adversarial list would ever emit it,
  # so this test stays GREEN while its own headline claim ("tok ∈ the closed set for EVERY
  # input") stops describing the closed set. Extracting the arms from TOK_BODY makes the oracle
  # track the SUT by construction. Mirrors the T-PARITY precedent in this file, which extracts
  # the lease basename from both sources rather than restating it.
  # Anchored on the printf CALL FORM inside a case arm, not a bare token, so a comment in the
  # body cannot inject a member (`cq-assert-anchor-not-bare-token`).
  T16_CLOSED="$(printf '%s\n' "$TOK_BODY" | grep -oE "printf '[a-zA-Z]+'" | grep -oE "'[a-zA-Z]+'" | tr -d "'" | sort -u)"
  T16_CLOSED_N="$(printf '%s\n' "$T16_CLOSED" | grep -c .)"
  _t16_tok_closed() {
    printf '%s\n' "$T16_CLOSED" | grep -qxF "$1"
  }
  # _login_kw's oracle needs no member list: its ENTIRE output vocabulary is comma-joined
  # lowercase literals, so `^([a-z]+,)*$` is the closed-form property. Any Form-A mutation that
  # splices input (`printf 'nospace:%s,' "$1"`, `echo -n "nospace:${1},"`) emits a colon, a
  # space, a slash or a quote and fails it, whatever the arm.
  _t16_kw_closed() { [[ "$1" =~ ^([a-z]+,)*$ ]]; }
  # The adversarial set: each of these BREAKS a Form-A implementation in a different way.
  # `failed`/`unauthorized` are here because base64 randoms cannot produce them — without them
  # two of _login_tok's nine arms were never exercised, so a Form-A body in either arm passed
  # the whole fuzz.
  for _f in '%s%s%s' '%n' '$(id)' '`id`' '${IFS}' '"; id; #' "'" '\' '../../etc/passwd' \
            '-' '--help' '' ' ' 'error' 'Error' 'time=x' 'WARNING!' 'Cannot' 'denied:' \
            'failed' 'failed:' 'unauthorized' 'unauthorized:' ; do
    T16_N=$((T16_N + 1))
    _o="$(_login_tok "$_f")"
    _t16_tok_closed "$_o" || T16_BAD="${T16_BAD}[tok in=<${_f}> out=<${_o}>] "
  done
  # _login_kw — REVIEW-CRITICAL. Until this loop existed, `_login_kw` had ZERO behavioural
  # coverage: the AC9 battery mutated _login_tok, the hatch and the call sites, and never touched
  # it, so a Form-A disclosure in ANY of its 16 arms shipped the raw stderr — username, token and
  # all — to journald -> Vector -> Better Stack UNSCRUBBED, with the whole suite green. Proven by
  # a review agent: mutating the `no space left on device` arm to splice `${1}` left the suite
  # byte-identical (same pass count, same failures). That arm is the H-C disk-full path, i.e. one
  # of the two live hypotheses this instrument exists to diagnose.
  # The meta-lesson, worth more than the fix: A MUTATION BATTERY ONLY COVERS WHAT YOU MUTATE.
  # Enumerate the SUT's functions and confirm each appears on the LEFT of a call in the test file.
  for _f in "${T16_KW_FIXTURES[@]}"; do
    T16_N=$((T16_N + 1))
    _o="$(_login_kw "$_f")"
    _t16_kw_closed "$_o" || T16_BAD="${T16_BAD}[kw in=<${_f}> out=<${_o}>] "
  done
  # Both emitters get the random corpus. Each random is ALSO appended to a measured prefix so it
  # reaches _login_kw's arms with a high-entropy tail — a spliced arm then emits the tail.
  for _i in $(seq 1 200); do
    T16_N=$((T16_N + 2))
    _f="$(head -c 18 /dev/urandom | base64 | tr -d '\n')"
    _o="$(_login_tok "$_f")"
    _t16_tok_closed "$_o" || T16_BAD="${T16_BAD}[tok in=<${_f}> out=<${_o}>] "
    _o="$(_login_kw "error saving credentials: permission denied ${_f}")"
    _t16_kw_closed "$_o" || T16_BAD="${T16_BAD}[kw in=<…${_f}> out=<${_o}>] "
  done
  # Non-vacuity floor on the DERIVED oracle: an extraction that silently returned nothing (or
  # one member) would make `_t16_tok_closed` reject everything -> loud RED, not a false green;
  # but a MIS-extraction that returned a huge set would accept everything, so pin the count too.
  # _login_tok has 9 arms today; the floor is deliberately below that so adding an arm does not
  # false-FAIL, while a collapsed extraction does.
  # (`T16_N -ge 200` used to sit here and was a TAUTOLOGY — T16_N increments unconditionally
  # across two literal-bounded loops, so it could never be false. It read as a non-vacuity guard
  # and asserted nothing. The real guards are T16_CLOSED_N's bounds and _t16_kw_closed's regex.)
  if [[ -z "$T16_BAD" && "$T16_CLOSED_N" -ge 5 && "$T16_CLOSED_N" -le 20 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: tok ∈ SUT-derived closed set (${T16_CLOSED_N} members); kw ∈ ^([a-z]+,)*\$ — $T16_N inputs across BOTH emitters"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: tok escaped the closed set (n=$T16_N, oracle_members=$T16_CLOSED_N): $T16_BAD"
  fi
fi
rm -f "$T16_LIB"

# T-5B-17 (AC8, task 1.8): GHCR parity. Before this change the two GHCR logins discarded stderr
# entirely (`>/dev/null 2>&1`), so a GHCR login failure was as unnamed as the zot one — and the
# BAKED-cred failure shape specifically is the #6090/#6400 recurrence signal, which is lost if
# only the post-refetch login is classified. Both lines are asserted for that reason.
#
# Body-scoped to each GHCR line (precedent: assert_pull_failure_host_id :1076). The zot gate emits
# `class=` too, so an unscoped `grep class=cred_store` over the capture would be satisfied by the
# SIBLING zot emit and pass with GHCR classification entirely absent.
# AC9 mutation 3.6: point the assertion at the zot payload -> RED, which is what proves the
# scoping is real and not decorative.
echo "--- #6497 T-5B-17: the class rides BOTH GHCR PRELUDE lines (baked-cred AND post-refetch) ---"
run_deploy_ghcr_login_stderr() {
  local sentry_file="$1" ghcr_stderr="$2" logger_file="$3"
  (
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d); trap 'rm -rf "$MOCK_DIR"' EXIT
    export PLUGIN_MOUNT_DIR="$MOCK_DIR/plugin-mount"
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export CRON_DEPLOY_LEASE_FILE="$MOCK_DIR/deploy-lease"
    export CRON_DRAIN_STATE_FILE="$MOCK_DIR/cron-drain.json"
    export CI_DEPLOY_STATE="$MOCK_DIR/ci-deploy.state"
    export MOCK_GHCR_LOGIN_FAIL_STDERR="$ghcr_stderr"
    export MOCK_SENTRY_CAPTURE_FILE="$sentry_file"
    export MOCK_LOGGER_CAPTURE_FILE="$logger_file"
    create_base_mocks "$MOCK_DIR"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$TEST_PATH_BASE"
    export CANARY_LAYER_3_SCRIPT="$MOCK_DIR/canary-bundle-claim-check.sh"
    bash "$DEPLOY_SCRIPT" >/dev/null 2>&1 || true
  )
}
# Body-scoped: each assertion reads only ITS OWN line, selected by that line's unique prefix.
assert_ghcr_login_class() {
  local label="$1" line_match="$2" want_class="$3" logger_file="$4"
  TOTAL=$((TOTAL + 1))
  local line; line="$(grep -F "$line_match" "$logger_file" 2>/dev/null | head -1)"
  if [[ -n "$line" ]] && printf '%s' "$line" | grep -q "class=${want_class}" \
     && printf '%s' "$line" | grep -q 'registry=ghcr'; then
    PASS=$((PASS + 1)); echo "  PASS: ${label} → class=${want_class}"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: ${label} — expected class=${want_class} on this line"
    echo "        line: ${line:-<line absent from journald>}"
  fi
}
T17D=$(mktemp -d)
run_deploy_ghcr_login_stderr "$T17D/s.txt" \
  'error saving credentials: open /home/deploy/.docker/config.json123: permission denied' \
  "$T17D/l.txt"
assert_ghcr_login_class "GHCR baked/first-cred login" \
  'PRELUDE: docker login ghcr.io FAILED with baked/first creds' 'cred_store' "$T17D/l.txt"
assert_ghcr_login_class "GHCR post-Doppler-refetch login" \
  'PRELUDE: docker login ghcr.io FAILED after Doppler re-fetch' 'cred_store' "$T17D/l.txt"

# T-5B-18 (task 1.9): `refetch_ghcr_and_relogin`'s stdout is a TYPED CONTROL CHANNEL — its two
# callers parse it with `stage="$(refetch_ghcr_and_relogin)"` and compare against `recovered`. The
# reflexive way to add telemetry to that function is `2>&1`, which would pipe unclassified stderr
# into the stage string, silently break the `== "recovered"` comparison, and discard the #6400
# recovery — while every existing recovery test stays green, because they assert the RECOVERED
# path and this corrupts only the FAILED one.
#
# So: the stage stays byte-exactly one of the three literals, and the class rides journald instead.
# AC9 mutation 3.5: emit the class on the helper's stdout -> the stage string is polluted -> RED.
echo "--- #6497 T-5B-18: the refetch helper's stdout stays a typed control channel ---"
TOTAL=$((TOTAL + 1))
T18_STAGE="$(grep -c 'STILL FAILED after Doppler re-fetch (stage=relogin_failed)' "$T17D/l.txt" 2>/dev/null)"
T18_HATCH="$(grep -c 'PRELUDE: docker login ghcr.io FAILED after Doppler re-fetch.*rc=.*stderr_chars=' "$T17D/l.txt" 2>/dev/null)"
if [[ "$T18_STAGE" -ge 1 && "$T18_HATCH" -ge 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: stage is byte-exactly 'relogin_failed'; the class + hatch ride journald instead"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: expected an unpolluted stage=relogin_failed AND a hatch on the journald line"
  echo "        stage_lines=$T18_STAGE hatch_lines=$T18_HATCH"
  grep -F 'PRELUDE' "$T17D/l.txt" 2>/dev/null | sed 's/^/          /' | head -8
fi
rm -rf "$T17D"

# T-5B-19 (AC2c): the hatch's containment subshell, pinned STRUCTURALLY.
#
# WHY THIS TEST EXISTS, in its own words: the AC9 battery measured that REMOVING the subshell
# leaves this suite 164/164 GREEN. That is not a passing grade — it is an unguarded invariant
# (`cq-assert-anchor-not-bare-token`: if deleting the guard leaves the suite green, it pins
# nothing). This test is the guard the battery proved was missing.
#
# The plan's AC2(b) falsifier — "remove the subshell -> (b) aborts the run -> RED" — is FALSE
# against this implementation. Two measurements say why (both run at /work, neither derived):
#   1. The emitters are built on `case`, which returns 0 on a NO-MATCH. The plan's abort vector
#      was `grep -q`, whose normal non-match returns 1. There is no `grep -q` here at all, so the
#      dominant abort class is designed out AT THE ROOT rather than contained — a strict
#      improvement on the plan, and the reason its falsifier no longer falsifies.
#   2. The plan's abort measurement is real but TOP-LEVEL ONLY. `kw="$(… | grep -q ZZZ …)"` does
#      abort under `set -euo pipefail` at top level; the SAME code inside a function invoked
#      through a command substitution does NOT — and `$( ( _login_hatch … ) )` is exactly how all
#      three sites call it.
# So the subshell today contains a failure mode nothing can currently reach. It STAYS: the
# cheapest future edit to `_login_kw` is a `grep -q` probe (that is literally the shape the plan
# proposed), and re-entering the abort class costs one deleted construct. No behavioural test can
# pin it — there is no reachable abort to observe — so the construct itself is the assertion.
#
# COMMENT-BLIND BY CONSTRUCTION: `ci-deploy.sh` › `_login_hatch()`'s header documents the call
# form VERBATIM ("CALL IT AS: hatch=..."), so a grep that does not strip comments matches that
# prose and passes with all three real call sites gutted — a bare-token false-pass hiding inside
# an assertion that otherwise looks correctly anchored. Non-comment lines only.
echo "--- #6497 T-5B-19: every hatch call site is wrapped in the containment subshell ---"
TOTAL=$((TOTAL + 1))
HATCH_NC="$(grep -vE '^[[:space:]]*#' "$DEPLOY_SCRIPT")"
# ARGUMENT-AGNOSTIC by necessity. This counted `_login_hatch[[:space:]]+"` — requiring the first
# argument to START WITH A DOUBLE QUOTE — and review proved that makes the equality claim below
# FALSE for the likeliest shapes a hurried 4th call site would take: `_login_hatch $E 0 1`,
# `_login_hatch ${LOGIN_ERR:-} 0 1`, and a `\`-continuation all counted ZERO, leaving CALLS=3
# WRAPPED=3 and the test GREEN with an unwrapped, uncontained 4th site. Anchoring on
# `_login_hatch` NOT followed by `(` counts every invocation regardless of argument form while
# still excluding the definition (`_login_hatch() {`). Let the wrapped-regex carry the shape
# check; the counter's only job is to see the call at all.
HATCH_CALLS="$(printf '%s\n' "$HATCH_NC" | grep -cE '_login_hatch([^(]|$)')"
HATCH_WRAPPED="$(printf '%s\n' "$HATCH_NC" | grep -cE '\$\([[:space:]]*\([[:space:]]*_login_hatch[[:space:]].*\)[[:space:]]*\|\|[[:space:]]*true[[:space:]]*\)')"
if [[ "$HATCH_CALLS" -eq 3 && "$HATCH_WRAPPED" -eq 3 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: all 3 hatch call sites emit from ( … ) || true — a telemetry failure cannot abort a deploy"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: hatch containment drift — invocations=$HATCH_CALLS wrapped=$HATCH_WRAPPED (both must be 3)"
  echo "        every call MUST read: x=\"\$( ( _login_hatch … ) || true )\""
  printf '%s\n' "$HATCH_NC" | grep -nE '_login_hatch([^(]|$)' | sed 's/^/          /'
fi

# T-5B-20 (#6565, errno probe round): each errno arm FIRES, and the kw vocabulary stays closed.
#
# *** DO-NOT-FIX NOTE — READ BEFORE "CORRECTING" THE SOURCING BELOW. ***
# This test SPLITS its oracle sourcing on purpose, and the split is load-bearing:
#   (a) the FIRING fixtures (literal -> expected token) are HAND-WRITTEN, and MUST STAY so;
#   (b) the VOCABULARY invariant is DERIVED from KW_BODY, and MUST STAY so.
# This file carries a loud precedent immediately above (`ci-deploy.test.sh` › T-5B-16's oracle note) reading "the oracle is
# DERIVED from the SUT, never hand-copied". That precedent is CORRECT and applies to (b). It does
# NOT apply to (a), and applying it there destroys this test:
#   deriving a FIRING fixture from KW_BODY feeds the arm's own literal back into itself, so a
#   TYPO'D arm (`*'cannot allocat memory'*`) matches its own typo and the test goes GREEN WITH THE
#   BUG. Measured, not reasoned: that is exactly what a derived fixture does here.
# Two reviewers gave opposite guidance on this and both were right about different assertions.
# The measurement settled it. If you are here to unify the sourcing: don't — you would be
# re-introducing the defect this note exists to prevent.
#
# (b) must be derived because it has to span arm #17 — the arm nobody has written yet. No
# hand-written member list can.
echo "--- #6565 T-5B-20: every errno arm fires with its own token; kw vocabulary stays closed ---"
TOTAL=$((TOTAL + 1))
T20_LIB=$(mktemp)
printf '%s\n' "$KW_BODY" > "$T20_LIB"
# shellcheck disable=SC1090
source "$T20_LIB"
T20_BAD=""
T20_N=0
# HAND-WRITTEN (see the DO-NOT-FIX note): each pair is (a real docker stderr shape carrying the
# errno, the token that arm must emit). The errno strings are the MEASURED `syscall.Errno.Error()`
# renderings (Go 1.21.6, /work Phase 0) — Go renders them lowercase; C `strerror` capitalizes.
# Each fixture carries a credential canary so an arm that splices its input fails the closed-form
# oracle below. Synthesized shapes only, split so no contiguous token literal exists in source
# (`cq-test-fixtures-synthesized-only` + GitHub push protection).
T20_CANARY="SENTINEL_LEAK_CANARY_errno pw=dckr_pat_""CCCCCCCCCCCCCCCCCCCCCCCCCCC user=deploy-bot"
T20_PAIRS=(
  "error saving credentials: open /home/deploy/.docker/config.json1234567890: cannot allocate memory ${T20_CANARY}|enomem"
  "error saving credentials: open /home/deploy/.docker/config.json1234567890: read-only file system ${T20_CANARY}|erofs"
  "error saving credentials: open /home/deploy/.docker/config.json1234567890: no such file or directory ${T20_CANARY}|enoent"
  "error saving credentials: open /home/deploy/.docker/config.json1234567890: invalid argument ${T20_CANARY}|einval"
  "error saving credentials: open /home/deploy/.docker/config.json1234567890: input/output error ${T20_CANARY}|eio"
  "error saving credentials: open /home/deploy/.docker/config.json1234567890: operation not permitted ${T20_CANARY}|eperm"
)
if ! declare -F _login_kw >/dev/null; then
  FAIL=$((FAIL + 1)); echo "  FAIL: could not source _login_kw (fixture error, not a code defect)"
else
  for _pair in "${T20_PAIRS[@]}"; do
    _fixture="${_pair%|*}"
    _want="${_pair##*|}"
    _got="$(_login_kw "$_fixture")"
    T20_N=$((T20_N + 1))
    # The arm must FIRE (its token present) ...
    case "$_got" in
      *"${_want},"*) : ;;
      *) T20_BAD="${T20_BAD}\n    arm '${_want}' did NOT fire; kw='${_got}'" ;;
    esac
    # *** ... and must fire ONLY on its OWN errno. THIS IS THE NEGATIVE ORACLE — do not drop it. ***
    # Without it this test is vacuous against the harm it exists to prevent. MEASURED: loosening the
    # enomem arm to `*'.docker/config.json'*` makes it fire on ALL SIX fixtures (they share the
    # `error saving credentials: open /home/deploy/.docker/config.json…` prefix) and the FULL SUITE
    # stays BYTE-IDENTICAL to control — not one assertion moves. A positive-only oracle is true of
    # the correct implementation AND of the broken one; that is the #6497 shape exactly
    # (`2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`).
    # The harm is the one `_login_kw`'s own header names — "in an arm it mis-routes the operator":
    # every H-C disk-full event would report `enomem`, and "which errno" is this round's ONLY question.
    # Scoped to the six ERRNO tokens on purpose: `errsaving` legitimately fires on all six (shared
    # prefix), so a blanket "no other token" assertion would be wrong. Only these six are exclusive.
    for _other in "${T20_PAIRS[@]}"; do
      _onot="${_other##*|}"
      [[ "$_onot" == "$_want" ]] && continue
      case "$_got" in
        *"${_onot},"*) T20_BAD="${T20_BAD}\n    ARM TOO LOOSE: the '${_want}' fixture ALSO fired '${_onot}' — kw='${_got}'. An arm matching something the fixtures SHARE (the config.json path, the 'error saving credentials' prefix) mis-routes every other errno to this token." ;;
      esac
    done
    # ... and the output must stay closed-form: comma-joined lowercase literals, nothing else.
    # Any Form-A splice emits a colon/space/slash/quote from the fixture and fails this.
    if ! [[ "$_got" =~ ^([a-z]+,)*$ ]]; then
      T20_BAD="${T20_BAD}\n    arm '${_want}' emitted a NON-closed-form value: '${_got}'"
    fi
  done
  # *** CARDINALITY PARITY — this is what gives the HAND-WRITTEN family (a) teeth against arm #17. ***
  # The DO-NOT-FIX note concedes (a) cannot span arm #17, and until this check nothing guarded that
  # gap. MEASURED: a typo'd 7th Form-B arm (`*'devic or resource busy'*` -> `printf 'ebusy,'`) lands,
  # never fires, and the suite PASSES — while the PASS line advertises the dead arm in its member
  # count as if it were reassurance.
  # This is a COUNT parity, never a derivation: no literal is fed back into its own oracle, so the
  # DO-NOT-FIX note is untouched. A new errno arm goes RED until someone HAND-WRITES its fixture —
  # which is exactly the intent, and the only way (a) can cover an arm nobody has written yet.
  # NOTE this deliberately wants the OPPOSITE of T-5B-16's floor policy ("the floor is deliberately
  # below that so adding an arm does not false-FAIL"): correct there, wrong here. For the errno
  # family a new un-fixtured arm MUST false-FAIL — an unfixtured probe is a silent dead probe.
  T20_ARM_N="$(printf '%s\n' "$KW_BODY" | awk '/--- INFERRED/{f=1;next} /--- FALSIFIED/{f=0} f' \
    | sed 's/#.*$//' | grep -cE "printf '[a-z]+,'")"
  if [[ "$T20_ARM_N" -ne "${#T20_PAIRS[@]}" ]]; then
    T20_BAD="${T20_BAD}\n    ERRNO ARM/FIXTURE PARITY: ${T20_ARM_N} errno arm(s) in _login_kw but ${#T20_PAIRS[@]} hand-written fixture(s) here. A new arm needs a HAND-WRITTEN (literal, token) pair — do NOT derive it from KW_BODY (see the DO-NOT-FIX note): a derived fixture feeds the arm's own typo back into its oracle and passes green WITH the bug."
  fi

  # ---- DERIVED invariants (see the DO-NOT-FIX note). These span arm #17. ----
  #
  # AC4 — THE ALPHABET INVARIANT, and the reason this family must be derived rather than listed.
  # It is a SECURITY property, not tidiness: `_login_kw`'s arms are the only code that pattern-
  # matches against raw stderr, and stderr can contain a pull token. So an arm literal containing a
  # character OUTSIDE the credential alphabet — a space, a hyphen, a slash — is STRUCTURALLY
  # incapable of occurring inside a credential, and therefore incapable of firing on one. `kw` then
  # carries zero bits about token content, by construction rather than by review.
  # A future arm like `*'abc123'*` would silently break that: it could match INSIDE a token, and
  # `kw` would leak one bit per such arm. No hand-written member list can guard arm #17 — only a
  # derivation from the body can. This is exactly why (b) is derived and (a) is not.
  #
  # THE ALPHABET IS `[A-Za-z0-9_]`, AND THE UNDERSCORE IS LOAD-BEARING — do not "tidy" it out.
  # zot alone would justify the narrower `[A-Za-z0-9]` (`zot-registry.tf` › `random_password.zot_pull`
  # is `length = 40`, `special = false` — verified, not assumed). But BOTH GHCR PAT formats carry an
  # underscore (`ghp_…`, `github_pat_…`), so under the narrower alphabet an arm literal like
  # `*'_pat_1'*` reads as "safe" while matching INSIDE a PAT — measured at ~5.9 bits about the PAT
  # body's first character, passing the invariant. The union is the only sound choice while either
  # credential can reach this function. (This is the same unverified-GHCR-claim the `_login_hatch`
  # header explicitly warns against — "Do NOT restate 40 for GHCR: the repo disagrees with itself" —
  # arriving in a test comment instead. The security property must hold under EITHER PAT format.)
  #
  # Anchored on the `case` MATCH FORM (`*'…'*`), never a bare token, so prose in a comment cannot
  # inject a member (`cq-assert-anchor-not-bare-token`).
  T20_LITERALS="$(printf '%s\n' "$KW_BODY" | grep -vE '^[[:space:]]*#' | sed 's/#.*$//' | grep -oE "\*'[^']+'\*" | sed "s/^\*'//; s/'\*$//")"
  T20_LIT_N="$(printf '%s\n' "$T20_LITERALS" | grep -c .)"
  # Minimum-cardinality guard: an extraction that silently returned zero would make every
  # invariant below VACUOUS — the empty-source trap this file's own bash gates warn about. 16 =
  # 7 measured + 6 inferred errno + 3 falsified.
  if [[ "$T20_LIT_N" -lt 16 ]]; then
    T20_BAD="${T20_BAD}\n    arm-literal extraction returned ${T20_LIT_N} (expected >=16: 7 measured + 6 errno + 3 falsified) — the invariants below would be vacuous"
  fi
  while IFS= read -r _lit; do
    [[ -z "$_lit" ]] && continue
    # (i) AC4: must contain a character outside the credential alphabet, so it cannot match
    # credential content. See the underscore note above.
    if [[ ! "$_lit" =~ [^A-Za-z0-9_] ]]; then
      T20_BAD="${T20_BAD}\n    ALPHABET VIOLATION: arm literal '${_lit}' is pure [A-Za-z0-9_] — it could match INSIDE a pull token or a GHCR PAT, making kw a credential oracle"
    fi
  done <<< "$T20_LITERALS"
  # (ii) The emitted TOKEN vocabulary stays closed-form: comma-terminated lowercase. A future arm
  # emitting `Enomem,` or `enomem:` breaks the `^([a-z]+,)*$` oracle that T-5B-16's fuzz and this
  # test both rely on. Derived for the same arm-#17 reason.
  T20_VOCAB="$(printf '%s\n' "$KW_BODY" | grep -vE '^[[:space:]]*#' | sed 's/#.*$//' | grep -oE "printf '[a-zA-Z]+,'" | grep -oE "'[a-zA-Z]+,'" | tr -d "',")"
  T20_VOCAB_N="$(printf '%s\n' "$T20_VOCAB" | grep -c .)"
  if [[ "$T20_VOCAB_N" -lt 16 ]]; then
    T20_BAD="${T20_BAD}\n    kw token extraction returned ${T20_VOCAB_N} members (expected >=16)"
  fi
  # (iii) SHARP EDGE #1, CLOSED HERE — the errno literals must be LOWERCASE.
  # Scoped to the INFERRED errno block on purpose: a file-wide "every literal is lowercase" is
  # UNSHIPPABLE, because main's own arms carry `non-TTY device` and `Cannot connect to the Docker
  # daemon`. The plan asserted the file-wide form and claimed it "closes" the capitalized-copy
  # class; it does not, and the residual was measurably OPEN — `Cannot allocate memory` (the C
  # `strerror(3)` rendering, which is what issue 6565's own analysis quotes) passes the alphabet
  # check (it contains spaces) and never reaches the token check (that reads `printf` tokens, not
  # literals). So the one arm most likely to be copied from the issue text was unguarded.
  # Go renders errno strings LOWERCASE (`syscall.Errno.Error()`, measured); C `strerror`
  # capitalizes. A capitalized arm never matches Go-produced docker stderr — it is a silent dead
  # probe, exactly the "confidently-wrong arm" the hatch's header says `kw` exists to expose.
  # Derived from the block, not from T20_PAIRS, so it spans the SEVENTH errno arm too.
  T20_ERRNO_LITS="$(printf '%s\n' "$KW_BODY" | awk '/--- INFERRED/{f=1;next} /--- FALSIFIED/{f=0} f' \
    | grep -vE '^[[:space:]]*#' | sed 's/#.*$//' | grep -oE "\*'[^']+'\*" | sed "s/^\*'//; s/'\*$//")"
  T20_ERRNO_N="$(printf '%s\n' "$T20_ERRNO_LITS" | grep -c .)"
  if [[ "$T20_ERRNO_N" -lt 6 ]]; then
    T20_BAD="${T20_BAD}\n    INFERRED-block extraction returned ${T20_ERRNO_N} errno literal(s) (expected >=6) — the lowercase invariant below would be vacuous; did the '--- INFERRED' / '--- FALSIFIED' markers move?"
  fi
  while IFS= read -r _elit; do
    [[ -z "$_elit" ]] && continue
    if [[ "$_elit" =~ [A-Z] ]]; then
      T20_BAD="${T20_BAD}\n    SHARP EDGE #1: errno literal '${_elit}' contains an uppercase char — Go renders errno strings lowercase, so this arm can NEVER match real docker stderr (a silent dead probe). Did it get copied from a C strerror(3) table?"
    fi
  done <<< "$T20_ERRNO_LITS"
  # (iv) *** THE CROSS-CHECK THAT MAKES (i) NON-FAIL-OPEN. Do not remove it as redundant. ***
  # (i) is only as good as its extraction, and the extraction is faithful ONLY to the single-quoted
  # `case` arm (`*'…'*`). Three ordinary shapes EVADE it — MEASURED, each with a live credential
  # oracle installed and (i) reporting GREEN:
  #     case "${1:-}" in *"abc123"*) printf 'dq,' ;; esac      -> evades (double-quoted)
  #     case "${1:-}" in *abc123*)   printf 'unq,' ;; esac     -> evades (unquoted)
  #     [[ "${1:-}" == *abc123* ]] && printf 'br,'             -> evades ([[ ]] instead of case)
  # Against the unquoted mutant: `kw='unq,'` when the token contained `abc123` and `kw=''` when it
  # did not — one bit of TOKEN CONTENT shipped to Better Stack unscrubbed. The `>=16` cardinality
  # guard cannot catch it (the count stays 16).
  # The fix needs no new extraction to maintain, because the test ALREADY HELD the evidence and was
  # not looking at it: in all three mutations the VOCAB extraction counted 17 while the LITERAL
  # extraction counted 16 — the derivation saw the arm; only (i) was blind to it.
  # So: every EMITTING arm must contribute at least one extracted MATCH-FORM. A shape (i) cannot
  # read shows up here as a token with no literal behind it. Verified not to false-positive on a
  # legitimate `|`-alternation arm (which yields 2 literals for 1 token: 18 >= 17, green).
  if [[ "$T20_LIT_N" -lt "$T20_VOCAB_N" ]]; then
    T20_BAD="${T20_BAD}\n    AC4 FAIL-OPEN: ${T20_VOCAB_N} emitting arm(s) but only ${T20_LIT_N} readable match-form(s) — at least one arm uses a shape the alphabet check CANNOT read (double-quoted / unquoted / [[ ]]), so it is UNGUARDED and may match inside a credential. Write the arm as case \"\${1:-}\" in *'literal'*) or extend the extraction."
  fi
  while IFS= read -r _member; do
    [[ -z "$_member" ]] && continue
    if ! [[ "$_member" =~ ^[a-z]+$ ]]; then
      T20_BAD="${T20_BAD}\n    kw token '${_member}' is not lowercase-alpha — breaks the closed-form oracle"
    fi
  done <<< "$T20_VOCAB"
  if [[ -z "$T20_BAD" ]]; then
    PASS=$((PASS + 1))
    # Word this precisely: the lowercase claims cover the emitted TOKENS (all 16) and the INFERRED
    # errno LITERALS (6) — NOT every arm literal (main's own `non-TTY device` / `Cannot connect …`
    # are legitimately capitalized). A looser PASS string makes the green CI log a third artifact
    # asserting an invariant that does not exist.
    echo "  PASS: all ${T20_N} errno arms fire with their own token; ${T20_VOCAB_N} kw TOKENS closed + lowercase; ${T20_ERRNO_N} INFERRED errno LITERALS lowercase (Sharp Edge #1); every arm literal outside [A-Za-z0-9_] (AC4) and readable by the alphabet check"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: errno arm / kw vocabulary drift:"
    printf "%b\n" "$T20_BAD"
  fi
fi
rm -f "$T20_LIB"

# T-5B-21 (#6565, D7): `errno_chars` — the field that bounds ALL ~130 errnos in ONE round.
#
# WHY THIS FIELD EXISTS, in one measurement: the six arms above answer only "is it ENOMEM?".
# Under the round's own 22-char arithmetic ONLY ENOMEM fits (measured: ENOMEM 22, EPERM 23,
# EROFS 21, EIO 18, EINVAL 16, ENOENT 25), so the other five fire only if the premise is WRONG —
# and if it is wrong, six guesses cover ~5% of ~130 errnos. `errno_chars` tests the premise
# instead of assuming it.
#
# THE PROPERTY THAT MAKES IT WORTH TWO LINES (measured at /work, not reasoned): `errno_chars` is
# INVARIANT under docker's uint32 temp suffix. The observed `stderr_chars` was 96 on zot and 97 on
# ghcr, and it took arithmetic to conclude those were the IDENTICAL error with a 9- vs 10-digit
# suffix. `errno_chars` reports 22 for BOTH. It skips the inference the round was built to make.
#
# NO-ECHO: this is a LENGTH, exactly like `stderr_chars` beside it — never content. The residual
# argument is RE-CONFIRMED here, not inherited from `stderr_chars` (D7 narrows the segment, so
# inheriting would be unearned): a fixed-length token substituted into the final colon segment
# yields a CONSTANT length regardless of its value, so the channel carries zero bits about token
# content — the property turns on fixed-ness, not on any particular number. A username landing in
# that segment costs `len(username)`, which is the SAME already-accepted residual `stderr_chars`
# carries (`ci-deploy.sh` › `_login_hatch` header: a declared non-secret constant / the public
# package owner). The narrowing does not create a new channel.
echo "--- #6565 T-5B-21: errno_chars is emitted, and is invariant under docker's uint32 temp suffix ---"
TOTAL=$((TOTAL + 1))
T21_BAD=""
# Source the REAL hatch body (with its emitter dependencies), same technique and same rationale as
# T-5B-16: `_login_hatch` is pure `case`/`printf` plus a `|| true`-guarded `docker --version`, so
# the extracted body IS the SUT — and driving a full deploy per fixture costs minutes each.
T21_LIB=$(mktemp)
HATCH_BODY="$(awk '/^_login_hatch\(\) \{/,/^\}/' "$DEPLOY_SCRIPT")"
{ printf '%s\n' "$KW_BODY"; printf '%s\n' "$TOK_BODY"; printf '%s\n' "$HATCH_BODY"; } > "$T21_LIB"
# shellcheck disable=SC1090
source "$T21_LIB"
if [[ -z "$HATCH_BODY" ]] || ! declare -F _login_hatch >/dev/null; then
  T21_BAD="${T21_BAD}\n    could not source the real _login_hatch (fixture error, not a code defect)"
fi
# The EXACT observed production shape, at both measured suffix widths (9 and 10 digits; 11 is
# impossible for a uint32). These reproduce stderr_chars 96 and 97 — the two live datums.
T21_E9="error saving credentials: open /home/deploy/.docker/config.json123456789: cannot allocate memory"
T21_E10="error saving credentials: open /home/deploy/.docker/config.json1234567890: cannot allocate memory"
T21_H9="$( ( _login_hatch "$T21_E9" 0 1 ) || true )"
T21_H10="$( ( _login_hatch "$T21_E10" 0 1 ) || true )"
# The field must exist at all.
case "$T21_H9" in
  *errno_chars=*) : ;;
  *) T21_BAD="${T21_BAD}\n    errno_chars absent from the hatch emit: '${T21_H9}'" ;;
esac
_t21_field() { printf '%s' "$1" | grep -oE 'errno_chars=[0-9]+' | cut -d= -f2; }
T21_N9="$(_t21_field "$T21_H9")"
T21_N10="$(_t21_field "$T21_H10")"
# Pin the two live datums: the shapes must reproduce the OBSERVED stderr_chars, or the fixture has
# drifted from production and every conclusion below is about a different string.
case "$T21_H9"  in *'stderr_chars=96 '*) : ;; *) T21_BAD="${T21_BAD}\n    9-digit fixture no longer reproduces the observed stderr_chars=96" ;; esac
case "$T21_H10" in *'stderr_chars=97 '*) : ;; *) T21_BAD="${T21_BAD}\n    10-digit fixture no longer reproduces the observed stderr_chars=97" ;; esac
# THE POINT: same errno, different suffix width -> stderr_chars MOVES (96 vs 97), errno_chars does NOT.
if [[ "$T21_N9" != "22" ]]; then
  T21_BAD="${T21_BAD}\n    errno_chars=${T21_N9:-<empty>} for the 9-digit shape; expected 22 (measured len('cannot allocate memory'))"
fi
if [[ "$T21_N9" != "$T21_N10" ]]; then
  T21_BAD="${T21_BAD}\n    errno_chars NOT invariant under the temp suffix: 9-digit=${T21_N9:-<empty>} 10-digit=${T21_N10:-<empty>} (this invariance IS the field's reason to exist)"
fi
# Degenerate input: no ': ' anywhere -> the segment is the whole string, so errno_chars ==
# stderr_chars. Not a defect; it is how "there was no colon segment" reports itself.
T21_HND="$( ( _login_hatch "unauthorized" 0 1 ) || true )"
if ! [[ "$T21_HND" == *'stderr_chars=12 '* && "$T21_HND" == *'errno_chars=12'* ]]; then
  T21_BAD="${T21_BAD}\n    no-colon input should render errno_chars == stderr_chars (12); got: '${T21_HND}'"
fi
# Empty stderr -> 0, and must not abort.
T21_HE="$( ( _login_hatch "" 0 1 ) || true )"
case "$T21_HE" in *'errno_chars=0'*) : ;; *) T21_BAD="${T21_BAD}\n    empty stderr should render errno_chars=0; got: '${T21_HE}'" ;; esac
# NO-ECHO, behaviourally: a canary in the final colon segment must move only the INTEGER, never
# appear in the emit. This is the assertion that would catch a `%s`-splice regression of the field.
T21_CANARY="dckr_pat_""DDDDDDDDDDDDDDDDDDDDDDDDDDD"
T21_HC="$( ( _login_hatch "error saving credentials: open /x: ${T21_CANARY}" 0 1 ) || true )"
case "$T21_HC" in
  *"$T21_CANARY"*) T21_BAD="${T21_BAD}\n    LEAK: the hatch echoed the final-segment canary: '${T21_HC}'" ;;
esac
# *** THE POSITIVE CONTROL — and the assertion that kills the hardcode. Do not drop either half. ***
# Two jobs in one line:
#  (1) The canary check above is ABSENCE-ONLY, and an absence-only assertion is vacuous without a
#      positive control: if `_login_hatch` ever aborted, `$T21_HC` would be EMPTY, the canary
#      "wouldn't be there", and it would PASS while measuring nothing.
#  (2) It falsifies a hardcode. MEASURED: every other assertion in this test is satisfied by
#          _errseg="${_e:$(( ${#_e} > 22 ? ${#_e}-22 : 0 ))}"      # i.e. "always 22"
#      which reports 22 for EVERY errno — eperm 23, erofs 21, eio 18, einval 16, enoent 25 all
#      become 22. The field whose entire purpose is "bounds ALL ~130 errnos in ONE round" collapses
#      to a constant, and the test that exists to prove it stays green. Root cause: everything above
#      feeds exactly ONE errno (22 chars), so 22 is indistinguishable from a constant.
#      This fixture's final segment is 36 chars, so it separates them: real -> 36, hardcode -> 22.
# (The naive `${_e: -22}` hardcode is already killed by the no-colon=12 case above — bash does not
# clamp negative offsets, so it yields 0, not 12. That degenerate case is doing real work; keep it.)
T21_SEGLEN="${#T21_CANARY}"
case "$T21_HC" in
  *"errno_chars=${T21_SEGLEN} "*|*"errno_chars=${T21_SEGLEN}") : ;;
  *) T21_BAD="${T21_BAD}\n    errno_chars is not tracking the segment: expected ${T21_SEGLEN} for a ${T21_SEGLEN}-char final segment, got '${T21_HC}'. If this reads 22, errno_chars is HARDCODED/clamped rather than measured — the field is then a constant, not a bound on the errno set." ;;
esac
# Length-fidelity across the WHOLE measured set, not one sample. The six lengths are the SUT's own
# comment's claim (`ci-deploy.sh` › `_login_kw`: enomem 22, eperm 23, erofs 21, eio 18, einval 16,
# enoent 25 — Go 1.21.6 `syscall.Errno.Error()`); this is what makes that claim checkable rather
# than decorative, and it is what a one-errno oracle structurally cannot do.
for _el in "cannot allocate memory|22" "operation not permitted|23" "read-only file system|21" \
           "input/output error|18" "invalid argument|16" "no such file or directory|25"; do
  _elit="${_el%|*}"; _elen="${_el##*|}"
  _eh="$( ( _login_hatch "error saving credentials: open /home/deploy/.docker/config.json123456789: ${_elit}" 0 1 ) || true )"
  case "$_eh" in
    *"errno_chars=${_elen} "*) : ;;
    *) T21_BAD="${T21_BAD}\n    errno_chars wrong for '${_elit}': expected ${_elen} (measured via go1.21.6 syscall.Errno.Error()), got '${_eh}'" ;;
  esac
done
if [[ -z "$T21_BAD" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: errno_chars=22 for both live datums (stderr_chars 96 AND 97) — invariant under the uint32 suffix, no echo"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: errno_chars drift:"
  printf "%b\n" "$T21_BAD"
fi
rm -f "$T21_LIB"

# Restore strict mode for the summary/exit.
set -e -o pipefail

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
