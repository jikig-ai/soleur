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
- [ ] 1.2 Add `refetch_ghcr_and_relogin()`: re-fetch prd GHCR cred (hardened
  timeout45/3-try); `docker login --password-stdin` into `$GHCR_DOCKER_CONFIG`;
  token `local` + unset; on success `export GHCR_READ_USER`; **echo a staged
  result** (`recovered|refetch_unavailable|relogin_failed`) and **return the
  login status** (NOT §1A's `dt=""`-fallthrough return-0 — P1-B/AC14). Guard on
  doppler + `DOPPLER_TOKEN`.
- [ ] 1.3 Replace §1A inline body (`ci-deploy.sh:669-679`) with a call to the
  helper — §1A observable behavior preserved. (GREEN 1.1.)

## Phase 2 — Pull-site recovery (`_ghcr_pull_or_recover`)

- [ ] 2.1 (RED) `ci-deploy.test.sh`: mock `docker login` ok + first GHCR pull
  `denied` + second pull ok ⇒ returns 0, exactly one re-login + one pull retry
  (AC1). Fails on `main`.
- [ ] 2.2 (RED) mock: login-ok/relogin-ok/retry-pull still denies ⇒ returns 1,
  `image_pull_failed`, one `pull_failure_event` tagged `recovery_stage=pull_still_denied`
  (AC2). Also: relogin fails ⇒ retry pull NOT attempted (AC14).
- [ ] 2.3 Extract `_pull_result_is_auth_denied` from `pull_failure_event`'s
  classifier (`ci-deploy.sh:525`) — ONE regex, classifies stderr **content**
  (predicate receives `tail -c 400 "$perr"`, not the path — AC3).
- [ ] 2.4 Add `_ghcr_pull_or_recover` and call it at BOTH GHCR pull sites
  (`:765`, `:775`); do NOT wrap the zot leg (`:755`) (AC4). `rm -f "$perr"` on
  every return (P2-H). (GREEN 2.1/2.2.)

## Phase 3 — Discriminating recovery telemetry

- [ ] 3.1 (RED) Sentry-store mock-trace: recovered-success emits ONE
  `pull_auth_recovery_event` (`op:image-pull-recovery`, host_id, info); auth miss
  emits NO second event — `pull_failure_event` carries `recovery_stage` tag
  (AC5).
- [ ] 3.2 Add `pull_auth_recovery_event` (mirror `pull_failure_event` transport;
  `jq -n --arg`; no raw stderr) + add optional `recovery_stage` arg to
  `pull_failure_event` surfaced as a tag. (GREEN 3.1.)
- [ ] 3.3 (RED/GREEN) AC13: recovered pull's login writes `$GHCR_DOCKER_CONFIG`;
  cosign `:ro` verify leg authenticates.

## Phase 4 — DEFERRED (cloud-init boot-path parity → follow-up issue)

- [ ] 4.1 File a follow-up issue: "boot-path GHCR seed-pull denial parity
  mirroring ci-deploy.sh #6400" (recreate-only; may be mooted by zot/ADR-096).
  NOT in this PR (simplicity review Rec1).

## Phase 5 — Config reconciliation + register/doc hygiene

- [ ] 5.1 Verify (read-only API) `prd_terraform.GHCR_READ_TOKEN` is the same
  pull-capable `read:packages` PAT as `prd.GHCR_READ_TOKEN`; file a follow-up if
  it diverges.
- [ ] 5.2 Correct the stale App-minted claim in
  `knowledge-base/project/learnings/2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md`
  (~line 71).
- [ ] 5.3 ADR-096: add the normative login≠pull-capability recovery contract for
  the interim GHCR path; ADR-088: factual note only (P2-C). Verify no C4 change
  (enumeration cited in plan).
- [ ] 5.4 Update `knowledge-base/engineering/architecture/principles-register.md`
  AP-016: minter can't pull GHCR; forward is ADR-096/zot (P2-D).

## Phase 6 — Follow-through + verify

- [ ] 6.1 Add `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` (Sentry
  auth_denied count == 0 since `start=` post-deploy; mirror
  `reconcile-ff-only-sentry-4977.sh`).
- [ ] 6.2 Add the `<!-- soleur:followthrough … -->` directive + `follow-through`
  label to #6400; wire any new `secrets=` into
  `.github/workflows/scheduled-followthrough-sweeper.yml`.
- [ ] 6.3 `bash -n` ci-deploy.sh; run `ci-deploy.test.sh` and
  `ship-deploy-pipeline-fix-gate.test.ts` (AC7/AC9). Confirm the exact runners via
  `package.json`/repo convention at /work.

## Notes

- PR body uses `Ref #6400` (not `Closes`) — closure is soak-gated post-deploy.
- Merge auto-fires `apply-deploy-pipeline-fix.yml` (delivers ci-deploy.sh, no
  SSH); the next `web-platform-release` deploy self-recovers.
