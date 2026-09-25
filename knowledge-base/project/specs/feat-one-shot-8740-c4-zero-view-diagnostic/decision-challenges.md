# Decision challenges: feat-one-shot-8740-c4-zero-view-diagnostic

These are decisions made during headless planning that need the operator's eye. They are
recorded per ADR-084, and `ship` renders them into the PR body. The plan is
`knowledge-base/project/plans/2026-09-25-fix-c4-zero-view-model-project-diagnostic-plan.md`.

---

## DC-1: Re-render the affected external repository? (User-Challenge: operator authorisation)

**Why this is a User-Challenge:** writing to an external tenant repository needs an explicit
operator ack (`hr-menu-option-ack-not-prod-write-auth`). A headless pipeline cannot give it.

**Default taken:** (a), do not write. The `/project` diagnostic and the Concierge now both
explain the empty canvas and name the edit that redraws it.

- **(a) Leave it (default, from the CPO).** The follow-through sweeper closes #8740 after 14 days
  with no production zero-view loads, once the fix is live. A census re-run showing 0 zero-view
  models also closes it.
- **(b) Authorise one re-render.** A single `.c4` write through the existing writer, with your
  explicit ack. The commit lands in the tenant's repository under the Soleur app.
- **(c) Contact the tenant through support.**
  - The CPO prefers this to (b), because it asks before writing.
  - The DHH review argued it should be the default, as the cheapest real resolution.
  - The trigger to move from (a) to (c) is a sweeper FAIL comment on #8740: production zero-view
    loads in the window.
  - Sentry sends no email for this warning-level issue. The only unfiltered alert rule fires on
    high-priority issues.

## DC-2: Diagnostic cause wording (Taste, resolved)

The reviewers disagreed on how much cause to assert:

| Reviewer | Wanted |
|---|---|
| CPO | "our renderer saved it incorrectly" (own the fault) |
| CMO | "an earlier version of Soleur saved its layout incorrectly" |
| Step 4.5 advisor | a hedge ("most likely") |
| DHH | no cause at all |

The DHH position is correct on the facts: the plugin writers (#8861) can still produce a
zero-view model, so it may not be the server renderer's fault. The shipped copy asserts no cause:
"its saved layout is incomplete. Your diagram source is fine."

The second sentence is true by ADR-050's measurement: a successful layout always emits at least
`index`. The CPO may prefer to restore first-person ownership for models the server wrote.

## DC-3: Concierge action wording (Taste)

- **Shipped (canonical diagrams folder):** "ask the Concierge to add a comment to this diagram's
  source, then reload the page."
  - The code guarantees it: any `.c4` write through the Concierge re-renders, and a `.md` write
    does not.
  - A matching sentence in `C4_PROMPT_ADDENDUM` stops the Concierge from "fixing" the source by
    adding `views` blocks.
- **Other folders:** these name a re-export in the user's repository instead. `edit_c4_diagram`
  can only write the canonical folder.
- **Not chosen:** the CPO's primary wording, "ask the Concierge to re-render this diagram". It
  would need a live check that the Concierge turns that request into a write.
- **Assumes the default engine:** `edit_c4_diagram` is registered only by the Claude Code engine
  dispatcher. The `codex-engine` path (default OFF) has no C4 tool.
- **Revisit when `c4-edit` rolls out:** an "or save it" clause may then be worth adding.
- **Revisit when #8739 ships:** remove "then reload the page" from both route copies and the
  addendum. Ship comments on #8739 with this.

## DC-4: Strip colour and the `hasModel=false` header (Taste)

- **Colour:** the CPO and the UX lead noted that amber, the staleness colour, fits "the saved
  layout is incomplete" better than the red "Diagram warnings" strip. Changing it means a new
  styled element and a wireframe, for one tenant. Not done here.
- **Header:** the UX lead also flagged a separate dead end. The `hasModel=false` header says "fix
  the source in the Code view", and that view is gated OFF by `c4-edit`. The zero-view path does
  not reach it. Worth handling in the `c4-edit` rollout.

## DC-5: Pre-existing `dir` traversal folded into this PR (Mechanical; disclosed)

- **The gap:** security review found that `?dir=%252e%252e/...` passes the route's guard and reads
  `.c4`, `README.md` and `model.likec4.json` from any folder of the workspace repo, not only the
  KB.
- **Why it is folded in:** the fix is in the same file, and the new warning's dedup key would
  otherwise be built on the uncanonical value.
- **The fix:** a per-segment allowlist, a length cap, control and line-separator rejection, and
  per-segment encoding (plan Phase 1 item 2, rows T6).
- **Why this is listed:** the PR grows beyond #8740's literal ask.
