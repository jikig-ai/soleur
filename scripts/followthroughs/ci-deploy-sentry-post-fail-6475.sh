#!/usr/bin/env bash
# Follow-through soak for #6475 Item 2 (D-6): fail-loud on ci-deploy.sh Sentry
# POST failures.
#
# WHAT IT PROVES. apps/web-platform/infra/ci-deploy.sh emits best-effort Sentry
# events at seven fail-open sites (7 `logger … "Sentry POST failed"` lines across
# the tags CRON_DRAIN, SANDBOX_CANARY, IMAGE_VERIFY, IMAGE_PULL [×2],
# IMAGE_PULL_RECOVERY, ZOT_GATE). Each
# POST is fail-OPEN — `curl … --max-time 10 || logger -t "$LOG_TAG" "<TAG>: Sentry
# POST failed"` — which is CORRECT on-host behaviour (a deploy must never abort
# because Sentry telemetry is unreachable). But it means the *failure of the alarm
# path itself* is journald-only, and per hr-no-ssh-fallback-in-runbooks nobody
# reads a host's journald — so a Sentry POST failure during a REAL fallback event
# is silently unalarmed. D-6 closes that blind spot by making the signal LOUD:
# actively queried on a schedule, surfaced onto #6475.
#
# The "Sentry POST failed" lines are tagged `logger -t "$LOG_TAG"` with
# LOG_TAG="ci-deploy", and `ci-deploy` is already in vector.toml Source 4
# (host_scripts_journald) SYSLOG_IDENTIFIER allowlist — so they already ship to
# Better Stack Logs. What was missing is the active query + alarm; this probe is it.
#
# WHY Better Stack, not Sentry: a FAILED Sentry POST never arrives at Sentry, so a
# Sentry *query* would PASS vacuously and auto-close #6475 blind (the exact #5934
# trap). The only queryable sink for the POST-failure line is Better Stack
# (journald → Vector). This probe queries Better Stack via
# scripts/betterstack-query.sh and NEVER Sentry.
#
# SOUND signal = for the soak window: ci-deploy activity is observed
# (liveness ≥ 1, proof the emit→Vector→Better Stack path is live and deploys ran)
# AND zero "Sentry POST failed" lines from ci-deploy. Any such line in the window
# is the fail-loud trigger.
#
# AND-scope to the ci-deploy SYSLOG_IDENTIFIER FIELD (load-bearing, not merely
# defense-in-depth): a bare `ci-deploy` substring match is WRONG because inngest
# ships GitHub-webhook processing logs to the same Better Stack source, and those
# rows embed branch names ("…-ci-deploy-…") and issue/PR bodies that quote both
# "Sentry POST failed" and "ci-deploy" verbatim (this tracker's own body does). Only
# the journald SYSLOG_IDENTIFIER field (`SYSLOG_IDENTIFIER":"ci-deploy`) reliably
# isolates real ci-deploy emissions from that webhook contamination — see the
# CI_DEPLOY_*_MARKER constants below. (Aside: among host_scripts_journald tags only
# ci-deploy emits "Sentry POST failed" via logger -t; the sibling
# scripts/seccomp-unenforced-alert.sh emits the same string via a GitHub-Actions
# `::warning::` echo, not logger -t, and is not in Source 4, so it never reaches
# Better Stack.)
#
# FAIL-SAFE: any query/auth/config failure OR zero ci-deploy liveness → TRANSIENT
# (exit 2), never PASS — the probe can only ever close #6475 on positive proof of
# a live, clean window.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (liveness ≥ 1 ci-deploy row AND zero POST-failure rows; sweeper closes #6475)
#   1 = FAIL       (≥ 1 ci-deploy "Sentry POST failed" row; the D-6 alarm — sweeper comments #6475, leaves open)
#   2 = TRANSIENT  (query unreachable/unauth, creds unset, OR zero ci-deploy liveness — inconclusive)
#
# Required env (read by betterstack-query.sh): BETTERSTACK_QUERY_HOST,
#   BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD (wired in
#   scheduled-followthrough-sweeper.yml). Optional: CI_DEPLOY_SENTRY_SOAK_WINDOW
#   (Nh/Nm/Nd, default 7d). Test seam: CI_DEPLOY_SENTRY_BQ overrides the
#   betterstack-query.sh path.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BQ="${CI_DEPLOY_SENTRY_BQ:-$SCRIPT_DIR/../betterstack-query.sh}"

WINDOW="${CI_DEPLOY_SENTRY_SOAK_WINDOW:-7d}"
if ! [[ "$WINDOW" =~ ^[0-9]+[hmd]$ ]]; then
  echo "TRANSIENT: invalid CI_DEPLOY_SENTRY_SOAK_WINDOW '$WINDOW' (expected Nh/Nm/Nd)" >&2
  exit 2
fi

if [[ ! -x "$BQ" ]]; then
  echo "TRANSIENT: betterstack-query.sh not found/executable at $BQ" >&2
  exit 2
fi

