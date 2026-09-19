# Decision Challenges — feat-one-shot-marketplace-drift-heartbeat-checkout (plan-review, 2026-09-18)

Plan-review panel (DHH, Kieran, code-simplicity, CTO devex; spec-flow-analyzer ran at plan Phase
3; a scoped advisor consult ran at plan Step 4.5) on
`knowledge-base/project/plans/2026-09-18-fix-marketplace-drift-heartbeat-local-action-resolution-plan.md`.
Headless run (one-shot pipeline): Mechanical findings were auto-applied to the plan; the item
below argues the operator's stated scope should shrink, so it is surfaced here per ADR-084 rather
than decided by the pipeline. `ship` renders this into the PR body and files it as an
`action-required` issue.

## User-Challenge decisions (operator to adjudicate)

| # | Decision | Pipeline default | Challenge |
|---|---|---|---|
| UC-1 | Keep the `-w '\nsentry-heartbeat: http_code=%{http_code}\n'` line added to `.github/actions/sentry-heartbeat/action.yml` (Proposed Solution §2, AC8, the "primary arm" clauses of AC9/AC16)? | **Keep** — it is the only way to satisfy the operator's stated constraint 4 ("show the sentry-heartbeat step log containing the curl to the Sentry Crons endpoint with an HTTP 2xx"); the scoped advisor consult also said keep (output-only, one file, still prints under `-f` on non-2xx). | DHH and code-simplicity both say **cut**: the plan's own thesis is that a step log is not evidence (the `Can't find 'action.yml'` line sat in 36 consecutive logs unread), the Sentry `checkins/` row is the gate, `-fSs` already prints the failure code, and the line touches all 14 call sites for one site's diagnostic while bifurcating AC9/AC16 into primary/fallback arms. |

**5-line frame for UC-1:**

1. **Your direction:** the PR must show, in the step log, the curl to the Sentry Crons endpoint with an HTTP 2xx.
2. **What the panel found:** that log line is a diagnostic, not a control; the API row (AC10/AC16) is what proves recovery, and the `-w` edit is the only composite change and the only cross-site change in the PR.
3. **Cost of keeping:** one output-only line in a shared composite; AC8; two-arm wording in AC9/AC16 for the fallback case.
4. **Cost of cutting:** constraint 4's step-log clause becomes unsatisfiable; evidence reduces to "0 resolution errors + `outcome=success`" in the log plus the API row.
5. **Default if you say nothing:** keep (the plan ships with the `-w` line).

## Mechanical findings applied to the plan (for the record, no decision needed)

- Row 8 contradiction (real-file copy vs synthesized twin) → replaced by row 9: mutate a copy of the live tree back to `./`, valid pre- and post-merge (Kieran P1-2, DHH, code-simplicity).
- Floor counted `./` only → `MIN_SAME_REPO_STEPS` over `./` + `$/`; file-count floor dropped (DHH, Kieran P2-6, code-simplicity).
- Four-bucket classification → two buckets plus one named reject (`$/…@ref`); rows with 0 members (`with: path:`, `with: repository:`, remote/docker classification) cut; lookalike rows collapsed to one anchored case (DHH, code-simplicity).
- Suite tail must be the `issue-write-scope` shape so `scripts/guard-vacuity-floor.test.sh` scores it constructible (Kieran P1-1).
- AC1/AC7/AC8 anchored on syntax, not bare tokens; AC2 given an executable one-liner; AC11 de-duplicated; AC15 no longer prescribes a full-shard run that refuses on a shared host (Kieran P1-3, P2-7, P2-10; CTO F4).
- Credential path flipped to the ADR-031 workstation token (`soleur/prd` `SENTRY_IAC_AUTH_TOKEN`, measured 200), `prd_terraform` no longer enshrined (CTO F5).
- Post-merge block reuses the run `/ship` already dispatches and gates DONE on the `checkins/` row; the inline reader is acknowledged as deliberate (code-simplicity, CTO F6, spec-flow P0).
- Reference-form posture + `SOLEUR-DEBT:` marker + rhysd/actionlint#711 citation in the workflow comment; +1 actionlint finding posted to #7042 (CTO F1, F3).
- Learning scoped to the two novel points and made conditional on `/compound` (code-simplicity).
- Fallback arm files a tracking issue for the `$/` migration (Kieran P2-9).
