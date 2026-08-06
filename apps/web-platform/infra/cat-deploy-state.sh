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
    # (HMAC + CF-Access gated, but defense-in-depth). Neutralizes TWO residual leak
    # paths — a binary echoing (a) the inngest signing key (fixed `signkey-` prefix) or
    # (b) a Better Stack heartbeat BEARER URL, whose token is a PATH segment and so
    # matches none of vector.toml's pii_scrub rules (those cover userid=, OAuth query
    # params, emails, Authorization: headers). #6536 added (b) by tailing
    # inngest-heartbeat.service, whose curl echoes the full URL on a glob-parse error;
    # the ping script's `curl -g` stops that at the source and this stops it here.
    # Hardens BOTH the inngest tails and the existing vector tail.
    # #7286 added the three rules below, and they are load-bearing rather than hygiene.
    # Tailing inngest-redis.service puts a CREDENTIAL-BEARING unit's stderr into an HTTP
    # response body for the first time: its ExecStart interpolates $INNGEST_REDIS_PASSWORD, and
    # on a config-parse failure redis echoes the offending argument VERBATIM —
    #   *** FATAL CONFIG FILE ERROR *** ... >>> 'requirepass <value>'
    # — which is the PREDICTED tail for two of #7286's seven hypotheses, not a hypothetical.
    # A Doppler auth failure (the leading hypothesis) likewise echoes a dp.* token fragment.
    #
    # These are added to the SHARED scrubber deliberately: it hardens all six tails this script
    # emits, and a second scrubber would drift from this one.
    #
    # THE RULES ARE PORTED FROM vector.toml's pii_scrub, NOT INVENTED HERE — and the first draft
    # of this block got that wrong in three ways that review caught with falsifying inputs:
    #
    #   1. The DSN rule was written redis-only (`(rediss?)://…`). vector.toml's is
    #      SCHEME-AGNOSTIC, and the difference is live: `service_journal_tail
    #      inngest-server.service` below tails a unit whose env carries INNGEST_POSTGRES_URI, and
    #      a Postgres DSN (scheme, userinfo with password, Supabase host) survived the redis-only
    #      form verbatim. vector.toml's own comment states that exact threat ("DSNs surface in
    #      connection-failure diagnostics verbatim"). Use its form.
    #   2. The rules were case-SENSITIVE. Redis matches config directives with strcasecmp and
    #      echoes the ORIGINAL casing on a parse error, so `REQUIREPASS "…"`, `RequirePass …`,
    #      `Masterauth …` and `REDIS://default:<pw>@…` all passed through unredacted. vector.toml
    #      is case-insensitive; the `I` flag restores parity.
    #   3. `AUTH` was unanchored, so it ate `NOAUTH Authentication required` — destroying the
    #      single most useful redis-auth diagnostic on the surface this PR exists to build.
    #      Anchored to a non-letter boundary so NOAUTH/XAUTH survive.
    #
    # So: this is a PORT of a mature scrubber, and any future rule added here should be diffed
    # against vector.toml's rather than written fresh. The one intentional divergence is that
    # vector.toml covers log SHIPPING and this covers the HTTP RESPONSE body — two paths, same
    # rules.
    #
    # Residual, deliberately not defended: a secret containing whitespace or a literal `@` is
    # only partially redacted (`requirepass "foo bar"` leaks `bar`). Not reachable today —
    # inngest.tf's `random_password` is `length = 48, special = false`, i.e. alnum — but that
    # invariant lives in another file with no cross-reference, so a hand-edited Doppler value
    # would break it silently. Stated rather than left implicit.
    #
    # Line-oriented, so these MUST precede the `tr '\n' '|'` fold below.
    journalctl -u "$unit" --no-pager --output=cat -n 100 2>/dev/null \
      | sed -E 's/signkey-(prod-)?[0-9a-fA-F]{4,}/signkey-REDACTED/g' \
      | sed -E 's#(uptime\.betterstack\.com/api/v[0-9]+/heartbeat/)[A-Za-z0-9_-]{4,}#\1REDACTED#g' \
      | sed -E 's/(requirepass|masterauth)[[:space:]]+[^[:space:]]+/\1 REDACTED/gI' \
      | sed -E 's/(^|[^A-Za-z])(AUTH)[[:space:]]+[^[:space:]]+/\1\2 REDACTED/gI' \
      | sed -E 's#([a-z][a-z0-9+.-]*://)[^:/@[:space:]]+:[^@/[:space:]]+@#\1REDACTED@#gI' \
      | sed -E 's#(rediss?://):[^@[:space:]]+@#\1REDACTED@#gI' \
      | sed -E 's/dp\.(st|sa|pt|ct)\.[A-Za-z0-9._-]+/dp.\1.REDACTED/gI' \
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
    #
    # CAPTURED ONCE, matched against a here-string — never
    # `journalctl --header | grep -q`. This file runs under `set -euo pipefail`
    # (line 2) and the header is large (~107 KB on any host with journal history)
    # with the match on line 1. `grep -q` exits on that first match, the
    # producer's next write() takes SIGPIPE, pipefail promotes 141 to the
    # pipeline status, and the `&&` reads FALSE — reporting persistent=false on
    # a host where journald is demonstrably persistent.
    #
    # Measured before the fix, on a host whose journald IS persistent:
    #   journalctl --header | grep -q '/var/log/journal'  =>  PIPESTATUS[0]=141, killed 20/20
    #   old form => persistent=false   (wrong)
    #   new form => persistent=true    (correct)
    # Not a race: the producer is far larger than the 64 KiB pipe buffer, so its
    # write always blocks and always loses.
    #
    # This survived because it is host-age-dependent — a fresh host has a small
    # header and reads correctly; the guard only starts lying once journals
    # accumulate. #6578.
    if command -v journalctl >/dev/null 2>&1; then
      local journal_header
      journal_header="$(journalctl --header 2>/dev/null || true)"
      if grep -qF '/var/log/journal' <<<"$journal_header"; then
        persistent=true
      fi
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

