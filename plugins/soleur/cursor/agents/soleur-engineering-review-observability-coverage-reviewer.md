---
name: soleur-engineering-review-observability-coverage-reviewer
description: "Use this agent when reviewing PRs that add server-side code (routes, server functions, Inngest functions, scripts, infra), code on a non-inspectable execution surface (agent sandbox, container readiness gate, cron worker), or code under `plugins/` that executes on a customer's self-hosted CLI (observability layer 7), to verify every new error path, log call, and failure mode is reachable from Sentry/Better Stack without SSH — including from the affected surface itself. Enforces hr-observability-as-plan-quality-gate, hr-no-ssh-fallback-in-runbooks, and hr-observability-layer-citation. Use silent-failure-hunter (upstream pr-review-toolkit) for the general catch-block check; use this agent for the layer-citation, runbook-SSH, and Inngest-middleware-coverage checks specific to Soleur's observability stack."
---

On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop.

Read `agents/engineering/review/observability-coverage-reviewer.md`, relative to the plugin root.
