# Tasks: S4 affected-index PR3a, the ratchet job, dark (Ref #10448, Ref #9729)

Plan: `knowledge-base/project/plans/2026-10-22-feat-s4-affected-index-pr3-required-ratchet-plan.md`. Rulings: `decision-challenges.md` in this directory. PR text uses `Ref #10448` and `Ref #9729` only. Holds: no `CI_PR_AFFECTED`, no lock removal, no PR D, no ruleset, no `scripts/test-all.sh`, no `scripts/lib/test-affected-paths.sh`, no `scripts/ci-pr-selection.sh`, no `scripts/required-checks.txt`.

## Phase 0 - measure what the floors will see

- 0.1 `git fetch origin main`, record the start commit, create a detached checkout of it.
- 0.2 Build the rows file once from the detached checkout (`--print-selection --paths=README.md`, detached run, Monitor wait).
- 0.3 Measure the line prefixes the real selector prints besides `AFFECTED_SELECTED` rows; pin the `c.extra` allowlist (hazard list plus unknown-prefix rule) with its source command.
- 0.4 Run the audit with `--list`; record the `SOLEUR_PR_AFFECTED_AUDIT` line (expect gap_refs about 1,884).

## Phase 1 - failing tests first (RED), in `plugins/soleur/test/ci-pr-affected-replay.test.sh`

- 1.1 Add section `== ratchet (PR3a)` with its own scratch repos (never the shared fixtures).
- 1.2 Floor rows (exit 2): rows versus `of=`, missing or duplicate summary, fallback, `c.extra` lines, malformed or space-prefixed rows counted, selector rc, empty rows, anti-vacuity.
- 1.3 Registration-only fixture (real selector, pinned selected set with a size floor; a non-registration runner edit falls back and exits 2).
- 1.4 Comparison rows (exit 1): new pair, stale line, duplicate, unsorted, malformed baseline, unaudited suite, stale or `*` accept row, accept row exempting a pair (passes).
- 1.5 Growth rows on a scratch merge-commit history: new-suite attack, same-count swap, shrink (passes), adoption only when absent at both, deleted file, unresolvable base and shallow history (exit 2).
- 1.6 Failure-text contract: suite, path, `file:line`; two remedies; three causes; stale line printed; no command that adds a pair.
- 1.7 `--print-baseline`: stdout only, bootstrap prints all, prune-only once a baseline exists, byte-identical and C-locale sorted.
- 1.8 Marker line regex, `::error` annotation, and `oracle-inputs-changed:` (non-blocking).
- 1.9 Importlib load of `resolve_base` and `baseline_at` from `plugins/soleur/scripts/lint-ratchet.py` with signature checks.
- 1.10 Job wiring rows on `.github/workflows/ci.yml` (no `needs`, positive `if:`, `continue-on-error`, `timeout-minutes` alone, `fetch-depth: 2`, select timeout env, three pin sets, absent from the three required-check files, durable "required means not continue-on-error" row).
- 1.11 Selection classification rows (baseline TSV and replay script are `non_doc`; `ci.yml` still a trigger).
- 1.12 Run the section against the unmodified SUT and keep the RED list for the PR body.

## Phase 2 - implementation in `scripts/ci-pr-affected-replay.py`

- 2.1 `ratchet` subcommand (`--root --list --baseline --accept --print-baseline`; base is `HEAD^1`, not an argument); share the zero-suites helper with `cmd_audit`.
- 2.2 Every exit-2 condition (floors, census, base) before any exit-1 verdict; distinct handler arms; baseline compared as opaque rendered lines; global pair-set growth check; 25-line cap per class.
- 2.3 Baseline-state table (absent/present at base and HEAD) and `base-unresolved` exit 2.
- 2.4 Reason-token table and the short marker line; the `::error` annotation is emitted by the workflow step.
- 2.5 `--print-baseline` (bootstrap, prune-only, stdout exactly the baseline bytes), `oracle-inputs-changed:` on stderr in that mode.
- 2.6 Docstring RATCHET section (REACH and DECLARED LIMITS stay the single source); add the job to `ALWAYS_RUN_JOBS`; re-anchor moved mutation rows.
- 2.7 Write the Guard 1 (12 rows) and Guard 2 (7 rows) `mutate` rows; add the deliberate-crash mutant to `CRASH_IS_THE_POINT`.

## Phase 3 - baseline, job, pins

- 3.1 Generate `scripts/ci-pr-affected-audit.baseline.tsv` on the rebased tree (remove any older copy first, then `ratchet --print-baseline`); `git add` it; line count equals `gap_refs`.
- 3.2 Add job `affected-index-ratchet` to `.github/workflows/ci.yml` (positive `if:`, `continue-on-error`, `timeout-minutes: 5` alone, `fetch-depth: 2`, select timeout 200, annotation from the step) and update the header sentence.
- 3.3 Classify the job in `UNGATED_PINNED`, `LIGHT_PINNED`, `ALWAYS_RUN_JOBS`; edit the `scripts/pr-fanout-ledger.txt` ci.yml row (27 to 28); run the consumer suites including the kb-consumers and fixture-relative censuses.
- 3.4 CI-shape rehearsal: `git clone --depth 2` of a merge-shaped commit, `CI=true`, no `origin/main`.
- 3.5 Record the first real run (`exit=0 reason=pass`, wall time at most 270 s) and read the throwaway DRAFT PR canary (one deliberate unbaselined pair in a tracked fixture) for the failing-`continue-on-error` conclusion; close it afterwards.

## Follow-through enrollment

- E.1 Author `scripts/followthroughs/ratchet-observation-window-10865.sh` (read-only; jobs API plus the emitted marker line; window rules from decision-challenges.md rows 26-27) and its stub-`gh` rows in the replay suite.
- E.2 At ship: add the `follow-through` label and the directive to tracker #10865 (closing it does not authorize PR3b #10859).
- E.3 Create the `s4-drain` label (`gh label create s4-drain`).

## Phase 4 - documentation

- 4.1 Runbook: ratchet sections, corrected wording, dark-phase reading guide, rollback recipe, the pre-PR4 declaration burden.
- 4.2 ADR-276: append the amendment (items 1-9 of the plan) and the stage-status line; no earlier text edited.

## Phase 5 - verification before ready

- 5.1 Replay suite green detached; record the new duration; shard manifests only via the generator if required.
- 5.2 `ratchet` exits 0 on the rebased tree with live equal to baseline equal to `gap_refs`.
- 5.3 Orphan census after tracking, c4 count parity, technical-ruling gate.
- 5.4 Simulate the revert in a scratch detached worktree and run its gates.
- 5.5 Re-run the sibling PR overlap loop; regenerate the baseline on the final rebased tree.

## Follow-on (not PR3a; file issues with `Ref #10448`)

- F1 PR3b: make the context required after the observation window; held for the budget owner's go-ahead.
- F2 PR4: code-edge drain, baseline shrinks in the same commit, runner-trigger edit runs the full battery once.
- F3 PR5: accept rows and non-code pairs, delete the baseline (strict zero), closing ADR line.
- F4 `no-run` investigation (five hypotheses, receipts, decision rule).
- F5 Evidence re-run, criterion c, flip PR: wait for a go-ahead naming the command.
