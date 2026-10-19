---
title: "chore(quality): draw down the ruff and eslint-test-dir baselines"
date: 2026-10-19
slug: lint-baseline-drawdown
branch: feat-one-shot-10433-lint-baseline-drawdown
issue: 10433
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: single-domain
closes: 10433
---

## Enhancement Summary

**Deepened on:** 2026-10-19
**Sections enhanced:** Research Insights (verified remedy shapes), Observability (probe corrected), Disposition Table (Group B), Technical Rulings (F3 wording).
**Method:** proportionate to a 64-finding mechanical cleanup. The skill's blanket fan-out of every agent was not run: the change is behaviour-preserving deletions and handle/handler rewrites, the technical forks are already CTO-ruled, and plan review already ran a four-seat panel. Deepen instead ran the mechanical halts and the empirical checks below.

### Key Improvements

1. **A bare `ExitStack` does not satisfy SIM115 (measured).** `stack = contextlib.ExitStack(); err = stack.enter_context(open(...))` is still flagged by the pinned ruff; only `with open(...) as f:` or `with ExitStack() as stack:` pass. The plan's earlier plan-review revision (R8) had kept `ExitStack` for the `Popen` stderr handle in `proxy-session-driver.py`; that row now uses `with open(err_path, "wb") as err:` over the rest of `main()`, read with `git diff -w`. This would otherwise have cost a failed `ruff --update` at work time.
2. **Observability probe made matchable.** `expected_output: entries 0` is a whitespace-bearing single token, which Phase 4.7 rejects as prose; the probe now prints `entries=` plus the count and the expected literal is `entries=0` (the probe-verb gate returns rc 0 and the command finishes in 0.03 s; it prints `entries=64` today and must print `entries=0` after Phase 5).
3. **Sentinel shape, `with open` + `enumerate(fh, 1)` and `suppress`-with-`break` verified clean under the pinned ruff** in a scratch file (the only finding in the scratch run was the bare-`ExitStack` case above).

### New Considerations Discovered

