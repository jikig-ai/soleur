# Decision challenges: feat-one-shot-8740-c4-zero-view-diagnostic

These are decisions made during headless planning that need the operator's eye. They are
recorded per ADR-084, and `ship` renders them into the PR body. The plan is
`knowledge-base/project/plans/2026-09-25-fix-c4-zero-view-model-project-diagnostic-plan.md`.

---

## DC-1: Re-render the affected external repository? (User-Challenge: operator authorisation)

**Why this is a User-Challenge:** writing to an external tenant repository needs an explicit
operator ack (`hr-menu-option-ack-not-prod-write-auth`). A headless pipeline cannot give it.

**Default taken:** (a), do not write. The `/project` diagnostic now explains the empty canvas
and names the edit that redraws it.

- **(a) Leave it (default, from the CPO).** The follow-through sweeper closes #8740 after 14 days
  with no production zero-view loads, once the fix is live. A census re-run showing 0 zero-view
  models also closes it.
- **(b) Authorise one re-render.** A single `.c4` write through the existing writer, with your
  explicit ack. The commit lands in the tenant's repository under the Soleur app.
- **(c) Contact the tenant through support.**
  - The CPO prefers this to (b), because it asks before writing.
  - The DHH review argued it should be the default rather than (a), as the cheapest real
    resolution.
  - The trigger to move from (a) to (c) is Sentry's first-seen email for the
    `op:zero-view-model` issue, or a sweeper FAIL on #8740.

## DC-2: Diagnostic cause wording (Taste, resolved)

The reviewers disagreed on how much cause to assert:

| Reviewer | Wanted |
|---|---|
| CPO | "our renderer saved it incorrectly" (own the fault) |
| CMO | "an earlier version of Soleur saved its layout incorrectly" |
| Step 4.5 advisor | a hedge ("most likely") |
| DHH | no cause, because a tenant's own likec4 run without graphviz produces the same zero-view model |

The shipped copy asserts no cause: "its saved layout is incomplete. Your diagram source is
fine." The second sentence is true by ADR-050's measurement: a successful layout always emits at
least `index`. The CPO may prefer to restore first-person ownership.

## DC-3: Concierge action wording (Taste)

- **Shipped:** "ask the Concierge to add a comment to this diagram's source, then reload the
  page." The code guarantees it: any `.c4` write through the Concierge re-renders.
- **Not chosen:** the CPO's primary wording, "ask the Concierge to re-render this diagram". It
  would need a live check that the Concierge turns that request into a write.
- **Assumes the default engine:** `edit_c4_diagram` exists only in the Claude Code engine
  dispatcher. The `codex-engine` path (default OFF) has no C4 tool.
- **Revisit when `c4-edit` rolls out:** an "or save it" clause may then be worth adding.
- **Revisit when #8739 ships:** remove "then reload the page". Ship comments on #8739 with this.

## DC-4: Strip colour and the `hasModel=false` header (Taste)

- **Colour:** the CPO and the UX lead noted that amber, the staleness colour, fits "the saved
  layout is incomplete" better than the red "Diagram warnings" strip. Changing it means a new
  styled element and a wireframe, for one tenant. Not done here.
- **Header:** the UX lead also flagged a separate dead end. The `hasModel=false` header says "fix
  the source in the Code view", and that view is gated OFF by `c4-edit`. The zero-view path does
  not reach it. Worth handling in the `c4-edit` rollout.
