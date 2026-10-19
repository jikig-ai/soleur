# Tasks — Slice C: broader ${CLAUDE_PLUGIN_ROOT} plugin-script migration (ADR-093, closes #6121)

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-07-07-fix-plugin-root-broader-script-migration-plan.md`

## Phase 0 — Preconditions
- [ ] 0.1 Confirm `EXACT_LITERAL_SAFE_COMMANDS` already carries `worktree-manager.sh list`/`ls` deployed-forms (Slice B): `grep -n WORKTREE_MANAGER_DEPLOYED_FORM apps/web-platform/server/safe-bash.ts`.
- [ ] 0.2 Confirm both factories inject `CLAUDE_PLUGIN_ROOT` from `getPluginPath()` (server-correct invariant): `git grep -n 'pluginPath' apps/web-platform/server/{agent-runner-query-options,cc-dispatcher}.ts`.
- [ ] 0.3 Freeze per-site migrate/exclude list via the BROAD pattern: `git grep -nE 'plugins/soleur/skills/[^ ]+\.sh' -- <14 in-scope files> | grep -vE '\.test\.sh'`. Classify each hit (agent-exec / prose / operator-echo) per the plan §Scope decision rule.

## Phase 1 — Migrate agent-run invocations (per-site fallback discipline)
- [ ] 1.1 `git-worktree/SKILL.md` — 22 worktree-manager.sh sites → `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` (repo-root anchor). `list` sites (72,124,217,299) must land as the exact carve-out literal.
- [ ] 1.2 `ship/SKILL.md` — auto-close-scan.sh (1149,1150,1151) + worktree-manager cleanup-merged (2039); EXCLUDE :605 prose.
- [ ] 1.3 `brainstorm/SKILL.md` — 7 invocations across 6 lines. **:37 is TWO** invocations: `feature` (env-prefixed, no-`bash`, `./`) + `draft-pr` (`bash ../../`) — two different fallbacks on one line. Plus :344 feature (no-`bash`, `./`), :367 draft-pr (`./`), :119 roadmap-reconcile (`./`), :429 check_deps (`./`), :606 archive-kb (`./`).
- [ ] 1.4 `brainstorm/references/brainstorm-brand-workshop.md` (**:5 feature no-`bash` `./`** [re-added], :22 draft-pr `../../`, :64 check_deps echo `./`) + `brainstorm-validation-workshop.md` (**:7 feature no-`bash` `./`** [re-added], :24 draft-pr `../../`).
- [ ] 1.5 `merge-pr/SKILL.md` (:386), `drain-prs/SKILL.md` (:49 triage-prs, :102 cleanup-merged), `fix-issue/SKILL.md` (:133).
- [ ] 1.6 `archive-kb/SKILL.md` (16,20,24), `deploy/SKILL.md` (68), `pencil-setup/SKILL.md` (23,29,101,122, **:193 RESOLVED→migrate**), `feature-video/SKILL.md` (37,43).
- [ ] 1.7 `community/SKILL.md` (28,73 community-router); EXCLUDE :75–78 credential-setup echoes (human is executor).
- [ ] 1.8 `compound/SKILL.md` — token-efficiency-report.sh (:289) git-root fallback `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}`; archive-kb.sh (:455) `./plugins/soleur`.
- [ ] 1.9 `product-roadmap/SKILL.md` (:29,39 roadmap-reconcile.sh, `./`) — **folded in** (same script as migrated brainstorm:119; cross-caller consistency).

## Phase 2 — safe-bash confirmation (expected: no code change)
- [ ] 2.1 Run the Phase-3 coupling test; expect green with the existing 2 carve-out entries.
- [ ] 2.2 ONLY if a migrated `list`/`ls` emission is not a member, add its exact deployed-form literal to `EXACT_LITERAL_SAFE_COMMANDS` (Stage-0 exact-equality, BEFORE `$`-denylist; do NOT weaken `SHELL_METACHAR_DENYLIST`). Route through security-sentinel.

## Phase 3 — AC5↔AC6 coupling test (new code)
- [ ] 3.1 Create `apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts` (vitest node; imports `EXACT_LITERAL_SAFE_COMMANDS` from `../server/safe-bash`).
- [ ] 3.2 Directory-walk `plugins/soleur/skills/**/*.md`; extract every `bash ${CLAUDE_PLUGIN_ROOT:-…}/…/worktree-manager.sh (list|ls)` emission; assert each ∈ the Set.
- [ ] 3.3 Vacuity guard: assert ≥4 `list` emissions scanned.

## Phase 4 — ADR-093 amendment + C4 check
- [ ] 4.1 Amend `ADR-093-*.md` `## Consequences`: broader migration landed, drift-coupling test, residual out-of-scope families + follow-up issue. No new ADR.
- [ ] 4.2 C4: confirm no impact (cite `platform.plugin` + `connectedRepoPlugin` already modeled); no `.c4` edit.

## Phase 5 — Follow-up + verify
- [ ] 5.1 File **P1 `type/security`** follow-up issue with the EXHAUSTIVE residual family list (`legal-generate:60` redaction-gate, `trigger-cron:40,43,47`, `incident`, `skill-security-scan:59,66`, `skill-creator:213`, `kb-search`, `harvest-debt`, `seo-aeo`, `drain-labeled-backlog`, `constraint-scaffold`, `model-launch-review`, `plan:327,840`, `compound-capture:473`); inline agent-vs-operator triage each. Reference in PR body + state surface REMAINS OPEN.
- [ ] 5.2 AC1 completeness = BROAD grep: `git grep -nE 'plugins/soleur/skills/[^ ]+\.sh' -- <in-scope files> | grep -vE 'CLAUDE_PLUGIN_ROOT' | grep -vE '\.test\.sh'` → 0 after removing ship:605, community:75–78.
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; full web-platform vitest (incl. new test + safe-bash.test.ts); `bash scripts/test-all.sh`; `bun test plugins/soleur/test/components.test.ts`.
- [ ] 5.4 Verify no fixture regeneration (`git diff` shows no fixture/snapshot files).
- [ ] 5.5 PR body: `Closes #6121`. Render `decision-challenges.md` (scope User-Challenge) into PR body + file `action-required` issue (ship Phase 6).
