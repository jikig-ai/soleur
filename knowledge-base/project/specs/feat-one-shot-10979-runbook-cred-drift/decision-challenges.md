# Decision Challenges — feat-one-shot-10979-runbook-cred-drift

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Replacement recipe form for the runbook blocks: issue body's explicit-export single-loader recipe vs. nested-loader canonical form + `AWS_*` export | technical | pending - assumed: nested loader + Tier-B `AWS_*` export (matches the "canonical form" pointer every existing annotation note already carries; the issue-body recipe is the operator-verified equivalent and is quoted in the plan so the implementer can fall back to it verbatim) |
| Adjacent stale sites found by repo-wide grep (`infra/github/README.md` ×6 — includes `state push`/`import`/`apply` writes on the same bucket; `apps/web-platform/infra/sentry/README.md` — read-only, still works; `apps/cla-evidence/infra/bootstrap.sh` + `apps/web-platform/scripts/bootstrap-live-verify.sh` — executable code, outside docs-only scope) | operator (scope) | pending - assumed: strict ARGUMENTS scope — descoped here per scope item 4's `runbooks/` bound and the docs-only constraint; RECOMMENDED follow-up issue covering the four paths (the `infra/github/README.md` write-path blocks reproduce the same mid-apply 403) |
| `inngest-luks-cutover-6894.md` `tf()` wrapper — does it need the Tier-B annotation (ask 5's evaluation question)? | technical | resolved: YES — the wrapper feeds the backend from ambient `AWS_*` only and step 5's `tf state push` is a write; annotation prescribed (plan item, AC-5) |
| Dated learnings — supersession notes warranted (ask 5's evaluation question)? | technical | resolved: YES for all four, scoped "in part, for writes" — the old recipe remains correct for read-only invocations (plan item, AC-7) |
| Scoped advisor consult (plan Phase 4.5) and plan-review panel (DHH/Kieran/code-simplicity) — no Task-capable subagent available in this planning context | process | pending - assumed: sequential self-review performed (`Reviewed-Coverage: sequential-fallback`); no independent review ran — disclosed in the plan's Dependencies & Risks |

## Notes

- No operator-answerable questions (money, scope authorization, priority, irreversible prod mutation, legal, brand) arose; all forks above are technical or process rulings recorded here per the headless-pipeline channel.
