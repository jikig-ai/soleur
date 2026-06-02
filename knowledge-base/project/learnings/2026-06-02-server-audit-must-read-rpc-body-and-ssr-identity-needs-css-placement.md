---
title: Server-side "which-tenant" audit must read the RPC body; SSR-painted identity needs CSS placement not a JS media gate
date: 2026-06-02
category: integration-issues
module: web-platform/dashboard-nav
tags: [audit-logging, multi-tenant, ssr, useMediaQuery, portal, dead-code, review-caught]
feature: feat-single-nav-rail
issue: 4813
pr: 4810
related_adrs: [ADR-047]
---

# Learning: which-tenant audit fidelity + SSR-painted identity placement (feat-single-nav-rail review)

## Problem

The single-nav-rail PR (#4813) shipped green CI (8164 tests) + tsc-clean, but
multi-agent review caught three PR-introduced defects that the test suite was
structurally blind to. Two are generalizable beyond this feature.

## L1 — A server-side "which tenant did this write touch" audit must derive the tenant from the actual write path (RPC/migration body), NOT from the request's session context

The AC11 wrong-workspace detector (`emitWorkspaceActionContext`) was added to log
the active workspace at the moment a tenant-sensitive action commits. For the
scope-grant route the emit resolved `resolveCurrentWorkspaceId(user.id, supabase)`
— the session's **active** workspace — with a comment asserting "the RPC scopes
the grant to the session's active workspace."

That premise was **false**. `grant_action_class` (migration 063) scopes the grant
UNCONDITIONALLY to the founder's **solo** workspace (`workspace_id = auth.uid()`);
multi-workspace scope-grants are deferred (#4342). So after a workspace switch the
detector would log a tenant the grant **never touched** — a false positive in
exactly the case the detector exists to catch. The comment was hallucinated against
the conceptual narrative, not read off the RPC body.

**Key insight:** This is the [legal-disclosure-prose-hallucinated-against-migration-body]
defect class applied to **audit/log code**. When you write code (or a comment) that
claims to record *which tenant a mutation landed in*, the source of truth is the
write path's own body — `pg_get_functiondef`/the migration SQL/the RPC — not the
route's session resolvers, which can diverge (a solo-fallback resolver returns the
active workspace; the RPC writes the solo one). **How to apply:** before emitting a
tenant id in an audit line, read the RPC/migration the mutation calls and emit the
exact column the write uses. The two sibling emits (invite-member, delegations) were
correct precisely because they logged a `workspaceId` an in-request guard had just
proven equal to the write target.

## L2 — Identity that must paint on the first SSR frame uses CSS breakpoint placement, never a JS `useMediaQuery` gate

To single-mount the workspace context band (one `OrgSwitcherContainer`/`LiveRepoBadge`
fetch, AC4b), the band was gated `isDesktop ? <rail band> : <mobile band>` via
`useMediaQuery`. `useMediaQuery` returns `false` during SSR **and the first hydration
render** (the client render must match the server output). So on a desktop hard-load,
for one tick neither band paints — including the **synchronous** back chevron (AC3) —
a transient violation of the "identity visible in every state" brand invariant.

**Key insight:** a JS viewport gate cannot satisfy a first-paint invariant — SSR has no
viewport, and hydration must match SSR. **How to apply:** render both placements and
let CSS pick (`md:hidden` on the mobile bar, `hidden md:block` on the rail), so the
correct one paints on frame 0 with no JS tick. The cost is two component instances
(two fetches); the AC4b single-*module* import guard still holds (the band is the only
importer), and CSS guarantees only one is ever visible — no duplicate identity on
screen. Single-render-site and first-paint-correctness are in tension whenever the two
placements live in different DOM parents; first-paint wins for a brand invariant.

## L3 — Lift context-coupled secondary navs via a React portal, not by lifting their data layer

The three secondary navs were asymmetric: the KB tree depends on `KbContext` (one
`/api/kb/tree` fetch shared with the doc viewer), Settings needs server-resolved tab
props, Conversations is self-contained. A "render keyed by segment in the parent"
approach would force lifting KB/Settings data up to the always-mounted parent (tree
fetched on every dashboard route). A **portal** (`RailSlotPortal` → `createPortal`)
keeps each nav inside its own provider subtree (React context follows the React tree,
not the DOM tree) while its DOM lands in the unified rail. See ADR-047.

## Session Errors

1. **Push rejected (non-fast-forward).** The Phase 0 rebase rewrote already-pushed
   planning commits. **Recovery:** verified the remote held only pre-rebase copies of
   my own commits (`git log HEAD..origin/<branch>`), then `push --force-with-lease`.
   **Prevention:** rebasing a branch whose planning commits are already on the PR means
   a force-with-lease on the first post-rebase push — expect it, verify divergence is
   self-only first.
2. **`next lint` interactive-prompt hang.** `npm run lint` (deprecated `next lint`)
   dropped into an ESLint-setup prompt under the multi-lockfile worktree.
   **Recovery:** gated Phase 3 on `tsc --noEmit` + full vitest suite; CI runs lint.
   **Prevention:** treat `next lint` as non-interactive-hostile here; rely on tsc + the
   suite at work-phase, defer lint to CI.
3. **`set -uo pipefail` tripped `ZSH_VERSION: unbound variable`** in the profile-sourcing
   shell snapshot, making a classification grep return empty. **Recovery:** recognized
   the source files were obviously present and proceeded. **Prevention:** avoid `set -u`
   for one-off greps that run through the snapshot's profile sourcing.
4. **Self-introduced P1 — scope-grant audit wrong tenant** (L1). **Recovery:**
   data-integrity-guardian read migration 063 and caught the divergence; emit `user.id`.
   **Prevention:** L1 — read the RPC/migration body before claiming which tenant a
   mutation wrote.
5. **Self-introduced P1 — SSR first-paint identity gap** (L2). **Recovery:** CSS
   placement. **Prevention:** L2 — never gate first-paint identity on `useMediaQuery`.
6. **Self-introduced P2 — dead code stranded** (`kbCollapsed` axis + `KbSidebarShell
   .onCollapse`) after the refactor removed their only activators. **Recovery:** removed
   the state, toggle, interface fields, and prop-drilled consumers. **Prevention:** when
   a refactor removes the sole activator of a state axis (a collapse button + its ⌘B),
   sweep the now-unreachable state and every prop-drilled consumer in the same change —
   tsc stays silent because the symbols are still referenced.
