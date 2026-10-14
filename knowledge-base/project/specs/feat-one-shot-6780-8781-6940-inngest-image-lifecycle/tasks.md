# Tasks: inngest-bootstrap image lifecycle — ADR-135 consumer bake, candidate build lane, cutover follow-ups

Plan: `knowledge-base/project/plans/2026-10-13-fix-6780-8781-6940-inngest-image-lifecycle-plan.md`
Branch: feat-one-shot-6780-8781-6940-inngest-image-lifecycle. `Ref #6780` `Ref #6940` `Closes #8781` (the Closes is contingent on decision D6 — option (a) build-only lane satisfying the ask).
No task in this file dispatches a workflow, runs terraform apply, writes Doppler, reboots, or touches a host.
Do NOT merge or rebase onto PARKED PR #10081 (textual overlap in `cloud-init-inngest.yml`). Do NOT touch `cloud-init-git-data.yml`/`git-data-bootstrap.sh` (sibling scope). Expect a small `vector.toml`/`journald-config.test.sh` conflict with PR #10255.
TEST-AUTHORING RULE (detector): no bare `<<`/`<<<` token outside a real heredoc in any `.test.sh` (assemble via a var); tail floors sit outside heredoc-blanked spans and self-exit with printf sentinel + `exit 1`; arm-level `if` lines carry none of the words `pass`/`fail`/`executed`/`cases` beside `-lt`/`-le`/`-ge`.

## Phase 0: RED tests first

- [ ] 0.1 `inngest-config-refresh.test.sh` (new): extract the baked script + both units from `cloud-init-inngest.yml` (the LUKS-suite heredoc convention); structural pins — service is `Type=oneshot` root with `Environment=HOME=/root`, `TimeoutStartSec`, `NoNewPrivileges=yes`, `ProtectSystem=strict`, `PrivateTmp=true`, `SyslogIdentifier=inngest-config-refresh`, `ConditionPathExists=/etc/default/inngest-server` on BOTH unit and timer, `StateDirectory=inngest-config`, `EnvironmentFile=/etc/default/inngest-server`, `doppler run --config ${DOPPLER_CONFIG} --only-secrets INNGEST_CONFIG_DIGEST --no-exit-on-missing-only-secrets`, `enable --now inngest-config-refresh.timer` runcmd line — expect RED
- [ ] 0.2 `inngest-config-refresh.test.sh`: HARD-1 pins — engine paths (`inngest-config-refresh`, `infra-config-install`, `cosign-trusted-root`, `applied.version`, the units) absent from `inngest-config-refresh-set.txt`, `DEST_SPEC`, and `FILE_MAP`; refresh-set lists exactly the 5 dedicated carriers — expect RED
- [ ] 0.3 `inngest-config-refresh.test.sh`: fixture arms under `--fixture-seams` — empty pointer → throttled noop exit 0; pointer==applied → noop, zero docker calls; happy path → APPLIED + `applied.version` + `applied.json`; `verify-blob` rc≠0 → VERIFY_FAIL reason=signature, nothing installed; VERSION ≤ applied → VERIFY_FAIL reason=rollback-or-replay; manifest sha mismatch → VERIFY_FAIL; missing/non-integer `applied.version` → floor + `SOLEUR_INFRA_PULL_FLOOR`; mid-set install failure → version NOT advanced — expect RED
- [ ] 0.4 `cloud-init-inngest-bootstrap.test.sh`: AC6c — all `jikig-ai/soleur-inngest-bootstrap:vX.Y.Z@sha256:<64hex>` refs across `cloud-init.yml` + `cloud-init-inngest.yml` count==4 and distinct==1 (new green-guard; verify it passes on main before the bake lands)
- [ ] 0.5 `cloud-init-inngest-bootstrap.test.sh` / `inngest-host.test.sh`: write_files payload pins — the refresh script, `infra-config-install` b64 entry, `cosign-trusted-root.json` b64 entry, `applied.version` (0644 root:root content `0`) — expect RED
- [ ] 0.6 `cutover-inngest-workflow.test.sh`: `CUTOVER_*` completeness guard — anchored `grep -oP '(?<![A-Za-z0-9_])CUTOVER_[A-Z_]+'` derivation over `scripts/cutover-inngest.sh`; each name env-mapped or in `DEFERRED_CUTOVER_VARS` (issue ref + reason required); `$WF_YAML`/`$BODY_SH` env-overridable; mapping pins for `CUTOVER_QUIESCE_PROBES` + `CUTOVER_PAGE_SIZE`; `page_size` input + pass-environment pins — expect RED on the new rows
- [ ] 0.7 `inngest-doublefire-probe.test.sh`: `INNGEST_GQL_PAGE_SIZE` validation arms — non-integer / 0 / >1000 → fail-closed FATAL; valid → `--argjson first` carries it — expect RED
- [ ] 0.8 `.github/scripts/test/test-check-inngest-bootstrap-build.sh` (new): normalized parity (cp set, Dockerfile COPY/ENV/ENTRYPOINT, sha-verify block) between the check script and the inline Build step; forbidden-token scan (no `docker push`/`cosign`/`crane`/`id-token`/`packages:`/`environment:`); paths-filter coverage of every `cp` source — expect RED
- [ ] 0.9 `journald-config.test.sh`: two-sided pins for `inngest-config-refresh` (unit `SyslogIdentifier=` ↔ Source-4 include) — expect RED

