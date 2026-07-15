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

# Image signature verification (#5933 Item 4; #6005 private-GHCR + offline rework).
# The running host pulls the app image by semver tag (ALLOWED_IMAGES); this
# cosign-verifies its signature and runs the VERIFIED DIGEST (not the tag → closes
# the tag-repoint TOCTOU). WARN mode (default) emits a discriminating Sentry event
# on any failure but NEVER blocks the deploy; the WARN→ENFORCE flip is a soak-gated
# fast-follow after a signed release is confirmed live.
#
# The app image is now a PRIVATE GHCR package (#6005), so the host authenticates via
# a scoped `read:packages` credential (ghcr_prelude_and_login below) before pulling.
# The verifier is a SHA-pinned distroless cosign CONTAINER (no host install). Per
# ADR-087 (Design B′) it runs `--network host` so the OCI-attached signature fetch
# rides the host's UNRESTRICTED egress — the #5046/ADR-052 container egress firewall
# is `iifname docker0`-scoped and never sees host OUTPUT, so ghcr.io stays OUT of the
# container allowlist. Trust is a LOCALLY-PINNED `trusted_root.json` mounted :ro
# (cosign-trusted-root.json, delivered out-of-band via the baked HOST-image
# host-scripts set + a running-host SSH provisioner — NEVER baked into the DEPLOY
# image, which is the artifact under verification) with `--offline` so no live
# Fulcio/Rekor/TUF egress is needed. (`--offline` is deprecated-but-frozen under the
# pinned cosign SHA — SOLEUR-DEBT below ties migration to the next SHA bump.)
# Identity is pinned to the reusable release workflow on main/release-tags ONLY — an
# intra-repo branch/tag signature must NOT verify (a loose `refs/(heads|tags)/.+`
# would accept attacker-branch RCE).
readonly COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870" # v3.1.1
readonly COSIGN_IDENTITY_REGEXP='^https://github\.com/jikig-ai/soleur/\.github/workflows/reusable-release\.yml@(refs/heads/main|refs/tags/v[0-9].+)$'
readonly COSIGN_OIDC_ISSUER='https://token.actions.githubusercontent.com'
readonly IMAGE_VERIFY_MODE="${IMAGE_VERIFY_MODE:-warn}" # warn (default) | enforce (soak-gated fast-follow)
# SOLEUR-DEBT(#6005): cosign `--offline` is deprecated (removed in cosign v4). It is
# inert under the pinned SHA (v3.1.1). Upgrade trigger: the next COSIGN_IMAGE SHA
# bump — migrate to the `--bundle`+`--trusted-root` new-bundle-format path (verify
# it exists on the target version first; v3.1.1 `verify` has neither `--bundle` nor
# `--new-bundle-format`). See ADR-087.
# Host paths for the private-GHCR pull credential + the pinned offline trust root.
# Overridable in tests; default to the real deploy-host layout. The docker config is
# written by ghcr_prelude_and_login (host pull auth) and mounted :ro into the
# ephemeral cosign verifier — it MUST carry an inline `auths."ghcr.io".auth` entry,
# NEVER a credStore/credHelpers indirection (the distroless cosign image has no
# credential helper; an indirection silently UNAUTHORIZEs the .sig fetch — ADR-087).
# The trusted root reaches the host via the baked HOST-image host-scripts set (fresh
# hosts) + terraform_data.cosign_trusted_root SSH delivery (running host) — see
# server.tf. It is NEVER baked into the DEPLOY image (circular trust).
readonly GHCR_DOCKER_CONFIG="${GHCR_DOCKER_CONFIG:-/home/deploy/.docker/config.json}"
readonly COSIGN_TRUSTED_ROOT_HOST="${COSIGN_TRUSTED_ROOT_HOST:-/etc/soleur/cosign-trusted-root.json}"

# Self-hosted zot registry (#6122/ADR-096). The pull path prefers zot ONLY when it is
# confirmed-configured-and-live (see zot_gate_and_login) — a strict dark-launch: until
# the operator provisions (1.8) + backfills (1.9) zot, ZOT_REGISTRY_URL is absent in
# Doppler prd, ZOT_ACTIVE stays 0, and every pull takes the UNCHANGED private-GHCR path
# (wg-dark-launch-deploy-gates). zot serves plain HTTP on the private net (cosign digest-
# pinning is the integrity guard, not TLS — Phase-0 spike), so cosign verify of a
# zot-pulled digest needs --allow-insecure-registry (Edge B). ZOT_REGISTRY_URL is fetched
# from Doppler at runtime by zot_gate_and_login (test-overridable); it is NOT readonly.
ZOT_REGISTRY_URL="${ZOT_REGISTRY_URL:-}"           # e.g. 10.0.1.30:5000 (schemeless host:port); empty ⇒ zot disabled
ZOT_ACTIVE=0                                        # set to 1 by zot_gate_and_login iff /v2/ probe + pull login both succeed
readonly ZOT_PROBE_TIMEOUT="${ZOT_PROBE_TIMEOUT:-3}" # seconds for the /v2/ reachability probe

# Sentinel exit codes persisted in STATE_FILE. Consumed by cat-deploy-state.sh
# and the GitHub Actions "Verify deploy script completion" step. Keep in sync
# with the case statement in .github/workflows/web-platform-release.yml.
readonly EXIT_RUNNING=-1
readonly EXIT_NO_PRIOR=-2

# Minimum free disk space required before starting a deploy (image pull +
# extraction headroom). 5GB expressed in KB to match `df --output=avail`.
readonly MIN_DISK_KB=$((5 * 1024 * 1024))  # 5GB for image pull + extraction

# Container memory caps (#5417). The prod container ran with NO --memory cap on
# an 8GB cx33: heavy concurrent Claude-eval crons drove HOST RAM pressure → the
# HOST kernel OOM-killed an arbitrary victim (possibly dockerd / inngest-server
# / the firewall resolver, NOT necessarily the Node process) → --restart
# unless-stopped churned the container ~10-60x/day, killing in-flight crons and
# flushing the DOCKER-USER egress jump. Capping --memory converts that into a
# DETERMINISTIC cgroup-OOM that kills only this container, sparing the rest of
# the host. Derivation + sizing rationale in ADR-062 and the #5417 plan (AC1).
#
# The cap is a STARTING value bounded by the deploy-window constraint
# (canary + prod run concurrently): CANARY_MEMORY_CAP + PROD_MEMORY_CAP +
# host_overhead must stay under 8GB. The container-restart-monitor's cgroup-OOM
# classification is the post-merge feedback signal to RAISE PROD_MEMORY_CAP if a
# legitimate concurrent-cron peak exceeds it (the AC2 cap-too-low regression).
# All three are env-overridable so that tuning is a Doppler/deploy-env change,
# not a code edit. --memory-swap == --memory disables swap growth (cloud-init
# configures no swap). PROD_NODE_MAX_OLD_SPACE_MB is set BELOW the cgroup cap so
# V8 hits a clean heap-exhaustion error before the opaque cgroup SIGKILL.
readonly PROD_MEMORY_CAP="${PROD_MEMORY_CAP:-4096m}"
readonly CANARY_MEMORY_CAP="${CANARY_MEMORY_CAP:-1536m}"
readonly PROD_NODE_MAX_OLD_SPACE_MB="${PROD_NODE_MAX_OLD_SPACE_MB:-3072}"
# The canary fires no crons (it only serves the deploy probe set), so its heap
# ceiling is well below its 1536m cgroup cap — set so a canary OOM is a clean V8
# error, not an opaque cgroup SIGKILL that fails the deploy with a cryptic signal.
readonly CANARY_NODE_MAX_OLD_SPACE_MB="${CANARY_NODE_MAX_OLD_SPACE_MB:-1152}"

# Plugin bind-mount target. Test harness overrides via env so the seed block
# writes under a tmpdir instead of /mnt/data (which the GH runner cannot create).
PLUGIN_MOUNT_DIR="${PLUGIN_MOUNT_DIR:-/mnt/data/plugins/soleur}"

# -----------------------------------------------------------------------------
# Host identity (#5274 Phase 3, ADR-068)
# -----------------------------------------------------------------------------
# Each web host injects its OWN stable infra id into the container as
# SOLEUR_HOST_ID — the per-user worktree write-lease's placement authority
# (host-identity.ts:resolveHostId, which fail-loud-THROWS in prod when the git-data
# flag is on and this is unset). Resolved ON-HOST from the Hetzner metadata service
# (the hcloud_server id — the SAME value terraform knows), with /etc/machine-id as
# a reboot-stable fallback; NEVER a per-container hostname (that would self-lock
# each recreate-deploy out of its own worktree). Best-effort: at flag-off the
# container never calls resolveHostId(), so an empty value is harmless; when 3.D
# flips the flag an unresolvable id fails the canary loud (the intended posture).
# Test harness overrides via SOLEUR_HOST_ID_METADATA_URL / SOLEUR_HOST_ID_OVERRIDE.
resolve_host_id() {
  if [[ -n "${SOLEUR_HOST_ID_OVERRIDE:-}" ]]; then
    printf '%s' "$SOLEUR_HOST_ID_OVERRIDE"
    return 0
  fi
  local url="${SOLEUR_HOST_ID_METADATA_URL:-http://169.254.169.254/hetzner/v1/metadata/instance-id}"
  local id
  id=$(curl -sf --max-time 3 "$url" 2>/dev/null || true)
  if [[ "$id" =~ ^[0-9]+$ ]]; then
    printf 'hetzner-%s' "$id"
    return 0
  fi
  id=$(tr -d '[:space:]' < /etc/machine-id 2>/dev/null || true)
  if [[ -n "$id" ]]; then
    printf 'machine-%s' "$id"
    return 0
  fi
  return 1
}
HOST_ID="$(resolve_host_id || true)"
readonly HOST_ID

# 2-host deploy fan-out (#5274 Phase 3, ADR-068 "deploy fan-out" amendment).
# After the receiving host's OWN prod swap succeeds, forward the SAME deploy to
# every PEER web host over the private net, so one webhook trigger delivers the
# container to BOTH hosts. DORMANT at the single-host state: SOLEUR_DEPLOY_PEERS is
# unset (the /hooks/deploy payload omits it until the release workflow renders the
# peer list) or lists only this host → no-op → the deploy path is byte-identical to
# pre-#5274. Loop-prevention: peers receive on /hooks/deploy-peer, which does NOT
# pass SOLEUR_DEPLOY_PEERS, so a peer never re-fans (A→B never triggers B→A).
# Re-signs with the SHARED webhook_deploy_secret read from hooks.json (root:deploy
# 0640; ci-deploy runs as the deploy user) — no new secret. Fire-and-forget like
# /hooks/deploy: a 202 means the peer ACCEPTED the trigger; per-host deploy SUCCESS
# is soak-verified via the peer's deploy-status over the private net (AC5). Returns
# non-zero if ANY peer forward was not accepted (folded into the deploy-status reason
# so the release workflow surfaces "web-1 ok, web-2 down" without SSH).
fan_out_to_peers() {
  local peers_csv="${SOLEUR_DEPLOY_PEERS:-}"
  [[ -n "$peers_csv" ]] || return 0

  local self_ips
  self_ips=" $(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ') "

  local hooks_file="${SOLEUR_HOOKS_JSON:-/etc/webhook/hooks.json}"
  local secret
  secret=$(jq -r '.[] | select(.id=="deploy-peer") | .["trigger-rule"].match.secret' \
    "$hooks_file" 2>/dev/null || true)
  if [[ -z "$secret" || "$secret" == "null" ]]; then
    logger -t "$LOG_TAG" "FANOUT: webhook secret unavailable ($hooks_file) — cannot forward to peers"
    return 1
  fi

  local payload sig
  payload=$(jq -cn --arg cmd "${SSH_ORIGINAL_COMMAND:-}" '{command:$cmd}')
  sig=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/.*= //')

  local rc=0 peer code _peer_arr
  IFS=',' read -ra _peer_arr <<< "$peers_csv"
  for peer in "${_peer_arr[@]}"; do
    peer="${peer//[[:space:]]/}"
    [[ -n "$peer" ]] || continue
    [[ "$self_ips" == *" $peer "* ]] && continue # never forward to self
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
      -X POST "http://${peer}:9000/hooks/deploy-peer" \
      -H "Content-Type: application/json" \
      -H "X-Signature-256: sha256=${sig}" \
      --data-binary "$payload" 2>/dev/null || echo "000")
    if [[ "$code" == "202" ]]; then
      logger -t "$LOG_TAG" "FANOUT: peer $peer accepted deploy (HTTP $code)"
    else
      logger -t "$LOG_TAG" "FANOUT: peer $peer NOT accepted (HTTP $code) — deploy-status will surface per-host state"
      rc=1
    fi
  done
  return "$rc"
}

