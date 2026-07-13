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
