---
feature: feat-one-shot-8097-betterstack-send-failed-alert
issue: 8097
plan: knowledge-base/project/plans/2026-09-12-feat-betterstack-send-failed-alert-rule-plan.md
---

# Decision challenges — feat-one-shot-8097-betterstack-send-failed-alert

Persisted at plan time (headless pipeline; no pause). The operator's stated direction is the
default and is what the plan implements. `ship` Phase 6 renders these into the PR body as
informational statements and files them as an `action-required` issue.

---

## UC-1 — `SOLEUR_<UNIT>_HALT` rows are a sibling PRIORITY-2 class the alert deliberately does not page on

- **What you said:** one alert on substring `_SEND_FAILED` OR `_REFUSED`, message starting `SOLEUR_`, PRIORITY 2 — `SOLEUR_*_SEND_SKIPPED` excluded (#8097).
- **What both signals recommend:** add `'_HALT'` as a third `multiSearchAny` needle, or record the exclusion as a decision in ADR-218 (the plan does the latter).
- **Why:** enumeration `git grep -n 'logger -p user.crit' -- apps/web-platform/infra/*.sh` (definers, not tests) → exactly 8 call sites: the four `emit_refusal()` bodies (covered) and four top-of-file guards emitting `SOLEUR_DISK_MONITOR_HALT` / `SOLEUR_RESOURCE_MONITOR_HALT` / `SOLEUR_CONTAINER_RESTART_MONITOR_HALT` / `SOLEUR_CRON_EGRESS_ALARM_HALT reason=xtrace-credential-bound issue=7797` (not covered). A HALT means the monitor refused to run at all — the monitored condition is then unwatched, which is the same customer-meets-the-outage-first consequence #8097 names for a failed send. `SOLEUR_RESEND_INBOUND_BOOTSTRAP_HALT` also exists but its script never calls `logger` (stdout only), so it would not match either way.
- **What context we might be missing:** #7797 may treat a HALT as a deploy-time/config condition that a different channel already surfaces (the unit exits non-zero and systemd records the failure); paging on it could be redundant with whatever #7797 wired. We did not read #7797's closure evidence.
- **If we're wrong, the cost is:** a monitor silently halted by the xtrace guard stays dark with no page until someone reads the warehouse; the fix is a one-token needle addition (`'_HALT'`) and a nonce/predicate bump to re-verify — small, but it is a second merge and a second synthetic page.

---

## T-1 (Taste, plan-review CTO-devex) — expose the readback as a script flag for the operator's agent

- **Finding:** the runbook's step 1 (`doppler run … betterstack-query.sh <SQL>`) is agent-executable, not operator-executable; a `--recent` flag on the #8097 follow-through printing rows + `channel=`/`http_code=` decode would let `/soleur:go` run one command.
- **Disposition:** not applied. The follow-through was simplified to three exit paths at the same review (DHH/code-simplicity); adding an interactive mode to a run-once closure script re-grows it. The runbook's step 0 ("paste the alert name into `/soleur:go`") routes the operator to an agent that can assemble the SQL from the runbook. Re-evaluate if a second Logs alert lands and a shared readback helper earns its keep.

## T-2 (Taste, plan-review CTO-devex) — route "rule doubt" re-verification through a CI direct-ingest probe

- **Finding:** an `alert_paused` or predicate edit could be re-tested by POSTing a synthetic row straight to the Better Stack ingest (ADR-172 pattern) without a merge; a `probe_rev` bump should be reserved for channel doubt (`row_absent`).
- **Disposition:** not applied. The ingest probe pages ops@ exactly as the apply-path probe does and proves strictly less (skips web-1's journald/Vector); Phase 0.6b cut it and code-simplicity flagged its reappearance as a runbook deliverable. One re-fire path (`probe_rev` bump, one page) keeps the runbook to a single procedure.
