# Learning: a guard for a channel nobody feeds ships green and inert — find the producer before building the consumer

## Problem

#10194 extended untrusted-data framing to GitHub-sourced agent input. One of its three parts wrapped the third-party text that four Inngest
leader prompts interpolate (`scrubbedContent`) in an untrusted-data envelope, with tests, a mutation battery and an ADR amendment saying
the four classes "interpolate third-party text". **Nothing in production supplies `scrubbedContent`.** The only caller of
`userPromptTemplate` passes `sourceRef`, owner, repo and number, so every leader prompt renders its empty-body fallback and the envelope
frames nothing at runtime. The plan, the brainstorm, the CTO's rulings, five plan reviewers and the author's own tests all agreed it was
live, because every one of them started from the consumer (the template reads the field) and none looked for the producer.

The review panel (13 seats) found it independently five times. The same panel and the plan both missed a second surface until a late
coverage consult named it: `workstream_issues_list` returns issue titles and descriptions to the agent and was not in the issue's surface
list, because the issue's list was written from the tools its author remembered.

## Solution

- Verified the gap with one grep (`git grep scrubbedContent` outside `leader-prompts/` returned nothing), kept the envelope as a guard for a
  future feeder, and said so in the ADR, the plan and #11076 instead of letting "four leader prompts framed" stand.
- Framed the Workstream tool the same way, and added a census test (read tools plus write tools must equal the registered set).
- Reworded the shared preamble so it reads correctly in both places it is used (ahead of tool output, and as a cron system-prompt append).

## Key Insight

A guard, envelope or sanitizer on field F protects only the paths where something actually writes F. Before building one, name the PRODUCER
of F (the code that sets it) and the full set of channels that carry the same class of data, by grep over the tool and prompt definitions,
not from a surface list in an issue. A consumer-side test that fixtures F by hand will pass whether or not production ever sets it, so it
can never reveal an unfed channel. Same family as the repo's "both endpoints pinned, the wire between them is not" rule, applied one level
earlier: here the wire did not exist.

## Session Errors

1. **Leader-envelope premise unverified at plan time** (plan Phase 2 and the ADR claimed live coverage). — Recovery: review found it five times; verified by grep; disclosed. — **Prevention:** plan-time grep for the producer of any field a new guard consumes (routed to `plan-sharp-edges.md`).
2. **Surface list inherited from the issue** (missed `workstream_issues_list`; plan and first-pass panel both missed it). — Recovery: coverage consult. — **Prevention:** enumerate channels by grepping tool definitions for GitHub-text return paths, same bullet.
3. **First plan design prepended the preamble to the cron prompt**, which would have broken `/soleur:` slash-command crons and changed the single-flight key. — Recovery: caught by two plan reviewers; moved to `--append-system-prompt`. — **Prevention:** already covered by the plan's own reviewer panel; no new rule.
4. **Also cut two plan items on review** (a `cron-bug-fixer` body envelope whose premise was false because `fixIssuePrompt` takes only a number; a conversation-id hash for a field that did not exist). — **Prevention:** none needed beyond Error 1's grep.
5. **The preamble wording shipped wrong for one of its two uses** (said "The following…" as a system-prompt append, omitted advisories, and could read a legitimate user task as data). — Recovery: four seats converged; reworded. — **Prevention:** a test pins the wording properties (now in `untrusted-content.test.ts`).
6. **`vitest run $(git grep …)` with an empty match ran the ENTIRE web-platform suite**, loaded the machine, and voided the first mutation battery (its unmutated control came back red). — Recovery: killed the stray run, re-ran the battery on a quiet machine with a green control. — **Prevention:** guard empty file lists before passing them to a runner that defaults to "run everything" (routed to `work-test-harness-sharp-edges.md`).
7. **Mutation row M7 did not land** (its anchor string did not exist in the file) and reported `landed=NO`. — Recovery: the landing assertion caught it; fixed the anchor. — **Prevention:** already covered (assert each mutation landed).
8. **A regex-driven bulk rewrite also rewrote the helper's own definition** (`emitHere` became self-recursive). — Recovery: caught by reading the grep output before running. — **Prevention:** after a bulk rewrite, grep the definition site; already a known class.
9. **A test mock omitted the run-progress writers**, so the single-flight arm hit a real Supabase client. — Recovery: copied the mock from the sibling suite.
10. **The worktree directory disappeared mid-session** for a reason I did not find; all work was already pushed. — Recovery: `git worktree add` on the existing branch and reinstalled dependencies. — **Prevention:** push after each verified unit (done); cause unknown, not attributed.
11. **Hook output twice claimed the user had typed a keyword they had not.** — Recovery: ignored and said so. — **Prevention:** none; a harness-side issue.
12. **`kill_mine` was given a pattern containing `/`**, and a hook blocked `pgrep -f` twice. — Recovery: used the documented forms. — **Prevention:** hooks worked as designed.

## Tags
category: workflow-patterns
module: untrusted-content, plan, review
