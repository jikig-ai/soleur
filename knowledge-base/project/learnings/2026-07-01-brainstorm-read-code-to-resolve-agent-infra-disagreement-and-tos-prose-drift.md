# Learning: When two agents disagree on infra state, read the code — and a new feature can expose pre-existing prose/code drift

## Problem

During the #5767 L5 runaway-guard brainstorm, two research agents returned **contradicting claims about the
same subsystem**:

- The **CTO** (reading `_cron-claude-eval-substrate.ts`) asserted the web agent runs as one opaque
  `spawn(claude --print)` child with **no per-turn token hook** — so a token ceiling would be net-new and
  require stream-json plumbing.
- **repo-research** (reading `agent-on-spawn-requested.ts`) asserted a durable per-turn loop that **already**
  has a cost ceiling (`turn-${n}-precheck-cost-ceiling` vs `PER_SPAWN_COST_CEILING_CENTS`), a BYOK
  `killTripped` cap, and `LEADER_MAX_TURNS=8`.

Taking either summary at face value would have produced a wrong-premise spec: either "build a circuit breaker
from scratch" (ignoring shipped code) or "it's basically done" (ignoring the opaque cron surface).

Separately, the CLO assessment surfaced that **ToS §3a.5** ("The Web Platform does not include a
Jikigai-provided cost ceiling") was **already false in production** — the 260¢ per-spawn ceiling had shipped
before this feature was even planned.

## Solution

1. **The orchestrator read the code itself** (`agent-on-spawn-requested.ts:319-418`, `constants.ts:19-22`,
   `persistFailure` at `:913-961`, `docs/legal/terms-and-conditions.md` §3a.5) rather than adjudicating
   between the two agent summaries. The resolution: **both were right about DIFFERENT execution surfaces** —
   `agent-on-spawn-requested.ts` (the #5868 durable leader loop) and `_cron-claude-eval-substrate.ts` (the
   opaque heavy-cron substrate) are distinct runtimes with distinct guards. This reframed the feature from
   "build" to "extend + fill" **before** Phase 2 approach selection.
2. The ToS drift was recorded as a P0 amendment folded into the first PR (PR-A), framed as *fixing existing
   drift*, not *adding wording for new work*.

## Key Insight

- **Contradicting subagent infra-claims are a signal that the agents scoped different files, not that one
  lied.** When two agents disagree on whether a capability exists, the orchestrator must grep/read the
  concrete symbol itself; the truth is often "both, on different surfaces." This is the
  "reconcile fast-returning leader recommendations with later-arriving research findings" guidance in
  brainstorm Phase 1.1, extended to the case where *two research agents* (not leader-vs-research) conflict.
- **A new feature that adds or relies on a capability is a prompt to check whether prose already describes
  the OLD world.** ToS/policy/register prose drifts from shipped code silently; the feature that makes a
  capability prominent is the natural moment to catch the pre-existing lie. Always grep the governing prose
  (ToS section, ADR, Article 30 register) for the capability the feature touches, and check it against the
  current code — the amendment may be overdue, not new.

## Session Errors

1. **Two research agents returned contradicting infra-state claims.** Recovery: orchestrator read
   `agent-on-spawn-requested.ts` + `_cron-claude-eval-substrate.ts` + `constants.ts` directly to establish
   both surfaces exist. **Prevention:** brainstorm Phase 1.1 already prescribes verifying "is X
   mounted/wired?" claims by grepping the specific consuming symbol — this session confirms the rule extends
   to *inter-agent* contradiction, not just single-agent absence claims. No new rule needed; the existing
   guidance covers it.
2. **ToS §3a.5 already drifted from shipped code** (`PER_SPAWN_COST_CEILING_CENTS=260` contradicts "no
   Jikigai-provided cost ceiling"). Recovery: recorded as a PR-A amendment fixing existing drift.
   **Prevention:** when a feature touches a capability governed by ToS/register/ADR prose, grep that prose
   for the capability and diff against code before scoping — the fix may predate the feature.
3. **Scratchpad directory absent** — a `cat >` to the session scratchpad path failed. Recovery: `mkdir -p`.
   **Prevention:** one-off; `mkdir -p` the scratchpad before first write.

## Tags
category: workflow-patterns
module: brainstorm
