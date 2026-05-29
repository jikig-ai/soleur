# Learning: A plan-mandated compound selector must be implemented as the full predicate

## Problem

PR #4603 (#4596) added a `deploy-docs.yml` step that looks up the `soleur_www`
Sentry uptime monitor in the `/detectors/` list endpoint to pause it. The plan's
Research-Reconciliation table (row 1) explicitly said:

> Identify the monitor by `name == "soleur-ai-www"` **+ `type`** from the list
> endpoint (Sentry allows duplicate names; cross-check `type`).

The `/work` implementation selected on name only:

```bash
id=$(jq -r '[.[] | select(.name == "soleur-ai-www")] | .[0].id // empty' <<<"$detectors")
```

`.[0]` blindly takes the first name-match. The `/detectors/` list returns *every*
detector type for the org (uptime, Crons monitors, metric/error detectors), and
Sentry allows duplicate names — so a future non-uptime detector sharing the name
could be paused/PUT-mutated instead. Latent wrong-target bug; no active impact
today (no dup name exists), so the code-quality review agent rated it P2.

## Solution

Implement the full predicate the plan specified, cross-checking `type`:

```bash
id=$(jq -r '[.[] | select(.name == "soleur-ai-www" and ((.type // "") | test("uptime")))] | .[0].id // empty' <<<"$detectors")
```

Substring `test("uptime")` (rather than an exact discriminator literal like
`uptime_domain_failure`) is used deliberately: the exact `type` string was a
`/work`-time live-probe open question the plan flagged but did not pin. Substring
match is resilient to the exact discriminator AND fail-safe — no match yields an
empty `id`, which the next line treats as "detector not found → skip pause with a
warning," never a wrong-detector mutation.

## Key Insight

When a plan's reconciliation/spec table prescribes a **compound** selector
(match on field A **AND** field B), implement the full predicate — not just the
primary field. A single-field selector against a list endpoint that returns
heterogeneous rows is a latent wrong-target defect that typecheck, lint, and
happy-path testing all miss; it surfaces only when a collision appears in
production data. The plan calling out "cross-check X" is the spec, not a
suggestion. When the exact value of the secondary discriminator is an
unresolved open-question, prefer a fail-safe partial match (substring / shape
check) over either dropping the check or pinning an unverified literal.

## Session Errors

1. **Pre-existing `actionlint` SC2034 blocked AC7 on first run.** The
   `deploy-docs.yml` screenshot-gate step had an unused `for i` loop var that
   made `actionlint` exit 1 before any new code was added. — Recovery: fixed
   `for i`→`for _` inline (the new probe loop already used `for _`). —
   Prevention: read an AC like "actionlint clean" as whole-file scope; a
   pre-existing lint finding in a file you're already editing is in-scope to
   clear inline, not defer.
2. **Detector selector dropped the plan-mandated `.type` cross-check** (the
   subject of this learning). — Recovery: added the `type` predicate inline
   post-review. — Prevention: the Key Insight above.
3. **Benign shell-snapshot stderr** (`ZSH_VERSION: unbound variable`) in one
   Bash result — harness shell-init noise, no functional impact, no action.

## Tags
category: integration-issues
module: ci/sentry-iac
issue: 4596
pr: 4603
