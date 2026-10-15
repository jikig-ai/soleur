# Affected-gate contract

Canonical contract for `plugins/soleur/scripts/affected-tests.sh` — the single
affected-suite gate entry point for Soleur-guided repos. Prescribed dispatch
(wired from `ship` Phase 4, `work` Phase 2 exit, `review`, `test-fix-loop`,
`grok-pre-push-gate.sh`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/affected-tests.sh"          # affected selection
bash "${CLAUDE_PLUGIN_ROOT}/scripts/affected-tests.sh" --full   # full battery
```

## Dispatch precedence

1. `test_command` in `.soleur-test-gate.json` — full-run command, bypasses selection.
2. A repo runner advertising the capability — `scripts/test-all.sh` whose
   `--print-selection` flag is registered at a case-label/usage-table position
   (a comment or prose mention does not count) — delegated `--affected` / `--full`.
3. Stack adapters, in order: nx/turbo → JS/TS (vitest `related`, jest
   `--findRelatedTests`) → Python (test-file diffs run those files; source diffs
   via `pytest-testmon` when importable, else full suite; `-n auto` iff
   `pytest-xdist` imports) → Go (changed packages + `go list` reverse-deps).

## Exit contract

| rc | Meaning | Skill action |
|----|---------|--------------|
| 0 | Selected tests passed, or `NO_TESTS_AFFECTED` (all-inert diff) | proceed |
| 1 | A selected test failed / runner signal-killed | stop; report failures |
| 4 | `AFFECTED_GATE_REFUSED reason=<no-stack\|bad-config\|vacuous-test-command\|no-base-ref\|toolchain-missing\|runner-refused>` | stop; fix the named cause — never retry blindly |
| 6 | `AFFECTED_GATE_BUDGET_DEFERRED` — budget expired AND a CI test workflow exists | proceed to CI; record CI as the authoritative gate; never label the run passed |
| 7 | No test suite detected at all | proceed with the disclosed note; never label passed |

Multi-stack aggregation: worst-of `1 > 4 > 6 > 0`; `7` only when every adapter
finds no suite. Delegated-runner codes map in: runner `4` → `reason=runner-refused`,
runner `3` → rc 1 `reason=runner-signal`.

## Output

- Human line: `Ran X of N test files affected by this change: passed.`
- Machine line: `AFFECTED_GATE ran=X of=N skipped=Y mode=<selected|full|custom> reason=… stack=… ci=<file|none>`
- `NO_TESTS_AFFECTED` + `No tests ran: docs-only change.` for an all-inert diff.
- `--explain` prints the selection and per-path reasons without running.
- `--self-check` validates config + toolchain and prints `AFFECTED_GATE_SELF_CHECK ok`.
- `--base <ref>` overrides base-ref resolution.
- Wording is always "affected-suite gate passed" — never "tests verified". CI
  stays the authoritative merge gate.

## `.soleur-test-gate.json` (committed repo root; every key optional; unknown key or wrong type → rc 4 `bad-config key=<k>`)

| Key | Type | Effect |
|-----|------|--------|
| `test_command` | string | Full-run command via `bash -c` from repo root; vacuous (`true`, `:`, `exit 0`, bare `echo`) → `vacuous-test-command` |
| `global_paths` | string[] | Replaces built-ins (lockfiles, `package.json`, `pyproject.toml`, `go.mod`, `tsconfig*`, `vitest.config.*`, `jest.config.*`, `conftest.py`, `.github/workflows/**`); any hit forces the full command |
| `inert_paths` | string[] | Replaces built-ins (default `**/*.md`); all-inert diff → `NO_TESTS_AFFECTED` |
| `budget_seconds` | number | Wall-clock cap; enforced only when CI detected; default 900 |
| `max_workers` | number | Overrides `max(1, ncpu/2) / (1 + running gate processes)` |
| `budget_ci` | boolean | Forces CI-deferral eligibility |

## Worked examples

- Vitest repo, scoped diff → `vitest related <changed-src+test-files> --run --maxWorkers=<w>`;
  `AFFECTED_GATE ran=6 of=31 skipped=25 mode=selected stack=js ci=ci.yml`.
- Repo with a `scripts/test-all.sh` registering `--print-selection` → delegated
  `bash scripts/test-all.sh --affected`; `mode=selected`.
- Repo with an unrelated `scripts/test-all.sh` → adapters run; the foreign
  runner is never invoked.
- `README.md`-only diff → rc 0, `NO_TESTS_AFFECTED`.
- Pytest repo without xdist → serial run with the reason printed; a pytest
  rc-5 collection is treated as empty selection, never a pass.
- Empty native selection on a code diff → full command, `reason=empty-selection`.
