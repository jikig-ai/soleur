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
- Exit gate: `TEST_GROUP=scripts` — 441/445: 0 suite FAILs, 3 declined, 1 = the runner's write-boundary guard tripped by my own mid-run docs commit (3284cb942 → bbafda23a). Full run covered 3284cb942; the delta re-verified by `tests/scripts/test-registry-delivery-change.sh` in isolation (96/96 then; 107/107 after the review pass). Contention banner: one sibling suite in feat-one-shot-8330.
- Mutation battery: 16/16 rows killed (13 plan rows + seam-guard re-run + harness floor + stub-ignores-argv).
- All five AC12 suites [ok]; AC1–AC13 verified by their literal commands.

### Session Errors
1. Committed the bookkeeping commit while the exit gate was running (the skill's "confirm clean, then do not edit under it" rule) — the runner's write-boundary guard reported it as the run's one failure. Cost: a triage pass; no re-run needed since the delta was docs + one suite line re-run in isolation.
2. First helper draft called `resolve_pr_for_sha` as `$(...)`, discarding `BY_SUBJECT` (the documented subshell trap); caught by the suite on the first GREEN attempt.
3. `@tsv` over a `tojson` subject re-escaped its backslashes so any subject with `"` failed to decode; switched the listing transport to base64. `sed` byte-range bracket for U+2028 needed `LC_ALL=C`.

## Review Phase
- Class: code (bash helper + suites); design-risk yes → design-validity pass (code-simplicity, architecture) then a 9-seat panel (security, test-design, code-quality, pattern-recognition, git-history, observability-coverage, data-integrity, performance, agent-native). Bash-only diff: shellcheck substituted for semgrep. Agents report-only; all fixes applied from HEAD by the lead.
- Findings: ~45 after dedupe — 1 P1 (code-quality: the "unchanged since the watermark" sentence keyed on `prs=`, true for an unattributed direct push that DID change the config → keyed on `commits=`), ~12 P2, the rest P3. Fixed inline in a7fd86648, e644a9808, 4625fc0c3, 3457bea1e. Filed as scope-out: #8365 (resolve_pr_for_sha extraction — cross-cutting-refactor, CONCUR, counter probe `scripts/followthroughs/resolve-pr-for-sha-extract-8279.sh`).
- Structural-cause roll-up: two. (a) "the verdict composition in YAML had no behavioural test" — the P1, the cancelled-arm contradiction, the non-refusal arms carrying refusal text and the gate-failed gap were all instances; closed by `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh` (31 rows). (b) "the stub answered any request" — E1–E5 survivors; closed by the request-checking stub + the registered battery.
- Wontfix with reason: `apply-web-platform-infra.yml`'s three `**Dispatch reason:**` summary echoes stay unescaped (pre-existing sink, display-only, out of AC13 scope; the producer now escapes and caps the subject, which bounds it). MARKER kept (the plan's Success Metric now keys on it). `${TARGETS:-$TRACKER}` kept but gated on `CHANGE_OUTCOME != success`. MAX_LOOKUPS kept (plan decision; the truncation is noted).
- Verification after the pass: suite 137/137; battery 21/21 killed; verdict harness 31/31 (mutation-checked: COMMITS→PRS and gate-failed removal both red); alarm guard 83 scanned / 11 violations; lint-workflow-issue-write-scope OK; lint-workflow-errexit-capture clean; guard-vacuity-floor 23/23; fixture-relative-assert 62/62; fixture-dir-operand-assert 71/71; lint-orphan-test-suites none; lint-shell-capture-exit 0 new; plugin bun tests 3114 pass; shellcheck clean on all four scripts.

### Session Errors (review)
4. My simulation stub returned raw JSON where the SUT applies `--jq`, so the "existing owner issue" path looked broken for one iteration — the instrument, not the code (verified by the harness row V4 afterwards).
5. The one-line anti-vacuity floor with `exit 2` was unconstructible for `scripts/guard-vacuity-floor.test.sh` (it slices to a standalone `fi` and treats rc=2 as CONSTRUCTION) — caught by running the ratchet lints after the commit, as the work skill prescribes.
