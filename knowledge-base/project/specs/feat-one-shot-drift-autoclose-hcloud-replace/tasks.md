# Tasks: drift auto-close must not close issues with pending hcloud_server replacements

Plan: `knowledge-base/project/plans/2026-10-02-fix-drift-autoclose-skip-hcloud-server-replacement-plan.md`
Branch: `feat-one-shot-drift-autoclose-hcloud-replace` — PR #9416 (draft). Live example: #9382 (do NOT close it from this PR).

## Phase 1 — RED: fixtures and suite

- 1.1 Synthesize fixtures under `scripts/fixtures/infra-drift-autoclose/`: `replacement-present`, `replacement-escaped-only`, `truncated-cut`, `truncated-title` (+ escaped-summary variant), `clean`, `clean-crlf`, `replacement-crlf` (all `*.body.md`, no real ids/tokens).
- 1.2 Write `scripts/infra-drift-autoclose.test.sh` (100755): single owning sandbox + EXIT trap, `CASES` incremented at call sites, accounting identity, known-negative `bad()` self-test, literal-threshold floor via `printf`+`exit 1`.
  - 1.2.1 `--classify` table arms (file fixtures + inline empty / no-plan / R1 action variants / comment-shape cases).
  - 1.2.2 Stub-`gh` e2e arms (argv-dispatching stub, refuses unknown calls): view fails, comments read fails, list fails, two-issue run closes exactly the clean one with `--reason completed`.
  - 1.2.3 Workflow wiring arm (python3 + yaml, step located by name): single script invocation, no inline `gh issue close`, `GH_TOKEN`/`MERGE_SHA` in `env`.
  - 1.2.4 In-suite mutation battery (function-anchored `sed` edits on a sandbox copy; each mutant asserted to differ from the original): rows 1-11, W1-W3, harness rows H1-H4.
- 1.3 Confirm every arm is RED before the script exists.

## Phase 2 — GREEN: the script

- 2.1 Write `scripts/infra-drift-autoclose.sh` (100755; no `-e`, every `gh` rc captured) with `normalize`, `has_hcloud_replacement`, `is_plan_bearing`, `has_truncation_marker`, `has_complete_terminator`, `classify`.
- 2.2 `--classify` mode (stdin JSON `{body, comments[]}` -> `close` | `skip:<slug>`, never calls `gh`; empty stdin = empty envelope -> `skip:empty-body`; malformed -> `skip:unparseable`). R1 uses the bracket expression `[][A-Za-z0-9_."'-]+` (`]` first) — never `\[\]` inside brackets.
- 2.3 Loop mode: list (unchanged query; failure -> `::error::` exit 1), body via `gh issue view`, body AND comments in ONE `gh issue view N --json body,comments` call (stderr to a separate file; failing or unparseable read -> `skip:gh-view-failed`; pagination verified at plan time), single `gh issue close N --reason completed --comment`, `::notice::` per skip, counter line (no conservation assertion — tautology) mirrored with per-reason skip counts to `$GITHUB_STEP_SUMMARY`; close comment names the five-target scope (see plan).

## Phase 3 — Wire the step

- 3.1 In `.github/workflows/apply-deploy-pipeline-fix.yml`, replace only the `run:` of "Auto-close any open drift issues for this stack" with `bash "${GITHUB_WORKSPACE}/scripts/infra-drift-autoclose.sh"`; keep `name`, `if:` (pinned by infra-config-gate AC18) and `env`; refresh the comment above.
- 3.2 Confirm no new path appears in the workflow's `on.push.paths`.

## Phase 4 — Register and ratchets

- 4.1 Add `run_suite "scripts/infra-drift-autoclose" bash scripts/infra-drift-autoclose.test.sh` to `scripts/test-all.sh` beside `scripts/infra-config-red-alert`.
- 4.2 Set `DRIFT_MIN_ASSERTIONS` to the measured green count.
- 4.3 Run targeted gates once (no full battery): the new suite, `scripts/lint-orphan-test-suites.sh`, `scripts/guard-vacuity-floor.test.sh` (raise `MIN_FIRING_SUITES` by the measured delta if the suite scores FIRES), `plugins/soleur/test/fixture-relative-assert.test.sh`, `plugins/soleur/test/fixture-dir-operand-assert.test.sh`, `shellcheck`, `python3 scripts/lint-guard-contract.py <plan>`.

## Phase 5 — Mutation proof and ship notes

- 5.1 By hand: delete the replacement check from a sandbox copy, capture the red output for the PR body.
- 5.2 PR body: `Ref #9382` (not `Closes`); cite `#9259`/`#9317`/`#9334` as the prior-art closures, mutation red output, scope notes (comments read, create/destroy widening, near-miss types).
