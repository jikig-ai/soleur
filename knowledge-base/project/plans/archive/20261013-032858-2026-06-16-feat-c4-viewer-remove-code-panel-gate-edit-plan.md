---
title: "feat: Remove C4 viewer code panel + gate edit behind c4-edit flag (Concierge-only KB writes)"
type: feat
date: 2026-06-16
branch: feat-one-shot-c4-viewer-remove-code-panel-gate-edit
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned
---

# feat: Remove the C4 viewer code panel + gate C4 edit behind a `c4-edit` flag (Concierge-only KB writes)

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-06-16

**Gates passed:** 4.6 User-Brand Impact (threshold `single-user incident`), 4.7 Observability
(5-field schema, no-SSH discoverability test), 4.8 PAT-shaped variable (none), 4.9 UI-Wireframe
Halt — fired on the `components/kb/*.tsx` edits; `ux-design-lead` produced a committed wireframe
at `knowledge-base/product/design/kb-viewer/c4-viewer-no-code-panel-gated-edit.pen`.

**Verification passes:**
- **Verify-the-negative grep pass (10 claims, all `confirms`):** `writeC4Diagram` has exactly
  two callers (PUT route + Concierge tool); the PUT route has no flag check today; `C4CodePanel`
  renders in exactly two surfaces; the other two C4 routes are GET-only; `KbRouteContext` carries
  no role; `resolveIdentity` fails closed to `prd`/`ANON_IDENTITY`; `resolveC4FlagEnabled` reads
  `c4-visualizer` only (never `c4-edit`); `envIsOn` is exact-`"1"`; all 3 flag-object fixtures are
  TS-exhaustive; `flip.sh` lacks `c4-edit`.
- **security-sentinel:** APPROVED — the PUT-route gate is the complete, fail-closed write
  boundary (no fail-OPEN path across anon/prd/dev/outage/identity-error, given the
  `FLAG_C4_EDIT=0` Doppler mirror). Two informational P2s folded in: the 30s `role:orgId` LRU
  governs future-canary propagation granularity (now noted in AC16); `resolveIdentity`'s
  `react.cache` is request-scoped (no cross-request staleness).

