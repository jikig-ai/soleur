---
date: 2026-05-20
type: best-practice
companion_rule: hr-observability-as-plan-quality-gate
trigger_pr: 4116
related: [hr-no-dashboard-eyeball-pull-data-yourself]
---

# Observability as a Plan-Quality Gate (companion to `hr-observability-as-plan-quality-gate`)

The hard rule body in `AGENTS.core.md` is trimmed to a one-liner pointing at this file. The full `Why:` + `How to apply:` prose lives here so the rule body stays under the per-rule byte budget without losing context.

## The rule (canonical short form)

> Every plan touching production code or infra MUST declare a `## Observability` block with 5 fields (`liveness_signal`, `error_reporting`, `failure_modes`, `logs`, `discoverability_test`) and a `discoverability_test.command` that runs WITHOUT SSH. Pure-docs plans skip.

`[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]`

## Why

In #4116, the Better Stack heartbeat for the prod Inngest server stayed `down` for 16+ hours before the operator noticed — not because the heartbeat was hard to read, but because no plan-time gate had ever asked the question "if this silently stops working in production, what tells the operator WITHOUT requiring an SSH session?".

The systemic failure mode is identical across every "infra ships, sits on disk, nobody knows it broke" incident the project has seen:

1. A change lands.
2. A failure mode exists for that change that does NOT surface in the app's golden-path UI.
3. The operator only notices when a downstream user-facing artifact breaks days later (cron didn't run, daily-priorities email didn't send, learnings-decay didn't fire).
4. Recovery is hard because the symptom is detached from the root cause in time.

Asking "WITHOUT SSH" is the load-bearing constraint. SSH access to the prod host is a privileged escape hatch that should NEVER be in the critical path for "did this work?" — both because access drift makes it unreliable (firewall, key rotation, cloudflared tunnel state) and because it can't be exercised by a future Soleur user evaluating self-host viability.

## How to apply

At `/plan` Phase 2.9, **every** plan touching `apps/*/server/`, `apps/*/infra/`, `scripts/`, GHA workflows, supabase migrations, or any cron primitive (`pg_cron`, Inngest function, scheduled GHA) MUST include a `## Observability` block with this exact schema:

```markdown
## Observability

[skill-enforced: plan Phase 2.9 + deepen-plan Phase 4.7]

- **liveness_signal:** what is the persistent "I am alive" signal, and where does it surface (heartbeat URL, cron-monitor slug, Sentry transaction)?
- **error_reporting:** which path captures errors (Sentry project + DSN, Better Stack, Slack alert)?
- **failure_modes:** numbered list of the top 3-5 ways this change can fail and how each surfaces.
- **logs:** where do operator-readable logs live (file paths on host, log-aggregator queries, GHA workflow run UI)?
- **discoverability_test:**
  - `command:` a copy-pasteable command that an operator runs from their workstation (NO SSH) to confirm the change is alive.
  - `expected:` the output that means "alive."
```

The `discoverability_test.command` is the gate's load-bearing assertion. If it requires `ssh user@host`, `kubectl exec`, `doppler run` against a prod project, or any other privileged surface, the gate fails. Acceptable shapes: `curl https://<public-endpoint>`, `gh run list`, Better Stack public-status URL, `psql $READONLY_DATABASE_URL -c "<query>"` against a read-only role.

Pure-docs plans (e.g., `knowledge-base/*.md` only) skip the gate. Any plan whose `Files to Edit` includes a runtime surface does NOT skip.

## Cross-references

- Trigger PR: [#4116](https://github.com/jikig-ai/soleur/pull/4116) — Better Stack heartbeat wrap + plan observability gate; this rule was added as part of that PR.
- Sibling: `hr-no-dashboard-eyeball-pull-data-yourself` — companion principle that operator-side verification must be active-pull, not passive-eyeball.
- Sibling: `hr-ssh-diagnosis-verify-firewall` — when an investigation can ONLY happen via SSH, the firewall step makes the SSH path itself observable.

## Re-evaluation

This rule should be considered for retirement when a higher-level primitive (e.g., a `discoverability_test:` block in `spec.md` frontmatter parsed by a CI check) makes the plan-text declaration mechanical. Until then, the prose declaration is what makes the gate observable to reviewers.
