# Decision Challenges - feat-one-shot-12362-stall-triage-headsha

The technical forks in this work were ruled by the CTO agent (one before planning started, one at
review); no operator question is open. `soleur:ship` renders this table into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Lift the E2 hold (issue-body template kept byte-identical in the previous stall-check PR, merged as 10e66d9ab8) so the headSha field can be added in a separate PR for #12362 | technical | Ruled by CTO agent, 2026-11-08: E2 lifted, add the test assertion, delete the follow-through probe, remove the follow-through label post-merge - the hold applied only to the earlier PR, and a membership assertion plus probe retirement closes the gap with no template change beyond one field |
| Review found three sibling files that print the same `gh run list --event merge_group --json databaseId,headBranch,conclusion,url` command next to prose saying to correlate by headSha/createdAt (`plugins/soleur/scripts/monitor-pr-checks.sh`, `plugins/soleur/scripts/sync-pr-behind.sh`, `plugins/soleur/skills/drain-prs/SKILL.md`); widen this PR to them or file a follow-up | technical | Ruled by CTO agent, 2026-11-08: widen this PR - three one-token edits (`headSha` right after `headBranch`), no wording or `--jq` change, no edit to `merge-queue-dequeue.md` (it makes no headSha claim); run the sibling suites on the unedited tree first, then after, and fall back to one `deferred-scope-out` issue only for a script whose suite cannot be fixed inline in the same edit |
