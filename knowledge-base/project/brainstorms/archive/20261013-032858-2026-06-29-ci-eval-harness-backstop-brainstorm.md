---
date: 2026-06-29
topic: CI backstop — gated classifier-skill eval-harness coverage
issue: 5703
status: complete
lane: single-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: CI backstop for gated classifier-skill edits (#5703)

## What We're Building

A deterministic (no-API) CI guard that keeps the **eval-harness gated-skill
registry honest**, closing the only residual bypass left after the v1 gate
(#5702/#5701):

1. **Registry-completeness test** — a new `*.test.sh` under
   `plugins/soleur/skills/eval-harness/test/` that asserts **bidirectional parity**
   between the `eval-gate:block:<id>:start` markers present across source files and
   the `block_id` entries in
   [`gated-skills.json`](../../../plugins/soleur/skills/eval-harness/gated-skills.json):
   every marker in a source file has a registry entry, and every registry entry's
   marker is present in its named `source_file`. Fail-closed with a clear
   remediation message.
2. **Registry-driven round-trip** — refactor
   `test/extract-block.test.sh` to derive its target loop from `gated-skills.json`
   instead of the hardcoded `for target in go-routing ticket-triage` (and its inline
   prompt-path ternary), so adding a registry entry auto-extends round-trip coverage.

Both run for **free** in the existing `scripts` test shard — `scripts/test-all.sh:186`
already globs `plugins/soleur/skills/*/test/*.test.sh`, which `ci.yml:375` runs on
every PR. **No new workflow, no API spend in CI, no branch-protection change.**

## Why This Approach

**The premise shifted under verification.** The issue asks for "a required CI check
that re-runs eval-harness arms on any PR touching a gated classifier skill and blocks
merge on a held-out regression." Two facts reshaped that:

- **Operator decision (this session):** CI stays **deterministic-only** — no API spend
  in CI. The semantic corpus eval (LLM, ~110–125 calls/target, flake-prone) remains a
  manual/opt-in local run. This removes the need for any target-task-less corpus mode
  in `eval-gate.cjs`.
- **The deterministic check already exists.** `ci.yml` → `test-all.sh scripts` →
  `extract-block.test.sh` already runs the projection-freshness round-trip on **every
  PR**. A manual edit to `commands/go.md`'s routing block that forgets to regenerate
  the projection **already fails CI today**. The SKILL.md claim ("they run under the
  standard test-all.sh discovery") was verified true against `test-all.sh:186`.

So the issue's stated mechanism is **substantially already shipped**. The genuine
residual gap is narrower: the round-trip test's target list is **hardcoded**, and
**nothing guards registry↔marker completeness**. Add a 3rd gated classifier's marker
without a `gated-skills.json` entry → its projection is silently unchecked, and the
hardcoded test loop wouldn't cover it either. That is precisely the "manual edit
bypasses the gate" failure class #5703 exists to close, generalized to "add/rename a
gated classifier." Approach A closes it with the smallest honest delta.

**Why not a dedicated path-scoped workflow (Approach B):** a separate
`eval-harness-gate.yml` triggered on registry-derived `paths:` would duplicate what the
`scripts` shard already enforces on every PR. The existing shard *is* a required check;
a distinctly-named one is cosmetic. Rejected as over-build.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Proceed vs. wait for trigger | **Proceed (proactive)** | #5703's re-eval criteria are a two-part AND: "#5702 ships" (✅ today) AND "observe ≥1 bypass" (✗ — gate is hours old). Operator **deliberately overrode** condition 2: a backstop is a preventive control and #5701 context is warm. |
| CI cost posture | **Deterministic-only, no API in CI** | Zero flake, fork-safe, no secret dependency. Semantic corpus eval stays manual/opt-in. |
| Scope | **Completeness guard + registry-driven round-trip** | The per-PR deterministic round-trip already runs; close the real residual (registry/marker drift + hardcoded target loop). |
| New workflow? | **No** | Existing `scripts` shard (`test-all.sh:186`) already discovers `skills/*/test/*.test.sh`. Reuse it. |
| Registry as source of truth | **gated-skills.json** | Single manifest; the new test and the refactored round-trip both read from it. |

## Open Questions

- **Marker scan exclusion:** the completeness scan must exclude
  `eval-harness/SKILL.md` and `README.md` (they *describe* the marker syntax in prose).
  Resolve at plan time: scan `gated-skills.json` `source_file` set for the registry→marker
  direction, and `git grep eval-gate:block:*:start` minus the eval-harness skill dir for
  the marker→registry direction. (Implementation detail, not a blocker.)
- **Remediation message wording** — the failing test should name the exact fix
  (`add the block to gated-skills.json` / `run gen-skill-prompt.cjs --all`). Plan-time.

## User-Brand Impact

- **Artifact:** the eval-harness gated-classifier registry guard (the CI safety net over
  `soleur:go` routing + `ticket-triage` P-level classifier prose).
- **Vector:** a silently-unchecked classifier regression — a gated block edited or a new
  classifier added without its projection/eval coverage wired — mis-routes a user's
  request or mis-prioritizes their ticket with no CI signal.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). Lane scoped to **single-domain
(Engineering)** in practice: this is internal CI/test tooling with no user-facing
surface, no credentials, no data, and no UI. The CTO lens is applied via the technical
grounding above; a full CPO/CLO/CTO triad would be disproportionate to a two-file
deterministic test change and would not change the outcome.

## Domain Assessments

**Assessed:** Engineering (applied inline). Marketing, Operations, Product, Legal,
Sales, Finance, Support — not relevant (internal CI/test tooling, no external surface).

### Engineering

**Summary:** The deterministic projection-freshness backstop already runs per-PR via
the `scripts` test shard; the net-new value is a registry-completeness invariant plus
making the round-trip test registry-driven. No new workflow, no API, no branch-protection
change. Fail-closed, runs free in the existing shard.

## Session Errors

- **Condition 2 of #5703's re-evaluation criteria was not satisfied** (no observed
  bypass; the v1 gate shipped hours earlier). It was **deliberately overridden** by the
  operator, not silently treated as met. #5703 should be updated to record that the
  per-PR deterministic gate already runs via `test-all.sh`, and that this PR closes the
  registry-completeness residual rather than building the originally-imagined API-eval
  workflow.
