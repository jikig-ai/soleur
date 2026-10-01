# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7960-phase-b-delivery-field/knowledge-base/project/plans/2026-09-18-fix-registry-heartbeat-phase-b-delivery-field-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Brief named `scripts/registry-userdata-budget.sh`; real path is `apps/web-platform/infra/registry-userdata-budget.sh` (plan uses the real path).
- `generate-kb-index.sh` output reverted during planning (out of plan scope); regenerated in /work Phase 4.4.
- No spec.md for the branch — `lane:` fell back to `cross-domain`.
- lefthook not on PATH — pre-commit hooks did not run on the two plan commits.

### Decisions
- Producer field: literal ` err_redact_rev=1` after `zot_last_err_src=`, before the free-text tail; literal (not `$VAR`) because the heartbeat runs `set -u`. Measured +17 B raw, stored 14,168 → 14,180 B (18,588 B headroom).
- Probe keys DELIVERY_PROVEN on the field (trusted region, newest real boot); `suppressed` kept as an independently sufficient second proof. BASELINE_AT_MERGE, its override and every boot-drift branch deleted; no-proof collapses to a single exit 3. Recorded in decision-challenges.md.
- Leak discriminator hardened (three case-insensitive patterns + `suppressed` row with a non-`none` tail is a leak); fixture canary makes "no row content on the public issue" a failing test.
- Tests 19 → 35 cases with mutation rows M1–M16; fixtures derive the token from the producer file. Heartbeat suite 33 → 36; boot guard +1 field.
- Delivery: explicit operator auth before merge → merge → expect preflight refusal behind the merge-triggered release → re-fire replace once idle → verify apply run (success + store-volume-preserved line) → pull-path health → probe PASS locally → `gh workflow run scheduled-followthrough-sweeper.yml` closes #7960. Follow-ups: 7440 sibling defect, dispatcher hard-coded refusal text, post-PASS docs PR tracker.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan
- learnings-researcher, repo-research-analyst, functional-discovery, git-history-analyzer, CTO, CLO, dhh/kieran reviewers, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, security-sentinel, test-design-reviewer, deployment-verification-agent
