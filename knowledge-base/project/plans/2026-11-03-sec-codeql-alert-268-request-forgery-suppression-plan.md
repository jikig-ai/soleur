---
title: "sec: CodeQL alert #268 — js/request-forgery (in-source suppression of an egress-pinned false positive)"
type: fix
date: 2026-11-03
slug: sec-codeql-alert-268-request-forgery-suppression
branch: feat-one-shot-codeql-268-request-forgery
issue: 9953
closes: 9953
priority: high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# sec: CodeQL alert #268 — js/request-forgery at `server/github-app.ts:255`

## Enhancement Summary

**Deepened on:** 2026-11-03
**Sections enhanced:** Technical Considerations (call-site inventory corrected), Dependencies & Risks (precedent note), Guard Contract (CTO caveats folded into tasks.md 2.2)
**Research agents used:** none — no Task/Agent tool in this harness; deepen ran in-process (mirroring the #8857 session-state constraint). The CTO ruling for the three technical forks was obtained via a `claude -p` spawn of the `soleur:engineering:cto` definition (one batched spawn).

### Key Improvements

1. **Verify-the-negative correction:** the call-site census is 14 `githubFetch(` sites, not 15 — and not all literals: 12 inline `${GITHUB_API}/…` literals + `probeOrgMembership`'s composed `url` (built from `${GITHUB_API}` + `encodeURIComponent` segments) + `postRepoCreate`'s plumbed `url` (pre-asserted at `github-app.ts:1116`; both of its own callers pass literals). The claim in Technical Considerations was corrected accordingly.
2. **Precedent-diff (Phase 4.4):** no in-repo precedent for `codeql[…]` annotations — `git grep 'codeql\[' -- apps/ plugins/ scripts/` is empty. The mechanism is novel in-repo; it was verified against upstream `github/codeql` sources (`AlertSuppression.qll` `CodeQlSuppressionComment` + `covers` semantics; PR github/codeql#11723 merged — the mechanism exists; #11772 closed unmerged — same-line form rejected).
3. **Live citation sweep (Quality Checks):** `#9953` OPEN (tracker); alert #268 `state: open` via code-scanning API; `#8857` CLOSED; PR `#9218` MERGED; labels `type/security` + `domain/engineering` exist via `gh label list`; rule ids cited (`cq-cite-content-anchor-not-line-number`, `cq-assert-anchor-not-bare-token`) verified in `AGENTS.md` index.
4. **Gate results:** 4.6 UBI PASS (`single-user incident`), 4.7 Observability PASS (5/5 fields), 4.8 PAT PASS (no hits), 4.9 UI skip (no UI-surface files), 4.10 encryption skip (no store/connection), 4.11 Guard Contract PASS (`lint-guard-contract.py` green; assembly is structural — chokepoint + exactly-once property), 4.12 Scope Check PASS (1 unfenced section, all rows mapped/asked/justified-inferred), 4.13 task-design skip (no new autonomous surface), 4.5/4.55 skip (no triggers).

### New Considerations Discovered

- `probeOrgMembership` (line ~461) passes a `url` **variable**, not a literal — one of the two non-literal call-site shapes; both stay inside the chokepoint pin.
- A `codeql[…]` annotation is line-adjacent ONLY: any formatter reflow or statement insertion silently un-covers the sink — the sentinel test is therefore load-bearing, not ornamental (CTO caveat).

## Overview

CodeQL alert [#268](https://github.com/jikig-ai/soleur/security/code-scanning/268)
(`js/request-forgery`, critical, open on `refs/heads/main` since 2026-10-10)
reports the `fetch(url, …)` sink inside `githubFetch` at
`apps/web-platform/server/github-app.ts:255` — "The URL of this request
depends on a user-provided value." The same sink is already egress-pinned:
`githubFetch` passes `url` through `githubEgressUrl`
(`server/github-url.ts` › `assertGithubApiAbsoluteUrl`), which throws unless
the URL parses to origin `https://api.github.com` with no userinfo and no
dot-segments (the CodeQL #234 / #8857 fix, PR #9218, merged 2026-09-29). The
alert is a **false positive**: the credential-bearing request cannot egress
anywhere but the GitHub API origin. It cannot be fixed by refactoring to a
CodeQL-recognized sanitizer because **the query has none for this class** —
see the sanitizer enumeration in Technical Considerations. This plan
suppresses the result in source (`// codeql[js/request-forgery]` on the line
above the sink), adds a drift sentinel to the existing egress-census test so
the suppression cannot silently detach from the sink, and leaves the runtime
guard untouched.

## Problem Statement / Motivation

The egress-pin landed 2026-09-29 (PR #9218); alert #268 was *created*
2026-10-10 — i.e., CodeQL scanned the guarded code and still reported,
because `githubEgressUrl` is a throwing assertion wrapper the query does not
model as a sanitizer. Every day the alert stays open it (a) presents as a
critical SSRF on `main`, (b) keeps tracker issue #9953 open, and (c) keeps
the `codeql-main-alert-gate` one push away from re-filing if the tracker ever
closes. The dismissal API (`PATCH …/alerts/268 state=dismissed`) is not
available to this pipeline — operator sign-off is required and was not given —
so the alert must be resolved by the scanner itself, in code.

## Proposed Solution

Insert a `// codeql[js/request-forgery]` suppression comment (with a
justification block) on the line immediately above the
`const response = await fetch(url, {` statement in `githubFetch`
(`apps/web-platform/server/github-app.ts`). Mechanics, verified against
`github/codeql` `shared/util/codeql/util/suppression/AlertSuppression.qll`
(PR github/codeql#11723 and the javascript `AlertSuppression.ql` shipped in
every default/extended analysis): a comment containing `codeql[<query-id>]`
that is the first node on its line suppresses the alert on the **next** line
— for CodeQL this emits a SARIF `suppressions: [{kind: "inSource"}]` marker,
which code scanning records as a suppressed (non-open) result. The runtime
egress pin stays; suppression affects scanner reporting only.

Second deliverable: a drift sentinel in `apps/web-platform/test/github-url.test.ts`
— assert that the line immediately preceding the `githubFetch` sink in
`server/github-app.ts` still carries `codeql[js/request-forgery]` (a comment
is adjacency-bound: if a future edit inserts a statement or moves the sink,
the suppression silently stops covering it and the alert re-opens). Layer on
top of the existing fetch-site census that already reads this file.

## Technical Considerations

### True/false-positive analysis (verdict: false positive)

- `githubFetch(url, options)` is the single chokepoint every credential-bearing
  GitHub API call in `server/github-app.ts` flows through; its first
  statement rebinds `url = githubEgressUrl(url, "github-app")` before `fetch`.
- `githubEgressUrl` → `assertGithubApiAbsoluteUrl` (`server/github-url.ts`)
  throws `github_api_egress_denied` unless: `new URL(rawUrl)` parses;
  `url.origin === "https://api.github.com"`; no userinfo; no `\`, `#`, or
  control bytes; no dot-segments in the raw path; length ≤ 4096. Refusals are
  mirrored to pino + Sentry (`reportEgressRefusal`, `op=url-refused`).
- All 14 `githubFetch(` call sites derive URLs from the `${GITHUB_API}`
  origin literal (verified by grep): 12 inline `${GITHUB_API}/…` template
  literals; `probeOrgMembership`'s `url` variable composed as
  `${GITHUB_API}/orgs/${encodeURIComponent(owner)}/members/${encodeURIComponent(githubLogin)}`;
  and `postRepoCreate`'s plumbed `url` param — itself pre-asserted at
  `github-app.ts:1116`, with both of `postRepoCreate`'s own callers passing
  literals (`/orgs/${encodeURIComponent(orgLogin)}/repos` and the
  `KB_TEMPLATE_*` constants). User-controlled path segments are
  `encodeURIComponent`'d or regex-validated (`GITHUB_LOGIN_RE`, `APP_SLUG_RE`)
  at the call sites.
- CodeQL's taint is real — the request-URL string contains
  remote-flow-controlled segments — but the *reported property* (URL depends
  on a user-provided value → credential can egress to an attacker host) is
  defeated by the origin pin: the worst an attacker achieves is a shaped path
  on `api.github.com`.

### Sanitizer enumeration (why no in-code refactor can satisfy the query)

`javascript/ql/lib/semmle/javascript/security/dataflow/RequestForgeryCustomizations.qll`
defines exactly two `Sanitizer` subclasses for `js/request-forgery`:

1. `UriEncodingSanitizer` — `encodeURIComponent`-class calls that encode path
   separators (already applied at call sites; irrelevant at the whole-URL sink).
2. `SanitizerFromModel` — barrier nodes declared by **data-extension models**
   (`models:` YAML in an extension pack / `codeql-config.yml`). The repo runs
   GitHub **default setup** (`query_suite: extended`, verified via
   `GET /repos/jikig-ai/soleur/code-scanning/default-setup`), which consumes
   no repo-local model/config files — this arm is unavailable by construction.

There is no hostname-allowlist barrier in the query, and the query's
`isAdditionalRequestForgeryStep` explicitly propagates taint through
`new URL(arg)`, so re-parsing cannot cleanse the value either. Conclusion: the
result cannot be silenced by reshaping the code — in-source suppression is the
only in-code mechanism, matching the task brief's escape clause.

### Why suppression is safe here (and not elsewhere)

The suppression targets the single chokepoint sink, not a call site: every
future `githubFetch(` caller inherits both the runtime pin AND the reporting
suppression. A caller that bypasses `githubFetch` entirely adds a new
`fetch(` site → the egress-census test (`GUARDED_FILES`, membership sweep in
`github-url.test.ts`) goes red AND CodeQL flags the new unguarded sink
unsuppressed — the suppression does not leak to other lines because it is
line-adjacent.

### Attack Surface Enumeration (security fix)

- Credential-bearing `fetch(` sites in `server/github-app.ts`: exactly two —
  line 199 (`` `https://api.github.com/app` `` literal, untainted — not flagged)
  and line 255 (the suppressed sink). Both pinned by the census count `["server/github-app.ts", 2]`.
- Other credential lanes named out of assembly by the #8857 plan: octokit
  literal-route, git/HTTPS subprocess, `GH_TOKEN` — unchanged by this plan.
- Residual risk accepted: if GitHub changes the alert's line-anchoring such
  that the line-adjacent comment no longer covers the result, the alert
  re-opens as a NEW result and the main-alert gate re-files — the sentinel
  test plus the gate bound the blast radius; no silent state.

### Performance / NFR

Comment-only runtime change; zero perf impact. The sentinel test adds ~µs.

### Why no ADR (Phase 2.10 assessment)

No new substrate, trust boundary, or recorded-architecture change: the egress
pin (ADR-level decision already made under #8857's plan) is unchanged, and an
in-source suppression comment is a scanner-reporting annotation, not an
architectural decision. No C4 update.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing change — a
  comment and a test. The failure mode worth naming: a misplaced suppression
  could hide a FUTURE true-positive `js/request-forgery` at this one sink;
  the runtime `githubEgressUrl` pin still throws on any non-GitHub URL, so
  the user-visible outcome stays a loud refusal (502 + Sentry), not an
  exfiltration.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  unchanged from today — an installation token could only egress if the
  origin pin itself regressed; that regression is covered by the existing
  census + mutation battery, not by the scanner.
- **Brand-survival threshold:** `single-user incident` — same declaration as
  the sibling #8857 plan: the touched surface is credential egress, and the
  worst shape is one user's installation token exfiltrated.

`requires_cpo_signoff: true` is set per plan Phase 2.6 step 3; CPO sign-off is
not collectible in this headless pipeline session — the flag stands for the
review phase, and `soleur:engineering:review:user-impact-reviewer` runs at
review time per the review skill's conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "CodeQL alert #268 state on refs/heads/main (open → the suppression failed or drifted; fixed/suppressed → healthy). Code scanning re-scans each push to main and the weekly scheduled run."
  cadence: "per push to main + weekly CodeQL schedule"
  alert_target: "codeql-main-alert-gate workflow files a `sec: CodeQL alert #N` issue for any open critical/high alert on main (re-files #9953's class if the alert re-opens)"
  configured_in: ".github/workflows/codeql-main-alert-gate.yml + scripts/codeql-main-alert-gate.sh"
error_reporting:
  destination: "runtime refusals still mirror via reportEgressRefusal → pino + Sentry (server/github-url.ts, feature=github-app, op=url-refused)"
  fail_loud: "thrown github_api_egress_denied propagates before any credential leaves the process"
failure_modes:
  - mode: "suppression comment detached from the sink by a later edit (statement inserted between comment and fetch, or sink moved)"
    detection: "github-url.test.ts drift-sentinel test goes red (adjacency assertion), or the alert re-opens and the main-alert gate re-files"
    alert_route: "CI failure (vitest) / GitHub issue via codeql-main-alert-gate"
  - mode: "CodeQL engine stops honoring in-source suppressions (upstream change)"
    detection: "alert #268 re-opens on a subsequent scan; main-alert gate files a fresh sec issue"
    alert_route: "GitHub issue via codeql-main-alert-gate"
  - mode: "new unguarded credential-bearing fetch site added elsewhere"
    detection: "github-url.test.ts membership sweep fails (uncategorized file); unsuppressed CodeQL result at the new line"
    alert_route: "CI failure (vitest) + code scanning alert"
logs:
  where: "stdout JSON via createChildLogger('github-egress') on refusal, ingested to Better Stack (unchanged)"
  retention: "per Better Stack retention for the platform source"
discoverability_test:
  command: grep -n "codeql\[js/request-forgery\]" apps/web-platform/server/github-app.ts
  expected_output: "codeql[js/request-forgery]"
```

## Guard Contract

Required — the deliverable includes a drift-check sentinel.

### Guard 1 — CodeQL suppression-adjacency sentinel

**Property.** The `codeql[js/request-forgery]` annotation always sits on the
line immediately preceding the `githubFetch` credential-bearing `fetch(url,`
sink in `server/github-app.ts`, so the in-source suppression can never
silently stop covering the result it was written for.

**Assembly.** One suppression annotation × one flagged sink:
`apps/web-platform/server/github-app.ts` `githubFetch` ›
`const response = await fetch(url, {` — currently the only
`js/request-forgery` in-source suppression in the repo (verified:
`git grep -n 'codeql\[' -- apps/ plugins/ scripts/` → empty). The sentinel is
a new test in `apps/web-platform/test/github-url.test.ts` that locates the
`fetch(url,` line in `githubFetch` and asserts the previous non-blank line
contains `codeql[js/request-forgery]`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `// codeql[js/request-forgery]` comment line | sentinel RED |
| 2 | Insert any statement (`const x = 1;`) between the comment and the `fetch(url,` line | sentinel RED |
| 3 | Move the `fetch(url,` call (e.g. into a helper) while leaving the comment | sentinel RED |
| 4 | Rename the sink's first arg shape so the census's `url` binding changes (companion guard: the existing fetch-site census, already in this file, independently REDs) | sentinel RED |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "determine whether the alert is a true positive (a caller passing a user-controlled URL) or a false positive (sanitizer unrecognized by CodeQL)" | Technical Considerations › True/false-positive analysis — verdict: false positive (sanitizer unrecognized) | mapped |
| 2 | "Fix the call site / sanitizer coverage accordingly" | Proposed Solution — `// codeql[js/request-forgery]` at the chokepoint sink + drift sentinel in `github-url.test.ts` | mapped |
| 3 | "if it is genuinely a false positive that cannot be silenced in code, document why" | Sanitizer enumeration — proves no CodeQL-recognized sanitizer exists; the alert CAN be silenced in code (suppression comment), so this arm is not taken | mapped |
| 4 | "dismiss via gh api … is NOT allowed without operator sign-off — instead keep it open and say so in the PR body" | Implementation Phase 3 — no API dismissal; PR body documents the in-source suppression and expected alert transition | mapped |
| 5 | "PR body MUST include `Closes #9953` (the tracker issue) on its own line" | Implementation Phase 3 — PR body requirement | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `// codeql[js/request-forgery]` suppression comment at `github-app.ts` sink | "Fix the call site / sanitizer coverage accordingly" | asked |
| Drift-sentinel test in `github-url.test.ts` | "Fix the call site / sanitizer coverage accordingly" — the suppression is the fix's coverage; the sentinel keeps it from silently lapsing | inferred — justified: Guard Contract exists because line-adjacent suppressions drift; repo convention (census tests already in this file) |
| `Closes #9953` in PR body | "PR body MUST include `Closes #9953` (the tracker issue) on its own line" | asked |
| No `gh api …/alerts/268` dismissal | "is NOT allowed without operator sign-off — instead keep it open and say so in the PR body" | asked |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` server + test
- Planned files: 2 | Estimated changed lines: ~40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

- `#2246` refactor(kb): low-severity polish from PR #2235 review — item 6
  names `server/github-app.ts` only as a *candidate destination* for a
  `parseOwnerRepo` extraction (different concern, different files edited).
  **Disposition: acknowledge** — folding a helper relocation into a
  suppression-comment PR would mix scopes; the scope-out stays open.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed (in-process; no agent-spawn tool in this harness — same
constraint the #8857 session-state recorded)
**Assessment:** Security-adjacent CI/tooling fix on an already-guarded code
path. The runtime control (egress pin, census tests, refusal telemetry) was
built and mutation-tested under #8857/PR #9218; this change is a
scanner-reporting annotation plus a drift sentinel. No new capability, no
perf surface.

### Legal

**Status:** reviewed (in-process)
**Assessment:** GDPR gate (plan Phase 2.7) evaluated: no regulated-data
surface touched — the diff is a comment and a test on a file that sends
GitHub-API requests; no new processing activity, no new distribution surface,
no `.sql`/migration/auth-flow/API-route edit. `brand_survival_threshold:
single-user incident` declared on credential-egress grounds (matching the
#8857 sibling), which fires gate trigger (b) — outcome: advisory no-op,
nothing to record in compliance-posture.md.

### Product/UX Gate

**Tier:** none — no user-facing surface; `## Files to Edit` contains no
UI-surface path (mechanical override does not fire on
`server/github-app.ts` / `test/github-url.test.ts`).

## Implementation Phases

### Phase 1 — Suppression comment + sentinel test

1. `apps/web-platform/server/github-app.ts`: insert the justification comment
   block + `// codeql[js/request-forgery]` line immediately above
   `const response = await fetch(url, {` inside `githubFetch`. The
   `codeql[…]` annotation must be the last line of the comment block and the
   first node on its line (`AlertSuppression.qll` `covers` semantics —
   verified against `github/codeql` source).
2. `apps/web-platform/test/github-url.test.ts`: add the drift-sentinel test
   (locate the `githubFetch` sink's `fetch(url,` line; assert the previous
   non-blank line contains `codeql[js/request-forgery]`).
3. Mutation matrix: drive each Guard-1 mutation RED locally, restore, green.

### Phase 2 — Verify

- `cd apps/web-platform && npx vitest run test/github-url.test.ts` — green
  (existing census + new sentinel).
- `cd apps/web-platform && npx vitest run test/github-app-token-hardening.test.ts test/github-url.test.ts` — adjacent suites green.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- Confirm suppression placement: the annotated line is immediately above the
  alert's start line (255) — `sed -n '250,262p' apps/web-platform/server/github-app.ts`.

### Phase 3 — PR + post-merge expectation

- PR body: `Closes #9953` on its own line; state the false-positive verdict,
  the sanitizer enumeration evidence, that the alert is suppressed in-source
  (not dismissed via the API — operator sign-off not obtained), and that the
  alert is expected to transition to non-open on the next scan after merge
  (record actual state via `gh api repos/jikig-ai/soleur/code-scanning/alerts/268 --jq .state`
  in the PR body / postmerge note).
- Labels: `type/security` (if it exists — mirror #8857's label convention via
  `gh label list` first), `domain/engineering`.
- Post-merge: postmerge verification re-reads the alert state; if still
  `open` after the next scheduled/push scan completes, the residual is
  documented on #9953 rather than silently left.

## Files to Edit

- `apps/web-platform/server/github-app.ts` — suppression + justification
  comment above the `githubFetch` sink (comment-only change to product code).
- `apps/web-platform/test/github-url.test.ts` — drift-sentinel test.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-codeql-268-request-forgery/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-codeql-268-request-forgery/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-codeql-268-request-forgery/session-state.md`

## Acceptance Criteria

- [ ] `apps/web-platform/server/github-app.ts` carries a `// codeql[js/request-forgery]`
      annotation on the line immediately preceding the `githubFetch`
      `fetch(url,` sink, preceded by a justification block naming the egress
      pin and the sanitizer-enumeration evidence.
- [ ] `githubEgressUrl` runtime pinning is unchanged (diff is comment-only in
      product code; `git diff -U0 -- apps/web-platform/server/github-app.ts`
      contains no non-comment line changes).
- [ ] `apps/web-platform/test/github-url.test.ts` contains the adjacency
      sentinel; each Guard-1 mutation drives it RED and restore returns green.
- [ ] `npx vitest run test/github-url.test.ts` green;
      `./node_modules/.bin/tsc --noEmit` clean.
- [ ] PR body contains `Closes #9953` on its own line, documents the
      false-positive verdict, and states the alert was suppressed in source
      (no API dismissal — operator sign-off not obtained).
- [ ] Post-merge/postmerge: `gh api …/code-scanning/alerts/268` state is
      recorded; if it has not transitioned to `fixed`/non-open after the
      merge-triggered scan, the residual is documented on #9953.

## Test Scenarios

- `unit` — Given the shipped source, when the sentinel test runs, then it
  passes: the previous non-blank line above `fetch(url,` in `githubFetch`
  contains `codeql[js/request-forgery]`.
- `unit` — Given a mutated source (each Guard-1 matrix row), when the test
  runs, then it fails (property: the sentinel must detect ANY detachment of
  annotation from sink — deletion, interposed statement, moved sink, renamed
  first-arg binding caught by the companion census).
- `integration` — Given the merged commit on `main`, when CodeQL's next
  analysis completes, then alert #268 is no longer `open` (SARIF `inSource`
  suppression). Verified via `gh api repos/jikig-ai/soleur/code-scanning/alerts/268 --jq .state`
  after the post-merge scan; not a CI-blocking check (scan timing is GitHub's).

## Success Metrics

- Alert #268 leaves `state: open` after the merge-triggered analysis
  (target: `fixed` — a suppressed-in-source result reports as non-open; the
  exact terminal label is recorded as evidence in the PR body).
- Issue #9953 closed by the merged PR.
- Zero regressions in the egress-census suite.

## Dependencies & Risks

- **Risk:** code scanning treats an `inSource`-suppressed result as
  `dismissed`-with-annotation rather than `fixed` — either is non-open, both
  satisfy the close; the PR body records whichever is observed.
- **Risk:** the alert's start line shifts if the file's earlier lines change
  before merge — mitigated by the sentinel and by re-checking adjacency at
  Phase 2 of `work` (`sed -n` probe above).
- **Risk:** a parallel PR edits `github-app.ts` near line 255 — collision
  probes returned no open PR touching this file; the overlap preflight
  re-runs at ship time.
- **Dependency:** none external — no infra, no secrets, no new dependencies.
- **Precedent note (Phase 4.4):** no in-repo precedent for `codeql[…]`
  annotations — the mechanism is novel here; its semantics were verified
  against upstream `github/codeql` sources, not sibling files.

## Sharp Edges

- Do NOT add the annotation to the SAME line as the sink: `codeql[…]`
  same-line comments are not honored (github/codeql#11772 closed
  unmerged); the annotation must be the last line of a comment block that is
  the first node on its line, directly above the alert line.
- Do NOT suppress via `lgtm[…]` (legacy alias works but the `codeql[…]` form
  is the current convention and matches the query-id scoping we want).
- The annotation suppresses only `js/request-forgery` at the covered line —
  it does not blanket the file; do not extend it to silence unrelated
  queries.
- If a future edit moves the sink, move the comment WITH it — the sentinel
  will otherwise go RED, which is the intended behavior, not a test bug.
- A plan whose `## User-Brand Impact` section is empty, `TBD`-only, or omits
  the threshold fails `deepen-plan` Phase 4.6 — filled above.
- Plan-subagent scope: this run plans inline (no agent-spawn tool); diff
  hygiene — only `knowledge-base/project/{plans,specs}/` files may appear in
  this phase's commits.