# -----------------------------------------------------------------------------
# Cron drain (#5669 / ADR-078)
# -----------------------------------------------------------------------------
# Every prod swap stops the container (`docker stop --time=12 soleur-web-platform`
# below), killing any in-flight cron `claude` child — the
# _cron-claude-eval-substrate.ts:706 "spawn cwd … no longer exists" symptom. The
# drain gate (in the swap block) waits for any live claude child to finish before
# the stop, and writes a host-mounted lease so NEW cron runs defer meanwhile.
#
# CRON_DRAIN_TIMEOUT = MAX of every per-function maxTurnDurationMs
# (cron-growth-audit = 70min/4200s; ci-deploy.test.sh asserts ≥ that max). Env-
# overridable pure timing knobs (ADR-062 PROD_MEMORY_CAP precedent — NOT Doppler
# secrets). The wrapper wall-clock (ci-deploy-wrapper.sh `timeout`) and the three
# web-platform-release.yml poll windows are raised in lockstep to 4800s ≥
# CRON_DRAIN_TIMEOUT + overhead (ci-deploy-wrapper.test.sh Test 6 enforces parity).
CRON_DRAIN_TIMEOUT="${CRON_DRAIN_TIMEOUT:-4200}"
CRON_DRAIN_POLL="${CRON_DRAIN_POLL:-10}"
CRON_DRAIN_PROBE_TIMEOUT="${CRON_DRAIN_PROBE_TIMEOUT:-10}"
# Lease basename MUST match _cron-shared.ts DEPLOY_LEASE_BASENAME; host
# /mnt/data/workspaces == container /workspaces (-v mount at the docker run).
# Test harness overrides both paths to a tmpdir.
CRON_DEPLOY_LEASE_FILE="${CRON_DEPLOY_LEASE_FILE:-/mnt/data/workspaces/.deploy-lease}"
CRON_DRAIN_STATE_FILE="${CRON_DRAIN_STATE_FILE:-/var/run/ci-deploy-cron-drain.json}"
# Faithful sandbox canary verdict (#5875 / ADR-079). Written per deploy, surfaced
# on /hooks/deploy-status by cat-deploy-state.sh (sandbox_canary_json).
# DURABLE on purpose (NOT /var/run tmpfs like CRON_DRAIN/SECCOMP below): this file
# alone carries the CROSS-DEPLOY soak accumulator (consecutive_pass + first_pass_at,
# see write_sandbox_canary_state). tmpfs is wiped on every reboot, which would
# silently reset the "≥5 greens over ≥3 days" soak (#5889) to zero and lose the
# span clock — the soak could then never complete on a host that reboots inside
# the window. /mnt/data is the durable Hetzner volume (deploy-owned, cloud-init
# `chown -R deploy:deploy /mnt/data`, in webhook.service ReadWritePaths), same
# durability tier as CRON_DEPLOY_LEASE_FILE. Reader default MUST match
# cat-deploy-state.sh sandbox_canary_json().
SANDBOX_CANARY_STATE_FILE="${SANDBOX_CANARY_STATE_FILE:-/mnt/data/ci-deploy-sandbox-canary.json}"
# Where the canary payload + fixture live INSIDE the image (Dockerfile COPY).
SANDBOX_CANARY_MJS="${SANDBOX_CANARY_MJS:-/app/scripts/sandbox-canary.mjs}"
# Loaded seccomp profile hash (#5875 item 4 / ADR-079). The host seccomp profile
# is delivered by terraform_data.docker_seccomp_config; the RUNNING container only
# loads it at `docker run` (--security-opt seccomp=…). To let apply-deploy-pipeline-fix.yml
# assert loaded==committed with NO SSH, ci-deploy.sh records the sha256 of the
# profile file the prod container was JUST started with, surfaced on
# /hooks/deploy-status by cat-deploy-state.sh (seccomp_profile_sha256). Separate
# small state file — /var/run tmpfs is fine here (unlike SANDBOX_CANARY_STATE_FILE):
# this is a per-deploy snapshot with no cross-reboot accumulator, so a reboot
# wiping it before the next deploy re-records it is harmless.
SECCOMP_PROFILE_HOST_PATH="${SECCOMP_PROFILE_HOST_PATH:-/etc/docker/seccomp-profiles/soleur-bwrap.json}"
SECCOMP_PROFILE_STATE_FILE="${SECCOMP_PROFILE_STATE_FILE:-/var/run/ci-deploy-seccomp-profile.json}"

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

# --- Cron drain helpers (#5669 / ADR-078) ------------------------------------
#
# cron_in_flight: pool-agnostic in-flight detection. claude-eval runs in the
# cron-platform pool (limit:1) AND the agent-runtime pool (limit:50,
# github-on-event.ts / cfo-on-payment-failed.ts) AND cc-soleur-go endpoints —
# all as `claude` children INSIDE the prod container — so detection must match
# ANY in-container claude child, NOT an Inngest-pool-scoped runs query (which
# would miss agent-runtime children and let the stop kill them). `docker exec`
# enters the container PID namespace where the child is a descendant of PID 1.
# Wrapped in its own `timeout` so a hung `docker exec` cannot extend the drain
# past the wall-clock (G5). Returns 0 (true) when a claude child is live.
cron_in_flight() {
  timeout "${CRON_DRAIN_PROBE_TIMEOUT}" \
    docker exec soleur-web-platform pgrep -f "claude" >/dev/null 2>&1
}

# report_cron_drain_timeout: loud, no-SSH page for the ONLY path that kills a
# cron. The load-bearing signal is the cron-drain state file (surfaced as
# cron_drain_timed_out=true over /hooks/deploy-status by cat-deploy-state.sh) +
# a journald WARN (→ Better Stack). Sentry is best-effort + env-guarded (mirrors
# container-restart-monitor.sh sentry_event). Fail-open: never aborts the deploy
# under `set -e` (callers add `|| true`).
report_cron_drain_timeout() {
  local waited="$1"
  logger -t "$LOG_TAG" "CRON_DRAIN_TIMEOUT: waited ${waited}s, claude still in flight — stopping container (in-flight cron will be killed; retries:1)"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    payload="$(jq -n --arg w "$waited" \
      '{message: ("ci-deploy cron drain timed out after " + $w + "s — in-flight cron killed by container swap"),
        level: "error", platform: "other", logger: "ci-deploy",
        tags: {feature: "ci-deploy", op: "cron-drain-timeout"},
        extra: {cron_drain_wait_secs: ($w | tonumber)}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "CRON_DRAIN: Sentry POST failed (timeout event)"
  fi
}

# write_cron_drain_state: persist the drain outcome for the no-SSH deploy-status
# webhook (cat-deploy-state.sh cron_drain_json reads this; safe sentinels -1 /
# false when the file is absent because a deploy never reached the drain). Always
# returns 0 so a state-write failure never converts into a deploy failure.
write_cron_drain_state() {
  local wait_secs="$1" timed_out="$2" tmp
  tmp="$(mktemp "${CRON_DRAIN_STATE_FILE}.XXXXXX" 2>/dev/null)" || return 0
  printf '{"cron_drain_wait_secs":%d,"cron_drain_timed_out":%s}\n' \
    "$wait_secs" "$timed_out" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv "$tmp" "$CRON_DRAIN_STATE_FILE" 2>/dev/null || { rm -f "$tmp"; return 0; }
  return 0
}

# write_sandbox_canary_state: persist the faithful-canary verdict for the no-SSH
# deploy-status surface (#5875 / ADR-079). Always returns 0 — the canary is
# NON-BLOCKING (dark-launch), so a state-write failure must never abort a deploy.
# jq builds the JSON so the reason/sdk_version strings are always escaped.
#
# Accumulates the soak signal on the host (deploy-state is the source of truth),
# so the canary-promotion follow-through is a single stateless GET rather than an
# issue-comment ledger:
#   - `pass`          → increment `consecutive_pass`; pin `first_pass_at` on the
#                       first green (self-pins the soak window strictly after this
#                       deploy — no operator timestamp to hand-pin).
#   - `sandbox_broken`→ reset both to 0 (a faithful FAIL restarts the soak).
#   - infra_error/*   → HOLD prior counters (a docker/exec hiccup or the
#                       dark-launch `fixture_uncaptured` state is a non-signal).
write_sandbox_canary_state() {
  local verdict="$1" reason="$2" sdk_version="${3:-}" tmp now prior_pass prior_first
  now="$(date +%s)"
  prior_pass=0; prior_first=0
  if [[ -f "$SANDBOX_CANARY_STATE_FILE" ]]; then
    prior_pass="$(jq -r '.consecutive_pass // 0' "$SANDBOX_CANARY_STATE_FILE" 2>/dev/null || echo 0)"
    prior_first="$(jq -r '.first_pass_at // 0' "$SANDBOX_CANARY_STATE_FILE" 2>/dev/null || echo 0)"
    [[ "$prior_pass" =~ ^[0-9]+$ ]] || prior_pass=0
    [[ "$prior_first" =~ ^[0-9]+$ ]] || prior_first=0
  fi
  local consecutive_pass first_pass_at
  case "$verdict" in
    pass)
      consecutive_pass=$((prior_pass + 1))
      if [[ "$prior_first" -gt 0 ]]; then first_pass_at="$prior_first"; else first_pass_at="$now"; fi
      ;;
    sandbox_broken)
      consecutive_pass=0; first_pass_at=0 ;;
    *)
      consecutive_pass="$prior_pass"; first_pass_at="$prior_first" ;;
  esac
  tmp="$(mktemp "${SANDBOX_CANARY_STATE_FILE}.XXXXXX" 2>/dev/null)" || return 0
  jq -nc \
    --arg v "$verdict" --arg r "$reason" --arg s "$sdk_version" --argjson ts "$now" \
    --argjson cp "$consecutive_pass" --argjson fp "$first_pass_at" \
    '{verdict:$v, reason:$r, sdk_version:$s, checked_at:$ts, consecutive_pass:$cp, first_pass_at:$fp}' \
    > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv "$tmp" "$SANDBOX_CANARY_STATE_FILE" 2>/dev/null || { rm -f "$tmp"; return 0; }
  return 0
}

# sandbox_canary_sentry_event: loud, no-SSH page on a faithful-canary FAIL — the
# signal #5873 lacked (hr-no-ssh-fallback-in-runbooks: never journald-only). Best-
# effort + env-guarded, mirrors report_cron_drain_timeout. Fail-open under set -e.
sandbox_canary_sentry_event() {
  local verdict="$1" reason="$2" sdk_version="${3:-}"
  logger -t "$LOG_TAG" "SANDBOX_CANARY_FAIL: verdict=$verdict reason=$reason sdk=$sdk_version (faithful canary; legacy probe gated the deploy)"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    payload="$(jq -n --arg v "$verdict" --arg r "$reason" --arg s "$sdk_version" \
      '{message: ("faithful sandbox canary " + $v + " (" + $r + ") — SDK " + $s),
        level: "error", platform: "other", logger: "ci-deploy",
        tags: {feature: "agent-sandbox", op: "sandbox-canary", verdict: $v},
        extra: {reason: $r, sdk_version: $s}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "SANDBOX_CANARY: Sentry POST failed"
  fi
}

# cosign_verify_event: loud, no-SSH page on an image-signature verify failure
# (#5933 Item 4). Best-effort + env-guarded, mirrors sandbox_canary_sentry_event.
# The `verify_result` tag discriminates ALL failure modes in one event so the
# root cause is decided without SSH. Fail-open under set -e.
cosign_verify_event() {
  local result="$1" ref="$2" detail="${3:-}"
  logger -t "$LOG_TAG" "IMAGE_VERIFY_FAIL: result=$result ref=$ref mode=$IMAGE_VERIFY_MODE detail=$detail"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    payload="$(jq -n --arg r "$result" --arg ref "$ref" --arg d "$detail" --arg m "$IMAGE_VERIFY_MODE" \
      '{message: ("image signature verify " + $r + " (" + $ref + ")"),
        level: (if $m == "enforce" then "error" else "warning" end),
        platform: "other", logger: "ci-deploy",
        tags: {feature: "supply-chain", op: "image-verify", verify_result: $r, mode: $m},
        extra: {ref: $ref, detail: $d}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "IMAGE_VERIFY: Sentry POST failed"
  fi
}

# _pull_result_is_auth_denied <stderr-content>: the SINGLE source of truth for
# "is this docker pull stderr a credential-capability denial?" (#6400). Both
# pull_failure_event's classifier AND the pull-site recovery gate
# (_ghcr_pull_or_recover) call this predicate so they agree BY CONSTRUCTION — a
# second copy of the regex would drift (cq/paren-safety class). It classifies the
# stderr CONTENT passed as $1, never a file path: the caller must pass
# `tail -c 400 "$perr"`, not "$perr", or the match silently no-ops (security/P2-E).
_pull_result_is_auth_denied() {
  printf '%s' "${1:-}" | grep -qiE 'unauthorized|authentication required|denied|forbidden'
}

# pull_failure_event: loud, no-SSH page on an authenticated PRIVATE-pull denial
# (#6005). Every deploy + fresh boot now hard-depends on a valid GHCR credential
# (M2 SPOF), so a pull auth failure must be Sentry/Better-Stack-diagnosable, not
# journald-only (hr-no-ssh-fallback-in-runbooks). The raw docker stderr is SCRUBBED
# to a coarse classification BEFORE it enters the payload — a 401/403 daemon error
# can echo the registry Authorization header (security-sentinel #7). Fail-open.
# #6400: optional 3rd arg recovery_stage — on an auth-denied MISS the pull-site
# caller passes refetch_unavailable|relogin_failed|pull_still_denied so ONE event
# discriminates the root-cause branch (no second event on the miss path). The tag is
# an empty string on a non-auth failure — grouping is unchanged (op/pull_result
# identical to pre-#6400; Sentry fingerprinting is message/culprit-based, not tag-based).
pull_failure_event() {
  local ref="$1" detail_raw="${2:-}" recovery_stage="${3:-}" pull_result
  if   _pull_result_is_auth_denied "$detail_raw"; then pull_result="auth_denied"
  elif printf '%s' "$detail_raw" | grep -qiE 'manifest unknown|not found|no such manifest'; then pull_result="manifest_unknown"
  elif printf '%s' "$detail_raw" | grep -qiE 'timeout|timed out|temporary failure|no route|connection refused'; then pull_result="network"
  else pull_result="pull_failed"
  fi
  logger -t "$LOG_TAG" "IMAGE_PULL_FAIL: ref=$ref result=$pull_result recovery_stage=${recovery_stage:-none}"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    # #6396: tag host_id so a deploy-path pull failure is host-attributable from Sentry alone
    # (PR #6395 had to cross-reference the release aggregate JSON to pin it to web-2). The
    # readonly HOST_ID global (:137-157) is empty-safe; jq emits an empty-string tag if unset.
    # #6400: recovery_stage tag surfaces the recovery branch on an auth-denied miss.
    payload="$(jq -n --arg ref "$ref" --arg r "$pull_result" --arg h "${HOST_ID:-}" --arg rs "$recovery_stage" \
      '{message: ("image pull failed (" + $r + ") " + $ref),
        level: "error", platform: "other", logger: "ci-deploy",
        tags: {feature: "supply-chain", op: "image-pull", pull_result: $r, host_id: $h, recovery_stage: $rs},
        extra: {ref: $ref}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "IMAGE_PULL: Sentry POST failed"
  fi
}

