---
title: "Tasks — Fix cron bash-sandbox bwrap userns failure (#5000, #5004)"
plan: knowledge-base/project/plans/2026-06-08-fix-cron-bash-sandbox-bwrap-userns-failure-plan.md
lane: cross-domain
date: 2026-06-08
---

# Tasks — Fix cron bash-sandbox bwrap userns failure (#5000, #5004)

## Phase 0 — Live-evidence precondition (RED gate; no code)

- [ ] 0.1 Pull live Sentry `extra` for the #5000 / #5004 runs via the org-issues API with `SENTRY_ISSUE_RW_TOKEN` (read-only, NO SSH). Search `cron-claude-eval` / `scheduled-output-missing` events for `stderrTail`/`stdoutTail` containing `Operation not permitted` / `bwrap` / `/proc`.
- [ ] 0.2 Confirm bwrap-userns failure (not contaminated max-turns, not upstream API 500, not billing). If evidence refutes → STOP and re-scope.
- [ ] 0.3 Record current host `kernel.apparmor_restrict_unprivileged_userns` state from the #4944 non-blocking drift detector output (deploy-status / Sentry) — informs a follow-up issue on #4932's systemd unit WITHOUT blocking this code fix.

## Phase 1 — Failing tests (RED)

- [ ] 1.1 Create/extend `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` (mirror `cron-content-generator.test.ts` harness).
- [ ] 1.2 Assert written `.claude/settings.json` parsed JSON has `sandbox.enabled === false`.
- [ ] 1.3 Assert `permissions.defaultMode === "bypassPermissions"`.
- [ ] 1.4 Assert `permissions.allow` deep-equals `[]` (no allowlist widening).
- [ ] 1.5 Add drift-guard anchored on the `sandbox.enabled: false` literal so a regression to `true` FAILs.
- [ ] 1.6 Tests assert WRITTEN config content, not model behavior (LLM out of the assertion path). Confirm RED against current substrate.

## Phase 2 — Implement (GREEN)

- [ ] 2.1 Edit `DEFAULT_CLAUDE_SETTINGS` in `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`: `sandbox.enabled: false` + `permissions.defaultMode: "bypassPermissions"`; keep `permissions.allow: []`.
- [ ] 2.2 Update the surrounding comment citing #5000/#5004 + docs rationale (sandbox auto-approval → `bypassPermissions` pairing; host-independent vs sysctl drift).
- [ ] 2.3 Verify repo-root `.claude/settings.json` is UNCHANGED (`git diff --name-only origin/main..HEAD` must not list it).
- [ ] 2.4 `vitest run apps/web-platform/test/server/inngest/` green.
- [ ] 2.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (NOT `npm run -w`).
- [ ] 2.6 `scripts/test-all.sh` green (orphan suites included).

## Phase 3 — Observability + docs

- [ ] 3.1 Update `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` H2: cron eval now sandbox-disabled + bypassPermissions; host sysctl (#4932/#4944) is defense-in-depth for non-cron consumers only.
- [ ] 3.2 Capture learning in `knowledge-base/project/learnings/integration-issues/<topic>.md`: real cron settings.json is the runtime overlay; sandbox-disable requires bypassPermissions pairing; sysctl-drift recurrence motivated removing the host dependency.

## Phase 4 — Verify recovery (post-merge, automated)

- [ ] 4.1 Deploy lands (web-platform-release.yml on merge touching `apps/web-platform/**`).
- [ ] 4.2 `/soleur:trigger-cron` → `cron/roadmap-review.manual-trigger` + `cron/growth-audit.manual-trigger` (trigger secret read read-only from Doppler; no SSH).
- [ ] 4.3 Confirm each produces a success `[Scheduled] …` issue with the correct `scheduled-<task>` label end-to-end.
- [ ] 4.4 `gh issue close 5000 5004`, each with a comment linking the merged PR. (PR body used `Ref #5000`/`Ref #5004`, not `Closes`.)

## Review gates

- [ ] CPO sign-off recorded (threshold = single-user incident).
- [ ] deepen-plan triad (security-sentinel + architecture-strategist + data-integrity-guardian) ran.
- [ ] `user-impact-reviewer` ran at review time; no open Critical.
