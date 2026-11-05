# Tasks — feat-one-shot-10448-boundary-prefix-deferred

Derived from `knowledge-base/project/plans/2026-11-05-feat-boundary-prefix-deferred-item-plan.md`.
Branch: `feat-one-shot-10448-boundary-prefix-deferred`. Draft PR: #12199. Issue: #10448.

## Phase 0 — Setup and ruling

- [x] 0.1 Spawn `soleur:engineering:cto` (prompt: "Rule on this technical question (BINDING). Do NOT use AskUserQuestion.") with the evidence packet from plan Phase 0 — PR5d deferral ruling row 10 + ACs, `receipts/glob-rate/glob-rate.tsv` row, `glob_decide` code facts (`src=measured` gate, `GLOB_ALWAYS_MAX_MS=10000`, 1222 ms = generated `default-weight` placeholder not a measurement), the three arms (a / a' / b) and their per-arm disqualifying facts — **ruled 2026-11-05: arm (a') measured-verdict; second row: rename-carry condition dissolved under strict zero**
- [x] 0.2 Record the ruling verbatim in `knowledge-base/project/specs/feat-one-shot-10448-boundary-prefix-deferred/decision-challenges.md`, replacing the `pending - assumed` row (format: `Ruled by CTO agent, <date>: <decision> - <rationale>`)

## Phase 1 — Resolution (arm a' ruled; arm B executes ONLY if the measured row lands >10 s and `glob_decide` returns `baselined`)

### Arm B — accepted-gap (terminal state of arm a' only if measured >10 s)

- [ ] 1a.1 Edit `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §7: add the residual paragraph naming `boundary-prefix.test.sh`'s four dir globs (~164 files under `.claude/hooks/` and `plugins/soleur/scripts/`) and the argv-bearer-sweep whole-tree census as the audit's documented lower bound, with measured rates/durations and a pointer at `DECLARED LIMITS`
- [ ] 1a.2 Verify `python3 -I scripts/ci-pr-affected-replay.py ratchet` reports `exit=0 reason=pass live=0` (no edge/accept change under this arm)
- [ ] 1a.3 Post the resolution comment on #10448 naming the ruling and closing the deferred item (arm b)

### Arm A' — install (RULED 2026-11-05; the 25% constant is NOT amended)

- [ ] 1b.1 Obtain a `measured` duration row: time the suite, regenerate `scripts/suite-durations.tsv` via `scripts/regenerate-shard-manifest.py` (per the ruling there is NO arm-a constant amendment — if the measured row exceeds `GLOB_ALWAYS_MAX_MS=10000` the verdict is `baselined` and the Arm-B documentation tasks execute instead)
- [ ] 1b.2 Re-measure at work time: `git fetch origin main && git rev-parse origin/main`; save `bash scripts/test-all.sh --print-selection --paths=README.md > rows.txt`; run `python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates <4-dir-glob TSV> --list rows.txt --pairs <7-pair TSV> --commits 200 --base <sha> --spot-check 3 --out knowledge-base/project/specs/feat-one-shot-10448-boundary-prefix-deferred/receipts/`
- [ ] 1b.3 Install per the measured verdict and the ruling (`glob:`/`dir/` edges in `AFFECTED_PLUGINS_SOLEUR_TEST_BOUNDARY_PREFIX_TEST_SH_PATHS` :4165 or an `ALWAYS_ON_SUITES` entry :132 — both in `scripts/lib/test-affected-paths.sh`; precedent: #11648 demotion when a re-priced median exceeded LOCAL_FAST_CAP_MS)
- [ ] 1b.4 Reconcile the 7 named pairs' dispositions: re-run the audit for `stale-accept` on the 13 accept rows; keep `^glob:.claude/hooks/*guardrails*.sh` and the exact-file edges (deferred-item AC 6)
- [ ] 1b.5 Verify: ratchet `exit=0`; `scripts/test-affected-kb-consumers.test.sh`; `scripts/test-all-fast-tier-budget.test.sh` (if `always_on`); selector spot check selecting the suite on a `.claude/hooks/` diff. Runner-change caveat: local `--affected` degrades to the full battery — run detached
- [ ] 1b.6 Post the resolution comment on #10448 (arm a/a', with measured numbers)

## Phase 2 — Observation-window evidence

- [ ] 2.1 Re-run `GH_TOKEN=$(gh auth token) bash scripts/followthroughs/ratchet-observation-window-10865.sh` (read-only) and post the status line + every `NOT YET:` line verbatim as a comment on #10865. Session baseline 2026-11-05: `units=115 wall_p95_s=269 wall_max_s=279`, paused on red merge_group run 42084778935 (`exit=1 new-pair`), no bot PR, p95 over the 240 s ceiling
- [ ] 2.2 Optional one line on #12129 noting the fresh whole-population p95 read

## Phase 3 — #10859 status comment (verify only, no flip)

- [ ] 3.1 Post a dated comment on #10859: (1) window open/paused per the Phase-2 probe; (2) rename-carry design dissolved as vacuous under strict zero (CTO ruling 2026-11-05 — conditional on strict zero holding, revival blocked by `baseline-reintroduced` + condition (c)); (3) jobs-API canary met per the 2026-10-23 observation-log entry (PR #10899, run 39937846319 — noting the run-level conclusion also carried draft-light and e2e reds, so `continue-on-error`'s run-level effect was not isolated)
- [ ] 3.2 Record the item-9 remainder for the owner: oracle control (a), accept-row growth design (b), cumulative baseline check at merge time (c), re-ruled ceilings (e — DONE), budget-owner go-ahead (f)

## Phase 4 — Verification and close-out

- [ ] 4.1 Confirm untouched: `continue-on-error: true` on `affected-index-ratchet`, `scripts/required-checks.txt`, `CI_PR_AFFECTED`, the activation lock (`git diff origin/main...HEAD -- .github/workflows/ci.yml scripts/required-checks.txt` is empty for those lines)
- [ ] 4.2 Confirm the deferred item's surviving ACs: individual dispositions + `^glob:.claude/hooks/*guardrails*.sh` edge installed (AC 6)
- [ ] 4.3 Update `decision-challenges.md` if any work-phase ruling deviated from the plan
