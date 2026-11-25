---
title: "fix: linkedin token validator rejects valid Community-app tokens (openid-only userinfo probe)"
date: 2026-09-29
slug: fix-linkedin-token-validator-userinfo
branch: feat-one-shot-9188-linkedin-token-validator
issue: 9188
closes: 9188
type: fix
lane: cross-domain
brand_survival_threshold: none
---

# fix: linkedin token validator rejects valid Community-app tokens (openid-only userinfo probe)

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** Proposed Solution (ordered probe chain synthesized
from the issue's two candidate directions — `/v2/me` is load-bearing between
userinfo and the ACL probe, not optional), Cut List (tri-state return,
ACL-as-sole-fallback, eager parallel probes, token-shape heuristics all
recorded with rejection reasons), Guard Contract (403-advances vs
401-stops mutation coverage), Observability (inconclusive-vs-rejected warn
distinction).
**Research agents used:** none spawnable in this environment — deepen-plan's
conditional halt gates (4.6 user-brand, 4.7 observability, 4.8 PAT-shape, 4.9
UI-wireframe, 4.10 encryption, 4.11 guard-contract lint) were executed
mechanically and all pass; the per-section fan-outs were covered by inline
repo greps plus the live-probe evidence already recorded in #9188/#9183.

### Key Improvements

1. Chain order reasoned, not defaulted: `userinfo` → `/v2/me` →
   `organizationalEntityAcls` — member-liveness before org-capability, because
   the ACL endpoint itself requires `rw_organization_admin` (a Community-app
   token minted without it must still pass via `/v2/me`).
2. `401` short-circuit is explicit: a Bearer rejected at the auth layer is
   endpoint-independent — burning fallback calls on a dead token is waste and
   slows the rejection the user is waiting on.
3. "Probe could not measure" (transport throw / unexpected status) gets a
   `logger.warn` on the linkedin chain only — the definitive-rejection vs
   could-not-measure distinction is preserved in observability even though
   the `boolean` contract collapses both to `false`.
4. `redirect: "manual"` scoped to the linkedin probes — never follow a
   redirect with a Bearer attached (sibling-parity hardening), without
   changing redirect behavior for the twelve other providers.

### New Considerations Discovered

- `app/api/keys/route.ts:32` coerces `provider` to `"anthropic" | "openai"` —
  `linkedin` can only arrive via `app/api/services/route.ts:76`. The fix's
  blast radius is exactly one route.
- No server-side consumer reads the stored per-user `linkedin` row today
  (the publishing/community crons use env vars `LINKEDIN_ACCESS_TOKEN` /
  `LINKEDIN_ORG_ACCESS_TOKEN`, not `api_keys`). "Valid" on this surface
  therefore means "alive and grants some LinkedIn capability" — capability
  gating belongs to whichever consumer eventually reads the row.
- `test/token-validators.test.ts` runs in the vitest `unit` project
  (`test/**/*.test.ts`, vitest.config.ts:87) — NOT `REPO_WIDE_SUITES`; no
  registry edit needed, unlike the sibling's cron test.

## Overview

`apps/web-platform/server/token-validators.ts:54` probes
`https://api.linkedin.com/v2/userinfo` to validate the `linkedin` provider on
the Connected Services surface (`POST /api/services`). `/v2/userinfo` requires
the `openid` scope, which exists only on the Soleur developer app
(`clientId 78wtm2wu15iikn`). A token minted under the Soleur Community app
(`clientId 78s808ujpe6lve` — `w_organization_social`, `rw_organization_admin`,
analytics, NO `openid`) is a perfectly valid token that 403s userinfo and is
rejected to the user as "Token validation failed". Unlike the weekly cron
fixed in #9181/PR #9183 — where the env-var name tells the probe which app
minted the token — a pasted token's minting app is unknowable from the value,
so the remediation shape changes from a per-token probe table to an ordered,
capability-aware probe chain: `userinfo` first, and on exactly `403`
(scope-denied, not dead) fall back through `/v2/me` (member liveness) to
`organizationalEntityAcls` (org-admin capability — the same endpoint the cron
uses for the org token). A `2xx` from any probe means valid; `401` means
dead and stops the chain; anything else fails closed as it does today.

## Problem Statement / Motivation