# pull_auth_recovery_event <ref> <stage>: fail-open, env-guarded Sentry breadcrumb
# fired ONLY on a recovered-success at the GHCR pull site (#6400). Distinct
# op:image-pull-recovery + level:info keeps recovered-successes OUT of the
# WEB-PLATFORM-59 (op:image-pull, error) failure grouping — the recovery firing at
# all IS the signal the baked cred was login-ok/pull-deny. host_id-tagged (#6396).
# NEVER includes raw docker stderr; payload built with jq -n --arg. Same store
# transport as pull_failure_event.
pull_auth_recovery_event() {
  local ref="$1" stage="${2:-recovered}"
  logger -t "$LOG_TAG" "IMAGE_PULL_RECOVERED: ref=$ref stage=$stage"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    payload="$(jq -n --arg ref "$ref" --arg s "$stage" --arg h "${HOST_ID:-}" \
      '{message: ("image pull recovered (" + $s + ") " + $ref),
        level: "info", platform: "other", logger: "ci-deploy",
        tags: {feature: "supply-chain", op: "image-pull-recovery", recovery_stage: $s, host_id: $h},
        extra: {ref: $ref}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "IMAGE_PULL_RECOVERY: Sentry POST failed"
  fi
}

# registry_pull_event <registry> <image_kind> <tag>: success breadcrumb recording
# WHICH registry served a pull (#6122/ADR-096). registry ∈ {zot, ghcr-fallback};
# image_kind ∈ {web, inngest}. The soak gate (scripts/followthroughs/zot-soak-6122.sh)
# counts registry=ghcr-fallback events per image — a healthy post-cutover fleet emits
# ONLY registry=zot, so ghcr-fallback is level=warning (the watched signal) and zot is
# level=info. Emitted ONLY when zot was ACTUALLY attempted (ZOT_ACTIVE=1); the pure-dark
# pre-activation period emits nothing, so the flip stays a strict no-op until zot is
# live. Fail-open, same Sentry store transport as pull_failure_event.
registry_pull_event() {
  local registry="$1" image_kind="$2" tag="$3"
  logger -t "$LOG_TAG" "IMAGE_PULL_OK: registry=$registry image=$image_kind tag=$tag"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    payload="$(jq -n --arg reg "$registry" --arg img "$image_kind" --arg t "$tag" \
      '{message: ("image pulled from " + $reg + " (" + $img + ":" + $t + ")"),
        level: (if $reg == "ghcr-fallback" then "warning" else "info" end),
        platform: "other", logger: "ci-deploy",
        tags: {feature: "supply-chain", op: "image-pull", registry: $reg, image: $img},
        extra: {tag: $t}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "IMAGE_PULL: Sentry POST failed"
  fi
}

# zot_gate_degraded_event <reason>: WARNING beacon for when zot is CONFIGURED
# (ZOT_REGISTRY_URL present) but the dark-launch gate could not activate it — the fleet
# silently reverts to the GHCR path on the frequent rolling-deploy path WITHOUT a
# registry=ghcr-fallback pull event (the pull path never attempts zot, so pull_image_with_
# fallback takes its dark branch). Without this, a post-cutover zot pull-cred degradation
# (host up + heartbeat green, but pull login failing) is journald-only and the fallback-rate
# alarm is blind (hr-no-ssh-fallback-in-runbooks). SILENT during dark-launch — only fires
# when ZOT_REGISTRY_URL is set. reason ∈ {probe_unreachable, creds_absent, login_failed}.
# Fail-open, same Sentry store transport as pull_failure_event.
zot_gate_degraded_event() {
  local reason="$1"
  logger -t "$LOG_TAG" "ZOT_GATE_DEGRADED: reason=$reason (configured but inactive — GHCR path)"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload
    payload="$(jq -n --arg r "$reason" \
      '{message: ("zot gate degraded (" + $r + ") — configured but inactive, using GHCR"),
        level: "warning", platform: "other", logger: "ci-deploy",
        tags: {feature: "supply-chain", op: "image-pull", registry: "zot-gate-degraded", zot_gate_reason: $r}}' 2>/dev/null)" || return 0
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null \
      || logger -t "$LOG_TAG" "ZOT_GATE: Sentry POST failed"
  fi
}

# refetch_ghcr_and_relogin (#6400): re-fetch the CURRENT prd GHCR read credential,
# re-run `docker login ghcr.io` into the SAME docker config the cosign verifier
# mounts :ro, and return a STAGE code so the caller can discriminate the failure.
# Echoes on stdout exactly one of: recovered | refetch_unavailable | relogin_failed
# Returns 0 IFF stage==recovered (the login status IS the exit status — this is the
# load-bearing difference from §1A's inline body, whose trailing `dt=""` (exit 0)
# would make the function return 0 on every path and muddy the `recovered` signal
# the pull-site gate keys on). Token via --password-stdin only; kept `local` + unset
# after so no child process env carries it. The recovered auth ENTRY is carried by
# the `docker login ghcr.io` filesystem write into $GHCR_DOCKER_CONFIG (persists past
# the `$(…)` subshell this helper runs in) — the SAME file the prelude wrote and the
# cosign verifier mounts :ro, so a recovered pull does not then 401 the .sig fetch
# (P2-F). (The `export GHCR_READ_USER` below is defensive-only — it is swallowed by the
# subshell and no downstream reader consumes the env var; the docker-config write is
# what authenticates.) Guarded on doppler + DOPPLER_TOKEN (prd-root scoped).
refetch_ghcr_and_relogin() {
  command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]] || { printf refetch_unavailable; return 1; }
  local du="" dt="" n=0
  n=0; until du="$(timeout 45 doppler secrets get GHCR_READ_USER  --plain --project soleur --config prd 2>/dev/null)"; [[ -n "$du" ]]; do n=$((n + 1)); [[ "$n" -ge 3 ]] && break; sleep 5; done
  n=0; until dt="$(timeout 45 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null)"; [[ -n "$dt" ]]; do n=$((n + 1)); [[ "$n" -ge 3 ]] && break; sleep 5; done
  [[ -n "$du" && -n "$dt" ]] || { dt=""; printf refetch_unavailable; return 1; }
  if printf '%s' "$dt" | docker login ghcr.io -u "$du" --password-stdin >/dev/null 2>&1; then
    export GHCR_READ_USER="$du"; dt=""; printf recovered; return 0
  fi
  dt=""; printf relogin_failed; return 1
}

# ghcr_prelude_and_login: fetch the deploy-time secrets the pull + verify + telemetry
# need INTO this script's OWN env, then authenticate the host docker daemon to the
# now-PRIVATE GHCR packages (#6005). Runs BEFORE the first `docker pull` — the
# existing resolve_env_file download (~:1010) runs AFTER pull+verify and hands
# secrets to the CONTAINER via --env-file, so those values are NEVER in this script's
# env at pull/verify time. Without this: (a) the private pull fails-closed, and
# (b) the WARN cosign telemetry is dark (SENTRY_* unset at verify time), blinding the
# very soak gate the ENFORCE flip depends on. Best-effort + fail-open: a missing GHCR
# credential does not abort here (the pull's own failure path + pull_failure_event
# surface it loudly); missing SENTRY_* just means a dark event, exactly as today. The
# token is captured into a var and piped via --password-stdin — NEVER argv/logs, and
# unset immediately after login so it never reaches a child process env.
ghcr_prelude_and_login() {
  # (#6090) Prefer BAKED GHCR read-creds (cloud-init writes /etc/default/soleur-ghcr-read,
  # deploy:deploy 0600 — the app-pull analogue of the seed-pull bake) so the app pull +
  # cosign verify authenticate on a cold host even when Doppler answers EMPTY at the boot
  # instant (the exact #6090 failure class, one layer down: an empty fetch here skipped the
  # login → anonymous private pull → cosign .sig fetch 401 → verify_failed → app never binds
  # :9000 → peer fan-out degraded). Doppler stays the fallback, HARDENED (timeout 45 + 3-try
  # retry) to match cloud-init's ghcr_login. GHCR_READ_USER is a username (safe to export);
  # the TOKEN reaches `docker login` via --password-stdin only and is unset so no child env
  # (docker/cosign subprocess) ever carries it.
  local k n ghcr_user="" ghcr_token=""
  # SOLEUR_GHCR_READ_FILE overrides the baked-cred path for tests ONLY; production is the
  # unchanged /etc/default/soleur-ghcr-read (cloud-init writes it deploy:deploy 0600).
  local ghcr_read_file="${SOLEUR_GHCR_READ_FILE:-/etc/default/soleur-ghcr-read}"
  if [[ -r "$ghcr_read_file" ]]; then
    # shellcheck disable=SC1091
    . "$ghcr_read_file" 2>/dev/null || true
    ghcr_user="${GHCR_READ_USER:-}"; ghcr_token="${GHCR_READ_TOKEN:-}"
    unset GHCR_READ_TOKEN   # keep the token out of THIS process env + its children
  fi
  if command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
    # SENTRY_* prefetch for the verify/pull telemetry curls (dark event if absent, as today).
    for k in SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY; do
      # `secrets get <NAME> --plain` returns the bare value on stdout (never argv).
      printf -v "$k" '%s' "$(doppler secrets get "$k" --plain --project soleur --config prd 2>/dev/null || true)"
      export "$k"
    done
    # Hardened Doppler fallback for any GHCR cred the bake did not supply.
    if [[ -z "$ghcr_user" ]]; then
      n=0; until ghcr_user="$(timeout 45 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null)"; [[ -n "$ghcr_user" ]]; do n=$((n + 1)); [[ "$n" -ge 3 ]] && break; sleep 5; done
    fi
    if [[ -z "$ghcr_token" ]]; then
      n=0; until ghcr_token="$(timeout 45 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null)"; [[ -n "$ghcr_token" ]]; do n=$((n + 1)); [[ "$n" -ge 3 ]] && break; sleep 5; done
    fi
  elif [[ -z "$ghcr_user" || -z "$ghcr_token" ]]; then
    logger -t "$LOG_TAG" "PRELUDE: doppler/DOPPLER_TOKEN unavailable and baked GHCR creds incomplete — skipping GHCR login + SENTRY prefetch"
  fi
  export GHCR_READ_USER="$ghcr_user"   # username, not a secret (matches prior exported behavior)
  if [[ -n "$ghcr_user" && -n "$ghcr_token" ]]; then
    if printf '%s' "$ghcr_token" | docker login ghcr.io -u "$ghcr_user" --password-stdin >/dev/null 2>&1; then
      logger -t "$LOG_TAG" "PRELUDE: docker login ghcr.io ok (private-package pull authenticated)"
    else
      # §1A (#6090 recurrence, web-2 fsn1 warm-standby 2026-07-13): the baked GHCR read token
      # is PRESENT but STALE — a fresh host's baked /etc/default/soleur-ghcr-read token ages
      # out by deploy time, and the EMPTY-only Doppler fallback above only re-fetches an
      # ABSENT cred, never a present-but-invalid one. Pre-fix, this login just failed non-
      # fatally → anonymous private pull → registry 401 → Sentry `image pull failed
      # (auth_denied)` → image_pull_failed → the warm standby never serves. Fix: on a login
      # FAILURE (not only EMPTY), re-fetch the CURRENT creds from Doppler (hardened timeout
      # 45 + 3-try idiom, mirroring the EMPTY path) and retry docker login ONCE. Fail-open: a
      # retry miss still lets the pull's own failure path + pull_failure_event surface loudly.
      logger -t "$LOG_TAG" "PRELUDE: docker login ghcr.io FAILED with baked/first creds — re-fetching current creds from Doppler and retrying"
      # #6400: §1A's inline re-fetch/relogin is now the shared refetch_ghcr_and_relogin
      # helper (identical observable behavior — recover on a login FAILURE — plus the
      # staged return the pull-site gate needs). The helper self-guards on
      # doppler/DOPPLER_TOKEN (stage=refetch_unavailable when absent) and keeps the
      # retried token out of any child env.
      # `|| true` is load-bearing: ci-deploy runs under `set -euo pipefail`, and the
      # helper returns non-zero on a recovery miss — a bare assignment would abort the
      # whole deploy on that nonzero (we parse the stage STRING, the rc is irrelevant here).
      local prelude_stage
      prelude_stage="$(refetch_ghcr_and_relogin)" || true
      if [[ "$prelude_stage" == "recovered" ]]; then
        logger -t "$LOG_TAG" "PRELUDE: docker login ghcr.io ok after Doppler re-fetch (recovered stale baked cred)"
      else
        logger -t "$LOG_TAG" "PRELUDE: docker login ghcr.io STILL FAILED after Doppler re-fetch (stage=$prelude_stage) — private pull may fail-closed"
      fi
    fi
  else
    logger -t "$LOG_TAG" "PRELUDE: GHCR_READ_{USER,TOKEN} not both present (baked file absent + doppler empty/unavailable) — skipping docker login"
  fi
  # The mounted $GHCR_DOCKER_CONFIG (inline auths entry) is what the cosign verifier
  # reuses; the token local goes out of scope when the function returns.
  ghcr_token=""
}

