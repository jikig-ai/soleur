---
feature: c4-hardening-residuals
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [8966, 8861]
brainstorm: knowledge-base/project/brainstorms/2026-09-26-c4-hardening-residuals-brainstorm.md
status: draft
created: 2026-09-26
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
# Spec — C4 hardening residuals (#8966)

No infrastructure provisioning in scope — all changes are application code, plugin scripts,
and tests. The "installing graphviz" line in Non-Goals is a *rejected* alternative, not a
manual step.

## Problem Statement

The web-platform C4/LikeC4 pipeline has three hardening residuals tracked in #8966:

1. **Writer divergence (#8861).** The two bare script-side `likec4 export json` writers —
   `plugins/soleur/scripts/render-c4-model.sh` and
   `plugins/soleur/scripts/generate-c4-from-components.ts` — lack the server render's
   `--no-use-dot` wasm-layout pin **and** its `views > 0` gate. Inside a container without
   graphviz either can commit a zero-view model (`View 'index' not found` for the tenant);
   on a graphviz-installed host they emit layout bytes that diverge from the server's
   wasm-layout bytes and break `c4-model-freshness.test.sh`'s byte diff.
   (`scripts/regenerate-c4-model.sh` is an `exec` wrapper, not a third argv site.)
2. **Save-outcome race.** `applySavedOutcome` (`components/kb/c4-workspace.tsx`) funnels the
   PUT save response and the `c4_diagram_saved` WS frame with no ordering token —
   last-applied-wins. A stale `rerendered:false` (e.g., a superseded render with no
   diagnostic) can overwrite a fresher `rerendered:true`, or vice-versa, under concurrent
   saves. Latent while `c4-edit` is flag-gated off; arms on the L26 re-enable.
3. **Dropped-frame banner loss.** The honest-stale banner is client `useState` only; a
   dropped `rerendered:false` frame is unrecoverable — on Concierge reopen the model
   refetches but the user never learns their save didn't re-render.

## Goals

- Bring all `likec4 export json` writers to identical layout-engine parity and views gating.
- Make save outcomes ordered so an older outcome can never overwrite a newer one.
- Make staleness a server-derived fact on read, so the banner survives dropped frames,
  remounts, and out-of-band pushes — with no new persisted state.
- Leave a parity guard that goes RED when any writer (present or future) drops the
  flag/gate.

## Non-Goals

- Retry affordance on the stale banner (new interactive surface; requires `.pen` + copy).
- Surfacing `rerendered:false` in the Concierge thread (separate honesty surface).
- Replay-buffer membership for `c4_diagram_saved` (rejected: conversation-keyed buffer,
  user-scoped frame — `learnings/2026-09-25-listener-survival-is-not-channel-survival.md`).
- Any durable save-outcome store — Supabase table or otherwise (ADR-059 Art. 30 precedent).
- Canonical-byte provenance (`renderedSourceKey` embedded in `model.likec4.json`) — reserve
  mechanism only if commit-order derivation proves unreliable.
- Installing graphviz as an alternate engine (rejected by ADR-050; EPL-2.0 per CLO).

## Functional Requirements

### FR1: Flag + views-gate parity on all writers (PR-A; closes #8861)

Every tracked `likec4 export json` invocation that produces `model.likec4.json` passes
`--no-use-dot` and gates on `(.views | length) > 0` (or the shared `c4ModelCounts`
contract), refusing — not committing — a zero-view export. Covered sites:

- `plugins/soleur/scripts/render-c4-model.sh` (~line 115 invocation, ~line 143 gate)
- `plugins/soleur/scripts/generate-c4-from-components.ts` (~line 260 argv; `assessRender` /
  `countModelJson` in `plugins/soleur/lib/c4-from-components.ts` gains a views count)
- Server paths already comply (`server/c4-render.ts:228,731,783-791`) — guard asserts, no
  code change expected.

### FR2: Stale banner derived from server state (PR-B)

`GET /api/kb/c4/project` reports per-`dirPath` staleness derived at read time — a
**tree-diff**: compare the Contents listing's per-source blob shas (already fetched)
against the source entries in the newest `model.likec4.json` commit's dir subtree
(`commits?path=` + `git/trees`, ~3 calls regardless of source count). A mismatch
(modified, deleted, or added source) means the committed model predates the sources —
`stale:true`. The banner is therefore a recomputed fact, surviving dropped frames,
remounts, and out-of-band pushes. Reuses the existing `C4Diagnostics` surface — no new
visual element beyond flag/dir-aware line-2 copy and `aria-live`.

### FR3: Authoritative staleness replaces outcome ordering (PR-B)

*Revised at plan review (operator-approved, 2026-09-26):* the issue proposed a monotonic
`saveSeq` carried through both save paths. Review found the ordering guarantee is
subsumed once the GET-derived `stale` is authoritative — every outcome application
already performs `reload()`, which re-reads post-commit truth, so ordering races cannot
manifest in the banner boolean. The contract instead: **`stale` present in the GET
response is authoritative for the banner**; `stale` absent leaves existing state
untouched (derivation failure → never a false banner); save outcomes supply
`staleDiagnostic` and drive the banner only when `stale` was absent. A superseded-shape
outcome (`rerendered:false`, no diagnostic) defers to the reload's GET verdict.

## Technical Requirements

### TR1: Parity guard on invocation form

Extend the writer census in `plugins/soleur/test/c4-canonical.test.ts` (~lines 217-243) to
assert each enumerated writer's invocation carries `--no-use-dot` and a views gate —
invocation form per `cq-assert-anchor-not-bare-token` (no bare-token grep a comment can
satisfy), all write sites enumerated per
`hr-write-boundary-sentinel-sweep-all-write-sites`, mutation-proven (dropping the flag in a
fixture must RED). Explicit dispositions for non-writer surfaces
(`skills/architecture/references/likec4-reference.md` — fixed to pinned version + flag in
PR-A — archived replay harness, CI install steps). Add zero-view rows to
`plugins/soleur/test/render-c4-model.test.sh` (stub fixture at ~line 123; bump `cases_run`
floor).

### TR2: Response-field discipline (no WS schema change)

The only wire change is `stale?: boolean` on the GET `/api/kb/c4/project` response —
absent on derivation failure, never `false` on error. `ProjectResponse` /
`useC4Project`'s `setData` normalization (`c4-shared.tsx`) must pass it through or the
mechanism silently no-ops. No `c4_diagram_saved` frame change (no strictObject
rolling-deploy exposure). Pin: the field carries no user-derived content (a boolean).

### TR3: Superseded-outcome semantics preserved

The supersede shape (`rerendered:false` with no diagnostic, `server/c4-writer.ts`
~lines 444-474) is distinguishable client-side: such an outcome must not itself set the
banner — it defers to the reload's GET-derived `stale` (a superseding save's model
commit is already on GitHub, so GET sees fresh). The `c4_rerender_superseded`
server-side source-set check and the banner remain distinct mechanisms.

