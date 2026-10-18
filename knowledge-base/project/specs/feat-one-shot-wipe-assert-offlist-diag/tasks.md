# Tasks: wipe-assert rc=34 diagnostic fields

Plan: knowledge-base/project/plans/2026-10-18-feat-wipe-assert-offlist-diagnostic-fields-plan.md
Refs: #10138, #6897 (Ref only, never Closes). Dispatches nothing.

## Phase 1: RED tests first (git-data-wipe-assert.test.sh only)

- 1.1 Add `RE_34` strict regex and `line34_ok` helper; add the strict check to `expect_refuse` conditioned on BOTH expected rc and actual `$RC` being 34; add `RC34_LINES_CHECKED` counter.
- 1.2 Add shim rows A120-A131 (incident replay, unknown dir, hooks plus tenant-shaped names in one listing, hooks symlink/file/`hooks.d`/`Hooks`, lost+found entries 1 and 2, off-list plus lost+found, must-PASS allowlisted tree, rc 37 carries no new field).
- 1.3 Add four mutant rows (hooks name-only, lf_entries hard-coded 0, offlist_n uncounted, hooks:d allowlisted).
- 1.4 Add harness rows driving `line34_ok` directly (reject `has_hooks_d=2`, missing field, extra `digest=`, trailing name, reordered; accept a non-canonical good line).
- 1.5 Add loopback arm H (`repositories`, `hooks` with `pre-receive`, `lost+found`) and pin `has_hooks_d=0` in arms B, D, G; `EXPECTED_ARMS_C` 7 to 8.
- 1.6 Extend the `ssh` shim with `$TL/stderr` passthrough; add exactly one Tier B row (rc 34, exit 5, verdict word unchanged, line passed through verbatim, `grep -qxF` on a file).
- 1.7 Run the suite against the UNCHANGED script and record the new rows RED (not a crash).

## Phase 2: Script change (git-data-wipe-assert.sh)

- 2.1 `wl_classify`: reset `HAS_HOOKS=0 OFFLIST_N=0 LF_ENTRIES=0`; `if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi` before the `case`; `*)` arm also increments `OFFLIST_N`; no allowlist arm added; variables not `local`.
- 2.2 `wipe_listing`: `LF_ENTRIES="$ln"` on the line before the untouched `[ "$ln" -eq 0 ] || OFFLIST=1`.
- 2.3 Append `has_hooks_d=$HAS_HOOKS lf_entries=$LF_ENTRIES offlist_n=$OFFLIST_N` to the rc=34 `say` line; `exit 34` and its placement unchanged.
- 2.4 Update the unit Outputs comment, the "NO NAME LEAVES THE HOST" header paragraph and the verdict comment; no word from row GP.
- 2.5 Re-run the suite GREEN; set the floors (`MIN_ASSERTIONS`, `EXPECTED_INVARIANT_RUNS`, `EXPECTED_ARMS_C`, `RC34_LINES_CHECKED`) from the measured counts.

## Phase 3: Runbook (exit-34 section only)

- 3.1 Replace the final clause near line 1236 with the CLO wording (decision row L-2).
- 3.2 Add `### Reading the exit-34 line` (definitions, decode table, measured / inherited / not proven / policy labels with 2026-10-18, conditioned on the merge, follow-up issue number, no promise of a next run).
- 3.3 Update the verdict-map cell near line 1350.

## Phase 4: Hand-offs (no production mutation)

- 4.1 `gh issue create` for the `hooks:d` allowlist question (Ref #10138, Ref #6897; roadmap milestone); cite its number in the runbook.
- 4.2 Route the final strings (script line, runbook subsection, PR body) to `soleur:legal:clo`; record the verdict in decision-challenges.md.
- 4.3 PR body: `Ref #10138`, `Ref #6897`; states only the rc=34 stderr output changes and nothing was dispatched; honest note that arm H runs in CI.

## Phase 5: Local gate (focused suites only)

- 5.1 `bash apps/web-platform/infra/git-data-wipe-assert.test.sh`
- 5.2 `bash apps/web-platform/infra/git-data-wipe-access.test.sh`
- 5.3 `bash apps/web-platform/infra/git-data-cutover-access.test.sh`
- 5.4 `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- 5.5 No `test-all.sh --affected`; no `| grep -q`; CI's required test context is the gate.
