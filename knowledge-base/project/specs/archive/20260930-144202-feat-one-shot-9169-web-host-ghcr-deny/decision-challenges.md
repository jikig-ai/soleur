# Decision challenges — #9169 (web-host ghcr.io deny)

Recorded headless by `soleur:plan` / `soleur:plan-review` (ADR-084). `soleur:ship` renders these
into the PR body and files the `action-required` issue.

## User-Challenge 1 — the `ghcr_blocked` carrier is a per-release marker, not a periodic heartbeat

- **Operator's stated direction (issue #9169):** "Add a `ghcr_blocked` field to a web-host
  heartbeat, so Better Stack shows the deny is in force."
- **What the plan does instead:** `ci-deploy.sh` emits `GHCR_DENY ghcr_blocked=<1|0|unknown>` once
  per invocation (every release, both hosts), next to `DEPLOY_SCRIPT_SHA`.
- **Why:** no periodic key=value web heartbeat reaches BOTH running hosts. `disk-monitor.sh`,
  `resource-monitor.sh` and the `web-zot-consumer-probe` canary reach web-2 only at birth
  (their installers are web-1-pinned); `ci-deploy.sh` is the one host script both running-host routes
  deliver. Measured cadence: 5 web-2 deploys in about 2 hours on 2026-09-30.
- **Cost of the operator's direction:** ship the probe script to web-2 through
  `deploy_pipeline_fix_web2`, which widens `TRIGGER_FILES` and its SKILL.md / workflow lockstep for one
  field.
- **Default if nobody objects:** the per-release marker ships; worst-case evidence age (time since the
  last release) is written into the ADR-096 amendment.

## Taste (applied, reversible) — named devex seat (`soleur:engineering:cto`)

Applied because each is purely technical and either coincided with an eng-panel finding or only adds
test/comment text; listed here because named-panel findings default to Taste.

- Do not pin the web-2 sentinel value in a test (coincided with DHH + code-simplicity).
- Classifier-agreement table across the registry classifier, `_ghcr_blocked_state` and
  `local.ghcr_deny_assert_sh` in `web-ghcr-deny.test.sh`.
- Guard 2 failure text names the active-active Phase 5 retirement of the web-1 SSH route.
- One-line charter comment on `zot_consumer_probe_install`.
