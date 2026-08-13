---
title: "Tasks — signal-shape propagation + whole-repo orphan walk"
branch: feat-one-shot-7429-7402-killed-signal-and-orphan-globs
plan: knowledge-base/project/plans/2026-08-13-fix-killed-propagation-and-orphan-suite-globs-plan.md
lane: single-domain
closes: [7429, 7402, 7523]
---

# Tasks

Derived from the finalized (post-review) plan. Phase order is load-bearing: contract changes
precede consumer changes, and every guard is RED-first.

**Read before starting:** the plan's `## Plan Review Revisions` table (R1-R31). Three statements
in earlier revisions were falsified at review — do not reintroduce them.

## Phase A0 — blast-radius enumeration (no edits)

- [ ] 0.1 Enumerate consumers: `git grep -rn 'run-registered-suites\|scripts/test/run-all' -- '*.sh' '*.yml' '*.ts' '*.md' | grep -v knowledge-base/project/`. Record which are binary zero/non-zero vs read a specific code.
- [ ] 0.2 Re-confirm `apps/web-platform/infra/run-registered-suites.test.sh:586` still does `cp "$SUT" "$PRISTINE"` (single-file). **If yes, the classifier MUST be inlined** — ADR-177 §A3 binds. (Plan R3: an earlier revision asserted the opposite.)
- [ ] 0.3 Re-confirm no CI layer special-cases 137/143.
- [ ] 0.4 Confirm the two exact-string consumers of the summary line still match: `run-registered-suites.test.sh:442` and `plugins/soleur/test/main-health-monitor-workflow.test.sh:554,571`.

## Phase A1 — `run-registered-suites.sh` propagation (RED first)

- [ ] 1.1 Add Guard 2 rows to `run-registered-suites.test.sh` **in the existing `run_mutant` vocabulary** (`:583-691`): python mutator on the pristine `cp`, a named `[FAIL] <id>` to kill, the DID-NOT-LAND diff, a noop-control. Confirm RED.
- [ ] 1.1a **The A6 tripwire is row M1b, at the SHIM — not inside the fixture suite.** Measured: at the suite position `kill -KILL $$` and `exit 137` are identical (`rc=$?` 137, xargs 0); at the shim, a real signal gives xargs **125** vs **123** for a deliberate exit. Assert 125. Use the house fixture shape `kill -TERM $$` + `sleep 5` (`test-all-killed-classification.test.sh:149`) — the sleep prevents an async-kill race.
- [ ] 1.1b **Pay the T9 integration debt in the same commit:** rewrite the `drop-accounting` mutator (`:673-674` — its literal is deleted by task 1.5), raise `MIN_ASSERTIONS` (`:716`) **and** the `>= 7` matrix floor (`:686`), and decide how G2 M5 is scored (its mutation and killing assertion are in different files; the harness cannot span them today).
- [ ] 1.2 Add the end-to-end arm in `scripts/test-all-killed-classification.test.sh` (it owns `build_sandbox`): assert `[KILLED]` in real `run_suite` output **and** `test-all.sh` exit 3.
- [ ] 1.3 Inline a **two-guard** classifier (`rc > 128` + non-empty `kill -l $((rc-128))`). Do NOT copy `<= 192` (ADR-177: not load-bearing). Keep rc 124 → failed.
- [ ] 1.4 Count `killed` **in the parent**, right after `RED=`/`PASS=` at `:346-347` — outside `dump_reds`, outside the `{…} | sed` pipeline. Derive `failed=$(( RED - killed ))` and a deterministic `kill_rc` (lexicographically-first killed suite key).
- [ ] 1.5 Replace the terminal `(( RED == 0 && … ))` at `:481`: `failed>0 || UNACCOUNTED>0 → 1`; `killed>0 → "$kill_rc"`; else 0.
- [ ] 1.6 Emit a killed breakdown line **gated on `killed > 0`** (mirrors `test-all.sh:1317-1319`). Keep the `:480` summary line BYTE-IDENTICAL — two exact-string consumers.
- [ ] 1.7 Verify `:469-470` logdir retention needs no edit (`killed>0 ⇒ RED>0` ⇒ logs kept) and the child's `PASS`/`RED  ` emit shape is untouched (`:252` T6b pin).
- [ ] 1.8 **Decide and implement D3 (UNACCOUNTED / xargs-125).** Preferred: capture xargs rc via `PIPESTATUS` (currently lost to `| tee "$LOG"`) and treat `125` + non-empty UNACCOUNTED as the killed shape. Otherwise record the `[FAIL]` rationale in the runner header. Silence fails AC9b.
- [ ] 1.9 GREEN, then re-run each mutation row **individually** and confirm each reddens.

## Phase A2 — `.github/scripts/test/run-all.sh` propagation (RED first)

- [ ] 2.1 Write Guard 3 rows. **Each fixture arm must stage ≥10 suites** or `MIN_SUITES=10` fires first and masks the row. M1 uses a real signal.
- [ ] 2.2 Replace `if ! bash "$t"; then FAIL=1; fi` with rc capture + classification; keep the floor dominant.
- [ ] 2.3 Constraint: this feeds `guard-script-fixture-tests`, a REQUIRED no-path-filter check. Stay BASH-ONLY.
- [ ] 2.4 GREEN, then mutate each row individually.

## Phase A3 — ADRs + issue correction

