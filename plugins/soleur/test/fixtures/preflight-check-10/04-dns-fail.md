---
date: 2026-05-20
type: feature
issue: 4118
branch: feat-one-shot-inngest-cloud-init-iac
---

# Plan — Fixture: PR #4148 Plan-As-Merged Snapshot (DNS-Fail Regression)

Snapshot of the Observability block from PR #4148's plan
(`2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` at commit `f2b2f959`).
The typo'd hostname `web-platform.soleur.ai` is preserved verbatim — it does
not resolve. Test asserts Check 10 returns FAIL when the stub executor returns
`(rc=6, stdout="")` (the canonical curl DNS-failure shape).

## Observability

[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]

- **liveness_signal:** Existing Better Stack heartbeat `betteruptime_heartbeat.inngest_prd` (60s period, 30s grace) — fires from the existing `inngest-heartbeat.timer` (installed by `inngest-bootstrap.sh`). If cloud-init's new runcmd block succeeds on a fresh VM, the heartbeat starts within ~120 s of cloud-init completion. If it fails, the heartbeat never registers — Better Stack alerts within `period + grace` = 90 s of expected first fire.
- **error_reporting:** Sentry — `apps/web-platform/server/inngest/client.ts` registers cron functions with Sentry monitor slugs (existing). Sentry's cron-monitor `missed` flag is the loud failure mode.
- **failure_modes:**
  1. cloud-init's `docker pull` of the OCI image fails (network, GHCR outage, tag drift). Cloud-init exits non-zero on this `set -e` block; `/var/log/cloud-init-output.log` carries the error. Operator sees on first boot.
  2. The bootstrap script's `INNGEST_CLI_SHA256` mismatch (upstream supply-chain attack on `releases.inngest.com`). `inngest-bootstrap.sh` already has `sha256sum -c` (existing line ~120) — abort with explicit error.
  3. systemd unit file write fails (disk full, permission). Cloud-init audit covers permission; `disk-monitor.timer` covers disk.
- **logs:** `/var/log/cloud-init-output.log` (on-host), `journalctl -u inngest-server.service`, `journalctl -u inngest-heartbeat.service`, Sentry cron monitor events, Better Stack heartbeat events.
- **discoverability_test.command:**
  ```bash
  # Run from operator workstation (NO SSH). Returns 200 or 401 if Inngest is alive; non-200/401 means absent.
  curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://web-platform.soleur.ai/api/inngest
  ```
  Expected output: `200` (or `401` with HMAC challenge). Anything else = Inngest absent or unreachable. `--max-time 10` per `hr-ssh-diagnosis-verify-firewall` sibling guidance on unbounded network calls.

## Acceptance Criteria

- [ ] None — fixture only.
