---
feature: aeo-rubric-reconcile-2679
plan: knowledge-base/project/plans/2026-04-22-chore-aeo-rubric-reconcile-plan.md
status: ready
---

# Tasks: AEO audit rubric reconciliation

## Phase 1 — Agent doc update

- [ ] 1.1 Read `plugins/soleur/agents/marketing/growth-strategist.md` GEO/AEO Content Audit section (lines ~45-120)
- [ ] 1.2 Add preamble mandating both tables in every AEO audit
- [ ] 1.3 Embed SAP scorecard template skeleton (Dimension / Weight / Score / Weighted / Notes; weights 40/35/25; grading scale A/B/B+/C/D)
- [ ] 1.4 Embed 8-component AEO diagnostic template skeleton (weights sum to 100: FAQ=20, Answer density=15, Statistics=15, Source citations=15, Conversational=10, Entity clarity=10, Authority/E-E-A-T=10, Citation-friendly=5)
- [ ] 1.5 Preserve existing narrative sub-signal guidance under each SAP dimension as rubric commentary beneath the skeletons
- [ ] 1.6 Run `npx markdownlint-cli2 --fix plugins/soleur/agents/marketing/growth-strategist.md`; re-read after fix to catch any `cq-prose-issue-ref-line-start` issues

## Phase 2 — Workflow prompt update

- [ ] 2.1 Read `.github/workflows/scheduled-growth-audit.yml` Step 2 block (lines ~98-109)
- [ ] 2.2 Replace the open-ended "produce a structured scoring table" with natural-language prompt enumerating both tables, weights, grading scale, and mandatory-both-tables directive
- [ ] 2.3 Verify 12-space base indentation stays inside the `prompt: |` block (no column-0 lines, no heredocs)
- [ ] 2.4 Validate YAML: run `yamllint .github/workflows/scheduled-growth-audit.yml` (or `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-growth-audit.yml'))"`)

## Phase 3 — Runbook parser update

- [ ] 3.1 Read `knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md` Phase 2 extraction block
- [ ] 3.2 Add Phase 2 header note documenting threshold-translation worked example (old `40` → `PRESENCE_PCT=40`, new `20/25` → `PRESENCE_PCT=80`)
- [ ] 3.3 Replace single-pattern grep with `awk -F'|' 'NF >= 5 && $2 ~ /^ *(\*\*)?Presence(\*\*)?( & Third-Party Mentions)? *$/'`
- [ ] 3.4 Update score parser: trim whitespace (`SCORE_CELL="${SCORE_CELL// /}"`), accept both `40` and `20/25`; include `$PRESENCE_LINE` in error message
- [ ] 3.5 Rename `PRESENCE_SCORE` → `PRESENCE_PCT` (or set both) at the Phase 3 branch-selection site so comparison is uniform
- [ ] 3.6 Update Test Scenarios table: add row for `20/25` format → `PRESENCE_PCT=80` → PASS, and preserve the historical `40` row → FAIL
- [ ] 3.7 Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-19-chore-aeo-presence-reaudit-after-pr-2596-plan.md`; re-read after

## Phase 4 — Ship and post-merge verification

- [ ] 4.1 Run `skill: soleur:compound` before commit (per `wg-before-every-commit-run-compound-skill`)
- [ ] 4.2 Run `skill: soleur:ship` to commit + push + mark PR ready. PR body must include `Closes #2679` and `Closes #2615` on their own lines, plus a verification paragraph citing `knowledge-base/marketing/audits/soleur-ai/2026-04-21-aeo-audit.md` with Presence `20/25 (80%)` ≥ 55. Backtick-wrap all issue references to avoid `cq-prose-issue-ref-line-start`.
- [ ] 4.3 After merge: `gh workflow run scheduled-growth-audit.yml`; poll `gh run list --workflow=scheduled-growth-audit.yml --limit 1 --json status,conclusion,url`
- [ ] 4.4 Run deterministic validator (from Acceptance Criteria) against the post-merge audit file — must pass on Structure/Authority/Presence rows + 8-component rows
- [ ] 4.5 If validator fails: file P1 follow-up (`priority/p1-high`, `type/chore`, `domain/marketing`) titled `chore(aeo): pinned prompt dropped — investigate agent compliance`
- [ ] 4.6 Confirm `#2679` and `#2615` are both CLOSED by the merge
