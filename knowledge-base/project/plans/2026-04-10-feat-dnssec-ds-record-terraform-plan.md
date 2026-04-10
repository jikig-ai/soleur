---
title: "feat: Add DNSSEC DS record and Terraform resource for soleur.ai"
type: feat
date: 2026-04-10
---

# feat: Add DNSSEC DS record and Terraform resource for soleur.ai

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
resource "cloudflare_zone_dnssec" "soleur_ai" {
  zone_id = var.cf_zone_id
  status  = "active"
}
```

Then run `terraform import` to adopt the existing DNSSEC state:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform import cloudflare_zone_dnssec.soleur_ai <zone_id>
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

- **Cloudflare provider version:** The project uses `cloudflare/cloudflare ~> 4.0`. The `cloudflare_zone_dnssec` resource is available in v4.x.
- **Import required:** DNSSEC was already enabled via #1835. The Terraform resource must be imported, not created from scratch, to avoid attempting to re-enable and potentially disrupting the pending propagation.
- **Status field:** Setting `status = "active"` is correct. Cloudflare treats `active` as the desired state; the API may return `pending` while propagation is in progress, but Terraform will not attempt to force a transition.
- **No DS record resource needed:** The DS record is at the **parent zone** (`.ai`), not the `soleur.ai` zone. Cloudflare Registrar handles propagation automatically. There is no Terraform resource for registrar-level DS records.
- **`.ai` TLD quirks:** The `.ai` registry (operated by the Government of Anguilla via Identity Digital) supports DNSSEC. CDS/CDNSKEY auto-scanning support depends on the registry operator, but Cloudflare Registrar handles the EPP DS submission directly.
- **Sharp edge -- perpetual drift:** The `cloudflare_zone_dnssec` resource's `status` attribute reflects the actual propagation state (`pending` vs `active`). If Terraform is applied while status is `pending`, verify the provider does not generate a perpetual diff. If it does, use a `lifecycle { ignore_changes = [status] }` block and remove it once status reaches `active`.

## Acceptance Criteria

- [ ] `cloudflare_zone_dnssec.soleur_ai` resource exists in `apps/web-platform/infra/dns.tf`
- [ ] Resource is imported into Terraform state (no orphaned/duplicate resources)
- [ ] `terraform plan` shows no unexpected changes after import
- [ ] DS record is present at the `.ai` parent zone (`dig soleur.ai DS @8.8.8.8` returns the record)
- [ ] DNSSEC validation works end-to-end (`dig +dnssec soleur.ai` shows `ad` flag)
- [ ] `knowledge-base/operations/domains.md` documents DNSSEC as enabled
- [ ] Issue #1877 is closed

## Test Scenarios

- Given DNSSEC is enabled and Terraform resource is imported, when `terraform plan` runs, then no changes are proposed (or only non-destructive differences)
- Given the DS record has propagated, when querying `dig soleur.ai DS @8.8.8.8`, then the DS record `2371 13 2 3EDA296C18ABFBD581F7DE282C61ED8634B27651F1740EA68C9FF9FAF6D1A66D` is returned
- Given DNSSEC is fully active, when querying `dig +dnssec soleur.ai @8.8.8.8`, then the response includes the `ad` flag
- Given the Terraform resource uses `status = "active"`, when the API returns `status = "pending"` during propagation, then no destructive plan is generated (may require `lifecycle` block)

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
