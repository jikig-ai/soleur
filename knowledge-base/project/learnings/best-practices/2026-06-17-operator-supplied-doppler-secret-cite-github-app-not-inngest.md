# Learning: operator-supplied doppler_secret should cite github-app.tf, not inngest.tf

## Problem
When authoring a new operator-supplied `doppler_secret` resource (a secret whose
value is minted by a human in a vendor dashboard and fed in via a no-default
`TF_VAR_*`), it is tempting to cite both `github-app.tf` and `inngest.tf` as the
mirrored precedent — both files contain `doppler_secret` resources with
`visibility = "masked"` + `lifecycle { ignore_changes = [value] }`. That citation
conflates two distinct patterns and misleads the next reader.

## Solution
Cite **`github-app.tf:40-65`** (`github_app_id` / `github_app_private_key`) as the
operator-supplied-secret precedent — those take `value = var.*` from an
operator-minted dashboard key, exactly like the new resource.

`inngest.tf`'s secrets (`inngest_signing_key_*`, `inngest_event_key_*`) take their
value from a **TF-generated `random_id`**, NOT an operator mint
(`variables.tf` notes "TF-generated via random_id ... no operator mint required").
So `inngest.tf` is a valid mirror **only** for the narrower
`ignore_changes`-on-value rotation rationale — never for the operator-supplied
*shape*.

## Key Insight
Two `doppler_secret` resources can share the `masked` + `ignore_changes` posture
while differing on the load-bearing axis: **where the value originates**
(operator mint vs TF-generated). A precedent citation must match the axis the
new code actually depends on. Surfaced by `code-quality-analyst` at review on the
#5480 IaC PR (P3, fixed inline).

## Tags
category: best-practices
module: apps/web-platform/infra
