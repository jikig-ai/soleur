---
title: "fix: linkedin-token-check org-token probe and generator URL assume wrong app"
date: 2026-09-28
slug: fix-linkedin-org-token-probe
branch: feat-one-shot-9181-linkedin-org-token-probe
issue: 9181
closes: 9181
type: fix
lane: cross-domain
brand_survival_threshold: none
---

# fix: linkedin-token-check org-token probe and generator URL assume wrong app

## Enhancement Summary

**Deepened on:** 2026-09-28
**Sections enhanced:** Proposed Solution (probe resolution fail-loud rule,
`httpStatus` observability, rejected `insufficient_scope` alternative), scope
lists (`rw_organization_admin` named as the ACL probe's own requirement),
References (OpenAPI/permissions-mapping citation).
**Research agents used:** none spawnable in this environment — deepen-plan's
conditional halt gates (4.6 user-brand, 4.7 observability, 4.8 PAT-shape, 4.9
UI-wireframe, 4.10 encryption, 4.11 guard-contract lint) were executed
mechanically and all pass; the per-section fan-outs were covered by inline
repo greps + one external contract check.

### Key Improvements

1. Missing-`TOKEN_PROBES`-entry behavior specified (fail loud via
   `reportSilentFallback` + `unknown`, never a default endpoint).
2. `403` filing carries `httpStatus` in log extras so the 401-vs-403
   distinction survives enum sharing.
3. Renewal scope text names both mandatory Community-app scopes
   (`w_organization_social` + `rw_organization_admin`).

### New Considerations Discovered

- `organizationalEntityAcls` requires `rw_organization_admin`-class access
  (LinkedIn permissions mapping) — a Community-app token minted with only
  `w_organization_social` would still 403 the probe; "all offered scopes" is
  the correct runbook instruction.
- Inngest `step.run` memoization constraint: `check-tokens`' return shape is
  deliberately unchanged (`TokenCheckResult[]`) so in-flight runs resume
  cleanly post-deploy.

## Overview

The weekly LinkedIn token check and the renewal bootstrap script were written
when a single LinkedIn developer app existed. There are now two: the Soleur
app (clientId `78wtm2wu15iikn`, OIDC scopes only: `openid`, `profile`,
`w_member_social`, `email`) and the Soleur Community app (clientId
`78s808ujpe6lve`, Community Management API scopes: `w_organization_social`,
`rw_organization_admin`, org/member analytics + feed). Both artifacts hardcode
the Soleur-app generator URL, and the cron probes BOTH secrets against
`api.linkedin.com/v2/userinfo`, which requires `openid` — a scope the Community
app does not offer. A correctly minted org token therefore fails the probe
forever: issue #7606 stays open indefinitely and the weekly check can never
auto-close it. This plan makes the probe and the renewal guidance per-token:
the org token is probed against an org-capable endpoint
(`organizationalEntityAcls`, verified HTTP 200 for org `129094054` on
2026-09-28) and the runbooks point each token at the app that can actually
mint it.

## Problem Statement / Motivation

Two coupled defects, both verified live during the 2026-09-28 renewal session
(issue #9181):

1. **Wrong clientId in renewal paths.** The cron's generated issue-body runbook
   (`cron-linkedin-token-check.ts`, the "Renewal steps" text) and
   `knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh`
   (`TOKEN_GENERATOR_URL`) both send the operator to the token generator with
   `clientId=78wtm2wu15iikn`. A token minted under the Soleur app can never
   carry `w_organization_social`, so following the runbook for the org secret
   produces a token that fails at post time.

2. **Probe assumes `openid`.** The cron runs `checkToken` against
   `https://api.linkedin.com/v2/userinfo` for BOTH secrets. `userinfo` requires
   `openid`; the Community-app org token gets a stable `403 ACCESS_DENIED`,
   which the current code maps to status `unknown` — no issue comment, no
   auto-close, ok heartbeat. The same wrong endpoint is baked into
   `bootstrap.sh`'s `token_probe` (used by both mint stages, the Doppler reuse
   ladder, and stage-4 verify), so a future renewal would reject-or-pass the
   org token on the wrong criterion, and `stage_2_org`'s separate ACL probe is
   advisory-only (warns, never gates).

Blocking relationship: #7606 (`[Action Required] LinkedIn OAuth token has
expired (LINKEDIN_ORG_ACCESS_TOKEN)`) intentionally stays open until the fixed
probe passes — it is the cron's own auto-close target, and this fix is what
unblocks it. #7404 (personal token) already auto-closes when its probe passes
because the personal token legitimately carries `openid`.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9181` — OPEN, body verbatim-matches the feature description
  (two defects + "Verified this session" block). Not stale.
- `gh issue view 7606` — OPEN (`[Action Required] LinkedIn OAuth token has
  expired (LINKEDIN_ORG_ACCESS_TOKEN)`). Parent stays open by design until the
  fixed probe auto-closes it.
- `gh issue view 9146` — OPEN (`operator-bootstrap template: --help skip-var
  derivation misses credential-entry vars`). Explicitly OUT OF SCOPE; the
  LinkedIn-specific logic being fixed lives in the generated `bootstrap.sh`,
  not in `plugins/soleur/skills/operator-bootstrap/template.sh` (verified:
  `template.sh`/`SKILL.md` contain no `token_probe`, `TOKEN_GENERATOR_URL`, or
  `userinfo` references), so this work cannot regress or depend on #9146.
- Cited files exist on `origin/main`:
  `apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts`
  (clientId literal at the "Renewal steps" body; `LINKEDIN_USERINFO_URL` const
  consumed by `checkToken` for both tokens) and
  `knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh`
  (`TOKEN_GENERATOR_URL` ~L254; `token_probe` ~L274; advisory ACL probe in
  `stage_2_org` ~L457).
- `78wtm2wu15iikn` occurs in exactly the two named files (grep, worktree);
  `78s808ujpe6lve` currently occurs nowhere in code — only in issue/KB text.
- ADR corpus check: `grep -rln linkedin knowledge-base/engineering/architecture/decisions/`
  → ADR-033 only (Inngest cron invariants: Octokit+fetch inside `step.run`,
  deterministic return shape). The fix preserves all three invariants; no
  rejected alternative is being re-proposed.

### Property List (Phase 0.6b)

- P1: A correctly minted Community-app org token reports `valid` from the
  weekly check, so #7606 auto-closes.
- P2: A wrongly minted org token (live but missing `w_organization_social`)
  surfaces as actionable, not silent — this defect class (a 403 read as
  "unknown" forever) is what the fix exists to kill.
- P3: Each renewal path names the generator URL of the app that can mint that
  token (Soleur app for the personal token, Community app for the org token).
- P4: The bootstrap script's pre-persist probe uses the same per-token
  endpoint the cron uses, so "passed bootstrap" implies "will pass the cron".

### Cut List (Phase 0.6b)

- Probing BOTH tokens against `/v2/me` for liveness — rejected: `/v2/me`
  proves liveness but not org capability, and its scope requirement
  (`r_liteprofile`/Sign-In product) is unverified for the Soleur-app personal
  token; per-token probes buy P1+P2 with no new assumption. (`/v2/me` remains
  the named fallback endpoint in the issue body if `organizationalEntityAcls`
  ever drifts.)
- Asserting `LINKEDIN_ORG_ID` (`129094054`) membership inside the ACL
  `elements` — rejected for this fix: it adds a new env dependency to the
  cron and a new failure shape; the issue asks for an org-capable endpoint
  probe, not an ACL-content assertion. Element count is logged, not gated.
- Editing `plugins/soleur/skills/operator-bootstrap/template.sh` — cut:
  #9146 owns the template defect, and no LinkedIn logic lives there.
- Editing `apps/web-platform/server/token-validators.ts` (`linkedin` provider
  probes userinfo for the keys/services API surface) — see "Adjacent surface"
  below; acknowledged, not folded.
- Editing `plugins/soleur/skills/community/scripts/linkedin-setup.sh` (uses
  userinfo to derive `person_id` from the personal token) — out of scope: it
  intentionally operates on the Soleur-app personal token where `openid` is
  legitimately present.

### Relevant files

- `apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts` —
  `LINKEDIN_USERINFO_URL` (L30), `checkToken` (L42-170), renewal body
  (L71-92, wrong clientId at L80, wrong org scope list at L83), handler
  (L176-240), `ok` heartbeat calc (L229).
- `apps/web-platform/test/server/inngest/cron-linkedin-token-check.test.ts` —
  fetch mocks keyed on the userinfo URL (L127, 148, 189, 224, 258, 286),
  source-anchor suites (L329-368) that currently ANCHOR the wrong endpoint.
- `knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh` —
  `TOKEN_GENERATOR_URL` (L254), `LINKEDIN_USERINFO`/`LINKEDIN_ORG_ACLS` consts
  (L255-256), `token_probe`/`token_is_live` (L274-287), `mint_or_reuse`
  signature + probe call (L324-384), `stage_1_personal` (L434), `stage_2_org`
  incl. advisory ACL block (L448-474), `stage_4_verify` live checks (L591-605),
  scope-table header comment (L236-240), closeout text (L631-635).
- `apps/web-platform/infra/cron-egress-allowlist.txt` — already contains
  `api.linkedin.com` (L26): the new endpoint is the same host, no egress or
  Terraform change.

### Institutional learnings applied

- `2026-04-09-linkedin-org-access-token-for-company-page-posts.md` /
  `2026-04-26-linkedin-org-token-fallback-silent-400.md` — personal vs org
  token scope routing is a previously-paid-for lesson (`w_organization_social`
  is required for `urn:li:organization:*` authors); this fix extends the same
  scope-awareness to the probe layer.
- `cq-assert-anchor-not-bare-token` / the file's own anchor-suite convention —
  new anchors assert content (the org endpoint, the Community clientId), and
  behavioral tests assert per-token probe routing, not just presence.
- Adjacent surface (same defect class, NOT folded):
  `apps/web-platform/server/token-validators.ts:54` probes userinfo for the
  `linkedin` provider used by `app/api/keys/route.ts` / `services/route.ts`.
  A Community-app token pasted there would also 403, but the correct endpoint
  depends on which app minted the pasted token and the issue does not name
  this file. **Disposition: acknowledge + file a follow-up issue** during work
  (candidate approach: userinfo → on 403 retry `/v2/me`; needs a per-app
  decision the 9181 evidence does not settle).

### Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies checked for all
four candidate paths (cron file, its test, bootstrap.sh, token-validators.ts):
zero matches.

### External research

Skipped — the issue's "Verified this session" block is live-probe evidence
stronger than docs; LinkedIn's own scope docs would only restate it.

## Proposed Solution

Make the probe endpoint and the renewal metadata per-token, driven by the
env-var name, in both artifacts.

**Cron (`cron-linkedin-token-check.ts`):**

- Replace `LINKEDIN_USERINFO_URL` with a per-token probe table, e.g.

  ```ts
  const TOKEN_PROBES: Record<string, { url: string; app: string }> = {
    LINKEDIN_ACCESS_TOKEN: {
      url: "https://api.linkedin.com/v2/userinfo",
      app: "Soleur",
    },
    LINKEDIN_ORG_ACCESS_TOKEN: {
      url: "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED",
      app: "Soleur Community",
    },
  };
  ```

- `checkToken` resolves its probe from `tokenName` (or takes the URL as a
  parameter — pick one; the signature records the decision). A `tokenName`
  absent from the table must fail LOUD — `reportSilentFallback` + status
  `unknown`, never a default endpoint: probing a future token at the wrong
  endpoint is exactly the defect class being removed. `holder` for the ACL
  response reads `elements` length instead of `name` (ACL payload shape is
  `{elements: [{organizationalTarget, role, state}], paging}` per LinkedIn's
  OpenAPI — no `name` field), e.g. `holder: "<n> administered org(s)"`.
- Filing rule: `401` → `expired` (unchanged semantics); `403` on the resolved
  probe → also files the SAME issue title (dedup by title keeps #7606's
  auto-close path single-threaded) but the body names the actual HTTP code and
  says what it means: `403` on an org endpoint = token alive but missing the
  app's scopes → re-mint WITH the listed scopes. A wrong-scope token is not
  "unknown" — that was the silent-failure mode. Non-401/403 non-2xx stays
  `unknown`. The result carries `httpStatus` in its logger `extra` so the
  401-vs-403 distinction survives into Inngest logs even though both share the
  `expired` status.
- **Rejected alternative — a new `insufficient_scope` status member:** more
  honest enum semantics, but it widens `TokenCheckResult` (consumer sweep:
  the `ok` calc and every test matcher), splits the dedup/auto-close lifecycle
  across two titles unless carefully keyed, and buys nothing operational —
  the filed body + `httpStatus` carry the distinction.
- Renewal body becomes per-token: generator URL `clientId=78wtm2wu15iikn` +
  `openid, profile, w_member_social, email` for `LINKEDIN_ACCESS_TOKEN`;
  `clientId=78s808ujpe6lve` + "all scopes the Community app offers —
  `w_organization_social` (org posting) and `rw_organization_admin` (the
  ACL probe's own scope requirement) are mandatory" for
  `LINKEDIN_ORG_ACCESS_TOKEN`.

**Bootstrap (`bootstrap.sh`):**

- Split `TOKEN_GENERATOR_URL` into `TOKEN_GENERATOR_URL_PERSONAL`
  (`78wtm2wu15iikn`) and `TOKEN_GENERATOR_URL_ORG` (`78s808ujpe6lve`).
- `token_probe <value> <url>` and `token_is_live <value> <url>` take the
  endpoint as a parameter; `mint_or_reuse` gains `<probe-url>` and
  `<generator-url>` params (keep the `SOLEUR_BOOTSTRAP_*` skip-var token on
  the same call line — `usage()` derives skip vars by grepping the
  `mint_or_reuse` line). Messages name the endpoint instead of hardcoding
  "userinfo".
- `stage_1_personal` passes the userinfo probe + Soleur generator URL +
  existing scope list. `stage_2_org` passes the ACL probe + Community
  generator URL + a corrected scope line (all offered Community scopes;
  `w_organization_social` and `rw_organization_admin` mandatory — the second
  is the ACL probe's own requirement) — and the now-redundant advisory ACL
  block is removed because the primary probe IS the ACL probe.
- `stage_4_verify` probes each Doppler value at its per-token endpoint (the
  `(userinfo 2xx)` message text is parameterized).
- Header scope-table comment and stage-4 closeout prose updated to name the
  per-token endpoints (they currently claim the cron calls userinfo for both).

**Tests (`cron-linkedin-token-check.test.ts`):**

- Fetch mocks become per-URL: userinfo serves the personal token, ACL URL
  serves the org token. Existing tests updated accordingly.
- New: org token ACL `200` → `valid` + auto-close path; ACL `401` →
  `expired` + filing; ACL `403` → filing (wrong-scope path) with the
  Community-app generator URL in the body; personal token still probes
  userinfo (routing assertion on fetch calls, not just status).
- Source anchors: add `organizationalEntityAcls` and `78s808ujpe6lve`; keep
  the `userinfo` anchor (still the correct endpoint for the personal token).
- Bootstrap anchors: a small block in the same test file (the repo already
  has tests reading `knowledge-base/project/specs/...` paths) asserting
  `bootstrap.sh` contains `78s808ujpe6lve`, that `stage_2_org`/`mint_or_reuse`
  routes the org token through `LINKEDIN_ORG_ACLS`, and that
  `token_probe` is endpoint-parameterized.

## Implementation Phases

### Phase 1 — Cron per-token probe + renewal body (TDD)

1. Update `cron-linkedin-token-check.test.ts` FIRST (`cq-write-failing-tests-before`):
   per-URL fetch mocks, org-403 filing test, probe-routing assertions, new
   source anchors, bootstrap.sh anchor block. Confirm the new tests are RED.
2. Edit `cron-linkedin-token-check.ts`: probe table, `checkToken` resolution,
   403 filing path with HTTP-code-aware body, per-token renewal steps.
3. Run the scoped suite with the package's actual runner — NOT `bun test`
   (`apps/web-platform/bunfig.toml` blocks bun discovery):
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-linkedin-token-check.test.ts`
   — confirmed GREEN. Typecheck:
   `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Phase 2 — Bootstrap script per-token probes

1. Edit `bootstrap.sh`: split generator URL, parameterize `token_probe`/
   `token_is_live`/`mint_or_reuse`, fix `stage_2_org` (probe param + remove
   advisory block + scope text), fix `stage_4_verify`, update comments/prose.
2. `bash -n` syntax check; run the script's `--help` and confirm skip-var
   derivation still lists `SOLEUR_BOOTSTRAP_LINKEDIN_*` tokens (do NOT run the
   script's stages — they mint/write live credentials).
3. Keep edits confined to the LinkedIn-specific stage block — the library
   contract above `main()` and the operator-bootstrap template are untouched
   (#9146 is out of scope).

### Phase 3 — Follow-up filing + closeout wiring

1. File the `token-validators.ts` adjacent-surface tracking issue (label
   `code-review` — verified extant via `gh issue list --label code-review`;
   body names `token-validators.ts:54` and the dual-probe candidate approach).
2. PR body uses `Closes #9181` (this PR fully resolves the two named code
   defects). It does NOT list `Closes #7606` — that issue is the cron's own
   dedup/auto-close target and closes itself once the deployed probe passes.
3. Deploy-gated verification (executed by the pipeline, not handed off —
   `gh workflow run` / the repo's `trigger-cron` path is agent-executable):
   once a release carrying this diff is live, dispatch
   `cron/linkedin-token-check.manual-trigger` and confirm #7606 receives the
   "is valid. Auto-closing." comment. The PR body describes this as a
   verification note — worded without the `ship-operator-step-gate.sh` deny
   tokens (`Operator`/`Post-merge`/`Follow-up` headers or operator-action
   bullets), since `ship` full-replaces the body from diff analysis.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts` —
  probe table (~L30), `checkToken` (L42-170), renewal body (L71-92).
- `apps/web-platform/test/server/inngest/cron-linkedin-token-check.test.ts` —
  fetch mocks, new behavioral + anchor tests.
- `knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh` —
  generator URL (L254), probe functions (L274-287), `mint_or_reuse`
  (L324-384), stages 1/2/4, scope-table comment (L236-240), closeout prose
  (L631-635).

## Files to Create

- None. (The follow-up issue is a tracker artifact, not a repo file.)

## Technical Considerations

- **ADR-033 invariants preserved:** all fetch/Octokit calls remain inside
  `step.run`; no new spawns; deterministic result shape. `TokenCheckResult`
  gains no new enum member (403 shares the `expired` filing path with a
  code-aware body — the union stays 5 values, `ok` calc unchanged). The
  `check-tokens` step's memoized return shape (`TokenCheckResult[]`) is
  unchanged, so a run memoized under the old code resumes cleanly on the new
  code after the deploy drain.
- **Emit-site coupling check:** the `reportSilentFallback` op tag is renamed
  (`fetch-userinfo` → per-probe) — swept consumers:
  `git grep -rn "fetch-userinfo" apps/web-platform/infra/` returns zero (no
  Sentry alert filters on it), so renaming darks nothing.
- **Egress:** `api.linkedin.com` is already in `cron-egress-allowlist.txt` —
  same host, no infra diff.
- **Rate limits:** one additional LinkedIn call is NOT introduced — the same
  count of fetches, different URL for the org leg.
- **`unknown` semantics kept** for transport errors and non-401/403 non-2xx
  (429 rate-limit, 5xx): those still must not file spurious issues.
- **JSON validation guard:** ACL responses are `{elements: [...], paging}` —
  `holder` extraction must tolerate a missing `name` without tripping
  `invalid_json` on a valid response.
- **Non-goals:** operator-bootstrap template fix (#9146); `token-validators.ts`
  linkedin provider (follow-up issue); `linkedin-setup.sh` person-id lookup;
  editing the historical `feat-linkedin-token-renewal/spec.md` (point-in-time
  record — its prose describing the old probe is correct as history).
- **No new persistent store, no new cross-component connection, no new
  infrastructure** → Encryption Posture and IaC gates not triggered.
- **No architectural decision** — a defect fix on an existing probe surface;
  ADR/C4 gate not triggered. A future engineer reading ADR-033 + the C4 is not
  misled by this change.

## User-Brand Impact

- **If this lands broken, the user experiences:** continued weekly
  `action-required` noise (or silence) about a LinkedIn token that is actually
  healthy — and, worse, org posting stays down while the monitor reports
  nothing actionable, repeating the exact silent-failure class this fix
  removes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure — the change reads the same two secrets at the same host
  (`api.linkedin.com`) over the same Authorization-header path; no token value
  is logged or persisted.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: this modifies an ops-monitoring probe and its
  runbook text only — no user-facing surface, no data model, and the only
  credential handling (Bearer header to api.linkedin.com) is unchanged.`

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor scheduled-linkedin-token-check (postSentryHeartbeat, ok=false when any token result is expired-class)"
  cadence: "weekly Monday 11:00 UTC + on-demand cron/linkedin-token-check.manual-trigger"
  alert_target: "Sentry monitor + deduplicated GitHub action-required issue per tokenName"
  configured_in: "apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts (SENTRY_MONITOR_SLUG, filing + auto-close paths)"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature=cron-linkedin-token-check, op=fetch-userinfo renamed to a per-probe op tag)"
  fail_loud: "401/403 on a token's resolved probe files or comments the token's action-required issue; network errors reportSilentFallback + status=unknown"
failure_modes:
  - mode: "org token minted under wrong app / missing w_organization_social"
    detection: "organizationalEntityAcls returns 403 -> filed issue with Community-app generator URL (NOT silent unknown)"
    alert_route: "GitHub issue label action-required + Sentry heartbeat ok=false"
  - mode: "expired token (either)"
    detection: "401 on the per-token probe -> deduplicated issue comment or create"
    alert_route: "GitHub issue label action-required + Sentry heartbeat ok=false"
  - mode: "api.linkedin.com unreachable / TLS-intercepting proxy"
    detection: "fetch throw -> reportSilentFallback + result status=unknown, heartbeat ok=true (transport is not a token defect)"
    alert_route: "Sentry issue"
logs:
  where: "Inngest run logs (logger.info per-token status incl. probe outcome)"
  retention: "Inngest retention window"
discoverability_test:
  command: "grep -l organizationalEntityAcls apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts"
  expected_output: "cron-linkedin-token-check.ts"
```

## Guard Contract

### Guard 1 — Per-token probe fidelity

**Property.** Each LinkedIn secret is probed at an endpoint its minting app
can authorize (`LINKEDIN_ACCESS_TOKEN` → userinfo; `LINKEDIN_ORG_ACCESS_TOKEN`
→ organizationalEntityAcls), and each generated renewal runbook names that
app's token-generator clientId.

**Assembly.** Chokepoint 1 (runtime probe): the `TOKEN_PROBES` lookup inside
`checkToken` — every token check must resolve its endpoint through the table.
Chokepoint 2 (operator probe): `token_probe`/`token_is_live` in bootstrap.sh —
every liveness call (mint verify, Doppler reuse ladder, stage-4 verify) passes
a per-stage endpoint. Chokepoint 3 (runbook text): the renewal-body generator
in the cron + the `TOKEN_GENERATOR_URL_*` constants in bootstrap.sh. The test
file's source-anchor + fetch-routing assertions are the enforcement layer.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Point `LINKEDIN_ORG_ACCESS_TOKEN`'s probe back at `v2/userinfo` in the cron | RED — routing test asserts the org check fetched the ACL URL |
| 2 | Delete the `LINKEDIN_ORG_ACCESS_TOKEN` entry from `TOKEN_PROBES` so org falls back to userinfo | RED — guard's own dispatch: a missing entry must fail an assertion, not silently default |
| 3 | In bootstrap.sh, make `stage_2_org` pass `LINKEDIN_USERINFO` as its probe | RED — source anchor asserts the org stage routes through `LINKEDIN_ORG_ACLS` |
| 4 | Revert the org renewal line to `clientId=78wtm2wu15iikn` (cron body or bootstrap `TOKEN_GENERATOR_URL_ORG`) | RED — anchors assert `78s808ujpe6lve` is present on the org path |
| 5 | Mutate the TEST mock to answer 200 for any URL | RED — the routing assertion fails because the URL predicate no longer discriminates |
| 6 | Must-PASS variant: ACL `200` with `{"elements":[]}` (valid scope, zero administered orgs) still reports `valid` | PASS — 2xx defines validity for this probe; membership assertion is explicitly out of scope (see Cut List) |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — an ops-monitoring fix on an existing
cron plus a generated operator script. No UI-surface paths in Files to Edit
(mechanical override did not fire); no regulated-data surface (GDPR gate
skipped); no new infrastructure (IaC gate skipped).

## Acceptance Criteria

- [ ] `checkToken` resolves its probe endpoint per token name:
  `LINKEDIN_ACCESS_TOKEN` → `https://api.linkedin.com/v2/userinfo`;
  `LINKEDIN_ORG_ACCESS_TOKEN` →
  `https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED`.
- [ ] A `401` on either resolved probe files/comments the token's
  `[Action Required] ...` issue (unchanged); a `403` on either resolved probe
  also files, with the body naming the HTTP code and the wrong-scope meaning;
  other non-2xx stays `unknown`.
- [ ] A `2xx` org-probe result auto-closes an open
  `... (LINKEDIN_ORG_ACCESS_TOKEN)` issue via the existing dedup path — this
  is the mechanism that resolves #7606.
- [ ] The generated renewal body names `clientId=78wtm2wu15iikn` for
  `LINKEDIN_ACCESS_TOKEN` and `clientId=78s808ujpe6lve` for
  `LINKEDIN_ORG_ACCESS_TOKEN`, with the correct scope list per app.
- [ ] `bootstrap.sh`: `TOKEN_GENERATOR_URL` is split per app;
  `token_probe`/`token_is_live`/`mint_or_reuse` are endpoint-parameterized;
  `stage_2_org` probes the ACL endpoint as its decisive check (advisory block
  removed); `stage_4_verify` probes each token at its endpoint.
- [ ] `bash -n bootstrap.sh` clean; `bootstrap.sh --help` still derives
  `SOLEUR_BOOTSTRAP_LINKEDIN_ACCESS_TOKEN` / `SOLEUR_BOOTSTRAP_LINKEDIN_ORG_ACCESS_TOKEN`.
- [ ] Test file updated: per-URL mocks, org-403 filing case, probe-routing
  assertion, new anchors (`organizationalEntityAcls`, `78s808ujpe6lve`),
  bootstrap.sh anchor block; suite GREEN.
- [ ] Follow-up issue filed for `token-validators.ts` linkedin userinfo probe
  (adjacent same-class surface, out of 9181's scope).
- [ ] `Closes #9181` in the PR body. #7606 is NOT in the PR's closes list —
  it closes via the deployed cron, not this merge.

## Test Scenarios

- Given `LINKEDIN_ORG_ACCESS_TOKEN` returns `401` on the ACL URL, when the
  cron runs, then the org action-required issue is filed/commented with the
  Community-app generator URL in the body and `ok` is false.
- Given the org token returns `403` on the ACL URL (valid token, missing
  scope), when the cron runs, then the issue is still filed (not `unknown`)
  and the body explains the missing-scope meaning.
- Given the org token returns `200` `{"elements":[...]}`, when the cron runs
  with an open `... (LINKEDIN_ORG_ACCESS_TOKEN)` issue, then the issue is
  commented + closed (`#7606` recovery path).
- Given `LINKEDIN_ACCESS_TOKEN` returns `200` on userinfo while the org leg
  fails, when the cron runs, then only the org issue is filed — per-token
  isolation preserved.
- Given `bootstrap.sh --help`, when a future renewal is needed, then the
  derived skip-var list still names both `SOLEUR_BOOTSTRAP_LINKEDIN_*` vars.
- Given a TLS-intercepted or offline environment, when `token_probe` curls
  the ACL URL and fails transport, then it reports `transport` (not
  `rejected`) — tri-state preserved for the new endpoint.

## Success Metrics

- On the first deployed run (weekly or manual trigger): the org probe returns
  2xx for the token minted under `78s808ujpe6lve`, and #7606 receives the
  "is valid. Auto-closing." comment + state=closed.
- Zero "still expired"/`unknown` weekly comments on #7606 after the fix
  deploys.

## Dependencies & Risks

- **Deploy dependency:** the cron runs against the deployed app's env — the
  fix takes effect only after a release ships it. Verification is the
  manual-trigger dispatch post-deploy (Phase 3, step 3), mirroring
  bootstrap.sh's existing closeout prose.
- **Risk — ACL endpoint drift:** if LinkedIn changes `organizationalEntityAcls`
  semantics, the org probe could 403 for a healthy token; mitigated by the
  `unknown`-for-unexpected-codes rule staying intact and by the issue body
  naming `/v2/me` as the documented fallback probe.
- **Risk — scope-list wording:** the Community app's offered scope set is
  vendor-controlled; the runbook says "all offered scopes,
  `w_organization_social` mandatory" rather than pinning a possibly-stale
  enumerated list.
- **Sharp edge:** the plan's ACs assert endpoint routing per token — a green
  suite that only checks `status` would pass even if both probes still hit
  userinfo; the fetch-URL assertions are load-bearing, not decorative.
- **Sharp edge:** `bootstrap.sh` is a generated artifact — the fix goes into
  the generated file deliberately (the LinkedIn logic lives there, not in the
  template); a future regeneration would drop it, which is why the
  `token-validators`/template concerns are tracked separately rather than
  silently re-derived.

## References & Research

- Issue: `gh issue view 9181` (defects + live-verified probe matrix, 2026-09-28).
- LinkedIn org-ACL contract (deepen-plan external check, 2026-09-28):
  `GET /v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR` lists
  organizations the member administers; response shape `{elements:
  [{organizationalTarget, role, state}], paging}`; requires
  `rw_organization_admin`-class Community Management access — hence 403 for a
  token minted outside the Community app or without the product scopes.
  Sources: LinkedIn Marketing permissions mapping
  (learn.microsoft.com/linkedin/shared/references/migrations/permissions-resources-mapping)
  and the organization access-control OpenAPI surface.
- `apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts` —
  full file reviewed (262 lines).
- `knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh` —
  full file reviewed (654 lines).
- `apps/web-platform/test/server/inngest/cron-linkedin-token-check.test.ts` —
  full file reviewed (369 lines).
- `knowledge-base/project/specs/feat-linkedin-token-renewal/spec.md` —
  design intent (probe-before-persist, tri-state probe, per-command acks).
- Learnings: `2026-04-09-linkedin-org-access-token-for-company-page-posts.md`,
  `2026-04-26-linkedin-org-token-fallback-silent-400.md`.
- ADR-033 (Inngest cron invariants) — preserved.

## Pipeline-mode disclosures

- Research fan-outs, domain-leader spawns, spec-flow, scoped advisor consult,
  and the plan-review panel were performed inline by the planning agent —
  this environment exposes no Task/Skill spawn tool. Headless rules applied
  throughout (no AskUserQuestion pauses).
- `lane:` defaulted to `cross-domain` — no `spec.md` exists for this branch
  to carry a `lane:` from (TR2 fail-closed per plan skill).
- Advisor-consult note: change is a mechanical per-token endpoint/metadata
  fix on an already-reviewed surface; the design forks (per-token table vs
  shared probe; 403→shared filing vs new status member) are decided inline
  with their rejected alternatives recorded in the Cut List and Proposed
  Solution.
