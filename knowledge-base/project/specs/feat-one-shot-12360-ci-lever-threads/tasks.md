# Tasks — feat-one-shot-12360-ci-lever-threads

Derived from `knowledge-base/project/plans/2026-11-08-fix-ci-lever-residual-threads-plan.md`.
Closes #12360 (thread 1); Refs #9729 (schedule term 1 — issue stays open for the later R3 re-ruling).

## Phase 1 — Thread 2: folded-job classification (`scripts/ci-pr-affected-replay.py`)

- [x] 1.1 Add `FOLDED_JOBS = frozenset((...))` immediately after `ALWAYS_RUN_JOBS` (~:214): exactly the 11 ci.yml member tokens (`adr-ordinals`, `rule-body-lint`, `tc-document-sha-guard`, `marketplace-manifest-guard`, `service-role-allowlist-gate`, `credential-path-guard`, `lockfile-sync`, `grok-fidelity`, `sandbox-canary-capture-gate`, `plugin-root-propagation-gate`, `harness-discovery`) + `cla-check` + `cla-evidence`; header comment naming the two authorities (ci.yml `member` tokens; `scripts/required-checks.txt` CLA rows) and the mechanism (posted check names surface on a refused merge_group run's job listing).
- [x] 1.2 `suites_failed_in`: extend the non-suite branch to `in ALWAYS_RUN_JOBS or in FOLDED_JOBS`; folded names record `note: "folded-job"` (never `unclassified-job`, never `ne`).
- [x] 1.3 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: add parity row `sorted(FOLDED_JOBS \ {cla-check,cla-evidence}) == sorted(member tokens extracted from ci.yml aggregate steps)` with non-empty floor; pin `cla-check`/`cla-evidence` to whole lines in `scripts/required-checks.txt`; disjointness `FOLDED ∩ (ALWAYS_RUN ∪ suite families) = ∅`; classification fixture row (failing `rule-body-lint` job → `rule-irrelevant`); mutant row dropping `in FOLDED_JOBS` (must go RED); `mystery-job` row unchanged.
- [x] 1.4 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` — all rows + mutants green.

## Phase 2 — Thread 1: bounded-parallel reads (`scripts/followthroughs/pr-battery-gate-saving-9323.sh`)

- [x] 2.1 Worker plumbing: `_pbg_pool` bounded-`&` runner with `wait -n -p` reap + bash≥5.1 serial fallback (mirror `test-all.sh:2230`); `PBG_JOBS` validation (`^[0-9]+$`, clamp 1-16, default 8); per-unit result files under `$WORK/`; `cut` marker convention (worker rc-46 → `cut` row → parent `cut_ny`); missing result file → CANNOT ESTABLISH; **workers never emit probe output or `exit`** — `cut_ny`/`fail_api` exist only in the parent.
- [x] 2.2 Runs-list phase: fetch ≤`PAGE_CAP` pages in one pool wave; short-page rule applied after aggregation in page order.
- [x] 2.3 Examine loop: parent writes candidate list; worker per candidate (head-lookup → files → machinery filter → jobs read) writes `qual|skip|cut|fail` to `$WORK/exam-<idx>`; parent sorts `qual` by `idx`, takes first `MAX_RUNS`; `green_prs`/`green_ids`/`sum_min`/`qwait_*` aggregated in candidate order.
- [x] 2.4 Artifact phase: stage A parallel listings (`$WORK/arts-<rid>`); parent builds download queue honoring `ART_READ_CAP` (listings + downloads counted by construction); stage B parallel downloads → `$WORK/tsv-<rid>-<aid>`; `run_partial`/`evidence_absent` semantics unchanged; stage C serial per-run `awk` pricing with existing `seen[$1]` dedupe.
- [x] 2.5 Escape loop + pending re-scope: worker per PR writes `$WORK/esc-<pr>` = `dropped|open|pending|ok|escape <detail>`; `state=="open"` → new `open` bucket (sha-set and sha-empty alike); parent prints `note:` lines for `dropped` AND `open`; merged-PR `pending` semantics unchanged.
- [x] 2.6 `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh`: re-pin `d2` (open PR → `open` bucket + note, not pending); new rows — open-PR note line, merged-PR missing push run still pends (exit 2), parallel-mode wall row (SLOW fixture converges under `PBG_BUDGET_S` where serial exits 2), missing-worker-result → exit 3, `PBG_JOBS` validation + clamp rows; all pre-existing rows (`s1`-`s9`, `b1`-`b9`, `c1`-`c4`, `pg1`, `h1`, `d1`, `q1`, `e1`, `m11`, `dx`, `t1`, `n1`, `w1`, `u0`-`u2`, xtrace-78) still green.
- [x] 2.7 `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — all rows green, assertion floor ≥ 50 met.

## Phase 3 — Verification + bookkeeping

- [ ] 3.1 Run both suites + `scripts/test-all-pr-battery-gate.test.sh`; run the `test-all.sh` shard legs covering the two edited suites.
- [ ] 3.2 Post-merge: `PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` locally → record the PASS/FAIL verdict line as a comment on #9323 (resolves its measurement arm).
- [ ] 3.3 PR body: `Closes #12360`, `Refs #9729`, `## Changelog` section; expected semver label `patch`.
- [ ] 3.4 Do NOT edit or comment on PR #12377; if it lands first, rebase and re-key the new fake-gh fixtures to its `keyof`/`fx_err` scheme.
