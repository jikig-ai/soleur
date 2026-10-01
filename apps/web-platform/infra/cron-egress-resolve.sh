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
#   - SELF-HEAL: each tick asserts the DOCKER-USER jump + default-drop rule
#     are live and re-execs the loader when absent (mid-life `nft flush` /
#     external tooling would otherwise fail OPEN with every monitor green).
#   - The timer-unit failure alarms via OnFailure= (cron-egress-alarm.service)
#     AND this script posts a Sentry Crons check-in (slug
#     cron-egress-resolve) so a DEAD timer surfaces as a missed check-in.
#
# Runs doppler-wrapped (prd config) so SENTRY_* / SUPABASE_* are present;
# every env read degrades gracefully when absent (dev hosts).
set -euo pipefail

ALLOWLIST_FILE="${ALLOWLIST_FILE:-/etc/soleur/cron-egress-allowlist.txt}"
ALLOW_SET="soleur_egress_allow"
DNS_SET="soleur_egress_dns"
CONTAINER="soleur-web-platform"
SENTRY_SLUG="cron-egress-resolve"
LOG_TAG="cron-egress-resolve"
LOADER="${LOADER:-/usr/local/bin/cron-egress-nftables.sh}"
LOCK_FILE="/run/cron-egress-resolve.lock"
FAILCOUNT_DIR="/run/cron-egress-resolve-failcount"
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
  local domain="${SENTRY_INGEST_DOMAIN:-}"
  local project="${SENTRY_PROJECT_ID:-}"
  local key="${SENTRY_PUBLIC_KEY:-}"
  if [[ -z "$domain" || -z "$project" || -z "$key" ]]; then
    log "WARN: Sentry env unset — skipping ${status} check-in"
    return 0
  fi
  curl -s -o /dev/null --max-time 10 -X POST \
    "https://${domain}/api/${project}/cron/${SENTRY_SLUG}/${key}/?status=${status}" \
    || log "WARN: Sentry check-in POST failed (status=${status})"
}

