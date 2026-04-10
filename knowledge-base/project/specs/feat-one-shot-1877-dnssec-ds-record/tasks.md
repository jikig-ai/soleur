# Tasks: DNSSEC DS Record and Terraform Resource

## Phase 1: Terraform Resource Setup

- [ ] 1.1 Add `cloudflare_zone_dnssec` resource to `apps/web-platform/infra/dns.tf`
  - Resource name: `cloudflare_zone_dnssec.soleur_ai`
  - Set `zone_id = var.cf_zone_id`
  - Set `status = "active"`
  - Include comment explaining Cloudflare Registrar auto-propagation
- [ ] 1.2 Run `terraform import cloudflare_zone_dnssec.soleur_ai <zone_id>` to adopt existing DNSSEC state
  - Use Doppler nested invocation pattern from `variables.tf` comments
- [ ] 1.3 Run `terraform plan` to verify no drift after import
  - If `status` field causes perpetual diff (`pending` vs `active`), add `lifecycle { ignore_changes = [status] }` block
- [ ] 1.4 Run `terraform apply` if any non-destructive changes are needed

## Phase 2: Verification

- [ ] 2.1 Check DS record propagation: `dig soleur.ai DS @8.8.8.8 +short`
  - Expected: `2371 13 2 3EDA296C18ABFBD581F7DE282C61ED8634B27651F1740EA68C9FF9FAF6D1A66D`
  - If not yet propagated, note in PR -- propagation takes 1-2 days
- [ ] 2.2 Verify DNSSEC end-to-end: `dig +dnssec soleur.ai @8.8.8.8`
  - Look for `ad` (authenticated data) flag in response
- [ ] 2.3 Check Cloudflare API status: `GET /zones/<zone_id>/dnssec`
  - Confirm `status` field (should be `pending` or `active`)

## Phase 3: Documentation and Cleanup

- [ ] 3.1 Update `knowledge-base/operations/domains.md`
  - Add `| DNSSEC | Enabled (active) |` to Security Configuration table
- [ ] 3.2 Close issue #1877 via PR body (`Closes #1877`)
