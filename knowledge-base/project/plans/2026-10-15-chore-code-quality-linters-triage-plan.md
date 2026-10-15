---
title: "chore(quality): triage GitHub Code Quality findings and wire deterministic linters into the work/review gates"
date: 2026-10-15
slug: code-quality-linters-triage
branch: feat-code-quality-linters-10331
issue: 10331
lane: cross-domain
type: chore
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(quality): triage Code Quality findings and wire deterministic linters

## Overview

GitHub Code Quality reported 169 findings on `main` (22 rules). This plan splits #10331 into five
independently mergeable slices, in the CTO's order. This branch (`feat-code-quality-linters-10331`,
draft PR #10342) carries the planning artifacts and PR1. PR2 to PR4 each branch from `main` after
the previous slice merges. PR bodies carry `Ref #10331`; only the final slice to merge carries
`Closes #10331` (if PR3b is dropped, that is whichever slice merges last).

| Slice | Deliverable | Depends on |
|---|---|---|
| PR1 | Triage the two `js/comparison-between-incompatible-types` findings (Art. 15/17 code) | none |
| PR2 | Guarded, class-name-only logging in the shipped plugin scripts with empty handlers (five at plan time: the four the issue names plus `incident/scripts/redact-engine.py`) | none |
| PR3a | Ruff baseline ratchet in the required test battery; eslint scope over the unscanned test dirs | PR2 (clean start) |
| PR3b | Plugin `work`/`review` detect-and-run of a project's own installed linters | PR3a design; **not** on the critical path of PR1, PR2, PR4 |
| PR4 | Rule-overlap table, then a dated ADR-276 Decision 6 amendment (keep or drop per-PR Code Quality); record billing | PR3a ratchet data |

## Research Insights

**Premise Validation.** Held: #10331, #9730 (S5), #1440 and #10344 are OPEN; ADR-276 carries the S5
row ("not started"); `knowledge-base/operations/expenses.md` has no Code Quality row. Corrected from
the issue body: (1) `apps/web-platform` already enables `@typescript-eslint/no-unused-vars` with a
committed ratchet (`BASELINE_FINDINGS = 192`, rule pin 74, in `apps/web-platform/test/eslint-config.test.ts`);
the gap is that `eslint .` runs from `apps/web-platform` only, so 111 `.ts` files (plus 1 `.tsx` and
2 `.js`) in `plugins/soleur/test/` and 4 in root `test/` are never linted; (2) no Python linter
exists; (3) `.claude/hooks/security_reminder_hook.py` is repo-only; (4) the code-scanning REST API
does not return Code Quality alerts; (5) `tsc --noEmit` exits 0 in `apps/web-platform`, so TS2367 is
not the source. **Measured 2026-10-15** (`uvx ruff` 0.17.0 with `--select F401,F841,F811,S110,S112,SIM115,BLE001`
and `check-typed-exception = true`, over the 64 tracked `.py` files outside `knowledge-base/`):
82 findings (S110 25, SIM115 21, BLE001 19, S112 10, F841 4, F401 3). Fixing all of them first and
running with no baseline is therefore out of scope for one chore. Without `check-typed-exception`,
ruff's S110/S112 skip typed handlers (`except OSError: pass`), which are most of the proxy's
teardown handlers, so the setting is load-bearing.

**Property List.** P1: the two flagged comparisons are proven correct or fixed, guards unchanged in
behavior. P2: no shipped plugin script swallows an exception silently and no fail-closed path
changes. P3: a new Python or test-dir finding of a ratcheted class fails the required test battery,
and fixing one never fails it. P4: a customer running `work`/`review` gets their own installed
linter's signal on changed files without Soleur imposing rules or executing project-defined commands.
P5: the keep-or-drop decision on Code Quality rests on a measured rule-overlap table and a recorded cost.

