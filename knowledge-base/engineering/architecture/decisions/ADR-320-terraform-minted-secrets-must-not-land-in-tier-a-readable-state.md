# ADR-320: Terraform-minted secrets must not land in Tier-A-readable state

- Status: proposed
- Date: 2026-11-04
- Refs: #8209, #9294, #10582 (G1b), ADR-241 (residual R2), ADR-220, ADR-006, ADR-065, ADR-130

## Context

ADR-241 tiers Terraform credentials. Tier A is what branch workflows may read; Tier B is delivered only through main-only environment secrets. The web-platform root's state lives in the `soleur-terraform-state` R2 bucket, which the Tier-A read-only pair (`r2-tf-state-read-8209`, `prd_terraform` `AWS_*`) can read. ADR-241 records that fact as residual R2: "Web-platform root state is Tier-A readable and holds other Terraform-minted secrets", pre-existing and accepted by ADR-220. R2 was only narrowed there (the two `doppler_secret.github_app_*` mirrors left that state); it was never turned into a rule.

The CTO ruling of 2026-10-12 on #8209 named the consequence: a secret that Terraform mints is stored in state, so anything that can read that state can read the secret. The known instance is `tls_private_key.ci_ssh`, whose private key is `DEPLOY_SSH_PRIVATE_KEY`, a second path to root on web-1 (G1b, tracked as #10582 under #9294). The R2 bucket has no versioning and no state lock (ADR-006), so a leaked read also exposes every earlier state object.

The git-data root key already shows the alternative: its state moved to `soleur-terraform-state-privileged` (readable by a bucket-scoped pair held in Tier B), so Tier A cannot read it (#8209 O8, O12).

## Decision

1. **A secret that grants write, root or production access is not created as a Terraform resource attribute in a root whose state Tier A can read.** That covers `tls_private_key`, `random_password` and any provider resource that returns a token or key as an attribute.
2. Such a secret is instead (a) minted outside Terraform and provisioned before the merge that needs it (ADR-065; ADR-130 for a bucket-scoped R2 token), or (b) created in a root whose backend is `soleur-terraform-state-privileged`, as the git-data root key is. A provider-level write-only or ephemeral attribute is acceptable only where the provider version in use is shown to keep the value out of state; that has to be demonstrated per resource, not assumed.
3. **Existing instances are debt, not exceptions.** `tls_private_key.ci_ssh` is the known one and is owned by #10582. Any other minted secret found in the web-platform state is moved or re-minted the same way when it is found; it is not left standing because R2 was accepted.
4. **No automated gate enforces this yet.** Until one exists, a PR that adds a `tls_private_key`, `random_password` or a token- or key-returning resource to a root with Tier-A-readable state is reviewed against this ADR.

## Consequences

- A new resource of that kind is provisioned before the merge that needs it (ADR-065) or lives in a privileged-bucket root. That is more setup than a plain Terraform resource, and it is the intended cost.
- R2 in ADR-241 stays accepted for what already sits in that state; this ADR stops it from growing.
- Rotating a secret that sits in readable state does not repair the exposure by itself: the next apply writes the new value to the same readable state. The rotation has to come with the move out.
- Status is `proposed` because decision 4's gate does not exist and #10582 is open. It becomes `adopting` when a gate is filed and wired, and `accepted` when `tls_private_key.ci_ssh` has left Tier-A-readable state.

Scope note 2026-11-05 (legal-acceptance verify token, see the PR-D amendment in ADR-319): Outside ADR-320 decision 1: read-only status token; the design was reviewed under decision 4 on 2026-11-05. Update 2026-11-07 (#12196): `apps/web-platform/infra/legal-acceptance-secrets.tf` implements that design (two independent `random_password` generators, one `doppler_secret` per config, no `ignore_changes`, no write reach), and `cross-layer-limits.test.ts` now fails when the route gains an export other than `GET`. The exemption holds while the route returns only `status`, `text_hash`, `decided_at` and `row_ok` and never writes; widening the response, adding a non-GET method or adding any write path re-triggers the decision-4 review and moves the token out of Terraform. Rotating it does not repair a leak, and rotation has no automated route: it is a local, operator-approved `-replace` of the generator under Tier-B credentials. Leaving Terraform means minting it outside and removing both secrets from state (the recipe is in the file header).
