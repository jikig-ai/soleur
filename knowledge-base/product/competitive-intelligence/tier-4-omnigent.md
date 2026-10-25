---
title: Omnigent (omnigent-ai/omnigent) — Tier 4 detail
competitor: Omnigent
tier: 4
last_updated: 2026-10-24
publishable: internal
---

# Omnigent (omnigent-ai/omnigent) — Tier 4 detail

Part of the [Competitive Intelligence index](../competitive-intelligence.md). Dated record — index links are the live set; this shard is append-only.

## Targeted addition

**[2026-09-11 targeted addition — Omnigent (omnigent-ai/omnigent)]** Added a **Tier 4 watch** for **Omnigent**, an Apache-2.0 **alpha** Python meta-harness (~9.8k GitHub stars that day; HEAD `be5cae72d9a96ee2cd8ddf6bb6fb0c306f80387a`) that wraps Claude Code, Codex, Cursor, OpenCode, Hermes, Pi, Grok Build (ACP `grok agent stdio`), and Devin. Same *class* as Multica's 14-provider daemon (run existing CLIs) and CrewAI's DIY substrate (productized). **Not a same-ICP threat** — engineering-team switchboard, zero business-domain agents, not a CaaS. Operator-closed 2026-09-11: **watch-only**. Rejected: dogfood probe, Soleur-plugin port, Concierge runtime. **Do not add `"omnigent"` to `export type Harness`** in `plugins/soleur/lib/harness.ts` — it is a supervisor over Claude/Grok, not a third Skill/Task/slash surface. **Plugin-fit is false as a first-class Omnigent plugin** (no marketplace; stub `--plugin-dir` for YAML bundles only). Telemetry **on by default** from v0.6.0 ([their docs](https://omnigent.ai/docs/deploy/telemetry); ingest processor unnamed — blocker for any later dogfood). No battlecard, no comparison page, no specialist cascade. Full eval: [brainstorm](../../project/brainstorms/archive/20261013-051752-2026-09-11-omnigent-meta-harness-eval-brainstorm.md). Targeted single-entry addition; `last_reviewed` left at 2026-07-04 so this does not reset the full-scan clock.

## Matrix detail (overlap-matrix Differentiation cell)

Apache-2.0 **alpha** meta-harness (`omnigent-ai/omnigent`; ~9,844 stars / public repo on 2026-09-11; HEAD `be5cae72d9a96ee2cd8ddf6bb6fb0c306f80387a`). Wraps vendor CLIs (Claude Code native + SDK, Codex, Cursor, OpenCode, Hermes, Pi) and ACP rows (Grok Build = `grok agent stdio`, Devin). YAML agents, policies, bwrap/seatbelt, web/desktop/phone. **Grok is one catalog row, not a Soleur harness:** `--model` refused; `XAI_API_KEY` not in host-to-runner allowlist; auth is `grok login --device-auth` on disk. **No plugin marketplace.** YAML path writes a stub `.claude-plugin/plugin.json` (name+description) and passes `--plugin-dir` for that agent's `skills/`. `omnigent claude` with no bundle uses host `~/.claude` (piggyback possible; Omnigent then injects permission / `AskUserQuestion` / SessionStart hooks — collision with Soleur SessionStart, **not dogfooded**). Telemetry **on by default** from v0.6.0; opt-out `OMNIGENT_ANALYTICS=0` / `DO_NOT_TRACK=1` / `telemetry: false`; "no PII / no prompts" is **their claim**; ingest processor **unnamed** on the public telemetry page. License Apache-2.0 (theirs) vs BUSL-1.1 (ours) — two grants; do not infer compatibility from SPDX.

*(The live Convergence-risk read stays in the index matrix row.)*

## Tier-4 takeaway (recorded 2026-09-11)

**[2026-09-11] Omnigent is a productized meta-harness, not a CaaS and not a Soleur runtime.** Watch in this tier (CrewAI class) so the next session does not re-open a third `Harness` union member or a plugin port. Do not seat it in Tier 3 — that shelf is "runs your company" and would manufacture a substitution we refuse. Re-open triggers are in the row; star count is not one of them.