**Cut List.** Bundling ruff/eslint into the plugin (detect-and-run buys P4). A new JSON/sha ratchet,
version file, label protocol and ratchet ADR (the baseline pattern in
`scripts/lint-shell-capture-exit.py` + `.baseline.txt`, registered in `scripts/test-all.sh`, buys P3).
A root eslint config and a second ratchet test (extending `eslint-config.test.ts` buys the scope).
Running a customer `package.json` `lint` script, `npx` or `uvx` (security; installed binaries only).
Changed-line delta reporting and `pyproject.toml` parsing in PR3b (raw output on changed files is
enough for v1). Clearing all 82 findings (the baseline absorbs them).

**Institutional pattern to copy.** `scripts/lint-shell-capture-exit.py` (`--baseline`,
`--write-baseline`, keyed by path + class + normalised text, header "may only SHRINK", live
`run_suite` at `scripts/test-all.sh`), `lint-shell-trace-credential-refusal.py --changed --base
origin/main` (whole-file debt for touched files; `work/SKILL.md` §6.5), and the repo's dual-glob
lefthook convention (gobwas learning, 2026-03-21).

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality | Plan response |
|---|---|---|
| "eslint no-unused-vars" needs adding to the gates | Rule + ratchet exist for `apps/web-platform` only | PR3a widens scope to `plugins/soleur/test/` and `test/`; does not re-add the rule |
| Python: add ruff | No Python linter, no config; 76 tracked `.py` (64 outside `knowledge-base/`; 16 shipped) | New work; exclude `knowledge-base/**` archive scratch; 82 findings baselined |
| `security_reminder_hook.py` ships to users | Lives at `.claude/hooks/`; repo-only, advisory, fails open by design | PR2 covers the shipped scripts (the 4 the issue names plus `redact-engine.py`); the hook falls under the PR3a baseline |
| 20 `py/empty-except` in 9 files | Ruff S110/S112 match only with `check-typed-exception = true` | PR2 derives its work list with that setting; PR3a's `ruff.toml` carries it |
| The two comparison findings are in two named files | Sites not locatable by API or `tsc`; static candidates ~10-30% confidence | PR1 locates them (ladder with a timebox) or closes as "unlocatable" |
| Gate runs in CI as a job | A non-required job would be advisory (`lint-webplat` is) | Ratchet registers as a live `run_suite` in `scripts/test-all.sh` (required `test` context); no new CI job |

## Open Code-Review Overlap

None. Queried open `code-review` issues against every file in `## Files to Edit` and `## Files to
Create`; no body references any of them.

## Implementation Phases

### PR1 — comparison findings (this branch)

