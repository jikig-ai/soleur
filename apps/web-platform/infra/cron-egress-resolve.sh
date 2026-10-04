#!/usr/bin/env bash
# cron-egress-resolve.sh — maintain the nftables egress allowlist sets
# (#5046 PR-2 / cron-egress-firewall).
#
# Resolves every host in /etc/soleur/cron-egress-allowlist.txt (plus the
# doppler-provided dynamic hosts: SENTRY_INGEST_DOMAIN, the Supabase URL
# hosts) to IPv4 addresses and reconciles the nftables sets
# @soleur_egress_allow / @soleur_egress_dns in table `ip filter`.
#
# Hard conditions (plan §Phase 2.B, arch-confirmed; hardened at PR #5089
# multi-agent review):
#   - ADDITIVE-THEN-PRUNE, ATOMICALLY: adds and deletes are emitted in ONE
#     `nft -f` transaction (no intermediate empty-set window). NEVER
#     `flush set` + repopulate.
#   - FAIL-SAFE ON EMPTY: if resolution yields ZERO addresses (transient DNS
#     outage), abort WITHOUT pruning — a frozen set beats an empty one.
#   - PARTIAL-FAILURE = ADDITIVE-ONLY: if ANY host failed to resolve this
#     tick — INCLUDING an expected-but-absent dynamic env var (a Doppler
#     rename must never prune the live Supabase/Sentry IPs) — skip ALL
#     deletes.
#   - BOTH RESOLVER VIEWS: the container resolves via ITS resolv.conf
#     (Docker substitutes 8.8.8.8/8.8.4.4 when the host's stub is
#     loopback-only) while this script runs on the HOST; CDN/geo answers can
#     diverge per resolver. Union the container's own getent view with the
#     host's so the set always contains the IPs the container will dial.
#   - DNS PIN UNION: @soleur_egress_dns always includes Docker's
#     substitution pair (8.8.8.8/8.8.4.4) — pruning them while the container
#     is down (deploy window) would blackhole ALL container DNS on restart.
#   - NEVER LINK-LOCAL (#9378): no address in 169.254.0.0/16 (the instance-metadata range; it serves
#     cloud-init user_data, which carries a Doppler read token) may enter either set, from ANY feeder:
#     the host's answers, the container's own getent view, the 24 h grace pool re-read from SEEN_DIR
#     (matching seen/ files are PURGED, never just skipped) and the resolver pin set. The v4-mapped
#     spelling (::ffff:169.254.x.y) counts as link-local too. A host whose answers were ALL link-local
#     counts as a resolution failure (additive-only tick, the existing partial-failure doctrine), and
#     the first occurrence per host posts a Sentry event (the stdout line below is journal-only: this
#     unit's SYSLOG_IDENTIFIER is not in Vector's host-script allowlist).
#   - SELF-HEAL: each tick asserts the DOCKER-USER jump + default-drop rule
#     (+ the default-drop log rule) are live and re-execs the loader when absent (mid-life `nft flush` /
#     external tooling would otherwise fail OPEN with every monitor green).
#   - The timer-unit failure alarms via OnFailure= (cron-egress-alarm.service)
#     AND this script posts a Sentry Crons check-in (slug
#     cron-egress-resolve) so a DEAD timer surfaces as a missed check-in.
#
# Runs doppler-wrapped (prd config) so SENTRY_* / SUPABASE_* are present;
# every env read degrades gracefully when absent (dev hosts).
set -euo pipefail
# (#7797) Refuse to run under shell tracing: this unit is doppler-wrapped and holds a live
# Sentry ingest key that -x would print. UNCONDITIONAL (every credential arrives from the
# unit's environment, so a `${VAR:+x}` hatch names nothing it can trust).
case "$-" in
  *x*)
    printf '[cron-egress-resolve] refusing to run under xtrace: this unit handles a live credential and -x would print it\n' >&2
    exit 78
    ;;
esac

ALLOWLIST_FILE="${ALLOWLIST_FILE:-/etc/soleur/cron-egress-allowlist.txt}"
ALLOW_SET="soleur_egress_allow"
DNS_SET="soleur_egress_dns"
CONTAINER="soleur-web-platform"
SENTRY_SLUG="cron-egress-resolve"
LOG_TAG="cron-egress-resolve"
LOADER="${LOADER:-/usr/local/bin/cron-egress-nftables.sh}"
LOCK_FILE="/run/cron-egress-resolve.lock"
FAILCOUNT_DIR="${FAILCOUNT_DIR:-/run/cron-egress-resolve-failcount}"
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
assert_fixture_dir "$FAILCOUNT_DIR"
# Post one escalation event after this many consecutive failures of the same
# host (at the 1-min timer cadence ≈ 30 min of sustained failure).
FAILCOUNT_ESCALATE=30
# Grace-window IP retention (LB-rotation fix). LB-fronted allowlisted hosts
# (Cloudflare/AWS/Google round-robin across large pools; a single-A-record
# snapshot pins only the current tick's few IPs, so a connect to a freshly-
# rotated IP before the next tick is default-dropped — the non-GitHub analogue
# of the api.github.com /meta gap, incident 5516336). Retain every IP DNS
# returned for an ALREADY-allowlisted host over a rolling window so the set
# accumulates that host's full rotation pool. This stays tight (only IPs
# resolved for an already-trusted host — never wholesale provider CIDRs, which
# would defeat ADR-052's default-drop); see the "remediation (LB-rotation
# IP-coverage gap)" runbook section. The store lives under a persistent
# StateDirectory (NOT tmpfs /run) so a reboot does not wipe the pool.
GRACE_WINDOW_SECS="${GRACE_WINDOW_SECS:-86400}"
SEEN_DIR="${SEEN_DIR:-/var/lib/cron-egress-resolve/seen}"

log() { echo "[$LOG_TAG] $*"; }

