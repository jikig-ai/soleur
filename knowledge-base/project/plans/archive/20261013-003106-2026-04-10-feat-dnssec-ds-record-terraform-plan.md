---
title: "feat: Add DNSSEC DS record and Terraform resource for soleur.ai"
type: feat
date: 2026-04-10
deepened: 2026-04-10
---

# feat: Add DNSSEC DS record and Terraform resource for soleur.ai

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 5
**Research sources used:** Context7 Cloudflare provider docs, Cloudflare DNSSEC docs, Cloudflare Registrar docs, 4 institutional learnings

### Key Improvements

1. Corrected Terraform resource attributes -- `dnssec_presigned` and `dnssec_multi_signer` should be `false` (not presigned, not multi-signer)
2. Added `lifecycle { ignore_changes = [status] }` recommendation based on institutional learning about Cloudflare/Terraform drift patterns
3. Added DNSViz visual verification step and `dig +cd` bypass testing
4. Added `terraform fmt` post-edit step (institutional learning: formatting mismatches caught by lefthook)
5. Clarified import syntax from Context7 docs: `terraform import cloudflare_zone_dnssec.soleur_ai '<zone_id>'` (single-quoted zone_id, no slash format)

### Institutional Learnings Applied

- `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` -- Validates the plan's approach of using FQDN; confirms provider v4 drift patterns
- `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` -- Confirmed `cloudflare_zone_dnssec` name is valid in v4.52.5 (not renamed in v5 migration)
- `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md` -- Exit code interpretation for drift detection; relevant for verification step
- `2026-03-21-terraform-state-r2-migration.md` -- Doppler `--name-transformer tf-var` and S3 backend credential conflict pattern; import quirks with Cloudflare provider v4

## Overview

Complete the DNSSEC chain of trust for `soleur.ai` by codifying the DNSSEC configuration in Terraform and verifying DS record propagation to the `.ai` parent zone. DNSSEC was enabled on the Cloudflare zone side in #1835; this follow-through (#1877) ensures the DS record reaches the registry and the configuration is managed declaratively.

## Problem Statement / Motivation

DNSSEC is enabled on the Cloudflare zone (status: `pending` as of 2026-04-10T14:02 UTC), but:

1. The DS record has **not yet propagated** to the `.ai` parent zone (confirmed via `dig soleur.ai DS +trace` returning NSEC3 denial)
2. The DNSSEC configuration is **not in Terraform** -- it was enabled via dashboard/API in #1835 but not codified, creating drift risk
3. The `domains.md` operational document does not reflect the DNSSEC status

Since `soleur.ai` is registered with **Cloudflare Registrar**, DS record propagation is automatic -- Cloudflare publishes CDS/CDNSKEY records and scans them at intervals to push the DS to the registry. This takes 1-2 days per Cloudflare documentation. No manual registrar action is needed.

## Proposed Solution

### 1. Add `cloudflare_zone_dnssec` Terraform resource

Add a new resource to `apps/web-platform/infra/dns.tf` to manage DNSSEC declaratively:

```terraform
# DNSSEC for soleur.ai -- chain of trust via DS record at .ai registry.
# Cloudflare Registrar auto-propagates DS records via CDS/CDNSKEY scanning.
# Status transitions: disabled -> pending -> active (1-2 days for registry propagation).
#
# The lifecycle block prevents perpetual drift during the pending -> active
# transition. The API returns "pending" while the DS record propagates to the
# .ai registry, but our desired state is "active". Without ignore_changes,
# every terraform plan would show a diff. Remove the lifecycle block once
# status reaches "active" (verify via: dig soleur.ai DS @8.8.8.8 +short).
resource "cloudflare_zone_dnssec" "soleur_ai" {
  zone_id             = var.cf_zone_id
  status              = "active"
  dnssec_multi_signer = false
  dnssec_presigned    = false

  lifecycle {
    ignore_changes = [status]
  }
}
```

### Research Insights -- Terraform Resource

**Attribute clarification (from Context7 Cloudflare provider docs):**

- `dnssec_multi_signer` must be `false` -- soleur.ai uses single-signer DNSSEC (Cloudflare only)
- `dnssec_presigned` must be `false` -- zone is not transferred in with external DNSSEC signatures
- `dnssec_use_nsec3` can be omitted (defaults to `false`) -- standard NSEC is sufficient for this zone
- `status` accepts `"active"` or `"disabled"` only; API returns `"pending"` as a read-only transition state

**Import quirks (from institutional learnings):**

- Cloudflare provider v4.52.5 import uses simple zone_id format (Context7 confirmed: `terraform import cloudflare_zone_dnssec.soleur_ai '<zone_id>'`)
- Unlike `cloudflare_zero_trust_access_policy`, the DNSSEC resource import is not broken in v4.x (per learning `2026-03-21-terraform-state-r2-migration.md`)
- After import, always run `terraform plan` to verify the imported state matches config; Cloudflare API may return additional computed attributes

