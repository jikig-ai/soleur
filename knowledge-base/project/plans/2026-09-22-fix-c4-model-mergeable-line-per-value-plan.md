---
title: "fix(kb): make model.likec4.json mergeable on GitHub (line-per-value, blank view hash)"
date: 2026-09-22
slug: fix-c4-model-mergeable-line-per-value
branch: feat-c4-model-mergeable
issue: 8542
closes: 8542
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(kb): make model.likec4.json mergeable on GitHub

## Overview

`knowledge-base/engineering/architecture/diagrams/model.likec4.json` is a committed product
artifact (ADR-235) written as one 1.1 MB JSON line. Any two PRs that regenerate it conflict, and
GitHub's server-side merge reports DIRTY. The fix is to change its canonical on-disk format so
git can merge two regenerations whenever the underlying edits don't collide:

- Parse likec4's export and set every `views[*].hash` to `""`.
- Serialize with `JSON.stringify(model, null, 1)`, then strip each line's leading spaces and add a
  trailing `\n`.

All **three** writers emit these bytes through one shared module. The residual conflicts are
real layout overlaps, and those keep regenerate-on-conflict.

Brainstorm: `knowledge-base/project/brainstorms/2026-09-22-c4-model-mergeable-brainstorm.md`.
Spec: `knowledge-base/project/specs/feat-c4-model-mergeable/spec.md`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Two writers (repo script, app) | **Three.** `plugins/soleur/scripts/generate-c4-from-components.ts` (run by `soleur:sync` via `bun`, from the installed plugin, inside CUSTOMER repos) also runs `likec4 export json` and publishes `model.likec4.json` (`generate-c4-from-components.ts` "RENDER OFF-TREE, PUBLISH ONLY AFTER THE GATE PASSES" block) | The third writer canonicalizes too, otherwise it would reformat the app's file on every sync |
| One module under `apps/web-platform/lib/` (TR1) | The app's Docker build context is `apps/web-platform` only (`Dockerfile` `COPY . .`), and the plugin runs from `${CLAUDE_PLUGIN_ROOT}` in customer repos, where `apps/` does not exist. No single path is reachable by all three writers | Source of truth `plugins/soleur/lib/c4-canonical.mjs`. Byte-identical copy at `apps/web-platform/lib/c4-canonical.mjs`. A parity test fails on any drift (Guard 1) |
| Freshness test covers the new format via `--out` (TR7) | True, but a byte cmp alone passes if a PR drops canonicalize and regenerates raw in the same diff. It runs in CI's test-scripts job (`ci.yml`, likec4 installed) and in main-health-monitor | Add a `--check` row to it |

## Research Insights

**Premise Validation.** #8542 is open. Every cited path exists on `origin/main` 69b08a4ee.
ADR-235 re-checked, and the classification holds: the viewer lists and fetches the committed blob
(`app/api/kb/c4/project/route.ts`, `e.name === C4_MODEL_JSON`). ADR-235's "conflicts are rare
(concurrent `.c4` edits only)" rationale is falsified by measurement: 27 of 121 commits in 7 days.
`rule-metrics.json` needs nothing. It is untracked and gitignored with no force-add writer, and of
37 open PRs carrying it only #8329 modifies it.

**Property List.**

- P1: Two PRs whose regenerated artifacts set no JSON leaf to different values merge clean on
  GitHub, and the merged bytes equal a fresh render of the merged sources.
- P2: Two PRs that set the same leaf differently still conflict. No silent false-clean.
- P3: Every writer emits the same bytes for the same sources, so none rewrites another's output.
- P4: Every reader still renders, and the served size stays under `MAX_C4_BYTES`.

**Cut List.**

- Option B (untrack) → P1: a runtime reader needs the committed blob. Out of scope.
- Option C (per-view files) → P1: measured no gain over A with the hash blanked.
- Option D (auto-resync bot) → P1: symptom-only. The existing resolver already covers residuals.
- Key sorting → P1: measured zero extra merges (indent 2 sorted vs unsorted are identical on all
  51 gap 1-2 pairs).
