# Tasks - feat-one-shot-10137-rotate-arm-volume-assert (#10137)

Plan: knowledge-base/project/plans/2026-10-12-fix-git-data-rotate-arm-volume-assert-plan.md

## Phase 1 - Tests first (RED)
- 1.1 Add post-apply rows PA1-PA7 to tests/scripts/test-git-data-host-replace-gate.sh (plaintext deleted under rotate; LUKS deleted under replace; empty/null/absent resource_changes; mode arm; NIC/attachment creates)
- 1.2 Add gate_mutate_and_check rows for the Guard Contract matrix; raise the anti-vacuity floor
- 1.3 Add apply-step assertions to plugins/soleur/test/terraform-target-parity.test.ts (APPLY_TARGET env, sourced lib, `if !` call, inline loop gone)

## Phase 2 - Library (GREEN)
- 2.1 (superseded at review: no git_data_gate_mode; the plan step publishes its accepted GATE_MODE as the gate_mode step output)
- 2.2 Add git_data_host_post_apply_assert (per-mode preserved set, readable/classifiable, NIC + both attachments, fail-closed mode arm)
- 2.3 Update the lib header usage notes

## Phase 3 - Workflow wiring
- 3.1 Apply step of job git_data_host_replace: env GATE_MODE from steps.plan.outputs.gate_mode, source lib, `if !` call, rename display name, keep id apply
- 3.2 Confirm plan step, GATE_MODE derivation and rotate-confirm step unchanged (git diff)

## Phase 4 - Verify (local only; no dispatch/apply/Doppler/wipe)
- 4.1 Run gate suite, parity test, root-key-arm, boot-signal-poll, preamble, census suites, shellcheck
- 4.2 python3 scripts/lint-encryption-posture.py --repo-sweep from the worktree
- 4.3 PR body: Closes #10137, Ref #6897; state that a fresh rotate dispatch needs the operator to name the command
