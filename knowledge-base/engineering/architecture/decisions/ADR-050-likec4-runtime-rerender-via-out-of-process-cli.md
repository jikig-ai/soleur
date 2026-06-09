# ADR-050: LikeC4 diagram re-render at runtime via out-of-process CLI spawn

- **Status:** Accepted
- **Date:** 2026-06-05
- **Deciders:** Jean (operator), CTO (architecture review)
- **Relates to:** PR #4963 (Layer 1 honesty), PR #4965 / #4964 (this change), ADR-033 (Inngest child-process-spawn precedent)

## Context

The LikeC4 C4-model visualizer renders from a **precomputed, layouted**
`model.likec4.json`. Until now that artifact was regenerated **only out-of-band**
via `/soleur:architecture render` (which runs `npx likec4 export json`). A
Code-tab Save (or the Concierge `edit_c4_diagram` tool) committed the `.c4`
source but left the rendered diagram stale.

The original posture, documented in `lib/c4-constants.ts` and
`app/api/kb/c4/project/route.ts`, was an explicit **"never render at runtime"**:
the `likec4`/`@likec4/language-services`/`@likec4/layouts` toolchain drags
vite/esbuild/bundle-require into prod deps and breaks the npm10/npm11
lockfile-sync parity that prod `npm ci` requires. Only `@likec4/core` +
`@likec4/diagram` (the client renderer) are installed.

PR #4963 (Layer 1) made the staleness honest (a banner). This change (Layer 2,
#4964) reverses the "never render at runtime" posture for the **write path
specifically**, so the diagram actually updates after a save.

## Decision

After `writeC4Diagram` commits a `.c4` source and syncs the workspace clone,
regenerate `model.likec4.json` by **spawning the `likec4` CLI out-of-process**
(`server/c4-render.ts`, modeled on `server/pdf-linearize.ts`), commit the
regenerated JSON via the same GitHub Contents API path, and re-sync. The
existing client `reload()` then surfaces the fresh `dump`.

Key constraints that make this NOT a reversal of the lockfile-parity rule:

1. **The CLI is spawned, never imported.** It is preinstalled as a Dockerfile
   global (`npm install -g likec4@1.50.0`, the `@anthropic-ai/claude-code`
   precedent), NOT a `package.json` dependency. vite/esbuild never enter prod
   deps; lockfile parity is untouched. The "never render at runtime" rule
   becomes, more precisely, "never *import* the toolchain into the bundle."
2. **The CLI lays out via bundled graphviz-wasm** — no native `dot` binary
   needed (verified: `likec4@1.50.0 export json` exits 0 with no `dot` on PATH).
3. **In-process, synchronous, failure-isolated.** `writeC4Diagram` runs in the
   Next/custom-server process (not the bwrap agent sandbox), where
   `child_process.spawn` is established precedent (`pdf-linearize.ts` → qpdf,
   `push-branch`/`git-auth` → git). The re-render is best-effort: a render /
   commit / sync failure is reported via `reportSilentFallback` and returns
   `rerendered:false`, degrading to the Layer-1 honest-stale banner. The `.c4`
   commit is load-bearing and is NEVER rolled back.

### Alternative rejected: Inngest out-of-process job (ADR-033 pattern)

The deferred fallback was an Inngest function shelling out to the CLI, with the
UI polling for the refreshed dump. Rejected because the synchronous in-request
path (bounded 25s, dev-cohort-gated, human-paced saves) delivers the
"Saved — diagram updated" UX directly, whereas the async job would force the
stale banner on every save (eventual consistency) for no benefit at this scale.
If a future constraint forbids spawning on the request path, the Inngest
function remains the template.

## Consequences

- **Positive:** the diagram visibly updates after a save with no manual
  `/soleur:architecture render`; both write surfaces (UI + Concierge) benefit
  from the single `writeC4Diagram` funnel.
- **Cost — double commit:** each save yields a paired `.c4` + `model.likec4.json`
  commit (acceptable; mirrors the manual render workflow). Could be folded into a
  single Git Trees write later (Non-Goal).
- **Cost — version dual-pin coupling:** the Dockerfile `likec4@X` pin must track
  the `package.json` `@likec4/core`/`@likec4/diagram` version so the exported
  schema matches `LikeC4Model.create`. Drift-guarded by
  `test/c4-likec4-version-pin.test.ts` (fails CI if the pins diverge).
- **Cost — latency on the save path:** multi-second worst case, bounded by
  `RENDER_TIMEOUT_MS=25s` + a concurrency gate (default 2, env
  `C4_RENDER_CONCURRENCY`). `maxDuration=60` on the PUT route is a forward-compat
  platform hint; the in-code timeout is the real bound under the custom server.
