---
title: "Plan review — Codex notice rights and retention"
date: 2026-10-26
plan: knowledge-base/project/plans/2026-10-26-fix-codex-notice-rights-and-retention-plan.md
reviewed_plan_head: 1b5c54acc86486da7cfad25c781119834577c201
status: revised-cto-ruled-focused-recheck-pending
---

# Plan review findings

The initial plan review was run in waves because Codex allows three active
child agents. The DHH, Kieran, simplicity, architecture, spec-flow and CPO
seats completed against the pushed plan at `1b5c54a`. The CTO seat's first turn
ended on a usage-limit error; its retry returned the ruling below. The plan has
been revised against these findings and still needs a focused revision check.

## Findings and disposition

| Reviewer | Priority | Finding | Required plan change |
|---|---|---|---|
| DHH, Kieran, simplicity | P1 | A later worker read can miss issuance metadata deleted after the access request was received. | Snapshot the eligible non-secret projection atomically with admission of a distinct DSAR request; retries reuse that request snapshot, while a new request cannot reuse an old completed job/archive. |
| Architecture | P1 | Contract eligibility must be checked at the trusted boundary before a receipt is issued or provider work is admitted. | Specify an exact allowlist of verified contracting subject roles. Ineligible roles receive no receipt and no provider admission; owner/team status alone is not contract evidence. |
| Spec-flow | P1 | Current client resend requires prior acknowledgment; an expired unacknowledged notice cannot be renewed through the existing UI. | Include a reachable metadata-only renewal action, fresh notice, fresh acknowledgment and separate explicit resend. Reconnect and retry must not send the old nonce or dispatch provider work. Commit a `.pen` wireframe before UI implementation. |
| CPO | P1 | A completed export job is reused by `enqueueExport`, so a later request may receive an older archive. | Distinguish retries of one request from a genuinely new request and bind the admission-time projection to that request/job. |
| Kieran | P1 | `now()` is transaction-start time and can become stale while lifecycle locks are acquired. | Evaluate expiry with `clock_timestamp()` after the protected row locks and immediately before delivery/acknowledgment writes. Test the lock-wait boundary. |
| DHH, Kieran, simplicity | P2 | A separate expiry column duplicates the 30-minute policy and can drift from issuance time. | Derive expiry from `issued_at + interval '30 minutes'`; index `issued_at` for cleanup. Same-nonce retries do not renew it; a new nonce does. |
| Kieran | P2 | Successful cron counts do not reveal delayed expired rows or starvation. | Observe oldest expired-row age, backlog and last successful cleanup; define an issuance-health refusal threshold and bounded backlog behavior. |
| Spec-flow, CPO | P2 | Article 15 access was incorrectly conditional on Article 20 eligibility, and the plan overstated held-message persistence. | Keep Article 15 for retained subject rows regardless of eligibility for new processing/portability. State the existing 30-minute, tab-memory/cache bound and the reload/remount limitations; do not promise indefinite draft recovery. |
| DHH, architecture | P2 | Scheduler selection and architecture-record scope were prematurely committed. | Inventory actual database-owned and monitored schedule patterns; select one substrate, reuse existing observability, and amend ADR 098 only if the DSAR-job lifecycle materially changes. |
| All completed reviewers | P1 | The source estimate omitted request-time snapshots, renewal UX, wireframe and mirrored legal documents. A correction targeting `main` cannot apply its migration before held PR #9051's migration 175. | Re-inventory and stack dependent correction PRs on #9051's feature branch. Preserve all six asks and one completion gate across the stack. Keep #9051 draft and auto-merge off. |
| CTO | Ruling | Use two dependent correction slices stacked on #9051's held feature branch; snapshot eligible rights data atomically at request admission and export by job ID; use one database-owned one-minute `pg_cron` cleanup plus independent expired-age monitoring. A database outage can prevent deletion. | Preserved in the revised plan. Both slices must integrate before reconsidering #9051 readiness; cron registration is not proof of a hard deletion bound during outages. |
| Code simplicity recheck | P2 | Ordinal-only references to migration 175 are ambiguous because main and #9051 use distinct files with that ordinal. | Replace each with `175_codex_history_notice_issuance.sql`; preserve distinct full filenames and remeasure before assigning correction ordinals. |

## Recheck requirements

The plan needs a focused revision check for the new design. Phase 2 must prove
the cleanup's measured five-minute capacity and independent monitor binding.
Legal processing clearance, backup/PITR facts, actual subject basis/capacity,
shared capture approval, writer exclusion, qualification, QA, exact-head review
and preflight remain independent gates.
