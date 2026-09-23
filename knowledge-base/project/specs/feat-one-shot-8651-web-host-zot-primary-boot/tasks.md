# Tasks: fix a dark fresh web-host boot (zot-first seed pull) — Ref #8651

Plan: `knowledge-base/project/plans/2026-09-23-fix-web-host-fresh-boot-zot-primary-plan.md` (deepened 2026-09-23)

## Phase 1: Setup (RED first)

- [x] 1.1 Measure the current web user_data render (`plugins/soleur/test/cloud-init-user-data-size.test.ts`, 70 pass at plan time; figure via an uncommitted local lower bound); record local vs CI (24,556).
- [x] 1.2 Create `apps/web-platform/infra/cloud-init-web-zot-seed.test.sh`: terraform-render `cloud-init.yml` (non-empty `sentry_dsn`, `host_name="soleur-web-2"`); extract runcmd item 1 joined with the host-script extraction item; rewrite `/run` + `/etc/default` into a sandbox and assert zero residuals; truncate at `STAGE=extract` with a never-printed sentinel; run under `timeout 20`.
  - [x] 1.2.1 Stubs: stateful `docker` (pull fails unless a prior `login` to that registry succeeded; failing login echoes stdin to stderr), argv-validating `ip` (converging variant), recording `sleep`, `timeout`, `doppler` (spawn log), `curl` (records POST bodies).
  - [x] 1.2.2 Guard 1 assertions: zot-first pull for `@sha256` refs, tag ref never hits the endpoint, no doppler spawn, `insecure-registries` write < zot login < first pull, token appears once in the `printf | docker login --password-stdin` form, token absent from every POST body and `/run` file, ≤200-char fixed-fields-first fatal detail, `cause=auth|unreach|manifest|timeout|unpinned`, image-ref file.
  - [x] 1.2.3 Guard 2 assertions: counter-bounded 75×2 s wait, `nic=<outcome>:<s>` in the detail, one routed warning on timeout/probe-fault, none on ready, empty-address guard, non-canonical address must-PASS.
  - [x] 1.2.4 Guard 3 census: 0 Doppler invocations (incl. `soleur-doppler-download`) above the single terminal `set -a` anchor; known-positive injection = 1; baseline at `3aaaede525` = 11; no `set -x`/xtrace.
  - [x] 1.2.5 Mutation section for Guards 1–3 (+ harness rows); cross-template per-leg wording parity with `cloud-init-inngest.yml` (comments stripped); `CI=true` + no terraform = FAIL.
  - [x] 1.2.6 Confirm RED against today's block (terraform locally, or record the red CI run URL).
- [x] 1.3 Register the suite in `.github/workflows/infra-validation.yml` `deploy-script-tests` next to `nic-wait-gate.test.sh` (job is advisory — ship must read it).

## Phase 2: Core Implementation

- [x] 2.1 `server.tf`: add `zot_pull_user = local.zot_pull_user`, `zot_pull_token = random_password.zot_pull.result` (no `nonsensitive()`) to the `hcloud_server.web` templatefile map; rationale prose (bake precedent, 150 s NIC bound provenance, rotation note, cleartext Basic on private net, read-only ACL) lives here.
- [x] 2.2 Update the other web render maps: `cloud-init-inngest-bootstrap.test.sh` `render_ci()`, `cloud-init-user-data-size.test.ts`; run `.github/scripts/validate-infra-templates.sh`.
- [x] 2.3 `cloud-init.yml` seed item: delete Doppler GHCR arms + ZOT_* Doppler reads; counter-bounded inline NIC wait (emit only timeout/probe-fault); baked zot login outside the GHCR subshell or persisted to `/run`; REF → zot only for `@sha256` refs; bounded zot attempts; GHCR flip only after a successful GHCR login; fixed-fields-first fatal detail with `cause` classification and pattern-redacted tail (keep `pull_err:`); success detail via `/run/soleur-stage-detail` before the byte-identical `app_zot` line, clear after; `( umask 077; … )` for `/run` files; keep the `until docker pull "$REF"` anchor, tripwire line, closing `set +e`.
- [x] 2.4 `_emit` and the `bootcmd:` beacon: add `host_name` (after `detail`); delete `_emit`'s Doppler DSN fallback and its source line.
- [x] 2.5 Colocated-inngest item: `ZURL='${registry_endpoint}'`.
- [x] 2.6 Re-measure user_data; trim comments first; raise `WEB_GZIP_BUDGET` only from a CI line with rationale; record headroom in the PR body (follow-up issue if < ~100 B).
- [x] 2.7 `scripts/fresh-host-boot-trail.sh`: add `message:"app image served"` to QUERY; out-of-slice image-origin line; `--image-origin <host_name>` mode (server-side `stage:`/`host_name:` filter, 14d, `TRANSIENT:` exit 2 on non-200/missing token/full page).
- [x] 2.8 `soleur-host-bootstrap-observability.test.sh` AC8: new literal, reverse pair on the full `app image served by zot`, prefix assertion, metacharacter assertion; 12-event fixture for the out-of-slice line.
- [x] 2.9 `scripts/followthroughs/web-fresh-boot-zot-8651.sh` + `.test.sh` (exit 0 on `app_zot` with `zot_login=ok` for `soleur-web-2` newer than `earliest` and no later seed fatal; 1 not yet; 2 `TRANSIENT:`).

