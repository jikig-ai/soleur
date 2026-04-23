# Tasks — feat-one-shot-command-center-fixes

Derived from `knowledge-base/project/plans/2026-04-23-fix-command-center-tool-progress-and-github-mcp-plan.md`.

## 0. Pre-flight

- [x] 0.1. Open Code-Review Overlap check: #2225, #2224, #2220 near chat-state-machine but none touch review_gate branch or stream_end emission. No fold-in.
- [ ] 0.2. Reproduce the stuck-bubble bug locally — skipped (pipeline mode; scenario already captured in original screenshots driving this PR).
- [x] 0.3. Pre-Phase-0 gates:
  - `gh issue view 2217` → CLOSED. Ship Option A (minimal patch).
  - `rg "const _exhaustive: never"` → 6 hits; none on WSMessage union. We don't widen WSMessage, no risk.
  - `tsc --noEmit` → clean baseline.

## 1. RED — failing tests for Bug 1

- [x] 1.1. Added "stream_end on one leader preserves peer leaders" regression sentinel — passes.
- [x] 1.2. Added "review_gate transitions a thinking peer bubble to done" + "review_gate transitions a tool_use peer bubble to done" — RED as expected.
- [x] 1.3. Added "review_gate leaves already-done bubbles untouched" + "stream_end on single leader transitions to done" — pass.
- [x] 1.4. agent-runner-stream-end.test.ts deferred — integration test would require heavy SDK mocking; chat-state-machine.test.ts covers the state transition. The finally-block guard is small, commented, and defended by the success-path `!streamEndSent` guard in tandem.
- [x] 1.5. RED output captured: 2 failed, 10 passed pre-fix.

## 2. GREEN — fix terminal transitions (Bug 1)

- [x] 2.1. `chat-state-machine.ts:review_gate` transitions every in-flight bubble to `done` before clearing activeStreams.
- [x] 2.2. `agent-runner.ts` declares `streamStartSent`/`streamEndSent` locals before the try; `stream_end` emission at existing success and resume-error sites guarded with `!streamEndSent`; finally block emits fallback when `streamStartSent && !streamEndSent`.
- [x] 2.3. Re-ran vitest — 12/12 pass, 2316 total across full suite.
- [ ] 2.4. Post-merge prod smoke.

## 3. GitHub read tools (Bug 2)

- [x] 3.1. `github-read-tools.ts` with `readIssue`, `readIssueComments`, `readPullRequest`, `listPullRequestComments`. Reuses `githubApiGet`. Narrowed shapes. 10 KB issue/PR body truncation, 4 KB comment truncation, per_page clamped at 50.
- [x] 3.2. `github-tools.ts` extended with four `tool(...)` definitions; `tools[]` and `toolNames[]` arrays updated.
- [x] 3.3. `tool-tiers.ts:TOOL_TIER_MAP` has four new `"auto-approve"` entries.
- [x] 3.4. `test/github-read-tools.test.ts` covers narrowing, truncation, null-body, per_page clamp, PR-specific fields, parallel fetch merge, partial-failure fallback.
- [x] 3.5. `vitest run test/github-read-tools.test.ts` → 9/9 pass.

## 4. Agent discoverability

- [x] 4.1. `## GitHub read access` block added to `systemPrompt` inside the `owner && repo` guard in agent-runner.ts. Enumerates the four tools, when to use, body-truncation note.
- [ ] 4.2. Post-merge prod smoke.

## 5. Final verification

- [x] 5.1. `tsc --noEmit` → clean.
- [x] 5.2. `vitest run` → 2316 passed, 11 skipped (pre-existing, unrelated).
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
