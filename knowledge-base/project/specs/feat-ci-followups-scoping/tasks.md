---
title: "Bun version probe — tasks (#3692)"
date: 2026-05-12
spec: knowledge-base/project/specs/feat-ci-followups-scoping/spec.md
plan: knowledge-base/project/plans/2026-05-12-chore-ci-bun-probe-plan.md
issue: 3692
pr: 3709
branch: feat-ci-followups-scoping
worktree: .worktrees/feat-ci-followups-scoping
lane: single-domain
brand_survival_threshold: none
---

# Tasks: Bun version probe (#3692)

## Phase 1 — Pre-bump verification

- [ ] 1.1 Read `.bun-version`; confirm contents = `1.3.11`.
- [ ] 1.2 Re-confirm latest 1.3.x: `npm view bun versions --json | jq -r '.[]' | grep -E '^1\.3\.[0-9]+$' | tail -1`. If output > `1.3.13`, update plan target before Phase 2.
- [ ] 1.3 `git status --short` — confirm only docs changes pending.

## Phase 2 — Bump and push

- [ ] 2.1 `echo "1.3.13" > .bun-version`.
- [ ] 2.2 Commit: `chore(ci): probe bun 1.3.13 for FPE-class re-evaluation` with `Closes #3692` in body.
- [ ] 2.3 `git push`; capture run-id of the triggered CI run.

## Phase 3 — Observe and classify

- [ ] 3.1 Watch the CI run (first attempt is authoritative).
- [ ] 3.2 Apply classification rules from plan Phase 3:
  - FPE-class detected via `grep -nE 'SIGFPE|panic:|Floating point (error|exception)|oh no:'` on `test-bun` job log → Phase 4b.
  - All 5 `test-bun` invocations + all other shards green → Phase 4a.
  - Otherwise → Phase 4c (inconclusive).

## Phase 4a — Green outcome

- [ ] 4a.1 Append `## 2026-05-12 probe: 1.3.13 clean` section to `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` using the plan's template.
- [ ] 4a.2 `git commit --amend --no-edit`.
- [ ] 4a.3 `git push --force-with-lease`.
- [ ] 4a.4 Mark PR #3709 ready.

## Phase 4b — FPE outcome

- [ ] 4b.1 `echo "1.3.11" > .bun-version`.
- [ ] 4b.2 Append `## 2026-05-12 probe: 1.3.13 FPE class still live` section to the FPE learning file with full grep match + job URL + runner OS.
- [ ] 4b.3 `git commit --amend --no-edit`.
- [ ] 4b.4 `git push --force-with-lease`. If lease rejects, apply fallback from plan Phase 4b (two-commit shape).
- [ ] 4b.5 File next-probe issue via the `gh issue create` invocation in plan Phase 4b.
- [ ] 4b.6 Mark PR #3709 ready.

## Phase 4c — Inconclusive outcome

- [ ] 4c.1 Append `## 2026-05-12 probe: 1.3.13 inconclusive` section to the learning file with failing shard + read.
- [ ] 4c.2 Leave PR #3709 in draft. Do NOT auto-revert.
- [ ] 4c.3 Comment on PR #3709 with failing-shard summary.
- [ ] 4c.4 Pause work until unrelated red is understood; re-run Phase 3 after fix.

## Phase 5 — Close (post-merge)

- [ ] 5.1 `gh issue close 3692 --comment "Probed in PR #3709. Outcome: <green | FPE | inconclusive>."`.
- [ ] 5.2 On FPE outcome only: verify next-probe issue (4b.5) is open with re-evaluation criteria.

## Out of scope (verified at plan time)

- `skill-security-scan-corpus.yml` and `skill-security-scan-pr-trailer.yml` use `bun-version: latest` — separate concern, file a follow-up only if probe surfaces FPE.
- #3693 (webplat split) and #3694 (e2e shard) tracked separately; not gated by this probe.
