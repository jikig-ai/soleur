# Tasks — ci: test-shard speedup phase 2 (mutations split + K=6 + parallel enumerate + heavy manifest)

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-09-23-feat-ci-test-shard-speedup-phase-2-plan.md`
Refs #8006 (phase-2 arm; issue stays open — the leg-duration soak probe closes it).

Locate all constructs by content anchor, not line number — line numbers were verified against this branch on 2026-09-23 and will drift. No `.ts` files in this diff → the bun-test hook will not fire; verification = targeted suites + authoritative CI. Suggested commit grouping: Phase 1 (guard+battery+ci matrix), Phase 2 (K=6 + manifest regen + probe + runbook), Phase 3 (heavy manifest arm + ADR amendment), Phase 4 (verify + ship).

## Phase 1 — Parallel guard + battery row-range split (A + C)

- [ ] 1.1 `plugins/soleur/test/scripts-shard-totality.test.sh`: parallelize every independent child `bash test-all.sh --enumerate` invocation — light leg-union loop, altK inner loops (light + heavy), malformed-spec loops (light + heavy), over/long/unset probes, `TEST_GROUP=all` enumerate. Mechanics: `child & pids[i]=$!` → per-pid `wait "${pids[i]}"` + rc capture (never bare `wait`); distinct `$WORK` file per child; verdicts emitted serially in declared order; index loops only (bash 3.2); bounded fan-out ≤ ~10 with a comment noting the bound.
- [ ] 1.2 Anchor sweep on that edit: `totality_holds` `diff -q "$1" "$2" >/dev/null 2>&1` body, the `cat "$WORK/ref_static" "$WORK/ref_glob" | sort -u > "$WORK/reference"` derivation line, and `enumerate_leg`'s argv shape stay byte-exact (HARNESS + ROW6 anchors in the battery).
- [ ] 1.3 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: `--rows A-B` flag — validate `^[0-9]+-[0-9]+$`, `1<=A<=B<=DECLARED_TOTAL`, else exit 2; parse before WORK setup; unset = all rows. `next_row` helper increments `DECLARED` at every row call site (`row`/`frow`/bespoke: ROW6 tautology, M4) and gates execution by range. CONTROL + instrument self-test run unconditionally on every leg.
- [ ] 1.4 Replace `MIN_ROWS=21` floor with: `DECLARED == DECLARED_TOTAL` (21 → 24 once 3.2's M7–M9 land — keep the constant in sync in the same edit that adds a row), `EXECUTED == IN_RANGE`, `IN_RANGE >= 1`. Report the range + counts in the footer.
- [ ] 1.5 `.github/workflows/ci.yml` `shard-totality-mutations`: `strategy: { fail-fast: false, matrix: { rows: [...] } }` (choose ranges to balance — `1-12`/`13-24` at 24 rows; rebalance if the PR run shows a skewed half); run line gains `--rows "${{ matrix.rows }}"`; update the `21 rows × ~12 leg-enumerations` comment; `timeout-minutes` stays 30.
- [ ] 1.6 Smoke: `bash plugins/soleur/test/scripts-shard-totality.test.sh` green; battery `--rows 1-12` and `--rows 13-24` each green on a clean tree; malformed `--rows` exits 2.
- [ ] Commit: `ci(8006): parallelize totality-guard enumeration and split the mutations battery into two matrix legs`

## Phase 2 — `test-scripts` K=6 (B)

- [ ] 2.1 `ci.yml` `test-scripts` matrix → `["1/6".."6/6"]`; re-derive the K comment block (K=6, ~39min/6 ≈ 6.5m/leg + ~60s setup).
- [ ] 2.2 Regenerate `scripts/suite-shard-legs.tsv` at n=6: `python3 scripts/regenerate-shard-manifest.py --run 35911999612 --write` (after the ci.yml edit — N comes from the workflow). Provenance header records n=6 + the run id.
- [ ] 2.3 `scripts-shard-totality-mutations.sh`: ROW5 anchors → K=6 literal + mutant drops `"6/6"`; M4 derives n from the manifest `# n=` header (no new literal). Update row description text.
- [ ] 2.4 `scripts/followthroughs/ci-leg-durations-8006.sh` + `.test.sh`: `nlight` 5→6, `nok` 8→9, header `(1/5..5/5)`/`8 legs` text. The probe's `LEG_BUDGET_S=900` stays.
- [ ] 2.5 `scripts/test-all.sh` “fans out over five legs” comment → six; `runbooks/ci-test-scripts-sharding.md` K=5 rows + append measured K=6 row to the K-simulation table.
- [ ] 2.6 Untruncated residue sweep: `grep -rn` for `"1/5"`, `/5"`, `% 5`, `K=5`, `five legs`, `mod 5` across `scripts/ plugins/soleur/test/ .github/workflows/ knowledge-base/engineering/operations/runbooks/` — only intentional non-shard hits remain.
- [ ] 2.7 Smoke: `SCRIPTS_SHARD=1/6 TEST_GROUP=scripts bash scripts/test-all.sh --enumerate` assigns ≥1 registration; `6/6` likewise; `bash scripts/followthroughs/ci-leg-durations-8006.test.sh` green.
- [ ] Commit: `ci(8006): test-scripts K=6 with regenerated n=6 manifest and updated leg-count contract`

