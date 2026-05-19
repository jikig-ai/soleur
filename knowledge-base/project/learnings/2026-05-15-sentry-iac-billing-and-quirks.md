---
name: sentry-iac-billing-and-quirks
description: Sentry-IaC gotchas surfaced during the 2026-05-15 #3849 token rotation session — terraform sentry_project default mismatch, jianyuan/sentry provider .enabled drift, and Sentry's per-seat billing gate on cron monitor activation
metadata:
  type: project
  date: 2026-05-15
  triggering_issue: "#3849"
  area: apps/web-platform/infra/sentry
---

# Sentry-IaC: billing gating and provider quirks

## Three gotchas surfaced in one session

The 2026-05-15 apply-sentry-infra workflow failed three different
ways in succession after the rotated `SENTRY_AUTH_TOKEN` finally
let the underlying Sentry API requests go through.

### Gotcha 1: `var.sentry_project` default mismatch

**Symptom:**
```
Error: Client Error
with data.sentry_project.web_platform,
  on main.tf line 36, in data "sentry_project" "web_platform":
Unable to read, got status code 404: {"detail":"Project does not exist"}
```

**Cause:** `apps/web-platform/infra/sentry/variables.tf` defaulted
`sentry_project = "web-platform"`. The real Sentry project slug
under the `jikigai` org is `soleur-web-platform`. The mismatch was
masked since #3811 merged because the previous broken token 403'd
before reaching the project lookup step.

**Fix:** PR #3857 — change the default to `soleur-web-platform`
(matches Doppler's `prd` and `prd_terraform` configs).

**Why:** The apply-sentry-infra workflow does not pass
`TF_VAR_sentry_project` from Doppler; it relies on the variable
default. A cleaner follow-up would be to wire Doppler →
`TF_VAR_sentry_project` like AWS creds, removing the default
entirely. Filed as scope-out.

### Gotcha 2: `jianyuan/sentry` provider `.enabled` drift

**Symptom:**
```
Provider produced inconsistent result after apply
When applying changes to sentry_cron_monitor.X, provider
"...jianyuan/sentry" produced an unexpected new value: .enabled:
was cty.True, but now cty.False.
```

**Cause:** The provider serialises monitors with `enabled = true`
in the plan, but the Sentry API ignores the flag at creation when
the org's billing quota has no headroom (see Gotcha 3). The
returned object has `status = "disabled"` and the provider
interprets this as a contract violation.

**Important:** The terraform apply is reported as "failed" but the
underlying resources DO get created. Always check Sentry's
`/api/0/organizations/<org>/monitors/` after a failure of this
shape before assuming nothing happened.

**Workaround:** Toggling activation via PATCH after creation is
the path when seats are available. The provider eventually
converges on a fresh plan once seats are sorted.

### Gotcha 3: Per-seat billing on cron monitors (the real block)

**Symptom (on PATCH to enable):**
```
HTTP 400
"You don't have enough pay-as-you-go available to create a new seat"
```

**Cause:** Sentry charges per *active* cron monitor seat. The
Developer (free) plan includes 1 seat; `am3_f` with
`onDemandBudget: 0` and no payment method on file blocks
activation of monitors 2+. The 8 monitors specified in
`cron-monitors.tf` are created but stuck in `status = "disabled"`
until billing is sorted.

**Diagnostic API:** `GET /api/0/customers/jikigai/` returns the
plan tier, `onDemandBudget`, and per-category PAYG usage. Use
this BEFORE running apply-sentry-infra against a new monitor set
so the billing block is surfaced upfront, not after a confusing
"plan succeeds, apply fails, monitors created-but-disabled"
sequence.

**Resolution path:** payment method entry is operator-only (case
(d) of [[hr-never-label-any-step-as-manual-without]]); enabling
the on-demand budget after a payment method is on file CAN be
driven via API or UI.

## How to apply (next time)

Before a Sentry-IaC apply that adds new monitor resources:

1. Probe `GET /api/0/customers/<org>/` and read `categories.crons`
   (or equivalent seat-bearing category) + `onDemandBudget`.
2. If insufficient seats AND `onDemandBudget == 0`, halt before
   the apply, surface the billing block, ask the operator
   whether to (a) enable PAYG, (b) upgrade plan, (c) reduce
   monitor scope, or (d) defer.
3. Only after seats are confirmed available, run the apply. The
   `.enabled` drift in Gotcha 2 should not fire when seats are
   sufficient.

## Related

- #3849 — the triggering rotation issue
- #3811 — original Sentry IaC adoption (introduced the slug
  default that PR #3857 fixed)
- ADR-031 — Sentry-as-IaC architecture
- [[hr-never-label-any-step-as-manual-without]] — case (d) of the
  operator-only set explicitly enumerates payment/billing entry
- `apps/web-platform/infra/sentry/cron-monitors.tf` — the 8 monitor
  resources whose activation depends on seat availability
