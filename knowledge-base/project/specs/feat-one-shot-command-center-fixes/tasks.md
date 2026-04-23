# Tasks — feat-one-shot-command-center-fixes

Derived from `knowledge-base/project/plans/2026-04-23-fix-command-center-tool-progress-and-github-mcp-plan.md`.

## 0. Pre-flight

- [ ] 0.1. Run Open Code-Review Overlap check:
  - `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`
  - For each of `apps/web-platform/server/agent-runner.ts`, `apps/web-platform/lib/chat-state-machine.ts`, `apps/web-platform/server/github-tools.ts`, `apps/web-platform/server/tool-tiers.ts`, `apps/web-platform/server/ci-tools.ts`: run `jq -r --arg path "<file>" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`.
  - For each match: fold-in OR acknowledge OR defer. Record in the plan's Open Code-Review Overlap section.
- [ ] 0.2. Reproduce the stuck-bubble bug locally. Start `cd apps/web-platform && doppler run -p soleur -c dev -- ./scripts/dev.sh`. Open `/command-center`. Ask "resume work on issue 2831". Screenshot the stuck "Working" chips. Save to `knowledge-base/project/specs/feat-one-shot-command-center-fixes/before.png`.

## 1. RED — failing tests for Bug 1

- [ ] 1.1. Add test "parallel-leader stream_end isolation" to `apps/web-platform/test/chat-state-machine.test.ts`. Expected: may already pass (sentinel).
- [ ] 1.2. Add test "review_gate preserves peer bubbles" to same file. Expected: RED.
- [ ] 1.3. Add test "tool-final turn regression sentinel" to same file. Expected: pass.
- [ ] 1.4. (Optional) Add `apps/web-platform/test/agent-runner-stream-end.test.ts` with exception-path scenario. Expected: RED after Phase 2 unless mocked out.
- [ ] 1.5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-state-machine.test.ts test/agent-runner-stream-end.test.ts`. Capture RED output.

## 2. GREEN — fix terminal transitions (Bug 1)

- [ ] 2.1. Edit `apps/web-platform/lib/chat-state-machine.ts:review_gate` branch. Iterate `activeStreams`; for each leaderId, set its bubble `state: "done"`. Then clear the map. Keep `timerAction: "clear_all"`.
- [ ] 2.2. Edit `apps/web-platform/server/agent-runner.ts`. Track `streamStartSent` and `streamEndSent` booleans. Move `stream_end` emission into a post-loop block that fires whenever `streamStartSent && !streamEndSent`, including on exception paths.
- [ ] 2.3. Re-run the vitest commands from 1.5. Confirm all previously RED tests pass. No prior green tests regress.
- [ ] 2.4. Manually re-run the repro from 0.2. Screenshot the `done` checkmark on all bubbles. Save to `knowledge-base/project/specs/feat-one-shot-command-center-fixes/after.png`.

## 3. GitHub read tools (Bug 2)

- [ ] 3.1. Create `apps/web-platform/server/github-read-tools.ts` with `readIssue`, `readIssueComments`, `readPullRequest`, `listPullRequestComments`. Reuse `githubApiGet` from `github-api.ts`. Narrow response shapes. Truncate issue/PR `body` at 10k chars with `…(truncated, use html_url for full)`.
- [ ] 3.2. Extend `apps/web-platform/server/github-tools.ts` with four `tool(...)` definitions. Update `tools` and `toolNames` arrays. Names: `github_read_issue`, `github_read_issue_comments`, `github_read_pr`, `github_list_pr_comments`.
- [ ] 3.3. Extend `apps/web-platform/server/tool-tiers.ts:TOOL_TIER_MAP` with four `"auto-approve"` entries under the new names.
- [ ] 3.4. Extend `apps/web-platform/test/github-tools.test.ts` (create if absent) with unit tests for the four tools. Mock `githubApiGet`. Assert narrowed shape + isError on REST failure.
- [ ] 3.5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-tools.test.ts`. All green.

## 4. Agent discoverability

- [ ] 4.1. In `apps/web-platform/server/agent-runner.ts` inside the `installationId && repoUrl` guard, append a `## GitHub read access` section to `systemPrompt`. Describe: tools available (the four new ones), when to use (resume from issue, summarize PR review, follow up on CI failures), scoping (connected repo only).
- [ ] 4.2. Manual smoke: start a Command Center session. Ask "read issue 2831 and summarize". Verify agent invokes `github_read_issue` (not `gh`). Attach transcript to PR.

## 5. Final verification

- [ ] 5.1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Clean.
- [ ] 5.2. `cd apps/web-platform && ./node_modules/.bin/vitest run`. All green.
- [ ] 5.3. Skill: soleur:compound. Capture any session learnings.
- [ ] 5.4. Skill: soleur:review (multi-agent review) on the PR branch.
- [ ] 5.5. Skill: soleur:ship with labels `type/bug`, `priority/p1-high`, `domain/engineering`, and `semver:minor` (or `patch` if the github-read tools are deferred).

## 6. Follow-up issues (BEFORE session ends)

- [ ] 6.1. `gh label list --limit 100 | grep -iE "deferred-scope-out|type/feature|domain/engineering|domain/product"` — verify all label names exist.
- [ ] 6.2. `gh issue create --title "[deferred] Evaluate installing gh CLI in runner Dockerfile as fallback to MCP-only GitHub access" --label deferred-scope-out --label domain/engineering --milestone "Post-MVP / Later" --body-file -`. Body includes `## Scope-Out Justification` per `rf-review-finding-default-fix-inline`.
- [ ] 6.3. `gh issue create --title "[feat] Web UI Command Center — single-leader default auto-routing with on-demand escalation" --label type/feature --label domain/product --milestone "Post-MVP / Later" --body-file -`. Body covers cost concern (~$0.44 double-turn), double-bubble UX, proposed UX (primary + @-mention escalation), acceptance criteria.
- [ ] 6.4. `gh issue create --title "[feat] Web UI Command Center should delegate to /soleur:go skill instead of re-implementing brainstorm/one-shot/work inline" --label type/feature --label domain/engineering --milestone "Post-MVP / Later" --body-file -`. Body references agent-native-architecture principle + `plugins/soleur/skills/go/SKILL.md`.
- [ ] 6.5. Verify all three with `gh issue view <N> --json number,title,state,labels,milestone`.

## 7. Post-merge

- [ ] 7.1. Skill: soleur:postmerge. Verify deploy webhook success.
- [ ] 7.2. Production smoke-test: open `/command-center`, resume a real conversation, verify bubble terminal states. Attach screenshot.