# zot_gate_and_login: dark-launch gate for the self-hosted zot registry (#6122/ADR-096).
# Sets ZOT_ACTIVE=1 ONLY when zot is confirmed-configured-and-live: ZOT_REGISTRY_URL
# present in Doppler prd AND a fast /v2/ probe answers AND the pull cred logs in. Any
# miss leaves ZOT_ACTIVE=0 → every pull falls straight through to the UNCHANGED GHCR path
# (wg-dark-launch-deploy-gates), so this is a strict no-op until the operator provisions
# (1.8) + backfills (1.9) zot. The zot `docker login` writes a second auths entry into
# the SAME $GHCR_DOCKER_CONFIG the cosign verifier mounts :ro — so Edge B (insecure .sig
# fetch auth) is satisfied ATOMICALLY with the pull cred. Fail-open: never aborts the
# deploy. Runs AFTER ghcr_prelude_and_login (which already prefetched SENTRY_* + guarded
# doppler/DOPPLER_TOKEN). Token reaches `docker login` via --password-stdin (never argv),
# and login output is >/dev/null 2>&1 so no trace/secret leaks.
zot_gate_and_login() {
  ZOT_ACTIVE=0
  command -v doppler >/dev/null 2>&1 || return 0
  [[ -n "${DOPPLER_TOKEN:-}" ]] || return 0
  [[ -n "$ZOT_REGISTRY_URL" ]] || \
    ZOT_REGISTRY_URL="$(doppler secrets get ZOT_REGISTRY_URL --plain --project soleur --config prd 2>/dev/null || true)"
  if [[ -z "$ZOT_REGISTRY_URL" ]]; then
    logger -t "$LOG_TAG" "ZOT_GATE: ZOT_REGISTRY_URL unset — GHCR path (dark, pre-provisioning)"
    return 0
  fi
  # Reachability probe: a live OCI registry answers /v2/ with 200 (open) or 401 (auth
  # required); a down/unreachable host yields 000 (curl connect failure) → GHCR path.
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$ZOT_PROBE_TIMEOUT" "http://${ZOT_REGISTRY_URL}/v2/" 2>/dev/null || echo 000)"
  if [[ "$code" != "200" && "$code" != "401" ]]; then
    logger -t "$LOG_TAG" "ZOT_GATE: /v2/ probe http=$code — GHCR path (zot unreachable)"
    zot_gate_degraded_event probe_unreachable
    return 0
  fi
  local zuser ztoken
  zuser="$(doppler secrets get ZOT_PULL_USER --plain --project soleur --config prd 2>/dev/null || true)"
  ztoken="$(doppler secrets get ZOT_PULL_TOKEN --plain --project soleur --config prd 2>/dev/null || true)"
  if [[ -z "$zuser" || -z "$ztoken" ]]; then
    logger -t "$LOG_TAG" "ZOT_GATE: ZOT_PULL_{USER,TOKEN} not both present — GHCR path"
    ztoken=""
    zot_gate_degraded_event creds_absent
    return 0
  fi
  if printf '%s' "$ztoken" | docker login "$ZOT_REGISTRY_URL" -u "$zuser" --password-stdin >/dev/null 2>&1; then
    ZOT_ACTIVE=1
    logger -t "$LOG_TAG" "ZOT_GATE: active — docker login $ZOT_REGISTRY_URL ok (zot-primary)"
  else
    logger -t "$LOG_TAG" "ZOT_GATE: docker login $ZOT_REGISTRY_URL FAILED — GHCR path (fallback)"
    zot_gate_degraded_event login_failed
  fi
  ztoken=""
}

# _ghcr_pull_or_recover <perr> (#6400): pull ${IMAGE}:${TAG} from GHCR; on an
# AUTH-denied failure (classified from the stderr CONTENT, not the file path),
# re-fetch the prd cred, relogin, and retry the pull EXACTLY ONCE before giving up.
# Returns 0 on success (first pull OR recovered retry). On failure returns 1 and
# sets the global RECOVERY_STAGE for the caller's pull_failure_event tag (empty when
# no recovery was attempted — a non-auth failure never enters the branch, so
# pull_failure_event fires byte-identically to pre-#6400). Fail-open: a recovery miss
# leaves the caller's terminal image_pull_failed state unchanged. No loop — retrying
# a genuinely-invalid prd cred would burn the deploy window (Sharp Edge). The
# `200>&-` closes the FD-200 advisory lock for the pull children (#5062), preserved.
_ghcr_pull_or_recover() {
  local perr="$1"
  RECOVERY_STAGE=""
  docker pull "${IMAGE}:${TAG}" 200>&- 2>"$perr" && return 0
  # classify the stderr CONTENT (tail -c 400), never the path — else recovery no-ops (P2-E).
  if _pull_result_is_auth_denied "$(tail -c 400 "$perr" 2>/dev/null)"; then
    # `|| true`: helper returns non-zero on a miss; a bare assignment would abort the
    # deploy under set -euo. We parse the stage STRING (that string, not the rc, is what
    # gets copied into RECOVERY_STAGE below; the rc is discarded via `|| true`).
    local stage; stage="$(refetch_ghcr_and_relogin)" || true   # recovered|refetch_unavailable|relogin_failed
    if [[ "$stage" == "recovered" ]]; then
      if docker pull "${IMAGE}:${TAG}" 200>&- 2>"$perr"; then
        pull_auth_recovery_event "${IMAGE}:${TAG}" recovered   # info breadcrumb, distinct op
        return 0
      fi
      RECOVERY_STAGE="pull_still_denied"                       # relogin ok but retry pull still denied
    else
      RECOVERY_STAGE="$stage"                                  # refetch_unavailable|relogin_failed
    fi
  fi
  return 1
}

# pull_image_with_fallback <image_kind>: pull $IMAGE:$TAG zot-primary with an ATOMIC
# GHCR fallback (#6122/ADR-096). image_kind ∈ {web, inngest} (beacon tag only). On
# success it reassigns the GLOBAL IMAGE to the registry-qualified repo actually pulled,
# so verify_image_signature + every downstream docker create/run follow the SAME
# registry — image ref + docker auth + cosign .sig target move together. Emits a
# registry_pull_event breadcrumb (zot on success, ghcr-fallback when zot was attempted
# but failed); pull_failure_event on total failure. Returns 1 only when BOTH registries
# fail (caller aborts, OLD container stays live — downtime-safe). FD-200 advisory lock
# is closed for the pull children (#5062).
pull_image_with_fallback() {
  local image_kind="$1" perr
  perr="$(mktemp 2>/dev/null || echo /tmp/ci-deploy-pull.err)"
  if [[ "$ZOT_ACTIVE" == "1" ]]; then
    local zot_ref="${ZOT_REGISTRY_URL}/${IMAGE#ghcr.io/}"
    if docker pull "${zot_ref}:${TAG}" 200>&- 2>"$perr"; then
      IMAGE="$zot_ref"
      registry_pull_event zot "$image_kind" "$TAG"
      rm -f "$perr" 2>/dev/null || true
      return 0
    fi
    # zot attempted but failed → ATOMIC fallback to GHCR (IMAGE stays the ghcr ref, so
    # cosign follows the GHCR RepoDigest with NO insecure flag). This is the soak gate's
    # watched event; surfaced loudly, not journald-only.
    logger -t "$LOG_TAG" "IMAGE_PULL: zot pull failed for ${zot_ref}:${TAG} — falling back to GHCR"
    # #6400: GHCR fallback leg now recovers on a login-ok/pull-deny cred (retry once).
    if _ghcr_pull_or_recover "$perr"; then
      registry_pull_event ghcr-fallback "$image_kind" "$TAG"
      rm -f "$perr" 2>/dev/null || true
      return 0
    fi
    pull_failure_event "${IMAGE}:${TAG}" "$(tail -c 400 "$perr" 2>/dev/null || true)" "${RECOVERY_STAGE:-}"
    rm -f "$perr" 2>/dev/null || true
    return 1
  fi
  # zot dark (not configured/unreachable) → unchanged GHCR path, now with pull-site
  # recovery (#6400): a baked cred that logs in but cannot pull is re-fetched + retried.
  if _ghcr_pull_or_recover "$perr"; then
    rm -f "$perr" 2>/dev/null || true
    return 0
  fi
  pull_failure_event "${IMAGE}:${TAG}" "$(tail -c 400 "$perr" 2>/dev/null || true)" "${RECOVERY_STAGE:-}"
  rm -f "$perr" 2>/dev/null || true
  return 1
}

# verify_image_signature <image:tag> — resolves the just-pulled image to its
# immutable repo@sha256 digest and cosign-verifies the signature (offline,
# identity-pinned) via the SHA-pinned cosign container. Echoes on stdout the ref
# the caller should RUN: the verified digest on success (TOCTOU-safe), or the
# original tag as a fail-open fallback in WARN mode. Emits a discriminating
# Sentry event on every failure. Return: 0 in WARN mode always (never blocks);
# in ENFORCE mode, 1 on any verify failure so the caller keeps the OLD container
# live (downtime-safe). The mode branch is the ONLY behavioural difference — the
# telemetry fires identically in both.
verify_image_signature() {
  local image_tag="$1" repo_digest err
  err="$(mktemp 2>/dev/null || echo /tmp/cosign-verify.err)"
  # Resolve the pulled tag to its immutable digest ref. Select the RepoDigest for the
  # SAME registry the tag names — after a dual-push era the local image can carry BOTH a
  # zot and a GHCR RepoDigest, and `{{index .RepoDigests 0}}` picks a non-deterministic
  # one; scoping to the pulled registry keeps the cosign target following the pull
  # registry atomically (#6122 Edge B). `${image_tag%:*}` strips only the trailing :tag
  # (the zot host:port colon is followed by '/', so it survives the strip).
  local repo="${image_tag%:*}"
  repo_digest="$(docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image_tag" 2>/dev/null | grep -F "${repo}@sha256:" | head -1 || true)"
  if [[ -z "$repo_digest" || "$repo_digest" != *"@sha256:"* ]]; then
    cosign_verify_event "inspect_failed" "$image_tag" "RepoDigests[0] empty or not a digest ref"
    printf '%s' "$image_tag" # fail-open: run the tag (WARN); ENFORCE aborts below
    rm -f "$err" 2>/dev/null || true
    [[ "$IMAGE_VERIFY_MODE" == "enforce" ]] && return 1
    return 0
  fi
  # Verify via the pinned cosign container (ADR-087 Design B′). The app image is a
  # PRIVATE GHCR package (#6005): `--network host` routes the OCI-attached .sig fetch
  # through the host's unrestricted egress (no ghcr.io in the container allowlist),
  # and the deploy user's docker config ($GHCR_DOCKER_CONFIG, written by
  # ghcr_prelude_and_login) is mounted :ro so cosign can authenticate that fetch.
  # Trust is the locally-pinned trusted_root.json (mounted :ro) with `--offline`, so
  # no live Fulcio/Rekor/TUF egress is needed. `docker pull` of the image does NOT
  # pull the .sig referrer, so the fetch (host egress) is still required.
  # Edge B (#6122): a zot-pulled digest lives on plain-HTTP zot on the private net, so
  # the .sig referrer fetch needs --allow-insecure-registry. When the pull fell back to
  # GHCR the digest is a ghcr.io ref and the flag stays off — image+auth+sig move
  # together. The zot auths entry was written into $GHCR_DOCKER_CONFIG by
  # zot_gate_and_login, so the mounted :ro config already authenticates the fetch.
  local zot_insecure=""
  [[ -n "$ZOT_REGISTRY_URL" && "$repo_digest" == "${ZOT_REGISTRY_URL}/"* ]] && zot_insecure=1
  if docker run --rm --network host \
       -v "$GHCR_DOCKER_CONFIG:/root/.docker/config.json:ro" \
       -v "$COSIGN_TRUSTED_ROOT_HOST:/etc/cosign/trusted_root.json:ro" \
       "$COSIGN_IMAGE" verify --offline \
       ${zot_insecure:+--allow-insecure-registry} \
       --trusted-root=/etc/cosign/trusted_root.json \
       --certificate-identity-regexp="$COSIGN_IDENTITY_REGEXP" \
       --certificate-oidc-issuer="$COSIGN_OIDC_ISSUER" \
       "$repo_digest" >/dev/null 2>"$err"; then
    logger -t "$LOG_TAG" "IMAGE_VERIFY: ok ref=$repo_digest"
    printf '%s' "$repo_digest" # run the VERIFIED digest (TOCTOU-safe)
    rm -f "$err" 2>/dev/null || true
    return 0
  fi
  # Classify the failure for the discriminating Sentry event (telemetry only —
  # best-effort string match on cosign stderr; never load-bearing).
  local result="verify_failed" tail
  tail="$(tail -c 400 "$err" 2>/dev/null || true)"
  if   printf '%s' "$tail" | grep -qiE 'no matching signatures|no signatures found'; then result="unsigned"
  elif printf '%s' "$tail" | grep -qiE 'certificate identity|none of the expected identities|subject.*mismatch'; then result="wrong_identity"
  elif printf '%s' "$tail" | grep -qiE 'rekor|tlog|transparency|tuf'; then result="rekor_unreachable"
  elif printf '%s' "$tail" | grep -qiE 'Unable to find image|manifest unknown|pull access denied|no such image'; then result="cosign_absent"
  fi
  cosign_verify_event "$result" "$repo_digest" "$tail"
  printf '%s' "$repo_digest" # WARN: run the verified digest anyway (immutability holds)
  rm -f "$err" 2>/dev/null || true
  [[ "$IMAGE_VERIFY_MODE" == "enforce" ]] && return 1
  return 0
}

