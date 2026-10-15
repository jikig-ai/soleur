# Learning: residual-bundle brainstorms rule technical forks via the CTO and present only authorization to the operator; stacked PRs are not "one PR"

## Problem

Issue #10117 bundled four test-machinery residuals ("covers() tail-blindness, root-anchored
grammar, --paths normalization, census-predicate tightening"), each described in its body as "a
design cycle, not an inline edit." Two friction points surfaced in the session:

1. Which design to take per item was genuinely contested (the issue itself named two candidate
   fixes for `covers()` and flagged the grammar extension as architectural).
2. The operator, asked to choose packaging, proposed a third option not offered: "would a stacked
   PR allow for one PR but alleviate the review-complexity concern?"

## Solution

- Spawned the CPO+CLO+CTO triad (user-brand-critical default) plus repo-research and
  learnings-research in one batch. The CTO returned per-item rulings (matchability witness for the
  census predicate, `_affected_normpath` reuse for `--paths`, enumerate-with-all-containment for
  `covers()`, detection-row-not-grammar for the root-anchor gap). Per
  `hr-technical-fork-is-not-an-operator-question`, the operator was then asked only the
  authorization: "authorize this full scope?" — not "pick a design."
- On the stacked-PR question, answered with the mechanism rather than the label: a stack is two
  PRs plus a merge-order dependency; it pays off only when the upper diff is unreadable without the
  lower. Here the items touch disjoint files, so independent PRs strictly dominate, and
  review-by-commit is the option that actually preserves a single review surface. Operator chose
  two independent PRs.

## Key Insight

- A "residuals bundle" issue is already triaged design work — the brainstorm's deliverable is
  *rulings + authorization + sequencing*, not a fresh option menu. The CTO assessment pattern
  (verify code facts, rule each item, recommend sequencing by blast radius) collapses four
  "design cycles" into one short session.
- When an operator proposes a packaging mechanism you did not offer, evaluate it on what it
  *mechanically is* (stack = ordered PR chain), not on the name. Stacking answers "the second diff
  needs the first to review cleanly"; it does not answer "I want fewer review surfaces."
- Latent-vs-live measurement settled the biggest fork: `git ls-files | grep -cE '^[^/]+\.(test\.sh|sh)$'`
  → 0 plus `SUITE_GLOBS` non-discovery made "detection row now, grammar on trigger" the obvious
  ruling — the gap's *cost model* changed once the corpus was measured empty.

## Session Errors

1. **`VAR=x cmd "$VAR/path"` does not expand** — the roadmap-reconcile call assigned
   `CLAUDE_PLUGIN_ROOT` inline and referenced `$CLAUDE_PLUGIN_ROOT` in the same command's
   arguments, which expand before the assignment takes effect
   (`bash: /skills/product-roadmap/scripts/roadmap-reconcile.sh: No such file`).
   **Prevention:** when a doc says "set CLAUDE_PLUGIN_ROOT for that command," either export it in a
   prior call or interpolate the literal resolved path — never same-line.
2. **`get_output` called with a non-schema field** (`command`) — rejected at validation, retried
   with `shell_id` only.
   **Prevention:** `get_output` polls by `shell_id`; the `sleep` goes in a separate `exec` call or
   the `timeout` parameter does the waiting.

## Tags

category: workflow-patterns
module: soleur-plugin / affected-test-machinery
