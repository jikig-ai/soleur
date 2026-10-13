# Tasks: unblock web-platform deploys (file-cap'd bwrap), Closes #9871, Ref #9860

Plan: `knowledge-base/project/plans/2026-10-09-fix-deploy-canary-filecap-bwrap-rollback-plan.md`

One PR, two commits: Commit A (image) unblocks alone; Commit B (host alignment) removes the posture delta and the alert noise and is revertable on its own.

## Phase 0 - Evidence and collision check (read-only, before any edit)

- 0.1 Re-check `gh pr list --search "linked:issue #9871" --state all` and open PRs touching `apps/web-platform/Dockerfile`, `ci-deploy.sh`, `sandbox-canary-soak.test.sh` (known: #9809); plan the rebase.
- 0.2 Re-run plan Phase 0.1 (tag to commit map, ancestry) and 0.2 (deploy job annotations) for the newest failed deploy.
- 0.3 Re-run the Better Stack query (Phase 0.4) for that deploy and compare `reason` / `bwrap_err` with the v0.333.1 signature.
- 0.4 If the signature differs, stop and re-plan (Phase 0.7 stop rule); do not edit the probe.

## Phase 1 - Repin the tests (RED)

- 1.1 Edit `apps/web-platform/infra/sandbox-canary-soak.test.sh` section 8: rewrite the "THREE halves" header and invert all four asserts (no `setcap` with the hardened regex, explicit emptiness-test audit, no `--cap-add`/`--privileged` on non-comment lines of `ci-deploy.sh` and `cloud-init.yml`).
  - 1.1.1 Add `check_no_filecap <dockerfile> <ci-deploy> <cloud-init>` (comment-stripped, continuation-joined, non-zero on missing or empty input).
  - 1.1.2 Add test-time-derived mutants M1-M6 and the pass stubs H1; add H2 (grep replaced by `true` must make M1 fail the suite).
- 1.2 Add the outer-wrap canary skip case to `apps/web-platform/infra/ci-deploy.test.sh` (marker logged, no `docker exec`, outer ledger absent).
- 1.3 Run both suites: expect RED on the current tree.

## Phase 2A - Image posture (Commit A)

- 2A.1 `apps/web-platform/Dockerfile`: delete the `RUN setcap ... /usr/bin/bwrap` line, rewrite its comment, keep `libcap2-bin`.
- 2A.2 Replace the `{bwrap}`-only audit with the empty-set audit RUN (explicit `[ -z "$all" ]`, after every install layer).
- 2A.3 Local negative-direction repro (plan Phase 0.5, setcap step removed): never prints `Unexpected capabilities`.

## Phase 2B - Host alignment (Commit B)

- 2B.1 `ci-deploy.sh`: remove `--cap-add SYS_ADMIN` from the canary and production `docker run`; rewrite the two arm-F comment blocks. `cloud-init.yml`: same.
- 2B.2 `run_outer_wrap_canary`: keep the `OUTER_LEDGER_ALIAS` early return, then skip behind `OUTER_WRAP_CANARY_ENABLED` (default 0) with the `OUTER_WRAP_CANARY_SKIPPED` marker via `logger`.
- 2B.3 Comment-only sweep: `sandbox-canary.mjs`, `agent-outer-wrap.ts` (plus a comment at `outerWrapEnabled`: flag must stay off), `tenant-isolation-inner-probe.sh`, soak script failure message.
- 2B.4 Run both suites: expect GREEN; `bash scripts/lint-orphan-test-suites.sh`; `plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 3 - Docs and probe script

- 3.1 ADR-075 dated addendum (supersedes three named passages; real section headings; flip the addendum status).
- 3.2 `canary-probe-set.md`: generic "Which sub-check failed" recipe (no cause grep, `SYSLOG_IDENTIFIER == "ci-deploy"` filter, redaction caution).
- 3.3 Create `scripts/verify-served-sha-filecap-free.sh` (the `discoverability_test`); check it prints nothing on the currently served sha.
- 3.4 Learning via `soleur:compound` (topic only).

## Phase 4 - Ship and verify

- 4.1 PR body: `Closes #9871`, `Ref #9860`; filtered evidence lines; note the two-commit structure.
- 4.2 Create deferral issues: (a) re-spike (Ref #9773), (b) pre-merge real-bwrap-as-uid-1001 probe, (c) report-only bwrap probe when health fails, (d) setuid/no-new-privileges hardening.
- 4.3 After merge: Monitor (20-minute budget) for deploy success, `ci-deploy.sh completed successfully` in the run log, `verify-served-sha-filecap-free.sh` output, filtered Better Stack `SANDBOX_PROBE_OK` row for the tag, deploy-status `ci_deploy_sha256` equals the repo file's.
- 4.4 Comment the fresh faithful-canary verdict on #9860; leave it open unless its own acceptance is met.
