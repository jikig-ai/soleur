---
title: "fix: render the LikeC4 diagram on public /shared document links"
type: fix
date: 2026-06-08
branch: feat-one-shot-share-document-not-conversation
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: Shared document link does not render the C4 diagram (renders prose only)

## Enhancement Summary

**Deepened on:** 2026-06-08

### Key Improvements

1. **Data-minimization sharpened the security boundary.** Verified the Diagram
   canvas needs only `data.dump`; `.c4` sources are Code-tab-only. The public
   endpoint now returns `{ dir, dump, viewIds }` and omits `sources` — removing
   a source-text exposure class from the public surface.
2. **Precedent-diff confirmed (Phase 4.4):** the new endpoint is a composition
   of two existing patterns (`prepareSharedRequest` + the C4 model read), no
   novel security primitive. Verbatim reuse mandated; only `dir` derivation is new.
3. **Load-bearing symbols verified** against the working tree
   (`workspacePathForWorkspaceId` is sync + workspace-id-keyed; `resolveActiveWorkspaceKbRoot`
   explicitly rejected as auth-gated). Wireframe produced + committed (Phase 4.9).

### New Considerations Discovered

- The C4 `model.likec4.json` is a file separate from the shared `.md`; its
  freshness is independent of the markdown content-hash gate. Parity with the
  authenticated viewer (which does NOT hash-gate the model) argues for serving
  the current committed model without an extra gate — confirm at /work.
- Agent-native parity already satisfied (share lifecycle has MCP tools); this
  render-path fix adds no operator action, so no new MCP tool. Recorded to
  pre-empt a spurious review scope-out.


🐛 **Bug.** When a workspace member shares a KB document that embeds a LikeC4
view (e.g. `engineering/architecture/diagrams/c4-model.md`), the public
`https://app.soleur.ai/shared/<token>` page renders the markdown **prose only**.
The interactive diagram (LikeC4 / React Flow canvas) that the authenticated KB
viewer shows for the same file is missing. The operator described this as the
share "capturing conversation context instead of the document" — that framing
is a **misdiagnosis** (see Research Reconciliation); the share faithfully serves
the document bytes, it just does not render the embedded diagram.

## Overview

The shared page (`apps/web-platform/app/shared/[token]/page.tsx`) renders
markdown with:

```tsx
<MarkdownRenderer content={data.content} nofollow />
```

`MarkdownRenderer` only turns a ` ```likec4-view ` fenced block into an
interactive `<C4Diagram/>` when its `enableC4` prop is `true`
(`apps/web-platform/components/ui/markdown-renderer.tsx:89,105`). The share page
omits `enableC4`, so the embed stays a plain code block — exactly the prose-only
output the operator sees. The JSDoc at `markdown-renderer.tsx:144-146` documents
this as deliberate: *"callers without the flag provider (e.g. public shared
docs) omit it and embeds stay code blocks."*

Simply flipping `enableC4` on is **not sufficient and would ship a broken
diagram**. `C4Diagram` → `useC4Project(dirPath)`
(`apps/web-platform/components/kb/c4-shared.tsx:47-76`) fetches diagram data from
`GET /api/kb/c4/project?dir=…`, which **requires an authenticated user**
(`apps/web-platform/app/api/kb/c4/project/route.ts:30-37`) and resolves the KB
root from the *caller's* active workspace
(`resolveActiveWorkspaceKbRoot`, line 45). An anonymous share viewer would get a
401 and the diagram would render an error spinner.

**The fix therefore has two coupled parts:**

1. A new **public, token-scoped** C4 data endpoint
   (`GET /api/shared/[token]/c4`) that resolves the KB root from the *share
   row's* `workspace_id` (mirroring `app/api/shared/[token]/route.ts`
   `prepareSharedRequest`), serves the precomputed `model.likec4.json` +
   `.c4` sources for the embed's dir, and is gated **only** by a valid,
   non-revoked share token. No Supabase auth.
2. A **token-aware diagram render path** on the shared page that fetches from
   that endpoint instead of `/api/kb/c4/project`, rendering the inline
   `C4Diagram` (NOT the full `C4Workspace`, which embeds the Concierge chat and
   the `.c4` Code editor — both are owner-only write surfaces that must never
   reach a public viewer).

The share-link **generation** path is correct and out of scope: `createShare`
stores `document_path` + `workspace_id` + `content_sha256`
(`app/api/kb/share/route.ts:74-80`); the conversation thread is never read by
the share or render path.

## Research Reconciliation — Spec vs. Codebase

| Operator claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Share captured conversation/thread content instead of the document" | `/api/shared/[token]` reads `document_path` from `kb_share_links` and serves the file bytes (frontmatter-stripped markdown). No conversation/thread is ever read. (`app/api/shared/[token]/route.ts:218-249`) | Re-scope from "stop capturing conversation" to "render the embedded diagram". No change to share generation. |
| "Shared page shows C4 prose but not the diagram" | Confirmed. `MarkdownRenderer` is called WITHOUT `enableC4`, so ` ```likec4-view ` stays a code block. (`app/shared/[token]/page.tsx:145`) | Render the diagram (parts 1+2 above). |
| (implied) "just enable C4 on the share page" | The C4 data route is auth-gated and caller-workspace-scoped; anon viewers 401. (`app/api/kb/c4/project/route.ts:30-45`) | New public token-scoped data endpoint is required. |