- (Kept, not cut) A `--check` CLI mode on the module → the discoverability probe needs a command
  free of shell metacharacters (preflight Check 10 rejects `|;&<>$`), and `--check` is that
  probe.

**Measurements.** Replay harness at `knowledge-base/project/specs/feat-c4-model-mergeable/replay/`,
run against real pairs of main commits touching `.c4` at gaps 1-10 (152 pairs):

- raw (today): 0/152 clean.
- Line-oriented with hash blanked: 107/152 clean-and-correct, 45 conflicts, **0 false-clean**.
- Indent 0 and indent 2 give identical outcomes on the 51 pairs where both were measured.
- Every residual conflict has a leaf both sides set differently: Graphviz coordinates in a shared
  view, or one relation's title.
- No real pair conflicted at the source level.

**Hash.** `views[*].hash` = `objectHash` (ohash, SHA-256/base64) of the pre-layout computed view
(`@likec4/core` `Builder.view-element.mjs`). There is no reader in `@likec4/diagram`, in
`LikeC4Model.create`, or in app code. The likec4 CLI never reads the exported artifact back:
measured, export output is byte-identical with a blank-hash artifact in its workspace.

**Size.** Indent 0 with blank hashes = 1,210,507 B (28.9% of 4 MiB). Indent 2 = 1,796,697 B.

**Shared-module precedent.** `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`:

- imported by TS (`server/cron-filing-deny-marker.ts`);
- run directly by `node` (guarded `main()` via `invokedPath.endsWith(...)`);
- bundled by esbuild into `dist/server`.

`tsconfig.json` has `allowJs: true`.

**Tests affected** (repo-research):

- `apps/web-platform/test/c4-render.test.ts`: asserts `res.json` is verbatim, byte-identical to
  the read.
- `apps/web-platform/test/c4-writer-rerender.test.ts`: the committed base64 must equal
  `RENDERED_JSON`. `c4-writer` passes `render.json` through, so this test is unaffected as long
  as it stubs `renderC4Model`. Verify.
- `plugins/soleur/test/c4-model-freshness.test.sh`: `cmp` byte-compare.
- The `sync-pr-behind.test.sh` and `resolve-regenerable-conflicts.test.sh` stubs replace
  `regenerate-c4-model.sh` and are unaffected.
- `plugins/soleur/test/c4-from-components.test.{sh,ts}`: check whether they assert published
  bytes.

**Learnings applied.**

- `2026-06-18-likec4-exits-0-on-syntax-error-…`: canonicalize only AFTER both validation gates.
  It never replaces them.
- `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite`: regenerate the
  artifact whenever a `.c4` source changes.
- `2026-09-21-a-conflict-starved-merge-ref-reads-as-ci-never-ran`: when checking this PR's CI,
  read `mergeStateStatus` plus the required-context intersection, not the visible check count.
- `2026-09-19-enumerate-the-readers-…`: readers enumerated, all use `JSON.parse`.

**#8384 lessons** (from the brief; none captured as learnings yet, so compound owns them):

- Run shell suites CI-style: `HOME=$(mktemp -d) GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`,
  with identity set in each fixture repo's local config.
- Re-run a file's suites after any merge from main that auto-merges it.
- Draft PRs get no `pull_request` CI.
- The admin merge is reserved to the operator by the permission layer.

## Implementation Phases

Everything lands in this one PR. It merges atomically, so the app deploy, the plugin release and
the regenerated artifact all ship from the same commit.

### Phase 1 — Canonical module (TDD)

