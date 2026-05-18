#!/usr/bin/env bash
set -euo pipefail
# Job control (#3704). Isolates backgrounded jobs (the canary probe loop's
# parallel curl `&` + wait $!) into their own process groups so a stray
# PGID-targeted signal — e.g., a future operator running
# `kill -TERM -<bash_pid>` to clean up — does not also propagate into bash's
# own PGID (which it inherits from webhook.service: webhook fork-execs this
# script without setpgid). NOT load-bearing for the TERM trap below: the
# trap uses `pkill -TERM -P $$` (PPID-based), which is independent of job
# control. set -m is defense-in-depth, not the kill primitive.
set -m

# Deploy script invoked by the webhook listener (adnanh/webhook).
# The webhook sets SSH_ORIGINAL_COMMAND from the JSON payload's "command" field.
# Parses it for structured "deploy <component> <image> <tag>" format.
#
# State file protocol and reason taxonomy:
#   plugins/soleur/skills/postmerge/references/deploy-status-debugging.md
#
# Deploy state file exit_code protocol (#2205):
#   0   success
#   >0  explicit failure (see reason field)
#   -1  ci-deploy.sh is still running (EXIT_RUNNING)
#   -2  no state file exists (cat-deploy-state.sh fallback; EXIT_NO_PRIOR)
#   -3  corrupt/unparseable state (cat-deploy-state.sh future; EXIT_CORRUPT)

readonly LOG_TAG="ci-deploy"

# Sentinel exit codes persisted in STATE_FILE. Consumed by cat-deploy-state.sh
# and the GitHub Actions "Verify deploy script completion" step. Keep in sync
# with the case statement in .github/workflows/web-platform-release.yml.
readonly EXIT_RUNNING=-1
readonly EXIT_NO_PRIOR=-2

# Minimum free disk space required before starting a deploy (image pull +
# extraction headroom). 5GB expressed in KB to match `df --output=avail`.
readonly MIN_DISK_KB=$((5 * 1024 * 1024))  # 5GB for image pull + extraction

# Plugin bind-mount target. Test harness overrides via env so the seed block
# writes under a tmpdir instead of /mnt/data (which the GH runner cannot create).
PLUGIN_MOUNT_DIR="${PLUGIN_MOUNT_DIR:-/mnt/data/plugins/soleur}"

# -----------------------------------------------------------------------------
# Deploy state observability (#2185)
# -----------------------------------------------------------------------------
# adnanh/webhook returns success-http-response-code (202) the moment ci-deploy.sh
# is spawned, independent of our exit code. Silent failures (flock contention,
# Doppler transient, canary rollback) therefore produce 202 with no CI-visible
# signal. We persist structured state to /var/lock/ci-deploy.state so that the
# /hooks/deploy-status webhook endpoint (cat-deploy-state.sh) can surface it.
STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"
START_TS=$(date +%s)
# These are populated as the script parses SSH_ORIGINAL_COMMAND; surfaced in state.
COMPONENT=""
IMAGE=""
TAG=""

# write_state always returns 0 so a failure inside state-writing (e.g. disk-full)
# never converts an explicit failure reason into an "unhandled" trap on re-entry.
# Mktemp/mv themselves are logged to syslog if they fail, so the problem remains
# visible via journalctl -u webhook.
write_state() {
  local exit_code="$1"
  local reason="${2:-}"
  local tmp
  tmp=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || {
    logger -t "$LOG_TAG" "write_state: mktemp failed for STATE_FILE=$STATE_FILE"
    return 0
  }
  # start_ts: schema-stable, consumed by web-platform-release.yml elapsed
  # annotation (#3398). Do NOT rename without updating that workflow.
  printf '{"start_ts":%d,"end_ts":%d,"exit_code":%d,"component":"%s","image":"%s","tag":"%s","reason":"%s"}\n' \
    "$START_TS" "$(date +%s)" "$exit_code" "${COMPONENT:-}" "${IMAGE:-}" "${TAG:-}" "$reason" \
    > "$tmp" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: printf/redirect failed"
    rm -f "$tmp"
    return 0
  }
  mv "$tmp" "$STATE_FILE" 2>/dev/null || {
    logger -t "$LOG_TAG" "write_state: mv failed"
    rm -f "$tmp"
    return 0
  }
  return 0
}

