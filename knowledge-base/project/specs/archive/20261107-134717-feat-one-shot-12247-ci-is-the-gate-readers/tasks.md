# Tasks: feat-one-shot-12247-ci-is-the-gate-readers

Plan: `knowledge-base/project/plans/2026-11-07-feat-ci-is-the-gate-token-reaches-work-review-grok-gate-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12247-ci-is-the-gate-readers/decision-challenges.md`
Standing constraints: file-selected suites only (no affected battery to completion); no push to a PR in the merge queue; no `--admin`; no ruleset change; components written canonically (`soleur:ship`); #12251 is a SEPARATE PR (ruling F4).

## Phase 1 - RED tests (append to `plugins/soleur/test/ship-battery-owed.test.sh` after the last T18p assertion and before the `# The floor counts` comment; never edit helpers above it)

- 1.1 Add `run_gate_tok`, `ctl19`, a PATH-shim `gh` call logger (no edit to `make_stub`) and the fake-plugin-tree builder. Every helper ends in `printf` plus `return 0` (errexit). Reuse fixtures with the `ctl18` rename trick.
- 1.2 Reader rows: T19a no token on a CI-skippable fixture is OWED with an empty call log (the bare control has a NON-empty log); T19b token on the incident shape is SKIPPABLE and a green-CI row asserts the operator-token reason; T19c token plus infra path is OWED; T19d `--bogus`, `--token-only extra` and an empty-string argument are UNDECIDABLE with reason `unknown argument`, a lone `--token-only` returns 42 as control.
- 1.3 Wrapper rows (fake plugin tree, stub reader and stub gate): reader rc 42 skips (exit 0, verdict line, SKIPPED line, `AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate`, gate not invoked, reader saw exactly `--token-only`); reader rc 0, 2, 137 run the gate; a reader printing SKIPPABLE text but exiting 1 or 2 runs the gate; gate rc 0 and 6 pass through; `--full`, `--explain` and an empty argument bypass the reader (stub configured to 42) and reach the gate verbatim; decoy `CLAUDE_PLUGIN_ROOT` does not skip; live-repo row: the resolved reader path answers `--token-only --bogus` with UNDECIDABLE; a plain git repo without `knowledge-base/` or `origin/main` returns OWED; flag parity (wrapper and Grok flag strings non-empty) run through the real reader in a `build_fixture` tree with no token.
- 1.4 Grok rows: two sentinel pairs, exact-line awk, skip-flag init INSIDE the dispatch sentinels, both extractions run together in one `set -euo pipefail` shell with stub `run_step` and a trailing stub; reader stub logs argv and fails unless it is exactly `--token-only`; 42 skips, 0 and 2 call `run_step`; banner says `PASS WITH SKIPPED GATE` only when skipped and the `PASS — safe to git push` echo sits only in the not-skipped branch; `GATE=...affected-tests.sh` and the bare gate line remain; exactly one comment-stripped `"$BATTERY_OWED"` invocation and one `--token-only` line.
- 1.5 Call-site pins (flag-based extraction, non-empty floors, one assertion per path): work step-9 fence has a `${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh` command line (comments stripped) and no non-comment `affected-tests.sh` invocation; work fan-out and review lead sentences carry the wrapper command form; NEGATIVE rows (readable first, then count 0) over `test-fix-loop/SKILL.md`, `lefthook.yml`, `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/lib/affected-tests/*`, `battery-refusal-wait.sh` and `scripts/test-all.sh` for `gate-or-skip`, `--token-only`, `battery-owed`, `session-state`, `ci-is-the-gate`; `operator-constraints.md` item 4 carries `--token-only` and `gate-or-skip.sh`.
- 1.6 Run the suite once and confirm each new row is RED for the right reason. Do not bump the floor yet.

## Phase 2 - Reader flag (`plugins/soleur/skills/ship/scripts/battery-owed.sh`)

- 2.1 Argument parse before the git checks: no argument or exactly `--token-only`; anything else (including a second argument or an empty string) calls `undecidable "unknown argument"` without echoing it.
- 2.2 No-token short-circuit right after `OPERATOR_CI_WORDS`, before condition 1.
- 2.3 Header: exit-contract line and consumer list (replace the "Work Phase 2 and review do not read it (#12247)" sentence). Leave the `CHANGED="$(git diff --name-status -M` line and the #12251 sentence untouched. No fall-through guard (cut by plan-review).

## Phase 3 - Wrapper (`plugins/soleur/scripts/gate-or-skip.sh`, mode 0755)

- 3.1 `set -uo pipefail` (no `-e`); siblings via `$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)`; token consulted only when `$#` is 0; `[[ -r "$OWED" ]]` guard; reader status on its own line (`"$BASH" "$OWED" --token-only; rc=$?`, no pipe, no `local rc=$(...)`); 42 prints the reader output, the SKIPPED line and the machine line and exits 0; else `exec "$BASH" "$GATE" "$@"`.
- 3.2 Header comment: exit mapping, why only 42, why any argument bypasses, non-consumers, ADR-179 sibling path, precedent `collision-precheck.sh`.