# run_faithful_sandbox_canary: NON-BLOCKING dark-launch (#5875 / ADR-079). Runs
# the SDK-captured bwrap argv INSIDE the canary container via the baked-in mjs,
# records the verdict to deploy-state, and pages Sentry on a faithful FAIL — but
# NEVER rolls back (the legacy probe stays the gate during dark-launch; a
# "faithful FAIL + legacy PASS" disagreement is the alertable promote signal).
# Exit-code classification: a failed `docker exec` (125/126/127 / ENOENT) is a
# canary_infra_error, NOT sandbox_broken — the #4941 false-rollback guard.
run_faithful_sandbox_canary() {
  local verdict reason sdk_version exec_rc out err_file docker_err
  # Capture docker's OWN stderr so a persistent infra_error (rc 126/127: "no such
  # container", "exec format error") carries its CAUSE onto the no-SSH surfaces —
  # the numeric rc alone would otherwise be the only signal (obs review P2).
  err_file="$(mktemp 2>/dev/null || echo /dev/null)"
  # set +o pipefail so the classification below reads docker exec's own rc, not
  # a downstream pipe member's (load-bearing under set -euo — mirrors the
  # canary_layer3 logger block).
  set +o pipefail
  out="$(docker exec soleur-web-platform-canary node "$SANDBOX_CANARY_MJS" --replay 2>"$err_file")"
  exec_rc=$?
  set -o pipefail
  if [[ "$exec_rc" -ne 0 ]]; then
    # docker/exec/node failure (125 daemon, 126/127 not-exec/not-found) — infra,
    # never a sandbox verdict. Fold docker's first stderr line (print-safe,
    # length-capped) into the reason so the cause rides deploy-state + the log.
    docker_err="$(head -1 "$err_file" 2>/dev/null | tr -dc '[:print:]' | cut -c1-120)"
    verdict="canary_infra_error"; reason="docker_exec_rc_${exec_rc}${docker_err:+: $docker_err}"; sdk_version=""
  else
    verdict="$(printf '%s' "$out" | jq -r '.verdict // "canary_infra_error"' 2>/dev/null || echo canary_infra_error)"
    reason="$(printf '%s' "$out" | jq -r '.reason // "unparseable"' 2>/dev/null || echo unparseable)"
    # sandbox-canary.mjs emits the SDK version as the camelCase key `sdkVersion`
    # (JS-idiomatic); this deploy-state chain is snake_case, so translate at the
    # boundary here. Accept snake_case too so a future mjs rename can't silently
    # re-blank it. Missing key ⇒ "" (the soak surface's sdk_version was empty
    # before this — the key never matched).
    sdk_version="$(printf '%s' "$out" | jq -r '.sdkVersion // .sdk_version // ""' 2>/dev/null || echo '')"
  fi
  if [[ "$err_file" != "/dev/null" ]]; then rm -f "$err_file" 2>/dev/null || true; fi
  write_sandbox_canary_state "$verdict" "$reason" "$sdk_version"
  echo "Faithful sandbox canary (non-blocking): verdict=$verdict reason=$reason"
  # Page only on a faithful FAIL (sandbox_broken) — the disagreement signal.
  # canary_infra_error is expected during dark-launch (fixture not yet captured)
  # and must not page.
  if [[ "$verdict" == "sandbox_broken" ]]; then
    sandbox_canary_sentry_event "$verdict" "$reason" "$sdk_version" || true
  fi
  return 0
}

# write_seccomp_profile_hash: record the sha256 of the seccomp profile the prod
# container was JUST started with (#5875 item 4 / ADR-079). The container loads
# the profile at `docker run --security-opt seccomp=<host file>`, so the sha256 of
# that host file at container-start time IS the "loaded" profile hash. Surfaced on
# /hooks/deploy-status by cat-deploy-state.sh (seccomp_profile_sha256), it lets
# apply-deploy-pipeline-fix.yml assert loaded==committed with NO SSH — the
# "applied ≠ loaded" gap that let a #5874-style recovery fix "apply" without ever
# loading. Always returns 0: recording the hash must never abort a succeeded deploy.
write_seccomp_profile_hash() {
  local host_path="${1:-$SECCOMP_PROFILE_HOST_PATH}" sha="" tmp now
  now="$(date +%s)"
  # cut the leading 64-hex field from `sha256sum`; empty (→ JSON "") if the
  # profile file is absent (e.g. a host predating docker_seccomp_config, or the
  # test harness). The existence guard + `|| true` keep a missing file from
  # tripping `set -euo pipefail` and aborting a SUCCEEDED deploy — this is a
  # best-effort observability write, never a gate (mirrors write_sandbox_canary_state).
  if [[ -f "$host_path" ]]; then
    sha="$(sha256sum "$host_path" 2>/dev/null | cut -d' ' -f1 || true)"
  fi
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || sha=""
  tmp="$(mktemp "${SECCOMP_PROFILE_STATE_FILE}.XXXXXX" 2>/dev/null)" || return 0
  jq -nc --arg sha "$sha" --argjson ts "$now" \
    '{seccomp_profile_sha256:$sha, loaded_at:$ts}' \
    > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv "$tmp" "$SECCOMP_PROFILE_STATE_FILE" 2>/dev/null || { rm -f "$tmp"; return 0; }
  return 0
}

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

# Verify inngest-server is healthy after restart (#4538), with an ADVISORY
# cron-plan check (#4650 / AC9, reframed #5159).
# /health is the HARD liveness gate: returns 1 if the server never became
# reachable (a dead process must fail the deploy).
# The cron-plan check is ADVISORY: a standalone inngest-server restart DE-PLANS
# all cron triggers, and they re-arm ONLY asynchronously — via a web-platform
# redeploy (new appVersion → SDK syncs `modified:true` → immediate re-arm) or
# the server's own `--poll-interval` self-heal (~minutes). A loopback
# `PUT /api/inngest` does NOT re-arm them (it's a `modified:false` no-op,
# proven #5159). So after /health passes we poll /v1/functions a FEW times
# best-effort: if a cron trigger appears we log success; if not, we log an
# advisory and STILL return 0. Persistent de-plans are caught out-of-band by
# the Sentry cron monitors (the H9b safety net), NOT by failing the deploy.
# Uses `|| true` after curl instead of set +e/-e toggle — toggling set -e
# inside a function re-enables it globally and causes the caller's non-zero
# capture (`VERIFY_RC=$?`) to never execute.
verify_inngest_health() {
  local max_attempts="${1:-10}"
  local interval="${2:-3}"
  # Advisory cron-plan probe budget (#5159). Best-effort only: crons re-arm
  # async (redeploy or --poll-interval), so a few attempts suffice to catch the
  # common fast-resync case. A missing cron after these attempts is NOT a deploy
  # failure — the Sentry cron monitors are the real safety net. Plain constant,
  # NOT a positional default — the call sites must stay arg-less
  # (ci-deploy.test.sh wiring grep), so a third parameter would be a knob nobody
  # is allowed to turn.
  local cron_max_attempts=10
  local response=""
  local healthy=0

  for i in $(seq 1 "$max_attempts"); do
    response=$(curl -sf --max-time 5 http://127.0.0.1:8288/health 2>/dev/null) || true

    if [[ -n "$response" ]]; then
      logger -t "$LOG_TAG" "INNGEST_HEALTH: healthy=true (attempt $i/$max_attempts)"
      healthy=1
      break
    fi
    logger -t "$LOG_TAG" "INNGEST_HEALTH: attempt $i/$max_attempts — connection failed or empty response"
    sleep "$interval"
  done

  if [[ "$healthy" -ne 1 ]]; then
    logger -t "$LOG_TAG" "INNGEST_HEALTH: healthy=false after $max_attempts attempts"
    return 1
  fi

  # Durable-backend HARD gate (#5450). Phase-0 verdict 0.3: inngest FAILS CLOSED
  # on an *unreachable* backend (so /health=200 above already proves a configured
  # backend is reachable — inngest won't serve otherwise). The residual silent
  # risk is *flags-absent*: a templating/image regression that drops the backend
  # flags → inngest defaults to in-memory Redis (non-durable) WHILE /health=200.
  # This gate is a CONSISTENCY assertion: when the durable backend is configured the
  # queue MUST also have inngest-redis active, or the deploy fails loud. It is
  # transparent to pre-migration / rollback states (sentinel absent → skip), so a
  # `--sqlite-dir`-only rollback still passes. Reads only the CONFIGURED ExecStart
  # ($VAR form — no secret value) + unit activeness; never logs the connection string.
  # Detection sentinel (#5560): the durable backend is detected by the NON-SECRET
  # --postgres-max-open-conns flag, NOT --postgres-uri/--redis-uri — those are now
  # delivered via the doppler-run ENVIRONMENT (never argv) so they no longer appear
  # in the ExecStart. inngest-bootstrap.sh writes --postgres-max-open-conns ONLY in
  # the durable branch (present iff durable). Build-time flag presence is separately
  # drift-guarded in inngest.test.sh; parser token-parity in inngest-inventory.test.sh.
  local exec_start=""
  exec_start=$(systemctl show -p ExecStart inngest-server.service 2>/dev/null || true)
  if [[ "$exec_start" == *'--postgres-max-open-conns'* ]]; then
    if ! systemctl is-active --quiet inngest-redis.service; then
      logger -t "$LOG_TAG" "INNGEST_DURABLE: FAIL — durable backend configured but inngest-redis.service is not active; armed reminders would not persist"
      return 1
    fi
    logger -t "$LOG_TAG" "INNGEST_DURABLE: ok — durable backend (--postgres-max-open-conns sentinel) configured and inngest-redis.service active"
  else
    # #5547 Gap 2/3: SQLite-only fail-safe ExecStart (Redis was not ready this
    # deploy → inngest-bootstrap wrote the empty BACKEND_FLAGS form). This is NOT
    # a failure — the server is available on the non-durable backend, so do NOT
    # return 1 (that would block a legitimate SQLite-only rollback). This
    # `logger -t "$LOG_TAG"` advisory is the AUTHORITATIVE no-SSH carrier for the
    # degraded state: LOG_TAG=ci-deploy is in Vector Source 4's tag allowlist →
    # Better Stack Logs. (The bootstrap-stderr INNGEST_DURABLE_DEGRADED marker is
    # NOT a carrier on this 0-exit path — ci-deploy reads $BOOTSTRAP_STDERR only
    # on a non-zero bootstrap exit.)
    logger -t "$LOG_TAG" "INNGEST_DURABLE: advisory — inngest-server running SQLite-only (non-durable); durable Redis was not ready this deploy (#5547). Server is available; armed reminders will NOT survive a host rebuild until a deploy with Redis ready."
  fi

  # Cron-plan probe (#4650 / AC9, ADVISORY post-#5159, #5520): /health proves
  # only process liveness. A standalone inngest restart de-plans cron triggers;
  # they re-arm async (web-platform redeploy → modified:true sync, or the
  # server's --poll-interval self-heal). Best-effort poll /v0/gql for a
  # re-armed cron trigger; if none appears, log an advisory and STILL succeed
  # (the Sentry cron monitors are the real safety net). GET /v1/functions is an
  # unregistered 404 in inngest v1.19.4 (#5520); the GraphQL `functions` field
  # on /v0/gql returns triggers as {type,value} objects — cron triggers carry
  # type="CRON". Dependency-free substring match on `"type":"CRON"` in the
  # minified GQL response (jq is not a host dependency).
  local functions_body=""
  for i in $(seq 1 "$cron_max_attempts"); do
    functions_body=$(curl -sf --max-time 5 -X POST -H "Content-Type: application/json" -d '{"query":"{ functions { triggers { type value } } }"}' http://127.0.0.1:8288/v0/gql 2>/dev/null) || true

    if [[ "$functions_body" == *'"type":"CRON"'* ]]; then
      logger -t "$LOG_TAG" "INNGEST_CRON_PLAN: ok — registry has >=1 cron-triggered function (attempt $i/$cron_max_attempts)"
      return 0
    fi
    logger -t "$LOG_TAG" "INNGEST_CRON_PLAN: attempt $i/$cron_max_attempts — no cron trigger present in registry yet"
    sleep "$interval"
  done

  logger -t "$LOG_TAG" "INNGEST_CRON_PLAN: advisory — no cron trigger re-armed yet; a standalone inngest restart de-plans crons until a web-platform redeploy (modified:true sync) or the --poll-interval self-heal re-arms them (#5159). NOT failing the deploy — Sentry cron monitors are the H9b safety net."
  return 0
}

# Single-source "is the inngest unit enabled at boot?" (enabled|enabled-runtime).
# Both verify_inngest_quiesced (fail-branch) and the enable handler (ok-branch) use this
# so the set of enabled-like states stays defined in ONE place. Exotic states
# (indirect/alias/generated/static/disabled) are intentionally NOT "enabled" here.
inngest_unit_enabled() {
  case "$(systemctl is-enabled inngest-server.service 2>/dev/null || true)" in
    enabled|enabled-runtime) return 0 ;;
    *) return 1 ;;
  esac
}

