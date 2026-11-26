# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12906-sdk-allow-cache-remeasure/knowledge-base/project/plans/2026-11-19-chore-remeasure-sdk-sandbox-network-allow-cache-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- plan-sharp-edges.md over read size limit; verified via paged subagent read.
- technical-ruling-gate.sh first run used a wrong path; passes from plugins/soleur/skills/ship/scripts/.
- Two deepen-table rows mislabelled Class technical outside the ruling table; relabelled; gate passes (20 rows).
- Discoverability probe rc=2 until #12897 merges (expected).

### Decisions
- Baseline is a scratch install of MEASURED_BASELINE (0.3.321) with pinned integrity (CTO items 17, 20).
- MIXED and re-asks-after-teardown are conclusive and both trigger #12906 (CTO items 14, 16).
- Run contained: HOME/XDG_RUNTIME_DIR masked, worktree + git common dir read-only, write probe fails closed (CTO item 19).
- npm isolation via env -i with scratch HOME/cache and /dev/null npmrc; floor reads time[exact].
- Build stage waits for #12897 merge; Measure stage waits for later of that and 2026-11-21T23:14Z release-age floor (CTO items 1, 10).

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO, CLO, functional-discovery, dhh, kieran, simplicity, security-sentinel, test-design reviewers.

## Operator Constraints

- constraint: This is evidence-only, do NOT bump the production SDK pin in this PR, and run the measurement against 0.3.328 installed in an isolated harness directory.
- constraint: Commit the harness invocation as a reusable script so the next SDK bump can re-run it in one command.
cto_spawns=1

## Measure Phase (resumed 2026-11-26)
- 0.3.328 measured: `REMEASURE verdict=CACHES exit=0 reason=measured`; ADR-278 Addendum 2026-11-26 written; #12906 commented; #12977 closed.
- npm latest 0.3.332 refused by the floor (`release-age-floor`, re-run after 2026-11-27T22:09:40Z); not measured.
- CI: quality-guards failed on MD034 bare URLs in the 0.3.325 addendum gateway cells (fixed by code spans); `test` red is the draft-light "full battery owed at ready" sentinel, cleared by the ready run.