One defect, verified live on 2026-09-28 during the #9181 remediation and
recorded in issue #9188:

- A Community-app org token returns `200` on
  `/v2/organizationalEntityAcls` and `/v2/me`, but `403 ACCESS_DENIED` on
  `/v2/userinfo`. Pasted into Command Center → Connected Services, it
  validates `false` and cannot be stored — a valid credential misclassified
  as invalid on a user-facing settings surface.

This is the same defect class as #9181 (probe endpoint must match the
token's minting app) on a different surface; #9181's plan explicitly deferred
it ("acknowledge + file a follow-up issue") because the keys/services surface
cannot key on an env-var name and needed a per-app decision the 9181 evidence
did not settle. #9188 is that follow-up.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9188` — OPEN, `type/bug`, `priority/p2-medium`, sole
  comment is automated triage. Body verbatim-matches the feature description
  (userinfo probe, two apps, live-verified probe matrix, two candidate
  directions). Not stale.
- `gh pr diff 9183` — merged sibling read in full: the remediation shape is
  a `TOKEN_PROBES` table keyed by env-var name (possible only because the
  cron knows which secret it holds), plus `redirect: "manual"`, fail-loud on
  unconfigured probes, `httpStatus` in log extras, and 401/403 both filing.
  The env-var key does not transfer to the pasted-token surface; the
  redirect hardening and the "403 = alive-but-scope-denied" reading do.
- `apps/web-platform/server/token-validators.ts` — full file reviewed (84
  lines). `VALIDATOR_CONFIGS.linkedin.url` is the only linkedin code point;
  `validateToken` returns `Promise<boolean>`, `res.ok` defines validity, a
  fetch throw collapses to `false`, timeout is 5s per call.
- Consumers swept (`hr-type-widening-cross-consumer-grep`, though no widening
  is proposed): `validateToken` has exactly two call sites —
  `app/api/services/route.ts:76` (the only route where `linkedin` is
  reachable; returns `{valid:false, error:"Token validation failed"}` on
  false) and `app/api/keys/route.ts:86` (provider coerced to
  `anthropic|openai` at L32 — linkedin unreachable). `waitlist.ts` matched
  the grep on a comment only. Return type stays `boolean`; both consumers
  keep working untouched.
- `server/providers.ts:22` — `linkedin` is in `PROVIDER_CONFIG` (category
  `social`) and NOT in `EXCLUDED_FROM_SERVICES_UI`, so the paste path exists.
  Its `envVar` (`LINKEDIN_ACCESS_TOKEN`) is informational — crons read env
  vars, not the per-user row.
- `test/token-validators.test.ts` — full file reviewed (151 lines). Global
  `fetch` stubbed via `vi.stubGlobal`; mocks resolve `{ok: boolean}` plain
  objects. New linkedin tests need `{ok, status}` shapes +
  `mockImplementation` keyed on URL — same pattern as the sibling's
  `mockLinkedInPerToken`.
- `apps/web-platform/infra/cron-egress-allowlist.txt:26` already contains
  `api.linkedin.com`, and the web route is not cron-egress-gated anyway —
  same host as today, no infra diff.
- ADR corpus: no ADR governs `token-validators.ts` (ADR-033 covers Inngest
  crons only — not triggered). No rejected alternative in the ADR corpus is
  re-proposed here.

### Property List (Phase 0.6b)

- P1: A Community-app org token (403 userinfo / 200 `/v2/me` / 200 ACL)
  validates `true` on the Connected Services surface.
- P2: A Soleur-app OIDC token (200 userinfo) still validates `true` in one
  probe — the common case pays zero extra calls.
- P3: A dead/invalid token still validates `false` — `401` anywhere is
  definitive and must not burn fallback probes.
- P4: "Probe could not measure" (transport error, timeout, 5xx, 429,
  unexpected 4xx) still returns `false` — the fix widens acceptance, it must
  never widen a couldn't-measure into a `true`.
- P5: Every other provider's verdict is byte-identical to today — no
  behavior change outside `linkedin`.

### Cut List (Phase 0.6b)

- Tri-state return (`valid | invalid | unknown`): rejected. It widens
  `Promise<boolean>` across both route consumers (and their response shapes /
  UI error copy) to buy a "try again later" distinction for a p2 settings
  surface. The rejected-vs-inconclusive distinction is preserved internally
  (control flow + a scoped warn log) without API change. If a future surface
  needs the distinction, widen then with the full consumer sweep.
