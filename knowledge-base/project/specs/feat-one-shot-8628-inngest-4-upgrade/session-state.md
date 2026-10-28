# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8628-inngest-4-upgrade/knowledge-base/project/plans/2026-10-28-chore-inngest-v4-upgrade-stream-detach-plan.md
- Status: complete

### Errors
- Bare git calls denied by main-branch guard; resolved with `git -C <abs-path>` (commits fa1c5128ef, a492b57d5a).
- No nested agent-spawn tool in the subagent harness; prescribed fan-outs ran as inline passes (disclosed in plan's Enhancement Summary; NOT claimed as independent review).
- webfetch denied in background mode; v4 facts verified via web_search + direct npm tarball inspection.
- Premise corrections: no bun.lock in this repo (package-lock.json only, npm@11); stream-detach test at apps/web-platform/test/server/inngest/stream-detach.test.ts; self-hosted server pinned at v1.45.1 not v1.19.4.

### Decisions
- 7-phase plan: dep pin → mechanical codemod (71 files) → middleware rewrite to Middleware.BaseMiddleware → wrapper/test/route deletion → S1–S8+S9 spike re-run → residuals (followthrough retirement + 4 fd-pinning P3s) → ADR-243 amendment.
- Brand-survival threshold: single-user incident with requires_cpo_signoff (serve handler shared with founder BYOK leader loop).
- Checkpointing promoted to R1 — v4 enables it by default; evidence-gated by new spike row S9 with documented `checkpointing: false` fallback.
- S7 wrapper-less stream cut is the deletion kill-proof.
- onRunError.isFinalAttempt (4.26.1) replaces run-log's manual attempt gate — recorded as option.
- ADR-243 amendment in-plan; C4 impact none.

### Components Invoked
- soleur:plan (full), soleur:deepen-plan (fan-outs inlined); cloud-detect.sh, collision-precheck.sh; commits fa1c5128ef + a492b57d5a.

## Technical-Ruling Gate (pre-work)
- cto_spawns=1 (one batched spawn, 6 items — max 2 for the pipeline)
- Outcome: Item A OVERTURNED planner default → ship `checkpointing: false`, S9 measurement-only. Items B–F confirmed/refined (no telemetry replacement; exported-for-test seam; single error-prefix family + op token; `streaming: true`; `^4.<latest>`; no bun.lock).
- Row 18 recategorized: `operator (challengeable)` → `operator (brand)` (closed category list).

## Pipeline Progress (one-shot #8628)
- Draft PR: #11381 (branch feat-one-shot-8628-inngest-4-upgrade, worktree .worktrees/feat-one-shot-8628-inngest-4-upgrade)
- Done: collision checks, worktree+draft-PR, plan+deepen (subagent), scope verify, CTO ruling batch (spawn 1), plan/tasks amended for checkpointing:false, ruling gate PASS.
- Next: soleur:work <plan file> → review → resolve → qa → compound → ship → postmerge.
- Session bookkeeping: #8316 + #9705 closed with evidence comments; #10290 stays deferred (no probe_schema bump); #11372 owned by sibling session (PR #11374 live); apply-web-platform-infra has unrelated red runs (422 alert resource — being fixed by that session; a gated host-update and a dark web-2 boot are operator-side).
