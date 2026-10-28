# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-27-feat-per-pr-monitor-lock-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking (learnings sub-agent hit a /tmp quota in its own shell; decision-challenges.md fixed to pass the ruling gate).

### Decisions
- Re-scoped: hard per-PR lock inside monitor-pr-checks.sh (rc 4 on a second monitor); the existing monitor-supersede-guard.sh hook, apps/**, registry-restore script and workflows untouched.
- Symlink lock (pid|lstart|epoch), no flock; fail open only when the lock cannot be set up.
- Grace retry before refusing; refusal text tells the agent what to do.
- cto_spawns=0 in this main context (rulings made inside the plan subagent).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO, learnings-researcher, dhh/kieran/simplicity reviewers

## Work Phase
- Status: complete (commit ea98993e09)
- Affected gate (`affected-tests.sh`, 267 of 679 suites selected): rc=6 AFFECTED_GATE_BUDGET_DEFERRED. The run queued 2h behind two sibling worktrees' test-all runs (ticket position 2) and its budget expired with zero suites run. Contract: CI (.github/workflows/ci.yml) is the authoritative gate; this run is NOT recorded as passed.
- Directly run evidence instead: monitor-lock.test.sh 54/54 (10/10 mutants killed), monitor-pr-checks.test.sh 69/69, ci-head-verdict.test.sh 91/0, sync-pr-behind.test.sh 272/0, 6 harness/workflow bun files 193/0, lint-orphan-test-suites, lint-trap-tempfile-ownership, lint-shell-capture-exit, fixture-relative/dir-operand ratchets, c4-count-parity, lint-guard-contract, discoverability probe.

## Review Phase (PR #11286)
- Tier: none (plugin tooling). Class: code. Panel SHA f71c8fd250: 9 seats (history, pattern, architecture, security, performance, structural-enumeration, agent-native, code-quality, test-design); fix round 1 on b7bcb0dabc: 5 seats (code-quality, security, test-design, agent-native, architecture). No P1 in either.
- Structural-cause roll-up: (1) the suite's harness could not tell a setup failure from a kill or a floor from a count (hold wait, mutate rc, ps stub, floor slack, self-test via no()); (2) the lock logic trusted record fields it had not validated (same-pid adoption, empty lstart, octal epoch, unbounded digits); (3) caller prose contradicted itself across harness.ts / drain-prs / the refusal line.
- dedup: ~60 raw -> 24 unique (all fixed except the rows marked residual)

| canonical defect | seats | disposition |
|---|---|---|
| same-pid record with foreign lstart adopted, lock then stolen | code-quality, structural | fixed (b7bcb0dabc), U3h |
| stale-reclaim compare/rm race (two winners ~20% of 2-racer rounds) | security, code-quality, structural | fixed, mkdir guard, U13; CTO F15 |
| leading-zero PR (007) -> second lock; octal epoch aborts acquire; unbounded digits | structural, security, code-quality | fixed, U7e, U10b |
| empty-lstart record counted live | security, code-quality | fixed, U3g |
| lock dir mode unchecked; find failure fail-open | security (x2 rounds) | fixed, U6 (777/770/703), find failure refuses |
| repo key: origin raw, GH_REPO ignored, insteadOf, GH_HOST | architecture, code-quality, security | fixed (GH_REPO, remote get-url, GH_HOST refusal) |
| M3/M4 vacuous kills; mutate() any-rc kill; ps stub ignores argv; floor slack; self-test via no() | test-design, structural | fixed, harness rc 2 = setup failure, strict ps stub, exact floor |
| U11 without contention control; /tmp fallback and perm clauses unpinned | test-design (fix round) | fixed, U11 control, U6 arms |
| refusal line: bypass hint, ownership branch, kill without ps check, "armed" | agent-native, architecture | fixed; CTO F14 |
| drain-prs vs harness.ts contradiction; wrong queue read; own-task case; kill ping-pong | agent-native (x2 rounds), architecture | fixed (round 2) |
| hook cannot see the script command | history, architecture | prose fixed; follow-up #11312 (CTO F17, CONCUR criterion 4) |
| fork-clone key divergence, stuck .reclaim guard, INT/QUIT, SIGPIPE delay | structural, architecture, code-quality | documented residuals in the lib header |
| shared-shard weight row, probe naming, selftest stray line, lock-name helper | performance, pattern | selftest line fixed; weight row not hand-edited (generated, warn-only); naming/helper left |
- Left as P3 residual by design: stale-guard double-sweep (needs a reclaimer crash plus 3 contenders), `git remote get-url` fork ranking, probe closes #11312 on PASS (date-shape contract).