## Phase 3: Testing and records

- [x] 3.1 `cloud-init-ghcr-seed-login.test.sh`: retire checks 1/1b and §1A (absence assertions with reason); keep login-before-pull and baked-DSN; `pull_ln` anchor matches the final loop.
- [x] 3.1b `sentry-zot-mirror-fallback-alert-op-contract.test.ts`: loosen the tag-string pin to an open prefix (ADR-147 "add tags; never rename the message").
- [x] 3.1c `cloud-init-user-data-size.test.ts` AC1c line byte-identical; `soleur-host-bootstrap-observability.test.sh` AC19(2) retired with absence assertion, AC18 `pull_err:` green.
- [ ] 3.2 Confirm unchanged-green: `nic-wait-gate.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-zot-pull-mutation.test.sh`.
- [x] 3.3 ADR-096 amendment (#8651): premise correction, replace "Everywhere else in the fleet…", digest-only rewrite, "fresh boot depends entirely on zot".
- [x] 3.3b ADR-114 + ADR-123 one-line cross-references (ADR-123 "GHCR fallback keeps it serving" marked stale).
- [x] 3.4 `model.c4`: `hetzner` element, `hetzner -> zotRegistry` edge (fresh-boot clause + SOLE scoped to deploy), `ghcr` system ("DELETED" scoped to deploy); regenerate `model.likec4.json`; run C4 tests + `c4-count-parity.test.sh`.
- [x] 3.5 `scripts/encryption-posture-ledger.json` web->zot `does_not_defend` gains the credential (shared, read-only ACL); run `lint-encryption-posture.py`.
- [ ] 3.6 Verify: no `local.host_script_files` path in the diff; `zot-soak-6122.sh` unchanged; no closing keyword for #6500/#6122/#6438/#8651 in commits or PR body; PR body first line = "merging alone mutates production: no".

### Implementation deviations (recorded, not silent)

- 1.1: local render 24,644 B before → 24,156 B after (−488 B); budget 24,740 unchanged. CI is the authority (~32 B above local).
- 1.2.6: RED confirmed locally against the pre-change block — Doppler census 11 (== the 3aaaede525 baseline) before any other row ran.
- 2.2: `validate-infra-templates.sh` fails closed locally (no `cloud-init` binary here); it runs in CI's `deploy-script-tests`.
- 2.3: `/run` files are pre-created with `install -m 600 /dev/null` (one loop) instead of `( umask 077; … )` subshells — same 0600 property, fewer bytes. The zot and GHCR legs are bounded `timeout 180 docker pull "$REF"` loops (3 attempts each) rather than `until docker pull "$REF"`; the seed-login test's `pull_ln` anchor moved with it. The NIC wait and zot login run in the main shell (not the GHCR subshell), so no `/run` persistence of W/ZL is needed.
- 2.8: the 12-event out-of-slice fixture and the `--image-origin` TRANSIENT rows live in `cloud-init-web-zot-seed.test.sh` (Guard 4 section, stubbed curl); AC8's static lockstep lives in the observability suite.
- 2.9: exit codes follow `sweep-followthroughs.sh` (0 PASS, 1 FAIL = dark again / GHCR-served, 2 NOT YET, 3 CANNOT ESTABLISH = `TRANSIENT:`), not the plan's 0/1/2 — the plan's "1 = not yet" would post a FAIL comment on every sweep. No time lower bound is needed: only the fixed template emits a host-tagged `app_zot` with a `zot_login=` detail.
- Parity (1.2.5): `login=` is not in `cloud-init-inngest.yml`'s code, so the shared-wording assertion is over `zot=[`, `ghcr=[`, `not-attempted`.

## Phase 4: Delivery (post-merge)

- [ ] 4.0 At ship: add the follow-through directive + `follow-through` label to #8651.
- [ ] 4.1 Dispatch `web-host-replace` of web-2 (`confirm=REPLACE-web-2`, no `image_tag` override), arm a watch, route the environment approval; on a failed apply follow the job's printed recovery.
- [ ] 4.2 Read the boot trail: image-origin `app_zot` with `zot_login=ok` (record `ghcr_login`, `nic`), verdict `fresh_boot_ready`, no seed fatal, no `app_ghcr_*`; inconclusive → re-run `--image-origin`; dark → new PR, never an unchanged re-dispatch.
- [ ] 4.3 Close #8651 as completed with run URL + event ids (or let the sweeper close it); close or comment #6985; `Ref` comments on #6500, #6122, #6438. web-2 stays out of service.
