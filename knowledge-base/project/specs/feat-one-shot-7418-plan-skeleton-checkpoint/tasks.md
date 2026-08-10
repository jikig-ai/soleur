# Tasks — plan skeleton checkpoint before the research fan-out (#7418)

Plan: `knowledge-base/project/plans/2026-08-10-chore-plan-skeleton-checkpoint-before-research-fanout-plan.md` (v2)
Branch: `feat-one-shot-7418-plan-skeleton-checkpoint`
Lane: `cross-domain` (no `spec.md` for this branch — TR2 fail-closed)
ADR: **ADR-174** (provisional; re-verify at ship — ADR-173 is triple-claimed on pushed branches)

> Read the plan's §Review Revisions before starting. v2 resolves 8 P0s from a 6-agent panel; the
> carrier key, the parsing rule, the resume bound and the gate re-run all changed from v1.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm CWD is the worktree (`git rev-parse --show-toplevel`), not the bare root.
- [ ] 0.2 Re-verify the ADR ordinal against freshly-fetched `origin/main` (`git fetch origin main`).
      If it moved, sweep this file **and** the plan for the old ordinal in the same edit.
- [ ] 0.3 Confirm the description budget baseline is unchanged: `bun test plugins/soleur/test/components.test.ts`
      (2400/2400, zero headroom — no `description:` may grow in this PR).
- [ ] 0.4 Re-read `plan/SKILL.md` §Managing Plan Documents (`:882-883`) and §Save Tasks (`:759-767`)
      — both are edited in Phase 2 and both currently contradict the resume design.

## Phase 1 — Contract test (RED)

- [ ] 1.1 Create `plugins/soleur/test/plan-skeleton-checkpoint.test.ts`.
- [ ] 1.2 Create the fixture whose **body** contains `pipeline_resume: research` at column 0 while its
      frontmatter does not. This is the regression fixture for the bug v1 shipped.
- [ ] 1.3 Assertion A — Phase 0.7 in `plan/SKILL.md` sits after `^### 0\.6\.` and before
      `### 1. Local Research`.
- [ ] 1.4 Assertion B — `pipeline_resume:` appears in `plan/SKILL.md`, `one-shot/SKILL.md`,
      `deepen-plan/SKILL.md`; the tokens `research|drafting|gates|finalize` appear in `plan/SKILL.md`
      only (`one-shot` may name `deepening` and nothing else).
- [ ] 1.5 Assertion C — the prescribed frontmatter-bounded extraction returns empty against the
      fixture.
- [ ] 1.6 Confirm RED on all three (they must fail before Phase 2).
- [ ] 1.7 Confirm the new test is auto-discovered: `bun test plugins/soleur/` (directory glob at
      `scripts/test-all.sh:732`). Do **not** invoke via `vitest`.

## Phase 2 — `plugins/soleur/skills/plan/SKILL.md` (GREEN)

- [ ] 2.1 Insert `### 0.7. Skeleton Checkpoint (Always)` between Phase 0.6 and `### 1. Local Research`.
- [ ] 2.2 In 0.7: resolve the plans dir from `git rev-parse --show-toplevel`; derive `PLAN_PATH` from
      the premise gate's issue title, with a freeform fallback when no `#N` is cited.
- [ ] 2.3 In 0.7: prescribe the skeleton frontmatter — `title`, `date`, `slug`, `branch`, `issue`
      (provisional), `pipeline_resume: research`, `resume_attempts: 0` — plus `## Overview`. State
      explicitly that `lane`, `type`, `closes`, `priority`, `domain`, thresholds and `status:` are
      **excluded**, and why pre-seeding `lane:` would widen the domain fan-out.
- [ ] 2.4 In 0.7: prescribe a sanitized Overview restatement (never a verbatim issue-body paste), and
      the write-denial arm — retry minimal once, then proceed skeleton-less and log.
- [ ] 2.5 In 0.7: the idempotency table (D8), including "never overwrite a cursor-free plan" and the
      bounded-deletion rule (anchor heading → next `^## `, cursor present only, never frontmatter).
- [ ] 2.6 Move the "Convert title to filename" bullet out of Step 2 (`:279`) into 0.7. It **moves** —
      it does not become a conditional no-op.
- [ ] 2.7 Add the Phase-0 resume-detection block (above Phase 0.5) that skips 0.5 idea refinement,
      **re-runs 0.6**, and re-runs gates 2.7–2.11 + Phase 3 unconditionally, citing ADR-032:425-427.
- [ ] 2.8 Add the explicit mode flag on resume so an attached session is not flipped headless by the
      plan-file-path predicate (`:349`).
- [ ] 2.9 **Phase 1.7: add the `## Research Insights` section write** (file paths, learnings, external
      findings, Premise Validation note). This is the change that makes the checkpoint pay.
- [ ] 2.10 Add cursor advances at the four sites: → `drafting` (after 1.7), → `gates` (after 1.7.5 +
      Files-to-Edit), → `finalize` (after 2.5 + 2.6), → `deepening` (at finalization). Section write
      first, cursor second, single Edit where possible.
- [ ] 2.11 Add `resume_attempts` increment, cap 2, strict-advance rule, and the cursor-deleting
      terminal arm.
- [ ] 2.12 Finalization: delete `pipeline_resume` on the direct path; rewrite `issue:`/`closes:`
      unconditionally; add the post-research frontmatter fields.