- `organizationalEntityAcls` as the SOLE fallback (issue option 2 verbatim):
  rejected. The ACL probe requires `rw_organization_admin` (per the sibling
  plan's LinkedIn permissions-mapping citation) — a Community token minted
  with only `w_organization_social`/analytics would 403 ACL too and still be
  wrongly rejected. `/v2/me` (member liveness, verified 200 on the Community
  token) sits before ACL to catch that shape; ACL last catches the converse
  shape (org-admin-capable but member-read-denied).
- Probing all three endpoints eagerly (parallel `Promise.any` or serial
  unconditional): rejected — the OIDC path (P2) resolves on probe 1; eager
  probing triples LinkedIn call volume on the common case and makes the
  fetch-order assertions meaningless.
- Token-shape heuristics to detect the minting app (JWT decode, prefix
  sniffing): rejected — LinkedIn access tokens are opaque; there is no
  reliable local signal. The probe chain IS the detection.
- Marking the verdict "valid-but-member-only" (issue option 1's phrasing):
  cut — `is_valid` is a boolean column and the route returns `{valid}`; no
  capability field exists and no consumer reads one. Recording capability is
  a future concern for whichever feature consumes the stored row.
- `redirect: "manual"` on ALL providers: cut to linkedin scope — a provider
  whose probe URL legitimately redirects would flip true→false under manual;
  unrelated behavior change, not required by the issue. Worth a separate
  hardening sweep question, not this PR.
- `reportSilentFallback`/Sentry on inconclusive probes: cut — a
  user-submitted validation failure is surfaced to the caller
  (`{valid:false}`), not a silent fallback; `cq-silent-fallback-must-mirror-to-sentry`
  does not fire. A `logger.warn` on the linkedin chain's inconclusive
  outcomes is the proportionate signal (Sentry noise per user paste is not).

### Relevant files

- `apps/web-platform/server/token-validators.ts` — `ValidatorConfig`
  interface (L5-9), `VALIDATOR_CONFIGS.linkedin` (L53-56), `validateToken`
  fetch/verdict loop (L67-84), `VALIDATION_TIMEOUT_MS` (L3).
- `apps/web-platform/test/token-validators.test.ts` — global fetch stub
  (L5-6), existing linkedin single-probe test (L93-96), network-error and
  timeout cases (L134-142).
- `apps/web-platform/app/api/services/route.ts` — `validateToken` call site
  (L76) and the `{valid:false}` rejection response (L77-79); rate limiter
  10/min/user (L16-19).
- `apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts`
  — merged sibling: the ACL URL with its query params (the canonical string
  to reuse verbatim) and the `redirect: "manual"` rationale.

### Institutional learnings applied

- Sibling plan `2026-09-28-fix-linkedin-org-token-probe-plan.md` — the
  per-app scope table, the "403 = alive but missing scope" reading, the ACL
  probe's `rw_organization_admin` requirement, and `redirect: "manual"` all
  transfer. Its own "Adjacent surface" note IS this issue.
- `cq-assert-anchor-not-bare-token` — new tests assert fetch URLs and call
  order/count (content), not just the boolean verdict: a green suite must be
  impossible while the chain still single-probes userinfo.
- Learnings `2026-04-09-linkedin-org-access-token-*` /
  `2026-04-26-linkedin-org-token-fallback-silent-400` — personal-vs-org
  scope routing is a previously-paid-for lesson; this fix extends it to the
  pasted-token surface.

### Open Code-Review Overlap

- The sibling #9181 work is merged; `gh issue list --label code-review`
  overlap for `token-validators.ts` resolves to this issue (#9188) itself —
  no competing open work on the file.

### External research

Skipped — #9188's live-probe matrix (userinfo 403 / `/v2/me` 200 / ACL 200
for the Community token, measured 2026-09-28) is stronger than docs; the
sibling's permissions-mapping citation covers the ACL endpoint's
`rw_organization_admin` requirement.

## Proposed Solution

Extend `ValidatorConfig` with an ordered fallback chain that is consulted
only on `403`, and give `linkedin` a three-endpoint chain.

**`token-validators.ts`:**

```ts
interface ValidatorConfig {
  url: string | (() => string);
  headers: (token: string) => Record<string, string>;
  method?: string;
  /**
   * Ordered probe endpoints consulted ONLY when the preceding probe
   * returned exactly 403 — authenticated but scope-denied, meaning the
   * token's minting app simply doesn't offer the scope that endpoint
   * requires. 401 is definitive (a dead Bearer is dead on every endpoint)
   * and short-circuits; any other non-2xx fails closed.
   */
  fallbackUrls?: string[];
  /** Pinned on linkedin: never follow a redirect with a Bearer attached. */
  redirect?: "manual";
}
```

```ts
linkedin: {
  // Two LinkedIn developer apps exist — Soleur (OIDC: openid, profile,
  // w_member_social, email) and Soleur Community (Community Management:
  // w_organization_social, rw_organization_admin, analytics — no openid).
  // A pasted token's app is unknowable from the value, so probe in
  // widening order: openid userinfo, then member liveness, then org-admin
  // capability (#9188).
  url: "https://api.linkedin.com/v2/userinfo",
  fallbackUrls: [
    "https://api.linkedin.com/v2/me",
    "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED",
  ],
  redirect: "manual",
  headers: (token) => ({ Authorization: `Bearer ${token}` }),
},
```

`validateToken` becomes a loop over `[primary, ...fallbackUrls]`:

- `res.ok` → `return true` (first success wins).
- `res.status === 401` → `return false` (definitive — stops the chain).
- `res.status === 403` → advance to the next probe; chain exhausted →
  `return false` (alive but grants nothing Soleur can use).
- Any other non-2xx (incl. 3xx surfacing via `redirect:"manual"`, 429, 5xx)
  → `return false` — could not measure; fail closed, unchanged semantics.
- Fetch throw (transport/timeout) → `return false` — unchanged; the same
  `api.linkedin.com` host serves every probe, so a transport failure would
  repeat identically.
- One `AbortSignal.timeout(VALIDATION_TIMEOUT_MS)` shared across the whole
  chain — a single 5s budget total, not 5s per probe (worst case stays the
  same as today).
- On an inconclusive linkedin outcome (transport throw or unexpected
  status — NOT 401/all-403, which is a definitive user-facing rejection),
  emit `logger.warn` with `{fn, provider, stage/status}` — never the token.
  Scoped to the fallback-chain path so the other providers' silent-false
  semantics are byte-identical.

For a config without `fallbackUrls`, the loop executes exactly one probe
with the same timeout/headers/method as today — verdicts unchanged (P5).

**Why this order:** userinfo first because it is the Soleur app's endpoint
and the cheapest resolution of the common case. `/v2/me` before
`organizationalEntityAcls` because member liveness is the broader net — the
ACL probe itself requires `rw_organization_admin`, so a narrower Community
mint would 403 it yet still be a live, useful token. ACL last upgrades a
"member-read denied but org-admin capable" token to valid.

## Implementation Phases

### Phase 1 — Fallback-chain validator (TDD)

1. Update `apps/web-platform/test/token-validators.test.ts` FIRST
   (`cq-write-failing-tests-before`). Fetch mocks keyed per URL via
   `mockFetch.mockImplementation((url) => …)` returning `{ok, status}`
   shapes; new cases under the linkedin describe:
   - Community-shaped token: userinfo 403 → `/v2/me` 200 ⇒ `true`; assert
     fetch order `[userinfo, me]` and callCount 2.
   - userinfo 403 + `/v2/me` 403 + ACL 200 ⇒ `true`; assert all three URLs
     in order (org-capable-but-member-denied shape).
   - userinfo 403 + `/v2/me` 403 + ACL 403 ⇒ `false` (alive but grants
     nothing).
   - userinfo 401 ⇒ `false` AND callCount 1 (dead Bearer short-circuits —
     no fallback burn).
   - userinfo 200 ⇒ `true` AND callCount 1 (Soleur OIDC regression guard —
     existing test gains a callCount assertion).
   - userinfo 500 (or 429) ⇒ `false` AND callCount 1 (unexpected status
     does not trigger fallback; could-not-measure fails closed).
   - fetch throws on userinfo ⇒ `false` AND callCount 1 (transport —
     unchanged semantics).
   - `redirect: "manual"` present in the fetch init for every linkedin
     probe (init-shape assertion).
   - One non-linkedin provider sanity: github 403 ⇒ `false` callCount 1
     (no fallback chain ⇒ behavior identical, P5 pin).
   - Confirm the new tests are RED against the current implementation.
2. Edit `apps/web-platform/server/token-validators.ts`: `fallbackUrls` +
   `redirect` fields on `ValidatorConfig`, the linkedin chain config, the
   probe loop in `validateToken`, shared `AbortSignal.timeout`, scoped
   `logger.warn` on inconclusive linkedin outcomes.
3. Run the scoped suite with the package's actual runner — NOT `bun test`
   (`apps/web-platform/bunfig.toml` blocks bun discovery):
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/token-validators.test.ts`
   — confirmed GREEN. Typecheck:
   `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Files to Edit

- `apps/web-platform/server/token-validators.ts` — `ValidatorConfig`
  (L5-9), `linkedin` entry (L53-56), `validateToken` loop (L67-84).
- `apps/web-platform/test/token-validators.test.ts` — linkedin cases
  (L93-96 expand into a per-URL chain suite), network/timeout cases gain
  callCount assertions.

## Files to Create

- None.

## Technical Considerations

- **Binary contract kept:** `Promise<boolean>` unchanged — no union
  widening, no consumer sweep needed beyond the two verified call sites.
  The "rejected vs could-not-measure" distinction lives in control flow
  (401 stops vs 403 advances) plus the scoped warn log, not in the API.
- **Shared timeout budget:** one `AbortSignal.timeout(5000)` for the whole
  chain bounds worst-case linkedin validation at 5s — identical to today's
  single-probe worst case, and tighter than a naive 3×5s per-probe
  implementation. `AbortSignal.timeout` composes here because every probe
  shares the same deadline.
- **Sequential, not parallel:** ordered probes give deterministic
  fetch-order assertions and avoid tripling call volume on OIDC tokens
  (P2). The route's 10/min/user limiter makes the worst case ≤30
  LinkedIn calls/min/user — well under vendor limits.
- **No body validation on fallback probes:** parity with today — `res.ok`
  defines validity; asserting `/v2/me` or ACL JSON shape would add
  semantics the other providers don't have. (The cron validates `name`/
  `elements` because it displays `holder`; the validator has no such
  consumer.)
- **`/v2/me` availability caveat:** verified 200 for the all-scopes
  Community token (2026-09-28). A hypothetical Community mint that 403s
  `/v2/me` still gets a third chance at ACL; a mint that 403s all three
  can neither read members nor admin orgs — `false` is the correct verdict
  on a services surface.
- **Egress:** same host (`api.linkedin.com`) as today; allowlist already
  covers it (L26); no infra diff.
- **Sentry noise:** deliberately no `reportSilentFallback` — see Cut List.
- **Non-goals:** capability labeling ("valid-but-member-only") in the API
  response; global `redirect:"manual"`; tri-state verdict; touching the
  cron (already fixed) or `bootstrap.sh` (already fixed); UI copy changes
  ("Token validation failed" stays honest).
- **No new persistent store, no new cross-component connection, no new
  infrastructure** → Encryption Posture and IaC gates not triggered.
- **No architectural decision** — a defect fix on an existing validator;
  ADR/C4 gate not triggered.

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) a valid
  Community-app org token still rejected — the bug persists, or (b) worse,
  an invalid token accepted — a dead credential stored as "connected" and
  discovered only when a future consumer tries to use it. The mutation
  matrix's 401-short-circuit and all-403-reject cases exist to pin (b).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  the Bearer token rides the same `Authorization` header to the same host
  as today, plus two more same-host paths. `redirect: "manual"` removes
  the residual "vendor 30x re-targets the Bearer" vector rather than
  adding one. Token values are never logged (the warn carries provider +
  status only).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: a probe-endpoint change on an existing
  validation surface — no schema, no credential-handling change beyond
  two additional same-host GETs, no user-facing UI delta.`

## Observability

```yaml
liveness_signal:
  what: "POST /api/services returns {valid:true} for a Community-app linkedin token"
  cadence: "on user submission (rate-limited 10/min/user)"
  alert_target: "none — user-surfaced verdict, not a monitored job"
  configured_in: "apps/web-platform/server/token-validators.ts (linkedin probe chain)"
