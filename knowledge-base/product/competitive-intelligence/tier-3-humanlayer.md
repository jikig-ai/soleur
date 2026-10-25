---
title: HumanLayer (humanlayer/humanlayer, “Riptide”) — Tier 3 detail
competitor: HumanLayer
tier: 3
last_updated: 2026-10-24
publishable: internal
---

# HumanLayer (humanlayer/humanlayer, “Riptide”) — Tier 3 detail

Part of the [Competitive Intelligence index](../competitive-intelligence.md). Dated record — index links are the live set; this shard is append-only.

## Targeted addition

**[2026-10-24 targeted addition — HumanLayer (humanlayer/humanlayer)]** Added a **peer-plugin audit + Tier 3 row** for **HumanLayer** ("Riptide" stack — multiplayer control plane for agent sessions; 12,344★; Apache-2.0 after an open→closed→open churn ending 2026-10-23). It is **not a skill-library peer and not a same-ICP threat**: the product is a daemon+Postgres-synced steering surface for Claude Code/Codex/OpenCode/Pi sessions sold to engineering leaders, while its shipped methodology (RPI → QRSPI) deliberately adds human gates — the opposite trajectory from Soleur's autonomy deepening. Audit verdict for the operator's three questions: (1) HumanLayer is better at multiplayer UX, session mobility, agent-agnostic mirroring, and distribution/narrative; Soleur is better at autonomy, enforcement, compounding memory, and org breadth — ~20–30% overlap, not a same-layer fight. (2) **Do not adopt the platform** — none of Soleur's differentiating machinery exists upstream, and Concierge-vs-riptide-cloud is a build-vs-buy trade that fails on license churn and a 2-founder team; extract mechanics instead (artifact comment queue, numbered-artifact precedence, `iterate-*` symmetry, `describe-pr` HTML tour; brainstorm the daemon-as-DB-reactor before any remote-runner work). (3) The gap to close is **narrative + packaging**, not capability — and BSL-1.1 already grants source visibility, so a license flip is a separate decision. Full audit: [audits/humanlayer-humanlayer.md](audits/humanlayer-humanlayer.md); targeted single-entry addition; `last_reviewed` left at 2026-07-04.

## Matrix detail (overlap-matrix Differentiation cell)

**Multiplayer control plane for coding-agent sessions** (12,344★; YC F24; >$3M raised). Per-host daemon launches Claude Code/Codex/OpenCode/Pi sessions as a Postgres-state reactor (Electric SQL → clients; zero inbound ports); desktop/web/mobile steering with teammate approvals; `automation run` ephemeral-daemon CI mode; `/hl:teleport` session migration; cross-agent mid-task handoff. RPI/QRSPI plugin (~22 skills) is explicitly **human-gated** — their own post-mortem moved them *toward* more HITL. Pricing: free ≤3 seats/200 sessions; **Pro $100/user/mo BYOK**; Enterprise (SSO, SOC 2, on-prem). License Apache-2.0 after open→closed→open churn; active dev may be in `humanlayer/synclayer`.

*(The live Convergence-risk read stays in the index matrix row.)*