## Phase 1: Workstream A — host-side consumer bake (#6780)

- [x] 1.1 `cloud-init-inngest.yml` write_files: `inngest-config-refresh.sh` payload (`/usr/local/bin/inngest-config-refresh.sh`, 0755 root:root) — pointer resolve → digest compare → zot pull @sha256 via `/etc/default/soleur-zot-read` → docker create/cp extract → `docker run` pinned cosign image `verify-blob` (baked trusted root + build-inngest-config-bundle identity regexp + OIDC issuer) → VERSION only from verified manifest → monotonic gate → `sha256sum -c` → stage-all → install-all via `infra-config-install` → advance `applied.version` + write `applied.json` → phone-home + `logger -t` emits. Escaping: bare `$` everywhere, `$${` only where a brace follows; `#` rationale lines only (the strip removes them pre-gzip)
- [x] 1.2 `cloud-init-inngest.yml` write_files: `infra-config-install` b64 payload (`/usr/local/bin/infra-config-install`, 0755), `cosign-trusted-root.json` b64 (`/etc/soleur/cosign-trusted-root.json`, 0644), `applied.version` (`/var/lib/inngest-config/applied.version`, 0644 root:root, `0`)
- [x] 1.3 `cloud-init-inngest.yml` write_files: `inngest-config-refresh.service` + `.timer` per the plan's unit shape; runcmd `systemctl enable --now inngest-config-refresh.timer` beside the sibling enable lines
- [x] 1.4 `inngest-host.tf` + `inngest-provision-rehearsal/rehearsal.tf`: add `infra_config_install_b64` and `cosign_trusted_root_b64` templatefile vars (identical `base64encode(file(...))` sources in both roots)
- [x] 1.5 `infra-config-install.sh` `DEST_SPEC` +5 (`/usr/local/bin/{inngest-redis-bootstrap,inngest-cutover-flip,inngest-server-flip-guard,cat-inngest-cutover-state,inngest-luks-cutover}.sh` = `755 root:root`); `infra-config-apply.sh` `FILE_MAP` +5 rows; `push-infra-config.sh` payload +5 b64 fields; `infra-config-verify.sh`/`cat-infra-config-state.sh`/`infra-config-gate.sh` count + lockstep moves
- [x] 1.6 `inngest-config-refresh-set.txt`: membership → the 5 dedicated carriers + a comment recording why the web-host seed-8 moved out (not dedicated dests; their real channel is the webhook push)
- [x] 1.7 `vector.toml`: `"inngest-config-refresh"` Source-4 entry + comment (goes live on next image bake; phone-home is the v1 channel)

