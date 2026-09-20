---
aliases:
  - server-side browser automation
  - Soleur-hosted Playwright
  - run the browser on your servers instead of mine
  - headless browser in the cloud platform
  - drive my supplier portals from your backend
scope: >-
  server-side browser automation: a Soleur-operated, Soleur-hosted headless browser that signs in to
  a tenant's third-party services with the tenant's credentials and performs the work on Soleur
  infrastructure. The refusal is that surface and nothing else. Browser automation itself ships and
  is not refused: the `soleur:agent-browser` skill drives a browser on the founder's own machine
  with the founder's own session, the `playwright` MCP server in `.mcp.json` is registered and in
  use, and `soleur:ux-audit` screenshots live routes through it. A request for any of those three is
  already answered yes.
why: >-
  Recorded in `knowledge-base/product/roadmap.md`, section "Architecture Decision: 3-Tier Service
  Automation (Brainstorm 2026-03-23)": "Server-side Playwright was rejected (HIGH risk from CTO,
  CLO, CFO)." Hosting the browser moves the tenant's third-party credentials, session cookies and
  every action taken under them onto Soleur infrastructure, and with them the undisclosed-agency
  liability counsel flagged in the same review — Soleur would be acting as the tenant inside
  services whose terms were written for the tenant. The cost review reached the same answer from
  the other side: a per-tenant browser is a per-tenant machine. The three signatures are what makes
  this durable rather than a mood; it is an architecture boundary, not a backlog position.
public_note: >-
  Browser work runs on your machine, in your browser, under your own login — never on Soleur's
  servers under ours.
instead: >-
  The shipped three-tier answer, in order of preference. Tier 1, direct APIs and MCP servers, covers
  roughly 80% of services and is deterministic and versioned. Tier 2, a browser on the founder's own
  device, covers roughly 15% where no API or MCP server exists, using the founder's own session.
  Tier 3, guided step-by-step instructions with deep links and review gates, covers the remaining
  5%. For anything visual against Soleur's own surfaces, `soleur:ux-audit` and the `playwright` MCP
  server already exist.
revisit_if: >-
  A tenant-isolated browser runtime becomes available that holds no long-lived third-party
  credential on Soleur infrastructure, AND counsel signs a framework covering agency for actions
  taken inside a third party's service on a tenant's behalf. Both, not either: the 2026-03-23 review
  raised technical, legal and cost objections independently, and removing one of the three does not
  answer the other two.
redundancy_check: not-implemented
searched:
  - "git ls-files | grep -icE 'server[- ]side[- ]playwright' -> 0"
  - "git grep -ilE '(chromium|firefox|webkit)\\.launch' -- apps/web-platform/server apps/web-platform/app -> 0"
  - "git grep -ilE 'hosted[- ](browser|playwright)' -- apps -> 0"
  - "git grep -ilE '(chromium|firefox|webkit|browser)\\.launch' -- apps -> 1, and it is apps/web-platform/scripts/live-verify/run.ts, a local verification script rather than a tenant-facing runtime"
---

# Server-side browser automation

Soleur does not run the browser. You do, on your own machine, signed in as yourself.

## Why the narrow scope matters here

This entry is the shape to copy, and the reason is in its `scope`. Browser automation, stated
broadly, **is a shipped Soleur capability** — the skill, the MCP server and the visual audit all
exist, and the acceptable-use policy names browser automation through a Playwright MCP server as
part of the product. An entry keyed on the broad concept would assert that an implemented capability
is absent, which is the one failure mode the no-list exists to prevent, and no guard could catch it:
a guard proves an entry is internally consistent, not that it is true.

So the boundary is drawn at the only place a refusal was actually recorded — the server side, with
Soleur holding the tenant's credentials — and the `scope` field names the implemented paths
explicitly, so that a later lookup for "browser automation" reads the yes as easily as the no.

## When this arrives as a request

It will, and usually in the founder's words rather than the architecture's: *let the agent go and do
it for me*. The answer is not "no". The answer is tier 1 if the service has an API or an MCP server,
tier 2 if it does not, and tier 3 if neither works — and in all three cases the founder's
credentials stay where the founder put them.
