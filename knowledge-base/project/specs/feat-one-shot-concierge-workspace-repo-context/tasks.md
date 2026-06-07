# Tasks — fix: Concierge derives owner/repo from active workspace

Plan: `knowledge-base/project/plans/2026-06-07-fix-concierge-derive-owner-repo-from-workspace-plan.md`
Lane: cross-domain

## Phase 1 — Setup / RED (failing tests first)

- [ ] 1.1 Confirm the package test runner: read `apps/web-platform/package.json`
  `scripts.test` and the vitest `include:` globs (`apps/web-platform/vitest.config.ts`)
  so new tests land where vitest collects them (`test/**`, not co-located).
- [ ] 1.2 Write failing source-presence test
  `apps/web-platform/test/cc-dispatcher-connected-repo-context.test.ts`
  (AC1/AC3/AC4/AC5): assert a connected-repo directive builder/constant exists with the
  `${connectedOwner}/${connectedRepo}` interpolation + an `-R` reference, and that the
  append sits inside the `connectedOwner && connectedRepo` guard.
- [ ] 1.3 Extend `apps/web-platform/test/soleur-go-runner-gh-auth-status.test.ts` (AC2):
  assert `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` does NOT contain `remote.origin.url` and
  still contains both paren-safe anchors (`gh auth status`, `-R owner/repo`).

## Phase 2 — Core Implementation / GREEN

- [ ] 2.1 `cc-dispatcher.ts`: add a `CONNECTED_REPO_CONTEXT` directive builder
  (module-scope, mirroring `GH_403_PROMPT_DIRECTIVE` at `:260-271`) returning a
  `## Connected repository` block that states `The connected repository is
  ${owner}/${repo}` and instructs `-R ${owner}/${repo}` (lock-step with
  `agent-runner.ts:1429-1441`). Carry the `agent-runner.ts:1425-1428` injection-safety
  comment.
- [ ] 2.2 `cc-dispatcher.ts` `realSdkQueryFactory`: after the `GH_403_PROMPT_DIRECTIVE`
  append (`:1530-1532`), append the new directive inside
  `if (connectedOwner && connectedRepo) { … }` (AC1/AC3/AC5).
- [ ] 2.3 `soleur-go-runner.ts`: rewrite the trailing clause of
  `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` (`:148-159`) — remove the `remote.origin.url`
  discovery instruction; point at "the connected repository named in your context" for
  `-R owner/repo`; keep the `gh auth status` false-negative guidance + both anchors (AC2).

## Phase 3 — Verification

- [ ] 3.1 Run `tsc --noEmit` and the web-platform vitest suite (AC6); all green.
- [ ] 3.2 Confirm no-connected-repo path is byte-identical to baseline (AC5).
- [ ] 3.3 Post-merge: Playwright MCP smoke against the Dashboard Concierge on a
  `jikig-ai/soleur`-connected workspace — "Fix Issue 4826" must NOT reply "no repo
  connected" and must route through the fix workflow (AC7).
