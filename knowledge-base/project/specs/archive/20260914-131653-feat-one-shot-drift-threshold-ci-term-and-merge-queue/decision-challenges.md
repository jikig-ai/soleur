# Decision challenges — feat-one-shot-drift-threshold-ci-term-and-merge-queue

Persisted by `plan` (headless) per ADR-084. `ship` renders these into the PR body and files the
`action-required` issue; nothing here was applied.

## UC-1 — Delete the per-PR fan-out ledger and its test (DHH, plan-review 2026-09-14)

- **Class:** user-challenge (a cut of operator-requested scope).
- **Operator's stated direction (default, kept):** Item 2 option (b) — "require a named
  consequence before adding a per-PR workflow, and audit the existing 23" — the filing-time
  lever ADR-216 applied to issues, applied to workflows.
- **The challenge:** the ledger is a hand-maintained second copy of `.github/workflows/`
  (job count, `paths`, `cancel`) whose one non-derivable column, "consequence", is validated as
  ≥ 4 words; its lifetime effect is one extra line per workflow diff plus a ~300-line suite,
  vacuity floors and a meta-guard bump. If fan-out growth must be bounded, one assertion in an
  existing suite — `sum(len(jobs) for pull_request-firing workflows) <= 52` — is ~20 lines.
- **Why it was not applied:** `code-simplicity-reviewer` (asked the same per-mechanism
  question) kept the ledger as the only mechanism satisfying property P4 ("no workflow can add a
  per-PR-push trigger without a recorded, named consequence"); a bare sum bounds the count but
  records no consequence, which is the half of P4 the brief asked for. The simplification panel
  is split, so the operator's direction stands.
- **What the operator decides:** keep the ledger (current plan), or replace it with the sum
  assertion and drop P4's "named consequence" half.
