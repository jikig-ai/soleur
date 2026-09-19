# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-19-fix-registry-dispatcher-derive-delivery-tracker-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None.

### Decisions
- Derive the delivered change from the watermark range (last successful run head → github.sha) intersected with commits touching cloud-init-registry.yml, resolved via `commits/{sha}/pulls` with an anchored `(#N)$` squash-suffix fallback; watermark lookup hoisted above the workflow_dispatch early-exit; proven range with no config touch yields no PR rather than blaming the last merge.
- One never-fail `change` derivation step feeds a single verdict/posting step with outcome-driven wording; the poll step no longer writes to the tracker.
- Artifacts post to the delivering PR(s) ∪ optional digit-validated `tracker` input via `gh api` issue-comments (issue/PR-agnostic; job-scoped `pull-requests: write`); an `action-required` p1 issue is created when no target is derivable.
- Plan-review cuts: comment dedupe, `range=identical` enum, `--max-lookups` flag, per-call timeout seam, 400-char cap, `(#N)` suffix strip, merged-entry preference, heredoc GITHUB_OUTPUT write. Kept `always()` on the timeout arm.
- Deepen hardening: targets re-validated at the posting loop, SHAs validated before URL use, `-f/-F` query fields, static jq, HTML-escaped SUMMARY_MD, control-char strip for annotations, `steps.change.outcome` surfaced.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; research agents (learnings-researcher, repo-research-analyst, functional-discovery, spec-flow-analyzer); plan-review panel (dhh, kieran, code-simplicity, cto); deepen agents (architecture-strategist, security-sentinel, test-design-reviewer, observability-coverage-reviewer, git-history-analyzer, framework-docs-researcher).

## Work Phase
- Status: complete (commits 48caae76f helper+suite, 3284cb942 workflow+ADR note, bbafda23a bookkeeping)
- Exit gate: `TEST_GROUP=scripts` — 441/445: 0 suite FAILs, 3 declined, 1 = the runner's write-boundary guard tripped by my own mid-run docs commit (3284cb942 → bbafda23a). Full run covered 3284cb942; the delta re-verified by `tests/scripts/test-registry-delivery-change.sh` 96/96 in isolation. Contention banner: one sibling suite in feat-one-shot-8330.
- Mutation battery: 16/16 rows killed (13 plan rows + seam-guard re-run + harness floor + stub-ignores-argv).
- All five AC12 suites [ok]; AC1–AC13 verified by their literal commands.

### Session Errors
1. Committed the bookkeeping commit while the exit gate was running (the skill's "confirm clean, then do not edit under it" rule) — the runner's write-boundary guard reported it as the run's one failure. Cost: a triage pass; no re-run needed since the delta was docs + one suite line re-run in isolation.
2. First helper draft called `resolve_pr_for_sha` as `$(...)`, discarding `BY_SUBJECT` (the documented subshell trap); caught by the suite on the first GREEN attempt.
3. `@tsv` over a `tojson` subject re-escaped its backslashes so any subject with `"` failed to decode; switched the listing transport to base64. `sed` byte-range bracket for U+2028 needed `LC_ALL=C`.