# --- #7286: make inngest-redis.service self-report -------------------------------------------
#
# THE GAP THIS CLOSES. On 2026-08-05 inngest-redis.service crash-looped for 16 hours and the
# ONLY fact any remote surface could establish about it was "it exited non-zero". Its stderr was
# unreadable off-box, so the watchdog printed a hard-coded GUESS at the cause into the incident
# issue and the operator had no way to adjudicate it. Meanwhile the decisive evidence sat one
# already-authenticated GET away — this endpoint simply had no field for it.
#
# These fields are structured so ONE payload discriminates every candidate cause at once:
#   dropin   -> stale-credential          datadir -> missing/re-owned data dir
#   tail     -> AOF corruption, OOM, bad directive, port already bound
#   binary   -> package churn / unmasked distro unit
# and `result` carries the systemd-populated fields that survive even when the process exits
# before writing a single byte — which is why this must never ship with the tail as its only
# new field.
#
# Read the property list by KEY, never positionally. `systemctl show` returns properties in
# systemd's OWN canonical order (not the caller's), and emits a BLANK line for a property the
# running systemd does not support (MemoryPeak needs >= 253) — so a `--value` positional parse
# silently MISALIGNS every field after the gap. That failure is invisible: it produces
# well-formed output with the values shifted.
systemd_prop() {
  local text="$1" key="$2"
  # Here-string, not a pipe: `awk ... exit` closing a pipe early would SIGPIPE the producer,
  # and `set -o pipefail` (line 2) would promote that 141 into this function's status.
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' <<<"$text" 2>/dev/null || true
}

INNGEST_REDIS_UNIT="inngest-redis.service"
INNGEST_REDIS_STATUS="$(service_status "$INNGEST_REDIS_UNIT")"
INNGEST_REDIS_JOURNAL_TAIL="$(service_journal_tail "$INNGEST_REDIS_UNIT")"