**Key finding:** the plan needed **no structural change** — the original shape (new flag,
client tab-hide ×2, fail-closed server gate, Concierge path untouched, gate-don't-delete) held
under adversarial verification. Enhancements are the committed wireframe + the canary-granularity
note in AC16.

## Overview

In the KB LikeC4 diagram viewer, the user-facing **Code panel** (the in-browser `.c4`
source editor with a **Save** button — the `C4CodePanel` component) is the only direct
end-user path that mutates the knowledge base. There are bigger underlying problems that
need fixing before KB editing is safe for end users, so this change **removes the code
panel from end users and gates the C4 edit capability behind a NEW runtime feature flag
`c4-edit` (default OFF for everyone, including dev)**. After this lands, the **only** live
path that modifies KB `.c4` diagrams is the **Soleur Concierge** (its existing
`edit_c4_diagram` MCP tool, gated on the separate `c4-visualizer` flag — **unchanged**).

This is a deliberate, **reversible** capability removal: we gate behind a default-OFF flag
rather than deleting `C4CodePanel`, so user editing can be re-enabled later by flipping the
Flagsmith flag once the underlying issues are fixed. Diagram **viewing** (the existing
`c4-visualizer` flag) is untouched.

The real security boundary is the **server write route** `PUT /api/kb/c4/[...path]` — it
has **no flag check today**. Hiding the Code tab in the client is cosmetic; the route must
be gated **fail-closed** (403 when `c4-edit` is OFF) or the capability is merely hidden, not
disabled. The two changes ship together: client tab-hide (UX) + server route gate (boundary).

**Complexity:** small (hours). One route gate + two client tab-hides + flag plumbing + tests.
No schema, no migration, no infra.

### Architecture: the two-flag model

| Flag | Gates | Status in this plan |
| --- | --- | --- |
| `c4-visualizer` (existing) | Diagram **view** (`GET /api/kb/c4/project`, render) **and** Concierge edit-tool eligibility (`resolveC4FlagEnabled` → `edit_c4_diagram`). | **Unchanged.** |
| `c4-edit` (**new**) | **Only** the user-direct edit surface: the Code-panel UI (2 sites) + the `PUT /api/kb/c4/[...path]` route. | Added, default **OFF** for all roles. |

The two flags resolve through **textually disjoint** code paths (verified). The Concierge
path reads `C4_VISUALIZER_FLAG` exclusively and never reads `c4-edit` — so flipping `c4-edit`
cannot affect Concierge writes, and flipping `c4-visualizer` cannot re-open user editing.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (entered directly via the one-shot path). The feature
description's premises were validated against `origin`/worktree code; all held, with these
clarifications carried into the plan:

| Premise (from feature description) | Codebase reality | Plan response |
| --- | --- | --- |
| "the code panel" is a single surface | `C4CodePanel` is rendered in **two** places: `c4-workspace.tsx` (full-page "Code" tab) **and** `c4-diagram.tsx` (inline markdown-embed "code" tab, already hidden when `readOnly`). | Gate **both** render sites on `c4-edit`. Missing either leaves the panel live in one surface. |
| "remove the edit feature from end users" | Removing only the client tab leaves `PUT /api/kb/c4/[...path]` reachable (curl/devtools/stale tab). The route has **no flag check today**. | Gate the **server route** fail-closed (403). This is the load-bearing boundary; the client hide is cosmetic. |
| "restrict KB modification so only Concierge can perform it" | `writeC4Diagram` (`server/c4-writer.ts`) is the **single shared write path** for both the PUT route and the Concierge tool. Exactly **two** callers; the other two C4 routes are GET-only. | Gate the PUT caller; leave `writeC4Diagram` + the Concierge caller untouched. Concierge becomes the only live writer. |
| The PUT route can read the user's role to gate | `KbRouteContext` (`server/kb-route-helpers.ts`) carries only `{user:{id}, userData, owner, repo, relativePath}` — **no identity/role**. | Route must call `createClient()` + `resolveIdentity(supabase)` itself (cache-deduped, fails closed to `prd`/`ANON_IDENTITY`), then `getRuntimeFlag("c4-edit", identity)`. |
| Adding the flag is a small, isolated edit | `getFeatureFlags` returns `Record<FlagName, boolean>`; **every** test fixture that constructs a full flags object is TS-exhaustive and will fail to compile until `"c4-edit": false` is added. | Enumerate all 3 fixture files in Files to Edit (see §Files to Edit). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a C4 diagram page where the direct
  `.c4` editor is gone **and** (if the Concierge edit path also fails) there is **no working
  way to change a diagram at all** — a complete dead-end on a core "your KB is editable"
  promise. A milder break (flag accidentally ON) degrades to today's shipped, tested Code
  panel — annoying, not harmful.
- **If this leaks, the user's data/workflow is exposed via:** N/A for data leakage —
  no PII surface, no schema change. The *workflow* exposure is the inverse: a fail-OPEN gate
  (flag resolves ON when it should be OFF) would let an end user commit `.c4` changes to their
  own repo through the surface we are deliberately closing. Diagram sources are git-tracked,
  so no destructive data loss is possible (`writeC4Diagram`'s `isC4DiagramPath` scope guard
  is unchanged).
- **Brand-survival threshold:** `single-user incident` — a single user hitting a broken
  edit path with no fallback experiences a complete capability dead-end on a core surface.
  Not `aggregate pattern` (no data loss, no multi-user blast radius, git-durable source).
  Not `none` (it is a user-facing core surface, not cosmetic/internal).

`requires_cpo_signoff: true` is set in frontmatter. CPO assessed the approach at plan time
(see Domain Review) and signed off with three conditions (discoverability hint, gate both
sites + verify shared-token view, record re-enable trigger). `user-impact-reviewer` will be
invoked at review time per the review skill's conditional-agent block.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Flag registered.** `c4-edit` is a key of `RUNTIME_FLAGS` in
  `apps/web-platform/lib/feature-flags/server.ts` mapped to `FLAG_C4_EDIT`; `getFeatureFlags`
  includes `"c4-edit"` in its snapshot. Verify: a unit test asserts `"c4-edit" in (await getFeatureFlags(ANON_IDENTITY))`.
- [x] **AC2 — Constant added.** `apps/web-platform/lib/c4-constants.ts` exports
  `C4_EDIT_FLAG = "c4-edit" as const` with a doc-comment stating it gates **only** the
  user-direct edit surface (PUT route + Code panel), **not** view or Concierge.
- [x] **AC3 — Code tab absent (workspace), flag OFF.** Rendering `C4Workspace` with the
  `c4-edit` provider value `false` shows **no "Code" tab button** and never mounts
  `C4CodePanel`; the **Concierge tab is present and is the default**. With `true`, the "Code"
  tab is present. (component test in `test/c4-workspace.test.tsx`)
- [x] **AC4 — Code tab absent (inline embed), flag OFF.** Rendering `C4Diagram` with
  `c4-edit` `false` shows only the "Diagram" tab, no `C4CodePanel`. Composes correctly with
  the existing `readOnly` gate (both off ⇒ diagram-only). (test in `test/c4-diagram.test.tsx`)
- [x] **AC5 — Server PUT 403 when flag OFF (load-bearing security gate).** `PUT
  /api/kb/c4/[...path]` with an authenticated `prd` identity and `c4-edit` resolving `false`
  returns **403** with a JSON body `{ error: "<human-readable message>" }`, and
  `writeC4Diagram` is **not called**. (route test)
- [x] **AC6 — Server PUT fail-closed on Flagsmith outage.** With `FLAGSMITH_ENVIRONMENT_KEY`
  unset (or Flagsmith throwing) and `FLAG_C4_EDIT` unset/`0`, the PUT route returns **403**
  (env-fallback mirror = OFF). (route test mirroring `feature-flags-debug-mode.test.ts:54`)
- [x] **AC7 — Server PUT allowed when flag ON.** With `c4-edit` resolving `true`, the route
  proceeds to `writeC4Diagram` (mocked) and returns **200**. Proves the gate is a gate, not a wall.
- [x] **AC8 — Identity is real, not anon.** The PUT route resolves the caller's real identity
  via `resolveIdentity(createClient())` (role + orgId) and gates **after** auth, **before**
  `writeC4Diagram`. An identity-read error fails closed to `role: "prd"` ⇒ 403. (asserted in route test)
- [x] **AC9 — Concierge path independent and intact.** With `c4-edit` OFF **and**
  `c4-visualizer` ON, the Concierge `edit_c4_diagram` tool still resolves eligible and reaches
  `writeC4Diagram`. A test pins that `resolveC4FlagEnabled` resolves `c4-visualizer` (NOT
  `c4-edit`), guarding against future cross-wiring. (`test/c4-concierge-tools.test.ts` +
  `test/resolve-c4-eligible.test.ts`)
- [x] **AC10 — Discoverability hint present.** When the Code tab is hidden (flag OFF) on the
  workspace, the UI surfaces a one-line in-place hint that diagrams are editable via the
  Concierge (exact copy in §Implementation Phases). No new component/page/flow — a text
  affordance only. (component test asserts the hint text renders when flag OFF and is absent
  when flag ON.) The resulting end-user state (Code tab absent, Concierge-only right pane,
  hint present) is wireframed at
  `knowledge-base/product/design/kb-viewer/c4-viewer-no-code-panel-gated-edit.pen` (committed;
  screenshots `07-c4-workspace-no-code-panel-edit-off.png` / `08-before-removed-concierge-code-tab.png`).
- [x] **AC11 — Flag-object fixtures updated.** All TS-exhaustive `Record<FlagName, boolean>`
  fixtures carry `"c4-edit": false`: `lib/feature-flags/server.test.ts` (3 sites),
  `test/feature-flag-provider.test.tsx` (2 sites), `test/kb-layout-panels.test.tsx`.
  Verify: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] **AC12 — flip.sh map extended.** `plugins/soleur/skills/flag-set-role/scripts/flip.sh`
  `FLAG_ENV_VARS` contains `["c4-edit"]="FLAG_C4_EDIT"` so a per-role flip mirrors to Doppler.
