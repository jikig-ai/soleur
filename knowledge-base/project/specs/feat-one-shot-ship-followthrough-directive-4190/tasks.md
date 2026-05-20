---
title: "tasks: rewrite /ship Phase 7 Step 3.5 to emit sweeper-parseable follow-through directive"
issue: 4190
plan: knowledge-base/project/plans/2026-05-20-feat-ship-followthrough-directive-rewrite-plan.md
lane: single-domain
---

# Tasks — feat: ship Phase 7 Step 3.5 sweeper-parseable directive

Derived from `knowledge-base/project/plans/2026-05-20-feat-ship-followthrough-directive-rewrite-plan.md`. Run sequentially; phases gate on the prior phase's exit signal.

## 1. Preconditions and discovery

- [ ] 1.1 Re-verify dependency PR states (informational, not blocking):
  - `gh pr view 4186 --json state,mergeable` (expect OPEN/MERGEABLE — the retrofit-example PR)
  - `gh pr view 4188 --json state` (expect MERGED — the wg-rule, now on main)
- [ ] 1.2 Confirm sweeper parser unchanged on main:
  - `git show main:scripts/sweep-followthroughs.sh | sed -n '36,48p'`
  - Expected: same `parse_directive() { awk '/<!-- *soleur:followthrough/, /-->/ ... }' }` block.
- [ ] 1.3 Empirically probe parser against single-line and multi-line fixtures (per plan Phase 0.2-0.3); record output in commit message or PR body if it diverges from plan claims.
- [ ] 1.4 `sed -n '1238,1316p' plugins/soleur/skills/ship/SKILL.md` — confirm the region under change matches what the plan rewrites.

## 2. Stub-script template

- [ ] 2.1 Create `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` per plan Phase 1.1 (exit 2 / TRANSIENT default; sentinel `# soleur:followthrough-stub v1`).
- [ ] 2.2 `chmod +x plugins/soleur/skills/ship/references/followthrough-stub-template.sh`.
- [ ] 2.3 Sanity-run: `bash plugins/soleur/skills/ship/references/followthrough-stub-template.sh; echo "exit=$?"` — expect `TRANSIENT: stub not customized` on stderr and exit=2.

## 3. RED — write the failing test + fixtures

- [ ] 3.1 Create `plugins/soleur/test/fixtures/followthrough-directive/` directory.
- [ ] 3.2 Write `pr-checklist-input.md` (sample PR body with one `- [ ] ⏳` row).
- [ ] 3.3 Write `expected-issue-body.md` (golden directive-bearing body using known fixture values: `script=scripts/followthroughs/test-fixture-9999.sh`, `earliest=2026-05-22T18:00:00Z`).
- [ ] 3.4 Write `expected-stub-script.sh` (copy of template; sentinel preserved).
- [ ] 3.5 Create `plugins/soleur/test/ship-followthrough-directive.test.sh` per plan Phase 2.2 — must include the awk parser block copied VERBATIM from `scripts/sweep-followthroughs.sh:36-48`.
- [ ] 3.6 `chmod +x plugins/soleur/test/ship-followthrough-directive.test.sh`.
- [ ] 3.7 Run test once expecting RED (SKILL.md not yet rewritten — assertions 3+4 fail): `bash plugins/soleur/test/ship-followthrough-directive.test.sh; echo "exit=$?"` — capture failure output.

## 4. GREEN — rewrite SKILL.md Phase 7 Step 3.5

- [ ] 4.1 Read current SKILL.md region (`sed -n '1238,1316p' plugins/soleur/skills/ship/SKILL.md`) so the surrounding scaffolding (Source PR / Created by / migration anchor / callback URL closure gate) is preserved.
- [ ] 4.2 Replace the `## Verification` block (lines 1261-1312 of current file) with the directive-emitting block from plan Phase 2.3. Preserve:
  - `## Follow-Through Item` header + ITEM_DESCRIPTION placeholder
  - **Source PR:** / **Created by:** / **Created:** lines
  - Migration filename anchor (current SKILL.md:1204)
  - Callback URL closure gate (current SKILL.md:1206-1236)
- [ ] 4.3 Add the new sub-steps 3.5.A (stub generation) through 3.5.F (operator-only ack) per plan Phase 2.3.
- [ ] 4.4 Append "Why this matters" update naming PR #4178 / #4186 per plan Phase 2.4.
- [ ] 4.5 Re-run `bash plugins/soleur/test/ship-followthrough-directive.test.sh` — expect GREEN (`PASS: ship-followthrough-directive contract`).

## 5. Self-dogfood + regression checks

- [ ] 5.1 Manually generate a fixture issue body using the new template values (plan Phase 3.1).
- [ ] 5.2 Pipe through the sweeper's awk parser (plan Phase 3.2) and confirm `script` + `earliest` lines emitted.
- [ ] 5.3 `date -u -d "2026-05-22T18:00:00Z" +%s` — confirm parseable.
- [ ] 5.4 `bun test plugins/soleur/test/components.test.ts` — confirm green (no skill-description budget regression).

## 6. Commit + push + open PR

- [ ] 6.1 Stage all artifacts:
  - `plugins/soleur/skills/ship/SKILL.md`
  - `plugins/soleur/skills/ship/references/followthrough-stub-template.sh`
  - `plugins/soleur/test/ship-followthrough-directive.test.sh`
  - `plugins/soleur/test/fixtures/followthrough-directive/` (all 3 files)
  - `knowledge-base/project/plans/2026-05-20-feat-ship-followthrough-directive-rewrite-plan.md`
  - `knowledge-base/project/specs/feat-one-shot-ship-followthrough-directive-4190/tasks.md`
- [ ] 6.2 Commit: `feat(ship): emit sweeper-parseable follow-through directive (closes #4190)`.
- [ ] 6.3 Push to `feat-one-shot-ship-followthrough-directive-4190`.
- [ ] 6.4 Open PR: title `feat(ship): rewrite Phase 7 Step 3.5 follow-through emitter to sweeper directive`; body MUST include `Closes #4190`, semver:minor label, and Brand-survival threshold `aggregate pattern`.

## 7. Follow-up (post-merge, NOT in this PR)

- [ ] 7.1 File scope-out tracking issue: `chore(soleur:go): port clo_routable: true YAML routing to <!-- soleur:followthrough --> body sentinel` — documents the operator-comment sentinel pattern as the new-convention equivalent of the legacy `clo_routable` field.

## References

- Plan: `knowledge-base/project/plans/2026-05-20-feat-ship-followthrough-directive-rewrite-plan.md`
- Issue: #4190
- Runbook: `knowledge-base/engineering/ops/runbooks/followthrough-convention.md`
- Sweeper script: `scripts/sweep-followthroughs.sh` (parser lines 36-48)
- Canonical reference script: `scripts/followthroughs/sentry-checkins-3859.sh`
