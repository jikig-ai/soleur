---
title: Multica (multica-ai/multica) — Tier 3 detail
competitor: Multica
tier: 3
last_updated: 2026-10-24
publishable: internal
---

# Multica (multica-ai/multica) — Tier 3 detail

Part of the [Competitive Intelligence index](../competitive-intelligence.md). Dated record — index links are the live set; this shard is append-only.

## Targeted addition

**[2026-07-04 targeted addition — Multica (multica-ai/multica)]** Added the tier's clearest **design-donor**: **Multica**, "the open-source managed agents platform" (**~39k GitHub stars**; Go backend + Next.js 16 + Postgres 17; a local daemon runs 14 coding CLIs on the user's *own* machine — the server never touches the LLM). Multica is **not a same-ICP threat** — it targets **engineering teams** and ships **zero business-domain agents** (no finance/legal/marketing/sales/support) — but its product primitives are the most directly adaptable surfaced to date, and at 39k stars it hard-validates the "agents as first-class teammates" thesis via a **polymorphic actor model** (`actor_type ∈ {member, agent}`) on a Linear-style board. Five adaptable gaps feed the **2026-07-04 three-tier Multica-adaptation brainstorm**: (1) agents-as-*visible*-teammates on the workstream board — Soleur's 68 domain agents are invisible chat-routers today; (2) an **Autopilot** primitive (concurrency policy + run-ledger + templates; extends routines/[#4674]); (3) a **severity-ranked Inbox** + task-completion push (extends [#4673]); (4) **(agent, work-item) session resumption**; (5) **auditable leader-routed Squads**. Out of scope by design: Multica's 14-provider daemon fleet and iOS client (chasing them dilutes Soleur's Claude-native vertical depth). License is **"Other"** — adapt designs, not source. Targeted single-competitor addition (no full six-tier rescan / specialist cascade); the next full scan remains 2026-07-08.

## Matrix detail (overlap-matrix Differentiation cell)

**The open-source "managed agents platform" — the multiplayer agent-ops layer Soleur is not.** `multica-ai/multica`, **~39k GitHub stars**; Go (Chi + sqlc + pgx) backend + Next.js 16 + Postgres 17; a **local daemon runs the agent CLIs on the user's own machine — the server never touches the LLM**. Tagline "Your next 10 hires won't be human." **Vendor-neutral: 14 coding CLIs** (Claude Code, Codex, Copilot, Cursor, Gemini, OpenCode, OpenClaw, Hermes, Pi, Kimi, Kiro, Antigravity, Qoder, Trae). Core design = **polymorphic actor model** (`actor_type ∈ {member, agent}`) so agents are first-class assignees/commenters/creators on a **Linear-style issue board** (timeline, reactions, subscriptions). Distinct primitives: **Squads** (leader-agent routes to the right member; task-scoped `mat_` tokens + `is_leader_task` anti-self-loop guards), **Autopilots** (cron/webhook/manual × `create_issue`|`run_only` × concurrency `skip|queue|replace` + run-ledger provenance + templates: bug-triage / weekly-report / security-scan), **severity-ranked Inbox** (`action_required|attention|info` + real-time task-completion push; agents can have inboxes), **session resumption** keyed on (agent, issue) w/ artifact-only GC, **Skills** as static markdown injected into provider-native paths + content-addressed bundle cache + import from clawhub/skills.sh/github, **Channels** (Slack/Lark inbound = session), **Composio** MCP overlay, GitHub App. Clients: **web + Electron desktop + iOS**. Business model: **usage-credit** (Stripe prepaid micro-credits) on Multica Cloud + open-source self-host (analytics off by default). **License: "Other" — review before reusing any source.**

*(The live Convergence-risk read stays in the index matrix row.)*

## Tier-3 takeaway (recorded 2026-07-04)

**[2026-07-04] Multica (multica-ai/multica, ~39k stars) is the tier's strongest design-donor, not a same-ICP threat.** It is engineering-team agent-ops — a Linear-style board where agents are polymorphic first-class teammates — with **no business-domain agents**, so its ICP is the opposite of Soleur's non-technical solo founder; treat it like Paperclip/Viktor (category validator + primitive donor, not a feature fight). Its adaptable primitives are the highest-leverage steal surfaced to date and map onto Soleur's **existing** hosted Command Center: agents-as-visible-teammates on the workstream board (Soleur's 68 domain agents are invisible chat-routers), the Autopilot primitive (concurrency policy + run-ledger + templates), a severity-ranked Inbox with task-completion push, (agent, work-item) session resumption, and auditable leader-routed Squads — all being worked in the 2026-07-04 three-tier Multica-adaptation brainstorm. Deliberately **out of scope**: 14-provider runtime/daemon breadth and the iOS client (chasing them dilutes Soleur's Claude-native vertical depth). License is **"Other"** — adapt designs, do not copy source.
