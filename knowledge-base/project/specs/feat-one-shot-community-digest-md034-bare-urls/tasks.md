# Tasks — fix: Render community digest URLs as markdown links (MD034)

Plan: `knowledge-base/project/plans/2026-10-06-fix-community-digest-md034-bare-urls-plan.md`
Branch: `feat-one-shot-community-digest-md034-bare-urls`

## Phase 1 — Failing tests first (RED)

- [ ] 1.1 In `apps/web-platform/test/server/inngest/cron-community-publication.test.ts`, rewrite
  the "carries the handler-constant click-through lines derived from repo" test (~line 788) to pin
  the exact compliant lines:
  - `digestMarkdown` contains `Review inbound items: [issues](https://github.com/jikig-ai/soleur/issues) and [pull requests](https://github.com/jikig-ai/soleur/pulls)`
  - `issueBody` contains `Inbound items: [issues](https://github.com/jikig-ai/soleur/issues) and [pull requests](https://github.com/jikig-ai/soleur/pulls)`
  - `issueBody` contains `Digest file: [<RUN_DATE>-digest.md](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/support/community/<RUN_DATE>-digest.md)`
  - NEW negative assertion: `expect(digestMarkdown).not.toMatch(/(?<![(<` + backtick + `])https?:\/\//)` and the same on `issueBody` (lookbehind set: `(`, `<`, backtick, `[`).
- [ ] 1.2 Update `cron-community-publication.test.ts` ~line 996: `"Inbound items: https://github.com/jikig-ai/soleur/issues"` → `"Inbound items: [issues](https://github.com/jikig-ai/soleur/issues)"`.
- [ ] 1.3 Update `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts` line 151 (inside `expectNoticeBody`): `"Inbound items: https://github.com/"` → `"Inbound items: [issues](https://github.com/"`.
- [ ] 1.4 Add ONE assertion in `apps/web-platform/test/server/inngest/cron-community-monitor-publication-flow.test.ts` adjacent to the existing `expect(atCommit).toBe(expectedRender().digestMarkdown)` (~line 440): `expect(atCommit).not.toMatch(/(?<![(<` + backtick + `])https?:\/\//)`. Do NOT touch lines ~294 or ~642 (sibling PR #9652 hunks).
- [ ] 1.5 Run the three suites and confirm the new/changed assertions are RED against the
  unmodified renderer: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-publication.test.ts test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-community-monitor-publication-flow.test.ts` (NOT `bun test` — `bunfig.toml` sets `pathIgnorePatterns = ["**"]`).

## Phase 2 — Renderer fix (GREEN)

- [ ] 2.1 In `apps/web-platform/server/inngest/functions/_cron-community-publication.ts`:
  - ~line 588: `Review inbound items: ${issuesUrl} and ${pullsUrl}` → `Review inbound items: [issues](${issuesUrl}) and [pull requests](${pullsUrl})`
  - ~line 606: `${DIGEST_FILE_LINE_PREFIX}${digestUrl}` → `${DIGEST_FILE_LINE_PREFIX}[${runDate}-digest.md](${digestUrl})`
  - ~line 607: `Inbound items: ${issuesUrl} and ${pullsUrl}` → `Inbound items: [issues](${issuesUrl}) and [pull requests](${pullsUrl})`
  - Do NOT touch `issuesUrl`/`pullsUrl`/`digestUrl` consts, `DIGEST_FILE_LINE_PREFIX`, or anything near `effectivePlatform`/`keepMetrics` (sibling PR #9652 surface at ~386/~448).
- [ ] 2.2 Re-run the three suites — all green. `./node_modules/.bin/tsc --noEmit` clean.

## Phase 3 — End-to-end lint verification

- [ ] 3.1 Produce a rendered digest file (via the flow-test workspace write, or a reconstructed copy of the template output) and run the pinned linter on it: `./node_modules/.bin/markdownlint --config .markdownlint.json <rendered-digest.md>` → 0 errors (AC6).
- [ ] 3.2 Verify `git diff --name-only origin/main...HEAD -- apps/` lists exactly 4 files; confirm no diff hunks near `effectivePlatform`/`keepMetrics` in `_cron-community-publication.ts` (AC8).
- [ ] 3.3 Confirm `withDigestNotice` invariant AC7 (existing test at publication.test.ts ~1008 green — exactly one `Digest file: ` line).

## Phase 4 — Commit

- [ ] 4.1 Commit the renderer + three test files together (one commit covering source and pins).
- [ ] 4.2 Note in PR body (via ship): fixes the `markdown-lint` failures on digest PRs #9586/#9647; does NOT address the dedup asymmetry itself (tracked by #6739).