error_reporting:
  destination: "app logs via logger.warn — scoped to inconclusive linkedin outcomes (transport throw or unexpected non-2xx/401/403 status); NOT Sentry (user-surfaced, not silent)"
  fail_loud: "definitive rejection (401, or 403 on all three probes) returns {valid:false} to the caller; could-not-measure returns {valid:false} plus the warn breadcrumb"
failure_modes:
  - mode: "Community-app token pasted (no openid)"
    detection: "userinfo 403 -> /v2/me or ACL 2xx -> valid"
    alert_route: "none needed — success path"
  - mode: "token minted with unusable scope set (403 x3)"
    detection: "chain exhausted -> {valid:false}"
    alert_route: "user-facing rejection"
  - mode: "api.linkedin.com unreachable / timeout"
    detection: "fetch throw or timeout -> {valid:false} + logger.warn breadcrumb"
    alert_route: "app logs"
logs:
  where: "web-platform server logs (logger.warn, fn=validateToken, provider=linkedin, stage status)"
  retention: "platform log retention"
discoverability_test:
  command: "grep -l organizationalEntityAcls apps/web-platform/server/token-validators.ts"
  expected_output: "token-validators.ts"
```

## Guard Contract

### Guard 1 — Capability-aware probe fidelity

**Property.** A pasted LinkedIn token validates `true` iff it is alive and
grants at least one capability the probes can measure — regardless of which
developer app minted it — and `false` iff it is dead (401) or
scope-empty (all probes 403) or unmeasurable, with the common OIDC path
resolved in exactly one probe.

**Assembly.** Chokepoint (runtime): the `[primary, ...fallbackUrls]` probe
loop inside `validateToken` — the only path to a linkedin verdict.
Chokepoint (config): the `linkedin` entry's ordered `fallbackUrls`. The
test file's per-URL mocks, fetch-order assertions, and callCount pins are
the enforcement layer.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert linkedin to userinfo-only (drop `fallbackUrls`) | RED — Community-shaped tests fail (403→200 chain unresolved) |
| 2 | Advance the chain on ANY non-ok (or on 401) instead of 403-only | RED — the 401 short-circuit test asserts callCount 1; the 500 test asserts callCount 1 |
| 3 | Stop the chain after `/v2/me` (drop ACL) | RED — the 403/403/200 case asserts `true` and a third fetch to the ACL URL |
| 4 | Reorder fallbacks (ACL before `/v2/me`) | RED — fetch-order assertion expects `[userinfo, me, acl]` |
| 5 | Treat fetch throw as "try next probe" | RED — transport test asserts callCount 1 (same-host failure repeats) |
| 6 | Remove `redirect: "manual"` | RED — init-shape assertion on fetch options |
| 7 | Mutate the TEST mock to answer 200 for any URL | RED — order/callCount assertions fail because URL predicates no longer discriminate |
| 8 | Must-PASS variant: userinfo 200, fallbacks unreachable | PASS — `true` with callCount 1 (OIDC regression) |
| 9 | Must-PASS variant: github (no `fallbackUrls`) returns 403 | PASS — `false` with callCount 1 (P5: untouched providers identical) |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a probe-endpoint change inside an
existing validator behind an existing authenticated route. No UI-surface
files in Files to Edit; no regulated-data surface (GDPR gate skipped —
the pasted token is encrypted-at-rest by the unchanged downstream path);
no new infrastructure (IaC gate skipped).

## Acceptance Criteria

- [ ] `validateToken("linkedin", …)` resolves `userinfo` → 403 → `/v2/me`
  → 403 → `organizationalEntityAcls` in that order; `2xx` from any probe
  returns `true`.
- [ ] `401` on any probe returns `false` immediately (single fetch).
- [ ] `403` on all three probes returns `false`.
- [ ] Any other non-2xx or a fetch throw returns `false` without probing
  further; inconclusive linkedin outcomes emit one `logger.warn` (no token
  value).
- [ ] Providers without `fallbackUrls` behave byte-identically (single
  probe, same timeout/headers, no redirect option change).
- [ ] `redirect: "manual"` on every linkedin probe fetch.
- [ ] Whole linkedin chain shares one 5s `VALIDATION_TIMEOUT_MS` budget.
- [ ] `test/token-validators.test.ts` covers the matrix above with
  per-URL mocks + order/callCount assertions; suite GREEN under
  `./node_modules/.bin/vitest run`.
- [ ] `Closes #9188` in the PR body.

