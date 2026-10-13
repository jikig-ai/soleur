---
title: "c4 hardening residuals: writer parity + read-time staleness"
type: fix
date: 2026-09-26
slug: c4-hardening-residuals
branch: feat-8966-c4-hardening-residuals
issue: 8966
# No `closes:` — the two implementation PRs carry per-PR linkage (`Closes #8861` on
# PR-A, `Ref #8966` on both; the umbrella closes manually when both merge). A `closes:`
# here would auto-close a tracker when the *planning* PR ships — spec-flow P2-10.
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan provisions no infrastructure — application code, plugin
     scripts and tests only. The iac guard trips on the word "installing" inside a
     *rejected* Non-Goal (the graphviz alternative ADR-050 already excludes). -->

# c4 hardening residuals: writer parity + read-time staleness

## Overview

Harden the web-platform C4/LikeC4 pipeline per issue #8966 across two phased PRs:

- **PR-A** — bring the two bare plugin `likec4 export json` writers
  (`plugins/soleur/scripts/render-c4-model.sh`,
  `plugins/soleur/scripts/generate-c4-from-components.ts`) to the server's
  `--no-use-dot` + views-gate parity, extend the writer census in
  `plugins/soleur/test/c4-canonical.test.ts` to pin both, and fix the
  `likec4-reference.md` recipe drift (`@latest` ×2, missing flag). **Closes #8861.**
- **PR-B** — make the stale-diagram banner a **recomputed fact** instead of a losable
  event: `GET /api/kb/c4/project` derives staleness by diffing the current source blob
  shas (Contents listing, already fetched) against the newest `model.likec4.json`
  commit's tree. When `stale` is present it is authoritative for the banner; save
  outcomes and `c4_diagram_saved` frames supply diagnostic copy and drive the banner only
  when `stale` is absent. **No WS/schema/PUT wire changes** — plan review found the
  issue's proposed `saveSeq` ordering token redundant once truth is recomputed on every
  `applySavedOutcome`'s `reload()` (operator-approved cut, 2026-09-26).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 8966` / `gh issue view 8861` → both **OPEN** (verified 2026-09-26).
  #8966 is the umbrella; item 1 is substantially #8861.
- Cited code paths verified on `origin/main`: `render-c4-model.sh:115` bare invocation +
  `:143` elements-only gate; `generate-c4-from-components.ts:260` argv (no flag);
  `server/c4-render.ts:228,731` carry the flag + `:783-791` views gate;
  `c4-workspace.tsx:89-101` `applySavedOutcome` funnel (`await reload()` then apply);
  `project/route.ts` fetches Contents listing `:198-216` + blobs `:304-320`. The issue's
  "three script writers" overstates: `regenerate-c4-model.sh:18` is an `exec` wrapper —
  **two** argv sites.