# final_write_state records an explicit exit and touches a sentinel so the EXIT
# trap does not overwrite the reason with "unhandled". Use at every known failure
# or success exit.
#
# Sentinel is touched BEFORE write_state (issue #2199 fix 2): if SIGKILL lands
# between mv and touch, the EXIT trap would see no sentinel and overwrite the
# just-written explicit reason with "unhandled". Touching first means a kill
# mid-write leaves the sentinel + (possibly old) state rather than no sentinel
# + correct state -- the trap leaves the reason alone either way.
final_write_state() {
  touch "${STATE_FILE}.final" 2>/dev/null || true
  write_state "$1" "$2"
}

# Clear any stale sentinel from a prior SIGKILLed invocation (issue #2199 fix 3).
# Without this, a previous run killed between final_write_state and the EXIT
# trap's `rm -f` leaves the sentinel behind, causing this run's failure reason
# to be silently skipped by the "unhandled" guard below.
rm -f "${STATE_FILE}.final"

# On any non-zero exit that did not call final_write_state, record "unhandled".
# The sentinel file tells us whether an explicit reason was already written.
# We also clear the sentinel so a future run starts clean.
# shellcheck disable=SC2064
trap 'rc=$?; if [ "$rc" -ne 0 ] && [ ! -f "${STATE_FILE}.final" ]; then write_state "$rc" "unhandled"; fi; rm -f "${STATE_FILE}.final"' EXIT

# Wall-clock-induced kill (#3704). When ci-deploy-wrapper.sh hits its 900s
# timeout, it sends SIGTERM to this script. Without a TERM trap, bash dies on
# the default action and leaves the state file at "running" — the workflow
# polls -1 (running) until its own 900s ceiling and exits 1 with no terminal
# reason. With this trap:
#   1. `trap - TERM INT` clears the trap FIRST so a second SIGTERM (e.g.,
#      from the wrapper's --kill-after grace if the body races slow disk)
#      cannot re-enter the handler mid-write.
#   2. final_write_state touches the .final sentinel + writes terminal state
#      so the EXIT trap's "unhandled" branch is skipped, AND the workflow
#      sees exit_code=124 reason=timeout in the very next poll. The EXIT
#      trap WILL still fire after `exit 124` below; the .final sentinel is
#      what keeps it from overwriting reason=timeout with reason=unhandled.
#   3. `pkill -TERM -P $$` sends TERM to every direct child of this bash by
#      PPID (docker pull, docker exec, canary-bundle-claim-check.sh). We
#      use -P (PPID-based) instead of `kill -TERM 0` (PGID-based) because
#      ci-deploy.sh inherits its parent's PGID (webhook.service does not
#      setpgid before fork-exec), so kill 0 would also TERM the webhook
#      listener and cascade restart noise. Empirically verified via
#      parent.sh/child.sh repro before shipping.
#   4. `exit 124` matches GNU timeout(1)'s exit code on SIGTERM-by-timeout,
#      so the workflow's `*)` case statement parses an actionable failure
#      rather than the symptom-only `unhandled`.
#
# CAVEAT: bash defers TERM trap delivery while a foreground command is
# running (e.g., `docker pull` blocked on a network syscall). For the
# hung-foreground case, the wrapper's --kill-after=20s SIGKILL is the
# load-bearing fallback — bash dies, no trap fires, state stays "running",
# and the workflow's Pre-rerun lock probe degrades-permissive past it via
# the elapsed>900s branch. This trap covers the subset of hangs where bash
# IS able to dispatch the trap (between commands, in `wait`, in shell logic).
# shellcheck disable=SC2064
trap 'trap - TERM INT; final_write_state 124 "timeout"; pkill -TERM -P $$ 2>/dev/null || true; exit 124' TERM INT

# Structured error output: on failure, emit the failing line number and exit code.
# In async mode (include-command-output-in-response: false), stderr goes to syslog
# via journalctl -u webhook, not the HTTP response.
trap 'echo "DEPLOY_ERROR: ci-deploy.sh failed at line $LINENO (exit $?)" >&2' ERR

