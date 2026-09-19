# Decision challenges — feat-one-shot-8279-dispatcher-derive-tracker

Taste / User-Challenge findings surfaced at plan-review (headless pipeline: persisted here for `ship` Phase 6 to render into the PR body and file as `action-required`). Mechanical findings were auto-applied to the plan and are not listed.

## T1 — Compose the verdict body in a second helper script (CTO devex advisory)

- **Class:** Taste (structural preference; no correctness gap).
- **Finding:** the rewritten refusal step binds ~10 outputs and composes four `WHAT`/`WHY`/`STATE` arms plus a posting loop and an issue-create fallback in YAML — a second ~150-line `run:` block in a workflow that already has one (the gate). Moving the composition (outcome → `KIND`/`WHAT`/`WHY`/`STATE`, marker, body) into `scripts/registry-delivery-verdict.sh` (env in, body on stdout) would make it unit-testable in the same suite and turn the AC9/AC11c greps into test rows.
- **Why not applied now:** the simplification panel (DHH + code-simplicity) in the same review cut mechanisms in the opposite direction; adding a second helper on a P3 chore runs against that. The plan keeps composition in YAML with an env-only binding discipline and grep-backed ACs.
- **Operator decision:** accept as-is (default), or ask `/work` to split the verdict composition into `scripts/registry-delivery-verdict.sh` with rows in `tests/scripts/test-registry-delivery-change.sh`.

## T2 — Trim the YAML-shape acceptance criteria (DHH)

- **Class:** Taste.
- **Finding:** AC5/AC5a/AC5c/AC6/AC7/AC11a-c assert the shape of the YAML with PyYAML one-liners; DHH would collapse them to "actionlint + `bash -n` + the two guard scripts pass".
- **Why applied only partially:** each retained AC pins a property a diff reader cannot see (step order, `if: always()`, the watermark hoist above the manual early-exit, injection-free `env:` binding). The mutation-row list and the helper's test rows were trimmed as DHH asked.
- **Operator decision:** none required; recorded so the trade-off is visible.