# Restart-loop discriminators. `is-active` alone is a COIN FLIP on a unit with RestartSec=5:
# #7286 measured three probes 8s apart reporting `degraded, degraded, durable`. NRestarts plus
# the two timestamps are what distinguish "still looping" from "recently fixed".
INNGEST_REDIS_RESULT=""
INNGEST_REDIS_DROPIN=""
INNGEST_REDIS_LOADSTATE=""
if command -v systemctl >/dev/null 2>&1; then
  # SyslogIdentifier is the OTHER HALF of the Source-4 pair, and without it the incident's
  # deeper cause stays undecidable. inngest-redis.service:26 states the invariant: Vector's
  # Source 4 matches SYSLOG_IDENTIFIER by EXACT VALUE, so "the tag and the allowlist entry only
  # work as a pair". `vector_config_identity` below reports the allowlist half; this reports the
  # EMITTER half. Both reach the host only via the OCI bootstrap image, so an on-host unit
  # predating #6617c would emit under `doppler` (the ExecStart basename) and match zero sources
  # — i.e. "redis is silent" and "redis's stderr is tagged wrong" would be indistinguishable.
  # Free: it rides the systemctl show already being issued, and it is systemd's LOADED view
  # (same rationale that makes DropInPaths the right form for the drop-in).
  #
  # LoadState + ActiveState are EMITTED, not just read. LoadState was previously computed for
  # tail_status and thrown away, which made a MASKED unit invisible (is-active says `inactive`,
  # DropInPaths is empty, tail reads `empty`). ActiveState is what the plan's "restart loop that
  # never latches failed" failure mode declares it ships — so without it that mode's stated
  # single-read predicate could not be evaluated from the payload at all.
  _redis_show="$(systemctl show \
    -p Result -p ExecMainStatus -p ExecMainCode -p NRestarts -p MemoryPeak \
    -p ExecMainStartTimestamp -p ActiveEnterTimestamp -p LoadState -p ActiveState \
    -p SyslogIdentifier \
    "$INNGEST_REDIS_UNIT" 2>/dev/null || true)"
  INNGEST_REDIS_LOADSTATE="$(systemd_prop "$_redis_show" LoadState)"
  for _k in Result ExecMainStatus ExecMainCode NRestarts MemoryPeak \
            ExecMainStartTimestamp ActiveEnterTimestamp LoadState ActiveState \
            SyslogIdentifier; do
    INNGEST_REDIS_RESULT+="${_k}=$(systemd_prop "$_redis_show" "$_k") "
  done
  INNGEST_REDIS_RESULT="${INNGEST_REDIS_RESULT% }"

  # THE CREDENTIAL DISCRIMINATOR. systemd's LOADED view, NOT a filesystem check — and that
  # distinction is the whole point of the field. After a delivery the drop-in is on disk whether
  # or not `daemon-reload` merged it, so a `[ -f ... ]` probe would report identically for
  # "fix landed and active" and "fix landed inert". systemd lists a path in DropInPaths only
  # once it has actually merged it, so this field alone separates those two states.
  # BASENAMES ONLY: never echo drop-in CONTENT — the shape gate legitimately permits
  # `Environment=`, so dumping content would put an env VALUE in the response body.
  _dropin_paths="$(systemd_prop "$(systemctl show -p DropInPaths "$INNGEST_REDIS_UNIT" 2>/dev/null || true)" DropInPaths)"
  # `|| true` on basename: it exits non-zero on a leading-dash token (which it parses as a flag),
  # and under this file's `set -euo pipefail` that would abort the WHOLE endpoint — in the PR
  # that removes the runbook's last-resort host login. Every sibling call in this block is
  # guarded; this one was the outlier. `${_p##*/}` would also work, but keeping basename with a
  # guard stays closer to the surrounding style.
  for _p in $_dropin_paths; do
    INNGEST_REDIS_DROPIN+="$(basename -- "$_p" 2>/dev/null || true) "
  done
  INNGEST_REDIS_DROPIN="${INNGEST_REDIS_DROPIN% }"
fi

# Four states that service_journal_tail collapses to the same empty string. Without this, an
# empty tail is an unreachable error path and "the unit logged nothing" is indistinguishable
# from "this host has no journalctl".
if ! command -v journalctl >/dev/null 2>&1; then
  INNGEST_REDIS_TAIL_STATUS="no-journalctl"
elif [[ "$INNGEST_REDIS_LOADSTATE" == "not-found" ]]; then
  INNGEST_REDIS_TAIL_STATUS="unit-unknown"