## Test Scenarios

- Given a Community-app token (userinfo 403, `/v2/me` 200), when the user
  pastes it into Connected Services, then `validateToken` returns `true`
  after exactly two probes.
- Given a Community-app token that cannot read members (userinfo 403,
  `/v2/me` 403, ACL 200), when validated, then it returns `true` after
  three probes in order.
- Given a dead token (userinfo 401), when validated, then `false` with no
  fallback probes burned.
- Given an alive token with no usable scope (403 on all three), when
  validated, then `false`.
- Given LinkedIn returns 429 or 500 on userinfo, when validated, then
  `false` and no fallback is attempted (could-not-measure fails closed).
- Given a Soleur OIDC token (userinfo 200), when validated, then `true`
  with exactly one fetch — zero regression on the existing path.

## Success Metrics

- A Community-app org token pasted into Command Center → Connected
  Services validates and stores successfully (`{valid:true}`).
- No change in verdict distribution for other providers (P5 holds; the
  github-403 pin test is the mechanical check).

## Dependencies & Risks

- **Risk — endpoint drift:** if LinkedIn changes `/v2/me` or ACL
  semantics, a formerly-valid shape could regress to all-403 → `false` —
  which is the pre-fix behavior anyway, so drift can only cost the NEW
  acceptance, never a false `true`.
