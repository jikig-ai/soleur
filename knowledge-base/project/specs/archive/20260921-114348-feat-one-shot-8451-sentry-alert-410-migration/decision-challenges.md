# Decision challenges — feat-one-shot-8451-sentry-alert-410-migration

## 1. `Ref #8282` instead of `Closes #8282` (User-Challenge)

- **Operator direction:** "if #8282 matches, have the plan carry `Closes #8282` alongside `Closes #8451`."
- **What the plan does instead:** it confirms #8282 is the same root cause (run 35333341158: the same two addresses, `410 {"detail":"This API no longer exists."}`, 3/3 attempts, apply skipped), but the PR carries `Ref #8282`.
- **Why:** #8282 is the apply-failure filer's own issue. `apply-sentry-infra.yml`'s "Close the apply-failure tracking issue (success)" step (`:1590`) closes it with the green run's URL as proof. A `Closes` at merge would close it before the adoption apply is verified. If that apply failed, the filer (which searches open issues only) would open a duplicate and split the incident history.
- **Cost of the operator's version:** low. It is reversible by reopening, but it would record resolution before evidence.
- **Default if unanswered:** `Ref #8282`, closed by the workflow on a green apply.

## 2. Forget-only instead of adopt-by-import (Taste; declined)

- **Reviewer (DHH) proposal:** `removed { destroy = false }` only. Stop managing the two rules in Terraform and drop the import, the projection exclusion and the count bump.
- **Why declined:** the operator asked for a migration to `sentry_alert` that keeps the live rules managed (import blocks). Forget-only loses Terraform ownership of the rules' existence, and it does not remove the write-hazard guards (the tripwire and the live pin), because a later re-declaration re-enters the same Create path.
- **Default:** adopt by import, as planned.