- [x] **AC13 — `.env.example` mirror.** `apps/web-platform/.env.example` contains
  `FLAG_C4_EDIT=0` under the runtime-flags section.
- [x] **AC14 — Stale doc comment corrected.** The `C4_VISUALIZER_FLAG` comment in
  `c4-constants.ts` no longer implies it gates "the whole visualizer" including user-edit.
- [x] **AC15 — No dead-code lint.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  passes and the lint step is clean — the gated-out `onSaved`/`setStale` bindings are not left
  as unused top-level declarations (`cq-ref-removal-sweep-cleanup-closures`).
- [x] **AC16 — Re-enable trigger recorded.** A GitHub tracking issue exists naming the
  "bigger underlying problems" as the explicit `c4-edit` re-enable trigger, linked to a
  roadmap row. `Ref` it in the PR body (do not `Closes` — the capability is deferred, not done).
  The issue notes the future-canary mechanics: the flag snapshot LRU is keyed `role:orgId`
  with a 30s TTL (`feature-flags/server.ts`), so a re-enable flip propagates in ~30s at
  **org+role** granularity (not per-user, not sub-30s) — set expectations for the canary author.

### Post-merge (operator)

- [ ] **AC17 — Flag created OFF in both Doppler configs.** Run `soleur:flag-create c4-edit`
  with dev=OFF and prd=OFF. `FLAG_C4_EDIT=0` in Doppler `soleur/dev` **and** `soleur/prd`
  (the fail-closed-on-outage property depends on this mirror being `0`). Verify with
  `soleur:flag-list`. Automation: feasible via the `flag-create`/`flag-list` skills (no SSH).
