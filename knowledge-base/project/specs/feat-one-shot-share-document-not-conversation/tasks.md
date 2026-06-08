# Tasks — fix: render the LikeC4 diagram on public /shared document links

Plan: `knowledge-base/project/plans/2026-06-08-fix-shared-document-diagram-render-plan.md`
Lane: cross-domain
Brand-survival threshold: single-user incident (CPO sign-off + review-time `user-impact-reviewer`)

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Confirm `prepareSharedRequest` shape in `app/api/shared/[token]/route.ts`
      (token lookup → revoked 410 → null-hash → workspace_id → ETag) is reusable
      for the new C4 endpoint. It is route-private; decide whether to extract a
      shared helper or duplicate the lookup (the markdown route exports only HTTP
      handlers per `cq-nextjs-route-files-http-only-exports` — a shared helper
      must live in a `server/*` module, not the route file).
- [ ] 0.2 Confirm the Diagram canvas needs only `dump` (verified at plan time:
      `c4-diagram.tsx:67`); `.c4` sources are Code-tab-only. Endpoint omits sources.
- [ ] 0.3 Confirm `workspacePathForWorkspaceId` (sync) is the resolver — NOT
      `resolveActiveWorkspaceKbRoot` (auth-gated).

## Phase 1 — Tests first (RED)

- [ ] 1.1 `test/shared-token-c4.test.ts`: valid token → `{ dir, dump, viewIds }`,
      no `sources` key; unknown token → 404; revoked token → 410 `code:"revoked"`;
      no Supabase session required.
- [ ] 1.2 `test/shared-token-c4.test.ts`: `dir` is bound to
      `dirname(document_path)`; a token for doc A cannot read C4 data for an
      unrelated dir B (client-supplied `dir` query param ignored / rejected).
- [ ] 1.3 `test/shared-token-c4.test.ts`: traversal (`..`, `\0`, symlink via
      `O_NOFOLLOW`) rejected; oversized model → 413; missing model →
      404 `MODEL_NOT_BUILT`.
- [ ] 1.4 `test/shared-page-diagram.test.tsx`: a diagram doc share renders the
      inline diagram (mocked `/api/shared/[token]/c4`); NO Concierge panel, NO
      Code editor / `onSaved` write path mounted.
- [ ] 1.5 Regression: a non-diagram markdown share renders unchanged
      (`shared-page-ui.test.tsx` stays green).

## Phase 2 — Implement public C4 endpoint (GREEN)

- [ ] 2.1 Create `app/api/shared/[token]/c4/route.ts` (GET only). Compose the
      share lookup/revoke/rate-limit pre-gate + the C4 model read. Resolve KB
      root via `workspacePathForWorkspaceId(shareRow.workspace_id)`. Derive `dir`
      from `path.dirname(shareRow.document_path)`; ignore/reject query `dir`.
      Return `{ dir, dump, viewIds }`. Reuse `O_NOFOLLOW`, fstat size gate
      (`MAX_C4_BYTES`), `isPathInWorkspace`, ENOENT→`MODEL_NOT_BUILT`, ELOOP→413.
      Errors route through `reportSilentFallback({ feature: "shared-c4" })`.
- [ ] 2.2 Structured logs: `shared_c4_served` / `shared_c4_not_built` mirroring
      the markdown route's `logger.info` events.

## Phase 3 — Wire the share page render path (GREEN)

- [ ] 3.1 Parameterize the C4 data fetch URL in `components/kb/c4-shared.tsx`
      `useC4Project` (or add a sibling hook) — default stays `/api/kb/c4/project`;
      the share page points it at `/api/shared/<token>/c4`. Grep both consumers
      (`c4-workspace.tsx`, `c4-diagram.tsx`) before changing the hook signature.
- [ ] 3.2 In `components/kb/c4-diagram.tsx`, ensure the public-share context
      renders the Diagram tab only — no Code tab / `onSaved` write affordance.
- [ ] 3.3 In `app/shared/[token]/page.tsx`, when `parseLikeC4Embed(content)`
      (from `lib/c4-embed.ts`) returns an embed, render the token-aware inline
      `C4Diagram` (preferred shape (b): share page pre-extracts + renders
      `C4Diagram` directly, leaving the owner-path `MarkdownRenderer` untouched).
      Else current `MarkdownRenderer` path. Render NEVER mounts `C4Workspace`.
- [ ] 3.4 Update the JSDoc at `markdown-renderer.tsx:144-146` to reflect that
      public shared diagram docs now render via the token-scoped path.

## Phase 4 — Verify

- [ ] 4.1 `tsc --noEmit` clean; route file exports HTTP handlers only.
- [ ] 4.2 Playwright (unauthenticated): share `c4-model.md`, open `/shared/<token>`
      logged out, assert the LikeC4 canvas renders (not a code block) and no
      chat/edit affordances are present. Matches wireframe
      `knowledge-base/product/design/kb-viewer/shared-document-diagram-render.pen`.
- [ ] 4.3 `curl -sI` the new endpoint with no auth cookie: 200 for a valid
      diagram share, 410 for revoked. (discoverability_test)
- [ ] 4.4 Confirm markdown content-hash 410 (`content-changed`) on the existing
      `/api/shared/[token]` route is unchanged.

## Phase 5 — Review / Ship

- [ ] 5.1 Phase 1.7.5 open code-review overlap check on the final Files list.
- [ ] 5.2 Multi-agent review including `user-impact-reviewer` (single-user-incident
      threshold) and `security-sentinel` (public data-boundary endpoint).
- [ ] 5.3 PR body: link the issue with `Ref`/`Closes` as appropriate; reference
      the wireframe. No post-merge operator steps (release pipeline restarts the
      container on merge).
