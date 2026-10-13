# Tasks — Gate co-located Inngest bootstrap on fresh web hosts (part of epic #6178)

Plan: `knowledge-base/project/plans/2026-07-11-feat-web-postcutover-inngest-colocation-toggle-plan.md`
Lane: single-domain · Threshold: single-user incident (requires CPO sign-off)

## Phase 1 — Terraform variable + wiring (contract first)
- [x] 1.1 Add `variable "web_colocate_inngest"` to `apps/web-platform/infra/variables.tf` (`type = bool` — LOAD-BEARING for string→bool coercion, `default = false`, non-sensitive, description citing ADR-100 / #6178 / hr-prod-host-config-change-immutable-redeploy).
- [x] 1.2 Add `web_colocate_inngest = var.web_colocate_inngest` to the `cloud-init.yml` templatefile map in `apps/web-platform/infra/server.tf` (`:137`, before the closing `}))`).

## Phase 2 — Gate the cloud-init runcmd block
- [x] 2.1 Insert col-0 `%{ if web_colocate_inngest ~}` immediately before the `# Bootstrap Inngest server on first boot` comment in `cloud-init.yml`.
- [x] 2.2 Insert col-0 `%{ endif ~}` immediately after the block's terminal `trap - EXIT` line and before the next `  - |` item. Do NOT change block indentation or `$${…}` escaping.
- [x] 2.3 Verify with `terraform console` that `web_colocate_inngest=false` (bool) AND `="false"` (string) both omit the block, and `=true` keeps it; all `yaml.safe_load`-clean.

## Phase 3 — Tests (single render authority + cheap structural smoke)
- [x] 3.1 Fix AC3 in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: strip `^%{` lines before `yaml.safe_load` (STRIP-ONLY — no rendered-validity assertion here; it lives once in the render leg).
- [x] 3.2 Add cheap structural smoke (no terraform): exactly one `%{ if web_colocate_inngest ~}` + one `%{ endif ~}`; `if` precedes the bootstrap comment; `endif` follows `trap - EXIT` and precedes the next `- |`; static grep asserting `type = bool` on the variable.
- [x] 3.3 Add the authoritative terraform-render leg (SKIP locally if `! command -v terraform`): render for `web_colocate_inngest` = `false` (bool), `"false"` (string), `true` (bool). Assert false/`"false"` OMIT `soleur-inngest-bootstrap` + the `inngest-bootstrap.sh` invocation AND RETAIN `--name soleur-web-platform` + `INNGEST_BASE_URL` + `/run/soleur-hostscripts.ok`, `yaml.safe_load`-clean; true INCLUDES the bootstrap, clean. Var list = server.tf map placeholders + the toggle. Do NOT keep the old awk span-deletion model.
- [x] 3.4 Add a `hashicorp/setup-terraform@…v4.0.0` step to the `deploy-script-tests` job in `.github/workflows/infra-validation.yml` so the render leg runs (not SKIPs) in CI.
- [x] 3.5 Run `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` → all PASS.
- [x] 3.6 Run `plugins/soleur/test/cloud-init-user-data-size.test.ts` (unmodified) + infra `*.test.ts` (target-parity, web-hosts-fanout-parity, server-tf-set-e) → green.
- [x] 3.7 `terraform fmt -check` + `terraform validate` on `apps/web-platform/infra/`.

## Phase 4 — Guardrail verification
- [x] 4.1 Confirm `inngest-bootstrap.sh` and `cloud-init-inngest.yml` are byte-unchanged in the diff.
- [x] 4.2 (Read-only) `terraform plan` shows no create/replace of `hcloud_server.web[*]`. No apply.
- [x] 4.3 PR body says "part of epic #6178" (NOT `Closes`); documents the `web_colocate_inngest=true` + recreate rollback.
