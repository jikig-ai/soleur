# Tasks — feat-one-shot-10045-kdeny-least-priv

Plan: `knowledge-base/project/plans/2026-10-11-chore-kdeny-kernel-stream-read-grant-plan.md`
Issue: #10045 · Lane: cross-domain (fail-closed default — no spec.md existed)

## Phase 1 — Grant definition + delivery plumbing

- [ ] 1.1 `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`: append
      `Cmnd_Alias KDENY_KERNEL_STREAM = /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat`
      + `deploy ALL=(root) NOPASSWD: KDENY_KERNEL_STREAM` with a #10045 rationale comment. Write
      `--since=-5min` UNESCAPED, matching the in-file `--unit=`/`--on-active=` precedent
      (plan Technical Considerations); escaped `--since\=-5min` is the documented fallback if
      sudo-rs ever rejects the unescaped form.
- [ ] 1.2 `apps/web-platform/infra/cloud-init.yml`: mirror the same content lines (compressed
      comment per byte budget) into the `/etc/sudoers.d/deploy-inngest-bootstrap` write_files
      block — comment-stripped parity with the source (AC5).
- [ ] 1.3 `apps/web-platform/infra/server.tf` `terraform_data.infra_config_handler_bootstrap`
      remote-exec: add `grep -q KDENY_KERNEL_STREAM /etc/sudoers.d/deploy-inngest-bootstrap` and
      `runuser -u deploy -- sudo -n /usr/bin/journalctl -k -n 400 --since=-5min --no-pager -o cat >/dev/null || { echo 'FATAL: …' >&2; exit 1; }`.
- [ ] 1.4 `apps/web-platform/infra/server.tf` `terraform_data.deploy_pipeline_fix_web2`
      remote-exec: same two lines; bump sentinel `dpf-web2-remote-exec-v2` → `-v3`.

## Phase 2 — Reader change (ci-deploy.sh)

- [ ] 2.1 `_canary_kdeny_read` journal rung: `timeout -k 1 3 sudo -n /usr/bin/journalctl -k -n 400
      --since=-5min --no-pager -o cat` first; on sudo denial (rc≠0 + `sudo:`-prefixed line in
      captured output + zero kernel lines) fall back to the existing unprivileged read. Verify the
      sudo-rs denial text on a web host before pinning fixture strings (plan Phase-2 note).
- [ ] 2.2 Update the function header comment (grant + fallback contract); re-scope the
      `SOLEUR-DEBT` note — grant landed via #10045; row stays while #9860 soaks.

## Phase 3 — Tests

- [ ] 3.1 `ci-deploy.test.sh`: `sudo` PATH-mock asserting argv `-n /usr/bin/journalctl -k -n 400
      --since=-5min --no-pager -o cat` then exec'ing the journalctl mock; `MOCK_SUDO_DENY=1` emits
      the denial on **stderr** rc 1. Fixtures: grant+journal answers; grant+silent-empty;
      denied→`noaccess` fallback; accepted-sudo+root-journalctl-failure → `error` (no re-fallback);
      dmesg rung unchanged.
- [ ] 3.2 `cloud-init-inngest-bootstrap.test.sh`: extend AC5 with the kdeny argv-lockstep assert —
      argv extracted from `ci-deploy.sh` == `Cmnd_Alias` body in source AND inline copies.
- [ ] 3.3 `infra-config-handler-bootstrap.test.sh`: asserts pinning the new `grep -q` + `runuser`
      probe lines in the web-1 remote-exec.

## Phase 4 — Docs, ADR note

- [ ] 4.1 `canary-probe-set.md` §kdeny: `j=ok`/`src=journal` expected post-rollout; fallback
      contract; sudo `COMMAND=` audit record; "grant did not land → re-run the bridge probe".
- [ ] 4.2 ADR-075 "Deferred" paragraph → #10045 resolved (one-line update; no Decision change).

## Verification

- [ ] V.1 `visudo -cf apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` exits 0.
- [ ] V.2 `bash apps/web-platform/infra/ci-deploy.test.sh` — kdeny battery green.
- [ ] V.3 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — parity + lockstep.
- [ ] V.4 `bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` — verify asserts.
- [ ] V.5 `terraform -chdir=apps/web-platform/infra validate` clean.
- [ ] V.6 Post-merge: `apply-deploy-pipeline-fix.yml` green incl. the execute probe on web-1+web-2.

## Out of scope

- #9860 stays open, untouched (soak-tracking).
- `systemd-journal` group, `dmesg` grant, helper script, journal ACL — rejected alternatives.
- No kdeny-row demotion/removal; the `SOLEUR-DEBT` comment is re-scoped in place.
