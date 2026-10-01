---
title: C4 hardening residuals — likec4 flag/gate parity, save-outcome ordering, stale-banner resurrection
date: 2026-09-26
issue: 8966
branch: feat-8966-c4-hardening-residuals
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm: C4 hardening residuals (#8966)

Source: GitHub issue #8966 — three non-blocking residuals from the #8739 review and the C4
regeneration audit (PR #8892, merged `26f63a66`).

## What We're Building

Three hardening fixes on the web-platform C4/LikeC4 diagram pipeline, phased as two PRs:

- **PR-A (dedupe: closes #8861).** Bring the two bare script-side `likec4 export json` writers
  to server parity: `--no-use-dot` (wasm layout pin) **and** a `views > 0` gate, plus a parity
  guard that asserts every writer's *invocation form* carries both — extending the existing
  writer census rather than building new guard machinery.
- **PR-B.** (a) A server-minted monotonic `saveSeq` carried on both the PUT save response and
  the `c4_diagram_saved` WS frame, applied newest-only per `dirPath` on the client; and
  (b) staleness **derived at read time** on `GET /api/kb/c4/project` so the honest-stale
  banner is a fact the server recomputes, not an event the client can lose.

## User-Brand Impact

- **Artifact:** the C4 diagram save→render→banner pipeline (`server/c4-writer.ts`,
  `server/c4-render.ts`, `app/api/kb/c4/**`, `components/kb/c4-*.tsx`, the three
  `model.likec4.json` writers under `plugins/soleur/scripts/` + `scripts/`).
- **Vector:** a save that committed source but failed to re-render leaves the user reading a
  stale architecture diagram with zero warning — the failure shape indistinguishable from
  success; a dropped `rerendered:false` frame makes it permanent across reopens.
- **Threshold:** single-user incident.

Tagged **user-brand-critical** (auto, per #5175).

## Verified Findings (premise check + research)

1. **Issue premise partially stale — re-framed.** The issue asserts "no
   `c4-render-tenant-config.test.ts` exists on `origin/main`." The file exists (landed
   2026-09-24 via #8732/#8687) but tests tenant-config sandbox isolation, not flag parity —
   the *parity guard* it names is what is missing. Substance confirmed; wording corrected.
2. **Item 1 is substantially #8861 (OPEN).** Filed by the #8740 plan for exactly the two
   plugin writers; its scope is flag **and** views gate (a bare writer can commit a
   *zero-view* model inside a container without graphviz — `View 'index' not found` for the
   tenant). ADR-050's 2026-09-25 addendum records the same residual and will need a
   supersede banner. `scripts/regenerate-c4-model.sh` is a pure `exec` wrapper into
   `render-c4-model.sh` — **two** argv sites, not three.
3. **Writer census already exists.** `plugins/soleur/test/c4-canonical.test.ts:217-243`
   enumerates every tracked `likec4 export json` invocation (git-grep + comment-stripped
   `INVOKES` regex, floor-asserted) — the parity assert belongs there; it auto-covers future
   writers. `apps/web-platform/test/c4-render-sandbox.test.ts:389` already has a mutation
   row pinning the flag on the server side.
4. **`c4-writer.ts` is bundled twice into one process** (Next route + WS server via the
   Concierge tool chain — same hazard that put the render pool on `globalThis`,
   `c4-render.ts:257-263`). A module-local sequence counter would silently split; a
   `Symbol.for`-keyed `globalThis` counter is mandatory, not stylistic.
5. **`commitSha` cannot be the ordering token** — git shas are not order-comparable on the
   client. The PUT response already carries it (`route.ts:81-89`); the WS frame lacks any
   ordering key. The superseded-render outcome (`rerendered:false`, no diagnostic,
   `c4-writer.ts:444-474`) is precisely the frame a newer `true` must not be overwritten by.
6. **Item 3's derivation primitive exists but its provenance does not.** `sourceKeyOf`
   (`server/c4-stage-sources.ts:208-213`) computes the rendered source set; GET
   `/api/kb/c4/project` already reads per-entry shas and performs read-side detection for
   zero-view models (#8740, `MODEL_LEVEL_LINE`). Nothing records which source set the
   committed model was rendered from — so staleness is *derivable* but never derived.
   Commit-order comparison (model artifact's commit vs newest source commit for `dirPath`)
   yields the signal with zero canonical-byte changes.
7. **Supabase persistence for this surface was already rejected.** ADR-059 declined durable
   storage for transient frames (Art. 30 surface + write amplification); the 2026-09-25
   learning `listener-survival-is-not-channel-survival` records item 3 verbatim as the
   measured, deferred hole — and why the replay-buffer remedy doesn't fit (buffer is
   conversation-keyed, frame is user-scoped).
8. **likec4-reference.md drift.** `plugins/soleur/skills/architecture/references/likec4-reference.md:113`
   teaches `npx -y likec4@latest export json` — floating tag, no `--no-use-dot`; inside a
   container it reports 0 views misleadingly. Fix in PR-A (pinned version + flag).
9. **Race is armed, not just theoretical.** The ordering gap is latent while `c4-edit` is
   flag-gated OFF — it goes live on the L26 re-enable. CPO recommends gating that
   re-enablement on the item-2 fix.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Item 1 scope | **Dedupe onto #8861: flag + views gate** | Same authors/audit lineage; the zero-view failure is the real user-visible defect, bytes-divergence second. `Closes #8861` in PR-A; ADR-050 addendum gets a supersede note. |
| Parity guard | **Extend `c4-canonical.test.ts` writer census** | Asserts invocation *form* per `cq-assert-anchor-not-bare-token`, enumerates *all* write sites per `hr-write-boundary-sentinel-sweep-all-write-sites`, and mutation-battery precedent proves a new writer goes RED. Disposition non-writer surfaces (`likec4-reference.md`, archived replay harness, CI install steps) explicitly. |
| Item 2 token | **Server-minted `saveSeq` in `writeC4Diagram`, at save *start*** | Single funnel covers PUT + Concierge paths structurally. Start-ordering prevents a slow older render's outcome from landing after a newer save's. `Symbol.for`-keyed `globalThis` counter (dual-bundle hazard); `Date.now()` floor so a server restart can't regress below a live client's last-applied value. Optional on the wire for rolling-deploy back-compat (ADR-059 `.optional()` convention). |
| Item 3 substrate | **Derive staleness at read time on GET — no new persisted state** | Unanimous-ish: CPO (option B) + CLO (option c, legally lightest) + research (ADR-059 rejected durable storage). Cheaper than a table (no migration, no Art. 30 row, no DSAR allowlist entry), and *more truthful*: covers out-of-band pushes that emit no frame — the OTHER_DIR caveat `c4-diagnostics.tsx` already acknowledges. Banner becomes a recomputed fact; dropped frames stop mattering. |
| Item 3 mechanism | **Commit-order comparison first; embedded provenance only if it proves unreliable** | Model artifact's commit vs newest `.c4` source commit for `dirPath` — no canonical-byte change, no `LikeC4Model.create` tolerance risk. Embedded `renderedSourceKey` is strictly stronger but moves all writers + `c4-canonical` mirror in lockstep — held in reserve (Open Questions). |
| PR phasing | **Two PRs** | PR-A is a pure plugin-repo diff (closes #8861, unblocks independently); PR-B shares the save-outcome code path (writer, route, wire schema, two consumers). A single PR would mix plugin test machinery with app dataflow for no benefit. |
| Banner UX | **Warning-only, existing `C4Diagnostics` reused** | Same component, same copy family, restored state — the #8695/#8739 copy/non-visual exemption precedent holds; no `.pen` needed. **Conditional hard-block:** if the plan adds a new affordance (e.g., retry-via-Concierge), a `.pen` wireframe becomes mandatory (`wg-ui-feature-requires-pen-wireframe`). |
| Observability | **Fold emit-path instrumentation into PR-B** | Extend the `cc-dispatcher.ts` `reportSilentFallback` site to count `rerendered:false` occurrences so the drop rate is measurable (CPO: unknown whether P1-trust or P2-polish frequency). |

## Approaches Considered

- **Item 3-A. Persist last save outcome (issue's candidate; CTO's side table `c4_diagram_save_state`):**
  records *save outcome*, not *model freshness* — an out-of-band push leaves "fresh" while
  stale; costs a migration + RLS + GDPR surface (CLO: five mandatory checks). Rejected — the
  shared-row coupling to item 2 dissolved once the seq became a process counter, and the
  semantic it records is the weaker one.
- **Item 3-B. Derive at read time (CHOSEN):** no new state, covers external writes, matches
  the zero-view read-detection pattern #8740 already shipped on the same route.
- **Item 3-C. Persist + derive:** belt-and-suspenders; over-scoped for one beta user.
- **Item 2-A. commitSha as ordering token:** rejected — not order-comparable client-side.
- **Item 2-B. Outcome-time counter:** rejected — a slow save A finishing after save B would
  let A's stale result win; allocation must reflect initiation order.

## Open Questions

- **Commit-order vs embedded provenance for staleness** (plan decides): does the GitHub
  metadata the GET route already fetches expose per-path commit ordering cheaply, or does
  the comparison need `commits?path=` per `dirPath`? Edge case: a sources-only revert
  commit (content equal to rendered set, sha different) yields a false-stale — acceptable
  conservative behavior, or worth content comparison?
- **`saveSeq` seeding:** `Date.now()` floor vs plain counter — plan pins the restart-skew
  edge (server restart with a retained live client).
- **likec4 1.50.0 `use-dot` default resolution** — ADR-050 records `isInsideContainer()`;
  confirm against the pinned CLI source before writing the guard's comment/rationale.
- **`rerendered:false` in the Concierge thread** (CPO): surfacing the failed outcome in the
  chat that initiated the edit is a distinct honesty surface — out of scope here, documented
  in Non-Goals.
- **Roadmap dependency:** recommend recording "L26 `c4-edit` re-enable gated on the item-2
  fix" — a one-line dependency in the spec/plan, not code.

## Non-Goals

- **Retry affordance on the stale banner** (e.g., "ask the Concierge to retry" button) —
  deferred; new interactive surface requires `.pen` wireframe + copy design first.
- **Surfacing `rerendered:false` inside the Concierge thread** — deferred; separate honesty
  surface from the diagram pane.
- **Replay-buffer membership** for `c4_diagram_saved` — rejected by the 2026-09-25 listener
  learning (conversation-keyed buffer, user-scoped frame).
- **Durable (DB) save-outcome store** — rejected (ADR-059 Art. 30 precedent; CLO cost
  analysis above).
- **Canonical-byte provenance** (`renderedSourceKey` embedded in `model.likec4.json`) —
  reserve mechanism only if commit-order derivation proves unreliable.
- Installing graphviz as an alternate layout engine — rejected by ADR-050 (a second engine
  diverging from the wasm pin); also EPL-2.0 per CLO.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Residual 3 is the highest user-trust item — the stale banner is a trust
contract and a dropped frame breaks it silently; residual 2 is latent but arms on the
`c4-edit` L26 re-enable (recommend gating it on this fix); residual 1 guards the honesty
mechanism itself. Evaluate derive-at-read (option B) before committing to persistence — it
closes a strictly larger hole (external pushes) at similar cost.

### Legal (CLO)

**Summary:** Residuals 1–2 have no legal document needs; residual 3's substrate is the only
legally load-bearing choice — derive-at-read is preferred (no new regulated surface), a
Supabase table would trigger the full migration checklist (Art. 6/5e/17, DSAR allowlist,
Art. 30 row). Ordering token must carry no user-derived identifier; persist only the
already-sanitized diagnostic if anything is stored. `soleur:gdpr-gate` fires at plan Phase
2.7 / work Phase 2 exit (API-route path trigger).

### Engineering (CTO)

**Summary:** Item 1 = #8861 (flag **and** views gate; two argv sites not three; extend the
existing census). Item 2: mint server-side in `writeC4Diagram` at save start; commitSha is
not orderable; ~9 touch points with union-widening sweep. Item 3: no diagram record exists;
recommends the shared-row design but flags the last-outcome ≠ freshness semantic —
orchestrator weighs its substrate rec against the ADR-059 durability rejection and the
CPO/CLO derive-at-read consensus; derive-at-read chosen.

## Session Errors

- **Stale issue premise, caught pre-worktree:** "no `c4-render-tenant-config.test.ts`
  exists on `origin/main`" was false — the file exists (different coverage). Recorded per
  the premise-probe contract; the parity-guard substance was verified independently.
- **Operator AskUserQuestion blocked by `pre-ask-technical-fork-gate.sh`** at route
  selection — correctly: pipeline routing and approach selection among technical variants
  are orchestrator calls here. Resolved via issue-ordered scope + leader consensus.

---

*See `specs/feat-8966-c4-hardening-residuals/spec.md` for the specification.*
