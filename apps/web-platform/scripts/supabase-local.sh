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
# POST-START DEFAULT-PRIVILEGE NORMALIZE (ADR-303)
# ----------------------------------------------
# On 2026-10-30 hosted Supabase stops auto-granting Data API access to NEW
# `public`-schema tables (changelog 45329). A local stack that still installs
# the old default privileges makes the rls-authz-fuzz gate measure PLATFORM
# DEFAULTS, not migration GRANTs — a circular proof (P6). So on every
# start-class verb (`start`, `db start`, `db reset` — reset recreates the
# database and reinstalls the bootstrap defacls) this wrapper runs `supabase`
# WITHOUT exec, then applies Supabase's documented revoke-default-privileges
# SQL inside the running db container, and fails LOUD if the normalized state
# cannot be established. The `[api] auto_expose_new_tables` config key does NOT exist on
# pinned CLI 2.84.2 (added by supabase/cli#5239, merged 2026-05-26, post-2.84.2)
# — do not "simplify" this into a config.toml line; dead config at best, a
# parse failure at worst. On any CLI bump to >=v2.116.0 the declarative key
# becomes REQUIRED instead (unset re-enables auto-expose, per cli#6337).
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
#      The post-start normalize uses 2 as well: the stack came up but its
#      default privileges could NOT be proven normalized — reporting a green
#      `start` for a stack still carrying bootstrap auto-grants would silently
#      degrade the rls-authz-fuzz grant gate into measuring platform defaults.
# 127  the `supabase` CLI is not on PATH (passthrough only).
#
# Dependencies: docker. (No jq — the assert path parses with grep so it runs in
# the minimal PATH the test harness and CI provide. The post-start normalize
# likewise runs psql INSIDE the db container via `docker exec`, so no host-side
# psql is needed — CI installs postgresql-client only after `start`.)

set -euo pipefail

_DEFAULT_NETWORK="supabase-local-loopback"  # suffixed with project_id below
LOOPBACK_IPV4="127.0.0.1"
LOOPBACK_IPV6="::1"
# Marks networks THIS script created, so it never deletes one it does not own.
OWNER_LABEL="com.soleur.supabase-local"
CLI_PROJECT_LABEL="com.supabase.cli.project"
REQUIRE_STACK=0
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

  supabase-local.sh assert [--require-stack]
      Verify every published port of every running Supabase container is bound
      to loopback. Exit 0 = OK or no stack, 1 = EXPOSED, 2 = could not verify.
      --require-stack makes "no containers" an error (2) instead of a pass —
      use it in CI, where a stopped stack means `start` silently did nothing.

  supabase-local.sh start|stop|status|db ...|migration ...|gen ...
      Passthrough to the Supabase CLI with --network-id applied, so containers
      publish to 127.0.0.1 instead of 0.0.0.0. Start-class verbs (`start`,
      `db start`, `db reset`) additionally normalize default privileges —
      new public relations get no automatic api-role grants (ADR-303).

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
    # No stack running.
    #
    # The two callers want OPPOSITE things here, so this is a flag, not a
    # default. The SessionStart hook fires on every session and a stopped stack
    # is the normal case, so silence + 0 is correct there. CI runs `assert`
    # immediately after `start`, where zero containers means the start silently
    # produced nothing — a pass would be a false all-clear on the gate that
    # authorises seeding the runner. Plan T3 specified the CI reading; the hook
    # reading was added at implementation time and the divergence is resolved
    # here rather than left as an undocumented contradiction.
    if [[ "$REQUIRE_STACK" == "1" ]]; then
      echo "supabase-local: NO_CONTAINERS — --require-stack was set but no" >&2
      echo "supabase-local: ${CLI_PROJECT_LABEL} containers are running." >&2
      return 2
    fi
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

# ---------------------------------------------------------------------------
# ensure_snippets_dir — pre-create the Studio SQL-snippets bind-mount source
# as the invoking user, so the container runtime never has to.
#
# On Linux, a bind-mount source directory that does not yet exist is created
# by the DAEMON (root), independent of which user the container process runs
# as. The Supabase CLI bind-mounts `supabase/snippets` into Studio on every
# `start`, so a worktree that has never run the stack gets a root:root
# directory the very first time it does — and an unprivileged `rm -rf` on the
# worktree afterward cannot unlink entries inside it (#7114). A bind-mount
# source that already exists keeps its existing ownership, so creating it as
# the current user before the daemon ever sees a missing path is the
# producer-side fix — this closes the class rather than remediating it after
# the fact.
# ---------------------------------------------------------------------------
ensure_snippets_dir() {
  mkdir -p "${SCRIPT_DIR}/../supabase/snippets"
}