- **Risk — `/v2/me` scope requirement narrowing:** the 200 evidence is
  for an all-scopes Community mint; a narrower mint 403ing `/v2/me` is
  still caught by ACL. The only unrecoverable shape is a token that can
  do nothing the probes measure — correctly `false`.
- **Latency:** worst case adds ~2 RTTs to `api.linkedin.com` only for
  tokens that 403 — bounded by the shared 5s signal.
- **Sharp edge:** a green suite that only asserts the boolean verdict is
  insufficient — the fetch-order/callCount assertions are load-bearing:
  they are what makes "fallbackUrls deleted" RED.
- **Sharp edge:** `mockFetch.mockImplementation` must key on URL, not just
  sequence, or a reordered-but-equivalent chain passes silently.

## References & Research

- Issue: `gh issue view 9188` (live-verified probe matrix 2026-09-28,
  two candidate directions, `Mandated-By: wg-when-an-audit-identifies-pre-existing`).
- Sibling: `gh pr diff 9183` (merged) — per-token probe table, ACL URL
  with query params, `redirect: "manual"`, 401/403 semantics; and
  `knowledge-base/project/plans/2026-09-28-fix-linkedin-org-token-probe-plan.md`
  (template shape; "Adjacent surface" disposition that became this issue).
- `apps/web-platform/server/token-validators.ts` — full file (84 lines).
- `apps/web-platform/test/token-validators.test.ts` — full file (151 lines).
- `apps/web-platform/app/api/services/route.ts` (L76 call site, L16-19
  limiter) and `app/api/keys/route.ts` (L32 provider coercion).
- `apps/web-platform/server/providers.ts` (L22 linkedin, L28 exclusions).
- LinkedIn org-ACL contract (per sibling's deepen-plan check):
  `GET /v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED`
  requires `rw_organization_admin`-class access — hence its position LAST
  in the chain, not as the sole fallback.

## Pipeline-mode disclosures

- Research fan-outs, domain-leader spawns, spec-flow, scoped advisor
  consult, and the plan-review panel were performed inline by the planning
  agent — this environment exposes no Task/Skill spawn tool. Headless
  rules applied throughout (no AskUserQuestion pauses).
- `lane:` defaulted to `cross-domain` — no `spec.md` exists for this
  branch to carry a `lane:` from (TR2 fail-closed per plan skill).
- Advisor-consult note: change is a config-driven probe-chain extension on
  an already-reviewed validator; the design forks (chain vs table,
  tri-state vs boolean, `/v2/me` vs ACL ordering) are decided inline with
  their rejected alternatives recorded in the Cut List and Proposed
  Solution.
