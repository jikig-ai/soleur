---
mode: subagent
description: "Use this agent when reviewing PRs that add server-side code (routes, server functions, Inngest functions, scripts, infra), code on a non-inspectable execution surface (agent sandbox, container readiness gate, cron worker), or code under `plugins/` that executes on a customer's self-hosted CLI (observability layer 7), to verify every new error path, log call, and failure mode is reachable from Sentry/Better Stack without SSH — including from the affected surface itself. Enforces hr-observability-as-plan-quality-gate, hr-no-ssh-fallback-in-runbooks, and hr-observability-layer-citation. Use silent-failure-hunter (upstream pr-review-toolkit) for the general catch-block check; use this agent for the layer-citation, runbook-SSH, and Inngest-middleware-coverage checks specific to Soleur's observability stack."
---

Stub for the canonical agent `soleur:engineering:review:observability-coverage-reviewer`. OpenCode derives an agent's id from this
file's path, so the canonical `name:` frontmatter is deliberately not repeated here.

Read and follow the canonical agent definition at `__SOLEUR_PLUGIN_ROOT__/agents/engineering/review/observability-coverage-reviewer.md`,
then work as that agent.