**Post-edit hygiene (from learning `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`):**

- Run `terraform fmt` after editing `.tf` files -- inline comments can cause formatting mismatches that break lefthook pre-commit hooks
- Run `terraform validate` to catch v4/v5 attribute name mismatches before applying

Then run `terraform import` to adopt the existing DNSSEC state:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform import cloudflare_zone_dnssec.soleur_ai '5af02a2f394e9ba6e0ea23c381a26b67'
```

After import, run format and validate:

```bash
cd apps/web-platform/infra && terraform fmt && terraform validate
```

### 2. Verify DS record propagation

Check whether the DS record has propagated to the `.ai` parent zone:

```bash
dig soleur.ai DS @8.8.8.8 +short
```

Expected output (when propagated):

```text
2371 13 2 3EDA296C18ABFBD581F7DE282C61ED8634B27651F1740EA68C9FF9FAF6D1A66D
```

If not yet propagated, verify CDS records are published:

```bash
dig soleur.ai CDS @derek.ns.cloudflare.com +short
```

This was confirmed working as of 2026-04-10 (returns the matching CDS record).

### 3. Verify DNSSEC validation end-to-end

```bash
dig +dnssec soleur.ai @8.8.8.8
```

Look for the `ad` (authenticated data) flag in the response flags section, indicating the resolver validated the DNSSEC chain.

### Research Insights -- Verification

**Additional verification tools (from Cloudflare troubleshooting docs):**

- **DNSViz:** Visit [dnsviz.net/d/soleur.ai/dnssec/](https://dnsviz.net/d/soleur.ai/dnssec/) for a visual DNSSEC chain-of-trust diagram. Useful for identifying exactly where the chain breaks if validation fails.
- **`dig +cd` bypass test:** Run `dig +cd soleur.ai @8.8.8.8` (checking disabled) to verify DNS resolution works without DNSSEC validation. If this succeeds but `dig +dnssec` fails, the issue is in the DNSSEC chain, not the underlying DNS records.
- **RRSIG inspection:** Run `dig soleur.ai RRSIG @8.8.8.8 +short` to verify zone signing is active. RRSIG records should exist for A, AAAA, TXT, and other record types.
- **Multiple resolver check:** Test against multiple resolvers to confirm propagation is not resolver-specific:

```bash
dig soleur.ai DS @8.8.8.8 +short       # Google
dig soleur.ai DS @1.1.1.1 +short       # Cloudflare
dig soleur.ai DS @9.9.9.9 +short       # Quad9
```

**Propagation timeline expectations:**

- CDS/CDNSKEY records are already published at Cloudflare nameservers (confirmed 2026-04-10)
- Cloudflare Registrar scans CDS/CDNSKEY at regular intervals and submits DS via EPP to the `.ai` registry
- Total propagation: 1-2 days from enablement (per Cloudflare Registrar docs)
- The `.ai` TLD is operated by Identity Digital; registry processing time may add up to 24 hours on top of Cloudflare's submission

### 4. Update `knowledge-base/operations/domains.md`

Add DNSSEC status to the Security Configuration table:

```markdown
| DNSSEC | Enabled (active) |
```

### 5. Terraform plan/apply

Run `terraform plan` to verify no drift, then `terraform apply` if the import introduced any configuration differences:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform plan
```

## Technical Considerations

