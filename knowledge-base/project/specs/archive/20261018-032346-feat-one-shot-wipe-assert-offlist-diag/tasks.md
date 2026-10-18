# Tasks: wipe-assert rc=34 diagnostic fields

Plan: knowledge-base/project/plans/2026-10-18-feat-wipe-assert-offlist-diagnostic-fields-plan.md
Refs: #10138, #6897 (Ref only, never Closes). Dispatches nothing.

## Phase 1: RED tests first (git-data-wipe-assert.test.sh only)

- 1.1 Add `RE_34` and `line34_ok` (also enforces `offlist_n>0 || lf_entries>0`); give `expect_refuse` an optional 4th argument (exact expected tail from `top_d=`); inside a branch conditioned on BOTH expected and actual rc 34, assert `line34_ok`, increment `RC34_LINES_CHECKED` (initialised beside `INVARIANT_RUNS`) and compare the whole last stderr line.
- 1.2 Fold the exact suffix into existing rows A06, A07, A10, A12; add a no-`has_hooks_d` assertion to A20 (rc 37).
- 1.3 Add worlds A120 (incident replay), A122 (hooks + tenant-shaped dir + file, `offlist_n=3`), A123 (loop: hooks symlink, file, `hooks.d`, `Hooks`), A124 (nested `lost+found/hooks`), A129 (off-list dir + lost+found entry), A132 (valid hooks + control-character name gives rc 35, no field).
- 1.4 Add mutant rows: hooks-name-only, hooks-glob, lf-entries-zero, offlist-n-flag, hooks-allowlisted, line-leaks-name; each case requires rc 34 and the whole expected line.
- 1.5 Add harness rows driving `line34_ok` (accept `lf_entries=7 offlist_n=0`; reject `has_hooks_d=2`, a trailing token, `offlist_n=0 lf_entries=0`).
- 1.6 Add loopback arm H only (`repositories`, `hooks` with `pre-receive`, `lost+found`), full-line equality; `EXPECTED_ARMS_C` 7 to 8; arms B, D, G unchanged.
- 1.7 Extend the `ssh` shim with `SHIM_ERR` passthrough; add exactly one Tier B row asserting only the `probe-stderr:` passthrough (`grep -qxF` on a file).
- 1.8 Set floors from an UNPRIVILEGED loopback-skipped run (`MIN_ASSERTIONS`, `EXPECTED_INVARIANT_RUNS`), `EXPECTED_ARMS_C` 8 and the one-line `RC34_LINES_CHECKED` floor.
- 1.9 Run the suite against the UNCHANGED script and record the new rows RED (not a crash or unbound variable).

## Phase 2: Script change (git-data-wipe-assert.sh)

- 2.1 `wl_classify`: reset `HAS_HOOKS=0 OFFLIST_N=0 LF_ENTRIES=0`; `if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi` before the `case`; `*)` arm also increments `OFFLIST_N`; no allowlist arm added; variables not `local`.
- 2.2 `wipe_listing`: `LF_ENTRIES="$ln"` on the line before the untouched `[ "$ln" -eq 0 ] || OFFLIST=1`.
- 2.3 Append `has_hooks_d=$HAS_HOOKS lf_entries=$LF_ENTRIES offlist_n=$OFFLIST_N` to the rc=34 `say` line; `exit 34` and its placement unchanged.
- 2.4 Update the unit Outputs comment, the "NO NAME LEAVES THE HOST" header paragraph and the verdict comment; no word from row GP.
- 2.5 Re-run the suite GREEN; set the floors (`MIN_ASSERTIONS`, `EXPECTED_INVARIANT_RUNS`, `EXPECTED_ARMS_C`, `RC34_LINES_CHECKED`) from the measured counts.

## Phase 3: Runbook (exit-34 section only)

- 3.1 Replace the final clause at 'Other results that route to the CLO' with the CLO wording (decision row L-2).
- 3.2 Add `### Reading the exit-34 line` (definitions, decode table, measured / inherited / not proven / policy labels with 2026-10-18, conditioned on the merge, follow-up issue number, no promise of a next run).
- 3.3 Update the verdict-map cell in the verdict-map row for the host listing.

## Phase 4: Hand-offs (no production mutation)

- 4.1 SUPERSEDED by decision row R-8: the `hooks:d` allowlist question is tracked in place on #6897 (no new issue); the runbook cites #6897.
- 4.2 Route the final strings (script line, runbook subsection, PR body) to `soleur:legal:clo`; record the verdict in decision-challenges.md.
- 4.3 PR body: `Ref #10138`, `Ref #6897`; states only the rc=34 stderr output changes and nothing was dispatched; honest note that arm H runs in CI.

## Phase 5: Local gate (focused suites only)

- 5.1 `bash apps/web-platform/infra/git-data-wipe-assert.test.sh`
- 5.2 `bash apps/web-platform/infra/git-data-wipe-access.test.sh`
- 5.3 `bash apps/web-platform/infra/git-data-cutover-access.test.sh`
- 5.4 `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- 5.5 No `test-all.sh --affected`; no `| grep -q`; CI's required test context is the gate.
