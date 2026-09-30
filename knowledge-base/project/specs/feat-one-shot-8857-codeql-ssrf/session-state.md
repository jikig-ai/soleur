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

## Work Phase

- Status: complete. Implementation + tests green (62 tests in github-url/github-api suites; 400 across the 19 directly-affected files; tsc clean).
- Commits: `142188f7bc` (guard + wiring), `b5e47d4a2b` (design-pass fixes).

### Review Phase (12 seats: design pass 2 + panel 7 + conditional 3)

- Design pass (code-simplicity + architecture) found: pipeline duplication in `githubApiUrl` (composed now), un-asserted literal sinks in `release-notes.ts`/`cron-weekly-release-digest.ts` (wrapped + censused now), telemetry asymmetry (shared `reportEgressRefusal`/`githubEgressUrl` now), census await-only regex + name-not-provenance weakness (widened + provenance-bound now).
- Panel + conditional seats added: open-world membership sweep (every file with fetch+GitHub-credential signal must be categorized), octokit literal-route tripwire, mint-ordering pre-assert in `postRepoCreate`, refusal-input log sanitization, `EGRESS_REFUSED` error branches in c4-writer/kb-delete catch paths, `encodeURIComponent(orgLogin)`, boundary rows + `mockClear` hygiene, plan-doc corrections (attack-table inngest mislabel, octokit rationale, timestamp, discoverability cmd).
- Mutation battery on the shipped guard: 10 mutations each RED (origin-delete, dispatch-neuter, dot-segment weaken, chokepoint-assert delete, `url`-suffix evasion, member-access fetch, new credential+fetch file, exemption suffix, octokit non-literal route, raw new fetch site); restore = green.
- Declined: octokit/git-HTTPS/GH_TOKEN-subprocess lanes are named out-of-assembly scope boundaries (plan), not unguarded defects; lowercase `github_api_egress_denied` kept to match `codex_egress_denied`/`engine_egress_denied` sibling taxonomy.
- Filed as scope-out: 0.

### Components Invoked

soleur:plan (in-process), soleur:deepen-plan (in-process), soleur:work (in-process), soleur:review (in-process panel via run_subagent), web_search, lint-guard-contract.py, markdownlint-cli2, gh, cloud-detect.sh, vitest, tsc, semgrep
