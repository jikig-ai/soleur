---
date: 2026-05-12
category: best-practices
module: plan, brainstorm
tags: [plan-quality, brainstorm-quality, external-api, pseudonymization, gdpr, sentry, better-stack]
related_issue: 3638
related_pr: 3685
related_learnings:
  - 2026-04-22-plan-ac-external-state-must-be-api-verified
  - 2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims
  - 2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites
---

# Learning: Plan-time API-contract verification (and pipeline-via-package.json) kills brainstorm claims

## Problem

The brainstorm for #3638 (hash userId in Sentry mirror + Art. 17 erasure) presented three options to the user, the user picked the most aggressive (Track A pepper-hash + full Track B active purge), and the brainstorm captured the choice with two load-bearing claims that turned out to be false at plan-write:

1. **CTO recommended** that a single Sentry call — `DELETE /api/0/organizations/{slug}/issues/?query=userIdHash:<hash>` — would erase events by tag. The brainstorm endorsed this verbatim. Plan-time WebFetch of the Sentry docs (`bulk-remove-a-list-of-issues`) returned: *"Only queries by 'id' are accepted."* The DELETE endpoint accepts only an `id=N&id=N` list, never a tag-query parameter. CTO had read the project-bulk-MUTATE endpoint docs and confused it with the org-issues-GET search semantics (which DOES accept `query=`).

2. **The brainstorm assumed `pino → Better Stack` was the runtime log pipeline** because Better Stack was listed in the project's sub-processor disclosure (#1048) and in PA8's recipient list. Plan-time `jq '.dependencies, .devDependencies' apps/web-platform/package.json | grep -iE "pino-|better-?stack|logtail"` returned only `pino` + `pino-pretty`. No `pino-better-stack`, no `@logtail/*`, no `pino-logtail`. Better Stack is actually the **uptime monitor on `/health`** (verified via `production-observability-sentry-pino-health-web-platform-20260328.md`), not a log recipient. PA8 itself already correctly said *"pino stdout never leaves Hetzner Finland."* The brainstorm conflated "sub-processor disclosed" with "data-flow pipeline."

Both errors would have shipped to /work as FRs/ACs the implementer could not honor. The cost would have been mid-implementation pivots, AC strikethroughs, and at worst a deferred-scope-out for a capability the codebase doesn't support.

A third class also surfaced during plan-review:

3. **Plan v1 misnamed `warnSilentFallback` as `reportSilentInfoFallback`** in the Phase 2.1 transform list, AND missed two direct `Sentry.captureMessage` sites at `ws-handler.ts:693, 719` that bypass the centralized observability helper. The plan-write grep was scoped to `observability.ts` (the file being edited), not the codebase-wide bypass surface that defeats the centralization.

## Solution

Three additive rules at plan-write time. The first two are sub-cases of the existing rule `2026-04-22-plan-ac-external-state-must-be-api-verified.md` (which covers external-service *state*); these extend the rule to external-service *contract* and *pipeline shape*.

### 1. Verify the API contract, not just the state

When a brainstorm option or a plan FR/AC names a specific endpoint, query parameter, HTTP verb, or filter shape on a third-party API, run **one of**: (a) WebFetch the canonical docs URL for that endpoint, (b) fetch the OpenAPI/Swagger schema and grep for the parameter name, or (c) curl the endpoint with a probe payload in a sandbox account. Plan-time existence-of-endpoint is not existence-of-feature.

Existing rule extension: `2026-04-22-plan-ac-external-state-must-be-api-verified.md` says *"verify via the actual API at plan time."* For state checks this means `gh secret list`, `doppler secrets get`, etc. For contract checks this means WebFetch / OpenAPI grep of the exact endpoint + parameter combination the plan names.

### 2. Verify the pipeline via `package.json`, not the sub-processor disclosure

Sub-processor lists, vendor tables, and DPA-tracking records say **who is permitted to receive personal data**, not **who currently does**. A third-party processor disclosure does not imply runtime data flow. Before reasoning about Art. 17 / Art. 30 obligations against a processor, grep `package.json` (or pyproject.toml, Cargo.toml, Gemfile.lock — language-appropriate dependency manifest) for the actual transport package:

| Claim | Manifest grep |
|---|---|
| pino → Better Stack | `pino-better-stack`, `@logtail/pino`, `pino-logtail` |
| logs → Datadog | `dd-trace`, `@datadog/*`, `winston-datadog` |
| events → Segment | `analytics-node`, `@segment/*` |
| metrics → Prometheus | `prom-client`, `@opentelemetry/exporter-prometheus` |

Absence of the transport package is dispositive: the pipeline doesn't exist, regardless of what the sub-processor list says.

### 3. Helper-centric grep is insufficient when the goal is centralization

