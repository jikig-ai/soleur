# Tasks: Zot / ADR-096 wrap-up (#9391 close + supersede notes)

Plan: knowledge-base/project/plans/2026-10-04-chore-zot-adr096-wrapup-close-9391-and-supersede-notes-plan.md

## Phase 1: Verify and close #9391 (read-only, then one issue close)

- 1.1 Re-read live state: issue 9391 is OPEN, apply-web-platform-infra.yml state, run 37209725107 conclusion
- 1.2 Confirm both "Apply complete" lines in run 37209725107 (7 added / 0 destroyed non-SSH; 2 added / 2 destroyed SSH)
- 1.3 Run reconcile-live-heartbeats.ts with the read-only token: expect surface=logs_alert declared=10 and no logs-alert-absent / logs-alert-paused row
  - 1.3.1 Direct API read: soleur-ghcr-hostsfile-deny-lost-prd paused=false
  - 1.3.2 If an 18:00Z scheduled reconcile run exists, cite its surface=logs_alert line too
- 1.4 Run the runbook ghcr_deny_rows decode: both =1 positive controls first, then both =0 queries (bounded output)
- 1.5 Post one evidence comment on #9391 (counts and names only, no raw rows, no secrets)
- 1.6 gh issue close 9391 (reason completed) and verify CLOSED; PR body uses Ref #9391, not Closes

## Phase 2: Append superseding notes (additions only)

- 2.1 cron-egress-blocked.md: dated "Superseded 2026-10-04" blockquote under "Known residual: web-1 until the apply workflow runs"
- 2.2 cron-egress-blocked.md: one-line dated update at the end of "Known residual: running web-2"
- 2.3 ADR-218: append bullet "Merge consequence, update 2026-10-04" at end of the #9391 amendment; use the numbers Phase 1.3 printed
- 2.4 Verify git diff --numstat shows 0 deletions and no .github/ or apps/ path

## Phase 3: Ship (existing draft PR #9487)

- 3.1 Commit (Co-Authored-By trailer, then Claude-Session trailer; no [ack-destroy] line)
- 3.2 Push, mark ready via soleur:ship, PR body with Ref #9391 and the Phase 4 findings; do not sync with main unless required
- 3.3 Rely on CI (infra-validation.yml runs ghcr-blocked-alert.test.sh); no local full test battery

## Phase 4: Read-and-report (no edits)

- 4.1 #9393: web-1 delivered; web-2 waits for #9372 rebirth (ADR-263), never plain web-host-replace; operator decides
- 4.2 #9390: held; trigger conditions all unmet; re-read confirms
- 4.3 #9291: surface only; web arm of the new alert inherits the per-deploy sample staleness
- 4.4 Monitor-audit warning: sentry-monitors-audit.sh Class A; two monitors in cron_monitor_alert_unrouted by design; report only
