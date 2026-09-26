# Tasks — c4 hardening residuals (#8966)

Derived from `knowledge-base/project/plans/2026-09-26-c4-hardening-residuals-plan.md`
(post-review final). Two PRs: PR-A (plugin writer parity, `Closes #8861`) and PR-B
(derived staleness, `Ref #8966`).

## Phase 1 — PR-A: writer parity

### 1.1 Flag + gate parity
- [ ] 1.1.1 `plugins/soleur/scripts/render-c4-model.sh`: add `--no-use-dot` to the npx
      `export json` invocation (:115); add `jq -e '(.views | length) > 0'` refusal beside
      the elements gate (:143) with the #8740 rationale comment.
- [ ] 1.1.2 `plugins/soleur/scripts/generate-c4-from-components.ts`: `"--no-use-dot"` in
      the spawnSync argv (:260).
- [ ] 1.1.3 `plugins/soleur/lib/c4-from-components.ts`: `countModelJson` gains `views`;
      `assessRender` gains `viewCount` input + `zero-views` status between element and
      relationship checks; audit `C4_MARKER_FIELDS`/`zeroCounts` ripple; fix the
      `toEqual` assertions at `test/c4-from-components.test.ts:308,315-316`.

### 1.2 Guard + tests
- [ ] 1.2.1 `plugins/soleur/test/c4-canonical.test.ts`: extend the writer census
      (:217-243) — per-member `--no-use-dot` (both invocation spellings incl.
      `export json --no-use-dot -o`) + views-gate marker (`views | length` in `.sh`,
      `viewCount` at the `.ts` writer's `assessRender` call site). Keep the floor
      assertion on the three known members; note the app-side `RENDER_SCRIPT` ownership.
- [ ] 1.2.2 Mutation-verify the Guard Contract matrix (5 rows: drop flag, drop
      `viewCount` arg, add non-compliant writer, vacuous census, comment-only fixture
      must-PASS).
- [ ] 1.2.3 `plugins/soleur/test/render-c4-model.test.sh`: zero-view row on the stub
      fixture (:123); bump `cases_run` floor (:221-224).

### 1.3 Docs
- [ ] 1.3.1 `plugins/soleur/skills/architecture/references/likec4-reference.md`: pin
      literal `likec4@1.50.0` + `--no-use-dot` on BOTH :112 (`validate`) and :113
      (`export`).
- [ ] 1.3.2 ADR-050 2026-09-25 addendum: supersede banner (plugin parity landed).

### 1.4 PR-A close-out
- [ ] 1.4.1 PR body: `Closes #8861` + `Ref #8966`; run plugin test suite +
      `c4-model-freshness.test.sh` green.

## Phase 2 — PR-B: derived staleness

### 2.1 Server derivation
- [ ] 2.1.1 `apps/web-platform/server/c4-staleness.ts` (new): `deriveDiagramStale` —
      `commits?path=${githubDir}/model.likec4.json&per_page=1` → M; `git/trees` walk to
      the dir subtree; set/sha compare of `LIKEC4_SOURCE_EXTENSIONS` entries vs current
      listing; on diff, `commits?path=<dir>&per_page=1` tip-age grace window (~render
      budget, OQ2 — pin against `c4-render.ts` timeout); all failures →
      `reportSilentFallback(feature=c4-project-read, op=stale-derivation)` + `undefined`.
      `M` empty → `undefined`.
- [ ] 2.1.2 `app/api/kb/c4/project/route.ts`: call it after the listing (:196-206); emit
      `stale` only when a verdict was produced.
- [ ] 2.1.3 `server/cc-dispatcher.ts`: counted `feature=c4-save-outcome` events on all
      three outcomes at the emit site (:2342-2367).

### 2.2 Client precedence + copy
- [ ] 2.2.1 `c4-shared.tsx`: `ProjectResponse` + `setData` rebuild (:55-61, :113-119)
      carry `stale`; drive-by fix the stale comment at :387.
- [ ] 2.2.2 Shared reconcile helper (sibling lib or c4-shared): banner =
      `data.stale` when present; outcome applies only when absent; supersede-shape
      outcomes (`rerendered:false`, no diagnostic) never self-set; outcome diagnostic
      only under a true banner.
- [ ] 2.2.3 `c4-workspace.tsx` + `c4-diagram.tsx`: both consume the shared helper —
      identical behavior.
- [ ] 2.2.4 `c4-diagnostics.tsx`: `aria-live="polite"` on the amber strip; line-2 copy
      via resolved props — flag-on → `SUPERSEDED_LINE`; flag-off + canonical →
      "Ask the Concierge to re-render this diagram"; non-canonical → OTHER_DIR shape.
      No flag hook inside the module (consumers pass props).

### 2.3 Tests
- [ ] 2.3.1 `test/c4-project-route.test.ts`: `setupGitHub` gains `/commits` +
      `/git/trees` arms + an assertion the calls issued.
- [ ] 2.3.2 `test/c4-staleness.test.ts` (new): pure-comparator matrix — same set/sha →
      not stale; modified/added/deleted source → stale; `.md`-only diff → not stale;
      `.likec4`/`.like-c4` covered; `M` absent → absent; grace window → absent.
- [ ] 2.3.3 `c4-workspace.test.tsx` / `c4-diagram.test.tsx`: precedence rows —
      present-authoritative, absent-untouched (frame-set banner survives), supersede
      defers, remount resurrection via GET.
- [ ] 2.3.4 `c4-shared.test.tsx`: normalization carries `stale`.

### 2.4 ADR + PR-B close-out
- [ ] 2.4.1 ADR-050 addendum: tree-diff derivation, grace window, ordering-subsumption
      decision (issue's `saveSeq` proposal superseded — cite plan review).
- [ ] 2.4.2 PR body: `Ref #8966`; run web-platform test suite green.

## Phase 3 — Lifecycle

- [ ] 3.1 `soleur:review` on each PR (incl. `user-impact-reviewer` — threshold is
      single-user incident).
- [ ] 3.2 QA: verify the banner resurrects on remount (synthetic: committed `.c4` with
      model predating it).
- [ ] 3.3 `soleur:compound` learnings; `soleur:ship` per PR; close #8966 when both merge.
