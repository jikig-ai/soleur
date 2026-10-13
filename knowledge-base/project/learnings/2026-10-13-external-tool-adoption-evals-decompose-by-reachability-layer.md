# Learning: external-tool adoption evals decompose by reachability layer — and prior evals carry the re-evaluation criteria

## Problem

An investigation of free-claude-code's "up to 90% lower token usage" stack (RTK
output filter + Headroom tool-result compressor + five aux-call "optimizations")
for possible adoption by Soleur. The pitch read as one question; it was actually
three, with different answers per mechanism.

## Solution

Decompose the vendor's bundle by **insertion layer** before any benefit analysis:

- **Proxy-layer mechanisms** (FCC's five aux-call mocks — quota probes, titles,
  suggestions, prefix detection, filepath extraction, verified in
  `api/optimization_handlers.py`) are unreachable from a plugin: a plugin sees
  tool-call lifecycle events, not provider API traffic. Worse, quota-probe mocking
  is circumvention-shaped on subscription auth and would falsify Soleur's
  published DPD clause if shipped in-plugin.
- **PostToolUse/tool-result compression** (Headroom) is unreachable for
  Bash/Read/Grep — only `updatedMCPToolOutput` exists, MCP-only. A prior measured
  eval had already decided no-build (244/581 payloads losing gate-relevant
  literals).
- **PreToolUse command rewriting + output filtering** (RTK) IS reachable — Soleur
  already ships the mechanic (`grep-rewrite.sh`, ADR-162). The one genuinely new
  surface; still needs a gate-literal divergence measurement before any
  "compatible" claim.

The same decomposition surfaced a defect independent of the adoption question:
`rtk` not being in `destructive-command-guard.sh`'s wrapper table is a live
bypass for users who install RTK on their own — evaluate third-party tools for
what they do to YOUR machinery even when you decide not to adopt them.

## Key Insight

1. **Vendor bundles are layer-heterogeneous.** "Can we use X?" is always N
   questions, one per insertion point. Reachability (proxy vs hook vs prompt
   layer) settles most of them before benefit analysis is worth running.
2. **Decided-no-build specs are the re-entry point, not a wall.** The archived
   Headroom spec's re-evaluation criteria (>15% AND zero divergence AND
   confinable) turned a would-be re-litigation into certify-and-scope — the new
   eval only had to cover what was genuinely new (RTK's deterministic filter
   shape). Re-deriving a measured verdict is the waste the criteria exist to
   prevent.
3. **"Up to 90%" was scoped to terminal-output tokens** — the vendor's own docs
   admit "90% of bash output is not 90% of your bill." Headline claims must be
   re-scoped to OUR traffic distribution (98.17% cache reads) before they mean
   anything.
4. **A defensive fix can be owed to users who adopt a tool you reject** — the
   guard bypass exists whether or not Soleur endorses RTK.

## Session Errors

- **CLO domain leader asserted "no root LICENSE file exists"** — refuted by
  `ls`/`git ls-tree` (LICENSE present on main). Recovery: orchestrator-side
  verification before weaving the claim into the brainstorm doc. Prevention:
  leader prompts should name which claims need orchestrator re-verification; the
  claim was recorded in the brainstorm's Session Errors so it cannot propagate.
- **Two `sed`-range fence extractions of `go.md` produced incomplete scripts**
  (unexpected EOF). Recovery: re-extracted with verified fence line numbers.
  Prevention: extract code fences by `grep -n '```'` anchors, not guessed ranges.
- **Guessed `plugins/soleur/hooks/grep-rewrite.sh`** — file lives in
  `.claude/hooks/`. Recovery: `find`. Prevention: locate before reading; repo has
  two hook homes (plugin-shipped vs repo-operator).

## Tags

category: workflow-patterns
module: brainstorm
related: [feat-headroom-token-compression-eval, ADR-162, ADR-264, #10230]

The layer-decomposition rule itself is extracted at `plugins/soleur/skills/brainstorm/references/external-platform-vendor-bundles.md` (brainstorm SKILL.md is at its byte ceiling — the pointer lives here).
