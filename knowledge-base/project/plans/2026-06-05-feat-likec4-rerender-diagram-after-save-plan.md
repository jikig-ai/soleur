---
title: "feat: LikeC4 Layer 2 — regenerate rendered diagram after .c4 Save"
type: feat
date: 2026-06-05
branch: feat-one-shot-likec4-rerender-on-save
closes: 4964
follows: 4963
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
mechanism: primary (in-process server-side `likec4` CLI spawn; Inngest fallback NOT needed — feasibility gate PASSED)
likec4_cli_pin: "1.50.0"
---

# feat: LikeC4 Layer 2 — actually re-render the diagram after a Code-tab Save 🛠️✨

## Enhancement Summary

**Deepened on:** 2026-06-05
**Sections enhanced:** mechanism (CLI version pin), spawn helper API, observability call form, precedent diff.

### Key Improvements (deepen pass)
1. **CLI version pin resolved to `likec4@1.50.0`** (NOT `@latest`/1.57.0). Verified: the
   client renderer is `@likec4/core` + `@likec4/diagram` at **1.50.0**; the CLI must
   match that major.minor so the `export json` schema is exactly what `LikeC4Model.create`
   consumes. `likec4@1.57.0` emits a richer schema (extra `globals`/`imports`/`manualLayouts`
   keys) — pinning the CLI to 1.50.0 eliminates cross-version drift. `likec4@1.50.0` exists
   as a standalone CLI package (`npm view likec4@1.50.0 version` → `1.50.0`) and exports the
   real prod model headless (no native graphviz) in ~0.8s, exit 0. (AC8)
2. **`reportSilentFallback` API corrected.** Canonical form is
   `reportSilentFallback(err, { feature, op, extra, message })` — `feature` is REQUIRED and
   `err` is positional (verified `server/observability.ts:183` + call sites in
   `workspace-reconcile-on-push.ts:174,266,298`). The earlier `{message:...}`-only shape was
   wrong; corrected throughout.
3. **Precedent-diff confirmed** for the spawn helper against `server/pdf-linearize.ts`
   (bounded timeout → SIGKILL, scoped env, settle-once, concurrency gate, reason-typed result).
4. **Verify-the-negative pass** on the command-injection claim: `renderC4Model(workspacePath)`
   takes only `workspacePath`; user-controlled `relativePath` never enters the spawn argv
   (it stays in `writeC4Diagram` for the GitHub commit, gated by `isC4DiagramPath`). Confirmed.

### New Considerations Discovered
- The GET route reads `*.c4` sources via `f.endsWith(C4_SOURCE_EXT)` (`route.ts:112-113`),
  so `model.likec4.json` is NOT double-read as a source — no conflict with regenerating it.
- `likec4@1.50.0` CLI reports `views: 42` (includes auto-derived element views) vs the 4
  named views — both render; not a concern, just a CLI-version output detail.

## Overview

