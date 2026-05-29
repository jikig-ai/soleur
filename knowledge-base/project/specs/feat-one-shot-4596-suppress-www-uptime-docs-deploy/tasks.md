---
feature: suppress soleur_www uptime monitor during docs-deploy Pages rebuild (Option A)
issue: 4596
lane: single-domain
plan: knowledge-base/project/plans/2026-05-29-feat-suppress-www-uptime-monitor-during-docs-deploy-plan.md
---

# Tasks — Option A: suppress soleur_www uptime monitor during docs-deploy

Derived from the plan. The plan body is the source of truth for the exact shell;
these tasks are the execution checklist for `/soleur:work`.

## Phase 0 — Preconditions (read + verify before editing)

- [ ] 0.1 Read `.github/workflows/deploy-docs.yml` in full (insert anchors are line-based:
  pause step after the Screenshot-gate step / before `Setup Pages`; resume step after
  `Deploy to GitHub Pages`).
- [ ] 0.2 Read `apps/web-platform/infra/sentry/uptime-monitors.tf` (`soleur_www` resource +
  its comment block).
- [ ] 0.3 Confirm secrets exist: `gh secret list | grep -E 'SENTRY_IAC_AUTH_TOKEN|SENTRY_API_HOST|SENTRY_ORG'`.
- [ ] 0.4 (Optional) Live-probe the Sentry `/detectors/` API: confirm
  `GET /api/0/organizations/{org}/detectors/` returns the `soleur-ai-www` object with
  `id`/`name`/`enabled`, and decide whether a partial `PUT {"enabled":false}` works or
  GET-then-PUT is required (default: GET-then-PUT).

## Phase 1 — deploy-docs.yml pause/resume bracket

- [ ] 1.1 Add the **pause** step (GET `/detectors/` → select `name == "soleur-ai-www"` →
  GET-then-PUT `.enabled = false`), with `id: pause_www_monitor` and a `monitor_id` output.
  Secrets via `env:` only. Not-found → `::warning::` + empty output, deploy continues. (AC1, AC4)
- [ ] 1.2 Add the **probe-then-resume** step with `if: always()` AFTER `Deploy to GitHub Pages`:
  bounded `301` probe loop (every `curl --max-time`), then GET-then-PUT `.enabled = true`
  regardless of probe outcome; PUT != 200 → `::error::` + exit 1. (AC2, AC3)
- [ ] 1.3 Confirm `permissions:` block is unchanged (`contents: read`, `pages: write`,
  `id-token: write`). (AC5)
- [ ] 1.4 Guard both steps with `which jq >/dev/null 2>&1 || (apt-get update && apt-get install -y jq)`.

## Phase 2 — Ratchet downtime_threshold 5→3

- [ ] 2.1 `apps/web-platform/infra/sentry/uptime-monitors.tf`: `soleur_www`
  `downtime_threshold = 5` → `3`. (AC6)
- [ ] 2.2 Replace the "longer fuse" comment block with an Option-A supersession note
  (cite #4596 + #4595). Do NOT add `enabled` or `lifecycle.ignore_changes`.

## Phase 3 — Verification

- [ ] 3.1 `actionlint .github/workflows/deploy-docs.yml` exits 0; extract new `run:` snippets
  and `bash -n` each. (AC7)
- [ ] 3.2 `cd apps/web-platform/infra/sentry && terraform init -backend=false && terraform validate` (AC8)
- [ ] 3.3 `bash tests/scripts/test-destroy-guard-counter-sentry.sh` and
  `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` both green (unchanged). (AC9)

## Phase 4 — Post-merge (automated)

- [ ] 4.1 Merge to `main` auto-fires `apply-sentry-infra.yml` (it already `-target=`s
  `sentry_uptime_monitor.soleur_www`); applies threshold=3. Verify via run summary or
  `GET /api/0/organizations/{org}/detectors/`. (AC10)
- [ ] 4.2 First post-merge `deploy-docs.yml` run pauses+resumes `soleur_www`; no page fires
  during the deploy window (Sentry detector check history). (AC11)

## Notes

- Use `Closes #4596` in the PR body (this is a code change merged pre-effect, not an
  ops-remediation that runs post-merge — the pause/resume lands in the workflow on merge).
- The `if: always()` resume step is the SOLE re-enable guarantee; do not rely on the next
  sentry apply to heal a stuck pause (provider sends `enabled: null` on omitted-attr apply;
  null-handling unverified).