# Verify inngest-server is QUIESCED (#6178, op=quiesce-web). The goal state is
# NOT-serving AND NOT-enabled — verifying only not-serving is a proxy that defeats the
# disable's purpose (data-integrity P1-A): a disable-failure on a unit WITH an [Install]
# section would pass as quiesced while still enabled → a mid-window reboot re-arms the old
# scheduler → the exact double-fire the disable prevents.
#
# Return codes (the handler maps them to reasons):
#   0 = quiesced (not-serving AND unit-inactive AND not-enabled)
#   1 = still serving/active  → inngest_still_serving
#   2 = still enabled         → inngest_still_enabled
#
# The /health poll is the MIRROR-IMAGE polarity of verify_inngest_health: that helper
# breaks on the FIRST success; this one must declare not-serving ONLY when EVERY probe
# fails. Return-on-first-failure is WRONG — a briefly-busy live scheduler (e.g. a GC
# pause) would false-read as quiesced. Probe budget is env-overridable (tests) and
# drift-guarded against the workflow poll window (ci-deploy.test.sh #6178).
verify_inngest_quiesced() {
  local max_attempts="${QUIESCE_PROBE_ATTEMPTS:-10}"
  local interval="${QUIESCE_PROBE_INTERVAL:-3}"
  local i served=0

  for i in $(seq 1 "$max_attempts"); do
    if curl -sf --max-time 5 http://127.0.0.1:8288/health >/dev/null 2>&1; then
      logger -t "$LOG_TAG" "INNGEST_QUIESCE: /health SERVED on attempt $i/$max_attempts — STILL RUNNING"
      served=1
      break
    fi
    logger -t "$LOG_TAG" "INNGEST_QUIESCE: /health down (attempt $i/$max_attempts)"
    sleep "$interval"
  done

  if [[ "$served" -eq 1 ]]; then
    return 1
  fi

  # /health is down across EVERY probe. ALSO require the unit to be inactive — the
  # double-fire risk is the scheduler EXECUTING queued jobs, which can outlive /health
  # in a shutdown/crash-loop window (arch P2-3). is-active is read-only (no sudo).
  if systemctl is-active --quiet inngest-server.service; then
    logger -t "$LOG_TAG" "INNGEST_QUIESCE: /health down but unit is STILL ACTIVE — not quiesced"
    return 1
  fi

  # Not-serving confirmed. Now assert NOT-enabled (the load-bearing half). is-enabled is
  # read-only (no sudo). `static` / no-[Install] / `masked` are benign (the unit cannot
  # auto-start on boot) → OK; only `enabled`/`enabled-runtime` (a live [Install] symlink)
  # is a FAIL — a mid-window reboot would re-arm the old scheduler.
  local enabled_state
  enabled_state=$(systemctl is-enabled inngest-server.service 2>/dev/null || true)
  logger -t "$LOG_TAG" "INNGEST_QUIESCE: is-enabled=${enabled_state:-<empty>}"
  if inngest_unit_enabled; then
    logger -t "$LOG_TAG" "INNGEST_QUIESCE: unit STILL ENABLED (state=$enabled_state) — a reboot would re-arm it"
    return 2
  fi
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
if [[ "$ACTION" != "deploy" ]] && [[ "$ACTION" != "restart" ]] \
   && [[ "$ACTION" != "quiesce" ]] && [[ "$ACTION" != "enable" ]]; then
  logger -t "$LOG_TAG" "REJECTED: unknown action '$ACTION'"
  echo "Error: unknown action '$ACTION'" >&2
  final_write_state 1 "action_unknown"
  exit 1
fi

if [[ "$ACTION" == "restart" ]]; then
  # restart inngest _ latest — lightweight systemctl restart (#4538).
  # Only inngest is restartable; web-platform restart is docker-level.
  if [[ "$COMPONENT" != "inngest" ]]; then
    logger -t "$LOG_TAG" "REJECTED: component '$COMPONENT' is not restartable"
    echo "Error: component '$COMPONENT' is not restartable" >&2
    final_write_state 1 "component_not_restartable"
    exit 1
  fi
  logger -t "$LOG_TAG" "ACCEPTED: restart $COMPONENT"
elif [[ "$ACTION" == "quiesce" ]]; then
  # quiesce inngest _ _ — no-SSH web-host scheduler stop+disable (#6178, op=quiesce-web).
  # Only inngest is quiescible (the dedicated-host cutover 2.2 gap).
  if [[ "$COMPONENT" != "inngest" ]]; then
    logger -t "$LOG_TAG" "REJECTED: component '$COMPONENT' is not quiescible"
    echo "Error: component '$COMPONENT' is not quiescible" >&2
    final_write_state 1 "component_not_quiescible"
    exit 1
  fi
  logger -t "$LOG_TAG" "ACCEPTED: quiesce $COMPONENT"
elif [[ "$ACTION" == "enable" ]]; then
  # enable inngest _ _ — no-SSH reverse re-enable+start (#6178, op=rollback only).
  if [[ "$COMPONENT" != "inngest" ]]; then
    logger -t "$LOG_TAG" "REJECTED: component '$COMPONENT' is not enableable"
    echo "Error: component '$COMPONENT' is not enableable" >&2
    final_write_state 1 "component_not_enableable"
    exit 1
  fi
  logger -t "$LOG_TAG" "ACCEPTED: enable $COMPONENT"
else
  # deploy action — validate image and tag
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
fi

# Serialize concurrent deploys (webhook may invoke ci-deploy.sh simultaneously).
# CI_DEPLOY_LOCK is overridable for testing; production uses /var/lock/ci-deploy.lock.
#
# FD-200 advisory flock: the lock is held by this bash process for the
# lifetime of the script. Release is implicit -- the kernel closes FD 200
# on process exit (any exit code, including SIGKILL). No manual `flock -u`
# path exists; loser writes reason="lock_contention" and exits non-zero.
# Long-running foreground docker children (prune/pull) close FD 200 via
# `200>&-` (#5062) so an orphaned child — bash SIGKILLed mid-`docker pull`
# before the TERM trap can `pkill` it — cannot hold the lock past this
# script's death. Without that, the flock outlives ci-deploy.sh and blocks
# all future deploys until a webhook restart.
# A "lock_contention" reason on a webhook retry therefore means the prior
# invocation is still in its critical section, NOT a release-path leak.
# See #3398 for the cascading-rerun pattern this serialization produces
# when the upstream poll ceiling is shorter than the realistic deploy
# window.
LOCK_FILE="${CI_DEPLOY_LOCK:-/var/lock/ci-deploy.lock}"
exec 200>"$LOCK_FILE"
flock -n 200 || {
  logger -t "$LOG_TAG" "REJECTED: another deploy in progress"
  # #6407 Defect C — observability marker for the restart/deploy lock-contention path. A
  # loser here means another deploy/restart already holds the critical section and will bring
  # the component current — benign, NOT a failure (the restart-verify poll treats
  # reason=lock_contention as non-terminal per ADR-079 #5960). Journald-only (tag ci-deploy →
  # Vector Source 4 → Better Stack). Observability ONLY — the final_write_state stamp below is
  # UNCHANGED (kept consistent with the deploy path; the consumer/poll adjudicates it).
  logger -t "$LOG_TAG" "SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action=$ACTION component=$COMPONENT outcome=deferred_to_in_flight" 2>/dev/null || true
  echo "Error: another deploy in progress" >&2
  final_write_state 1 "lock_contention"
  exit 1
}

# Initial "running" state write (issue #2199 fix 1): deferred until AFTER flock
# acquisition and SSH_ORIGINAL_COMMAND parsing so COMPONENT/IMAGE/TAG are populated.
# Writing earlier produced an empty-tag "running" state, and a loser that failed
# flock -n would write "lock_contention" over the winner's in-progress state.
write_state "$EXIT_RUNNING" "running"

# --- Restart action handler (#4538) ---
# Lightweight systemctl restart; no image pull, no disk space check needed.
if [[ "$ACTION" == "restart" ]]; then
  echo "Restarting inngest-server.service..."
  if ! sudo /usr/bin/systemctl restart inngest-server.service; then
    logger -t "$LOG_TAG" "FAILED: systemctl restart inngest-server.service"
    final_write_state 1 "inngest_restart_failed"
    exit 1
  fi

  set +e
  verify_inngest_health
  VERIFY_RC=$?
  set -e
  if [[ "$VERIFY_RC" -eq 0 ]]; then
    logger -t "$LOG_TAG" "SUCCESS: restart $COMPONENT"
    final_write_state 0 "success"
    exit 0
  else
    final_write_state 1 "inngest_health_failed"
    exit 1
  fi
fi

# --- Quiesce action handler (#6178, op=quiesce-web) ---
# No-SSH web-host scheduler stop+disable. The stop + disable are TOLERATED non-zero
# (an already-stopped/absent unit, or a unit with no [Install] section, must NOT fail
# the op) — verify_inngest_quiesced is the real gate. Each tolerated sudo call is guarded
# with `if ! sudo …; then` so a non-zero return under `set -e` cannot abort BEFORE
# final_write_state (which would leave a stale "running" state + no reason off-host —
# an hr-observability-as-plan-quality-gate regression). Mirrors the restart handler's
# set +e/-e-around-verify pattern verbatim.
if [[ "$ACTION" == "quiesce" ]]; then
  echo "Quiescing inngest-server.service (stop + disable)..."
  if ! sudo /usr/bin/systemctl stop inngest-server.service; then
    logger -t "$LOG_TAG" "INNGEST_QUIESCE: stop returned non-zero (already-stopped/absent tolerated — verify is the gate)"
  fi
  if ! sudo /usr/bin/systemctl disable inngest-server.service; then
    logger -t "$LOG_TAG" "INNGEST_QUIESCE: disable returned non-zero (no [Install]/already-disabled tolerated — the enabled-state assertion in verify is the gate)"
  fi

  set +e
  verify_inngest_quiesced
  VERIFY_RC=$?
  set -e
  case "$VERIFY_RC" in
    0) : ;;  # not-serving AND not-enabled — quiesced
    2)
      logger -t "$LOG_TAG" "FAILED: quiesce — inngest still ENABLED (reboot would re-arm)"
      final_write_state 1 "inngest_still_enabled"
      exit 1
      ;;
    *)
      logger -t "$LOG_TAG" "FAILED: quiesce — inngest still SERVING/active"
      final_write_state 1 "inngest_still_serving"
      exit 1
      ;;
  esac

  # Fan the SAME `quiesce inngest _ _` out to every peer web host over the private net
  # (mirrors the deploy fan-out; peers receive on /hooks/deploy-peer → no re-fan). A peer
  # 202 is SPAWN-ACCEPTANCE only, NOT proof the peer quiesced (the peer's own verdict lands
  # on the PEER's deploy-status slot, unreadable here — DI-C3). So a non-accepted 202 =
  # an UNREACHABLE/REJECTED peer, not an un-quiesced one. Single-host default:
  # SOLEUR_DEPLOY_PEERS unset → fan_out_to_peers returns 0 immediately (dormant).
  if ! fan_out_to_peers; then
    logger -t "$LOG_TAG" "FAILED: quiesce — a peer fan-out was NOT accepted (unreachable/rejected)"
    final_write_state 1 "quiesced_peer_fanout_unaccepted"
    exit 1
  fi

  logger -t "$LOG_TAG" "SUCCESS: quiesce $COMPONENT"
  final_write_state 0 "quiesced"
  exit 0
fi

# --- Enable action handler (#6178, op=rollback reverse) ---
# The TRUE inverse of quiesce: enable + start + verify-serving-and-enabled in ONE
# flock-held handler (fixes the two-POST enable+restart flock race — arch P1-1). `restart`
# STAYS PURE (never re-enables); only this deliberate `enable` verb re-arms, so it MUST be
# reachable ONLY via op=rollback (security regression guard). The start half reuses the
# pre-existing INNGEST_START (#5450) grant — a restart is not needed because quiesce stopped
# the unit.
if [[ "$ACTION" == "enable" ]]; then
  echo "Re-enabling inngest-server.service (enable + start)..."
  if ! sudo /usr/bin/systemctl enable inngest-server.service; then
    logger -t "$LOG_TAG" "FAILED: systemctl enable inngest-server.service"
    final_write_state 1 "inngest_enable_failed"
    exit 1
  fi
  if ! sudo /usr/bin/systemctl start inngest-server.service; then
    logger -t "$LOG_TAG" "FAILED: systemctl start inngest-server.service"
    final_write_state 1 "inngest_start_failed"
    exit 1
  fi

  set +e
  verify_inngest_health
  VERIFY_RC=$?
  set -e
  if [[ "$VERIFY_RC" -ne 0 ]]; then
    logger -t "$LOG_TAG" "FAILED: enable — inngest not serving after start"
    final_write_state 1 "inngest_reenable_unverified"
    exit 1
  fi
  # Symmetric to the quiesce verify: confirm the unit is now ENABLED (is-enabled query,
  # read-only). Not-enabled after an enable is a re-arm failure (a reboot would drop it).
  ENABLED_STATE=$(systemctl is-enabled inngest-server.service 2>/dev/null || true)
  if ! inngest_unit_enabled; then
    logger -t "$LOG_TAG" "FAILED: enable — unit is not enabled afterward (state=${ENABLED_STATE:-<empty>})"
    final_write_state 1 "inngest_reenable_unverified"
    exit 1
  fi

  if ! fan_out_to_peers; then
    logger -t "$LOG_TAG" "FAILED: enable — a peer fan-out was NOT accepted (unreachable/rejected)"
    final_write_state 1 "enabled_peer_fanout_unaccepted"
    exit 1
  fi

  logger -t "$LOG_TAG" "SUCCESS: enable $COMPONENT"
  final_write_state 0 "enabled"
  exit 0
fi

# Check available disk space (minimum 5GB required for image pull + extraction)
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
if [[ "$AVAIL_KB" -lt "$MIN_DISK_KB" ]]; then
  logger -t "$LOG_TAG" "REJECTED: insufficient disk space (${AVAIL_KB}KB available, ${MIN_DISK_KB}KB required)"
  echo "Error: insufficient disk space for deploy" >&2
  final_write_state 1 "insufficient_disk_space"
  exit 1
fi

# #6005: authenticate the host docker daemon to the now-PRIVATE GHCR packages and
# prefetch SENTRY_* into this script's env BEFORE any pull/verify. Covers BOTH the
# web-platform and inngest pull sites below. Fail-open (never aborts the deploy).
ghcr_prelude_and_login
# #6122/ADR-096: evaluate the zot dark-launch gate (probe + pull login) once, covering
# BOTH pull sites. Sets ZOT_ACTIVE; strict no-op (GHCR path) until zot is provisioned.
zot_gate_and_login