## Premise Validation

No external GitHub issues/PRs are cited by reference in the task. Code artifacts
cited by the task (`c4-model.md`, the `/shared/[token]` route, `MarkdownRenderer`)
all exist on the working tree and were read directly. ADR-044 (`workspace_id`
keying), #4964 (out-of-process `.c4` render), and #4996 (LikeC4 logo relocation)
are referenced only as in-code comments and were confirmed by reading the cited
files. No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** a public share recipient sees a
half-rendered architecture document — the diagram the owner intended to show is
either missing (current bug) or, if the public endpoint is mis-scoped, a viewer
could read `.c4` sources / model JSON from a workspace they were never granted.
**If this leaks, the user's workspace KB is exposed via:** an over-broad
`/api/shared/[token]/c4` endpoint that accepts a `dir` param without re-binding
it to the shared document's own directory, or that resolves a workspace other
than the share row's `workspace_id` — letting any valid token read arbitrary C4
projects across the workspace.
**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer`
> will be invoked at review-time per `review/SKILL.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Sharing `engineering/architecture/diagrams/c4-model.md` and opening
      `/shared/<token>` (logged OUT) renders the interactive LikeC4 canvas, not a
      `likec4-view` code block. (Playwright, unauthenticated context.)
- [ ] `GET /api/shared/<token>/c4` returns `{ dir, dump, viewIds }` (NO `sources`
      — see Research Insights data-minimization) for a valid token with NO
      Supabase session, and resolves the KB root from the share row's
      `workspace_id` (NOT `auth.getUser()`).
- [ ] `GET /api/shared/<token>/c4` returns 404/410 for an unknown / revoked token,
      mirroring `prepareSharedRequest` semantics (revoked → 410 `code:"revoked"`).
- [ ] The endpoint binds the resolved C4 `dir` to the **shared document's own
      directory** (`path.dirname(document_path)`), ignoring any client-supplied
      `dir` that escapes it — proven by a test that a token for doc A cannot read
      C4 sources for an unrelated dir B. Path-traversal (`..`, `\0`, symlink)
      rejected exactly as `app/api/kb/c4/project/route.ts:55-62` does.
- [ ] The shared page renders the inline `C4Diagram` variant only — NO Concierge
      chat panel, NO `.c4` Code editor save affordance reachable from `/shared/*`.
      (Assert the share render path never mounts `C4Workspace` / `C4CodePanel`'s
      `onSaved` write path.) The rendered composition matches the committed
      wireframe `knowledge-base/product/design/kb-viewer/shared-document-diagram-render.pen`
      (header + prose + read-only diagram panel + CTA; no edit/chat affordances).
- [ ] Non-diagram markdown shares (a doc with no `likec4-view` embed) render
      unchanged — existing `shared-page-ui.test.tsx` stays green.