- [ ] **AC18 — Redeploy note.** The Doppler `FLAG_C4_EDIT` env var is baked at container
  start; the Flagsmith flag itself propagates within ~30s (no redeploy). The `=0` Doppler
  mirror governs only the outage-fallback and must stay `0` in dev+prd until GA. A future
  dev-only canary is a **Flagsmith** flip (`soleur:flag-set-role c4-edit dev on`), live in
  ~30s, no redeploy, no Doppler change.

## Implementation Phases

> **Phase order is load-bearing:** the flag must be registered (Phase 1) before any consumer
> (client gate / route gate / fixtures) references it, or `tsc` fails. Tests are written
> RED-first within each phase per `cq-write-failing-tests-before`.

### Phase 1 — Register the `c4-edit` flag (code-wiring)

Files: `lib/feature-flags/server.ts`, `lib/c4-constants.ts`, `.env.example`.

1. `lib/feature-flags/server.ts` — append to `RUNTIME_FLAGS`:
   ```ts
   // feat-c4-viewer-remove-code-panel-gate-edit — gates ONLY the user-direct
   // C4 edit surface (PUT /api/kb/c4 + the Code panel UI). Default OFF for all
   // roles; user editing is removed pending substrate fixes, re-enabled later by
   // flipping the Flagsmith flag. Does NOT gate view (c4-visualizer) or the
   // Concierge edit tool (also c4-visualizer). Fail-closed: FLAG_C4_EDIT=0 mirror.
   "c4-edit": "FLAG_C4_EDIT",
   ```
2. `lib/c4-constants.ts` — add `export const C4_EDIT_FLAG = "c4-edit" as const;` with the
   doc-comment from AC2, and fix the `C4_VISUALIZER_FLAG` comment (AC14).
3. `.env.example` — add `FLAG_C4_EDIT=0` beside `FLAG_C4_VISUALIZER=0` (line ~149).
4. Update the 3 TS-exhaustive fixture files (AC11) so `tsc` passes:
   - `lib/feature-flags/server.test.ts` — add `"c4-edit": false` at the 3 `getFeatureFlags`
     snapshot assertions (lines ~169, ~187, ~205).
   - `test/feature-flag-provider.test.tsx` — add to the 2 `<FeatureFlagProvider flags={{…}}>` literals (lines ~13, ~22).
   - `test/kb-layout-panels.test.tsx` — add to its flags object.

### Phase 2 — Gate the server write route (the security boundary)

File: `app/api/kb/c4/[...path]/route.ts`. RED test first (`test/c4-edit-route-gate.test.ts` or extend an existing route test).

After `authenticateAndResolveKbPath` succeeds and **before** `writeC4Diagram`:
```ts
import { createClient } from "@/lib/supabase/server";          // server client
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { getRuntimeFlag } from "@/lib/feature-flags/server";
import { C4_EDIT_FLAG } from "@/lib/c4-constants";
// …after `const { ctx } = resolved;`
const identity = await resolveIdentity(await createClient()); // cache-deduped; fails closed to prd/ANON
if (!(await getRuntimeFlag(C4_EDIT_FLAG, identity))) {
  return NextResponse.json(
    { error: "Diagram editing is currently disabled. Ask the Concierge to edit this diagram." },
    { status: 403 },
  );
}
```
- Confirm the exact `createClient` import path used by other server routes (e.g. `app/api/flags/route.ts`) before pinning the import.
- Tests: AC5 (403 + writeC4Diagram not called), AC6 (outage fail-closed), AC7 (200 when ON), AC8 (real identity, prd-on-error).

