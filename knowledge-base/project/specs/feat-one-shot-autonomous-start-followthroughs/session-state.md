# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-27-chore-autonomous-start-followthroughs-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None.

### Decisions
- Dated trackers use one weekly watch workflow with notify-once scripts, not a sweeper directive (CTO F2; departs from the brief's literal text, recorded in decision-challenges.md).
- Sweeper cannot invoke a skill or agent: scripts post data only; the next soleur:go session records the CTO ruling.
- No new billing credential; billing read is attempted with the Actions token and degrades to PR-volume data.
- #11177 watcher: trigger 1 = a hook other than both secret-scan and brand-hex gate; trigger 2 runs the real gate over first-parent commits on main.
- Footprint kept minimal against sibling PR 11154 (convention runbook untouched).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; soleur:engineering:cto (x3) and review seats.
cto_spawns=3 (planning phase)

## Review Phase: dedup ledger (panel SHA 383d39f76e; fix commit 16c0590939)

Structural-cause roll-up: (1) several guards narrower than the property they name (Guard 1 census/oracle/permissions facet, trigger-2 window, stderr screen); (2) failure causes discarded on error paths (obs); (3) billing logic written twice with drifted thresholds; (4) fixture gaps on verdict branches (test-design).

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| no annotation on exit 3 (billing) | obs: silent exit 3 on billing read failure | observability, code-quality | 16c0590939 |
| git -C worktree lacks env -u GIT_* | structural: inherited GIT_DIR retargets the main repo | structural, security (token to gate child) | 16c0590939 |
| `'' --dry-run` runs the real path | structural: argv parse ignores later args | structural | 16c0590939 |
| census/oracle/permissions facet narrower than property | structural: Guard 1 assembly < property | structural, test-design | 16c0590939 |
| --since committer-date window; WARN-only screen; no canary | structural: trigger-2 window/classifier | structural | 16c0590939 |
| yes-verdict untested; tracker not pinned | test-design: verdict branches unpinned | test-design | 16c0590939 |
| 10-20 billing line flagged / verdict printed when months unreadable | code-quality: billing verdict wrong | code-quality | 16c0590939 |
| incomplete_results ignored; unquoted hyphen term (verified live: 5 vs 0 hits) | code-quality + coverage consult | code-quality, consult | 16c0590939 |
| default-branch guard unproven on schedule | architecture + obs + code-quality | architecture, obs, code-quality | 16c0590939 |
| HTTP causes discarded; WN_DRY_RUN env | obs + pattern + simplicity | obs, pattern, simplicity | 16c0590939 |
| budget/timeout; weights at floor | performance | performance | 16c0590939 |
| ADR-033 citation; retirement list; accept-row wording | history/architecture | history, architecture, security | 16c0590939 |
| fixture-write ratchet (47 sites) | repo-global ratchet | lead (gate run) | 16c0590939 (+ this round) |

Accepted residuals (not fixed): clean-judged commits re-judged weekly (bounded by cap and budget; header documents it); trigger 1 cannot see wrapper-lib or variable-built sources (header documents it); sentinel match anywhere in a bot comment (script 3 writes multi-sentinel tail blocks); shared test-harness hoist (follow-up, simplicity).