### TR4: Read-derivation cost bound

Staleness derivation on `GET /api/kb/c4/project` must reuse data the route already fetches
plus a small bounded set of metadata calls per `dirPath` — the plan's mechanism is 3–4
calls total regardless of source count (`commits?path=` for the model commit, `git/trees`
walks for the dir subtree, one tip-age check only when a diff exists). A grace window
suspends `stale` while the dir tip is younger than the render budget (in-flight two-commit
window). False-stale on a content-equal sources revert is acceptable conservative
behavior (documented).

### TR5: Observability

PR-B extends the `cc-dispatcher.ts` `reportSilentFallback` emit path to count
`rerendered:false` occurrences, so the field rate of failed renders/dropped frames is
measurable. Plan's `## Observability` block cites the covering layer per
`hr-observability-layer-citation`; `soleur:gdpr-gate` runs at plan Phase 2.7 and work Phase
2 exit (API-route path trigger).

### TR6: ADR + docs bookkeeping

ADR-050's 2026-09-25 addendum gets a supersede banner when PR-A lands; the save-ordering
protocol (commitSha rejection, save-start minting, dual-bundle `Symbol.for` rationale)
gets an ADR entry or ADR-050 addendum — plan decides. Roadmap dependency recorded:
L26 `c4-edit` re-enable gated on FR3.

## Acceptance Criteria

- `render-c4-model.sh` and `generate-c4-from-components.ts` pass `--no-use-dot` and refuse
  zero-view exports; `c4-model-freshness.test.sh` stays green.
- The census test REDs if any writer's `export json` invocation drops the flag or the
  views gate; a newly added writer without both also REDs.
- Two same-`dirPath` saves whose outcomes arrive out of order apply newest-only in both
  consumer components (server-side ordering covered by `c4-writer-concurrency.test.ts`
  harness pattern).
- After a `rerendered:false` outcome with the WS frame dropped, reopening the diagram or
  the Concierge still shows the stale banner — and an out-of-band source push that leaves
  the model behind shows it too.
- `Closes #8861` in PR-A; `Ref #8966` (umbrella stays open until all residuals land).
