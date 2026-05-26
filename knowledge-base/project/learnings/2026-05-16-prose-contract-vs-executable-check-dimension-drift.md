---
title: Plan-prose contract claims and the executable check that enforces them must assert the same dimensions
date: 2026-05-16
category: integration-issues
module: planning, terraform, jq, ci-gates
related_prs:
  - https://github.com/jikig-ai/soleur/pull/3891
related_learnings:
  - knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md
  - knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md
tags: [plan-quality, jq, terraform, ci-contracts, review-gate]
---

# Plan-prose contract vs executable check — dimension drift

## Problem

PR #3891 (CI Required ruleset widening via Terraform) shipped both a plan and a runbook (`infra/github/README.md`) plus an ADR (`ADR-032`) that documented a 3-dimension load-bearing pre-apply gate:

> "before_count: 5, after_count: 14, actions: ["update"], with zero other property changes"

But the implemented jq probe was:

```sh
terraform show -json tfplan.binary | jq '
  .resource_changes[]
  | select(.address == "github_repository_ruleset.ci_required")
  | .change.after.rules[0].required_status_checks[0].required_check
  | length
'
# Expected: 14
```

The probe asserts **one** dimension (`after_count`). The prose contract claims **three** dimensions (`actions`, `before_count`, `after_count`). The drift was invisible at authoring time because each surface (plan body, README, ADR-032) carried the same prose-vs-code pair — author and implementer both copied the prose contract without validating that the executable check actually drilled the named keys.

Failure modes the as-shipped probe would have passed silently:
- `actions: ["replace"]` instead of `["update"]` — an unexpected resource recreate would still produce a 14-element `after_count`.
- `before_count` other than 5 — if the live ruleset had been mutated between import oracle capture and plan-diff probe, a different baseline would still produce 14 if the after-state matches.
- Unrelated property drift on the same resource — bypass_actors reorder, condition tweak, integration_id phantom diff — none affect `required_check | length`.

Multi-agent post-implementation review (code-quality-analyst) caught it pre-merge.

## Root cause

Plan-prose contracts and executable checks live in separate paragraphs of the same document. The prose makes a claim ("the probe asserts X and Y and Z"). The code-block contains a check (`... | length`). Both look correct in isolation. Neither side carries a mechanical assertion that the named-in-prose dimensions are the ones drilled-in-code. The plan author reasons "I want a probe that asserts X, Y, Z" and writes prose to that effect, then writes a `jq | length` because it's the canonical "count blocks" idiom — without re-checking the prose contract against the canonical idiom's actual output.

This is a generalization of the **handshake schema drift** pattern (`2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`) — there, a skill instructed an operator to write a row into a file, and the row template drifted from the schema documented in that same file. Here, the same class: a contract documented in prose, an enforcement codified in shell/jq/sql/bash, drift between the two.

## Solution

**At plan-authoring time:** when a `## Test Strategy`, `## Acceptance Criteria`, or `## Sharp Edges` section names ≥2 invariants ("X equals Y **and** Z equals W"), the executable check below it must explicitly drill each named key:

```sh
# BAD — single-dimension drill claiming N-dimension contract:
... | jq '.change.after.rules[0].required_status_checks[0].required_check | length'

# GOOD — N-dimension drill matching the N-dimension prose contract:
... | jq '{
    actions:      .change.actions,
    before_count: (.change.before.rules[0].required_status_checks[0].required_check | length),
    after_count:  (.change.after.rules[0].required_status_checks[0].required_check  | length)
  }'
```

The output shape (an object with N keys, one per documented dimension) becomes the assertion shape — any drift on any key produces a visible diff at probe time, not a silent pass.

**At plan-review time:** for each prose-claimed invariant, grep the corresponding code block for the named key. If the prose says "asserts `actions: [update]`", the code must contain a literal `.actions` selection. If it says "before_count == 5", the code must select `.before.` somewhere. A `| length` at the end with no upstream key selection is a single-dimension probe regardless of how many dimensions the prose names.

**At review-agent prompt construction:** include the prose contract verbatim AND the code block, and ask the agent "does the code select every key named in the prose?" Code-quality-analyst caught PR #3891's gap because the spawn prompt asked it to check "whether each section earns its place" — that framing led it to read the prose claim and the code together. Without that framing (e.g., a code-only review), it would have looked at the jq and approved it as syntactically correct.

## Generalization beyond Terraform

Same pattern applies to:

- **Shell guards:** comment says "exits non-zero on (X or Y or Z)", script only checks `[[ -n "$X" ]]`.
- **Test assertions:** docstring says "verifies returned shape has fields A, B, C", test asserts only `result.A === expected`.
- **Migration WHERE clauses:** comment says "idempotent and matches normalizer N", `WHERE col <> N(col)` catches drift on re-runs but not on first-apply (see `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`).
- **CI workflow conditions:** workflow comment says "runs on PRs touching paths A, B, C", `paths:` filter lists only A.

The general rule: when prose enumerates a set, the enforcement codified next to that prose must select-and-assert each member of the set. A `| length` / `--count` / `wc -l` at the end is a one-dimension probe — it satisfies zero of the N dimensions the prose claims unless the prose claim is literally "the count is N".

## Session Errors

1. **Miscategorized job-source workflow** — claimed `Bash fixture tests for guard scripts` lived in `secret-scan.yml`; actual home is `pr-quality-guards.yml`. **Recovery:** AC5 verification grep returned MISSING, surfaced the discrepancy, fixed inline comment in `ruleset-ci-required.tf`. **Prevention:** When authoring a comment claiming a workflow's source, run `grep -rln "$JOB_NAME" .github/workflows/` to pin ownership.

2. **PreToolUse security_reminder_hook false-block** — first Edit to `infra-validation.yml`'s `paths:` filter was hook-blocked despite the edit not touching `${{ }}` interpolation. Retry of the same Edit on the next call succeeded. **Recovery:** Retry. **Prevention:** Acceptable as-is — the hook is precaution-by-design (any workflow edit triggers the reminder). A refinement to fire only on edits that actually touch shell-interpolation lines would reduce noise but is out-of-scope.

3. **Plan-time AWS env-var typo** — `tasks.md` Phase 2.1 had `AWS_ACCESS_KEY_SECRET` instead of canonical `AWS_SECRET_ACCESS_KEY`. **Recovery:** Caught by review code-quality-analyst; fixed inline. **Prevention:** Plan-authors run `grep -nE 'AWS_(ACCESS|SECRET)_' <plan-files>` and validate against the canonical two-name dictionary (`AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`) before committing the plan.

4. **Prose-contract vs executable-check drift (this file's subject).** **Recovery:** Caught by review code-quality-analyst; strengthened probe to assert all three dimensions. **Prevention:** see Solution section above.

5. **Wrong-direction Terraform rollback** — Phase 5 step 3 used `apply -refresh-only` which reconciles state FROM the API (the wrong direction for a rollback — would silently undo the operator's restored state). **Recovery:** Caught by review; replaced with `plan -out=tfplan-rollback.binary` followed by plain `apply tfplan-rollback.binary` with operator attestation. **Prevention:** When documenting a TF rollback path, distinguish "pull state from API" (`-refresh-only`) from "push restored state to API" (plain `apply`). Code review of any rollback-direction documentation should walk the data flow from R2 → state → API explicitly.

## Tags
category: integration-issues
module: planning, terraform, jq, ci-contracts
