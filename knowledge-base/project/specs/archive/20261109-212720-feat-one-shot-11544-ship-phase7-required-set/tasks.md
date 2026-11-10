# Tasks — feat-one-shot-11544-ship-phase7-required-set

Plan: `knowledge-base/project/plans/2026-11-09-feat-ship-phase7-required-set-read-plan.md`. PR body: `Closes #11544`, `Ref #9927` (never `Closes #9927`).

## Phase 1 — the script (RED first)

- 1.1 Write `plugins/soleur/scripts/required-set-report.test.sh` rows S1-S11 against a stub resolver (RED), with a per-row private `TMPDIR` emptiness helper.
  - 1.1.1 Stub replays the real `required` contract (hints first, marker last, rc 0 decided / 3 error / 2 usage).
  - 1.1.2 Private `TMPDIR` per row; one owning EXIT trap; no `git` spawned.
- 1.2 Write `plugins/soleur/scripts/required-set-report.sh` (GREEN): always exit 0, `timeout -k 5 120`, stdout/stderr to two `mktemp` files under one `trap ... EXIT`, `soleur_ctx_sanitize_nl` with a `declare -F` fallback, anchored marker ERE bound to the PR, `tail -n 1`, candidate cap 20, one degraded line otherwise.
- 1.3 Add the disposition row to `.claude/hooks/lib/context-sanitize.test.sh`; run it.
- 1.4 Hand-run the Guard 2 mutation matrix once; record the mutated lines for the PR body.

## Phase 2 — registries

- 2.1 Time the suite (`date +%s%N` bracket) for the real duration in ms.
- 2.2 In a scratch copy, run `python3 scripts/regenerate-shard-manifest.py --incremental --write` to learn the leg; discard header-stamp churn.
- 2.3 Insert exactly one sorted data row each into `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` (`measured`). Do not edit `scripts/test-all.sh`.

## Phase 3 — the fence (canonical)

- 3.1 Fixture first: add rows R1, R2, R2b, R3a/b, the six-variant R4 loop, R5, R6, R7, F2, F3, the `MOCK_FLAP_AT` knob, the default stub script in `PLUGIN_COPY`, `RROOT` stubs (the verdict stub branches on `$1`), the `WANTR` pin (RED).
- 3.2 Edit `plugins/soleur/skills/ship/SKILL.md` Phase 7 fence (GREEN): init block after `VERDICT_OK`; `rs_qs`/`rs_v` samples (verdict bounded by `timeout -k 5 60`) after the every-5th-tick queue read; green-dwell trigger block (`rs_hold`, 10 gate-holding ticks, 3 reads) after the required-check scan.
- 3.3 Add the **Required-set read (#11544)** exit paragraph after **Required-check failure exit.**

## Phase 4 — mirror, parity, docs

- 4.1 Mirror 3.2 into `plugins/soleur/skills/merge-pr/SKILL.md` section 5.2 plus one pointer sentence.
- 4.2 Fixture parity: `[ship.phase7.required_set]`, `RS_SH=...` and the `done < <(bash "$RS_SH" ...)` dispatch in the mirror loop and the shared-token loop.
- 4.3 `plugins/soleur/skills/ship/references/ready-run-wait.md`: line 5, delete the "does not perform this read yet" sentence, add the Phase 7 paragraph.
- 4.4 Comment-only sentence fixes in `monitor-pr-checks.sh` and `ci-head-verdict.sh` headers (no executable line changes).
- 4.5 Hand-run the Guard 1 mutation matrix once; record the mutated lines.

## Phase 5 — pre-push checks (repo-global; the file-selected affected gate misses these)

- 5.1 `bash .claude/hooks/lib/context-sanitize.test.sh`
- 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
- 5.3 `bash scripts/lint-orphan-test-suites.sh`; `bash plugins/soleur/test/scripts-shard-totality.test.sh`; `bash plugins/soleur/test/scripts-shard-manifest.test.sh`; `bash plugins/soleur/test/fixture-env-adoption.test.sh`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `python3 scripts/lint-trap-tempfile-ownership.py`
- 5.4 `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`; `bash plugins/soleur/test/monitor-pr-checks.test.sh`; `bash plugins/soleur/test/ci-head-verdict.test.sh`; `bash plugins/soleur/scripts/required-set-report.test.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`
- 5.5 `shellcheck plugins/soleur/scripts/required-set-report.sh`; `python3 scripts/lint-guard-contract.py`; `python3 scripts/lint-infra-no-human-steps.py`
- 5.6 The two redirect-tombstone tests fail only because the clone is shallow: confirm they fail identically on a clean checkout of the same depth.
- 5.7 `git diff --name-only origin/main | grep -c '^\.github/workflows/'` prints 0.

## Not touched

`.github/workflows/`, `scripts/test-all.sh`, `harness.ts` / `pr-merge-poll.ts`, and the operator-held acts of epic #9927 named in the pipeline brief. The monitor dedupe is documented in place (plan, Deferred section); no issue is filed.
