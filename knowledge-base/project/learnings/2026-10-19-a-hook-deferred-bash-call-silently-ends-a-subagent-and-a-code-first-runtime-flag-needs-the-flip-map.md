# Learning: a hook-deferred Bash call silently ends a subagent, and a code-first runtime flag needs the flip map

## Problem

One PR (#10546) closed three post-incident follow-ups (a deploy-time SDK Bash smoke, the outer-wrap canary demotion, a bundle of sandbox hardening items). It was implemented by one agent per phase, reviewed by a 12-seat panel plus a 7-seat fix round, and fixed in three rounds. Two process failures cost the most time and one shipped defect was invisible to every local signal until a review seat found it:

1. **Subagents stopped with no report.** The Phase 4 implementer ended four times, and agent-native (twice), patterns and structural-enumeration review seats ended too. Each notification said "completed", the output file held only a header, and the next tool call in the transcript had no result. The cause was never in the agent's text: a settings-level PreToolUse hook (`hook_deferred_tool`, `permissionMode: auto`) defers any Bash command whose text names the operator-typed flag tooling (the flag-set-role and flag-create skill scripts, `flip.sh`). A subagent cannot approve a deferred call, so its run ends. One seat's report-writing heredoc was deferred because the report text itself named those paths. Four resumes passed before the cause was read out of the transcript.
2. **A new runtime flag was wired in code but missing from the flip tool's map.** `agent-sandbox-unix-deny` was added to `RUNTIME_FLAGS`, `.env.example` and the resolver, but not to `FLAG_ENV_VARS` in the flag-set-role flip script. `plugins/soleur/test/flip-flag-map-parity.test.sh` (a different shard from every suite that covers `server.ts`) went red, and the documented flip and rollback command would have exited "unknown flag". The implementer was told to do everything the flag-create skill prescribes except the typed write, and neither create mode adds the map entry for an already-wired flag.

## Solution

1. Diagnose a silent seat stop in one command: `jq -c 'select(.type=="attachment") | select(.attachment.type=="hook_deferred_tool") | .attachment.toolInput.command' <agent output file>`. Then brief every seat and fix agent to read those files with the Read tool, write reports with the Write tool, and keep the tooling names out of Bash commands. After the briefing was corrected, the remaining 7 fix-round seats and 3 fix agents all delivered.
2. Add `["agent-sandbox-unix-deny"]="FLAG_AGENT_SANDBOX_UNIX_DENY"` to the flip map; the parity suite passes (15 flags). The flag-create skill now says a code-first `RUNTIME_FLAGS` entry also needs the map entry.

## Key Insight

A silent subagent stop is not a model failure to be resumed around; it is usually a deferred tool call, and the transcript says which one. Separately, a verification that is selected by files (the suites that reference the changed file) cannot see a repo-global parity ratchet that lives in another shard: the flip-map suite references neither `server.ts` nor the new flag, so only a review seat running it, or the CI shard that contains it, could catch the omission.

## Session Errors

1. **Planning subagent interrupted by a session end.** Recovery: resumed once via SendMessage; the on-disk skeleton plan was completed in place. **Prevention:** the plan-artifact recovery rule already covers this (select the plan by `branch:`, test for `## Acceptance Criteria`); no change.
2. **Phase 3 implementer killed by an API 429.** Recovery: resumed after the limit reset; five commits were already in. **Prevention:** commit per logical unit (already the rule) so a kill loses nothing.
3. **Phase 4 implementer and four review seats ended with no report (hook-deferred Bash).** Recovery: transcript diagnosis, then a Read/Write-tool briefing. **Prevention:** added to `review/references/risk-tier-and-fix-rounds.md` "Briefing fix agents and seats" with the jq diagnosis.
4. **"125 files" cited as the branch size to justify cutting Phase 5.** It came from a two-dot diff against a stale local `origin/main`; the real count was 74. Caught by the data-integrity seat. Recovery: corrected in decision-challenges and tasks. **Prevention:** the review skill already says "three-dot diffs only"; the miss was my own measurement before any gate. Measure a size claim with `git diff --name-only $(git merge-base origin/main HEAD) HEAD | wc -l` and write the command next to the number.
5. **New runtime flag missing from the flip map (red parity suite).** Recovery: one map line. **Prevention:** `flag-create` SKILL.md bullet (above).
6. **Merge conflict with `origin/main` in `scripts/test-all.sh` surfaced at review time.** Recovery: kept main's new `run_suite` and the branch's removal. **Prevention:** the review skill's Step 1 `merge-tree` check caught it before the panel; no change.
7. **Ruling-gate shape failures (3 rows) on the first gate run.** Recovery: rewrote the rows to `Ruled by CTO agent, <date>: <decision> - <rationale>` and used the closed category list. **Prevention:** none beyond the gate itself.
8. **`gh` run from a non-git directory failed, and the unguarded `;` after a failed `&&` chain left an empty body file that `gh issue edit` would have written to tracker #10548.** Caught by a read-back before any damage (the edit also failed on the same error). **Prevention:** run `gh` from the repo root; never put a body-file consumer after a `;` that follows a redirected producer, chain with `&&` and verify the file is non-empty.
9. **`scripts/test-all.sh --affected` refused (rc=4) on every attempt** (sibling worktrees running full gates; a removed `run_suite` line degrades selection to full). Recovery: targeted suites per fix; the CI shards are the authoritative gate. **Prevention:** none local; existing contention guidance holds.
10. **`ci-deploy.test.sh` flaked locally under concurrent runs.** Root cause found by the test-design seat: fixed `/tmp/canary-*` probe paths in `ci-deploy.sh` collide across concurrent suite runs. Fixed by `CANARY_PROBE_TMPDIR`.
11. **A fix agent died on `EAI_AGAIN` mid-run.** Recovery: resumed; state recovered from `git status`. **Prevention:** commit before long verification runs (already the rule).

## Tags
category: workflow-issues
module: soleur:review, soleur:work, soleur:flag-create
