---
title: "Self-pull from the observability layer in diagnostic loops — never ask the operator to fetch data; if a signal is missing, add the marker"
date: 2026-07-08
category: workflow-patterns
module: go, one-shot, reproduce-bug, incident, observability
tags: [observability, better-stack, sentry, self-pull, operator-role, instrumentation, blind-surface, concierge, worktree-wedge]
related_prs: [6183, 6184]
related_issues: [5934]
related_rules: [hr-no-dashboard-eyeball-pull-data-yourself, hr-no-ssh-fallback-in-runbooks, hr-observability-layer-citation]
---

# Learning: self-pull observability in diagnostic loops; a missing signal is a cue to instrument, not to escalate

## Problem

During the #5934 Concierge worktree-wedge diagnosis, the agent repeatedly asked the
**operator** to paste verbatim error output and to run `grep`/`stat`/`git config`
probes — twice — when the diagnostic data was (or should have been) in the
observability layer: Better Stack `SOLEUR_*` markers (queryable via
`scripts/betterstack-query.sh`) and Sentry. The operator is non-technical; their role
in an incident is DECISIONS, not data retrieval. The wedge then stayed invisible
through four fixes because the fatal error was emitted to a per-PID logfile with an
`[error]` prefix that the marker regex missed — there was no monitored signal to pull,
so the reflex defaulted to "ask the operator."

## Root Cause (two halves)

1. **Self-pull gap.** The existing hard rule `hr-no-dashboard-eyeball-pull-data-yourself`
   said "don't eyeball dashboards" but the reflex extended to "ask the operator to fetch
   instead" — which is the same anti-pattern with the human in the retrieval loop. Pulling
   errors/telemetry is the agent's job (`doppler run -p soleur -c prd_terraform --
   scripts/betterstack-query.sh --since <N> --grep <marker>`, plus Sentry), never the
   operator's.

2. **Missing-signal gap.** The wedge was invisible because no monitored stdout sentinel
   existed for the failing path. The fix that finally enabled self-diagnosis was to ADD
   markers in the emitting code — `SOLEUR_GIT_CONFIG_TARGET_MASKED` (the masked-config
   fatal path) and later `SOLEUR_GIT_WORKTREE_VERIFY_FAILED` (a silent verify path). Once
   those markers landed and deployed, the agent could self-pull the exact failure. So a
   missing diagnostic signal is a cue to instrument the deployed code, not to escalate to
   the operator for it.

## Key Insight

- **In any diagnostic / incident / verification loop, the operator decides — they do not
  fetch.** Pull errors and telemetry yourself from the observability layer (Better Stack
  `SOLEUR_*` markers via `scripts/betterstack-query.sh`, creds in Doppler `prd_terraform`;
  Sentry via `scripts/sentry-issue.sh`). Never ask the operator to paste error output, run
  probes (`grep`/`stat`/`findmnt`/`git config`), or eyeball logs. This extends
  `hr-no-dashboard-eyeball-pull-data-yourself` from "don't eyeball dashboards" to "don't
  ask the operator to fetch either."

- **A signal missing from telemetry is an instrumentation task, not an escalation.** If the
  data you need isn't in Better Stack/Sentry, ADD a monitored stdout `SOLEUR_*` sentinel in
  the emitting code so the next occurrence self-reports — then self-pull it. (On a blind
  execution surface like the Concierge agent-sandbox, this is the ONLY correct move —
  companion to `2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md`;
  remember a merged marker only helps once it DEPLOYS.)

## Where This Is Wired

Guidance bullets added to the diagnostic-entry surfaces where the reflex fires:
`plugins/soleur/commands/go.md`, `plugins/soleur/skills/one-shot/SKILL.md`,
`plugins/soleur/skills/reproduce-bug/SKILL.md`, `plugins/soleur/skills/incident/SKILL.md`.
Not added to AGENTS.md — `AGENTS.core.md` is over the always-loaded byte budget
(`scripts/lint-agents-rule-budget.py` rejects growth); the reflex-point skills are the
correct home.
