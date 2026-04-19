---
title: "tasks: feat-one-shot-1052-resource-monitoring"
date: 2026-04-19
issue: 1052
plan: ../../plans/2026-04-19-feat-resource-monitoring-before-beta-invites-plan.md
---

# Tasks — Resource Monitoring Before Beta Invites

Derived from the plan at
`knowledge-base/project/plans/2026-04-19-feat-resource-monitoring-before-beta-invites-plan.md`.

## Phase 0 — Read-only verification (confirmed during deepen pass)

- 0.1 Read `apps/web-platform/infra/disk-monitor.sh` and `disk-monitor.test.sh` end-to-end.
- 0.2 Confirm `/health` route is served from `apps/web-platform/server/index.ts:28-38` (custom HTTP server, NOT App Router).
- 0.3 Confirm `sessions` is already exported at `apps/web-platform/server/ws-handler.ts:73` — no new export helper needed.
- 0.4 Confirm existing health test at `apps/web-platform/test/server/health.test.ts` — extend it; do not create a parallel `test/health.test.ts`.
- 0.5 Confirm `/workspaces` path convention in `apps/web-platform/server/workspace.ts` (`process.env.WORKSPACES_ROOT || "/workspaces"`).
- 0.6 Confirm production container publishes `-p 0.0.0.0:3000:3000` in `apps/web-platform/infra/ci-deploy.sh` (so host-side `curl 127.0.0.1:3000/health` works).

## Phase 1 — RED tests

- 1.1 Create `apps/web-platform/test/server/session-metrics.test.ts` with failing assertions. Use `vi.mock("../../server/ws-handler", () => ({ sessions: new Map([["u1", {}], ["u2", {}]]) }))` for session count. Mock `fs.readdirSync` + `fs.statSync` for workspace count (include one `.orphaned-*` entry to prove filtering).
- 1.2 Edit `apps/web-platform/test/server/health.test.ts` (file exists). Add `.toBe` equality assertions for `cpu_pct_1m`, `mem_pct`, `load_avg_1m`, `active_sessions`, `active_workspaces`. Use the existing `describe("buildHealthResponse", ...)` block.
- 1.3 Create `apps/web-platform/infra/resource-monitor.test.sh` following `disk-monitor.test.sh`. Mock curl with `echo "$*" >> "$mock_dir/curl_args"`; assert via `grep -qF`. Cases: under-threshold no-email; WARN fire; cooldown honored; CRIT fire after WARN (per-threshold); missing env file graceful skip.
- 1.4 Run `cd apps/web-platform && ./node_modules/.bin/vitest run server/session-metrics server/health` — expect failures on missing module and missing fields.
- 1.5 Run `bash apps/web-platform/infra/resource-monitor.test.sh` — expect failure on missing `resource-monitor.sh`.

## Phase 2 — GREEN implementation

- 2.1 Create `apps/web-platform/server/session-metrics.ts` — imports `{ sessions }` directly from `./ws-handler`; readdir-based workspace counter. (No ws-handler edit needed — deepen pass confirmed the Map is already exported.)
- 2.2 Extend `HealthResponse` interface and `buildHealthResponse()` in `apps/web-platform/server/health.ts` with `cpu_pct_1m` (loadavg/nproc for hot-path cheapness), `mem_pct` (`MemAvailable`-based), `load_avg_1m`, `active_sessions`, `active_workspaces`.
- 2.3 Create `apps/web-platform/infra/resource-monitor.sh` following the `disk-monitor.sh` pattern: `set -euo pipefail`, always exit 0, per-threshold cooldown, `/proc/meminfo` MemAvailable for memory, `/proc/stat` 1-sec delta for CPU, Resend POST via `jq -n` payload and `curl --max-time 10`.
- 2.4 Re-run tests from Phase 1 — all pass.
- 2.5 Run `cd apps/web-platform && ./node_modules/.bin/vitest run` for the full app suite — no pre-existing regressions.

## Phase 3 — Terraform + cloud-init wiring

- 3.1 Add `resource-monitor.sh` + env file + systemd service + timer entries to `apps/web-platform/infra/cloud-init.yml` (mirror the disk-monitor entries).
- 3.2 Add `resource-monitor.sh` base64 injection variable in `templatefile(...)` call inside `apps/web-platform/infra/server.tf`.
- 3.3 Add `terraform_data.resource_monitor_install` in `server.tf` as a mirror of `terraform_data.disk_monitor_install`.
- 3.4 Run `cd apps/web-platform/infra && terraform fmt -recursive && terraform validate`.
- 3.5 Run `cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan` — confirm exactly "2 to add" (or equivalent) with no surprise changes.
- 3.6 Do NOT apply. Plan output goes into the PR description.

## Phase 4 — Roadmap + deferral issues

- 4.1 Edit `knowledge-base/product/roadmap.md` row 4.8 priority column P1 → P2; add `#1052` reference alongside `#673`.
- 4.2 Create follow-up issue: "ops: per-workspace cgroup CPU/RAM accounting (v2 of #1052)" — milestone Phase 4, labels `priority/p3-low`, `domain/operations`, `type/feature`.
- 4.3 Create follow-up issue: "ops: evaluate Prometheus/Grafana once capacity investigation exceeds 1 hr/week or second VM added" — milestone `Post-MVP / Later`, labels `priority/p3-low`, `domain/operations`, `type/chore`.
- 4.4 Verify both issues exist via `gh issue view <N>` before proceeding.

## Phase 5 — Compound + review

- 5.1 Run `skill: soleur:compound` before commit.
- 5.2 Commit on feature branch: `feat(ops): deploy resource monitoring before beta invites (#1052)` — include plan file and tasks.md.
- 5.3 Push to remote.
- 5.4 Run `skill: soleur:review` — address any BLOCKING or HIGH findings inline per `rf-review-finding-default-fix-inline`.

## Phase 6 — Ship

- 6.1 Run `skill: soleur:ship` — ship gate enforces `semver:patch` label.
- 6.2 Verify PR body contains `Closes #1052` (body, not title, per `wg-use-closes-n-in-pr-body-not-title-to`).
- 6.3 After merge: `gh pr merge <N> --squash --auto`; poll until MERGED.
- 6.4 Post-merge verification per the plan's "Post-merge (operator)" acceptance criteria (requires operator approval to run `terraform apply`).

## Definition of Done

- PR merged to `main` with `semver:patch` label.
- Operator has run `terraform apply` in a separate session and confirmed:
  - `systemctl is-active resource-monitor.timer` returns `active` on the web server.
  - One alert has been successfully fired and received via the `WARN_MEM_PCT=1` smoke test.
  - `curl https://app.soleur.ai/health` (note: `/health`, not `/api/health`) returns the five new fields.
- Follow-up deferral issues (Phase 4.2, 4.3) exist and are milestoned.
- Roadmap row 4.8 reflects priority P2 and references both `#1052` and `#673`.
