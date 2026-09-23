# Tasks — ci: test-shard speedup phase 2 (mutations split + K=6 + parallel enumerate + heavy manifest)

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-09-23-feat-ci-test-shard-speedup-phase-2-plan.md`
Refs #8006 (phase-2 arm; issue stays open — the leg-duration soak probe closes it).

Locate all constructs by content anchor, not line number — line numbers were verified against this branch on 2026-09-23 and will drift. No `.ts` files in this diff → the bun-test hook will not fire; verification = targeted suites + authoritative CI. Suggested commit grouping: Phase 1 (guard+battery+ci matrix), Phase 2 (K=6 + manifest regen + probe + runbook), Phase 3 (heavy manifest arm + ADR amendment), Phase 4 (verify + ship).

## Phase 1 — Parallel guard + battery row-range split (A + C)

- [x] 1.1 `plugins/soleur/test/scripts-shard-totality.test.sh`: parallelize every independent child `bash test-all.sh --enumerate` invocation — light leg-union loop, altK inner loops (light + heavy), malformed-spec loops (light + heavy), over/long/unset probes, `TEST_GROUP=all` enumerate. Mechanics: `child & pids[i]=$!` → per-pid `wait "${pids[i]}"` + rc capture (never bare `wait`); distinct `$WORK` file per child; verdicts emitted serially in declared order; index loops only (bash 3.2); bounded fan-out ≤ ~10 with a comment noting the bound.
- [x] 1.2 Anchor sweep on that edit: `totality_holds` `diff -q "$1" "$2" >/dev/null 2>&1` body, the `cat "$WORK/ref_static" "$WORK/ref_glob" | sort -u > "$WORK/reference"` derivation line, and `enumerate_leg`'s argv shape stay byte-exact (HARNESS + ROW6 anchors in the battery).
- [x] 1.3 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: `--rows A-B` flag — validate `^[0-9]+-[0-9]+$`, `1<=A<=B<=DECLARED_TOTAL`, else exit 2; parse before WORK setup; unset = all rows. `next_row` helper increments `DECLARED` at every row call site (`row`/`frow`/bespoke: ROW6 tautology, M4) and gates execution by range. CONTROL + instrument self-test run unconditionally on every leg.
- [x] 1.4 Replace `MIN_ROWS=21` floor with: `DECLARED == DECLARED_TOTAL` (21 → 24 once 3.2's M7–M9 land — keep the constant in sync in the same edit that adds a row), `EXECUTED == IN_RANGE`, `IN_RANGE >= 1`. Report the range + counts in the footer.
- [x] 1.5 `.github/workflows/ci.yml` `shard-totality-mutations`: `strategy: { fail-fast: false, matrix: { rows: [...] } }`; run line gains `--rows "${{ matrix.rows }}"`; `timeout-minutes` stays 30. **Commit-boundary rule:** the flag validator refuses `B > DECLARED_TOTAL`, so the range literals must match the row count at each commit — Phase 1 shipped `1-11`/`12-21` (21 rows), Phase 3.5's commit bumped to `1-12`/`13-24` (24 rows).
- [x] 1.6 Smoke: guard green (35/35, ~18s vs ~60s); battery `--rows 1-11` and `--rows 12-21` each green on a clean tree; malformed `--rows` exits 2 (all shapes probed).
- [x] Commit: `0338eba6f8` — `feat(8006): split mutation battery 2 ways + parallelize totality-guard enumerate children`

## Phase 2 — `test-scripts` K=6 (B)

- [x] 2.1 `ci.yml` `test-scripts` matrix → `["1/6".."6/6"]`; K comment block re-derived (K=6, ~39min/6 ≈ 6.5-7.7m/leg + ~60s setup).
- [x] 2.2 `scripts/suite-shard-legs.tsv` regenerated at n=6 from run 35911999612 (489 labels, predicted legs 384.4–404.4s spread 20s; 84 assignments moved).
- [x] 2.3 `scripts-shard-totality-mutations.sh`: ROW5 anchors → K=6 literal + mutant drops `"6/6"`; M4 derives n from the manifest `# n=` header (incl. n=0 guard); row description text updated.
- [x] 2.4 `scripts/followthroughs/ci-leg-durations-8006.sh` + `.test.sh`: `nlight` 5→6, `nok` 8→9, header `(1/6..6/6)`/`9 legs` text. `LEG_BUDGET_S=900` unchanged.
- [x] 2.5 `scripts/test-all.sh` "five legs" comment → six; `runbooks/ci-test-scripts-sharding.md` K=5 rows → K=6 + topology table extended with the mutations split row.
- [x] 2.6 Untruncated residue sweep done — remaining `/5`/`% 5` hits are intentional (inngest soak probe mod-5 slicing, historical measured data, unrelated literals).
- [x] 2.7 Smoke: `SCRIPTS_SHARD=1/6` `3/6` `6/6` → 83/83/80 registrations; `ci-leg-durations-8006.test.sh` 13/13 green.
- [x] Commit: `b53d412b5c` (combined with Phase 3 — `feat(8006): K=6 light legs + duration-aware heavy manifest`)

