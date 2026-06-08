---
title: "Silent headless /soleur:* skill-resolution degradation across the cron-eval producer fleet"
date: 2026-06-08
incident_pr: 4995
incident_window: "~since each producer's claude-eval introduction through 2026-06-08 (heartbeat-invisible)"
recovery_at: "2026-06-08 (on merge of PR #4995)"
suspected_change: "Headless `claude --print` cron evals never carried `--plugin-dir plugins/soleur` + `Skill` in `--allowedTools`; the symlinked plugin was never registered under `--print`."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - silent quality degradation (no uptime/error-rate signal)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The scheduled "claude-eval producer" crons (`apps/web-platform/server/inngest/functions/cron-*.ts` + `event-ship-merge.ts`) spawn a headless `claude --print` process whose prompt instructs it to run a `/soleur:<skill>` plugin skill. Under `--print`, the interactive marketplace/`enabledPlugins` trust flow that registers the symlinked `plugins/soleur` directory is skipped, so the eval could not resolve or invoke the skill unless its spawn argv carried `--plugin-dir plugins/soleur` AND `Skill` (+`Task`) in `--allowedTools`. None of the producers did. The evals silently fell back to the agent hand-rolling the work — degraded output — while the per-producer `cron-cloud-task-heartbeat` watchdog stayed GREEN (an audit issue was still filed every run), so the degradation was invisible to monitoring.

PR #4989 (#4987) fixed the first instance (`cron-content-generator`) after the #4982 verification run surfaced a "content-writer skill unavailable" symptom. Multi-agent review of #4989 found content-generator was not the only affected producer — 10 siblings shared the identical latent gap. This PIR covers the fleet-wide class; PR #4995 applies the fix to all 10 and adds a self-discovering parity guard so the gap cannot silently re-open.

## Status

resolved — fix landed fleet-wide in PR #4995; a source-shape parity test now fails CI if any producer regresses or a new producer adds a `/soleur:*` prompt without the flags.

## Symptom

Scheduled audit/content/SEO/UX/legal/competitive/ship/bug-fix crons file their `[Scheduled] …` summary issues on schedule (heartbeat green), but the eval's `/soleur:*` skill invocation does not resolve, so the agent produces hand-rolled, degraded output instead of running the real skill. No error surfaced to Sentry or the watchdog.

## Incident Timeline