# --- Link-local guard (#9378) ---------------------------------------------------
# One predicate, two stdin filters. is_link_local normalises each octet with 10# (so 169.254.009.1 is read as
# decimal) and strips the v4-mapped prefix, then tests 169.254.0.0/16 membership.
is_link_local() { # <addr>
  local a="${1#::[fF][fF][fF][fF]:}"
  [[ "$a" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  (( 10#${BASH_REMATCH[1]} == 169 && 10#${BASH_REMATCH[2]} == 254 ))
}
ll_only() { local a; while IFS= read -r a; do ! is_link_local "$a" || printf '%s\n' "$a"; done; } # stdin lines that ARE link-local
ll_strip() { local a; while IFS= read -r a; do is_link_local "$a" || printf '%s\n' "$a"; done; } # stdin lines that are NOT
ll_report() { # <source> <addrs>: journal line always; the Sentry event once per source until it answers clean again
  local marker="$FAILCOUNT_DIR/.ll-$1" extra addrs
  addrs="$(tr '\n' ' ' <<< "$2")"; addrs="${addrs% }"
  log "WARN: $1 answered link-local address(es) [$addrs] - DROPPED (169.254.0.0/16 is never allowlisted)"
  [[ -e "$marker" ]] && return 0
  : > "$marker"
  extra="$(jq -nc --arg src "$1" --arg addrs "$addrs" '{source: $src, addresses: $addrs, remediation: "a vendor name in cron-egress-allowlist.txt (or a dynamic host env) resolves into the instance-metadata range; the address was dropped. Investigate DNS for that host."}')"
  sentry_event "cron-egress-resolve: '$1' answered a link-local address (169.254.0.0/16, the instance-metadata range); dropped, never allowlisted" "resolve_link_local" "$extra"
}
ll_clear() { rm -f "$FAILCOUNT_DIR/.ll-$1"; } # <source>

# Strict dotted-quad filter (stdin lines -> stdout lines): four decimal fields, each
# <= 255 with no leading zeros. Container-supplied addresses (getent / resolv.conf read
# through docker exec) reach the nft batch only through this: a `999.1.1.1` that matched
# a bare `^[0-9]+(\.[0-9]+){3}$` would make `nft -f` reject the WHOLE transaction and
# abort the tick before the GHCR probe. Pure awk, no gawk-only constructs (the host
# runs mawk).
strict_ipv4_lines() {
  awk -F. 'NF == 4 {
    ok = 1
    for (i = 1; i <= 4; i++) {
      if ($i !~ /^[0-9]+$/ || $i + 0 > 255 || ($i != "0" && $i ~ /^0/)) ok = 0
    }
    if (ok) print
  }'
}

# Serialize against concurrent invocations (timer tick vs loader bootstrap vs
# terraform re-provision). Without this, two identical reconciles can race and
# one batch fails on an already-deleted element (kernel rolls back atomically —
# no corruption — but the loser posts a spurious error check-in).
if [[ "${CRON_EGRESS_LOCKED:-}" != "1" ]]; then
  exec env CRON_EGRESS_LOCKED=1 flock -w 120 "$LOCK_FILE" "$0" "$@"
fi

# --- Sentry Crons check-in (mirrors postSentryHeartbeat, _cron-shared.ts) ---
sentry_checkin() {
  local status="$1"
  # (#7898 §2) Sentry ingest-triple adjudication: the destination is pinned to a Sentry ingest
  # host and the project id / public key to their shapes before the key is sent anywhere; a
  # value that fails the pin is refused (never posted), not corrected.
  # BEGIN sentry-dest-pin (#7898)
  sentry_dest_ok=0; sentry_refuse_reason=""; _si_host=""
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    _si_host="${SENTRY_INGEST_DOMAIN%.}"
    _si_host="${_si_host,,}"
    if [[ "$_si_host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.ingest\.(de|us)\.sentry\.io$ ]]; then
      sentry_dest_ok=1
    else
      sentry_refuse_reason=host-shape
    fi
    if (( sentry_dest_ok )) && [[ ! "$SENTRY_PROJECT_ID" =~ ^[0-9]+$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=project-shape; fi
    if (( sentry_dest_ok )) && [[ ! "$SENTRY_PUBLIC_KEY" =~ ^[a-f0-9]{32}$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=key-shape; fi
  fi
  # END sentry-dest-pin (#7898)
  if (( ! sentry_dest_ok )); then
    log "WARN: Sentry env unset or refused (${sentry_refuse_reason:-unset}) — skipping ${status} check-in"
    return 0
  fi
  # (#7873) transport confinement, position load-bearing: --disable FIRST aborts ~/.curlrc
  # parsing; --noproxy '*' ignores a planted proxy env. The URL interpolates the FOLDED host.
  curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null --max-time 10 -X POST \
    "https://${_si_host}/api/${SENTRY_PROJECT_ID}/cron/${SENTRY_SLUG}/${SENTRY_PUBLIC_KEY}/?status=${status}" \
    || log "WARN: Sentry check-in POST failed (status=${status})"
}

# Post a Sentry error EVENT (store API — legacy-but-stable endpoint; migrate
# to the envelope API if Sentry ever sunsets /store/). $1=message $2=op
# $3=extra-json.
sentry_event() {
  local msg="$1" op="$2" extra="$3"
  # BEGIN sentry-dest-pin (#7898)
  sentry_dest_ok=0; sentry_refuse_reason=""; _si_host=""
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    _si_host="${SENTRY_INGEST_DOMAIN%.}"
    _si_host="${_si_host,,}"
    if [[ "$_si_host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.ingest\.(de|us)\.sentry\.io$ ]]; then
      sentry_dest_ok=1
    else
      sentry_refuse_reason=host-shape
    fi
    if (( sentry_dest_ok )) && [[ ! "$SENTRY_PROJECT_ID" =~ ^[0-9]+$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=project-shape; fi
    if (( sentry_dest_ok )) && [[ ! "$SENTRY_PUBLIC_KEY" =~ ^[a-f0-9]{32}$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=key-shape; fi
  fi
  # END sentry-dest-pin (#7898)
  if (( ! sentry_dest_ok )); then
    log "WARN: Sentry env unset or refused (${sentry_refuse_reason:-unset}) — event not posted (op=${op})"
    return 0
  fi
  local payload
  payload="$(jq -n \
    --arg msg "$msg" \
    --arg op "$op" \
    --argjson extra "$extra" \
    '{message: $msg, level: "error", platform: "other", logger: "cron-egress-resolve",
      tags: {feature: "cron-egress-firewall", op: $op},
      extra: $extra}')"
  # (#7873) transport confinement, position load-bearing (see sentry_checkin).
  curl --disable --noproxy '*' --proto '=https' -g -s -o /dev/null --max-time 10 -X POST \
    "https://${_si_host}/api/${SENTRY_PROJECT_ID}/store/" \
    -H "Content-Type: application/json" \
    -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
    -d "$payload" \
    || log "WARN: Sentry event POST failed (op=${op})"
}

fail() {
  log "ERROR: $*"
  sentry_checkin error
  exit 1
}

command -v nft >/dev/null || fail "nft binary not found"
command -v jq >/dev/null || fail "jq binary not found"
mkdir -p "$FAILCOUNT_DIR"
mkdir -p "$SEEN_DIR"

container_running() {
  timeout 10 docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"
}

# --- Gather hostnames ---------------------------------------------------------
HOSTS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && HOSTS+=("$line")
  done < "$ALLOWLIST_FILE"
else
  fail "allowlist file missing: $ALLOWLIST_FILE"
fi

# Dynamic hosts from the doppler env (operator-configured; not hardcodable).
# An expected-but-ABSENT env var counts as a resolution failure: it forces
# this tick additive-only so the previously-resolved IPs for that host are
# never pruned (a Doppler secret rename must not become an app-wide outage).
FAILED_HOSTS=0
extract_host() { echo "$1" | sed -E 's|^[a-z+]+://||; s|/.*$||; s|:.*$||'; }
for var in SENTRY_INGEST_DOMAIN NEXT_PUBLIC_SUPABASE_URL SUPABASE_URL; do
  val="${!var:-}"
  if [[ -n "$val" ]]; then
    HOSTS+=("$(extract_host "$val")")
  else
    log "WARN: dynamic-host env $var unset — ADDITIVE-ONLY tick (no prune)"
    FAILED_HOSTS=$((FAILED_HOSTS + 1))
  fi
done

[[ ${#HOSTS[@]} -gt 0 ]] || fail "no hosts to resolve (empty allowlist)"
HOSTS_SORTED="$(printf '%s\n' "${HOSTS[@]}" | sort -u)"

# --- Resolve (host view + container view) --------------------------------------
# Container view: ONE docker exec resolving the full host list with the
# container's OWN resolvers — the answers it will actually dial.
CONTAINER_VIEW=""
if container_running; then
  CONTAINER_VIEW="$(printf '%s\n' "$HOSTS_SORTED" \
    | timeout 60 docker exec -i "$CONTAINER" sh -c \
        'while read -r h; do getent ahostsv4 "$h" 2>/dev/null | awk "{print \$1}"; done' \
    2>/dev/null || true)"
fi

DESIRED_ALLOW=""
for host in $HOSTS_SORTED; do
  ips="$(timeout 10 getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  # Link-local answers are dropped HERE so that "every record was link-local" reads as a resolution failure of
  # this host (additive-only tick); the merged sets are scrubbed again below, for every feeder.
  host_ll="$(printf '%s\n' "$ips" | ll_only)"
  if [[ -n "$host_ll" ]]; then
    ll_report "$host" "$host_ll"
    ips="$(printf '%s\n' "$ips" | ll_strip)"
  else
    ll_clear "$host"
  fi
  if [[ -z "$ips" ]]; then
    log "WARN: could not resolve $host${host_ll:+ (every record was link-local)} (keeping its previous addresses)"
    FAILED_HOSTS=$((FAILED_HOSTS + 1))
    # Escalate sustained failure of a single host: ADDITIVE-ONLY forever is
    # silent laxity drift + a possibly-dead needed host; page once at the
    # threshold instead of never.
    fc_file="$FAILCOUNT_DIR/$host"
    fc="$(( $(cat "$fc_file" 2>/dev/null || echo 0) + 1 ))"
    echo "$fc" > "$fc_file"
    if [[ "$fc" -eq "$FAILCOUNT_ESCALATE" ]]; then
      sentry_event \
        "cron-egress-resolve: host '$host' has failed resolution ${fc} consecutive ticks (prune suspended; investigate or remove from cron-egress-allowlist.txt)" \
        "resolve_host_failed" \
        "{\"host\": \"$host\", \"consecutive_failures\": $fc, \"remediation\": \"apps/web-platform/infra/cron-egress-allowlist.txt (auto-applies on merge via terraform_data.cron_egress_firewall)\"}"
    fi
    continue
  fi
  rm -f "$FAILCOUNT_DIR/$host"
  DESIRED_ALLOW+="$ips"$'\n'
done
DESIRED_ALLOW+="$CONTAINER_VIEW"$'\n'
DESIRED_ALLOW="$(echo "$DESIRED_ALLOW" | strict_ipv4_lines | sort -u || true)"
# The container's own getent view is a second feeder: scrub it before anything is recorded in SEEN_DIR.
cv_ll="$(printf '%s\n' "$CONTAINER_VIEW" | ll_only)"
if [[ -n "$cv_ll" ]]; then ll_report "container-view" "$cv_ll"; else ll_clear "container-view"; fi
DESIRED_ALLOW="$(printf '%s\n' "$DESIRED_ALLOW" | ll_strip)"

# FAIL-SAFE: never operate against a fully-empty resolution (DNS outage).
[[ -n "$DESIRED_ALLOW" ]] || fail "resolution returned ZERO addresses — refusing to touch the sets (fail-safe)"

# --- Grace-window IP retention (LB-rotation fix) -------------------------------
# Runs AFTER the fail-safe-on-empty guard so a zero-resolution tick aborts above
# and never reaches the store (a DNS outage must not be papered over by stale
# IPs). Record every current-tick IP's last-seen, then union back any IP seen for
# an allowlisted host within the window — so the ALLOW set accumulates each LB
# host's full rotation pool instead of just this tick's single-A-record snapshot.
NOW_EPOCH="$(date +%s)"
# 1. RECORD/refresh last-seen for every current-tick IP — ALWAYS (every tick,
#    including no-prune ticks), so a transient partial failure cannot stall the
#    pool's freshness. The IP is a dotted quad → safe store filename.
while IFS= read -r ip; do
  [[ -n "$ip" ]] || continue
  echo "$NOW_EPOCH" > "$SEEN_DIR/$ip"
done <<< "$DESIRED_ALLOW"
# 2. UNION stored-within-window IPs into the retained set — ALWAYS — re-filtering
#    every readback value through the IPv4 regex (a corrupted/non-dotted-quad
#    store entry must never reach the nft batch). 3. EVICT past-window entries
#    ONLY on a prune tick (FAILED_HOSTS==0); a no-prune tick keeps them so a
#    Doppler/DNS blip cannot drop the live pool (additive-only invariant).
RETAINED="$DESIRED_ALLOW"
if [[ -d "$SEEN_DIR" ]]; then
  while IFS= read -r seen_file; do
    [[ -n "$seen_file" ]] || continue
    ip="$(basename "$seen_file")"
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    # PURGE (not skip): a planted seen/169.254.169.254 would otherwise be re-read, and re-added, for the whole grace window.
    if is_link_local "$ip"; then
      rm -f "$seen_file"
      log "WARN: purged link-local entry $ip from the grace-window store"
      continue
    fi
    ts="$(cat "$seen_file" 2>/dev/null || echo 0)"
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    age=$(( NOW_EPOCH - ts ))
    if (( age <= GRACE_WINDOW_SECS )); then
      RETAINED+=$'\n'"$ip"
    elif [[ "$FAILED_HOSTS" -eq 0 ]]; then
      # Eviction (store reclamation) is gated on the prune tick BY DESIGN: a
      # no-prune tick touches nothing (the simplest additive-only invariant) —
      # do NOT "fix" the suppressed eviction during a sustained partial failure
      # as a leak. The store is bounded: a single prune tick (FAILED_HOSTS==0)
      # drains the whole past-window backlog, and sustained FAILED_HOSTS>0 is
      # already the paged condition (resolve_host_failed at FAILCOUNT_ESCALATE).
      rm -f "$seen_file"
    fi
  done < <(find "$SEEN_DIR" -type f 2>/dev/null)
fi
RETAINED="$(echo "$RETAINED" | strict_ipv4_lines | sort -u || true)"

# --- DNS resolver pin set ------------------------------------------------------
# Union of: Docker's loopback-stub substitution pair (ALWAYS — the container
# falls back to these whenever the host resolv.conf is loopback-only, and a
# deploy-window prune of them would blackhole all container DNS on restart),
# the running container's actual resolv.conf, and the host's real upstreams.
DNS_IPS=$'8.8.8.8\n8.8.4.4'
if container_running; then
  DNS_IPS+=$'\n'"$(timeout 10 docker exec "$CONTAINER" cat /etc/resolv.conf 2>/dev/null | awk '/^nameserver/ {print $2}' || true)"
fi
if [[ -r /run/systemd/resolve/resolv.conf ]]; then
  DNS_IPS+=$'\n'"$(awk '/^nameserver/ {print $2}' /run/systemd/resolve/resolv.conf)"
fi
DNS_IPS="$(echo "$DNS_IPS" | strict_ipv4_lines | sort -u || true)"
# FINAL CHOKEPOINT: whatever a feeder above let through, nothing link-local reaches a set. The resolver pin set
# is fed from the container's own resolv.conf, which is container-influenced input.
dns_ll="$(printf '%s\n' "$DNS_IPS" | ll_only)"
if [[ -n "$dns_ll" ]]; then ll_report "dns-pin" "$dns_ll"; else ll_clear "dns-pin"; fi
DNS_IPS="$(printf '%s\n' "$DNS_IPS" | ll_strip)"
RETAINED="$(printf '%s\n' "$RETAINED" | ll_strip)"
[[ -n "$DNS_IPS" ]] || fail "no IPv4 resolver to pin"

# --- Reconcile (one atomic nft -f transaction) ---------------------------------
current_set() {
  local raw
  # Distinguish "nft failed" (fail loud — schema drift would otherwise read
  # as an empty set and disable pruning forever) from "set legitimately
  # empty/missing at bootstrap" (loader declares sets before first call).
  if ! raw="$(nft -j list set ip filter "$1" 2>/dev/null)"; then
    echo ""
    return 0
  fi
  # Elements are plain strings for a bare ipv4_addr set; counter/comment
  # decorations wrap them as {"elem":{"val":...}}. prefix/range shapes would
  # emit null and be filtered by the IPv4 grep — if `flags interval` is ever
  # added, extend this parser FIRST or pruning silently desyncs.
  echo "$raw" \
    | jq -r '.nftables[]?.set?.elem?[]? | if type == "object" then .elem.val else . end' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true
}

build_batch() {
  local set_name="$1" desired="$2" prune="$3"
  local current adds dels
  current="$(current_set "$set_name")"
  adds="$(comm -23 <(echo "$desired") <(echo "$current") | paste -sd, -)"
  dels="$(comm -13 <(echo "$desired") <(echo "$current") | paste -sd, -)"
  [[ -n "$adds" ]] && echo "add element ip filter $set_name { $adds }"
  if [[ "$prune" == "prune" && -n "$dels" ]]; then
    echo "delete element ip filter $set_name { $dels }"
  fi
  return 0
}

PRUNE="prune"
if [[ "$FAILED_HOSTS" -gt 0 ]]; then
  log "WARN: $FAILED_HOSTS host(s)/env(s) failed this tick — ADDITIVE-ONLY (no prune)"
  PRUNE="no-prune"
fi

BATCH="$(
  build_batch "$ALLOW_SET" "$RETAINED" "$PRUNE"
  build_batch "$DNS_SET" "$DNS_IPS" "$PRUNE"
)"

if [[ -n "$BATCH" ]]; then
  echo "$BATCH" | nft -f - || fail "nft batch apply failed"
  log "applied: $(echo "$BATCH" | tr '\n' ' ' | cut -c1-400)"
else
  log "sets already converged (no changes)"
fi

# --- Self-heal: assert the enforcement rules are still live ---------------------
# The sets being converged proves nothing about ENFORCEMENT — if the
# DOCKER-USER jump or the default-drop rule (or its log rule) was removed mid-life (external
# nft flush, third-party tooling), traffic is silently ACCEPTED with every
# monitor green. Re-exec the loader to reinstall. Skipped when the loader
# itself invoked us (CRON_EGRESS_FROM_LOADER=1) — at bootstrap the rules are
# legitimately not installed yet (sets populate BEFORE the drop by design).
#
# The read is capture-then-match, never `nft ... | grep -q` under pipefail: a `grep -q`
# early exit can SIGPIPE `nft` (status 141, read as "missing"), and an `nft` read that
# fails against netlink contention reads as "missing" too. Each rule is THREE-valued
# (present / absent / unreadable) and a failed read is never reported as an absent rule
# (#9392), with one exception: nft's own ENOENT (rc 1 and an `Error: No such file or directory`
# first line: the object is gone, a deleted table or chain) IS an absent rule, not contention.
# A missing binary (rc 127), another error that merely ends in the same words, or a different
# status stays unreadable. Globals set:
# ENF_JUMP ENF_DROP ENF_LOG (present|absent|unreadable), ENF_RC_JUMP, ENF_RC_DROP
# (the LAST attempt's status), ENF_READ_FAILED, ENF_READ_RETRIED, ENF_HEAL.
# Needles: the jump by its target token (so `jump SOLEUR-EGRESS-OLD` does not count), the
# drop rule and the default-drop log rule by their own comments (the drop comment's closing
# quote excludes the log rule's "... default drop log").
enforcement_probe() {
  ENF_JUMP=unreadable; ENF_DROP=unreadable; ENF_LOG=unreadable
  ENF_RC_JUMP=0; ENF_RC_DROP=0; ENF_READ_FAILED=false; ENF_READ_RETRIED=false; ENF_HEAL=false
  local out_jump="" out_chain="" attempt jump_gone=false drop_gone=false
  local jump_re='jump[[:space:]]+SOLEUR-EGRESS([[:space:]]|$)'
  local sleep_s="${NFT_RETRY_SLEEP:-1}"
  [[ "$sleep_s" =~ ^[0-9]$ ]] || sleep_s=1
  for attempt in 1 2; do
    jump_gone=false; drop_gone=false
    ENF_RC_JUMP=0; out_jump="$(nft list chain ip filter DOCKER-USER 2>&1)" || ENF_RC_JUMP=$?
    ENF_RC_DROP=0; out_chain="$(nft list chain ip filter SOLEUR-EGRESS 2>&1)" || ENF_RC_DROP=$?
    if (( ENF_RC_JUMP == 1 )) && [[ "$out_jump" == "Error: No such file or directory"* ]]; then jump_gone=true; fi
    if (( ENF_RC_DROP == 1 )) && [[ "$out_chain" == "Error: No such file or directory"* ]]; then drop_gone=true; fi
    if { (( ENF_RC_JUMP == 0 )) || [[ "$jump_gone" == true ]]; } && { (( ENF_RC_DROP == 0 )) || [[ "$drop_gone" == true ]]; }; then break; fi
    ENF_READ_RETRIED=true
    if (( attempt == 1 )); then sleep "$sleep_s"; fi
  done
  if (( ENF_RC_JUMP == 0 )) || [[ "$jump_gone" == true ]]; then
    ENF_JUMP=absent
    if [[ "$out_jump" =~ $jump_re ]]; then ENF_JUMP=present; fi
  fi
  if (( ENF_RC_DROP == 0 )) || [[ "$drop_gone" == true ]]; then
    ENF_DROP=absent; ENF_LOG=absent
    if [[ "$out_chain" == *'comment "soleur-egress: default drop"'* ]]; then ENF_DROP=present; fi
    if [[ "$out_chain" == *'comment "soleur-egress: default drop log"'* ]]; then ENF_LOG=present; fi
  fi
  if [[ "$ENF_JUMP" == unreadable || "$ENF_DROP" == unreadable ]]; then ENF_READ_FAILED=true; fi
  if [[ "$ENF_JUMP" != present || "$ENF_DROP" != present || "$ENF_LOG" != present ]]; then ENF_HEAL=true; fi
}

# The Sentry `extra` for op=enforcement_missing: which cause class fired. $1 = the loader
# re-run's exit status (0 ok, 124 timed out). A jq or systemctl failure degrades (minimal
# object / "unknown"), it never aborts the heal. Timestamps are the host-local strings
# systemd prints.
enforcement_extra() {
  local loader_rc="${1:-0}"
  local remediation="self-healed by re-running cron-egress-nftables.sh; investigate what flushed DOCKER-USER"
  local docker_since loader_since host
  docker_since="$(timeout 2 systemctl show docker.service -p ActiveEnterTimestamp --value 2>/dev/null)" || docker_since=unknown
  loader_since="$(timeout 2 systemctl show cron-egress-firewall.service -p ActiveEnterTimestamp --value 2>/dev/null)" || loader_since=unknown
  host="$(hostname 2>/dev/null)" || host=unknown
  jq -nc \
    --arg remediation "$remediation" --arg host "${host:-unknown}" \
    --arg jump "$ENF_JUMP" --arg drop "$ENF_DROP" --arg log "$ENF_LOG" \
    --argjson rcj "$ENF_RC_JUMP" --argjson rcd "$ENF_RC_DROP" \
    --argjson failed "$ENF_READ_FAILED" --argjson retried "$ENF_READ_RETRIED" --argjson lrc "$loader_rc" \
    --arg dsince "${docker_since:-unknown}" --arg lsince "${loader_since:-unknown}" \
    '{remediation: $remediation, host: $host, jump_present: $jump, drop_present: $drop, log_present: $log,
      rc_jump: $rcj, rc_drop: $rcd, read_failed: $failed, read_retried: $retried,
      loader_rc: $lrc, docker_since: $dsince, loader_since: $lsince}' 2>/dev/null \
    || printf '{"remediation": "%s"}\n' "$remediation"
}

# Order (#9392 review): the loader re-runs FIRST (egress is open until it does, so only the
# probe sits in front of it), under `timeout` so a wedged loader (netlink contention is the
# #9392 hypothesis) becomes rc 124 and still reaches the event and `fail` instead of being
# killed with the unit at TimeoutStartSec=120 (60 s + the 10 s event POST + the 10 s `fail`
# check-in fit inside it when the heal starts within ~40 s of the tick start; a slower tick can
# still be cut with the unit, and then only the OnFailure alarm email reports). The event then
# posts BEFORE `fail`, so a failed or timed-out
# self-heal still reports; its `extra` carries the probe's pre-heal rule state and the loader's
# status. A failed Sentry POST only logs (sentry_event), it cannot stop the heal.
if [[ "${CRON_EGRESS_FROM_LOADER:-}" != "1" ]]; then
  enforcement_probe
  if [[ "$ENF_HEAL" == true ]]; then
    log "WARN: enforcement rules missing — re-running loader (self-heal) jump=$ENF_JUMP drop=$ENF_DROP log=$ENF_LOG read_failed=$ENF_READ_FAILED"
    loader_rc=0
    timeout -k 2 60 "$LOADER" || loader_rc=$?
    extra="$(enforcement_extra "$loader_rc")"
    sentry_event \
      "cron-egress-firewall: enforcement rules were MISSING at tick (jump/drop absent) — loader re-run triggered" \
      "enforcement_missing" \
      "$extra"
    (( loader_rc == 0 )) || fail "self-heal loader re-run failed (rc=$loader_rc)"
  fi
fi

# --- GHCR deny probe (#9275, ADR-096 5.3b-iii) -----------------------------------
# GitHub's Packages frontends (ghcr.io, docker.pkg.github.com) are carved OUT of
# the generated CIDR allow list by gen-github-egress-cidr.sh. This probe proves
# the carve holds: every >= GHCR_PROBE_INTERVAL seconds it asks the APP container
# (docker exec, so the measurement is taken from inside the surface being
# denied) to open a TCP connection to each name. A completed handshake means the
# deny is lost -> op=ghcr_deny_lost; a probe that cannot decide for about an hour
# (GHCR_PROBE_BLIND_AT consecutive inconclusive, container-absent or budget-skipped
# due runs) -> op=ghcr_deny_probe_blind, re-emitted every GHCR_PROBE_BLIND_AT further
# blind runs so one failed Sentry POST is never the last word. Both ride the existing
# routed Sentry rule.
#
# TRUST BOUNDARY: the probe runs INSIDE the app container, so a root-compromised
# container can forge a `held` answer. It is a drift detector (a carve that silently
# stopped holding), not a trust anchor against a hostile container.
#
# The probe's own SYNs hit the logged default drop (the carved IPs are no longer
# allowed), so the drop sampler below discards a kernel line only when ALL of:
# PROTO=TCP, SPT inside the reserved probe port range, DPT=443, DST inside a
# `# Excluded (GitHub Packages frontends): <cidr>` header prefix of the CIDR
# file; the header tokens are the FIRST occurrence on the line and a line carrying an
# ICMP-error inner header (`[SRC=`) is never discarded. Any other drop (including one
# from the reserved range) is still counted.
#
# curl output is produced inside a possibly-compromised container and parsed by
# this root script: it is capped (`head -c 256` inside the command substitution, so
# the cap bounds what is BUFFERED, not just what is parsed), split without eval,
# regex-validated field by field, compared with `awk -v` (never (( )) / [[ -gt ]]),
# and reaches Sentry only via `jq --arg`. No --retry: a retry flag can turn a failure
# into success.
GHCR_PROBE_PORT_LO=49100
GHCR_PROBE_PORT_HI=49199
GHCR_PROBE_NAMES="ghcr.io docker.pkg.github.com"
GHCR_PROBE_INTERVAL=270
GHCR_PROBE_BLIND_AT=12
# Budget arithmetic against the 120 s unit TimeoutStartSec (cron-egress-resolve.service).
# The probe starts only while $SECONDS <= 30. Worst case from there: container_running
# 10 s + 2 names x (15 s timeout + 2 s kill grace + one Sentry POST 10 s) = 64 s, so the
# probe ends by t=94 s; the sampler's egress_blocked POST (10 s) and the ok check-in
# (10 s) then finish by t=114 s, 6 s inside the unit budget. The self-heal above runs BEFORE this
# gate and is not part of that arithmetic: the probe's slice is the same (<= ~1 s), and the heal path
# is bounded by its own `timeout -k 2 60` loader run; a tick past 30 s skips the GHCR probe (counted
# as blind, which needs GHCR_PROBE_BLIND_AT consecutive runs to alert).
GHCR_PROBE_BUDGET_SECS=30
CIDR_FILE="${CIDR_FILE:-/etc/soleur/cron-egress-allowlist-cidr.txt}"

# Pure verdict. $1=curl/docker-exec exit code, $2=raw `-w` output
# ('<time_namelookup> <time_connect> <remote_ip>'). Prints one line:
#   <reached|held|inconclusive> <time_namelookup|-> <time_connect|-> <remote_ip|->
# reached      time_connect > 0 (a handshake completed)
# held         rc 28 AND time_connect == 0 AND time_namelookup > 0 (the name
#              resolved, the connect hung: a drop). A hung RESOLVER also exits 28
#              with time_connect == 0 and must NOT read as held.
# inconclusive anything else, including any field that is not a plain number.
ghcr_probe_verdict() {
  local rc="$1" raw="$2" line nl="" tc="" ip="" extra="" shown_ip="-" o
  line="${raw:0:128}"
  line="${line%%$'\n'*}"
  read -r nl tc ip extra <<<"$line" || true
  if [[ ! "$rc" =~ ^[0-9]{1,3}$ || -n "$extra" ]] \
    || [[ ! "$nl" =~ ^[0-9]+(\.[0-9]+)?$ || ! "$tc" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "inconclusive - - -"
    return 0
  fi
  if [[ "$ip" =~ ^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$ ]]; then
    shown_ip="$ip"
    for o in "${BASH_REMATCH[@]:1}"; do
      if (( 10#$o > 255 )); then shown_ip="-"; fi
    done
  fi
  if awk -v v="$tc" 'BEGIN { exit !(v + 0 > 0) }'; then
    echo "reached $nl $tc $shown_ip"
  elif [[ "$rc" == "28" ]] && awk -v v="$nl" 'BEGIN { exit !(v + 0 > 0) }'; then
    echo "held $nl $tc -"
  else
    echo "inconclusive $nl $tc -"
  fi
}

# Per-name consecutive-blind counter under FAILCOUNT_DIR. The `ghcr_probe.` prefix
# makes these files collide with no host name: the host-failure counters beside them
# are named for allowlisted hosts, and the loop that removes them (`rm -f
# "$FAILCOUNT_DIR/$host"`) only ever names a host, never globs the directory.
# $1=state (held|reached reset it; inconclusive|absent increment it) $2=name. Prints
# the new count; the caller emits ghcr_deny_probe_blind whenever it is a positive
# multiple of GHCR_PROBE_BLIND_AT (first at 12, again at 24, 36, ...).
ghcr_probe_blind_step() {
  local state="$1" name="$2" f cur
  f="$FAILCOUNT_DIR/ghcr_probe.${name}.blind"
  case "$state" in
    held|reached) rm -f "$f"; echo 0; return 0 ;;
  esac
  cur="$(cat "$f" 2>/dev/null || true)"
  [[ "$cur" =~ ^[0-9]{1,6}$ ]] || cur=0
  cur=$(( 10#$cur + 1 ))
  echo "$cur" > "$f"
  echo "$cur"
}

# Dispatch. $1=optional epoch seconds (clock seam for tests). Cadence is a stamp
# file, not a wall-clock-minute gate: the timer has AccuracySec=1min drift. A DUE run
# that cannot probe is never silent: a budget skip steps every name's blind counter
# with reason budget_skipped (no stamp, so the next tick retries) and a container-
# absent run steps it with container_absent. Only the loader-invoked tick and a
# not-yet-due tick return without counting.
run_ghcr_probe() {
  local now="${1:-}" last stamp name rc out verdict nl tc ip state reason count skip=""
  local in_cidr in_name sha
  if [[ -z "$now" ]]; then now="$(date +%s)"; fi
  if [[ "${CRON_EGRESS_FROM_LOADER:-}" == "1" ]]; then return 0; fi
  stamp="$FAILCOUNT_DIR/ghcr_probe.stamp"
  last="$(cat "$stamp" 2>/dev/null || true)"
  [[ "$last" =~ ^[0-9]{1,12}$ ]] || last=0
  if (( now - 10#$last < GHCR_PROBE_INTERVAL )); then return 0; fi
  if (( SECONDS > GHCR_PROBE_BUDGET_SECS )); then
    skip="budget_skipped"
    log "WARN: tick already ${SECONDS}s old — skipping GHCR probe this run (counted as blind)"
  else
    echo "$now" > "$stamp"
  fi

  local container_up=1
  if [[ -z "$skip" ]] && ! container_running; then container_up=0; fi

  for name in $GHCR_PROBE_NAMES; do
    rc=0; out=""; verdict="inconclusive"; nl="-"; tc="-"; ip="-"; reason="inconclusive"
    if [[ -n "$skip" ]]; then
      state="absent"; reason="$skip"; rc="-"
    elif (( container_up )); then
      # head -c 256 INSIDE the substitution bounds what is buffered from the container;
      # the exit code is timeout/docker-exec's own (PIPESTATUS[0]), so rc 28 survives.
      out="$(timeout -k 2 15 docker exec "$CONTAINER" curl -q -s -o /dev/null --noproxy '*' \
        --connect-timeout 5 --max-time 8 \
        --local-port "${GHCR_PROBE_PORT_LO}-${GHCR_PROBE_PORT_HI}" \
        -w '%{time_namelookup} %{time_connect} %{remote_ip}' "https://${name}/" 2>/dev/null | head -c 256; exit "${PIPESTATUS[0]}")" || rc=$?
      read -r verdict nl tc ip <<<"$(ghcr_probe_verdict "$rc" "$out")" || true
      state="$verdict"
    else
      state="absent"; reason="container_absent"; rc="-"
    fi
    log "GHCR probe ${name}: ${state} (rc=${rc} namelookup=${nl} connect=${tc})"

    if [[ "$state" == "reached" ]]; then
      # in_allow_cidr = the generated CIDR set; in_allow_name = the by-name set (the
      # by-name allow wins by order, so a carved IP can still be admitted there).
      # Membership is nft's own exit status (no `nft | grep -q`, which pipefail would mask).
      in_cidr="unknown"; in_name="unknown"
      if [[ "$ip" != "-" ]]; then
        if nft get element ip filter soleur_egress_allow_cidr "{ $ip }" >/dev/null 2>&1; then
          in_cidr="true"
        else
          in_cidr="false"
        fi
        if nft get element ip filter soleur_egress_allow "{ $ip }" >/dev/null 2>&1; then
          in_name="true"
        else
          in_name="false"
        fi
      fi
      sha="$(sha256sum "$CIDR_FILE" 2>/dev/null | cut -d' ' -f1 || true)"
      sentry_event \
        "cron-egress-firewall: GHCR deny lost (a bridge container completed a TCP handshake to a GitHub Packages frontend)" \
        "ghcr_deny_lost" \
        "$(jq -n --arg name "$name" --arg remote_ip "$ip" --arg time_connect "$tc" \
          --arg in_allow_cidr "$in_cidr" --arg in_allow_name "$in_name" --arg file_sha256 "${sha:-unreadable}" \
          '{name: $name, remote_ip: $remote_ip, time_connect: $time_connect,
            in_allow_cidr: $in_allow_cidr, in_allow_name: $in_allow_name, file_sha256: $file_sha256,
            remediation: "knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md#ghcr-carve-9275"}')"
    fi

    count="$(ghcr_probe_blind_step "$state" "$name")"
    if (( count > 0 && count % GHCR_PROBE_BLIND_AT == 0 )); then
      sentry_event \
        "cron-egress-firewall: GHCR deny probe is blind (cannot decide for about an hour)" \
        "ghcr_deny_probe_blind" \
        "$(jq -n --arg name "$name" --arg reason "$reason" --arg last_rc "$rc" --arg last_namelookup "$nl" \
          '{name: $name, reason: $reason, last_rc: $last_rc, last_namelookup: $last_namelookup,
            remediation: "knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md#ghcr-carve-9275"}')"
    fi
  done
}

# Sampler filter (stdin kernel lines -> stdout kept lines). Drops a line only when
# PROTO=TCP AND SPT in [GHCR_PROBE_PORT_LO, GHCR_PROBE_PORT_HI] AND DPT=443 AND DST
# lies inside a `# Excluded (GitHub Packages frontends): <cidr>` prefix of the CIDR
# file (integer containment, no address expansion). Assumed line format is the
# nf_log_ipv4 LOG shape: `... SRC=<a> DST=<b> ... PROTO=TCP SPT=<p> DPT=<q> ...`; an
# ICMP error carries the offending packet's header again as `[SRC=.. DST=.. ..
# PROTO=TCP SPT=.. DPT=..]`, so each token is taken at its FIRST occurrence (the outer
# header) and any line containing `[SRC=` is kept (counted). Every header CIDR is
# re-validated strictly and must be /28 or longer; ANY parse problem (no header, bad
# CIDR) makes the filter pass everything through — it fails toward counting.
filter_ghcr_probe_drops() {
  local excl
  excl="$(sed -n 's/^# Excluded (GitHub Packages frontends): *//p' "$CIDR_FILE" 2>/dev/null | tr '\n' ' ' || true)"
  if [[ -z "${excl// /}" ]]; then cat; return 0; fi
  awk -v plo="$GHCR_PROBE_PORT_LO" -v phi="$GHCR_PROBE_PORT_HI" -v excl="$excl" '
    function oct_ok(s) { return (s ~ /^[0-9]+$/ && length(s) <= 3 && s + 0 <= 255 && (s == "0" || s !~ /^0/)) }
    function ip2n(s,   p, j) {
      if (split(s, p, ".") != 4) return -1
      for (j = 1; j <= 4; j++) if (!oct_ok(p[j])) return -1
      return ((p[1] * 256 + p[2]) * 256 + p[3]) * 256 + p[4]
    }
    BEGIN {
      bad = 0; m = 0; n = split(excl, tok, " ")
      for (i = 1; i <= n; i++) {
        if (split(tok[i], c, "/") != 2 || c[2] !~ /^[0-9]+$/ || c[2] + 0 < 28 || c[2] + 0 > 32) { bad = 1; break }
        base = ip2n(c[1])
        if (base < 0) { bad = 1; break }
        size = 2 ^ (32 - c[2]); start = base - (base % size)
        m++; cs[m] = start; ce[m] = start + size - 1
      }
      if (m == 0) bad = 1
    }
    {
      spt = ""; dpt = ""; dst = ""; proto = ""
      for (f = 1; f <= NF; f++) {
        if (spt == "" && $f ~ /^SPT=[0-9]+$/) spt = substr($f, 5)
        else if (dpt == "" && $f ~ /^DPT=[0-9]+$/) dpt = substr($f, 5)
        else if (dst == "" && $f ~ /^DST=[0-9.]+$/) dst = substr($f, 5)
        else if (proto == "" && $f ~ /^PROTO=[A-Za-z0-9]+$/) proto = substr($f, 7)
      }
      drop = 0
      if (!bad && index($0, "[SRC=") == 0 && proto == "TCP" && spt != "" && dpt == "443" && spt + 0 >= plo && spt + 0 <= phi) {
        d = ip2n(dst)
        if (d >= 0) for (k = 1; k <= m; k++) if (d >= cs[k] && d <= ce[k]) drop = 1
      }
      if (!drop) print
    }'
}

# Fail-toward-counting wrapper (stdin -> stdout, always rc 0). If the filter itself
# fails (awk dialect/runtime error) a bare `$(... | filter || true)` would turn an
# EMPTY output into "zero drops" and silence every egress_blocked alert. Here the
# filter's exit code is read separately and a failure keeps the UNFILTERED input.
ghcr_probe_filter_or_keep() {
  local in out frc=0
  in="$(cat)"
  out="$(printf '%s\n' "$in" | filter_ghcr_probe_drops)" || frc=$?
  if (( frc != 0 )); then
    log "WARN: GHCR drop filter failed (rc=${frc}) — counting every drop unfiltered"
    printf '%s\n' "$in"
    return 0
  fi
  printf '%s\n' "$out"
}

# Placed AFTER the self-heal block and BEFORE the drop sampler so a probe failure
# can never skip `sentry_checkin ok`: errors inside run under `||` do not abort.
run_ghcr_probe || log "WARN: GHCR probe errored (non-fatal)"

# --- Fail-loud: surface kernel drops to Sentry -----------------------------------
# BOTH drop prefixes are counted: `egress-blocked: ` (off-allowlist) AND
# `egress-dns-exfil: ` (off-pin resolver) — the latter is the design's named
# DNS-exfil detector and must page too (AC-P2.10). These kernel lines do NOT
# ship to Better Stack (Vector's journald sources are priority/unit-scoped);
# this Sentry event is the ONLY no-SSH channel for drop forensics, so the
# sample is included. Window is 3min on a 1-min cadence — overlap is safe
# (Sentry dedupes into one issue), a gap is not. The GHCR probe's own drops are
# removed by filter_ghcr_probe_drops via ghcr_probe_filter_or_keep (see above).
KERNEL_DROPS="$(journalctl -k --since "-3min" --no-pager 2>/dev/null | grep -E 'egress-(blocked|dns-exfil): ' || true)"
KERNEL_DROPS="$(printf '%s\n' "$KERNEL_DROPS" | ghcr_probe_filter_or_keep)"
BLOCK_HITS="$(printf '%s\n' "$KERNEL_DROPS" | grep -c . || true)"
if [[ "${BLOCK_HITS:-0}" -gt 0 ]]; then
  log "WARN: $BLOCK_HITS egress drop(s) in the last 3m"
  SAMPLE="$(printf '%s\n' "$KERNEL_DROPS" | tail -3 | tr '"' "'" | tr '\n' ';' | cut -c1-500)"
  sentry_event \
    "egress-blocked: container egress denied (${BLOCK_HITS} hits in last 3m)" \
    "egress_blocked" \
    "$(jq -n --arg sample "$SAMPLE" --argjson hits "$BLOCK_HITS" \
      '{sample: $sample, hits: $hits,
        remediation: "if a NEEDED host: add it to apps/web-platform/infra/cron-egress-allowlist.txt with an evidence comment (auto-applies on merge); runbook: knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md"}')"
fi

sentry_checkin ok
log "OK: allow=$(echo "$DESIRED_ALLOW" | wc -l) addrs, retained=$(echo "$RETAINED" | wc -l), dns=$(echo "$DNS_IPS" | wc -l) resolvers, failed_hosts=$FAILED_HOSTS, blocked_3m=$BLOCK_HITS"
