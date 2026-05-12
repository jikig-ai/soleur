---
plan: knowledge-base/project/plans/2026-05-12-fix-kb-sidebar-header-vertical-alignment-plan.md
branch: feat-one-shot-sol-39-sidebar-misalignment
lane: single-domain
linear: SOL-39
---

# tasks: fix KB sidebar header vertical-baseline misalignment

## Phase 0 — Ground-truth measurement (BEFORE any code edit)

- 0.1. Boot dev server: `bun run dev` from `apps/web-platform/`.
- 0.2. Navigate Playwright MCP to `/dashboard/kb` at viewport 1280×800.
- 0.3. Run `mcp__playwright__browser_evaluate` snippet (per plan Phase 0) to capture `{ brandY, kbY, yDelta, direction }`.
- 0.4. Record measurement in the PR-body draft under "Ground-truth (pre-fix)". Expected: `direction = "Soleur lower than KB", yDelta ≈ 4`. If divergent, halt and re-investigate.

## Phase 1 — Failing test (TDD RED)

- 1.1. Edit `apps/web-platform/test/kb-sidebar-collapse.test.tsx`: append the new `describe("KB sidebar header alignment with main app brand row", ...)` block per plan Phase 1.
- 1.2. Run `bun test apps/web-platform/test/kb-sidebar-collapse.test.tsx`. New assertion MUST fail; existing assertions MUST pass.

## Phase 2 — Fix the KB sidebar header padding

- 2.1. Edit `apps/web-platform/components/kb/kb-sidebar-shell.tsx` line 17: change `<header>` className from `flex shrink-0 items-center justify-between px-4 pb-3 pt-4` to `flex min-h-7 shrink-0 items-center justify-between px-4 py-5`.

## Phase 3 — TDD GREEN

- 3.1. Run `bun test apps/web-platform/test/kb-sidebar-collapse.test.tsx`. All assertions green.
- 3.2. Run `bunx tsc --noEmit` from `apps/web-platform/`. No new errors.

## Phase 4 — Quantitative visual QA via Playwright MCP

- 4.1. Combination #1 (main open, KB open): re-run the `browser_evaluate` snippet; record `{ brandY, kbY, yDelta }`. AC: `yDelta ≤ 1`.
- 4.2. Combination #2 (main collapsed, KB open): same. AC: `yDelta ≤ 1`.
- 4.3. Combinations #3 + #4: screenshots only (KB header is `overflow-hidden`-ed).
- 4.4. Capture screenshots in BOTH default + light themes (theme-token rotation risk per plan §Risks).
- 4.5. Attach measurements + screenshots to PR body.

## Phase 5 — Ship

- 5.1. Commit (single commit, conventional message: `fix(kb): align KB sidebar header baseline with main app brand row`).
- 5.2. Push and open PR. Body cites `Ref SOL-39` (or `Closes SOL-39` if Linear close-on-merge wired).
- 5.3. Run `/soleur:review` for multi-agent review.
- 5.4. After review applies, run `/soleur:ship` to enqueue auto-merge.

## Phase 6 — Post-merge

- 6.1. Verify production deploy shows aligned headers (smoke-screenshot).
- 6.2. Consider filing the shared `<SidebarHeader>` scope-out per plan §Sharp Edges (third-occurrence trigger).
