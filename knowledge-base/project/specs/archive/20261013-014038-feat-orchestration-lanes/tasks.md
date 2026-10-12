---
feature: feat-orchestration-lanes
issue: 2721
plan: knowledge-base/project/plans/2026-05-12-feat-orchestration-lanes-plan.md
spec: knowledge-base/project/specs/feat-orchestration-lanes/spec.md
brand_survival_threshold: none
lane: cross-domain
---

# Tasks — feat-orchestration-lanes

5 phases, TDD-structured. Contract (Phase 2) before consumers (Phase 3+). Each phase = one commit checkpoint.

## Phase 1 — Test Scaffold (RED for everything)

- [ ] **1.1 RED** — Create `plugins/soleur/test/lane-frontmatter.test.sh` with 7 assertions (all failing) per plan §Phase 1. Include `# Marker-existence gate; does NOT prove semantic correctness — see plan §Risks R3.` header comment.
- [ ] **1.2 Verify RED** — Run `bash plugins/soleur/test/lane-frontmatter.test.sh`; expect non-zero exit, every assertion failing.
- [ ] **1.3 Commit** — `test: scaffold lane-frontmatter content gate (RED)`.

## Phase 2 — Lane Vocabulary in domain-config (contract)

- [ ] **2.1 GREEN** — Append `## Lane Inference` to `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` per plan §Phase 2. Include: 3-row lane table, fail-closed default rule, USER_BRAND_CRITICAL × lane composition order, carry-forward contract (spec.md canonical), stability note.
- [ ] **2.2 Verify** — Run test scaffold; assertion #1 should now pass.
- [ ] **2.3 Commit** — `feat(brainstorm): canonical lane vocabulary in domain-config (GREEN: #1)`.

## Phase 3 — brainstorm SKILL.md (Phase 0.4 + Phase 0.5 step 0 + Phase 3.6 prescription)

Single file, single commit (3 edits same file).

- [ ] **3.1 GREEN Edit A** — Insert Phase 0.4 between Phase 0.1 (`**Why:**` paragraph close) and Phase 0.25 (heading) per plan §Phase 3 Edit A. Include pipeline-mode fallback, interactive AskUserQuestion (3 presets + auto-Other), fail-closed "Other" with **operator terminal echo**, override telemetry with **terminal echo**.
- [ ] **3.2 GREEN Edit B** — Prepend Phase 0.5 Processing Instructions step 0 (renumber existing 6 steps to 1–6) per plan §Phase 3 Edit B. Include procedural-skip terminal echo, single-domain config-order tie-break, cross-domain expansion terminal echo.
- [ ] **3.3 GREEN Edit C** — Modify Phase 3.6 step 4 to prescribe `lane:` + `brand_survival_threshold:` in spec.md frontmatter (not brainstorm-doc — spec.md is canonical).
- [ ] **3.4 Verify** — Run test scaffold; assertions #2, #3, #4 should now pass.
- [ ] **3.5 Commit** — `feat(brainstorm): Phase 0.4 + Phase 0.5 step 0 + Phase 3.6 lane prescription (GREEN: #2-#4)`.

## Phase 4 — Downstream Consumers (plan + work SKILL.md)

Two files, single commit (same logical change).

- [ ] **4.1 GREEN Edit A** — Modify `plugins/soleur/skills/plan/SKILL.md` `## Save Tasks to Knowledge Base` section per plan §Phase 4 Edit A. Use the canonical gsub awk pattern from `skill-security-scan/scripts/run-scan.sh:34`. Enum-validate; fail-closed to `cross-domain` + operator terminal echo + plan body note on missing/invalid.
- [ ] **4.2 GREEN Edit B** — Modify `plugins/soleur/skills/work/SKILL.md` Phase 0 per plan §Phase 4 Edit B. Insert step 4.5 with file-existence guard, gsub awk extraction, enum-validate case. Modify step 5 announce to conditionally append ` (lane=<value>)`.
- [ ] **4.3 Verify** — Run test scaffold; assertions #5, #6 should now pass.
- [ ] **4.4 Commit** — `feat(plan,work): propagate lane: from spec.md frontmatter (GREEN: #5, #6)`.

## Phase 5 — Parent Audit Spec Amendment + Exit Gate

- [ ] **5.1 GREEN Edit A** — Amend `knowledge-base/project/specs/feat-claude-skills-audit/spec.md` FR4 per plan §Phase 5 Edit A: replace four-lane block with one-sentence three-lane single-axis statement + link back to feat-orchestration-lanes spec/brainstorm.
- [ ] **5.2 GREEN Edit B** — Append one sentence to TR7 per plan §Phase 5 Edit B: specify fail-closed default = `cross-domain`.
- [ ] **5.3 Verify** — Run test scaffold; assertion #7 should now pass. Run full scaffold: `bash plugins/soleur/test/lane-frontmatter.test.sh` exits 0 with all 7 GREEN.
- [ ] **5.4 Exit gate** — `./node_modules/.bin/bun test plugins/soleur/test/components.test.ts` passes (re-measure baseline; was 1029/0 at plan-write time).
- [ ] **5.5 Exit gate** — `bash scripts/test-all.sh` passes (orphan-suite discovery).
- [ ] **5.6 Exit gate** — `./node_modules/.bin/bun test` full suite passes (no regression).
- [ ] **5.7 Commit** — `feat(spec): amend feat-claude-skills-audit FR4/TR7 to single-axis (GREEN: #7)`.

## Phase 6 — Pre-PR Final Steps

- [ ] **6.1** — File ONE umbrella issue for the 2 deferrals (`--lane=X` shortcut, `work` Tier hint) per plan §Non-Goals. Label `deferred-scope-out`; milestone `Post-MVP / Later`. Body lists both items with re-evaluation triggers.
- [ ] **6.2** — Update PR body: include `Closes #2721` (NOT `Ref #2721` — no post-merge operator action gates closure).
- [ ] **6.3** — Verify PR body contains `## Changelog` section per `plugins/soleur/AGENTS.md` pre-commit checklist (semver:minor label applied at /ship time).
- [ ] **6.4** — Mark PR #3625 ready for review.
