# Tasks — feat-one-shot-10390-verify-blob-reject

Derived from `knowledge-base/project/plans/2026-10-22-fix-inngest-config-refresh-verify-blob-reject-plan.md`.
TDD order: failing rows land before the fix rows they pin.

## Phase 0 — Diagnostic reproduction (no SSH)

- [x] 0.1 Create `.github/workflows/diagnose-inngest-verify.yml` (`workflow_dispatch`, `packages: read`,
      digest input defaulting to `4e17987c…`): pull bundle, `docker cp` tarball, `tar -tzf` +
      `jq` the `.sigstore.json`, run the verbatim host `verify-blob` with stderr visible, plus the
      0700-stage-dir and `--network host` A/B arms. (AC1)
- [~] 0.2 Dispatch it (post-merge — new workflows are only dispatchable on the default branch); record the measured stderr into the plan/PIR and select the Phase-1 branch. (AC2)

## Phase 1 — Root-cause fix (branch on Phase-0 stderr)

- [ ] 1.1 Apply the branch the measured stderr selects (producer bundle fix / verify invocation /
      host mount-perms / trusted-root render). Never a verification-weakening flag. (AC2, AC10)

## Phase 2 — Stderr capture + `detail=` (lands under every branch)

- [x] 2.1 `cloud-init-inngest.yml` `inngest-config-refresh.sh`: capture verify stderr to
      `$STATE_DIR/verify.stderr` (≤4 KiB, 0600); classify into `detail=` token. (AC3)
- [x] 2.2 `.github/workflows/inngest-config-drift.yml`: add `detail` to `_summ_row` field regex. (AC5)

## Phase 3 — Tests (failing rows first)

- [x] 3.1 `inngest-config-refresh.test.sh`: S-rows (stderr capture present, `detail=` emitted,
      token allowlist) + F-rows (stubbed stderr → classified token; bounded file). (AC4)
- [ ] 3.2 Producer-side test rows if Phase 1 selects a producer fix. (AC4)
- [ ] 3.3 `inngest-host.test.sh` floor row bump — only with the Phase-4 promotion change. (AC9)

## Phase 4 — Ship via immutable redeploy + promotion/floor

- [ ] 4.1 Merge; dispatch `apply-web-platform-infra.yml -f apply_target=inngest-host-replace`. (AC6)
- [ ] 4.2 If producer-side: dispatch `build-inngest-config-bundle.yml` at version N+1, promote via
      Terraform `doppler_secret`, bump floor 5→6 in the same change. (AC9)
- [ ] 4.3 Post-replace off-box watch: zero `reason=signature` rows in the first hour. (AC6)

## Phase 5 — ADR addendum + PIR + follow-through

- [x] 5.1 ADR-135 defect-3 addendum. (AC8)
- [x] 5.2 PIR under `knowledge-base/engineering/operations/post-mortems/`; `## Follow-ups` filed. (AC8)
- [x] 5.3 `scripts/followthroughs/inngest-verify-clean-10390.sh` + tracker directive + sweeper
      `secrets=` wiring; ≥24h clean soak. (AC7)
