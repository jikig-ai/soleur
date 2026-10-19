# Learning: a presence pin on a paragraph's lead-in survives the paragraph being gutted

## Problem

#10499 added a final-report decision check and a seat-dissent rule as short prose paragraphs in `review/SKILL.md` and
`work/SKILL.md`, with a drift pin in `components.test.ts`. The plan's Guard Contract pinned each paragraph by its bold
lead-in (`**Final-report decision check`, `**Seat dissent from a ruling.**`). The author's own mutation battery (delete
the paragraph, rename the heading, revert item 4) reported every row RED. The test-design seat then replaced the body
after the lead-in with `TODO` and wrapped a paragraph in an HTML comment: both stayed green.

## Solution

- Pin the LOAD-BEARING CLAUSE, not the lead-in: the link plus the section pointer and the "only X stays" clause, and the
  "never to the operator" tail of the dissent rule.
- Strip fenced blocks and HTML comments from the text before matching, with a self-test row proving a fenced and a
  commented anchor are rejected and a re-flowed one is accepted.
- Pin the reference-side labels (`**8.1`, `**8.2`) the skills cite, so a pointer cannot dangle under a green test.
- A discoverability command in a plan (`grep -c '<phrase>'`) must carry the same `**` anchor as the pin, or a later
  sentence that merely names the phrase changes its count.

The same panel found the substantive gap the prose created: a new intake of "recorded rulings" read PR-body and
untracked-file text with no provenance, so a forged `Ruled by CTO agent` line could suppress a finding. Label each
line's source, gate PR-body lines on the author's `author_association`, and tell the owner the ruling is unverified
context.

## Key Insight

A presence pin proves a heading survived, not that the rule did. For prose rules the only mechanical guard is a pin, so
choose anchors by asking "what edit keeps this anchor and removes the rule?", and mutate by gutting the body, not only
by deleting the anchor.

## Session Errors

1. **Lead-in anchors in the Guard Contract** - Recovery: lengthened anchors, stripped fences/comments, 10 pairs -
   **Prevention:** plan Sharp Edges bullet (routed).
2. **Discoverability command counted a second mention** - Recovery: `**`-anchored command - **Prevention:** same bullet.
3. **Ruling intake without provenance** - Recovery: source labels + association gate in delegation 8.2.1 -
   **Prevention:** review of any intake of text from the artifact under review asks who wrote it.
4. **`emit-review-trailer.sh --risk-tier` rejected free text** - Recovery: used `none` - **Prevention:** read the
   script's usage line before passing a descriptive value.
5. **Planning subagent skipped plan-review and the full deepen fan-out; one `gh issue create` blocked for a missing label**
   - Recovery: disclosed in the plan, retried with `meta/machinery` - **Prevention:** none needed (disclosed scope choice).

## Tags

category: workflow-patterns
module: plugins/soleur/skills/review, work, brainstorm-techniques