## Phase 3 — Heavy manifest (D) + ADR-240 amendment

- [ ] 3.1 `scripts/regenerate-shard-manifest.py`: `--group {light,heavy}` (default light). Heavy arm: artifact regex `^suite-timings-scripts-heavy-\d+$`; registered set `--enumerate scripts-heavy`; leg count from the `test-scripts-heavy` job block; default `--manifest` → `scripts/suite-shard-legs-heavy.tsv`; `GENERATOR_VERSION` 1→2. Generate the heavy table (`--group heavy --run 35911999612 --write`, 3 rows, `# n=3`).
- [ ] 3.2 `plugins/soleur/test/regenerate-shard-manifest.test.sh`: `--group heavy` fixtures (heavy artifact family filter — a light artifact in the dir must not leak in; wrong-group registered set → ⊆ failure).
- [ ] 3.3 `scripts/test-all.sh`: engagement predicate gains the `scripts-heavy` arm → `suite-shard-legs-heavy.tsv` through the same parse/validate/activate path; `SOLEUR_SHARD_MANIFEST_HEAVY` override mirroring `SOLEUR_SHARD_MANIFEST` (same fail-closed cases; consumed + unset at the same site); update the heavy-exclusion comment and the “six legs” line.
- [ ] 3.4 `plugins/soleur/test/scripts-shard-manifest.test.sh`: heavy section — `# n=` == heavy matrix N, ⊆ registered-heavy, legs in range, no dups, every leg pinned, rows ≥ 1 (NOT ≥100; the file has ~3 rows and the suite must say so).
- [ ] 3.5 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: M7 heavy minus-one → GREEN (hash fallback), M8 heavy phantom → GREEN (inert), M9 heavy empty → GREEN (all-hash total) — bound via `SOLEUR_SHARD_MANIFEST_HEAVY`; `DECLARED_TOTAL` → 24.
- [ ] 3.6 `ADR-240` amendment: “Per-group manifests” moved from Rejected alternatives to an adopted amendment — premise (3/3 bijection) still true; adopted for insertion-stability + uniform semantics as a separate file (not an in-file section, keeping light parsers verbatim); update the “test-scripts-heavy unaffected” consequence.
- [ ] 3.7 Smoke: `SCRIPTS_SHARD=2/3 TEST_GROUP=scripts-heavy bash scripts/test-all.sh --enumerate` → manifest assignment active; file removed → positional degrade + notice; `SOLEUR_SHARD_MANIFEST_HEAVY=` (set-empty) → exit 2.
- [ ] Commit: `ci(8006): duration-aware heavy manifest arm + ADR-240 amendment`

## Phase 4 — Verification + ship

- [ ] 4.1 Local suite run: `scripts-shard-manifest.test.sh`, `scripts-shard-totality.test.sh`, `scripts-shard-totality-mutations.sh` (both `--rows` halves + full), `regenerate-shard-manifest.test.sh`, `test-all-affected.test.sh`, `ci-test-aggregator-diagnosis.test.sh`, `ci-leg-durations-8006.test.sh`.
- [ ] 4.2 Live-corpus guards: `scripts/guard-vacuity-floor.test.sh`, `scripts/lint-shell-capture-exit.test.sh`, `plugins/soleur/test/fixture-relative-assert.test.sh` (baseline updated same-commit if new flagged sites), `scripts/lint-orphan-test-suites.sh`.
- [ ] 4.3 `actionlint .github/workflows/ci.yml`. (Plan/tasks are under `knowledge-base/project/` — excluded from markdownlint scope by `.markdownlintignore` #7927.)
- [ ] 4.4 PR-body checklist items mirrored from plan ACs; PR #8665 (existing draft) gets the changes — no new PR. `Refs #8006`, not `Closes`.
- [ ] 4.5 CI measurement on the PR run: mutations legs ≈5m, worst job ≈8.5m or less; record the numbers in the PR body.
- [ ] 4.6 Post-merge: regenerate manifest from the first green K=6 main run if timings shifted; comment results on #8006; the follow-through probe validates the soak automatically.
