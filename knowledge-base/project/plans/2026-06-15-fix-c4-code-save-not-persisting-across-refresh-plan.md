---
title: "fix(c4): Code-tab Save does not persist across a page refresh (stale on-disk clone)"
type: fix
date: 2026-06-15
branch: feat-one-shot-c4-code-save-not-persisting
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tracking_issue: 5221
supersedes_plan: knowledge-base/project/plans/2026-06-12-fix-c4-code-save-not-persisting-plan.md
---

# 🐛 fix(c4): Code-tab Save does not persist across a page refresh

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Overview/Approach, Research Reconciliation, Acceptance
Criteria, Implementation Phases, Files to Edit, Sharp Edges
**Research agents used:** Explore (implementation-realism), architecture-strategist,
kieran-rails-reviewer, code-simplicity-reviewer

### Key Improvements (from multi-agent review)

1. **Design reworked to GitHub-PRIMARY read (simpler + strictly more correct).**
   The original D1 "detect-stale-then-fallback" design already paid one GitHub
   call per load (the freshness probe), so it bought nothing over just reading
   GitHub directly — but added a sha-reconcile/git-plumbing surface the route
   doesn't have today (it only does `fs.open`). New design: `GET /project` reads
   `.c4` sources + `model.likec4.json` from GitHub (source of truth) as the
   PRIMARY path; the on-disk clone is gone from this route. This dissolves the
   D1/D2 decision, AC2, the AC5 stale-marker, and the `c4-shared.tsx` edit.
2. **B2 (correctness, was a silent-corruption hazard): the GitHub Contents API
   omits the base64 `content` field for files > 1 MB**, and `model.likec4.json`
   is capped at 4 MB (`MAX_C4_BYTES`). A 1–4 MB model would decode to empty/garbage
   and serve a broken dump WITHOUT tripping the 413. **Fix: read file bodies via
   the Git Blobs API (`GET /repos/{owner}/{repo}/git/blobs/{sha}`, base64 up to
   100 MB) using the sha from the diagrams-dir Contents listing.** Precedent for
   base64-decode at `server/inngest/functions/cron-ruleset-bypass-audit.ts:100-120`.
3. **Resolver reuse (drops a Files-to-Edit entry): `resolveActiveWorkspaceRepoMeta`
   already exists** (`server/workspace-resolver.ts:473`), returns ADR-044-correct
   active-workspace `{ repoUrl, githubInstallationId }`, accepts a
   `preResolvedActiveWorkspaceId`, and is already used by `sync/route.ts:91` +
   `upload/route.ts:87`. Owner/repo parse is a one-liner (`upload/route.ts:198-201`).
   No `workspace-resolver.ts` extension needed.
4. **B1: the test file `apps/web-platform/test/c4-project-route.test.ts` ALREADY
   EXISTS** (PR #5218). Append the F-D cases to it (Files-to-Edit), do NOT
   "create" it, and reconcile the mock topology (it currently uses a real tmpfs +
   no GitHub mock; the new cases mock `githubApiGet` per `c4-writer-rerender.test.ts`).

### New Considerations Discovered

- The stale-clone root cause is **KB-wide**: `tree`/`content`/`search`/`share`
  and the public `shared/[token]/c4` read the SAME stale clone (architecture P0).
  This PR fixes only the C4 project read (the reported surface); the #5221 comment
  must acknowledge the wider scope so the markdown read routes + public share path
  get the same GitHub-primary policy in the reconcile redesign.
- Map a Contents-API/Blobs 404 → the existing `MODEL_NOT_BUILT` 404 (a
  never-rendered diagram must still surface "run render", not a generic error).
- Pin both blob reads to a single resolved HEAD sha (`?ref={sha}`) so the source
  and dump are a consistent snapshot, not two independently-racing reads.

## Overview

In the KB document viewer's **Code** panel, editing a `.c4` file (e.g.
`founder = actor "Founder"` → `founder = actor "Founder TEST"`), clicking
**Save**, then **refreshing the page** shows the OLD text in the editor AND the
OLD diagram. The edit does not survive a reload.

**The commit DID land.** `writeC4Diagram` commits the `.c4` (and re-rendered
`model.likec4.json`) to GitHub via the Contents API and returns `200`
(`c4-writer.ts:113-122`). GitHub is the source of truth. The revert is a
**read-path cache-coherence bug**:

