---
title: "EnvironmentFile= decoupled from env-population is an env-injection trap"
date: 2026-05-20
category: bug-fixes
issue: 4116
related_prs: [3973, 4085, 4093, 4104, 4111]
tags: [systemd, doppler, observability, env-injection, substrate-cascade]
---

## What happened

`inngest-heartbeat.service` had been emitting `curl: (3) URL rejected: Malformed input to a URL function` every 60 seconds from 2026-05-19T16:21Z to 2026-05-20T~08:00Z (16+ hours). The Better Stack heartbeat resource (`betteruptime_heartbeat.inngest_prd`) — the ONLY external liveness signal for the self-hosted Inngest server between cron fires — was silently dark.

The fix landed in PR #4123 (Ref #4116): wrap the heartbeat service's `ExecStart=` line in `doppler run --project soleur --config prd`, mirroring the pattern that `inngest-server.service:137` already uses.

## Root cause (mechanism)

`inngest-bootstrap.sh` writes two systemd units that BOTH carry `EnvironmentFile=/etc/default/inngest-server`:

- `inngest-server.service` — wraps its start line in `/usr/bin/doppler run … -- inngest start …`, so all `INNGEST_*` secrets resolve from Doppler prd at process-start time.
- `inngest-heartbeat.service` — did NOT wrap its start line. The pre-fix shape was `ExecStart=${HEARTBEAT_SCRIPT}` where the script invokes `curl -fsS … "$INNGEST_HEARTBEAT_URL"`.

Substrate-cascade PR #4085 fixed the broader env-injection problem at `/etc/default/inngest-server` by writing the three load-bearing Doppler-CLI env vars (DOPPLER_TOKEN, DOPPLER_CONFIG_DIR, DOPPLER_ENABLE_VERSION_CHECK) into that file. PR #4085 did NOT materialize `INNGEST_HEARTBEAT_URL` into the same file — by intent, since the secret already lived in Doppler prd and could be resolved at runtime via `doppler run`. But the heartbeat unit was not wrapped, so it read directly from `EnvironmentFile=` and got an empty string.

Per `systemd.exec(5)`: "If `EnvironmentFile=` is missing or empty, no error is generated." Missing keys silently load as empty strings. `curl` accepts an empty `URL` argument and fails at the protocol layer with status `3/NOTIMPLEMENTED`.

## Why no gate caught it

The substrate cascade (#4017 → #4085 → #4093 → #4104 → #4111) was a five-PR sequence specifically focused on env-injection bugs. Each PR's acceptance criteria centered on inngest-server.service starting successfully — none checked the heartbeat sibling. The heartbeat resource has `paused = true` at apply time (intentional to prevent first-ping alerting), so Better Stack never sent a missed-ping alert even though the script was failing every 60s.

The PR that introduced the heartbeat unit (PR-A #3973 — "feat(infra): IaC for inngest-server — Doppler + BetterStack providers + bootstrap + OCI build") passed every plan-time gate but declared no observability surface. PR-F #3940 was the upstream trigger-layer feature (runtime code, no infra files); the substrate that hosts the heartbeat was retroactively built in PR-A. The operator-blind zone aggregated across the substrate cascade until issue #4116 surfaced it via post-mortem.

## Generalization: the trap class

**`EnvironmentFile=` decoupled from the env-population path is a structural trap.**

Two failure shapes:

1. **Caller assumes env-population path; population is incomplete.** PR-A's heartbeat unit assumed `INNGEST_HEARTBEAT_URL` would be in `/etc/default/inngest-server`. Bootstrap script (then and now) writes only the keys it knows about. Drift between "what the unit reads" and "what the writer writes" is invisible until runtime.

2. **Caller assumes Doppler-wrapped invocation; unit forgets to wrap.** The fix moves the contract from "host-side env file is source of truth" to "Doppler prd is source of truth, materialized at `doppler run` time". Pattern-parity with `inngest-server.service` ensures the same source-of-truth across all sibling units.

**Canonical fix.** When a systemd unit needs a Doppler-managed secret:

```diff
- ExecStart=${HEARTBEAT_SCRIPT}
+ DOPPLER_BIN="$(command -v doppler 2>/dev/null || true)"
+ if [[ -z "$DOPPLER_BIN" ]]; then exit 1; fi
+ ExecStart=${DOPPLER_BIN} run --project soleur --config prd -- ${HEARTBEAT_SCRIPT}
```

Resolve the binary path via `command -v` rather than hardcoding `/usr/bin/doppler` (cloud-init installs to `/usr/local/bin/doppler`; the hardcoded path in `inngest-server.service:137` is a latent same-class risk — file follow-up issue).

## Workflow gate added (the load-bearing piece)

Per #4116's structural ask, a new always-loaded hard rule was added: `hr-observability-as-plan-quality-gate`. Every plan touching production code/infra MUST declare a `## Observability` block with 5 fields (`liveness_signal`, `error_reporting`, `failure_modes`, `logs`, `discoverability_test`) and a `discoverability_test.command` that runs WITHOUT SSH.

Enforcement layers:

- `plugins/soleur/skills/plan/SKILL.md` Phase 2.9 — schema requirement at plan-template time.
- `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.7 — halt condition for missing section or placeholder field values.
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` MINIMAL/MORE/A-LOT — the block lands in every detail tier.
- `AGENTS.core.md` — `hr-observability-as-plan-quality-gate` (571 B, well within the 600 B per-rule cap).

The PR also backfilled the `## Observability` block in the two TR9 cron specs (`feat-cron-follow-through-monitor-tr9`, `feat-agent-loop-crons-inngest-tr9`) so the rule's coverage is not retroactively bypassed.

## Detection / future-proofing

For any new systemd unit reading Doppler secrets:

```bash
# Both inngest-server and inngest-heartbeat must wrap their start line in doppler run
grep -nE '^ExecStart=' apps/web-platform/infra/inngest-bootstrap.sh | grep -c 'doppler run'
# Expected: 2
```

The `inngest.test.sh` test harness now asserts the heartbeat-unit shape (RED before the fix, GREEN after).

For the structural class — every future plan touching production code/infra is now refused at deepen-plan time if it omits the `## Observability` block.

## Related learnings

- `2026-05-15-multi-stage-premise-validation-compounds-and-agents-sidecar-loader-class-fit.md` — loader-class-fit logic that determined `core` (not `rest`) was the right placement.
- `2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md` — sibling rule (`hr-all-infrastructure-provisioning-servers`) from the same PR-F context.
