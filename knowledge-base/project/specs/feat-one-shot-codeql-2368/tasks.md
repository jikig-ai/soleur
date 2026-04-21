# Tasks — feat-one-shot-codeql-2368

Derived from `knowledge-base/project/plans/2026-04-19-fix-verify-and-close-codeql-issue-2368-plan.md`.

## 1. Setup

- [x] 1.1 Confirm worktree CWD `.worktrees/feat-one-shot-codeql-2368/` and branch `feat-one-shot-codeql-2368`.
- [x] 1.2 `mkdir -p knowledge-base/project/specs/feat-one-shot-codeql-2368`.

## 2. Phase 1 — Verification Sweep

- [x] 2.1 Snapshot all CodeQL alerts: `gh api '/repos/jikig-ai/soleur/code-scanning/alerts?per_page=100' --paginate > knowledge-base/project/specs/feat-one-shot-codeql-2368/alerts-snapshot.json`.
- [x] 2.2 Filter to `apps/web-platform/*` and write `web-platform-alerts.json` (jq pipeline from plan Phase 1.2).
- [x] 2.3 Run hard assertion: zero `state=open` high/critical alerts in `apps/web-platform/*`. If non-zero, ABORT and convert to remediation.
- [x] 2.4 Cross-check the 9 issue-named alerts against the inventory table in the plan. Any miss → stop.

## 3. Phase 2 — Code-Drift Spot Check

- [x] 3.1 `git log --since=2026-04-16` for each of the 9 named source files; record commit list.
- [x] 3.2 For each commit returned, eyeball-diff against the specific defense named in the corresponding `dismissed_comment`.
- [x] 3.3 Record outcome in scratch notes for Phase 3.

## 4. Phase 3 — Verification Evidence + Close-Out

- [x] 4.1 Write `knowledge-base/project/specs/feat-one-shot-codeql-2368/verification.md` with the alert-state table, drift summary, and PR/brainstorm links.
- [x] 4.2 `npx markdownlint-cli2 --fix` on changed `.md` files (specific paths, per AGENTS.md `cq-markdownlint-fix-target-specific-paths`).
- [x] 4.3 Stage + commit: plan, tasks, snapshot JSONs, verification.md, learning. Use `/soleur:ship` for PR creation with `Closes #2368`.

## 5. Phase 4 — Workflow + Skill Edits + Learning

- [x] 5.1 **Primary fix:** edit `.github/workflows/codeql-to-issues.yml`, add the `close-orphans` job per the plan sketch (`needs: check-alerts`). Lint with `actionlint .github/workflows/codeql-to-issues.yml` before commit.
- [x] 5.2 **Secondary fix:** read `plugins/soleur/skills/triage/SKILL.md` end-to-end first (per `hr-always-read-a-file-before-editing-it`), then add a CodeQL alert-state precheck bullet near the existing security-triage prose.
- [x] 5.3 Write `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md` with frontmatter `category: best-practices`, `tags: [codeql, github-actions, triage, automation]`, the timeline, the workflow sketch, and the rationale for `best-practices/` over `bug-fixes/`.
- [x] 5.4 Run `npx markdownlint-cli2 --fix` on the specific changed `.md` files only (per `cq-markdownlint-fix-target-specific-paths`).

## 6. Acceptance + Ship

- [x] 6.1 Run all pre-merge acceptance criteria from plan.
- [ ] 6.2 `/soleur:ship` to push branch, open PR with `Closes #2368` in body, request labels `type/security`, `domain/engineering`, `app:web-platform` (verify each label with `gh label list --limit 100 | grep -i <keyword>` first).
- [ ] 6.3 Post-merge: verify `gh issue view 2368 --json state` returns `CLOSED`.
- [ ] 6.4 Post-merge: trigger `gh workflow run codeql-to-issues.yml`, poll via `gh run list --workflow=codeql-to-issues.yml --limit 1 --json status,conclusion` (use Monitor tool or `run_in_background` per `hr-never-use-sleep-2-seconds-in-foreground`). Investigate any failure before ending session per `wg-after-merging-a-pr-that-adds-or-modifies`.
