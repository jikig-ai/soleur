# Tasks — feat-one-shot-10932-residuals-2-3-restore-w9

Plan: `knowledge-base/project/plans/2026-10-30-chore-registry-restore-w9-residuals-2-3-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-10932-residuals-2-3-restore-w9/decision-challenges.md`

Only code file edited: `tests/scripts/test-registry-d10-workflow-wiring.sh`. Do not touch the workflow, the engine,
`tests/scripts/lib/restore-engine-header.sh`, `tests/scripts/test-registry-pull-path-health.sh`,
`scripts/lib/test-affected-paths.sh` or `scripts/lib/test-relevance-paths.sh`.

## 0. Preflight (no edits)

- 0.1 Re-read the W9 block, the lib and the engine header; re-count header failure codes from the live engine (expect 1 2 3 4 5 6 78).
- 0.2 `git fetch origin main`; rebase onto it (no stash); re-confirm every item is still stale with `git grep` on `origin/main`.
- 0.3 Baselines, one Bash call each (detached with an rc file when long): wiring 47/0, pull-path-health 63/0, restore-from-ghcr 98/0, `bun test plugins/soleur/test/workflow-file-size.test.ts`. If the local battery queues (rc 6), CI's required `test` context is the gate; never label it passed locally.
- 0.4 `wc -c` the workflow after the rebase and record it (no edit planned; expected 489,131).
- 0.5 Time W1-W8 in a sandbox copy (threshold ~5 s for gating them under `W9_NESTED`).

## 1. Guard 2 — computed die/exit word census (3b)

- 1.1 RED: controls for `w9_computed_sites` fail because the function is absent (sandbox copy).
- 1.2 Implement `w9_computed_sites`: blank whole-line comments; remove the two allowed lines (`^die\(\) \{( #.*)?$`, `^[[:space:]]*exit "\$code"$`), each exactly once; token pass `grep -noE '\b(die|exit)\b( [0-9]+\b)?'`; offenders = tokens without a single-space digit argument; floor >= 1 accepted token.
- 1.3 Call the same function from `w9_check` ("computed die/exit site" problem with line numbers).
- 1.4 Controls: computed variable, bare exit, case-arm `)`, two-space, zero-sites floor (direct calls) + one wire-in through `w9_check`.

## 2. Guard 1 — Restore summary step (3a)

- 2.1 RED: controls for `w9_summary_check` fail (function absent).
- 2.2 W9_PY modes `sumextract`/`sumenv`/`sumkeys`, and `mutate:sum*` dispatched BEFORE the `78)`-arm search; summary controls use step name "Restore summary".
- 2.3 `w9_summary_check`: pin `if == always()`, env == exactly `RESTORE_RESULT=${{ job.status }}`, forbidden keys (code pin), position after the restore step; run the body under `env -i ... bash -e -c` for success / cancelled / empty; semantic anchors (`closed`, `cancelled`, whole word `failed`), empty stdout, non-empty summary file, heading.
- 2.4 Row `W9s` + controls `sumifdrop`, `sumenvlit`, `sumswap`, `sumredirect`, `sumorder`.

## 3. Guard 3 — verdict swap (3c)

- 3.1 RED by hand: `if true` / `-z`->`-n` on the W9 row leaves the suite 47/0 (quote in PR).
- 3.2 `w9_expect` data-returning verdict function for the loop and the row; canary row.
- 3.3 `W9_NESTED=1` guard: `exit 64` after the W9 row, before the controls loop; skips controls, meta-control, floor.
- 3.4 Meta-control: tree under `$W9_TMP/meta`, nested run on the `drop1`-mutated workflow; require exit 64, `cmp` differs, exactly one FAIL line naming `W9 the restore step maps` and `exit 1 fell`.

## 4. Residual 2 wording

- 4.1 Reword the "Exit 1 is added to the tested population (the header does not list it)" comment.
- 4.2 "fewer than 6 failure codes" -> "fewer than 7 failure codes"; keep `-ge 7`, `grep -vx 1`, "both without 1".
- 4.3 Rewrite only the two false header-block sentences ("NOT covered here"; "A text parse of the case ... none is kept").
- 4.4 Recount `EXPECTED_ASSERTIONS` from a green run (estimate ~62), keep it exact.

## 5. Verify and ship

- 5.1 Run the four gates (own Bash call each; read the log before reporting a gate as running).
- 5.2 Mutation-prove every non-committed Guard Contract row in a `scripts/soleur-sandbox.sh` copy, restoring from a pristine copy, never `git checkout`.
- 5.3 `scripts/ci-pr-affected-replay.py ratchet`, `lint-infra-no-human-steps.py --changed --base origin/main`, `lint-guard-contract.py`, secret scan before every push. Never `git stash`; use the proc.sh helpers rather than process-name pattern kills.
- 5.4 PR body: first line "Merging this PR mutates no production system ..."; `Ref #10932`, `Ref #9757` only; residual 2 fixed against the live count; 3a/3b/3c closed; no sub-item dropped; accepted residues; #10932 NOT fully cleared (the `grep -vx 1` ignore and engine-owned wording remain) — ask the operator before closing it. Keep the PR DRAFT. Do not touch #11312, #11379, #10924; do not close #9757 or #10932.
