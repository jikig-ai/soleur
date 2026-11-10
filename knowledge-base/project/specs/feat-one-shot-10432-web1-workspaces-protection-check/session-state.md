# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10432-web1-workspaces-protection-check/knowledge-base/project/plans/2026-11-10-infra-web1-workspaces-volume-protection-check-plan.md
- Status: complete
- cto_spawns=0 (technical-ruling gate PASS, 19 rows, before work)

### Errors
None. No .tf or boot-byte change needed, so CTO stop condition 6 did not fire. Rows 13-15 of decision-challenges.md were first drafted with unearned CTO attribution; replaced with real CTO rulings before commit.

### Decisions
- One sole-copy-protection-check job with two matrix rows (inngest, web1), fail-fast false, strict matrix context in gha-expr.py; row values validated only by the suite's pre-merge matrix-shape check (CTO rulings 1, 13).
- Web-1 pin 106443278 anchored to a new appended ADR-119 addendum (also corrects stale 106406962 as a note); suite checks it against the addendum and a new read-only read-back section in runbook 6604; ADR-282 gets a short note that its pin literal moved into the matrix row (rulings 2, 12).
- Inngest strings byte-identical, copied never retyped; per-entry text in case "${ENTRY}:${VERDICT}" with one fail-closed *) arm; entry-neutral step names; R3b literal in token-drift-workflow-causes.test.sh updated (rulings 3, 7, 9, 15).
- Suite: green refactor first (195/195), then RED rows proven one by one; cross-entry rows C1-C6, C8-C10; FLOOR and TABLE_ROWS move to realized counts (rulings 8, 14).
- #10430 Sentry check-in out of scope; filers gain GH_REPO so a failed checkout still files an issue; #11163 closed at ship time with grep evidence (rulings 4, 10).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, learnings-researcher, functional-discovery, spec-flow-analyzer, dhh/kieran/simplicity/security/test-design/observability/architecture reviewers.

## Operator Constraints

- constraint: Only merge group or dispatch runs are Guard 1 evidence, a push run is not. State run kind and leg with every CI claim.
- constraint: Queue, do not sync, update-branch or push an armed BEHIND PR. The fallback sync fires only after queue wait expired. Re-arm the Monitor each 30 minutes.
- constraint: No sleep in Bash and no background polling, use Monitor. Run local batteries only if CI cannot gate the change, and prefer CI as the gate.
- constraint: Bare gh pr merge. Separate git add and git commit calls. Never git stash. Never pgrep -f. Never cd out of the worktree, use subshells.
- constraint: Run python3 -I .github/scripts/check-workflow-duplicate-keys.py after any merge from main.
- constraint: The Review-Evidence comment must name the current PR head.
- constraint: Test files you add must be byte-equal to canonical helpers. Run the repo-global ratchets fixture-dir-operand-assert, fixture-relative-assert, guard-vacuity-floor and use the env bash shebang in any mock shim.
- ci-is-the-gate: Run local batteries only if CI cannot gate the change, and prefer CI as the gate.
