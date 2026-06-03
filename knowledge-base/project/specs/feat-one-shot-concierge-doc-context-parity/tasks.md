# Tasks — Fix Concierge open-document context parity + PIR follow-up cleanup

Plan: `knowledge-base/project/plans/2026-06-03-fix-concierge-open-doc-context-parity-plan.md`
Branch: `feat-one-shot-concierge-doc-context-parity`
Lane: cross-domain
Brand-survival threshold: single-user incident (deepen-plan / ultrathink review recommended at /work)

## Phase 0 — Reproduce & localize (no code)
- [ ] 0.1 Reproduce: open a KB doc, ask the Concierge about it on a connected workspace.
- [ ] 0.2 Capture Sentry breadcrumbs: `concierge document context resolved` (documentKindResolved,
  documentContentBytes, documentExtractError) + `cc-pdf-resolver-skip`.
- [ ] 0.3 Classify the failing layer: (a) workspace path unresolved/unpopulated, (b) prefix-gate
  drop (`knowledge-base/`), or (c) `isPathInWorkspace` rejection.
- [ ] 0.4 Diff the UI file-tree workspace source vs `fetchUserWorkspacePath`/agent-sandbox `cwd`.
  Name the exact divergence line — this is the root cause. Cross-ref workspace-scoping plans.
- [ ] 0.5 Run Open Code-Review Overlap query against final Files-to-Edit
  (`gh issue list --label code-review --state open --json number,title,body --limit 200` + jq).

## Phase 1 — RED (failing regression test first)
- [ ] 1.1 Add `apps/web-platform/test/ws-handler-concierge-open-doc-context.test.ts` (or extend
  `cc-dispatcher-concierge-context.test.ts`). Path must match `test/**/*.test.ts` (vitest node).
- [ ] 1.2 Seed a synthetic workspace fixture (temp dir + `users.workspace_path` swap; drain
  `_resetWorkspacePathCacheForTests`).
- [ ] 1.3 Assert the assembled Concierge context (`documentArgs.documentContent` / system prompt)
  contains the open KB doc body. Drive through resolver/dispatch boundary (no LLM).
- [ ] 1.4 Confirm the test FAILS on `origin/main` (`./node_modules/.bin/vitest run <path>`).

## Phase 2 — GREEN (fix workspace-source divergence)
- [ ] 2.1 Converge `fetchUserWorkspacePath` (resolver + agent sandbox `cwd`) onto the same per-user
  workspace the UI file tree renders from. Reuse existing workspace-resolver helpers.
- [ ] 2.2 Preserve the `knowledge-base/` prefix gate and `isPathInWorkspace` containment verbatim.
- [ ] 2.3 Mirror any new degraded path to Sentry (`cq-silent-fallback-must-mirror-to-sentry`).
- [ ] 2.4 Confirm the Phase 1 test now PASSES.
- [ ] 2.5 Do NOT re-plumb the ⌘⇧L quote path (already works) and do NOT duplicate PR #4868 /
  git-workspace-plumbing git-credential work.

## Phase 3 — Secondary docs cleanup (PIR follow-ups)
- [ ] 3.1 PIR "Follow-ups" line ~153: replace "File as a monitoring follow-up." → cite #4849
  (closed, MVP alert) and #4854 (open, deferred scheduled probe).
- [ ] 3.2 PIR "Action Items" line ~161: replace "tracked as a monitoring follow-up" → same
  #4849/#4854 citation.
- [ ] 3.3 Literal citations only — no `Closes`/`Ref` for #4849/#4854 in the PR body.

## Phase 4 — Verify & ship
- [ ] 4.1 `tsc --noEmit` + full web-platform vitest node project pass.
- [ ] 4.2 grep gates: `File as a monitoring follow-up` → 0; `tracked as a monitoring follow-up`
  → 0; `#4849` ≥ 1; `#4854` ≥ 1 in the PIR.
- [ ] 4.3 PR body includes a Phase 0 root-cause note naming the workspace-source divergence.
- [ ] 4.4 Given single-user-incident threshold: run deepen-plan / ultrathink substance review
  (data-integrity-guardian + security-sentinel + architecture-strategist).
