---
module: System
date: 2026-05-22
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Plan referenced flag/file names that had been retired or renamed since plan-time"
  - "Operator's stated requirement (per-role progressive rollout) didn't match plan's assumption (global booleans)"
  - "First implementation pass built the wrong system; required full pivot to a v2 plan and ~3h of rework"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags:
  - planning
  - plan-drift
  - resume-from-memory
  - requirements-elicitation
  - flagsmith
related:
  - knowledge-base/project/learnings/workflow-issues/2026-03-20-verify-both-source-and-dest-before-migration-planning.md
---

# Learning: Resume a stale plan only after re-verifying it against current code AND re-eliciting the operator's mental model

## Problem

Session started with a memory entry pointing to `feat-flagsmith-adoption` worktree where a plan committed 1 day earlier (`2026-05-21-feat-flagsmith-adoption-plan.md`) was awaiting approval. I treated the plan as authoritative and started executing Stage 1.

Two distinct drifts surfaced mid-implementation:

**Drift 1 — code reality vs. plan claims (~30min in):** The plan named the runtime flags as `kb-chat-sidebar` + `command-center-soleur-go`. A grep of the actual codebase showed flags were `kb-chat-sidebar` + `dev-signin`. `FLAG_CC_SOLEUR_GO` had been retired in PR #3270 (`cc-soleur-go runs unconditionally`). The plan also claimed `ws-handler.ts:604` was a `getFlag()` call site — it was a `tenantFor()` call. Total call-site drift: plan said 2, reality was 4 (including `dev-signin` consumers the plan didn't know about).

**Drift 2 — operator's mental model vs. plan's design (~3h in):** I shipped v1 of the implementation (provider + hook + sync env-flag carve-out + global-boolean Flagsmith resolution), ran tests green, and was about to ship. User then asked "before shipping, explain how it works." When I described the global-boolean SaaS model with a Flagsmith dashboard as the operator interface, the user clarified: actual requirement is **per-role progressive rollout** (`prd` for everyone, `dev` for beta testers), with Claude as the only operator (no human dashboard). The plan had been written from a misread of the original brainstorm; my implementation faithfully executed the wrong plan.

Recovery cost: full re-pitch (`2026-05-22-feat-flagsmith-adoption-plan-v2.md`), v1 plan marked SUPERSEDED, ~600 lines of identity-aware code, Supabase migration for `users.role`, two-PR split to defer skills, complete ADR rewrite, and a multi-agent code review that caught a P1 silent-fallback violation introduced during the rework.

## Failed attempts (what didn't help)

- **Resuming from the memory pointer alone.** The session-start memory entry was accurate and well-formed — it pointed to the plan, the worktree, and the pre-setup state. It did NOT capture: (a) whether the plan's premises still held against current code, (b) what the operator's mental model actually was. Memory is a position bookmark, not a contract.
- **Treating the plan's "draft" status as the only gate.** The plan had explicit "awaiting user approval" status. I asked the user 4 open questions before code; they answered all 4. That gate validated the questions the plan had thought to ask — not the questions the plan should have asked.
- **Trusting the call-site count from the plan body.** Plan said "2 call sites for getFlag" with file:line. Both lines were stale references. The plan had been written from training-data familiarity with similar codebases plus a quick grep at plan-time that had since drifted.

## Root cause

Two-part workflow gap:

1. **No "freshness re-verification" gate when resuming a plan.** When a plan is more than ~1 day old (or sits across a "real" session boundary), the assumptions baked into it can drift. The `/soleur:go` skill detects the worktree exists and offers to continue, but doesn't re-run the plan-time grep to verify the plan's call-site claims still hold.

2. **No requirements re-elicitation gate.** The plan's design decisions are derived from interpreted requirements. When the plan was written 1 day before by a session that's now compacted, the operator's mental model isn't queryable — only the plan's interpretation of it is. Without a "walk me through what happens when a feature ships" elicitation at resume-time, the plan's interpretation can be silently wrong and the implementation can faithfully execute the wrong design.

