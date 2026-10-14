# Tasks — feat-one-shot-fix-compound-issues

Derived from `knowledge-base/project/plans/2026-04-18-chore-bundle-fix-compound-route-to-definition-proposals-plan.md`.

## 1. Setup

- [ ] 1.1 Re-read each of the 12 issues to confirm proposed bullet text is current (drift check).
- [ ] 1.2 Run open code-review overlap query from plan (confirm None).
- [ ] 1.3 Measure AGENTS.md size (expect 30617 bytes baseline) and confirm no rule-ID collisions for `cq-mutation-assertions-pin-exact-post-state` and `cq-destructive-prod-tests-allowlist`.
- [ ] 1.4 Verify section anchors in target skill files (re-anchor if drift).

## 2. Core Implementation

- [ ] 2.1 AGENTS.md — add two Code Quality rules (#2365 mutation assertion, #2366 destructive-test allowlist).
- [ ] 2.2 plugins/soleur/skills/work/SKILL.md — add 3 bullets to Phase 3 (#2116 credential helper, #2228 tsc, #2248 negative-space), 1 bullet to Phase 2 (#2228 reducer extraction).
- [ ] 2.3 plugins/soleur/skills/plan/SKILL.md — append 5 Sharp Edges bullets (#2237 items 1+2, #2266, #2363, #2364).
- [ ] 2.4 plugins/soleur/skills/review/SKILL.md — append 1 Common Pitfalls bullet (#2237 item 3).
- [ ] 2.5 plugins/soleur/skills/review/references/review-todo-structure.md — append Sharp Edges subsection for `gh --milestone` title-not-number (#2273).
- [ ] 2.6 plugins/soleur/agents/engineering/review/data-integrity-guardian.md — add new `## Sharp Edges` section with 2 bullets (#2471).
- [ ] 2.7 Close #2522 with reconciliation comment — no repo-local code change (hook is upstream in `claude-plugins-official` marketplace).

## 3. Testing / Quality Check

- [ ] 3.1 Run `npx markdownlint-cli2 --fix` on edited markdown files (not repo-wide).
- [ ] 3.2 Run `bash .claude/hooks/security_reminder_hook.test.sh` — confirm pass.
- [ ] 3.3 Run `python3 .claude/hooks/lint-rule-ids.py AGENTS.md` — confirm new IDs parse.
- [ ] 3.4 Measure AGENTS.md post-edit: `wc -c AGENTS.md` < 40000.
- [ ] 3.5 Verify every new rule is under 600 bytes via awk gate from plan Phase 3.

## 4. Ship

- [ ] 4.1 Invoke `/ship` (compound + review gates) with `semver:patch` label.
- [ ] 4.2 PR body uses `Closes #N` for all 12 issues.
- [ ] 4.3 Immediately after PR opens, post reconciliation comment on #2522.
- [ ] 4.4 Poll auto-merge; on merge, verify all 12 issues auto-closed in GitHub UI.