- **Start time (detected):** 2026-06-07 (analytically, during multi-agent review of PR #4989)
- **End time (recovered):** 2026-06-08 (PR #4995 merge)
- **Duration (MTTR):** ~1 day from fleet-wide detection to fleet-wide fix (root-cause fix for the first instance landed in #4989 on 2026-06-07).

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-06-07 | #4982 verification run surfaces "content-writer skill unavailable" for content-generator. |
| agent | 2026-06-07 | PR #4989 fixes content-generator (`--plugin-dir` + `Skill,Task`); multi-agent review flags the fleet-wide gap → issue #4993. |
| agent | 2026-06-08 | PR #4995 applies the fix to all 10 sibling producers + adds the self-discovering parity guard. |

## Participants and Systems Involved

- Inngest scheduled functions under `apps/web-platform/server/inngest/functions/` (10 producers).
- The shared `_cron-claude-eval-substrate.ts` spawn path (symlinks `plugins/soleur`, injects GH token).
- Claude Code CLI `--print` headless mode (plugin registration semantics).

## Detection (+ MTTD)

- **How detected:** analytic — multi-agent code review of the content-generator fix (#4989), not a monitoring alert. The `cron-cloud-task-heartbeat` watchdog could not detect it because the heartbeat keys on artifact-creation, which still happened (degraded).
- **MTTD (mean time to detect):** unbounded for the silent-degradation period — the defect produced no monitorable signal; it was caught only by extending the #4989 root-cause analysis to sibling producers.

## Triggered by

system — a latent gap in the eval spawn argv, present since each producer's claude-eval introduction.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Headless `--print` does not auto-register the symlinked plugin; `--plugin-dir` + `Skill` in `--allowedTools` are required | `claude --help` documents `--plugin-dir`; `feature-request-plugin-dir-settings.md` root-cause doc; #4989 validated against the #4982 symptom; `~/.claude.json` had 60 inherited soleur refs masking a local probe while the ephemeral container has none | none | confirmed |

## Resolution

Applied the `--plugin-dir plugins/soleur` + `Skill`(+`Task`) fix to all 10 sibling producers (PR #4995), mirroring the merged #4989 shape verbatim. Reconciled the disproven "cwd-relative discovery" comments across 8 files. Added a self-discovering cross-producer parity guard (`cron-producer-output-wiring.test.ts`) that classifies any `cron-*`/`event-*` spawning a claude eval with a `/soleur:` prompt and asserts each carries the three flags — discovered set `=== 11` (the 10 + content-generator, which self-discovers, so the guard also protects the original fix).

## Recovery verification

- `tsc --noEmit` clean; full `test/server/inngest/` vitest suite green (1419 passed); parity guard RED→GREEN (24/24).
- A live fully-isolated `claude --print` probe was infeasible (no `ANTHROPIC_API_KEY` in env or Doppler); the mechanism is triple-confirmed (root-cause doc + contamination trace + merged #4989), and the CI source-shape parity test is the binding recurrence gate.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the crons produce degraded output?** The eval could not invoke its `/soleur:*` skill.
2. **Why couldn't it invoke the skill?** The plugin was not registered in the headless process.
3. **Why was it not registered?** Under `claude --print`, the interactive marketplace/`enabledPlugins` trust flow is skipped, so a bare symlinked `plugins/` dir is not auto-discovered; `--plugin-dir` is required and was absent. `Skill` was also missing from `--allowedTools`.
4. **Why was the flag absent across the fleet?** The producers were authored from a shared template predating the headless-plugin-registration understanding; a since-disproven "plugin resolution is cwd-relative" comment was copied into 8 files and treated as fact.
5. **Why did it go undetected?** The heartbeat watchdog keys on artifact-creation (the summary issue still filed) rather than on output quality, so a degraded-but-non-empty run reads as healthy.

## Versions of Components

- **Version(s) that triggered the outage:** all producer versions prior to PR #4995 (content-generator prior to #4989).
- **Version(s) that restored the service:** PR #4995 (fleet) / PR #4989 (content-generator).

## Impact details

### Services Impacted

Scheduled automation: agent-native audit, growth audit, growth execution, UX audit, competitive analysis, legal audit, SEO/AEO audit, campaign calendar, event-ship-merge, bug-fixer. Each ran but produced hand-rolled output instead of skill-driven output.

### Customer Impact (by role)

- Prospect: none (internal automation only).
- Authenticated app user: none directly; downstream content/SEO/growth artifacts may have been lower quality than skill-driven runs.
- Legal-document signer: none.
- Admin via Access: degraded internal audit/report quality (the operator consumes these artifacts).
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Solo operator consumed degraded audit/content artifacts of unknown extent; no rework attributable yet.

## Lessons Learned

### Where we got lucky

The #4982 verification run happened to surface an explicit "skill unavailable" string for content-generator; without it the fleet-wide gap could have persisted indefinitely behind the green heartbeat.

### What went well

Multi-agent review of the first fix (#4989) generalized the root cause to siblings rather than treating it as a one-off; the fleet fix is self-protecting via the parity guard.

### What went wrong

A heartbeat that keys on artifact-creation, not output quality, gave a false-green for a degraded run. A disproven theory ("cwd-relative discovery") was copied as fact into 8 files.

## Follow-ups

- [x] Apply the fix to all 10 sibling producers (PR #4995).
- [x] Add a self-discovering parity guard so a new `/soleur:*` producer without the flags fails CI.
- [x] Reconcile the disproven cwd-relative comments fleet-wide.
- [ ] Consider an output-quality signal (beyond artifact-creation) for the claude-eval heartbeat so silent-degradation is detectable at runtime, not only analytically. (Tracked as a non-blocking improvement — the parity guard already prevents the flag-absence recurrence class.)

## Action Items

- The recurrence gate is the CI parity test (`cron-producer-output-wiring.test.ts`); no separate GitHub issue required for the flag-absence class — the test fails CI on regression.
- The runtime output-quality-signal idea is captured in Follow-ups; promote to an issue only if a future degraded run recurs despite the flags being present.