- [ ] 3.1 Write `ADR-187` (decisions 1 + 3: exit-shape signalling, observed-rc-only). Re-verify the ordinal is free across all `origin/*` refs first.
- [ ] 3.2 **Append** an ADR-177 addendum (never edit its body): decision 2 (exit 3 stays top-level-only), decision 4 (A6 status correction), the npm measurement, and that the `exec vitest` remedy is unnecessary.
- [ ] 3.3 Strike the npm row from #7429's body; record the measurement there.
- [ ] 3.4 Reconcile with ADR-178 (shared bash primitives) and add a **textual parity pin** asserting the inlined classifier is byte-identical across the three files.
- [ ] 3.5 Update `.github/workflows/main-health-monitor.yml:580` — it claims only "the six suites … via `bun`/`node` directly" can surface a signal-shaped exit; the set grows by 108 (98 infra + 10 fixture).

## Phase B1 — widen the orphan linter (RED first)

- [ ] 4.1 Create `scripts/lint-orphan-test-suites.test.sh` with Guard 1's **M1-M11** against a **synthetic** git repo (path-shaped empty files + the three real inputs) — not a tree copy: the worktree is 13,630 files / 258 MB and 11 copies is ~2.8 GB on a loaded box. It must still be a real git repo (`git init` + `git add`) or `git ls-files` returns nothing and every row is vacuous; assert non-empty enumeration before any row runs.
- [ ] 4.1a Include the four rows added at review: **M8** producer partial-narrowing (revert to `scripts/*.test.sh` — clears every floor and prints `none`; highest-value row), **M9** surface 4, **M10** surface 5, **M11** exclusion key matching zero files.
- [ ] 4.1b Give M1/M3/M5/M9/M10 a **single-surface precondition** — assert the target suite is covered by exactly one surface before mutating, else a union match makes the mutation a silent no-op.
- [ ] 4.2 Widen to the whole-repo walk: `git ls-files '*.test.sh'` diffed against the **six**-surface union. Pin `LC_ALL=C` for all sort/comm.
- [ ] 4.3 **Derive glob patterns from `test-all.sh`** — add `--print-suite-globs`; never duplicate the nine patterns into the linter (else M5 passes green).
- [ ] 4.4 Re-key exclusions from **basename to repo-relative path**; fail closed when a key matches 0 or ≥2 tracked files. (Collisions verified: `parity.test.sh`, `argv-ceiling.test.sh`.) Keep the `#NNNN` requirement.
- [ ] 4.5 Re-key floors: producer-side whole-repo count floor + a **`< 1` zero-check per surface** (not ratcheting counts). Keep `cmd_seen`.
- [ ] 4.6 Rewrite the stale `:11-13` header rationale; update the citation at `scripts/lint-workflows.sh:25`.
- [ ] 4.7 Register the new suite in `test-all.sh`. **Do NOT add it to `REQUIRED_RUNNERS`** (category error — that array holds runners).
- [ ] 4.8 Reconcile the third authority: `run-registered-suites.sh:179-205 report_orphans` uses the naive basename grep this plan rejects. Add `--list` and have surface 3 delegate to it; cross-check exclusion lists with `.github/scripts/test/test-infra-suite-registration.sh`.
- [ ] 4.9 Refresh stale registration comments in `test-all.sh` at `:917`, `:957`, `:1004`, `:1014`, `:1033`.

## Phase B2 — close the orphans to zero

- [ ] 5.1 **Before adding the glob**, enumerate what `plugins/soleur/skills/*/scripts/*.test.sh` newly sweeps in beyond the four linear-fetch suites. Triage any slow/credentialed/non-CI-safe member in this PR.
- [ ] 5.2 Add the glob to `test-all.sh:1205` (covers the 4 linear-fetch suites).
- [ ] 5.3 Register `scripts/board/set-board-status.test.sh` explicitly (`scripts/board/` is covered by no glob; #7402's "run by board-status-sync.yml" claim is refuted — that workflow runs `set-board-status.sh`).
- [ ] 5.4 Register `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` explicitly.
- [ ] 5.5 Run the four turned-on linear-fetch suites; **fix or exclude** what they surface. `scripts/lint-shell-capture-exit.baseline.txt:145-148` already flags 4 S1 findings in `persist-safe-integration.test.sh` — a never-run suite may not be green.
- [ ] 5.6 Confirm surface 6 keeps `workspaces-luks-loopback.test.sh` **covered** (not orphaned, not excluded), and that removing surface 6 reddens (AC25).

## Phase B3 — subsume #7523

- [ ] 6.1 Confirm the whole-repo walk reaches `scripts/followthroughs/*.test.sh` by construction; all 7 are currently registered, so zero new orphans surface.
- [ ] 6.2 Note in the PR that #7523's floor-adjustment checkbox is discharged by 4.5. Use `Closes #7523`.

## Phase C — verification

- [ ] 7.1 Work every AC (AC1-AC28). Record the Guard 1/2/3 mutation results as a **row-by-row table** in the PR body, not in aggregate.
- [ ] 7.2 Prefer touched shards: `TEST_GROUP=scripts` (A2/B), `TEST_GROUP=infra` (A1). Long gates under `setsid nohup`, read the **rc file**, never pipe through `tail`.
- [ ] 7.3 Read the contention preamble / `LOCK_`/`BANNER` lines before diagnosing any red.
- [ ] 7.4 Any probe that kills processes MUST scope `pgrep`/`pkill` to its own `setsid` session id — a global `pkill -f 'node.*vitest'` would kill a concurrent session's suite.
- [ ] 7.5 Re-verify the ADR ordinal across all `origin/*` refs immediately before merge; on renumber sweep plan + tasks + every AC naming it in one edit.
- [ ] 7.6 PR body: `Closes #7429`, `Closes #7402`, `Closes #7523`.
