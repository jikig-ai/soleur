# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-03-sec-codeql-alert-268-request-forgery-suppression-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

None blocking. This harness has no Task/Agent tool, so plan + deepen-plan + research ran inline in the runner context (same constraint recorded by the #8857 session-state); the CTO ruling was obtained via a `claude -p` spawn of the `soleur:engineering:cto` definition (one batched spawn; `agent_rounds` incremented).

### Decisions

- Alert #268 verdict: **false positive** — `githubFetch`'s `url` is egress-pinned by `githubEgressUrl` (throws unless origin `https://api.github.com`, no userinfo, no dot-segments); all 15 call sites pass `${GITHUB_API}/…` literals with encoded segments.
- No CodeQL-recognized sanitizer exists for hostname-pinning: `js/request-forgery` sanitizers are `UriEncodingSanitizer` + `SanitizerFromModel` (data extensions, unavailable under default setup `query_suite: extended`); taint propagates through `new URL(arg)`. So a code refactor cannot clear the alert — in-source suppression is the only in-code mechanism.
- Fix shape (CTO-ruled 2026-11-03): `// codeql[js/request-forgery]` line-adjacent above the single chokepoint sink `apps/web-platform/server/github-app.ts:255` + drift-sentinel test in `github-url.test.ts` (content-anchored, exactly-once assertion, interpose-a-line mutation case).
- `Closes #9953` required in PR body; no API dismissal (operator sign-off not obtained).
- `cto_spawns=1`

### Components Invoked

soleur:plan (in-process), worktree-manager.sh, pipeline-tally.sh, technical-ruling-gate.sh (--branch PASS), pr-overlap-preflight.sh (--mode start, exit 0), gh (issue/pr/code-scanning APIs), `claude -p` CTO spawn, web fetches of github/codeql QLL sources.

## Review Phase

Panel: class=code, tier=single-user incident, design-risk=yes. 13 seats via `claude -p` (no Task tool): design pass {code-simplicity, architecture} + base {git-history, pattern, code-quality, security, performance, data-integrity, agent-native} + conditional {test-design, user-impact, structural-enumeration}. PANEL_SHA=ec4922a79f.

Dedup ledger (raw 14 → 5 unique):
| raw finding | defect key | reporting seat(s) | fix commit |
|---|---|---|---|
| adjacency toContain too loose | sentinel-anchor | test-design, pattern, structural, code-simplicity(adjacent) | e9576d779e |
| exactly-once count uses includes | sentinel-anchor | test-design, pattern | e9576d779e |
| sink locator first-match unscoped | sink-scope | test-design, pattern, structural | e9576d779e |
| suppression comment too long | comment-bloat | code-simplicity | e9576d779e |
| header missing sentinel mention | doc-drift | pattern | e9576d779e |
| "only egress to origin" overstates pin | wording | security | e9576d779e |
| structural UNCOVERED#3 (pin removal untested) | covered-by-existing-census | structural | none — existing census binds githubEgressUrl(url before sink; verified |
| structural UNCOVERED#4 (CodeQL honoring unverifiable locally) | post-merge-check | structural | none — plan AC: verify alert state post-merge |
| nosemgrep-line-convention suggestion | convention | pattern | none — codeql[] annotation stands alone; reason lives in comment block |

Fix round: report-only, seats {test-design+pattern+structural consolidated, security+code-quality consolidated, 1 verification pass} over diff ec4922a79f..HEAD.

Fix-round result: all 5 findings closed (seats: consolidated test-design/pattern/structural + security/code-quality; verifier equivalent = both seats concur + local mutation re-drive M5/M6 RED). Vitest 46/46 green post-fix.

## QA Phase

Plan Test Scenarios: unit-layer sentinel + mutation scenarios — executed via `npx vitest run test/github-url.test.ts` (46/46 green) and the Guard-1 mutation battery (M1-M6 all RED, restore green). Integration scenario (post-merge CodeQL alert state) is not executable pre-merge — deferred to postmerge per Acceptance Criteria. No Playwright/API surface in this diff.

## Compound Phase

Learning written: knowledge-base/project/learnings/security-issues/2026-11-03-codeql-js-request-forgery-suppression-comment.md