# Resolve env file: download secrets from Doppler to a temp file (chmod 600).
# Cleaned up automatically via EXIT trap after resolve_env_file. Exits on any failure -- no fallback.
resolve_env_file() {
  if ! command -v doppler >/dev/null 2>&1; then
    logger -t "$LOG_TAG" "FATAL: Doppler CLI not installed"
    echo "Error: Doppler CLI not installed on this server" >&2
    final_write_state 1 "doppler_unavailable"
    exit 1
  fi

  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
    logger -t "$LOG_TAG" "FATAL: DOPPLER_TOKEN not set"
    echo "Error: DOPPLER_TOKEN environment variable not set" >&2
    final_write_state 1 "doppler_token_missing"
    exit 1
  fi

  local tmpenv
  tmpenv=$(mktemp /tmp/doppler-env.XXXXXX)
  chmod 600 "$tmpenv"

  local doppler_output doppler_stderr_file
  doppler_stderr_file=$(mktemp /tmp/doppler-stderr.XXXXXX)
  if ! doppler_output=$(doppler secrets download --no-file --format docker --project soleur --config prd 2>"$doppler_stderr_file"); then
    local doppler_stderr
    doppler_stderr=$(cat "$doppler_stderr_file")
    logger -t "$LOG_TAG" "FATAL: Doppler secrets download failed: $doppler_stderr"
    rm -f "$tmpenv" "$doppler_stderr_file"
    echo "Error: Failed to download secrets from Doppler: $doppler_stderr" >&2
    final_write_state 1 "doppler_fetch_failed"
    exit 1
  fi
  rm -f "$doppler_stderr_file"

  echo "$doppler_output" > "$tmpenv"
  echo "$tmpenv"
  return 0
}

# Exact allowlist of valid images per component (not prefix match -- prevents suffix injection).
declare -A ALLOWED_IMAGES=(
  [web-platform]="ghcr.io/jikig-ai/soleur-web-platform"
  [inngest]="ghcr.io/jikig-ai/soleur-inngest-bootstrap"
)

# Log truncated command to avoid persisting attacker payloads to syslog
logger -t "$LOG_TAG" "SSH_ORIGINAL_COMMAND: ${SSH_ORIGINAL_COMMAND:0:200}"

if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: no command provided"
  echo "Error: no command provided" >&2
  final_write_state 1 "command_missing"
  exit 1
fi

# Validate field count (exactly 4 fields expected: deploy <component> <image> <tag>)
field_count=$(printf '%s\n' "$SSH_ORIGINAL_COMMAND" | wc -w)
if [[ "$field_count" -ne 4 ]]; then
  logger -t "$LOG_TAG" "REJECTED: expected 4 fields, got $field_count"
  echo "Error: malformed command (expected 4 fields, got $field_count)" >&2
  final_write_state 1 "command_malformed"
  exit 1
fi

# Parse command -- read -r prevents backslash interpretation in untrusted input
read -r ACTION COMPONENT IMAGE TAG <<< "$SSH_ORIGINAL_COMMAND"

