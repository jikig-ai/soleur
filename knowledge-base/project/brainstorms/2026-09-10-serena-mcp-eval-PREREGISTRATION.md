---
title: "Serena MCP evaluation — PRE-REGISTERED falsification criteria"
date: 2026-09-10
status: pre-registration (committed BEFORE any measurement)
lane: cross-domain
---

# Pre-registered falsification criteria — Serena MCP

Committed before any measurement was run. Operator-confirmed thresholds.
Fitting these after seeing data would defeat their purpose; this file is the
timestamped proof they were fixed first.

## Axis A — operator dev sessions (this monorepo, local Claude Code)

ADOPT only if ALL hold:

| # | Criterion | Threshold |
|---|---|---|
| A1 | Reachable surface: share of tool-result tokens in real local transcripts spent on code navigation Serena could replace (Read/Grep/Glob against CODE files, not prose) | **> 15%** |
| A2 | Measured token reduction on that slice, symbol-wise retrieval vs current grep+read | **> 25%** |
| A3 | Gate divergence: Serena retrieval must not become the evidence source for any grep-discharged gate (`hr-verify-repo-capability-claim-before-assert`, `hr-third-party-content-grep-on-undertaking`, `hr-type-widening-cross-consumer-grep`) | **zero** |

Rationale for A1's level: the Headroom evaluation (2026-09-07) died at a 2-3%
reachable surface. 15% asserts Serena must address a materially larger slice
than the tool we most recently rejected.

## Axis B — Soleur end users (server-side sandbox, BYOK per ADR-041)

ADOPT only if ALL hold:

| # | Criterion | Threshold |
|---|---|---|
| B1 | Egress: proven local-only under monitoring; AND the sandbox can install it within the ADR-052 egress allowlist | binary |
| B2 | Cold-start cost per workspace amortizes against measured per-workflow savings, using the cost instrumentation shipped in PR #7916 (migration 136) | net positive |
| B3 | Demand: evidence that code search is a felt user cost, not an assumed one | non-zero |

NOTE: users pay real money per token on their OWN Anthropic key. The operator's
flat-subscription "$0 marginal" fact does NOT transfer to this axis (the error
§1 of the Headroom record was corrected for).

## Axis C — knowledge-base markdown

Inherited from the 2026-06-29 codebase-memory-mcp evaluation: a code-symbol
engine is inert on prose. C is not a Serena question; the KB semantic-search
need routes to the pgvector track.

## Write tools — separate gate (operator decision, 2026-09-10)

Serena's editing tools (`replace_symbol_body`, `insert_before/after_symbol`,
rename, move, safe-delete) are evaluated but gated SEPARATELY from retrieval.
Read adoption does not imply write adoption.

| # | Criterion | Threshold |
|---|---|---|
| W1 | Every LSP-driven write site passes `hr-write-boundary-sentinel-sweep-all-write-sites` | all sites |
| W2 | Writes are observable (an edit made by Serena is attributable and reviewable) | binary |