# Component-specific deploy logic
case "$COMPONENT" in
  web-platform)
    echo "Pruning unused Docker images..."
    # `200>&-` closes the FD-200 advisory lock for these long-running docker
    # children (#5062). Without it, a `docker pull` blocked on a network syscall
    # when ci-deploy-wrapper.sh SIGKILLs the script — bash cannot dispatch the
    # TERM trap mid-foreground-command, so `pkill -P $$` never runs (the caveat
    # documented at the trap above) — is orphaned, still holding FD 200. The
    # flock then outlives ci-deploy.sh for the FULL duration of the orphaned pull
    # (~40 min on a full re-pull), blocking every future deploy with
    # reason="lock_contention" until a webhook restart. Closing FD 200 for these
    # children means the kernel releases the lock the instant ci-deploy.sh dies;
    # the orphaned pull keeps running harmlessly (and warms the layer cache for
    # the next attempt). prune is included for the same reason — a slow prune on
    # a disk-full host is the same orphan class.
    docker image prune -af 200>&-
    # #6005/#6122: the pull is against a PRIVATE package (M2 SPOF). pull_image_with_fallback
    # tries zot-primary (when ZOT_ACTIVE) with an atomic GHCR fallback, reassigns IMAGE to
    # the registry that served it (so verify + run follow the same registry), and emits a
    # loud no-SSH beacon on total failure — keeps the OLD container live (downtime-safe).
    if ! pull_image_with_fallback web; then
      final_write_state 1 "image_pull_failed"
      exit 1
    fi

    # #5933 Item 4: cosign-verify the pulled image's signature (WARN mode) and run
    # the VERIFIED DIGEST at every subsequent create/run below (plugin-seed, canary,
    # production) — closes the tag-repoint TOCTOU. WARN never blocks; ENFORCE aborts,
    # keeping the OLD container live (downtime-safe). VERIFIED_REF is always a
    # runnable ref (verified digest, or the tag as a WARN fail-open fallback).
    if ! VERIFIED_REF="$(verify_image_signature "$IMAGE:$TAG")"; then
      logger -t "$LOG_TAG" "DEPLOY_ABORT: image signature verify failed (ENFORCE) for $IMAGE:$TAG — keeping previous version"
      final_write_state 1 "cosign_verify_failed"
      exit 1
    fi

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
    if ! docker create --name soleur-plugin-seed "$VERIFIED_REF" >/dev/null; then
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
    # #5934 durable substrate remediation (ADR-081): clear any residual
    # CHARACTER-DEVICE `.git/config.lock` the container filesystem substrate may
    # have left on the persistent /mnt/data/workspaces volume, BEFORE the canary
    # `docker run`. NOTE: the OLD production container is still LIVE here (it is not
    # stopped until the blue-green cutover below), so the volume is NOT quiescent —
    # safety comes from the sweep's `-type c` filter, since a live git writer's lock
    # is always a REGULAR file, never a character device (see the CONCURRENCY SAFETY
    # note in git-lock-chardevice-sweep.sh). The in-sandbox #5912 `atomic_git_config`
    # self-heal is the in-session stopgap; this removes the node at the substrate.
    # `-x`-guarded (inert until infra-config-apply delivers the sweep), `timeout`-
    # bounded (a hang on a `find`/`umount` over the LIVE volume must never freeze the
    # deploy for the whole fleet), and `|| true` (a non-zero exit never blocks a
    # deploy — a failure already shipped a loud SOLEUR_CHARDEV_SWEEP_FAILED marker).
    if [[ -x /usr/local/bin/git-lock-chardevice-sweep.sh ]]; then
      sudo timeout 60 /usr/local/bin/git-lock-chardevice-sweep.sh || true
    fi
    # NOTE (#4886 follow-up): the `.cron` subdir isolation was reverted. A
    # `mkdir -p /mnt/data/workspaces/.cron` in the deploy critical path ENOSPC-
    # fails under `set -e` when the shared volume is already full (the exact
    # state this work targets) — deadlocking the very deploy that delivers the
    # GC. CRON_WORKSPACE_ROOT stays `/workspaces`, so cron-workspace-gc sweeps
    # the SAME path the leaked `soleur-*` clones already live in; the GC's
    # `soleur-` prefix guard (UUID workspace dirs are 36-char hex, never
    # `soleur-*`) is the load-bearing protection, not the subdir. Dedicated-
    # volume isolation is deferred to #4891 (re-eval once the volume is healthy).
    ENV_FILE=$(resolve_env_file)
    # Chain the env-file cleanup with the existing state-writing EXIT trap.
    # Replacing the trap entirely would lose the "unhandled" reason capture.
    # shellcheck disable=SC2064
    trap 'rc=$?; rm -f "$ENV_FILE"; if [ "$rc" -ne 0 ] && [ ! -f "${STATE_FILE}.final" ]; then write_state "$rc" "unhandled"; fi; rm -f "${STATE_FILE}.final"' EXIT

    # Compose NODE_OPTIONS by APPENDING our heap cap to any operator-set value
    # in the Doppler env-file (#5417 review). `-e NODE_OPTIONS=...` on docker run
    # overrides `--env-file` for the same key, so a bare `-e` would silently drop
    # a Doppler-provided NODE_OPTIONS (e.g. --enable-source-maps, --dns-result-order).
    # Our --max-old-space-size comes LAST so it wins if Doppler also set one.
    DOPPLER_NODE_OPTIONS=$(grep -E '^NODE_OPTIONS=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)
    PROD_NODE_OPTIONS="${DOPPLER_NODE_OPTIONS:+$DOPPLER_NODE_OPTIONS }--max-old-space-size=$PROD_NODE_MAX_OLD_SPACE_MB"
    CANARY_NODE_OPTIONS="${DOPPLER_NODE_OPTIONS:+$DOPPLER_NODE_OPTIONS }--max-old-space-size=$CANARY_NODE_MAX_OLD_SPACE_MB"

    # Start canary on port 3001 (old container still serving on 80/3000)
    # Custom AppArmor profile: allows mount/umount/pivot_root for bwrap
    # while maintaining Docker's other security restrictions (#1570).
    # tmpfs /tmp (closes #2473): caps overlayfs COW write-amp from ~20 MB
    # pdf-linearize tempfiles and keeps /tmp ephemeral. Post-GIT_ASKPASS
    # migration (git-auth.ts), git no longer writes credential helpers
    # under /tmp — the askpass script lives in $HOME instead.
    docker run -d \
      --name soleur-web-platform-canary \
      --log-driver journald \
      --restart no \
      --memory "$CANARY_MEMORY_CAP" \
      --memory-swap "$CANARY_MEMORY_CAP" \
      --init \
      --security-opt apparmor=soleur-bwrap \
      --security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json \
      --tmpfs /tmp:rw,nosuid,nodev,size=256m \
      --env-file "$ENV_FILE" \
      --add-host host.docker.internal:host-gateway \
      -e INNGEST_BASE_URL=http://host.docker.internal:8288 \
      -e CRON_WORKSPACE_ROOT=/workspaces \
      -e SOLEUR_HOST_ID="$HOST_ID" \
      -e NODE_OPTIONS="$CANARY_NODE_OPTIONS" \
      -v /mnt/data/workspaces:/workspaces \
      -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
      -p 0.0.0.0:3001:3000 \
      "$VERIFIED_REF"

    # Layered canary probe set. Contract:
    #   knowledge-base/engineering/operations/runbooks/canary-probe-set.md
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
    #
    # NOTE: a prior change (#4932) added --unshare-user --proc /proc here to
    # mirror the cron Bash sandbox's userns+/proc path. It was reverted — that
    # synthetic invocation failed in the canary even with the host userns sysctl
    # correctly asserted (verified: the apply set the sysctl at 14:30:31, the
    # probe still failed at 14:38:43), so it does NOT track the real cron
    # capability and instead rolled back EVERY web-platform deploy. The userns
    # drift it was meant to catch is now PREVENTED at the source by the
    # boot-persistent bwrap-userns-sysctl.service unit + fresh-host trigger in
    # server.tf. A faithful, non-blocking userns/proc canary check (matched to
    # the actual claude bwrap invocation, validated against the host) is a
    # follow-up — it must not gate deploys until proven to pass on a healthy host.
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

      # Faithful sandbox canary (#5875 / ADR-079) — NON-BLOCKING dark-launch.
      # Runs the SDK-captured split-unshare argv the legacy probe above does NOT
      # exercise (that gap is why #5849 shipped green). Records a verdict + pages
      # on a faithful FAIL, but never gates/rolls back this deploy. `|| true`
      # keeps a canary hiccup from aborting the deploy under set -e.
      run_faithful_sandbox_canary || true
    fi

    if [[ "$CANARY_HEALTHY" == "true" ]]; then
      # SUCCESS: swap canary to production
      echo "Canary passed, swapping to production..."

      # --- Cron drain gate (#5669 / ADR-078) --------------------------------
      # Tear the canary down FIRST (free its CANARY_MEMORY_CAP) so the drain
      # wait does NOT hold canary + old-prod + cron resident (~6.9GB) for up to
      # ~70min on the 8GB host (platform-strategist memory-dwell fix). The canary
      # has already validated the image (health + sandbox above) and fires no
      # crons, so removing it now is safe.
      { docker stop soleur-web-platform-canary 2>/dev/null || true; }
      { docker rm soleur-web-platform-canary 2>/dev/null || true; }

      # Write the deploy lease so NEW cron runs defer (the substrate reads
      # /workspaces/.deploy-lease == this host-mounted path) — closes the
      # start-race where a fresh claude launches into the about-to-die container
      # while the loop drains the current one.
      mkdir -p "$(dirname "$CRON_DEPLOY_LEASE_FILE")" 2>/dev/null || true
      # Symlink guard (#5669 review): the lease lives in the 1001-owned,
      # container-writable /mnt/data/workspaces (claude runs arbitrary model-driven
      # code as uid 1001 there). A compromised cron child could plant a symlink at
      # the lease path; `: >` runs as root and would FOLLOW it, truncating an
      # arbitrary root-owned file. Unlink any symlink first — `rm -f` unlinks the
      # link itself without following.
      [[ -L "$CRON_DEPLOY_LEASE_FILE" ]] && rm -f "$CRON_DEPLOY_LEASE_FILE"
      : > "$CRON_DEPLOY_LEASE_FILE" 2>/dev/null \
        || logger -t "$LOG_TAG" "CRON_DRAIN: could not write lease $CRON_DEPLOY_LEASE_FILE"

      # Drain: wait for any in-flight claude child to finish before the stop,
      # bounded by CRON_DRAIN_TIMEOUT (= MAX per-function maxTurnDurationMs). The
      # `|| true` guards keep a nonzero helper from aborting the deploy (set -e).
      drain_start=$(date +%s)
      cron_drain_timed_out=false
      while cron_in_flight; do
        waited=$(( $(date +%s) - drain_start ))
        if (( waited >= CRON_DRAIN_TIMEOUT )); then
          cron_drain_timed_out=true
          report_cron_drain_timeout "$waited" || true
          break
        fi
        sleep "$CRON_DRAIN_POLL"
      done
      CRON_DRAIN_WAIT_SECS=$(( $(date +%s) - drain_start ))
      write_cron_drain_state "$CRON_DRAIN_WAIT_SECS" "$cron_drain_timed_out" || true
      logger -t "$LOG_TAG" "CRON_DRAIN: waited ${CRON_DRAIN_WAIT_SECS}s (timed_out=${cron_drain_timed_out}) before prod stop"

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
        --log-driver journald \
        --restart unless-stopped \
        --memory "$PROD_MEMORY_CAP" \
        --memory-swap "$PROD_MEMORY_CAP" \
        --init \
        --security-opt apparmor=soleur-bwrap \
        --security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json \
        --tmpfs /tmp:rw,nosuid,nodev,size=256m \
        --env-file "$ENV_FILE" \
        --add-host host.docker.internal:host-gateway \
        -e INNGEST_BASE_URL=http://host.docker.internal:8288 \
        -e CRON_WORKSPACE_ROOT=/workspaces \
        -e SOLEUR_HOST_ID="$HOST_ID" \
        -e NODE_OPTIONS="$PROD_NODE_OPTIONS" \
        -v /mnt/data/workspaces:/workspaces \
        -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
        -p 0.0.0.0:80:3000 \
        -p 0.0.0.0:3000:3000 \
        "$VERIFIED_REF"; then
        # Canary was already stopped+removed before the cron drain gate above
        # (memory-dwell fix), so no teardown is needed here on the success path.

        # Record the LOADED seccomp profile hash (#5875 item 4 / ADR-079). The
        # prod container was just started with --security-opt seccomp=<host file>,
        # so the sha256 of that file NOW is exactly what this container loaded.
        # apply-deploy-pipeline-fix.yml asserts this == sha256(committed) with no
        # SSH — the "applied ≠ loaded" gap closer. Best-effort; never gates.
        write_seccomp_profile_hash

        # Clear the deploy lease so the new container's crons resume immediately
        # (#5669 / ADR-078). Best-effort: the substrate's TTL fail-open is the
        # real backstop if a crash skips this clear, but clearing now avoids
        # deferring the next cron fire.
        rm -f "$CRON_DEPLOY_LEASE_FILE" 2>/dev/null || true

        # Inngest health sanity check (informational, #4538).
        # Non-blocking: does NOT gate deploy success.
        sleep 5
        inngest_health=$(curl -sf --max-time 5 http://127.0.0.1:8288/health 2>/dev/null || echo "")
        if [[ -n "$inngest_health" ]]; then
          logger -t "$LOG_TAG" "INNGEST_HEALTH_CHECK: ok"
        else
          logger -t "$LOG_TAG" "INNGEST_WARN: inngest-server not reachable after deploy — consider running restart-inngest-server.yml workflow"
        fi

        # bwrap userns drift detector (#4927/#4928; follow-up to #4932/#4941).
        #
        # The cron Bash sandbox (bwrap) creates an unprivileged user namespace
        # and mounts /proc; that path is gated by the host sysctl
        # kernel.apparmor_restrict_unprivileged_userns, which MUST be 0 (asserted
        # on every boot by bwrap-userns-sysctl.service, see server.tf). When it
        # drifted to 1 on 2026-06-04, every cron Bash call failed silently and
        # three producers went dark for ~2 weeks before the watchdog noticed.
        #
        # This reads the EXACT value that drifted — not a synthetic `bwrap` probe
        # with guessed flags (an earlier attempt at the latter, #4932, failed on a
        # healthy host because its invocation did not match the real sandbox, and
        # because it GATED it rolled back every deploy; reverted in #4941). Reading
        # the sysctl is unambiguous and false-positive-free.
        #
        # NON-BLOCKING by design (mirrors INNGEST_HEALTH_CHECK above): the actual
        # fix is the boot-persistent sysctl unit; this is detection only and must
        # never gate a deploy. Surfaces a loud WARN to journald → Better Stack so a
        # future drift pages within one deploy cycle instead of going dark.
        userns_restrict=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo "unreadable")
        if [[ "$userns_restrict" == "0" ]]; then
          logger -t "$LOG_TAG" "BWRAP_USERNS_SYSCTL_CHECK: ok (apparmor_restrict_unprivileged_userns=0)"
        else
          logger -t "$LOG_TAG" "BWRAP_USERNS_SYSCTL_DRIFT: apparmor_restrict_unprivileged_userns=${userns_restrict} (expected 0) — cron Bash sandbox will fail silently; restart bwrap-userns-sysctl.service"
        fi

        echo "Deploy succeeded"
        # Local prod swap succeeded — now fan out to peer hosts (dormant/no-op at
        # single-host state). A peer forward failure does NOT fail this host's
        # deploy (it succeeded); it degrades the state reason so deploy-status
        # surfaces "web-1 ok, web-2 down" (#5274 Phase 3, ADR-068).
        if fan_out_to_peers; then
          final_write_state 0 "ok"
        else
          final_write_state 0 "ok_peer_fanout_degraded"
        fi
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
    # #6005/#6122: soleur-inngest-bootstrap is ALSO a PRIVATE package. zot_gate_and_login
    # (run before the case) already evaluated the gate + logged in; pull_image_with_fallback
    # tries zot-primary with an atomic GHCR fallback, reassigns IMAGE to the served
    # registry (downstream create/inspect follow it), and emits a loud no-SSH beacon on
    # total failure.
    if ! pull_image_with_fallback inngest; then
      final_write_state 1 "image_pull_failed"
      exit 1
    fi

    # Extract the script + pinned ENV vars from the image.
    # Fixed path (not mktemp) so the sudoers entry in
    # /etc/sudoers.d/deploy-inngest-bootstrap can pin the exact path —
    # Ubuntu 24.04's sudo-rs rejects wildcards in command arguments.
    # Webhook serializes deploys; concurrent collisions not possible. (#4144)
    INNGEST_EXTRACT_DIR=/tmp/inngest-extract
    # Symlink precondition: refuse to rm -rf a symlink (would follow the
    # link and clobber unrelated paths); refuse to operate if a hostile
    # local user pre-created the dir with non-deploy ownership. Defensive
    # against TOCTOU races on world-writable /tmp.
    if [[ -L "$INNGEST_EXTRACT_DIR" ]]; then
      logger -t "$LOG_TAG" "FAILED: $INNGEST_EXTRACT_DIR is a symlink — refusing to extract"
      final_write_state 1 "inngest_extract_symlink_refused"
      exit 1
    fi
    if [[ -e "$INNGEST_EXTRACT_DIR" && "$(stat -c %U "$INNGEST_EXTRACT_DIR" 2>/dev/null)" != "$(id -un)" ]]; then
      logger -t "$LOG_TAG" "FAILED: $INNGEST_EXTRACT_DIR owned by unexpected user — refusing to extract"
      final_write_state 1 "inngest_extract_owner_mismatch"
      exit 1
    fi
    rm -rf "$INNGEST_EXTRACT_DIR"
    mkdir -m 0700 -p "$INNGEST_EXTRACT_DIR"
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
    # Vector config (TR9 PR-5 observability shipper). Optional — image
    # built before this feature lands won't have /vector.toml; the script's
    # downstream `[[ -f /tmp/vector.toml ]]` guard skips Vector install
    # gracefully when missing.
    #
    # Clear /tmp/vector.toml FIRST so a prior deploy's content can't survive
    # into this one if the docker cp silently fails. Without this rm, a
    # silent cp failure (e.g., older OCI image missing /vector.toml) made
    # the bootstrap re-install the stale prior config — surfaced 2026-05-21
    # during the Better Stack pivot when v1.1.7 deploy left the old
    # Sentry-sink config running because /tmp/vector.toml hadn't been
    # replaced.
    rm -f /tmp/vector.toml
    docker cp "$INNGEST_EXTRACT_CONTAINER:/vector.toml" /tmp/vector.toml 2>/dev/null || true
    # Durable Redis assets (#5450) — stage to /tmp like /vector.toml above. The
    # existing-host deploy runs inngest-bootstrap.sh DIRECTLY on the host (the
    # Alpine extract container has no systemctl), so it bypasses the OCI image
    # ENTRYPOINT that stages these on the fresh-host cloud-init path
    # (cloud-init.yml mirrors this same docker-cp block). Without these lines the
    # bootstrap's `[[ -f /tmp/inngest-redis.conf && ... ]]` guard is always false
    # → Redis never installs → the durable ExecStart crash-loops on 127.0.0.1:6379
    # (#5547 Gap 1, the ~3.5h #5542 outage symptom). `rm -f` FIRST so a stale
    # prior-deploy asset can't survive a silent cp failure (same defense as the
    # /tmp/vector.toml rm above). `2>/dev/null || true` keeps a pre-#5450 rollback
    # image (no /inngest-redis.* baked) functional — the bootstrap's Gap-2
    # fail-safe then keeps inngest on the SQLite-only ExecStart.
    rm -f /tmp/inngest-redis.conf /tmp/inngest-redis.service /tmp/inngest-redis-bootstrap.sh
    docker cp "$INNGEST_EXTRACT_CONTAINER:/inngest-redis.conf" /tmp/inngest-redis.conf 2>/dev/null || true
    docker cp "$INNGEST_EXTRACT_CONTAINER:/inngest-redis.service" /tmp/inngest-redis.service 2>/dev/null || true
    docker cp "$INNGEST_EXTRACT_CONTAINER:/inngest-redis-bootstrap.sh" /tmp/inngest-redis-bootstrap.sh 2>/dev/null || true
    chmod +x /tmp/inngest-redis-bootstrap.sh 2>/dev/null || true
    # Read ENV vars baked into the image at build time (see
    # .github/workflows/build-inngest-bootstrap-image.yml — ENV
    # INNGEST_CLI_VERSION=... / INNGEST_CLI_SHA256=...
    # plus VECTOR_CLI_VERSION / VECTOR_CLI_SHA256 (TR9 PR-5)).
    image_env=$(docker inspect "$IMAGE:$TAG" -f '{{range .Config.Env}}{{println .}}{{end}}')
    docker rm "$INNGEST_EXTRACT_CONTAINER" >/dev/null 2>&1 || true
    INNGEST_CLI_VERSION=$(printf '%s\n' "$image_env" | grep '^INNGEST_CLI_VERSION=' | cut -d= -f2-)
    INNGEST_CLI_SHA256=$(printf '%s\n' "$image_env" | grep '^INNGEST_CLI_SHA256=' | cut -d= -f2-)
    # `|| true` is load-bearing: ci-deploy.sh runs under `set -euo pipefail`;
    # grep-no-match returns 1, which `pipefail` propagates as the pipeline
    # exit, which `$(...)` captures as the assignment exit. set -e then exits
    # the script BEFORE final_write_state runs, and the EXIT trap writes
    # reason=unhandled. Old inngest-bootstrap images (pre-TR9 PR-5) don't carry
    # these env vars; rollback to such an image MUST stay functional. Missing
    # values flow through to the bootstrap's `${VECTOR_CLI_VERSION:-}`
    # warn-and-skip guard. Hotfix surfaced 2026-05-21 — v1.0.3 baseline rollback
    # failed with reason=unhandled after TR9 PR-5 introduced this extraction.
    VECTOR_CLI_VERSION=$(printf '%s\n' "$image_env" | grep '^VECTOR_CLI_VERSION=' | cut -d= -f2- || true)
    VECTOR_CLI_SHA256=$(printf '%s\n' "$image_env" | grep '^VECTOR_CLI_SHA256=' | cut -d= -f2- || true)
    if [[ -z "$INNGEST_CLI_VERSION" || -z "$INNGEST_CLI_SHA256" ]]; then
      logger -t "$LOG_TAG" "FAILED: image missing INNGEST_CLI_{VERSION,SHA256} ENV"
      rm -rf "$INNGEST_EXTRACT_DIR"
      final_write_state 1 "inngest_image_env_missing"
      exit 1
    fi
    chmod +x "$INNGEST_EXTRACT_DIR/inngest-bootstrap.sh"

    echo "Running inngest-bootstrap.sh on host (version=$INNGEST_CLI_VERSION, vector=${VECTOR_CLI_VERSION:-disabled})..."
    # Execute on host. The script needs root to write /etc/systemd/system,
    # /usr/local/bin/inngest, /etc/default/inngest-server, and to invoke
    # systemctl. ci-deploy.sh itself runs as the `deploy` user with sudo
    # access (see webhook.service hardening). The sudoers entry at
    # /etc/sudoers.d/deploy-inngest-bootstrap (provisioned by Terraform)
    # pins the exact command and env_keep's the four version vars (#4144 + TR9 PR-5).
    export INNGEST_CLI_VERSION INNGEST_CLI_SHA256 VECTOR_CLI_VERSION VECTOR_CLI_SHA256
    # Capture stderr to a file so a non-zero exit's last lines are surfaced
    # via cat-deploy-state (no-SSH debugging per hr-no-ssh-fallback-in-runbooks
    # and the TR9 PR-5 observability stack). The bootstrap script logs to
    # journald + stdout; stderr captures bash's own diagnostics (set -x,
    # syntax errors, unbound var traps) which journald wouldn't show.
    BOOTSTRAP_STDERR=/tmp/inngest-bootstrap-stderr.log
    rm -f "$BOOTSTRAP_STDERR"
    if ! sudo --preserve-env=INNGEST_CLI_VERSION,INNGEST_CLI_SHA256,VECTOR_CLI_VERSION,VECTOR_CLI_SHA256 \
        /usr/bin/bash /tmp/inngest-extract/inngest-bootstrap.sh 2> "$BOOTSTRAP_STDERR"; then
      # Extract a SHORT (≤400 char) reason suffix from the stderr tail so
      # cat-deploy-state's JSON reason field carries actionable detail.
      # Strip control bytes that would break JSON encoding.
      stderr_tail=$(tail -c 600 "$BOOTSTRAP_STDERR" 2>/dev/null \
        | tr -d '\r' | tr '\n' '|' | tr -dc '[:print:]|' | tail -c 400)
      logger -t "$LOG_TAG" "FAILED: inngest-bootstrap.sh non-zero exit; stderr_tail=${stderr_tail}"
      rm -rf "$INNGEST_EXTRACT_DIR"
      # Reason field carries the stderr tail so cat-deploy-state surfaces it
      # via /hooks/deploy-status without requiring SSH to journalctl.
      final_write_state 1 "inngest_bootstrap_failed:${stderr_tail}"
      exit 1
    fi

    rm -rf "$INNGEST_EXTRACT_DIR"

    # Post-bootstrap health gate (#4652, reframed #5159). The bootstrap restarts
    # inngest-server with the new ExecStart (--poll-interval / --sdk-url). The
    # HARD gate is /health (process liveness) — verify_inngest_health returns 1
    # only when /health is unreachable. The cron-plan probe inside it is ADVISORY:
    # deploying the INNGEST image cannot re-arm web-platform crons (only a
    # web-platform redeploy mints a new appVersion → modified:true sync that
    # re-arms; a standalone inngest restart de-plans crons until that or the
    # --poll-interval self-heal — proven #5159, the loopback PUT is a
    # modified:false no-op). So a de-planned registry here is NOT a deploy
    # failure; persistent de-plans are caught out-of-band by the Sentry cron
    # monitors (apps/web-platform/infra/sentry/cron-monitors.tf, failure_issue
    # _threshold=1). See the H9 runbook for redeploy/poll recovery.
    set +e
    verify_inngest_health
    VERIFY_RC=$?
    set -e
    if [[ "$VERIFY_RC" -ne 0 ]]; then
      logger -t "$LOG_TAG" "FAILED: inngest deploy /health liveness check (cron-plan is advisory post-#5159)"
      final_write_state 1 "inngest_health_failed"
      exit 1
    fi

    # #5547 Gap 3: distinguish a degraded-durability deploy (SQLite-only
    # fail-safe — Redis not ready) from a healthy durable one so
    # /hooks/deploy-status .reason surfaces it without SSH. The bootstrap exits 0
    # in both cases (the server stays available). The AUTHORITATIVE signal is the
    # WRITTEN ExecStart lacking the --postgres-max-open-conns durable sentinel
    # (re-derived below; #5560 — the postgres/redis URIs are env-delivered now, so
    # the non-secret --postgres-max-open-conns flag is the durable marker on argv).
    # The bootstrap-stderr INNGEST_DURABLE_DEGRADED marker is only a SECONDARY
    # cross-check OR'd in here: the legacy stderr-tail→reason path (line ~957)
    # fires only on a NON-zero bootstrap exit, so on this 0-exit success path the
    # marker is not the load-bearing carrier — the ExecStart re-derivation is.
    inngest_exec_start=$(systemctl show -p ExecStart inngest-server.service 2>/dev/null || true)
    if [[ "$inngest_exec_start" != *'--postgres-max-open-conns'* ]] \
       || grep -q 'INNGEST_DURABLE_DEGRADED' "$BOOTSTRAP_STDERR" 2>/dev/null; then
      logger -t "$LOG_TAG" "SUCCESS: inngest $IMAGE:$TAG deployed (degraded durability — SQLite-only; durable Redis not ready, #5547)"
      final_write_state 0 "success_degraded_durability"
    else
      logger -t "$LOG_TAG" "SUCCESS: inngest $IMAGE:$TAG deployed"
      final_write_state 0 "success"
    fi
    ;;
  *)
    logger -t "$LOG_TAG" "ERROR: no deploy handler for '$COMPONENT'"
    echo "Error: no deploy handler for '$COMPONENT'" >&2
    final_write_state 1 "no_handler"
    exit 1
    ;;
esac