## Phase 4 - Grok gate (`plugins/soleur/scripts/grok-pre-push-gate.sh`)

- 4.1 `BATTERY_OWED` beside `GATE=` (keep `GATE=` exactly).
- 4.2 Sentinel-delimited branch (`# grok-token-dispatch:start` / `:end`, commented as sliced by T19) around `run_step "affected-tests gate" bash "$GATE"`; init the skip flag to 0 inside it; capture with the `rc=$?` or-assignment so `set -e` cannot abort; branch on 42 only; `[note]` line on stderr.
- 4.3 Banner as a two-way branch inside `# grok-token-banner:start` / `:end`. `grep -rn "safe to git push"` first (expected: only the banner line itself).
- 4.4 Header comment.

## Phase 5 - SKILL.md call sites (byte-measured; ship and one-shot stay byte-identical)

- 5.1 `plugins/soleur/skills/work/SKILL.md`: step-9 fence command to the wrapper with a short fence comment keeping the literal `affected-tests.sh`; rewrite the fan-out lead sentence (keep the "Two mechanical backstops" anchor and the `bash scripts/test-all.sh --print-selection` preview; link the contract rc table; rc 6 and 7 are never reported as passed); move the compat-spelling paragraph verbatim to the contract reference; no other prose.
- 5.2 `plugins/soleur/skills/review/SKILL.md`: rewrite the lead-gate sentence (same constraints; keep "Two backstops"); MOVE the `SOLEUR_SUBAGENT=1` tail sentence verbatim to the contract reference (mind the line break inside the backtick token).
- 5.3 `wc -c` before and after (work 359177, review 475913): net delta at or below 0 each; `python3 scripts/lint-skill-body-budget.py --base origin/main`; `grep -c "bash scripts/test-all.sh"` after; regenerate ONLY the work and review rows of `apps/web-platform/test/fixtures/plugin-root-skills-ratchet.tsv`, downward.

## Phase 6 - Docs, ADR, edges

- 6.1 `plugins/soleur/skills/ship/references/affected-gate-contract.md`: short wrapper section, exit-table row for the skip, intro line update, trust lines (review-time skip trusts the branch under review; the declaration asserts a CI gate exists), the `one-shot/SKILL.md:25` drift note, and the two moved paragraphs.
- 6.2 `plugins/soleur/skills/one-shot/references/operator-constraints.md`: item 4 only; fenced example byte-identical.
- 6.3 ADR-242: top-of-list `amended_by:` pointer plus `## Amendment — 2026-11-07 (#12247)` appended at the end (10-15 lines: supersedes the closing sentence of the 2026-11-06 amendment, channel count, consumers, non-consumers, residuals, rejected A and C, #12297); one-line pointer in the ADR-183 paragraph.
- 6.4 `scripts/lib/test-affected-paths.sh`: edges for the new reads in the suite's array (wrapper and Grok script after `battery-owed.sh`; work, review, test-fix-loop SKILL.md and `lefthook.yml` after `ship/SKILL.md`; `# why` comments; the self-edge stays last); preview with `bash scripts/test-all.sh --print-selection`.

## Phase 7 - Verification (file-selected)

- 7.1 Floor from the first fully green run's own PASS counter; set `print_results` to it.
- 7.2 Mutation battery in a `soleur-sandbox.sh` copy (plugins/soleur, scripts/lib, lefthook.yml), line-range-scoped mutants, instrument control, mutation-landed check, lead-unique scratch name, two fix rounds plus one verification pass. Matrices: Guard 1 rows 1-6, Guard 2 rows 1-10.
- 7.3 One fresh read-only verifier over the final diff.
- 7.4 Suites and lints: `ship-battery-owed.test.sh`, `collision-precheck.test.sh`, `fanout-suite-scope.test.sh`, `fullsuite-merge-gate.test.ts`, `workflow-fidelity.test.ts`, `plugin-root-anchoring.test.ts`, `invocation-axis.test.ts`, `scripts-shard-runtime-coverage.test.sh`, `components.test.ts`, `c4-count-parity.test.sh`, `lint-skill-body-budget.py --base origin/main`, `lint-guard-contract.py`, shellcheck, markdownlint.
- 7.5 Smoke, only if the branch's `session-state.md` exists: `bash plugins/soleur/skills/ship/scripts/battery-owed.sh --token-only; echo rc=$?` (never the wrapper); paste the actual line.

## Ship notes

- PR body: `Closes #12247`, `Ref #12251`, `Ref #12297`, `Ref #12246`; declare net issue flow (files #12297, closes #12247); surface decision rows P8, S1 and S2.
- Read `infra-validation` and `sandbox-canary-capture-gate` by hand with `gh pr checks` and record the actual conclusions; rely on the required checks for the rest.