### Phase 3 — Hide the Code panel in both client surfaces + discoverability hint

Files: `components/kb/c4-workspace.tsx`, `components/kb/c4-diagram.tsx`. RED component tests first.

1. `c4-workspace.tsx`:
   - Read `const c4EditEnabled = useOptionalFeatureFlag(C4_EDIT_FLAG);`
   - Remove the `["code", "Code"]` entry from the tab tuple when `!c4EditEnabled` (remove the
     **button**, not just the body — a lingering button → empty panel, SpecFlow P1-1). When
     only "concierge" remains, render no tab strip (single tab = noise).
   - Gate the whole `{rightTab === "code" && …}` block on `c4EditEnabled`. Keep `stale`/
     `setStale` and the `C4Diagnostics` banner declared (the banner stays meaningful for
     diagnostics; `stale` is simply always-false when the panel can't mount). Ensure the
     `onSaved`/`setStale` wiring lives **inside** the gated JSX branch so no unused top-level
     binding trips lint (AC15, `cq-ref-removal-sweep-cleanup-closures`).
   - **Discoverability hint (AC10):** when `!c4EditEnabled`, render a one-line muted hint in
     the right panel header or Concierge empty-state: **"To change this diagram, ask the
     Concierge."** (Text affordance only — no new component/flow.)
2. `c4-diagram.tsx`:
   - Read `c4EditEnabled`. Drop `"code"` from the `["diagram","code"]` tab map when
     `!c4EditEnabled` (in addition to the existing `readOnly` gate — they compose: code tab
     shows only when `!readOnly && c4EditEnabled`). Gate the `{!readOnly && tab === "code" && …}`
     block to also require `c4EditEnabled`.

### Phase 4 — Concierge-independence guard + flip.sh + tests sweep

Files: `test/c4-concierge-tools.test.ts`, `test/resolve-c4-eligible.test.ts`,
`plugins/soleur/skills/flag-set-role/scripts/flip.sh`, and the existing C4 test files.

1. Add `["c4-edit"]="FLAG_C4_EDIT"` to `flip.sh` `FLAG_ENV_VARS` (lines ~54–59) — AC12.
2. AC9 tests: assert (a) Concierge eligibility uses `c4-visualizer` only; (b) with `c4-edit`
   OFF + `c4-visualizer` ON, `edit_c4_diagram` still reaches `writeC4Diagram`.
3. Sweep `test/c4-code-panel.test.tsx` — these tests exercise `C4CodePanel` directly (mount
   the component, not via the flag-gated parent), so they remain valid as the component is
   preserved. Confirm they still pass unchanged (the component is gated at the parent, not deleted).
4. Run the full `tsc --noEmit` + the C4 + feature-flags test set.

### Phase 5 — Tracking issue + docs

1. File the re-enable tracking issue (AC16): title names the "bigger underlying problems",
   body records the re-enable trigger + a `knowledge-base/product/roadmap.md` row. `Ref #N` in
   the PR body.
2. Verify no stale operator-facing docs reference a user-facing C4 code editor that this
   change contradicts (`knowledge-base/engineering/architecture/diagrams/README.md`,
   `ADR-050`). Update only if they assert end-user editing as a current feature; the
   re-render/CLI mechanics are unaffected.

## Files to Edit

**Code (apps/web-platform):**
- `lib/feature-flags/server.ts` — register `c4-edit` in `RUNTIME_FLAGS`.
- `lib/c4-constants.ts` — add `C4_EDIT_FLAG`; fix `C4_VISUALIZER_FLAG` comment.
- `app/api/kb/c4/[...path]/route.ts` — **fail-closed `c4-edit` gate (403)** — the boundary.
- `components/kb/c4-workspace.tsx` — gate Code tab (button + body) + discoverability hint.
- `components/kb/c4-diagram.tsx` — gate inline Code tab (composes with `readOnly`).
- `.env.example` — `FLAG_C4_EDIT=0`.

**Tests:**
- `lib/feature-flags/server.test.ts` — `"c4-edit": false` at 3 snapshot sites (+ optional `c4-edit` membership assertion).
- `test/feature-flag-provider.test.tsx` — `"c4-edit": false` at 2 sites.
- `test/kb-layout-panels.test.tsx` — `"c4-edit": false` in its flags object.
- `test/c4-workspace.test.tsx` — AC3 (tab absent/present by flag) + AC10 (hint).
- `test/c4-diagram.test.tsx` — AC4 (inline tab absent by flag, composes with readOnly).
- `test/c4-edit-route-gate.test.ts` (new) — AC5/AC6/AC7/AC8 route-gate tests.
- `test/c4-concierge-tools.test.ts` — AC9 (Concierge path intact with c4-edit OFF).
- `test/resolve-c4-eligible.test.ts` — AC9 (resolveC4FlagEnabled pins c4-visualizer, not c4-edit).

**Skill plumbing:**
- `plugins/soleur/skills/flag-set-role/scripts/flip.sh` — `FLAG_ENV_VARS` `c4-edit` entry.

**Explicitly NOT edited (verified — preserve as-is):**
- `server/c4-writer.ts` (`writeC4Diagram` shared write path + `isC4DiagramPath` scope guard).
- `server/c4-concierge-tools.ts` (`edit_c4_diagram` tool).
- `server/resolve-c4-eligible.ts`, `server/cc-dispatcher.ts` (Concierge eligibility on `c4-visualizer`).
- `components/kb/c4-shared.tsx` `C4CodePanel` component body, `c4-code-syntax.ts` (kept for re-add; just not mounted when flag OFF).
- `app/api/kb/c4/project/route.ts`, `app/api/shared/[token]/c4/route.ts` (GET read paths — do NOT add the edit gate here).

## Files to Create

- `apps/web-platform/test/c4-edit-route-gate.test.ts` — server route-gate tests (or fold into an existing route test if one covers the PUT path).

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (63 issues); none reference
`c4-workspace`, `c4-shared`, `c4-diagram`, `c4-writer`, `api/kb/c4`, `feature-flags/server`,
or `c4-concierge`.

## Observability

```yaml
liveness_signal:
  what: "PUT /api/kb/c4/[...path] returns 200 only when c4-edit ON; 403 when OFF. Concierge edit_c4_diagram (on c4-visualizer) continues to emit the existing c4_write logger.info on success."
  cadence: per-request (event-driven, not polled)
  alert_target: none (the 403 is an EXPECTED deny while the flag is globally OFF — alerting on it would be noise)
  configured_in: "apps/web-platform/app/api/kb/c4/[...path]/route.ts (gate) + apps/web-platform/server/c4-writer.ts:138 (existing c4_write info log, Concierge path)"
error_reporting:
  destination: "Sentry via existing writeC4Diagram captureException paths (Concierge path, unchanged). The c4-edit 403 is NOT mirrored to Sentry — expected deny."
  fail_loud: "Yes for genuine write failures (writeC4Diagram already captures). The gate deny is a quiet, structured info log, not an error."
failure_modes:
  - mode: "Gate fails OPEN (flag resolves ON when it should be OFF)"
    detection: "Route test AC6 (Flagsmith-outage ⇒ 403) + AC5 (flag-false ⇒ 403). soleur:flag-list drift check confirms Doppler FLAG_C4_EDIT=0 in dev+prd."
    alert_route: "CI test failure (pre-merge); flag-list drift report (post-merge)"
  - mode: "Concierge edit path accidentally gated by c4-edit (cross-wiring)"
    detection: "AC9 test pins resolveC4FlagEnabled to c4-visualizer; AC9 asserts Concierge writes with c4-edit OFF."
    alert_route: "CI test failure (pre-merge)"
  - mode: "Stale client still issues PUTs after removal (old JS)"
    detection: "Optional info-level logger event c4_edit_gate_denied (pseudonymized userId via renameUserIdToHash, mirroring the c4_write pattern) — no alert, used to confirm real traffic reaches the gate during a future canary."
    alert_route: none (diagnostic only)
logs:
  where: "pino structured logs (Better Stack pipeline). Existing c4_write info log for successful Concierge writes; optional c4_edit_gate_denied info log for denied PUTs."
  retention: "per existing Better Stack retention (unchanged)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-edit-route-gate.test.ts test/c4-workspace.test.tsx test/c4-diagram.test.tsx test/c4-concierge-tools.test.ts"
  expected_output: "PUT returns 403 with flag OFF and 200 with flag ON; Code tab absent with flag OFF; Concierge edit_c4_diagram still reaches writeC4Diagram with c4-edit OFF + c4-visualizer ON. (NO ssh — pure test-suite verification of the gate invariant.)"
```

## Domain Review

**Domains relevant:** Product, Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two-flag model is coherent and non-overlapping; the Concierge path reads
`c4-visualizer` exclusively and cannot be gated by `c4-edit`. Gating the single PUT route is
the correct and sufficient server boundary (exactly two `writeC4Diagram` callers; the other
two C4 routes are GET-only). Env-fallback `FLAG_C4_EDIT=0` makes the gate fail-closed on a
Flagsmith outage. **P1:** the PUT handler has no identity in `ctx` today — it must call
`createClient()` + `resolveIdentity` (cache-deduped, fails closed to `prd`) and gate after
auth / before `writeC4Diagram`; prefer `resolveIdentity` over a bare `users.role` read so a
future org/dev canary needs no code change. **P2s:** add a test pinning the Concierge flag to
`c4-visualizer`; keep gated-out `onSaved`/`setStale` inside the JSX branch to avoid unused-
binding lint; verify the `flip.sh` map gets the `c4-edit` entry; update the stale
`C4_VISUALIZER_FLAG` comment. No P0, no migration/data/infra risk, no new ADR required (flag-
gated removal of an existing surface). Doppler redeploy caveat folded into AC18.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override fired — Files to Edit include
`components/kb/c4-workspace.tsx` + `components/kb/c4-diagram.tsx`)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** none — copywriter: none recommended
**Pencil available:** yes (Tier-0 headless CLI; Node 24.15.0). Wireframe committed at
`knowledge-base/product/design/kb-viewer/c4-viewer-no-code-panel-gated-edit.pen` (deepen-plan
Phase 4.9 producer). Headless/pipeline arm — wireframe ready for async operator review; no
interactive pause.

