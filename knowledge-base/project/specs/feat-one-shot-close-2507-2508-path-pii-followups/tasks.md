---
category: tasks
tags: [analytics, plausible, gdpr, pii, runbook, ops]
date: 2026-04-18
plan: knowledge-base/project/plans/2026-04-18-docs-path-pii-followups-plausible-erasure-and-filter-audit-plan.md
issues: [2507, 2508]
---

# Tasks — Drain #2507 + #2508 (path-PII ops follow-ups)

## 1. Setup

- [x] 1.1 Verify worktree: `pwd` ends with `.worktrees/feat-one-shot-close-2507-2508-path-pii-followups`.
- [x] 1.2 Verify branch: `git branch --show-current` equals `feat-one-shot-close-2507-2508-path-pii-followups`.
- [x] 1.3 Re-read `apps/web-platform/app/api/analytics/track/sanitize.ts` to confirm `SCRUB_PATTERNS` still holds `[email]` / `[uuid]` / `[id]` sentinels at the `SCRUB_PATTERNS` symbol anchor.

## 2. Author `plausible-pii-erasure.md`

- [x] 2.1 Create `knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md` with YAML frontmatter (`category: compliance`, `tags: [plausible, gdpr, pii, erasure]`, `date: 2026-04-18`).
- [x] 2.2 Write the **Scope** section: triggers (GDPR Art. 17, CCPA §1798.105 requests for pre-2026-04-17 users).
- [x] 2.2.1 Include explicit reference to PR #2503 and issue #2462 — both numbers.
- [x] 2.3 Write the **Regex source of truth** section with the three sentinels + regex strings verbatim from `SCRUB_PATTERNS`.
- [x] 2.4 Write the **Audit — Cloud Plausible** subsection: authenticated `curl` template against `/api/v1/stats/breakdown` with `property=event:props:path` and a filter per sentinel. Include Doppler key fetch (`PLAUSIBLE_API_KEY` from `prd`).
- [x] 2.5 Write the **Audit — Self-hosted Plausible** subsection: three ClickHouse `SELECT count() FROM plausible_events_db.events_v2 WHERE match(pathname, …)` templates, one per sentinel.
- [x] 2.5.1 Include a `DESCRIBE TABLE` pre-flight to guard against schema drift.
- [x] 2.6 Write the **Deletion — Cloud** subsection: Plausible support-request template (subject, body fields, signature).
- [x] 2.7 Write the **Deletion — Self-hosted** subsection: ClickHouse `ALTER TABLE … DELETE WHERE …` template with mandatory dry-run, backup reminder, change-control checklist.
- [x] 2.8 Write the **Privacy-policy note** section explaining retention-window semantics.
- [x] 2.9 Write the **Cross-references** section linking scrubber source (symbol anchor), scrubber plan, Plausible docs, sibling filter-audit runbook, issues #2462 / #2503 / #2507 / #2508.
- [x] 2.10 Run `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md` — must return 0 errors.
- [x] 2.11 Re-read file after lint autofix.

## 3. Author `plausible-dashboard-filter-audit.md`

- [x] 3.1 Create `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md` with YAML frontmatter (`category: analytics`, `tags: [plausible, dashboard, filter, audit, path-pii]`, `date: 2026-04-18`).
- [x] 3.2 Write the **Scope** section referencing PR #2503 and #2462.
- [x] 3.3 Write the **Sentinel mapping** table with three BEFORE/AFTER examples (email, UUID, numeric ID).
- [x] 3.4 Write the **Audit procedure — KB grep** subsection: `rg` template for email / UUID / 6+ digit patterns over `knowledge-base/**/*.md`. Note: hits on the two new runbooks themselves are expected.
- [x] 3.5 Write the **Audit procedure — BI tool checklist** subsection: checkboxes for Plausible native, Looker Studio, Metabase, Tableau, Grafana.
- [x] 3.6 Write the **Remediation** section with prefix-filter and sentinel-filter examples, plus time-window caveat.
- [x] 3.7 Write the **Operator announcement template** — one-paragraph copy-pasteable message for #engineering.
- [x] 3.8 Write the **Close-out criteria** section with explicit 2026-05-17 date (30 days after 2026-04-17).
- [x] 3.9 Write the **Cross-references** section.
- [x] 3.10 Run `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md` — 0 errors.
- [x] 3.11 Re-read file after lint autofix.

## 4. Source cross-link

- [x] 4.1 Edit `apps/web-platform/app/api/analytics/track/sanitize.ts`: add a two-line comment immediately before `const SCRUB_PATTERNS` pointing at both new runbooks. Use symbol anchor (`SCRUB_PATTERNS`), not line number.
- [x] 4.2 Verify no other behaviour change: `git diff apps/web-platform/app/api/analytics/track/sanitize.ts` shows comment-only addition.
- [x] 4.3 Run scrubber tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts test/sanitize-props.test.ts` — must pass.

## 5. Verify runbook templates end-to-end

- [x] 5.1 Dry-run the erasure runbook's Stats API `curl` template against prod if `PLAUSIBLE_API_KEY` is in Doppler `prd`. Expect HTTP 200 with JSON body. If key absent, note in PR body and skip.
- [x] 5.2 Run the filter-audit runbook's KB grep template. Hits on the two new runbook files are expected; any other hit needs a one-sentence audit note in the PR body.
- [x] 5.3 Confirm both runbooks pass markdownlint in a single invocation.

## 6. Compound + commit

- [x] 6.1 Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`. Capture any learnings.
- [x] 6.2 Stage files: plan, tasks.md, two runbooks, one source edit.
  - `knowledge-base/project/plans/2026-04-18-docs-path-pii-followups-plausible-erasure-and-filter-audit-plan.md`
  - `knowledge-base/project/specs/feat-one-shot-close-2507-2508-path-pii-followups/tasks.md`
  - `knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md`
  - `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`
  - `apps/web-platform/app/api/analytics/track/sanitize.ts`
- [x] 6.3 Commit: `git commit -m "docs(ops): drain path-PII scope-outs #2507 + #2508"`.
- [x] 6.4 Push: `git push -u origin feat-one-shot-close-2507-2508-path-pii-followups`.

## 7. PR

- [x] 7.1 Create PR: title `docs(ops): drain path-PII scope-outs #2507 + #2508`.
- [x] 7.2 PR body MUST include `Closes #2507` and `Closes #2508` on separate lines (not in title — per `wg-use-closes-n-in-pr-body-not-title-to`).
- [x] 7.3 PR body includes summary, test plan checklist, notes on what the runbooks enable, and the close-out date 2026-05-17.
- [x] 7.4 Run `skill: soleur:review` and `skill: soleur:qa` (docs-only, so QA focus is markdownlint + tests-pass).
- [x] 7.5 After approval, mark PR ready: `gh pr ready <N>`; queue auto-merge: `gh pr merge <N> --squash --auto`; poll until MERGED.
- [x] 7.6 Post-merge: run `cleanup-merged`. Verify auto-close fired on #2507 and #2508 (`gh issue view 2507 --json state` → `CLOSED`; same for #2508).
