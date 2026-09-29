---
title: "fix(web-platform): pin GitHub API egress to the api.github.com origin (CodeQL #234)"
type: fix
date: 2026-09-29
slug: sec-codeql-alert-234-server-side-request-forgery
branch: feat-one-shot-8857-codeql-ssrf
issue: 8857
closes: 8857
priority: p0-critical
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deepened: 2026-09-29
---

# fix(web-platform): pin GitHub API egress to the api.github.com origin (CodeQL #234)

Ref #8857. CodeQL code-scanning alert #234 (`js/request-forgery`, critical) flags
`apps/web-platform/server/github-api.ts` — the `fetch(url, …)` inside
`fetchWithRetry` — because the request URL is `${GITHUB_API}${path}` with `path`
supplied by callers whose interpolated segments trace to request input.

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Research
Insights, Sharp Edges)
**Research agents used:** none — pipeline subagent has no Task fan-out; all
verification ran inline via `gh api`, `gh pr view`, `git log`, and code greps
(commands shown inline below).

### Key Improvements

1. **Chokepoint self-enforcement.** `fetchWithRetry` now additionally asserts
   `assertGithubApiAbsoluteUrl(url)` on its own input, so a future caller that
   forgets `githubApiUrl(path)` still cannot reach `fetch` with an unpinned
   URL — the last line before egress always asserts.
2. **`postRepoCreate` shape verified.** `github-app.ts`'s `githubFetch(url)`
   sink at `postRepoCreate` takes a caller-supplied `url` parameter — the one
   call-site *shape* that would bypass a `path`-only guard. Verified all
   `githubFetch` callers (14 sites incl. `postRepoCreate`, fed only by
   `createRepoForOrg`/`createRepoFromTemplate`) build `${GITHUB_API}/…`
   literals today; the absolute-URL assertion covers the future deviation.
3. **Boundary-adjacent fixtures** (per
   `learnings/best-practices/2026-05-22-parity-tests-must-include-boundary-adjacent-fixtures.md`):
   the test matrix pins the off-by-one host shapes — suffix host
   (`api.github.com.evil.example`), userinfo (`api.github.com@evil.example`),
   scheme-relative (`//evil.example`), encoded dot-segments (`%2e%2e`,
   `.%2E`) — not just the canonical bad input.
4. **Precedent-diff recorded** against `assertCodexEndpoint` /
   `normalizeEndpoint` (see Risks): the guard reuses the repo's existing
   `new URL` + `https:` + no-userinfo + host check, and adds the two checks
   the precedents do not need — leading-`/` and raw dot-segment refusal —
   because the input here is a path fragment, not a whole URL.

### New Considerations Discovered

- CodeQL alert #234 is already `state: fixed` on main (verified live:
  `gh api repos/jikig-ai/soleur/code-scanning/alerts/234 --jq .state` →
  `fixed`, `fixed_at: 2026-09-25T14:06:00Z`), resolved when PR #8853
  (`9279de94fe`) added the `kbGithubUrlPath` sanitizer that broke the taint
  path. The plan proceeds with the sink guard as durable close + regression
  lock rather than verify-only.
