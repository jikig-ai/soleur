# Interface Contract — feat-one-shot-9307-generic-affected-gate

Plan: `knowledge-base/project/plans/2026-10-15-feat-plugin-generic-affected-test-gate-plan.md` (authoritative for all semantics; this file only partitions file scope and pins the observable interface).

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/lib/affected-tests/common.sh`, `plugins/soleur/scripts/lib/affected-tests/js.sh`, `plugins/soleur/scripts/lib/affected-tests/python.sh`, `plugins/soleur/scripts/lib/affected-tests/go.sh`, `plugins/soleur/scripts/lib/affected-tests/nx-turbo.sh`, `plugins/soleur/scripts/grok-pre-push-gate.sh` (dispatch call only), `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/skills/test-fix-loop/SKILL.md`, `plugins/soleur/skills/ship/scripts/battery-owed.sh` (conditional, verify-only), `scripts/lib/test-affected-paths.sh` (conditional, only if census requires) |
| Agent 2 (Tests) | `plugins/soleur/scripts/affected-tests.test.sh`, `plugins/soleur/test/fullsuite-merge-gate.test.ts` (pin update) |

Neither agent writes `plugins/soleur/skills/ship/references/affected-gate-contract.md`, the ADR, or `plugin.json`/`CHANGELOG.md`/root `README.md` — the coordinator writes docs and Ship owns version triad files.

## Public Interfaces

### `affected-tests.sh` (the gate; every interface below is the contract Agent 2 tests)

Invocation: `bash plugins/soleur/scripts/affected-tests.sh [--full] [--base <ref>] [--explain] [--self-check]`

- `--full` — bypass selection; run the detected full command (delegated `test-all.sh --full` in the Soleur repo).
- `--base <ref>` — override base-ref resolution for the changed set.
- `--explain` — print the selection and per-path reasons without running anything; exit 0.
- `--self-check` — validate config load + toolchain probe only; print `AFFECTED_GATE_SELF_CHECK ok`; completes in < 15 s; never runs tests.

### Dispatch precedence (exactly this order)

1. `test_command` key in `.soleur-test-gate.json` (repo root) — full-run command via `bash -c` from repo root; bypasses selection entirely.
2. Repo runner capability probe — `scripts/test-all.sh` exists AND its `--print-selection` flag is registered at a case-label or usage-table position (NOT a comment or prose mention); delegates `--affected` (or `--full` under `--full`).
3. Stack adapters, detected in order: nx/turbo (`nx.json`/`turbo.json`), JS/TS (`vitest related <files> --run`; jest `--findRelatedTests <files>`; honor `scripts.test` for the full command), Python (`pyproject.toml`/`pytest.ini`; test-file diffs run those files, source diffs → `pytest-testmon` if importable else full suite; `-n auto` iff `pytest-xdist` importable else serial), Go (`go.mod`; changed packages + reverse-dependency closure via `go list`; `go test -p <width>`).

A foreign `scripts/test-all.sh` (no `--print-selection` registration) is NEVER invoked with Soleur flags — falls through to adapters.

### Exit contract — one `finish()` exit site; the ONLY place exit codes are produced

- `0` — every selected test passed, OR `NO_TESTS_AFFECTED` printed for an all-inert diff.
- `1` — a selected test failed or the runner was signal-killed; a failure seen before budget expiry wins over deferral.
- `4` — `AFFECTED_GATE_REFUSED reason=<no-stack|bad-config key=<k>|vacuous-test-command|no-base-ref|toolchain-missing|runner-refused|foreign-runner>`; tests exist but no runner/command resolves, bad config, no base ref after one bounded deepen, missing toolchain, or a delegated runner refused.
- `6` — `AFFECTED_GATE_BUDGET_DEFERRED` (budget expired AND a CI test workflow was detected).
- `7` — no test suite detected at all (disclosed note; never labelled passed).

Multi-stack aggregation: worst-of with precedence `1 > 4 > 6 > 0`; `7` only when every adapter finds no suite. Delegated runner codes map in: its `4` → `4 reason=runner-refused`, its `3` → `1 reason=runner-signal`.

### Output contract

- Human sentence: `Ran X of N test files affected by this change: passed.` (never the words "tests verified"; always "affected-suite gate passed").
- Machine line: `AFFECTED_GATE ran=<X> of=<N> skipped=<Y> mode=<selected|full|custom> reason=<…> stack=<…> ci=<file|none>` — emitted on every run path including refusals (with the refusal reason).
- Inert verdict: `NO_TESTS_AFFECTED` + `No tests ran: docs-only change.` + `inert_rule=<which>` reported.
- Budget deferral: `AFFECTED_GATE_BUDGET_DEFERRED ran=<X> of=<N>` line + rc 6.
- Self-check: `AFFECTED_GATE_SELF_CHECK ok`.

### `.soleur-test-gate.json` schema (committed repo-root override; every key optional, unknown key = rc 4)

| Key | Type | Semantics |
|-----|------|-----------|
| `test_command` | string | Full-run command; vacuous values (`true`, `:`, `exit 0`, bare `echo`) → rc 4 `reason=vacuous-test-command` |
| `global_paths` | string[] | Replaces built-ins; any hit forces the full command |
| `inert_paths` | string[] | Replaces built-ins (`**/*.md` default); all-inert diff → rc 0 `NO_TESTS_AFFECTED`; a mixed diff is never inert |
| `budget_seconds` | number | Wall-clock cap; enforced ONLY when CI detected; default 900 (unmeasured) |
| `max_workers` | number | Overrides width formula |
| `budget_ci` | boolean | Forces CI-deferral eligibility |

Built-in `global_paths`: lockfiles, `package.json`, `pyproject.toml`, `go.mod`, `tsconfig*`, `vitest.config.*`, `jest.config.*`, `conftest.py`, `.github/workflows/**`.

### Changed-set + base-ref resolution

`--base <ref>` > `@{upstream}` > `origin/HEAD` > `origin/main` then `origin/master` > `git merge-base`. Changed set = committed-vs-base ∪ staged ∪ unstaged ∪ untracked. Shallow clone → ONE bounded deepen/fetch, then rc 4 `reason=no-base-ref` (never a silent full, never a silent empty).

### Environment detection helpers (in `common.sh`, sourced by `affected-tests.sh`)

- `affected_ncpu` → `getconf _NPROCESSORS_ONLN` → `sysctl -n hw.ncpu` → `nproc`; prints integer ≥ 1.
- `affected_running_gates` → count of running `affected-tests.sh` processes anchored on argv slot (NEVER `pgrep -f` or `ps|grep` self-match spellings).
- `affected_timeout` → `timeout` → `gtimeout` → bounded-watchdog fallback (no bare `timeout` dependency).
- `affected_emit` / `finish` helpers: marker + human line emission and the single exit site.

### Worker width

`max(1, ncpu/2)` divided by `1 + running affected-tests.sh processes`; `max_workers` overrides; caps vitest/jest `--maxWorkers`, pytest `-n`, go `-p`, nx/turbo `--parallel`.

### CI detection

`.github/workflows/*.yml` with a `pull_request` or `push` trigger containing a test command, or `budget_ci: true`; the matched file is printed as `ci=<file>`.

### Portability contract (asserted by the suite)

No bare `timeout`, `nproc`, `sed -i`, `date -d`, `readlink -f`, `stat -c`; no `pgrep -f`/`ps|grep` spellings; every external binary listed in the script header; `CLAUDE_PLUGIN_ROOT` unset → identity-resolver plugin-root resolution (ADR-179 pattern).
