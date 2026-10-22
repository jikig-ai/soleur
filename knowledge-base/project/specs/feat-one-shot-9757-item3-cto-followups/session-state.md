# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-22-fix-ci-head-verdict-stall-clock-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- CTO follow-up list (P2/P3/P4) not in #9757 body/comments; recovered from the held-merge session transcript. Pre-existing: scripts/ci-pr-affected-preactivation.sh expects a literal `full-verified` that ci-head-verdict.sh never had (left alone).

### Decisions
- P3: stall clock = max(ready event, kept run created_at, or earliest check-suite created_at when no run); failed suite read -> state=error exit 3.
- Stall rule defined once in the script header; consumers point at it; ADR-276 addendum.
- P2 and P4 are follow-up PRs/issues, not in this PR.
- cto_spawns=3 (plan phase)

### Components Invoked
soleur:plan, plan-review, deepen-plan; cto x3; research + review agents.

## Review Phase (panel SHA e1f662fa86; 7 seats: history, pattern, architecture, security, code-quality, agent-native, test-design)

dedup: 45 raw -> 19 unique. structural-cause roll-up: none. Risk tier: none (source: plan).

| canonical defect key | seats | disposition |
|---|---|---|
| persistent state=error reason=no-check-suites is invisible to consumers (stderr dropped) | agent-native, architecture, history | fixed inline: ready-run-wait.md row (no-check-suites = CI never saw the head, recover as stalled), usage()/header say so; no consumer-message change (CTO ruling) |
| doc/header wording: clock starts at the LATER of T and A, not "first appearance" | agent-native, quality, pattern, history | fixed inline (ready-run-wait.md, header, usage) |
| "see ci-head-verdict.sh" pointer not actionable; --help lacks the rule | agent-native | fixed inline: usage() states the rule, consumer messages say `--help` |
| stall-branch inline comment duplicates header; one-line if/else | pattern, quality | fixed inline |
| RUN_TS naming; dead RUN_TS guard; dead ANCHOR_REASON reset; ANCHOR_EPOCH=0 init | pattern, quality, test-design | fixed inline (RUN_EPOCH, guard + reset removed, init empty); the pre-epoch suite guard stays (reachable, new V26 row) |
| tests: completed runs after 120m never read (S3) | test-design | fixed: V7 rows |
| tests: suites listed ascending only (S1); one page only (S2); one kept run only | test-design | fixed: V25b/V25d descending, V25e paged stub, V24c two kept runs; mutants M46, M47 |
| tests: source-text grep on REAL_SUT, missing state asserts, V25d naming, plan-only comment, floor numbers in comment | quality, pattern, test-design | fixed inline |
| scripts/followthroughs/ci-draft-light-soak-9728.sh prose/sticky abort | architecture | accepted: message pinned by its own test, probe retires with #9728, fails closed |
| ADR-276 line 392 forward pointer | history | wontfix: originals stay unedited by ADR convention; the amendment supersedes by subject |
| anchor upper bound (future created_at); header says last vs consumers first marker | security | wontfix: server-supplied, same trust as the Date header; pre-existing consumer behaviour |
| re-run keeps created_at (run_started_at) | architecture | wontfix: named residual, Actions-tab check before undo is the guard |
| retry the suite read once before error | history | wontfix: CTO ruling forbids a fallback; the next poll resolves a transient |
| ABSENT line wording in admin-merge-ready.sh | agent-native, quality | wontfix: test-pinned, still literally true |
