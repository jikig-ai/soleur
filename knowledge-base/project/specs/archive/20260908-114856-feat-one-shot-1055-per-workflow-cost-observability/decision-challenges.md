# Decision Challenges — feat-one-shot-1055-per-workflow-cost-observability

Written at plan time by `soleur:plan` running headless inside a `/soleur:one-shot`
pipeline. Per ADR-084 and `plan/SKILL.md` §4.5, a **User-Challenge** — a finding that the
operator's *stated direction* should change — is never silently applied in headless mode.
It is persisted here for `/ship` to render into the PR body and file as an
`action-required` issue.

Plan: `knowledge-base/project/plans/2026-09-07-feat-per-workflow-agent-cost-observability-plan.md`

---

## UC-1 — This PR should not close #1055

**Operator's stated direction.** The pipeline was dispatched as
"#1055 — implement per-workflow / **per-agent** LLM cost observability", framing both
dimensions as the gap to close.

**The challenge.** Per-agent is not delivered, and at subagent grain it is not
deliverable from the frame that carries the money. `SDKResultMessage` — the only frame
with `total_cost_usd` — has no agent identity and no `parent_tool_use_id`:

```
awk '/^export declare type SDKResultSuccess = \{/,/^\};/' \
  apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts \
  | grep -ciE 'agent|subagent|parent_tool_use_id' || true
→ 0
```

At *leader* grain the dimension is degenerate on the dominant path: `cc-dispatcher.ts:4108`
passes the constant `CC_ROUTER_LEADER_ID` (`"cc_router"`), so a GROUP BY on it yields one
non-trivial group. Both the CTO and the CPO reached this conclusion independently and
both recommended against auto-closing the issue.

**What the plan does instead.** The PR body uses `Ref #1055`. A successor issue scoped to
per-agent attribution is filed at Phase 6 with a concrete re-evaluation trigger, and
Issue #1055 closes when that lands.

**Cost of the alternative.** `Closes #1055` would assert that "which agents consume the
most tokens" was answered. It was not.

---

## UC-2 — The primary cut may be domain, not workflow

**Operator's stated direction.** The issue title and the dispatch both name *workflow* as
the dimension to add.

**The challenge (CPO).** For a non-technical solo founder, "brainstorm vs review" is not a
mental model they hold; "Marketing $2.10 · Engineering $1.80 · Legal $0.40" is, and it is
the brand thesis rendered as a receipt. The CPO recommends the domain breakdown visible by
default with the workflow breakdown behind a disclosure — same query, better altitude —
and notes the domain cut is also what instruments Pricing Gate #2 and issue #1442.

**The counter (CTO A2).** `conversations.domain_leader` is the constant `cc_router` on the
dominant cc-soleur-go path, so a domain GROUP BY may return one non-trivial group and a
column of identical values.

**Why this is not resolved in the plan.** The two assessments are not reconcilable from
the code alone — they disagree about what the *data* looks like, not about what is
desirable. Plan Phase 0.3 runs the deciding query against dev
(`GROUP BY domain_leader` over costed conversations) before any code is written. The
measurement settles it; this entry records that the question was asked and by whom, so the
operator can overrule the measurement if the product judgment should outrank it.

---

## UC-3 — #1055's milestone and priority look wrong

**Operator's stated direction.** #1055 sits in milestone **Post-MVP / Later** (#6) with
`priority/p3-low` and `domain/engineering`, and the plan does not change them.

**The challenge (CPO).** The `domain_leader` cost cut directly instruments the **Pricing
Gate #2** criterion ("Multi-domain validation: 5+ users engaged with 2+ non-engineering domains") and
feeds issue **#1442** (Phase 4.4, 2-week unassisted usage tracking, `p1-high`, OPEN).
Recommendation: move to Phase 4, `priority/p2-medium`, add `domain/product`. Separately,
`#1055` appears nowhere in `knowledge-base/product/roadmap.md`, and
`wg-every-feature-listed-in-a-roadmap-phase` cuts both ways — if it ships, it needs a row.

**Why this is not applied.** Re-milestoning and re-prioritising an issue is a PM decision
about the operator's own roadmap, not a technical fork. `hr-technical-fork-is-not-an-operator-question`
draws the line the other way round: this one genuinely is the operator's call.

---

## UC-4 — The highest-value fix on this surface is not this feature

**The challenge (spec-flow-analyzer).** The existing usage rows carry no title and no
link, so after reading "Reviewing the code — $18.40" the user's next question — "*which*
review?" — has no answer. spec-flow calls linking each usage row to its conversation
"the single highest-value flow fix on this surface", and notes that adding a workflow
label makes each row wider without making it identifiable.

**Why this is not in scope.** It is a different feature on the same component, and folding
it in would widen a `single-user incident`-threshold money surface for a reason unrelated
to #1055. Raised here rather than filed, so the operator decides whether it deserves its
own issue rather than the plan quietly inflating its own scope.

---

## UC-5 — Two labels a founder is likely to conflate

**The challenge (ux-design-lead).** `one-shot` and `work` both mean "Claude wrote code" to
a non-technical reader. They are distinguishable in principle — one-shot runs the whole arc
unattended, work executes an already-approved plan — but the design lead flags that merging
them costs one bucket of resolution and buys clarity.

**The copywriter's position.** Keep them separate, and label `one-shot` **"Idea to
shipped"** rather than anything ship-shaped: one-shot is the whole plan→work→review→ship
pipeline in one dispatch, so it will usually be the *largest* bucket, and giving the
biggest number the smallest-sounding verb phrase misinforms.

**Disposition.** The plan follows the copywriter (the char-budgeted `copy.md` is the
authority for user-facing strings). Recorded because it is a taste call on the operator's
own product vocabulary, and because the two specialists did not fully agree.
