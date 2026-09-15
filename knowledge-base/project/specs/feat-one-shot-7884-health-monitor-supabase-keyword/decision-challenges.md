# Decision challenges — feat-one-shot-7884-health-monitor-supabase-keyword

Persisted headless per ADR-084 and the plan-review classifier. These are **Taste / User-Challenge**
decisions from plan review. They were **not** applied to the plan. `ship` Phase 6 renders this into
the PR body and files an `action-required` issue for any still open.

Plan: `knowledge-base/project/plans/2026-09-15-fix-health-monitor-supabase-keyword-import-plan.md`

## UC-1 — Split the reconcile into a second PR (User-Challenge)

- **Your direction (the default):** one PR (#8216) delivers all three 2026-09-15 decisions: import +
  keyword, the live-vs-declared guard, and the records.
- **Challenge (DHH P0, code-simplicity P1):** ship the alarm first (HCL, `-target=` line, contract
  test, probe, runbook, ADR-204 edit) and the reconcile in a second PR, so a review snag in the
  workflow/reconcile code does not keep production blind to a database outage.
- **What we don't know:** how long review of the reconcile half takes. After the plan-review cuts it
  is much smaller (no new workflow steps, no second issue family, no YAML test harness).
- **If you agree:** the plan's Phase 2 and the ADR-222 inventory section move to a follow-up PR;
  #7884 stays open until it merges.
- **Status:** open.

## T-1 — Alarm name (Taste)

- **Plan:** `pronounceable_name = "soleur app database readiness"`.
- **Alternative (CTO devex P2):** `"soleur app database down"` reads more plainly in an inbox subject.
- Either works; the reconcile matches monitors by URL, so a later rename is free.
- **Status:** open.

## T-2 — Keep the plan-added config-drift check (P6) (Taste)

- **Plan:** keep `monitor-config-drift` on `monitor_type`, `required_keyword` and `paused`, because the
  web-platform drift plan has filed six auto-closed issues in ~7 weeks and does not reliably surface a
  vendor-side disarm of this alarm. CTO and architecture review supported keeping it narrow.
- **Alternative (DHH, code-simplicity):** cut it and fix the noisy drift channel instead.
- **Status:** open.
