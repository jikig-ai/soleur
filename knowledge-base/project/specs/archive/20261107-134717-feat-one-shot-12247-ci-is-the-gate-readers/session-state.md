# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-07-feat-ci-is-the-gate-token-reaches-work-review-grok-gate-plan.md
- Status: complete

### Errors

None blocking. Brief byte ceiling for ship/SKILL.md (273781) matches nothing in the repo; measured ceilings are planned as byte deltas. #12030 is open and the queue is currently green (last 8 merge_group runs succeeded).

### Decisions

- Ruled by CTO agent, 2026-11-07: #12251 does not fold into this PR; this PR carries Ref #12251 (separate PR, fix is -z plus --ignore-submodules=none).
- battery-owed.sh gets a --token-only flag (no token returns OWED immediately); new thin wrapper plugins/soleur/scripts/gate-or-skip.sh serves work step 9, work fan-out lead gate and review lead gate; Grok pre-push gate gets an inline --token-only branch.
- test-fix-loop, ship Phase 4 and lefthook stay token-blind; lefthook deferral tracked as #12297.
- F12: no gate needs the token after Phase 6.45 archival; recorded once in the ADR-242 amendment.
- Closing mechanism: PR body Closes #12247, Ref #12251, Ref #12297, Ref #12246.

### Components Invoked

soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (1 spawn), research and review agents per the plan.

## Operator Constraints

- constraint: Rely on CI required test check. Required checks are test, lockfile-sync, markdown-lint, tenant-integration-required. Read infra-validation and sandbox-canary-capture-gate by hand. Do not run the local affected battery to completion.
- constraint: Never push to a PR that is in the merge queue. Never admin merge. Never touch the ruleset. If the queue dequeues a PR a second time, stop and report before re-arming.
- constraint: A PR body citing a follow-through tracker uses Ref, never Closes. Declare net-issue-flow when the PR files issues and closes none.
- constraint: Technical forks go to the CTO agent and legal wording to the CLO agent, never to the operator.
- constraint: Check a push real exit code, no pipe to tail. Run git add and git commit in separate calls. No rm -rf inside the worktree. No SSH.
- constraint: Mutation-battery discipline for any new guard, a green unmutated control, a mutation-landed check, a lead-unique scratchpad file name. Cap fix rounds at two targeted rounds plus one verification pass.
- ci-is-the-gate: Rely on CI required test check, do not run the local affected battery to completion.

## Review Phase (PR 12294, panel SHA f3bee8bda5)

dedup: 72 raw -> 22 unique. Tier: none (source: plan). Seats: 8 panel + 1 coverage consult. structural-cause roll-up: verdict-owning helpers and extraction anchors that pin a substring or a spelling instead of the command or the wire (test-design 1/3/4/5/7, security 4, architecture 2, enumeration populations); one cause, one fix family (controls plus exact-line equality plus footprint counts). Coverage consult: five leads, four refuted by probe (copied-plugin fail-closed, GIT_DIR unset by reader, per-run mktemp log, no stale-prose hits), one is the recorded token-lifetime residual.

| defect | seats | disposition |
|---|---|---|
| test helpers (assert_has, assert_lacks, reason_args) neuterable with no signal (P1) | test-design | fixed: pass+fail controls, counters unwound; mutation-proven |
| work step 9 command neuterable (echo, or-true); gateLines widened for ship too (P2) | test-design, architecture, enumeration | fixed: exact-line equality row; wrapper spelling admitted for work step 9 only |
| Grok waiver hid the AGENTS rule-budget lint (P2) | architecture | fixed: grok-fidelity runs it when waived; row plus export-line pin |
| Grok BATTERY_OWED path unexercised; waiver footprint; skip note unpinned (P2/P3) | test-design, pattern, security | fixed: real-assignment row, footprint row, note row |
| stale "no Grok arm" rationale (P2) | history | fixed: scope note in the reader header |
| "SKIPPED" not a unique anchor (P2) | agent-native | fixed: AFFECTED_GATE_SKIPPED in work, review; pinned |
| declared edges, wider rc sets, stdout pin, negative list incl. pre-push hook and token pattern (P3) | arch, enumeration, test-design | fixed |
| contract headings/grammar, issue-vs-PR wording, unknown-argument message, wrapper var rename (P3) | pattern, code-quality, history | fixed |
| inline assert_fixture_dir duplicate (P2) | pattern, code-quality | fixed: removed, sourced canonical helper suffices (ratchets green) |
| Grok recipe deletes the log on green so the banner is invisible (P2) | agent-native, security S1 | accepted: ship/SKILL.md byte-frozen; ADR-242 residual; Phase 4 already prints the same verdict |
| one-shot/SKILL.md line 25 stale (P3) | several | accepted: 9 B headroom; disclosed in the contract |
| same-commit edit of the gate scripts plus token (S2), BASH_ENV, symlinked wrapper (P3) | security | accepted: no new capability, CI required check and merge queue gate the merge; symlink fails closed |
| near-copy helpers (run_gate_args etc.), sentinel/BASH naming, header shape (P3) | pattern, code-quality | wontfix: cosmetic, keeps the existing helpers above the accept-row cites untouched |
| token lifetime across branch reuse | consult | design residual, operator-constraints item 5 |

### Fix round 1 (targeted: test-design, architecture, security, agent-native)

No P1 or P2 except test-design P2 (waiver footprint and export value unpinned outside the sentinel blocks): fixed with an executable slice of the real script through the export line, a footprint over all three waiver names, a consumer pin, a GATE path row, a prose pin and a closed caller-set row. Declared edge for the lib directory, contract and ADR wording (grok-fidelity runs the budget lint on a waive; rc 6/7 residual with CI backstop), unique-token wording and a deep link in work step 9. Accepted: rc 6/7 lint skip is pre-existing and pinned by workflow-fidelity.test.ts; BASH_ENV; consumer-side wording of one-shot line 25.