# Post a Sentry error EVENT (store API — legacy-but-stable endpoint; migrate
# to the envelope API if Sentry ever sunsets /store/). $1=message $2=op
# $3=extra-json.
sentry_event() {
  local msg="$1" op="$2" extra="$3"
  if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then
    log "WARN: Sentry env unset — event not posted (op=${op})"
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
  curl -s -o /dev/null --max-time 10 -X POST \
    "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
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
  if [[ -z "$ips" ]]; then
    log "WARN: could not resolve $host (keeping its previous addresses)"
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
DESIRED_ALLOW="$(echo "$DESIRED_ALLOW" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"

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
RETAINED="$(echo "$RETAINED" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"

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
DNS_IPS="$(echo "$DNS_IPS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"
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
# DOCKER-USER jump or the default-drop rule was removed mid-life (external
# nft flush, third-party tooling), traffic is silently ACCEPTED with every
# monitor green. Re-exec the loader to reinstall. Skipped when the loader
# itself invoked us (CRON_EGRESS_FROM_LOADER=1) — at bootstrap the rules are
# legitimately not installed yet (sets populate BEFORE the drop by design).
if [[ "${CRON_EGRESS_FROM_LOADER:-}" != "1" ]]; then
  if ! nft list chain ip filter DOCKER-USER 2>/dev/null | grep -q 'jump SOLEUR-EGRESS' \
    || ! nft list chain ip filter SOLEUR-EGRESS 2>/dev/null | grep -q 'egress-blocked'; then
    log "WARN: enforcement rules missing — re-running loader (self-heal)"
    sentry_event \
      "cron-egress-firewall: enforcement rules were MISSING at tick (jump/drop absent) — loader re-run triggered" \
      "enforcement_missing" \
      '{"remediation": "self-healed by re-running cron-egress-nftables.sh; investigate what flushed DOCKER-USER"}'
    "$LOADER" || fail "self-heal loader re-run failed"
  fi
fi

# --- GHCR deny probe (#9275, ADR-096 5.3b-iii) -----------------------------------
# GitHub's Packages frontends (ghcr.io, docker.pkg.github.com) are carved OUT of
# the generated CIDR allow list by gen-github-egress-cidr.sh. This probe proves
# the carve holds: every >= GHCR_PROBE_INTERVAL seconds it asks the APP container
# (docker exec, so the measurement is taken from inside the surface being
# denied) to open a TCP connection to each name. A completed handshake means the
# deny is lost -> op=ghcr_deny_lost; a probe that cannot decide for about an hour
# (GHCR_PROBE_BLIND_AT consecutive inconclusive or container-absent due runs)
# -> op=ghcr_deny_probe_blind. Both ride the existing routed Sentry rule.
#
# The probe's own SYNs hit the logged default drop (the carved IPs are no longer
# allowed), so the drop sampler below discards a kernel line only when ALL of:
# SPT inside the reserved probe port range, DPT=443, DST inside a
# `# Excluded (GitHub Packages frontends): <cidr>` header prefix of the CIDR
# file. Any other drop (including one from the reserved range) is still counted.
#
# curl output is produced inside a possibly-compromised container and parsed by
# this root script: it is capped, split without eval, regex-validated field by
# field, compared with `awk -v` (never (( )) / [[ -gt ]]), and reaches Sentry
# only via `jq --arg`. No --retry: a retry flag can turn a failure into success.
GHCR_PROBE_PORT_LO=49100
GHCR_PROBE_PORT_HI=49199
GHCR_PROBE_NAMES="ghcr.io docker.pkg.github.com"
GHCR_PROBE_INTERVAL=270
GHCR_PROBE_BLIND_AT=12
GHCR_PROBE_BUDGET_SECS=60
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

# Per-name consecutive-blind counter under FAILCOUNT_DIR (ghcr_probe. prefix keeps
# these files clear of the host-named files the resolver prunes). $1=state
# (held|reached reset it; inconclusive|absent increment it) $2=name. Prints the
# new count; the caller emits ghcr_deny_probe_blind at EXACTLY GHCR_PROBE_BLIND_AT.
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
# file, not a wall-clock-minute gate: the timer has AccuracySec=1min drift.
run_ghcr_probe() {
  local now="${1:-}" last stamp name rc out verdict nl tc ip state reason count
  local in_cidr sha
  if [[ -z "$now" ]]; then now="$(date +%s)"; fi
  if [[ "${CRON_EGRESS_FROM_LOADER:-}" == "1" ]]; then return 0; fi
  if (( SECONDS > GHCR_PROBE_BUDGET_SECS )); then
    log "WARN: tick already ${SECONDS}s old — skipping GHCR probe this run"
    return 0
  fi
  stamp="$FAILCOUNT_DIR/ghcr_probe.stamp"
  last="$(cat "$stamp" 2>/dev/null || true)"
  [[ "$last" =~ ^[0-9]{1,12}$ ]] || last=0
  if (( now - 10#$last < GHCR_PROBE_INTERVAL )); then return 0; fi
  echo "$now" > "$stamp"

  local container_up=1
  if ! container_running; then container_up=0; fi

  for name in $GHCR_PROBE_NAMES; do
    rc=0; out=""; verdict="inconclusive"; nl="-"; tc="-"; ip="-"; reason="inconclusive"
    if (( container_up )); then
      out="$(timeout 15 docker exec "$CONTAINER" curl -q -s -o /dev/null --noproxy '*' \
        --connect-timeout 5 --max-time 8 \
        --local-port "${GHCR_PROBE_PORT_LO}-${GHCR_PROBE_PORT_HI}" \
        -w '%{time_namelookup} %{time_connect} %{remote_ip}' "https://${name}/" 2>/dev/null)" || rc=$?
      read -r verdict nl tc ip <<<"$(ghcr_probe_verdict "$rc" "$out")" || true
      state="$verdict"
    else
      state="absent"; reason="container_absent"; rc="-"
    fi
    log "GHCR probe ${name}: ${state} (rc=${rc} namelookup=${nl} connect=${tc})"

    if [[ "$state" == "reached" ]]; then
      in_cidr="unknown"
      if [[ "$ip" != "-" ]]; then
        if nft get element ip filter soleur_egress_allow_cidr "{ $ip }" >/dev/null 2>&1; then
          in_cidr="true"
        else
          in_cidr="false"
        fi
      fi
      sha="$(sha256sum "$CIDR_FILE" 2>/dev/null | cut -d' ' -f1 || true)"
      sentry_event \
        "cron-egress-firewall: GHCR deny lost (a bridge container completed a TCP handshake to a GitHub Packages frontend)" \
        "ghcr_deny_lost" \
        "$(jq -n --arg name "$name" --arg remote_ip "$ip" --arg time_connect "$tc" \
          --arg in_allow_cidr "$in_cidr" --arg file_sha256 "${sha:-unreadable}" \
          '{name: $name, remote_ip: $remote_ip, time_connect: $time_connect,
            in_allow_cidr: $in_allow_cidr, file_sha256: $file_sha256,
            remediation: "knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md#ghcr-carve-9275"}')"
    fi

    count="$(ghcr_probe_blind_step "$state" "$name")"
    if [[ "$count" == "$GHCR_PROBE_BLIND_AT" ]]; then
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
# SPT in [GHCR_PROBE_PORT_LO, GHCR_PROBE_PORT_HI] AND DPT=443 AND DST lies inside a
# `# Excluded (GitHub Packages frontends): <cidr>` prefix of the CIDR file
# (integer containment, no address expansion). Every header CIDR is re-validated
# strictly and must be /28 or longer; ANY parse problem (no header, bad CIDR) makes
# the filter pass everything through — it fails toward counting.
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
      spt = ""; dpt = ""; dst = ""
      for (f = 1; f <= NF; f++) {
        if ($f ~ /^SPT=[0-9]+$/) spt = substr($f, 5)
        else if ($f ~ /^DPT=[0-9]+$/) dpt = substr($f, 5)
        else if ($f ~ /^DST=[0-9.]+$/) dst = substr($f, 5)
      }
      drop = 0
      if (!bad && spt != "" && dpt == "443" && spt + 0 >= plo && spt + 0 <= phi) {
        d = ip2n(dst)
        if (d >= 0) for (k = 1; k <= m; k++) if (d >= cs[k] && d <= ce[k]) drop = 1
      }
      if (!drop) print
    }'
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
# removed by filter_ghcr_probe_drops (three-conjunct filter, see above).
KERNEL_DROPS="$(journalctl -k --since "-3min" --no-pager 2>/dev/null | grep -E 'egress-(blocked|dns-exfil): ' || true)"
KERNEL_DROPS="$(printf '%s\n' "$KERNEL_DROPS" | filter_ghcr_probe_drops || true)"
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
