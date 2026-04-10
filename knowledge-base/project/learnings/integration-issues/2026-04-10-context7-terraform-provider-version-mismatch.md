# Learning: Context7 docs may not match pinned Terraform provider version

## Problem

During the plan/deepen-plan phase for adding a `cloudflare_zone_dnssec` resource, Context7 MCP was used to research the resource's available attributes. Context7 returned documentation for a newer Cloudflare provider version than the one actually installed (v4.52.5). This caused three `terraform validate` failures on the first attempt:

1. `dnssec_multi_signer` is not a valid attribute in v4.52.5
2. `dnssec_presigned` is not a valid attribute in v4.52.5
3. `status` is a computed-only attribute -- cannot be set in config

The plan also prescribed a `lifecycle { ignore_changes = [status] }` block, which is redundant for a computed attribute and produced a warning. After fixing the resource attributes, a stale comment referencing the removed lifecycle block was left behind and caught by review agents.

Separately, the first `terraform init` attempt used wrong Doppler secret names (`R2_ACCESS_KEY_ID` instead of `AWS_ACCESS_KEY_ID`), despite this being documented in an existing learning.

## Solution

Removed all three unsupported attributes (`dnssec_multi_signer`, `dnssec_presigned`, `status`) and the `lifecycle` block, leaving only `zone_id = var.cf_zone_id`. Fixed the stale comment to accurately describe the minimal resource. Used correct Doppler key names (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

The correct `cloudflare_zone_dnssec` resource for provider v4.52.5 is:

```hcl
resource "cloudflare_zone_dnssec" "this" {
  zone_id = var.cf_zone_id
}
```

## Key Insight

Context7 MCP documentation may not match the pinned provider version. It returns the latest available docs, not version-specific docs. Always run `terraform validate` immediately after adding a new resource -- before proceeding with import, plan, or apply. The plan phase should cross-check Context7 results against the actual provider version in `.terraform.lock.hcl` or the version constraint in `main.tf`.

This is a generalization of the v4/v5 naming issue documented in `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`. That learning covers resource and attribute renames between major versions; this one covers Context7 as a specific vector for version-mismatched documentation, including computed-vs-configurable attribute differences within a single major version.

## Session Errors

1. **Plan prescribed unsupported Terraform attributes (dnssec_multi_signer, dnssec_presigned)** -- Recovery: Removed both attributes after `terraform validate` failure. -- Prevention: After retrieving resource docs from Context7, check the installed provider version (`grep -A2 'registry.terraform.io/cloudflare/cloudflare' .terraform.lock.hcl`) and verify each attribute exists in that version by running `terraform validate` before proceeding.

2. **Plan prescribed `status = "active"` which is computed-only in v4.52.5** -- Recovery: Removed the `status` attribute after `terraform validate` reported it as not configurable. -- Prevention: When Context7 lists an attribute, distinguish between configurable and computed-only. If unsure, run `terraform validate` -- computed attributes produce a clear error when set explicitly.

3. **Plan prescribed `lifecycle { ignore_changes = [status] }` for a computed attribute** -- Recovery: Removed the lifecycle block since it is redundant when the attribute is already computed-only. -- Prevention: Only add `lifecycle { ignore_changes }` for attributes that are both configurable and subject to external drift. Computed attributes are never in the plan diff and do not need ignore rules.

4. **Stale comment left after fixing resource attributes** -- Recovery: Review agents caught the stale comment referencing the removed lifecycle block; updated to accurately describe the resource. -- Prevention: After removing code, re-read surrounding comments and update or remove any that reference the deleted code. Treat comment accuracy as part of the fix, not a separate cleanup.

5. **Used wrong Doppler secret names (R2_ACCESS_KEY_ID vs AWS_ACCESS_KEY_ID) on first try** -- Recovery: Corrected to `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` per the existing dual-credential pattern. -- Prevention: Before running `terraform init` with Doppler, reference the canonical pattern in `2026-04-05-terraform-doppler-dual-credential-pattern.md` or the AGENTS.md rule: "Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately for the R2 backend."

## Related Learnings

- [2026-03-20-cloudflare-terraform-v4-v5-resource-names.md](../2026-03-20-cloudflare-terraform-v4-v5-resource-names.md) -- v4/v5 attribute naming mismatches
- [2026-04-05-terraform-doppler-dual-credential-pattern.md](2026-04-05-terraform-doppler-dual-credential-pattern.md) -- R2 backend credential extraction pattern

## Tags

category: integration-issues
module: terraform, context7, cloudflare, doppler