elif [[ -z "$INNGEST_REDIS_JOURNAL_TAIL" ]]; then
  INNGEST_REDIS_TAIL_STATUS="empty"
else
  INNGEST_REDIS_TAIL_STATUS="ok"
fi

# Presence + mtime + BYTE LENGTH ONLY of the shared credential — never the value. Load-bearing
# because the drop-in's `-` prefix makes it silently INERT when this file is absent, so without
# this field "fix delivered" and "fix delivered inert" are indistinguishable.
INNGEST_REDIS_CREDFILE=""
_credfile="${SOLEUR_DOPPLER_TOKEN_FILE:-/etc/default/soleur-doppler-token}"
if [[ -f "$_credfile" ]]; then
  INNGEST_REDIS_CREDFILE="present mtime=$(stat -c '%Y' "$_credfile" 2>/dev/null || echo 0) bytes=$(stat -c '%s' "$_credfile" 2>/dev/null || echo 0)"
else
  INNGEST_REDIS_CREDFILE="absent"
fi

# Data-dir hypothesis.
#
# EVERY CALL IS UNDER `timeout`, and that is the load-bearing part rather than defensive habit.
# /mnt/data is a NETWORK-BACKED Hetzner volume (inngest-redis.service pins RequiresMountsFor,
# server.tf attaches it by-id). On a detached or IO-erroring volume, `[[ -d ]]`, `stat` and `df`
# all block in UNINTERRUPTIBLE SLEEP — and `2>/dev/null || echo` catches ERRORS, not HANGS, while
# webhook.service sets no command timeout, so the HTTP connection would simply hang. That is the
# worst possible failure for this field: "missing or re-owned data dir" is one of the very
# hypotheses it was added to adjudicate, so an unbounded probe disables the endpoint under
# exactly the condition it exists to report — in the PR that deletes the SSH fallback.
#
# `timeout` on the `[[ -d ]]` is not expressible, so the presence test rides `timeout ... test`.
# Missing `timeout` collapses to `unknown` rather than running unbounded.
#
# The symlink check is lstat on the FINAL component only, so a symlinked PARENT is not refused.
# That is acceptable and deliberately not more: the payload is owner/group/mode plus a df
# percentage — never file CONTENT — so this is not a disclosure primitive, and the env seam is
# not caller-reachable (the deploy-status hook passes no arguments or environment).
INNGEST_REDIS_DATADIR=""
_datadir="${INNGEST_REDIS_DATA_DIR:-/mnt/data/redis}"
if ! command -v timeout >/dev/null 2>&1; then
  INNGEST_REDIS_DATADIR="unknown-no-timeout"
elif timeout 3 test -L "$_datadir" 2>/dev/null; then
  INNGEST_REDIS_DATADIR="refused-symlink"
elif timeout 3 test -d "$_datadir" 2>/dev/null; then
  INNGEST_REDIS_DATADIR="present $(timeout 3 stat -c '%U:%G %a' "$_datadir" 2>/dev/null || echo 'unknown') use=$(timeout 3 df -h --output=pcent "$_datadir" 2>/dev/null | tail -1 | tr -d ' ' || echo '?')"
elif timeout 3 test -e "$_datadir" 2>/dev/null; then
  INNGEST_REDIS_DATADIR="present-not-a-directory"
else
  # Distinguishes "the probe answered: absent" from "the probe could not answer" — a wedged
  # volume must NOT read as a clean absence. `timeout` exits 124 on expiry.
  _dd_rc=0; timeout 3 test -e "$_datadir" >/dev/null 2>&1 || _dd_rc=$?
  if [[ "$_dd_rc" == "124" ]]; then
    INNGEST_REDIS_DATADIR="probe-timeout"
  else
    INNGEST_REDIS_DATADIR="absent"
  fi
fi

