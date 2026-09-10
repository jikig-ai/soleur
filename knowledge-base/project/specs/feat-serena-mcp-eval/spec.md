---
title: "Serena MCP evaluation — decision record (no-build)"
feature: feat-serena-mcp-eval
date: 2026-09-10
status: decided-no-build
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-10-serena-mcp-eval-brainstorm.md
preregistration: knowledge-base/project/brainstorms/2026-09-10-serena-mcp-eval-PREREGISTRATION.md
tracking_issue: 5708
---

# Spec — Serena MCP evaluation (no-build outcome)

This spec records a **decision not to build**. There are no functional requirements,
because nothing is being implemented. It carries the lane and brand-survival threshold
forward per the brainstorm→plan contract, and fixes the re-evaluation criteria so a
future session certifies a trigger instead of re-deriving the analysis.

## Problem Statement

Determine whether Serena MCP (<https://github.com/oraios/serena>) — a semantic
code-retrieval and editing MCP server built on Language Server Protocol backends —
should be adopted for (a) Soleur's own development sessions and (b) Soleur end users.
Deferred to its own evaluation by the Headroom record's Key Decision #6.

## Outcome

**Not adopted, for either audience — on DIFFERENT grounds, and the two ground lists
must not be merged.**

- **Operator dev sessions:** rejected on a **measured** reachable surface.
  Pre-registered A1 threshold was >15% of tool-result bytes spent navigating code.
  Measured **5.86%**, and **11.16%** at a deliberately over-generous upper bound.
  Both bounds fail. A2 (reduction) was never measured — A1 settles it alone.
- **Soleur users:** rejected on **structural** grounds — three independent sandbox
  hard stops — plus zero demand evidence. Explicitly **NOT** rejected on cost:
  users run BYOK on their own Anthropic key (ADR-041), so token reduction is real
  money to them. The operator's flat-subscription economics do not transfer.

**Why the separation is the point:** the Headroom record had to be corrected for
exactly this error, extending an operator-side "$0 marginal" fact onto the user half.
The Serena user-half rejection stands on the sandbox blockers and the write boundary,
never on economics.

## Non-Goals

- Vendoring Serena source into this repo.
- Publishing any container image with `serena-agent` or fetched LSP artifacts baked in
  (that is conveyance, and Serena ships no `NOTICE`/`THIRD_PARTY_NOTICES`).
- Adopting Serena's memories/onboarding, in any pilot.
- Re-evaluating pgvector Stage 3 (separable, ADR-gated).
- Adding Oraios to the Article 30 sub-processor table (would over-claim; PA-2 governs).

## Decisions carried forward

| # | Decision |
|---|---|
| 1 | No adoption for operator dev sessions (A1 failed at both bounds). |
| 2 | No adoption for Soleur users (B1 structural, B3 demand absent). |
| 3 | Write tools rejected on an **independent** gate — stands even if Axis A is later reversed. |
| 4 | Serena memories/onboarding never adopted (competes with the git-tracked KB moat). |
| 5 | Migration 136 is not a usable baseline for this question (tenant-side, conversation-grain). |
| 6 | This record tracks **#5708**; it does not supersede it and does not open a parallel track. |

## Re-evaluation criteria

Reproduced from the brainstorm so a future session can execute rather than re-derive.
**ALL must hold within an axis.**

**Axis A:** non-test application code exceeds 25% of tracked lines (today ~8%), OR a
re-run of A1 exceeds 15% at the *lower* bound; AND a pilot shows ≥20% per-task token
reduction with zero divergence on `file:line` citations, rule-id anchors, and
`eval-gate:block` markers.

**Axis B:** tool- or turn-grain token attribution exists (today an explicit ADR-209
non-goal); AND ≥3 Phase-4 founders run non-trivial repos **on the sandbox**; AND #1443
exit interviews name search cost or latency unprompted; AND the sandbox gains a Python
runtime plus an egress posture permitting the install — itself an ADR-052 weakening
requiring its own ADR.

Axis B must be measured **on the sandbox**, never inherited from operator transcripts.

## Conditions that apply if ever reopened

From the CLO assessment, recorded so they are not re-derived:

1. Block egress to `oraios-software.de` (silently-failing news beacon in
   `src/serena/dashboard.py`); test that it fails closed.
2. Allowlist enabled language servers. **Java and Terraform stay off** pending
   verification of the bundled JRE 21 and `terraform-ls` (HashiCorp BUSL) licenses.
3. Pin to an exact version + hash; re-verify egress hosts and LSP set on every bump.
   There is no `SECURITY.md` (404, definitive), so there is no disclosure channel.
4. `.serena/` gitignored, never committed to a user's repo, cleaned with the workspace.
5. Serena would be the **first non-`http` `mcpServers` entry** and the first executed
   code in the plugin — a different review class than the four vendor-operated URLs.

## Verification

No implementation to verify. The evidence backing this record:

- Pre-registration committed at `f2b04cabb`, **before** any measurement.
- A1 measurement scaffold committed under
  `knowledge-base/project/specs/feat-serena-mcp-eval/measurement/`, including the
  known-broken v1 retained as the error record.
- Both instruments validated against synthesized known-positive and known-negative
  fixtures before their output was trusted.