1. RED: `plugins/soleur/test/c4-canonical.test.ts` (bun). Every `git` spawn passes
   `gitCleanEnv()` from `plugins/soleur/test/lib/git-clean-env.ts`. Rows:
   - A view that has a `hash` key gets `""`. A view without one gets NO key added (the
     `c4-render.test.ts` fixture has `views: { index: {} }`). The fixture has ≥ 2 views, so a
     "first view only" bug reds.
   - Round trip: `JSON.parse(canonical)` deep-equals `JSON.parse(input)` with the view hashes
     blanked. Key order equals `JSON.stringify(JSON.parse(input))` key order, NOT the input
     text; JS hoists integer-like keys.
   - No line starts with whitespace, and the output ends with exactly one `\n`.
   - Idempotence: `canonical(canonical(x)) === canonical(x)`.
   - Non-view `hash` keys are untouched (a `manualLayouts[*].hash` fixture).
   - Non-JSON or non-object input throws.
   - The CLI runs under **`node`** (not bun's `process.execPath`):
     - `node c4-canonical-cli.mjs IN` writes to stdout bytes identical to the import;
     - `--check` prints `canonical` (exit 0) on canonical input;
     - `--check` prints `not-canonical` (exit 1) on raw input.
   - Mergeability, on synthetic base/A/B files through `git merge-file`:
     - (a) disjoint leaf edits plus both sides changing view hashes: raw conflicts, canonical
       merges, and the result parses to the expected object;
     - (b) a same-leaf edit: canonical still conflicts.
   - `git check-attr -a` on the artifact path reports `linguist-generated` and nothing else. No
     `binary`, `-diff`, `-merge` or `merge=`: the resolver's comment documents that `binary`
     silently side-picks.
2. GREEN, as two files. The split keeps `import.meta`, `process.argv` and `fs` out of any module
   that esbuild bundles to CJS (`dist/server/index.cjs`) or that the vitest `node:fs/promises`
   mock replaces:
   - `plugins/soleur/lib/c4-canonical.mjs`: PURE. It only exports
     `canonicalizeC4Model(json: string): string`, with no imports and no I/O. Its first line is a
     `GENERATED MIRROR: edit plugins/soleur/lib/c4-canonical.mjs, then cp to apps/web-platform/lib/`
     header, which is identical in both copies.
   - `plugins/soleur/lib/c4-canonical-cli.mjs`: a plugin-only CLI that imports the pure module and
     uses sync `node:fs`. `<in>` writes canonical bytes to stdout. `--check <file>` prints
     `canonical`/`not-canonical` and exits 0/1. Any error exits 2 with nothing on stdout.
3. `cp` the pure module to `apps/web-platform/lib/c4-canonical.mjs`. Add
   `apps/web-platform/test/c4-canonical-mirror.test.ts` (vitest). It asserts the two files are
   byte-identical AND that the two resolved paths differ. A PR touching only the apps copy then
   still runs a parity check, and so does a PR touching only the plugin copy, because the bun
   suite repeats the same row.

### Phase 2 — Wire the three writers (each canonicalizes only AFTER its existing validation gates)

1. `scripts/regenerate-c4-model.sh`: after both gates, run
   `node "$REPO_ROOT/plugins/soleur/lib/c4-canonical-cli.mjs" "$TMP/model.likec4.json" > "$TMP/canonical.json"`.
   A non-zero exit refuses to publish. The existing atomic publish then copies `canonical.json`.
   jq stays a validator only.
2. `apps/web-platform/server/c4-render.ts`: after the elements gate, return
   `canonicalizeC4Model(raw)`, imported from `@/lib/c4-canonical.mjs`. A throw maps to the
   existing `io_error` with `detail: "canonicalize failed: …"`. The `RenderReason` union is not
   widened; `detail` separates it in Sentry. Rewrite the "never re-`JSON.stringify`d / raw bytes"
   comments.
3. `plugins/soleur/scripts/generate-c4-from-components.ts`: after the verdict and before publish,
   write `canonicalizeC4Model(readFileSync(stagedJson, "utf8"))` to the staged path. A throw makes
   the run `failed` with no publish, so the committed artifact is never replaced.
4. Tests:
   - `c4-render.test.ts`: expects canonical bytes, and adds a `LikeC4Model.create` row on a
     blank-hash model.
   - `c4-from-components.test.sh`: its end-to-end arm asserts
     `node plugins/soleur/lib/c4-canonical-cli.mjs --check <published model>` prints `canonical`.
   - `c4-model-freshness.test.sh`: also runs `--check` on the committed artifact, so a PR that
     drops canonicalize AND regenerates in the same diff still reds.
   - `apps/web-platform/test/c4-likec4-version-pin.test.ts`: add the plugin's
     `LIKEC4_VERSION` (`plugins/soleur/lib/c4-from-components.ts`) to the pinned set. A pin skew
     would make writers disagree on layout even with identical canonicalizers.
5. Verify, and fix if needed, that `app/api/kb/c4/project/route.ts` and
   `app/api/shared/[token]/c4/route.ts` degrade to a handled error when `JSON.parse` of the
   committed blob fails. A bad clean merge in a customer repo must not white-screen the viewer.

### Phase 3 — Regenerate the artifact and repo plumbing

1. Run `bash scripts/regenerate-c4-model.sh`, then run the freshness suite.
2. Create `.gitattributes` containing only
   `knowledge-base/engineering/architecture/diagrams/model.likec4.json linguist-generated=true`.
3. `resolve-regenerable-conflicts.sh`: update the comment that says the repo has no
   `.gitattributes`. No code change. `RESOLVABLE_PATHS` stays 1 member, and
   `kb-caches-untracked.test.sh` `EXPECTED_N=5` is unchanged.

### Phase 4 — ADR + docs

1. Amend ADR-235 (product section):
   - the canonical format, the blank hash (with the no-reader evidence), the three writers, and
     the pure module plus its mirror;
   - correct the "conflicts are rare" alternatives row: measured 27/121;
   - the replay numbers;
   - regenerate-on-conflict exists **only in this repo**. Customer repos have no resolver; their
     residual true overlaps stay DIRTY until a writer re-renders;
   - rollout: app and plugin ship from one merge. Older self-hosted CLI plugins keep writing the
     raw format, and each alternation rewrites the whole file. This is accepted, and upgrading is
     the remedy;
   - size headroom drops from 3.70x to 3.46x of `MAX_C4_BYTES`.
2. ADR-050: a one-line amendment saying the render returns canonical bytes.
3. Prose sweep. Run `git grep -n 'model.likec4.json' -- plugins/soleur/skills` and fix only lines
   that claim one-line, verbatim or raw bytes, or that show writing raw `likec4 export json`
   output onto `model.likec4.json`. Point those at the plugin CLI instead. Candidates: `merge-pr`,
   `architecture` (+ `references/likec4-reference.md`), `drain-prs`, `ship`, `work`,
   `settle-then-admin-merge.md`.

### Phase 5 — Acceptance replay with the real module (the user's measured acceptance)

1. Add a `canonical` format to `replay.py` that shells out to `node c4-canonical-cli.mjs`.
2. Re-run it over main's real `.c4` pairs at gaps 1-10.
3. The positive control is the real true-overlap pairs: sources merge clean, but the artifact must
   conflict. Record which leaves overlap for 3 of them.
4. Commit the results JSONL and a summary table in the spec dir. The PR body quotes the table.

## Files to Create

- `plugins/soleur/lib/c4-canonical.mjs` (pure)
- `plugins/soleur/lib/c4-canonical-cli.mjs` (CLI, plugin only)
- `apps/web-platform/lib/c4-canonical.mjs` (byte-identical mirror of the pure module)
- `plugins/soleur/test/c4-canonical.test.ts`
- `apps/web-platform/test/c4-canonical-mirror.test.ts`
- `.gitattributes`

## Files to Edit

- `scripts/regenerate-c4-model.sh`
- `apps/web-platform/server/c4-render.ts`
- `plugins/soleur/scripts/generate-c4-from-components.ts`
- `apps/web-platform/test/c4-render.test.ts`
- `apps/web-platform/test/c4-likec4-version-pin.test.ts`
- `plugins/soleur/test/c4-from-components.test.sh`
- `plugins/soleur/test/c4-model-freshness.test.sh`
- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh` (comment only)
- `apps/web-platform/app/api/kb/c4/project/route.ts`, `apps/web-platform/app/api/shared/[token]/c4/route.ts` (only if the Phase 2.5 check finds an unhandled parse failure)
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/engineering/architecture/decisions/ADR-235-generated-artifacts-caches-untracked-products-regenerated-on-conflict.md`
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`
- skill prose from the Phase 4.3 sweep (grep-selected)
- `knowledge-base/project/specs/feat-c4-model-mergeable/replay/replay.py` and results

## Open Code-Review Overlap

- #8540 (review: PR #8504 grok /go command shims) matched on the string `ADR-235`. It concerns
  `INDEX.md` staying out of that PR's diff, not the product artifact. **Acknowledge**: it is a
  different concern, and this plan's ADR-235 amendment does not touch it.

No other open code-review issue names a file in this plan.

## User-Brand Impact

**If this lands broken, the user experiences:** a stale or blank C4 diagram in the KB viewer
(`/dashboard/kb`), or a diagram edit that silently fails to re-render. That happens if the app's
canonicalizer throws, or if a reader rejects the new layout.

**If this leaks, the user's workflow is exposed via:** no data exposure. The file holds only data
derived from the customer's own `.c4` sources (CLO: no legal surface). The risk is integrity:
writer divergence would churn full-file rewrites in the customer's git history.

**Brand-survival threshold:** single-user incident. CPO reviewed at brainstorm and accepts the
one-time reformat with a changelog line.

## Observability

```yaml
liveness_signal:
  what: canonical format of the committed artifact (every views[*].hash == "", no leading whitespace, trailing newline)
  cadence: every PR and main push (CI test-scripts shard runs c4-model-freshness.test.sh; main-health-monitor re-renders)
  alert_target: CI required check failure on the PR; main-health-monitor issue on main
  configured_in: .github/workflows/ci.yml (test-scripts shard), .github/workflows/main-health-monitor.yml
error_reporting:
  destination: Sentry via reportSilentFallback (feature c4-rerender, op render) for the app writer; CI log for repo/plugin writers
  fail_loud: yes. A canonicalize throw in c4-render returns reason io_error, which is already mirrored to Sentry, and the diagram stays on the last good commit
failure_modes:
  - mode: canonicalizer throws on a malformed export (app path)
    detection: renderC4Model returns io_error; reportSilentFallback "c4 re-render failed" (feature c4-rerender)
    alert_route: Sentry issue alert for feature c4-rerender
  - mode: writer divergence (a writer publishes raw or differently-canonical bytes)
    detection: c4-canonical.test.ts parity + CLI-vs-import rows; c4-model-freshness.test.sh byte cmp
    alert_route: CI required check
  - mode: canonical mirror drift between plugins/ and apps/ copies
    detection: c4-canonical.test.ts byte-identity row
    alert_route: CI required check
logs:
  where: Sentry (app); GitHub Actions logs (CI)
  retention: Sentry plan default; Actions 90 days
discoverability_test:
  command: node plugins/soleur/lib/c4-canonical-cli.mjs --check knowledge-base/engineering/architecture/diagrams/model.likec4.json
  expected_output: "canonical"
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-235** so that the product artifact's committed format is canonical line-per-value
with a blank view hash. Record:

- three writers share `plugins/soleur/lib/c4-canonical.mjs`, with a parity-tested mirror under
  `apps/web-platform/lib/`;
- the corrected conflict-frequency measurement;
- rejected options B, C and D, with the replay numbers.

Also add a one-line amendment to **ADR-050**: the render path returns canonical bytes.

### C4 views

No C4 impact. I read `model.c4`, `views.c4` and `spec.c4` and checked for anything this change
adds:

- **External human actor:** none new. The diagram-editor user is already modeled as the founder
  actor.
- **External system:** none new. GitHub as the customer-repo host is already modeled.
- **Container/data store:** none new. The web platform server and the connected repo are
  unchanged.
- **Access relationship:** none changed. The change is a byte format of an existing file.

`plugins/soleur/test/c4-count-parity.test.sh` must stay green.

## Guard Contract

### Guard 1 — writer byte-parity and format

**Property.** For any likec4 export, every writer publishes exactly `canonicalizeC4Model(export)`.
The two copies of the pure module are byte-identical, and the committed artifact is canonical.

**Assembly.** The chokepoint is `canonicalizeC4Model`. Every writer must pass through it:

- `scripts/regenerate-c4-model.sh` publish (via the node CLI);
- the `apps/web-platform/server/c4-render.ts` return;
- the `plugins/soleur/scripts/generate-c4-from-components.ts` staged publish.

Each writer has a dedicated check:

| Writer | Check |
|---|---|
| Repo | `c4-model-freshness.test.sh`: byte cmp + `--check` |
| App | `c4-render.test.ts` canonical-bytes row |
| Plugin | `c4-from-components.test.sh` end-to-end `--check` |

The copies are covered by the bun and vitest mirror rows. The likec4 version across writers is
covered by `c4-likec4-version-pin.test.ts`, which now includes the plugin constant.

**Mutation matrix** (each must go RED):

| # | Mutation | Row that must go RED |
|---|---|---|
| 1 | Edit one byte in `apps/web-platform/lib/c4-canonical.mjs` only | The vitest mirror row |
| 2 | `c4-render.ts` returns `raw` instead of the canonical string | The `c4-render.test.ts` canonical-bytes row |
| 3 | `regenerate-c4-model.sh` publishes `$TMP/model.likec4.json` AND the committed artifact is regenerated raw in the same diff | The freshness `--check` row (the byte cmp alone stays green) |
| 4 | `generate-c4-from-components.ts` skips canonicalize | The `c4-from-components.test.sh` end-to-end `--check` row |
| 5 | `canonicalizeC4Model` blanks only the FIRST view's hash | The bun "every view blank" row (≥ 2 views) |
| 6 | The plugin `LIKEC4_VERSION` bumped to 1.50.1 alone | The `c4-from-components.test.ts` drift guard (at work time, the plugin constant turned out to be pinned there already, against `regenerate-c4-model.sh`, so the version-pin test needed no edit) |

**Harness rows.**

- Must-PASS non-canonical input: a raw export with non-empty hashes, a hash-less view and a
  non-alphabetical key order. It canonicalizes and passes every row.
- Suite edit: point the vitest mirror row's second path at the first file. The "paths differ"
  assertion must red.

**Anchor.** One diff can change the module and the artifact together. Integrity therefore comes
from the freshness suite re-rendering from `.c4` sources with pinned likec4 in CI, plus the
`--check` row, not from any stored value.

## Acceptance Criteria

- [ ] AC1: `bun test plugins/soleur/test/c4-canonical.test.ts` passes, including the synthetic
  merge rows (a) and (b) and the `check-attr` row.
- [ ] AC2: Mutation rows 1-6 and both harness rows were each applied once and observed RED, and
  the tree was restored. The PR body lists them.
- [ ] AC3: `bash plugins/soleur/test/c4-model-freshness.test.sh` passes on the regenerated
  artifact.
- [ ] AC4: `node plugins/soleur/lib/c4-canonical-cli.mjs --check knowledge-base/engineering/architecture/diagrams/model.likec4.json`
  prints `canonical`.
- [ ] AC5: The replay with the real module over main's `.c4` pairs at gaps 1-10 shows:
  - raw is clean on 0 pairs;
  - canonical is clean-and-correct on ≥ 100 pairs with 0 false-clean;
  - every true-overlap pair conflicts (positive control).

  The table is committed and quoted in the PR body.
- [ ] AC6: These suites pass:
  - `cd apps/web-platform && ./node_modules/.bin/vitest run` over `test/c4-render.test.ts`,
    `test/c4-writer-rerender.test.ts`, `test/c4-project-route.test.ts`,
    `test/shared-token-c4.test.ts`, `test/kb-share-preview.test.ts`,
    `test/c4-likec4-version-pin.test.ts`, `test/c4-code-syntax.test.ts` and
    `test/c4-canonical-mirror.test.ts`;
  - the plugin suites `c4-from-components.*`, `c4-count-parity`, `kb-caches-untracked`,
    `resolve-regenerable-conflicts` and `sync-pr-behind`. The shell suites run under
    `HOME=$(mktemp -d) GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`.
- [ ] AC7: A committed blob that fails `JSON.parse` returns a handled error from both C4 routes,
  not a 500 crash (a test row exists or is added).
- [ ] AC8: ADR-235 is amended, including the customer-repo resolver scope and the rollout
  paragraph, and ADR-050 has its note. `RESOLVABLE_PATHS` has 1 member and `EXPECTED_N=5`.

## Test Scenarios

These are the rows in AC1, the Guard Contract matrix, and AC5-AC7.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** CTO chose A. Constraints are folded in above: Node-only serialization;
canonicalize after validation; a parity test; a blank-hash `LikeC4Model.create` test;
`linguist-generated`. This plan corrects the module location: the plugin is the source of truth
with an app mirror, because there are three writers.

### Legal

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No legal surface.

### Product/UX Gate

**Tier:** none (no UI surface; no files under components/ or app/**/page.tsx)
**Decision:** reviewed (CPO at brainstorm: accept, changelog line only)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text,
  or omits the threshold fails `deepen-plan` Phase 4.6.
- Only Node serializes. jq reformats numbers, so jq must never write the artifact.
- The replay compares against a render of the MERGED sources. A textually clean merge that
  differs from that render is a false-clean, and there must be none.
- The mirror is byte-identical by construction. Edit the plugin copy, then `cp` it. Never edit
  the mirror alone.
- After any merge from main that auto-merges a file this PR changes, re-run that file's suites
  (#8384 lesson).
- Mark the PR ready to get `pull_request` CI; drafts get none. When CI looks absent, read
  `mergeStateStatus` first.
- Every open PR that touches `.c4` and was branched before this merge conflicts once on the whole
  file. The resolver handles it locally. Say so in the PR body.
- Non-goal: excluding the artifact from agent `git diff` reads in review/ship. `linguist-generated`
  covers GitHub's view, and agents already work from `--stat` for generated files. It can be
  revisited if review cost shows up.

## Plan Review (2026-09-22)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO (devex), plus the
Step 4.5 advisor consult. There were no P0s.

**Applied:**

- the pure/CLI split (advisor, Kieran);
- blank the hash only if present, and a key-order oracle of `JSON.stringify(JSON.parse(x))`
  (Kieran);
- make mutation 4 able to fail, with a `--check` row in c4-from-components (Kieran);
- a freshness `--check` row (spec-flow);
- the plugin likec4 pin added to the pin test (spec-flow);
- the plugin writer fails closed (architecture);
- a vitest mirror row and the mirror header (architecture, CTO);
- `.gitattributes` pinned by a `check-attr` row, and the resolver comment updated
  (architecture, CTO, spec-flow);
- the ADR scopes the resolver to this repo, with rollout and old-CLI churn (architecture,
  spec-flow);
- a viewer parse-failure check (spec-flow, architecture);
- a wider prose sweep (CTO, spec-flow);
- CLI output to stdout with no second atomic-write path (simplicity, DHH);
- cuts: the `main()` no-op mutation, the self-comparison harness row (reworked as a "paths differ"
  assertion), the crafted source-conflict control (the real true-overlap pairs are the positive
  control), the size AC and the process AC.

**Not applied:**

- DHH's cut of the replay re-run and of the mutation matrix. The replay IS the user's stated
  acceptance ("measured, not asserted"), and the Guard Contract gate requires the matrix.
- DHH's cut of `--check`. The freshness byte cmp cannot see a same-diff raw regeneration.
- A distinct `RenderReason` for canonicalize failures. `detail` suffices, and widening the union
  touches consumers.
