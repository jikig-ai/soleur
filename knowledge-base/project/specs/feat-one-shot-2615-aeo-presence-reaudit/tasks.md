---
title: "Tasks — AEO Presence re-audit (#2615)"
plan: knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md
issue: 2615
created: 2026-04-19
---

# Tasks — AEO Presence re-audit after PR #2596

This is a verification-only follow-through. No code, content, or workflow
changes will ship. Tasks below are operator actions against `gh` + the
existing `scheduled-growth-audit.yml` cron.

## 1. Pre-audit setup

- 1.1. Confirm the audit cron is healthy.
  - `gh run list --workflow=scheduled-growth-audit.yml --limit 5`
  - If the most recent run failed, investigate before proceeding.
- 1.2. Run the live-surface sanity check from the plan's Phase 2.
  - `curl -sSL https://soleur.ai/ -o /tmp/soleur-home.html`
  - Verify GitHub Stars tile renders an integer, `landing-press-strip` partial
    is present, and Organization JSON-LD has 5 `sameAs` URLs +
    `subjectOf[NewsArticle]`.
  - On failure: trigger `gh workflow run deploy-docs.yml`, wait for completion,
    re-check before proceeding.

## 2. Trigger or wait for the audit

- 2.1. **Default path:** wait for the Monday 09:00 UTC cron.
  - Next scheduled: 2026-04-20 09:00 UTC.
- 2.2. **Expedited path** (only if operator wants to close before Monday or the
  cron failed):
  - `gh workflow run scheduled-growth-audit.yml`
  - `gh run watch` (or poll `gh run list --workflow=scheduled-growth-audit.yml --limit 1`)
  - Wait for the `ci/growth-audit-<timestamp>` PR to auto-merge.

## 3. Extract the Presence score

- 3.1. Run the Phase 2 extraction script from the plan.
  - Locates the latest `*-aeo-audit.md` file.
  - Detects stub-fallback reports (workflow Step 3 failure mode).
  - Reads the Scoring Table header to find the `Score` column index by name.
  - Extracts the row anchored on `"Presence & Third-Party Mentions"`.
  - Validates the score is a 0–100 integer.
  - Also extracts overall AEO score for the closing comment.
- 3.2. **Marginal-score re-run** (audit-pair rule). If `52 <= score <= 58`:
  - `gh workflow run scheduled-growth-audit.yml`
  - Wait for the new audit's PR auto-merge.
  - Re-run 3.1 against the newer audit file.
  - Take the higher of the two scores as canonical.
  - Both audit dates and scores must appear in the closing comment.

## 4. Close or escalate

- 4.1. **PASS** (`PRESENCE_SCORE >= 60`): Close #2615 with the
  Branch A comment template (Phase 3 of the plan).
- 4.2. **PARTIAL PASS** (`55 <= PRESENCE_SCORE < 60`): Close #2615 with the
  Branch A comment template, but include the F-band caveat clause that the
  template auto-injects when score < 60.
- 4.3. **FAIL** (`PRESENCE_SCORE < 55`): Branch B path:
  - File the P1 tracker (`priority/p1-high,type/chore,domain/marketing`,
    milestone `Phase 4: Validate + Scale`) using the body template in the
    plan's Phase 3.
  - Add `needs-attention` label to #2615.
  - Comment on #2615 with the new tracker number.
  - Do NOT close #2615.

## 5. Definition of Done

- 5.1. #2615 is in a terminal state (closed with verification comment, or open
  with `needs-attention` + linked P1 tracker).
- 5.2. The audit file used for the decision is on `main` under
  `knowledge-base/marketing/audits/soleur-ai/`.
- 5.3. No code, content, workflow, or infra changes shipped from this plan.
- 5.4. If escalation fired, the new tracker is assigned to milestone
  `Phase 4: Validate + Scale` and labeled `priority/p1-high,type/chore,domain/marketing`.
