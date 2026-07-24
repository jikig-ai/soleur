# Decision Challenges — feat-one-shot-cf-token-scope-6755

Headless-mode record (one-shot pipeline, no interactive operator). `ship` Phase 6
renders these into the PR body and files an `action-required` issue so the operator
can ratify or reverse. Per ADR-084 (User-Challenge) + plan Step 4.5 / plan-review
headless arm.

## UC-1 — Widen mechanism: Playwright MCP vs. a standing `User API Tokens:Edit` API token

**Operator's framing (from the issue/pipeline args):** weigh whether a robust
API-based approach — provisioning/using a dedicated scoped token that holds
`User API Tokens:Edit`, avoiding the browser entirely — is preferable to Playwright
browser automation, since the agent-browser daemon was wedged when #6755 was filed.

**Plan's decision (diverges from the framing's implicit API lean):** the plan adopts
**Playwright MCP dashboard automation** for the widen, and **rejects a standing
`User API Tokens:Edit` token**. Rationale:

1. **The "wedged daemon" argument does not point at API — it points at the wrong
   browser surface.** `soleur:agent-browser` (Vercel's CLI daemon) is the surface that
   wedges (stale socket). Playwright MCP (`mcp__playwright__*`) is a distinct, more
   robust surface, and is the *documented* house tool for exactly this operation —
   learning `2026-03-21-cloudflare-api-token-permission-editing.md` (#992) records a
   successful CF token-permission edit via Playwright on
   `dash.cloudflare.com/profile/api-tokens`, with the exact click-path.

2. **A standing `User API Tokens:Edit` token reintroduces Global-API-Key-equivalent
   power the account deliberately lacks.** `apps/web-platform/infra/variables.tf:285`
   and ADR-130 both record that NO Soleur token holds `User API Tokens:Edit` and the
   account has NO Global API Key — a deliberate posture. Such a token can mint/edit/
   delete *any* token → *any* scope; on leak it is a full-account compromise. ADR-130
   axis-1 (least-privilege) weighs decisively against creating and storing it for a
   security delta this large.

3. **An *ephemeral* operator-supplied `User API Tokens:Edit` token (mint→use→revoke).**
   Honest note (from security review): this is arguably *security-optimal for the
   automation phase* — deterministic API, no live full-power dashboard session transit, no
   browser-capture leak surface. It is rejected because (a) it briefly creates an omnipotent
   token whose orphaning (skipped/failed revoke) leaves a standing Global-API-Key-equivalent,
   and (b) it is dominated on UX (dashboard mint + paste + delete > driving the widen
   in-session). Documented as a possible future opt-in, not adopted.

**Honesty correction (security review).** The adopted Playwright path is NOT *strictly*
least-privilege: it still transits a full-power CF dashboard session (the session cookie is
account-wide, strictly broader than the token being edited). The invariant it keeps is
narrower and cleaner — *no omnipotent token ever exists*, even transiently — and the
session's leak surface is mitigated (no `browser_network_requests`/`browser_console_messages`
file dumps, edit-control-scoped screenshots, snapshot-only navigation). The ADR-130
amendment states this honestly rather than claiming Playwright is strictly least-privilege.

**Reversal trigger:** if Playwright automation of the CF dashboard proves too fragile
in practice (DOM churn), revisit the ephemeral-API path — and revisit the standing
meta-token *only* as a deliberate, separately-argued reversal of the no-omnipotent-
credential posture (mirroring how ADR-130 treated the `default=""` alternative), never
as a side effect.
