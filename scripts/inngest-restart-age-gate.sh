#!/usr/bin/env bash
# inngest-restart-age-gate.sh — restart give-up AGE gate for the external inngest health
# watchdog (#6374, Defect 3). SOURCED by .github/workflows/scheduled-inngest-health.yml
# AND by scripts/inngest-restart-age-gate.test.sh.
#
# WHY an AGE gate, not a body counter: the auto-dispatch step runs BEFORE the tracking
# issue is created (on the first failure there is no store to read/write), and a
# `gh issue edit --body` counter is a read-modify-write clobber/race. An age gate needs
# ONE read (the open [ci/inngest-down] issue createdAt) and ZERO writes, and self-corrects
# on recovery (the issue auto-closes → the next episode opens a fresh issue → age resets).
# It only ends the ~14x churn when Phase 2's stable probe is in place — a flapping
# false-positive re-opens/re-closes the issue and resets the age (documented contingency).
#
# echoes "true" (dispatch a restart) or "false" (give up — restarts exhausted).
#   $1 = the open issue createdAt (ISO-8601) or "" when no issue is open (first failure)
#   $2 = GIVE_UP_WINDOW minutes (e.g. 45 ≈ 3 */15 cycles)
#   $3 = now epoch seconds (injected for deterministic tests)
restart_ok_from_age() {
  local created="$1" window_min="$2" now_epoch="$3"
  # First failure of the episode — no issue yet → dispatch once.
  if [[ -z "$created" ]]; then echo "true"; return 0; fi
  local created_epoch
  created_epoch=$(date -u -d "$created" +%s 2>/dev/null || echo "")
  # Unparseable timestamp → fail-OPEN: never let a parse glitch strand a genuinely-down
  # inngest by suppressing its restart. The Sentry heartbeat keeps paging regardless.
  if ! [[ "$created_epoch" =~ ^[0-9]+$ ]]; then echo "true"; return 0; fi
  local age_min=$(( (now_epoch - created_epoch) / 60 ))
  if (( age_min < window_min )); then echo "true"; else echo "false"; fi
}

# resolve_effective_failure_mode — persistence-escalation resolver for the functions_query_degraded
# soft mode (#6407). A SUSTAINED functions_query_degraded (loopback /health=200 but the /v0/gql
# functions query PERMANENTLY wedged) must not be soft-masked forever: once the open
# [ci/inngest-functions-degraded] issue is >= GIVE_UP_WINDOW minutes old, reclassify the cycle's
# verdict to inngest_down (restart + page). First occurrence stays soft. All OTHER modes pass
# through unchanged. Reuses restart_ok_from_age for the age math (single source of truth) — "true"
# while age < window (or no issue = first occurrence) keeps it soft; "false" at/after the window
# escalates. Pure (age injected); the caller keeps the ONE `gh issue list` read outside the seam so
# the decision itself is deterministically unit-testable (#6407 review, test-design Finding A).
#   $1 = the current cycle's failure_mode
#   $2 = the open [ci/inngest-functions-degraded] issue createdAt (ISO-8601) or "" (none open)
#   $3 = GIVE_UP_WINDOW minutes
#   $4 = now epoch seconds (injected for deterministic tests)
# echoes the effective failure_mode.
resolve_effective_failure_mode() {
  local failure_mode="$1" created="$2" window_min="$3" now_epoch="$4"
  if [[ "$failure_mode" != "functions_query_degraded" ]]; then echo "$failure_mode"; return 0; fi
  if [[ "$(restart_ok_from_age "$created" "$window_min" "$now_epoch")" == "false" ]]; then
    echo "inngest_down"
  else
    echo "functions_query_degraded"
  fi
}
