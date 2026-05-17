---
date: 2026-05-17
classification: bug-fixes
sources:
  - "PR-β #3945 §11 partial-apply on 2026-05-17"
  - "ADR-031 §Per-app root"
  - "apps/web-platform/infra/sentry/issue-alerts.tf"
tags:
  - sentry
  - terraform
  - branch-c
  - dedup-quirk
title: "Sentry POST /rules/ dedup keys on action-shape + filter_match + action_match, not on conditions_v2"
---

# Sentry POST `/api/0/projects/{org}/{project}/rules/` dedup keys on action-shape, not on conditions_v2

## The bug

`apps/web-platform/infra/sentry/issue-alerts.tf` defines 4 auth issue-alert
resources (`auth_exchange_code_burst`, `auth_callback_no_code_burst`,
`auth_per_user_loop`, `auth_signout_burst`). The file's docblock says
"IMPORT-ONLY: these resources mirror existing Sentry rules created by the
legacy script" and `conditions_v2 = []` + `filters_v2 = []` are
placeholders covered by `lifecycle.ignore_changes`.

For the legacy migration path (apply against an org where the 4 rules
already exist via `configure-sentry-alerts.sh`, then `terraform import`),
this works fine. But for the **apply-creates-fresh** path used in PR-β §11
(new `jikigai-eu` org with no pre-existing rules), terraform tried to
create all 4 from scratch and Sentry's API returned:

```
HTTP 400 — {"name":["This rule is an exact duplicate of 'auth-signout-burst'
in this project and may not be created."],"ruleId":[597309]}
```

The dedup check fired on rules 2 and 3 of the 4-rule batch. Reproducing
the dedup test with the legacy `configure-sentry-alerts.sh` (which
populates real conditions) hit the same error on the very first POST —
so the dedup is NOT on `conditions_v2` content.

## What the dedup is keyed on

Empirical observation (PR-β §11 reapply): when frequency was varied per
resource (60 → 61, 62, 30), all 4 rules created successfully. With
frequency=60 across 3 of the 4, only the first one (auth_signout_burst)
landed; the next 2 failed with the dedup error.

Hypothesis (confirmed by frequency-disambiguation test): Sentry's dedup
key on POST `/rules/` is approximately:

  hash(action_match + filter_match + frequency + actions_v2-shape)

NOT on conditions or filters content. The dedup ignores the very fields
that operators use to differentiate alerts (specific filter values like
`op:exchangeCodeForSession` vs `op:callback_no_code`).

## The fix

`apps/web-platform/infra/sentry/issue-alerts.tf` — set unique `frequency`
per resource (60/61/62/30) so the dedup hash differs at POST time. The
real operator-managed frequency value drifts back via Sentry UI and is
captured under `lifecycle.ignore_changes = [..., frequency]` (already
present in the resource block).

This is creation-time disambiguation only. Post-create, the UI-managed
value can be any frequency without terraform interference.

## Why this matters

The `configure-sentry-alerts.sh` legacy path AND the terraform apply-
creates-fresh path both hit this. The fix should be in the IaC truth
because:
1. Branch C2 or any future state-drop + re-import cycle hits the same
   dedup wall.
2. New environments (staging, second-tenant) creating these rules from
   scratch encounter the same.
3. The `lifecycle.ignore_changes` posture preserves operator-managed
   frequencies after create — the fix has zero functional cost.

## Bonus finding: jianyuan/sentry v0.15.0-beta2 `enabled` field bug

When the apply-creates-fresh path created the 8 cron monitors, terraform
errored on each with:

```
provider produced an unexpected new value: .enabled: was cty.True,
but now cty.False. This is a bug in the provider, which should be
reported in the provider's own issue tracker.
```

The resources were nonetheless created in Sentry (verifiable via
`GET /api/0/organizations/{org}/monitors/`), but terraform marked all 8
as **tainted** (treating them as failed creates). Re-running plan after
a `terraform untaint` showed `enabled: false → true` in-place updates —
which then 403'd because the internal-integration token lacks
project:admin scope to flip monitor status.

Workaround: leave the in-place-update drift; Sentry monitors transition
to `status=active` automatically on first cron check-in (the 9 scheduled
GitHub Actions workflows that already POST to the new DSN will activate
them within their next scheduled fire window).

Tracking: provider bug should be reported upstream against
[jianyuan/terraform-provider-sentry](https://github.com/jianyuan/terraform-provider-sentry/issues)
with reproducer.

## Re-evaluation triggers

- jianyuan/sentry provider bumps to v0.15.0 stable — re-test creation
  flow against an empty org and verify whether `enabled` drift persists.
- Sentry product changes: if the POST `/rules/` dedup behavior is fixed
  to consider conditions_v2 content, the frequency disambiguation can
  revert to a uniform `60`.
