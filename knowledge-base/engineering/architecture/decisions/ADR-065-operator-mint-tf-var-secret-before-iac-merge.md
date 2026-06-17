# ADR-065: An operator-mint no-default TF variable must be provisioned in `prd_terraform` before the IaC that references it merges

- **Status:** Accepted
- **Date:** 2026-06-17
- **Issue:** #5468 (the inbound-mail-finalize fix); IaC follow-up tracked in #5480
- **Lineage:** ADR-031 (per-root auto-apply-on-merge workflow), `hr-tf-variable-no-operator-mint-default`, `hr-all-infrastructure-provisioning-servers`, `hr-exhaust-all-automated-options-before`.

## Context

The #5468 fix is two-pronged: a **code-resilience** half (a degraded-finalize
tail so an inbound body-fetch / summarizer failure produces a visible degraded
row instead of a silent permanent NULL) and a **config root-cause** half (a
least-privilege `RESEND_RECEIVING_API_KEY` so the inbound body fetch stops
throwing `restricted_api_key`). The plan classified the config half's operator
mint as a **post-merge** step (AC12).

That classification is structurally unsafe. `.github/workflows/apply-web-platform-infra.yml`
auto-applies on merge for any `apps/web-platform/infra/*.tf` change, invoking
`doppler run -c prd_terraform --name-transformer tf-var -- terraform plan -out=tfplan -target=…`.
Terraform resolves **all** root variables before `-target` pruning — empirically
confirmed: a `terraform plan -target=<unrelated resource>` with an unset
no-default variable fails `Error: No value for required variable`. So a new
`variable "resend_receiving_api_key"` with no default (correct per
`hr-tf-variable-no-operator-mint-default` — an empty default would silently ship
a broken/empty credential) would fail the **whole** merge-triggered apply until
`TF_VAR_resend_receiving_api_key` exists in Doppler `prd_terraform`. Minting that
key is dashboard/console-gated and cannot be done autonomously in-session.

The plan invoked github-app.tf / inngest.tf as precedent for "operator-supplied
secret in the same PR." That precedent actually **refutes** the plan: those IaC
files were added to the repo *before* the auto-apply-on-merge workflow existed,
so their operator secrets were already present in `prd_terraform` by the time any
auto-apply resolved `var.github_app_id`. The real established pattern is
**secret-in-`prd_terraform`-first, IaC-second** — never "merge an unset
no-default var and let the merge-triggered apply fail."

## Decision

**An operator-mint, no-default Terraform variable in an auto-applied root must
be provisioned in Doppler `prd_terraform` before the IaC that declares it
merges.** When the mint is operator-gated (CAPTCHA/console) and cannot run
in-session, **split** the change:

1. The autonomous half (code, tests, `.env.example`, anything with **no `*.tf`
   change**) merges first — so the infra auto-apply workflow does not even
   trigger — and resolves the issue's actual defect.
2. The IaC half (the `variable` + the `doppler_secret` + the
   `apply-web-platform-infra.yml` `-target` line) lands in a follow-up PR that
   merges **only after** the operator has minted the secret and set the
   `TF_VAR_*` in `prd_terraform`.

For #5468: the degraded-finalize tail + receiving-key read merge now and
`Closes #5468` (the silent-permanent-NULL defect is gone — the closure condition
per the plan's own Sharp Edge); the IaC + mint is tracked in #5480.

## Consequences

- **Positive:** the autonomous fix is not blocked on a CAPTCHA-gated operator
  action; `main`'s auto-apply-on-merge never enters a loudly-failing state;
  `hr-tf-variable-no-operator-mint-default` stays intact (no masking default).
- **Negative:** full mail_class restoration is deferred to the follow-up PR;
  until then inbound mail degrades visibly (the resilience win) rather than being
  fully classified — strictly better than the pre-fix silent NULL.
- **Generalizes:** any future operator-mint secret feeding an auto-applied TF
  root follows this split. The cheap pre-check: when a plan adds a no-default TF
  variable to `apps/web-platform/infra/`, confirm its `TF_VAR_*` is already in
  `prd_terraform` (or sequence the mint before the IaC PR) — do not assume a
  post-merge apply will tolerate it.

## Rejected alternatives

- **IaC in this PR + pre-merge operator mint.** Blocks an autonomous merge on a
  CAPTCHA-gated action for a defect the degraded tail already fixes without the
  key.
- **Placeholder `TF_VAR` now, rotate later.** A placeholder is still a
  send-scoped/restricted key (inbound keeps degrading until rotation); adds a
  Doppler secret + an apply with zero functional gain and a real "mistaken for a
  real key" hazard.
- **`default = ""` / make the workflow tolerate unset.** Violates
  `hr-tf-variable-no-operator-mint-default`; an empty receiving key would reach
  `prd` and silently re-introduce the `restricted_api_key` failure class with no
  operator signal.
