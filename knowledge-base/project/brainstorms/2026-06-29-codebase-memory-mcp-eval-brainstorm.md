---
title: Evaluate codebase-memory-mcp for Soleur code/KB indexing
date: 2026-06-29
type: brainstorm
status: decided — defer (tracking issue #5708 filed)
tracking_issue: 5708
lane: cross-domain
brand_survival_threshold: single-user incident
external_tool: https://github.com/DeusData/codebase-memory-mcp
---

# Brainstorm: Adopt codebase-memory-mcp for Soleur?

## What We Evaluated

Whether Soleur should adopt **codebase-memory-mcp** (DeusData) — a local, MIT-licensed
MCP server that indexes a codebase into a persistent SQLite knowledge graph
(tree-sitter AST + call graphs + bundled local Nomic embeddings, 14 MCP tools,
claimed ~99% token reduction vs file-by-file grep) — to make Soleur agents find
information more efficiently. Three deployment axes were assessed separately:

- **Axis A** — operator dev loop (this Soleur monorepo).
- **Axis B** — Soleur Users' own connected repos (per-user workspace).
- **Axis C** — Soleur's markdown knowledge-base (learnings/ADRs/AGENTS.md).

## Verified Tool Facts (premise gate, Phase 1.0)

- MIT license; 20.9k★; single static C binary, zero runtime deps; distributed via npm/Homebrew/releases.
- **100% local** — no cloud, no API keys; bundled Nomic embeddings; "code never leaves machine" (claim, see Open Questions).
- True MCP server (passes the headless-MCP-first test-1 gate): `search_graph`, `trace_path`,
  `query_graph` (Cypher), `get_code_snippet`, `search_code`, `semantic_query` (vector),
  `get_architecture`, `detect_changes`, `manage_adr`, etc.
- Core competency is **code intelligence** (AST, call graph, symbol resolution, dead-code). Vector search is a secondary, generic capability.
- Index = local SQLite (`~/.cache`), optional committable `.codebase-memory/graph.db.zst` snapshot, background git-watcher re-indexes incrementally.

## Decision

**Defer the tool; pilot A + B later (tracking issue filed). Reject the tool for C; route C's underlying need to the existing pgvector Stage-3 track.**

| Axis | Verdict | Rationale |
|------|---------|-----------|
| A — operator monorepo | **Pilot later** | Strong fit (persistent disk, single trusted machine, large polyglot repo); cheap (one pinned `.mcp.json` entry). Best done as a *measurement probe* to produce token/latency evidence that gates B. Not urgent. |
| B — user connected repos | **Defer-with-trigger** | Promising but gated: (1) egress proof, (2) index-persistence across container re-provision, (3) demand evidence, (4) ICP fit. |
| C — KB markdown | **Reject this tool** | Code-graph value is inert on prose; only its generic vector search would apply. The real need is the already-scoped, ADR-gated **pgvector Stage-3** embeddings work (#4119/#4176/#4043), on Soleur's existing Supabase Postgres. |

## Why This Approach (YAGNI)

The cheap, low-risk win (Axis A) is decoupled from the expensive bets (B) and the
mis-scoped one (C). Axis A is the measurement vehicle: it generates the exact
token-COGS / latency evidence that would justify (or kill) Axis B, on the operator's
own trusted machine, before any user code is ever exposed to a third-party binary.

## Key Decisions

- **The tool does NOT address multi-turn "amnesia."** Its "memory" is a persistent *code index*, not conversational memory. The original amnesia P1 (#1044) is **CLOSED/Done**; the live adjacent work is durable session resume (#5240 + deferred #5273/#5274/#5275) — a session-persistence layer this tool doesn't touch. (Corrects a stale CPO citation of the 2026-03-23 roadmap review note at `roadmap.md:59`.)
- **C → pgvector, not this tool.** KB semantic search is a real, pre-validated gap, but its home is pgvector Stage-3 (ADR-gated), not a 158-language code engine.
- **Index-persistence path for B:** the tool's committable `graph.db.zst` snapshot is a natural fit for the ephemeral-container problem — commit/persist the index artifact so it survives workspace re-provision instead of cold-rebuilding (minutes of CPU × users × refreshes).
- **Pin, never `@latest`:** if piloted, pin an exact version (supply-chain: fast-moving C binary).

## Open Questions

1. **Egress claim (load-bearing, CLO condition b):** the "no outbound connections" claim must be *tested* — run a full index under network-egress monitoring (`tcpdump` / deny-all sandbox) and confirm zero outbound calls. Until proven, no user code touches it.
2. **Workspace persistence contradiction (hinge for B):** ADR-038 says user workspaces are logically durable (deleted only on account deletion), but `2026-06-12-resumability-claim-must-verify-workspace-lifecycle.md` says the *physical* container disk is re-provisioned and doesn't survive reconnect. A local SQLite index lives on the physical disk → needs the `graph.db.zst` persistence path or rebuild-on-provision. Confirm the real model before any B decision.
3. **bwrap / MCP-launch model:** Bash runs in a frozen-mount bwrap sandbox; an MCP server subprocess must run outside it (or via IPC). Confirm how the agent-runner would launch a per-workspace MCP server.
4. **Bundled-component licenses (CLO condition a):** 158 vendored tree-sitter grammars + the Nomic model carry their own licenses — verify none are non-permissive *before we redistribute* (clear if users self-install).
5. **Demand evidence:** does code-search grep materially dominate per-session token COGS / user-visible latency? Measure on Axis A first (empirical-demand gate, `2026-05-13-brainstorm-mcp-tier-classify-defer-when-empirical-demand-absent.md`).

## User-Brand Impact

- **Artifact:** a third-party code-indexing MCP server (`codebase-memory-mcp`) running in Soleur agent runtimes, potentially inside Soleur Users' workspaces indexing their private code.
- **Vector:** a user's private source code silently egressing to a third party if the "100% local" claim is false or regresses in a future version.
- **Threshold:** single-user incident.
- **Mitigation captured:** Open Question 1 (egress proof) is a hard gate before any user-facing (Axis B) adoption; pinned versions; operator-only pilot first.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Marketing/Operations/Sales/Finance/Support assessed as low-relevance (internal capability/infra adoption, not a customer-facing or positioning decision).

### Engineering (CTO)

**Summary:** Pilot A behind a flag (low risk); reject B until workspace persistence is confirmed (cold-start re-index cost is the blocker); reject C (code engine, 95% dead weight on prose). Biggest cross-cutting risk: a fast-moving C binary as an unpinned runtime dep in every user workspace.

### Product (CPO)

**Summary:** "Agents slow at finding info" is operator token-COGS, not user-felt pain; the evidenced user pain is session continuity, not search. Validated ICP today is *technical* founders. Pilot A as an experiment, defer B (needs repo-connect GA + a user with a non-trivial codebase), reject C. Measure before wiring.

### Legal (CLO)

**Summary:** Clear-with-conditions. MIT is fine (attribution only if *we* redistribute). No new sub-processor/GDPR obligation *if* the no-egress claim holds — and that claim must be tested (egress-monitored index run), which is the load-bearing brand-survival gate. Verify bundled grammar/model licenses before redistribution.
