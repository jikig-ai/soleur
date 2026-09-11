# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-10-fix-git-data-hash-bound-hardening-batch-plan.md
- Status: complete (plan + plan-review + deepen-plan 2026-09-11)
- Plan artifact: recovered (selector=branch) — planning subagent hit an API rate limit mid plan-review corrections; resumed from transcript and finished.

### Errors
- Rate-limit interruption during final correction pass; on resume, Kieran P0-2 was already on disk and P0-4's residual was applied.
- deepen-plan not run by the planning subagent (coordinator over-broad "do not re-run" instruction on resume) — scheduled as its own pass.
- Kieran P1-2 and P1-3: RESOLVED at deepen-plan (P1-2: set-equality assertions (a)(b)(c) + rows 5b-5d + FR11b; P1-3: probe is now the Guard 5 suite with FR13's row label; `credentials_required` removed because Check 10 treats any non-placeholder value as SKIP-DECLARED).
- Brief's claim that the inngest-bootstrap drift-guard is red on main did not reproduce (163/163 locally); recorded as unreproduced.
- One research citation path corrected; plan-write guard `iac-routing-ack` added with truthfulness note.

### Decisions
- Delete the void rung-2 evidence file (never edit it): keeps birth gate HOLD and CI freshness step dormant; new Guard 4 enforces.
- F11 fleet decision: git-data only. web host has ignore_changes=[user_data]; inngest/registry are ForceNew on live hosts. Follow-ups filed.
- Four of six fixes redesigned against measurement (mountpoint rc on healthy host; F7 ownership chain root:git 0750; AcceptEnv pin cut; sshd -T before unit action, emit on sshd_config_warn which this PR also routes).
- Erasure outcome token and daemon-timestamp assertion cut; app layer still reports success on refusal — cutover-deadlined follow-up.
- UC-1 recorded in decision-challenges.md: drop the betterstack-query.sh --table fix from this PR (operator-requested scope; never auto-applied).

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, cto, clo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cpo; deepen-plan: verify-the-negative sweep (sonnet), learnings-researcher, test-design-reviewer
- Lints: lint-guard-contract.py, lint-infra-no-human-steps.py, c4-count-parity.test.sh, git-data-userdata-budget.sh, cloud-init-inngest-bootstrap.test.sh

## Deepen Phase
- Status: complete (separate subagent pass)
- P1-3 resolved: `--help` probe replaced by `tests/scripts/test-betterstack-query-archive.sh` row label; credentials_required removed (was a SKIP-DECLARED waiver).
- P1-2 resolved: Guard 2 gains three set-equality assertions + mutation rows 5b–5d; `gc_timer` pages via fatal rule — pinned as exception, filed FR17/FR11b.
- Guard 4 tier corrected: birth-time arm inside git_data_rung2_rehearsal_gate (fetch-depth: 0) + advisory PR-range arm; residual to #8010.
- Verify-the-negative sweep 13/14; two corrections (issue-alerts.tf removed+import pair; F10 is five AcceptEnv sites across three files).
- Test-design findings folded; Guard 5 refusal pinned at exit 64 + stderr naming BS_TABLE.
