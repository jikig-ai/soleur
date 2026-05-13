---
date: 2026-05-13
tags: [ops, ci, runbook, github-api, empirical-verification]
issues: [3569, 3544, 3542, 2719]
pr: 3736
category: integration-issues
---

# Two compounding gaps caught while fixing the daily ruleset bypass audit (#3569)

## Problem

The daily `scheduled-ruleset-bypass-audit` workflow had been firing
`live_missing_bypass_actors / ci/guard-broken` on every run since
2026-05-11. Operator received a "Ruleset bypass audit malfunctioned"
email each morning. Issue #3569 had accumulated three daily comments,
each citing the same failure mode.

Two distinct failure-of-process gaps surfaced while fixing it.

## Gap 1 — Runbook misclaim with destructive prescription

The runbook at
`knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` line
105 mapped `live_missing_bypass_actors` to **"ruleset deleted entirely"**
with a prescription:

> **This is auth-broken-class even if labeled guard-broken** — the
> ruleset is gone. Restore via `scripts/create-ci-required-ruleset.sh`
> and re-add `skill-security-scan PR gate` via
> `scripts/update-ci-required-ruleset.sh`.

The audit script's failure mode actually fires for **two opposite
states**:

1. The ruleset was genuinely deleted (HTTP 200 was a fluke or stale
   cache; or HTTP 404 routes through a different `failure_mode`).
2. The caller token lacks `administration` scope and GitHub silently
   **redacts `.bypass_actors` from the response payload** while still
   returning HTTP 200 with the rest of the ruleset metadata intact.

Empirical demonstration of the redaction:

```bash
# Anonymous (no token / non-admin token):
curl -s "https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388" | jq -r 'keys[]'
# -> _links, conditions, created_at, enforcement, id, name,
#    node_id, rules, source, source_type, target, updated_at
# (no `bypass_actors` key)

# Admin-scoped token (workstation gh CLI):
gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors'
# -> [{"actor_id":null,"actor_type":"OrganizationAdmin",...}, ...]
```

An operator following the runbook would have run
`create-ci-required-ruleset.sh` against a healthy live ruleset.
That script PUTs the canonical bypass_actors over the live state —
**exactly the catastrophic widening the audit was built to detect**.
Any operator-side typo, stale canonical, or out-of-sync canonical row
would silently broaden the auth surface; the next skill-install PR
from a malicious actor could merge without `skill-security-scan PR
gate` running.

