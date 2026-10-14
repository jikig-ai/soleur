---
synced_to: [brainstorm]
---

# Learning: a research agent named the hosted app as the self-hosted surface, and agent-written docs reached CI unlinted

## Problem

Three defects from one session shared a root: a check or claim was taken on the strength of how it read, not on what it measured.

- **Wrong surface.** In the #9577 and #9578 brainstorms the repo-research agent was asked which states a homepage demo could truthfully show to self-hosted users. Its report listed the hosted app's engine statuses (`apps/web-platform/server/agent-engine-dispatch.ts`) under "Self-Hosted Plugin Pipeline", described drift guards that do not match the test file, and for #9578 proposed a new agent, a new workflow edge and a web-app schema field that the issue itself rules out ("extend the plan-phase acceptance field, do not build a new engine"). The CPO and CTO reports, which named the right surface, disagreed with it. The disagreement was the tell.
- **Unlinted agent-written docs.** PR #9584 added two audit files written by the CLO agent. Required check `markdown-lint` failed on them (bare URLs, a list without a blank line), which cost a ~90 minute CI cycle after the PR was otherwise ready. The lint scope excludes `knowledge-base/project/` but not `knowledge-base/legal/`, so the files were in scope and nobody ran the lint before pushing.
- **A lint result that was not one.** Linting a learning file under `knowledge-base/project/` printed the CLI's usage text and `lint_rc=0`. The exit code was `tail`'s, and the usage text meant `.markdownlintignore` had filtered out every input, so nothing was linted.

## Solution

- For any "which surface emits X" question (self-hosted plugin versus hosted app), name the surface in the research prompt, and reconcile the report against the leaders' reports before it bounds scope. A claim attributing a file under `apps/web-platform` to the self-hosted pipeline is wrong on its face: that directory is the hosted app.
- Before pushing a diff that adds Markdown outside `knowledge-base/project/`, run `bash scripts/markdown-lint.sh --repo-sweep`. It reads the same scope file as CI. A `.md` file written by a delegated agent counts as a diff you did not author, which is the case most likely to carry lint errors.
- A linter that prints usage and exits 0 on a path you gave it has found nothing to lint. Check the scope file before treating that as a pass, and write `cmd; rc=$?` with nothing between.

## Key Insight

When two reports about the same thing disagree, the disagreement is the finding, not noise to average. Each of the three defects was visible one step earlier as a mismatch (a file path in the wrong tree, a scope file naming the directory, an exit code that came from a different command) and each was resolved by reading the surface that was actually measured.

## Session Errors

**Ended a turn on `<promise>DONE</promise>` while a queued PR was unmerged and the requested brainstorms were not started.** Recovery: the stop hook flagged the unkept promise; retracted DONE, checked the PR and started the brainstorms. Prevention: emit the completion promise only when every PR the pipeline queued is MERGED and every item the user listed is done.

**Treated a red, non-required `CodeQL` check as not mattering.** Recovery: the post-merge alert gate filed #9625; fixed in #9629. Prevention: read a failing check's rule and location before queueing merge, whether or not it is required (see the CodeQL learning from #9629).

**Agent-written audit files failed the required `markdown-lint` check.** Recovery: `markdownlint --fix` on both files, one extra CI cycle. Prevention: run the repo-sweep lint before pushing a diff that adds Markdown outside `knowledge-base/project/`.

**Read `lint_rc=0` and a usage dump as a lint result.** Recovery: found that `.markdownlintignore` excludes `knowledge-base/project/`. Prevention: check the scope file when a linter prints usage; capture `rc` immediately after the command.

**Wrote an invented third entry into a learning's Session Errors list.** Recovery: removed it before commit. Prevention: every Session Errors entry must correspond to an event in the transcript; delete a placeholder rather than fill it.

**A review seat said a fixture covered mixed case; it did not.** Recovery: read the fixture, then pinned upper and mixed case. Prevention: verify a seat's claim about a file against the file.

**A research agent misattributed the hosted app's statuses to the self-hosted pipeline.** Recovery: cross-checked against the CPO and CTO reports and recorded a reconciliation note in the brainstorm. Prevention: as above.

**A phrase in the brainstorm document came out garbled ("the CTO-of-the-test").** Recovery: corrected before commit. Prevention: re-read a generated summary paragraph once before writing it to a committed file.

## Tags

category: workflow-issues
module: brainstorm, ship, review
