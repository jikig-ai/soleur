---
title: "Sporadic cron egress drops were the substrate's own plugin-MCP auto-connect + CC telemetry — silence at source, don't allowlist"
date: 2026-06-29
issue: 5691
pr: 5700
tags: [cron, egress, mcp, claude-code, observability, adr-052]
category: bug-fixes
---

# Cron egress drops to un-enumerated MCP/telemetry hosts: the dialer was the substrate, not a cron's prompt

## Symptom

After #5676 silenced the dominant intended drop (the `npx` → `registry.npmjs.org`
registry-metadata probe), the single grouped `op=egress_blocked` Sentry issue
(`126858085`) still showed **sporadic, low-volume** drops to un-enumerated hosts:
`mcp.vercel.com` (3), `mcp.cloudflare.com` (2), `mcp.stripe.com` (1), and a
GCP global-LB serving a Datadog `us5` *default* vhost `34.149.66.137` (21).

## Root cause (static trace, no SSH)

The dialer is **the claude-eval cron substrate itself**, not any cron's
prompt or tool grant:

- Every claude-eval cron spawns `claude --print --plugin-dir plugins/soleur …`.
- `--plugin-dir plugins/soleur` loads `plugins/soleur/.claude-plugin/plugin.json`,
  whose `mcpServers` block bundles **four remote HTTP MCP servers** — `context7`
  (`mcp.context7.com`), `cloudflare`, `vercel`, `stripe`.
- Claude Code **connects plugin MCP servers automatically at startup**. That
  startup handshake IS the egress dial.
- The dials are **non-essential by construction**: the containment hook
  (`buildCronEvalSettings`, relax-minimal) denies every `mcp__*` tool —
  `CRON_MCP_ALLOWLISTS` grants Playwright to `cron-ux-audit` ONLY. No cron may
  use the cloudflare/vercel/stripe/context7 tools, so the connections are pure
  startup overhead the firewall correctly drops.

The `34.149.66.137` Datadog-vhost host is a **default cert on a shared GCP
global-LB → NOT proof of the customer** (the app's own Sentry ingest
`34.160.81.0` is never in the blocked set, so there is no blackholed-observability
hole). Most plausible dialer: Claude Code's own non-essential outbound traffic
(telemetry/error-reporting/auto-update) or the `context7` MCP backend.

## Fix: silence at source, keep blocked (ADR-052 boundary preserved)

No allowlist or CIDR widened — that would reverse ADR-052's default-drop for
zero benefit (the tools are denied anyway). Two levers, injected at the
`spawnClaudeEval` chokepoint (covers all 15 substrate callers):

1. **`--strict-mcp-config`** prepended at argv index 0 (BEFORE `--print`, so it
   can never land after a trailing `--` prompt separator) → the CLI ignores the
   plugin-bundled MCP servers. `cron-ux-audit` re-supplies ONLY its Playwright
   server via `--mcp-config .mcp.json` (relative path resolves to the per-fire
   overlay it writes into `spawnCwd`, not the repo-root dev file).
2. **`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`** in the spawn env → kills CC's
   own non-essential traffic.

The two inline-spawn crons (`cron-daily-triage`, `cron-follow-through-monitor`)
do **not** route through `spawnClaudeEval` and pass no `--plugin-dir`, so they
make no MCP dial — for them the telemetry env is the load-bearing fix and
`--strict-mcp-config` is defensive belt-and-suspenders.

## Why spike-gated

`--strict-mcp-config` suppressing **plugin-bundled** MCP servers (vs only
project/user scope) is **undocumented**. The load-bearing proof is a
deterministic `--debug-file` trace, NOT a post-merge production-absence
inference (the drops are vol 1–3 sporadic, so an absence window shorter than the
natural inter-arrival gap cannot *confirm* removal):

- **Contrast (no strict):** `--plugin-dir plugins/soleur --debug-file …` →
  debug log shows `mcp.cloudflare.com` + `mcp.context7.com` connect attempts.
- **Spike A (strict):** add `--strict-mcp-config` → **zero** plugin-MCP host
  lines, and the `ux-audit` skill + `ux-design-lead` sub-agent still resolve.
- **Spike B (strict + `--mcp-config .mcp.json`):** Playwright present, four
  plugin hosts absent.

## Gotchas

- **`--debug` alone emits nothing in `--print` mode** — debug logs do not reach
  stdout/stderr. Use `--debug-file <path>` to capture them; that is what makes the
  zero-connect assertion provable.
- **`--allowedTools` is variadic and eats the prompt** — a bare
  `claude --print --allowedTools Skill "prompt"` fails with "Input must be
  provided…" because `Skill` consumes `"prompt"` as a tool name. Put `--` before
  the positional prompt (the same end-of-options marker the crons' `CLAUDE_CODE_FLAGS`
  already end with).
- **The headline failure mode is SILENT.** If `cron-ux-audit` lost Playwright
  under strict mode it would post a zero-screenshot exit-0 GREEN liveness
  check-in — the runtime Sentry Crons monitor is liveness-only and cannot catch
  it. The guard is therefore entirely **pre-merge** (Spike B + the
  `cron-ux-audit.ts` `--mcp-config` parity test), never a runtime monitor.

## Durable guard

A structural drift invariant (`cron-claude-eval-mcp-flags.test.ts`) asserts
`resolveClaudeBin()` is referenced ONLY in the substrate + the 2 known inline
crons — a NEW inline claude-spawner trips it, forcing the author to route through
`spawnClaudeEval` (auto-inherits the flag+env) or carry the flag+env explicitly.
The real fix (migrating the 2 inline crons onto the chokepoint) is filed as a
follow-up.
