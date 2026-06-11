# Learning: Verify the runtime's billing model before scoping any "capture cost" feature

## Problem

Brainstorming #5086 ("Token-cost ledger for autonomous loops: feed actual API spend into the
ops expense ledger"), the issue's entire premise was that the enumerated autonomous loops
(`one-shot`, `drain-labeled-backlog`, `test-fix-loop`, `*.workflow.js`) have per-token API spend
worth capturing. They do not. Those loops run on the operator's **flat Claude Code Max 20x
subscription** ($200/mo × 2 seats, already booked as R&D dev-tooling in `cost-model.md`) — their
**marginal dollar cost per run is $0**. Only the CI `claude-code-action` jobs
(`claude-code-review.yml`, `test-pretooluse-hooks.yml`), authed with `ANTHROPIC_API_KEY`, incur
real per-token charges.

Had the premise gone unchallenged, the feature would have (a) manufactured a **false billing
surprise** — attaching dollar figures to runs that cost nothing, eroding the exact BYOK
operator-trust the feature exists to protect — and (b) **corrupted the hand-maintained
`expenses.md` ledger** by writing per-run rows into a recurring-vendor table that `cost-model.md`
derives burn from.

## Solution

Before scoping any cost/usage-capture feature, **classify the runtime's billing model first**:

- **Flat subscription** (Claude Code Max/Pro seat, OAuth token): marginal cost per run = $0. The
  honest signal is token-headroom / subscription-ceiling-spillover (a future step-up *exposure*,
  Sentry-PAYG style), NOT per-run dollars. Keep it OUT of the dollar ledger.
- **Metered API key** (`ANTHROPIC_API_KEY`, pay-per-token): real charges. This is the only path
  worth ledgering as dollars.

Then split capture by path. For the metered CI path, `claude-code-action@v1.0.101` exposes an
`execution_file` output (the Claude Code result JSON) carrying `total_cost_usd` — a **no-SSH,
no-dashboard** source readable in-workflow via `jq` (satisfies
`hr-no-dashboard-eyeball-pull-data-yourself`). Distinguish auth mode by checking whether the
workflow passes `anthropic_api_key` vs `claude_code_oauth_token`.

Land per-run data in a **committed machine-written sidecar** (cross-operator) — NOT the existing
`.claude/hooks/agent-token-tee.sh` sink, which tees to gitignored `.session-tokens.jsonl` (local,
per-machine, a dead end for a persistent ledger). The recurring-vendor ledger gets at most **one
monthly aggregate line** that the cost model references as a derived input.

## Key Insight

A "capture cost" feature inherits the *billing model* of whatever it measures. Conflating a
flat-subscription runtime with a metered-API runtime produces a feature that invents costs that
were never charged — worse than no feature, because a wrong number on a trust surface breaks the
trust. **The first question for any cost-visibility request is "is this runtime flat-rate or
metered?", not "where do we store the number?"** This mirrors the existing brainstorm-playbook
discipline of verifying vendor commercial terms live before letting them bound scope.

## Tags
category: workflow-patterns
module: brainstorm, finance/cost-model, operations/expenses
issue: 5086
related: 5085, 5173
