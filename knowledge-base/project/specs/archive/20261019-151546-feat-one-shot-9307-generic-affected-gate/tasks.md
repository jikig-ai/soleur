# Tasks — feat: plugin-shipped stack-detecting affected test gate (PR 2 of #9307)

Plan: `knowledge-base/project/plans/2026-10-15-feat-plugin-generic-affected-test-gate-plan.md`
Branch: `feat-one-shot-9307-generic-affected-gate` · Issue: #9307 (deliverable 2)

Every phase is test-first: write the failing test or fixture, see it red, then implement.

## Phase 1 — Script core: dispatch, config, diff, exit contract

- [ ] 1.1 Write `plugins/soleur/scripts/affected-tests.test.sh` scaffold: synthesized fixture repos (`cq-test-fixtures-synthesized-only`), PATH-shimmed fake runners that validate argv VALUES and log invocations, `gitFixtureEnv`-style constructed env for any `git` spawn.
- [ ] 1.2 RED: assert `affected-tests.sh` missing → run fails; write `plugins/soleur/scripts/affected-tests.sh` skeleton with `set -euo pipefail`, header listing every external binary it invokes, and the single `finish()` exit site.
- [ ] 1.3 `.soleur-test-gate.json` load + fail-closed validation (malformed / unknown key / wrong type → rc 4 `reason=bad-config key=<k>`; vacuous `test_command` → rc 4 `reason=vacuous-test-command`). Guard 3 rows red→green.
- [ ] 1.4 Base-ref resolution (`--base` > `@{upstream}` > `origin/HEAD` > `origin/main`|`origin/master` > `git merge-base`) and the changed-set union (committed ∪ staged ∪ unstaged ∪ untracked); shallow clone → one bounded deepen → rc 4 `reason=no-base-ref`.
- [ ] 1.5 `global_paths` / `inert_paths` classifiers (built-ins per plan Phase 1; mixed diff never inert; `inert_rule=` reported; all-inert → rc 0 `NO_TESTS_AFFECTED`).
- [ ] 1.6 Capability probe on `scripts/test-all.sh` (`--print-selection` registration token, not free text) + dispatch precedence `test_command` > runner > adapters. Guard 2 rows red→green.
- [ ] 1.7 Marker + human line (`AFFECTED_GATE ran=X of=N skipped=Y mode=… reason=… stack=… ci=…`), `--explain`, `--self-check` (`AFFECTED_GATE_SELF_CHECK ok` < 15 s), `--full` passthrough. Guard 1 dispatch rows red→green.

## Phase 2 — Adapters

- [ ] 2.1 `plugins/soleur/scripts/lib/affected-tests/common.sh`: ncpu detection (`getconf _NPROCESSORS_ONLN` → `sysctl -n hw.ncpu` → `nproc`), sibling-process count anchored on argv slot (no `pgrep -f`/`ps|grep`), `timeout`→`gtimeout`→watchdog wrapper, emit helpers.
- [ ] 2.2 `js.sh`: detect `package.json` (+ `bunfig.toml`, workspace roots); `vitest related <files> --run` (subcommand, verified vitest 4.1.11 — NOT `--related`); jest `--findRelatedTests <files>`; honor `scripts.test` for the full command; `passWithNoTests` / "no tests found" → non-vacuous check, not pass.
- [ ] 2.3 `python.sh`: detect `pyproject.toml`/`pytest.ini`; test-file diffs run those files; source diffs → `pytest-testmon` when importable else full suite with `-n auto` when `pytest-xdist` imports else serial + reason; rc 5 → non-vacuous check.
- [ ] 2.4 `go.sh`: detect `go.mod`; changed packages + reverse-dependency closure via `go list`; `go test -p <width>`.
- [ ] 2.5 `nx-turbo.sh`: detect `nx.json`/`turbo.json`; `nx affected` / `turbo run test --filter=...[<base>]`.
- [ ] 2.6 Verify each adapter's real exit codes and empty-result output in the target environment before mapping; record version notes per adapter. Guard 1 per-adapter rows red→green.

## Phase 3 — Budget, CI detection, worker width, cloud

