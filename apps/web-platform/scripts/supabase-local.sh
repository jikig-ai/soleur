#!/usr/bin/env bash
# supabase-local.sh — bind the local Supabase dev stack to loopback, and prove it.
#
# WHY THIS SCRIPT EXISTS (ADR-153)
# --------------------------------
# The Supabase CLI exposes NO bind-address setting. `config.toml` has `port` keys
# and nothing else; `internal/utils/docker.go` sets PortBindings with no HostIP, so
# Docker's default (0.0.0.0 + ::) always applies. Upstream implemented a bind option
# (supabase/cli#4613) and CLOSED IT UNMERGED on 2025-12-23 as a deliberate policy
# call, with the maintainer prescribing "lean on docker network" instead. So this
# wrapper is the vendor-documented remedy and is PERMANENT — not a stopgap awaiting
# a CLI upgrade. Do not "simplify" it away by adding a config.toml setting; there
# isn't one, and a line that looks like one would silently do nothing.
#
# DECOY: `SUPABASE_SERVICES_HOSTNAME` (newer CLI) reads like a bind knob. It is
# dial-side only — it changes which host the CLI CONNECTS TO for health checks.
# It does not affect what containers bind to.
#
# USAGE
#   supabase-local.sh assert          # verify loopback-only binding; the gate
#   supabase-local.sh <any supabase subcommand> [args...]
#                                     # passthrough with --network-id applied
#   supabase-local.sh --help
#
# EXIT CODES (assert)
#   0  loopback-only, or no stack running (nothing to assert)
#   1  EXPOSED — at least one published port is reachable off-loopback
#   2  UNKNOWN — docker unreachable. Never conflated with 0: an unreachable
#      daemon is not evidence of safety.
#
# Dependencies: docker. (No jq — the assert path parses with grep so it runs in
# the minimal PATH the test harness and CI provide.)

set -euo pipefail

NETWORK_NAME="${SUPABASE_LOCAL_NETWORK:-supabase-local-loopback}"
LOOPBACK_IPV4="127.0.0.1"
CLI_PROJECT_LABEL="com.supabase.cli.project"

usage() {
  cat <<'EOF'
supabase-local.sh — loopback-bound wrapper for the local Supabase stack (ADR-153)

  supabase-local.sh assert
      Verify every published port of every running Supabase container is bound
      to loopback. Exit 0 = OK or no stack, 1 = EXPOSED, 2 = docker unreachable.

  supabase-local.sh start|stop|status|db ...|migration ...|gen ...
      Passthrough to the Supabase CLI with --network-id applied, so containers
      publish to 127.0.0.1 instead of 0.0.0.0.

  supabase-local.sh --help
      This message.

The Supabase CLI has no bind-address setting (upstream PR supabase/cli#4613 was
closed unmerged on policy). A dedicated Docker network carrying
com.docker.network.bridge.host_binding_ipv4=127.0.0.1 is the vendor-documented
remedy. See ADR-153.
EOF
}

