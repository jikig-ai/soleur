#!/usr/bin/env bash
set -euo pipefail

# Read-only deploy state reporter for #2185 webhook observability.
# Invoked by /hooks/deploy-status (adnanh/webhook) -- see hooks.json.tmpl.
# Returns the JSON written by ci-deploy.sh write_state, MERGED with live
# `systemctl is-active` fields: `services.inngest_heartbeat` (the oneshot
# .service, #4116 — discoverability_test for the plan-skill observability gate)
# and `services.inngest_heartbeat_timer` (the .timer, #4896 — the durable
# liveness signal; the oneshot .service reads `inactive` as its healthy steady
# state, so the timer's active-state is what proves liveness). Sentinels:
#   {"exit_code":-2,"reason":"no_prior_deploy"} -- no state file exists
#   {"exit_code":-3,"reason":"corrupt_state"}   -- state file unparseable
# Exit-code protocol defined in ci-deploy.sh header (#2205).

# Best-effort: systemctl may be unavailable in non-systemd contexts (local
# tests, containers). `systemctl is-active` prints a canonical state word to
# stdout and exits non-zero for inactive/failed; the `|| true` swallows the
# exit so the stdout value reaches the caller. Empty stdout only on
# missing systemctl (covered by the `else` branch).
service_status() {
  local unit="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "$unit" 2>/dev/null || true
  else
    echo "unknown"
  fi
}

# Tail of recent journal entries for a unit. Read-only; returns at most 100
# lines (capped to ~8000 chars total). Strips control bytes so the JSON
# `vector_journal_tail` field round-trips cleanly. Empty on missing
# journalctl OR non-existent unit. Used for no-SSH RCA of vector.service
# startup failures (TR9 PR-5).
#
# Tail bumped from 10 → 100 lines because the original cap was eclipsed
# by high-volume per-request error logs (e.g., Vector's sink retries
# flooded the 10-line window). The 8000-char cap keeps the JSON payload
# small enough for the webhook response while letting diagnostic content
# (envelope_debug sink output, init errors) rise above per-request noise.
service_journal_tail() {
  local unit="$1"
  if command -v journalctl >/dev/null 2>&1; then
    # #5159: belt-and-suspenders redaction before surfacing over /hooks/deploy-status
    # (HMAC + CF-Access gated, but defense-in-depth). Neutralizes the one residual
    # leak path — a binary echoing the inngest signing key (fixed `signkey-` prefix)
    # in an error line. Hardens BOTH this new inngest tail and the existing vector tail.
    journalctl -u "$unit" --no-pager --output=cat -n 100 2>/dev/null \
      | sed -E 's/signkey-(prod-)?[0-9a-fA-F]{4,}/signkey-REDACTED/g' \
      | tr -d '\r' | tr '\n' '|' | tr -dc '[:print:]|' | tail -c 8000 \
      || true
  fi
}

# journald persistent-storage state (#4792). No-SSH post-apply verification for
# the persistent + bounded host journal: reports whether /var/log/journal exists
# and journald is actually writing there (persistent vs volatile), plus the root
# filesystem headroom and the inngest SQLite store size that share `/` with the
# journal. All best-effort + read-only; missing tools collapse to safe defaults
# so the webhook never errors on a non-systemd / minimal host.
journald_storage_json() {
  local persistent=false dir_present=false root_avail="" store_bytes=0
  if [[ -d /var/log/journal ]]; then
    dir_present=true
    # `journalctl --header` lists active journal files with their on-disk paths;
    # a file under /var/log/journal proves journald is in persistent mode (a
    # volatile-only journal lists /run/log/journal paths instead).
    if command -v journalctl >/dev/null 2>&1 \
      && journalctl --header 2>/dev/null | grep -q '/var/log/journal'; then
      persistent=true
    fi
  fi
  # Avail bytes on the root filesystem (the journal lives on `/`, NOT /mnt/data).
  if command -v df >/dev/null 2>&1; then
    root_avail=$(df -h --output=avail / 2>/dev/null | tail -1 | tr -d ' ' || true)
  fi
  # Inngest SQLite store footprint — competes with the journal for root-disk space.
  if [[ -d /var/lib/inngest ]] && command -v du >/dev/null 2>&1; then
    # On du failure the pipe exits via cut (success), so a trailing `|| echo 0`
    # would never fire — store_bytes goes empty and the ${store_bytes:-0} guard
    # at the jq call site supplies the 0. Keep the fallback at the call site only.
    store_bytes=$(du -sb /var/lib/inngest 2>/dev/null | cut -f1)
  fi
  jq -nc \
    --argjson persistent "$persistent" \
    --argjson dir_present "$dir_present" \
    --arg root_avail "$root_avail" \
    --argjson store_bytes "${store_bytes:-0}" \
    '{persistent: $persistent, journal_dir_present: $dir_present, root_avail: $root_avail, inngest_store_bytes: $store_bytes}'
}