- Phase 4.6 (user-brand impact), 4.7 (observability), 4.8 (PAT-shaped variables), 4.12 (scope check) all pass on the revised plan: the threshold line is `none` with the sensitive-path scope-out bullet, the `## Scope Check` appears once unfenced with a `Recommendation:` line, and no PAT-shaped token or cited rule id appears. Phases 4.9 to 4.11 do not fire (no UI file, no persistent store or `.tf`, no guard is delivered). Phase 4.4 (precedent-diff): `contextlib.suppress` is the codebase's own idiom (`proxy-session-driver.py` already uses it twice).
- Every cited `knowledge-base/` path resolves; no `#N` is cited without a live check (#10331, #10433 open; #10583 created in this session).
- Rewritten `try:` blocks were read in place (`lint-rule-ids.py` L148/L375, `tests/conftest.py`, the hook's outer `try`): the dependent code sits inside the guarded block or, for the three sentinel sites, is covered by the sentinel shape.

## Overview

Slice 3 of the code-quality arc (tracker #10331). The shrink-only lint ratchet (ADR-290) holds 44 ruff
entries and 20 eslint test-directory entries as known findings. This plan chooses which groups of those
findings to fix in this PR, fixes them without changing behaviour, and shrinks both baseline files.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10433 is OPEN (its body says 62 ruff entries; the live baseline holds 44 after slice 1, ADR-290 Amendment 1 records the correction); #10331 is OPEN; ADR-290 is `active` and its Decision does not reject a drawdown. Both `--check` runs are green in this worktree (`ruff: OK (44 findings baselined, 68 files scanned)`, `eslint-test-dirs: OK (20 findings baselined, 124 files scanned)`). Every cited file exists on this branch. Total live debt: 44 + 20 = 64 findings across 33 files (20 Python files, 13 eslint files). The engine supports an empty baseline (`tests/scripts/test_lint_ratchet.py::test_zero_finding_clean_run_passes_with_an_empty_baseline`). Nothing stale.

**Property List (Phase 0.6b).**

1. P1: Both baseline files end with fewer entries than they hold now, and never more (shrink-only).
2. P2: No fix changes the behaviour of the code it touches, and no test that guarded something is weakened.
3. P3: The `ruff.toml`, the eslint config and the engine's pin tests are not loosened to reach P1.

**Cut List.** No mechanism is proposed by the ask beyond "fix findings, run `--update`", so there is nothing to cut. Considered and cut as unneeded: a `ruff --fix` autofix pass (rewrites fixtures its own suites assert on, learning `2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`; also `--update` already refuses to grow); a new tracking script (`lint-ratchet.py --list` already prints the live findings).

**Value-proposition measurement (Phase 0.6c).** Not applicable: the justification is a debt reduction, not a cost saving.

**Live findings by area** (`python3 plugins/soleur/scripts/lint-ratchet.py {ruff,eslint-test-dirs} --list`):

- Python, repo tooling (group A, 25 entries): `.claude/hooks/security_reminder_hook.py` S110 x2; `scripts/backfill-frontmatter.py` F401 + F841 x2; `scripts/ci-pr-affected-replay.py` SIM115 x3; `scripts/lint-agents-enforcement-tags.py`, `lint-anthropic-content-position.py`, `lint-trap-tempfile-ownership.py` S112 x1 each; `scripts/lint-rule-ids.py` S110 x2; `scripts/lint-shell-capture-exit.py` SIM115; `scripts/lint-workflow-local-action-checkout.py` S110 + S112 x2; `scripts/regenerate-shard-manifest.py` SIM115 x4; `tests/conftest.py` S110 x2 + S112; `tests/scripts/test_lint_rule_ids.py` F401.
- Python, fixtures and mutation harness (group B, 16 entries): `apps/web-platform/infra/doppler-download-error-channel.mutation.py` SIM115 x2; `plugins/soleur/skills/agent-browser/test/fixtures/` `fake-playwright-mcp.py` x4, `make-proxy-mutant.py` x2, `proxy-session-driver.py` x4, `session-facts.py` x3; `plugins/soleur/test/fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py` x1.
- Python, shipped plugin scripts (group C, 3 entries): `plugins/soleur/skills/preflight/scripts/founder-check.py` F841 x2 (dead `word_start` flag at the shell-quoting predicate; dead `status` in `_tasks_plan`); `plugins/soleur/skills/skill-creator/scripts/quick_validate.py` F401 (`import os`).
- ESLint, test dirs (group D, 20 entries, 13 files): see the disposition table in the plan body.

**Verified remedy shapes** (pinned ruff 0.16.10 from the engine's own cache, scratch file, `ruff check --config ruff.toml`): `with contextlib.suppress(X):` (including a `break` inside it), `with contextlib.ExitStack() as stack: stack.enter_context(open(...))`, and `Path(p).read_text()` all pass the five selected rules. Measured in deepen-plan: a bare `stack = contextlib.ExitStack(); stack.enter_context(open(...))` (stack not entered with `with`) is STILL flagged SIM115, so the only compliant shapes for a long-lived handle are `with open(...) as f:` (re-indent) or `with ExitStack() as stack:` (also a re-indent); the sentinel shape (`except OSError: text = None` then `if text is None: continue`) and `enumerate(fh, 1)` under `with open` pass. `except X: pass` and `except X: continue` do not, even for typed handlers (`check-typed-exception = true`).

**Institutional learnings applied.**

- `2026-10-09-a-rollback-recipe-nobody-had-run-and-a-baselined-file-touched-without-its-changed-lint.md`: a baselined file touched in a PR owes its whole debt; `--changed`-mode lints run only in CI, so run the per-file suite and the sibling lint of each edited file locally.
- `2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md` and `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`: hand-edit fixtures and harnesses; never run an autofix over them; prove the mutation batteries still kill.
- `2026-10-12-resume-after-plugin-load-failure-merge-conflict-on-shared-baseline-literal.md`: on a baseline merge conflict recompute with the tool (`--update`), never pick a side.
- `2026-10-19-a-newest-wins-reference-picked-my-own-unpushed-work-and-a-filtered-test-run-hid-an-import-error.md`: capture a test run's exit code; a `grep`-filtered run hid an IndentationError.
- `2026-10-07-a-helper-that-runs-nothing-still-has-to-parse-like-the-shell-that-will.md` and `2026-10-15-a-never-raises-helper-must-survive-a-missing-stderr-and-a-locator-must-name-your-own-frame.md`: `founder-check.py` wording lives in one `WORDING` map read by exact-string tests; edit constants, not literals (this PR edits neither).
- `2026-03-18-bun-test-segfault-missing-deps.md`: `node_modules` is present in this worktree (root and `apps/web-platform`), so bun and vitest run.

**Community / functional overlap (Phases 1.5, 1.5b).** No uncovered stack. The functional-discovery agent found no overlapping registry artifact (one unrelated generic `code-cleanup` plugin, discarded).

**Open code-review overlap (Phase 1.7.5).** Recorded in the plan body.

## Open Code-Review Overlap

Two open `code-review` issues name files this plan edits. Both are acknowledged, neither is folded in:

- #3531 (`[flake] marketing-content-drift.test.ts beforeAll docs:build exceeds 5s hook timeout`) - **Acknowledge.** The plan deletes one dead local (`buildAttempted`) in the same file; the timeout flake is a different concern with its own cycle. The issue stays open.
- #8920 (`review: #8900 lint-shell-capture-exit S3/S4 ...`) - **Acknowledge.** A review-evidence record for another PR; this plan changes one `open()` call in `scripts/lint-shell-capture-exit.py` and nothing the issue discusses.

## Technical Rulings

All forks were ruled by the CTO agent (no operator question was asked). Persisted as rows in `knowledge-base/project/specs/feat-one-shot-10433-lint-baseline-drawdown/decision-challenges.md`.

| Fork | Ruling (CTO agent, 2026-10-19) |
|---|---|
| F1 scope | One PR, all 64 findings, per-area commits in this order: ruff group A, B, C, then eslint, then baseline regeneration. Each commit shrinks its own baseline entries (see Plan Review Revisions R1). The per-area commits are a review aid only: the repo squash-merges, so they collapse on merge. Before editing `quick_validate.py`, grep for `from quick_validate import *` and `quick_validate.os`; if an importer relies on the stray `os`, hold that one file out and say so on #10433. |
| F2 S110/S112 | Behaviour must stay byte-identical, no logging added. `contextlib.suppress(<same exception tuple>)`; in loops, a guarded body or a sentinel assignment. The telemetry hook prints nothing and never blocks. `tests/conftest.py` keeps its retry loop; run the whole `tests/` suite. |
| F3 SIM115 | One-shot reads become `Path(p).read_text()` or `with open()`; long-lived handles use a re-indent under `with` (an `ExitStack` not entered with `with` is still flagged, R8), with the close timing unchanged (the `Popen` stderr handle must outlive the child). Proof for the redaction-proxy fixtures and the mutation harness: per-mutant killed/survived counts must be identical before and after. Plan refinement (Plan Review Revisions R6): run the proxy suite and the mutation battery once AFTER the edits; a before-run is taken (in a detached worktree at `origin/main`) only if the after-run shows any survivor or failure. |
| F4 dead bindings | Delete by default; underscore-prefix only positional callback params. `renamed = rename_dateless_file()` keeps the call. `checked` (harness-model-map): the ruling's condition (restore only if no existing floor covers it) resolves to DELETE, see Plan Review Revisions R7. `compared`: delete (the `seenShapes.size` floor supersedes it). `DATED_POST` `date`: remove the parameter and the four call-site arguments; if the template should have interpolated it, file an issue rather than change behaviour. A test may be strengthened only to restore a vacuity guard that a dead binding shows was dropped: tiny, passes today, named in the commit message. |
| F5 end state | Engine and its suite untouched. Both baselines regenerated to empty with `--update`. One ADR-290 amendment line. The `DRAWDOWN` constant and header cleanup is tracked in #10583. PR body says `Closes #10433` and `Ref #10331` only. |
| F6 conflicts | On a baseline merge conflict take the base branch's copy and re-run `--update`; never hand-merge. If `--update` refuses because the base added a finding, fix that finding in this PR. Re-run both `--check` commands before push and after the final rebase. |

## Plan Review Revisions

Plan review (DHH, Kieran, code-simplicity, CTO devex lens), 2026-10-19. Mechanical findings were applied above; taste calls are recorded in `decision-challenges.md`.

- R1 (Kieran P1, mechanical): lefthook `--check` requires the baseline to equal the live census on every staged `*.py` or test `.ts`, so each commit shrinks its own baseline with `--update` and stages it (Phases 1-4); Phase 5 re-derives after the final rebase.
- R2 (Kieran P2, mechanical): AC3 named the wrong eslint config; the ratchet reads `apps/web-platform/eslint.test-dirs.config.mjs`.
- R3 (Kieran, CTO, DHH, mechanical): the AC6 list is replaced by the Covering Suites table with resolved suite names (the wrong `test-infra-suite-registration.sh` and the vague `.claude/hooks/*.test.sh` are gone; the vitest arm and the `tests/` unittest entry points are added).
- R4 (Kieran, mechanical): missing imports named in the Disposition Table; counts corrected (33 files, 13 eslint files); `redirect-tombstones` is exactly four call sites; the `compared` comments are reworded.
- R5 (Kieran, CTO, mechanical): AC4 scoped to code files and to a net-addition check, so it cannot fail on the plan's own prose or on the pre-existing `# noqa: E402`.
- R6 (DHH, simplicity, taste within CTO F3): the mutation battery and proxy suite run once after the edits; the before-run is taken only if a survivor or failure appears. The battery is awaited with `Monitor`. The Phase 0 before-state sweep, the founder-check verdict-table oracle and the reintroduction probe are cut: ruff proves the flag is never read, `test_lint_ratchet.py` already pins empty-baseline and NEW-finding behaviour, and none maps to an ask.
- R7 (simplicity, mechanical under CTO F4's own condition): `checked` in `harness-model-map.test.ts` is deleted, not restored (constant non-empty arrays, no `continue`, existing fence-existence assertions); this also removes the only test-strengthening item.
- R8 (DHH, simplicity, Kieran, taste): `ci-pr-affected-replay.py` handles use `with` and a re-indent read with `git diff -w`; `proxy-session-driver.py` also uses `with open(err_path, "wb") as err:` over the rest of `main` (a bare `ExitStack` that is not entered with `with` is still flagged SIM115, measured at deepen-plan), read with `git diff -w`.
- R9 (DHH, Kieran, mechanical): the `skill-security-scan.test.ts` parse stays as a bare `JSON.parse(...)` statement so no guard is weakened (P2).
- R10 (simplicity, taste): per-area commits are a review aid only; the repo squash-merges, so no commit "reverts alone".
- Declined: trimming the `## Observability` block (plan Phase 2.9 requires it because one Files-to-Edit entry sits under `apps/*/infra/`); folding the ADR-290 amendment into #10583 (CTO F5 ruled it in this PR).

## User-Brand Impact

- **If this lands broken, the user experiences:** a customer running `soleur:preflight` sees a `founder-check.py` crash or a changed verdict, or `soleur:skill-creator` fails to validate a skill, because a "dead" local or import turned out to be live.
- **If this leaks, the user's data is exposed via:** no exposure vector: the diff deletes dead bindings and rewrites file-handle and exception-handler shapes; it adds no network call, no credential read and no new write path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** every edit in the two customer-visible shipped scripts is the deletion of a name ruff proves is never read (one flag, one tuple element, one import), covered by `preflight-founder-check.test.ts` (for `founder-check.py`) and the import smoke in AC7 (for `quick_validate.py`); the next tier would apply to a behaviour change, which this plan forbids.

threshold: none, reason: the only sensitive-path file (`apps/web-platform/infra/doppler-download-error-channel.mutation.py`) is an offline mutation harness that is not wired into CI and runs on no production path; its edit swaps two `open()` calls for `Path.read_text`/`write_text`.

## Observability

Plan Phase 2.9 fires on the letter (one Files-to-Edit entry sits under `apps/*/infra/`), but the change adds no code path that can fail at runtime: it removes lint findings. The observable property is that the two ratchet baselines are empty and stay so.

```yaml
liveness_signal:
  what: the shrink-only ratchet reruns on every PR as the required-context suites lint-ratchet-ruff-live and tests/scripts/lint-ratchet, plus the vitest arm eslint-test-dirs-ratchet.test.ts; a regression turns the required test context red
  cadence: per PR and per push to main
  alert_target: the PR check status (required context), main-health monitor on push to main
  configured_in: scripts/test-all.sh (run_suite "scripts/lint-ratchet-ruff-live"), lefthook.yml (ruff-ratchet, eslint-test-dirs-ratchet)
error_reporting:
  destination: CI check result and the ratchet's own stderr (NEW/STALE lines, capped at 25 per class)
  fail_loud: exit 1 on drift, exit 2 on infrastructure error, both fail the required context
failure_modes:
  - mode: a new finding lands in a scanned file
    detection: lint-ratchet.py --check reports NEW and exits 1
    alert_route: the PR author sees a red required check before merge
  - mode: a baseline regains an entry through a merge conflict resolved by hand
    detection: --check compares the baseline with the live census and with the merge base (growth refused)
    alert_route: red required check
logs:
  where: CI job log of the test context
  retention: GitHub Actions default log retention
discoverability_test:
  command: python3 -c "print('entries=' + str(sum(1 for f in ('scripts/lint-ratchet-ruff.baseline.txt', 'scripts/lint-ratchet-eslint-test-dirs.baseline.txt') for l in open(f) if not l.startswith('#'))))"
  expected_output: entries=0
```

## Architecture Decision (ADR/C4)

Not an architectural decision: no boundary, substrate or invariant changes. The one in-scope documentation task is a single amendment line in ADR-290 (the drawdown completed; the baselines are empty; the Consequences count of 62 ruff findings was already corrected by Amendment 1) - task 5.2 below. C4: no impact. Actors, external systems and relationships checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: this change touches no external actor, no vendor edge, no data store and no access relationship; the ratchet is an internal CI gate that no view models. The derived cardinalities embedded in `model.c4` edge prose are unchanged (no workflow or monitor is added or removed).

## Files to Edit

Baselines and docs:

- `scripts/lint-ratchet-ruff.baseline.txt` (44 -> 0 entries, via `--update`)
- `scripts/lint-ratchet-eslint-test-dirs.baseline.txt` (20 -> 0 entries, via `--update`)
- `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md` (one amendment line)

Group A, repo tooling (25 findings):

- `.claude/hooks/security_reminder_hook.py` (S110 x2)
- `scripts/backfill-frontmatter.py` (F401, F841 x2)
- `scripts/ci-pr-affected-replay.py` (SIM115 x3)
- `scripts/lint-agents-enforcement-tags.py` (S112)
- `scripts/lint-anthropic-content-position.py` (S112)
- `scripts/lint-trap-tempfile-ownership.py` (S112)
- `scripts/lint-rule-ids.py` (S110 x2)
- `scripts/lint-shell-capture-exit.py` (SIM115)
- `scripts/lint-workflow-local-action-checkout.py` (S110, S112 x2)
- `scripts/regenerate-shard-manifest.py` (SIM115 x4)
- `tests/conftest.py` (S110 x2, S112)
- `tests/scripts/test_lint_rule_ids.py` (F401)

Group B, fixtures and mutation harness (16 findings):

- `apps/web-platform/infra/doppler-download-error-channel.mutation.py` (SIM115 x2)
- `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py` (x4)
- `plugins/soleur/skills/agent-browser/test/fixtures/make-proxy-mutant.py` (x2)
- `plugins/soleur/skills/agent-browser/test/fixtures/proxy-session-driver.py` (x4)
- `plugins/soleur/skills/agent-browser/test/fixtures/session-facts.py` (x3)
- `plugins/soleur/test/fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py` (x1)

Group C, shipped plugin scripts (3 findings, own commit):

- `plugins/soleur/skills/preflight/scripts/founder-check.py` (F841 x2)
- `plugins/soleur/skills/skill-creator/scripts/quick_validate.py` (F401)

Group D, eslint test dirs (20 findings):

- `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `harness-model-map.test.ts`, `harness-parity.test.ts`, `heartbeat-live-reconcile.test.ts`, `lib/scratch-session.ts`, `marketing-content-drift.test.ts`, `model-launch-review.test.ts`, `preflight-discoverability-test.test.ts`, `redirect-tombstones.test.ts`, `skill-security-scan.test.ts`, `terraform-target-parity.test.ts`, `web-host-escrow-preflight-census.test.ts`
- `test/content-publisher.test.ts`

## Files to Create

None. (Plan artifacts only: this plan, `tasks.md`, `decision-challenges.md`.)

## Disposition Table (per site; line numbers drift, so work from `--list`)

Rule for every row: behaviour byte-identical, no new log line, no `# noqa` (the ratchet counts with `--ignore-noqa` and `--no-inline-config`, so a waiver would not shrink the baseline). Add the import each new shape needs (`contextlib` for `suppress` in `lint-rule-ids.py`, `lint-workflow-local-action-checkout.py`, `tests/conftest.py`, and the hook if absent; `pathlib.Path` where a row says so): `py_compile` does not catch a missing import, only the file's suite does.

### Group A - repo tooling

| File | Rule | Remedy |
|---|---|---|
| `.claude/hooks/security_reminder_hook.py` L103 | S110 | Replace `try:` with `with contextlib.suppress(OSError, subprocess.SubprocessError):`, drop the `except ... pass`; no re-indent. Add `import contextlib` if absent. |
| same, L134 | S110 | The outer fire-and-forget `try: ... except Exception: pass` becomes `with contextlib.suppress(Exception):` (same indentation, keep the comment). Prints nothing, never blocks. Import `contextlib` if absent. |
| `scripts/backfill-frontmatter.py` | F401 | Drop `format_field` from the `from frontmatter_lib import` line; `scripts/test_backfill_frontmatter.py` must not reach it through this module (grep first). |
| same | F841 x2 | Delete the `new_body_stripped = ...` line (its sibling `content_stripped` is live). `renamed = rename_dateless_file()` becomes a bare call: the side effect stays. |
| `scripts/ci-pr-affected-replay.py` L190 | SIM115 | `for line in open(p):` becomes `with open(p) as fh:` + `for line in fh:` (re-indent, exact line semantics). |
| same, L478 and L559 | SIM115 | Long-lived append handle `out` in `cmd_collect` and `cmd_ejections`: re-indent the rest of each function under `with open(path, "a") as out:` (an `ExitStack` that is never closed would only quiet the lint). The handle is never closed explicitly today; the new shape closes it at function exit, which is not observable because every write is flushed. Read the diff with `git diff -w`. Add nothing else: no `contextlib` import is needed. |
| `scripts/lint-agents-enforcement-tags.py` | S112 | Body is `if token.search(...): return True` with nothing after it: `with contextlib.suppress(OSError):`. |
| `scripts/lint-anthropic-content-position.py`, `scripts/lint-trap-tempfile-ownership.py` | S112 | Later code uses the bound `text`, so suppress would leave a stale value from the previous iteration. Use a sentinel: `try: text = ... except OSError: text = None`, then `if text is None: continue`. |
| `scripts/lint-rule-ids.py` x2 | S110 | `except subprocess.CalledProcessError: pass` -> `with contextlib.suppress(subprocess.CalledProcessError):` around the same block. Keep the "file not in HEAD yet" comment. |
| `scripts/lint-shell-capture-exit.py` | SIM115 | `open(path, encoding="utf-8", errors="replace").read().split("\n")` -> `Path(path).read_text(encoding="utf-8", errors="replace").split("\n")` (identical: text-mode read, same split). Add `from pathlib import Path` (the file imports no pathlib today). Keep the `except OSError: return []`. |
| `scripts/lint-workflow-local-action-checkout.py` L251 | S110 | The git-ls-files fall-through: `with contextlib.suppress(OSError, subprocess.SubprocessError):` around the block with the inner `return`. |
| same, L273 | S112 | `with contextlib.suppress(OSError):` (nothing follows the `if`). |
| same, L307 | S112 | Sentinel: `doc = None` on `(OSError, UnicodeDecodeError, RecursionError, yaml.YAMLError)`; the existing `isinstance(doc, dict)` / `isinstance(steps, list)` guards then reach the same `continue`. Verify by reading the lines that follow. |
| `scripts/regenerate-shard-manifest.py` L291 | SIM115 | `with open(workflow or CI_YML, encoding="utf-8") as fh: txt = fh.read()` (no new import needed). |
| same, L338/L372/L398 | SIM115 | `enumerate(open(path, ...), 1)` -> `with open(path, encoding="utf-8") as fh:` + `enumerate(fh, 1)`. Not `read_text().splitlines()`: `splitlines` splits on more separators than file iteration does. |
| `tests/conftest.py` L100 | S110 | `with contextlib.suppress(OSError): os.unlink(tmp)` inside the `except BaseException:` that re-raises. |
| same, L186 | S112 | Keep the 8-try loop: `with contextlib.suppress(FileExistsError): os.mkdir(candidate, 0o700); root = candidate; break`. |
| same, L221 | S110 | `with contextlib.suppress(ValueError):` around the `signal.getsignal ... signal.signal` block; keep the "not the main thread" comment. |
| `tests/scripts/test_lint_rule_ids.py` | F401 | Delete `import os` (grep shows no other `os.` use besides a comment). |

### Group B - fixtures and mutation harness (hand-edit, never autofix)

| File | Remedy |
|---|---|
| `apps/web-platform/infra/doppler-download-error-channel.mutation.py` | `s = Path(dst).read_text()` and `Path(dst).write_text(s.replace(old, new, 1))`; the harness stays byte-for-byte equivalent in what it mutates. Add `from pathlib import Path`. |
| `fake-playwright-mcp.py` | `Path(p).write_text(...)` (L33, L119); `json.loads(Path(p).read_text())` (L81, L105). Add `from pathlib import Path` if absent. Add `from pathlib import Path` if absent. |
| `make-proxy-mutant.py` | `src = Path(src_path).read_text(encoding="utf-8")`; `Path(out_path).write_text(mutated, encoding="utf-8")`. Add `from pathlib import Path`. |
| `proxy-session-driver.py` | L59 stderr handle `err`: the `Popen` child writes to it, so it must outlive the child: `with open(err_path, "wb") as err:` over the rest of `main()` (re-indent; delete the trailing `err.close()`, keep the earlier `err.flush()`), so the handle closes at the same point or earlier on an exception. L100 `Path(err_path).read_bytes()`; L130 `json.dump(objs, open(...))` -> `with open(...) as fh: json.dump(objs, fh, indent=1, ensure_ascii=False)`; L132 `Path(...).write_text(str(val) + "
")`. Add `from pathlib import Path`. Read with `git diff -w`. |
| `session-facts.py` | `Path(...).read_bytes()` / `json.loads(Path(argv[3]).read_text())`. Add `from pathlib import Path`. |
| `wiring_facts.py` | `text = Path(path).read_text(encoding="utf-8")` inside the existing `try/except OSError`. |

### Group C - shipped plugin scripts

| File | Remedy |
|---|---|
| `founder-check.py` L551-583 | `word_start` is assigned four times and never read, and no `~`/`#` branch consults it: delete the declaration and the four assignments. The predicate's verdicts are unchanged because it never read the flag. |
| `founder-check.py` L833 | `status, text = "missing", ""` -> `text = ""`. |
| `quick_validate.py` | Delete `import os`. Only `package_skill.py` imports `validate_skill` from it; no `import *`, no `quick_validate.os` (verified by grep). |

### Group D - eslint test dirs

| File | Remedy |
|---|---|
| `cloud-init-user-data-size.test.ts` | Delete dead helpers `renderedSize` and `varLengths`; if `applyTemplateVars` or an import then goes unused, delete it too (re-run `--list` until clean). |
| `web-host-escrow-preflight-census.test.ts` | Delete the dead `logicalLines` const (its sibling `joinCont` is live). |
| `model-launch-review.test.ts`, `preflight-discoverability-test.test.ts` | Drop `beforeAll` / `PROBE_VERB_ALLOWLIST` from the import lists. |
| `heartbeat-live-reconcile.test.ts`, `skill-security-scan.test.ts` | Delete the statement `const out = result.markers.join("\n")` (pure expression, no effect). In `skill-security-scan.test.ts` keep the parse as a bare statement `JSON.parse(r.stdout || "{}");`: it is the only check that the first fixture's stdout is valid JSON, and P2 forbids weakening it. |
| `marketing-content-drift.test.ts` | Delete `buildAttempted` (declaration + the one assignment). |
| `content-publisher.test.ts` x4 | Delete `const RS = "\\x1e"` (the bash side spells its own `$'\\x1e'`). |
| `harness-parity.test.ts` | `const [dir, name]` -> `const [, name]`. |
| `scratch-session.ts` | `catch (e) {` -> `catch {`. |
| `terraform-target-parity.test.ts` | L4579 `(b) =>` -> `() =>`; L7647 drop the trailing unused `r, sum` params. |
| `redirect-tombstones.test.ts` | Remove the `date` parameter of `DATED_POST` and the argument at its exactly four call sites (CTO F4). |
| `harness-model-map.test.ts` | Delete `let checked = 0`. The CTO F4 condition (restore only if no existing floor) resolves to delete: `PINNED_WORKFLOWS` and `envCases` are non-empty constant arrays, the loop has no `continue`, so an assertion on `checked` would be a tautology, and fence existence is already asserted by the `start`/`end` checks in `extractFence` and the fence-set equality test. |
| `preflight-discoverability-test.test.ts` | Delete `compared` and its `compared++`; reword the nearby comments that say "`compared` increments once per surviving row" so they no longer cite the deleted counter (the live floor is `seenShapes.size >= MIN_COMPARED`). |

## Covering Suites

Resolved at plan time from `scripts/test-all.sh` `run_suite` lines and `ls`; each is run with its exit code captured (never `grep`-filtered). Group A:

| Edited file | Covering suite(s) |
|---|---|
| `.claude/hooks/security_reminder_hook.py` | `bash .claude/hooks/security_reminder_hook.test.sh`; `bash .claude/hooks/log-rotation.test.sh` (the L103 site is the rotation call) |
| `scripts/backfill-frontmatter.py` | `python3 scripts/test_backfill_frontmatter.py` |
| `scripts/ci-pr-affected-replay.py` | `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` |
| `scripts/lint-agents-enforcement-tags.py` | `bash scripts/lint-agents-enforcement-tags.test.sh`; `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.rules.md` |
| `scripts/lint-anthropic-content-position.py` | `bash scripts/lint-anthropic-content-position.test.sh`; `python3 scripts/lint-anthropic-content-position.py` |
| `scripts/lint-trap-tempfile-ownership.py` | `bash scripts/lint-trap-tempfile-ownership.test.sh` |
| `scripts/lint-rule-ids.py` | `python3 -m unittest tests.scripts.test_lint_rule_ids`; `bash scripts/lib/rule-line-regex-parity.test.sh`; the live line in `scripts/test-all.sh` (`python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.rules.md`) |
| `scripts/lint-shell-capture-exit.py` | `bash scripts/lint-shell-capture-exit.test.sh` |
| `scripts/lint-workflow-local-action-checkout.py` | `bash scripts/lint-workflow-local-action-checkout.test.sh`; `python3 scripts/lint-workflow-local-action-checkout.py` |
| `scripts/regenerate-shard-manifest.py` | `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`; `bash plugins/soleur/test/scripts-shard-manifest.test.sh` |
| `tests/conftest.py` | `python3 -m unittest tests.scripts.test_lint_ratchet tests.scripts.test_lint_rule_ids tests.scripts.test_lint_rule_bodies tests.scripts.test_rule_id_regex_parity` (the unittest entry points that import it through `tests/scripts/_git_fixture_env.py`; `pytest` is not installed here) |
| `tests/scripts/test_lint_rule_ids.py` | the same unittest module |

Group B: `bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` (drives `fake-playwright-mcp.py`, `make-proxy-mutant.py`, `proxy-session-driver.py`, `session-facts.py`); `bash plugins/soleur/test/codeql-main-alert-gate-workflow-wiring.test.sh` (`wiring_facts.py`); `python3 apps/web-platform/infra/doppler-download-error-channel.mutation.py` for the harness itself (about 6 minutes, not wired into CI; its control stage runs first and prints `control: GREEN`). Group C: `bun test plugins/soleur/test/preflight-founder-check.test.ts`; the `quick_validate`/`package_skill` import smoke (AC7). Group D: `bun test <file>` for each touched `plugins/soleur/test/*` file; `bun test test/content-publisher.test.ts` (the `test/content-publisher` line in `scripts/test-all.sh`); `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` under vitest from `apps/web-platform` (the arm CI enforces for `eslint-test-dirs`).

## Implementation Phases

### Phase 0 - Pre-flight

1. `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `... eslint-test-dirs --check`: expect OK (44 / 20).
2. `git fetch origin main` and confirm the branch is not behind in a way that touches the baselines (a base that added a finding is fixed in this PR, F6).

### Phase 1 - Group A commit (repo tooling)

Apply the group A rows. After each file: `python3 -m py_compile <file>`, then that file's covering suite from the table above. Then `python3 plugins/soleur/scripts/lint-ratchet.py ruff --update` and stage the baseline with the code: lefthook runs `ruff-ratchet --check` on every staged `*.py`, which requires the baseline to equal the live census, so a commit that fixes findings without shrinking the baseline is refused (R1). Commit: `chore(quality): drain the repo-tooling ruff findings (Ref #10331, Ref #10433)`; the commit body carries a one-line equivalence note per file.

### Phase 2 - Group B commit (fixtures, mutation harness)

Apply the group B rows by hand (never autofix). Run the proxy suite once and the wiring suite. Run `python3 apps/web-platform/infra/doppler-download-error-channel.mutation.py` once after the edit, waiting with `Monitor` (an `until` loop on the process, not `run_in_background` polling; it takes about 6 minutes): expect `control: GREEN` and no `SURVIVED` line. If it reports any survivor or failure, take a before-run in a detached worktree at `origin/main` and compare per-mutant counts (R6). Then `ruff --update`, stage the baseline, commit.

### Phase 3 - Group C commit (shipped plugin scripts)

First `git grep -nE 'from quick_validate import \*|quick_validate\.os' -- . ':!knowledge-base'` must print nothing (F1 precondition). Apply the group C rows; run `bun test plugins/soleur/test/preflight-founder-check.test.ts`, `python3 -m py_compile` both files, and the AC7 import smoke. Then `ruff --update`, stage the baseline, commit.

### Phase 4 - Group D commit (eslint test dirs)

Apply the group D rows. Iterate `python3 plugins/soleur/scripts/lint-ratchet.py eslint-test-dirs --list` until empty (a deleted helper can orphan an import; the next `--list` reports it). Run each touched test file under its runner. Then `eslint-test-dirs --update`, stage the baseline, commit.

### Phase 5 - Final baselines, docs, ship

1. `git fetch origin main` and rebase onto `origin/main`. Only then re-run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --update` and `... eslint-test-dirs --update` so the baselines are regenerated against the final base (a base that added a finding is fixed here, not baselined). Both baselines now hold only their header comments; `--check` both: expect `OK (0 findings baselined, ...)`, and the `## Observability` probe prints `entries=0`.
2. Add one amendment line to ADR-290 (`## Amendment 2 (2026-10-19, slice 3 of #10331)`: both baselines drained by the drawdown PR, ratchet now a plain zero-findings gate; the header and `DRAWDOWN` constant cleanup is tracked in #10583).
3. Run the repo's own affected-suite selection for the final diff and run what it lists (`bash scripts/test-all.sh --affected`, the local default per its header), in addition to the Covering Suites table, so a suite nobody named is not missed.
4. `soleur:ship` (PR body: `Ref #10331`, `Closes #10433`, #10583 linked; equivalence note; mutation-battery result; no closing keyword for #10331), then `soleur:postmerge`. A BEHIND PR with auto-merge armed waits for the merge queue. #10331 stays OPEN.

## Test Scenarios

- Both ratchet `--check` runs report `0 findings baselined` and exit 0 (the empty-baseline and NEW-finding behaviours are already pinned by `tests/scripts/test_lint_ratchet.py`, which this PR does not touch).
- The founder-check change is a deletion of a never-read flag (ruff F841 proves it) and is covered by `preflight-founder-check.test.ts`; no hand-built oracle.
- Proxy suite and mutation battery: green after the edit; any survivor triggers the before/after comparison of Phase 2.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change (dead-code and file-handle cleanup in scripts, fixtures and test files; no user-facing surface, no copy, no pricing, no legal text).

## Sharp Edges

- The ratchet keys on a hash of the normalised source line: editing a baselined line changes its anchor, so the old entry goes STALE and the line, if still a finding, becomes NEW. The only valid end state is zero findings in the touched file, then `--update`.
- A deleted helper can orphan an import (eslint `no-unused-vars` reports the import next); loop `--list` until it prints nothing.
- Do not use a `# noqa` or `// eslint-disable` to "fix" a site: counting is waiver-proof, so it would not shrink the baseline and would hide the finding from review.
- `enumerate(open(path), 1)` is not equivalent to `read_text().splitlines()`: file iteration splits on `\n` only. Keep the exact iteration shape.
- When the plan says "edit `try:` into `with suppress(...)`" check whether code AFTER the block reads a name bound inside it; if so use the sentinel shape, otherwise a stale value from the previous loop iteration leaks through.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here.
- A baseline merge conflict is resolved by taking the base branch's copy and re-running `--update`, never by hand.
- `plugins/soleur/skills/work/SKILL.md` is at its byte ceiling and no SKILL.md is edited here; `plugin-root-anchoring.test.ts` is therefore not triggered.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Slice 3 = drawdown of the baselined lint findings tracked in open issue #10433" | Phases 1-4, Files to Edit | mapped |
| 2 | "Fix findings in groups by code area; every fix PR must shrink a baseline and never grow one" | Groups A-D, per-area commits | mapped |
| 3 | "Before pushing run `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` and `... eslint-test-dirs --check` ... then `--update` to shrink the baseline" | Phase 5.1, AC1-AC2 | mapped |
| 4 | "keep #10331 OPEN; PR bodies say \"Ref #10331\" and \"Ref #10433\", no closing keyword" and "the PR that empties a baseline may close #10433" | Phase 5.4 (`Ref #10331`; `Closes #10433` because this PR empties both baselines, as the brief allows and CTO F5 ruled) | mapped (the brief itself permits the close) |
| 5 | "Shipped plugin scripts (founder-check.py, quick_validate.py, the redaction proxy) are the careful ones" | Group C own commit, Group B before/after proof | mapped |
| 6 | "Decide scope for THIS PR: which group(s) of findings by code area to fix now ... the CTO agent rules the grouping and whether remaining groups get further PRs, recording a follow-up note on #10433" | Technical Rulings F1 (all groups, one PR), follow-up #10583 | mapped |
| 7 | "run soleur:ship and soleur:postmerge to completion; when a PR is BEHIND with auto-merge armed, wait for the merge queue" | Phase 5.3 | mapped |
| 8 | "run apps/web-platform/test/plugin-root-anchoring.test.ts locally if a SKILL.md snippet changes" | Sharp Edges (no SKILL.md edited) | mapped |
| 9 | "Slice 4 ... is a SEPARATE later PR ... do not do it here" | Non-goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Groups A-D, all 64 findings | "Fix findings in groups by code area" | asked |
| suppress / with / sentinel remedies | "every fix PR must shrink a baseline" | asked |
| Proxy suite + mutation battery after the edit | "Shipped plugin scripts (founder-check.py, quick_validate.py, the redaction proxy) are the careful ones" | asked |
| ADR-290 amendment line | "ADR-290 describes the shrink-only lint ratchet" | inferred - justification: CTO F5 ruling; one line records that the Consequences count of findings is now zero |
| Follow-up issue #10583 (drop the header and `DRAWDOWN` constant) | "recording a follow-up note on #10433" | asked |

### Split Assessment

- Subsystems touched: 4 - plugin scripts and fixtures (`plugins/soleur/**`), repo scripts and tests (`scripts/`, `tests/`), hooks (`.claude/hooks/`), infra harness (`apps/web-platform/infra/`) plus the `test/` dir.
- Planned files: 36 | Estimated changed lines: about 250 (mostly 1-10 line edits; two re-indented bodies shown by `git diff -w`)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the thresholds are exceeded on subsystem and file count, but the CTO ruled one PR (F1) because every edit is a behaviour-preserving cleanup verified by the existing per-file suites; per-area commits keep it reviewable (a review aid only: the repo squash-merges). Splitting would pay several ship cycles on a conflict-prone baseline file.

## Non-Goals

- Slice 4 of #10331 (Code Quality on/off decision and the expenses entry) is a separate later PR in its own worktree.
- No engine change: `plugins/soleur/scripts/lint-ratchet.py`, its tests, `ruff.toml` and the eslint config are untouched (tracked in #10583).
- No autofix (`ruff --fix`, `eslint --fix`) anywhere; no widening of the ruff or eslint rule sets.

## Acceptance Criteria

- [ ] AC1: `python3 plugins/soleur/scripts/lint-ratchet.py ruff --check` exits 0 and prints `0 findings baselined`; `scripts/lint-ratchet-ruff.baseline.txt` holds no non-comment line.
- [ ] AC2: `python3 plugins/soleur/scripts/lint-ratchet.py eslint-test-dirs --check` exits 0 and prints `0 findings baselined`; the `## Observability` probe prints `entries=0` for both baselines. The vitest arm `apps/web-platform/test/eslint-test-dirs-ratchet.test.ts` passes.
- [ ] AC3: `git diff origin/main...HEAD --stat -- ruff.toml plugins/soleur/scripts/lint-ratchet.py plugins/soleur/scripts/ruff-requirements.txt tests/scripts/test_lint_ratchet.py apps/web-platform/eslint.test-dirs.config.mjs` is empty (no config, pin or engine loosened; `eslint.test-dirs.config.mjs` is the config the ratchet reads, `ESLINT_CONFIG` in `lint-ratchet.py`).
- [ ] AC4: No waiver is added: `git diff origin/main...HEAD -U0 -- '*.py' '*.ts' '*.mjs' | grep -E '^[+-][^+-].*(noqa|eslint-disable)'` shows no net addition (the only expected hit is the pre-existing `# noqa: E402` line on the `frontmatter_lib` import in `scripts/backfill-frontmatter.py`, which appears once as `-` and once as `+`). No former `except ...: pass|continue` handler gains a log line (review checks; F2).
- [ ] AC5: The Phase 2 mutation battery run ends with `control: GREEN` and no `SURVIVED` line (or, if it showed one, the before/after per-mutant counts are identical and are recorded in the PR body), and the proxy suite is green.
- [ ] AC6: Every suite in the Covering Suites table for a touched file exits 0 with its exit code captured, and the Phase 5 `--affected` selection is green. CI's required `test` context is the final arbiter.
- [ ] AC7: `python3 -c "import sys; sys.path.insert(0,'plugins/soleur/skills/skill-creator/scripts'); import quick_validate, package_skill"` exits 0 and the `quick_validate` grep of Phase 3 prints nothing.
- [ ] AC8: ADR-290 carries the Amendment 2 line referencing #10583; no `Closes #10331` appears anywhere in the diff or PR body; the PR body says `Ref #10331` and `Closes #10433`; #10331 is still OPEN after merge.