Brand-survival threshold for the ruleset is `single-user incident`
(carries from #2719). The runbook's prescription was a single-step path
from "audit alarm" to "incident".

## Gap 2 — Plan-time API research treated as load-bearing for security scope

The plan researched the GitHub Apps + rulesets contract via context7 and
concluded:

> the rulesets endpoint redacts .bypass_actors from the response when
> the caller lacks administration:read

Plan AC4b therefore prescribed minting the install token with
`permissions: {administration: read, metadata: read}` for least-privilege.

First workflow_dispatch run on the feature branch (workflow run
[25823297400](https://github.com/jikig-ai/soleur/actions/runs/25823297400))
minted exactly that token (verified in step log:
`Installation token minted (selection=selected, perms={"administration":"read","metadata":"read"})`)
and the audit STILL fired `token_scope_insufficient`. GitHub's actual
contract requires `administration: write` — `read` returns 200 OK with
`bypass_actors` redacted, indistinguishable from "ruleset deleted".

Plan AC4b's least-privilege intent was preserved by stacking other
mitigations: `repository_ids: [<this-repo>]` filter at mint time, 1h
token lifetime, `::add-mask::` registration, per-run mint with no
persistence, and the audit script never PUTs to the rulesets endpoint
(only GETs).

## Solution

PR #3736 ships:

1. **Runbook rewrite** (line 105 + new triage subsection): the
   `live_missing_bypass_actors` row now requires an admin-scoped probe
   (`gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors'`)
   from a workstation BEFORE any restore action. New
   `token_scope_insufficient` row + dedicated triage section enumerates
   the permissions/secret-rotation path. New `ruleset_enforcement_disabled`
   row covers a related "paused but not deleted" case caught at review.
2. **App-installation token mint** (workflow yaml): new `mint-jwt` +
   `mint-install-token` steps using the existing `soleur-ai` GitHub App
   (drift-guard secrets) with mint-time scope-down to
   `{administration: write, metadata: read}` + `repository_ids: [this-repo]`.
3. **`token_scope_insufficient` failure mode** (audit script): new
   sentinel `.id == 14145388 AND .enforcement == "active"` distinguishes
   token-scope-redacted from ruleset-deleted.

End-to-end verified on workflow run
[25823976265](https://github.com/jikig-ai/soleur/actions/runs/25823976265)
post-review-fixes: "Ruleset bypass audit passed." + #3569 auto-closed
by the workflow's own auto-close-on-green step.

## Key Insights

### Runbooks that prescribe destructive actions need probe-first gates

A runbook step that maps a single failure signal to a single destructive
action is high-blast-radius. The signal must be probed for ambiguity
**before** the destructive step. Phrasing pattern:

> "**DO NOT immediately run `<destructive script>`.** First probe live
> state via `<read-only diagnostic command>`. (a) If `<expected-healthy>`
> → the failure is upstream of the prescribed fix; investigate
> `<alternative cause>`. (b) If `<expected-unhealthy>` → THEN run
> `<destructive script>`."

Apply this pattern to every existing runbook entry whose prescribed
fix is a `PUT`, `DELETE`, `DROP`, `TRUNCATE`, or any other destructive
operation against shared/production state.

### Plan-time API research is a hypothesis, not a contract

context7 / docs research at plan time captures what the docs say. The
live API contract is what the API actually returns. For
**security-relevant scope claims** (which permission lets you read
which field, what the API redacts, when it returns 200 vs 403, etc.),
empirical verification on a feature branch is required before treating
the research as load-bearing. The plan should mark such claims as
"verify on feature branch" preconditions, not as final ACs.

In this PR the gap was only ~10 minutes (run-trigger → see redaction →
escalate scope) because the verification ran on a feature branch with
no production exposure. If the workflow had been merged on plan-time
research alone, the audit would have continued firing
`token_scope_insufficient` daily and the operator would have seen
zero behavioral change from the "fix".

### Daily false-positive alarms are themselves the brand-survival risk

The audit existed to detect a single-user-incident-class drift in
`bypass_actors`. Three days of false-positive alarms is three days
where the operator would dismiss the next alarm as "more of the same"
— including the alarm that meant a real broadening had happened. The
real risk surface of an alarm-fatigue gap is the audit BLINDING ITSELF
to the very class of incident it was built to catch.

## Session Errors

1. **Misdiagnosis at action-plan time** — Proposed running
   `scripts/create-ci-required-ruleset.sh` against a healthy ruleset
   based on the runbook's literal prescription. **Recovery:** Paused
   for read-only verification before any destructive call. **Prevention:**
   The runbook fix in this PR (probe-first gate on every destructive
   prescription) generalizes to the rule "every runbook step that
   PUTs/DELETEs/DROPs against shared state must require a read-only
   probe first." Routed to a learning-bullet on the audit runbook itself.
2. **Plan research overstated API scope** — Plan said
   `administration: read` would suffice; live API required `write`.
   **Recovery:** Empirical workflow_dispatch on the feature branch
   caught it pre-merge. **Prevention:** Plan ACs should mark
   security-relevant scope claims as "verify on feature branch"
   preconditions, not as terminal ACs. Routed to plan-skill Sharp Edge.
3. **Internal plan AC inconsistency** — Plan AC2 said `grep
   'administration' workflow.yml` should return zero matches, but the
   same plan endorsed an App-token approach that REQUIRES the string in
   the POST body. **Recovery:** Honored AC2's spirit (no
   `administration` in `permissions:` block) and noted the literal-grep
   mismatch in the PR commit body. **Prevention:** Plan ACs that
   prescribe negative-space greps should be scoped to specific yaml
   blocks (e.g., `yq '.permissions.administration'`) not whole-file
   greps that catch comments + body content.