# Package-churn / port-collision hypotheses. ABSOLUTE path (matching the unit's own ExecStart),
# never a PATH lookup, and under `timeout` so a wedged binary cannot hang the endpoint.
# `is-enabled` exits non-zero when masked/disabled, hence the `|| true` under `set -e`.
# The `absent` token is NOT cosmetic. Without it this field emitted a bare " distro_unit=" for
# THREE different causes — binary absent (the package-churn hypothesis this field exists to
# test), `timeout` absent, and `--version` failing — collapsing them into one representation on
# the one field whose whole job is to discriminate them. Its two siblings (credfile, datadir)
# both got explicit absent tokens; this one was the outlier.
INNGEST_REDIS_BINARY=""
_redis_bin="${SOLEUR_REDIS_SERVER_BIN:-/usr/bin/redis-server}"
if ! command -v timeout >/dev/null 2>&1; then
  INNGEST_REDIS_BINARY="unknown-no-timeout"
elif [[ ! -x "$_redis_bin" ]]; then
  INNGEST_REDIS_BINARY="absent"
else
  INNGEST_REDIS_BINARY="$(timeout 5 "$_redis_bin" --version 2>/dev/null | head -c 200 || true)"
  [[ -n "$INNGEST_REDIS_BINARY" ]] || INNGEST_REDIS_BINARY="version-unreadable"
fi
if command -v systemctl >/dev/null 2>&1; then
  INNGEST_REDIS_BINARY+=" distro_unit=$(systemctl is-enabled redis-server 2>/dev/null || true)"
fi

# Settles "is redis silent, or is the SHIPPER not carrying it?" FROM THE PAYLOAD. vector.toml is
# baked into the OCI bootstrap image and is NOT in the infra-config FILE_MAP, so a running host's
# config can predate the inngest-redis allowlist entry — in which case zero Better Stack rows
# says nothing about redis.
#
# THE HASH ALONE CANNOT ANSWER THAT, and the first draft's comment claiming it could was wrong.
# The on-host file is a RENDER, not a copy: vector.toml carries four @@HOST_NAME@@ sentinels and
# three different renderers substitute them differently (soleur-host-bootstrap.sh uses
# $(hostname), inngest-bootstrap.sh a literal, server.tf the TF-known name). So the on-host
# sha256 NEVER equals the repo sha256 on any host, and a repo comparison degrades to "did it
# change between two reads" — which is not the question.
#
# The question is a MEMBERSHIP one, so answer it directly: does the running config allowlist the
# `inngest-redis` tag? Precedent for grepping the INSTALLED file for a marker rather than
# hashing it is already in-repo (server.tf's probe-script assertions).
#
# The grep is anchored on the QUOTED ENTRY form, not the bare token: vector.toml names
# `inngest-redis` in a comment ~14 lines above the real allowlist entry, so a bare-token grep
# would report the allowlist as live on a config that only DISCUSSES it. Same
# comment-matches-the-assertion class this PR's other guards are anchored against.
#
# The sha is kept as a cheap change-detector (two reads, same host), which is all it was ever
# able to be.
VECTOR_CONFIG_IDENTITY=""
_vector_cfg="${VECTOR_CONFIG_PATH:-/etc/vector/vector.toml}"
if [[ -f "$_vector_cfg" ]]; then
  # `redis_allowlisted` is the field that actually adjudicates E8. Anchored on the quoted entry
  # so the comment 14 lines above the real entry cannot satisfy it.
  _vec_redis=no
  grep -qF '"inngest-redis",' "$_vector_cfg" 2>/dev/null && _vec_redis=yes
  VECTOR_CONFIG_IDENTITY="redis_allowlisted=$_vec_redis sha256=$(sha256sum "$_vector_cfg" 2>/dev/null | cut -d' ' -f1 || true) mtime=$(stat -c '%Y' "$_vector_cfg" 2>/dev/null || echo 0)"
else
  VECTOR_CONFIG_IDENTITY="absent"
fi