#### Findings

**spec-flow-analyzer:** Flow is complete — with `c4-edit` OFF the right panel keeps its
primary purpose (Concierge tab, default). **P0:** the server route gate is the real boundary
(client hide is cosmetic) — encoded as Phase 2 + AC5–AC8. **P1s:** remove the Code tab BUTTON
not just body (else empty-panel dead-end) — encoded in Phase 3; the 403 body must carry a
human-readable error — encoded in Phase 2; the `c4-edit`-for-dev-cohort decision is OFF/
independent — encoded in §Overview + AC17. Dead-code (`stale`/`onSaved`) is inert-but-harmless
— **gate, don't delete** — encoded in Phase 3 + AC15. Edge cases (mid-session flip ⇒ server
403; inline embed; shared-token read-only stays read-only; scope the gate to PUT only) all
addressed.

**CPO:** Proceed. On-thesis (agent-first, Concierge-primary). Brand-survival threshold =
**`single-user incident`** (both edit paths gone ⇒ per-user dead-end) — drove the User-Brand
Impact section + `requires_cpo_signoff: true`. Three conditions, all encoded: (1) ship a
minimal in-UI discoverability hint ("ask the Concierge to edit") — AC10; (2) gate **both**
render sites + verify the shared-token view is read-only — Phase 3 + Files-NOT-edited note;
(3) record the re-enable trigger at flag-creation to avoid a zombie flag — AC16. Parity is
preserved only conditionally on the re-add actually happening (tracking issue is the guard).