# ---------------------------------------------------------------------------
# normalize_default_privileges — flip the fresh stack to post-2026-10-30
# default privileges (ADR-303, PRIMARY mechanism per the 2026-10-26 CTO ruling;
# the [api] auto_expose_new_tables key does not exist on pinned CLI 2.84.2).
#
# Applies Supabase's documented "Revoke default privileges" SQL
# <!-- verified: 2026-10-27 source: https://supabase.com/docs/guides/api/securing-your-api -->
# for the migration role (`postgres` — the docs' verbatim form), then sweeps
# for every OTHER pg_default_acl owner whose entries still grant the api roles
# on public tables/sequences (the ruling's "owner set may be broader"
# catch-all).
#
# ROLE THE PSQL SESSION RUNS AS — load-bearing. On the pinned image the
# bootstrap defacl entries in `public` are owned by `supabase_admin`, NOT by
# `postgres`, and `ALTER DEFAULT PRIVILEGES FOR ROLE <other>` requires
# superuser or membership in that role — a `psql -U postgres` session CANNOT
# alter supabase_admin's defacls, so the sweep raised mid-run, ON_ERROR_STOP
# fired, and `start` exited 2 on a correctly-functioning stack (CI run
# 121583902510). `supabase_admin` IS the image's superuser, so a session under
# it can alter its own AND postgres's defacls; the docker-exec'd psql uses
# in-container trust auth, so `-U supabase_admin` needs no password. The docs'
# two FUNCTION statements are
# deliberately omitted: the 10-30 flip does not change function defaults, the
# in-schema form is inert against the built-in PUBLIC EXECUTE default
# (supabase#49338), and the schema-less `revoke execute on functions from
# public` goes BEYOND the flip — it would strip the PUBLIC EXECUTE default the
# migration corpus's SECURITY DEFINER RPCs rely on (that surface is governed by
# ADR-112's own two-tier guard, not this one).
#
# Runs psql INSIDE the db container (precedent:
# learnings/2026-07-11 §4 — `docker exec -i supabase_db_<project> psql`), so no
# host-side psql is required: the fuzz CI job installs postgresql-client only
# AFTER `start`. The closing DO block re-reads pg_default_acl and RAISES if any
# api-role default table/sequence privilege remains — the normalize fails loud
# rather than letting `start` report green over a stack whose grant state the
# fuzz gate would misread as migration-authored.
# ---------------------------------------------------------------------------
normalize_default_privileges() {
  # Locate THIS project's db container by the same label the assert gate scopes
  # on, so a second stack on the host cannot receive our revokes.
  local db_id ps_rc
  db_id=""
  set +e
  db_id="$(docker ps --filter "label=${PS_LABEL_FILTER}" --filter "name=supabase_db" --format '{{.ID}}' 2>/dev/null | head -1)"
  ps_rc=$?
  set -e
  if [[ "$ps_rc" -ne 0 ]]; then
    echo "supabase-local: post-start normalize — cannot reach the Docker daemon to locate" >&2
    echo "supabase-local: the db container; default privileges were NOT normalized." >&2
    return 2
  fi
  if [[ -z "${db_id//[[:space:]]/}" ]]; then
    echo "supabase-local: post-start normalize — no supabase_db container found for this" >&2
    echo "supabase-local: stack (label ${PS_LABEL_FILTER}). Refusing to report a successful" >&2
    echo "supabase-local: start while default privileges are unverified." >&2
    return 2
  fi

  if ! docker exec -i "$db_id" psql -U supabase_admin -d postgres --no-psqlrc -v ON_ERROR_STOP=1 <<'NORMALIZE_SQL'; then
-- Supabase's documented "Revoke default privileges" statements, verbatim in
-- the `for role postgres` form (securing-your-api; `postgres` is the migration
-- role). The bootstrap defacl owner on the pinned image is `supabase_admin` —
-- the owner-agnostic sweep below reaches it and any other owner; the psql
-- session itself runs AS `supabase_admin` (the image's superuser) because
-- `postgres` cannot `alter default privileges for role` another role.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

-- Owner-agnostic sweep: any OTHER pg_default_acl owner (e.g. a supabase_admin
-- entry the image bootstrapped) whose entries still confer api-role default
-- table/sequence privileges in `public` gets the same revoke. aclexplode
-- grantee 0 is PUBLIC — a PUBLIC default grant reaches every api role.
do $$
declare
  o record;
begin
  for o in
    select distinct own.rolname as owner_name
    from pg_default_acl d
    join pg_roles own on own.oid = d.defaclrole
    join pg_namespace ns on ns.oid = d.defaclnamespace
    where ns.nspname = 'public'
      and d.defaclobjtype in ('r', 'S')
      and exists (
        select 1
        from aclexplode(d.defaclacl) a
        left join pg_roles g on g.oid = a.grantee
        where a.grantee = 0
           or g.rolname in ('anon', 'authenticated', 'service_role')
      )
  loop
    execute format(
      'alter default privileges for role %I in schema public revoke all on tables from anon, authenticated, service_role',
      o.owner_name);
    execute format(
      'alter default privileges for role %I in schema public revoke all on sequences from anon, authenticated, service_role',
      o.owner_name);
  end loop;
end $$;

-- Fail-closed proof, in the same session: if ANY api-role (or PUBLIC) default
-- table/sequence privilege survives in `public` — an owner the sweep could not
-- alter, a defacl shape the sweep missed — raise rather than let `start`
-- report green over an un-normalized stack. The rls-authz-fuzz gate re-asserts
-- this state independently; this is the start-side half.
do $$
declare
  bad int;
begin
  select count(*) into bad
  from pg_default_acl d
  join pg_namespace ns on ns.oid = d.defaclnamespace
  where ns.nspname = 'public'
    and d.defaclobjtype in ('r', 'S')
    and exists (
      select 1
      from aclexplode(d.defaclacl) a
      left join pg_roles g on g.oid = a.grantee
      where a.grantee = 0
         or g.rolname in ('anon', 'authenticated', 'service_role')
    );
  if bad > 0 then
    raise exception 'supabase-local normalize: % api-role default table/sequence privilege(s) remain in pg_default_acl after revoke', bad;
  end if;
end $$;
NORMALIZE_SQL
    echo "supabase-local: post-start normalize FAILED — the stack's default privileges could" >&2
    echo "supabase-local: not be proven normalized. Reporting start as failed rather than letting" >&2
    echo "supabase-local: the fuzz gate measure platform defaults as if they were migration grants." >&2
    return 2
  fi
  echo "supabase-local: normalized default privileges — new public relations/sequences get no automatic api-role grants (ADR-303)."
  return 0
}

main() {
  case "${1:-}" in
    ""|--help|-h|help)
      usage
      return 0
      ;;
    assert)
      [[ "${2:-}" == "--require-stack" ]] && REQUIRE_STACK=1
      cmd_assert
      ;;
    *)
      command -v supabase >/dev/null 2>&1 || {
        echo "supabase-local: the 'supabase' CLI is not on PATH." >&2
        exit 127
      }
      # Only ensure the network (and the snippets bind-mount source) for verbs
      # that can CREATE containers.
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
        *) ensure_network; ensure_snippets_dir ;;
      esac
      # Start-class verbs (`start`, `db start`, `db reset`) get the post-start
      # normalize: run `supabase` WITHOUT exec so the wrapper survives to apply
      # the revoke-default-privileges SQL, then propagate the start verb's own
      # exit code. `db reset` belongs here because it recreates the database —
      # the image bootstrap's defacl entries come back with it, and without a
      # re-normalize the fuzz gate silently resumes measuring platform
      # defaults. A failing start skips the normalize — the stack never
      # provably came up, so start's own nonzero is the correct (and already
      # loud) verdict; a normalize that cannot prove the pg_default_acl state
      # fails the whole verb (never a quiet green over bootstrap defaults).
      _start_class=0
      case "${1:-}" in
        start) _start_class=1 ;;
        db) [[ "${2:-}" == "start" || "${2:-}" == "reset" ]] && _start_class=1 ;;
      esac
      if [[ "$_start_class" == "1" ]]; then
        set +e
        supabase --network-id "$NETWORK_NAME" "$@"
        start_rc=$?
        set -e
        if [[ "$start_rc" -ne 0 ]]; then
          exit "$start_rc"
        fi
        # normalize returns 0 or 2 only; a bare `exit $?` would misread as
        # "propagate whatever the last builtin produced" — be explicit.
        if ! normalize_default_privileges; then
          exit 2
        fi
        exit 0
      fi
      # --network-id MUST precede "$@" so subcommands using `--` passthrough
      # (e.g. `db lint -- --strict`) still parse correctly.
      exec supabase --network-id "$NETWORK_NAME" "$@"
      ;;
  esac
}

main "$@"