When a plan centralizes a transform inside a helper function (here: `userId → userIdHash` inside `reportSilentFallback`), the plan-time grep MUST also enumerate **direct call sites of the underlying API** that bypass the helper. Helper-scoped grep returns zero matches outside the helper itself — fast and fast green-lit — but misses every code path that calls the underlying API directly. Required two-grep pattern:

```bash
# helper-centric grep (catches what we expect to catch)
rg "<helperName>\(" apps/web-platform/

# bypass grep (catches what defeats centralization)
rg "<underlyingApi>\(" apps/web-platform/ | grep -v "<helperFile>"
```

For Sentry-centralization scenarios, the bypass-grep is `rg "Sentry\.(captureException|captureMessage)\("` excluded by the helper's own file. Two sites surfaced for #3638 that the helper grep alone would have missed.

### Generalized regex shape for centralized-transform AC gates

When the AC enforces "no raw `userId` in emit," do NOT use `userId:` literal-colon match. Shorthand object literals (`{ userId }`) carry no colon and slip through:

```bash
# Fragile — misses shorthand
rg "userId:\s*\b(userId|user\.id|ctx\.userId)\b" apps/web-platform/server/

# Robust — matches both colon and shorthand within object-literal context
rg "(extra|tags):\s*\{[^}]*\buserId\b" apps/web-platform/server/
```

The robust form anchors on the **container shape** (`extra:`, `tags:`) and uses a word-boundary token match for `userId` regardless of how it's spelled inside the braces.

## Key Insight

**Brainstorm-time leader recommendations are framing-correct but API-contract uncertain.** The CTO recommendation, the CLO retention framing, and the CPO sequencing all read coherently in the brainstorm — each leader optimized for their lens, none ran the docs probe. Plan-time is where the contract gets nailed. If the plan inherits the brainstorm's API-contract claims without verification, the plan ships fiction that /work has to recover from.

The simplification cascade is also worth noting: once the API-contract check killed Track B (active purge), the plan dropped 3 FRs, 1 TR, 4 ACs, a runbook, an env var, two PA8 edits, and a vendor-table row. The retention-only posture is the *legally* sufficient one (CLO had said so in the brainstorm, but engineering chose belt-and-braces); the API check forced engineering back to the legal-minimum position because the belt was a hallucination.

## Prevention

- **Plan skill Sharp Edges:** Add a one-line Sharp Edge explicitly covering API-contract claims (not just API-state) and pipeline-via-package.json. Adjacent to the existing `2026-04-22-...-external-state-must-be-api-verified` Sharp Edge.
- **Brainstorm skill verifying-claims-against-codebase Sharp Edge:** the existing block already covers "verifying referenced PR/issue state" and "verifying capability gaps need repo grep." Extend with "verifying external-API claims by leader agents need plan-time docs-fetch before freezing into FRs."
- **For any plan that centralizes a transform inside a helper:** require the two-grep pattern (helper-centric + bypass) in the plan's verification ACs, not just the helper-centric grep.

## Session Errors

1. **Brainstorm-time CTO Sentry DELETE-by-tag claim was a docs misread.**
   **Recovery:** Plan-time WebFetch caught it; pivoted to retention-only.
   **Prevention:** This learning — verify API contract at plan time. Add a Sharp Edge.

2. **Brainstorm assumed `pino → Better Stack` pipeline from sub-processor disclosure.**
   **Recovery:** Plan-time `package.json` grep showed no transport; corrected PA8 update scope.
   **Prevention:** This learning — verify pipeline via dependency manifest. Add to brainstorm Phase 1.1 grep list.

3. **Plan v1 misnamed `warnSilentFallback`** as `reportSilentInfoFallback`.
   **Recovery:** Kieran plan-review caught it.
   **Prevention:** Plan-write must `git grep -n "^export function" <file>` for the actual exported symbol list rather than guessing names from siblings. Routed to plan skill Sharp Edges.

4. **Plan v1 missed direct `Sentry.captureMessage` sites at `ws-handler.ts:693, 719`** that bypass `reportSilentFallback`.
   **Recovery:** Kieran's codebase-wide grep caught both; added Phase 2.6 inline.
   **Prevention:** This learning — two-grep pattern for centralized-transform plans.

5. **Plan v1 AC3 regex was fragile** against shorthand object literals.
   **Recovery:** Kieran corrected to the container-shape regex.
   **Prevention:** This learning — robust regex shape documented above. Plan skill Sharp Edges note.

## Related

- `2026-04-22-plan-ac-external-state-must-be-api-verified.md` — the parent rule this learning extends from state to contract + pipeline.
- `2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md` — adjacent rule for verifying leader claims at brainstorm time.
- `2026-04-28-sentry-payload-pii-and-client-observability-shim.md` — Sentry-payload PII rules consumed by this plan.
- `2026-04-17-pii-regex-scrubber-three-invariants.md` — PII-scrubber design invariants, structurally adjacent.
- Issue #3638 (this work), #3686 (deferred D-durable-audit-log).
