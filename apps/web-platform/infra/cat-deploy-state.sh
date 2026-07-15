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

# Identify the host that answered this read (#6425). deploy.soleur.ai is a Cloudflare
# Tunnel hostname and Cloudflare selects a connector per edge colo, so a read of
# /hooks/deploy-status answers from whichever connector the caller's colo picked —
# NOT necessarily the host the caller meant. Without this field a wrong-host answer is
# indistinguishable from a correct one, which is exactly what made #6425 cost 16h.
# Resolved from the Hetzner metadata service (the hcloud_server id — the SAME value
# terraform knows, so AC13 can assert identity against a TF-known value rather than
# self-consistency), with /etc/machine-id as a reboot-stable fallback.
#
# SOLEUR-DEBT: 2nd of 3 resolve_host_id copies (ci-deploy.sh source-of-truth, this,
# inngest-inventory.sh). Kept in sync by test_host_id_drift_guard, NOT a shared sourced
# lib — sourcing works in infra (ci-deploy.sh sources its env file), but DISTRIBUTING a new script costs
# ~11 surfaces (push-infra-config.sh, hooks.json.tmpl, infra-config-apply.sh FILE_MAP,
# infra-config-install.sh DEST_SPEC + its 2 hardcoded counts, server.tf triggers_replace,
# apply-deploy-pipeline-fix.yml paths, ship-deploy-pipeline-fix-gate.test.ts,
# ship/SKILL.md) plus the bake path. Upgrade trigger: a 4th copy OR any consumer outside
# infra/. Tracked: #6465.
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
    # HASHED, never raw: machine-id(5) says the value "should be considered confidential and
    # must not be exposed in untrusted environments" — systemd's own guidance is to hash it
    # per-application (sd_id128_get_machine_app_specific). This fallback now reaches an HTTP
    # response body and journald -> Vector -> Better Stack (a third-party vendor), which the
    # ci-deploy.sh original never did. Hashing is LOSSLESS here: host_id only ever needs to be
    # STABLE and COMPARABLE (same-host vs different-host), never reversible.
    printf 'machine-%s' "$(printf '%s' "$id" | sha256sum | cut -c1-12)"
    return 0
  fi
  return 1
}
# `|| true` is load-bearing: this script is `set -euo pipefail`, and resolve_host_id
# return 1s when metadata is unreachable AND /etc/machine-id is unreadable. A bare
# assignment would abort the hook and turn /hooks/deploy-status into a non-200 — losing
# the whole state read to protect one field. An empty host_id is emitted instead: an
# ABSENT field is indistinguishable from an old script, an empty one is not.
HOST_ID="$(resolve_host_id || true)"
readonly HOST_ID

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

# Faithful sandbox canary verdict (#5875 / ADR-079). The no-SSH surface for the
# dark-launched canary: the last deploy's verdict (pass | sandbox_broken |
# canary_infra_error), its reason, and the SDK version it ran against. Read from
# the small state file ci-deploy.sh writes (write_sandbox_canary_state). Safe
# sentinel (verdict "unknown") when the file is absent because a deploy never ran
# the canary. Best-effort + read-only. The canary-promotion follow-through
# (scripts/followthroughs/canary-promotion-5875.sh) reads this field.
sandbox_canary_json() {
  # DURABLE path (NOT /var/run tmpfs) — MUST match ci-deploy.sh
  # SANDBOX_CANARY_STATE_FILE. The soak accumulator must survive host reboots or
  # it silently resets to zero (#5889); see the writer's rationale.
  local f="${SANDBOX_CANARY_STATE_FILE:-/mnt/data/ci-deploy-sandbox-canary.json}"
  if [[ -f "$f" ]]; then
    local v r s c cp fp
    v="$(jq -r '.verdict // "unknown"' "$f" 2>/dev/null || echo unknown)"
    r="$(jq -r '.reason // ""' "$f" 2>/dev/null || echo '')"
    s="$(jq -r '.sdk_version // ""' "$f" 2>/dev/null || echo '')"
    c="$(jq -r '.checked_at // 0' "$f" 2>/dev/null || echo 0)"
    cp="$(jq -r '.consecutive_pass // 0' "$f" 2>/dev/null || echo 0)"
    fp="$(jq -r '.first_pass_at // 0' "$f" 2>/dev/null || echo 0)"
    [[ "$c" =~ ^[0-9]+$ ]] || c=0
    [[ "$cp" =~ ^[0-9]+$ ]] || cp=0
    [[ "$fp" =~ ^[0-9]+$ ]] || fp=0
    jq -nc --arg v "$v" --arg r "$r" --arg s "$s" --argjson c "$c" --argjson cp "$cp" --argjson fp "$fp" \
      '{verdict:$v, reason:$r, sdk_version:$s, checked_at:$c, consecutive_pass:$cp, first_pass_at:$fp}'
  else
    echo '{"verdict":"unknown","reason":"","sdk_version":"","checked_at":0,"consecutive_pass":0,"first_pass_at":0}'
  fi
}

# Loaded seccomp profile hash (#5875 item 4 / ADR-079). The no-SSH surface for
# the "applied ≠ loaded" gap: the sha256 of the seccomp profile the RUNNING prod
# container actually started with (--security-opt seccomp=<file>), recorded by
# ci-deploy.sh write_seccomp_profile_hash at container start. apply-deploy-pipeline-fix.yml
# asserts this == sha256(committed apps/web-platform/infra/seccomp-bwrap.json)
# after its sequenced post-apply redeploy. Emits "" when the file is absent (a
# host predating this field, or no deploy yet). Best-effort + read-only.
seccomp_profile_sha256_value() {
  local f="${SECCOMP_PROFILE_STATE_FILE:-/var/run/ci-deploy-seccomp-profile.json}"
  local sha=""
  if [[ -f "$f" ]]; then
    sha="$(jq -r '.seccomp_profile_sha256 // ""' "$f" 2>/dev/null || echo "")"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || sha=""
  fi
  printf '%s' "$sha"
}

