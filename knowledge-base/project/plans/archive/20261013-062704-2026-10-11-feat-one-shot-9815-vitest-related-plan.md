---
title: "webplat vitest: narrow local affected runs to `vitest related` on the changed app files (#9815)"
type: feat
date: 2026-10-11
slug: feat-one-shot-9815-vitest-related
branch: feat-one-shot-9815-vitest-related
issue: 9815
closes: 9815
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# webplat vitest: narrow local affected runs to `vitest related` on the changed app files (#9815)

## Enhancement Summary

**Deepened on:** 2026-10-11 (sequential-fallback — no Task/subagent spawn on
this harness; every research lane ran in-process and none claims independent
review). Deepening here means *running the pinned binary*: a scratch npm
install of `apps/web-platform` (vitest **4.1.11**, matching the `^4.1.11` pin
in `apps/web-platform/package.json:110`) plus a synthesized three-file vitest
project drove every `related` claim below against the real CLI, and two
module-graph probes ran against the real app config.

**Sections enhanced:** Proposed Solution (corrected flag spelling),
meta-fallback set (measured, not guessed), eligibility predicate (the exact
`_AFFECTED`/`_aff_fallback`/`TEST_GROUP` conjuncts), Guard Contract (the
splice-window and registration-anchor analysis), Sharp Edges (six new, all
measured), Alternatives (`vitest run --related` falsified; `--changed`
rejected on diff-source drift).

### Key Improvements over the issue text

1. **The issue's flag spelling does not exist at the pinned version.**
   `vitest run --related` throws `CACError: Unknown option '--related'`
   (measured, vitest 4.1.8 and 4.1.11). The real form is the **subcommand**
   `vitest related <files...> --run --project <name>` — and it cannot be
   expressed through `npm run test:ci` (that script *is* `vitest run`), so
   the narrowing invocation calls `node_modules/.bin/vitest` directly — the
   binary the webplat arm's own precondition probe already requires.
2. **Zero-related exits 0.** `vitest related <uncovered>` prints
   `No test files found, exiting with code 0` and **exits 0** — the exact
   silent-green shape the issue's AC(c) exists to forbid. The wrapper must
   grep the marker; it cannot trust rc (measured).
3. **`setupFiles`/`globalSetup` are invisible to `related`** — verified on
   the real `vitest.config.ts`: `related test/setup-node.ts` resolves zero
   files. They would self-heal through the zero-fallback anyway; the meta
   set makes the intent explicit.
4. **`related` sees only static imports** (vitest docs) — three non-literal
   `import(<var>)` sites exist in `server/inngest/functions/cron-ux-audit.ts`;
   recorded as an accepted residual in Sharp Edges.
