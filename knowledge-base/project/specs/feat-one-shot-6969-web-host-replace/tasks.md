# Tasks — feat-one-shot-6969-web-host-replace

Derived from `knowledge-base/project/plans/2026-07-26-feat-web-host-replace-dispatch-target-plan.md`.
Lane: `cross-domain`. Brand-survival threshold: `single-user incident`.

## Phase 0 — Preconditions (verify; do not assume)

- [x] 0.1 Read `tests/scripts/lib/git-data-host-replace-gate.sh` in full — it is the template.
- [x] 0.2 Confirm `for_each` keying of `hcloud_volume.workspaces` (`server.tf:1627`) and
      `hcloud_volume.workspaces_luks` (`workspaces-luks.tf:207`); record which web-2 carries.
- [x] 0.3 Determine whether web-host LUKS passphrase resources exist (`random_password.*`,
      `doppler_secret.*_key`). If yes → `luks_passphrase_touched` arm is required.
- [x] 0.4 Read `apps/web-platform/infra/web-probe.tf` — do the 4 probe resources reference the
      server id? They belong in the `-target` set only if a replace must change them.
- [x] 0.5 Determine `cloudflare_record.app` behavior for a non-web-1 key (expect no-op) and for
      web-1 (expect content change). Gate must handle both without a weakening special case.
- [x] 0.6 Re-read `web-host-birth-environment.tf` ADOPTION note before touching that file at all.

## Phase 1 — Gate library (TDD — test FIRST)

- [x] 1.1 Write `tests/scripts/test-web-host-replace-gate.sh` with one fixture per arm (RED).
- [x] 1.2 Write `tests/scripts/lib/web-host-replace-gate.sh` (GREEN).
- [x] 1.3 Define the allow-set ONCE as `_WEB_HOST_REPLACE_ALLOW='def allow($k): [...]'`.
- [x] 1.4 Arms: `server_replaced==1`; identity match; `workspaces_volume_destroyed==0`;
      `luks_volume_destroyed==0`; `luks_passphrase_touched==0` (if applicable);
      `nic_recreated>=1`; `volume_attachment_recreated>=1`; `reboot_updates==0`; `out_of_scope==0`.
- [x] 1.5 Fail-closed: missing file, unparseable JSON, absent `resource_changes` array, non-array
      `.change.actions` (copy the birth gate's explicit null-guard — it is mutation-proven).
- [x] 1.6 Use exact-equality `IN(...)` membership, never `contains`/`inside`.
- [x] 1.7 No `[ack-destroy]` bypass on this path.
- [x] 1.8 Mutation check: delete each arm in turn; each deletion must turn a test red.

## Phase 2 — Workflow job

- [x] 2.1 Add `web_host_replace` job to `.github/workflows/apply-web-platform-infra.yml`.
- [x] 2.2 `environment: web-platform-infra-apply` (reuse; do NOT re-declare in Terraform).
- [x] 2.3 `concurrency: {group: web-1-swap, cancel-in-progress: false}` + keep the shared
      workflow-level R2 serializer literal byte-identical.
- [x] 2.4 Reuse `web_host_key` / `image_tag` / `reason`; add `confirm=REPLACE-<key>` semantics.
      Do NOT add new inputs (dispatch cap is 10; 5 used).
- [x] 2.5 Add `web-host-replace` to the `apply_target` enum `options:` and `description:`.
- [x] 2.6 Source `stock-preflight-gate.sh`; update its header sourcing list.
- [x] 2.7 Digest-pin resolve + coherence preflight, mirroring the birth path.
- [x] 2.8 Route `web_host_key` exclusively through `env:` — never `${{ }}` inside a `run:` body.

## Phase 3 — Guard-suite sweep (orphan-suite class)

- [x] 3.1 `plugins/soleur/test/terraform-target-parity.test.ts` — add `web_host_replace` to
      `stripDispatchJobs`; consider a `WEB_REPLACE_TARGETS` pin mirroring `REGISTRY_REPLACE_TARGETS`.
- [x] 3.2 `scripts/test-all.sh` — add
      `run_suite "tests/scripts/web-host-replace-gate" bash tests/scripts/test-web-host-replace-gate.sh`.
- [x] 3.3 `tests/scripts/test-stock-preflight-gate.sh` — extend if it pins the sourcing list.
- [x] 3.4 `.github/workflows/infra-validation.yml` — register the new suite if required.
- [x] 3.5 Verify the per-PR `host_creates` HALT is byte-unchanged.

## Phase 4 — Docs + ADR

- [x] 4.1 New ADR (ordinal provisional; re-verify at ship): web-host replacement is a distinct
      gated dispatch, not a widened birth. Include Alternatives Considered (a)/(b)/(c).
- [x] 4.2 C4: enumerate external actors / systems / access relationships against all three `.c4`
      files; a "no C4 impact" conclusion must cite what was checked.
- [x] 4.3 New runbook `knowledge-base/engineering/operations/runbooks/web-host-replace.md`;
      cross-link with `web-host-birth.md`.

## Phase 5 — Verification

- [x] 5.1 `bash tests/scripts/test-web-host-replace-gate.sh`
- [x] 5.2 `bun test plugins/soleur/test/terraform-target-parity.test.ts`
- [x] 5.3 `bash apps/web-platform/infra/run-registered-suites.sh` (authoritative for infra)
- [x] 5.4 `bash scripts/test-all.sh`
- [x] 5.5 `bash scripts/check-adr-ordinals.sh`
- [x] 5.6 `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra`

## Phase 6 — Ship (PR body uses `Ref #6969`, never a closing keyword)

- [ ] 6.1 `/soleur:review` → `/soleur:compound` → `/soleur:ship`.

## Phase 7 — Execute the rebirth (in scope)

- [ ] 7.1 Dispatch:
      `gh workflow run apply-web-platform-infra.yml -f apply_target=web-host-replace
      -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f image_tag=web-v0.239.0
      -f reason='dark-host rebirth onto the boot-stage error channel'`
- [ ] 7.2 Confirm the run QUEUES on the reviewer gate (evidence: run URL in `waiting`).
- [ ] 7.3 After approval, poll the run; read the boot trail.
- [ ] 7.4 Update the post-mortem with the outcome.
- [ ] 7.5 Close #6969 ONLY after 7.3/7.4, with live evidence in the closing comment.