HEARTBEAT_STATUS="$(service_status inngest-heartbeat.service)"
# #6536: the unit's OWN journal tail. `inngest_heartbeat: failed` reports THAT the unit broke
# but never WHY — the deciding datum is its stderr, and #6536 burned 3 days (3,724 fires)
# precisely because that stderr was unreadable off-box. Now that the unit sets
# SyslogIdentifier=inngest-heartbeat, this tail surfaces the discriminator with no SSH:
# curl's `blank argument` rc=2 line, doppler's project/auth error, or the dark-arm
# `url_present=no` row. Complements (does not replace) the Better Stack channel — this one
# works even when Vector itself is the thing that is broken.
HEARTBEAT_JOURNAL_TAIL="$(service_journal_tail inngest-heartbeat.service)"
# #6536: WHICH heartbeat arm this host actually rendered. inngest-bootstrap.sh resolves host
# identity at RENDER time — on DOPPLER_PROJECT=soleur-inngest it substitutes the dark arm into
# the ping script (absent URL -> log + exit 0); on the co-located web host it deletes the
# sentinel, so an absent URL reaches curl and exits 2, loudly. That decision is a one-time
# bootstrap-log line, so off-box there is otherwise NO way to tell which arm a running host
# carries — the two hosts' scripts differ by three lines and nothing reports it.
#
# Why that matters concretely: the render keys off $DOPPLER_PROJECT, and inngest-bootstrap.sh
# defaults it to `soleur` when unset. A future redeploy path that reaches this host without
# exporting it would render the WEB arm here and silently restore the 60s rc=2 storm #6536
# fixed. This field makes that a one-field read instead of a re-diagnosis. `url_present=no`
# appears ONLY in the dark arm's logger line — never in the script's comments — so its
# presence is an exact discriminator (verified against both rendered outputs).
#
# `-r` first: absent/unreadable is reported as its own value, never conflated with `absent`
# (a missing script and a deliberately-omitted arm are different faults).
if [ -r /usr/local/bin/inngest-heartbeat.sh ]; then
  if grep -q 'url_present=no' /usr/local/bin/inngest-heartbeat.sh 2>/dev/null; then
    HEARTBEAT_DARK_ARM="rendered"      # dedicated host: absent URL skips the ping (expected while dark)
  else
    HEARTBEAT_DARK_ARM="absent"        # co-located web host: absent URL stays loud (expected on the live pusher)
  fi
else
  HEARTBEAT_DARK_ARM="script-missing"
fi
# inngest-heartbeat.service is a Type=oneshot unit (no RemainAfterExit) driven by
# inngest-heartbeat.timer (OnUnitActiveSec=60s; the unit + timer are written by
# inngest-bootstrap.sh — the heartbeat block around the HEARTBEAT_UNIT/HEARTBEAT_TIMER
# heredocs, NOT :216-245, which is the Doppler-token materialisation block). It
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
  --arg hbj "$HEARTBEAT_JOURNAL_TAIL" \
  --arg hbd "$HEARTBEAT_DARK_ARM" \
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
  --arg rs "$INNGEST_REDIS_STATUS" \
  --arg rj "$INNGEST_REDIS_JOURNAL_TAIL" \
  --arg rr "$INNGEST_REDIS_RESULT" \
  --arg rd "$INNGEST_REDIS_DROPIN" \
  --arg rc2 "$INNGEST_REDIS_CREDFILE" \
  --arg rdd "$INNGEST_REDIS_DATADIR" \
  --arg rb "$INNGEST_REDIS_BINARY" \
  --arg rts "$INNGEST_REDIS_TAIL_STATUS" \
  --arg vci "$VECTOR_CONFIG_IDENTITY" \
  '$base + $cr + $cd + $sl + {host_id: $hid, sandbox_canary: $sc, seccomp_profile_sha256: $sps, journald_storage: $js, services: (($base.services // {}) + {
    inngest_heartbeat: $hb,
    inngest_heartbeat_journal_tail: $hbj,
    inngest_heartbeat_dark_arm: $hbd,
    inngest_heartbeat_timer: $hbt,
    inngest_server: $is,
    vector: $vs,
    vector_journal_tail: $vj,
    inngest_journal_tail: $ij,
    inngest_crons: $ic,
    inngest_redis: $rs,
    inngest_redis_journal_tail: $rj,
    inngest_redis_result: $rr,
    inngest_redis_dropin: $rd,
    inngest_redis_credfile: $rc2,
    inngest_redis_datadir: $rdd,
    inngest_redis_binary: $rb,
    inngest_redis_tail_status: $rts,
    vector_config_identity: $vci
  })}'
