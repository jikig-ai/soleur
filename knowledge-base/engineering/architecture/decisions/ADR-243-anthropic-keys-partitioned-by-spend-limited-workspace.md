---
title: "ADR-243: Anthropic keys are partitioned by blast radius into spend-limited Console workspaces"
status: active
date: 2026-09-23
issue: 8505
---

# ADR-243: Anthropic keys are partitioned by blast radius into spend-limited Console workspaces

## Context

Until #8505, CI, manual evals and production billed ONE operator Anthropic key: the same SHA-256
fingerprint (`c95e2853ab74`) sat in Doppler `ci`, in every `prd*` config, and in the
`ANTHROPIC_API_KEY` repository secret. The prepaid balance is org-wide, so any eval grid or CI run
could drain it and take the production crons and the email-triage summarizer down with it, and a
CI-side leak exposed the production credential. The balance ran out on 2026-09-19 and again from
2026-09-21 to 2026-09-23.

Anthropic has no per-key spend limit. Limits are per **workspace**, set only in the Console (the
Admin API can create workspaces but cannot set their limits), and the Default workspace cannot
carry one.

## Decision

Partition operator keys by consumer class into Console workspaces, each with a monthly spend limit.

- **CI and manual evals** bill a service-account key in workspace `soleur-ci-eval`
  (`wrkspc_01GCfbuC9cVBXiWkkEfnyi4D`, org `d8d6285b…`), limited to **$100/month** with an email
  notification at $80. The key is minted in the Console; the procedure, records and revocation path
  are in [anthropic-console-workspace-key.md](../../operations/runbooks/anthropic-console-workspace-key.md).
- **Terraform distributes it** ([anthropic-ci-key.tf](../../../../apps/web-platform/infra/anthropic-ci-key.tf)):
  from Doppler `prd_terraform/ANTHROPIC_API_KEY_CI` to Doppler `ci/ANTHROPIC_API_KEY` and the
  `ANTHROPIC_API_KEY` repo secret. A precondition refuses a value equal to the production key, and
  [anthropic-key-distinctness.sh](../../../../apps/web-platform/scripts/anthropic-key-distinctness.sh)
  proves distinctness across every `prd*` config by fingerprint.
- **Production crons** move to their own workspace in #8614, which also retires the old key that
  sat in the repo secret.

Rejected: a second key in the Default workspace (no spend limit possible there); a separate
Anthropic organisation (separate billing, more than the problem needs); Admin API automation (it
cannot set workspace spend limits, and no admin key exists).

## Consequences

- A workspace cap hit is its own CI failure class. `anthropic-preflight` soft-skips it with a
  `::warning::` on `specified API usage limits`; it is not operator credit exhaustion and never pages.
  Operator exhaustion is reported separately by the named Sentry marker in
  `server/anthropic-credit.ts`, routed by `sentry_alert.anthropic_credit_exhausted`.
- The balance is still org-wide. The cap bounds CI's share; it gives production no reserve.
- The CI key lands in the web-platform Terraform state, which more principals can read than should
  ever hold the production key (see #8209 on `prd_terraform`'s reach). That is acceptable for this
  key because its worst case is the $100 cap. The production key is referenced only inside
  preconditions, which are not persisted, so it never lands in state.
- Keys are Console-minted, so rotation is a runbook step, not an apply.
