# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-25-feat-ship-terminator-journald-to-better-stack-plan.md
- Status: complete (the first planning attempt was cut off by an API limit and lost its uncommitted work with the worktree directory; a second attempt committed and pushed as it went)
- Plan artifact: complete (selector=branch)
- Draft PR: #10975. Epic #10205, item #10136, ADR-294. Brand-survival threshold: single-user incident.

### Errors
- The first planning subagent stopped on a weekly rate limit; its worktree directory was gone and nothing had been committed. Recovered by re-attaching a worktree to the existing branch, rebasing the init commit and re-running planning.
- Local run of `cloud-init-inngest-bootstrap.test.sh` fails its tool-gated assertion-count floor because `cloud-init` is not installed locally (CI installs it).
- No `vector` or `stunnel` binary locally: the stunnel line shapes were measured in an alpine container; Vector VRL is untested until the work phase.

### Decisions
1. Admission by unit: add `soleur-inngest-tls.service` to Source 1 `include_units` and Source 2 `exclude_units`; the Source 4 identifier route was rejected.
2. Fail-open drop-list filter for the three healthy-request stunnel lines (infallible VRL); budget 400 rows/day before a flip, 8,000 after.
3. Web-host fan-out accepted: the merge re-delivers `vector.toml` to web-1 and web-2 (observability only, `.prev` restore kept).
4. Replace gating: a separate `user_data` trim PR plus a CI-rendered margin of at least 300 B on current main must land before the replace go is asked; #10543 fixed is a hard precondition; the go names image tag, digest and host id.
5. Security: Doppler-token scrub rule, a pin that the stunnel config has no `debug` key, admission rows that keep the `inngest-tls-health` crit row shipping.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:gdpr-gate; agents: learnings-researcher, soleur:engineering:cto (x2), soleur:product:cpo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, security-sentinel, observability-coverage-reviewer, user-impact-reviewer.

### Constraints carried (owner, verbatim in force)
Arm nothing and merge nothing; no Inngest host replace, no flip, no apply dispatch; no Doppler writes; production evidence only through Better Stack; A5/A6/A7 stay owner-typed.

## Review Phase (2026-10-25, PANEL_SHA f80c1516e8, fix commit 73d357d0b1)

Panel: 11 seats (git-history, pattern, architecture, security, performance, data-integrity, code-quality, test-design, user-impact, observability, structural enumeration) + simplicity pass + coverage consult + one batched CTO ruling (V1-V6 in decision-challenges.md). 0 P1.

### Dedup ledger

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| drop literals are unanchored substrings; a LOG3/LOG4 variant or failure suffix is dropped | filter-anchoring | data-integrity, security, test-design | 73d357d0b1 |
| failure-path rows unbounded (restart loop, refusal flood); budget covers healthy only | budget-scope | security, performance, data-integrity | 73d357d0b1 (docs: CTO V1, no throttle) |
| runbook stall decode false (a curl timeout produces a close row); zero-rows reading; baseline measured on a stub; reset 0/N shape | runbook-decode-truth | code-quality, observability, architecture | 73d357d0b1 |
| runbook v1.1.59 present tense, A1 row lapsed precondition, delivery step unconditional | post-merge-tense | architecture, code-quality, git-history | 73d357d0b1 |
| runbook query not field-isolated, newest-200 window, 24h read prose-only | runbook-query | observability | 73d357d0b1 |
| cloud-init-inngest.yml missing from workflow paths | path-filter | pattern, architecture, structural | 73d357d0b1 |
| Doppler rule: word-boundary anchor, order vs strip, over-redaction | scrub-rule-edges | security, data-integrity | 73d357d0b1 (CTO V-D2) |
| non-string message ships unscrubbed | scrub-fail-open | security, structural, architecture | 73d357d0b1 (CTO V6) |
| floor sized for the engine-less run, check()/run_case unpoliced, consumer set of the raw source unpinned, 0/0 and decoy fixtures, comment-stripped structure rows | test-vacuity | test-design | 73d357d0b1 |
| ten one-line edits pass all four suites (graph reachability, admission model merge) | graph-pins | structural | #11098 (CTO V3/V4) plus the narrow pin in 73d357d0b1 |
| stale self-claims (Source 2 formula, timing comment, ADR trim, P4 unruled) | stale-claims | architecture, code-quality, pattern, git-history | 73d357d0b1 |
| merge gate for web hosts is advisory | merge-gate | user-impact | PR body (CTO V5) |
| coverage consult leads: over-tight anchors, shared scrub stage fixtures, legal emitters wording | consult-leads | consult | fixtures added; over-tight anchors accepted (fail-open, detected by the first-hour prefix read); legal wording: the terminator is a unit on the host plane the policy already names |

structural-cause roll-up: the P2 test findings, the structural map and two scrub findings share one cause: every guard pinned the nodes and lists this PR added and not the wires or the population around them (seat that should have enumerated it: structural enumeration; it did).
