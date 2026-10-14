# Tasks — fix(infra): bake GHCR read-creds into web-host cloud-init `ghcr_login` (#6090)

Plan: `knowledge-base/project/plans/2026-07-07-fix-ghcr-login-bake-creds-cold-boot-plan.md`
Lane: cross-domain (spec.md absent — fail-closed default). Ref #6090.

## Phase 1 — Terraform var passthrough (producer first)
- [ ] 1.1 In `apps/web-platform/infra/server.tf`, add to the `hcloud_server.web`
      `templatefile("${path.module}/cloud-init.yml", { … })` map (near `sentry_dsn`):
      `ghcr_read_user = var.ghcr_read_user` and `ghcr_read_token = var.ghcr_read_token`.
- [ ] 1.2 Confirm `var.ghcr_read_user` / `var.ghcr_read_token` already declared + `sensitive = true`
      in `variables.tf` (no edit expected — verify only).

## Phase 2 — cloud-init `ghcr_login` bake + hardened fallback (consumer)
- [ ] 2.1 In `apps/web-platform/infra/cloud-init.yml` `ghcr_login` block (~L438-452), replace the
      two `timeout 15 doppler secrets get GHCR_READ_{USER,TOKEN} … || true` fetches with
      baked-preferred (`GHCR_USER='${ghcr_read_user}'` / `GHCR_TOKEN='${ghcr_read_token}'`) +
      hardened Doppler fallback (`timeout 45` + `until … [ -n "$VAR" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done`).
- [ ] 2.2 Preserve verbatim the detail-tag capture block (`ghcr_creds_missing` / `ghcr_login_ok` /
      `ghcr_login_fail`) and the downstream `pull_err:` append.
- [ ] 2.3 Verify no `$$`-escaping needed (`$(`, `$((`, `$VAR` pass through; only `${…}` interpolates).

## Phase 3 — AC19 test
- [ ] 3.1 Append AC19 to `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`
      after the AC18 block (before the pass/fail tally): assert baked-preferred + hardened
      timeout/retry in cloud-init.yml, and both var passthroughs in server.tf. Use the file's
      existing `ok`/`no` helpers.

## Phase 4 — Validation (all must pass)
- [ ] 4.1 `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`
- [ ] 4.2 cloud-init schema Valid (sed `${…}`→dummyval, `$${`→`${`, then `cloud-init schema --config-file`)
- [ ] 4.3 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`
- [ ] 4.4 Sibling: `server-tf-set-e.test.sh`, `cron-egress-enforce-probe.test.sh`,
      `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-plugin-seed.test.sh`
- [ ] 4.5 `actionlint`; `terraform -chdir=apps/web-platform/infra fmt -check` + `validate`
- [ ] 4.6 `git grep -c 'timeout 15 doppler secrets get GHCR_READ' apps/web-platform/infra/cloud-init.yml` == 0

## Phase 5 — Ship
- [ ] 5.1 PR body: `Ref #6090` (NOT `Closes`) + `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- [ ] 5.2 Post-merge web-2 recreate = OPERATOR-GATED (`apply-web-platform-infra.yml -f apply_target=web-2-recreate`);
      do NOT auto-dispatch. Verify `ghcr_login_ok` detail tag + `cloud_init_complete` via Sentry (no SSH); then `gh issue close 6090`.