## Phase 3 — Heavy manifest (D) + ADR-240 amendment

- [x] 3.1 `scripts/regenerate-shard-manifest.py`: `--group {light,heavy}` (default light). Heavy arm: artifact family `suite-timings-scripts-heavy-*`; registered set `--enumerate scripts-heavy`; leg count from the `test-scripts-heavy` job block; default `--manifest` → `scripts/suite-shard-legs-heavy.tsv`. Generated `scripts/suite-shard-legs-heavy.tsv` (`--group heavy --run 35911999612 --write`, 3 rows, `# n=3`).
- [x] 3.2 `plugins/soleur/test/regenerate-shard-manifest.test.sh`: `--group heavy` fixtures H (mixed light+heavy artifacts — light labels warn-drop) + I (all-unregistered → exit 2); floor raised to 20.
- [x] 3.3 `scripts/test-all.sh`: engagement predicate gains the `scripts-heavy` arm → `suite-shard-legs-heavy.tsv` through the same parse/validate/activate path; `SOLEUR_SHARD_MANIFEST_HEAVY` override (same fail-closed cases; consumed + unset with `SCRIPTS_SHARD`/`SOLEUR_SHARD_MANIFEST`); comments updated.
- [x] 3.4 `plugins/soleur/test/scripts-shard-manifest.test.sh`: heavy section — `# n=` == heavy matrix N, ⊆ registered-heavy, legs in range, no dups, every leg pinned, rows ≥ 1; floor raised to 25 (now 32 checks).
- [x] 3.5 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: `hfrow()` added (binds `SOLEUR_SHARD_MANIFEST_HEAVY`); M7 heavy minus-one → GREEN (hash fallback), M8 heavy phantom → GREEN (inert), M9 heavy header-only → **RED** (all-hash `{3,2,2}` starves leg 1 — the zero-assignment refusal outranks totality at n=3; plan's GREEN expectation corrected on first red), inserted BEFORE MUSTPASS; `DECLARED_TOTAL` → 24; ci.yml ranges `1-12`/`13-24` in the same commit; heavy fixtures materialize unconditionally. M7's minus-one drops `battery-tag-authorship-mutations` specifically (its hash lands on a still-populated leg) so the row is the positive coverage case.
- [x] 3.6 `ADR-240` amended — per-group manifests moved rejected → adopted (insertion-stability + uniform semantics; separate file, not in-file section); heavy consequence + override-seam bullets updated.
- [x] 3.7 Smoke: `SCRIPTS_SHARD=2/3 TEST_GROUP=scripts-heavy` → `scripts/battery-tag-authorship-mutations`; missing file → positional degrade + notice; `SOLEUR_SHARD_MANIFEST_HEAVY=` set-empty → exit 2 (verified direct, no pipeline).
- [x] Commit: `b53d412b5c` (combined with Phase 2)

## Phase 4 — Verification + ship

- [x] 4.1 Local suite run: `scripts-shard-manifest.test.sh` 32/32, `scripts-shard-totality.test.sh` 36/36 (+1 tiling row post-review), `regenerate-shard-manifest.test.sh` 23/23, `test-all-affected.test.sh` 50/50 (31/31 post-#8329 rebase), `ci-leg-durations-8006.test.sh` 13/13. Battery `--rows 1-12`/`13-24` on clean tree: **13/13 each** (12 rows + control per half).
- [x] 4.2 Live-corpus guards: `guard-vacuity-floor` 23/23, `lint-shell-capture-exit` 25/25, `fixture-relative-assert` 62/62 after baseline regen (generator-test 21→26 sites, same commit).
- [x] 4.3 `actionlint .github/workflows/ci.yml` — clean (one pre-existing SC2034 at :1705, unrelated).
- [ ] 4.4 PR-body checklist items mirrored from plan ACs; PR #8665 (existing draft) gets the changes — no new PR. `Refs #8006`, not `Closes`.
- [ ] 4.5 CI measurement on the PR run: mutations legs ≈5m, worst job ≈8.5m or less; record the numbers in the PR body.
- [ ] 4.6 Post-merge: regenerate manifest from the first green K=6 main run if timings shifted; comment results on #8006; the follow-through probe validates the soak automatically.
