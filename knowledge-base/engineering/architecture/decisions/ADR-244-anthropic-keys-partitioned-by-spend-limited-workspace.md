---
title: "ADR-244: Anthropic keys are partitioned by blast radius into spend-limited Console workspaces"
status: active
date: 2026-09-23
issue: 8505
---

# ADR-244: Anthropic keys are partitioned by blast radius into spend-limited Console workspaces

## Context

Until #8505, CI, manual evals and production billed ONE operator Anthropic key: the same
fingerprint sat in Doppler `ci`, in every `prd*` config, and in the `ANTHROPIC_API_KEY`
repository secret. The prepaid balance is org-wide, so any eval grid or CI run could drain it
and take the production crons and the email-triage summarizer down with it, and every
same-repo pull-request CI run received the production credential. The balance ran out on
2026-09-19 and again from 2026-09-21 to 2026-09-23.

Anthropic has no per-key spend limit. Limits are per **workspace**, set only in the Console
(the Admin API can create workspaces but cannot set their limits), and the Default workspace
cannot carry one.

## Decision

Partition operator keys by consumer class into Console workspaces, each with a monthly spend
limit.

- **CI and manual evals** bill a service-account key in workspace `soleur-ci-eval`, limited to
  $100/month with an email notification at $80. The key is minted in the Console; records,
  procedure and revocation are in
  [anthropic-console-workspace-key.md](../../operations/runbooks/anthropic-console-workspace-key.md),
  the single source for the workspace's identifiers.
- **Terraform distributes it** ([anthropic-ci-key.tf](../../../../apps/web-platform/infra/anthropic-ci-key.tf))
  from Doppler `prd_terraform/ANTHROPIC_API_KEY_CI` to Doppler `ci/ANTHROPIC_API_KEY` and the
  `ANTHROPIC_API_KEY` repo secret, on the merge's apply. Terraform validates only the key's
  shape (`sk-ant-`).
- **Distinctness from the production key is proven live, not in Terraform.**
  [anthropic-key-distinctness.sh](../../../../apps/web-platform/scripts/anthropic-key-distinctness.sh)
  compares every `ci*` config against every `prd*` config by fingerprint. Comparing in Terraform
  would need the production key declared in this root, which writes it into the plan file on the
  runner and makes every apply depend on `prd_terraform` inheriting it — against #8209 (tiering
  `prd_terraform`) and #8614 (rotating the production key). A hash-of-prod variable was also
  rejected: it goes stale on rotation and then passes for the new production key.
- **Production crons** move to their own workspace in #8614, which also rotates the production
  key that sat in the repo secret.

Rejected: a second key in the Default workspace (no spend limit possible there); a separate
Anthropic organisation (separate billing, more than the problem needs); Admin API automation
(it cannot set workspace spend limits, and no admin key exists).

## Consequences

- A workspace cap hit is not operator credit exhaustion and never pages. Where a workflow runs
  `.github/actions/anthropic-preflight`, the cap soft-skips its Claude step with a
  `::warning::`. Three consumers do not run the preflight — `ci.yml`'s sandbox-canary and
  plugin-root gates, and `scheduled-machinery-drain.yml` — so at the cap they fail (the drain
  quietly, under `continue-on-error`). The drain is dispatched by a production cron but bills
  this CI key.
- Operator exhaustion is reported by the named Sentry marker (`server/anthropic-credit.ts`) at
  two chokepoints — the HTTP transport and the email-triage summarizer — and routed by
  `sentry_alert.anthropic_credit_exhausted`. The claude-eval CLI crons are not chokepoints;
  the hourly canary on the same org balance reports exhaustion within the hour.
- The balance is still org-wide. The cap bounds CI's share; it gives production no reserve.
- The CI key lands in the web-platform Terraform state and plan files. Acceptable for this key,
  whose worst case is the $100 cap.
- The production key still reaches CI where a workflow runs under Doppler `prd`
  (`web-platform-release.yml`). That is outside the two slots this decision governs.
- Keys are Console-minted, so rotation is a runbook step, not an apply.
