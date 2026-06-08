---
title: "Tasks — Re-fix cron bwrap-userns via layered containment (re-scope of #5000/#5004)"
plan: knowledge-base/project/plans/2026-06-08-fix-cron-sandbox-dontask-allowlist-tiered-plan.md
supersedes_plan: knowledge-base/project/plans/2026-06-08-fix-cron-bash-sandbox-bwrap-userns-failure-plan.md
lane: cross-domain
date: 2026-06-08
brand_survival_threshold: single-user incident
---

# Tasks — Re-fix cron bwrap-userns (#5000, #5004) — layered containment v2

> Supersedes the BLOCKED bypassPermissions task list. Tier-1 (this PR) = permission-layer +
> hook containment, no infra. Tier-2 (follow-up issue) = egress firewall + least-priv token.

## Phase 0 — Gating pre-merge probes (NO code; if any fails, STOP/escalate)

- [ ] 0.1 (AC0/D0a) Probe `permissions.defaultMode`: run `claude --print --settings <tmp>` with a candidate overlay + scoped `--allowedTools`; one allowlisted + one non-allowlisted command. Confirm non-allowlisted is **denied, not hung**, in `--print`. Try `dontAsk` first, then `default`. PIN the working mode. Paste evidence into PR desc.
- [ ] 0.2 (AC0/D0b) Probe path-deny: confirm `permissions.deny:["Read(/proc/**)"]` blocks `cat /proc/self/environ`.
- [ ] 0.3 (AC0/D0c) Probe L3 hook: confirm a `PreToolUse` jq-decision hook denies a `Bash` whose `tool_input.command` matches a secret pattern (`ghs_…`).
- [ ] 0.4 Re-grep producers: `git grep -nE '(^|[",])Bash([,"])' apps/web-platform/server/inngest/functions/cron-*.ts` → expect **12** bare-`Bash` carriers. List them.
- [ ] 0.5 Classify the 3 raw-`spawn("bash")` crons (content-publisher, content-vendor-drift, rule-prune) + confirm skill-freshness/workspace-gc spawn no claude + verify compound-promote/strategy-review.
- [ ] 0.6 Inventory all `cron-*.test.ts` assertions on `--allowedTools`.

## Phase 1 — Failing tests (RED)

- [ ] 1.1 Rewrite `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` `DEFAULT_CLAUDE_SETTINGS` block (currently asserts `bypassPermissions`): assert `defaultMode` = pinned value, `sandbox.enabled:false`, `deny` contains every `Read(/proc/**)`+secret-file rule AND egress/interpreter/subshell verbs, `hooks.PreToolUse` references the L3 hook, `allow:[]`, and `"bypassPermissions"` is not the JSON value (AC1).
- [ ] 1.2 (AC2b) BEHAVIORAL deny tests via real `claude --print` + scoped `--allowedTools`: `cat /proc/self/environ` denied; `curl http://example.com` denied; secret-shaped `echo "ghs_…"` denied by L3 hook. Assert exit/refusal.
- [ ] 1.3 (AC4b) Unit test: each verbatim roadmap-review prompt command (incl. single-quoted `gh api 'repos/jikig-ai/soleur/…'`) matches an allow pattern.
- [ ] 1.4 (AC3) Strengthened bare-`Bash` grep test returns 0; expected count 12.
- [ ] 1.5 (AC5) community-monitor `buildSpawnEnv` test: ANTHROPIC_API_KEY+GH_TOKEN PRESENT; read-auth tokens per D5 choice present; degradation surfaced not silent.
- [ ] 1.6 Confirm RED against current substrate.

## Phase 2 — Implement (GREEN)

- [ ] 2.1 Create L3 hook `plugins/soleur/<path>/cron-secret-scan-hook.sh` (jq → secret-pattern → deny JSON).
- [ ] 2.2 D1 substrate: replace `DEFAULT_CLAUDE_SETTINGS` with the deny-floor + `hooks.PreToolUse` + pinned `defaultMode` + `sandbox:false`; rewrite the comment block (remove all bypassPermissions rationale). `git config` NOT in any allow.
- [ ] 2.3 D3 roadmap-review `--allowedTools`: drop bare `Bash`+vestigial WebSearch/WebFetch; enumerate prompt-matched gh/git verbs (sub-command granularity); resolve the `gh api` single-quote; add branch/push verbs or fail-loud (AC4c).
- [ ] 2.4 D2: drop bare `Bash` from the other 11 substrate-claude crons; scoped allow for the narrow ones (broad ones fail-closed/contained).
- [ ] 2.5 D5 community-monitor: keep read-auth tokens (or split read/write); surface any platform degradation (CPO C1/C2).
- [ ] 2.6 D6: pause Inngest schedules for the deferred set (or mute monitors + link); self-label fallback issues `tier-2-deferred` (AC9).
- [ ] 2.7 Update per-cron `--allowedTools` tests (re-grep).
- [ ] 2.8 (AC7) Verify repo-root `.claude/settings.json` UNCHANGED.
- [ ] 2.9 (AC6) `vitest run apps/web-platform/test/server/inngest/` green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `scripts/test-all.sh` green.

## Phase 3 — Observability + docs

- [ ] 3.1 Runbook `cloud-scheduled-tasks.md`: host-independent layered containment; #4932/#4944 = non-cron defense-in-depth; Tier-2 deferral + deferred-monitor handling.
- [ ] 3.2 ADR-033 amendment I7 (claude-code crons: sandbox-off + per-cron scoped allow + secret-file/egress deny + L3 hook; raw-`spawn("bash")` crons NOT covered → Tier-2 firewall).
- [ ] 3.3 Learning `knowledge-base/project/learnings/integration-issues/<topic>.md` (date at write-time): `/proc/self/environ` defeats a bash-only allowlist; built-in read-only bash always runs unless deny-overridden; daily-triage prod precedent; layered design.

## Phase 4 — Follow-up issues (Phase 4 of plan)

- [ ] 4.1 File Tier-2 issue (`type/security`): egress firewall (Terraform) + least-priv `generateInstallationToken` (`github-app.ts:594`) + restore broad set incl. #5000 + the 3 raw-bash crons; final deferred set from D4. Note: firewall does NOT stop `gh issue create --body $secret` → L2/L3 stay load-bearing.
- [ ] 4.2 File daily-triage/follow-through allowlist-audit issue (`type/security`, low-pri).
- [ ] 4.3 (AC8/AC10) PR body: `Ref #5000`+`Ref #5004`; link both follow-up issue numbers.

## Phase 5 — Verify recovery (post-merge, automated)

- [ ] 5.1 (AC11) Deploy lands; `/soleur:trigger-cron` → `cron/roadmap-review.manual-trigger`; confirm `[Scheduled] Weekly Roadmap Review …` issue produced end-to-end → `gh issue close 5004` (comment links PR). If no issue → AC4b mismatch regressed; fix forward, do NOT close.
- [ ] 5.2 (AC12) D4 trigger-cron validation across Tier-1 candidates; record pass/fail per cron in the Tier-2 issue.
- [ ] 5.3 (AC13) Confirm #5000 self-reports FAILED-contained, labeled `tier-2-deferred`, left OPEN.

## Review gates

- [ ] CPO sign-off recorded — APPROVE-WITH-CONDITIONS (C1/C2/C3 encoded). Re-confirm conditions hold at ship.
- [ ] deepen-plan triad / review-time: security-sentinel + user-impact-reviewer + architecture-strategist (re-run against the diff; the plan-time panel already ran).
- [ ] No open Critical at review.
