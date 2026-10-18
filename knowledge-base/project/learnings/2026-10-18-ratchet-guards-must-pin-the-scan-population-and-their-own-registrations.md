# Learning: a shrink-only ratchet must pin the scan population, the tool configs, and its own registrations

## Problem

PR3a of #10331 added a baseline ratchet (`scripts/lint-ratchet.py`: ruff over tracked Python, eslint `no-unused-vars` over test dirs). The first cut was green (78 tests, a hand-run mutation set) and a nine-seat review still found it narrower than its property:

- the scanned population was never reconciled to the tracked population: ruff's `--force-exclude` plus its default excludes (`dist/`, `venv/`, ...) silently dropped tracked files, an undecodable file was counted as scanned while contributing nothing, and a tracked symlink was counted by the floor but dropped by the census;
- the configs that define a *finding* were mostly unpinned: `per-file-ignores`, or an eslint rule set to `off`, followed by `--update` is a legal shrink;
- fail-open defaults: `--update` ignored the floor and an unresolvable base, an unrecognised pip failure became a local SKIP, and unexpected exceptions exited 1 (the "drift" code);
- the registration (a `run_suite` line, an `ALWAYS_ON_SUITES` entry, a lefthook entry) could be deleted with everything green.

## Solution

- Add a totality check per tool: every tracked in-scope file must appear in the tool's own file list, else exit 2; a file the tool could not read is a failure, not a smaller census.
- Pin the whole parsed `ruff.toml` document and a sha256 of the eslint config; pin scope tuples, floors, marker tuples and extension lists.
- Make `--update` apply the floor and refuse when no merge base resolves; make SKIP require a *positively recognised* reachability failure; catch `Exception` in `main` so nothing unexpected exits 1.
- Pin each registration with exact-line assertions, plus one test that every guard class was loaded.
- On the fix round, run the lead's own sandbox mutation battery with one mutant per fix; the two survivors were equivalent.

## Key Insight

A ratchet is correct only for the population it scans and the rules its configs define. Count floors and green mutation batteries say nothing about either. Ask of every guard: *what set does this quantify over, and which assertion pins that set?*

## Session Errors

1. **Plan `decision-challenges.md` rows were planner-ruled or contained literal pipes.** Recovery: one batched CTO spawn plus pipe removal. **Prevention:** the technical-ruling gate caught it before `work`; no change.
2. **A local clone of the worktree into `/var/tmp` failed with a cross-device link error, and chained commands then ran in the live worktree (the lead, then an architecture seat).** Recovery: `git reset`, `git rm -f`, `unlink`, verified with `git status`. **Prevention:** use the sandbox allocator and gate every step after a clone or `cd` with `&&`; the existing review rule on allocated sandboxes already says so (a new bullet did not fit the skill body budget).
3. **New always-on suite labels had no `suite-durations.tsv` row, so only the full battery failed.** Recovery: two `floor` rows. **Prevention:** the `test-affected-paths.sh` header now says so.
4. **The Write tool turned ` ` escapes into raw separators in a regex literal.** Recovery: build the class from code points. **Prevention:** already documented in the review notes; nothing added.
5. **Hooks blocked `git stash list`, a process-pattern search and `rm -rf` on a worktree path, and one hook matched prose inside a heredoc.** **Prevention:** hooks worked as designed; write prose files with the Write tool.
6. **The full battery under load average ~34 false-failed one suite on a 120 s sandbox timeout.** Recovery: re-ran alone, 211 passed. **Prevention:** read the per-suite log before judging.
7. **ADR ordinal 289 collided with a sibling branch.** Recovery: renumbered to 290 after a cross-ref probe. **Prevention:** already a documented sharp edge.
8. **Semgrep registry packs failed once with a rule-validation error.** Recovery: retry. **Prevention:** a failed engine is never a clean result (applied).

## Tags

category: workflow-patterns
module: scripts/lint-ratchet
