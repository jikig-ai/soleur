---
brand_survival_threshold: aggregate pattern
---

# perf(infra): make the no-op sleep mock the DEFAULT in ci-deploy.test.sh

## Hypotheses

The **plan-skill** Phase 1.4 network-outage gate fired on the literal token
`timeout`; telemetry emitted. The L3→L7 checklist does not apply: the subject is
`actions/runner` cancelling a job that exceeded `timeout-minutes` — a scheduler
decision made on the runner with no host and no sshd in the causal chain.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

Every layer is structurally inapplicable. The suite resolves nothing over the
network and is deployed nowhere; no production surface participates.

## Plan Review Outcome

Cut the 15-line network-outage dismissal down to two sentences.