# Creds-presence guard via an explicit empty-check, NOT a bash parameter-expansion
# abort-gate — the abort form exits status 1 under the sweeper's non-interactive
# shell (= FAIL = a loud alarm on a green codebase). Unset creds are inconclusive,
# not a recurrence → TRANSIENT.
if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  echo "TRANSIENT: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not all set — cannot query Better Stack; inconclusive" >&2
  exit 2
fi

# The `ci-deploy` discriminator MUST isolate the journald SYSLOG_IDENTIFIER FIELD,
# never a bare `ci-deploy` substring. Better Stack's `raw` column is the full
# journald JSON, and inngest ships GitHub-webhook processing logs to the SAME source
# — those embed branch names ("…-ci-deploy-…") and issue/PR bodies (which quote both
# "Sentry POST failed" and "ci-deploy" verbatim, including THIS tracker's own body).
# A bare-substring post-filter matched those and false-FAILed against live prod
# (2 doppler-tagged webhook rows in a 14d window, SYSLOG_IDENTIFIER=doppler, zero
# real ci-deploy emissions). Field isolation drops them. Two byte-forms are needed:
#  - LIKE_MARKER: the SERVER-side --grep term. betterstack-query.sh runs it as
#    `raw LIKE '%<term>%'` against the UNescaped ClickHouse column.
#  - GREP_MARKER: the CLIENT-side grep over betterstack-query.sh's JSONEachRow STDOUT,
#    where the inner quotes are backslash-escaped (`\"…\"`). Verified empirically
#    against real rows: real emissions carry `SYSLOG_IDENTIFIER\":\"ci-deploy\"`;
#    the webhook-contamination rows do not.
readonly CI_DEPLOY_LIKE_MARKER='SYSLOG_IDENTIFIER":"ci-deploy'
readonly CI_DEPLOY_GREP_MARKER='SYSLOG_IDENTIFIER\":\"ci-deploy\"'

# fetch_rows <grep_term> — echo the raw JSONEachRow output for rows matching
# <grep_term> in the window; return non-zero (caller → TRANSIENT) on any query
# failure. Mode-2 `--grep` auto-UNION-ALLs the ~40-min hot window with the s3
# archive, so a multi-day window is NOT silently truncated.
fetch_rows() {
  local term="$1" out rc
  out="$("$BQ" --since "$WINDOW" --grep "$term" --limit 1000 2>/dev/null)"; rc=$?
  [[ "$rc" -ne 0 ]] && return 1
  printf '%s' "$out"
  return 0
}

# POST-failure detection: fetch rows carrying the "Sentry POST failed" marker
# (broad, server-side), then post-filter to the ci-deploy SYSLOG_IDENTIFIER FIELD.
post_fail_rows="$(fetch_rows "Sentry POST failed")" || {
  echo "TRANSIENT: Better Stack query failed (POST-failure marker) — auth/config/network" >&2; exit 2; }
offending="$(printf '%s\n' "$post_fail_rows" | grep -F "$CI_DEPLOY_GREP_MARKER" || true)"
post_fail_count="$(printf '%s\n' "$offending" | grep -c . || true)"

# FAIL is evaluated BEFORE the liveness fetch so a real recurrence can never be
# masked by a fault on the (separate) liveness query — a "Sentry POST failed" row
# tagged ci-deploy is itself proof of activity, so FAIL is sound regardless of the
# liveness count. This is the genuine "FAIL takes precedence" ordering.
if [[ "$post_fail_count" -ge 1 ]]; then
  echo "FAIL: ${post_fail_count} ci-deploy 'Sentry POST failed' event(s) in ${WINDOW} — a real fallback/degraded-state Sentry POST failed and the alarm path was silent on-host. The D-6 blind spot recurred; investigate the offending deploy(s):"
  printf '%s\n' "$offending"
  exit 1
fi

# Liveness: real ci-deploy rows (SYSLOG_IDENTIFIER field) in the window — proof the
# emit→Vector→Better Stack path is live and deploys ran. Server-side --grep narrows
# with the LIKE marker; the client count re-isolates on the escaped field marker so
# a stray substring cannot inflate liveness. Zero → TRANSIENT, never PASS.
liveness_rows="$(fetch_rows "$CI_DEPLOY_LIKE_MARKER")" || {
  echo "TRANSIENT: Better Stack query failed (ci-deploy liveness) — auth/config/network" >&2; exit 2; }
liveness_count="$(printf '%s\n' "$liveness_rows" | grep -cF "$CI_DEPLOY_GREP_MARKER" || true)"

if [[ "$liveness_count" -eq 0 ]]; then
  echo "TRANSIENT: no ci-deploy (SYSLOG_IDENTIFIER) rows in ${WINDOW} — the emit→Better Stack path is unobserved (no deploys in window, or delivery not live); inconclusive, never PASS" >&2
  exit 2
fi

echo "PASS: ${liveness_count} ci-deploy row(s), zero 'Sentry POST failed' in ${WINDOW} — the ci-deploy Sentry-POST-failure rate holds at ~0 (D-6 #6475 soak clean)"
exit 0
