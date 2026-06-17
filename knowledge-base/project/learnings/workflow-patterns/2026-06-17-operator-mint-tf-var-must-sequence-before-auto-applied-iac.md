# Learning: an operator-mint no-default TF var must be sequenced into Doppler `prd_terraform` BEFORE the IaC that references it merges

## Problem

The #5468 fix (inbound mail stranded at NULL) was two-pronged: a code-resilience
degraded-finalize tail (autonomous) + a least-privilege `RESEND_RECEIVING_API_KEY`
delivered via a new `variable "resend_receiving_api_key"` (no default, per
`hr-tf-variable-no-operator-mint-default`) + a `doppler_secret` resource. The plan
classified the key mint (AC12) as a **post-merge** operator step.

That classification is structurally unsafe in this repo: `apply-web-platform-infra.yml`
**auto-applies on merge** for any `apps/web-platform/infra/*.tf` change, and Terraform
resolves **all** root variables before `-target` pruning (empirically confirmed:
`terraform plan -target=<unrelated resource>` with an unset no-default var fails
`Error: No value for required variable`). So merging the IaC would have failed the
merge-triggered apply until the operator minted the key (CAPTCHA/console-gated, not
doable in-session).

## Solution

Routed the binding sequencing decision to the `soleur:engineering:cto` agent (per
the `/work` "architectural-fork decisions route to CTO" hard gate). The CTO ruled
**Option B (split)** with decisive precedent: `github-app.tf` / `inngest.tf` predate
the auto-apply workflow, so the established pattern is **secret-in-`prd_terraform`-first,
IaC-second** — never "merge an unset no-default var and let the merge-triggered apply
fail." Implemented:

- Removed the IaC (variable + `doppler_secret` + `resend.tf`) from this PR — leaving an
  **empty infra diff** so `apply-web-platform-infra.yml` does not even trigger.
- Shipped only the code-resilience half (degraded tail + receiving-key read +
  `.env.example`), which resolves the issue's defect (silent permanent NULL → visible
  degraded row) and legitimately `Closes #5468`.
- Filed follow-up #5480 (IaC + operator prerequisites) and recorded **ADR-065**.

## Key Insight

When a plan adds a **no-default Terraform variable** to an **auto-applied infra root**
(`apps/web-platform/infra/`), the variable's `TF_VAR_*` must already exist in Doppler
`prd_terraform` at merge time — Terraform validates every root variable before any
`-target` filter, so an unprovisioned no-default var fails the whole auto-apply. If the
mint is operator-gated (CAPTCHA/console) and can't run in-session, SPLIT: merge the
code (no `*.tf` change → workflow doesn't fire) and defer the IaC to a follow-up PR that
merges after the mint. The cheap pre-check: a plan adding a no-default infra var must
either confirm its `TF_VAR_*` is already in `prd_terraform` or sequence the mint first.

## Session Errors

1. **IaC-routing hook blocked the initial plan write** (`hr-all-infrastructure-provisioning-servers`, AC10 raw `doppler secrets set`). Recovery: re-routed through a `doppler_secret` TF resource. **Prevention:** already hook-enforced — worked as designed (planning phase, forwarded via session-state.md).
2. **Stale local `main` ref surfaced sibling-PR (#5472) files in `git diff main`; `origin/main` advanced twice mid-session.** Recovery: `git fetch origin main && git rebase origin/main` (twice). **Prevention:** diff against `origin/main` not local `main`; rebase when a sibling lands (already documented in work-skill bare-repo stale-ref guidance).
3. **Plan classified an operator-mint IaC step as post-merge that the auto-apply-on-merge workflow could not tolerate.** Recovery: CTO ruling → split (Option B) + ADR-065 + #5480. **Prevention:** the plan-skill Sharp Edge added this session (route-to-definition below).
4. **`bash test-all.sh > log 2>&1; echo "EXIT=$?"` in a backgrounded command sent the EXIT line to the background task's own output file, not `log`; a Monitor then grepped the wrong file.** Recovery: read the real exit from the task output file. **Prevention:** when capturing a backgrounded suite's rc, put the `echo "EXIT=$?"` inside the redirect group, or read the rc from the task output file the harness reports — don't point a Monitor at the redirect target for a marker the redirect never receives.
5. **One review agent (performance-oracle) returned a degenerate `--resume non-interactive` non-result.** Recovery: proceeded with 9/10 agents per the rate-limit fallback gate (perf surface here was negligible). **Prevention:** one-off harness/env; the fallback gate already handles partial coverage.

## Tags
category: workflow-patterns
module: infra / one-shot / plan
related: ADR-065, #5468, #5480