## Phase 2: Workstream B — candidate build lane (#8781)

- [x] 2.1 `.github/workflows/check-inngest-bootstrap-build.yml`: `pull_request` paths filter (mirroring mint's carrier globs + self + script + test), `permissions: contents: read`, one job running the script
- [x] 2.2 `.github/scripts/check-inngest-bootstrap-build.sh`: pin-read (same `*.tf` greps) → cli tarball sha256-verify → stage 14 carriers → Dockerfile heredoc → `docker build` with revision label; NO push/sign/mirror/bump
- [x] 2.3 `infra-validation.yml`: path-map comment entries for the new files (candidate lane + refresh suite)

## Phase 3: Workstream C — #6940 follow-ups

- [x] 3.1 `cutover-inngest.yml`: `CUTOVER_QUIESCE_PROBES: ${{ vars.CUTOVER_QUIESCE_PROBES }}` env line; `page_size` input (optional string); `CUTOVER_PAGE_SIZE: ${{ inputs.page_size }}`; update the `#6940` comment block (item 1 landed #9698; item 2 guard exists with BASELINE deferred pending AC-V4; item 3 param plumbed)
- [x] 3.2 `scripts/cutover-inngest.sh`: `&page_size=` appended to BOTH doublefire URL sites when `CUTOVER_PAGE_SIZE` is a valid integer 1–1000 (invalid → `::error::` + skip the param, never a malformed URL)
- [x] 3.3 `hooks.json.tmpl`: `{ "source": "url", "name": "page_size", "envname": "INNGEST_GQL_PAGE_SIZE" }` in the doublefire hook's `pass-environment-to-command`
- [x] 3.4 `inngest-doublefire-probe.sh`: `PAGE_SIZE` integer/range validation (1–1000, fail-closed) before `--argjson first`

## Phase 4: Suites green + floors

- [x] 4.1 `bash apps/web-platform/infra/inngest-config-refresh.test.sh` GREEN; floor = MEASURED
- [x] 4.2 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, `inngest-host.test.sh`, `inngest.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `journald-config.test.sh`, `infra-config-install.test.sh`, `infra-config-apply.test.sh`, `infra-config-verify.test.sh`, `ci-deploy.test.sh`, `inngest-config-bundle-pack.test.sh`, `cutover-inngest-workflow.test.sh`, `inngest-doublefire-probe.test.sh` all GREEN at measured floors
- [x] 4.3 `bash .github/scripts/test/test-check-inngest-bootstrap-build.sh` GREEN
- [x] 4.4 `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` — stored <= 32,768; record post-change headroom (pre: 21,520 / 11,248)

## Phase 5: Docs

- [x] 5.1 ADR-135 dated amendment: zot-direct pull (GHCR cred deleted by #8036); marker-channel v1 = phone-home + journald tag post-bake; refresh-set v1 = 5 dedicated carriers, scripts-only
- [x] 5.2 `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md`: channel-live precondition stays; first-promotion window (dispatch → TF_VAR → targeted apply → floor 5→6 → off-box confirm); note the zot pull path
- [x] 5.3 `knowledge-base/engineering/operations/runbooks/inngest-server.md` §Bootstrap-image release: cross-ref the refresh channel for `*.sh` changes (an image bake is no longer required for refresh-set members once the channel is live)
- [x] 5.4 `bash plugins/soleur/test/c4-count-parity.test.sh` green (no C4 edit expected)

## Phase 6: Handoff (no dispatch)

- [ ] 6.1 Full local suite list from the plan's Acceptance Criteria; `git diff --name-only origin/main...HEAD` contains neither sibling file
- [ ] 6.2 PR body: first line answers "does merging this mutate production?" (`no — user_data ForceNew; inert until the next sanctioned inngest-host-replace + a promoted pointer`); `Ref #6780` `Ref #6940` `Closes #8781`; lists unrun operator-gated steps (host replace, first promotion, drift-executor wiring, AC-V4-gated baseline mapping, page_size measurement dispatch)
