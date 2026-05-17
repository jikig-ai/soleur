# cla-evidence — Terraform root

Provisions the off-site evidence archive for the CLA signature flow:
`soleur-cla-evidence` R2 bucket (EU region, Cloudflare R2 Lock Rules with
a 10-year age-based retention floor providing write-once-read-many
(WORM) semantics) plus the two scoped Cloudflare API tokens used by the
sidecar workflow and by Terraform itself.

**Owner:** deruelle / ops@jikigai.com
**Issue:** #3209
**Plan:** `knowledge-base/project/plans/2026-05-04-feat-cla-legal-rigor-evidence-layer-plan.md`
**Runbook:** `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md`
**Retention:** 10 years (`maxAgeSeconds = 315360000`) from object creation, enforced by an R2 native Lock Rule.
**Region:** `weur` (Western Europe, best-effort per Cloudflare R2 placement).

## Change-control gate

Edits to this root must:

1. Be reviewed by both CTO and COO equivalents (or the agent-domain leaders for
   `soleur:engineering` and `soleur:operations`).
2. Carry an explicit per-command ack at apply time
   (`hr-menu-option-ack-not-prod-write-auth`) — the operator runs
   `terraform plan`, the assistant shows the diff, the operator types go-ahead,
   then the assistant runs `terraform apply -auto-approve`.
3. Never relax `prevent_destroy` or the 10-year (`maxAgeSeconds = 315360000`)
   Lock Rule retention floor without paired updates to `gdpr-policy.md`
   (off-site-archive balancing test) and the inspection runbook.

## Single-writer apply

The R2 backend has no lock (per institutional learning
`2026-03-21-terraform-state-r2-migration.md` — R2 lacks S3 conditional writes
needed for `use_lockfile = true`). Two operators applying simultaneously will
overwrite each other's state. Coordinate via the standard `#ops` Slack channel
before running `terraform apply` here.

## Retention enforcement (R2 native Lock Rules)

Cloudflare R2 does NOT implement the S3 `PutObjectLockConfiguration` API
surface — verified empirically during the 2026-05-16 bootstrap (PR #3201).
The native equivalent is the R2 Lock Rules REST endpoint:

```
PUT /accounts/{account_id}/r2/buckets/{bucket_name}/lock
Body: {"rules":[{"id":"...","enabled":true,"prefix":"","condition":{"type":"Age","maxAgeSeconds":315360000}}]}
```

A `null_resource` in `object_lock.tf` calls this endpoint via `curl` using
`var.cf_admin_token` (the bootstrap-only one-hour admin token). The
`cloudflare_r2_bucket_lock` provider resource ships only for object-key-level
rule-based age/date conditions — a different feature surface — so the `curl`
shim remains the bridge until a native TF resource for the bucket-default
endpoint ships (FW1 in PR #3920 plan).

If the lock-rule PUT silently fails (token rotated, scope missing), the
post-apply verification step below catches it before the bootstrap proceeds.

### Mandatory post-apply verification (operator step)

After every `terraform apply` that touches this root, the operator MUST run:

```bash
CF_ADMIN_TOKEN_BOOTSTRAP=<one-hour token> \
CF_ACCOUNT_ID=<jikigai account id> \
R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  bash apps/cla-evidence/infra/main.test.sh --live
```

The `--live` flag GETs `/accounts/{id}/r2/buckets/<name>/lock` and asserts at
least one Age rule with `maxAgeSeconds >= 315360000` exists. Exit code 0
confirms the WORM guarantee is live; non-zero means the bucket completed
creation but the Lock Rule provisioner failed silently and the bucket is
unprotected. **Do not proceed to the bootstrap PR merge until this assertion
passes** — the entire legal-evidence claim rests on the Lock Rule being
active. See user-impact-reviewer Finding 8 from PR #3201 multi-agent review
for the failure-mode rationale.

## Token rotation

- **Object-write token (`R2_CLA_EVIDENCE_*`):** synced to Doppler `prd_cla`
  config, surfaced to workflows via `DOPPLER_TOKEN_CLA` repo secret. Rotation
  cadence: yearly, or on any leak signal. See sibling section in
  `knowledge-base/engineering/ops/runbooks/cloudflare-service-token-rotation.md`.
- **State-write token:** consumed by Terraform only. Rotation cadence: yearly.

## Token blast radius

Both API tokens are **bucket-scoped**, not account-scoped (per PR #3201
multi-agent review). Each token's `resources` map names exactly the bucket it
needs via `com.cloudflare.edge.r2.bucket.<account>_default_<bucket>`:

- `cla_evidence_object_write` → `soleur-cla-evidence` only.
- `cla_evidence_state_write` → `soleur-terraform-state` only.

R2 tokens don't support prefix-level scoping — bucket is the finest grain. The
state-write token therefore covers all of `soleur-terraform-state` (which holds
other Terraform roots' state too). Tightening below bucket level requires a
dedicated state bucket per root and is deferred as out-of-scope for this layer.

`main.test.sh` includes a static-lint regression guard: any future edit
reverting to account-wide `com.cloudflare.api.account.<id>` scope fails the
gate.

## NOT in this root

- IP-allowlist on tokens — rejected at plan-review (DHH F1 + Code-Simplicity F2).
  The bucket holds already-public GitHub identities; the recurring CIDR refresh
  chore is not earned at this scope.
- A `refresh-gh-actions-cidrs.sh` helper. Same reason.
- Read-only standing tokens. Read access is generated ad-hoc via the Cloudflare
  dashboard at retrieval time (see Phase 7 runbook).