# Live loaded-vs-committed seccomp discriminators (#5960 / ADR-079 item-4 amend).
# The recorded seccomp_profile_sha256_value above reads ONLY the ephemeral tmpfs
# state file (reboot-cleared per #5877) — an empty value cannot distinguish
# not-delivered / host-stale / not-reloaded, and apply-deploy-pipeline-fix.yml's
# redeploy assert has no way to prove the RUNNING container is enforcing the
# committed profile. These three live, read-only fields close that gap in ONE
# deploy-status read (no SSH):
#   seccomp_profile_host_present         : the on-host profile file exists.
#   seccomp_profile_host_sha256          : RAW sha256sum of the on-host file — the
#     DELIVERY leg. Matches the workflow's raw COMMITTED_SHA (sha256sum of the
#     committed seccomp-bwrap.json); sha256sum is jq-version-independent, so
#     host==committed is skew-free.
#   seccomp_profile_loaded_matches_host  : the RUNNING container's inlined seccomp
#     (docker inspect HostConfig.SecurityOpt) canonical-equals the on-host file —
#     the RELOAD leg, computed with ONE host jq on BOTH sides so it never crosses
#     jq versions (skew-immune by construction). #5875 item-4's real contract,
#     "the container is enforcing the committed profile", decomposes into
#     (host==committed) AND (loaded==host); this field is the second conjunct.
# Reuses the audit-bwrap-uid.sh:105-146 docker-inspect + jq -cS + EMPTY_HASH-guard
# technique. Best-effort + read-only: every failure collapses to a safe sentinel
# (present=false, host_sha256="", matches=false) so the webhook never errors on a
# non-docker / minimal host, and a jq failure that hashes the empty stream to
# sha256("") never yields a false loaded==host match.
seccomp_live_json() {
  local host_path="${SECCOMP_PROFILE_HOST_PATH:-/etc/docker/seccomp-profiles/soleur-bwrap.json}"
  local present=false host_sha="" matches=false
  if [[ -f "$host_path" ]]; then
    present=true
    host_sha="$(sha256sum "$host_path" 2>/dev/null | cut -d' ' -f1 || true)"
    [[ "$host_sha" =~ ^[0-9a-f]{64}$ ]] || host_sha=""
  fi
  # Reload leg — only meaningful once the host file is present and readable.
  if [[ "$present" == true && -n "$host_sha" ]] && command -v docker >/dev/null 2>&1; then
    local name="${CONTAINER_NAME:-soleur-web-platform}"
    local entries entry
    entries="$(docker inspect "$name" \
      --format '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' 2>/dev/null || true)"
    # `|| true`: head closing the pipe early can SIGPIPE sed (141); under
    # pipefail that would abort the whole webhook script at the SECCOMP_LIVE
    # assignment. Uniform with every other pipe in this function.
    entry="$(printf '%s\n' "$entries" | sed -n 's/^seccomp=//p' | head -n1 || true)"
    # A literal /path means Docker did not resolve --security-opt seccomp=<file>
    # into inlined JSON at container-create (audit-bwrap-uid.sh:123 drift) → false.
    if [[ -n "$entry" && "$entry" != /* ]]; then
      local empty_hash inlined_hash file_hash
      empty_hash="$(printf '' | sha256sum | cut -d' ' -f1)"
      # `|| true` on both: a jq parse failure under set -euo pipefail would abort
      # the script before the guard; instead let it hash the empty stream and let
      # the EMPTY_HASH guard reject the sha256("") == sha256("") false-match.
      inlined_hash="$(printf '%s' "$entry" | jq -cS . 2>/dev/null | sha256sum | cut -d' ' -f1 || true)"
      file_hash="$(jq -cS . "$host_path" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)"
      if [[ -n "$inlined_hash" && "$inlined_hash" != "$empty_hash" \
            && "$inlined_hash" == "$file_hash" ]]; then
        matches=true
      fi
    fi
  fi
  jq -nc \
    --argjson present "$present" \
    --arg host_sha "$host_sha" \
    --argjson matches "$matches" \
    '{seccomp_profile_host_present: $present,
      seccomp_profile_host_sha256: $host_sha,
      seccomp_profile_loaded_matches_host: $matches}'
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
SANDBOX_CANARY="$(sandbox_canary_json)"
SECCOMP_PROFILE_SHA256="$(seccomp_profile_sha256_value)"
SECCOMP_LIVE="$(seccomp_live_json)"

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
  --argjson sc "$SANDBOX_CANARY" \
  --arg sps "$SECCOMP_PROFILE_SHA256" \
  --argjson sl "$SECCOMP_LIVE" \
  --arg hid "$HOST_ID" \
  '$base + $cr + $cd + $sl + {host_id: $hid, sandbox_canary: $sc, seccomp_profile_sha256: $sps, journald_storage: $js, services: (($base.services // {}) + {
    inngest_heartbeat: $hb,
    inngest_heartbeat_timer: $hbt,
    inngest_server: $is,
    vector: $vs,
    vector_journal_tail: $vj,
    inngest_journal_tail: $ij,
    inngest_crons: $ic
  })}'
