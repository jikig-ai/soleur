# Decision challenges: feat-one-shot-11303-gated-tier-allowedtools-bypass

Headless plan-review output (2026-10-27). Mechanical findings were applied to the plan. The rows below are Taste, scope or technical items where the plan keeps the stated direction (or a CTO ruling) as the default and records the dissent so `ship` can surface it.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Filter only inside `buildAgentQueryOptions` (drop the `agent-runner.ts` call-site edit and the fail-closed throw as duplicates of one invariant) | technical | Ruled by CTO agent, 2026-10-27: keep both; the call site is the stated ask and the throw at the single `opts.allowedTools` assignment is the second line of defence against a future caller (ruling 1). Dissent: DHH reviewer, code-simplicity reviewer (throw is cuttable) |
| Replace the cherry-picked probe with a minimal fresh three-row probe | operator (scope) | Plan keeps the stated direction: cherry-pick `0acc541b6f` and switch it to `buildAllowedTools`, then add the `:raw` canary and drop the redundant `:no-allowed` rows. Dissent: DHH reviewer (couples a P1 fix to a sibling branch, rewrites the file anyway) |
| Drop the in-suite mutation battery (oracle run over mutants) as a test of a test | operator (scope) | Plan keeps it: the brief names the battery ("drop a gated tool from the filter; empty census; add an unclassified gated tool"). The matrix was trimmed elsewhere (about 8 rows, the Guard 3 self-check, the source scan). Dissent: DHH reviewer |
| Replace the regex source scan of `agent-runner.ts` literals with something else | taste | Applied: the scan is replaced by reading registered tool names from a booted legacy session and asserting each has an explicit tier entry (three reviewers called the scan brittle; the CTO had accepted a cheap scan). |
| Open tracked issues for consent-fatigue policy and the offline/expired-gate UX | taste | Plan default: documented in the plan's Non-Goals (rule `wg-when-deferring-a-capability-create-a`; the brief says no extra issues unless a rule requires one). Dissent: CPO advisory (asked for filed, milestoned follow-ups), spec-flow reviewer |
| Plugin MCP wildcards stay pre-approved (third-party write tools in context7, cloudflare, vercel, stripe plugins) | operator (scope) | Plan keeps the brief's direction ("keeping auto-tier tools and plugin MCP wildcards"); `canUseTool` also allows these without a card, so it is not a bypass of an existing gate. Residual risk is named in the PR body. Dissent: spec-flow reviewer (threshold only partly closed) |
