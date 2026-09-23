# Decision challenges — feat-one-shot-8209-evict-prd-terraform-secrets

## DC-1 (taste) — RESOLVED 2026-09-22: R7 folded into this PR after the plan-review architecture-strategist concurred with the CTO

- **Source:** CTO domain review (plan Phase 2.5).
- **Challenge:** The CTO asked that the Tier-A R2 backend key (`prd_terraform` `AWS_*`, read/write
  on `soleur-terraform-state`) become read-only in THIS PR, with the read/write key moved to
  Tier B.
- **Plan decision:** Deferred to its own issue (R7, `priority/p1-high`). Doing it here means
  editing every Tier-B "Extract backend credentials" step inside the byte-budgeted
  `apply-web-platform-infra.yml`, and it adds another operator mint.
- **What stays exposed meanwhile:** a branch actor can tamper with web-platform state.
- **Gate:** D2 `accepted` is gated on R7.
- **Operator choice:** accept the deferral, or fold R7 into this PR.

## DC-2 (user-challenge): #8209 does not close on this PR

- **Finding:** The issue asks for eviction "from any config a branch workflow can name". The
  soleur-ai *runtime* App key sits in Doppler `prd`, which the repo secret `DOPPLER_TOKEN_PRD` and
  every `prd_*` branch-config token can read. That App holds `administration:write` on
  `jikig-ai/soleur`, so whoever holds the key can rewrite any environment's branch policy.
- **Plan decision:** The PR says `Ref #8209`. R1 is filed at p1 and blocks #8211's real cutover.
- **Operator choice:** accept that sequencing, or widen this PR to re-plumb the runtime key. That
  would require host bootstrap and immutable-redeploy changes.

## DC-3 (taste, cost): Doppler Team + OIDC not adopted

- The environment-secret design works on the Developer plan.
- A Doppler upgrade would later replace only the carrier: the privileged read token would give
  way to OIDC. It is a recurring cost the operator has not approved.

## DC-4 (taste): dedicated `soleur-infra` App vs reusing the soleur-ai Terraform key

- **Plan recommendation:** create the `soleur-infra` App (O1). It is installed on `jikig-ai` only,
  and it holds `environments:write`, which R6 needs.
- **Simplicity-review counterpoint:** P1 is already met by moving the existing (distinct)
  soleur-ai Terraform key into Tier B under the `GITHUB_INFRA_APP_*` names and rotating it at O13.
  That removes O1 and the manifest.
- **What the code supports:** the code is identical either way. This is an operator choice at O1.
- **Cost of choosing the counterpoint:** Tier B keeps a key that reaches the two third-party
  installations, and R6 stays blocked on the 403.