**Wireframe disposition:** The change is a **removal/hiding** of an existing affordance behind
a default-OFF flag — it produces no new page/flow/component; the resulting user state
("diagram + Concierge panel, no code editor") approximates the pre-existing `readOnly` shape,
with one additive **one-line text hint** (AC10). The mechanical UI-surface override fired on
the `components/kb/*.tsx` edits, so `ux-design-lead` produced a committed wireframe at
`knowledge-base/product/design/kb-viewer/c4-viewer-no-code-panel-gated-edit.pen` (deepen-plan
Phase 4.9 producer; Tier-0 headless Pencil) documenting the AFTER state (Code tab absent,
Concierge-only right pane, hint placement) plus a BEFORE reference frame of the removed Code
tab. Plan runs in the **non-interactive one-shot pipeline**, so the headless arm applies —
the wireframe is ready for async operator review; no interactive approval pause.

## Infrastructure (IaC)

Skipped — no new infrastructure. The only "new resource" is the `FLAG_C4_EDIT` Doppler
secret in `soleur/dev` + `soleur/prd`, which is created via the **`soleur:flag-create` skill**
(the sanctioned, non-SSH mechanism that mutates Flagsmith + server.ts + .env.example + Doppler
in one step) — not via operator SSH or dashboard clicks. No server, systemd unit, cron, DNS,
TLS, or firewall change.

