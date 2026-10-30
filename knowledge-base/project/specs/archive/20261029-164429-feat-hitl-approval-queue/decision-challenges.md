# Decision challenges — feat-hitl-approval-queue (plan review, 2026-10-27)

Persisted by plan-review (headless). Technical rulings are recorded in the plan as "Ruled by CTO agent" / "Ruled by CLO agent"; these rows are product or scope choices where the plan's direction (operator-approved wireframes, CTO ruling scope) is the default and a reviewer proposed otherwise.

## Decision Classes

| # | Class | Proposal | Source | Plan disposition |
|---|-------|----------|--------|------------------|
| 1 | user-challenge | Drop the in-chat approval card; chat shows a link to the landing page only (removes three WS message types, the decide handler and chat-state-machine change) | DHH reviewer | Kept the chat card: the operator approved the wireframes with it as the primary surface; landing page still exists for the away user |
| 2 | taste | Ship four tools, not eight (`email_send`, `email_reply`, `github_push_branch`, `workspace_set_autonomous`) | DHH, CPO (questions `email_suppress`, `create_pull_request`) | Kept eight; each tool beyond the first is a canonicalizer, a view and a test, and the census guard forces the choice for any new tool. Challengeable at review |
| 3 | taste | Remove UI states: "newer request exists" banner, "already decided by <name>" loser state, request-count header | DHH | Kept; they answer spec-flow gaps rated degraded or single-user-incident |
| 4 | taste | One-tap "Tell your agent to retry" button that sends a prefilled message after a late approval | UX reviewer | Not in slice 1 (new capability); listed in the consolidated deferral issue |
| 5 | taste | Suppress or delay the push when the Owner is the requester and is in a live session | UX reviewer | Not in slice 1; listed in the deferral issue |
| 6 | taste | Push a notice for an approved-but-unconsumed expiry | UX reviewer | Kept inbox-only so a stale approval does not ping the Owner again |
| 7 | taste | Replace the byte-identical replay with deny-message text carrying the exact canonical arguments | CPO | Deny text says to call again with exactly the same arguments; echoing the canonical text into the deny message is left to work-time judgment |
| 8 | taste | Do not extend `expires_at` on approve | Kieran (P3) | Not extended; documented |
