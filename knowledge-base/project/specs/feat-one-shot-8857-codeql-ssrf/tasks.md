---
title: "fix(web-platform): pin GitHub API egress to the api.github.com origin (CodeQL #234)"
branch: feat-one-shot-8857-codeql-ssrf
plan: knowledge-base/project/plans/2026-09-29-sec-codeql-alert-234-server-side-request-forgery-plan.md
lane: cross-domain
---

# Tasks — feat-one-shot-8857-codeql-ssrf

Derived from `knowledge-base/project/plans/2026-09-29-sec-codeql-alert-234-server-side-request-forgery-plan.md`.

## 1. Setup

- [x] 1.1 Confirm CWD is `.worktrees/feat-one-shot-8857-codeql-ssrf/` and branch `feat-one-shot-8857-codeql-ssrf`.
- [x] 1.2 Re-read `apps/web-platform/server/github-api.ts` and `apps/web-platform/server/github-app.ts` (`githubFetch`) before editing.

## 2. Phase 1 — Guard module + failing tests

- [x] 2.1 Create `apps/web-platform/server/github-url.ts`:
  - [ ] 2.1.1 Export `githubApiUrl(path: string): string` — reject empty/over-4096-length, non-`/` leading, `//`-leading, `\`, `#`, control chars (reuse `hasControlChar` from `./kb-github-path`), and dot-segments (literal or `%2e` variants) on the raw path; parse `new URL(GITHUB_API_ORIGIN + path)`; assert `origin === "https://api.github.com"` and empty username/password; return `url.href`.
  - [ ] 2.1.2 Export `assertGithubApiAbsoluteUrl(url: string): string` — same origin/userinfo/dot-segment assertions for absolute-URL callers.
  - [ ] 2.1.3 Throw plain `Error` on refusal (not `GitHubApiError` — a refusal is a programmer/attacker error, not a GitHub response error).
- [x] 2.2 Create `apps/web-platform/test/github-url.test.ts`:
  - [ ] 2.2.1 Reject cases: `"@evil.example/x"`, `".evil.example"`, `"evil.example/x"` (no leading slash), `"//evil.example/x"`, `"/repos/o/../../x"`, `"/a/%2e%2e/b"`, `"/a/.%2E/b"`, backslash in path, `#` in path, control char, empty string.
  - [ ] 2.2.2 Accept cases: `"/repos/o/r/issues"`, `"/graphql"`, `"/repos/o/r/issues?state=open&per_page=50"`, `"/repos/o/r/git/ref/heads/feat/x"` (branch with slash).
  - [ ] 2.2.3 `assertGithubApiAbsoluteUrl`: reject `"https://evil.example/x"`, `"https://api.github.com@evil.example/x"`, `"https://api.github.com.evil.example/x"`; accept `"https://api.github.com/repos/o/r"`.
  - [ ] 2.2.4 Egress census: read `server/github-api.ts` + `server/github-app.ts` source, enumerate every `fetch(` site, assert each URL arg is a guard output; the literal `fetch("https://api.github.com/app")` is the single named exemption.

## 3. Phase 2 — Wire the sinks

- [x] 3.1 `apps/web-platform/server/github-api.ts`: `githubApiGet`, `githubApiGetText`, `githubApiPost`, `githubApiDelete` each call `githubApiUrl(path)` BEFORE `generateInstallationToken(...)`; on refusal emit `log.error` + `reportSilentFallback` (feature `github-api`, op `url-refused`) and rethrow.
- [x] 3.1a `fetchWithRetry` re-asserts `assertGithubApiAbsoluteUrl(url)` on its own input so the chokepoint is self-enforcing for callers that skip `githubApiUrl`; `handleErrorResponse` keeps receiving raw `path` (display string only).
- [x] 3.2 `apps/web-platform/server/github-app.ts`: `assertGithubApiAbsoluteUrl(url)` at the top of `githubFetch` (covers `postRepoCreate`'s plumbed `url` param too).
- [x] 3.3 Extend `apps/web-platform/test/github-api.test.ts`: refused `path` → throw with `mockFetch` call count 0 (no token minted).

## 4. Phase 3 — Verify and close

- [x] 4.1 `cd apps/web-platform && npx vitest run test/github-url.test.ts test/github-api.test.ts test/github-api-retry.test.ts` — green.
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] 4.3 `npx markdownlint-cli2` on changed `.md` files (specific paths only).
- [ ] 4.4 `gh api repos/jikig-ai/soleur/code-scanning/alerts/234 --jq .state` → record value as PR-body evidence.
- [ ] 4.5 Ship via `/soleur:ship`: PR body `Closes #8857` + alert-state evidence; labels `type/security`, `domain/engineering`, `app:web-platform` (all three verified via `gh label list`).
- [ ] 4.6 Post-merge: `gh issue view 8857 --json state` → `CLOSED`.
