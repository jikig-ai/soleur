Enable the `checkout.session.expired` event on the Soleur Stripe webhook endpoint so PR #9115's new marker-cleanup arm fires. Until it is enabled, abandoned-checkout markers persist past their usefulness — harmless (the daily 24h retention sweep and route reclaim paths still self-heal) but the prompt cleanup the PR intends never runs.

This is a deferred-automation backlog item per
wg-block-pr-ready-on-undeferred-operator-steps.
Re-evaluate when: Stripe webhook configuration gains an API/CLI path reachable by the agent (the Stripe MCP server is registered but unavailable in this session), or the event subscription is managed in IaC.
playwright-attempt: https://dashboard.stripe.com/webhooks → redirected to /login (Stripe Dashboard credential wall; no credentials in session scope).

Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps
