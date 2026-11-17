# Learning: a negative claim handed to the CTO came from a windowed regex, and the guard's first mutation row never reached the new arm

## Problem

PR #12378 (closes #12362) added `headSha` to the merge-queue stall issue's Triage step 2 `gh run list --json` list, with a membership guard in `plugins/soleur/test/merge-queue-stall-check.test.sh` and the retirement of the follow-through probe that existed only to nag until the gap closed. The nine-seat review panel found that three other files print the same command next to prose telling the reader to correlate by `headSha`/`createdAt`, and the CTO widened the PR to them. Four things went wrong on the way, all caught, none by the author:

1. **A negative claim in a ruling request was wrong.** I verified a fourth candidate file, `merge-queue-dequeue.md`, with `grep -aoE '.{110}headSha.{90}'`. The claim ("correlate ... by `headSha`/`createdAt`") sits near the end of a long line with fewer than 90 characters after it, so the regex returned nothing and I wrote "it makes no headSha claim" into the request. The CTO's binding condition "do not edit that file" rested on it. An architecture seat traced the file independently and falsified the premise; the CTO then lifted the condition.
2. **The planned mutation row MT3 (break the selector) never exercised the new code.** The older `agent-runnable` check at the top of `structural_check` returns first, so the row was killed by the wrong arm, and the new arm's "zero members" branch was unreachable. Five seats reported it.
3. **A header sentence shifted a line that another file cites by number.** `scripts/lib/test-affected-paths.sh:594` cites `merge-queue-stall-check.test.sh:14`; my 3-line header addition moved that line to 17. The verifier found it.
4. **Editing one printed message re-keyed ratchet accept rows.** The `sync-pr-behind.sh:570` line names `merge-queue-dequeue.md`; changing it changed its anchor hash, so two accept rows went `stale-accept`, and the rewritten row then failed `accept-bad-kind` until its reason used a typed kind.

## Solution

- Dequeue recipe: one-token edit, pure insertion verified against the committed file, plus a second CTO ruling recorded in `decision-challenges.md` (append-only: the old row stays, the new row supersedes one condition).
- MT3 became a left-extended lookalike (`xheadSha`), which a right-boundary-only membership test survives; the pass floor stayed 166. The three jq checks share one `local sel`; REASON strings name only what is measured.
- The header sentence moved to a new item 4 after item 3, so lines 2 and 14 are where the citation says.
- The two accept rows were re-keyed to the new anchor (`7b7d1b90e86f`); the rewritten reason carries the typed kind `message: <file:line>`.
- Verified by commands: suite 166/0, ratchet `--base origin/main` `exit=0 reason=pass live=0`, sibling suites identical before and after (276 / 1155 / 71 / all-pass), `git grep` of the old list returns nothing outside `knowledge-base/`.

## Key Insight

A negative about a document ("it makes no X claim") needs the same standard as a positive: a count over the WHOLE file with a positive control, never a context-window regex. `risk-tier-and-fix-rounds.md` already says a negative about a doc is not evidence of absence (its `cut -c1-300` example); the instance here used a different instrument (`.{110}x.{90}`) and walked straight past that rule. The cost was a binding ruling built on my premise, found by luck of an independent seat. Put the command AND its output in the ruling request, so the CTO can see what was measured.

The second lesson is the usual one for guard rows: for every mutation row ask which arm fires, not whether something fires. A new arm added after an older arm in the same function is shadowed by it for every input the older arm rejects, so a row that breaks that input tests the old arm again. Drive the row against the function with the new arm deleted: if it still reds, it covers nothing new.

Two smaller ones: cite a line by a content anchor, not a number (the citation in `test-affected-paths.sh` is still a number, so the fix was to keep the cited line fixed), and a ratchet that keys accept rows on a hash of the referring line will go stale on any edit to that line, including a one-token change.

## Session Errors

1. **`git stash list` in a Bash call (hook blocked it; nothing ran)** — Recovery: re-ran without it. **Prevention:** none needed; the guard hook worked. Do not add stash subcommands, even read-only ones, to a compound Bash command.
2. **Foreground run of a ~10 minute suite under `timeout 580`** — Recovery: detached launch with an rc file and a Monitor. **Prevention:** a suite with a known ~10 minute runtime is always launched detached with an rc file (already the documented pattern).
3. **A duplicate Monitor on one target** — Recovery: stopped the second. **Prevention:** one Monitor per target; the supersede hook names the earlier one.
4. **The combined affected gate ended `rc=6` (budget-deferred behind sibling sessions)** — Recovery: recorded as not run, ran the directly relevant suites by name, left CI as the authority. **Prevention:** none beyond the documented rc contract; never label an rc 6 as a pass.
5. **Told the CTO a file "makes no headSha claim" from a windowed regex** — Recovery: re-verified with a whole-line search, took the architecture seat's finding to the CTO, which lifted its condition. **Prevention:** before a negative about a file goes into a ruling or a brief, run `grep -c` on the exact token over the whole file with a positive control, and quote the command and its output in the request.
6. **First ad-hoc driver for the bare-token control printed nothing, even for the unmutated control** — Recovery: noticed the empty control, found the suite derives `REPO_ROOT` from its own path, overrode that one line in the sandbox copy. **Prevention:** run the unmutated control first and treat an empty control as a broken instrument (it was).
7. **markdownlint run directly over `knowledge-base/project/`** — Recovery: the repo's gate is `scripts/markdown-lint.sh`, which honours `.markdownlintignore` (that tree is excluded by design); it was clean. **Prevention:** run a repo's own lint script, not the underlying tool.
8. **Header edit shifted a line cited by `test-affected-paths.sh` as `:14`** — Recovery: moved the sentence to a separate item after item 3. **Prevention:** before adding lines to a file's header, `grep -rn '<basename>:[0-9]' scripts/ plugins/ .claude/` for citations into it.
9. **Editing a printed message re-keyed two ratchet accept rows (stale, then bad-kind)** — Recovery: re-keyed both rows, typed the reason. **Prevention:** when an edit touches a line that names another file, run the ratchet with `--base origin/main` before committing; read its remedy text first.
10. **The planned MT3 was shadowed by an older arm** — Recovery: replaced it. **Prevention:** drive every new mutation row against the function with the new arm removed; if it still reds, it tests the old arm.
11. **A seat's "stale #11681" claim came from a shallow-clone graft** — Recovery: re-checked with `GIT_SHALLOW_FILE=/nonexistent/none`; the plan was right. **Prevention:** in this clone, archaeology that depends on the first commit that introduced a string needs the shallow-file override.

## Tags

category: workflow-issues
module: ci-guards, merge-queue, review-process
