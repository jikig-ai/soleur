# Tasks — feat(ci): carve heavy test-all suites into `scripts-heavy` + `test-scripts` K=5

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-09-22-feat-ci-test-shard-speedup-plan.md`
Refs #8006 (delivers the rebalance arm; the label-keyed partition mechanism stays open — do NOT `Closes #8006`).

Locate all constructs by content anchor, not line number — line numbers in the plan were verified against `origin/main` on 2026-09-22 and will drift. Tests first (cq-write-failing-tests-before): extend the guards so they go RED on the absent group BEFORE the runner/workflow edits.

## Phase 1 — Guard + consumer extensions (RED first)

- [x] 1.1 `scripts/test-all-enumerate-toolchain.test.sh`: widen the group derivation `sed` char class `[a-z|]*` → `[a-z|-]*` (:308) and the validity check `^[a-z]+$` → `^[a-z-]+$` (:319) so `scripts-heavy` survives derivation.
- [x] 1.2 `plugins/soleur/test/scripts-shard-totality.test.sh`: add a `scripts-heavy` pass — parameterize `enumerate_leg` (:89-99, currently hardcodes `TEST_GROUP=scripts`/`--enumerate scripts`), reference extraction scope (:123-132 gains a `want_scripts_heavy` block extractor), leg list from the `test-scripts-heavy:` job block (:169-178), wire check (:201-210). Heavy reference floor is EXACTLY 3 — do NOT copy `REF_N >= 100` (:157). Heavy any-K rows use `altK in 2 3` ONLY — `SCRIPTS_SHARD=4/5` over 3 registrations is syntactically valid but leg 4 hits the zero-assignment refusal (exit 2, correct); add a row asserting that refusal instead. Re-derive `MIN_ROWS` (:377) per the file's itemized-floor discipline. Update the `TEST_GROUP=scripts`-hardcoded rows (:316,:342,:356,:365) to also cover `scripts-heavy`.
- [x] 1.3 `plugins/soleur/test/scripts-shard-totality-mutations.sh`: update ROW5's anchored literal (:297) to the new light matrix `["1/5"…"5/5"]`; add a row mutating the heavy matrix literal; add the re-gate row (heavy registration back under `want_scripts` → RED via empty-leg refusal).
- [x] 1.4 `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`: W2 needs-count `== 4` → `== 5` (:409); `want` map gains `SCRIPTS_HEAVY_RESULT: test-scripts-heavy` (:382-389); `run_body` 5-arg (:135-141); success-line needle ↔ new ci.yml literal (:166,:283); re-derive MIN_ROWS (:422-432); failure-arm fixtures cover heavy matrix legs.
- [x] 1.5 `plugins/soleur/test/ship-battery-owed.test.sh:705`: anchor/reorder the alternation so `test-scripts` cannot prefix-match `test-scripts-heavy` (longest-first or end-anchor); update the premise comment in `plugins/soleur/skills/ship/scripts/battery-owed.sh` (:25-27 premise, :375-377 `want_*` list).
- [x] 1.6 `scripts/test-all-infra-coverage-notice.test.sh`: add `scripts-heavy` to BOTH loops (:227 and :243).
- [x] 1.7 `plugins/soleur/test/fullsuite-merge-gate.test.ts`: add `scripts-heavy` to `SHARDS` (:50); widen positional regex `[A-Za-z]+` → `[A-Za-z-]+` (:145).
- [x] 1.8 `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`: extend `job_block()` coverage to `test-scripts-heavy` — note this is a PARITY assertion (the `users` set derives from `plugins/soleur/test/*.test.sh`, i.e. scripts-group needs; the three heavy suites are bash+git/coreutils only). `job_block()`'s awk already terminates `test-scripts:` correctly at the hyphenated `test-scripts-heavy:`.
- [x] 1.9 Pin-parity guards — close the first-match blindness for the cloned in-file pins: `plugins/soleur/test/required-checks-canonical-parity.test.sh:255-262` (`head -1` extraction) and `apps/web-platform/test/c4-likec4-version-pin.test.ts:66` (non-`g` regex) — extend both to assert ALL in-file occurrences of `GITLEAKS_VERSION`/`GITLEAKS_SHA256`/`likec4@` agree (e.g. `grep -oE … | sort -u` → 1 distinct value).
- [x] 1.10 Verify RED: run the extended guards — they must fail on the absent `scripts-heavy` group / missing job before implementation proceeds.

## Phase 2 — Runner (`scripts/test-all.sh`)

- [x] 2.1 `TEST_GROUP` case arm (:617-625): add `scripts-heavy` to the accepted list; update both usage strings and the doc comment (:603-611).
- [x] 2.2 Add `want_scripts_heavy() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts-heavy" ]]; }` beside the `want_*` block (:710-717). MUST include `all` (ADR-183 ship gate).
- [x] 2.3 Re-gate the three heavy registration sites from `want_scripts` to `want_scripts_heavy`: registry battery incl. its `skip_suite` relevance arm (:2509-2515), tag-authorship (:2872), run-all incl. relevance arms (:2983-2991). Keep the `run_suite`/`skip_suite` chokepoint shape.
- [x] 2.4 Widen the SCRIPTS_SHARD group-scope refusal (:653) from `!= "scripts"` to accept `scripts` OR `scripts-heavy`; update the error prose. The `unset SCRIPTS_SHARD` (:684) stays AFTER the check.
- [x] 2.5 Add a test that `bash scripts/test-all.sh --enumerate all` output contains all three heavy labels (full-gate coverage pin).
- [x] 2.6 Verify: `--enumerate scripts-heavy` emits exactly 3 `SUITE_REGISTRATION` records; `SCRIPTS_SHARD=2/3 TEST_GROUP=scripts-heavy` executes exactly one heavy suite; `SCRIPTS_SHARD` set with other groups still exits 2.

