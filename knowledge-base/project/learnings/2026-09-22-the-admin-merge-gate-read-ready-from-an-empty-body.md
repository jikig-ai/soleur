---
title: The admin-merge gate read "ready" from an empty body, and its wiring lint was a sample
date: 2026-09-22
category: workflow-issues
module: ship
tags: [guard-vacuity, fail-open, admin-merge, required-checks, review]
issue: 8500
pr: 8547
---

# Learning: the gate built to stop a vacuous "all green" shipped its own vacuous "all green"

## Problem

#8500 asked for one script, `plugins/soleur/scripts/admin-merge-ready.sh`, that proves every
ruleset-required check is PRESENT and green on the exact head before any `gh pr merge --admin`,
because #8458 merged with 25 of 26 required contexts green and the aggregate `test` context not
yet created. The first implementation iterated the required set (the right fix for #8458) and
then decided readiness as **"the classifier named no non-green context"**. That is the #8458
shape one layer down: an empty or unparseable API body classifies nothing, names nothing, and
reads `verdict=ready`, exit 0. The security seat reproduced it with a zero-byte `runs.json` and
with an empty `files.json` (which also skipped the untrusted-CI refusal).

The same PR's wiring lint had the sibling defect: its population was a SAMPLE -- two directories,
`*.md`/`*.sh` only, the literal single-spaced `gh pr merge`, and a `--match-head-commit` check a
trailing `# comment` satisfied. The structural-enumeration seat listed ten one-line edits that add
an unguarded admin merge the lint could not see.

## Solution

- **Decide readiness positively.** The classifier emits a `green` count and the script returns 0
  only when `req > 0 && green == req && no culprit lines`; every API body is shape-checked
  (`jq -e`) before it is read, and a zero-count-but-no-culprit result is an ERROR, not ready.
- **Skipped/neutral is only as good as its suite:** a required context skipped while a dependency
  in the same check suite is being RE-RUN is PENDING, not green (latest-per-name `in_progress`
  sibling), and FAILED if a sibling concluded red.
- **Restrict to `head_sha`, refuse unknown ruleset rule types** (`workflows`, `code_scanning`, ...
  are bypassed by `--admin` too), refuse an incomplete PR file list (`changedFiles` mismatch or
  the 3000-file cap), pin the base, and give stale its own exit code (4) so callers branch on the
  exit code rather than parsing output.
- **Never print PR-controlled strings.** A newline in a `.github/workflows/` filename forged a
  `SOLEUR_ADMIN_MERGE_READY verdict=ready` line in the Monitor stream; the refusal now prints a
  count.
- **The merge block reads success only from the PR state** (`MERGED` at `$SHA`), including after a
  non-race merge error, and passes the readiness exit code through.
- **The lint's population is derived** (every text file under `plugins/soleur`, whitespace-tolerant,
  flags matched as tokens after stripping a trailing shell comment), requires the gate before EVERY
  admin merge, forbids API-level merges, and each W row asserts the VIOLATION it expects.

## Key Insight

A gate whose verdict is "nothing bad was named" is satisfied perfectly by an instrument that looked
at nothing -- and the PR that exists to remove that shape from one layer reliably reintroduces it in
the next, because the author is holding the old layer in mind. Ask of every readiness/health
verdict: **what does it print when every input is empty?** If the answer is the green verdict, the
gate needs a positive count.

## Session Errors

1. Planning (forwarded): functional-discovery skipped; a docs-researcher CodeQL finding came from a
   commit with no check runs; the skipped/neutral doc was not found at plan time.
   **Prevention:** fetch vendor docs from the docs repo's raw markdown
   (`raw.githubusercontent.com/github/docs/main/content/...`) when the rendered site 404s.
2. The first `git commit` streamed the whole lefthook output into context.
   **Prevention:** redirect every commit to a log and read the tail.
3. The ugrep `grep` shim rejected `--include=*.md`. **Prevention:** use `git grep` or `/usr/bin/grep`.
4. The `TEST_GROUP=scripts` gate was REFUSED (rc=4, sibling full-gate run), then sat on the lock
   >15 min and was killed twice before later edits. **Prevention:** run `--capacity` first; finish
   all edits (review fixes, compound) before launching the one gate run.
5. A report-only review seat ran `git merge --no-commit` in the shared worktree (aborted cleanly).
   **Prevention:** give read-only seats `isolation: "worktree"` when they may probe merges.
6. `fixture-relative-assert` would have reddened CI on 10 unguarded redirects, then read `>>`/`<N>`
   inside quoted string literals as redirects. **Prevention:** run that ratchet on any new
   `*.test.sh` before its first commit; write stub bodies with quoted heredocs.
7. Both suites' floors used `-ne`, invisible to `guard-vacuity-floor`. **Prevention:** copy
   `sync-pr-behind.test.sh`'s tail (literal `-lt` floor, separate conservation and ledger checks).
8. Readiness decided negatively (empty body = ready). **Prevention:** the Key Insight above.
9. `case_mutant` credited a crashing mutant as a kill. **Prevention:** each mutation row names the
   defect the mutant must exhibit, checked after the row fails.
10. The wiring lint's population was a sample. **Prevention:** derive the population from the tree
    with a whitespace-tolerant, comment-stripped, token-level match, and plant one violation per
    axis (directory, extension, spacing, comment, split line, order).
11. The reference claimed a merge queue can make `--admin` "only enqueue"; this repo has no merge
    queue and `--admin` bypasses one. **Prevention:** check `infra/github/*.tf` and `gh <cmd> --help`
    before writing a rationale about vendor behaviour.
12. Rewritten suites failed on `env` not finding `timeout`/`bash` under a restricted PATH.
    **Prevention:** resolve tool paths (`command -v timeout`, `$BASH`) before narrowing PATH.
13. shellcheck SC2100 on an unquoted hyphenated assignment. **Prevention:** quote string literals.
14. A pre-existing MD032 in a touched learning blocked the markdown lint. **Prevention:** lint every
    touched `.md` before committing.
15. Two mutation rows became equivalent after the positive-readiness fix. **Prevention:** re-derive
    every mutation row after strengthening a predicate (label survivors fixture-gap vs equivalent).
16. A `TaskStop` call omitted `task_id`. **Prevention:** none needed (one-off).
