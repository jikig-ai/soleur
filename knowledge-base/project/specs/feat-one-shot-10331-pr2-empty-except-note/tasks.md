# Tasks: guarded class-name-only exception notes in shipped plugin scripts (PR2 of #10331)

Plan: `knowledge-base/project/plans/2026-10-15-chore-code-quality-empty-except-note-pr2-plan.md`
Branch `feat-one-shot-10331-pr2-empty-except-note`, draft PR #10375. PR body carries `Ref #10331` and no closing keyword.
Rulings: `knowledge-base/project/specs/feat-one-shot-10331-pr2-empty-except-note/decision-challenges.md`.

## Phase 0 - Precondition and baseline

- 0.1 Re-run the pinned ruff derivation (`uvx ruff==0.17.0 check --isolated --no-cache --select S110,S112,BLE001 --config 'lint.flake8-bandit.check-typed-exception = true'` over `plugins/soleur/**/*.py` excluding `test/`); the S110/S112 set must equal the plan's site table
- 0.2 Run the suites that execute the five scripts on the unchanged tree; keep green baselines and captured outputs
  - 0.2.1 `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`, `playwright-mcp-lifetime.test.sh`, `redact-a11y-snapshot.test.sh`
  - 0.2.2 `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`
  - 0.2.3 `plugins/soleur/test/preflight-founder-check.test.ts`
  - 0.2.4 `plugins/soleur/test/resolve-debt.test.sh`
  - 0.2.5 `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`
- 0.3 Run a clean real proxy session (EOF teardown); any noted site that fires moves to the silent column
- 0.4 Confirm `scripts/test-all.sh --affected` selects the resolve-debt and scan-ancestor suites from a script-only diff
- 0.5 Decide whether `fake-playwright-mcp.py` needs an extension (only if no existing switch reaches the child-needs-SIGKILL or non-JSON-candidate sessions)

## Phase 1 - Tests first (RED)

Four suites (proxy, founder-check, resolve-debt, scan-ancestor); per-suite copies carry identical assertion text; redact-engine's suite is not edited.

- 1.1 Unit cases via `importlib.util.spec_from_file_location` (founder-check TS suite spawns `python3 -I`)
  - 1.1.1 Line reads `<prefix>: swallowed <ClassName> at <site>`; canary in the exception message absent from stderr; user-defined `OSError` subclass prints its own name
  - 1.1.2 No raise when `sys.stderr.write` raises `OSError` and when `sys.stderr` is a closed file (one case)
- 1.2 AST census: every `_note(` call (and every proxy `pending.append((exc, label))` in a handler) has a string-literal label; at least one call found; `_note(exc, site="x")` and `_note(str(exc), "a")` fail
- 1.3 Per-site behaviour where a trigger exists
  - 1.3.1 scan-ancestor `flush-stdout` via the stdout-on-`/dev/full` case: note present, `UNRESOLVED:` line and rc 3 unchanged
  - 1.3.2 founder-check `out-file-write` via an `--out` directory plus the internal-error trigger: rc 4 and stdout verdict byte-identical to a literal captured on the unchanged script, one extra stderr line
- 1.4 Proxy real-subprocess cases
  - 1.4.1 Clean EOF session emits no `swallowed` marker (characterization)
  - 1.4.2 Child needing the SIGKILL step: fixed marker set per fixture, canary in client input absent, `child exited rc=...` and `survived SIGTERM` rows unchanged
  - 1.4.3 Non-JSON candidate lines with a canary: no marker, result still redacted (characterization)
  - 1.4.4 `sys.stderr.write` raising `RuntimeError` inside `teardown`: the group kill still happens
- 1.5 resolve-debt gains a case labelled `T-note: swallowed note carries the class name only` (its `PASS: T-note` line is the discoverability signal)
- 1.6 New bash assertions satisfy `scripts/lint-shell-capture-exit.py`; confirm the RED cases are RED

## Phase 2 - Implement

- 2.1 Add `_note(exc, site)` (guard `(OSError, ValueError)`; proxy adds `RuntimeError` and routes through the unmodified `log()`) to proxy, founder-check, resolve-debt, scan-ancestor
- 2.2 Call it from the nine paths in the plan's table (proxy 5 via a deferred list emitted after the kill ladder and before `child exited`, founder-check 2, resolve-debt 1, scan-ancestor 1)
- 2.3 Add greppable justification comments to the seven silent handlers (proxy `escaped_tree_in`, `wait_group_empty`, `teardown` stdin-wait and SIGTERM; scan-ancestor `reconfigure`; redact-engine two decode probes citing ADR-095); keep `pass`/`continue`, no `noqa`
- 2.4 Do not touch fail-closed arms, the proxy `log()` line, or founder-check's imports

## Phase 3 - Verify

- 3.1 Phase 1 cases GREEN; pre-existing assertions unchanged; diff captured outputs of the merged-stream suites against Phase 0 baselines
- 3.2 Re-run the ruff derivation; remainder equals the table; build the PR-body table mapping the 20 audit `py/empty-except` alerts to a PR2 site, a PR3a baseline entry, or out of scope
- 3.3 Run `scripts/test-all.sh --affected`, the `lint-shell-capture-exit` baseline check, and `scan-ancestor-signal-helpers.py --list` over the edited suites
- 3.4 Guard 1 spot-check on scratch copies (informal, not a gate): proxy via `make-proxy-mutant.py` with a unique anchor, others via a patched `SCRIPT` copy
- 3.5 Re-run the discoverability command `bash plugins/soleur/test/resolve-debt.test.sh` (expects `PASS: T-note`); after the PR's Code Quality scan runs, read its result for the five files

## Phase 4 - Issues, PR body, umbrella

- 4.1 File the CodeQL confirmation tracking issue (labels `type/chore`, `priority/p3-low`; milestone `Post-MVP / Later`; `Re-eval by: 2026-11-14`) with the query-source finding and the decision rule
- 4.2 File the `str(e)` fail-closed-arms follow-up (labels `type/security`, `deferred-scope-out`, `priority/p2-medium`; milestone `Post-MVP / Later`; re-eval date), redact-engine first, plus the closed-stderr unguarded writes and the founder-check `clear-output` stale-file residue
- 4.3 PR body: `Ref #10331`, silent-handler pointer to the Phase 3 output, the `operator (scope)` row, "guard catches `OSError` and `ValueError` (proxy also `RuntimeError`)", precondition and failure action, both issue links; after `ship` rewrites it, grep for closing keywords and require none
- 4.4 Comment the updated umbrella checklist on #10331 (PR1 done, PR2 linked, PR3a, PR3b, PR4 unchecked)