# Per-cron last-fire timestamps written by postSentryHeartbeat (#4131).
# Glob is best-effort; empty dir or missing path produces "{}".
inngest_crons_json() {
  local dir="/var/lib/inngest/cron-fires"
  if [[ ! -d "$dir" ]]; then echo "{}"; return; fi
  local result="{}"
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    local slug last_ok
    slug=$(jq -r '.slug // empty' "$f" 2>/dev/null) || continue
    last_ok=$(jq -r '.last_ok_at // empty' "$f" 2>/dev/null) || continue
    [[ -n "$slug" && -n "$last_ok" ]] || continue
    result=$(echo "$result" | jq --arg s "$slug" --arg t "$last_ok" '. + {($s): {last_ok_at: $t}}')
  done
  echo "$result"
}

# Container restart / OOM observability (#5417). The no-SSH surface for the
# restart-churn fix: RestartCount + OOMKilled + State.ExitCode straight from
# `docker inspect`, the rolling restarts/hour the container-restart-monitor
# persists, and a redacted tail of kernel OOM-kill lines. All best-effort with
# safe sentinels (restart_count -1, oom_killed false, container_exit_code -1)
# so the webhook never errors on a non-docker host. NOTE: the container's exit
# code is exposed as `container_exit_code`, NEVER `exit_code` — the top-level
# `exit_code` is the load-bearing DEPLOY-result sentinel (#2205 protocol) and
# must not be clobbered by the container's State.ExitCode.
container_restart_json() {
  local rc=-1 oom=false cexit=-1 rate=0 oom_tail=""
  local name="${CONTAINER_NAME:-soleur-web-platform}"
  if command -v docker >/dev/null 2>&1; then
    local insp
    insp="$(docker inspect "$name" \
      --format '{{.RestartCount}} {{.State.OOMKilled}} {{.State.ExitCode}}' 2>/dev/null || true)"
    if [[ -n "$insp" ]]; then
      read -r rc oom cexit <<< "$insp"
      [[ "$rc" =~ ^[0-9]+$ ]] || rc=-1
      [[ "$oom" == "true" || "$oom" == "false" ]] || oom=false
      [[ "$cexit" =~ ^-?[0-9]+$ ]] || cexit=-1
    fi
  fi
  local rate_file="${CONTAINER_RESTART_RATE_FILE:-/var/run/container-restart-monitor.rate}"
  if [[ -f "$rate_file" ]]; then
    rate="$(cat "$rate_file" 2>/dev/null || echo 0)"
    [[ "$rate" =~ ^[0-9]+$ ]] || rate=0
  fi
  # Redacted, capped tail of kernel OOM-kill lines (vector ships these to Better
  # Stack too). Inherits the same signkey- redaction + control-byte strip as the
  # vector/inngest tails above (#5159) — OOM lines carry no PII, but defense-in-
  # depth keeps the redaction uniform across every journald tail this script emits.
  if command -v journalctl >/dev/null 2>&1; then
    oom_tail="$(journalctl -k --no-pager -n 200 2>/dev/null \
      | grep -iE 'oom-kill|killed process|out of memory' \
      | sed -E 's/signkey-(prod-)?[0-9a-fA-F]{4,}/signkey-REDACTED/g' \
      | tr -d '\r' | tr '\n' '|' | tr -dc '[:print:]|' | tail -c 2000 || true)"
  fi
  jq -nc \
    --argjson rc "$rc" \
    --argjson oom "$oom" \
    --argjson cexit "$cexit" \
    --argjson rate "$rate" \
    --arg oom_tail "$oom_tail" \
    '{restart_count: $rc, oom_killed: $oom, container_exit_code: $cexit,
      restart_rate_per_hour: $rate, oom_journal_tail: $oom_tail}'
}

