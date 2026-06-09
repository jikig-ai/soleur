---
title: To check whether a credential/integration exists, grep the provider registry — not just process.env / .env.example
date: 2026-06-08
category: best-practices
tags: [plan, premise-validation, credentials, providers, grep, iac, doppler, funnel]
severity: medium
resolved: true
issue: 5049
---

# Learning: Credential-existence premise checks must grep the provider registry, not just `process.env`

## Problem

While planning #5049 (activation funnel), the Research Reconciliation asserted
"there is **no `BUTTONDOWN_API_KEY`** anywhere; reading subscribers needs a
net-new secret routed via Terraform." That premise was **false** and load-bearing
for ~40% of the plan (a new `infra/buttondown.tf` `doppler_secret`, a new variable,
an operator-mint step, a post-merge `terraform apply`).

The grep that produced the false negative was scoped to runtime-read forms:
`grep -riE "BUTTONDOWN" .env.example` and `grep "process.env" apps/web-platform`.
But the key is registered in a **config object**, not read via `process.env` at
the grep site: `server/providers.ts:23` (`buttondown: { envVar: "BUTTONDOWN_API_KEY", ... }`)
with a working validator already hitting `api.buttondown.com` with
`Authorization: Token` at `server/token-validators.ts:57`. Kieran plan-review
caught it (P0).

## Solution

When a plan's premise turns on "does integration/credential X already exist?",
grep the **integration registries**, not only the runtime-read forms:
- `server/providers.ts` / any `*PROVIDER_CONFIG*` / `SERVICE_PROVIDERS` map
- `server/token-validators.ts` (validators reveal the host + auth scheme already in use)
- the bare credential NAME across the repo (`git grep -n BUTTONDOWN_API_KEY`), not
  just `process.env.X` — config maps reference it as a string value.

A credential referenced as a string in a config object is invisible to a
`process.env`-scoped grep. The bare-name grep is the high-signal check.

## Key Insight

The "verify named artifacts before freezing the plan" rule has a specific failure
mode for credentials: the existence check must match how the credential is
*registered*, not how it is *read*. Registry-as-string defeats a `process.env`
grep. One `git grep -n <CREDENTIAL_NAME>` (unscoped) would have caught it.

Corollary (same session): the broader brainstorm reframe held — a funnel whose
success metric is fully Supabase-derivable should not add a vendor read for a
non-gating number (4-agent plan-review converged to defer Buttondown to #5071).
See [[2026-06-08-brainstorm-funnel-reframe-substrate-exists-and-tool-cannot-read-back]].

## Session Errors

1. **False "no BUTTONDOWN_API_KEY anywhere" premise** — grep scoped to
   `process.env`/`.env.example` missed the `server/providers.ts` registry entry.
   Recovery: Kieran plan-review flagged P0; plan re-scoped (Buttondown deferred to
   #5071). Prevention: unscoped `git grep -n <CREDENTIAL_NAME>` + grep provider
   registries when checking credential existence.
2. **`doppler secrets set` tripped the IaC PreToolUse hook** (twice — the hook is a
   substring match, so even prose saying "do NOT use `doppler secrets set`"
   triggers it). Recovery: routed the secret through a Terraform `doppler_secret`
   resource (the `github-app.tf` precedent), then removed the literal phrase from
   the plan text entirely. Prevention: route new secrets through `doppler_secret`
   Terraform from the first draft; never write the literal CLI phrase in plan prose.

## Related

- [#5049](https://github.com/jikig-ai/soleur/issues/5049) — parent
- [#5071](https://github.com/jikig-ai/soleur/issues/5071) — deferred Buttondown count
- `apps/web-platform/server/providers.ts:23`, `apps/web-platform/server/token-validators.ts:57`

## Tags

category: best-practices
module: plan
tags: [plan, premise-validation, credentials, providers, grep, iac]
severity: medium
resolved: true
