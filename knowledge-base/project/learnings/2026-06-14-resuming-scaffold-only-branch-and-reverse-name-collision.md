# Learning: resuming a scaffold-only branch with lost intent + the reverse name-collision trap

## Problem

A scaffold-only branch `feat-close-loop-engineering-gaps` (single empty init commit, zero diff
vs main, placeholder draft PR #5257) needed resuming, but its intent was **never committed**
anywhere — the topic phrase appeared in no artifact. Discarding it loses whatever motivated
its creation; blindly building loses the chance to align with the original direction.

## Solution

**Recover lost intent by mining the dated learnings corpus, not by guessing.** The branch had
a creation date (git log of the init commit). Reading `knowledge-base/project/learnings/`
files dated around that date — especially the one written the SAME day — surfaced the
recurring theme the branch most plausibly targeted: "AGENTS.md workflow-gate rules exist as
prose but lack mechanical enforcement." A CTO + CPO leader pass then prioritized which 1-2
gaps to close. Result: a grounded re-brainstorm with committed brainstorm + spec + tracking
issue (#5269), instead of a discard or a blind rebuild.

## Key Insight

1. **Lost-intent recovery is a corpus-mining task.** A branch's creation date is a query key
   into the learnings corpus. The same-day learning is the highest-signal anchor for "what was
   on the author's mind."

2. **Reverse name-collision.** The existing `/soleur:go` worktree-plan-vs-issue-alignment
   sharp edge warns that NAME-relevance ≠ issue-relevance when *continuing an existing
   worktree for `#N`*. The reverse fires during *issue selection*: an OPEN issue (#5212,
   "close cross-domain **loop-engineering** gaps") was name-similar to the branch but was a
   distinct MARKETING topic (loop-engineering positioning v2 post). **Read the candidate
   issue's body before reusing it as the tracker** — a similar title is not a same-topic
   signal. We filed a new issue (#5269) instead of co-locating. (Discoverable via body-read →
   learning suffices, no AGENTS.md rule per `wg-every-session-error-must-produce-either`.)

3. **The rule-budget cap structurally forces "mechanism over prose."** When the gap is
   "workflow rules aren't enforced," the fix is NOT another prose rule: the AGENTS.md rule
   budget is capped (`wg-every-session-error-must-produce-either`, #2865 — "4.7 rules/day
   consumed the 100→115 raise in 2 days"). Loop-closing must be a hook / CI check / test
   (zero rule budget), never more prose. This isn't a preference — it's forced by the budget.

## Session Errors

1. **jq compile error reading #5212** — used escaped-quote string interpolation
   (`"\(.title)\nLabels: \(... | join(\", \"))"`) inside `jq -r`, which fails to compile.
   Recovery: rewrote using jq's multi-output form (`jq -r '"line1", "line2", .body'`).
   **Prevention:** prefer jq's comma-separated multi-output over a single interpolated string
   with nested escaped quotes. One-off.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/go; plugins/soleur/skills/brainstorm