Layer 1 (#4963, merged 2026-06-05) made the LikeC4 Code-tab Save **honest**: a saved
`.c4` edit commits the source but the rendered diagram stays stale, and an amber
staleness banner says so. Layer 2 (this plan, **Closes #4964**) makes the diagram
**actually update**: after the `.c4` source is committed + synced, regenerate the
precomputed `model.likec4.json` out-of-process via the `likec4` CLI, commit the
regenerated JSON through the same GitHub Contents API path, re-sync, and let the
existing `reload()` surface the fresh dump. The staleness banner then only appears
when the re-render **fails or is skipped** — not on every save.

**Mechanism decision (feasibility gate PASSED — primary chosen, Inngest fallback NOT needed).**
The recommended primary mechanism is feasible and chosen. Evidence (verified at plan time,
2026-06-05):

1. **`likec4 export json` runs headless with no native graphviz.** Ran
   `npx -y likec4@latest export json` against the **real prod model** (`spec.c4` +
   `model.c4` + `views.c4`, 40 elements / 4 views) on a clean tmp dir with **no `dot`
   binary on PATH**. Exit 0 in **522ms**; log line `INFO likec4.lang layout wasm`
   confirms LikeC4 v1.x lays out via **graphviz-wasm** (bundled in the npm package),
   not a native binary. Output `model.likec4.json` parsed cleanly with `_stage:
   "layouted"`, `views: 4`, `elements: 40` — the exact shape the GET route reads as
   `dump` and `C4Canvas` renders via `LikeC4Model.create`.
2. **The web container can execute the CLI in the right process.** `writeC4Diagram`
   runs in the **Next.js / custom server process**, NOT the bwrap agent sandbox.
   Verified call sites: `app/api/kb/c4/[...path]/route.ts` (PUT route) and
   `server/c4-concierge-tools.ts` (Concierge MCP tool, esbuild-bundled into the custom
   server). The Dockerfile's bwrap/apt/network restrictions apply to the **Agent SDK
   sandbox shell**, not the server process. The runner image is `node:22-slim` with
   `node` present; server-side `child_process.spawn` of out-of-process binaries is
   already established precedent (`server/pdf-linearize.ts` spawns `qpdf`,
   `server/push-branch.ts`/`git-auth.ts`/`workspace.ts` spawn `git`).
3. **The diagrams dir is on disk where the CLI needs it.** `writeC4Diagram` already
   receives `workspacePath`; the synced clone lives at
   `<WORKSPACES_ROOT (=/workspaces)>/<workspace_id>/knowledge-base/<C4_DIAGRAMS_DIR>`.
   After `syncWorkspace`, the freshly-committed `.c4` is on disk; the CLI exports the
   JSON in place; we commit + re-sync the JSON.

**Lockfile-parity constraint preserved.** The `likec4` CLI is **preinstalled in the
web-platform Docker runner image** (a Dockerfile change), NOT added to
`apps/web-platform/package.json`. Only `@likec4/core` + `@likec4/diagram` stay as deps
(client render). The CLI is invoked out-of-process by absolute path — never imported —
so vite/esbuild/bundle-require never enter prod deps and npm10/npm11 `npm ci` +
`lockfile-sync` parity is untouched (the exact constraint documented in
`lib/c4-constants.ts` and `app/api/kb/c4/project/route.ts`).

## Research Reconciliation — Spec vs. Codebase

| Investigation claim | Reality (verified 2026-06-05) | Plan response |
| --- | --- | --- |
| `model.likec4.json` (`C4_MODEL_JSON`) read by GET route as `dump` from synced clone | ✅ Confirmed `app/api/kb/c4/project/route.ts:63-83` reads `model.likec4.json` via O_NOFOLLOW fd; `MODEL_NOT_BUILT` 404 when absent | Re-render writes this file; no GET-route change needed |
| Generated by `npx -y likec4@latest export json -o model.likec4.json .` | ✅ `plugins/soleur/skills/architecture/SKILL.md` render sub-command; verified it works headless on real model | Reuse the exact command; preinstall CLI to avoid per-save npx cold-fetch |
| Only `@likec4/core` + `@likec4/diagram` installed — re-layout must run CLI out-of-process | ✅ `apps/web-platform/package.json:29-30` exactly these two at `1.50.0`; no parser/layout engine | Preinstall CLI in Dockerfile (NOT package.json); spawn by absolute path |
| Both write surfaces funnel through `writeC4Diagram()` | ✅ PUT route + Concierge tool both call it; scope guard `isC4DiagramPath` enforced once | Add re-render inside `writeC4Diagram` (or an adjacent helper it calls) → both surfaces covered for free |
| UI consumers already call `reload()` after save via `onSaved` | ✅ `c4-workspace.tsx:190`, `c4-diagram.tsx:79` both `setStale(true); await reload()` | Flip: `reload()` first, then set `stale` ONLY if server reports re-render failed |
| Layer-1 `stale` flag is a per-session React state set on every save | ✅ `useState(false)` in both components; banner copy in `c4-shared.tsx:165` | Re-key on server response: stale = re-render did NOT succeed |
| Concierge tool prompt claims "you cannot trigger re-render" | ✅ `c4-concierge-tools.ts:55-59` + tool description say the diagram only refreshes out-of-band | Update copy per the #4963 honesty-sweep learning (tool desc + prompt addendum) — re-render now happens |
| ADR-033 child-process-spawn precedent / `infra/inngest.tf` exist (fallback) | ✅ Both exist | **Fallback NOT used** — primary feasible; documented as the rejected option |

## User-Brand Impact

**If this lands broken, the user experiences:** they edit a `.c4` source in the Code
tab, hit Save, and either (a) the diagram silently shows stale geometry while claiming
it re-rendered (regression of Layer-1 honesty), or (b) the Save itself hangs/errors
because the re-render blew the latency budget or crashed the spawn — turning a working
"commit + honest banner" flow into a broken one.

**If this leaks, the user's data / workflow is exposed via:** the re-render spawns a CLI
against an **on-disk path** under the user's workspace clone. A path-scope bug
(diagrams-dir guard bypass) could let the spawned process read/write outside the
diagrams dir; a command-injection bug could run arbitrary args. Mitigated by:
`isC4DiagramPath` already gates the write; the spawn uses **fixed argv + a path derived
from `workspacePath` + the constant `C4_DIAGRAMS_DIR`** (never user-controlled
filenames in argv), scoped env, and a bounded timeout.

**Brand-survival threshold:** `aggregate pattern`. The C4 visualizer is dev-cohort-gated
(`c4-visualizer` flag, dev cohort only — see MEMORY); a single failed re-render
degrades to the existing honest-stale banner (Layer-1 already shipped), not a data
incident. No new regulated-data surface; no PII; operator/dev-only exposure. Threshold
does NOT reach `single-user incident` → no CPO sign-off gate, but `## Domain Review`
still runs.

## Problem

`writeC4Diagram` commits the `.c4` and re-syncs the clone, but `model.likec4.json` is
**never regenerated at runtime** — it is only rebuilt out-of-band via
`/soleur:architecture render`. So a Code-tab Save leaves the rendered diagram showing
the OLD layout until someone manually re-renders and commits. Layer 1 made this honest;
Layer 2 makes it actually update.

## Approach

Add an out-of-process re-render step to the write path, integrated so it covers **both**
write surfaces and degrades gracefully.

### Server: new `server/c4-render.ts` (spawn helper, modeled on `pdf-linearize.ts`)

A single, well-tested module that spawns the `likec4` CLI:

```ts
// apps/web-platform/server/c4-render.ts  (NEW)
import { spawn } from "node:child_process";
import { join } from "node:path";
import { C4_DIAGRAMS_DIR, C4_MODEL_JSON } from "@/lib/c4-constants";

export type RenderReason = "spawn_error" | "non_zero_exit" | "timeout" | "io_error";
export type RenderResult =
  | { ok: true; durationMs: number }
  | { ok: false; reason: RenderReason; detail?: string };

const RENDER_TIMEOUT_MS = 25_000; // bound; real model exports in <1s, headroom for cold start
const LIKEC4_BIN = process.env.LIKEC4_BIN || "likec4"; // preinstalled in the runner image

/**
 * Regenerate `model.likec4.json` in place under the workspace's diagrams dir by
 * spawning the preinstalled `likec4` CLI. Fixed argv; the only path passed is the
 * scope-guarded diagrams dir derived from `workspacePath` + the C4_DIAGRAMS_DIR
 * constant (never a user-controlled filename), so there is no command-injection or
 * scope-escape surface. Settle-once promise, bounded timeout, scoped env — mirrors
 * server/pdf-linearize.ts.
 */
export async function renderC4Model(workspacePath: string): Promise<RenderResult> {
  const diagramsDir = join(workspacePath, "knowledge-base", C4_DIAGRAMS_DIR);
  // spawn(LIKEC4_BIN, ["export", "json", "-o", C4_MODEL_JSON, "."], { cwd: diagramsDir, ... })
  //   - stdio: ["ignore","ignore","pipe"]; capture stderr (sanitized, truncated) for non_zero_exit
  //   - setTimeout(RENDER_TIMEOUT_MS) → child.kill("SIGKILL") → reason:"timeout"
  //   - scoped env { PATH, LANG, LC_ALL, HOME, TMPDIR } only
  //   - settle-once guard (see pdf-linearize runQpdf)
}
```

`-o model.likec4.json .` writes the JSON **into the cwd (diagrams dir)**, which is
exactly where the GET route reads it from on disk and where it must be committed.

### Server: wire re-render into `writeC4Diagram` (single integration point → both surfaces)

After the existing commit + `syncWorkspace` succeed, and **only when the written file
is a `.c4` source** (skip for `.md` view-embed saves — those don't change layout):

1. `renderC4Model(workspacePath)` → regenerate `<diagramsDir>/model.likec4.json` on disk.
2. On success: read the regenerated JSON, commit it via the **same GitHub Contents API
   path** (`githubApiGet` for the existing blob sha → `githubApiPost` PUT to
   `.../contents/.../diagrams/model.likec4.json`), then `syncWorkspace` again so the
   committed JSON and the on-disk clone match (and survive the next reconcile/GC).
3. Return a new field on `WriteC4Result`: `rerendered: boolean` (true on full success;
   false on any re-render/commit/sync failure — the `.c4` commit already succeeded, so
   we never fail the whole save just because re-render failed).

```ts
// WriteC4Result success shape (extended)
| { ok: true; commitSha: string | null; rerendered: boolean }
```

**Failure isolation (critical, no .c4-path regression):** the `.c4` commit + first
sync are the load-bearing success. The re-render is best-effort: wrap it in its own
try/catch and on any failure call `reportSilentFallback` (canonical form — `feature`
required, `err` positional; verified `server/observability.ts:183` + call sites):

```ts
reportSilentFallback(renderErr, {
  feature: "c4-rerender",
  op: "render" /* or "commit-json" | "resync" */,
  extra: { userIdHash, workspacePath, relativePath },
  message: "c4 re-render failed — source committed, diagram stale",
});
// then: return { ok: true, rerendered: false }
```

(`reportSilentFallback` already mirrors to Sentry internally, so a separate
`Sentry.captureException` is redundant — match the `workspace-reconcile-on-push.ts`
pattern.) The user still gets the committed source + the honest stale banner — exactly
the Layer-1 behavior — so a re-render bug can never make the save *worse* than today.

**Latency:** real-model export is <1s; `RENDER_TIMEOUT_MS = 25_000` is a ceiling for a
cold first invocation. Add `export const maxDuration = 60;` to the PUT route
(`app/api/kb/c4/[...path]/route.ts`) so commit + sync + render + commit + sync fits the
serverless wall clock (Next default is short). A small in-module concurrency gate
(POOL_SIZE 1–2, env `C4_RENDER_CONCURRENCY`, mirroring `pdf-linearize.ts`) caps peak
RAM from concurrent wasm-layout subprocesses.

### Dockerfile: preinstall the `likec4` CLI in the runner image

Add to `apps/web-platform/Dockerfile` runner stage, alongside the existing
`npm install -g @anthropic-ai/claude-code@<pin>` precedent (a global install that is
NOT a package.json dep — exactly the pattern that preserves lockfile parity):

```dockerfile
# LikeC4 CLI for runtime diagram re-render after Code-tab Save (#4964).
# Global install (NOT a package.json dep) — preserves npm10/npm11 lockfile-sync
# parity (lib/c4-constants.ts), same pattern as `npm install -g @anthropic-ai/claude-code`.
# Pinned to 1.50.0 to MATCH the client renderer @likec4/core/@likec4/diagram@1.50.0
# (package.json:29-30) so `export json` emits the exact schema LikeC4Model.create reads.
# Lays out via bundled graphviz-wasm; no native dot binary needed (verified 2026-06-05:
# `likec4@1.50.0 export json` exits 0 with no `dot` on PATH, real model in ~0.8s).
RUN npm install -g likec4@1.50.0
```

**Version pin is `1.50.0` (NOT `@latest`).** Resolved at deepen-plan time:
`npm view likec4 dist-tags` → `latest: 1.57.0`, but the installed client is `1.50.0` and
`likec4@1.57.0` emits extra schema keys (`globals`/`imports`/`manualLayouts`). Matching the
CLI to the client major.minor (`1.50.0` — confirmed to exist as a standalone CLI package)
eliminates cross-version drift. Bump the CLI pin together with the `@likec4/*` client deps
in future upgrades. The global bin lands at `/usr/local/bin/likec4`; `LIKEC4_BIN` env
override exists for tests only (default PATH resolution works in the image).

### UI: flip `stale` to mean "re-render did NOT succeed"

The PUT response and the GET `dump` are the two signals. Cleanest wiring:

- **PUT route** returns `{ commitSha, rerendered }` (plumb the new field through).
- **`C4CodePanel.save`** (`c4-shared.tsx`): on a `.c4` save, read `rerendered` from the
  response; pass it to `onSaved(rerendered)` (widen `onSaved` to
  `(rerendered: boolean) => void | Promise<void>`).
- **`c4-workspace.tsx` / `c4-diagram.tsx`** `onSaved` handler: `await reload()` FIRST
  (pull the fresh `dump`), then `setStale(!rerendered)` — stale banner shows only when
  the server could not re-render. On success, banner stays hidden and the reloaded
  `dump` is the fresh geometry.
- **Save-in-progress copy:** while saving, the existing `saveMsg` shows an honest
  "Saving…" → on success with `rerendered:true` show "Saved — diagram updated."; with
  `rerendered:false` show "Saved — diagram will update after re-render." (reuse the
  Layer-1 copy infra; no new toast/modal). Optionally show "Rendering…" between PUT
  return and `reload()` completion.

### Copy: update the Concierge tool prompt/description (honesty sweep)

Per the #4963 learning (`2026-06-05-llm-facing-claim-correction-must-sweep-tool-desc-and-prompt-addendum.md`),
LLM-facing claims live in BOTH the tool `description` and the prompt addendum. Update
`c4-concierge-tools.ts:55-59` (+ any prompt addendum that mirrors it): the diagram now
**does** re-render after `edit_c4_diagram` succeeds; tell the user it updated (or that
it stayed stale if the re-render failed). Grep the whole c4 surface for the old
"out-of-band" / "you cannot trigger" copy and sweep all occurrences.

## Files to Edit

- `apps/web-platform/server/c4-writer.ts` — call `renderC4Model` after commit+sync (only for `.c4` saves); commit the regenerated JSON via the same Contents API path; re-sync; add `rerendered` to the success result; failure-isolate (Sentry + `reportSilentFallback`, never fail the `.c4` save).
- `apps/web-platform/app/api/kb/c4/[...path]/route.ts` — plumb `rerendered` into the JSON response; add `export const maxDuration = 60;`.
- `apps/web-platform/server/c4-concierge-tools.ts` — propagate `rerendered` in the tool's text response; **update the honesty copy** (tool description + the "out-of-band / you cannot trigger" prompt lines).
- `apps/web-platform/components/kb/c4-shared.tsx` — `C4CodePanel.save` reads `rerendered`, widens `onSaved(rerendered)`, updates `saveMsg` copy; `C4Diagnostics` banner unchanged (only its trigger changes).
- `apps/web-platform/components/kb/c4-workspace.tsx` — `onSaved` handler: `reload()` then `setStale(!rerendered)`.
- `apps/web-platform/components/kb/c4-diagram.tsx` — same `onSaved` re-key.
- `apps/web-platform/Dockerfile` — `RUN npm install -g likec4@1.50.0` in the runner stage (with the no-native-graphviz / lockfile-parity comment).
- `apps/web-platform/lib/c4-constants.ts` — (optional) update the `C4_MODEL_JSON` doc comment: it is now regenerated at runtime on the write path (no longer "never at runtime").
- `apps/web-platform/app/api/kb/c4/project/route.ts` — (optional) update the GET route doc comment that says the model is rebuilt "out-of-band only".
- Any prompt-addendum file that mirrors the Concierge honesty copy (grep result from the sweep above).

## Files to Create

- `apps/web-platform/server/c4-render.ts` — the `renderC4Model` spawn helper (modeled on `pdf-linearize.ts`: bounded timeout, scoped env, settle-once, concurrency gate, reason-typed result).
- `apps/web-platform/test/c4-render.test.ts` — unit tests for `renderC4Model` (spawn mocked): success → `{ok:true}`; non-zero exit → `non_zero_exit` with sanitized stderr; timeout → SIGKILL + `timeout`; spawn ENOENT → `spawn_error`; fixed-argv assertion (no user input in argv); cwd = scope-guarded diagrams dir.
- `apps/web-platform/test/c4-writer-rerender.test.ts` — `writeC4Diagram` integration (GitHub API + sync + render mocked): `.c4` save triggers render + JSON commit + re-sync, returns `rerendered:true`; render failure returns `{ok:true, rerendered:false}` and the `.c4` commit still succeeds (no regression); `.md` save does NOT trigger render; OUT_OF_SCOPE / 413 / SHA_MISMATCH paths unchanged.
- (Extend, not create) `apps/web-platform/test/c4-code-panel.test.tsx` / `c4-workspace.test.tsx` / `c4-diagram.test.tsx` — `rerendered:true` → banner hidden after reload; `rerendered:false` → banner shown; save copy reflects state.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Re-render on `.c4` save.** A `.c4` save through `writeC4Diagram` (both the PUT route and the Concierge tool) regenerates `model.likec4.json` via the spawned CLI, commits it via the same GitHub Contents API path, and re-syncs. Asserted by `c4-writer-rerender.test.ts` (render + GitHub API + sync mocked): render called with cwd = `<workspacePath>/knowledge-base/engineering/architecture/diagrams`, then a second `githubApiPost` PUT to `.../contents/.../diagrams/model.likec4.json`, then a second `syncWorkspace`.
- [ ] **AC2 — No `.c4`-path regression on render failure.** When `renderC4Model` returns `{ok:false}` (or the JSON commit/sync fails), `writeC4Diagram` still returns `{ok:true, rerendered:false}`, the `.c4` commit is NOT rolled back, and `Sentry.captureException` + `reportSilentFallback({message:"c4 re-render failed"})` fire. Asserted in `c4-writer-rerender.test.ts`.
- [ ] **AC3 — `.md` saves skip render.** A `.md` view-embed save does NOT spawn the CLI (layout unchanged). Asserted in `c4-writer-rerender.test.ts`.
- [ ] **AC4 — Spawn helper is safe + bounded.** `c4-render.test.ts` asserts: fixed argv `["export","json","-o","model.likec4.json","."]` (no user-controlled tokens), cwd is the scope-guarded diagrams dir, `RENDER_TIMEOUT_MS` → SIGKILL → `reason:"timeout"`, ENOENT → `spawn_error`, non-zero exit → sanitized+truncated stderr in `detail`.
- [ ] **AC5 — Stale banner re-keyed.** UI tests: `onSaved(rerendered:true)` → after `reload()` the `C4Diagnostics` stale strip is NOT rendered; `onSaved(rerendered:false)` → stale strip IS rendered. Asserted in `c4-workspace.test.tsx` + `c4-diagram.test.tsx` (or `c4-code-panel.test.tsx`).
- [ ] **AC6 — Honesty copy swept.** `grep` over the c4 surface (`apps/web-platform/server/c4-concierge-tools.ts` + any prompt-addendum file) confirms NO remaining "you cannot trigger" / "only ... out-of-band" claim about re-render reachability; the existing `c4-prompt-addendum-honesty.test.ts` is updated to assert the new (re-render-happens) copy.
- [ ] **AC7 — Lockfile parity untouched.** `apps/web-platform/package.json` + `package-lock.json` are unchanged except (if any) the two existing `@likec4/*` deps; `likec4` is NOT added as a dep. `npm ci` + `lockfile-sync` CI gate passes. The CLI appears ONLY in `Dockerfile` (`npm install -g likec4@1.50.0`).
- [ ] **AC8 — Dockerfile pin is `likec4@1.50.0` (matches client, NOT `@latest`).** The `RUN npm install -g likec4@1.50.0` uses the concrete version matching `@likec4/core`/`@likec4/diagram@1.50.0`, with the no-native-graphviz + lockfile-parity + version-match comment. (Resolved at deepen-plan: `latest` is 1.57.0 but emits a drifted schema; 1.50.0 CLI exists and matches the renderer.)
- [ ] **AC9 — Latency budget.** PUT route sets `export const maxDuration = 60;`; concurrency gate caps concurrent renders (env `C4_RENDER_CONCURRENCY`, default ≤2).
- [ ] **AC10 — Tests + types green.** `./node_modules/.bin/vitest run apps/web-platform/test/c4-render.test.ts apps/web-platform/test/c4-writer-rerender.test.ts <ui tests>` pass; `tsc --noEmit` clean (new `rerendered` field + widened `onSaved`).

### Post-merge (operator / CI)

- [ ] **AC11 — Image builds with the CLI.** `web-platform-release.yml` builds the runner image; the `npm install -g likec4` layer succeeds. (Automated by the existing release pipeline on merge to main touching `apps/web-platform/**` — the merge IS the deploy; no separate operator step.)
- [ ] **AC12 — End-to-end re-render verified post-deploy.** After deploy, a dev-cohort user edits a `.c4` in the Code tab, Saves, and the diagram visibly updates without a manual `/soleur:architecture render`. Verify via Playwright MCP against the dev-gated page (`c4-visualizer` flag is dev-cohort) — automate up to the rendered-diff assertion. Closes #4964.

## Test Scenarios

1. **Happy path:** edit `model.c4` (add an element), Save → JSON regenerated, committed, synced; `reload()` shows the new element; no stale banner; copy says "diagram updated."
2. **Render failure (CLI missing/crash):** `renderC4Model` → `spawn_error`/`non_zero_exit` → `.c4` still committed, `rerendered:false`, Sentry + silent-fallback fire, stale banner shows (Layer-1 fallback intact).
3. **Render timeout:** pathological/huge model exceeds `RENDER_TIMEOUT_MS` → SIGKILL, `rerendered:false`, stale banner.
4. **`.md` save:** no spawn, no second commit; behaves as today.
5. **Invalid `.c4` (parse error) saved:** `likec4 export` may exit non-zero → `rerendered:false` + stale banner + (existing) diagnostics surface the parse error.
6. **Concierge `edit_c4_diagram`:** same re-render fires (shared `writeC4Diagram`); tool response carries `rerendered`; honesty copy reflects it.
7. **Concurrent saves:** concurrency gate serializes renders; no RAM blowup.

## Risks & Mitigations

- **Latency on the save path (multi-second).** Real model <1s; ceiling 25s; PUT `maxDuration=60`. Render is best-effort and isolated — a slow render degrades to the honest banner, never a failed save. *Mitigation in AC2/AC9.*
- **Command injection / scope escape via spawn.** Fixed argv; the only path is the
  constant-derived diagrams dir; user-controlled `relativePath` never enters argv and is
  already gated by `isC4DiagramPath` before any write. Scoped env. *AC4.*
- **Lockfile-parity regression** if `likec4` sneaks into package.json. Hard-blocked by
  AC7 + the existing `lockfile-sync` CI gate; CLI lives only in the Dockerfile. Precedent: `npm install -g @anthropic-ai/claude-code` already does exactly this.
- **graphviz-wasm absent at runtime.** It is bundled in the `likec4` npm package (the
  feasibility run used no native `dot`); the global install ships it. *AC8/AC11.*
- **Double-commit churn** (`.c4` then `model.likec4.json` = two commits per save). Acceptable; mirrors the manual `/soleur:architecture render` workflow which also commits the JSON alongside `.c4`. Could be folded into one commit later (Non-Goal).
- **Workspace reconcile/GC racing the JSON commit.** Committing the JSON to GitHub +
  re-syncing (not just leaving it on disk) ensures it survives the next reconcile/GC —
  same durability story as the `.c4` source.

### Precedent diff — spawn helper vs `server/pdf-linearize.ts`

`renderC4Model` follows the established server-side-spawn precedent verbatim (verified at
deepen-plan). Side-by-side:

| Concern | `pdf-linearize.ts` (precedent) | `c4-render.ts` (this plan) |
| --- | --- | --- |
| Spawn | `spawn("qpdf", [fixed argv], {env, stdio})` | `spawn("likec4", ["export","json","-o",C4_MODEL_JSON,"."], {cwd, env, stdio})` |
| Timeout | `setTimeout(TIMEOUT_MS)` → `child.kill("SIGKILL")` → `reason:"timeout"` | same; `RENDER_TIMEOUT_MS=25_000` |
| Scoped env | `{PATH,LANG,LC_ALL,TMPDIR}` only | `{PATH,LANG,LC_ALL,HOME,TMPDIR}` (HOME needed for npm-global bin resolution) |
| Settle-once | `settle()` guard on `settled` bool | same |
| Concurrency gate | `acquire()/release()` POOL_SIZE 2 | same; env `C4_RENDER_CONCURRENCY` default ≤2 |
| Reason-typed result | `LinearizeReason` union | `RenderReason` union (`spawn_error\|non_zero_exit\|timeout\|io_error`) |
| stderr capture | sanitized + truncated to 512 | same |

No novel pattern; the only deltas are `cwd` (qpdf uses tempfile paths, likec4 uses the
diagrams dir as cwd) and `HOME` in the env allow-list (npm-global `likec4` bin needs it).

## Non-Goals

- Single-atomic-commit of `.c4` + `model.likec4.json` (currently two commits). Deferred; file tracking issue if pursued.
- In-browser/WASM layout (would pull the heavy toolchain into client/prod deps — explicitly rejected by `lib/c4-constants.ts`).
- Re-rendering for arbitrary KB markdown or non-diagram surfaces.
- Moving re-render to Inngest (the documented fallback) — NOT needed; primary is feasible. If a future constraint (e.g., the server process must not spawn) forces it, the `workspace-reconcile-on-push.ts` Inngest function is the template and the UI would poll the GET route for the refreshed `dump`.

## Domain Review

(Filled by Phase 2.5 — Engineering/Architecture relevant; Product/UX gate ADVISORY: modifies existing Code-tab save UX, no new page/route/component file → auto-accept on pipeline path. Re-confirm at deepen-plan.)

## Observability

```yaml
liveness_signal:
  what: "c4 re-render success/failure logged on every .c4 save (logger.info event:c4_rerender ok|failed)"
  cadence: "per save (user-driven, not scheduled)"
  alert_target: "Sentry via reportSilentFallback(feature='c4-rerender') on failure"
  configured_in: "apps/web-platform/server/c4-writer.ts (re-render block) + server/c4-render.ts"
error_reporting:
  destination: "reportSilentFallback(renderErr, {feature:'c4-rerender', op, extra, message}) — mirrors to Sentry internally (server/observability.ts:183); no separate captureException needed"
  fail_loud: "true — every render/commit/sync failure on the re-render path is captured; the .c4 save still succeeds so the user is never blocked, but the failure is never swallowed silently"
failure_modes:
  - mode: "likec4 CLI missing from image (ENOENT)"
    detection: "renderC4Model → reason:spawn_error → Sentry + breadcrumb; AC11 image build assertion"
    alert_route: "Sentry issue + reportSilentFallback"
  - mode: "render timeout (pathological model)"
    detection: "RENDER_TIMEOUT_MS → SIGKILL → reason:timeout"
    alert_route: "Sentry + breadcrumb; user sees stale banner"
  - mode: "JSON commit/sync fails after render"
    detection: "githubApiPost/syncWorkspace throw → rerendered:false"
    alert_route: "Sentry + breadcrumb; user sees stale banner"
logs:
  where: "pino server logger (event:c4_write already present; add event:c4_rerender) → existing log sink"
  retention: "per existing platform log retention"
discoverability_test:
  command: "./node_modules/.bin/vitest run apps/web-platform/test/c4-render.test.ts apps/web-platform/test/c4-writer-rerender.test.ts"
  expected_output: "all tests pass; render-failure test asserts Sentry.captureException + reportSilentFallback called and result.rerendered === false"
```

## Infrastructure (IaC)

No new infrastructure. The `likec4` CLI is baked into the existing web-platform Docker
runner image (a Dockerfile layer, same class as the existing `@anthropic-ai/claude-code`
/ `gh` / Chromium preinstalls) — no new server, secret, vendor, DNS, or persistent
runtime process. The image is built + deployed by the existing `web-platform-release.yml`
pipeline on merge to main; the merge IS the deploy. Phase 2.8 gate: skipped (pure
code + image-layer change against an already-provisioned surface).

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` (2026-06-05)
and matched every Files-to-Edit path (`c4-writer.ts`, `c4-shared.tsx`, `c4-workspace.tsx`,
`c4-diagram.tsx`, `c4-concierge-tools.ts`, `Dockerfile`, `app/api/kb/c4`) against open
issue bodies — zero overlaps. No scope-out to fold in, acknowledge, or defer.

## Related Learnings

- `knowledge-base/project/learnings/best-practices/2026-06-05-llm-facing-claim-correction-must-sweep-tool-desc-and-prompt-addendum.md` — Layer-1 (#4963) learning: LLM-facing claims live in BOTH the tool `description` and the prompt addendum; sweep both when correcting the re-render-reachability copy (AC6).
