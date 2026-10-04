# Learning: a two-line credential switch, and every review round's defects lived in the verification and the runbook commands

## Problem
PR-2 of the scoped-App-token work (#9321) switched two release jobs from the broad Tier-B Doppler project to a narrow one: an optional `doppler-project` composite input, two secret references, and guards. The production change was a handful of lines. The review (12 seats, no P1, six P2, about 20 P3) found its defects almost entirely in what surrounded it:

- A comment rewritten by search-and-replace ("is the only way to the App key") became false the moment the third caller kept the broad source.
- A new comment contained the literal string a suite's presence row greps for, so the row passed with the real line deleted.
- The new guard's caller population matched one spelling of the composite path; a remote, dot-dot or wrapper-composite spelling escaped it, and the release-job `BROAD_RE` was case-sensitive.
- The runbook commands the PR added were the least-audited surface: the post-merge proof grepped a whole run log for `source=`, which matches GitHub's echo of the composite script; the rollback picked `MERGE_SHA` with a loose full-text pull-request search on the issue number, which returned an unrelated PR; the in-flight gate read a failed `gh run list` as zero; shell state does not persist between an agent's Bash calls so `REVERT_SHA` was empty in the next fence.
- Fixes for those findings introduced the next round's findings (controls that passed on an earlier "did not land" failure, a helper that treated any non-zero rc as RED).

Separately, the bootstrap itself failed once: Doppler prints `null`, not `[]`, for a config with no tokens, so `jq '.[]'` aborted and the stage read an empty list as unreadable.

## Solution
- Patched the two `jq` filters to `(. // [])`, and added a stub case emitting `null` so reverting the fix reddens a suite.
- Anchored the proof on the rendered annotation (`##[notice]app=soleur-infra`, `##[error]mint-infra-app-token:`) instead of the whole log, because GitHub echoes a composite's script body into the log.
- Looked the merged PR up directly (`gh pr view <n> --json state,mergeCommit`), made every gate fail closed on a failed listing or a non-numeric count, re-derived state at the top of each fence, and verified every fence by running it with stub `gh`/`doppler`/`git` (34 stubbed assertions) instead of reading it.
- Made guard rows name the clause that fired, gave verdict helpers must-reject controls that require the helper's own tag, and made `mutant_red` pass only on the expected rc.

## Key Insight
A change whose production diff is tiny still has a large verification surface, and the surface authored last (comments, runbook commands, the guards' own helpers, the fix commits) is audited least. Two reusable checks: (1) an operator command that derives an identifier with a loose search (`--search`, `grep` over a whole log) needs the unique lookup instead, and every gate in a runbook fence must fail closed because a failed read looks like an empty one; (2) a runbook is verified by EXECUTING its fences against stubs, never by reading them, because shell state, step names and log rendering are exactly what a read cannot see.

## Session Errors
1. **The primary checkout was one commit behind origin/main when the session started** (the brief said it was current). Recovery: `git checkout --detach origin/main`. **Prevention:** verify `HEAD == origin/main` with a fresh fetch before reporting a checkout current (already the first step of the brief; no rule change).
2. **The operator-stage approval hook refused the first apply because the session was in `bypassPermissions` mode.** Recovery: the operator switched modes and the stage was re-planned. **Prevention:** none needed, the hook's message was exact.
3. **`mint-and-store-token` failed its preflight on Doppler's `null` empty token list** — Recovery: patched the two jq filters in the PR. **Prevention:** a stub world must emit the vendor's real empty shape (`null`), not the idiomatic one (`[]`).
4. **The Edit hook blocked writing to the main checkout while worktrees existed.** Recovery: created a worktree first. **Prevention:** none, working as designed.
5. **A Bash heredoc was rejected because its text contained a Doppler secrets-delete command without `> /dev/null`, and later text containing the operator-stage `--apply` form was refused too.** Recovery: wrote the brief with the Write tool and told the fix agent the rule. **Prevention:** briefs and runbook text carrying such commands go through Write/Edit, and the runbook command itself must end `> /dev/null` with a names-only verification.
6. **A repo-wide `grep -rln` for hook registration exceeded 120 s and was moved to background.** Recovery: targeted grep on the two likely files. **Prevention:** search a named path set before the repo root (`hr-never-run-commands-with-unbounded-output`).
7. **`gh issue create` was refused by the filing hook until it carried one of three exits.** Recovery: `--label meta/machinery`. **Prevention:** none, the deny text names the exits.
8. **A review seat accidentally ran one non-target runbook fence (a `terraform init` block) while extracting fences, and another ran `git checkout --detach` in the shared worktree.** No state changed (the init failed on backend credentials; the detach was restored). **Prevention:** seat briefs that ask for fence execution must name the ONE section whose fences may run, stub `gh`/`doppler`/`git`/`terraform` on PATH, and forbid any git write in the shared worktree. Routed into `review/SKILL.md` Sharp Edges.
9. **The review panel's first fix pass introduced defects in its own fixes (false comment, self-satisfying anchor, wrong `MERGE_SHA`, fail-open gate), and a third pass was needed.** **Prevention:** already documented ("a fix commit is the least-audited surface"); the new point is to execute runbook fences against stubs before the fix round, not after.
10. **The Stop hook flagged several closing messages that stated a future action in the first person.** Recovery: closing text was restated as an explicit `<stop>` gate or the action was taken in the same turn. **Prevention:** end a turn on a tagged gate when waiting; do not write "I run X after Y" as prose.

## Tags
category: workflow-patterns
module: infra-credentials, review, runbooks
