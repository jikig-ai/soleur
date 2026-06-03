---
title: "Tasks — fix oneshot heartbeat misreport + confirm #4886 deploy recovery (#4896)"
plan: knowledge-base/project/plans/2026-06-03-fix-inngest-heartbeat-oneshot-misreport-and-confirm-deploy-recovery-plan.md
lane: cross-domain
issue: 4896
---

# Tasks

## Phase 0 — Preconditions & recovery confirmation (read-only, no prod write)

- [ ] 0.1 Confirm deploy queue recovered: `gh run list --workflow=web-platform-release.yml --limit 12 --json conclusion,createdAt,headSha`; assert first run after #4895 (`b06de5b6`) is `success` and the 3 issue SHAs (`1998af5f`/`251b80ea`/`4d1e1cb8`) are the failures.
- [ ] 0.2 Confirm prod current: `curl -fsS --max-time 12 https://app.soleur.ai/health | jq .`; assert `version >= 0.102.0`, `status == "ok"`.
- [ ] 0.3 Identify reporter test runner: `ls apps/web-platform/infra/*.test.sh`; confirm `cat-deploy-state.test.sh` is a bash `assert`-helper script (NOT bun/vitest).
- [ ] 0.4 Re-read `cat-deploy-state.sh:19-26,102-134` + `inngest-bootstrap.sh:216-245`; confirm timer unit name is exactly `inngest-heartbeat.timer`.

## Phase 1 — Add durable timer-liveness field (RED → GREEN)

- [ ] 1.1 (RED) In `cat-deploy-state.test.sh`, add 4 `inngest_heartbeat_timer` presence assertions mirroring the existing `inngest_heartbeat` asserts at lines 39-66 (no_prior_deploy / OK / services-merge / corrupt_state). Run → fails.
- [ ] 1.2 In `cat-deploy-state.sh`: add `HEARTBEAT_TIMER_STATUS="$(service_status inngest-heartbeat.timer)"` beside the `.service` read (line 102). Precedent: this is the 4th identical `service_status` reader call (`.service` units already read at :102-104) — same helper, same shape, lowest-risk extension (deepen-plan Phase 4.4 precedent-diff: pattern is NOT novel).
- [ ] 1.3 In `cat-deploy-state.sh`: add `--arg hbt "$HEARTBEAT_TIMER_STATUS"` to the final `jq -nc` and emit `inngest_heartbeat_timer: $hbt` inside the `services` object (after line 129).
- [ ] 1.4 Add inline comment on the `inngest_heartbeat` (.service) field: `inactive` is the NORMAL steady state for a timer-driven oneshot; `inngest_heartbeat_timer` (`active` on healthy host) is the durable liveness signal. Cite #4896.
- [ ] 1.5 (GREEN) `bash apps/web-platform/infra/cat-deploy-state.test.sh` → all asserts pass.

## Phase 2 — Blast-radius verification

- [ ] 2.1 `git diff --name-only` lists exactly `cat-deploy-state.sh` + `cat-deploy-state.test.sh` (+ plan/spec docs); `inngest-bootstrap.sh` + `web-platform-release.yml` untouched (AC4).
- [ ] 2.2 Run full infra reporter test surface from 0.3 (AC5).

## Phase 3 — Ship + post-merge close

- [ ] 3.1 PR body uses `Ref #4896` (NOT `Closes`); summarize corrected RCA, point at #4895 (deadlock fix) + #4891 (deferred capacity isolation). (AC6)
- [ ] 3.2 (post-merge) After this PR's release run, `/health` reports this PR's `build_sha`/`version` (AC7) — curl + jq, no SSH.
- [ ] 3.3 (post-merge) Volume-pressure check via deploy-status JSON `journald_storage.root_avail` + `scheduled-workspace-gc` Sentry trend; if pressured, fire GC via `/soleur:trigger-cron cron/workspace-gc.manual-trigger` (no SSH). (AC8)
- [ ] 3.4 (post-merge) `gh issue close 4896` with corrected-RCA comment. (AC9)
