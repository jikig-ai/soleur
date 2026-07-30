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
#   2  UNKNOWN — the binding could not be verified (docker unreachable, or a
#      container could not be inspected). Never conflated with 0: an unreachable
#      daemon is not evidence of safety. `ensure_network` also uses 2 for
#      "cannot create/remove the network" — in both cases the stack was NOT
#      started, so the safe reading is identical: nothing is running unverified.
# 127  the `supabase` CLI is not on PATH (passthrough only).
#
# Dependencies: docker. (No jq — the assert path parses with grep so it runs in
# the minimal PATH the test harness and CI provide.)

set -euo pipefail

_DEFAULT_NETWORK="supabase-local-loopback"  # suffixed with project_id below
LOOPBACK_IPV4="127.0.0.1"
LOOPBACK_IPV6="::1"
# Marks networks THIS script created, so it never deletes one it does not own.
OWNER_LABEL="com.soleur.supabase-local"
CLI_PROJECT_LABEL="com.supabase.cli.project"
# Single-sourced: a typo in either the read or the write site alone would
# silently degrade every invocation into a recreate-then-create loop.
HOST_BINDING_KEY="com.docker.network.bridge.host_binding_ipv4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Scope the gate to THIS project's stack. Filtering on the label KEY alone
# matches every Supabase CLI stack on the host, so the hook would warn about an
# unrelated repo's stack while prescribing an `npm run db:stop` that cannot fix
# it. Derived from config.toml — never a hardcoded string repeated in two
# places (the CLI sets this label from the same value).
_project_id() {
  local cfg="${SCRIPT_DIR}/../supabase/config.toml" id=""
  if [[ -r "$cfg" ]]; then
    id="$(sed -nE 's/^[[:space:]]*project_id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$cfg" | head -1)"
  fi
  printf '%s' "$id"
}
PROJECT_ID="${SUPABASE_LOCAL_PROJECT_ID:-$(_project_id)}"
# Project-scoped: Supabase containers carry the DNS aliases `db` /
# `db.supabase.internal`, so two projects sharing one bridge round-robin
# between each other's Postgres. The CLI's own default is per-project too.
[[ -n "$PROJECT_ID" ]] && _DEFAULT_NETWORK="${_DEFAULT_NETWORK}-${PROJECT_ID}"
NETWORK_NAME="${SUPABASE_LOCAL_NETWORK:-$_DEFAULT_NETWORK}"
# Fall back to the key-only filter if config.toml is unreadable: a WIDER scope
# errs toward warning about someone else's stack, never toward missing our own.
if [[ -n "$PROJECT_ID" ]]; then
  PS_LABEL_FILTER="${CLI_PROJECT_LABEL}=${PROJECT_ID}"
else
  PS_LABEL_FILTER="${CLI_PROJECT_LABEL}"