- [ ] 3.1 CI detection: `.github/workflows/*.yml` with `pull_request`/`push` trigger + a test command, or `budget_ci: true`; print the matched file.
- [ ] 3.2 Budget enforcement (default `budget_seconds` 900, labelled unmeasured): expiry → `AFFECTED_GATE_BUDGET_DEFERRED` rc 6; pre-expiry failure → rc 1; no CI → ignored with the upfront line.
- [ ] 3.3 Worker width `max(1, ncpu/2) / (1 + running gate processes)`; `max_workers` override; maps to `--maxWorkers`/`-n`/`-p`/`--parallel`.
- [ ] 3.4 Cloud: `CLAUDE_PLUGIN_ROOT` unset → identity-based plugin-root resolver (ADR-179, same pattern as `soleur:go` fences); toolchain check → rc 4 `reason=toolchain-missing`.

## Phase 4 — Wire call sites (pointer-only, net-negative byte edits)

- [ ] 4.1 Create `plugins/soleur/skills/ship/references/affected-gate-contract.md`: rc table + per-skill action per code, config schema, one worked example per stack.
- [ ] 4.2 `plugins/soleur/skills/ship/SKILL.md`: Phase 4 — `--full` arm → `affected-tests.sh --full`; OWED arm → `affected-tests.sh`; keep `battery-owed.sh` + 42-only-skip; replace runner-specific prose with pointer (≤183 B net).
- [ ] 4.3 `plugins/soleur/skills/work/SKILL.md`: Phase 2 exit dispatch → gate call; pointer (≤10 B net — replace prose, do not append).
- [ ] 4.4 `plugins/soleur/skills/review/SKILL.md`: lead gate names the entry point; one clause noting no-`test-all.sh` repos use the plugin gate for seat scope (≤8 B net).
- [ ] 4.5 `plugins/soleur/skills/test-fix-loop/SKILL.md`: name the entry point for repos without a runner.
- [ ] 4.6 `plugins/soleur/scripts/grok-pre-push-gate.sh`: resolve gate via `dirname "$0"` sibling path; call instead of `bash scripts/test-all.sh --affected`.
- [ ] 4.7 `plugins/soleur/test/fullsuite-merge-gate.test.ts`: update the pin — no bare/mode-less `test-all.sh` invocation survives AND the prescribed dispatch is `affected-tests.sh`; keep the delegation property asserted via the suite.
- [ ] 4.8 Verify `plugins/soleur/skills/ship/scripts/battery-owed.sh` probes do not assume `scripts/test-all.sh` exists; add one suite row for the no-local-runner verdict if needed (42/0/2 contract unchanged).
- [ ] 4.9 Green checks: `python3 scripts/lint-skill-body-budget.py --base origin/main`; `bun test plugins/soleur/test/components.test.ts` (no `description:` change); harness-parity tests; `bash scripts/lint-orphan-test-suites.sh` (new suite classified via name-stem edge — no manual `AFFECTED_*_PATHS` for the glob suite).

## Phase 5 — ADR + build-versus-buy verdict

- [ ] 5.1 Time-boxed read of the community `toolchain` plugin (melodic-software, MIT); written verdict: adopt-with-attribution or reject-with-reasons.
- [ ] 5.2 Author `ADR-<next>` via `soleur:architecture` (provisional ordinal; re-probe every `origin/*` ref + fresh `origin/main` immediately before merge; on renumber sweep `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-9307-generic-affected-gate/` + this plan): ADR-242 cross-repo extension; ADR-183 scoping for no-runner repos; parallelism model per repo kind; exit contract + runner-code mapping; cloud behavior; toolchain verdict. Status `adopting`.
- [ ] 5.3 Re-confirm C4: all three `.c4` files checked; `bash plugins/soleur/test/c4-count-parity.test.sh` green; add elements in this PR if any actor/system/edge is unmodeled.

## Ship conditions

- [ ] PR body: "affected-suite gate" wording, `Ref #9307`, `runner-changed` caveat if it fired, required `test` context green.
- [ ] #8231 comment records deliverable-3 disposition (precondition fails: #7376 open, #7454 deferral stands, 2026-10-09 comment).
- [ ] Adjacent-issue notes: #8621, #10333 informed of the dispositions recorded in the plan.
