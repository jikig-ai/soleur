# Decision Challenges — feat-one-shot-12156-oracle-fast-lane (#12156)

Pipeline-mode plan; no Task/Agent tool available, so technical rulings are recorded
`pending - assumed` per the one-shot technical-ruling contract. Operator-class rows
surface at ship time.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| T1 — merge_group reduced set narrows ADR-276 Decision 5 ("merge_group may not select") | technical | pending - assumed: proceed via a dated ADR-276 amendment in the same PR (the issue explicitly asks for the merge_group arm; the amendment names the lever, kill-switch, lock, exit criterion and census link per ADR-276 3(g)); the push arm is protected by tightening push-dedupe so an oracle-reduced green never elides the push run |
| T2 — pipeline planning artifacts in the lane surface (`knowledge-base/**/*.md` + root `*.md`) | technical | pending - assumed: include the stage-1 doc allowlist verbatim — every real repair PR carries planning `.md`s (PR #12128 measured) so a strict oracle-only surface never fires; residual risk is an edge-selected suite that reads a changed `.md` being skipped, bounded because content gates (credential-path-guard, markdown-lint, rule-body-lint) still run as required contexts |
| T3 — census/validation manifest membership for `oracle-index-check` | technical | pending - assumed: `scripts/ci-oracle-lane-suites.txt` = every registration whose SUT is the oracle/selector machinery (lint-orphan-test-suites, test-all-affected-{a..d}, test-all-group-affected, test-affected-derive{,-cache}, test-affected-kb-consumers, ci-pr-affected-replay-{a,b,c}, ci-pr-selection, ci-pr-affected-preactivation); Guard 4 pins non-empty + live-registration parity |
| T4 — oracle merge_group green must not elide the push run | technical | pending - assumed: extend the push-dedupe jobs-API proof to require all five heavy legs `success` (skipped leg → `elide=false`); keeps main's post-merge full battery as the oracle's backstop |
| T5 — new driver `scripts/ci-oracle-lane.sh` vs extending `scripts/ci-pr-selection.sh` | technical | pending - assumed: new driver — S4's driver is pull_request-scoped and doc-only by design and still activation-locked; a separate lever keeps both independently switchable and revertible |
| T6 — `e2e` and `encryption-posture` are never in the oracle skip set | technical | pending - assumed: keep both running — `e2e` is a standalone required context whose merge_group producer cannot be `if:`-gated per probe-merge-group-coverage.sh; `encryption-posture` is cheap and keeps the aggregator loop honest |
| O1 — CPO sign-off at `single-user incident` threshold | operator (sign-off) | pending - `requires_cpo_signoff: true` is set in the plan frontmatter; headless run so the sign-off could not be collected — confirm CPO has reviewed the plan (or the 2026-10-12 S4 brainstorm's identical threshold framing) before `soleur:work` |
| O2 — activation authorization (set `CI_ORACLE_LANE=on`, later remove `ORACLE_LANE_LOCKED=1`) | operator (irreversible-authorization / production-mutating) | pending - assumed: dark launch only in this PR; activation is a separate authorized step after ≥1 real oracle repair is observed — tracked on the #10865 observation window |

## BLOCKED rows

None — every ask mapped and every inferred item carries a justification in
`## Scope Check` → `### Plan-Item Provenance`.