- `github-app.ts` already encodes this posture piecemeal (`GITHUB_LOGIN_RE`,
  `encodeURIComponent` on login/owner segments, and a code comment that
  "forecloses any `?`/`#`/`..`-in-segment from reshaping the GitHub API
  path") — the sink assertion unifies it at the boundary.
- Citations verified live in this pass: PR #2416 MERGED, PR #2421 MERGED,
  PR #8853 MERGED, PR #8687 MERGED, issue #2368 CLOSED, alert #92 dismissed
  `false positive` on this same file (earlier instance at line 40).

## Overview

The GitHub API wrapper builds every request URL by concatenating the constant
`https://api.github.com` with a caller-supplied `path` and hands the result to
`fetch` together with an `Authorization: token <installation-token>` header.
Nothing in the module checks what `path` actually is. A `path` that does not
start with `/` (for example `@attacker.example/x` or `.attacker.example/x`)
rebinds the URL's authority component, and the fetch then carries a live GitHub
App installation token to an attacker-controlled host. Dot-segments (`..`,
`%2e%2e`) inside a well-formed path additionally let an interpolated segment
escape the caller-intended endpoint prefix (e.g. `/repos/{owner}/{repo}/…`) to
reach a different `api.github.com` endpoint than the one the call site built.

Live verification (2026-09-29): the alert is already `state: "fixed"` on
`refs/heads/main` (fixed_at 2026-09-25T14:06:00Z) because PR #8853
(`9279de94fe`) added per-segment validation + percent-encoding at the
`app/api/kb/**` call sites, which broke the taint path CodeQL had traced. The
*sink* remains unguarded: any future caller passing an unsanitized `path`
re-opens the forgery class silently, with no test or runtime check to catch it.
This plan therefore lands the sink-side guard the alert asks for, plus the
regression tests that keep it closed, then verifies the alert state and closes
issue #8857.

## Problem Statement / Motivation

- `fetchWithRetry` (`github-api.ts`, the flagged line) and the raw `fetch` in
  `githubApiDelete` are the two sinks in the module; `githubFetch` in
  `github-app.ts` is the sibling sink carrying the same credential class (App
  JWT and installation tokens) to the same constant prefix.
- The `path` values are assembled at ~15 call sites from a mix of inputs:
  server-resolved `owner`/`repo` from `workspaces.repo_url`, tool-call
  arguments from agent sessions (e.g. `workflowId`, `ref`, issue numbers),
  route params (`[...path]` → `urlPath`, `sha`, `githubDir`), and GitHub API
  response fields (`default_branch`, `head_sha`). At least two of those are
  remote-attacker influenceable; none is currently checked at the sink.
- Severity is credential exfiltration, not just endpoint confusion: the
  `Authorization` header on the forged request is the installation token.

## Research Reconciliation — Spec vs. Codebase

| Issue claim (from #8857) | Reality (verified 2026-09-29) | Plan response |
|---|---|---|
| Alert #234 open, needs remediation | `gh api .../code-scanning/alerts/234` returns `state: fixed`, `fixed_at: 2026-09-25T14:06:00Z` — auto-resolved by PR #8853's path sanitizer, not by a sink fix | Land the sink-side origin assertion anyway (durable defense), verify alert stays `fixed`, close the issue with evidence |
| "URL depends on a user-provided value" at `github-api.ts` | True: `path` parameters reach `fetch` unvalidated at both `fetchWithRetry` and `githubApiDelete`; sibling `githubFetch` in `github-app.ts` shares the pattern | Guard all three chokepoints |
| p0-critical SSRF | The only live token-exfiltration vector requires a `path` lacking a leading `/` (authority rebinding) or a dot-segment traversal; all current call sites pass `/`-prefixed literals — the alert is a latent boundary defect, not an exploited live hole | Severity framing kept; fix is small because the boundary is narrow |

## Proposed Solution

Add one dependency-free leaf module, `apps/web-platform/server/github-url.ts`,
that owns GitHub API URL construction and validation, and route every outbound
GitHub API request through it:

```ts
// apps/web-platform/server/github-url.ts
const GITHUB_API_ORIGIN = "https://api.github.com";

// A raw segment that is — or percent-decodes to — "." or "..". WHATWG URL
// parsing resolves dot-segments before fetch sees them; refuse them on the
// raw path so an interpolated segment cannot escape the caller's prefix.
const DOT_SEGMENT = /^(?:\.|%2e){1,2}$/i;

export function githubApiUrl(path: string): string {
  // 0. reject empty / over-long input before any regex work — path carries
  //    attacker-influenced bytes; cap at 4096 (GitHub API paths are far shorter)
  // 1. path must be a leading-"/" path: anything else can rebind the authority
  //    ("@evil.example", ".evil.example" suffix-join) — this is the forgery
  // 2. reject "//" (caller almost certainly meant scheme-relative), "#"
  //    (fragment truncation), "\\" (WHATWG folds it to "/"), control chars
  // 3. reject dot-segments on the RAW path (literal and %-encoded)
  // 4. parse and assert origin === "https://api.github.com", no userinfo
  //    (mirrors assertCodexEndpoint in server/codex-code-adapter.ts)
  // 5. return url.href (the parsed, normalized form)
}

export function assertGithubApiAbsoluteUrl(url: string): string {
  // same assertions for absolute-URL callers (github-app.ts githubFetch)
}
```

- `github-api.ts`: `githubApiGet`, `githubApiGetText`, `githubApiPost`,
  `githubApiDelete` each resolve `const url = githubApiUrl(path)` **before**
  `generateInstallationToken(...)` — never mint a credential for a request the
  module refuses — and pass `url` (not a raw concat) into `fetchWithRetry` /
  `fetch`. `fetchWithRetry` **also** asserts `assertGithubApiAbsoluteUrl(url)`
  on its input, so the chokepoint is self-enforcing for any future caller that
  skips `githubApiUrl`. On refusal: `log.error` + `reportSilentFallback`
  (feature `github-api`, op `url-refused`) then rethrow; the thrown error is a
  plain `Error` (it is a programmer/attacker error, not a GitHub response
  error — `GitHubApiError.statusCode` would misroute it through the 502 path).
  `handleErrorResponse` keeps receiving the raw `path` — it is a display
  string in error text, not a request target.
- `github-app.ts`: `githubFetch` calls `assertGithubApiAbsoluteUrl(url)` at its
  top — one assertion covers all ~15 call sites, including `postRepoCreate`
  whose `url` parameter is plumbed from `createRepoForOrg` /
  `createRepoFromTemplate` (both `${GITHUB_API}/…` literals today — the
  assertion is what keeps that true under a future caller).
- The leaf imports only `hasControlChar` from `./kb-github-path` (already
  exported, dependency-free) so both `github-api.ts` and `github-app.ts` can
  consume it without a cycle — the same placement reasoning that put
  `isRetryable` in `github-retry.ts`.

Deliberately NOT done (mechanism-minimality cuts + constraints):

- No `redirect: "manual"`/`"error"`: `githubApiGetText` on
  `/actions/jobs/{id}/logs` depends on GitHub's 302 to a signed download URL;
  breaking that is a functional regression. Undici's `fetch` strips
  `Authorization` on cross-origin redirects (fetch spec http-redirect-fetch),
  so the residual redirect risk is bounded to GitHub-operated hosts.
- No per-call-site `encodeURIComponent` sweep: segments are documented at each
  call site; the sink guard plus the existing `kbGithubUrlPath` sanitizer cover
  the two real exposure classes (authority rebinding, dot-segment traversal).
- No endpoint-prefix allowlist (`^/(repos|graphql)/…`): brittle against future
  legitimate paths (`/app/installations`, `/orgs/`, `/users/`), buys little
  once dot-segments are refused.
- No changes to `codeql-to-issues.yml`: the orphan-close sweep for
  already-resolved alerts is covered by prior work (#2368 plan), and this PR
  closes #8857 itself.

## Technical Considerations

### Attack Surface Enumeration (security fix — all token-bearing fetch sites)

| Sink | File | URL construction | Credential | Covered by fix |
|---|---|---|---|---|
| `fetchWithRetry` | `server/github-api.ts` (`fetch(url, …)` — the flagged line) | `url` param = `${GITHUB_API}${path}` built by `githubApiGet`/`githubApiGetText`/`githubApiPost` | installation token | yes — `githubApiUrl(path)` |
| raw `fetch` in `githubApiDelete` | `server/github-api.ts` | `${GITHUB_API}${path}` | installation token | yes — `githubApiUrl(path)` |
| `githubFetch` | `server/github-app.ts` (`fetch(url, …)`) | absolute `${GITHUB_API}/…` at ~15 call sites (`/app/installations/…`, `/orgs/{login}/members/…`, `/repos/{o}/{r}`, `/users/{login}/installation`) | App JWT / installation token | yes — `assertGithubApiAbsoluteUrl(url)` |
| literal `fetch("https://api.github.com/app")` | `server/github-app.ts` | compile-time constant, no interpolation | App JWT | safe by construction — no tainted input |
| `server/github/probe-octokit.ts` | octokit client | URL construction inside octokit | token | out of scope — octokit assembles request URLs internally |
| other `fetch(url)` sinks | `cf-cache-purge.ts`, `token-validators.ts`, `dsar-export.ts`, `server/inngest/*` | vendor-specific (Cloudflare, Anthropic, Resend, Sentry, Doppler) | other tokens | out of scope — different credential boundary; noted so the sweep boundary is explicit |

### Interpolated-segment inventory (who can influence `path`)

- Server-resolved: `owner`/`repo` from `workspaces.repo_url` (parsed in
  `kb-route-helpers.ts`), `installationId` (number), `default_branch` /
  `head_sha` / `sha` (GitHub API responses — upstream-trusted but not
  contract-checked).
- Agent-tool args: `workflowId`, `ref`, `issue_number`, `pull_number`,
  `per_page`, `branch` (the last via `URLSearchParams`, already encoded).
- HTTP route params: `[...path]` → `kbGithubUrlPath` (already validated and
  per-segment encoded — the sanitizer that resolved the alert), `sha`,
  `githubDir`, `[...path]` rename body `newName` (via `sanitizeFilename`).

The guard catches the residual class none of those upstream checks own: a
`path` that is structurally not a GitHub API path.

### Performance / NFR

One `new URL()` parse per request, before token mint — negligible against a
network round-trip. No new dependencies, no new persistence.

### Why no ADR (Phase 2.10 assessment)

The change adds a validation assertion inside existing modules; it moves no
ownership/tenancy boundary, adds no substrate, and imposes no contract on
consumers (callers keep passing `path` strings exactly as today — the check is
invisible until violated). The competent-engineer test: existing ADRs + C4 do
not describe request construction at this granularity, and the C4 Container
view's "platform → GitHub API" edge is unchanged. Checked
`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`
elements for external actors/systems touched: the GitHub API external system
is already modeled; no actor or access relationship changes. Conclusion: no
ADR, no C4 edit.

## User-Brand Impact

- **If this lands broken, the user experiences:** every GitHub-backed surface
  for the affected workspace fails at once — KB file save/delete/rename, C4
  diagram writes, workstream board reads, agent CI/issue tools all throw a URL
  refusal. That failure is loud (502 + Sentry), not silent.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  GitHub App installation token exfiltrated to an attacker host, granting the
  attacker the installation's permissions over the user's connected repository
  (read/write of that user's code, issues, and CI).
- **Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true` is set per plan Phase 2.6 step 3; CPO sign-off was
not collectible in this headless pipeline session — the flag stands for the
review phase, and `soleur:engineering:review:user-impact-reviewer` runs at
review time per the review skill's conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "URL-refusal events (log.error + reportSilentFallback, feature=github-api, op=url-refused) — the healthy signal is zero occurrences; any occurrence means a caller built a non-GitHub-bound path and the guard fired"
  cadence: "per request (only on refusal)"
  alert_target: "Sentry issue via reportSilentFallback"
  configured_in: "apps/web-platform/server/github-api.ts (reportSilentFallback call added by this change); Sentry wiring in apps/web-platform/server/observability.ts"
error_reporting:
  destination: "Sentry web-platform project via reportSilentFallback (existing) + route-level Sentry.captureException in app/api/kb/** handlers"
  fail_loud: "thrown Error propagates to the route/MCP-tool wrapper — routes return 502/GITHUB_API_ERROR, tools return isError; the request is never sent"
failure_modes:
  - mode: "attacker or buggy caller supplies a non-GitHub-bound path"
    detection: "github-api log error + reportSilentFallback event feature=github-api op=url-refused"
    alert_route: "Sentry issue"
  - mode: "false-positive refusal of a legitimate path shape (regression)"
    detection: "sudden cluster of url-refused Sentry events plus 502s on KB/C4/CI surfaces"
    alert_route: "Sentry issue; unit tests pin the accepted shapes"
  - mode: "guard removed or bypassed by a later refactor"
    detection: "apps/web-platform/test/github-url.test.ts + the github-api.ts egress-census test go red"
    alert_route: "CI failure (vitest)"
logs:
  where: "stdout JSON via createChildLogger('github-api') / createChildLogger('github-app'), ingested to Better Stack (ADR-218)"
  retention: "per Better Stack log retention for the platform source"
discoverability_test:
  command: rg -l -e githubApiUrl -e assertGithubApiAbsoluteUrl apps/web-platform/server/github-api.ts apps/web-platform/server/github-app.ts apps/web-platform/server/github-url.ts
  expected_output: github-api.ts
```

## Guard Contract

### Guard 1 — GitHub egress origin pin

**Property.** No `fetch` that carries a GitHub credential can send it to an
origin other than `https://api.github.com`, and no `path`/`url` argument can
traverse outside its caller-intended endpoint prefix via dot-segments or
authority rebinding.

**Assembly.** Every outbound GitHub API request in the platform flows through
exactly three chokepoints: `fetchWithRetry` and the raw `fetch` in
`githubApiDelete` (`apps/web-platform/server/github-api.ts`), and `githubFetch`
(`apps/web-platform/server/github-app.ts`). All four public wrappers
(`githubApiGet`, `githubApiGetText`, `githubApiPost`, `githubApiDelete`)
resolve their `path` through `githubApiUrl` before any fetch; `fetchWithRetry`
itself re-asserts `assertGithubApiAbsoluteUrl(url)` so the chokepoint holds
for callers that skip the builder; `githubFetch` asserts the same on its
absolute URL. The compile-time literal `fetch("https://api.github.com/app")`
in `github-app.ts` carries no interpolated input and is the single named
exemption. Octokit (`probe-octokit.ts`) is a separate construction path and is
explicitly out of assembly.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `url.origin !== GITHUB_API_ORIGIN` comparison in `githubApiUrl` | RED — the `@`-host-rebinding and suffix-host test cases pass a forged URL through |
| 2 | Reduce `githubApiUrl` to `return GITHUB_API + path` (guard's own dispatch silently neutered — every caller still "uses" it) | RED — every reject-case test fails |
| 3 | Add a second egress member after a compliant first: a new wrapper (e.g. `githubApiPut`) that calls `fetch(`${GITHUB_API}${path}`)` directly | RED — the egress-census test asserting no `fetch(` argument in `github-api.ts`/`github-app.ts` is a raw `GITHUB_API` template outside `github-url.ts` fails |
| 4 | Weaken the dot-segment regex to literal `..` only (drop `%2e` handling) | RED — the `%2e%2e` traversal test escapes `/repos/{o}/{r}` on the normalized URL |
| 5 | Harness row — must-PASS input differing from canonical: `/repos/o/r/issues?state=open&per_page=50` (query-bearing path) and `/graphql` (non-`repos` prefix) | PASS — proves the guard is not a reject-everything stub |

**Anchor.** Runtime assertion guard — it compares no stored value, so no
external anchor applies; the URL grammar itself is the reference.

## Research Insights

**Premise validation (Phase 0.6).** Checked `gh issue view 8857` (open, labels
`priority/p0-critical`, `domain/engineering`, `type/security`, no closing PRs),
`gh api .../code-scanning/alerts/234` (`state: fixed`,
`fixed_at: 2026-09-25T14:06:00Z`, ref `refs/heads/main`), and the fix commit:
PR #8853 (`9279de94fe`, merged 2026-09-25 14:06 UTC) added per-segment dir
validation + percent-encoding on `app/api/kb/c4` routes — the call-site
sanitizer that broke the taint path. The cited file exists and still carries
the unguarded sink. A prior `js/request-forgery` alert on this file (#92,
line 40) was dismissed `false positive` in the April triage; the new alert is
a distinct instance created 2026-09-24 when PR #8687 added the `opts.signal`
call surface. Conclusion: premise partially stale (alert already resolved);
the issue still wants a durable close, and the sink defect is real.

**Property List (Phase 0.6b).**

- P1: a GitHub credential can never egress to a non-`api.github.com` origin,
  regardless of caller input.
- P2: a future caller adding a new `path` source cannot silently reopen the
  class — there is a runtime refusal and a test that goes red.
- P3: issue #8857 closes with verifiable evidence (alert state + test suite).

**Cut List (Phase 0.6b).**

- Endpoint-prefix allowlist → P1 partially → rejected: brittle against legit
  prefixes (`/app`, `/orgs`, `/users`, `/graphql`); origin + dot-segment
  refusal buys P1 without the false-positive surface.
- `redirect: "error"` on fetch → would harden redirect-leak → rejected: breaks
  `/actions/jobs/{id}/logs` 302 handling; undici already strips `Authorization`
  cross-origin.
- Per-call-site `encodeURIComponent` sweep → P1 partially → rejected:
  `kbGithubUrlPath` already encodes the only free-form route segment; the sink
  guard covers the structural class for all callers at once.
- `codeql-to-issues.yml` orphan-sweep → P3 partially → rejected: prior #2368
  work covers the orphan class; this PR closes the issue directly.

**Relevant file paths.**

- `apps/web-platform/server/github-api.ts` — flagged sink + 4 wrappers
  (`githubApiGet`, `githubApiGetText`, `githubApiPost`, `githubApiDelete`),
  `fetchWithRetry`, `GITHUB_API` constant.
- `apps/web-platform/server/github-app.ts` — `githubFetch` chokepoint,
  `GITHUB_LOGIN_RE`, existing `encodeURIComponent` call-site precedent.
- `apps/web-platform/server/kb-github-path.ts` — existing per-segment
  sanitizer (`kbGithubUrlPath`, `hasControlChar`, `DOT_SEGMENT` pattern); the
  sanitizer that resolved the alert.
- `apps/web-platform/server/codex-code-adapter.ts` (`assertCodexEndpoint`) and
  `server/agent-engine-data-egress-policy.ts` (`normalizeEndpoint`) — the
  repo's existing URL-assertion convention: `new URL()` + `https:` + no
  userinfo + host allowlist.
- `apps/web-platform/server/github-read-tools.ts`, `server/ci-tools.ts`,
  `server/trigger-workflow.ts`, `server/c4-writer.ts`,
  `server/c4-stage-sources.ts`, `server/agent-runner.ts`,
  `app/api/kb/file/[...path]/route.ts`, `app/api/kb/upload/route.ts`,
  `app/api/kb/c4/project/route.ts` — `path`-supplying callers.
- `apps/web-platform/test/github-api.test.ts`,
  `apps/web-platform/test/github-api-retry.test.ts` — test conventions
  (`vitest`, `globalThis.fetch` mock, `mockTokenResponse`).

**Institutional learnings.**

- `knowledge-base/project/plans/2026-04-19-fix-verify-and-close-codeql-issue-2368-plan.md`
  — the verify-and-close precedent for CodeQL-derived issues whose alert
  resolved between filing and work; the alert-state API check is the evidence
  step.
- `knowledge-base/project/plans/2026-05-26-fix-ssrf-hardening-cron-follow-through-monitor-plan.md`
  — prior SSRF hardening (`_predicate-validator.ts`): `Set.has()` host
  allowlist, `new URL` normalization, DNS/`ipaddr.js` machinery for
  *arbitrary* URLs. Not reused — here the host is a compile-time constant, so
  DNS rebinding and IP-range checks buy nothing.
- `knowledge-base/engineering/architecture/decisions/ADR-051` /
  `ADR-052` — GitHub-token and container-egress boundary context.
- Constitution: comments must cite symbol anchors not line numbers;
  `cq-silent-fallback-must-mirror-to-sentry` (refusal mirrors to Sentry);
  minimalism ladder (leaf module over per-callsite surgery).

**External references.**

- CodeQL query help `js/request-forgery` (CWE-918): pick the hostname from an
  allow-list rather than constructing it from user input; restrict path input
  so `../` cannot redirect the request.
- CodeQL `js-incomplete-url-substring-sanitization`: check the parsed URL's
  host against an explicit allowlist — never substring/regex matching on the
  raw URL string.
- WHATWG URL: `%2e%2e` (and `.%2e` mixes) normalize to `..`; `\` folds to `/`
  for special schemes — both are refused on the raw path before parsing.
- undici `fetch` strips `Authorization` on cross-origin redirects (fetch spec
  `http-redirect-fetch`; GHSA-3787-6prv-h9w3 fixed the `Proxy-Authorization`
  sibling gap).

**Related issues/PRs:** #8857 (this), #8853/#8740 (path sanitizer that fixed
the alert), #8687/#8623 (`opts.signal` surface), #2416/#2421 (April triage +
threat-model switch), #2368 (orphaned-alert precedent), alert #92 (prior
dismissal on this file).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no
reference to `server/github-api.ts`, `server/github-app.ts`,
`server/github-read-tools.ts`, or `test/github-api.test.ts` (checked
2026-09-29, 200-issue scan).

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed (orchestrator-inline — this plan ran inside a pipeline
subagent with no Task fan-out; the assessment below is the orchestrator's)
**Assessment:** Single-module security hardening using the repo's existing
URL-assertion convention (`assertCodexEndpoint`). No architectural change, no
new dependency, no schema/auth surface. The leaf-module placement mirrors the
`github-retry.ts` circular-import resolution. Technical risk concentrated in
false-positive refusals — mitigated by must-PASS test rows covering every
current call-site path shape (`/repos/…`, `/graphql`, query-bearing paths,
`git/ref/heads/{branch-with-slash}`).

### Legal

**Status:** reviewed (orchestrator-inline)
**Assessment:** The exposure vector is a credential (GitHub App installation
token), not personal data. No privacy-policy, DPA, or register implication —
the change narrows where a credential can egress. GDPR gate (Phase 2.7) does
not fire: the diff touches no schema, migration, auth flow, API route, or
`.sql` file, and none of the (a)–(d) supplemental triggers apply — no new
processing activity, no new distribution surface, `brand_survival_threshold`
is declared but the gate's triggers are the four enumerated shapes, not the
threshold alone.

### Product/UX Gate

Not relevant — Files to Edit/Create contain no UI-surface path
(`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`, `pages/**`, `*.njk`,
`*.html` — the mechanical override does not fire). Backend-only security fix.

**Brainstorm-recommended specialists:** none (no brainstorm ran — one-shot
pipeline entry).

## Implementation Phases

### Phase 1 — Guard module + failing tests

- Create `apps/web-platform/server/github-url.ts` with `githubApiUrl(path)` and
  `assertGithubApiAbsoluteUrl(url)` per the Proposed Solution sketch.
- Create `apps/web-platform/test/github-url.test.ts` covering every reject
  class and the must-PASS shapes (see Test Scenarios).
- Run the new test file RED first where the assertions depend on the new
  module (`cq-write-failing-tests-before` applies to the guard behavior:
  reject-case tests are written alongside the module because the module does
  not exist yet — the RED is demonstrated by the mutation-matrix runs below).

### Phase 2 — Wire the sinks

- `apps/web-platform/server/github-api.ts`: route `githubApiGet`,
  `githubApiGetText`, `githubApiPost`, `githubApiDelete` through
  `githubApiUrl(path)` before token mint; add `log.error` +
  `reportSilentFallback` on refusal.
- `apps/web-platform/server/github-app.ts`: `assertGithubApiAbsoluteUrl(url)`
  at the top of `githubFetch`.
- Add the egress-census test (in `test/github-url.test.ts`): read the two
  module sources at test time and enumerate every `fetch(` call site in
  `server/github-api.ts` and `server/github-app.ts` — a census over the file
  set, not a pinned name list (per the #8097 sharp edge: one row of the
  contract must redden when a NEW unclassified fetch site appears). Assert each
  site's URL argument is a `githubApiUrl`/`assertGithubApiAbsoluteUrl` output,
  with the compile-time literal `fetch("https://api.github.com/app")` named as
  the single documented exemption.
- Extend `test/github-api.test.ts` with wrapper-level tests: a refused `path`
  throws before `generateInstallationToken`'s fetch (assert `mockFetch` had
  zero calls — proving no token was minted for a refused request).

### Phase 3 — Verify and close

- `cd apps/web-platform && npx vitest run test/github-url.test.ts test/github-api.test.ts test/github-api-retry.test.ts` — green (runner verified:
  `package.json` scripts use `vitest`; `vitest.config.ts` collects
  `test/**/*.test.ts`).
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean (the
  `npm run -w` form is not usable; the root package.json has no `workspaces`
  field).
- `gh api repos/jikig-ai/soleur/code-scanning/alerts/234 --jq .state` →
  `fixed` (post-merge re-scan keeps it `fixed`; record the value in the PR
  body as evidence).
- PR body: `Closes #8857`, labels `type/security`, `domain/engineering` —
  mirror #2368's label convention; verify labels via `gh label list` first.

## Files to Edit

- `apps/web-platform/server/github-api.ts` — route all four wrappers through
  the URL guard; refusal observability.
- `apps/web-platform/server/github-app.ts` — assert inside `githubFetch`.
- `apps/web-platform/test/github-api.test.ts` — wrapper-level guard tests.

## Files to Create

- `apps/web-platform/server/github-url.ts` — the egress URL guard (leaf).
- `apps/web-platform/test/github-url.test.ts` — guard unit tests + egress
  census.

## Acceptance Criteria

- [ ] `githubApiGet`, `githubApiGetText`, `githubApiPost`, `githubApiDelete`
  each reject — before any token mint — a `path` that (a) lacks a leading `/`,
  (b) contains a dot-segment (literal `..`/`.` or `%2e` variants), (c)
  contains `\`, `#`, or a control character, or (d) parses to an origin other
  than `https://api.github.com` or carries userinfo.
- [ ] `githubFetch` in `github-app.ts` rejects an absolute URL whose origin is
  not `https://api.github.com` or that carries userinfo.
- [ ] Every currently-existing call-site path shape still passes:
  `/repos/…`, `/graphql`, query-bearing paths, and `git/ref/heads/` branch
  names containing `/`.
- [ ] A refusal emits `log.error` + `reportSilentFallback` (feature
  `github-api`, op `url-refused`) and no HTTP request is sent.
- [ ] The egress-census test fails if a new `fetch(` site in `github-api.ts`
  or `github-app.ts` receives a raw `GITHUB_API`-concatenated string.
- [ ] `cd apps/web-platform && npx vitest run` on the touched test files is
  green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [ ] Post-merge: `gh api repos/jikig-ai/soleur/code-scanning/alerts/234 --jq
  .state` remains `fixed` (or `dismissed` with reason), and issue #8857 is
  closed by the PR.

## Test Scenarios

- Given `path = "@evil.example/x"`, when `githubApiGet` is called, then it
  throws a URL-refusal error and `mockFetch` was never called (no token mint).
- Given `path = ".evil.example"`, when `githubApiUrl` runs, then the parsed
  host `api.github.com.evil.example` fails the origin check → throw.
- Given `path = "/repos/o/../../x"` or `path = "/a/%2e%2e/b"`, when the guard
  runs, then throw before parsing normalizes the traversal away.
- Given `path = "/repos/o/r/x\\.."` or `path` containing `#`, when the guard
  runs, then throw.
- Given `path = "/repos/o/r/issues?state=open&per_page=50"` and
  `path = "/graphql"`, when the guard runs, then it returns the normalized
  URL unchanged (must-PASS rows).
- Given `url = "https://api.github.com@evil.example/x"` or
  `"https://evil.example/x"` to `assertGithubApiAbsoluteUrl`, then throw;
  given `"https://api.github.com/repos/o/r"`, then pass.
- Given the existing `test/github-api.test.ts` suite (GET/POST/403/DELETE-guard
  behaviors), when re-run, then all prior assertions stay green — the guard
  changes no accepted behavior.

## Success Metrics

- CodeQL alert #234 stays `fixed` on the next post-merge scan; no new
  `js/request-forgery` alert fires on the touched files.
- Zero `url-refused` Sentry events in the first 7 days post-deploy (a nonzero
  count means a shipped caller violates the contract — itself a finding).

## Dependencies & Risks

### Precedent diff (Phase 4.4 — pattern-bound behavior)

| Aspect | `assertCodexEndpoint` / `normalizeEndpoint` (existing) | `githubApiUrl` (this plan) |
|---|---|---|
| Input | whole URL string | path fragment joined to a constant prefix |
| Host check | caller-supplied `allowedHosts` list on `url.hostname` | fixed `origin === "https://api.github.com"` |
| Userinfo / scheme | rejects non-`https:` + non-empty user/pass | identical assertions |
| Dot-segments | not checked (whole-URL callers own their paths) | refused on the raw path (literal + `%2e` forms) — the fragment is attacker-shapeable |
| Leading-`/` | not applicable | required — a fragment without it can rebind the authority |

Same predicate family, one extra axis for the fragment input. No precedent for
a path-fragment guard inside the GitHub wrappers themselves; closest is
`kbGithubUrlPath`, a call-site sanitizer this design complements rather than
duplicates (it validates the KB file-path segment; the sink guard validates
the assembled request shape).

- **False-positive refusal**: a legit path shape not in the test corpus gets
  rejected in production. Mitigated by the must-PASS rows enumerated from the
  real call-site inventory and by loud (Sentry) refusal. Revert is one leaf
  module + 4 call-site lines.
- **Premise staleness**: the alert is already `fixed`; a reviewer could ask
  why code lands at all. Answer (in PR body): the alert cleared because a
  call-site sanitizer broke one taint path; the sink itself is still
  unguarded, and this diff is the durable close plus regression tests.
- **github-app.ts behavior change**: `githubFetch` callers currently pass only
  `${GITHUB_API}/…` URLs (verified by grep); the assertion is a no-op for them
  and trips only on a future deviation.

## References & Research

- Issue: #8857; CodeQL alert: #234 (`js/request-forgery`, CWE-918).
- Prior dismissals/triage: alert #92 (this file, `false positive`), #2368,
  #2416, #2421.
- Resolving commit for the alert: `9279de94fe` (PR #8853).
- Conventions reused: `assertCodexEndpoint`
  (`apps/web-platform/server/codex-code-adapter.ts`), `normalizeEndpoint`
  (`server/agent-engine-data-egress-policy.ts`), `kbGithubUrlPath`
  (`server/kb-github-path.ts`).
- CodeQL query help: `js/request-forgery`,
  `js-incomplete-url-substring-sanitization` (codeql.github.com).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — it is filled above.
- `githubApiDelete` does not go through `fetchWithRetry`; it is a second,
  separately-shaped sink. The fix must cover it or the guard's window is
  narrower than the property (Guard Contract row 3).
- `github-app.ts` must not import from `github-api.ts` — the import direction
  is already `github-api.ts → github-app.ts` (`generateInstallationToken`);
  the helper lives in the leaf `github-url.ts` to keep it acyclic, the same
  reason `isRetryable` lives in `github-retry.ts`.
- Do not set `redirect: "manual"`/`"error"` on the shared fetch path — it
  breaks `githubApiGetText` log downloads, which rely on GitHub's 302.
- The filename slug (`sec-codeql-alert-234-server-side-request-forgery`) is
  fixed; the `title:` was refined post-research without a `git mv`.
- Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed) —
  no `specs/feat-one-shot-8857-codeql-ssrf/spec.md` exists; the brainstorm
  phase did not run on this one-shot path.
