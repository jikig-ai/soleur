---
module: Soleur Plugin
date: 2026-09-14
problem_type: documentation_gap
component: documentation
symptoms:
  - "Operator could not determine whether the Soleur plugin runs in Devin Cloud sessions vs. Devin CLI only"
  - "All repo Devin docs (devin/INSTRUCTIONS.md, README, parity plan) cover the CLI surface only — zero cloud coverage"
  - "A domain-leader subagent reported a cloud-hooks claim that could not be verified against the live docs"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
status: open
synced_to: [brainstorm]
tags: [devin-cloud, plugin-surfaces, harness-parity, capability-matrix]
---

# Troubleshooting: Which Devin plugin surfaces actually load in cloud sessions

## Problem

Whether the Soleur Devin plugin supports sessions running on Devin Cloud (Cognition-managed VMs) rather than the local CLI was not answered anywhere in-repo; every Devin doc targeted the CLI. Resolving it required reading the vendor's plugin docs surface-by-surface and reconciling them against what Soleur depends on.

## Environment

- Module: Soleur Plugin (`plugins/soleur`, `.devin-plugin/plugin.json`)
- Affected Component: `devin/INSTRUCTIONS.md` compat layer, `devin/skills/{go,help,sync}` wrappers, `hooks/hooks.json`, `.devin/config.json`
- Date: 2026-09-14

## Symptoms

- "Does our plugin support Devin Cloud sessions?" had no answer in `devin/INSTRUCTIONS.md`, README, or any ADR/spec
- `devin plugins list` showed both a synced install (`soleur#plugins/soleur`) and a `--local` one — only the synced form reaches cloud sessions
- Devin docs are CLI-scoped; cloud behavior is stated per-surface in `extensibility/plugins/overview`, not in one matrix

## What Didn't Work

**Trusting a subagent's doc claim:** The CTO leader reported that live docs show plugin `command` hooks (PreToolUse/Stop) DO run in cloud, with only SessionStart/SessionEnd and prompt-type excluded. Re-fetching `docs.devin.ai/cli/extensibility/plugins/overview` showed it still says plugin hooks register "in local Devin sessions (the CLI and Devin Desktop)". The claim could not be verified — treated hooks as absent and parked the discrepancy in the brainstorm's Open Questions for the empirical probe (spec FR9).

## Solution

The verified surface matrix (docs.devin.ai, 2026-09-14):

| Surface | Cloud session |
|---|---|
| Plugin skills (`/soleur:*`) | Loads |
| Plugin `AGENTS.md` / `rules/` | Loads |
| Plugin MCP servers | Works; auth via web-app connection, not `devin mcp login` |
| Repo `.devin/config.json` `requiredPlugins` | Honored "from each cloned repository" |
| Plugin subagents (`agents/**/*.md`) | Absent — local CLI/Desktop only |
| Plugin hooks (`hooks.json` at plugin root) | Absent — local sessions only; fail-open |
| Repo-level hooks (`.devin/hooks.v1.json`, `.devin/config.json` hooks, `.claude/settings.json`) | Undocumented — the pivotal open question |

Consequences for Soleur: 66 agent definitions and all hook-enforced gates (rules-corpus injection, credential guard, `guardrails.sh`, `<promise>DONE</promise>` stop-gate) vanish in cloud; skills + rules + MCP survive. The designed answer is "Soleur Cloud Mode" — honest degradation with detection, disclosure, and ack-gates — spec'd at `knowledge-base/project/specs/feat-devin-cloud-session-parity/spec.md` (issue #8159, PR #8155).

## Why This Works

Devin's plugin doc states cross-surface support up front ("Plugins work across Devin cloud sessions, the Devin CLI, and Devin Desktop") but buries the per-surface caveats in the bullet list — read each bullet, not the headline. The correct verification loop for platform-capability claims: live-doc fetch per surface → reconcile against repo's own dependency inventory (`devin plugins list`, hook/agent counts) → flag anything undocumented as an empirical probe item, never an assumption.

## Prevention

- When answering "does harness X support Y", enumerate the plugin's own surfaces first (skills/rules/agents/hooks/MCP/requiredPlugins), then verify each against vendor docs — a single "plugins work in cloud" headline hides per-surface carve-outs.
- Treat a subagent's vendor-doc claim as a claim to re-derive; fetch the cited page yourself before letting it bound scope.
- Only `devin plugins install` (no `--local`) syncs to the personal manifest that cloud sessions read — `--local` installs never reach cloud.

## Session Errors

**Issue filing rejected twice by the user-impact gate**

- **Recovery:** `User-Impact:`/`Fix-Size:` lines were present (own lines, firm counts) but the gate still refused — it classified a plugin-gates/disclosure feature as verification machinery; filed successfully with `--label meta/machinery` (exit 1).
- **Prevention:** For brainstorm issues whose deliverable is itself gates/banners/ledgers for the plugin, default to `meta/machinery` rather than arguing exit-2 — "affects something a user receives" is judged narrowly for infra-surface features.

**Spec-template source had no spec.md**

- **Recovery:** `specs/feat-devin-plugin-parity/` contains only `tasks.md`; used `specs/review-workflow-hardening/spec.md` as the format reference.
- **Prevention:** When pulling a template, `ls` the directory first — spec dirs may carry only `tasks.md`/`session-state.md` (ADR-174 excludes them from INDEX too).

**Subagent-reported doc claim unverifiable** (see "What Didn't Work")

- **Recovery:** Treated as absent (conservative) + recorded as an explicit open question for empirical probe.
- **Prevention:** Same as Prevention bullet 2 — a leader's confident platform claim is a citation to check, not a fact to thread into scope.

## Related Issues

- Spec: `knowledge-base/project/specs/feat-devin-cloud-session-parity/spec.md` (issue #8159)
- Deferred: #8160 (upstream subagent/hook support), #8161 (personal-data cloud sessions pending Cognition DPA), #8162 (full-parity posture)
- Prior art: `knowledge-base/project/plans/2026-09-11-feat-devin-plugin-parity-plan.md` (CLI parity — shipped; cloud out of its scope)
