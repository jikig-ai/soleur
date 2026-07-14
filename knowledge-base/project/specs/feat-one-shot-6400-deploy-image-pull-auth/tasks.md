---
feature: feat-one-shot-6400-deploy-image-pull-auth
issue: 6400
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-14-fix-deploy-ghcr-pull-denial-recovery-plan.md
---

# Tasks — fix(infra): deploy GHCR `image_pull_failed` recover on pull-denial (§1A gap)

Derived from the finalized plan. Implement in order (contract-changing phases
before consumers). Fail-open is a contract, not a nicety — assert it.

## Phase 0 — Diagnosis-first (no code; no SSH)

- [ ] 0.1 Sentry API: count/group `op:image-pull` events by `host_id` +
  `pull_result` since the incident window. Record which hosts + `auth_denied`.
- [ ] 0.2 Better Stack Vector logs (`betterstack-query.sh`, source 2457081): pull
  `ci-deploy` `PRELUDE:` lines for the failing host+window. Determine branch:
  login-ok→pull-deny (Scenario 1/2) vs login-fail→refetch-still-failed.
- [ ] 0.3 `curl -s https://app.soleur.ai/health | jq .version` — current prod
  build; note whether the acute outage self-resolved. Ship the structural fix
  regardless.
- [ ] 0.4 Record findings in `phase0-evidence.md` under this spec dir.

## Phase 1 — Shared re-fetch/relogin helper (`ci-deploy.sh`)

- [ ] 1.1 (RED) Add `ci-deploy.test.sh` case: baked `docker login` FAILS →
  §1A recovers via the new helper (regression parity with existing §1A test).
- [ ] 1.2 Extract `refetch_ghcr_and_relogin()` (re-fetch prd GHCR cred, hardened
  timeout45/3-try; `docker login --password-stdin`; re-export `GHCR_READ_USER`;
  unset token). Guard on doppler + `DOPPLER_TOKEN`.
- [ ] 1.3 Replace §1A inline body (`ci-deploy.sh:669-679`) with a call to the
  helper — byte-identical behavior. (GREEN 1.1.)

## Phase 2 — Pull-site recovery (`pull_image_with_fallback`)

- [ ] 2.1 (RED) `ci-deploy.test.sh`: mock `docker login` ok + first GHCR pull
  `denied` + second pull ok ⇒ `pull_image_with_fallback web` returns 0, exactly
  one re-login + one pull retry (AC1). Fails on `main`.
- [ ] 2.2 (RED) mock: both pulls deny ⇒ returns 1, `image_pull_failed` terminal
  state unchanged (AC2, fail-open).
- [ ] 2.3 Extract `_pull_result_is_auth_denied` predicate from
  `pull_failure_event`'s classifier (`ci-deploy.sh:525`) — one regex (AC3).
- [ ] 2.4 In both GHCR pull branches (`:765`, `:775`): on `auth_denied`, call
  `refetch_ghcr_and_relogin` + retry the pull once before
  `pull_failure_event`+return 1. Do NOT touch the zot pull leg (AC4). (GREEN
  2.1/2.2.)

## Phase 3 — Discriminating recovery telemetry

- [ ] 3.1 (RED) Sentry-store mock-trace assert: `pull_auth_recovery_event` fires
  with `host_id` + `outcome` tag only when recovery is attempted (AC5).
- [ ] 3.2 Add `pull_auth_recovery_event` (mirror `pull_failure_event` transport;
  `op:image-pull-recovery`; `level` info/warning by outcome). (GREEN 3.1.)

## Phase 4 — Boot-path parity (`cloud-init.yml`) — secondary

- [ ] 4.1 (RED) `cloud-init-ghcr-seed-login.test.sh`: seed login-ok / seed-pull
  deny → retry-after-relogin.
- [ ] 4.2 Mirror the pull-denial tolerance in the seed `ghcr_login` block
  (`cloud-init.yml:471-498`). Note in-PR: lands only on host recreate.

## Phase 5 — Config reconciliation + docs

- [ ] 5.1 Verify (read-only API) `prd_terraform.GHCR_READ_TOKEN` is the same
  pull-capable PAT as `prd.GHCR_READ_TOKEN`; file a follow-up if it diverges.
- [ ] 5.2 Correct the stale App-minted claim in
  `knowledge-base/project/learnings/2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md`
  (~line 71).
- [ ] 5.3 Amend ADR-088 staleness section with the login≠pull-capability
  recovery contract (see plan ADR/C4). Verify no C4 change needed (enumeration
  cited in plan).

## Phase 6 — Follow-through + verify

- [ ] 6.1 Add `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` (Sentry
  auth_denied count == 0 since `start=` post-deploy; mirror
  `reconcile-ff-only-sentry-4977.sh`).
- [ ] 6.2 Add the `<!-- soleur:followthrough … -->` directive + `follow-through`
  label to #6400; wire any new `secrets=` into
  `.github/workflows/scheduled-followthrough-sweeper.yml`.
- [ ] 6.3 `bash -n` ci-deploy.sh; run `ci-deploy.test.sh`,
  `cloud-init-ghcr-seed-login.test.sh`, `ship-deploy-pipeline-fix-gate.test.ts`
  (AC7/AC9). Confirm the exact runners via `package.json`/repo convention at /work.

## Notes

- PR body uses `Ref #6400` (not `Closes`) — closure is soak-gated post-deploy.
- Merge auto-fires `apply-deploy-pipeline-fix.yml` (delivers ci-deploy.sh, no
  SSH); the next `web-platform-release` deploy self-recovers.
