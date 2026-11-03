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
