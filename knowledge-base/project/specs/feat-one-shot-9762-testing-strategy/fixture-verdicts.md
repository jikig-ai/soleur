# Fixture verdicts — AC-3 evidence (issue #9762)

Recorded 2026-10-08 on branch `feat-one-shot-9762-testing-strategy`.
The extended `## Pyramid & Fast-Feedback Check` checklist in
`plugins/soleur/agents/engineering/review/test-design-reviewer.md` was applied
to each committed fixture by the implementing agent (the review lane reads the
agent body and evaluates the diff — the same path `soleur:review` agent 13
takes).

## Fixture 1 — `plugins/soleur/test/fixtures/test-pyramid/slow-e2e-no-justification.diff`

Adds `apps/web-platform/e2e/checkout-flow.e2e.ts`.

### Pyramid

| File | Layer | Signals | Verdict | Confidence |
|------|-------|---------|---------|------------|
| `apps/web-platform/e2e/checkout-flow.e2e.ts` | e2e | dedicated `e2e/` dir + `*.e2e.ts` extension, `@playwright/test` import, `page.goto`, `page.waitForTimeout(15000)` | FAIL — no `pyramid-justified:` marker in file, no `## Test Pyramid` block in PR body | high |

**Verdict: FAIL** — cites the missing e2e justification marker. The
`waitForTimeout(15000)` carries a stated necessity in code (the payment-iframe
comment), so under the written WARN rule ("no stated necessity") it does not
draw the WARN arm — the FAIL is on marker absence alone.

## Fixture 2 — `plugins/soleur/test/fixtures/test-pyramid/fast-unit.diff`

Adds `apps/web-platform/test/order-total.test.ts`.

### Pyramid

| File | Layer | Signals | Verdict | Confidence |
|------|-------|---------|---------|------------|
| `apps/web-platform/test/order-total.test.ts` | unit | flat `test/` dir, `vitest` import, pure function, no I/O | PASS | high |

**Verdict: PASS** — unit-layer, no e2e or slow-cost signals; no justification
required at this layer.

## Mutation matrix (plan Guard Contract, Guard 1)

Executed during work against `plugins/soleur/test/test-pyramid-fixtures.test.sh`
(standalone run `bash plugins/soleur/test/test-pyramid-fixtures.test.sh`):

| Row | Mutation applied | Expected | Observed |
|-----|------------------|----------|----------|
| M1 | `pyramid-justified` lines deleted from `test-design-reviewer.md` | RED | rc=1 |
| M2 | `pyramid-justified:` inserted into `slow-e2e-no-justification.diff` | RED | rc=1 |
| M3 | e2e fixture's `+++ b/` path repointed `e2e/` → `test/` | RED | rc=1 |
| M4 | `assert_eq` overridden to always-pass | RED (instrument self-test) | rc=1 |
| M5 | `fast-unit.diff` truncated to comment-only | RED | rc=1 |
| M6 | trailing comment line appended to `fast-unit.diff` | GREEN | rc=0 |
| M7 | `assert_eq` overridden so FAIL never increments | RED (instrument self-test) | rc=1 |

All files restored after each row (`git status` clean of residue except the
intended diff).