## GDPR / Compliance Gate

Skipped — no regulated-data surface touched. No schema, migration, `.sql`, auth-flow, or new
API route. The PUT route already exists and authenticates; this change only **restricts** it
(adds a deny gate) and does not introduce new processing, new data movement, or LLM/external-
API use on operator data. The `writeC4Diagram` scope guard and data handling are unchanged.

## Risks & Mitigations

- **Gate fails OPEN on misconfiguration.** Mitigation: env-fallback `FLAG_C4_EDIT=0` in both
  Doppler configs (AC17); AC5/AC6 tests; `soleur:flag-list` drift check post-merge.
- **Partial removal (one render site missed).** Mitigation: both sites enumerated (Phase 3,
  AC3+AC4); the inline-embed gate composes with `readOnly`.
- **Concierge path cross-wired to `c4-edit`.** Mitigation: AC9 pins `resolveC4FlagEnabled` to
  `c4-visualizer`; `c4-writer.ts`/`c4-concierge-tools.ts`/`resolve-c4-eligible.ts` explicitly
  NOT edited.
- **Zombie flag (exists, never re-enabled).** Mitigation: AC16 tracking issue + roadmap row +
  `Ref #N` (not `Closes`); flag NOT added to any per-role ON map.
- **Vendored LikeC4 DOM assumption.** N/A — this change does not target LikeC4 internal DOM
  via CSS; it gates React-owned tab JSX. (Noted because the 2026-06-04 learning warns against
  stylesheet-grep selectors; not applicable here.)

## Relevant Learnings

- `knowledge-base/project/learnings/2026-05-04-flag-boundary-creates-new-error-class-mapper-must-handle.md`
  — a flag boundary is an error-code contract; the 403 deny needs a human-readable body
  (AC5, Phase 2).
- `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md` — Doppler
  env baked at container start; Flagsmith flip is the live lever (AC18).
- `knowledge-base/project/learnings/bug-fixes/2026-06-12-c4-save-revert-stale-clone-optimistic-apply.md`
  — `C4CodePanel` optimistic-save logic is kept intact behind the flag (re-add fodder; not deleted).
- `knowledge-base/project/learnings/2026-06-15-flag-delete-doppler-message-worm-action-enum-flagsmith-reuse.md`
  — if `c4-edit` is ever deleted later, the audit action is `archive` and Flagsmith names are reusable.
- `knowledge-base/project/learnings/2026-06-04-vendored-library-css-hook-must-be-verified-against-rendered-dom-not-stylesheet.md`
  — not applicable (no CSS-selector targeting of LikeC4 internals), noted to scope it out.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan fills it — threshold
  `single-user incident`.)
- The PUT handler has **no identity in `ctx`** — `resolveIdentity(await createClient())` must be
  called in the handler (cache-deduped). Do not assume `ctx.userData` carries a role.
- Adding `c4-edit` to `RUNTIME_FLAGS` is a **breaking compile change** for every TS-exhaustive
  `Record<FlagName, boolean>` fixture — update all 3 fixture files (5 literal sites) in the
  same change or `tsc --noEmit` fails (AC11).
- Remove the Code tab **button**, not just its body — a lingering button lands the user on an
  empty panel.
- Typecheck/test for `apps/web-platform`: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  and `./node_modules/.bin/vitest run <path>` — NOT `npm run -w` (no root `workspaces` field) and
  NOT bare `bun test`.
- Gate **only** the PUT route — do NOT add the `c4-edit` gate to the GET `project` or
  `shared/[token]` read routes.
