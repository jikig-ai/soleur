# Interface Contract — feat-one-shot-12156-oracle-fast-lane (#12156)

Tier 0 lifecycle parallel. Plan: `knowledge-base/project/plans/2026-11-05-ci-oracle-only-fast-lane-plan.md` (authoritative for rationale, guard matrices, observability, ADR amendment spec). Tasks: `tasks.md` in this directory.

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `scripts/ci-oracle-lane.sh` (new), `scripts/ci-oracle-lane-suites.txt` (new), `.github/workflows/ci.yml` (oracle-selection job, oracle-index-check job, `if:` conjuncts on the five heavy legs + `shard-totality-mutations`, `test` aggregator `needs:`/`entries[]`/env + ORACLE-ONLY-SKIP tolerance arm, push-dedupe jobs-API elide proof tightening), `scripts/test-all.sh` (one `run_suite` line), `scripts/lib/test-affected-paths.sh` (one new `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` array) |
| Agent 2 (Tests) | `scripts/ci-oracle-lane.test.sh` (new sentinel — RED first), `scripts/ci-push-dedupe.test.sh` (extend), `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` (extend) |

Neither agent touches: ADR-276 amendment, runbook `ci-oracle-lane.md`, KB artifacts, `tasks.md`/plan checkboxes, `plugin.json`/`CHANGELOG.md`/`README.md` (ship's), or ANY file outside its own row.

## Public Interfaces

### 1. Driver `scripts/ci-oracle-lane.sh` (bash, env-only inputs)

Inputs (env): `EVENT_NAME` (`pull_request`|`merge_group`|`push`), `SWITCH` (expected exact `on`), `PR_HEAD_SHA`, `HEAD_REPO`, `MERGE_GROUP_HEAD_SHA`, `MERGE_GROUP_BASE_SHA`, `RUN_ATTEMPT`.

Outputs — one `GITHUB_OUTPUT`-style block AND stdout, grammar-revalidated before emit: `oracle_only` (`true`|`false`), `active` (`true`|`false`), `skip_legs` (comma-separated ⊆ `test-webplat,test-bun,test-scripts,test-scripts-heavy,web-platform-build`), `head_sha`, `base_sha`. While `readonly ORACLE_LANE_LOCKED=1` stands, `active` is NEVER `true` — the job annotates `would_skip` telemetry instead (dark launch). Defaults-first block emits `oracle_only=false` etc. BEFORE any classification, so a dead script still emits a parseable safe block; script always exits 0 (EXIT trap); `SOLEUR_ORACLE_LANE` notice line carries the verdict.

Classification — `oracle_only=true` iff EVERY changed path is in surface:
1. `scripts/ci-pr-affected-audit.accept.tsv`
2. ~~`scripts/ci-pr-affected-audit.baseline.tsv`~~ — REMOVED at design review: PR5z strict zero deleted the file, so the only possible diff is a `baseline-reintroduced` alarm shape that must pay the full battery (classifies `outside_surface`)
3. `scripts/lib/test-affected-paths.sh` AND every changed hunk line lies inside an `^AFFECTED_[A-Z0-9_]+_PATHS=(` … `^)` array extent computed in BOTH base and head images (a new/deleted whole array still classifies; any hunk line outside extents — `ALWAYS_ON_SUITES`, `_CLOSURE_LEAF_*`, `AFFECTED_CONSUMED_EDGES`, comments, functions — disqualifies the whole diff)
4. `knowledge-base/**/*.md` or root-level `*.md` — identical grammar to `ci-pr-selection.sh` `is_doc_path`

Hard exclusions (any hit → `oracle_only=false`): `scripts/ci-pr-affected-replay.py`, `scripts/test-all.sh`, `plugins/soleur/scripts/lint-ratchet.py`, `.github/workflows/ci.yml`, any other `scripts/lib/**` path, plus every guard: pull_request merge-ref two-parent shape, same-repo head, `RUN_ATTEMPT == 1`, ≤500 files, M/A/D only, modes {000000,100644,100755}, printable-ASCII paths, no `::`/`,` in paths. merge_group diffs `MERGE_GROUP_BASE_SHA..MERGE_GROUP_HEAD_SHA` (whole batch — a code PR in the batch fails closed). `SWITCH` must be exactly `on` (bash compare) else `oracle_only=false`.

### 2. `oracle-selection` job (ci.yml)

`if: ${{ (github.event_name == 'pull_request' || github.event_name == 'merge_group') && vars.CI_ORACLE_LANE != '' }}`, `continue-on-error: true`, `contents: read`, checkout `fetch-depth: 0`, NO `needs:` (parallel root), `timeout-minutes` alone on its line. Outputs the five driver outputs. merge_group env comes from `github.event.merge_group.{head_sha,base_sha}`.

### 3. Leg `if:` conjuncts

Five heavy legs (`test-webplat`, `test-bun`, `test-scripts`, `test-scripts-heavy`, `web-platform-build`) each gain `needs: oracle-selection` + the same `!(… && needs.oracle-selection.outputs.active == 'true' && head-bound && contains(format(',{0},', needs.oracle-selection.outputs.skip_legs), ',<leg>,'))` shape the S4 legs carry, head bound event-agnostically via `github.event.pull_request.head.sha || github.event.merge_group.head_sha`. `shard-totality-mutations` gains `needs: oracle-selection` + `!((event∈{pull_request,merge_group}) && needs.oracle-selection.outputs.active == 'true' && head_sha bound)` — the legs' four-term conjunct minus `skip_legs` membership (it skips on `active`, not `oracle_only`, so the locked dark phase never skips it). `e2e`, `encryption-posture`, `affected-index-ratchet`, `pr-selection`, `draft-light`, `push-dedupe`, all guard/lint jobs: NEVER skipped.

### 4. `oracle-index-check` job (ci.yml)

`if: ${{ always() && !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}`, `needs: [oracle-selection]`, joins `test`'s `needs:` and `entries[]`. When `needs.oracle-selection.outputs.oracle_only == 'true'`: run every manifest line serially, propagate exit codes; else print `not-oracle-only` and exit 0 (<1min). A skipped/empty `oracle_only` reads as not-oracle-only.

### 5. `test` aggregator — ORACLE-ONLY-SKIP tolerance

Second named tolerance alongside PR-AFFECTED-SKIP: tolerated iff `EVENT_NAME ∈ {pull_request, merge_group}` AND `ORACLE_ACTIVE == 'true'` AND `ORACLE_HEAD_OK == 'true'` (head bound to the event's own head SHA) AND `ATTEMPT == '1'` AND the skipped leg matches the five-name regex allowlist via delimited match. `oracle-index-check` is NEVER tolerable. Legs print `ORACLE-ONLY-SKIP` verdict lines.

### 6. push-dedupe elide proof

Elide requires `success` on ALL SIX lane-skippable legs: the five heavy legs + `shard-totality-mutations`. `skipped`/absent/malformed entry → `elide=false`. Sentinel pins the leg-name set bi-directionally (new skippable leg ⇒ driver allowlist + aggregator regex + this proof in the same diff).

### 7. Manifest `scripts/ci-oracle-lane-suites.txt`

`label + argv` per line, plus a committed commented exclusion list. Members (enumerate-exact labels per `test-all.sh --enumerate`): `scripts/lint-orphan-test-suites`, `scripts/test-all-affected-a`, `-b`, `-c`, `-d`, `scripts/test-all-group-affected`, `scripts/test-affected-derive`, `scripts/test-affected-derive-cache`, `scripts/test-affected-kb-consumers`, `plugins/soleur/test/ci-pr-affected-replay-a`, `-b`, `-c`, `scripts/ci-pr-selection`, `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`. Exclusions (commented, with reason): `lint-orphan-test-suites-mutations-{a,b}`, `test-all-orphan-log-retention`, `affected-tests.test.sh`, `affected-tests-pool-default.test.sh`, `audit-suite-reads`, `tests/scripts/lint-ratchet`, `pre-push-ratchet-lane`, `ci-path-gating.test.sh`.

### 8. Edge + registration

`run_suite "scripts/ci-oracle-lane" bash scripts/ci-oracle-lane.test.sh` in `scripts/test-all.sh`. New `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` array in `scripts/lib/test-affected-paths.sh` = {`scripts/ci-oracle-lane.sh`, `scripts/ci-oracle-lane.test.sh`, `scripts/ci-oracle-lane-suites.txt`, `.github/workflows/ci.yml`, `scripts/lib/test-affected-paths.sh`}.

### 9. Sentinel `scripts/ci-oracle-lane.test.sh`

Mirrors `scripts/ci-pr-selection.test.sh` harness shape: fixture-diff battery driving the REAL driver (temp git repos under `mktemp -d` with `assert_fixture_dir` guards), the plan's Guard Contract mutation matrices (Guards 1–4) as RED rows, output-grammar checks, lock check (`ORACLE_LANE_LOCKED=1` ⇒ `active=false` + `would_skip` annotate), fail-closed defaults, manifest parity (non-empty + live-registration + exclusion-list bijection), and the property sweep (any fixture: `oracle_only=true` ⇒ all paths in-surface, all test-affected-paths hunks in-extent).
