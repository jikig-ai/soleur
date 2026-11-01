---
title: Peer-Plugin Audit Log (non-audit outcomes)
last_updated: 2026-11-01
publishable: internal
---

# Peer-Plugin Audit Log (non-audit outcomes)

Part of the [Competitive Intelligence index](../competitive-intelligence.md). Dated record — index links are the live set; this shard is append-only.

Verification log for `soleur:competitive-analysis peer-plugin-audit` invocations whose target did NOT produce an Overlap Matrix row (per `peer-plugin-audit.md` §"Non-audit outcome").

## travisvn/awesome-claude-skills — 2026-05-15

- **Repo:** <https://github.com/travisvn/awesome-claude-skills>
- **License:** not detected (ports limited to methodology)
- **Stars / forks (at audit time):** 12,562 / 1,364
- **Auditor:** `soleur:competitive-analysis peer-plugin-audit`
- **Outcome:** **category mismatch; no audit produced.** Repo is an awesome-list (curated README of links) with zero `SKILL.md` files. The procedure's `Non-audit outcome` branch fired correctly (`peer-plugin-audit.md` §"Non-audit outcome"); no Overlap Matrix row added, no parallel file under `research/peer-plugin-audits/`.
- **Verification value:** confirms the sub-mode's error branch works against a non-skill-library target. Closes follow-through `#2749`.

## Prior intakes (moved from the index footer, 2026-10-24)

*Prior intakes preserved:* 2026-04-18 full Tier 0+3 scan; 2026-05-30 targeted Viktor addition (Tier 3, AlphaSignal brief, unverified); 2026-06-08 full six-tier scan + targeted NanoCorp reconciliation (Tier 3) — NanoCorp ads are "Coming Soon" not live, ARR figures contradictory; **2026-06-14 targeted Cofounder/cofounder.co addition (Tier 3, $8.7M USV seed, primary-source verified) — closest product match to date; no full rescan or specialist cascade this intake.*

## Scheduled scan (Tiers 0, 3) — 2026-11-01 (blocked)

- **Invocation:** automated scheduled `competitive-intelligence` run, Tiers 0 and 3, no interactive user.
- **Outcome:** **web research blocked; no competitor data verified.** The run's `cron-containment` PreToolUse hook rejected every `WebSearch` and `WebFetch` call with `tool class not permitted`. That covers about 25 attempts across the orchestrator and three parallel research subagents (Tier 0 platforms; Tier 3 autonomous-CaaS; Tier 3 orchestrators/platforms). Blocked targets included polsia.com, nanocorp.so, cofounder.co/pricing, soloceoai.com, tanka.ai, github.com/sankalpasawa/sutra, and the GitHub API pages for paperclipai/paperclip, multica-ai/multica, humanlayer/humanlayer and alirezarezvani/claude-skills. No agent fell back to `curl`/`gh api` via Bash, because the hook is a deliberate control and working around it would defeat it.
- **What the run did change (locally verifiable only):** index source-freshness ages recomputed (brand-guide.md 153 days, business-validation.md 146 days since `last_reviewed`); Recommendations P1 item 1 (b)–(f) marked done after checking business-validation.md; New Entrants reconciliation status added; data-freshness banners added to Tier 0 and Tier 3; a downstream-sync cascade run (see the index's Cascade Results).
- **What the run did NOT do:** change any overlap level, convergence-risk read, price, funding or traction figure; add new entrants; bump `last_reviewed`. **Do not read any Tier 0/3 row as "no change as of 2026-11-01".**
- **Follow-through:** allow `WebSearch`/`WebFetch` for this cron job (operator/config change), then re-run Tiers 0 and 3 without waiting for the next monthly slot.
