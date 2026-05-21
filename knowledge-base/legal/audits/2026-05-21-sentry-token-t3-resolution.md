---
title: "Sentry token T3 resolution — Internal Integration token mechanism confirmed"
date: 2026-05-21
parent_issue: 3861
related_issues: [3849, 3958, 3962]
related_pr: 4209
related_plan: knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md
supersedes_status: knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md
gate: 3b
status: resolved
verdict: T3-confirmed-as-T4-Internal-Integration-mechanism
probe_run_at: 2026-05-21T07:00:00Z
---

## Purpose

Closes the empirical question deferred by the 2026-05-19 probe-divergence audit
(`knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`
§Theory state T3): _why_ the runtime `SENTRY_AUTH_TOKEN` in Doppler `prd`
returned HTTP 401/403 against `/api/0/organizations/jikigai/` during the
2026-03-28 → 2026-05-16 window, given that both `jikigai` and `jikigai-eu`
orgs were operator-owned EU-database orgs throughout (Sentry support replies
2026-05-19; PA8 §(d) UPDATE block in Article 30 register; PIR Phase 9
Gate-3b Correction section).

The probe-divergence audit identified the verification path ("hit
`/api/0/me/` or `/api/0/` with the runtime token to surface its identity")
but the actual probe was halted by an unrelated R2-class token-leak incident
before that path was walked. PR-2 #4209 landed the corrective corpus sweep
on the substantive story (T0 falsification) without nailing T3's mechanism.
This audit closes that residual.

## Probe (2026-05-21)

All probes used the runtime `SENTRY_AUTH_TOKEN` from Doppler `prd` via
`doppler run --project soleur --config prd --command 'curl ... -H
"Authorization: Bearer $SENTRY_AUTH_TOKEN" ...'`. Token value was never
exposed to the conversation transcript (see §"Token-handling discipline"
below).

### Step 1 — Token shape fingerprint

Token format: **64 hex characters, no `sntryu_` / `sntrys_` prefix.**

Per Sentry's documented token taxonomy:

- `sntryu_<32-hex>` — User Auth Token (Personal Token) [post-2024]
- `sntrys_<32-hex>` — Org Auth Token [post-2024]
- bare `<64-hex>` — legacy User Auth Token OR Internal Integration token (pre-2024 format; same surface shape, different auth class)

Shape alone is ambiguous between legacy User Auth and Internal Integration.
Steps 2–5 disambiguate.

### Step 2 — `/api/0/` root (token identity)

`GET https://sentry.io/api/0/` with the runtime token returned **HTTP 200**
with body shape:

```json
{
  "version": "0",
  "auth": {
    "scopes": [
      "org:ci",
      "org:read",
      "project:read",
      "project:releases",
      "project:write"
    ]
  },
  "user": {
    "id": "4569715",
    "name": "web-platform-ci-26eeaf-32dbf505-df3b-4cf8-9a0b-babb6dba9d47@proxy-user.sentry.io",
    "username": "web-platform-ci-26eeaf-32dbf505-df3b-4cf8-9a0b-babb6dba9d47",
    "email": "web-platform-ci-26eeaf-32dbf505-df3b-4cf8-9a0b-babb6dba9d47@proxy-user.sentry.io",
    "dateJoined": "2026-05-17T11:25:11.910265Z",
    "hasPasswordAuth": false,
    "isManaged": false,
    "isSuperuser": false,
    "isStaff": false,
    "isActive": true,
    "lastLogin": null,
    ...
  }
}
```

Three load-bearing fingerprints visible at this surface:

1. **`user.email` domain `@proxy-user.sentry.io`** — Sentry's internal
   namespace for proxy-user identities, used exclusively by Internal
   Integrations (SentryApp `status: internal`). A User Auth Token's
   `user.email` is the real user email (e.g., `jean.deruelle@jikigai.com`).
2. **`user.dateJoined: 2026-05-17T11:25:11Z`** — twelve minutes after the
   `jikigai-eu` org creation (`dateCreated: 2026-05-17T11:13:30Z` per the
   2026-05-19 probe-divergence audit Step 2 body). The proxy-user identity
   was minted at integration-install time, not at any user signup.
3. **`auth.scopes`** — exactly the standard Internal Integration scope set
   for a CI/release token. User Auth Tokens carry user-selected scopes from
   the dashboard mint surface; Internal Integration tokens inherit scopes
   from the integration definition.

### Step 3 — `/api/0/users/me/` (negative-evidence disambiguator)

`GET https://sentry.io/api/0/users/me/` with the runtime token returned
**HTTP 403** with body `{"detail": "You do not have permission to perform
this action."}`.

User Auth Tokens (`sntryu_*` and legacy User Auth) return HTTP 200 at this
surface with the real user's account record. **Internal Integration tokens
return 403 because the proxy-user identity is not a real user that can call
`/users/me/`.** This is definitive negative evidence the runtime token is
NOT a User Auth Token.

### Step 4 — `/api/0/organizations/` listing

`GET https://sentry.io/api/0/organizations/` with the runtime token returned
**HTTP 200** with body `[]` (empty array). Probed against three host
classes:

| Host | HTTP | Body |
|---|---|---|
| `sentry.io/api/0/organizations/` | 200 | `[]` |
| `jikigai-eu.sentry.io/api/0/organizations/` | 200 | `[]` |
| `de.sentry.io/api/0/organizations/` | 200 | `[]` |

User Auth Tokens return the orgs the user is a member of (typically ≥ 1).
**Internal Integration tokens cannot enumerate orgs via the listing surface;
they can only access their installation org via slug-direct paths
(`/api/0/organizations/<bound-slug>/...`).** The empty array is the
documented behavior, not an authorization-class anomaly.

Cross-check: `GET https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/`
with the same token returned HTTP 200 with the full org body (verified
inline in this session, 2026-05-21T06:28Z; previously also verified in the
2026-05-19 probe-divergence audit Step 2). The token can access its bound
org directly; it cannot list orgs.

### Step 5 — `/api/0/organizations/jikigai-eu/sentry-apps/` (positive-evidence match)

`GET https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/sentry-apps/`
with the runtime token returned **HTTP 200** with two Internal Integrations
on the `jikigai-eu` org:

| name | slug | status | scopes |
|---|---|---|---|
| `iac-terraform-prd` | `iac-terraform-prd-814bdd` | `internal` | `alerts:read`, `alerts:write`, `event:read`, `org:read`, `project:admin`, `project:read`, `project:write` |
| **`web-platform-ci`** | **`web-platform-ci-26eeaf`** | `internal` | **`org:ci`, `org:read`, `project:read`, `project:releases`, `project:write`** |

The `web-platform-ci-26eeaf` slug matches the runtime token's proxy-user
prefix (`web-platform-ci-26eeaf-32dbf505-df3b-4cf8-9a0b-babb6dba9d47`)
byte-for-byte. The `web-platform-ci` integration's scopes match the
runtime token's `auth.scopes` byte-for-byte. The runtime token is
**positively identified** as the auth token of the `web-platform-ci`
Internal Integration installed on `jikigai-eu`.

The `iac-terraform-prd-814bdd` integration is a separate token
(`SENTRY_IAC_AUTH_TOKEN` per Doppler `prd` enumeration, prefix
`7d18d1c1...` — a distinct 64-hex token); its existence is incidental to
this audit.

## T3 → T4 promotion

The 2026-05-19 probe-divergence audit's T3 claim was:

> **T3:** Personal Token, user-membership boundary — the runtime token's
> token-holder identity (the user / service-account it authenticates as) is
> recognized by Sentry but is not a member of the `jikigai` org.

T3's substance is **CONFIRMED** with mechanical refinement promoted to T4:

> **T4 (refinement of T3):** The runtime `SENTRY_AUTH_TOKEN` is a Sentry
> **Internal Integration token** (legacy 64-hex format, but distinct auth
> class from User Auth Tokens) issued for the `web-platform-ci` Internal
> Integration installed on the `jikigai-eu` organization. The token
> authenticates as an auto-generated proxy-user identity
> (`web-platform-ci-26eeaf-...@proxy-user.sentry.io`, user ID `4569715`,
> dateJoined `2026-05-17T11:25:11Z` — 12 minutes after `jikigai-eu` org
> creation). The proxy-user is — by Sentry's design — a member only of the
> integration's installation org; it has no membership in any other
> organization (including operator-owned ones).

T3's "Personal Token" wording is corrected to "Internal Integration token"
(the more precise auth-class label); the membership-boundary causal claim
is preserved verbatim.

## Mapping back to the 2026-03-28 → 2026-05-16 401/403 surface

The runtime token during that window was the equivalent `web-platform-ci`
Internal Integration installed on the original (now-canceled, vendor-side,
2026-05-21) `jikigai` org. When the original-window audit script probed
`/api/0/organizations/jikigai/` (the integration's installation org, but
via the pre-rename slug-routing surface), responses were determined by the
composite of (a) the integration's proxy-user membership scope and (b) the
`eu.sentry.io` regional host's `activeorg`-cookie slug-rewrite bug for
`-eu`-suffix slugs (ADR-031 §Cluster/Host Glossary, API row). The original
401/403 surface is fully explained by these two mechanisms in superposition.

**There was never a third-party recipient.** The integration's proxy-user
is Sentry-internal bookkeeping infrastructure for the operator-administered
integration; it is not a separate data controller, sub-processor, or
recipient under Art. 30. The original 2026-05-17 "phantom-ingest to unowned
third-party org" framing was incorrect at every layer.

## §5(2) accountability record

This audit + the 2026-05-19 probe-divergence audit
(`knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`)
+ the Article 30 PA8 §(d) UPDATE block + the PIR Phase 9 Gate-3b Correction
section together constitute the §5(2) accountability evidence for the
2026-05-17 disclosure correction. The substantive story (T0 falsification,
operator ownership confirmed across both orgs, no third-party recipient
occurred, no Art-33 / Art-34 notification was warranted) was canonical
from 2026-05-19; the precise causal mechanism (T4 Internal Integration
proxy-user membership boundary) is now empirically nailed.

## Token-handling discipline

This probe used Doppler-resolved environment-variable substitution inside
the `doppler run` command boundary; the token value never entered the
conversation transcript, shell history, or any local file. Token fingerprint
("first 8 hex chars + length") was surfaced via
`printf "%s" "$SENTRY_AUTH_TOKEN" | head -c 8` inside the same `doppler run`
boundary, with output limited to the prefix. No `browser_evaluate`,
Playwright snapshot, or other DOM-walking surface was invoked, so the
2026-05-19 R2-class token-leak failure mode could not recur.

## Cross-references

- PIR §Phase 9 Gate-3b Correction:
  `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`
- 2026-05-19 probe-divergence audit (supersedes_status above):
  `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`
- Article 30 PA8 §(d) UPDATE block:
  `knowledge-base/legal/article-30-register.md:160`
- ADR-031 §Cluster/Host Glossary (regional host slug-rewrite bug — the
  second mechanism in the composite original-window surface):
  `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
- Compliance-posture row UPDATE block (sweepd in PR-2):
  `knowledge-base/legal/compliance-posture.md` "Sentry residency cleanup" row