# Validate action
if [[ "$ACTION" != "deploy" ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown action '$ACTION'"
  echo "Error: unknown action '$ACTION'" >&2
  final_write_state 1 "action_unknown"
  exit 1
fi

# Validate component exists in allowlist
if [[ -z "${ALLOWED_IMAGES[$COMPONENT]+x}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown component '$COMPONENT'"
  echo "Error: unknown component '$COMPONENT'" >&2
  final_write_state 1 "component_unknown"
  exit 1
fi

# Validate image matches exact expected value for this component
if [[ "$IMAGE" != "${ALLOWED_IMAGES[$COMPONENT]}" ]]; then
  logger -t "$LOG_TAG" "REJECTED: invalid image '$IMAGE' for component '$COMPONENT'"
  echo "Error: invalid image" >&2
  final_write_state 1 "image_mismatch"
  exit 1
fi

# Validate tag format (vX.Y.Z)
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  logger -t "$LOG_TAG" "REJECTED: invalid tag '$TAG'"
  echo "Error: invalid tag format" >&2
  final_write_state 1 "tag_malformed"
  exit 1
fi

logger -t "$LOG_TAG" "ACCEPTED: deploy $COMPONENT $IMAGE:$TAG"

# Serialize concurrent deploys (webhook may invoke ci-deploy.sh simultaneously).
# CI_DEPLOY_LOCK is overridable for testing; production uses /var/lock/ci-deploy.lock.
#
# FD-200 advisory flock: the lock is held by this bash process for the
# lifetime of the script. Release is implicit -- the kernel closes FD 200
# on process exit (any exit code, including SIGKILL). No manual `flock -u`
# path exists; loser writes reason="lock_contention" and exits non-zero.
# A "lock_contention" reason on a webhook retry therefore means the prior
# invocation is still in its critical section, NOT a release-path leak.
# See #3398 for the cascading-rerun pattern this serialization produces
# when the upstream poll ceiling is shorter than the realistic deploy
# window.
LOCK_FILE="${CI_DEPLOY_LOCK:-/var/lock/ci-deploy.lock}"
exec 200>"$LOCK_FILE"
flock -n 200 || {
  logger -t "$LOG_TAG" "REJECTED: another deploy in progress"
  echo "Error: another deploy in progress" >&2
  final_write_state 1 "lock_contention"
  exit 1
}

# Initial "running" state write (issue #2199 fix 1): deferred until AFTER flock
# acquisition and SSH_ORIGINAL_COMMAND parsing so COMPONENT/IMAGE/TAG are populated.
# Writing earlier produced an empty-tag "running" state, and a loser that failed
# flock -n would write "lock_contention" over the winner's in-progress state.
write_state "$EXIT_RUNNING" "running"

# Check available disk space (minimum 5GB required for image pull + extraction)
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [[ "$AVAIL_KB" -lt "$MIN_DISK_KB" ]]; then
  logger -t "$LOG_TAG" "REJECTED: insufficient disk space (${AVAIL_KB}KB available, ${MIN_DISK_KB}KB required)"
  echo "Error: insufficient disk space for deploy" >&2
  final_write_state 1 "insufficient_disk_space"
  exit 1
fi

# Component-specific deploy logic
case "$COMPONENT" in
  web-platform)
    echo "Pruning unused Docker images..."
    docker image prune -af
    docker pull "$IMAGE:$TAG"

    # Clean stale canary from previous failed deploy
    { docker stop soleur-web-platform-canary 2>/dev/null || true; }
    { docker rm soleur-web-platform-canary 2>/dev/null || true; }

    # Seed the read-only plugin bind-mount from the new image (#3045).
    # Source of truth: /opt/soleur/plugin in the image (vendored at build time).
    # Must run BEFORE the canary docker run so the canary itself sees populated
    # content on first read — the Layer 3 probe script lives in the same mount.
    # Uses an ephemeral container (`docker create` + `docker cp` + `docker rm`)
    # so we never run a second instance of the new image during the canary phase.
    # `docker cp src/. dst/` copies *contents* of src into dst (NOT src as a
    # child of dst); `find -mindepth 1 -delete` is a single POSIX-portable
    # cleanup form shared with cloud-init.yml — handles dotfiles like
    # `.claude-plugin/` correctly.
    echo "Seeding plugin mount from image..."
    # Pre-flight: a prior SIGKILLed deploy may have left this container behind.
    # `docker create --name` would otherwise fail with "container already exists".
    docker rm -f soleur-plugin-seed >/dev/null 2>&1 || true
    if ! docker create --name soleur-plugin-seed "$IMAGE:$TAG" >/dev/null; then
      final_write_state 1 "plugin_seed_create_failed"
      exit 1
    fi
    # Pre-create the mount dir so the sentinel write below cannot fail with
    # ENOENT in test harnesses that run with PLUGIN_MOUNT_DIR pointed at a
    # tmpdir. In production cloud-init.yml already creates /mnt/data/plugins/
    # soleur, so this is a no-op there.
    mkdir -p "$PLUGIN_MOUNT_DIR"
    find "$PLUGIN_MOUNT_DIR" -mindepth 1 -delete 2>/dev/null || true
    # Redirect cp stdout so it stays out of the docker-trace assertion stream
    # used by ci-deploy.test.sh (which greps DOCKER_TRACE:* from script stdout).
    # Stderr is preserved for journalctl debugging on real failures.
    if ! docker cp soleur-plugin-seed:/opt/soleur/plugin/. "$PLUGIN_MOUNT_DIR/" >/dev/null; then
      docker rm soleur-plugin-seed >/dev/null 2>&1 || true
      final_write_state 1 "plugin_seed_copy_failed"
      exit 1
    fi
    docker rm soleur-plugin-seed >/dev/null
    # Sentinel marker — written LAST so a SIGKILL mid-cp leaves the marker
    # absent. `verifyPluginMountOnce` checks for it to distinguish "manifest
    # extracted early but partial copy" from a healthy mount.
    printf '%s\n' "seeded $(date -u +%Y-%m-%dT%H:%M:%SZ) tag=$TAG" \
      > "$PLUGIN_MOUNT_DIR/.seed-complete"

    # Prepare environment (shared between canary and production)
    sudo chown 1001:1001 /mnt/data/workspaces
    ENV_FILE=$(resolve_env_file)
    # Chain the env-file cleanup with the existing state-writing EXIT trap.
    # Replacing the trap entirely would lose the "unhandled" reason capture.
    # shellcheck disable=SC2064
    trap 'rc=$?; rm -f "$ENV_FILE"; if [ "$rc" -ne 0 ] && [ ! -f "${STATE_FILE}.final" ]; then write_state "$rc" "unhandled"; fi; rm -f "${STATE_FILE}.final"' EXIT

    # Start canary on port 3001 (old container still serving on 80/3000)
    # Custom AppArmor profile: allows mount/umount/pivot_root for bwrap
    # while maintaining Docker's other security restrictions (#1570).
    # tmpfs /tmp (closes #2473): caps overlayfs COW write-amp from ~20 MB
    # pdf-linearize tempfiles and keeps /tmp ephemeral. Post-GIT_ASKPASS
    # migration (git-auth.ts), git no longer writes credential helpers
    # under /tmp — the askpass script lives in $HOME instead.
    docker run -d \
      --name soleur-web-platform-canary \
      --restart no \
      --security-opt apparmor=soleur-bwrap \
      --security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json \
      --tmpfs /tmp:rw,nosuid,nodev,size=256m \
      --env-file "$ENV_FILE" \
      -v /mnt/data/workspaces:/workspaces \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 0.0.0.0:3001:3000 \
      "$IMAGE:$TAG"

    # Layered canary probe set. Contract:
    #   knowledge-base/engineering/ops/runbooks/canary-probe-set.md
    readonly CANARY_HEALTH_HTTP="/tmp/canary-health-http"
    readonly CANARY_LOGIN_HTTP="/tmp/canary-login-http"
    readonly CANARY_LOGIN_BODY="/tmp/canary-login-body.html"
    readonly CANARY_DASH_HTTP="/tmp/canary-dash-http"
    readonly CANARY_DASH_BODY="/tmp/canary-dash-body.html"
    # Structured marker emitted by `components/error-boundary-view.tsx`.
    # Stable across copy edits — replaces the brittle "An unexpected error
    # occurred" sentinel which only renders when `error.digest` is falsy.
    readonly CANARY_ERROR_BOUNDARY_MARKER='data-error-boundary='
    # CANARY_LAYER_3_SCRIPT is env-overridable so tests can inject a mock.
    # Shipped to /usr/local/bin via terraform_data.deploy_pipeline_fix
    # (existing servers) and cloud-init write_files (fresh servers); the host
    # path mirrors ci-deploy.sh and cat-deploy-state.sh. The previous default
    # under /app/shared/apps/... never resolved because the canary container
    # only mounts /mnt/data/plugins/soleur, not /mnt/data/apps (#3033).
    CANARY_LAYER_3_SCRIPT="${CANARY_LAYER_3_SCRIPT:-/usr/local/bin/canary-bundle-claim-check.sh}"

    rm -f "$CANARY_HEALTH_HTTP" "$CANARY_LOGIN_HTTP" "$CANARY_LOGIN_BODY" \
          "$CANARY_DASH_HTTP" "$CANARY_DASH_BODY"

    echo "Waiting for canary health check..."
    CANARY_HEALTHY=false
    CANARY_FAIL_REASON="canary_health_failed"
    for i in $(seq 1 10); do
      # Probe /health, /login, /dashboard in parallel — caps per-iteration
      # wall-clock to ~max(--max-time) instead of 3× sequentially. The probes
      # have no ordering dependency: each writes to its own files and the
      # post-wait checks are pure reads.
      curl -s --max-time 5 -o /dev/null -w '%{http_code}' \
        http://localhost:3001/health > "$CANARY_HEALTH_HTTP" 2>/dev/null &
      H_PID=$!
      curl -s --max-time 5 -o "$CANARY_LOGIN_BODY" \
        -w '%{http_code}' http://localhost:3001/login > "$CANARY_LOGIN_HTTP" 2>/dev/null &
      L_PID=$!
      curl -s --max-time 5 --max-redirs 0 -o "$CANARY_DASH_BODY" \
        -w '%{http_code}' http://localhost:3001/dashboard > "$CANARY_DASH_HTTP" 2>/dev/null &
      D_PID=$!
      wait "$H_PID" "$L_PID" "$D_PID" 2>/dev/null || true

      HEALTH_HTTP=$(cat "$CANARY_HEALTH_HTTP" 2>/dev/null || echo "000")
      if [[ "$HEALTH_HTTP" != "200" ]]; then
        CANARY_FAIL_REASON="canary_health_failed"
        sleep 3
        continue
      fi
      LOGIN_HTTP=$(cat "$CANARY_LOGIN_HTTP" 2>/dev/null || echo "000")
      if [[ "$LOGIN_HTTP" != "200" ]] || [[ ! -s "$CANARY_LOGIN_BODY" ]]; then
        CANARY_FAIL_REASON="canary_login_failed"
        sleep 3
        continue
      fi
      DASH_HTTP=$(cat "$CANARY_DASH_HTTP" 2>/dev/null || echo "000")
      if [[ ! "$DASH_HTTP" =~ ^(200|302|307)$ ]]; then
        CANARY_FAIL_REASON="canary_dashboard_5xx"
        sleep 3
        continue
      fi
      # Body-content rejection — server-component throws render the error
      # boundary into SSR HTML. The structured marker survives copy changes.
      if grep -qF "$CANARY_ERROR_BOUNDARY_MARKER" "$CANARY_LOGIN_BODY" 2>/dev/null \
        || grep -qF "$CANARY_ERROR_BOUNDARY_MARKER" "$CANARY_DASH_BODY" 2>/dev/null; then
        CANARY_FAIL_REASON="canary_error_boundary"
        sleep 3
        continue
      fi
      # Layer 3 — inlined-JWT bundle assertion. Catches client-only validator
      # throws that SSR HTML probing cannot detect (the #3007 regression class).
      # Shipped to /usr/local/bin via terraform_data.deploy_pipeline_fix and
      # cloud-init.write_files (#3033). Absence is a warning, not a hard fail
      # (canary host may predate the script ship).
      #
      # The script's stderr carries refined failure-reason strings
      # (canary_layer3_login_fetch_failed / canary_layer3_no_chunks /
      # canary_layer3_no_jwt / canary_layer3_jwt_decode_failed /
      # canary_layer3_jwt_claims). Pipe through `logger` so operators can
      # triage via `journalctl -u webhook -t ci-deploy | grep canary_layer3_`.
      # `set +o pipefail` is load-bearing — without it, the script-side fail
      # would propagate through the pipe and `set -euo` would abort ci-deploy
      # before the rc check runs. ${PIPESTATUS[0]} is the script's rc
      # regardless of logger's outcome.
      # CANARY_FAIL_REASON stays mapped to the umbrella "canary_layer3_jwt_claims"
      # for log-stability: the deploy-status workflow at
      # .github/workflows/web-platform-release.yml line 274 surfaces this string
      # via `::error::` and the umbrella keeps that line stable across deploys.
      # The `*)` catch-all in that workflow accepts any non-zero reason, so
      # the umbrella is for human-log stability, not a parser contract.
      # Granular reasons (canary_layer3_no_chunks / _no_jwt / _decode_failed /
      # _login_fetch_failed) are surfaced via journalctl through `logger -t`
      # for SSH-time triage. See #3033 follow-ups for promoting granular
      # reasons into the state file's reason field directly.
      if [[ -x "$CANARY_LAYER_3_SCRIPT" ]]; then
        set +o pipefail
        "$CANARY_LAYER_3_SCRIPT" http://localhost:3001 2>&1 | logger -t "$LOG_TAG" -p user.warning
        layer3_rc=${PIPESTATUS[0]}
        set -o pipefail
        if [[ "$layer3_rc" -ne 0 ]]; then
          CANARY_FAIL_REASON="canary_layer3_jwt_claims"
          sleep 3
          continue
        fi
      fi
      CANARY_HEALTHY=true
      echo " Canary OK (health/login/dashboard probes passed)"
      break
    done

    # Verify bwrap sandbox works inside canary (#1557).
    # If bwrap fails, the OS-level sandbox (Layer 1) is non-functional.
    if [[ "$CANARY_HEALTHY" == "true" ]]; then
      echo "Verifying bwrap sandbox..."
      if ! docker exec soleur-web-platform-canary bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true 2>&1; then
        echo "Canary sandbox check failed, rolling back..."
        logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: bwrap sandbox non-functional in $IMAGE:$TAG"
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        # ENV_FILE trap still runs to clean up the secrets file.
        final_write_state 1 "canary_sandbox_failed"
        exit 1
      fi
      echo "Sandbox OK"
    fi

    if [[ "$CANARY_HEALTHY" == "true" ]]; then
      # SUCCESS: swap canary to production
      echo "Canary passed, swapping to production..."
      { docker stop --time=12 soleur-web-platform 2>/dev/null || true; }
      { docker rm soleur-web-platform 2>/dev/null || true; }

      # ADR-027: pre-`docker run` single-replica assertion. The two docker
      # commands above use `|| true` to mask "container not found" on a
      # first-deploy host, but the same `|| true` would also mask a stop
      # failure that leaves the prior container running. Without this guard,
      # the docker run below would surface a cryptic "name already in use".
      # Here we surface the ADR-027 invariant by name so an operator knows
      # which doc to read.
      if docker ps --filter "name=^soleur-web-platform$" --format '{{.Names}}' | grep -q .; then
        echo "ERROR: soleur-web-platform container is still running after docker stop/rm." >&2
        echo "       Single-replica invariant (ADR-027) violated. See" >&2
        echo "       knowledge-base/engineering/architecture/decisions/ADR-027-process-local-state-for-runners.md" >&2
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        final_write_state 1 "adr027_prod_already_running"
        exit 1
      fi

      # tmpfs /tmp (closes #2473): see canary block above for rationale.
      # Post-GIT_ASKPASS migration, git auth is in $HOME (git-auth.ts) so
      # /tmp no longer needs to be exec-able for git credential helpers.
      if docker run -d \
        --name soleur-web-platform \
        --restart unless-stopped \
        --security-opt apparmor=soleur-bwrap \
        --security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json \
        --tmpfs /tmp:rw,nosuid,nodev,size=256m \
        --env-file "$ENV_FILE" \
        -v /mnt/data/workspaces:/workspaces \
        -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
        -p 0.0.0.0:80:3000 \
        -p 0.0.0.0:3000:3000 \
        "$IMAGE:$TAG"; then
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        echo "Deploy succeeded"
        final_write_state 0 "ok"
        exit 0
      else
        # Production start failed after canary success (infra issue, not app)
        logger -t "$LOG_TAG" "DEPLOY_ERROR: production container failed to start after canary passed"
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        final_write_state 1 "production_start_failed"
        exit 1
      fi
    else
      # ROLLBACK: canary failed, keep old container running
      echo "Canary health check failed, rolling back..."
      { docker logs soleur-web-platform-canary --tail 30 2>&1 || true; } | logger -t "$LOG_TAG"
      { docker stop soleur-web-platform-canary 2>/dev/null || true; }
      { docker rm soleur-web-platform-canary 2>/dev/null || true; }
      logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: canary failed for $IMAGE:$TAG (reason=$CANARY_FAIL_REASON), keeping previous version"
      final_write_state 1 "$CANARY_FAIL_REASON"
      exit 1
    fi
    ;;
  inngest)
    # Inngest server bootstrap (PR-F follow-up, #3960).
    #
    # No canary: inngest-server binds loopback only (127.0.0.1:8288/8289) so
    # there is no external traffic to shadow. The bootstrap script's
    # `systemctl is-active` + version-file check at /var/lib/inngest/version
    # provides idempotency; a second deploy of the same $TAG is a ~50ms no-op.
    #
    # Delivery model: the OCI image is a SHA-pinned content carrier. The
    # bootstrap script + the embedded INNGEST_CLI_VERSION / _SHA256 ENV vars
    # are extracted from the image and the script is executed ON THE HOST
    # (NOT inside the container). The container itself is Alpine + bash +
    # curl + tar + coreutils — it does not have `systemctl`, so running the
    # script inside it would fail at `systemctl daemon-reload`. The host has
    # systemd + the deploy user + the systemd unit paths the script writes.
    echo "Pulling Inngest bootstrap image $IMAGE:$TAG..."
    docker pull "$IMAGE:$TAG"

    # Extract the script + pinned ENV vars from the image.
    INNGEST_EXTRACT_DIR=$(mktemp -d /tmp/inngest-extract.XXXXXX)
    INNGEST_EXTRACT_CONTAINER="soleur-inngest-extract-$$"
    docker rm -f "$INNGEST_EXTRACT_CONTAINER" >/dev/null 2>&1 || true
    if ! docker create --name "$INNGEST_EXTRACT_CONTAINER" "$IMAGE:$TAG" >/dev/null; then
      logger -t "$LOG_TAG" "FAILED: docker create for inngest-bootstrap extract"
      rm -rf "$INNGEST_EXTRACT_DIR"
      final_write_state 1 "inngest_extract_create_failed"
      exit 1
    fi
    if ! docker cp "$INNGEST_EXTRACT_CONTAINER:/inngest-bootstrap.sh" "$INNGEST_EXTRACT_DIR/inngest-bootstrap.sh"; then
      docker rm "$INNGEST_EXTRACT_CONTAINER" >/dev/null 2>&1 || true
      rm -rf "$INNGEST_EXTRACT_DIR"
      final_write_state 1 "inngest_extract_copy_failed"
      exit 1
    fi
    # Read ENV vars baked into the image at build time (see
    # .github/workflows/build-inngest-bootstrap-image.yml — ENV
    # INNGEST_CLI_VERSION=... / INNGEST_CLI_SHA256=...).
    image_env=$(docker inspect "$IMAGE:$TAG" -f '{{range .Config.Env}}{{println .}}{{end}}')
    docker rm "$INNGEST_EXTRACT_CONTAINER" >/dev/null 2>&1 || true
    INNGEST_CLI_VERSION=$(printf '%s\n' "$image_env" | grep '^INNGEST_CLI_VERSION=' | cut -d= -f2-)
    INNGEST_CLI_SHA256=$(printf '%s\n' "$image_env" | grep '^INNGEST_CLI_SHA256=' | cut -d= -f2-)
    if [[ -z "$INNGEST_CLI_VERSION" || -z "$INNGEST_CLI_SHA256" ]]; then
      logger -t "$LOG_TAG" "FAILED: image missing INNGEST_CLI_{VERSION,SHA256} ENV"
      rm -rf "$INNGEST_EXTRACT_DIR"
      final_write_state 1 "inngest_image_env_missing"
      exit 1
    fi
    chmod +x "$INNGEST_EXTRACT_DIR/inngest-bootstrap.sh"

    echo "Running inngest-bootstrap.sh on host (version=$INNGEST_CLI_VERSION)..."
    # Execute on host. The script needs root to write /etc/systemd/system,
    # /usr/local/bin/inngest, /etc/default/inngest-server, and to invoke
    # systemctl. ci-deploy.sh itself runs as the `deploy` user with sudo
    # access (see webhook.service hardening). Use sudo with explicit env
    # passthrough so the script sees the pinned version/SHA.
    if ! sudo -E env \
        "INNGEST_CLI_VERSION=$INNGEST_CLI_VERSION" \
        "INNGEST_CLI_SHA256=$INNGEST_CLI_SHA256" \
        bash "$INNGEST_EXTRACT_DIR/inngest-bootstrap.sh"; then
      logger -t "$LOG_TAG" "FAILED: inngest-bootstrap.sh non-zero exit"
      rm -rf "$INNGEST_EXTRACT_DIR"
      final_write_state 1 "inngest_bootstrap_failed"
      exit 1
    fi

    rm -rf "$INNGEST_EXTRACT_DIR"
    logger -t "$LOG_TAG" "SUCCESS: inngest $IMAGE:$TAG deployed"
    final_write_state 0 "success"
    ;;
  *)
    logger -t "$LOG_TAG" "ERROR: no deploy handler for '$COMPONENT'"
    echo "Error: no deploy handler for '$COMPONENT'" >&2
    final_write_state 1 "no_handler"
    exit 1
    ;;
esac
