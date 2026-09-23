# Tasks: fix a dark fresh web-host boot (zot-first seed pull) — Ref #8651

Plan: `knowledge-base/project/plans/2026-09-23-fix-web-host-fresh-boot-zot-primary-plan.md`

## Phase 1: Setup (RED first)

- [ ] 1.1 Measure the current web user_data render (`plugins/soleur/test/cloud-init-user-data-size.test.ts`); record local vs CI (24,556) figures.
- [ ] 1.2 Create `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh`: terraform-render `cloud-init.yml` (non-empty `sentry_dsn`), extract runcmd item 1 joined with the host-script extraction item, rewrite /run and /etc/default paths (asserted sed), stop at STAGE=extract, execute under stubs (`docker`, argv-validating `ip`, recording `sleep`, `timeout`, `doppler`, `curl`, fake `/run`).
  - [ ] 1.2.1 Guard 1 assertions (zot-first pull, no doppler spawn, login before pull, no GHCR pull after failed GHCR login, two-leg fatal detail, host_name tag, image-ref file).
  - [ ] 1.2.2 Guard 2 assertions (NIC wait arms, 75x2 s bound, empty-address guard, stage names routed by `web_private_nic_boot_gate`).
  - [ ] 1.2.3 Guard 3 census (0 doppler invocations above the terminal `set -a` source; ≥1 below).
  - [ ] 1.2.4 Mutation section executing the Guard Contract matrices + harness rows; cross-template `zot=[`/`ghcr=[` parity assertion.
  - [ ] 1.2.5 Confirm the suite is RED against today's block.
- [ ] 1.3 Register the suite in `.github/workflows/infra-validation.yml`.

## Phase 2: Core Implementation

- [ ] 2.1 `server.tf`: add `zot_pull_user = local.zot_pull_user`, `zot_pull_token = random_password.zot_pull.result` to the `hcloud_server.web` templatefile map; rationale prose (bake precedent, 150 s NIC bound provenance, rotation note, cleartext Basic on private net) lives here.
- [ ] 2.2 Update the other web render maps: `cloud-init-inngest-bootstrap.test.sh` `render_ci()`, `cloud-init-user-data-size.test.ts`; run `.github/scripts/validate-infra-templates.sh`.
- [ ] 2.3 `cloud-init.yml` seed item: delete Doppler GHCR arms + ZOT_* Doppler reads; inline NIC wait; baked zot login; unconditional zot REF; bounded zot pull; GHCR flip only after a successful GHCR login; two-leg fatal detail within 200 chars (fixed fields first, `pull_err:` kept); login outcomes persisted across the GHCR subshell via /run files; success detail via `/run/soleur-stage-detail`; keep emit call forms, tripwire line, closing `set +e`.
- [ ] 2.4 `_emit`: add `host_name` tag; delete the Doppler DSN fallback and its source line.
- [ ] 2.5 Colocated-inngest item: `ZURL='${registry_endpoint}'`.
- [ ] 2.6 Re-measure user_data; trim comments first; raise `WEB_GZIP_BUDGET` only from a CI line with rationale; record headroom in PR body (file a follow-up if < ~100 B).
- [ ] 2.7 `scripts/fresh-host-boot-trail.sh`: add `message:"app image served"` to QUERY; out-of-slice image-origin line; `--image-origin <host_name>` mode.
- [ ] 2.8 `soleur-host-bootstrap-observability.test.sh` AC8: new literal + pair + metacharacter assertion; fixture for the out-of-slice origin line.

## Phase 3: Testing and records

- [ ] 3.1 `cloud-init-ghcr-seed-login.test.sh`: retire check 1/1b (Doppler GHCR fetch) and §1A re-fetch assertions (assert absence with reason); keep login-before-pull and baked-DSN; keep its `pull_ln` anchor matching the final loop form.
- [ ] 3.1b `sentry-zot-mirror-fallback-alert-op-contract.test.ts`: `host_name` appended after `detail`; loosen the tag-string pin to an open prefix (ADR-147).
- [ ] 3.1c `cloud-init-user-data-size.test.ts` AC1c line stays byte-identical; `soleur-host-bootstrap-observability.test.sh` AC19(2) retired with absence assertion, AC18 `pull_err:` still satisfied.
- [ ] 3.2 Confirm unchanged-green: `nic-wait-gate.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-zot-pull-mutation.test.sh`.
- [ ] 3.3 ADR-096 amendment (#8651): premise correction + bake paragraph + "fresh boot depends entirely on zot".
- [ ] 3.4 `model.c4` `hetzner -> zotRegistry` fresh-boot clause; run C4 tests + `c4-count-parity.test.sh`.
- [ ] 3.5 `scripts/encryption-posture-ledger.json` web->zot `does_not_defend` gains the credential; run `lint-encryption-posture.py`.
- [ ] 3.6 Verify: no host-scripts file in the diff; `zot-soak-6122.sh` unchanged; no closing keyword for #6500/#6122/#6438/#8651 in commits or PR body; PR body first line = "merging alone mutates production: no".

## Phase 4: Delivery (post-merge)

- [ ] 4.1 Dispatch `web-host-replace` of web-2 (`confirm=REPLACE-web-2`, no `image_tag` override), arm a watch, route the environment approval.
- [ ] 4.2 Read the boot trail: image-origin line `app_zot` with `ghcr_login=fail`, verdict `fresh_boot_ready`, no seed fatal.
- [ ] 4.3 Close #8651 as completed with run URL + event ids; close or comment #6985; `Ref` comments on #6500, #6122, #6438. web-2 stays out of service.