- [ ] Content-hash gate unchanged: a modified source doc still 410s
      `content-changed`; the new C4 endpoint does not weaken the markdown
      hash gate on `/api/shared/[token]`.
- [ ] `tsc --noEmit` clean; no new auth-route export from `app/**/route.ts` beyond
      HTTP method handlers (`cq-nextjs-route-files-http-only-exports`).

### Post-merge (operator)

- [ ] None — pure code change against already-provisioned surfaces; the
      web-platform release pipeline restarts the container on merge.

## Files to Edit

- `apps/web-platform/app/shared/[token]/page.tsx` — branch markdown render: when
  the content has a `likec4-view` embed, render the diagram via a token-aware
  path; else current `MarkdownRenderer`. Pass a token-scoped data source down.
- `apps/web-platform/components/ui/markdown-renderer.tsx` — allow the
  `likec4-view` → diagram swap to use a token-scoped fetcher. Two viable shapes
  (decide at /work): (a) add an optional `c4Fetcher`/`shareToken` prop threaded
  to `C4Diagram`; (b) keep `MarkdownRenderer` untouched and let the share page
  pre-extract the embed (via `parseLikeC4Embed`, `lib/c4-embed.ts`) and render
  `C4Diagram` itself. Prefer (b) — smaller blast radius, no new branch in the
  shared owner-path renderer. Update the JSDoc at lines 144-146 accordingly.
- `apps/web-platform/components/kb/c4-shared.tsx` — `useC4Project` currently
  hardcodes `/api/kb/c4/project`. Parameterize the fetch URL (or add a sibling
  hook) so the share page can point it at `/api/shared/[token]/c4`. Keep the
  owner path's URL as the default.
- `apps/web-platform/components/kb/c4-diagram.tsx` — accept the token-scoped
  data source; ensure the Code tab's save (`onSaved` → write) is disabled / not
  rendered in the public-share context.

## Files to Create

- `apps/web-platform/app/api/shared/[token]/c4/route.ts` — public token-scoped
  C4 data endpoint. Reuses the share lookup + revoke + workspace-id resolution
  pattern from `app/api/shared/[token]/route.ts` (`prepareSharedRequest`) and
  the C4 read logic from `app/api/kb/c4/project/route.ts` (model JSON ONLY —
  omit `.c4` sources per data-minimization, `O_NOFOLLOW`, `MAX_C4_BYTES`,
  `isPathInWorkspace`). The `dir` is derived server-side from the share row's
  `document_path` directory — NOT taken from the query string. Resolve the KB
  root via `workspacePathForWorkspaceId(shareRow.workspace_id)` (NOT
  `resolveActiveWorkspaceKbRoot`, which requires auth). Apply
  `shareEndpointThrottle` rate-limiting.
- `apps/web-platform/test/shared-token-c4.test.ts` — token-scoped data endpoint:
  valid/unknown/revoked token, workspace-id resolution, dir-binding (cannot read
  unrelated dir), traversal rejection.
- `apps/web-platform/test/shared-page-diagram.test.tsx` — share page renders the
  diagram (mocked endpoint) and does NOT mount Concierge/Code-write surfaces.

## Open Code-Review Overlap

To be populated by the Phase 1.7.5 check during /work (none expected — this is a
narrow new-endpoint + render-branch change). Recorded here so the check ran.

## Observability