1. `GET /api/kb/c4/project` reads BOTH the layouted `model.likec4.json`
   (`project/route.ts:89`) AND the raw `.c4` sources (`project/route.ts:132`)
   **exclusively from the on-disk workspace clone** (`kbRoot`) — never from
   GitHub.
2. The on-disk clone is updated only by a best-effort `git pull --ff-only`
   inside `syncWorkspace` (`c4-writer.ts:124`, `workspace-sync.ts:107`). When
   the clone is **diverged / un-fast-forwardable** — its self-heal *aborts*
   when the clone holds un-pushed `session-sync` commits, to avoid destroying
   agent work (`workspace-sync.ts:198-218`, `op:self-heal-aborted-dirty`) — the
   pull never advances and the clone stays **permanently stale**.
3. On refresh, `GET /project` re-reads that stale clone → returns pre-edit text
   and the pre-edit diagram dump.

### Why the prior fix (#5220) does NOT cover this symptom

The 2026-06-12 plan shipped **F-A1 (client-side optimistic apply)**: on a 200,
the just-saved text is pinned in a React `useRef` (`savedContentRef`,
`c4-shared.tsx`) so the in-session `reload()` doesn't visually revert the
editor. That ref lives in component state. **On a full page refresh the
component unmounts and remounts, `savedContentRef` resets to `{}`, and the
optimistic hedge is gone** — the editor re-seeds from the stale clone with no
protection. #5220 explicitly deferred the server-side root cause as **F-C**
(tracking issue **#5221**, OPEN) and noted the optimistic marker "persists for
the session … until remount". The user's report is precisely the
post-remount / post-refresh case F-C left open.

This plan fixes the **read path** so a refresh serves source-of-truth content,
closing the user-visible slice of #5221 **without** taking on the full
workspace-wide reconcile redesign (which remains tracked in #5221).

### Chosen approach (single fix, minimal blast radius) — REVISED post-deepen

**F-D — Read `GET /api/kb/c4/project` from the GitHub source of truth.**
The route reads the `.c4` sources and `model.likec4.json` from **GitHub** (the
authoritative post-Save state) as the PRIMARY path, removing the dependency on
the possibly-permanently-stale on-disk clone for this endpoint. GitHub is the
source of truth; the clone is a cache that can diverge, and a cache lag must
never present as data loss (the #4976 insight, applied to the read path).

This is the **GitHub-primary** design (selected over the original
detect-stale-then-fallback "D1" after the simplicity + Kieran + architecture
reviews converged): D1 already paid one GitHub call per read for its freshness
probe, so reading GitHub directly costs no more, removes the on-disk
`fs.open`/`O_NOFOLLOW`/TOCTOU read blocks and the sha-reconcile/git-plumbing
surface entirely, and eliminates the staleness window by construction. Concretely:

1. Resolve active-workspace coordinates by REUSING the existing
   `resolveActiveWorkspaceRepoMeta(user.id, serviceClient, activeWorkspaceId)`
   (`server/workspace-resolver.ts:473`) — ADR-044-correct, membership-scoped,
   already wired in `sync`/`upload` routes. Parse `owner`/`repo` from `repoUrl`
   (copy `upload/route.ts:198-201`).
2. List the diagrams dir via `GET /repos/{owner}/{repo}/contents/knowledge-base/{C4_DIAGRAMS_DIR}?ref={sha}`
   (one call) to get the per-file blob `sha` for each `.c4`/`README.md` +
   `model.likec4.json`. Pin to a single resolved HEAD `sha` so source + dump are
   a consistent snapshot.
3. Fetch each file body via the **Git Blobs API**
   `GET /repos/{owner}/{repo}/git/blobs/{sha}` (base64, supports up to 100 MB —
   the Contents API's `content` field is empty for files > 1 MB, and
   `model.likec4.json` is capped at 4 MB by `MAX_C4_BYTES`, so the Contents
   `content` field is unusable here). base64-decode, enforce `MAX_C4_BYTES`.
   Precedent for the base64-decode shape: `cron-ruleset-bypass-audit.ts:100-120`.
4. Map a GitHub 404 on `model.likec4.json` → the existing `MODEL_NOT_BUILT` 404
   (a never-rendered diagram must still say "run render").
5. On any GitHub-read failure, return a distinct error (not a silent stale
   serve); `reportSilentFallback` mirrors it. (AC5 — see Observability.)

The on-disk clone is NOT read by this route after F-D. The clone-staleness root
cause remains workspace-wide and tracked in **#5221**; this PR fixes the C4
read surface and acknowledges the wider scope in the #5221 comment.

---

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue / prior plan) | Reality (verified in code) | Plan response |
| --- | --- | --- |
| "The C4 save bug is already fixed (#5220 merged)." | #5220 shipped client-side optimistic apply only; it is reset on remount, so it does NOT survive a page refresh (`c4-shared.tsx` `savedContentRef = useRef({})`). | Premise is NOT stale. This plan fixes the server read path (the deferred F-C slice). |
| "Read path can fall back to GitHub easily — the route already has owner/repo/installationId." | PARTLY. `GET /project` resolves via `resolveActiveWorkspaceKbRoot` → `{ kbRoot }` only (`project/route.ts:48-54`); it lacks owner/repo/installationId. BUT a sibling resolver `resolveActiveWorkspaceRepoMeta` ALREADY returns ADR-044-correct active-workspace `{ repoUrl, githubInstallationId }` (`workspace-resolver.ts:473`), accepts a `preResolvedActiveWorkspaceId`, and is used by `sync`/`upload` routes. | REUSE `resolveActiveWorkspaceRepoMeta` (no resolver extension). Parse owner/repo from `repoUrl` per `upload/route.ts:198-201`. AC4 pins the member case (the resolver already self-scopes membership). |
| "The GitHub Contents API can return file bodies (used by `c4-writer.ts`)." | MISLEADING. `c4-writer.ts` reads only the `sha`/`type` and WRITES base64 — it never READS a body. The Contents API omits the base64 `content` field for files > 1 MB; `model.likec4.json` is capped at 4 MB. A 1–4 MB model would decode to empty → broken dump, no 413. | Read file BODIES via the **Git Blobs API** (`GET /git/blobs/{sha}`, base64 to 100 MB) using the sha from the Contents directory listing. Add AC for the 1–4 MB round-trip (B2). |
| "syncWorkspace would self-heal a diverged clone." | Only when the clone holds ZERO un-pushed commits (`workspace-sync.ts:198`). A clone holding un-pushed `session-sync` commits aborts and stays stale (`op:self-heal-aborted-dirty`). | GitHub-primary read does NOT depend on the clone advancing. The reconcile redesign stays in #5221. |
| "model.likec4.json GitHub copy is current after a `.c4` save." | TRUE — `rerenderAndCommit` commits the re-rendered JSON to GitHub (`c4-writer.ts:302-311`) before returning 200. So BOTH source AND dump exist on GitHub at refresh time. | Read BOTH from GitHub pinned to one HEAD sha, so the diagram and the code preview both reflect the edit consistently. |
| "Test file `c4-project-route.test.ts` is new." | FALSE — it already exists (PR #5218, owner-sources/README/symlink suite). | Append F-D cases to it (Files-to-Edit), reconcile mock topology (it uses real tmpfs + no GitHub mock; new cases mock `githubApiGet`). |

---

## User-Brand Impact

**If this lands broken, the user experiences:** they edit a `.c4`, click Save,
see "Saved", refresh — and their change is **gone** from both the editor and the
rendered diagram. The user concludes the product silently discarded their work
(the worst single-user failure mode: a save button that lies). This is exactly
the report that opened this plan.

**If this leaks, the user's data/workflow is exposed via:** the read fallback
fetches KB file content from GitHub using the **active workspace's** installation
token. A coordinate-resolution bug (resolving the caller's OWN repo instead of
the active shared workspace) could serve a member the wrong workspace's diagram,
or 404 a legitimately-shared one. The fallback MUST resolve the same
active-workspace owner/repo the sidebar/tree/content READ paths use (ADR-044,
`project/route.ts:42-46`), and MUST keep the existing
`isPathInWorkspace` / diagrams-dir scope guard so no path outside the diagrams
dir is ever fetched.

**Brand-survival threshold:** `single-user incident`. A single user who watches
one save evaporate after refresh loses trust in persistence entirely.

> CPO sign-off required at plan time before `/work` begins. CPO has product
> ownership of the "Save must persist" contract; confirm CPO has reviewed this
> approach (or invoke the CPO domain leader in Phase 2.5). `user-impact-reviewer`
> will be invoked at review-time per the review SKILL conditional-agent block.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Refresh persists the edit (the bug).** A `vitest` test for `GET
  /api/kb/c4/project` proves: with `githubApiGet` mocked to return the post-edit
  `.c4` blob + post-edit `model.likec4.json` (the source of truth), the route
  returns the **post-edit** `.c4` source AND the **post-edit** dump — regardless
  of any on-disk clone state. RED first against the current on-disk-only route,
  then GREEN.
- [ ] **AC2 — Large-model round-trip (B2, the silent-corruption guard).** A test
  proves a `model.likec4.json` **between 1 MB and 4 MB** round-trips correctly:
  the route fetches its body via the **Git Blobs API** (`GET /git/blobs/{sha}`),
  base64-decodes the full content, and serves the complete dump. (A naive
  Contents-API `content` read would return empty for >1 MB and serve a broken
  dump — this AC fails on that implementation.)
- [ ] **AC3 — Scope guard preserved.** The route fetches ONLY paths under the
  diagrams dir; the existing `requestedDir` `..`/NUL rejection
  (`project/route.ts:58-65`) and `isPathInWorkspace` validation still gate the
  path string before it becomes a GitHub path. A test asserts a crafted `dir`
  with `..` is still 400 and triggers no GitHub fetch.
- [ ] **AC4 — Active-workspace coordinates (ADR-044).** The route resolves
  `owner`/`repo`/`installationId` via `resolveActiveWorkspaceRepoMeta` for the
  **active workspace**, NOT the caller's own `users` row. A test for an invited
  member viewing a shared workspace proves the route reads the SHARED workspace's
  repo.
- [ ] **AC5 — GitHub-read failure is honest (no silent revert).** If the GitHub
  read fails (network/auth/rate-limit), the route returns a distinct **503**
  error (e.g. "Couldn't load the latest diagram — try again") and `reportSilentFallback`
  mirrors it; it does NOT silently serve stale clone content as if fresh. A test
  pins the 503 + the absence of any stale-content body.
- [ ] **AC6 — `MODEL_NOT_BUILT` preserved.** A GitHub 404 on `model.likec4.json`
  maps to the existing `MODEL_NOT_BUILT` 404 (`project/route.ts:92-100`), not a
  generic 500/503. A test asserts the 404 + `code: "MODEL_NOT_BUILT"` for a
  never-rendered diagram.
- [ ] **AC7 — Bounds preserved.** The route enforces `MAX_C4_BYTES` on the
  fetched `model.likec4.json` and `.c4` sources (mirroring `project/route.ts:86`).
  A test asserts an oversized (>4 MB) GitHub blob yields 413 (not an unbounded
  buffer). Distinct from AC2 (1–4 MB succeeds; >4 MB → 413).
- [ ] **AC8 — Observability.** A GitHub-read FAILURE is mirrored via
  `reportSilentFallback` (error) with `feature: "c4-project-read"`,
  `op: "github-read-failed"`. An op-contract test in the style of
  `test/sentry-workspace-sync-health-alert-op-contract.test.ts` pins the op slug
  so the alert/monitor can filter on it. (See `## Observability`.)
- [ ] **AC9 — Typecheck + suites green.** `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` exits 0. `./node_modules/.bin/vitest run`
  green for the edited `c4-project-route.test.ts` (existing suites PLUS the new
  F-D cases) and the three existing C4 suites (`c4-code-panel.test.tsx`,
  `c4-writer-rerender.test.ts`, `c4-workspace.test.tsx`).
- [ ] **AC10 — #5221 scope unchanged.** This PR does NOT close #5221 (the
  workspace-wide reconcile redesign + git-op mutex remain open). The PR body uses
  `Ref #5221` and adds a comment on #5221 noting (a) the C4 read slice is now
  mitigated by F-D's GitHub-primary read, and (b) `tree`/`content`/`search`/`share`
  + the public `shared/[token]/c4` route read the SAME stale clone and need the
  same policy in the reconcile redesign. (No `Closes #5221`.)

### Post-merge (operator)

- [ ] **AC11 — Live dogfood.** On the dev-cohort deployment: KB → C4 page → Code
  tab → edit a label in `model.c4` → Save → **refresh the page** → confirm the
  edit persists in BOTH the editor and the rendered diagram. (Automation: not
  feasible — reproducing a permanently-diverged prod clone requires the live
  operator clone's divergence state, which a synthetic CI clone cannot
  reproduce; the unit tests cover the route logic deterministically.)

---

## Implementation Phases

### Phase 0 — Preconditions (mostly settled by deepen-plan; one sweep)

0.1 **Confirm the resolver + Blobs-API shape** against installed code before
coding: `resolveActiveWorkspaceRepoMeta` returns `{ repoUrl, githubInstallationId }`
and accepts `preResolvedActiveWorkspaceId` (`workspace-resolver.ts:473`); the
owner/repo parse precedent is `upload/route.ts:198-201`; the base64-decode
precedent is `cron-ruleset-bypass-audit.ts:100-120`; `githubApiGet` returns parsed
JSON (`github-api.ts:78-97`) — confirm whether `GET /git/blobs/{sha}` works
through `githubApiGet` as-is (it returns `{ content, encoding }`) or needs no new
helper. Record findings in the PR body. (No design decision is open — the
GitHub-primary design has none.)

0.2 **Open Code-Review overlap check.** `gh issue list --label code-review
--state open --json number,title,body --limit 200` then `jq` for
`project/route.ts`, `c4-project-route.test.ts`. Record matches + disposition in
`## Open Code-Review Overlap`.

### Phase 1 — RED (failing tests first)

1.1 **Append** F-D cases to the EXISTING `test/c4-project-route.test.ts` (do NOT
create it — it already holds the owner-sources/README/symlink suite from #5218).
Reconcile the mock topology: the existing suite uses a real tmpfs + no GitHub
mock; the new cases add `vi.mock("@/server/github-api", …)` mirroring
`c4-writer-rerender.test.ts`'s `vi.hoisted` + `vi.importActual` pattern. Mock
`githubApiGet`/Blobs to return the POST-edit `.c4` + `model.likec4.json`; assert
the current on-disk-only route does NOT serve them → **RED**. (AC1)

1.2 Add the large-model test: a 1–4 MB `model.likec4.json` fetched via the Blobs
API base64-decodes fully and serves the complete dump → fails on a Contents-API
`content` implementation. (AC2)

1.3 Add: scope-guard (`dir` with `..` → 400, zero GitHub fetch) (AC3);
active-workspace member (AC4); GitHub-read failure → 503 (AC5);
`MODEL_NOT_BUILT` 404 on GitHub 404 (AC6); oversized >4 MB → 413 (AC7);
op-contract slug (AC8).

### Phase 2 — GREEN (minimal implementation)

2.1 In `GET /api/kb/c4/project` (`app/api/kb/c4/project/route.ts`): resolve the
active workspace id (reuse the existing `resolveActiveWorkspaceKbRoot` for
`activeWorkspaceId`), then call
`resolveActiveWorkspaceRepoMeta(user.id, serviceClient, activeWorkspaceId)`; parse
`owner`/`repo` from `repoUrl` (copy `upload/route.ts:198-201`).

2.2 List the diagrams dir via the Contents API pinned to a single HEAD `sha`
(`?ref={sha}`) to get per-file blob shas; fetch each body via
`GET /git/blobs/{sha}` (Blobs API), base64-decode, enforce `MAX_C4_BYTES`. Build
`sources` (`.c4` + `README.md`, same filter as today, `project/route.ts:122-124`)
and `dump` (`model.likec4.json`). Preserve the `viewIds` derivation and the
`Cache-Control: private, no-cache` header.

2.3 Map a GitHub 404 on `model.likec4.json` → `MODEL_NOT_BUILT` 404
(`project/route.ts:92-100`). On any other GitHub-read failure → distinct 503 +
`reportSilentFallback(op:"github-read-failed", feature:"c4-project-read")`
(AC5/AC8). Remove the on-disk `fs.open`/`O_NOFOLLOW` read blocks (no longer read
by this route).

2.4 Keep the path guards that validate the `dir` STRING before it becomes a
GitHub path: the `..`/NUL rejection (`project/route.ts:58-65`), `isPathInWorkspace`,
and the 401 auth gate.

### Phase 3 — Guards & regression

3.1 `tsc --noEmit` clean (AC9).
3.2 `vitest run` of `c4-project-route.test.ts` (existing + new cases) + the three
existing C4 suites green (AC9).
3.3 `app/api/shared/[token]/c4` (the PUBLIC read path) reads the SAME stale clone
(`shared/[token]/c4/route.ts:85,123`) and exhibits the identical bug for external
viewers. It is OUT OF SCOPE for this PR (different auth model, higher blast
radius) but MUST be filed as an explicit tracked follow-up (a #5221 sub-item or a
new issue), not left as a soft note. (AC10)

### Phase 4 — Tracking-issue update (NOT close)

4.1 Comment on **#5221**: (a) the C4 read slice (refresh shows stale
source/diagram) is now mitigated by F-D's GitHub-primary read; (b) the SAME
stale-clone root cause affects `tree`/`content`/`search`/`share` and the public
`shared/[token]/c4` route (all read the same `kbRoot` clone) — the reconcile
redesign should adopt the same GitHub-primary read policy (ideally a reusable
`server/` helper) across those surfaces; (c) the write/reconcile liveness gap
(perpetual divergence from best-effort `session-sync` push) + the `rev-list→reset`
TOCTOU mutex remain the core open work. Re-eval triggers unchanged. (AC10)

### Phase 5 — Post-merge (operator)

5.1 Live dogfood per AC10.

---

## Observability

```yaml
liveness_signal:
  what: "GET /api/kb/c4/project served a read from the GitHub source of truth"
  cadence: "per page load / Save→reload of the C4 Code panel"
  alert_target: "Sentry — feature:c4-project-read, op:github-read-failed rate"
  configured_in: "apps/web-platform/server/observability.ts (reportSilentFallback) + Sentry inbound filters"
error_reporting:
  destination: "Sentry (reportSilentFallback → captureException, level error) + pino → Better Stack drain"
  fail_loud: "GitHub-read failure is error-level (reportSilentFallback) AND returns a 503 to the client — never a silent stale serve"
failure_modes:
  - mode: "GitHub read fails (network/auth/rate-limit/blobs error)"
    detection: "githubApiGet/Blobs throws in the read path"
    alert_route: "reportSilentFallback feature:c4-project-read op:github-read-failed (error) + 503 response"
  - mode: "model.likec4.json absent on GitHub (never rendered)"
    detection: "GitHub 404 on the model blob"
    alert_route: "404 MODEL_NOT_BUILT response (expected; no page) — client shows 'run render'"
  - mode: "oversized model/source from GitHub (>4 MB)"
    detection: "Buffer.byteLength(decoded) > MAX_C4_BYTES"
    alert_route: "413 response + reportSilentFallback op:github-read-oversize"
logs:
  where: "pino structured logs → container stdout → Vector journald → Better Stack; Sentry for warn+"
  retention: "Better Stack drain retention (existing); Sentry default"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-project-route.test.ts"
  expected_output: "AC1 asserts post-edit source+dump served from GitHub; op-contract test asserts op slug c4-project-read/github-read-failed present"
```

No SSH in any verification path. All failure modes are reachable from
Sentry/Better Stack via the `feature:c4-project-read` tag.

---

## Domain Review

**Domains relevant:** Product (UI persistence contract), Engineering (read-path
architecture). No marketing/sales/finance/legal/ops implications.

### Product/UX Gate

**Tier:** advisory — this fixes the behavior of an EXISTING surface (the C4 Code
panel); it adds no new page, modal, or interactive component. No `.tsx` under
`components/**` or `app/**/page.tsx` is created (the change is server-side in
`app/api/kb/c4/project/route.ts` + a resolver; `c4-shared.tsx` is touched only if
AC5 surfaces a `stale` marker the client must render).
**Decision:** auto-accepted (pipeline) — pipeline/subagent context.
**Agents invoked:** none (advisory, pipeline auto-accept).
**Skipped specialists:** none.
**Pencil available:** N/A (no new UI surface).

#### Findings

The product-critical invariant is "Save persists across refresh." The fix
restores that invariant by reading source-of-truth content. CPO sign-off is
required (single-user-incident threshold) on the approach, not on any new UI.

---

## Open Code-Review Overlap

Run in Phase 0.4 against `project/route.ts`, `workspace-resolver.ts`,
`c4-shared.tsx`. Default expectation: **None** (the prior C4 PRs #5217–#5220 are
merged). Record actual result in the PR body.

---

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **Client-side: persist `savedContentRef` to `localStorage`/`sessionStorage`** so the optimistic apply survives refresh. | Treats the symptom, not the cause: storage-pinned content masks the stale clone indefinitely, drifts from the actual committed bytes, and can show a user content that never actually committed if a later refresh races a different device. Source of truth is GitHub; the read should reflect it. |
| **Fix the write path so the clone always fast-forwards** (the full F-C/#5221 redesign: recover un-pushed `session-sync` commits, add a working-tree git mutex). | Largest blast radius (touches the shared reconcile invariant every consumer depends on) and is a genuine reconciliation design, not a bug-fix. Deferred to #5221 (already filed). F-D unblocks the user now without that risk; #5221 stays open. |
| **D1 detect-stale-then-fallback** (compare clone blob sha vs GitHub, read GitHub only on mismatch). | The freshness probe is itself one GitHub call per read, so D1 does NOT avoid the per-load round-trip — it only avoids the BODY fetch on a clean clone, while ADDING sha-reconcile + git-plumbing the route doesn't have today (it only does `fs.open`). GitHub-primary is fewer lines and strictly more correct (no staleness window). **Rejected in favor of GitHub-primary** at deepen-plan (simplicity + Kieran + architecture converged). |
| **D2 signal-driven fallback** (fall back only when a stale signal is present). | No server-visible signal exists for a *permanently* diverged clone on a fresh page load (the optimistic ref is client-only; `op:self-heal-aborted-dirty` is fire-and-forget telemetry, not a durable per-workspace flag). D2 would not fire on the reported symptom. |
| **Keep clone primary, GitHub as fallback with a `stale:true` client marker** (the pre-deepen F-D). | Re-serving the stale clone with a banner re-introduces the exact silent-staleness the fix exists to kill, and adds a `c4-shared.tsx` UI edit. GitHub-primary + hard 503 on read failure is simpler and more honest. |

---

## Sharp Edges

- An empty / `TBD`-only `## User-Brand Impact` section fails `deepen-plan`
  Phase 4.6. This section is filled (threshold `single-user incident`).
- **B2 — the GitHub Contents API drops the base64 `content` field for files
  > 1 MB.** `model.likec4.json` is capped at 4 MB (`MAX_C4_BYTES`,
  `lib/c4-constants.ts:35`), so a 1–4 MB model read via the Contents API `content`
  field decodes to EMPTY and serves a broken/empty dump WITHOUT tripping the 413 —
  silent corruption worse than the original bug. **Read file BODIES via the Git
  Blobs API** (`GET /repos/{owner}/{repo}/git/blobs/{sha}`, base64 to 100 MB)
  using the sha from the diagrams-dir Contents listing. AC2 pins the 1–4 MB
  round-trip; AC7 pins >4 MB → 413.
- **No existing code reads file BODIES from GitHub.** `c4-writer.ts` reads only
  `sha`/`type` (`:104,:293`) and WRITES base64; the base64-decode READ precedent
  is `cron-ruleset-bypass-audit.ts:100-120`. Confirm in Phase 0.1 whether
  `githubApiGet` returns the Blobs `{ content, encoding }` shape directly (it
  returns parsed JSON) or needs a thin wrapper.
- **Reuse `resolveActiveWorkspaceRepoMeta`** (`workspace-resolver.ts:473`) — it
  already returns ADR-044-correct active-workspace `{ repoUrl, githubInstallationId }`,
  membership-scoped (NOT the caller's own `users` row), and accepts a
  `preResolvedActiveWorkspaceId`. Do NOT extend `resolveActiveWorkspaceKbRoot` or
  read `workspaces.github_installation_id` directly (REVOKED from `authenticated`
  per migration 079 → returns null). Parse owner/repo from `repoUrl` per
  `upload/route.ts:198-201`. Resolving the caller's own row would serve an invited
  member the wrong workspace's diagram — AC4 pins the member case.
- **Pin both reads to one HEAD `sha`.** Fetch the Contents listing and all blob
  bodies with `?ref={sha}` against a single resolved commit so the `.c4` source
  and the `model.likec4.json` dump are a consistent snapshot (not two
  independently-racing reads that a concurrent Save can split).
- If a `.c4` save's re-render FAILED (`rerendered:false`), the GitHub
  `model.likec4.json` is the LAST-GOOD dump, not one matching the just-saved
  source. Serve the GitHub dump as-is (it IS the committed JSON); the existing
  Layer-1 honest-stale banner (#4963) covers source/dump skew. Do NOT re-render
  in the read path.
- Map a GitHub 404 on `model.likec4.json` → the existing `MODEL_NOT_BUILT` 404
  (`project/route.ts:92-100`), so a never-rendered diagram still says "run
  render" rather than 503. AC6.
- **The test file `c4-project-route.test.ts` ALREADY EXISTS** (PR #5218) and uses
  a real tmpfs + no GitHub mock. APPEND the F-D cases and add a `githubApiGet`/Blobs
  mock per `c4-writer-rerender.test.ts`'s `vi.hoisted`+`vi.mock`+`vi.importActual`
  topology; the two styles must coexist in the one file. Do NOT "create" it.
- The stale-clone root cause is **KB-wide**: `tree`/`content`/`search`/`share` +
  public `shared/[token]/c4` read the same `kbRoot` clone. This PR fixes only the
  C4 project read; the #5221 comment must record the wider scope so they adopt the
  same GitHub-primary policy in the reconcile redesign (ideally a reusable helper).
- Do NOT use `Closes #5221` — the workspace-wide reconcile redesign + git mutex
  are NOT in this PR. Use `Ref #5221` and comment to narrow scope (AC10).
- Test runner is **vitest**, test files live in `apps/web-platform/test/**`
  (`*.test.ts(x)`). Typecheck is `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` (NO `npm run -w …` — the repo root declares
  no `workspaces`).

---

## Files to Edit

- `apps/web-platform/app/api/kb/c4/project/route.ts` — read `.c4` sources +
  `model.likec4.json` from the GitHub source of truth (Contents listing for shas
  pinned to one HEAD `sha`, then Git Blobs API for bodies); reuse
  `resolveActiveWorkspaceRepoMeta` for owner/repo/installationId; enforce
  `MAX_C4_BYTES`; map GitHub 404 → `MODEL_NOT_BUILT`; on read failure → 503 +
  `reportSilentFallback`; remove the on-disk `fs.open` read blocks. (core change)
- `apps/web-platform/test/c4-project-route.test.ts` — **EXISTING file** (PR #5218);
  APPEND the F-D cases (AC1–AC8) and reconcile the mock topology (add a
  `githubApiGet`/Blobs mock per `c4-writer-rerender.test.ts`). Do NOT create.

No change expected to `server/workspace-resolver.ts` (reuse the existing
`resolveActiveWorkspaceRepoMeta`), `server/observability.ts` (reuse
`reportSilentFallback`), or `components/kb/c4-shared.tsx` (GitHub-primary read
removes the staleness window, so no client stale-marker is needed).

## Files to Create

- None. (The test file already exists; the route is edited in place.)

---

## Test Scenarios

1. GitHub has post-edit source+dump → route serves post-edit source + post-edit dump (AC1).
2. 1–4 MB `model.likec4.json` via Blobs API → full dump served (AC2; fails on a Contents-`content` impl).
3. `dir` with `..` → 400, zero GitHub fetch (AC3).
4. Invited member on a shared workspace → reads the SHARED workspace repo (AC4).
5. GitHub read throws → 503, no stale-content body (AC5).
6. GitHub 404 on model → `MODEL_NOT_BUILT` 404 (AC6).
7. Oversized (>4 MB) GitHub `model.likec4.json` → 413 (AC7).
8. Op-contract: `feature:c4-project-read` op slug `github-read-failed` present (AC8).
