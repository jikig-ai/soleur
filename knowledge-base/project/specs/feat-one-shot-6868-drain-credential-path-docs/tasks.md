# Tasks — Drain grandfathered resolvable-credential-path docs (#6868)

Plan: `knowledge-base/project/plans/2026-07-23-chore-drain-grandfathered-credential-path-docs-plan.md`

Guard-safe forms only in this file (`~/.ssh/id_<key>`, `~/.doppler/`, `~/.docker/`,
descriptive names) — this file is itself in the linter's scan scope.

## Phase 1 — Baseline capture

- [x] 1.1 Run `python3 scripts/lint-credential-path-literals.py` → 30 hard-fail / 12 files (SSOT).
- [x] 1.2 Note advisory baseline (15 lines) — `/home/<user>/` + `/root/` remote-host, out of scope.

## Phase 2 — Neutralize per credential family (12 files)

- [x] 2.1 SSH private keys → `~/.ssh/id_<key>` placeholder (keeps command shape):
  - [x] `learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` (2)
  - [x] `plans/2026-03-21-infra-scheduled-terraform-drift-detection-plan.md` (3)
  - [x] `plans/2026-04-03-fix-web-platform-infra-drift-doppler-install-plan.md` (3)
  - [x] `plans/2026-04-14-fix-one-shot-verify-deploy-and-apply-tf-plan.md` (1)
  - [x] `plans/2026-05-20-fix-ci-host-ssh-auth-deploy-pipeline-fix-plan.md` (4)
- [x] 2.2 Docker config → `~/.docker/` / `$HOME/.docker/` directory form:
  - [x] `plans/2026-07-04-fix-cosign-verify-private-ghcr-auth-offline-plan.md` (2)
  - [x] `plans/2026-07-17-fix-web-platform-docker-login-erofs-cred-path-plan.md` (3)
  - [x] `learnings/integration-issues/2026-07-05-plan-live-confirmed-anonymous-registry-pull-is-a-cached-creds-false-confirm.md` (1)
- [x] 2.3 Doppler home credential → `~/.doppler/` directory form:
  - [x] `plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md` (2)
- [x] 2.4 Doppler repo-root project-pointer → descriptive "the Doppler project-pointer file" (never a bare pointer literal):
  - [x] `plans/2026-03-20-feat-adopt-doppler-secrets-manager-plan.md` (6)
  - [x] `specs/feat-secrets-manager/tasks.md` (1)
- [x] 2.5 netrc deny-rule → `Read(~/.netr*)` glob (still denies the file, breaks the resolvable literal):
  - [x] `plans/2026-06-08-fix-cron-sandbox-dontask-allowlist-tiered-plan.md` (2)

## Phase 3 — Verify to zero

- [x] 3.1 AC1 full-scan exit 0 / "OK".
- [x] 3.2 AC2 `--changed --base origin/main` exit 0 (CI gate).
- [x] 3.3 AC3 no advisory token edited (diff proof); advisory count rose 15 → 18 lines
      because 3 co-located hard+advisory lines (erofs plan 15/40/63) unmasked their advisory
      when the hard-fail was drained — expected, not a regression.
- [x] 3.4 AC4 plan + this tasks.md self-clean.
- [x] 3.5 AC5 `lint-credential-path-literals.test.sh` green.
- [x] 3.6 AC7 diff limited to the 12 docs + plan + tasks.md.

## Phase 4 — Promotion decision (record + defer)

- [ ] 4.1 File follow-up issue for the `lint-bot-statuses` required-check promotion (deferred).
- [ ] 4.2 Reference the follow-up number in the PR body; `Closes #6868`.