## Phase 3 — Workflow (`.github/workflows/ci.yml`)

- [x] 3.1 `test-scripts` matrix `["1/3","2/3","3/3"]` → `["1/5","2/5","3/5","4/5","5/5"]`.
- [x] 3.2 Re-derive the `timeout-minutes: 60` justification comment on `test-scripts` (:1141-1176) — the battery budget no longer lives on this leg.
- [x] 3.3 Add `test-scripts-heavy` job: same step shape as `test-scripts` (checkout `fetch-depth: 0`, gitleaks, likec4, setup-bun pins per the lockstep note :881-885 — extend the note to four jobs), `matrix.shard: ["1/3","2/3","3/3"]`, `SCRIPTS_SHARD: ${{ matrix.shard }}` env, `TEST_TIMING_LOG` + artifact upload named `suite-timings-scripts-heavy-${{ strategy.job-index }}` — v4 artifact names are immutable per run; a verbatim `suite-timings-scripts-*` clone collides with light legs and reds every CI run. `timeout-minutes: 60` (≤ 60 keeps `test-scripts` on a longest needs-path).
- [x] 3.4 Aggregator `test`: `needs:` + `SCRIPTS_HEAVY_RESULT` env + `entries=()` (:1481) + success-line literal (:1555) + `failure` arm matrix wording (:1503 covers both `test-scripts*`).
- [x] 3.5 Move the stale K-simulation comment block (:998-1136, ~140 lines) to new runbook `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` carrying the re-derived table + reproduction recipe (CI-artifact TSV interleave under C collation); leave a 2-line pointer comment. Sweep stale prose — grep-driven, not memory: `grep -rn 'webplat.*bun.*scripts\|test-scripts' .github/workflows/ scripts/ plugins/soleur/skills/ plugins/soleur/scripts/` and update `:57, :870, :873-885, :1226-1230, :1331-1344`, `main-health-monitor.yml:88`, `grok-pre-push-gate.sh:6`, `work/SKILL.md:1505`, `test-all.sh:613,:650,:663,:829,:317`, `pr-quality-guards.yml:413`, `gdpr-gate-self-test.yml:82`, `ci-test-aggregator-diagnosis.test.sh:8` header.
- [x] 3.6 B9 check: confirm `prod-version-drift-check.test.sh`'s `green2-test-scripts-at-boundary` (:2085-2091) `v2 ≥ 60`, else extend the derivation to max over both matrix jobs.
- [x] 3.7 Verify: `wc -c .github/workflows/ci.yml` ≤ `origin/main` byte count; yamllint/workflow validators pass.

## Phase 4 — Docs + ADR

- [x] 4.1 `plugins/soleur/skills/work/SKILL.md`: update `TEST_GROUP=` enumeration (:1160) and §9 shard map (:1037 — heavy suites' paths now route to `scripts-heavy`).
- [x] 4.2 `plugins/soleur/skills/ship/SKILL.md:364`: gate-job enumeration gains `test-scripts-heavy`.
- [x] 4.3 Create ADR-238 (provisional ordinal; renumber+sweep on collision): "Carve cost-heavy scripts suites into `TEST_GROUP=scripts-heavy`" via `soleur:architecture`.
- [x] 4.4 No C4 edit (CI-internal topology; verified no external actor/system/store change).

## Phase 5 — Follow-through + verify

- [x] 5.1 New `scripts/followthroughs/ci-leg-durations-8006.sh`: queries first three post-merge `main`-push CI runs via `gh api`; leg > 15 min → exit 1; < 3 qualifying runs → exit 2; else 0.
- [x] 5.2 File tracker issue with `<!-- soleur:followthrough script=scripts/followthroughs/ci-leg-durations-8006.sh secrets=GH_TOKEN earliest=<merge+1d ISO-8601> -->` + `follow-through` label.
- [x] 5.3 Run the affected guards: `scripts-shard-totality.test.sh`, `scripts-shard-totality-mutations.sh`, `ci-test-aggregator-diagnosis.test.sh`, `test-all-enumerate-toolchain.test.sh`, `test-all-infra-coverage-notice.test.sh`, `ship-battery-owed.test.sh`, `fullsuite-merge-gate.test.ts`, `scripts-shard-runtime-coverage.test.sh`, `prod-version-drift-check.test.sh`, `workflow-run-deploy-invariants.test.sh`, `lint-orphan-test-suites.sh`, `workflow-file-size.test.ts` — all GREEN.
- [x] 5.4 PR's own CI run validates end-to-end: every `test-scripts*` leg ≤ 15 min, `test` aggregator green (AC6). Record leg timings in the PR body.
