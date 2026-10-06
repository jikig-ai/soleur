# Tasks: fix(go): session-start .mcp.json restore overwrites a dirty tracked file

Plan: `knowledge-base/project/plans/2026-10-06-fix-go-session-start-mcp-json-dirty-restore-plan.md`
Issue: #9622. Do not touch the primary checkout's `.mcp.json`; all behavior is exercised in `mktemp` fixture repos.

## Phase 1: RED (test file only)

- [ ] 1.1 Add `mode` parameter to `mk_workspace` in `plugins/soleur/test/go-session-gates.test.sh`
  - [ ] 1.1.1 `dirty` (default, unchanged: tracked, dirty vs `HEAD`) with a loud comment that a row wanting the restore must use `stale`
  - [ ] 1.1.2 `stale` mode: commit main's file on `main`, `checkout -b feat`, commit a different `.mcp.json`, leave the worktree clean
  - [ ] 1.1.3 `fresh_ws <name> [mode]` passes the mode through
- [ ] 1.2 Re-point five rows at `stale`: R3 (R1/R2/R3 loop), R3e, R3f, R3g, R11
  - [ ] 1.2.1 Delete the explicit `printf '{"fixture":"DIRTY"}'` writes in R3e and R11
  - [ ] 1.2.2 Update the two comments that justified those writes
- [ ] 1.3 Add the R12 section after R11c and before R6 (each parent-shell `git -C "$ws"` write guarded by `: "${ws:?...}"` and the `git_fixture_env` subshell form)
  - [ ] 1.3.1 R12: default fixture, success arm: content unchanged, marker present, no `.soleur-tmp`, `cleanup-merged` still dispatched
  - [ ] 1.3.2 R12b: staged-only edit: content unchanged, marker present
  - [ ] 1.3.3 R12c: capability-refusal arm (`NOCAP_ROOT`): content unchanged, marker present
  - [ ] 1.3.4 R12d: classifier-absent arm (`CLASSLESS`): content unchanged, marker present
  - [ ] 1.3.5 R12e: `stale` + untracked (`git rm --cached` + commit): content restored to main (1 assertion)
  - [ ] 1.3.6 R12f: two bare unborn repos (`assert_fixture_dir` + `git_fixture_env`): staged -> marker `mcp-json-dirty` + content unchanged; untracked -> no dirty marker, `mcp-json-no-local-main` present (4 assertions)
  - [ ] 1.3.7 R12h: `stale`, run the gate twice: run 1 refreshes to main; run 2 prints no `mcp-json-dirty` and bytes still equal main (3 assertions)
  - [ ] 1.3.8 R12i: default fixture + `git update-index --skip-worktree`, edited: content unchanged, marker present (2)
  - [ ] 1.3.9 R12j: `stale` + untracked (`git rm --cached` + commit), then `.mcp.json` replaced by a symlink to a differing scratch file: still a symlink, target unchanged, marker present (3)
  - [ ] 1.3.10 R12g: `stale` + `mkdir .mcp.json.soleur-tmp`: `mcp-json-read-failed rc=1`, no dirty marker (pins `SHOW_RC=$?`)
- [ ] 1.4 Run `SOLEUR_GO_GATES_SKIP_H3=1 bash plugins/soleur/test/go-session-gates.test.sh`; confirm R12, R12b, R12c, R12d, R12f (marker assertion), R12i, R12j RED, R12h's second run RED (marker prints under the old code), and R12g, R12e and the re-pointed rows GREEN and the re-pointed rows still GREEN against the old go.md

## Phase 2: GREEN (go.md restore block only)

- [ ] 2.1 Insert the `KEEP` computation (symlink; tracked and not a plain cached entry (`ls-files -v` tag other than `H`) or dirty vs `HEAD`) and turn the first restore condition into `if [ "$KEEP" = true ]; then <silent when equal to main, else echo marker>; elif git show main:.mcp.json > .mcp.json.soleur-tmp ...; then`, leaving the inner `mv` and the `else` (with `SHOW_RC=$?`) untouched (snippet in the plan, Phase 2)
- [ ] 2.2 Reword the fence-internal comment that calls `.mcp.json` untracked
- [ ] 2.3 Update the one prose sentence after the fence ("refresh is harmless inside a worktree")
- [ ] 2.4 Confirm no hunk touches a `# --- soleur plugin-root resolver` region and no bash fence was added

## Phase 3: floors, baselines, sweep

- [ ] 3.1 Raise `MIN_ASSERTIONS` to the value measured with `SOLEUR_GO_GATES_SKIP_H3=1` (expected 219: 4+2+2+2+1+4+2+3+2+3 new assertions) and update its comment
- [ ] 3.2 Run `fixture-relative-assert.test.sh` and regenerate its baseline with `--write-baseline` (expected to move); run `fixture-dir-operand-assert.test.sh` and `fixture-env-adoption.test.sh`, regenerating only if they move
- [ ] 3.3 Run `go-routing-table-parity.test.sh`, the five bun suites named in the plan, and `plugin-root-anchoring.test.ts` under vitest
- [ ] 3.4 One H3 real-harness run if `claude` is on PATH
- [ ] 3.5 Run each mutation row from the plan's Guard Contract against the finished suite and record RED/GREEN
- [ ] 3.6 Confirm the primary checkout's `.mcp.json` hash is unchanged
- [ ] 3.7 PR body: `Closes #9622`, `## Changelog` (`semver:patch`), one sentence on why five existing rows changed, a note to re-measure `MIN_ASSERTIONS` after any rebase, and a pointer to `decision-challenges.md`
