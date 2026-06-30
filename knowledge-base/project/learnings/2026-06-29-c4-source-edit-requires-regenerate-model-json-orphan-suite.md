---
date: 2026-06-29
category: workflow-patterns
module: architecture-c4
problem_type: build-error
severity: low
symptoms:
  - "c4-model-freshness.test.sh FAILs: model.likec4.json is STALE"
  - "c4-code-syntax + c4-render tests pass but the full suite still goes red"
root_cause: edited .c4 sources without regenerating the committed model.likec4.json artifact
tags: [c4, likec4, architecture, orphan-suite, full-suite-gate, generated-artifact]
related:
  - 2026-06-29-verify-proposer-edit-shape-before-binding-a-verification-gate
---

# Learning: Editing `.c4` sources requires regenerating `model.likec4.json` (full-suite-only orphan gate)

## Problem

The skill-eval-gate build added an `evalharness` component + a `compound -> evalharness` edge to
`knowledge-base/engineering/architecture/diagrams/model.c4` and `views.c4`. The two C4 tests run by
name in CI/touched-file loops — `c4-code-syntax.test.ts` and `c4-render.test.ts` — both passed. But
`scripts/test-all.sh` went red on `plugins/soleur/test/c4-model-freshness.test.sh`: the committed
`model.likec4.json` (a generated render of the `.c4` sources) was stale — `45 elements / 62 relations`
committed vs `46 / 63` freshly rendered, the diff being exactly the new component + edge.

## Solution

After ANY edit to a `.c4` source, run `bash scripts/regenerate-c4-model.sh` and commit the updated
`model.likec4.json` in the same change. The freshness test compares a fresh render to the committed
JSON and fails on any drift.

## Key Insight

`c4-model-freshness.test.sh` is an **orphan suite** — it is NOT one of the by-name C4 tests a
touched-file or per-PR loop runs, so editing `.c4` and running only the obvious `c4-*.test.ts` files
gives a false green. Only `scripts/test-all.sh` (the work Phase 2 full-suite exit gate) discovers it.
This is the exact value of the full-suite gate: it catches generated-artifact staleness that the
touched-file set never sees. Treat `model.likec4.json` like a lockfile — it is generated from the
`.c4` sources and must be regenerated + committed whenever they change.

## Session Errors

- **Edited `.c4` sources without regenerating `model.likec4.json`** — Recovery: `bash scripts/regenerate-c4-model.sh` + commit; freshness test green. Prevention: regenerate the committed model JSON in the same edit cycle as any `.c4` change (this learning); the full-suite exit gate is the backstop.

## Tags
category: workflow-patterns
module: architecture-c4