```yaml
liveness_signal:
  what: shared_page_viewed / shared_c4_served structured log events
  cadence: per public share view
  alert_target: none (organic-traffic-dependent; no synthetic prober added)
  configured_in: app/api/shared/[token]/route.ts + new c4/route.ts logger.info calls
error_reporting:
  destination: Sentry via reportSilentFallback (existing observability helper)
  fail_loud: true — unexpected errors on the new c4 endpoint route through
             reportSilentFallback({ feature: "shared-c4", op: "serve" }), mirroring
             the markdown route's mapSharedError 500 branch.
failure_modes:
  - mode: token valid but model.likec4.json absent (MODEL_NOT_BUILT)
    detection: 404 code:"MODEL_NOT_BUILT" returned; logged as shared_c4_not_built
    alert_route: none (owner-action: run /soleur:architecture render)
  - mode: dir resolves outside workspace / traversal attempt
    detection: 400 Invalid dir; logged with token + attempted dir
    alert_route: Sentry if frequency spikes (potential probe)
  - mode: anon viewer hits auth-gated /api/kb/c4/project by mistake
    detection: 401 (no regression — share page must never call that URL)
    alert_route: covered by Pre-merge AC asserting the share path uses the token endpoint
logs:
  where: pino structured logs (server), Sentry (errors) — same sinks as the
         existing share route
  retention: per existing log/Sentry retention; no new sink
discoverability_test:
  command: "curl -sI https://app.soleur.ai/api/shared/<token>/c4 (no auth cookie); expect 200 for a valid diagram share, 410 for revoked"
  expected_output: HTTP/1.1 200 with application/json body containing a dump; revoked → 410
```

## Domain Review

**Domains relevant:** Engineering (security/data-boundary), Product/UX.

### Engineering — data-boundary

**Status:** reviewed (planner assessment; deepen-plan will spawn leaders)
**Assessment:** The new public endpoint is the brand-survival surface. It MUST
(a) resolve workspace strictly from the share row's `workspace_id`, never from
session or query; (b) bind the C4 `dir` to the shared document's own directory
so a token cannot pivot to other workspace dirs; (c) reuse the existing
traversal/`O_NOFOLLOW`/size guards verbatim. This is a `single-user incident`
threshold surface — deepen-plan must run `security-sentinel` +
`data-integrity-guardian` (plan-review style/scope agents are structurally blind
to a mis-scoped data boundary).

### Product/UX Gate

**Tier:** advisory (modifies the existing `/shared/[token]` page; no new route,
no new multi-step flow — the diagram replaces an already-present code block in
the same content column). The mechanical UI-surface glob matches
(`app/**/page.tsx`, `components/**/*.tsx`), so a `.pen` wireframe is required.
**Decision:** reviewed (wireframe produced)
**Agents invoked:** ux-design-lead (via Pencil headless CLI, `PENCIL_CLI_KEY`
from Doppler `soleur/dev`)
**Skipped specialists:** none
**Pencil available:** yes (headless CLI Tier 0)
**Wireframe:** `knowledge-base/product/design/kb-viewer/shared-document-diagram-render.pen`
(committed) — adds the "Public Shared Document — Diagram Render (/shared/[token])"
frame: branded header, centered prose, inline read-only LikeC4 diagram panel
(Diagram tab only, no Code/edit tab, no Concierge), pan/zoom, CTA banner.

#### Findings

The intended outcome is *parity* with the authenticated KB viewer's inline embed
(`C4Diagram`), minus owner-only write affordances. No new visual design — the
wireframe documents the read-only public composition (header + prose + diagram +
CTA) and the explicit absence of edit/chat affordances, built on the existing
`kb-viewer` design set.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Just pass `enableC4` to `MarkdownRenderer` on the share page | Diagram data fetch (`/api/kb/c4/project`) is auth-gated → anon viewer 401s; ships a broken spinner. |
| Reuse `/api/kb/c4/project` and relax its auth to accept a share token | Conflates two trust models in one route; the route is caller-workspace-scoped and would need a token branch that's easy to get wrong. A dedicated public endpoint keeps the token trust boundary isolated and auditable. |
| Render the full `C4Workspace` on the share page | Embeds the Concierge chat + `.c4` Code save editor — owner-only write surfaces. Must NOT be public. Inline `C4Diagram` (read-only canvas) is the correct public shape. |
| Pre-rasterize the diagram to a static image at share-create time | Loses interactivity (pan/zoom/drill-down) the operator explicitly expects; stale on source edits; larger scope. Deferred — not a goal. |

## Research Insights (deepen-plan, 2026-06-08)

**Verified load-bearing symbols (all exist on the working tree):**

