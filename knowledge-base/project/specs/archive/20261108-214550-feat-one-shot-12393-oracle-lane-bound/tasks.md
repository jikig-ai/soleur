# Tasks — feat-one-shot-12393-oracle-lane-bound

Plan: `knowledge-base/project/plans/2026-11-08-fix-oracle-index-check-manifest-bound-plan.md`
Issue: #12393 (closes). Design rulings: `decision-challenges.md` (pending-assumed rows — spawn
`soleur:engineering:cto` at work start to convert if a spawn capability exists).

## Phase 1 — Leg-assignment file and membership wiring

- [x] 1.1 Create `scripts/ci-oracle-lane-legs.tsv` — commented header (grammar `label<TAB>leg`,
  K=5, measured-durations provenance from `scripts/suite-durations.tsv`, rebalance trigger:
  re-pack when any leg's projected total comes within ~5 min of the 30-min bound), then 15 rows
  per the plan's packing table (leg 1: `plugins/soleur/test/ci-pr-affected-replay-a`; leg 2:
  `scripts/test-all-affected-d`, `scripts/test-affected-kb-consumers`,
  `scripts/lint-orphan-test-suites`, `scripts/ci-oracle-review`; leg 3:
  `scripts/test-all-affected-c`, `plugins/soleur/test/ci-pr-affected-replay-c`,
  `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`; leg 4:
  `scripts/test-all-affected-b`, `scripts/test-all-group-affected`,
  `scripts/test-affected-derive-cache`; leg 5: `plugins/soleur/test/ci-pr-affected-replay-b`,
  `scripts/test-all-affected-a`, `scripts/test-affected-derive`, `scripts/ci-pr-selection`).
  Re-run the plan's measurement command first; re-pack if the table drifted (AC8).
- [x] 1.2 `scripts/ci-oracle-lane.sh` — add `scripts/ci-oracle-lane-legs.tsv` to the
  hard-exclusion `case` (the "always pays the battery" list, ~line 180), comment updated.
- [x] 1.3 `scripts/lib/test-affected-paths.sh` — add the legs file to
  `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS`.
- [x] 1.4 `.github/CODEOWNERS` — add `/scripts/ci-oracle-lane-legs.tsv @deruelle` beside the
  manifest row (~line 31).
- [x] 1.5 `scripts/pr-fanout-ledger.txt` — dated note on the ci.yml row: matrix = one declared
  job (count stays 22); the +K−1 no-op leg slots on non-oracle `pull_request`/`merge_group`
  runs is the named consequence.

## Phase 2 — Matrix + leg-filtered run block (ci.yml `oracle-index-check` only)

- [x] 2.1 Add `strategy: { fail-fast: false, matrix: { leg: ["1/5","2/5","3/5","4/5","5/5"] } }`
  to the job (precedent: `test-scripts`).
- [x] 2.2 Pass `ORACLE_LEG: ${{ matrix.leg }}` into the manifest step `env:`.
- [x] 2.3 Extend the manifest `run:` block (keeping `not-oracle-only` early exit FIRST):
  unset/empty/malformed `ORACLE_LEG` → `::error`+exit 1; legs file missing → `::error`+exit 1;
  per member, look up its leg row — unassigned → `::error`+exit 1, wrong leg → `continue`;
  per-leg `ran==0` → `::error`+exit 1. Keep `    timeout-minutes: 30` alone on its line.
- [x] 2.4 Refresh ONLY the comments inside the `oracle-index-check` block (serial→legs; drop
  the stale "~10-20 min" estimate — never re-quote a measured number). Do NOT touch `needs:`,
  `if:`, checkout/fetch gates, the aggregator, `scripts/ci-oracle-lane-suites.txt`,
  `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (AC5/AC7).

## Phase 3 — Sentinel guard extension (`scripts/ci-oracle-lane.test.sh`)

- [x] 3.1 New `check_legs()` beside `check_manifest()`: legs rows ≡ manifest member labels
  (bi-directional), leg values ⊆ the live ci.yml `matrix.leg` set (parse the YAML), every
  matrix leg owns ≥1 member, no duplicate assignment rows.
- [x] 3.2 Mutant rows per the plan's Guard Contract matrix (rows 1-8: unassigned member, stale
  row, out-of-set leg, vacuous leg, missing legs file, duplicate assignment, plus the two
  must-PASS rows — re-packed coverage and row reorder stay clean).
- [x] 3.3 Extend the extracted-body sandbox replay: stub `ci-oracle-lane-legs.tsv` +
  `ORACLE_LEG=k/K` runs only that leg's stub members; arms for unset/malformed `ORACLE_LEG`,
  missing legs file, unassigned member, vacuous leg → exit 1 (AC3/AC4).
- [x] 3.4 Update comments saying "SERIALLY"/"label + argv per line" where legs semantics now
  apply; add the legs file's driver-exclusion fixture case if the enumeration is one-per-path.

## Phase 4 — Recorded artifacts

- [x] 4.1 `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` — leg description
  serial→legs; §Activation status line naming this PR + canary conditions.
- [x] 4.2 ADR-276 `### Stage status` — one dated line: serial→K=5 matrix legs, same job ID;
  measured serial 65.4 min vs bound 30; +K−1 no-op legs cost note (append-only convention).

## Phase 5 — Verification

- [x] 5.1 Run `bash scripts/ci-oracle-lane.test.sh` (AC1-AC4), `actionlint` on ci.yml if
  available, and the plan's measurement command (AC8). The full battery covers this PR (the
  diff is not oracle-only — lane files are hard-excluded).
- [x] 5.2 On the PR's own CI run: all 5 `oracle-index-check (k/5)` legs conclude success with
  `not-oracle-only` — live pre-merge exercise of the matrix wiring.
- [x] 5.3 PR body: note #12274 verified-fixed on `origin/main` and recommend close (AC11);
  `Closes #12393` in body.

## Phase 6 — Post-merge (operator-authorized, runbook §Activation)

- [x] 6.1 `gh variable set CI_ORACLE_LANE --body on --repo jikig-ai/soleur`; verify
  `gh api repos/jikig-ai/soleur/actions/variables/CI_ORACLE_LANE` → `"value": "on"`.
- [x] 6.2 Docs-only canary PR (knowledge-base `*.md` touch): confirm `oracle_only=true`, the
  `ORACLE-ONLY-SKIP` aggregate lines naming the five legs, and every
  `oracle-index-check (k/5)` green inside the bound (AC12). On failure:
  `gh variable delete CI_ORACLE_LANE --repo jikig-ai/soleur` and file follow-up under #11556.
- [x] 6.3 On green: canary run ID into #12393 (closing note) and the ADR-276 status thread.
