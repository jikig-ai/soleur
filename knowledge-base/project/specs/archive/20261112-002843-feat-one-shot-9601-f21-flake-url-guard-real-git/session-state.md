# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/archive/20261112-002843-2026-11-11-test-f21-flake-root-cause-and-url-guard-entry-point-real-git-plan.md
- Status: recovered from partial-artifact (planning subagent terminated by an API rate limit before emitting its Session Summary; plan body with ## Acceptance Criteria was on disk).
- Plan artifact: recovered (selector=branch)

### Errors
- Planning subagent terminated early: API rate limit (HTTP 429). No Session Summary emitted.

### Decisions
- See decision-challenges.md rows R1-R7 (CTO rulings) and the plan's Research Insights.
- F21 baseline: 3/130 isolated failures (2.3%), second replicate's no-op main push, empty stderr; mechanism SIGPIPE (rc 141) in send-pack's trailing flush after a command-less request with push options.

### Work Phase (2026-11-11)
- Commits: db3abb95d3 (shared fake transport with draining receive-pack), 20aa1b169f (entry-point real-git rows, env by injected builder), then measurements.md.
- AC2 stress: plain 1972/10000 rc141, drain 0/10000. AC4 F20 5/5; AC5 F21 200/200, whole file 20/20 (load 11.3-18.9). AC7: 11 mutants, all RED; no survivor, no row added for WS1/WS3/CQ1.
- Affected gate (gate-or-skip.sh): rc 1, runner terminated before its verdict line (KILLED/UNACCOUNTED rows = unresolved). Real FAIL rows triaged: c4-count-parity and corpus-weight-budget also fail on origin/main 3d27b57cb8 (pre-existing); decide-boundary 55/55 and operator-ack-guard 62/62 green in isolation (load flakes); c4-render-tenant-config fails on this host's likec4 mise shim (no dist chunk, environment). None touch the diff. No issue filed (operator constraint).

### Components Invoked
- soleur:plan, soleur:engineering:cto, soleur:product:cpo (advisory), review seats (per plan text)

## Operator Constraints

- constraint: File no issue unless the CTO rules it and the operator says so. Comments on existing non-epic issues only as the CTO rules.
- constraint: Never touch, read, reference or close the excluded issues and the excluded allowlist file named in the operator brief, and never write their numbers or names in any diff line, PR body, commit or comment.
- constraint: Operator-class actions are never done by the agent - flags, environments, prd writes, prd migrations or psql, legal wording sign-off, public security claims ahead of a measured control, reading or flipping AGENT_OUTER_WRAP live.
- constraint: Never sync an armed or queued PR without an explicit operator OK. BEHIND while armed is expected in merge-queue mode.
- constraint: Closing keyword only once its links are measured, otherwise Ref N. Ref 9601 only.
- constraint: Brand-survival threshold stays single-user incident for agent-sandbox changes. Real-git falsifier first, git 2.38 or later, then the fix. State plainly what the control does NOT claim.
- constraint: Infra Validation red, affected-index-ratchet red and the mutation-battery timeout are known main-red noise, do not fix here. Tenant-integration deadlock or timeouts get one rerun of failed jobs, not a fix.
- constraint: Run the local gate only when no review panel is running. Run single targeted suites, not the full battery.

## Review dedup ledger (PANEL_SHA 269ae8c2ba, 12 seats, P1=0)

dedup: the raw count was not carried across a context compaction, so it is not stated → 14 unique rows below (keyed by defect class plus root cause). Fix commits: 44f981dcfd, bac4e27d06.

| Defect | Sev | Seats | Disposition |
|---|---|---|---|
| no rescue-first push row (N6-MOVE survived) | P2 | user-impact, test-design | fixed 44f981dcfd |
| no pushInsteadOf row (M-A survived) | P2 | security-sentinel, user-impact | fixed 44f981dcfd |
| B-path check blind to Error.message | P2 | test-design | fixed 44f981dcfd (also the mocked row) |
| report ops filtered, not exact | P2 | code-simplicity | fixed 44f981dcfd |
| PR body "no data at risk" false for a no-op rescue push | P2 | user-impact | fixed in the PR body |
| helper: verb or argv not refused, no ssh-off, no timeout, error lacks status | P3 | architecture, code-quality, pattern, performance, agent-native | fixed 44f981dcfd |
| helper header: "LONGER", rates uncited, file:// vs GIT_ALLOW_PROTOCOL=ssh | P3 | architecture, test-design, code-simplicity, performance | fixed 44f981dcfd, bac4e27d06 |
| fetch rows: no workspace snapshot, hasObject bare catch, inverted control lacks a positive | P3 | data-integrity, test-design | fixed 44f981dcfd |
| argv not pinned, control catch discards error, ID collision, title truncation | P3 | test-design, code-quality, pattern, agent-native | fixed 44f981dcfd |
| measurements: fetch-side N6 analogue, commit naming | P3 | git-history | addendum bac4e27d06 |
| one check spans both pushes; include carriers; store fence | P3 | security-sentinel, coverage consult | stated in the PR body, plan and file header |
| no pin on the receive-pack splice | (consult) | coverage consult | UG-FAKE, 44f981dcfd |
| simplicity #2: revert to `env:` | P3 | code-simplicity | rejected: fixture-env-adoption requires the builder call |
| production call-site comments, per-push re-check | P3 | architecture, security-sentinel | carry-forward, out of scope (CTO R6), unfiled |
