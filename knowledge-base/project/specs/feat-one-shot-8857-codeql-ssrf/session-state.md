# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-29-sec-codeql-alert-234-server-side-request-forgery-plan.md
- Status: complete

### Errors
None blocking. Subagent had no agent-spawn capability, so plan/deepen-plan research and review fan-outs ran inline (recorded in the plan's Domain Review and Enhancement Summary).

### Decisions
- CodeQL alert #234 already `state: fixed` on main (PR #8853 `kbGithubUrlPath` call-site sanitizer); plan lands the missing sink-side guard + regression tests as the durable close.
- Fix shape: new leaf `server/github-url.ts` exporting `githubApiUrl(path)` + `assertGithubApiAbsoluteUrl(url)`; applied at all four wrappers in `github-api.ts`, self-enforced inside `fetchWithRetry`, and inside `githubFetch` in `github-app.ts`.
- Cut list: no `redirect:"manual"`, no endpoint-prefix allowlist, no per-call-site encode sweep, no `codeql-to-issues.yml` changes.
- Gates: `brand_survival_threshold: single-user incident`, `requires_cpo_signoff: true`; `## Observability` + `## Guard Contract` emitted; no ADR (internal hardening).

### Components Invoked
soleur:plan (in-process), soleur:deepen-plan (in-process), inline research/review equivalents, web_search, lint-guard-contract.py, markdownlint-cli2, gh, cloud-detect.sh