- [ ] 2.13 Reconcile §Managing Plan Documents (`:882-883`) with the resume rule.
- [ ] 2.14 Narrow `git add knowledge-base/project/plans/` (`:764`) to the exact plan path.
- [ ] 2.15 Prescribe frontmatter-bounded parsing everywhere the cursor or `branch:` is read; do not
      use the line-anchored gsub awk form (`:1013`) for these keys.

## Phase 3 — `plugins/soleur/skills/one-shot/SKILL.md` (GREEN)

- [ ] 3.1 Rewrite the recovery branch (`:195-201`) with D4's **total** table: absent+passes,
      absent+fails, `deepening`+fails, `deepening`+passes, known-token (both), unrecognized.
      **Retain** the existing positive section assertion as a conjunct.
- [ ] 3.2 Apply the **same conjunct** on the success path after `### Plan File` extraction (`:172`).
- [ ] 3.3 Ensure every arm terminates in an explicit "continue to step 3" — no arm ends at a skill
      invocation (the ADR-083 CONTINUATION-GATE guard).
- [ ] 3.4 Replace the date-glob selector (`:196`) with a frontmatter `branch:` selector: bounded and
      non-recursive over `plans/*.md`, `plans/archive/` excluded, explicit tiebreak (highest date
      prefix, then newest mtime), date glob as fallback.
- [ ] 3.5 Disambiguate the unrelated session-state `- Status: complete` literal (`:181`) and make it
      consistent with the D4 verdict.
- [ ] 3.6 Do **not** introduce "checkpoint"-as-durable-state prose into this file — `:210` already
      uses the word to mean the opposite.
- [ ] 3.7 Confirm `one-shot` never names the tokens `research|drafting|gates|finalize`.
- [ ] 3.8 Add the `Recovery verdict:` line to the `## Plan Phase` block of session-state.md —
      `<resume|complete|undetermined|legacy> (cursor=<x>, attempts=<n>, selector=<branch|date-glob>)`.
      This is the plan's `## Observability` `liveness_signal`; without it a mis-resume is invisible
      and the only operator symptom is a double-billed run.

## Phase 4 — `deepen-plan`, templates reference, ADR

- [ ] 4.1 `deepen-plan/SKILL.md`: set the cursor to `deepening` on entry (§1), delete it on exit.
- [ ] 4.2 `deepen-plan/SKILL.md`: every HALT gate (§4.6–4.10) **deletes** the cursor and records the
      halt reason — a designed refusal must never be replayed as a crash.
- [ ] 4.3 Add a scope note for `workflows/deepen-plan.workflow.js:54-56` (the `-deepened` output path
      would otherwise leave the cursor on the file `one-shot` holds).
- [ ] 4.4 `plan/references/plan-issue-templates.md`: document the skeleton frontmatter keys in all
      three templates (`:18-22`, `:148-152`, `:302-306`).
- [ ] 4.5 Author `ADR-174-*.md`, `status: accepted`, with an `amends: [ADR-015]` edge (not a rewrite —
      ADR-112:122-126 rejected that shape) and citations to ADR-032/121/126/089/026/151/083/132.
      Record that CONTINUATION-GATE is un-ADR'd prose.

## Phase 5 — Verify

- [ ] 5.1 `bun test plugins/soleur/test/plan-skeleton-checkpoint.test.ts` — GREEN.
- [ ] 5.2 `bun test plugins/soleur/test/components.test.ts` — budget still 2400/2400.
- [ ] 5.3 `bun test plugins/soleur/test/workflow-fidelity.test.ts` — sentinels intact.
- [ ] 5.4 Sibling suites over `plan/SKILL.md`: `observability-schema-parity`,
      `wireframe-feedback-pause`, `mandatory-wireframes-hardening`,
      `ship-soak-followthrough-enrollment-gate`, `scratch-path-collision`, and
      `bash plugins/soleur/test/lane-frontmatter.test.sh`.
- [ ] 5.5 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 5.6 `bash scripts/test-all.sh` — full suite.
- [ ] 5.7 Walk T1–T15 from the plan as a manual read-through against the edited prose.

## Phase 6 — Follow-ups (file as issues during `/work`)

- [ ] 6.1 Stale skill-description budget figure: `1800` appears in 5 places across 4 files
      (`plan/SKILL.md` ×3 incl. `:969`, `brainstorm/SKILL.md`, `skill-creator/SKILL.md`,
      `review/SKILL.md`). Fix by citing `SKILL_DESCRIPTION_WORD_BUDGET` by name, not another literal.
- [ ] 6.2 Checkpoint-commit the skeleton for durability against worktree recreation and
      `worktree-manager.sh:1751`'s plain `mv`.
- [ ] 6.3 `archive-kb` guard refusing to archive a cursor-bearing plan (largely dissolved by
      deletion-at-finalization; file only if 6.2 lands).
- [ ] 6.4 Triage #4133 — its criteria appear already satisfied by
      `plugins/soleur/test/observability-schema-parity.test.ts`.
- [ ] 6.5 **Observability gate-definition mismatch** (found during this deepen pass). `plan/SKILL.md`
      §2.9 triggers only on code-class paths under `apps/*/server|src|infra` or `plugins/*/scripts/`,
      so a `plugins/*/skills/**/SKILL.md`-only plan reads as "no Observability section needed".
      `deepen-plan/SKILL.md` §4.7 Step 1 skips only when *every* path matches its pure-docs list,
      which explicitly excludes `.md` inside `plugins/*/skills/` — so the same plan reads as
      "section required" and HALTs. The two gates disagree on exactly the prompt-only change class.
      This plan resolves it by supplying the section (correct under layer 7), but the definitions
      should be reconciled so the answer does not depend on which gate runs.