# ---------------------------------------------------------------------------
# assert — the gate.
#
# Reads NetworkSettings.Ports, NOT HostConfig.PortBindings. PortBindings reports
# an empty HostIp for BOTH the wildcard and the loopback-bound state, so a gate
# reading it cannot distinguish them (the proxy trap). NetworkSettings.Ports is
# the resolved view.
#
# Fail-closed: any HostIp that is not explicitly loopback — including an EMPTY
# one — counts as exposed.
# ---------------------------------------------------------------------------
cmd_assert() {
  local ids ps_rc inspect_out host_ips exposed=0 checked=0 containers=0

  set +e
  ids="$(docker ps --filter "label=${CLI_PROJECT_LABEL}" --format '{{.ID}}' 2>/dev/null)"
  ps_rc=$?
  set -e
  if [[ "$ps_rc" -ne 0 ]]; then
    echo "supabase-local: UNKNOWN — cannot reach the Docker daemon." >&2
    echo "supabase-local: an unreachable daemon is not evidence of safe binding." >&2
    return 2
  fi

  if [[ -z "${ids//[[:space:]]/}" ]]; then
    # No stack running. Nothing to assert — stay silent so the SessionStart
    # hook does not nag on every session.
    return 0
  fi

  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    containers=$((containers + 1))
    set +e
    inspect_out="$(docker inspect --format '{{json .NetworkSettings.Ports}}' "$id" 2>/dev/null)"
    set -e

    # Extract every HostIp OCCURRENCE, keeping the full `"HostIp":"..."` match
    # rather than the extracted value.
    #
    # LOAD-BEARING: an empty HostIp ("HostIp":"") is a REAL wildcard binding on
    # some Docker versions. Extracting values first makes it an empty string,
    # which an emptiness check then reads as "this container publishes nothing"
    # — silently skipping the exact state this gate exists to catch (fail-open).
    # Matching on the occurrence keeps an empty value observable.
    #
    # A "<port>/tcp": null entry (declared but unpublished — 6 of 11 supabase
    # containers do this) produces no match at all and is correctly skipped.
    host_ips="$(grep -oE '"HostIp":"[^"]*"' <<<"$inspect_out" || true)"
    [[ -n "$host_ips" ]] || continue

    local match ip
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      ip="${match#\"HostIp\":\"}"
      ip="${ip%\"}"
      checked=$((checked + 1))
      case "$ip" in
        "$LOOPBACK_IPV4"|"::1")
          ;;
        *)
          exposed=$((exposed + 1))
          echo "supabase-local: EXPOSED — container ${id} publishes on '${ip}' (not loopback)." >&2
          ;;
      esac
    done <<<"$host_ips"
  done <<<"$ids"

  if [[ "$exposed" -gt 0 ]]; then
    echo "supabase-local: ${exposed} of ${checked} published binding(s) across ${containers} container(s) are OFF-LOOPBACK." >&2
    echo "supabase-local: remediate with  npm run db:stop && npm run db:start  (see ADR-153)." >&2
    return 1
  fi

  echo "supabase-local: OK — ${checked} published binding(s) across ${containers} container(s), all loopback."
  return 0
}

# ---------------------------------------------------------------------------
# ensure_network — create the loopback-bound network if absent or wrong.
#
# Verifies by VALUE, not mere existence: a pre-existing same-name network
# without the option would silently publish on 0.0.0.0.
# ---------------------------------------------------------------------------
ensure_network() {
  local existing opt
  set +e
  existing="$(docker network ls --filter "name=^${NETWORK_NAME}$" --format '{{.Name}}' 2>/dev/null)"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "supabase-local: cannot reach the Docker daemon; refusing to start." >&2
    exit 2
  fi

  if [[ -n "${existing//[[:space:]]/}" ]]; then
    set +e
    opt="$(docker network inspect "$NETWORK_NAME" \
             --format '{{index .Options "com.docker.network.bridge.host_binding_ipv4"}}' 2>/dev/null)"
    set -e
    if [[ "${opt//[[:space:]]/}" == "$LOOPBACK_IPV4" ]]; then
      return 0
    fi
    echo "supabase-local: network '${NETWORK_NAME}' exists without the loopback binding option — recreating." >&2
    if ! docker network rm "$NETWORK_NAME" >/dev/null 2>&1; then
      echo "supabase-local: FAILED to remove the mis-configured network. Aborting rather than" >&2
      echo "supabase-local: starting a stack that would publish on 0.0.0.0." >&2
      exit 2
    fi
  fi

  if ! docker network create \
        -o "com.docker.network.bridge.host_binding_ipv4=${LOOPBACK_IPV4}" \
        "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "supabase-local: FAILED to create the loopback-bound network '${NETWORK_NAME}'." >&2
    echo "supabase-local: aborting — refusing to fall back to a 0.0.0.0-published stack." >&2
    exit 2
  fi
}

main() {
  case "${1:-}" in
    ""|--help|-h|help)
      usage
      return 0
      ;;
    assert)
      cmd_assert
      return $?
      ;;
    *)
      command -v supabase >/dev/null 2>&1 || {
        echo "supabase-local: the 'supabase' CLI is not on PATH." >&2
        exit 127
      }
      ensure_network
      # --network-id MUST precede "$@" so subcommands using `--` passthrough
      # (e.g. `db lint -- --strict`) still parse correctly.
      exec supabase --network-id "$NETWORK_NAME" "$@"
      ;;
  esac
}

main "$@"
