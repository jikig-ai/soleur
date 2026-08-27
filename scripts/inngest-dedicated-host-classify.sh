#!/usr/bin/env bash
# inngest-dedicated-host-classify.sh — pure classifier for the DEDICATED inngest host's
# SOLEUR_INNGEST_SERVER_PROBE row (#7674). SOURCED by
# .github/workflows/scheduled-inngest-health.yml and by
# apps/web-platform/infra/inngest-dedicated-host-classify.test.sh. No network, no side effects:
# given a row count plus three extracted fields it echoes exactly one verdict token.
#
# WHY THIS EXISTS. inngest-server-probe.sh has emitted SOLEUR_INNGEST_SERVER_PROBE hourly since
# #6617a, and until now NOTHING read it. Measured 2026-08-25: the dedicated host had been
# `server_active=inactive` for 5.4 days on one unchanged boot_id, and every one of those ~130
# rows ALSO carried `cutover_flag=rolled-back` — symptom and cause in the same line, unread.
# Meanwhile scheduled-inngest-health.yml polled the WEB host and stayed green, because the web
# host was genuinely healthy. A dead dedicated host was invisible by construction.
#
# WHY THE BRAKE GETS ITS OWN VERDICT. `inactive` with a standing rollback flag is not a fault —
# it is the flip FSM's `rollback` arm having done exactly what it was told, then no-op'ing on
# every 30s tick since. Collapsing it into a generic "not serving" would page for a deliberate
# state while burying the one field that explains it. The remediations are disjoint: a brake is
# released by a cutover, an unexplained stop is a diagnosis.
#
# Verdicts:
#   healthy             server_active=active AND http_code=200
#   stopped-by-brake    not serving, AND cutover_flag ∈ {rollback, rolled-back} — the flag
#                       explains the stop; no restart can fix it, only a cutover releases it
#   not-serving         not serving, and the flag does NOT explain it — a genuine unknown
#   probe-unavailable   no row in the window, an unreadable query, or a row whose fields did
#                       not parse. NEVER "healthy": a missing signal must not read as a
#                       working one (the probe_unavailable discipline of the sibling
#                       classifier, scripts/inngest-liveness-classify.sh)
#
# NOTE ON ORDERING: the brake arm is evaluated only AFTER the serving check, so a host that is
# genuinely serving is never laundered into `stopped-by-brake` by a stale flag, and a flag can
# never launder a non-200 into health.

# $1 = row count from the Better Stack read, or __UNREADABLE__ when the query failed
# $2 = server_active field   $3 = http_code field   $4 = cutover_flag field
classify_dedicated_host() {
  local rows="$1" active="$2" code="$3" flag="$4"

  # Absence and unreadability both fail to "cannot tell", never to health. A non-decimal count
  # reaches here only from a query failure sentinel, so it joins them rather than being coerced.
  case "$rows" in
    ''|*[!0-9]*) echo "probe-unavailable"; return 0 ;;
  esac
  if [[ "$rows" -eq 0 ]]; then echo "probe-unavailable"; return 0; fi

  # Rows existed but the fields did not parse — a shape change in the marker, or a row from a
  # renderer we do not understand. Same direction: cannot tell.
  if [[ -z "$active" || -z "$code" ]]; then echo "probe-unavailable"; return 0; fi

  if [[ "$active" == "active" && "$code" == "200" ]]; then echo "healthy"; return 0; fi

  case "$flag" in
    rollback|rolled-back) echo "stopped-by-brake"; return 0 ;;
  esac

  echo "not-serving"
}
