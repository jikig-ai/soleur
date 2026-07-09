# Decision Challenges — feat-one-shot-workstream-issue-creator-attribution

Persisted at deepen-plan time (headless). `ship` should render these in the PR body and file an `action-required` issue for the operator.

## 1. Part B write-path re-scope + likely PR split (sequencing / scope)

**Operator's stated direction:** one feature that both (A) shows who created each Workstream issue and (B) attributes Soleur-created issues back to the initiating human ("Soleur · initiated by <you>").

**What deepen-plan review found (verified P0 — Kieran + spec-flow, independently):** the operator's live Concierge does NOT create issues via the `create_issue` tool. All new conversations route to the `soleur_go` runtime (`ws-handler.ts:1653/2255`), which registers an empty MCP allowlist (`cc-dispatcher.ts:291`) and mints a `GH_TOKEN` so the agent files issues via `gh issue create` over Bash (`cc-dispatcher.ts:110`). The `create_issue` tool (and its `createIssue` TS helper, where the plan originally stamped the marker) is only built on the LEGACY `startAgentSession` path — which the live Concierge bypasses. The `soleur-go-runner.ts:177-185` prompt even references `create_issue` as a "gated tool" that the runtime never wires (a dangling directive).

**Consequence:** stamping the initiator marker at `create_issue`/`createIssue` would render every unit test green while the operator's core want ("initiated by <you>") fails 100% of the time on the real path.

**Recommendation (challenge to the implicit "one PR" framing):**
- **Ship Part A now** — it is self-contained, needs no write-path change, and already delivers the "human vs Soleur" distinction the operator asked for.
- **Land Part B as a focused follow-up PR** that (mechanism A) wires `create_issue` into the Concierge's `soleur_platform` MCP server (promoting the deferred #3722 hook) and redirects the Concierge off raw `gh`, so issue creation funnels through `createIssue` where the marker is stamped — plus fixes the dangling prompt directive. Mechanism B (marker via prompt directive on the `gh` command) was considered and rejected as unreliable (model-composed `gh`).

**Why surface, not silently apply:** splitting the operator's single request into two PRs and pulling in cc-MCP wiring (#3722 scope) is a sequencing + scope decision the operator should confirm. The default remains the operator's direction (deliver both parts); this only recommends the ordering that avoids shipping a silently-non-functional Part B.

**Secondary finding (coverage caveat, not a challenge):** even once Part B is wired, the initiator login resolves to `null` for email-signup users who connected a repo but never did GitHub-OAuth resolve (`users.github_username` is written only by `app/api/auth/github-resolve/callback/route.ts:149`). Those users' Soleur-created issues render plain "Soleur" (graceful, but the "initiated by" refinement silently won't fire for them). Covered by the `attribution_status` liveness enum in the plan's Observability section.
