---
title: "feat: affected-only, parallel test gate for Soleur users and the Soleur repo"
date: 2026-09-30
slug: affected-parallel-test-gate
branch: feat-affected-parallel-test-gate
issue: 9307
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Make the local pre-ship test gate select only the suites a change can affect and run them in parallel, for Soleur users' own repositories as well as the Soleur repo. Delivered as three pull requests under one umbrella issue: a fix for docs-only over-selection in the Soleur runner (PR 1, this branch), a plugin-shipped stack-detecting gate that the work, ship and review skills call (PR 2, its own branch off main), and an opt-in parallel launcher for the Soleur bash runner (PR 3, tracked by #8231, behind a go/no-go measurement).

## Research Insights

**Premise Validation (Phase 0.6).** Cited: #9307 (open, umbrella), #8231 (open, `priority/p3-low`, `meta/machinery`), PR #9306 (draft). Held: the ADR-242 affected-by-default mechanism is on `origin/main` (so this is not greenfield for the Soleur repo), and the plugin ships no test gate (every skill and `grok-pre-push-gate.sh` calls the repo-local `scripts/test-all.sh`). **Corrected during planning:**

- The brainstorm read `--print-affected-set` output (per-registration class receipts from `_affected_emit_receipt`) as the diff's selection and claimed "306 selected". Real selection for a knowledge-base-only diff is the 145-entry `ALWAYS_ON_SUITES` floor plus about 5 edge suites, all via one false-positive edge: the bare `test` token from `bun test <file>` in the `_affected_derive` catch-all, substring-matched by `_diff_touches`. Brainstorm, spec, issue #9307 and the learning were corrected.
- A research agent reported the skill description budget over by 781 words. `bun test plugins/soleur/test/components.test.ts` passes, so headroom is about zero, not negative (last baseline 2389/2389, then +24 for #8880 = 2413).
- A research agent said plugin scripts do not ship unless referenced. `plugins/soleur` ships whole through the marketplace `git-subdir` entry, and `cloud-detect.sh` is already reached as `${CLAUDE_PLUGIN_ROOT}/scripts/...`.
- #8231 is blocked on less than its body says: the green-baseline precondition was met 2026-09-18 (#8270 merged), but #7376 (`run-registered-suites.sh` flaky under `xargs -P`) and the `JOBS=1` stopgap (#7432) are still open, and the per-mount bytes probe attributed nothing.
- No existing plugin script does stack detection (untruncated `git grep -l 'pyproject.toml\|go.mod'` over `plugins/soleur/scripts` and `plugins/soleur/skills/*/scripts` hits only `skill-security-scan/scripts/check-supply-chain.sh`, which is a supply-chain scanner, not a runner detector).

**ADR corpus (mechanism grep).** ADR-242 (affected-by-default; amended 2026-09-29 by #9173), ADR-183 (full suite at ship, not at implementation exit), ADR-133 (tmpfs contention; the advisory lock proceeds on timeout; the verdict was measured on one host and does not transfer), ADR-240 (shard assignment is checked-in derived data), ADR-179 (bare plugin-root anchor). The mechanism for PR 3 (process-level shard workers packed from `scripts/suite-durations.tsv`) is described in a 2026-09-29 comment on #8231. In-process `xargs -P` over the bash suite loop is the rejected alternative (#3672 brainstorm: module-level `process.env`, `_site/` rebuild races, fixed ports).

**Property List (Phase 0.6b).**

- P1. A change that cannot affect a suite does not run that suite.
- P2. Selected suites run in parallel at a width the host can bear, without cross-suite interference.
- P3. A narrowed gate never reports green on an empty, undecidable, vacuous or unknown-stack selection (fails toward coverage).
- P4. The operator can see what ran and what was skipped.
- P5. The gate works in a user repo that has no Soleur runner.
- P6. Wall-clock is bounded, and the gate defers to CI only when a CI test workflow exists.

**Cut List.**

- A custom affected-test engine -> cut; native runner selection buys P1 for users.
- Usage telemetry on test selection -> cut; buys no property and adds a privacy surface (CLO).
- In-process `xargs -P` over the bash suite loop -> cut; already rejected (#3672); process-level shard workers buy P2 instead.
- Making parallel the Soleur-runner default -> cut for now; #7376 is unresolved, so PR 3 stays opt-in.
- A new `soleur:test-gate` skill -> cut; the description budget has zero headroom, and a shipped script plus body edits buy P5.
- Path-class inertness for `knowledge-base/**/archive/**` -> cut; no edge matched on KB grounds in the measured diff.
- A second duration source -> cut; `scripts/suite-durations.tsv` (#9232 / PR #9233) is the single source.
- A budget for repos with no CI -> cut; deferring to a CI that does not exist ships an unverified change.
- The `stack` override key -> cut in plan review (detection or `test_command` covers it).
- A C4 element/edge/view change -> cut (no C4 file edit; see the Architecture section).
- A per-suite `AFFECTED_SELECTED` record inside `--print-affected-set` -> cut in plan review; a separate `--print-selection` mode replaces it.

**Value-Proposition Measurement (Phase 0.6c).** Command: an `awk` join of the 145 `ALWAYS_ON_SUITES` labels against `scripts/suite-durations.tsv` (light group) gives 141 matched suites = 2,355,008 ms of 4,501,710 ms summed suite time, so **52%** of the light-group battery is the always-on floor. A docs-only diff therefore costs about half a full battery before any edge is considered; removing the 5 false-positive edge suites is small by comparison, and the always-on floor plus serial execution dominate. #8231's Phase 0 measured a 6.22x ceiling (total / longest suite) over 435 suites. The saving from narrowing the floor is unmeasured until the PR 1 audit classifies which entries genuinely need to be always-on.

**Repo research (files and constraints).**

- Test-gate call sites: `plugins/soleur/skills/ship/SKILL.md` Phase 4 (`battery-owed.sh` exit 42/0/2, then `bash scripts/test-all.sh --affected` / `--full`), `plugins/soleur/skills/work/SKILL.md` Phase 2 exit, `plugins/soleur/skills/review/SKILL.md` (the `TEST_GROUP=affected` block), `plugins/soleur/scripts/grok-pre-push-gate.sh` (the `test-all.sh --affected` line), `plugins/soleur/skills/test-fix-loop/SKILL.md`. None has a fallback when `scripts/test-all.sh` is absent.
- Test placement: `plugins/soleur/scripts/*.test.sh` is an auto-registered suite glob (the `SUITE_GLOBS` array in `scripts/test-all.sh`); a new suite there must also be classified for the affected census (`scripts/lint-orphan-test-suites.sh`: an unclassified suite is an error; declared edges must be tracked paths; `_MIN_ALWAYS_ON_DECLARED` is a floor).
- Skills reach plugin scripts as `"${CLAUDE_PLUGIN_ROOT}/scripts/<name>"` (bare anchor, ADR-179); mirror the existing `battery-owed.sh` invocation form exactly.
- Skill-body byte ceilings (`plugins/soleur/test/skill-body-budget.json`, enforced by `scripts/lint-skill-body-budget.py --base origin/main`), measured 2026-09-30: `ship` 274000 ceiling vs 273291 bytes (709 free), `work` 362000 vs 361979 (**21 free**), `review` 477000 vs 475132 (1868 free). Edits to `work` must be net-zero or net-negative; move prose into a reference file and leave a pointer.
- No repo-level override-file precedent exists in the plugin. `.soleur/` is gitignored in this repo (`.gitignore`) and holds local state such as `decisions.jsonl`, so a committed override file cannot live there.
- Editing `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` triggers the `runner-changed` fallback (full battery) on that PR by design (ADR-242 amendment). PR 1 and PR 3 therefore run full or rely on CI; PR 2 does too if its census classification edits `scripts/lib/test-affected-paths.sh`.
- Track-1 census constraints: the orphan linter does not check that an always-on suite genuinely needs to be always-on, so shrinking that set is constrained only by the `_MIN_ALWAYS_ON_DECLARED` floor and by the new property test.
- Track 3 mechanics (verified for the enumerate path only): `python3 scripts/regenerate-shard-manifest.py --durations scripts/suite-durations.tsv --legs W --manifest <abs> --write` packs legs (W=4: 131/130/130/133 suites, 524 rows; the manifest path must be absolute), and `SCRIPTS_SHARD=k/W SOLEUR_SHARD_MANIFEST=<abs> bash scripts/test-all.sh scripts` runs one leg. Local contention: the repo-global `tc_acquire "test-all"` lock queues W workers; the sibling-run refusal excludes only the caller's pgid; `cf-tunnel-liveness-gate-mutations` asserts `git status` on live trees; `_site/` has producer/producer writers; two vitest registrations share `node_modules/.vite`; host-wide `/proc` walkers (`orphan-process-reaper*`, `test-all-capacity-signal`) exist; the infra runner already forks `-P min(nproc,6)`.
- Community registries: no candidate combines cross-stack selection, an override file, a budget that defers to CI and a skipped-test report. The `toolchain` plugin (melodic-software, MIT) gets a time-boxed read with a written verdict (PR 2, Phase 9); nothing is vendored.

**Learnings applied.** ADR-133 verdicts do not transfer between hosts (re-measure); a scope-aware selection arm that consumes the chain silently selects everything (the #9197 review finding, fixed in the #9173 amendment); `--print-affected-set` deletion/timeout hazards (#8761); read what a tool's output describes before quoting it as a measurement (this session's correction).

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| "A docs-only diff selects ~190 suites; over-selection is broad edges" | `--print-affected-set` prints classes; selection is 145 always-on + ~5 edge suites (all via the bare `test` edge) | PR 1 reframed: anchor directory edges, audit the always-on floor (52% of light-group suite time), make selection observable |
| "The plugin ships no test gate" | True: skills call repo-local `scripts/test-all.sh` with no fallback | PR 2 ships the gate and one dispatcher entry point |
| "Unblock #8231" | Green baseline met 2026-09-18; #7376 and the `JOBS=1` stopgap still open | PR 3 is an opt-in launcher behind a go/no-go measurement; default stays serial |
| "Override file lives under `.soleur/`" (research suggestion) | `.soleur/` is gitignored and holds local state | Override file is a committed repo-root `.soleur-test-gate.json` |
| "Description budget over by 781 words" (agent claim) | Budget test passes; headroom about zero | No new skill; no `description:` edits |
| "Skill edits are cheap" (implicit) | `work` has 21 bytes of ceiling headroom, `ship` 709, `review` 1868 | Body edits are pointer-only and net-zero/negative; prose goes to a reference file |
| "PR 2 mirrors `battery-owed.sh`'s exit contract" (earlier draft) | `battery-owed.sh` uses 42/0/2; the repo runner uses 4 for a sibling refusal and 3 for signal-shaped termination | PR 2 defines its own codes (0/1/4/6/7) and maps the runner's; no claim of mirroring |

## Problem Statement / Motivation

A parallel session's pre-ship gate "ran serially on a contended machine and over-selected 229 mostly unrelated suites" (over 30 minutes), so the operator stopped it and let CI decide. Two separable defects sit under that report. In the Soleur repo, the always-on ratchet floor (145 suites, 52% of light-group suite time) plus one false-positive edge dominate a docs-only diff, and execution is serial. For every other Soleur user there is no gate at all: `work`, `ship` and `review` call `scripts/test-all.sh`, which their repos do not have, so a skill run there either fails on a missing script or runs whatever the model improvises.

## Proposed Solution

Three pull requests under umbrella #9307 (PR 3 tracked by #8231). PR 1 and PR 2 are independent (PR 2 probes the Soleur runner by capability, not by anything PR 1 adds) and each is its own branch off `main`; PR 1 lands first by default.

- **PR 1 (this branch, #9306) — Soleur-runner selection fix.** Anchor directory edges as path prefixes; audit `ALWAYS_ON_SUITES` with observed-read evidence and move KB-only readers to declared subtree edges; add a diff-aware `--print-selection` mode; add the dropped-consumer property test; amend ADR-242.
- **PR 2 — plugin-shipped gate.** `plugins/soleur/scripts/affected-tests.sh` is the single entry point: it prefers a repo runner that advertises the Soleur capability, else detects the stack (JS/TS, Python, Go, nx/turbo), selects with the native tool, runs with native workers, applies a budget that defers to CI only when a CI test workflow exists, handles cloud sessions, and prints a human line plus an `AFFECTED_GATE` marker.
- **PR 3 — opt-in local shard launcher for the Soleur bash runner.** Starts with a go/no-go contention measurement; ships only an off-by-default launcher (W process-level shard workers packed from `scripts/suite-durations.tsv`, serial tail for non-shardable suites, union-equals-full check, deterministic exit aggregation).

## Technical Considerations

- **Fail toward coverage everywhere.** Empty selection on a non-inert diff, undetectable base ref and a runner that exits 0 having collected zero tests all degrade to the full command or refuse; none degrades to green. Empty selection is detected from the selected file list, never from a runner's output or exit code (vitest `--passWithNoTests`, pytest rc 5 and jest's "no tests found" all read as success or as non-zero depending on version).
- **Dispatch by capability, not filename.** The gate hands `--affected` to `scripts/test-all.sh` only when that file advertises the capability (`grep -q -e '--print-affected-set' scripts/test-all.sh`); a user's unrelated `scripts/test-all.sh` is not a Soleur runner. Precedence: explicit `test_command` in `.soleur-test-gate.json` > capability-advertising repo runner > stack adapters.
- **Override file `.soleur-test-gate.json`** (committed, repo root). Keys: `test_command`, `global_paths` (force run-all), `inert_paths` (REPLACES the built-in defaults), `budget_seconds`, `max_workers`, `budget_ci` (boolean, forces CI-deferral eligibility for CI systems the detector does not know). Validation fails closed: malformed JSON, an unknown key or a wrong type is rc 4 with `reason=bad-config key=<k>`; it never degrades to a default. `test_command` is a full-run command only (it bypasses selection), runs from the repo root through `bash -c`, and is refused with `reason=vacuous-test-command` when it is a known no-op (`true`, `:`, `exit 0`, or a bare `echo`).
- **Base ref and diff source.** Resolution order: `--base <ref>` > `@{upstream}` > `origin/HEAD` > `origin/main` then `origin/master` > `git merge-base`. The changed set is the union of committed-vs-base, staged, unstaged and untracked files, so an untracked new test counts. A shallow clone triggers one bounded deepen/fetch attempt, then refuses with `reason=no-base-ref` (never a silent full or a silent empty).
- **Budget semantics.** Enforced only when a CI test workflow is detected: a `.github/workflows/*.yml` file that triggers on `pull_request` or `push` and contains a test command, or `budget_ci: true`. The matched file is printed. On expiry the gate stops cleanly, prints `AFFECTED_GATE_BUDGET_DEFERRED`, and exits 6; a test failure seen before expiry is rc 1, never rc 6. Default `budget_seconds` is 900, labelled unmeasured (the reporting session was stopped past 30 minutes). Without CI the budget is ignored and the selected set runs to completion, with an upfront "no CI detected, running to completion" line.
- **Exit contract (PR 2), one exit site (`finish()`).** 0 = every selected test passed, or `NO_TESTS_AFFECTED` for an all-inert diff; 1 = a selected test failed or a runner was killed by a signal; 4 = refused (tests exist but no runner or command resolves, bad config, no base ref, missing toolchain, vacuous `test_command`, foreign runner refused); 6 = budget deferred to CI; 7 = no test suite detected in the repo (ship proceeds with a disclosed note and never labels it passed). Multi-stack aggregation is worst-of with precedence 1 > 4 > 6 > 0, and 7 only when every adapter reports no suite; each adapter reports its own `ran` count and the non-vacuous rule applies per adapter. The repo runner's codes map in: its 4 (sibling refusal or unresolved) -> 4 `reason=runner-refused`, its 3 (signal-shaped) -> 1 `reason=runner-signal`, others pass through; derive the table from the runner's own `EXIT CONTRACT` header at work time.
- **Adapters (all four, per the operator's direction).**
  - JS/TS: vitest `related --run <files>`, jest `--findRelatedTests <files>`; a `global_paths` hit forces the full command.
  - Python: pytest has no native selection, so the default is test-file-only diffs run those files, source diffs use `--testmon` when it imports, else the full suite with `-n auto` when `xdist` imports (else serial with a stated reason).
  - Go: changed packages plus their reverse-dependency closure (`go list` over the module), never changed packages alone.
  - nx/turbo: `nx affected` / `turbo run test --filter=...[<base>]`; parallel by default.
- **Portability (user hosts include macOS).** No bare `timeout` (use the `timeout` -> `gtimeout` -> bounded-bash-watchdog pattern already in `.claude/hooks/git-commit-secret-scan.sh`); no `nproc` (use `getconf _NPROCESSORS_ONLN`, then `sysctl -n hw.ncpu`, then `nproc`); no `sed -i`, `date -d`, `readlink -f` or `stat -c`. List every external binary the script invokes in its header and check each against BSD userland.
- **Worker width.** Default `max(1, ncpu/2)` divided by `1 + the number of other running affected-tests.sh processes` (`pgrep -f`), labelled unmeasured (ADR-133: a contention verdict does not transfer between hosts); overridable with `max_workers`. It caps the runner's own worker option (vitest/jest `--maxWorkers`, pytest `-n`, Go `-p`, nx/turbo `--parallel`).
- **Cloud (Devin) sessions, included in PR 2.** When `CLAUDE_PLUGIN_ROOT` is unset, resolve the plugin root with the identity-based resolver the `soleur:go` fences use (ADR-179); attempt the shallow deepen described above; check the toolchain (`command -v node|python3|go`) and refuse with `reason=toolchain-missing` when the detected stack's tool is absent; the gate reads a repo and runs its tests, so no secrets or production mutation are involved and no `message_user` ack applies. Record the cloud behavior in the ADR.
- **Claim wording.** Output prints one human sentence and one machine marker: "Ran X of N test files affected by this change: passed." beside `AFFECTED_GATE ran=X of=N skipped=Y mode=<selected|full|custom> reason=<...> stack=<...> ci=<file|none>`; for `NO_TESTS_AFFECTED`: "No tests ran: docs-only change." PR bodies say "affected-suite gate passed", never "tests verified" (CLO); CI stays the authoritative merge gate.
- **Runner-changed self-reference.** PR 1 (and PR 3) edit `scripts/test-all.sh` / `scripts/lib/test-affected-paths.sh`, so their own local gate runs the full battery by design and CI is authoritative; state that in each PR body.
- **NFR impacts.** Local developer tooling: no runtime, availability or data-residency change; performance is the point. The Soleur-repo baseline is the summed suite time in `scripts/suite-durations.tsv`.

## Implementation Phases

Every phase is test-first (`cq-write-failing-tests-before`): the failing test or fixture is written and seen red before the change that turns it green.

### PR 1 — Soleur-runner selection fix (this branch)

**Phase 1 — Anchor directory edges; drop the bare command word.**

- Files to edit: `scripts/test-all.sh` (the `_diff_touches` function and the `_affected_derive` catch-all case that calls `_affected_add_edge` for any token that resolves), `scripts/lib/test-affected-paths.sh` (the edge-convention header: "a trailing `/` denotes a directory prefix").
- Derive the full consumer list at plan/work time with `git grep -n '_diff_touches\|_affected_add_edge' scripts/ plugins/soleur/scripts/`; every hit is a call site to review.
- Behavior: `_affected_add_edge` normalizes a token that is a directory (`-d`) to a trailing-`/` prefix; `_diff_touches` matches a directory edge as a line-start prefix of `_diff_names` and a file edge as an exact line. `test` no longer matches `specs/feat-affected-parallel-test-gate/spec.md`; `bun test test/foo.ts` still yields the file edge `test/foo.ts`.
- Anchoring changes semantics for every existing edge, so sweep all declared edge arrays and run a before/after selection diff over a corpus of real diffs (the last 30 first-parent commits on `origin/main`, `git log --first-parent --name-only`): every suite that stops being selected must be a demonstrated false positive; record the diff in `knowledge-base/project/specs/feat-affected-parallel-test-gate/edge-anchoring-corpus.md`.
- Tests: extend `scripts/test-all-affected.test.sh` with a synthesized diff of only `knowledge-base/project/specs/feat-x-test-y/spec.md` asserting none of the five `test`-edge suites is selected, plus positive rows (`test/x-community.test.ts` selects them; `apps/web-platform/test/z.ts` selects its own suite and not the root `test/` suites).

**Phase 2 — Always-on audit with observed-read evidence, and KB subtree edges.**

- Files to edit: `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`, declared edge arrays), the `_MIN_ALWAYS_ON_DECLARED` constant in `scripts/test-all.sh` (set to the new count minus a fixed slack of 5 in the same commit, so the floor tightens with the audit instead of loosening).
- Method: for each of the 145 entries classify what it reads: the real repo tree (`git ls-files`, `find`, recursive grep), a named subtree, or only `mktemp` fixtures. For every demotion candidate, confirm with an observed read-set: run the suite once under `strace -f -e trace=openat,stat,newfstatat` (Linux operator host) and compare the observed repo paths to the proposed edges; a suite may leave `ALWAYS_ON_SUITES` only when its observed reads are fully covered by declared edges. Candidates named by research: `check-pa-22-live` and `tenant-dpa-register-guard-live` (`knowledge-base/legal/`), `lint-guard-contract-live` (`knowledge-base/project/plans/`), `lint-agents-compound-sync-live` (a KB runbook), the KB index suites (`ensure-kb-index`, `generate-kb-index-live`, `kb-caches-untracked`), and `lint-migrated-rule-ids-live`. Suites that walk the whole tree stay always-on (the census requires it).
- Deliverable: the audit table (entry, reads, observed read-set evidence, verdict) committed to `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md`, with the before/after summed always-on time from `scripts/suite-durations.tsv`. The PR body links it.
- ADR: amend ADR-242 in this PR (anchored edges, the audited floor, `--print-selection`); it is PR 1's decision record.

**Phase 3 — Make selection observable (`--print-selection`).**

- Files to edit: `scripts/test-all.sh` (a new mode flag next to `--print-affected-set`; it reuses the pre-pass that decides execution, so the print and the run cannot diverge).
- Behavior: `--print-selection` prints `AFFECTED_SELECTED<TAB>label<TAB>0|1` per registration and one `AFFECTED_SUMMARY selected=N of=M always_on=A edge=E fallback=<reason|none>`; `--print-affected-set` and its `AFFECTED_CLASS` receipt are untouched, so the census and mutation batteries keep working. Print the summary line at the start of every affected run.
- Tests: on a synthesized diff, assert the exact expected selected set (not a bound).

**Phase 4 — Dropped-consumer ratchet (Guard 2).**

- Files to create: `scripts/test-affected-kb-consumers.test.sh` (auto-registered by the `scripts/*.test.sh` glob; classify it in the affected census) — **Correction 2026-10-01 (review):** there is no such glob (repo-root `scripts/*.test.sh` is registered one `run_suite` line at a time); the orphan census reported the suite as never run, and it is now registered at the end of the scripts block with a declared edge set.
- Oracle: for every registration from `bash scripts/test-all.sh --enumerate-commands all` (derived, never a hand list), a suite that references a real repo `knowledge-base/` path, in its own file or one hop into a script it invokes (not under `$tmp`/`mktemp`/`FIXTURE`), must be `always_on` or carry a covering edge. The one-hop reach closes the "suite calls a lint that reads the tree" miss; the Phase 2 observed-read-sets are the empirical cross-check.

### PR 2 — plugin-shipped gate (own branch off main)

**Phase 5 — Script core, dispatch and contract.**

- Files to create: `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/affected-tests.test.sh` (auto-registered by the `plugins/soleur/scripts/*.test.sh` glob; synthesized fixture repos generated in the test per `cq-test-fixtures-synthesized-only`; fake runner shims on `PATH`). Confirm at work time whether classifying the new suite edits `scripts/lib/test-affected-paths.sh` (which would trigger `runner-changed` on PR 2 too).
- Implements: capability-based dispatch, base-ref resolution, the changed-set union, `global_paths` and `inert_paths`, the single `finish()` exit site, the rc table above, the human line plus marker, `--explain` (prints selection and reasons, runs nothing), `--self-check` (verifies libs load and the config validates; prints `AFFECTED_GATE_SELF_CHECK ok` in well under 15 seconds).
- Built-in `global_paths` (force the full command): lockfiles, `package.json`, `pyproject.toml`, `go.mod`, `tsconfig*`, `vitest.config.*`, `jest.config.*`, `conftest.py`, `.github/workflows/**`. Built-in `inert_paths`: `**/*.md`. A mixed diff (inert plus code) is never inert; the matched rule is reported as `inert_rule=`.

**Phase 6 — Adapters.** One file per adapter under `plugins/soleur/scripts/lib/affected-tests/` (`js.sh`, `python.sh`, `go.sh`, `nx-turbo.sh`), each detecting from `package.json` / `pyproject.toml` or `pytest.ini` / `go.mod` / `nx.json` or `turbo.json`, honoring the project's own `scripts.test` for the full command (do not assume a runner; check `bunfig.toml` and the runner's discovery globs before naming a test path), and mapping the native runner's exit codes and empty results to the contract (pytest rc 5, vitest `passWithNoTests`, jest "no tests found") after verifying each exit code in the target environment. Go computes the reverse-dependency closure with `go list`. Every adapter has its own Guard 1 rows and a fixture.

**Phase 7 — Budget, CI detection, worker width, cloud handling.** `timeout` -> `gtimeout` -> watchdog wrapper; CI detection as specified; worker-width formula; the cloud behavior (identity-based plugin-root resolution, shallow deepen, toolchain check).

**Phase 8 — Wire call sites (single entry point, pointer-only edits).**

- Files to edit: `plugins/soleur/skills/ship/SKILL.md` (Phase 4, the `else` arm after `battery-owed.sh`), `plugins/soleur/skills/work/SKILL.md` (Phase 2 exit), `plugins/soleur/skills/review/SKILL.md` (the `TEST_GROUP=affected` block), `plugins/soleur/skills/test-fix-loop/SKILL.md` (name the same entry point), `plugins/soleur/scripts/grok-pre-push-gate.sh` (resolve the script from `dirname "$0"`, not from `CLAUDE_PLUGIN_ROOT`), `plugins/soleur/skills/ship/scripts/battery-owed.sh` (a skip verdict when the repo has no local runner and CI already verified this tree; its 42/0/2 contract is unchanged; add a test row in its existing suite).
- Files to create: `plugins/soleur/skills/ship/references/affected-gate-contract.md` (rc table with the action each skill takes for each code, config schema, one worked example per stack); `work` and `review` link it by the correct relative path from their own directory (`../ship/references/affected-gate-contract.md`), and every reference is linked as `[name](./path)` not bare backticks.
- Each skill calls one command, `"${CLAUDE_PLUGIN_ROOT}/scripts/affected-tests.sh"`, in the same fenced form `battery-owed.sh` uses; the dispatcher owns the repo-runner-versus-adapter choice, so the skills carry no branching.
- Byte budget: edits are net-neutral or net-negative against the ceilings (`ship` 709 free, `work` 21 free, `review` 1868 free); replace existing prose with a pointer and verify with `python3 scripts/lint-skill-body-budget.py --base origin/main`. No `description:` line changes, so the description budget is untouched (re-run `bun test plugins/soleur/test/components.test.ts`). Re-run the harness-parity census (`plugins/soleur/scripts/harness-parity-census.ts` and its tests) after the edits.

**Phase 9 — ADR-262 and the build-versus-buy verdict.** Read the community `toolchain` plugin's source (time-boxed) and record a written verdict, including its MIT license terms, in ADR-262: adopt with attribution, or reject with reasons. Author ADR-262 (ordinal provisional; re-verify against every `origin/*` ref and freshly-fetched `origin/main` immediately before merge) via `soleur:architecture`.

### PR 3 — opt-in local shard launcher

**Phase 10 — Go/no-go measurement first.** Measure in the ADR-133 style: W=1 vs W=4 inside one `taskset` scope on the operator host, sampling `bytes_tmp`/`bytes_tmpdir`, over enough repeats to bound the flake rate (the #8231 plan estimates about 59 runs for a 5% bound). **No-go** if the wall-clock cut is under 30% or #7376's flaky suites go red under W; then record the evidence on #8231 and end PR 3 as a documented decision with no launcher.

**Phase 11 — Launcher (only on go).** Files to create: `scripts/test-all-parallel.sh` and `scripts/test-all-parallel.test.sh`. It packs the manifest (absolute path) with `regenerate-shard-manifest.py --legs W`, starts W workers with `SCRIPTS_SHARD=k/W`, a per-worker `TEST_TIMING_LOG` and log, runs the non-shardable family (`cf-tunnel-liveness-gate-mutations`, `_site` writers, reapers, capacity suites) as a serial tail, pins the infra runner to `JOBS=1`, asserts union-of-workers equals the serial registered population, and aggregates exit codes deterministically. It does not touch `tc_acquire` or the sibling-refusal ordering, takes the single `test-all` lock itself, and stays off by default. ADR-262 states which parallelism model a repo gets: native runner workers for users' repos, process-level shard workers only for the Soleur bash runner.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Posture-only prose in `work`/`ship` | No testable contract; model-discretion drift; leaves users without any gate |
| A full custom affected-test engine | Large, per-stack, premature; native selectors already exist |
| `xargs -P` over the bash suite loop | Rejected in #3672 (env-at-load, `_site/` races, fixed ports) |
| New `soleur:test-gate` skill | Description budget at zero headroom; a script plus body edits buy the same property |
| Parallel as the Soleur-runner default | Blocked by open #7376 and the `JOBS=1` stopgap |
| Override file under `.soleur/` | Gitignored; holds local state |
| Dispatch on `[[ -f scripts/test-all.sh ]]` | A user's own script of that name would be handed `--affected`; capability probe instead |
| Trim to JS/TS + Python adapters | Recommended by five review seats; the operator kept all four adapters, so Go's false-narrow risk is met with a reverse-dependency closure and its own Guard 1 rows |

## User-Brand Impact

**If this lands broken, the user experiences:** a Soleur-guided ship in their own repo that reports the affected-suite gate green while a broken change ships (false-narrow selection or a vacuous zero-test pass), or a gate that refuses or hangs on a stack it cannot detect and blocks their ship.

**If this leaks, the user's workflow is exposed via:** the override file or gate output naming private test paths in a PR body or log; no credential, data or network surface is touched, and the script reads only the user's repo and runs their own test command.

**Brand-survival threshold:** `single-user incident`

CPO sign-off: the brainstorm carried CPO, CLO and CTO assessments (Domain Review below); `requires_cpo_signoff: true` is set. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed (carried forward from the 2026-09-30 brainstorm, and again at plan review)
**Assessment:** Ship a stack-detecting script with a testable contract rather than skill prose; parallelism from the native runner; refuse a vacuous zero-selection; a `global_paths` override; the ADR-242 extension warrants an ADR. Plan-review additions applied: `--explain`, config validation, a time-boxed `toolchain` verdict, committed audit table, PR 2 independent of PR 1.

### Product (CPO)

**Status:** reviewed (carried forward, and again at plan review)
**Assessment:** New product surface for plugin users. CI-as-authoritative only when a CI test workflow is detected (now requires a `pull_request`/`push` trigger). Plain-sentence output next to machine markers. Success metrics replaced with measurable ones. Deferral of PR 3 was suggested and declined by the operator (it is behind a go/no-go gate).

### Legal (CLO)

**Status:** reviewed (carried forward)
**Assessment:** No legal implications. Honest labeling ("affected-suite gate passed", not "tests verified"); invoking user-installed tools is fine, bundling them needs a license check; no telemetry.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (no user-facing UI surface: script, skill bodies and runner internals only)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Observability

Scope: PR 2 (the plugin script executes on a customer's self-hosted CLI, layer 7 per `hr-observability-layer-citation`); PR 1 and PR 3 touch only repo-root `scripts/`.

```yaml
liveness_signal:
  what: "AFFECTED_GATE stdout marker line, plus a human sentence, printed on every gate run (ran/of/skipped/mode/reason/stack/ci)"
  cadence: "per gate run"
  alert_target: "the operator or agent reading the run output; ship reads the exit code"
  configured_in: plugins/soleur/scripts/affected-tests.sh
error_reporting:
  destination: "stdout/stderr markers and the exit code; no remote sink (user repos, no telemetry by decision)"
  fail_loud: "non-zero exit with AFFECTED_GATE_REFUSED reason=<...> (rc 4) or a failed-test exit (rc 1); never exit 0 on zero tests without the inert-diff verdict"
failure_modes:
  - mode: "stack undetected while tests exist, or no test command"
    detection: "AFFECTED_GATE_REFUSED reason=no-stack, rc 4, asserted by affected-tests.test.sh"
    alert_route: "the calling skill surfaces the marker and stops the ship step"
  - mode: "empty selection on a non-inert diff"
    detection: "AFFECTED_GATE mode=full reason=empty-selection (fell back), asserted by the test suite"
    alert_route: "marker in run output"
  - mode: "budget expired with CI detected"
    detection: "AFFECTED_GATE_BUDGET_DEFERRED ran=X of=N, rc 6"
    alert_route: "ship records CI as the authoritative gate and does not merge until CI is green"
logs:
  where: "the calling session's terminal"
  retention: "session lifetime"
discoverability_test:
  command: bash plugins/soleur/scripts/affected-tests.sh --self-check
  expected_output: AFFECTED_GATE_SELF_CHECK ok
```

## Guard Contract

### Guard 1 — affected-gate never reports a vacuous green (plugin script, PR 2)

**Property.** `affected-tests.sh` exits 0 only if at least one selected test ran and passed in every adapter that ran, or the whole diff is inert and it printed `NO_TESTS_AFFECTED`.

**Assembly.** Every exit-0 path: each adapter (JS/TS, Python, Go, nx/turbo), the empty-selection fallback, the inert-diff verdict, the budget-deferral path, the runner-delegation path and the `test_command` path. All flow through one `finish()` function that owns the exit code and the `AFFECTED_GATE` line; a second exit site is the defect. The inert classifier and the per-adapter non-vacuous check must quantify over every changed path and every adapter, not the first.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make an adapter return an empty selection for a code diff and skip the fallback | RED (exit 0 with zero tests run) |
| 2 | Remove the runner from `PATH` (the guard's own dispatch finds nothing) | RED if it exits 0; must be rc 4 `AFFECTED_GATE_REFUSED` |
| 3 | Diff of one inert file then one code file: make the inert check stop at the first path | RED (mixed diff treated as inert) |
| 4 | Make CI detection return true with no workflow present, so the budget defers | RED (deferral without CI) |
| 5 | A runner shim that exits 0 having collected zero tests (pytest rc 5 mapped to success, or `passWithNoTests`) | RED |
| 6 | Multi-stack repo where one adapter selects zero tests and another passes; aggregate with a single global count | RED (per-adapter non-vacuous rule) |
| 7 | `test_command: "true"` in the override file | RED (must refuse `vacuous-test-command`) |
| 8 | A test fails at 10 s and the budget expires at 20 s; report rc 6 | RED (failure wins: rc 1) |
| 9 | Go leaf package changed; make the closure return only the changed package | RED (dependents must be selected) |
| 10 | Harness row: edit the fake runner shim to print success without recording its invocation | RED (the suite asserts the invocation log is non-empty) |
| 11 | Harness must-PASS row that is not the canonical: a pnpm-workspace fixture with the vitest config in a subdirectory and a non-default base branch | PASS |

**Anchor.** No stored value is compared, so no anchor applies; the contract is behavioral.

### Guard 2 — dropped-consumer ratchet for KB readers (PR 1)

**Property.** Every registered suite that reads a real repo `knowledge-base/` path (directly or one hop through a script it invokes) is `always_on` or carries an edge that covers that path.

**Assembly.** The population is derived from `bash scripts/test-all.sh --enumerate-commands all` joined to each suite's file and its one-hop invoked scripts, never a hand-listed set; the chokepoint is the declared-edge and always-on arrays in `scripts/lib/test-affected-paths.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the KB edge from a declared suite that reads `knowledge-base/project/rejected/` | RED |
| 2 | Make the enumeration return zero registrations (the guard's own dispatch) | RED (floor on population size) |
| 3 | Add a second real-KB reader after a compliant first, with no edge | RED |
| 4 | A suite that reads the KB only through a lint script it invokes, with no edge | RED (one-hop reach) |
| 5 | Harness row: edit the oracle so it also flags `$tmp/knowledge-base` fixture mentions | RED (a must-PASS fixture-only suite starts failing) |
| 6 | Harness must-PASS row that is not the canonical: a suite that builds `mktemp` KB fixtures and has no KB edge | PASS |

**Anchor.** Set identity, not a count: the population is derived, not stored, so a substitution that keeps N cannot pass; the size floor guards only against a vacuous dispatch.

### Guard 3 — anchored directory edges (PR 1)

**Property.** A diff path that merely contains a bare word (for example `test`) never selects a suite whose edge is a directory unless the path starts with that directory.

**Assembly.** `_diff_touches` and `_affected_add_edge` in `scripts/test-all.sh`, the only place edge matching happens; every declared edge array flows through them.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `_diff_touches` to the substring match | RED (`specs/feat-x-test-y/spec.md` selects the `test` suites) |
| 2 | Make the guard's dispatch skip all edges (the pre-pass selects nothing) | RED (the positive row `test/x-community.test.ts` selects nothing) |
| 3 | Add a second path after a compliant first (`knowledge-base/a.md` then `test/y.test.ts`) and stop matching after the first | RED |
| 4 | Harness row: delete the positive assertion from the suite | RED (a separate test asserts the suite still contains the positive row) |
| 5 | Harness must-PASS row that is not the canonical: `apps/web-platform/test/z.ts` must select its own suite and must not select the root `test/` suites | PASS |

**Anchor.** Not applicable; no stored value is compared.

### Guard 4 — union-equals-full and non-masking aggregation (PR 3)

**Property.** The launcher's worker population equals the serial registered population, and the launcher's exit code is non-zero if any worker fails or dies by signal.

**Assembly.** The manifest packer output, the W worker invocations, the serial tail, and the exit aggregation in `scripts/test-all-parallel.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop one leg's suites from the manifest | RED (union check) |
| 2 | Empty manifest (the guard's own dispatch) | RED |
| 3 | A second worker fails after the first passes; aggregate only the first | RED |
| 4 | Harness row: replace a worker with a stub that exits 0 without running suites | RED (population check) |
| 5 | Harness must-PASS row that is not the canonical: W=1 must equal the serial run | PASS |

**Anchor.** The serial `--enumerate` population is the anchor outside the launcher's own output.

### Guard 5 — runner capability probe (PR 2)

**Property.** The gate hands `--affected` only to a `scripts/test-all.sh` that advertises the capability; a foreign script of that name is never invoked with Soleur flags.

**Assembly.** The single dispatch function in `affected-tests.sh` that chooses between `test_command`, the repo runner and the adapters; every call site (`ship`, `work`, `review`, `test-fix-loop`, `grok-pre-push-gate.sh`) reaches it, because each calls the one entry point.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the probe to `[[ -f scripts/test-all.sh ]]` with a foreign script that prints `ok` and exits 0 | RED (foreign script must not be delegated to) |
| 2 | Make the probe always fail (the guard's own dispatch) | RED (a Soleur-runner fixture must still be delegated to) |
| 3 | Fixture with a capability-advertising runner and an explicit `test_command`: let the runner win | RED (`test_command` takes precedence) |
| 4 | Harness row: replace the fixture's foreign script with one that advertises the capability text only in a comment | RED (the probe must match the flag registration, not free text) |
| 5 | Harness must-PASS row that is not the canonical: a runner advertising the capability through a renamed but equivalent flag table | PASS |

**Anchor.** No stored value is compared; the probe reads the repo's own runner, so the anchor is the runner's flag table, checked in the fixture.

## Architecture Decision (ADR/C4)

### ADR

- PR 1 amends ADR-242 (anchored directory edges, the audited always-on floor, `--print-selection`); this is PR 1's decision record and lands in PR 1, not later.
- PR 2 creates ADR-262 (provisional ordinal) "The plugin ships a stack-agnostic affected-test gate; the repo-local runner is the override" via `soleur:architecture`. It must state that it scopes ADR-183 (full suite at ship) for repos with no Soleur runner, which parallelism model each kind of repo gets (native workers for user repos, process-level shard workers only for the Soleur bash runner, ADR-133 not transferring between hosts), the exit-code contract and its mapping to the runner's codes, the cloud behavior, and the `toolchain` build-versus-buy verdict.

### C4 views

Read all three files (`model.c4`, `views.c4`, `spec.c4`). Checked and already modeled: the external actor (`founder` runs Soleur sessions), the external systems (the user's test runners are the user's own toolchain on the same machine, not a system edge), the container (`platform.plugin` already states it ships shared bash primitives to a user's machine, ADR-178, so a shipped gate script is the same kind of thing), and the actor-to-surface relationships (`founder -> platform.plugin`, `devin -> platform.plugin`, `codex -> platform.plugin`) are unchanged. **No C4 file edit**: no element, edge, view include or derived count (skills 103, agents 67) changes, and the plan review cut the one description edit as not worth three C4 checks. Confirm with `c4-count-parity.test.sh` green at work time and cite that run.

### Sequencing

ADR-262 is authored in PR 2 describing the target state with `status: adopting` until PR 2 merges; PR 3's launcher is recorded in it as opt-in.

## Open Code-Review Overlap

- #8659 (`scripts/test-all.sh`: 33 suites replace test-helpers' composed EXIT trap): **Acknowledge.** Different concern (trap composition), needs its own cycle; PR 1 does not touch trap code.
- #7942 (two `*.mutation.sh` batteries run in no gate): **Acknowledge, and apply the lesson.** The mutation matrices above live inside `*.test.sh` suites that a gate runs; the issue stays open.
- #8800 (census sandbox shares inodes with the live repo): **Acknowledge.** The new property test only reads and must not write through the census sandbox; a constraint on Phase 4.

## Acceptance Criteria

### Pre-merge (PR 1)

- [ ] `bash scripts/test-all-affected.test.sh` has a failing-first row for a KB-only diff whose path contains "test" (none of the five `test`-edge suites selected) and positive rows for `test/x-community.test.ts` and `apps/web-platform/test/z.ts`; all pass after Phase 1.
- [ ] The edge-anchoring corpus record exists and every suite that stopped being selected is justified as a false positive.
- [ ] `bash scripts/test-all.sh --print-selection` on a synthesized KB-only diff prints exactly the expected selected set (exact, not a bound) and an `AFFECTED_SUMMARY` line; `--print-affected-set` output is unchanged (compare a fresh run against the merge-base's output for the same registration set).
- [ ] The always-on audit table, with observed read-set evidence per demoted entry, is committed at `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md`, with before/after summed always-on time from `scripts/suite-durations.tsv`; every entry moved out of `ALWAYS_ON_SUITES` is covered by the ratchet.
- [ ] `_MIN_ALWAYS_ON_DECLARED` equals the new always-on count minus 5; `bash scripts/lint-orphan-test-suites.sh` is green (run with its own invocation, not a restated path list).
- [ ] `scripts/test-affected-kb-consumers.test.sh` exists, derives its population from `--enumerate-commands all`, and every Guard 2 and Guard 3 mutation row reddens.
- [ ] ADR-242 is amended in this PR.
- [ ] PR body says "affected-suite gate", contains `Ref #9307` (not `Closes`), states that the local gate ran full by `runner-changed`, and CI's required `test` context is green.

### Pre-merge (PR 2)

- [ ] `plugins/soleur/scripts/affected-tests.sh` implements the exit contract (0/1/4/6/7) with one exit site; `affected-tests.test.sh` exercises all Guard 1 and Guard 5 rows and each adapter fixture, and every mutation row reddens.
- [ ] The dispatcher probes capability, not filename; a foreign `scripts/test-all.sh` fixture is not delegated to.
- [ ] Every external binary the script invokes is listed in its header and checked against BSD userland (no bare `timeout`, `nproc`, `sed -i`, `date -d`, `readlink -f`, `stat -c`).
- [ ] `ship`, `work`, `review`, `test-fix-loop` and `grok-pre-push-gate.sh` call the single entry point; `python3 scripts/lint-skill-body-budget.py --base origin/main` is OK; `bun test plugins/soleur/test/components.test.ts` passes with no `description:` line changed; the harness-parity census passes.
- [ ] `bash plugins/soleur/scripts/affected-tests.sh --self-check` prints `AFFECTED_GATE_SELF_CHECK ok` in under 15 seconds.
- [ ] `battery-owed.sh` keeps its 42/0/2 contract and its suite has a row for the no-local-runner skip verdict.
- [ ] ADR-262 exists with the `toolchain` verdict; `bash plugins/soleur/test/c4-count-parity.test.sh` is green with no C4 file edited.
- [ ] The reference is linked from each skill by a working relative path (`git ls-files` resolves it).

### Pre-merge (PR 3)

- [ ] The Phase 10 measurement record exists; if no-go, PR 3 is a documented decision with no launcher.
- [ ] If go: the launcher is off by default, Guard 4 rows redden, the union check equals the serial `--enumerate` population, and a signal-killed worker makes the launcher non-zero.

### Post-merge

- [ ] #9307 stays open until PR 2 merges; #8231 gets a comment recording PR 3's outcome (go with evidence, or no-go with evidence).

## Test Scenarios

- Given a KB-only diff whose path contains "test", when the affected gate runs, then no root-`test/` suite is selected.
- Given a diff of `test/x-community.test.ts`, when it runs, then the `test/x-community` suite is selected.
- Given a user repo with vitest and no `scripts/test-all.sh`, when `ship` reaches Phase 4, then the plugin script runs the related tests and prints `AFFECTED_GATE ran=X of=N skipped=Y`.
- Given a user repo with an unrelated `scripts/test-all.sh`, when the gate runs, then it does not delegate to it.
- Given a repo with test files but no detectable runner and no `test_command`, then rc 4 `reason=no-stack`; given a repo with no test files at all, then rc 7 and ship proceeds with a disclosed note, never labelled passed.
- Given a code diff where the native selector returns nothing, when the gate runs, then it falls back to the full command with `reason=empty-selection`.
- Given a diff of only `README.md`, then rc 0 with `NO_TESTS_AFFECTED`; given `README.md` plus `src/a.ts`, then it is not inert.
- Given CI is detected and the budget expires with no failure, then rc 6; given a test failed before expiry, then rc 1; given no CI, then the budget is ignored.
- Given a pytest repo without pytest-xdist, then it runs serially and prints the reason; given a pytest run that collects zero tests (rc 5), then it is not a pass.
- Given a shallow clone with no base ref after the bounded deepen attempt, then rc 4 `reason=no-base-ref`.
- Given a malformed `.soleur-test-gate.json` or an unknown key, then rc 4 `reason=bad-config`, never a silent default.
- Regression: a narrowed gate passing while a consumer breaks is covered by Guard 1 rows 1, 5, 6 and 9 and Guard 2 rows 1 and 4.

## Success Metrics

- Soleur repo: selected suites for a knowledge-base-only diff, before 150 (145 always-on + 5 edge), after the audited floor plus true consumers; the before/after summed always-on time comes from `scripts/suite-durations.tsv`.
- Alpha tester repo: the `ran X of N` lines from gate runs, collected at the tester's check-in (there is no telemetry by decision).
- Guardrail: any diff the local gate passed but CI's full battery failed is recorded as an escape; no baseline exists for non-Soleur repos, so the first datapoint is collected, not assumed.

## Dependencies & Risks

- **False-narrow gate (highest).** Mitigated by fail-toward-coverage, Guard 1, per-adapter non-vacuous checks, the Go reverse-dependency closure and the "affected-suite gate" wording.
- **Always-on shrink drops a true consumer.** Mitigated by Guard 2 (derived population, one-hop reach, set identity), the observed read-set evidence and the committed audit table.
- **All four adapters kept over review advice.** The operator chose the wider set; the cost is a larger Guard 1 matrix and a per-stack maintenance surface, and native selector flags drift, so each adapter carries its own fixture and version note.
- **#7376 unresolved.** PR 3 is opt-in and gated by measurement.
- **ADR ordinal collision.** ADR-262 is provisional; re-check against fresh `origin/main` and every `origin/*` ref before merge.
- **Skill-body byte ceilings nearly exhausted** (`work` 21 bytes free): pointer-only, net-neutral edits.
- **`runner-changed` full fallback** on PR 1 and PR 3 (and PR 2 if it edits the census index): state it in each PR body.
- **Cloud sessions.** Included in PR 2: identity-based root resolution, shallow deepen, toolchain check; a hosted cloud workspace that clones a user repo is served by the same script.

## Plan Review Outcome

Panel: DHH, Kieran, code-simplicity (per-mechanism), architecture-strategist and spec-flow-analyzer (single-user-incident escalation), plus CTO (devex lens) and CPO (product lens); a strong-model advisor consult ran on a curated payload (ADR-083). Mechanical findings were applied (capability-based dispatch and one dispatcher entry point, exit-code contract and aggregation precedence, empty-selection and vacuous-runner handling, `test_command` denylist, base-ref order and untracked files, portability, content anchors instead of line numbers, test-first ordering, floor-with-slack, correct reference-link paths, Guard 3 row fix). Operator decisions (2026-09-30): keep all four adapters; refuse only when tests exist, else rc 7; include cloud handling; apply all taste-class changes and keep PR 3. Taste changes applied: `--print-selection`, drop the `stack` key and the C4 edit, `**/*.md` inert default with config replacing defaults, human line beside the marker, `--explain`, observed-read-set audit evidence, the `toolchain` verdict, the committed audit table, PR 2 independent of PR 1. Not applied: splitting the audit into its own PR (kept as commits within PR 1); a soft always-on time ratchet; a `WOULD_SKIP` shadow receipt.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The `test_command` escape hatch is the natural repair for a stuck rc 4, so it is refused when vacuous (`true`, `:`, `exit 0`, bare `echo`); a repair that passes the check points at the hole.
- A list nothing consults is inert while reading as coverage: the always-on and edge arrays are consulted only by the pre-pass in `scripts/test-all.sh` (`_diff_touches` at the selection decision); any entry added or moved must be checked against that consumer, and the Phase 3 `--print-selection` output is the proof.
- `--print-affected-set` prints classes, not the diff's selection; do not quote its line count as a selection (this plan's own first draft did).
- Skill-body ceilings: `work` has 21 bytes free. Measure `ceiling - wc -c` before writing prose there, and prefer replacing text with a pointer.
- A new fixture that spawns `git` must use the constructed environment helpers (`gitFixtureEnv`), and a fake runner must replay the real tool's multi-line output and exit codes, not the consumer's reading of them.
- Do not build an env-assignment prefix from a conditional expansion in the script (`${X+VAR="$X"} cmd` is a command word); assign and assert the refusal's reason.
- ADR ordinals are provisional until merge: probe across every `origin/*` ref and re-run immediately before merge.
- Verify every exit code and empty-result behavior of vitest, jest, pytest, `go test`, nx and turbo in the target environment before mapping it; do not assume a runner (read `package.json` `scripts.test`).
