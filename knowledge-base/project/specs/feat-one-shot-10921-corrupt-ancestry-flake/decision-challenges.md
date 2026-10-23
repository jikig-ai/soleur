# Decision Challenges — feat-one-shot-10921-corrupt-ancestry-flake

Headless run (planning subagent, no Agent/Task tool). Per technical-ruling-delegation.md,
technical rulings that would normally go to `soleur:engineering:cto` are recorded as
`pending - assumed: <default>`; `ship` renders these into the PR body and files an
`action-required` issue.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Corrupt-graph construction mechanism (never-written oid via `hash-object`/`update-ref` vs repack-aware `rm` vs `git fsck` probe) | technical | pending - assumed: never-written oid via `hash-object -w` + `update-ref`. Measured on git 2.56: packed-store `rm` reproduces the exact CI failure (Arm B); forged-parent construction is layout-immune and survives `git repack -ad` (Arm C); repack-aware deletion still reasons about store layout — the assumption that failed. |
| Which preconditions are skip-eligible | technical | pending - assumed: only the `--merged`/`merge-base` walk-contract (rc0 + `error:`/`Could not read` on stderr) is skip-eligible; construction invariants (dead oid readable, forge not taking) are harness-bug FAIL, per ADR-188's discriminating-absence + harness-rung rules. |
| Cross-run persistence observer for the new `SKIP (loud):` producers — extend `t5-skip-persistence-bound-7510.sh` (add `pr-quality-guards.yml` run-source + `g1b.`/`g2b.`/`fl.` markers) vs a sibling probe in the same monitor workflow vs defer to a follow-up | technical | pending - assumed: extend the standing probe in this PR (the probe's own comment: "a probe that goes quiet on the arm the fix creates is worse than no probe"). The sibling-probe alternative is lower regression risk on a working instrument at the cost of ~100 duplicated machinery lines; deferral leaves a new skip producer unobserved — the exact residual ADR-188 accepts only with a bound. |
| Brand-survival threshold (`none` vs `aggregate pattern` vs `single-user incident`) | technical | pending - assumed: `aggregate pattern`. The diff is CI-internal; realized harm requires both this change weakening coverage AND a subsequent real tag anomaly — a coverage-regression pattern, not a single merge's breach. If ruled `single-user incident`, add `requires_cpo_signoff: true` and CPO review before `soleur:work`. |
| Agent spawns skipped (research fan-out, spec-flow, advisor consult, domain leaders, plan-review panel) — subagent context without Agent tool | technical | pending - assumed: ran inline (research, premise validation, empirical reproduction, gate evaluation, self-review). `Reviewed-Coverage: inline-fallback` — no independent review ran. |

## Not Yet Specified candidates

- Whether the skip persistence probe's second run-source should sample `pull_request` head runs,
  `merge_group` runs, or both — implement-time resolution acceptable (the suite is identical on
  both legs; sampling either bounds the residual).