The deeper issue: memory pointers capture *artifacts* (file paths, commit SHAs) but not *premises* (the grep that the plan was written against, the mental model that produced the plan's design). Pointers point at the bookshelf, not the reasoning that put the books there.

## Solution (workflow change, not code)

**Before resuming any plan older than 24 hours OR across session boundaries:**

1. **Re-grep the plan's load-bearing references.** For every file:line, flag name, function name, or API path the plan cites, verify it still exists and behaves as the plan describes. If `git log -p --since="<plan-date>"` shows churn in cited files, treat the plan as stale until those sections are revised.

2. **Re-elicit the operator's mental model with a concrete scenario question.** Don't ask "is this plan OK?" — ask "walk me through what happens when [the most common use case] runs." If the operator's narration doesn't match the plan's design, stop and re-plan before coding.

3. **Plan-vs-reality drift = stop and surface, not push through.** When drift is found mid-implementation, the cheap action feels like "small edits to the plan" but the load-bearing action is "stop, surface to operator, and decide whether to re-plan." In this session, drift 1 was small enough to absorb (4 call sites instead of 2 — same shape); drift 2 was design-invalidating and required a v2 plan.

4. **Memory entries for in-flight work should carry premises, not just pointers.** When ending a session that leaves a plan awaiting approval, the memory entry should include the one-sentence premise: "Plan assumes [X]; operator confirmed [Y]; if either changes, re-plan." This session's memory entry had pointers but no premises.

## Session Errors

1. **v1 plan was stale on flag names.** Plan referenced `command-center-soleur-go` (retired in PR #3270). Actual flags: `kb-chat-sidebar` + `dev-signin`. **Recovery:** stopped Stage 1 before code mutations, surfaced the drift, asked user to confirm. **Prevention:** before resuming a multi-day-old plan, re-grep call sites against current code (`/soleur:go` should add a "re-verify plan freshness" step when the loaded worktree's plan file is more than 24h old).

2. **Built the wrong system on first pass (~3h wasted on global-boolean design).** v1 implementation modelled flags as global booleans; actual requirement was per-role targeting. **Recovery:** explicit "explain how it works" elicitation from user surfaced the mismatch BEFORE merge — could have been after. **Prevention:** when resuming a plan, ask "walk me through the most common use case" as a requirements-validation step before touching code.

3. **`psql` not on host PATH blocked migration rehearsal.** `doppler run -- bash scripts/run-migrations.sh` aborted with "psql not found". **Recovery:** built a dockerised `psql` shim wrapping `postgres:16` image (`docker run --rm -i postgres:16 psql`). **Prevention:** `apps/web-platform/scripts/run-migrations.sh` could detect missing psql and fall back to docker automatically (or print the one-line shim command).

4. **`mockQueryChain<T>` typecheck failed on null data.** Test passed `mockQueryChain<{role: unknown}>(null)`; T didn't admit null. **Recovery:** widened generic to `mockQueryChain<{role: unknown} | null>(...)`. **Prevention:** `test/helpers/mock-supabase.ts` could accept `T | null` as the documented contract, or its docstring could call out the `| null` widening pattern for nullable-data tests.

5. **Consumer migration broke 5 KbLayout test files.** Replacing client-side `/api/flags` fetch with `useFeatureFlag()` made tests throw because they rendered without `FeatureFlagProvider`. **Recovery:** added `vi.mock("@/components/feature-flags/provider")` to each affected test file. **Prevention:** when introducing a new required Context to a component tree, grep for all renders of any descendant in tests and wrap them (or mock the hook) in the same commit. Tests can't be left out of the same atomic change.

6. **Modified migration SQL file after dev rehearsal.** Added documentation comments to `054_users_role_column.sql` after dev had already applied it. Comment-only, semantically inert, but a smell. **Recovery:** none needed — content was comments only and the runner tracks by filename. **Prevention:** treat applied migration files as frozen. Any clarifying comment goes either in the verify file (always re-readable) or in the ADR, not in the .sql.

7. **`.env.example` edit left dangling prose fragments.** First trim chained Edits that left orphan lines from the prior prose. **Recovery:** re-read + Write the full new section. **Prevention:** when doing a large prose rewrite (>5 line shrink), prefer `Write` with the full replacement section over chained `Edit` calls.

## Prevention

- **`/soleur:go` should detect stale plans at resume.** When the worktree's plan file is more than 24h old or has commits between plan-date and now that touched any file the plan cites, surface a "plan may be stale — verify against current code?" prompt before routing to `work`/`one-shot`.

- **`/soleur:work` (or `/soleur:plan` revisit) should elicit operator mental model at resume.** Single concrete-scenario question: "Walk me through what happens when [most common use case]." The answer either confirms the plan's design or surfaces a mismatch before code commits.

- **Memory schema for in-flight work should carry a `premises:` section.** Pointers (worktree, plan path, branch) are necessary but insufficient. Add a one-sentence premise capture: "Plan assumes X. Operator confirmed Y. Re-validate before continuing if Z changes."

- **For multi-PR splits, document the contract that holds the pieces together as code, not prose.** This PR split the resolution path from the operator skills with a "skill enforces env-var mirror" invariant. Between PR #1 and PR #2, the contract is on paper. Future similar splits should ship an assertion (dev-only Sentry warning on divergence) rather than relying on a future skill that doesn't exist yet.

- **Cross-reference:** [[2026-03-20-verify-both-source-and-dest-before-migration-planning]] established the pattern "verify both sides before planning" for directory migrations. This learning extends it: "verify both the plan's premises AND the operator's mental model before resuming a paused plan."

## Files referenced

- `knowledge-base/project/plans/2026-05-21-feat-flagsmith-adoption-plan.md` (v1, marked SUPERSEDED)
- `knowledge-base/project/plans/2026-05-22-feat-flagsmith-adoption-plan-v2.md` (v2, shipped)
- `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- `apps/web-platform/lib/feature-flags/server.ts` (identity-aware resolution)
- `apps/web-platform/supabase/migrations/054_users_role_column.sql`
- Branch: `feat-flagsmith-adoption` (commits `9ecec01d`, `6aceaa21`, `fe9e6e22`)
