# Decision Challenges — feat-one-shot-6767-ruleset-entrypoint-preapply-gate

Persisted headless during plan-review (6-agent panel, 2026-07-22). `ship` Phase 6
renders these into the PR body and files an `action-required` issue for the
operator to adjudicate.

## UC-1 — Retrospective drift audit may be redundant (Taste / User-Challenge)

**Raised by:** DHH-rails-reviewer (HIGH) + code-simplicity-reviewer (MEDIUM).

**Challenge:** The retrospective drift audit (deliverable 3) is largely redundant.
The plan's own Research Reconciliation + Alternatives tables concede that all 4
zone siblings + the 1 account ruleset are **already in state**, so `terraform
plan` refreshes their entrypoints every run and the existing infra-drift detector
already surfaces a dashboard-added rule as ordinary drift. Historical loss (rules
deleted before a sibling's first apply) is already gone from live and
unrecoverable. So a standing `--audit` mode + a dispatch job + a runbook may
detect nothing that `plan` + the drift detector don't already show. The reviewers
recommend cutting the standing audit and, if desired at all, running a one-shot
confirmation `GET` loop once.

**Why it was NOT auto-applied:** This is **operator-requested scope** — #6767's
own corrective comment lists "**Drift audit (retrospective)**" as an explicit
checkbox deliverable ("Enumerate the five live entrypoints and diff against
config … Read-only, cheap"). Per the classifier, a simplify-cut of
operator-requested scope is never-Mechanical → surfaced, not silently removed.

**Current plan disposition:** the audit is KEPT but built as lean as the issue
frames it — a `--audit` mode of the existing gate script (no separate script),
run via one guarded read-only dispatch, findings posted once to #6767 (single
system-of-record). The heavier "standing/recurring" framing was already dropped.

**Operator decision needed:** keep the one-shot guarded audit as scoped, OR drop
the audit entirely and rely on `terraform plan` + the infra-drift detector for
the in-state siblings.
