# Tasks — feat-one-shot-9510-stock-gate-recovery

Plan: `knowledge-base/project/plans/2026-10-06-fix-stock-gate-class-aware-recovery-plan.md`
Issue: #9510 | PR: #9634

## Phase 1 — RED (failing tests first)

- [ ] 1.1 Extend `tests/scripts/test-stock-preflight-gate.sh`:
  - `_STOCK_LAST_CLASS` set per abort arm; `orderable` on success; reset/`none`/`mixed` folding in `stock_preflight_gate`.
  - `stock_abort_closing` prints class-aware text per class (stock keeps wait-and-re-fire; config/unreachable/malformed/none distinct).
  - `stock_recovery_report`: fresh fetch per planned create (seam counter), class named, doctrine block, non-zero exit; state-json arm maps absent vs present/tainted.
  - Workflow-parity assertions: every `stock_preflight_gate` call site pairs with `stock_abort_closing`; every enumerated apply failure branch names `stock_recovery_report`.
  - Re-measure the assertion floor.
- [ ] 1.2 Run the suite; confirm the new cases are RED for the right reason.

## Phase 2 — GREEN: the lib

- [ ] 2.1 `tests/scripts/lib/stock-preflight-gate.sh`: `_STOCK_LAST_CLASS` propagation on every arm; extract the planned-create `@tsv` jq into a shared helper used by both `stock_preflight_gate` and `stock_recovery_report`.
- [ ] 2.2 `stock_abort_closing <label>` — class-aware `::error::` closing line; advice table lives in the lib.
- [ ] 2.3 `stock_recovery_report <plan_json> [state_json]` — fresh re-read per planned create, per-class line, absent/tainted arm from optional state JSON, retained-volume doctrine, always non-zero.
- [ ] 2.4 Run the suite to GREEN. Grep the suite for every new emitted token (per the 2026-10-05 learning).

## Phase 3 — GREEN: the workflow

- [ ] 3.1 `.github/workflows/apply-web-platform-infra.yml`: replace the eight hand-written closing echos with `stock_abort_closing <label>` (+ kept host-specific tails); class-aware advisory-probe prefix; wire `stock_recovery_report` into the six destroy-first apply failure branches and the two additive creates; add the missing `inngest-host-replace` failure branch.
- [ ] 3.2 `wc -c` after each edit; keep the file under 490,000 B (measured headroom ~4.3 KB at branch point).
- [ ] 3.3 `actionlint` (if installed) + `git diff --check` + YAML parse.

## Phase 4 — mutation battery

- [ ] 4.1 Scratch-mirror `tests/scripts/`; drive each Guard Contract row RED; paste row/verdict table into the PR body.

## Phase 5 — runbooks

- [ ] 5.1 `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — rewrite the `stock-preflight ABORTED` row for the class-aware closing line.
- [ ] 5.2 `web-host-replace.md` "If the apply fails partway" + `registry-host-replace-dispatch.md` — document the recovery-read block.

## Phase 6 — verify

- [ ] 6.1 `bash tests/scripts/test-stock-preflight-gate.sh` green; `test-eu-location-allowset-parity.sh`; workflow-grep suites; `git grep -n 'stock-preflight ABORTED'` shows only helper-emitted lines.
- [ ] 6.2 Never dispatch the apply workflow; never run `terraform apply`.