- Stale premise caught: the issue asserts no `c4-render-tenant-config.test.ts` exists on
  `origin/main`; it exists (2026-09-24, #8732/#8687) covering sandbox isolation — the
  missing artifact is the *parity guard*, added by extending the existing census.
- Mechanism vs ADR corpus: durable outcome store → ADR-059 **rejected** it for transient
  frames — excluded; read-time derivation → #8740 precedent on the same GET route;
  sequence-token ordering → superseded by authoritative recompute (review decision, below);
  a graphviz engine → rejected by ADR-050 (and EPL-2.0 per CLO).

### Property List (Phase 0.6b)

- P1: every `model.likec4.json` writer uses the wasm layout engine (byte parity).
- P2: a zero-view export is refused, never committed, by every writer.
- P3: a *future* writer that drops either pin fails CI (census, not per-file list).
- P4: an older/mis-ordered save outcome can never overwrite fresher truth in the banner —
  satisfied structurally: the banner boolean is a GET-derived fact, not outcome ordering.
- P5: the stale-diagram banner is recoverable after a dropped frame / remount / out-of-band
  source push — derived on read.
- P6: the rate of `rerendered:false` outcomes is measurable (observability deliverable).

### Cut List (Phase 0.6b + plan-review)

- Supabase `c4_diagram_save_state` table (CTO brainstorm candidate) — cut: P5 bought by
  read-time derivation; re-opens ADR-059's rejected durability surface.
- `renderedSourceKey` embedded in `model.likec4.json` — cut: changes canonical bytes;
  the tree-diff derivation needs nothing persisted.
- New `c4_diagram_stale` WS message type — cut: GET response field suffices.
- New banner component — cut: existing `C4Diagnostics` strip (warning-only).
- **`saveSeq` ordering token (issue-prescribed, cut at plan review, operator-approved)** —
  every save outcome already triggers `await reload()` before applying
  (`c4-workspace.tsx:89-101`, `c4-diagram.tsx:62-74`); with `stale` authoritative on GET,
  ordering cannot corrupt the boolean. The token's marginal value was ordering *on the
  `stale`-absent fallback path only* — not worth ~12 files of wire plumbing, a
  `strictObject` old-client drop window, and a seq-vs-replaySeq grenade. P4 holds
  structurally.
- `staleReason` enum — cut: underivable without the rejected commit-message parsing;
  the copy defect it fed is fixable with `c4EditEnabled` + dir-canonicality, both already
  client-side.

### Repo findings (implementation-shape)

- **Staleness derivation (final, post-review):** on GET, after the Contents listing
  (`route.ts:198-216`): (1) `commits?path=${githubDir}/model.likec4.json&per_page=1` →
  `M` (its `commit.tree.sha` is on the list item); (2) `git/trees/{M.tree.sha}` → locate
  the `<dir>` subtree entry → `git/trees/{subtreeSha}` → the source entries at
  model-commit time; (3) stale iff the set/sha of `LIKEC4_SOURCE_EXTENSIONS`
  (`.c4`,`.likec4`,`.like-c4` — `c4-stage-sources.ts:55`, NOT the route's narrower
  `.c4`-only `sourceEntries` filter at `:297-303`) entries differ between `M`'s tree and
  the current listing — catches modified, added, and out-of-band-deleted sources with
  zero date semantics. **Grace window:** when a diff exists, one
  `commits?path=<dir>&per_page=1` for the tip's `committer.date` — younger than the
  render budget (~120s) → omit `stale` (the in-flight two-commit window
  `route.ts:126-133` documents). **Bounded:** 2 calls clean, 4 worst case. All failures →
  `reportSilentFallback(feature=c4-project-read, op=stale-derivation)` + field absent.
  No model commit (`M` empty — pre-render dirs) → `stale` absent.
- **Client merge contract:** `ProjectResponse` + `setData` (`c4-shared.tsx:55-61,113-119`)
  carry `stale` — the normalization rebuild is a silent-drop footgun otherwise. In
  `applySavedOutcome`/`c4-diagram.tsx` listener: reconcile the outcome against the
  *just-completed* reload's `data.stale` — present ⇒ authoritative for the boolean;
  absent ⇒ outcome applies as today; supersede-shape outcomes (`rerendered:false` + no
  diagnostic) never set the banner on their own (defer to GET — a superseding save's
  model commit is already live). One shared reconcile helper keeps the two consumers
  behavior-identical.
- **Copy defect (pre-existing, made load-bearing):** `SUPERSEDED_LINE` names a Save
  affordance gated off by `c4-edit` (default OFF) — fix line-2 by resolved props:
  flag-on → existing copy; flag-off + canonical dir → "Ask the Concierge to re-render
  this diagram" (`ZERO_VIEW_DIAGNOSTIC` precedent, `route.ts:67`); non-canonical dir →
  the OTHER_DIR shape ("re-run the diagram export for this folder") — `C4Diagnostics`
  takes resolved copy as props (the module must stay light/no-flag-import, `:3-5`).
- **Zero-view parity:** `.sh` gains `jq -e '(.views | length) > 0'` beside `:143`; `.ts`
  gains `views` in `countModelJson` (`lib/c4-from-components.ts:450-459`) + `viewCount`
  on `assessRender` (`:468-491`); the census pins the flag per writer and the gate at the
  `assessRender({...viewCount...})` call site (`generate-c4-from-components.ts:342`) —
  the gate code lives in the lib, not the writer file.
- **Observability anchor:** `cc-dispatcher.ts:2342-2367` emit path gains a counted
  `feature=c4-save-outcome, outcome=rerendered|rerendered-false|emit-failed` event
  (all three — a rate needs the denominator).

### Learnings applied

- `2026-09-25-listener-survival-is-not-channel-survival.md` — the dropped-frame hole;
  read-time derivation is its remedy.
- `2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md` —
  mutation-prove the parity guard.
- `2026-09-25-my-checker-named-a-property-its-population-regex-could-not-reach.md` —
  census reconciles invocation *spellings*.
- `cq-assert-anchor-not-bare-token`, `hr-write-boundary-sentinel-sweep-all-write-sites`.

### Community / external research

Functional-overlap check ran (three registries): no overlap. External research skipped —
strong local context.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "three script-side writers" lack the flag | Two argv sites; `regenerate-c4-model.sh` is an `exec` wrapper | Fix the two; census covers the wrapper transitively |
| no `c4-render-tenant-config.test.ts` exists | File exists; covers sandbox isolation, not parity | Parity assert lands in `c4-canonical.test.ts` census |
| "monotonic save identifier carried through both paths" (item 2) | Every outcome already `await reload()`s before applying | `saveSeq` cut at plan review — ordering is irrelevant once `stale` is authoritative; spec FR3 revised with operator approval |
| "persist last outcome server-side" | No diagram table exists; ADR-059 rejected durable transient state | Read-time derivation — no store |

## Implementation Phases

### PR-A — writer parity (closes #8861)

1. `plugins/soleur/scripts/render-c4-model.sh`: `--no-use-dot` on the `:115` npx
   invocation; `jq -e '(.views | length) > 0'` refusal beside `:143` (#8740 rationale
   comment: elements-but-no-views = layout failure, never the user's source).
2. `plugins/soleur/scripts/generate-c4-from-components.ts`: `"--no-use-dot"` in the
   `:260` argv; `lib/c4-from-components.ts` `countModelJson` gains `views` (widening
   breaks the `toEqual` at `test/c4-from-components.test.ts:308,315-316` — update);
   `assessRender` gains `viewCount` + `zero-views` status between element and
   relationship checks; audit `C4_MARKER_FIELDS` (`:82-90`) + `zeroCounts`
   (`generate-c4-from-components.ts:73`) ripple first.
3. `plugins/soleur/test/c4-canonical.test.ts`: extend the `:217-243` census — flag per
   writer by invocation form + views-gate marker (`views | length` in `.sh`;
   `viewCount` at the `.ts` writer's `assessRender` call site). Mutation-prove per the
   Guard Contract. Note: the census also pins the app-side `RENDER_SCRIPT`
   (`c4-render.ts:228`) — intended; record ownership (plugin suite guarding app file).
4. `plugins/soleur/test/render-c4-model.test.sh`: zero-view row on the stub fixture
   (`:123`); bump the `cases_run` floor (`:221-224`).
5. `plugins/soleur/skills/architecture/references/likec4-reference.md`: pin the literal
   `likec4@1.50.0` (not `$LIKEC4_VERSION` — meaningless in a doc fence) + `--no-use-dot`
   on **both** `:112` (`validate`) and `:113` (`export`) lines.
6. ADR-050 2026-09-25 addendum: supersede banner noting the plugin writers landed parity.

### PR-B — derived staleness (ref #8966)

1. `server/c4-staleness.ts` (new): `deriveDiagramStale` — the tree-diff above (M lookup →
   subtree walk → sha/set compare vs the listing → grace-window tip check on diff).
   `LIKEC4_SOURCE_EXTENSIONS` filter on both sides. All failures →
   `reportSilentFallback` + `undefined` (absent). Export for direct unit tests.
2. `app/api/kb/c4/project/route.ts`: call it after the listing (`:196-206`), emit
   `stale` only when derivation produced a verdict.
3. `c4-shared.tsx`: `ProjectResponse` + `setData` carry `stale`; fix the stale comment at
   `:387` (says GET reads the clone — it reads GitHub, `route.ts:116-124`).
4. `c4-workspace.tsx` + `c4-diagram.tsx`: shared reconcile — banner = `data.stale` when
   present, else outcome-driven as today; supersede-shape outcomes never self-set;
   outcome diagnostic shows only under a true banner.
5. `c4-diagnostics.tsx`: `aria-live="polite"` on the amber strip (async resurrection
   announces to AT); line-2 copy via resolved props per the matrix in Repo findings.
6. `cc-dispatcher.ts:2342-2367`: counted `feature=c4-save-outcome` events (all three
   outcomes) — the emit path's `reportSilentFallback` stays.
7. Tests: `c4-project-route.test.ts` `setupGitHub` gains `/commits` + `/git/trees` arms +
   a call-issued assertion (else the suite greens on a dead arm);
   `c4-workspace.test.tsx`/`c4-diagram.test.tsx`: precedence rows (present-authoritative,
   absent-untouched, supersede-shape defers, remount resurrection);
   `c4-shared.test.tsx` normalization row; a `c4-staleness` unit suite for the pure
   comparator (sha set/sha mismatch → stale; `.md`-only diff → not stale; `M` absent →
   absent; grace window).
8. ADR-050 addendum: record the tree-diff derivation, the grace window, and the
   ordering-subsumption decision (issue's seq-token proposal superseded — cite the
   plan-review record).

## Files to Edit

- `plugins/soleur/scripts/render-c4-model.sh` (PR-A)
- `plugins/soleur/scripts/generate-c4-from-components.ts` (PR-A)
- `plugins/soleur/lib/c4-from-components.ts` (PR-A)
- `plugins/soleur/test/c4-canonical.test.ts` (PR-A)
- `plugins/soleur/test/render-c4-model.test.sh` (PR-A)
- `plugins/soleur/test/c4-from-components.test.ts` (PR-A — `toEqual` ripple)
- `plugins/soleur/skills/architecture/references/likec4-reference.md` (PR-A)
- `knowledge-base/engineering/architecture/decisions/ADR-050-*.md` (both PRs)
- `apps/web-platform/app/api/kb/c4/project/route.ts` (PR-B)
- `apps/web-platform/components/kb/c4-shared.tsx`, `c4-workspace.tsx`, `c4-diagram.tsx`,
  `c4-diagnostics.tsx` (PR-B)
- `apps/web-platform/server/cc-dispatcher.ts` (PR-B — observability counter only)
- Tests (PR-B): `test/c4-project-route.test.ts`, `c4-workspace.test.tsx`,
  `c4-diagram.test.tsx`, `c4-shared.test.tsx`

## Files to Create

- `apps/web-platform/server/c4-staleness.ts` (PR-B — pure derivation, testable)
- `apps/web-platform/test/c4-staleness.test.ts` (PR-B)
- `knowledge-base/product/design/engineering/c4-stale-banner-resurrection.pen` (done,
  operator-approved)

## Architecture Decision (ADR/C4)

### ADR

- Amend `ADR-050` with a new addendum (PR-B): record the read-time tree-diff staleness
  derivation (content-addressed compare, grace window, fail-absent) and the explicit
  decision that save-outcome ordering needs no wire token because every consumer reloads
  truth before applying — issue #8966's `saveSeq` proposal is superseded, documented as
  the reviewed alternative. Reaffirm ADR-059's durability rejection for this surface.
- PR-A adds a supersede banner to the 2026-09-25 addendum (plugin-writer parity landed).

### C4 views

**No C4 impact.** Enumeration against all three model files
(`diagrams/{model,views,spec}.c4`): (a) no new external human actor (`founder` covers the
viewer; `public-reader` unaffected); (b) no new external system (commits/trees reads ride
the existing `webapp`/`api` → `github` edge); (c) no new container/data store
(derivation is stateless); (d) no access-relationship change (GET auth unchanged).

### Sequencing

No soak-gated slices — ADR stays `accepted`, addendum dated.

## User-Brand Impact

- **If this lands broken, the user experiences:** a stale or non-rendering C4 architecture
  diagram presented as current — silently, on the KB surface whose pitch is "the diagram
  is the truth" (banner lies in either direction: absent-when-stale or stuck-when-fresh).
- **If this leaks, the user's data is exposed via:** the save path's `diagnostic` string
  can carry tenant repo file names — it must stay `sanitizeDiagnosticPath`-sanitized end
  to end (existing 20k-char wire cap kept).
- **Brand-survival threshold:** `single-user incident`

## Observability

```yaml
liveness_signal:
  what: "counted save-outcome events (feature=c4-save-outcome, outcome=rerendered|rerendered-false|emit-failed — all three so the rate has a denominator)"
  cadence: "per frame emit"
  alert_target: "Sentry issue stream (existing reportSilentFallback sink)"
  configured_in: "apps/web-platform/server/cc-dispatcher.ts (emit site) + apps/web-platform/app/api/kb/c4/project/route.ts (derivation-failure report) — no new infra"
error_reporting:
  destination: "Sentry web-platform via reportSilentFallback (@/server/observability)"
  fail_loud: "derivation failure -> Sentry + stale field absent (never a false banner); the pino c4_rerender_superseded warn stays log-level (corrected — it is NOT a Sentry emit today)"
failure_modes:
  - mode: "commits/trees derivation fails or rate-limits on GET"
    detection: "reportSilentFallback(feature=c4-project-read, op=stale-derivation); response omits stale -> frame-driven fallback"
    alert_route: "Sentry issue"
  - mode: "in-flight two-commit window misread as stale"
    detection: "grace window (dir tip younger than render budget -> omit stale); the resync self-corrects on the saver's own post-return reload"
    alert_route: "Sentry banner-rate anomaly via c4-save-outcome counter"
  - mode: "script writer still emits dot-layout or zero-view bytes"
    detection: "c4-canonical.test.ts census RED + render-c4-model.test.sh zero-view row RED at CI"
    alert_route: "CI red pre-merge"
logs:
  where: "pino stdout -> journald on the web host (existing); Sentry for reportSilentFallback events"
  retention: "existing platform retention"
discoverability_test:
  command: "bash -c \"grep -q 'stale' apps/web-platform/app/api/kb/c4/project/route.ts && echo ok\""
  expected_output: "ok"
```

## Domain Review

**Domains relevant:** Product, Legal, Engineering (brainstorm carry-forward)

### Engineering (CTO — carry-forward)

**Status:** reviewed
**Assessment:** confirmed two argv sites; recommended a shared outcome store for items
2+3 — superseded first by derive-at-read (orchestrator) then by the ordering-token cut
(plan review). No capability gaps.

### Legal (CLO — carry-forward)

**Status:** reviewed
**Assessment:** residuals carry no legal-doc surface; derive-at-read is the preferred
(no new regulated surface) option — selected. The `stale` field carries no user-derived
content; diagnostics stay `sanitizeDiagnosticPath`-sanitized. `soleur:gdpr-gate`
advisory ran at plan time and re-runs at work Phase 2 exit.

### Product/UX Gate

**Tier:** blocking (mechanical override — `components/kb/c4-*.tsx` in Files to Edit)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo (carry-forward + plan-review panel);
soleur:product:spec-flow-analyzer (Step 3); soleur:product:design:ux-design-lead
(review mode)
**Skipped specialists:** soleur:product:design:ux-design-lead as *producer* (Pencil agent
CLI hit the weekly Claude subscription limit; the `.pen` was authored by the orchestrator
to the existing component's exact appearance and then corrected per the agent's review);
soleur:marketing:copywriter — no leader recommended it; banner copy reuses existing
sanctioned phrases.
**Pencil available:** yes (headless CLI installed; agent-auth rate-limited until
2026-09-30) — `.pen` at
`knowledge-base/product/design/engineering/c4-stale-banner-resurrection.pen`,
operator-approved 2026-09-26.

#### Findings

CPO: honest staleness is load-bearing for "the diagram is the truth"; warning-only is
correct while `c4-edit` is flag-off; copy must not name dead affordances — extended to a
third branch (non-canonical dir where Concierge cannot write). spec-flow: no P0s; 5 P1s
incorporated (.md masking, mint timing → moot post-cut, remount watermark → moot
post-cut, precedence pinning, dead-end copy). ux-design-lead: `.pen` corrected to depict
the flag-off default and the shipped derivation; `aria-live` added; in-thread
surfacing + retry affordance deferred to #8987.

## GDPR / Compliance Gate

`soleur:gdpr-gate` advisory at plan time (API-route path trigger): the GET route gains
read-only `commits`/`git/trees` calls and a boolean — no new personal-data categories, no
store, no new processing subject; no Art. 9 surface; no Art. 30 register change (the
rejected table was the only register-relevant candidate). CLO reviewed at brainstorm;
nothing Critical.

## Guard Contract

### Guard 1 — writer parity census

**Property.** Every file in the repo that invokes `likec4 export json` to produce
`model.likec4.json` carries `--no-use-dot` in its invocation AND a views-nonempty gate —
and any new writer lacking either fails the suite.

**Assembly.** Derived, not listed: `git grep -l -E 'export["'"'"', ]+json'` over
`*.sh *.ts *.mjs *.js` (minus test paths), comment-stripped, filtered through
invocation-form regexes covering both spellings (argv array
`["']export["'],\s*["']json["']` and shell `export json -o` — including the
`export json --no-use-dot -o` post-fix form). Members flow through the
`c4-canonical.test.ts` census chokepoint; the `.ts` writer's gate marker is asserted at
its `assessRender` call site because the gate code lives in `lib/c4-from-components.ts`.
Non-writer surfaces (docs, CI install steps) are outside the grep population by glob
construction — no dispositions needed (Kieran P1-1 corrected the earlier .md claim).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `--no-use-dot` from `render-c4-model.sh`'s invocation (views gate stays) | RED |
| 2 | Drop `viewCount` from the `assessRender` call in `generate-c4-from-components.ts` | RED |
| 3 | Add a new writer file invoking `likec4 export json` with neither flag nor gate | RED |
| 4 | Neuter the census regex so it matches zero files ("0 checked", exit 0) | RED — floor assertion on the three known members catches a vacuous census |
| 5 | Harness row: a synthetic `.ts` fixture whose `export json -o` appears only inside a comment/template-doc string | must-PASS — comment-stripping excludes it; proves the guard keys on invocation form, not bare text |

**Anchor.** Census derives from `git grep` over the tracked tree — population and
protected thing share one diff. The floor names the three known members verbatim, so a
diff editing a writer without updating the floor still fails; mutation rows pin the
per-member property, not membership.

## Test Scenarios

- Given `render-c4-model.sh` in a container without graphviz, when `likec4 export json`
  runs, then wasm layout is used AND a zero-view model is refused —
  `render-c4-model.test.sh` stubbed-npx rows.
- Given `generate-c4-from-components.ts` on a zero-view render, when `assessRender`
  evaluates, then status is `failed`/`zero-views` — `c4-from-components.test.ts`.
- Given sources identical to the model commit's tree, when GET runs, then `stale:false`
  or absent → no banner; given a modified/added/deleted `.c4` (or `.likec4`) source, then
  `stale:true` — `c4-staleness.test.ts` + `c4-project-route.test.ts` mock-tree rows.
- Given a diff where the dir tip is younger than the render budget (in-flight save), when
  GET runs, then `stale` absent — grace-window row.
- Given `stale:true` on GET then a `rerendered:true` frame, when applied, then banner
  follows the GET verdict (outcome's diagnostic only shown when stale).
- Given a supersede-shape outcome (`rerendered:false`, no diagnostic) with GET
  `stale:false`, when applied, then no banner — supersede defers to derived truth.
- Given a frame-set banner then a GET with `stale` absent, when the fetch resolves, then
  the banner is untouched — absent ≠ false.
- Given a dropped `rerendered:false` frame and a page remount, when GET runs, then the
  banner resurrects — the headline AC.
- `c4-model-freshness.test.sh` stays green.

## Acceptance Criteria

- [ ] `render-c4-model.sh` and `generate-c4-from-components.ts` both pass `--no-use-dot`
      and refuse zero-view exports; `Closes #8861` in the PR-A body.
- [ ] The extended census REDs on: a dropped flag, a dropped `viewCount` call-site arg,
      and a new non-compliant writer (mutation matrix verified by running it).
- [ ] `likec4-reference.md` pins literal `likec4@1.50.0` + `--no-use-dot` on both recipe
      lines.
- [ ] `GET /api/kb/c4/project` returns `stale:true` iff the `LIKEC4_SOURCE_EXTENSIONS`
      entries differ (set or sha) between the model commit's dir subtree and the current
      listing — covering modified, added, and deleted sources — subject to the
      grace window.
- [ ] `stale` absent on any derivation failure (commits/trees error, no model commit) +
      `reportSilentFallback` event.
- [ ] GET `stale` present is authoritative for the banner in BOTH consumers; `stale`
      absent leaves existing state untouched; `ProjectResponse`/`setData` carry the field.
- [ ] Supersede-shape outcomes (`rerendered:false` + no diagnostic) never set the banner
      without a concurring GET verdict.
- [ ] Banner line-2 copy resolves on `c4EditEnabled` + dir-canonicality — flag-off names
      the Concierge; non-canonical dir names the repo-side export; flag-on keeps
      `SUPERSEDED_LINE`.
- [ ] `aria-live="polite"` on the amber strip.
- [ ] The stale banner resurrects on page remount/Concierge reopen with no WS frame.
- [ ] ADR-050 addendum records the tree-diff derivation + the ordering-subsumption
      decision; the 2026-09-25 addendum carries the supersede banner.
- [ ] `Ref #8966` in both PR bodies (`Closes #8861` on PR-A); umbrella closes manually
      when both merge.
- [ ] Observability: `feature=c4-save-outcome` counts all three outcomes; the
      discoverability probe passes preflight Check 10.

## Open Code-Review Overlap

Checked 86 open `code-review` issues against the Files-to-Edit list:

- **#3374** (`slot_reclaimed` WS frame), **#3242** (`tool_use` raw name) — different frame
  surfaces; **acknowledge** (no longer touch `ws-client.ts`/`types.ts` at all post-cut).
- **#3280** (`useWebSocket` reducer refactor) — **acknowledge**; moot for wire, still a
  co-tenant of `ws-client.ts` if it lands mid-PR.
- **#3243** (decompose `cc-dispatcher.ts`) — **defer**: our remaining edit is a ~5-line
  counter at the emit site; relocatable if #3243 lands first.

## Sharp Edges

- **The derivation is content-addressed, not date-ordered** — tree-sha comparison kills
  committer.date skew (backdated/future-dated pushes, same-second commits, squash
  rewrites). Do not "simplify" it back to date comparison; the date ordering was the
  advisory's original design and three reviewers falsified it.
- **`.md` writes are irrelevant to staleness** — only `LIKEC4_SOURCE_EXTENSIONS` entries
  participate; an `.md` tip can neither flag stale nor mask a stale `.c4` (the masking
  hole was pinned by the earlier dir-tip design's review).
- **In-flight window:** a GET landing between the source commit and the model commit
  would derive `stale:true` during a succeeding save — the grace window (tip younger than
  the render budget → omit `stale`) covers it; the saver's own post-return reload is
  already past it.
- **Absent ≠ false:** a `?? false` normalize-and-sync is the bug shape — `stale` present
  is authoritative, absent is untouched.
- **Supersede-shape is detectable** — `rerendered:false` + no diagnostic means the
  writer's source-set check fired; it defers to GET, never self-sets.
- **`hr-third-party-content-grep-on-undertaking`:** N/A — no third-party undertakings.
- **`requires_cpo_signoff: true`** is set; `user-impact-reviewer` runs at PR review; an
  empty/placeholder `## User-Brand Impact` fails deepen-plan Phase 4.6 — filled above.
- **`wg-plan-prescribed-skills-must-run-inline`:** `soleur:gdpr-gate` re-runs at work
  Phase 2 exit; `soleur:architecture` authors the ADR-050 addendum in-PR.
- **Persistently-failing render** leaves a permanent banner whose only remedy (Concierge)
  can loop — acceptable at this threshold; in-thread surfacing is #8987.

## Open Questions

- **OQ1:** If the tree-diff derivation proves unreliable at work time (e.g., `git/trees`
  pagination on a large dir subtree), fall back to a `renderedSourceKey` hash embedded in
  the model *commit message* (not the JSON bytes — canonical parity forbids artifact
  changes), recomputed at read from the listing's blob shas.
- **OQ2:** The exact grace-window bound (render budget ~120s vs the 25s render timeout +
  slack) — pin against `c4-render.ts`'s timeout constant at implementation, with a
  comment citing this note.
- **OQ3:** likec4 1.50.0's `use-dot` default resolution (`isInsideContainer()` vs
  dot-on-PATH) — confirm against the pinned binary's source before writing the guard's
  rationale comment.

## Deferred (tracked)

- In-thread `rerendered:false` surfacing + retry affordance paired with `c4-edit`
  re-enable → **#8987** (filed per `wg-when-deferring-a-capability-create-a`).
- Replay-buffer membership for `c4_diagram_saved` — rejected, not deferred.
- Durable save-outcome store — rejected (ADR-059 precedent), not deferred.
- `saveSeq` ordering token — rejected at plan review (superseded by authoritative
  recompute), not deferred.

## References

- Issue: #8966 (umbrella), #8861 (writer parity — closed by PR-A), #8987 (deferral)
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-26-c4-hardening-residuals-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-8966-c4-hardening-residuals/spec.md`
- Wireframe: `knowledge-base/product/design/engineering/c4-stale-banner-resurrection.pen`
- ADRs: ADR-050 (render pipeline — amended), ADR-059 (durability precedent), ADR-235
  (three-writer canonical artifact)
- Prior plan (frame contract): `knowledge-base/project/plans/2026-09-25-fix-c4-reload-on-concierge-edit-plan.md`