- **Cloudflare provider version:** The project uses `cloudflare/cloudflare ~> 4.0` (locked at v4.52.5 in `.terraform.lock.hcl`). The `cloudflare_zone_dnssec` resource is available in v4.x and the name is unchanged in v5 (per learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`).
- **Import required:** DNSSEC was already enabled via #1835. The Terraform resource must be imported, not created from scratch, to avoid attempting to re-enable and potentially disrupting the pending propagation.
- **Status field:** Setting `status = "active"` is correct. Cloudflare treats `active` as the desired state; the API returns `pending` while propagation is in progress. The `lifecycle { ignore_changes = [status] }` block prevents perpetual drift during the transition period.
- **No DS record resource needed:** The DS record is at the **parent zone** (`.ai`), not the `soleur.ai` zone. Cloudflare Registrar handles propagation automatically. There is no Terraform resource for registrar-level DS records.
- **`.ai` TLD quirks:** The `.ai` registry (operated by the Government of Anguilla via Identity Digital) supports DNSSEC. CDS/CDNSKEY auto-scanning support depends on the registry operator, but Cloudflare Registrar handles the EPP DS submission directly.
- **Sharp edge -- perpetual drift:** The `cloudflare_zone_dnssec` resource's `status` attribute reflects the actual propagation state (`pending` vs `active`). The `lifecycle { ignore_changes = [status] }` block is included in the resource definition to prevent this. Once DS propagation completes and status reaches `active`, remove the lifecycle block and verify a clean `terraform plan`.
- **Sharp edge -- drift detection exit codes (from learning `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`):** After adding this resource, verify the scheduled drift detection workflow produces exit code 0, not exit code 1. Exit 1 means the plan itself errored (e.g., missing variable), which silently masks real drift on other resources. A successful import followed by `terraform plan` exit code 0 confirms no masking.
- **Sharp edge -- `terraform fmt` required after edit:** Adding inline comments to `.tf` files commonly introduces formatting mismatches (extra spaces before `#`). Always run `terraform fmt` after editing, as lefthook pre-commit hooks will reject unformatted files (per learning `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`).

## Acceptance Criteria

- [x] `cloudflare_zone_dnssec.soleur_ai` resource exists in `apps/web-platform/infra/dns.tf`
- [x] Resource is imported into Terraform state (no orphaned/duplicate resources)
- [x] `terraform plan` shows no unexpected changes after import (no DNSSEC-related changes)
- [ ] DS record is present at the `.ai` parent zone (pending — 1-2 day propagation)
- [ ] DNSSEC validation works end-to-end (pending DS propagation)
- [x] `knowledge-base/operations/domains.md` documents DNSSEC as enabled
- [ ] Issue #1877 is closed (will close via PR body)

## Test Scenarios

- Given DNSSEC is enabled and Terraform resource is imported, when `terraform plan` runs, then exit code is 0 and no changes are proposed (or only non-destructive differences)
- Given the DS record has propagated, when querying `dig soleur.ai DS @8.8.8.8`, then the DS record `2371 13 2 3EDA296C18ABFBD581F7DE282C61ED8634B27651F1740EA68C9FF9FAF6D1A66D` is returned
- Given DNSSEC is fully active, when querying `dig +dnssec soleur.ai @8.8.8.8`, then the response includes the `ad` flag
- Given the Terraform resource uses `status = "active"` with `lifecycle { ignore_changes = [status] }`, when the API returns `status = "pending"` during propagation, then no destructive plan is generated
- Given the `.tf` file has been edited, when `terraform fmt` runs, then no formatting changes are needed (exit code 0)
- Given the `.tf` file has been edited, when `terraform validate` runs, then validation passes (no v4/v5 attribute name mismatches)
- **Verification commands for QA:**
  - `dig soleur.ai DS @8.8.8.8 +short` -- expects DS record (may take 1-2 days)
  - `dig soleur.ai DS @1.1.1.1 +short` -- cross-resolver confirmation
  - `dig +dnssec soleur.ai @8.8.8.8` -- expects `ad` flag in response
  - `dig +cd soleur.ai @8.8.8.8` -- expects normal response (DNSSEC bypass sanity check)
  - DNSViz: [dnsviz.net/d/soleur.ai/dnssec/](https://dnsviz.net/d/soleur.ai/dnssec/) -- visual chain-of-trust verification

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a straightforward infrastructure-as-code task. The `cloudflare_zone_dnssec` resource is well-documented and the import workflow is standard. The only risk is potential Terraform drift during the `pending` -> `active` transition, mitigated by the `lifecycle` block fallback. No architectural concerns.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Manual dashboard verification only (no Terraform) | Rejected | Violates infrastructure-as-code principle; creates drift risk |
| Wait for `active` status before adding Terraform resource | Rejected | Delays codification unnecessarily; import works in `pending` state |
| Add DS record manually at registrar | Not applicable | Cloudflare Registrar handles this automatically for Cloudflare-registered domains |

## References

- Issue: #1877 (this follow-through)
- Parent issue: #1835 (DNSSEC enablement)
- Cloudflare DNSSEC docs: [developers.cloudflare.com/dns/dnssec](https://developers.cloudflare.com/dns/dnssec/)
- Cloudflare Registrar DNSSEC: [developers.cloudflare.com/registrar/account-options/enable-dnssec](https://developers.cloudflare.com/registrar/account-options/enable-dnssec/)
- Terraform resource: [cloudflare_zone_dnssec](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone_dnssec)
- Existing DNS config: `apps/web-platform/infra/dns.tf`
- Existing variables: `apps/web-platform/infra/variables.tf`
- Domain registry: `knowledge-base/operations/domains.md`

## Current State (2026-04-10)

| Check | Result |
|-------|--------|
| Cloudflare DNSSEC status | `pending` (enabled 2026-04-10T14:02 UTC) |
| CDS record at CF nameservers | Present and correct |
| CDNSKEY record at CF nameservers | Present and correct |
| DS record at `.ai` parent | Not yet propagated (NSEC3 denial) |
| Terraform resource | Not yet added |
| Expected propagation | Within 1-2 days of enablement |
