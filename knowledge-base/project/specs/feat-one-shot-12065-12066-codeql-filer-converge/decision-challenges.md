# Decision Challenges — feat-one-shot-12065-12066-codeql-filer-converge

Plan: `knowledge-base/project/plans/2026-11-04-feat-codeql-filer-convergence-plan.md`
Context: Devin one-shot planning phase, depth-1 — the CTO agent cannot be spawned on this harness, so genuine technical forks are recorded as `pending - assumed:` defaults per the technical-ruling-delegation rule. The convergence design itself is already CTO-ruled (issue #12004 comment 6625921398, 2026-11-04); rows below are residual forks the ruling left open, not re-litigation.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Converge to one filer (gate script sweep mode; cron delegates) | technical | Ruled by CTO agent, 2026-11-04 (issue #12004 comment 6625921398): one implementation, two triggers; `close-orphans` stays a separate job. Implemented as designed. |
| Degraded-issue title in sweep mode | technical | `pending - assumed: codeql-sweep-degraded` — ruling 12004.2 rejected sharing `codeql-gate-degraded` for attribution; post-convergence the same rationale maps to trigger attribution. Same upsert machinery, `LABELS_P2`, and `action-required` digest routing either way; only the title differs. |
| Locus of SHA→main-HEAD resolution | technical | `pending - assumed: script resolves via timeout 60 gh api repos/{repo}/commits/main + .sha re-validation; the workflow does NOT pass SHA` — honors "SHA optional/resolved to main HEAD"; exercises the path in production; evaluates main even for off-main dispatches. Alternative (workflow passes `github.sha`) leaves resolution dead code. |
| Sweep job timeout sizing | technical | `pending - assumed: DEADLINE_SECONDS '240' + timeout-minutes 10` — applies the gate's own A21 invariant (job_timeout*60 ≥ deadline + 300) to the new caller; the default 1800 s deadline under a 5-minute job kill would silence the degrade path — the failure the ruling exists to kill. |
| check-alerts exit semantics + `needs:` edge | technical | `pending - assumed: sweep inherits gate verdict semantics (exit 1 when it files; a filing day skips close-orphans until the next green run)` — consequence of "the gate's implementation becomes the only one"; the filed action-required issue is the durable page. `needs:` unchanged (ruled: close-orphans stays a separate job). |
| `dry_run` dispatch input on codeql-to-issues.yml | technical | `pending - assumed: add it` — sole zero-write verification path for the rewired caller post-merge; mirrors the gate workflow's existing input contract. Marked `inferred` in the plan's provenance table. |
| Deferral candidate (recorded, no issue filed) | technical | `pending - assumed: extracting close-orphans into a tested script is out of scope` — #12066's prescribed fix is one predicate; the wiring suite's parsed-YAML pins cover the regression class. If a future pass extracts it, the shim gains `gh api .../alerts/N` + `gh issue comment/close` support. |

## Not Yet Specified candidates

None.
