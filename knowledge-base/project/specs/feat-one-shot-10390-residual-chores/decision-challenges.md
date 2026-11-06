---
title: Decision challenges — feat-one-shot-10390-residual-chores
date: 2026-11-06
---

# Decision Challenges

Headless pipeline run (one-shot planning subagent — no operator TTY, no
Task/Agent spawn capability, `cloud-detect` → `not-local:no-devin-env`).
Rulings that would normally go to a CTO/operator gate are recorded here per
`technical-ruling-delegation.md` and surfaced at ship time.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Surface-1 regression channel: decrement `ADVISORY_CEILING` vs promote the quoted `IDENT="$(gh…)` class into the census (advisory → gate finding) | technical | pending - assumed: decrement the ceiling to the post-resolution live count (target 0) — issue #12092's acceptance prescribes the ceiling as the regression channel ("resolved sites decrement it, never silently satisfy"), and a 0-floored ceiling delivers the same fail-closed property through the existing test layer without new lint grammar. Alternative on record: promote quoted captures to census findings after all 13 are dispositioned. |
| Inside-substitution `|| true` close-path reads (`scheduled-supabase-watchdog.yml:512`, `scheduled-actions-queue-health.yml:228`): `# dedupe: benign` marker vs move the `||` outside with a `::warning::` arm | technical | pending - assumed: `# dedupe: benign` markers — matches the in-repo precedent `scheduled-cron-artifact-age.yml:151` ("# dedupe: benign — || true inside on a close-path read: a failed lookup yields empty RECOVERED and the stale issue stays open") and `scheduled-inngest-health.yml:408`; a failed close-path read keeps the alarm open (visible), which is the benign bucket the marker vocabulary was defined for. Alternative on record: normalize both (the docstring calls inside-substitution `|| true` the worst shape; normalization removes it rather than blessing it — stronger against future copy-paste to a filing path). Work phase may re-consult if review objects. |
| Census-head extension to `gh api` issues-GETs and `gh issue|pr view` probes | technical | pending - assumed: do NOT extend `GH_DEDUPE_HEAD` — `gh api` argv grammar (`-X GET` + `/issues` path filtering vs POST writes) and `view`'s single-read shape do not share the enumeration-defect class the head models; the dedupe-shaped inventory is ≤2 sites already dispositioned. Per-site markers + the PR-body audit record deliver the issue's "decide per surface" acceptance without new grammar or a false-positive surface. |
| `scheduled-machinery-drain.yml:187` disposition: fail-closed `::error::`+`exit 1` vs fail-open `|| { …; matches=""; }` | technical | pending - assumed: fail-closed — a blind `matches=""` takes the else branch and files a DUPLICATE standing keep-open issue, the exact defect the dedupe read exists to prevent; `exit 1` reds the step (visible, retried next week). |
| `codeql-1537-revisit-watch.yml:84` disposition | technical | pending - assumed: `|| { echo "::warning::…"; track_num=""; }` — lands on the step's existing `[[ -z ]]` → `::warning::` + `exit 0` path, matching the step's own doctrine ("a transient API failure must NOT false-fire; treat any non-clean read as unknown → no-op"). |
| `scheduled-inngest-health.yml:699` (`HAS_ESCALATION`) disposition | technical | pending - assumed: normalize to the sibling `|| HAS_ESCALATION_RC=$?` + `::warning::` defer shape (`scheduled-supabase-watchdog.yml:441-444` is the in-repo template) — under `set -euo` the bare capture aborts mid-escalation; deferring one tick keeps the alarm visible without reposting the exhaustion comment on every faulting tick. |
| "Measured check-ins" bar for the WS2 route | technical | pending - assumed: satisfied — Sentry env `production` reports `status=ok`, `activeIncident=null`, `lastCheckIn 2026-11-06T10:00:01Z` on the `*/15` cadence since `dateCreated 04:32Z` (~22 expected ticks, zero missed-check-in incidents). A miss past `nextCheckInLatest` flips env status to error and opens an incident, so continuous `ok` over the full window is the plural-measured evidence the unrouted reason asks for. Work re-verifies before the `.tf` edit. |
