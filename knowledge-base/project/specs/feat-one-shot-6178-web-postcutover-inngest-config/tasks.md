# Tasks — Gate co-located Inngest bootstrap on fresh web hosts (part of epic #6178)

Plan: `knowledge-base/project/plans/2026-07-11-feat-web-postcutover-inngest-colocation-toggle-plan.md`
Lane: single-domain · Threshold: single-user incident (requires CPO sign-off)

## Phase 1 — Terraform variable + wiring (contract first)
- [ ] 1.1 Add `variable "web_colocate_inngest"` to `apps/web-platform/infra/variables.tf` (`type = bool`, `default = false`, non-sensitive, description citing ADR-100 / #6178 / hr-prod-host-config-change-immutable-redeploy).
- [ ] 1.2 Add `web_colocate_inngest = var.web_colocate_inngest` to the `cloud-init.yml` templatefile map in `apps/web-platform/infra/server.tf` (`:137`, before the closing `}))`).

## Phase 2 — Gate the cloud-init runcmd block
- [ ] 2.1 Insert col-0 `%{ if web_colocate_inngest ~}` immediately before the `# Bootstrap Inngest server on first boot` comment in `cloud-init.yml`.
- [ ] 2.2 Insert col-0 `%{ endif ~}` immediately after the block's terminal `trap - EXIT` line and before the next `  - |` item. Do NOT change block indentation or `$${…}` escaping.
- [ ] 2.3 Verify with `terraform console` that `web_colocate_inngest=false` omits the block and `=true` keeps it; both `yaml.safe_load`-clean.

## Phase 3 — Tests
- [ ] 3.1 Fix AC3 in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: strip `^%{` lines before `yaml.safe_load`; add a rendered-both-states YAML-validity assertion.
- [ ] 3.2 Add toggle coverage: markers present + placed; gated span CONTAINS IREF pin + `inngest-bootstrap.sh` run; span-deleted render has NO `soleur-inngest-bootstrap` / `inngest-bootstrap.sh` and parses YAML (models false); marker-only-removed render keeps IREF + parses (models true); optional terraform-render leg with SKIP-when-absent.
- [ ] 3.3 Run `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → all PASS.
- [ ] 3.4 Run `plugins/soleur/test/cloud-init-user-data-size.test.ts` (unmodified) + infra `*.test.ts` (target-parity, web-hosts-fanout-parity, server-tf-set-e) → green.
- [ ] 3.5 `terraform fmt -check` + `terraform validate` on `apps/web-platform/infra/`.

## Phase 4 — Guardrail verification
- [ ] 4.1 Confirm `inngest-bootstrap.sh` and `cloud-init-inngest.yml` are byte-unchanged in the diff.
- [ ] 4.2 (Read-only) `terraform plan` shows no create/replace of `hcloud_server.web[*]`. No apply.
- [ ] 4.3 PR body says "part of epic #6178" (NOT `Closes`); documents the `web_colocate_inngest=true` + recreate rollback.