1. **Locate, timeboxed (`hr-exhaust-all-automated-options-before`).** (a) Browser automation
   (Playwright MCP) against the repository's Code Quality alert list; (b) if that session is
   unauthenticated, the local CodeQL CLI with the JS quality suite over
   `apps/web-platform/server/`, filtered to the rule (a zero-hit run is not proof of a false
   positive, because the CLI suite may differ from Code Quality's); (c) ask the operator for the two
   file:line pairs. If none of the three yields the sites within the timebox, PR1 closes as
   **unlocatable**: record the reason and file a follow-up issue; do not claim P1.
2. **Test first (`cq-write-failing-tests-before`).** Per located site, a vitest case in
   `apps/web-platform/test/` driving the guard with the input class the comparison distinguishes
   (e.g. `CrossTenantViolation` for a foreign `invitee_user_id`; `refused`/`unauthorized` erasure
   outcomes set `gitDataErasurePending`). Run `soleur:gdpr-gate` on the diff.
3. **Decide per site.** Real bug: fix, test green. Redundant-but-harmless check (outcome on `account-delete.ts`): remove the check with a test pinning the surrounding contract. False positive: dismiss the alert through the
   same browser automation with the stated reason (so it stops feeding PR4's counts), link the
   dismissal in the PR body, and change no production code. If a guard is shown defeatable: **PR1
   halts**, the CLO assesses the Art. 33 72-hour clock, and PR2 to PR4 proceed independently (they
   touch no erasure/export code).
4. **Record.** Add a "Resolution" section to
   `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`.

### PR2 — shipped-script handlers

1. **Derive the set.** `uvx ruff==0.17.0 check --isolated --no-cache --select S110,S112,BLE001
   --config 'lint.flake8-bandit.check-typed-exception = true'` over `plugins/soleur/**/*.py` excluding `test/` and fixtures (five scripts at plan time: the four the issue names plus `plugins/soleur/skills/incident/scripts/redact-engine.py`, 2 S112 hits at lines 234 and 338, also a redaction path; any script found outside this set is justified in the PR body) (version pinned
   inline here; `ruff.toml` and its `required-version` land in PR3a). The output is the work list.
2. **One helper per script.** `_note(exc)` writes `type(exc).__name__` and nothing else to stderr,
   wrapped in its own `OSError` guard so a closed pipe cannot turn a swallowed error into a crash.
   Teardown handlers (`close`, `wait`, `killpg`, temp cleanup) call it and keep their behavior.
   Never log `str(exc)`, `repr(exc)` or payload text. Fail-closed arms (`refuse_start`,
   `error_result`, withheld-on-failure) are not touched. The helper's own guard is the one
   deliberate silent handler, documented in a comment, so S110 does not reach zero.
3. **Tests first.** Extend the proxy's existing suite: run the proxy as a real subprocess with a
   canary secret in the failing input and assert the canary never appears in the captured stderr;
   refuse/withhold results unchanged. A stderr-note case for `founder-check.py`, `resolve-debt.py`,
   `scan-ancestor-signal-helpers.py` and `redact-engine.py`.
4. **Close the unknown.** Whether a log call or a comment clears `py/empty-except` is unverified.
   File a tracking issue at PR2 time with a decision rule: after the next Code Quality scan, if the
   count for the PR2 scripts did not drop, switch to a comment-form note or dismiss with reason.

### PR3a — repo linters

1. **Ruff baseline ratchet, copied from the existing pattern.** New `ruff.toml` (`required-version`
   pin, select `F401,F841,F811,S110,S112,SIM115,BLE001`, `[lint.flake8-bandit]
   check-typed-exception = true`, exclude `knowledge-base/**`). New `scripts/ruff-ratchet.py`
   modelled on `lint-shell-capture-exit.py`: runs `ruff check --output-format json`, relativizes
   paths to the repo root, reads each file to take the offending line, and keys each finding
   `path<TAB>rule<TAB>normalised-line`. The baseline `scripts/ruff-ratchet.baseline.txt` is sorted,
   one key per line **with a count** (a multiset, so identical lines in one file do not collapse and
   a fix-then-re-add cannot pass). Header: "may only SHRINK". `--write-baseline` exists but only
   removes keys; a ruff pin bump regenerates the baseline in the same diff. `--changed --base
   origin/main` owes a touched file's whole debt (mirrors §6.5); a separate `--check-shrink --base
   origin/main` fails when the baseline gains a key relative to base unless the same diff changes
   the `required-version` pin. Both reuse the `origin/main` fallback the other lints use
   (`github.base_ref` is empty on `merge_group`, shallow clones need `fetch-depth: 0`). A deliberate
   suppression is a ruff `# noqa: RULE  reason` comment, not a label (labels are invisible on
   `merge_group`).
2. **Wire into required contexts, not new jobs (ADR-276 Decision 1).** Register
   `run_suite "scripts/ruff-ratchet" bash scripts/ruff-ratchet.test.sh` and a live
   `run_suite "scripts/ruff-ratchet-live" python3 scripts/ruff-ratchet.py --baseline
   scripts/ruff-ratchet.baseline.txt` in `scripts/test-all.sh`. Add a lefthook entry using the
   repo's dual-glob convention for `.py` that invokes `ruff-ratchet.py --changed --base origin/main`
   (defined invocation, no staged-file mode). The failure message names the exact remediation.
   Install ruff in the existing python-running job with the pinned version; any new install site
   must pass `lint-workflow-install-sites.sh` with SHA-pinned actions. Verify with `scripts/lint-orphan-test-suites.sh` that the new suites are registered. Report the added job-minutes
   in the PR body, as the ADR-276 S1 amendment does.
3. **ESLint scope, extend first.** Try adding `plugins/soleur/test` and `test` to
   `apps/web-platform`'s eslint run: extend `lintScriptArgs()` and `MIN_FILES_BY_DIR` in
   `eslint-config.test.ts` . `MIN_FILES_BY_DIR` is keyed by top-level dir under `apps/web-platform` (`test: 1000` already exists) and its self-guard rejects any floor under 10, so add a distinct key `plugins/soleur/test` with floor 100; root `test/` has 4 files, carries no floor (as the test already states for small dirs) and is covered by the global count. Re-pin `BASELINE_BY_RULE` (the new dirs also surface `no-empty` and similar findings). Only if flat config ignores paths outside
   its base, fall back to a root `eslint.config.mjs` that resolves plugins from
   `apps/web-platform/node_modules` via `createRequire` and run with
   `apps/web-platform/node_modules/.bin/eslint --config`. One config root, one test, in the
   required `test-webplat` context. Fold the run into `lint-webplat` (already does `npm ci`).
4. **Ratchet design note.** No new ADR. Add one paragraph to ADR-242 stating the baseline-ratchet
   pattern now also covers Python findings and test-dir eslint, extending (not superseding) the
   existing highwater and baseline files.

### PR3b — plugin detect-and-run (off the critical path)

1. New `plugins/soleur/scripts/detect-project-linters.sh`: detects `eslint.config.*` and
   `ruff.toml`/`.ruff.toml` at the repo root only (no monorepo walk, no `pyproject.toml` parse, no
   `package.json` `lint` script). Prints one line per linter found, or `no linter configured`.
   Never installs and never executes anything.
2. `work/SKILL.md` and `review/SKILL.md`: a short body-only step that runs an **already-installed**
   binary (`node_modules/.bin/eslint`, `ruff` on PATH) with explicit changed-file paths, a timeout
   and an output cap (`hr-never-run-commands-with-unbounded-output`); never `npx`, `uvx`, `npm run`.
   Raw output only. A tool exit meaning "config or run error" is reported as "linter errored", never
   as clean, and never blocks. `no linter configured` skips silently with a one-line note. In
   `review` (which runs on PR heads) use the base-branch config, or ask before running a config
   from the PR head. Confirm the hosted Bash must-ask lane (ADR-284) behavior. No `description:` edit. **Byte ceilings:** `plugins/soleur/test/skill-body-budget.json` leaves `work` 10 bytes (359189 vs 359179) and `review` 8 bytes (475921 vs 475913), and ceilings only ratchet down, so each SKILL.md edit (including the PR3a pointer) ships an offsetting trim in the same file; record `ceiling - wc -c` in the PR body.
3. Tests with synthetic fixture repos: eslint-only, ruff-only, none; a repo with a `package.json`
   `lint` script that would write a sentinel file (must not run); a config that errors (reported as
   errored); a linter that sleeps past the timeout; output past the cap.

### PR4 — Code Quality decision

1. **Rule-overlap table.** `knowledge-base/engineering/audits/2026-10-15-code-quality-rule-overlap.md`
   maps each of the 22 baseline rules to the ruff/eslint rule that covers it or "none", with the
   uncovered share. Static mapping, no ratchet.
2. **Decision as its own dated amendment.** ADR-276 says S5 is decision-only and Decision 6 reserves
   Code Quality for its own CLO/CTO decision, so do not edit the S5 row owned by #9730: write a
   dated amendment citing Decision 6, with CLO and CTO sign-off recorded. Default per the CTO: keep
   on unless the uncovered share is negligible.
3. Add the Code Quality row to `knowledge-base/operations/expenses.md` ($10 per active committer per
   month plus AI credits, as shown when the feature was enabled on 2026-10-14; marked as an estimate
   with `verify_by`; billing owner flagged for the operator).

## Files to Edit

- `apps/web-platform/server/account-delete.ts`, `apps/web-platform/server/dsar-export.ts` (PR1, only if a real bug is found)
- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`, `plugins/soleur/skills/preflight/scripts/founder-check.py`, `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`, `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`, `plugins/soleur/skills/incident/scripts/redact-engine.py` (PR2)
- `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES` entry for `scripts/ruff-ratchet-live`, so local `--affected` runs select it), `lefthook.yml`, `apps/web-platform/test/eslint-config.test.ts`, `apps/web-platform/eslint.config.mjs`, `apps/web-platform/package.json` (the `lint` script that `lintScriptArgs()` reads; `cq-before-pushing-package-json-changes` applies), `.github/workflows/ci.yml` (PR3a, install step only)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` (PR3a, one paragraph)
- `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/review/SKILL.md` (PR3a pointer, PR3b step)
- `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md` (PR1 resolution)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`, `knowledge-base/operations/expenses.md` (PR4)

## Files to Create

- Regression tests for the two comparison sites under `apps/web-platform/test/` (PR1)
- Proxy subprocess canary test and stderr-note cases next to the existing suites (PR2)
- `ruff.toml`, `scripts/ruff-ratchet.py`, `scripts/ruff-ratchet.baseline.txt`, `scripts/ruff-ratchet.test.sh` (PR3a)
- `plugins/soleur/scripts/detect-project-linters.sh`, `plugins/soleur/test/detect-project-linters.test.sh` (PR3b)
- `knowledge-base/engineering/audits/2026-10-15-code-quality-rule-overlap.md` and the dated ADR-276 amendment (PR4)

## User-Brand Impact

**If this lands broken, the user experiences:** a redaction proxy that crashes or stops withholding
(an agent session sees unredacted browser content), a DSAR export or account erasure that reports
success on a defeated guard, or a `review` run that executes code from a customer's pull request.

**If this leaks, the user's data is exposed via:** a log line in a plugin script that echoes an
exception message carrying redacted-away content, a mistyped cross-tenant guard admitting another
subject's rows into an export, or detect-and-run executing a project-defined command with the
reviewer's credentials.

**Brand-survival threshold:** single-user incident

The CPO sign-off from the brainstorm is conditional on PR3b staying minimal (detect-only, installed
binaries only, advisory); the operator override of the CPO's deferral advice is recorded in the
brainstorm. `soleur:engineering:review:user-impact-reviewer` runs at review time on PR1, PR2 and PR3b.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering
**Status:** reviewed (brainstorm carry-forward plus plan-review panel 2026-10-15)
**Assessment:** four-PR order held; ratchet reuses the existing baseline pattern; no new CI job; PR4 is its own amendment citing ADR-276 Decision 6.

### Product
**Status:** reviewed (brainstorm carry-forward plus CPO plan review)
**Assessment:** verdict proceed; PR3b is off the critical path and minimal; no roadmap row exists for PR3b, the operator override is the recorded justification.

### Legal
**Status:** reviewed (brainstorm carry-forward; gdpr-gate run on this plan: no Critical or Important findings)
**Assessment:** no CLO sign-off unless PR1 finds a real defect; PR4's Code Quality decision needs CLO/CTO sign-off per Decision 6. Missing DPA file tracked as #10344.

### Product/UX Gate
**Tier:** none
**Decision:** no user-facing UI surface in any slice.
**Pencil available:** N/A (no UI surface)

## Observability

```yaml
liveness_signal:
  what: scripts/ruff-ratchet live run and the eslint ratchet test, both inside the required test battery
  cadence: every PR and every merge_group run
  alert_target: required `test` check status on the PR
  configured_in: scripts/test-all.sh, apps/web-platform/test/eslint-config.test.ts
error_reporting:
  destination: CI job log; plugin scripts write a class-name-only line to the user's terminal stderr (observability layer 7, customer self-hosted CLI, no Sentry by design for privacy)
  fail_loud: true
failure_modes:
  - mode: a finding is swapped rather than added
    detection: multiset baseline keyed on path, rule and normalised line
    alert_route: required test red
  - mode: ruff glob matches zero files and passes vacuously
    detection: self-test asserts a minimum file-count floor
    alert_route: required test red
  - mode: a plugin script stderr note leaks exception content
    detection: canary-secret subprocess test
    alert_route: required test red
  - mode: detect-and-run executes a project-defined command
    detection: sentinel-file fixture test
    alert_route: required test red
logs:
  where: GitHub Actions run logs; plugin stderr in the user's terminal
  retention: GitHub default (90 days)
discoverability_test:
  command: bash scripts/ruff-ratchet.test.sh
  expected_output: ruff-ratchet-selftest ok
```

This block is the PR3a one: its command cannot exist in a tree before the file does. PR1, PR2 and
PR3b each carry their own block, naming their own test file, authored together with that test.

## Architecture Decision (ADR/C4)

### ADR
No new ADR for the ratchet: it reuses an existing pattern, so PR3a adds one paragraph to ADR-242.
PR4 writes a dated ADR-276 amendment citing Decision 6 (a task in PR4, not a follow-up issue). Both
land in the PR that makes the change true.

### C4 views
No C4 change. Checked against `model.c4`, `views.c4` and `spec.c4`: no element or edge names
lefthook, eslint, ruff or CodeQL (grep over `model.c4` returns only the existing `github`,
`betterstack` and `zotRegistry` elements and edges); the work adds no external actor, no external
system or vendor, no data store, and changes no actor-to-surface access relationship (Code Quality is
a setting on the already-modeled `github` element). Run `plugins/soleur/test/c4-count-parity.test.sh`
in each slice.

### Sequencing
Nothing here is deferred: ADR-242's paragraph ships with PR3a and the ADR-276 amendment with PR4.

## Guard Contract

### Guard 1 — ruff baseline ratchet (PR3a)

**Property.** A finding of a ratcheted rule that is not covered by the committed baseline fails the
required test battery, and a finding covered by the baseline never does.

**Assembly.** The key function (`path`, `rule`, normalised line), the baseline file and its multiset
counts, how ruff is resolved by each executor (CI pinned install, lefthook, PR2's `uvx ruff==0.17.0`), the ruff invocation and its file-selection set, the `--changed` and `--check-shrink` paths,
the `test-all.sh` registrations, and the lefthook entry. The chokepoint is the key function; the
battery and lefthook call the same script.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Add an unused import to a tracked `.py` file with no baseline entry | key absent from baseline |
| 2 | Add a second identical `except OSError: pass` to a file whose first is baselined | count exceeds the baselined count (multiset) |
| 3 | Remove one baselined unused import and add a different one in the same file | key set changed although the total is equal |
| 4 | Point the file-selection set at an empty directory | floor check: 0 files checked fails |
| 5 | Add a baseline key in a diff that does not change the `required-version` pin | `--check-shrink` fails |
| 6 | Make `ruff` unresolvable, or put a different version on PATH | the live suite exits non-zero (version mismatch or absent binary is an error, never a skip or green); the self-test also asserts the live suite checked > 0 files |

**Harness rows.** RED: delete the script's non-zero exit on new findings; the self-test must fail.
PASS (not the canonical): a file whose baselined finding moved to a different line number still
passes, and a ruff pin bump with a regenerated baseline in the same diff passes `--check-shrink`.

**Anchor.** The baseline and the code move in one diff, so the guard proves consistency, not
integrity. The independent anchor is `--check-shrink --base origin/main`: the baseline may only
shrink relative to the merge base, except in a diff that also changes the `required-version` pin.

### Guard 2 — eslint scope floor for the test dirs (PR3a)

**Property.** Every `.ts` file under `plugins/soleur/test/` and `test/` is inside the eslint run,
and the unused-vars count of that whole run cannot grow. The pin is global, so drawdown elsewhere in
`apps/web-platform` can mask growth in the new directories; that residual is accepted and stated.

**Assembly.** The extended `lintScriptArgs()` paths, `MIN_FILES_BY_DIR` floors, `BASELINE_BY_RULE`,
and a count of `eslint-disable` comments in the scoped dirs.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Introduce an unused variable in a `plugins/soleur/test` file | rule count exceeds the pin |
| 2 | Narrow the path list so `plugins/soleur/test` is dropped | `MIN_FILES_BY_DIR` floor fails |
| 3 | Add a file-level `eslint-disable` over a new unused variable | `eslint-disable` comment count exceeds its pin (the directive is used, so the unused-directive check cannot see it) |
| 4 | Move 20 test files out of the scoped dirs | floor fails |

**Harness rows.** RED: set the pin above the current count; the one-sided test must still fail on
growth. PASS (not the canonical): a run with the count below the pin passes (drawdown never reds).

**Anchor.** Pin and code move in one diff; the independent anchor is the `MIN_FILES_BY_DIR` floor
plus the existing base-branch comparison in `eslint-config.test.ts`.

### Guard 3 — detect-and-run never executes project-defined commands (PR3b)

**Property.** `work`/`review` detect-and-run executes only an already-installed linter binary with
explicit paths, never a project-defined script, and never reads a linter error as clean.

**Assembly.** The detector script, the run step in `work/SKILL.md` and `review/SKILL.md`, the
timeout and output cap, and the exit-code mapping.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Make the step call `npm run lint` when a `lint` script exists | sentinel-file fixture is written |
| 2 | Map a config-error exit to "clean" | errored-config fixture must report "linter errored" |
| 3 | Remove the timeout | sleeping-linter fixture hangs past the test bound |
| 4 | Remove the output cap | oversized-output fixture exceeds the line bound |

**Harness rows.** RED: a fixture whose linter binary is absent must report not-installed, not
clean. PASS (not the canonical): an unconfigured repo prints `no linter configured` and exits 0.

**Anchor.** Fixtures are synthetic and live in the same PR; the independent anchor is the
architecture-review requirement that `review` uses the base-branch config.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "triage the two js/comparison-between-incompatible-types findings in apps/web-platform/server/account-delete.ts and dsar-export.ts" [issue #10331] | PR1 | mapped |
| 2 | "replace silent `except: pass` and `except BaseException` with logged or re-raised handling, starting with the redaction proxy and the security hook" [issue #10331] | PR2 (the hook is repo-only and falls under the PR3a baseline) | mapped |
| 3 | "add deterministic linters to the work and review gates (ruff for Python ... eslint no-unused-vars for JS/TS), each with a baseline that only ratchets down" [issue #10331] | PR3a, PR3b | mapped |
| 4 | "decide whether per-PR GitHub Code Quality stays on" [issue #10331] | PR4 | mapped |
| 5 | "record it there or confirm the billing owner" (expenses.md) [issue #10331] | PR4 step 3 | mapped |
| 6 | "Scope the slicing into separate PRs where independent." [brief] | Overview table | mapped |
| 7 | "Internal plus plugin detect-and-run" [operator answer, brainstorm] | PR3b | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| PR1 locate-and-test | "triage the two js/comparison-between-incompatible-types findings" | asked |
| PR2 `_note` helper, class-name-only | — | inferred — justification: the redaction proxy's exceptions can carry content, so logging a message would break the redaction property the issue names |
| PR3a ruff baseline ratchet | "each with a baseline that only ratchets down" | asked |
| PR3a eslint scope widening | "eslint no-unused-vars for JS/TS" | asked |
| PR3a ADR-242 paragraph | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the pattern's scope changes, so its record must change in the same PR |
| PR3b detect-and-run | "Internal plus plugin detect-and-run" | asked |
| PR3b safety limits (installed binaries only, timeout, cap, base-branch config) | — | inferred — justification: `review` runs on PR heads, so executing project-defined commands would run attacker-controlled code; found by three plan reviewers |
| PR4 rule-overlap table | "decide whether per-PR GitHub Code Quality stays on" | inferred — justification: the CTO ruled the decision must rest on a measured overlap, not assertion |
| PR4 expenses row | "record it there or confirm the billing owner" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `plugins/soleur`, `scripts`, `.github`
- Planned files: ~28 | Estimated changed lines: ~1,100 across all slices
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — one PR per slice, as the Overview table states. Each slice alone is under every threshold.

## Acceptance Criteria

### Pre-merge (per PR)

- [ ] PR1: sites located and recorded, or PR1 closed as "unlocatable" with a follow-up issue; each located site has a regression test; fixed, or dismissed with the reason linked in the PR body; `gdpr-gate` run; baseline audit has a Resolution section
- [ ] PR2: the S110/S112/BLE001 set for the shipped scripts is empty or each remainder is justified in the PR body; the canary-secret subprocess test passes; the proxy's existing suite passes unchanged; a tracking issue with the decision rule exists
- [ ] PR3a: `scripts/ruff-ratchet.test.sh` passes all six Guard 1 mutation rows and the harness rows; the live run is registered in `scripts/test-all.sh`; Guard 2 rows pass with the extended eslint scope (or the documented root-config fallback); ADR-242 paragraph added; added job-minutes reported; `lint-workflow-install-sites.sh` green
- [ ] PR3b: Guard 3 fixtures pass (including the sentinel, errored-config, timeout and output-cap cases); `work` and `review` run on changed files only; `bun test plugins/soleur/test/components.test.ts` unchanged
- [ ] PR4: overlap table committed; ADR-276 amendment cites Decision 6 with CLO and CTO sign-off recorded; expenses row added with a `verify_by` estimate marker
- [ ] Every slice: `plugins/soleur/test/c4-count-parity.test.sh` green; PR body has `Ref #10331` (the final merged slice carries `Closes #10331`); each PR states its precondition and what happens if it fails

### Post-merge

- [ ] None that require a person: PR2's open question is tracked by the issue with a decision rule (PR2 step 4); the billing owner is flagged in the PR4 expenses row as an estimate

## Test Scenarios

- Given a foreign `invitee_user_id` and `inviter_user_id` row, when the DSAR guard runs, then `CrossTenantViolation` is raised (PR1)
- Given a failing redaction input containing a canary secret, when the proxy runs as a subprocess, then stderr carries only an exception class name and the refuse/withhold result is unchanged (PR2)
- Given a new unused import in a file with no baseline entry, when `ruff-ratchet.py` runs, then it exits non-zero naming path and rule (PR3a)
- Given a customer repo whose `package.json` has a `lint` script that writes a sentinel, when `detect-project-linters.sh` and the run step execute, then the sentinel is absent (PR3b)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan's section is filled.
- Never log `str(exc)`/`repr(exc)` from the redaction proxy: exception text can carry the content being redacted.
- Ruff's S110/S112 skip typed handlers unless `check-typed-exception = true`; a work list derived without it silently misses most of the proxy's teardown handlers.
- A baseline keyed without a count collapses identical lines in one file and lets a fix-then-re-add pass; store a multiset.
- `lefthook.yml` entries without the repo's dual-glob convention can pass zero args and pass vacuously.
- Labels are invisible on `merge_group` events; never make a gate's escape hatch a PR label.
- The code-scanning API does not list Code Quality alerts; do not plan around reading them by `gh api`.
- The CodeQL `py/empty-except` query's treatment of comments and log calls is unverified; PR2 step 4 handles the unknown.
- `plugins/soleur/test/skill-body-budget.json` ceilings only ratchet down and `work`/`review` have 10 and 8 bytes spare: every SKILL.md edit needs an offsetting trim in the same file.
- Local `--affected` selects suites through `scripts/lib/test-affected-paths.sh`; a suite registered only in `scripts/test-all.sh` is not selected locally.
