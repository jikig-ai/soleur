---
title: Machine-readable verify_by marker + scheduled expiry gate for estimate ledger rows
status: accepted
date: 2026-07-17
issue: 6602
supersedes: null
---

# ADR-121: verify_by expiry gate for estimate ledger rows

## Context

`knowledge-base/operations/expenses.md` carries vendor spend, some of it **estimates** (a
catalog list price, a flat published tier, an amortized annual figure) pending confirmation on
the next invoice. The failure mode this ADR addresses (#6589): the Sentry row sat **78% wrong for
five weeks** because its "verify on next invoice" caveat was **prose** — no date, no owner, no
machine-readable marker — so nothing fired when the estimate outlived its own verification window.
An operator then mis-reads a COGS subtotal / break-even / margin off a stale figure.

A sibling proposal (#6584) is a **parity gate**: compare the tabled `cost-model.md` lines to the
*active* ledger rows — an **existence check**. That cannot see the #6589 defect: the Sentry row was
present, tabled, and correctly anchored; only its **amount** was fiction. Existence-checking sees
present-vs-absent, never present-but-wrong-amount.

The defect is **time-based** — "an estimate that outlives its verify_by date" fires with **zero
commits** between PRs — so a commit-time test or PR hook structurally cannot catch it. The runtime
gate must be **scheduled**.

## Decision

1. **The estimate flag is a machine-readable marker, not prose.** An estimate row carries, in its
   Notes cell, an HTML-comment marker:
   `<!-- estimate verify_by=YYYY-MM-DD owner=<role> source="<named invoice/endpoint>" -->`.
   It is **invisible** in the rendered ledger, **greppable**, and **parseable** per field. A row is
   an estimate **iff** it carries the marker; verifying a figure against a live source **removes**
   the marker (the Sentry row now carries none). So `verify_by`/`owner`/`source` are the single
   source of truth — there is no prose date to drift from the marker date (the precise rot in #6589).
2. **`verify_by` tracks the vendor's real billing cadence**, not booking-date + an arbitrary window:
   monthly vendors → next monthly invoice; **annual vendors → the annual renewal date** (a month-out
   date on an annually-billed row noise-files every month for a figure that cannot be re-verified
   until renewal).
3. **A deterministic checker enforces it.** `scripts/expenses-verify-by-check.sh` (100% bash, no LLM)
   parses the markers position-independently (grep the token, not awk column offsets) and exits
   **1** (expired, offending rows named) / **0** (clean, incl. an explicit "0 estimates" state) /
   **2** (malformed marker OR broken-parser positive-sample failure — never a silent skip).
4. **Scheduling is Inngest-dispatched (ADR-033), never a raw `schedule:` key.** `cron-expenses-verify-by.ts`
   (weekly, Mon 08:00 UTC) dispatches `scheduled-expenses-verify-by.yml` via `workflow_dispatch`; the
   workflow runs the checker and, on rc 1, files a **single idempotent** GitHub issue (constant title,
   offending rows in the body), auto-closing it when a later run is clean.
5. **No new Sentry cron monitor (Design A).** A monitor seat costs $0.78/mo against the ~$7.78 PAYG
   headroom on the very Sentry row #6589 corrected; for a low-stakes weekly advisory checker that is
   not worth it. Scheduler liveness rides `cron-inngest-cron-watchdog` + `EXPECTED_CRON_FUNCTIONS`
   parity. The feature practices the frugality it enforces.

This is the **complementary control** to #6584's existence-based parity gate: parity checks whether a
row is *present*; this checks whether a present row's amount has *expired its verification date*. Rationale
mirrors **ADR-076** (a curated register + a deterministic drift detector, LLM never in the detection path)
and **ADR-033** (Inngest dispatch-hybrid as the single scheduling substrate).

## Consequences

- Every estimate figure now carries an owner and a real expiry date; the next #6589 self-reports on the
  calendar instead of hardening silently into a cited number.
- The marker collapses *estimate* and *verified-but-usage-volatile* into one binary state ("no marker =
  verified"). Usage/monitor-count-driven rows (Sentry, xAI) that move without a discrete invoice arguably
  need a **recurring** re-verify cadence, not a one-shot `verify_by`. Out of scope here; noted for a
  follow-up (those rows carry their own notes + drivers today).
- A `|` inside a marker breaks the markdown table cell — the checker treats it as an anomaly (exit 2), so
  the constraint is enforced, not just documented.
- The gate is on-demand runnable (`gh workflow run scheduled-expenses-verify-by.yml --ref main`); a missed
  scheduled run only delays noticing an expired estimate by a week.

## Alternatives Considered

| Alternative | Why not |
|-------------|---------|
| Raw GHA `schedule:` cron | Blocked by the `new-scheduled-cron-prefer-inngest` PreToolUse hook; Inngest is the single scheduling substrate (ADR-033). |
| Commit-time test / PR hook only | Cannot catch calendar rot — the defect fires with zero commits between PRs. A unit test *also* exists (`.test.sh`) but tests the checker, not the calendar. |
| #6584 parity (existence) gate alone | Sees present-vs-absent, not present-but-wrong-amount — the exact #6589 blind spot this closes. Complementary, not a substitute. |
| New Sentry cron monitor (Design B) | $0.78/mo against ~$7.78 PAYG headroom on the row #6589 corrected; a self-referential cost on a low-stakes advisory checker. Design A (no monitor) chosen, cfo-endorsed. |
| Prose "verify on next invoice" caveat (status quo) | The #6589 defect itself — unparseable, undated, unowned; nothing fires when it expires. |
