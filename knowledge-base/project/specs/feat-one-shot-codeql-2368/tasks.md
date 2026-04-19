# Tasks — feat-one-shot-codeql-2368

Derived from `knowledge-base/project/plans/2026-04-19-fix-verify-and-close-codeql-issue-2368-plan.md`.

## 1. Setup

- [ ] 1.1 Confirm worktree CWD `.worktrees/feat-one-shot-codeql-2368/` and branch `feat-one-shot-codeql-2368`.
- [ ] 1.2 `mkdir -p knowledge-base/project/specs/feat-one-shot-codeql-2368`.

## 2. Phase 1 — Verification Sweep

- [ ] 2.1 Snapshot all CodeQL alerts: `gh api '/repos/jikig-ai/soleur/code-scanning/alerts?per_page=100' --paginate > knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json`.
- [ ] 2.2 Filter to `apps/web-platform/*` and write `web-platform-alerts.json` (jq pipeline from plan Phase 1.2).
- [ ] 2.3 Run hard assertion: zero `state=open` high/critical alerts in `apps/web-platform/*`. If non-zero, ABORT and convert to remediation.
- [ ] 2.4 Cross-check the 9 issue-named alerts against the inventory table in the plan. Any miss → stop.

## 3. Phase 2 — Code-Drift Spot Check

- [ ] 3.1 `git log --since=2026-04-16` for each of the 9 named source files; record commit list.
- [ ] 3.2 For each commit returned, eyeball-diff against the specific defense named in the corresponding `dismissed_comment`.
- [ ] 3.3 Record outcome in scratch notes for Phase 3.

## 4. Phase 3 — Verification Evidence + Close-Out

- [ ] 4.1 Write `knowledge-base/project/specs/feat-one-shot-codeql-2368/verification.md` with the alert-state table, drift summary, and PR/brainstorm links.
- [ ] 4.2 `npx markdownlint-cli2 --fix` on changed `.md` files (specific paths, per AGENTS.md `cq-markdownlint-fix-target-specific-paths`).
- [ ] 4.3 Stage + commit: plan, tasks, snapshot JSONs, verification.md, learning. Use `/soleur:ship` for PR creation with `Closes #2368`.

## 5. Phase 4 — Workflow Learning + Skill Edit

- [ ] 5.1 Locate the right home for the pre-filing alerts-API gate (likely `plugins/soleur/skills/triage/SKILL.md`; alternatives: `fix-issue`, `.github/workflows/codeql-*.yml`).
- [ ] 5.2 Edit the skill (or file a separate workflow-improvement issue if the gap is in CI YAML, not a skill).
- [ ] 5.3 Write `knowledge-base/project/learnings/<bug-fixes-or-best-practices>/<topic>.md` recording the symptom, root cause, and chosen prevention. Author picks date at write-time.
- [ ] 5.4 Re-run markdownlint on the learning + skill files.

## 6. Acceptance + Ship

- [ ] 6.1 Run all pre-merge acceptance criteria from plan.
- [ ] 6.2 `/soleur:ship` to push branch, open PR with `Closes #2368`, request labels `type/security`, `domain/engineering`, `app:web-platform`.
- [ ] 6.3 Post-merge: verify `gh issue view 2368 --json state` returns `CLOSED`. Confirm CodeQL workflow ran on the verification PR.
