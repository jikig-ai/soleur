# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-04-fix-bump-claude-code-sdk-bun-1-4-4-pair-plan.md
- Status: complete (plan, plan-review, deepen-plan run; tasks.md committed; commit ff4b11e44a)
- Plan artifact: complete (selector=branch)

### Errors
Session interrupted and resumed; UTC clock jumped ~08:59 -> ~17:10, so the web_egress baseline (1 of 22 workspaces, 2026-11-04T08:59:56Z) is re-run at Phase 1 start and at merge. The issue's acceptance probe `grep -m1 '^Bun v'` is vacuous (matches bare fragment); the plan uses `grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'`.

### Decisions
- Pin exactly claude-code 2.1.311 / agent-sdk 0.3.311 (CTO F1).
- Real-SDK re-proof in a scratch install before any pin moves; one atomic pin commit (CTO F3).
- Standing guard asserting embedded Bun >= 1.4.4 in both binaries (CTO F2); argv-tail pins re-anchored on content (CTO F4).
- Forced scope: model-launch-review Haiku swap (F5), classifier census update, ADR-079/075/278 notes.
- PR 10926: flag comment only, no code change (F6); closing it is the owner's call (F7).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO, CPO, repo-research, learnings, functional-discovery, 5-seat plan-review panel.

cto_spawns=2 (rulings F1-F4 plan-time, F5-F6 batch)

## Work Phase
- Status: complete (2026-11-04 UTC). Commits: b15a8fd972 (F5 swap), ea0a75b39b (atomic pin commit with sdk-bump-verified trailer). Pushed to draft PR 12073.
- Evidence: phase1-evidence.md (scratch proof); branch-head re-proof: 7 runtime files 172 passed with C4_BWRAP_REQUIRED=1, docker masked-/proc arm 54 passed (AppArmor override, CI covers that half), cli-tools stage global install reports Bun v1.4.4 (sha256 86dc1fcc...).
- Fixture re-captured with the Doppler `ci` ANTHROPIC_API_KEY (CTO F13, dev has no key); first capture failed on a new `$HOME/.claude/seed-admin` tmpfs token, fixed with a new placeholder.
- PR 10926 flag comment posted (F6). F7 (close 10926 as superseded) stays an owner decision.
- Open: re-run the prd web_egress count before marking the PR ready and at merge (baseline 1 of 22, re-measured 2026-11-04T17:16:38Z: 1 of 22).