# Cron-drain observability (#5669 / ADR-078). The no-SSH surface for the
# graceful-drain fix: how long the last deploy waited for an in-flight cron
# before swapping the container (cron_drain_wait_secs), and whether the drain
# timed out and killed the cron anyway (cron_drain_timed_out — the only path
# that pages). Read from the small state file ci-deploy.sh writes
# (write_cron_drain_state). Safe sentinels (wait -1, timed_out false) when the
# file is absent because a deploy never reached the drain — distinguishable from
# a real 0-wait drain (wait 0). Best-effort + read-only.
cron_drain_json() {
  local wait_secs=-1 timed_out=false
  local f="${CRON_DRAIN_STATE_FILE:-/var/run/ci-deploy-cron-drain.json}"
  if [[ -f "$f" ]]; then
    local w t
    w="$(jq -r '.cron_drain_wait_secs // -1' "$f" 2>/dev/null || true)"
    t="$(jq -r '.cron_drain_timed_out // false' "$f" 2>/dev/null || true)"
    [[ "$w" =~ ^-?[0-9]+$ ]] && wait_secs="$w"
    [[ "$t" == "true" || "$t" == "false" ]] && timed_out="$t"
  fi
  jq -nc \
    --argjson w "$wait_secs" \
    --argjson t "$timed_out" \
    '{cron_drain_wait_secs: $w, cron_drain_timed_out: $t}'
}

HEARTBEAT_STATUS="$(service_status inngest-heartbeat.service)"
# inngest-heartbeat.service is a Type=oneshot unit (no RemainAfterExit) driven by
# inngest-heartbeat.timer (OnUnitActiveSec=60s, inngest-bootstrap.sh:216-245). It
# reports `inactive` from `systemctl is-active` as soon as each 60s ExecStart
# completes successfully — i.e. `inactive` is the NORMAL, healthy steady state
# between fires, NOT a fault (`failed` is the real fault, e.g. the empty-URL
# #4116 class). The durable liveness signal is the TIMER's active-state below;
# read both so `inactive` alone is never re-read as a deploy failure (#4896).
HEARTBEAT_TIMER_STATUS="$(service_status inngest-heartbeat.timer)"
INNGEST_SERVER_STATUS="$(service_status inngest-server.service)"
VECTOR_STATUS="$(service_status vector.service)"
VECTOR_JOURNAL_TAIL="$(service_journal_tail vector.service)"
# #5159 follow-up 2: surface the inngest-server's OWN journal tail (its
# sync/registration log) so a restart's re-register behavior is diagnosable with
# no SSH — the decisive evidence the serveHost refutation left unseen.
INNGEST_JOURNAL_TAIL="$(service_journal_tail inngest-server.service)"
INNGEST_CRONS="$(inngest_crons_json)"
JOURNALD_STORAGE="$(journald_storage_json)"
CONTAINER_RESTART="$(container_restart_json)"
CRON_DRAIN="$(cron_drain_json)"

STATE_FILE="${CI_DEPLOY_STATE:-/var/lock/ci-deploy.state}"

# Compute the base JSON once, then perform a single jq merge with the
# heartbeat field. ci-deploy.sh's mv may be observed mid-write (corrupt
# JSON); the workflow's -3 case treats that as retryable, not fatal.
if [[ ! -f "$STATE_FILE" ]]; then
  BASE='{"exit_code":-2,"reason":"no_prior_deploy"}'
elif ! BASE="$(jq -c . "$STATE_FILE" 2>/dev/null)"; then
  BASE='{"exit_code":-3,"reason":"corrupt_state"}'
fi

jq -nc \
  --argjson base "$BASE" \
  --arg hb "$HEARTBEAT_STATUS" \
  --arg hbt "$HEARTBEAT_TIMER_STATUS" \
  --arg is "$INNGEST_SERVER_STATUS" \
  --arg vs "$VECTOR_STATUS" \
  --arg vj "$VECTOR_JOURNAL_TAIL" \
  --arg ij "$INNGEST_JOURNAL_TAIL" \
  --argjson ic "$INNGEST_CRONS" \
  --argjson js "$JOURNALD_STORAGE" \
  --argjson cr "$CONTAINER_RESTART" \
  --argjson cd "$CRON_DRAIN" \
  '$base + $cr + $cd + {journald_storage: $js, services: (($base.services // {}) + {
    inngest_heartbeat: $hb,
    inngest_heartbeat_timer: $hbt,
    inngest_server: $is,
    vector: $vs,
    vector_journal_tail: $vj,
    inngest_journal_tail: $ij,
    inngest_crons: $ic
  })}'