5. **Two measured resolution samples** (this worktree's install):
   `lib/feature-flags/lru-cache.ts` → 133 unit test files in 19.97s;
   `lib/safety/redaction-allowlist.ts` → 203 unit files in 44.47s;
   `components/ui/button.tsx` → 185 component files in 44.24s. The
   narrowing works and is transitive; breadth is graph-position-dependent —
   the worst measured case is still ~half the full-project cost (~82s unit,
   ~80s bundle).

## Overview

`apps/web-platform [unit]` is edge-selected on `WEBPLAT_APP_PATHS`: any diff
touching `apps/web-platform/` pays the full unit project (~82 s local,
`baseline-timing.tsv` sibling record). `apps/web-platform
[repo-wide+component]` is exempt from affected selection by design
(`_suite_affected` exempt list, `scripts/test-all.sh:3496`) and pays ~80 s on
every local run whose group includes it (`want_webplat`: `all`, `webplat`,
`affected` — `scripts/test-all.sh:1337`).

Vitest 4.1.x ships `vitest related <files> --run`, which runs only test files
covering the named source files through the static module graph. This plan
narrows the *invocation* inside the two labels — never the selection — when
the local run is affected-shaped: the runner derives the changed
`apps/web-platform/` file list from `$_diff_names`, declines narrowing on a
measured meta-file set and on every eligibility miss, and the wrapper falls
back to today's byte-identical full invocations whenever the list is empty
or `related` resolves zero test files. `repo-wide` is never narrowed (its
subject is the repository, not the app import graph); `component` and `unit`
are.

CI is unchanged: the `CI` conjunct keeps every CI leg on the current
single-invocation command.

## Problem Statement

The affected gate (ADR-242) already decides *whether* the webplat vitest
suites run; it cannot decide *how much of the project* runs, because the
registration dispatches `npm run test:ci -- --project unit` — the full
project — unconditionally once the edge fires. On a one-file app diff the
local gate still pays ~82 s for `unit` plus ~80 s for the bundle, the two
heaviest line items of an affected run. The #8322 spec anticipated exactly
this follow-up: "`vitest related` refinement is follow-up"
(`knowledge-base/project/specs/archive/20260920-163321-feat-8322-affected-test-gate/spec.md:39`).

## Proposed Solution

Three wired pieces; no selection machinery changes.

1. **`scripts/lib/test-relevance-paths.sh` gains the meta set and two pure
   functions** beside `WEBPLAT_APP_PATHS` (:329):

   - `WEBPLAT_RELATED_META=( ... )` — repo-root paths whose change must run
     the full projects (measured set below). Membership is checked against
     the **whole** diff, not only app paths, because two entries live
     outside the app.
   - `webplat_related_meta_hit <diff_names_blob>` — prints the first meta
     path present in the blob, rc 1 when none (pure, fixture-drivable).
   - `webplat_related_files <diff_names_blob>` — tokenizes the blob with the
     same `IFS=$' \t' read -ra` convention `_AFFECT_PATTERNS` uses
     (`test-all.sh:3457-3488` — it keeps `R100<TAB>old<TAB>new` both paths
     and drops status tokens), keeps tokens under `apps/web-platform/`,
     strips the prefix, dedupes (`LC_ALL=C sort -u`), prints app-relative
     paths one per line.

   Both are pure functions of their argument — no runner state, no git — so
   the new suite drives them against synthetic diffs exactly like
   `test-all-fast-tier-budget` drives `check_tier`.

2. **`scripts/test-all.sh`, inside `if want_webplat; then` (splice window
   :4785–:6728 — sandbox-immune, see Guard Contract)** — before the first
   `run_suite` of the arm, compute:

   ```bash
   _webplat_related=""
   if (( _ENUMERATE == 0 )) && [[ -z "${CI:-}" ]] \
      && [[ "${SOLEUR_TEST_FORCE_ALL:-}" != "1" ]] \
      && [[ "$_diff_detect_ok" == "1" && "$_diff_head_ok" == "1" ]] \
      && { [[ "$TEST_GROUP" == "affected" ]] \
           || { (( _AFFECTED == 1 )) && [[ -z "$_aff_fallback" ]]; }; }; then
     if _meta="$(webplat_related_meta_hit "$_diff_names")"; then
       echo "[vitest-related] meta path in diff (${_meta}) — webplat vitest runs the FULL projects." >&2
     else
       _webplat_related="$(webplat_related_files "$_diff_names")"
     fi
   fi
   ```

   Every conjunct is load-bearing: `CI` keeps AC(d); `FORCE_ALL` means
   "run everything" and must not narrow; the diff-ok flags mean an
   undecidable diff narrows nothing; `_AFFECTED==1 && -z _aff_fallback`
   covers the default local gate AND group-scoped affected runs while
   declining under `force-all`/`index-missing`/`undecidable-diff`/
   `runner-changed` degradation (a degraded run is a full battery — the
   ADR-242 decision-3 doctrine, applied one level down); `TEST_GROUP ==
   affected` covers the heuristic selector, which has no `_aff_fallback`
   axis and needs none — the related list reads the raw diff, not the
   selector's verdicts. Under `_ENUMERATE`, `_webplat_related` stays `""`
   so the command record prints `WEBPLAT_RELATED=""` deterministically.

   Both registrations stay **exactly two lines** (the `m2` mutator in
   `test-all-webplat-gate.test.sh:141` deletes `run_suite …,+1d`) and gain
   one `env` var (never exported — nested-runner children must not inherit
   a stale list; the #9814 learning's env-scrub class):

   ```bash
   run_suite "apps/web-platform [repo-wide+component]" env VITEST_SHARD="${VITEST_SHARD:-}" \
     WEBPLAT_RELATED="${_webplat_related:-}" \
     bash apps/web-platform/scripts/vitest-related.sh bundle

   if _diff_touches "${WEBPLAT_APP_PATHS[@]}"; then
     run_suite "apps/web-platform [unit]" env VITEST_SHARD="${VITEST_SHARD:-}" \
       WEBPLAT_RELATED="${_webplat_related:-}" \
       bash apps/web-platform/scripts/vitest-related.sh unit
   else
     ... unchanged skip_suite path ...
   fi
   ```

   (Shown at 3 lines for readability; landed as label+env on line 1,
   command on line 2 — the two-line `\+ continuation` shape the anchors
   require.)

3. **`apps/web-platform/scripts/vitest-related.sh`** (new; the repo's
   `scripts/foo.sh` + `scripts/foo.test.sh` convention):

   ```text
   vitest-related.sh unit    — narrow-or-full for --project unit
   vitest-related.sh bundle  — --project repo-wide FULL (always), then
                               narrow-or-full for --project component
   ```

   It `cd`s to its own app root (`cd "$(dirname "$0")/.."`), reads
   `WEBPLAT_RELATED` (newline-separated, `mapfile -t`; empty → full path),
   and per narrowable project:

   ```bash
   node_modules/.bin/vitest related "${files[@]}" --run --project "$proj" 2>&1 | tee "$_cap"
   ```

   — `--run` is load-bearing (docs: `related` defaults to watch), the
   project filter is per-invocation, and the related argv paths are
   app-relative ("all files should be relative to root folder", vitest
   docs). After the run it greps `$_cap` for `No test files found`; a hit
   runs `npm run test:ci -- --project "$proj"
   ${VITEST_SHARD:+--shard="$VITEST_SHARD"}` — today's full invocation —
   and prints `VITEST_RELATED project=$proj inputs=<n> outcome=full-zero`.
   A nonzero related rc propagates with **no** fallback (a red is a
   verdict, not a coverage gap). `bundle` mode always runs `repo-wide`
   full first and `component` after, capturing both rcs — today's single
   invocation runs both projects unconditionally, and the split form must
   preserve that (an `&&` would skip `component` on a repo-wide red, a
   silent coverage loss inside the suite). `VITEST_SHARD` is forwarded
   only on full invocations — the narrowed path is local-only and shard is
   unset there; `--shard` + `related` is never combined.

   Receipts (stdout, greppable, `AFFECTED_*`/`WEIGHT_DRIFT` convention):
   `VITEST_RELATED<TAB>project=<p><TAB>inputs=<n><TAB>outcome=related|full-zero|full-empty`.

### The measured meta-fallback set (`WEBPLAT_RELATED_META`)

Derived from the actual layout — every file that changes *what the run
means* or every test's environment while being invisible (or partial) to the
per-test module graph:

```text
apps/web-platform/vitest.config.ts                  # project definitions, pools, timeouts
apps/web-platform/test/vitest.canary.config.ts      # second vitest config (mutation batteries)
apps/web-platform/test/repo-wide-suites.ts          # project membership — imported by the config
apps/web-platform/test/repo-wide-containment.test.ts # the guard that makes app-local narrowing sound (doctrine)
apps/web-platform/test/setup-node.ts                # setupFiles for unit+repo-wide — verified invisible to related
apps/web-platform/test/setup-dom.ts                 # setupFiles for component — verified invisible
apps/web-platform/test/global-setup-git-tripwire.ts # globalSetup — verified invisible
apps/web-platform/package.json                      # scripts + deps (partial-resolve risk: tests import it)
apps/web-platform/package-lock.json                 # resolved dep graph
apps/web-platform/tsconfig.json                     # esbuild transform of every module
apps/web-platform/.npmrc                            # install semantics
apps/web-platform/.nvmrc                            # toolchain
apps/web-platform/scripts/vitest-related.sh         # the narrowing mechanism never narrows its own diff (self-reference)
scripts/lib/test-relevance-paths.sh                 # the gate predicate — "a commit that NARROWS this predicate
                                                    #  must run the suite the predicate gates" (existing comment)
```

Explicitly **not** meta, with the reasoning measured:

- `test/helpers/**`, `test/mocks/**`, `test/fixtures/**` (48 non-test files)
  — imported members of the module graph; `related` resolves their
  importers correctly (verified: a helper input resolved exactly its
  importing test). The issue's "shared helpers" prompt is satisfied by the
  graph, not the list — narrowing on a helper diff is *correct* coverage.
- `next.config.ts`, `middleware.ts`, `instrumentation.ts`,
  `sentry.*.config.ts`, `eslint.config.mjs`, `postcss.config.mjs`,
  `playwright.config.ts`, `bunfig.toml`, `.dependency-cruiser.*` — app
  source/config whose coverage, if any, runs *through* importers; whatever
  resolves is the right set, and zero resolves to the full fallback anyway.
- `test/rls-fuzz/**`, `test/migration-lint/**` — ordinary imported members.

### Eligibility, precisely

Narrowing is active iff ALL of: `_ENUMERATE==0`, `CI` unset,
`SOLEUR_TEST_FORCE_ALL != 1`, `_diff_detect_ok==1`, `_diff_head_ok==1`, and
(`TEST_GROUP == affected` OR (`_AFFECTED==1` AND `_aff_fallback` empty)).
Notes verified against the runner:

- `_AFFECTED` arms on every local non-`--full` run whose group ask is not
  `affected` (`test-all.sh:414-424`) — including `TEST_GROUP=webplat`, where
  the pre-pass is group-scoped off (`:3717-3721`) and `_aff_fallback` stays
  empty, so narrowing still applies. Consistent: the list is diff-derived,
  not selection-derived.
- `TEST_GROUP=affected` runs the same arm (`want_webplat` includes it) and
  its `_suite_affected` exempt list already always-runs both labels — the
  narrowing is strictly inside the invocation.
- The `runner-changed` fallback (`_aff_fallback` non-empty, `:3749-3764`)
  degrades branch-scope affected runs to the full battery; the conjunct
  re-uses that verdict so a degraded-full run never narrows inside itself.

## Technical Approach

### How the diff reaches the invocation

`$_diff_names` is assembled at `test-all.sh:1949-2075`: `git diff
--name-only HEAD`, `origin/main...HEAD`, `--name-status -M` rename rows
(both old and new paths), untracked appends, the staged-scope
`git diff --cached` variant, and the `--paths` fabricated list. The
computation tokenizes it exactly like `_AFFECT_PATTERNS` (:3457-3488): per
line, `IFS=$' \t' read -ra` keeps every path field and drops status tokens
(`M`, `R100` — no `/`, no `.`). Keep tokens starting `apps/web-platform/`,
strip the prefix, dedupe. Deleted files stay in the list (vitest tolerates
nonexistent inputs — they contribute zero); a rename contributes both
sides. Paths containing spaces or tabs produce no clean token — an
accepted limitation identical to `_AFFECT_PATTERNS`'s: the file then
contributes nothing to the list, and if it was the only app change the
zero-fallback runs full (fail-safe direction, never silent narrowing).

### Where the narrowing lives — the splice-window answer

Runner-SUT suites copy `test-all.sh` wholesale and replace the
`tc_acquire`→`tc_epilogue` window (`test-all.sh:4785`/`:6728`) with fixture
registrations; everything *above* the window rides into every sibling
sandbox (the just-landed learning
`knowledge-base/project/learnings/2026-10-11-a-runner-arm-above-the-splice-window-fires-inside-every-sibling-sandbox.md`,
landing with #9814). Placement consequences, all deliberate:

- The whole computation sits **inside** `if want_webplat` — inside the
  window — so it is spliced out of every sandbox: zero fixture exposure.
- `WEBPLAT_RELATED_META` and the two functions live in
  `scripts/lib/test-relevance-paths.sh`, sourced above the window — they
  ride in, but a data array and two function *definitions* are inert; the
  learning's hazard is default-armed *side-effects*, not symbols.
- `WEBPLAT_RELATED` travels via `env` per registration — never exported —
  so a nested runner child cannot inherit a parent's list (the same
  learning's env-scrub half).

## Implementation Phases

- **Phase 1 — lib + suite RED.** Write
  `apps/web-platform/test/vitest-related.test.sh` with the arm set in Test
  Scenarios (RED: wrapper and lib functions absent), then implement
  `webplat_related_meta_hit` / `webplat_related_files` /
  `WEBPLAT_RELATED_META` in `scripts/lib/test-relevance-paths.sh` and
  `apps/web-platform/scripts/vitest-related.sh` to GREEN. The suite obeys
  the three always-on-ratchet constraints from the `2026-10-05` learning:
  one owning `trap … EXIT` over every `mktemp` operand, provably-absolute
  fixture roots, per-arm env scrub (`env -u TEST_GROUP`, never inherit
  `CI`/`WEBPLAT_RELATED`).
- **Phase 2 — runner wiring.** In `scripts/test-all.sh`'s `want_webplat`
  arm: add the computation block (after the node_modules precondition,
  before the first `run_suite`), add the `WEBPLAT_RELATED` env var to both
  registrations, retarget the commands at the wrapper — each registration
  kept to exactly two lines, every nested `fi` indented, and **no
  `_diff_touches` literal anywhere in the computation** (the A3 arm's awk
  terminates its `UNGATED` extraction on the first match).
- **Phase 3 — register + classify.** `run_suite
  "apps/web-platform/test/vitest-related.test.sh" bash
  apps/web-platform/test/vitest-related.test.sh` inside the same arm (the
  `destroy-ask-mutation` precedent: `apps/web-platform/test/*.test.sh`
  matches no `SUITE_GLOBS` entry and the suite needs the app's
  `node_modules`, which the arm's precondition probe guarantees), plus an
  `AFFECTED_APPS_WEB_PLATFORM_TEST_VITEST_RELATED_PATHS` block in
  `scripts/lib/test-affected-paths.sh` = { the suite, the wrapper,
  `scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`,
  `apps/web-platform/vitest.config.ts` (the meta-derivation arm's subject),
  `scripts/lib/test-affected-paths.sh` (self-inclusion convention) }.
- **Phase 4 — measurement + ADR-242 amendment.** Record the before/after
  table (method in Success Metrics) into the spec's measurements file, and
  append a dated `## Amendment — 2026-10-11 (#9815)` section to ADR-242.

## Files to Edit

- `scripts/test-all.sh` — computation block + two registration retargets +
  one `run_suite` line, all inside `want_webplat` (:6272–:6379).
- `scripts/lib/test-relevance-paths.sh` — `WEBPLAT_RELATED_META` +
  `webplat_related_meta_hit` + `webplat_related_files` beside
  `WEBPLAT_APP_PATHS` (:329).
- `scripts/lib/test-affected-paths.sh` — one `AFFECTED_*_PATHS` edge block.
- `knowledge-base/engineering/architecture/decisions/ADR-242-*.md` — dated
  amendment (Phase 4).

## Files to Create

- `apps/web-platform/scripts/vitest-related.sh` — the invocation wrapper.
- `apps/web-platform/test/vitest-related.test.sh` — the suite.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| `vitest run --project unit --related <files>` (the issue's literal proposal) | **Does not exist** at 4.1.8/4.1.11 — `CACError: Unknown option '--related'` (measured). The real spelling is the `related` subcommand, unreachable through the `test:ci` npm script, so the invocation needs `node_modules/.bin/vitest` regardless. |
| `vitest run --changed [since]` | A second, *different* diff source: vitest's own git query vs the runner's `_diff_names` (branch window + staged scope + untracked + rename-source + `--paths`). Two diff answers that can disagree is the drift class the runner's whole derivation machinery exists to prevent; the runner's diff is authoritative. |
| Narrow by positional test-file args (`vitest run <changed test files>`) | Only runs files that *are* tests — misses every test that covers a changed *source* file, which is the common case. `related` exists precisely to bridge source→test through the graph. |
| Decline `[unit]` when `related` resolves zero but `component` covers the diff | Violates the issue's own AC(c) and the zero-selected refusal doctrine — zero resolution reads as "no coverage", never as "green, skip it". Recorded as an accepted limitation: a pure `.tsx`-only diff still pays full `unit`. |
| Narrow `repo-wide` too | Its subject is the repository (#7498) — its tests read plugin scripts, workflow YAML and the knowledge base through `fs`, not the app import graph. `related` on app files resolves ~zero repo-wide tests, so narrowing it would be the silent-green vacuity the whole design refuses. |
| Put the meta check wrapper-side | The wrapper only sees the app-relative list; two meta entries live outside the app (`scripts/lib/test-relevance-paths.sh` and the list's own self-reference semantics). The runner owns the whole-diff check; the wrapper owns zero-fallback. |
| Compute the file list inside the `bash -c` | The suite child cannot see `$_diff_names` unexported, and re-deriving git state inside the suite forks the diff source (the `--changed` objection, one level down). |
| `--passWithNoTests` + rc-based zero detection | rc is 0 on zero-related regardless — detection must read the marker text; `--passWithNoTests` would make an empty full-project run *also* green, weakening the fallback's evidence. |
| Inline the branching in the `bash -c` string | Keeps `npm run test:ci` in the argv (battery-tag ledger stays warm) but buries a state machine in a quoted string — untestable, ungreppable. A named script is the repo convention and gets a real suite. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a local `test-all.sh` run
  whose webplat vitest legs silently cover *less* than the diff needs —
  the worst shape is the inverse failure (a narrowing that pretends to be
  coverage), which is exactly what the zero-marker grep, the meta set, and
  the eligibility conjuncts exist to prevent. In the other direction a
  broken computation degrades to today's full runs — slower, never wrong.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no data surface; the exposure is *workflow* — the fast-feedback gate
  producing green-shaped output over coverage it did not obtain.
- **Brand-survival threshold:** `single-user incident` — same class the
  #9813 and #9814 plans rated for runner-side coverage gates: no end user
  is touched, but a defect in the default local gate is an availability /
  trust incident for the caller class this repo serves.

*Scope-out override:* n/a.

CPO sign-off required at plan time before `soleur:work` begins — invoke the
CPO domain leader or confirm prior coverage;
`soleur:engineering:review:user-impact-reviewer` is invoked at review time.

## Observability

```yaml
liveness_signal:
  what: VITEST_RELATED<TAB>project=<p><TAB>inputs=<n><TAB>outcome=related|full-zero|full-empty receipt lines inside each webplat suite's output, plus the runner-side "[vitest-related] meta path in diff" stderr banner
  cadence: once per webplat label per local affected-shaped run (absent entirely on CI and under --full)
  alert_target: none — local dev tooling; lines are visible in suite output and in the per-suite tee'd logs
  configured_in: apps/web-platform/scripts/vitest-related.sh (receipts) + scripts/test-all.sh (meta banner)
error_reporting:
  destination: suite stdout/stderr (captured by the runner's per-suite tee)
  fail_loud: a zero-resolution or meta-hit is *announced* (receipt + banner), never silent — the failure class is a quiet narrow, and both detectors print their verdict
failure_modes:
  - mode: related marker text changes on a vitest upgrade → zero-resolution goes undetected and green-silences
    detection: the suite's real-binary arm drives the actual installed vitest on a zero-match fixture and asserts the marker — a bump that changes the text reds the arm
    alert_route: apps/web-platform/test/vitest-related.test.sh RED on the bump diff
  - mode: meta set drifts from vitest.config.ts (a new setupFiles/globalSetup entry)
    detection: B4 arm re-derives the setup/config set from vitest.config.ts + package manifest and diffs against the array
    alert_route: suite RED on the config edit that adds a run-semantics file without updating META
  - mode: related resolves a nonzero but wrong set (dynamic-import blind spot)
    detection: no automated detector — bounded residual (3 non-literal import sites), documented in Sharp Edges; the zero-fallback covers the common single-diff case
    alert_route: code review + this plan's recorded residual
  - mode: eligibility regression (CI narrows, FORCE_ALL narrows, degraded-full narrows)
    detection: fixture arms drive each conjunct's diff+env shape through the lib functions and the arm-text assertions pin the conjuncts' presence
    alert_route: suite RED at the mutating diff
logs:
  where: suite stdout/stderr, per-suite tee'd logs under the run's _suite_log_dir
  retention: console lifetime; durable copies only for non-ok suites (existing runner retention)
discoverability_test:
  command: rg -n VITEST_RELATED apps/web-platform/scripts scripts/lib
  expected_output: VITEST_RELATED
```

## Encryption Posture

```yaml
# No persistent store and no new cross-component connection. The wrapper
# captures vitest output to a mktemp file inside the run — same class as the
# runner's existing per-suite tee'd logs, deleted with the suite's fixture.
at_rest: []
in_transit: []
```

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
with a dated `## Amendment — 2026-10-11 (#9815)` section (the ADR's own
convention — single Decision followed by dated amendments, latest `#9813`
2026-10-10): **"the affected gate's fail-toward-coverage doctrine extends
inside the two webplat vitest labels — `vitest related` narrows the
invocation on a local affected-shaped run, and a meta-file hit, an empty
candidate list, or a zero-resolution all take the full project."** Record:
the corrected subcommand spelling, the measured meta set, the eligibility
conjuncts (including the `_aff_fallback` reuse — a degraded-full run never
narrows inside itself), the repo-wide-never-narrowed boundary, and that
selection machinery (`_suite_affected`, `ALWAYS_ON_SUITES`,
`AFFECTED_CONSUMED_EDGES`) is untouched — this is intra-suite narrowing,
not selection. Alternatives table gains: `vitest run --related`
(falsified — flag does not exist), `--changed` (rejected — second diff
source), positional filters (miss source→test coverage), skip-on-zero
(violates the refusal doctrine).

### C4 views

No C4 impact — checked against `knowledge-base/engineering/architecture/diagrams/`:
no new actor, external system, container, or data store; the local gate is
below modeled granularity (same verdict as #9814).

### Sequencing

True at merge — a single `status: accepted` amendment, no adopting window.
Order vs #9814 (in merge queue, not yet on main): either order merges
cleanly — #9814's arm is above the window near `_durable_log_dir`, this
plan's are inside `want_webplat`; the only contact is the shared learning,
which this plan already obeys. **Note for the merger:** if #9814 lands
first, its timing rows make the before/after measurement cheaper (read
`TEST_TIMING_LOG` rows instead of manual timings); if this lands first,
#9814's weight-drift will simply observe these labels' *narrowed* local
timings — honest data, no conflict.

## Guard Contract

### Guard 1 — narrow-or-full predicate (wrapper + lib functions)

**Property.** For a local affected-shaped run whose diff's app-file set
contains no meta path, the narrowable projects run `vitest related` on the
changed files; on a meta hit, an empty candidate set, or a `No test files
found` resolution, they run today's exact full invocation; and on any
eligibility miss (CI, FORCE_ALL, degraded fallback, undecidable diff,
enumerate) the suite command executes the unmodified full path. `repo-wide`
runs full in every shape. A nonzero related rc propagates without a
fallback re-run; a `bundle` run always executes both halves.

**Assembly.** Three sites: `webplat_related_meta_hit` /
`webplat_related_files` / `WEBPLAT_RELATED_META` (lib, pure functions of
`$_diff_names`), the eligibility block (runner, in-window), and the
wrapper's related-invocation + marker grep + full fallback
(`apps/web-platform/scripts/vitest-related.sh`). Identity set = tokens of
`$_diff_names` under `apps/web-platform/`; the meta set is a fixed
substring membership check.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `No test files found` grep removed | RED — zero-resolution fixture reports outcome=related having run 0 files |
| 2 | `--run` dropped from the related invocation | RED — static arm pins the flag; without it `related` enters watch and never exits (docs) |
| 3 | `vitest.config.ts` removed from META | RED — meta-diff fixture must produce outcome=full, not a narrowed list |
| 4 | `-z ${CI:-}` conjunct dropped | RED — CI=1 fixture shape must yield an empty `_webplat_related` |
| 5 | `_aff_fallback` conjunct dropped | RED — runner-changed diff shape must yield empty (degraded-full never narrows inside itself) |
| 6 | `FORCE_ALL` conjunct dropped | RED — FORCE_ALL=1 fixture must yield empty |
| 7 | `bundle` reordered to `&&` (component skipped on repo-wide red) | RED — the both-halves arm asserts component executes after a repo-wide failure |
| 8 | Marker grep matches a substring of a real test line | PASS-by-construction — the marker is anchored on vitest's exact phrase; a fixture line containing it still behaves correctly (treated as zero → full, the safe side) |
| 9 | Must-PASS: covered-source fixture runs only its importer set | PASS — file count < project total, outcome=related, rc propagates |
| 10 | Must-PASS: deleted-path input contributes zero without error | PASS — union semantics verified, nonexistent input is ignored by vitest |

**Anchor.** The zero detector keys on vitest's stdout phrase — a
version-pinned string. The suite's synthesized-project arm runs the real
installed binary, so a vitest bump that rewords the marker turns the arm
red on the bump diff itself — the detector is self-checking.

### Guard 2 — meta-set derivation + registration anchors

**Property.** `WEBPLAT_RELATED_META` names every run-semantics file:
`vitest.config.ts` and `vitest.canary.config.ts` (the `test/vitest*.config.*`
glob on disk), every `setupFiles:`/`globalSetup:` entry parseable from
`vitest.config.ts`, the `repo-wide-suites` config import, the package
manifest pair, `tsconfig.json`, `.npmrc`, `.nvmrc`, the containment guard,
the wrapper itself, and the predicate lib — each entry a file that exists
on disk. And the runner text keeps every sibling-suite anchor: the two
registrations remain two-line `run_suite` statements, the computation block
contains no `_diff_touches` literal, and no column-0 `fi` appears inside
the `want_webplat` block before its close.

**Assembly.** The suite derives the expected set from `vitest.config.ts`
(grep `setupFiles:`/`globalSetup:`/`repo-wide-suites`) + `find
apps/web-platform -maxdepth 1` + `test/vitest*.config.*` and diffs against
the array; the anchor arms grep the `want_webplat` block
(`test-all-webplat-gate.test.sh`'s own `extract_block` idiom) for the
structural invariants.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A `setupFiles` entry added to a fixture config without a META update | RED — derivation diff is non-empty |
| 2 | META entry deleted (e.g. `test/setup-dom.ts`) | RED — present-in-config but absent-from-array |
| 3 | Registration grows a third line | RED — two-line assertion; also m2's `,+1d` mutator in the sibling suite would break, which it detects |
| 4 | `_diff_touches` literal inserted into the computation block | RED — static arm; the sibling suite's A3 UNGATED extraction would silently truncate without it |
| 5 | Column-0 `fi` inserted before the arm close | RED — extraction parity arm sees a truncated block |
| 6 | Must-PASS: unrelated app-source diff produces a non-empty related list | PASS — `webplat_related_files` keeps ordinary source tokens |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "when --affected selection is active and the diff touches the app, run `vitest run --project unit --related <changed app files>`" | FR-1/FR-3/FR-4 — eligibility block + `vitest related <files> --run --project unit` via wrapper (spelling corrected — flag does not exist) | mapped |
| 2 | "fall back to the full project when the changed set includes config/meta files (vitest.config.ts, package.json, test/repo-wide-containment.test.ts, shared helpers — enumerate in plan)" | FR-2 — `WEBPLAT_RELATED_META` (measured set above; "shared helpers" resolved to *not*-meta — they are graph members; reconciliation note in Research Insights) | mapped |
| 3 | "or when --related resolves to zero files (zero = 'no coverage', not 'green' — same refusal class as the affected gate's zero-selected refusal)" | FR-3 — marker grep → full; documented that rc is 0 and the marker is the only signal | mapped |
| 4 | AC(a): "app diff touching only app/components/X.tsx runs related files not the whole project (measured before/after)" | FR-3 + Success Metrics — component narrows via related; `unit` documents the zero→full behavior on `.tsx`-only diffs | mapped |
| 5 | AC(b): "config/meta changes still run full" | FR-2 + Guard-2 derivation arm | mapped |
| 6 | AC(c): "--related empty-set falls back to full (fail safe), never silently narrows" | FR-3 + Guard-1 mutations 1, 10 | mapped |
| 7 | AC(d): "CI unchanged — CI legs already run full; local only" | NFR-1 — the `CI` conjunct + full-path byte parity | mapped |
| 8 | "Same for `[repo-wide+component]` (~80s) whenever the webplat arm runs" | bundle mode: repo-wide full (never narrowable) + component related-or-full | mapped — with the honest bound that `repo-wide` itself is not narrowable |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `scripts/lib/test-relevance-paths.sh` (META + functions) | asks 2, 5 | inferred — the lib already owns `WEBPLAT_APP_PATHS`; co-location keeps the gate's declarations in one file and rides sandbox copies inertly |
| `apps/web-platform/scripts/vitest-related.sh` | asks 1, 3, 6 | inferred — the `test:ci` script cannot express the `related` subcommand, and the repo's `foo.sh`/`foo.test.sh` convention wants a named SUT |
| `apps/web-platform/test/vitest-related.test.sh` | — | inferred — Guard Contract matrices must be exercised; house convention |
| eligibility conjuncts incl. `_aff_fallback` | asks 3, 7 | inferred — a degraded run IS a full battery (ADR-242 decision 3); narrowing inside it would silently shrink a deliberately-full run |
| `AFFECTED_*_PATHS` edge block + registration | — | inferred — orphan-census and shard-totality requirements for any new suite |
| `VITEST_RELATED` receipt lines | ask 3 ("never silently narrows") | inferred — observability: the narrow/full verdict must be greppable, matching `AFFECTED_*`/`WEIGHT_DRIFT` convention |
| ADR-242 amendment | — | inferred — the plan changes the local gate's coverage semantics; the decision record must follow |
| both-halves-run rc aggregation in `bundle` | — | inferred — today's single invocation runs both projects unconditionally; `&&` would silently skip `component` on a repo-wide red |

### Split Assessment

- Subsystems touched: 2 — `scripts/` and `apps/web-platform/` (plus the ADR)
- Planned files: 5 edit + 2 create | Estimated changed lines: ~420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 lines
- Recommendation: single PR

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1: on a local affected-shaped run (`_AFFECTED==1` with empty
  `_aff_fallback`, or `TEST_GROUP=affected`) whose diff touches
  `apps/web-platform/` and no meta path, `apps/web-platform [unit]` invokes
  `node_modules/.bin/vitest related <changed app-relative files> --run
  --project unit` — emitting `outcome=related`.
- [ ] FR-2: a diff containing any `WEBPLAT_RELATED_META` path produces an
  empty `_webplat_related`, the stderr meta banner, and today's full
  invocations for both labels.
- [ ] FR-3: a related invocation that prints `No test files found` is
  followed by the full project run for that project — `outcome=full-zero`
  receipt — never a silent green.
- [ ] FR-4: `apps/web-platform [repo-wide+component]` under narrowing runs
  `repo-wide` full unconditionally, then `component` narrow-or-full; both
  halves execute and either half's red fails the suite.
- [ ] FR-5: `VITEST_SHARD` forwards to full invocations only; the narrowed
  path never combines `--shard` and `related`.
- [ ] FR-6: every path token under `apps/web-platform/` in `$_diff_names`
  — including `R100` old+new, staged-scope names, untracked files, and
  `--paths` names — reaches the related argv app-relative.

### Non-Functional Requirements

- [ ] NFR-1: CI is byte-identical — under `CI` the env var is empty and the
  wrapper's full path issues `npm run test:ci -- --project …
  ${VITEST_SHARD:+--shard=…}` exactly as today (AC d).
- [ ] NFR-2: no selection machinery changes — `_suite_affected`,
  `ALWAYS_ON_SUITES`, `AFFECTED_CONSUMED_EDGES`, `WEBPLAT_APP_PATHS`, the
  `_diff_touches` relevance gate, and the `skip_suite` decline path are
  untouched; enumerate records remain deterministic
  (`WEBPLAT_RELATED=""`).
- [ ] NFR-3: every narrowing failure mode degrades to full — ineligible
  run, meta hit, empty list, zero resolution, deleted-file input,
  space-bearing filename — never to a narrowed green.
- [ ] NFR-4: `WEBPLAT_RELATED` is passed via `env`, never exported — nested
  runners inherit nothing.
- [ ] NFR-5: bash-3.2 safe (`mapfile`/`read -ra`/`sort -u`; no `declare
  -A`); no new runner-SUT sandbox exposure (all runner-side code is inside
  the splice window; lib additions are inert symbols).
- [ ] NFR-6: a nonzero related rc propagates with no fallback re-run — a
  red is a verdict, not a coverage gap.

### Quality Gates

- [ ] QG-1: `apps/web-platform/test/vitest-related.test.sh` green —
  synthesized-project arms drive the real installed vitest (4.1.11) for
  narrow/zero/test-file-input/meta/marker shapes; mutation rows all kill.
- [ ] QG-2: `scripts/test-all-webplat-gate.test.sh` green — its A1–A4 +
  M1/M2 anchors survive the retarget (two-line registrations, gate
  unchanged, no column-0 `fi`, no `_diff_touches` in the computation).
- [ ] QG-3: `scripts/test-all-group-affected.test.sh` and
  `scripts/test-all-affected.test.sh` green — exempt-label list and
  sandbox splices untouched (the arm is in-window).
- [ ] QG-4: `scripts/lint-orphan-test-suites.sh` census green with the new
  registration + edge block; shard-totality enumerate parity green.
- [ ] QG-5: `scripts/battery-tag-authorship.test.sh` +
  `scripts/lint-integration-env-gates.test.sh` green — the retargeted argv
  (`env … bash apps/web-platform/scripts/vitest-related.sh …`) classifies
  to a resolvable root, not `UNCLASSIFIED`; if the `npm run test:ci`
  OUT_OF_CLASS ledger entry goes unmatched, adjust it in the same diff and
  re-run the suite (its own contract: re-measure, don't carry forward).
- [ ] QG-6: consumer sweep — `git grep -lE 'test:ci|web-platform
  \[unit\]|repo-wide\+component|WEBPLAT_RELATED|vitest-related' --
  scripts apps/web-platform plugins/soleur/test` enumerated and every
  hit's suite run (QG-5-style manifest sweep per `2026-10-03` SE9).
- [ ] QG-7: `python3 scripts/lint-guard-contract.py` green against this
  plan's Guard Contract.

## Test Scenarios

### Acceptance Tests (RED phase targets)

Wrapper arms drive a **synthesized** vitest project in `mktemp -d`
(three-file module graph: `src/a.ts` → `test/a.test.ts`,
`src/b.ts`→`src/a` → `test/b.test.ts`, `test/c.test.ts` uncovered,
`src/orphan.ts` uncovered) with `node_modules` symlinked to the app's
install — real vitest 4.1.11, synthesized fixtures only
(`cq-test-fixtures-synthesized-only`):

- A1 (narrow): `WEBPLAT_RELATED=src/a.ts` + `unit` → only `a.test.ts` +
  `b.test.ts` run; receipt `outcome=related`; suite rc propagates.
- A2 (zero): `WEBPLAT_RELATED=src/orphan.ts` → marker detected → full
  project executes all three files; receipt `outcome=full-zero`.
- A3 (empty): `WEBPLAT_RELATED=""` → today's exact full invocation;
  `outcome=full-empty`.
- A4 (bundle): `bundle` + `src/a.ts` → `repo-wide` full executes AND
  `component` narrows; a `component` red with green `repo-wide` fails the
  script; a `repo-wide` red still runs `component` (both-halves).
- A5 (self): `WEBPLAT_RELATED=test/c.test.ts` → the file runs itself
  (input-as-test semantics).
- A6 (shard): `VITEST_SHARD=1/2` → forwarded on full invocations, absent
  from the related argv.
- A7 (red-no-refallback): a related set containing a failing test →
  nonzero rc, and the full invocation is NOT subsequently executed.
- A8 (real-binary marker): `related` on a nonexistent path against the
  real binary → asserts the literal `No test files found` phrase — the
  version-bump tripwire.
- A9 (lib units): `webplat_related_files` on a synthetic blob containing
  `R100<TAB>apps/web-platform/old.ts<TAB>apps/web-platform/new.ts`,
  `M<TAB>apps/web-platform/lib/x.ts`, `apps/web-platform/app/y.tsx`, and
  `scripts/z.sh` → emits exactly `app/y.tsx`, `lib/x.ts`, `new.ts`,
  `old.ts`; `webplat_related_meta_hit` on a blob containing
  `apps/web-platform/package.json` → prints it.

### Regression Tests

- B1: both registrations carry `WEBPLAT_RELATED=` via `env` and remain
  two-line `run_suite` statements.
- B2: the computation block contains every eligibility conjunct (CI,
  FORCE_ALL, `_aff_fallback`, `_ENUMERATE`, both `_diff_*_ok`, both axes).
- B3: the computation block contains no `_diff_touches` literal and the
  `want_webplat` block contains no new column-0 `fi` before its close
  (extraction parity with `test-all-webplat-gate`).
- B4: META derivation — re-derive the setup/config set from
  `vitest.config.ts` + disk and diff against the array; every array entry
  exists on disk.
- B5: `[unit]`'s relevance gate and `skip_suite` decline path unchanged
  (delegated — `test-all-webplat-gate` stays green).

### Edge Cases

- Deleted source file → contributes a dead token; union resolves the rest;
  if alone → `full-zero`, and the full run catches the now-broken
  importer.
- Diff of *only* `scripts/lib/test-relevance-paths.sh` → `[unit]` selected
  via `WEBPLAT_APP_PATHS` but meta hits → full unit (doctrine: the guard
  runs on the diff that changes it).
- `.tsx`-only diff → `component` narrows, `unit` resolves zero →
  `full-zero` (recorded limitation; the alternative violates AC c).
- `--affected-scope=staged` → list is the index's paths, resolved against
  the worktree graph (paths are the selection; the graph is current —
  fail-safe direction).
- Diff touching `apps/web-platform/test/helpers/x.ts` → resolves the
  importing tests only — correct narrowing (helpers are graph members).
- Very large app diff (hundreds of files) → related resolves a broad
  subset ≈ full cost; still correct, never broader than full.

## Success Metrics

Method: on a branch whose diff touches only app files, run the affected
gate (or drive the wrapper directly) and read the suite's
`VITEST_RELATED` receipts + wall time; compare against the label's
committed baseline (`baseline-timing.tsv`: `repo-wide+component` 81,554
ms; `unit` ~82 s issue-stated). Already measured on this worktree's
install (vitest 4.1.11, recorded for the measurements file): `related
lib/feature-flags/lru-cache.ts --project unit` → 133 files / 19.97 s;
`related lib/safety/redaction-allowlist.ts --project unit` → 203 files /
44.47 s; `related components/ui/button.tsx --project component` → 185
files / 44.24 s. The shipped metric: `apps/web-platform [unit]` on a
single-source-file diff completes materially under its full ~82 s with
`outcome=related`, and the AC(a) components-diff case shows `component`
narrowed with `unit` reporting `full-zero` — honest, receipt-verifiable.

## Dependencies & Prerequisites

`apps/web-platform/node_modules` installed locally (the arm's precondition
probe already enforces it). Ordering inside the PR: lib + wrapper + suite
(Phase 1) before runner wiring (Phase 2); registration before the
edge-block's classify walk matters only to enumerate parity, landed in the
same diff. **This diff touches `scripts/test-all.sh`** → local affected
runs degrade to the full battery (`runner-changed`) while the PR is open —
expected; the feature verifies itself on the *next* branch. #9814 is in
the merge queue with no code contact (its arm is above the window, ours is
inside); its landing order only changes which timings the measurement
reads.

## Risk Analysis & Mitigation

| Risk | Likelihood | Mitigation |
|---|---|---|
| Zero-resolution exits 0 and reads as green | Certain without the grep | Marker grep + `full-zero` receipt + Guard-1 M1; the real-binary arm re-verifies the marker text per vitest bump |
| Dynamic `import(var)` coverage invisible to `related` | Bounded — 3 non-literal sites, all in `server/inngest/functions/cron-ux-audit.ts` (fixture-path loaders) | Recorded residual; single-file diffs to such modules resolve zero → full. A follow-up lint on new non-literal dynamic imports in vitest-covered dirs is the cheap ratchet if the class grows |
| Meta set drifts from `vitest.config.ts` (new setup/globalSetup file) | Medium over time | Guard-2 derivation arm re-derives and diffs; also every such file resolves zero → auto-fallback even unstated |
| Broad-graph diffs (shared leaf modules) → related ≈ half the project | Expected — measured 133–203 files on real modules | Correct and still cheaper; the receipt reports `inputs=` so the narrow/full tradeoff is visible per run; no threshold knob (keep it simple) |
| Registration retarget breaks sibling-suite anchors (m2 `,+1d`, A3 awk, extract_block `^fi$`) | Medium — three distinct anchor shapes | Sharp Edges enumerate all three + QG-2/QG-3 run the suites themselves |
| `npm run test:ci` argv substring disappears → `battery-tag-authorship` OUT_OF_CLASS unmatched / `UNCLASSIFIED` | Medium | QG-5 names the check and the remediation (ledger adjust in-diff, re-measure) — the suite's own "re-measure, don't carry forward" rule |
| `WEBPLAT_RELATED` leaks into a nested runner via export | Low | `env` per registration, never exported — the #9814 learning's env-scrub rule, stated at the call site |
| Space/tab-bearing app filename splits wrong | Rare | Same accepted limitation as `_AFFECT_PATTERNS`; the contribution is lost → at worst `full-zero` |
| Marker grep false-positive inside test output | Very low | The phrase is vitest's runner banner text; a false hit degrades to full — the safe direction |
| Two vitest startups in bundle mode when narrowed | Expected | ~1–2 s overhead vs the related saving; recorded, accepted |
| Worktree-vs-index skew under `--affected-scope=staged` | Low | The paths are the selection; `related` resolves the current graph — a superset direction, never narrower than the staged intent |

## Sharp Edges

1. **`vitest run --related` does not exist** — `CACError: Unknown option
   '--related'` at 4.1.8 and 4.1.11. The invocation is
   `node_modules/.bin/vitest related <files> --run --project <p>`.
   `--run` is load-bearing: `related` defaults to *watch* mode (vitest
   docs); without it the suite hangs forever.
2. **Zero-related is a green-shaped non-event**: `No test files found,
   exiting with code 0`, rc 0. rc cannot detect it — only the marker text
   can. Never add `--passWithNoTests`.
3. **`related` reads static imports only.** `import(<var>)` is invisible
   (3 sites: `cron-ux-audit.ts:296/:384/:480`). Literal `import("x")` is
   fine.
4. **Registration anchors (three shapes, all in sibling suites):** the
   `want_webplat` block is extracted by
   `awk '/^if want_webplat; then$/…/^fi$/'` — any *column-0* `fi` inside
   the arm truncates it; A3's UNGATED region is `awk
   '/_diff_touches/{exit}'` — the computation must contain zero
   `_diff_touches` literals (comment or code); and `m2` deletes
   `run_suite … ,+1d` — each registration stays exactly two lines.
5. **`env` not `export`**: `_webplat_related` is per-run state; exporting
   it would let a nested runner inherit a stale list (the learning's
   second half). `${_webplat_related:-}` guards `set -u`.
6. **In-window placement is load-bearing**: anything added *above*
   `tc_acquire "test-all"` (`:4785`) rides into every runner-SUT sandbox —
   the #9814 learning. The computation goes inside `want_webplat`; the
   lib additions are inert symbols (data + function definitions, no
   side-effect).
7. **`repo-wide` is never narrowed** — its subject is the repository, not
   the app graph; a narrowed repo-wide is the vacuity this feature exists
   opposite to. `bundle` mode hard-codes full `repo-wide` first.
8. **Deleted/renamed files are safe**: dead tokens contribute zero;
   renames contribute both sides via the `R100` tab-split tokenization.
9. **The diff blob is multi-source**: branch window, staged index,
   untracked, `--paths` — the tokenizer is source-agnostic; all feed
   `related` correctly because paths are the selection and the graph is
   current.
10. **`vitest related` argv must be root-relative** (docs) — the runner
    strips `apps/web-platform/`; the wrapper `cd`s to the app root before
    invoking.

## Research Insights

**Sequential-fallback disclosure:** no Task/subagent spawn on this
harness; every lane (codebase, learnings, ADR corpus, empirical vitest)
ran sequentially in-process. Nothing here claims independent review.

**Premise Validation.** Issue #9815's claims verified against the tree:
both labels dispatch `npm run test:ci` inside `want_webplat`
(`test-all.sh:6336-6346`); `[unit]` is consumed-edge on
`WEBPLAT_APP_PATHS` (`test-affected-paths.sh:312`); `[repo-wide+component]`
is `_suite_affected`-exempt by design (`:3419`, `:3496`); ~82 s / ~80 s
weights confirmed by `baseline-timing.tsv` (81,554 ms) and
`measurements-continuation-2026-10-09.md` (the #9763 spec, ~80 s + ~82 s).
The `vitest related` refinement is the spec's own recorded follow-up
(`feat-8322-affected-test-gate` spec :39). ADR-242 verified as the owning
decision record; the dated-amendment convention confirmed (`#9813`
2026-10-10 latest).

**Property List.** (1) Local affected runs narrow the webplat vitest
invocations to the changed app files. (2) Meta/config changes pay full.
(3) Zero resolution pays full — never silent narrowing. (4) repo-wide
never narrows. (5) CI unchanged. **Cut list:** declining `[unit]` on
component-covered-only diffs (violates the issue's own doctrine);
narrowing `repo-wide` (vacuity); `--changed` (wrong diff source).

**Reconciliation — Spec vs. Codebase.** Two corrections, both measured:
(a) the issue's flag spelling `vitest run --related` does not exist — the
subcommand `vitest related … --run` is the mechanism; (b) "shared helpers"
are module-graph members that `related` resolves correctly (verified) —
the meta set therefore covers only run-semantics/config/guard files, and
helpers stay narrowable. Everything else verified as stated.

**Learnings applied.**
`2026-10-11-a-runner-arm-above-the-splice-window-fires-inside-every-sibling-sandbox.md`
(from #9814's branch — all new runner-side code inside the window; env
vars via `env`, never exported; inert lib symbols only above the window);
`2026-10-05` fixture-hygiene triple (owning trap, absolute fixture root,
per-arm env scrub); `2026-10-03` SE9 (QG-6 consumer sweep enumerates
readers of the changed surface); the `cq-assert-anchor-not-bare-token` /
`cq-test-fixtures-synthesized-only` rules (synthesized vitest project, no
live fixtures); ADR-242 decision 3 (degraded = full) applied
intra-suite via the `_aff_fallback` conjunct.

**Conventions captured.** `foo.sh`+`foo.test.sh` under
`apps/web-platform/scripts/`; `apps/web-platform/test/*.test.sh` is
explicit-registration territory (the `destroy-ask-mutation` precedent at
`:6374-6378` — needs `node_modules`, so it lives in this arm); receipts
are `UPPER_SNAKE<TAB>key=value` lines; mutation-armed assertions are the
house test shape (`mutate` + drive-red).

**Deepen pass (2026-10-11).** Empirical, not doc-only: `npm ci
--ignore-scripts` in this worktree installed the pinned toolchain
(4.1.11); a synthesized 3-file project in /tmp established the semantics
(transitive resolution, test-file self-resolution, union on multi-file
input, zero→rc0 marker, setup-file invisibility, `--project`
composition); two real-app runs priced the breadth (133–203 files,
20–44 s vs ~82 s full). Docs check (vitest.dev CLI) added two edges the
probes could not: static-import-only resolution and root-relative argv —
both folded in. Remaining unverifiable-here: the AC(a) before/after on a
real gate run — the method is spec'd and the raw numbers are recorded
above.

## Non-Goals

- Narrowing `repo-wide` — impossible by construction and wrong by design.
- Declining `[unit]` when `related` resolves zero — the doctrine reads
  zero as "no coverage", never "green".
- Any change to suite selection (`_suite_affected`, `ALWAYS_ON_SUITES`,
  consumed edges, `WEBPLAT_APP_PATHS`, the relevance gate).
- CI/merge-gate behavior — byte-identical full invocations.
- `vitest --changed`, coverage-provider-based selection, or
  positional-file filtering.
- A lint on dynamic imports (recorded as the residual's cheap follow-up,
  not part of this PR).
- `npm test` / watch-mode ergonomics — the local *gate* is the surface.