fi

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
  local ids ps_rc inspect_out inspect_rc host_ips grep_rc
  local exposed=0 checked=0 containers=0 unknown=0

  set +e
  ids="$(docker ps --filter "label=${PS_LABEL_FILTER}" --format '{{.ID}}' 2>/dev/null)"
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
    inspect_rc=$?
    set -e

    # A container we could not inspect is UNKNOWN, never SAFE. Discarding this
    # rc reported "OK — all loopback" for a container whose bindings were never
    # read (e.g. it died between `docker ps` and `docker inspect`) — a fail-open
    # in the gate itself, and a direct contradiction of the exit-code contract
    # at the top of this file. Counted, not returned immediately, so a DEFINITE
    # exposure elsewhere still outranks it (1 beats 2 — see the verdict below).
    if [[ "$inspect_rc" -ne 0 ]]; then
      unknown=$((unknown + 1))
      echo "supabase-local: UNKNOWN — cannot inspect container ${id} (rc=${inspect_rc})." >&2
      continue
    fi

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
    # rc 1 = no match (legitimate: the `"8080/tcp":null` case). rc>=2 = grep
    # ERROR, and 127 = grep absent — this file's header advertises running in a
    # minimal PATH, which is exactly where a missing tool is plausible. `|| true`
    # collapsed all three into "no bindings" and returned OK over a 0.0.0.0 stack.
    set +e
    host_ips="$(grep -oE '"HostIp":"[^"]*"' <<<"$inspect_out")"
    grep_rc=$?
    set -e
    if [[ "$grep_rc" -ge 2 ]]; then
      unknown=$((unknown + 1))
      echo "supabase-local: UNKNOWN — HostIp parse failed for ${id} (grep rc=${grep_rc})." >&2
      continue
    fi
    [[ -n "$host_ips" ]] || continue

    local match ip
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      ip="${match#\"HostIp\":\"}"
      ip="${ip%\"}"
      checked=$((checked + 1))
      case "$ip" in
        # The whole 127.0.0.0/8 range plus both IPv6 loopback spellings. Matching
        # two literals reported 127.0.0.53 and 0:0:0:0:0:0:0:1 as EXPOSED — the
        # safe direction, but a tripwire that cries wolf is a tripwire that gets
        # ignored.
        127.*|"$LOOPBACK_IPV6"|0:0:0:0:0:0:0:1)
          ;;
        *)
          exposed=$((exposed + 1))
          echo "supabase-local: EXPOSED — container ${id} publishes on '${ip}' (not loopback)." >&2
          ;;
      esac
    done <<<"$host_ips"
  done <<<"$ids"

  # Verdict precedence: a DEFINITE exposure (1) outranks an UNKNOWN (2), which
  # outranks OK (0). Never collapse unknown into ok.
  if [[ "$exposed" -gt 0 ]]; then
    echo "supabase-local: ${exposed} of ${checked} published binding(s) across ${containers} container(s) are OFF-LOOPBACK." >&2
    echo "supabase-local: remediate with  npm run db:stop && npm run db:start  (see ADR-153)." >&2
    return 1
  fi

  # POSITIVE-EVIDENCE FLOOR. Containers were found but NOTHING was parsed out of
  # them: the parse produced no evidence, which is not the same as evidence of
  # safety. This is the ROOT of the empty-HostIp bug fixed earlier — that fix
  # patched one instance; this closes the class. Demonstrated shapes that
  # otherwise returned OK over a 0.0.0.0 stack: a space after the JSON colon,
  # differing key case (`hostIP`), a truncated value, empty output, and literal
  # `null` — all with `docker inspect` exiting 0.
  if [[ "$containers" -gt 0 && "$checked" -eq 0 && "$unknown" -eq 0 ]]; then
    echo "supabase-local: UNKNOWN — ${containers} container(s) yielded no parsable" >&2
    echo "supabase-local: HostIp. The binding was NOT verified (parse produced nothing)." >&2
    return 2
  fi

  if [[ "$unknown" -gt 0 ]]; then
    echo "supabase-local: UNKNOWN — ${unknown} of ${containers} container(s) could not be inspected; binding not verified." >&2
    return 2
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
             --format "{{index .Options \"${HOST_BINDING_KEY}\"}}" 2>/dev/null)"
    set -e
    if [[ "${opt//[[:space:]]/}" == "$LOOPBACK_IPV4" ]]; then
      return 0
    fi
    # NEVER remove a network this script did not create. SUPABASE_LOCAL_NETWORK
    # is operator-overridable, so without this guard pointing it at an existing
    # network (e.g. a compose project's `myapp_default`) would DESTROY that
    # network on the next invocation. Verified reproducible.
    local owned
    owned="$(docker network inspect "$NETWORK_NAME" \
               --format "{{index .Labels \"${OWNER_LABEL}\"}}" 2>/dev/null || true)"
    if [[ "${owned//[[:space:]]/}" != "1" ]]; then
      echo "supabase-local: network '${NETWORK_NAME}' exists, lacks the loopback binding" >&2
      echo "supabase-local: option, and was NOT created by this script (no ${OWNER_LABEL} label)." >&2
      echo "supabase-local: refusing to delete a network we do not own. Remove it yourself," >&2
      echo "supabase-local: or set SUPABASE_LOCAL_NETWORK to an unused name." >&2
      exit 2
    fi
    echo "supabase-local: network '${NETWORK_NAME}' exists without the loopback binding option — recreating." >&2
    if ! docker network rm "$NETWORK_NAME" >/dev/null 2>&1; then
      echo "supabase-local: FAILED to remove the mis-configured network. Aborting rather than" >&2
      echo "supabase-local: starting a stack that would publish on 0.0.0.0." >&2
      exit 2
    fi
  fi

  if ! docker network create \
        -o "${HOST_BINDING_KEY}=${LOOPBACK_IPV4}" \
        --label "${OWNER_LABEL}=1" \
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
      ;;
    *)
      command -v supabase >/dev/null 2>&1 || {
        echo "supabase-local: the 'supabase' CLI is not on PATH." >&2
        exit 127
      }
      # Only ensure the network for verbs that can CREATE containers.
      #
      # LOAD-BEARING: `docker network rm` fails while containers are attached,
      # so running ensure_network on `stop` aborted with "refusing to start"
      # and never invoked the CLI — and `db:stop` is the FIRST HALF of the
      # remediation both this script and the SessionStart hook prescribe. The
      # guard would hard-fail in exactly the mis-configured state it exists to
      # remediate from. `status` is read-only and must work with the daemon in
      # any state.
      case "${1:-}" in
        stop|status) ;;
        *) ensure_network ;;
      esac
      # --network-id MUST precede "$@" so subcommands using `--` passthrough
      # (e.g. `db lint -- --strict`) still parse correctly.
      exec supabase --network-id "$NETWORK_NAME" "$@"
      ;;
  esac
}

main "$@"
