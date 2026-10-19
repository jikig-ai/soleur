# Tasks: audit silent and catch-all exception handlers in shipped plugin scripts (slice 1 of #10331)

Plan: `knowledge-base/project/plans/2026-10-18-chore-plugin-script-except-audit-plan.md`
Branch `feat-one-shot-10331-except-audit`, draft PR #10503. PR body carries `Ref #10331` and no closing keyword.
Rulings: `knowledge-base/project/specs/feat-one-shot-10331-except-audit/decision-challenges.md`.

## Phase 0 - Baseline (no edits)

- 0.1 `python3 scripts/lint-ratchet.py ruff --check` green; `--list` shows the 18 S110/S112 entries under `plugins/soleur/` (first run installs the pinned ruff; offline -> SKIP, CI is the backstop)
- 0.2 Run the seven suites on the unchanged tree and keep them green: proxy, `playwright-mcp-lifetime`, `redact-a11y-snapshot` (agent-browser), `redact-sentinel` (incident), `preflight-founder-check.test.ts`, `resolve-debt.test.sh`, `scan-ancestor-signal-helpers.test.sh`
- 0.3 List every proxy mutant row; confirm none names an edited handler line
- 0.4 Import pins: add `contextlib` to the proxy suite's `NFR1/NFR3` `allowed` set; founder-check Guard 4 already permits it; the other suites have no pin

## Phase 1 - Cases first (characterization GREEN on the unchanged tree)

- 1.1 Proxy suite, via `mk_variant` (not `beside()`): redactor raising `SystemExit` / `KeyboardInterrupt` at import; `redact_text` and `looks_like_a11y_tree` raising each; assert rc 2 and the exact reason line. Bump `EXPECTED_MUTANTS`, `EXPECTED_RED_ROWS`, `MIN_ASSERTIONS` only if rows are added as mutants
- 1.2 Scan-ancestor suite: section-F style subprocess, `mod.run` raising `KeyboardInterrupt`, `mod.main()`; assert rc 3 and `UNRESOLVED: uncaught KeyboardInterrupt`; bump `PLANNED_TOTAL`
- 1.3 `redact-sentinel.test.sh`: `_b64_decode` of a non-base64 string returns `None`
- 1.4 Confirm the PR2 non-JSON-candidate canary and clean-session no-marker cases reach the new sentinel branch

## Phase 2 - Implement (one script at a time, suite after each)

- 2.1 resolve-debt (A1); founder-check (A2); scan-ancestor (A3, A4, C4)
- 2.2 redact-engine (A9, B2, B3)
- 2.3 proxy (A5-A8, B1, C1-C3, `_NOT_JSON`, `import contextlib`); drop the dead `# noqa: BLE001`; keep mutant-05 text and the `log()` line untouched; no stderr write moves ahead of `os.killpg`
- 2.4 Fixtures (D1-D6; D3 wraps write AND flush; narrow D5 to the call's exceptions); D1 checked by `py_compile` + ruff census
- 2.5 Check-10 manifest / suite-integrity floors only where case counts changed

## Phase 3 - Verify and shrink

- 3.1 `ruff --list`: no S110/S112 left under `plugins/soleur/`; nothing new
- 3.2 `python3 scripts/lint-ratchet.py ruff --update` then `--check`: 44 entries, 52 lines (S110 7, S112 6); surviving SIM115/F841 entries byte-identical
- 3.3 All seven suites green; every proxy mutant row lands and is killed on an assertion failure
- 3.4 `scripts/test-all.sh --affected`, `tests/scripts/test_lint_ratchet.py`, `lint-shell-capture-exit` baseline check green; `scripts/lint-ratchet.py`, `ruff.toml`, eslint baseline untouched
- 3.5 Guard 1 rows 1-5 RED on scratch copies (never in place), evidence pasted for the PR body
- 3.6 Discoverability command prints `3`
- 3.7 Before merge: rebase on `origin/main`; on a baseline conflict take main's copy and re-run `--update`; re-verify counts

## Phase 4 - Issues and PR body

- 4.1 File the slice-2 deferral issue (ruff-cache recovery hint; eslint per-extension test in CI) with labels, milestone `Post-MVP / Later`, re-eval date
- 4.2 Comment on #10433 with the new counts (62 -> 44)
- 4.3 PR body: `Ref #10331`, decision-challenges table, census before/after, Guard 1 evidence, deferral link, CodeQL-not-confirmed line (#10381), umbrella checklist state; grep for closing keywords after `ship` rewrites it
