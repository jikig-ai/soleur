# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-05-feat-likec4-rerender-diagram-after-save-plan.md
- Status: complete

### Errors
None. Feasibility gate resolved empirically (ran `likec4 export json` against the real prod model, no native dot, exit 0 ~0.5s via bundled graphviz-wasm). All deepen-plan gates passed.

### Decisions
- PRIMARY mechanism chosen (server-side `child_process.spawn` of preinstalled `likec4` CLI in `writeC4Diagram`); Inngest fallback NOT needed.
- New `server/c4-render.ts` spawn helper modeled on `server/pdf-linearize.ts` (bounded timeout → SIGKILL, scoped env, settle-once, concurrency gate, reason-typed result). Fixed argv (no user input in argv); cwd = scope-guarded diagrams dir.
- Re-render integrated inside `writeC4Diagram` (covers both PUT route + Concierge tool); best-effort/failure-isolated — `.c4` commit never rolls back on render failure → `rerendered:false` + Sentry/reportSilentFallback + Layer-1 stale banner.
- CLI preinstalled via Dockerfile `npm install -g likec4@1.50.0` (NOT a package.json dep → lockfile parity preserved); pinned to 1.50.0 to match `@likec4/core`/`@likec4/diagram@1.50.0` renderer (1.57.0 emits drifted schema).
- UI: re-key `stale` to mean "re-render did NOT succeed" — `onSaved(rerendered)` widened; `reload()` first, then `setStale(!rerendered)`.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