- `workspacePathForWorkspaceId(workspaceId: string)` — `apps/web-platform/server/workspace-resolver.ts:668`. **Synchronous**, takes the workspace id directly. This is exactly what `prepareSharedRequest` already uses (`app/api/shared/[token]/route.ts:194`). The new C4 endpoint resolves its KB root identically: `path.join(workspacePathForWorkspaceId(shareRow.workspace_id), "knowledge-base")`. **Do NOT call `resolveActiveWorkspaceKbRoot`** (that path requires an authenticated user — `app/api/kb/c4/project/route.ts:45`).
- `isPathInWorkspace(...)` — `apps/web-platform/server/sandbox.ts:110`.
- `shareEndpointThrottle` — `apps/web-platform/server/rate-limiter.ts:244` (reuse for rate-limit parity with the markdown share route).
- `MAX_C4_BYTES` is **route-local** in `app/api/kb/c4/project/route.ts:14` (not exported). The new endpoint should define its own copy (4 MiB) or extract a shared constant — decide at /work; copying is acceptable (one literal).

**Data-minimization (sharpens the User-Brand Impact boundary):** The interactive
**Diagram** canvas consumes only `data.dump`
(`components/kb/c4-diagram.tsx:67` → `C4Canvas dump=...`). The raw `.c4`
`data.sources` are consumed **only** by the Code-tab editor `C4CodePanel`
(`components/kb/c4-shared.tsx:225,252,259`), which the public share does NOT
render. Therefore the public `/api/shared/[token]/c4` endpoint should return
`{ dir, dump, viewIds }` and **omit `sources` entirely** — the share viewer
never needs the raw architecture-source text. This removes both an unnecessary
read-only-editor surface AND a class of source-text exposure. (The authenticated
`/api/kb/c4/project` keeps returning sources for the owner's Code tab.)

**Precedent-diff (Phase 4.4):** The new endpoint is a *composition* of two
existing, established patterns — no novel security primitive:

| Concern | Precedent to mirror verbatim |
| --- | --- |
| token lookup → revoke 410 → workspace_id resolution → rate limit | `app/api/shared/[token]/route.ts` `prepareSharedRequest` (lines 119-206) |
| C4 model read (`O_NOFOLLOW`, fstat size gate, `isPathInWorkspace`, ENOENT→`MODEL_NOT_BUILT`, ELOOP→413) | `app/api/kb/c4/project/route.ts` (lines 64-106) |

Reuse both verbatim; the only new logic is deriving `dir` from
`path.dirname(shareRow.document_path)` instead of the query string.

**Agent-native parity (informational, NOT in scope):** The KB share lifecycle
already has MCP-tool parity (`createShare`/`listShares`/`revokeShare` in
`server/kb-share-tools.ts`). This fix adds no new operator *action* (it's a
render-path fix), so no new MCP tool is warranted. Recorded so the review phase
does not file a spurious agent-parity scope-out.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  TBD/TODO/placeholder, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This section is filled.)
- **Do not take the C4 `dir` from the query string on the public endpoint.**
  Derive it server-side from the share row's `document_path` directory. A
  client-supplied `dir` is the over-broad-read vector named in User-Brand Impact.
- **Public share must render `C4Diagram` (inline, read-only), never
  `C4Workspace`.** `C4Workspace` mounts `KbChatContent` (Concierge) and
  `C4CodePanel` with an `onSaved` write callback — both owner-only.
- The C4 model file (`model.likec4.json`) is a SEPARATE file from the shared
  `.md` doc. The markdown route's `content_sha256` hash gate covers the `.md`
  only; the C4 endpoint serves the model JSON whose freshness is independent.
  Decide at /work whether the public C4 endpoint needs its own staleness signal
  or whether serving the current committed model (matching the authenticated
  viewer's behavior) is acceptable — the authenticated viewer does NOT hash-gate
  the model, so parity argues for no extra gate. Document the decision.
- `c4-shared.tsx` `useC4Project` is shared by the authenticated `C4Workspace`
  AND inline `C4Diagram`. When parameterizing its fetch URL, keep the existing
  `/api/kb/c4/project` default so the authenticated paths are untouched; grep
  both consumers before changing the hook signature.
