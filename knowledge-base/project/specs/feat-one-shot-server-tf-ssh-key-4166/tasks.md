---
title: "Tasks: fix(infra): unblock apply-web-platform-infra terraform plan at server.tf:12 (#4166)"
plan: knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-ssh-key-path-4166-plan.md
lane: single-domain
---

# Tasks — feat-one-shot-server-tf-ssh-key-4166

Derived from [the plan](../../plans/2026-05-20-fix-apply-web-platform-infra-ssh-key-path-4166-plan.md). Single-PR scope. No `.tf` changes.

## Phase 0 — Preconditions

- [x] 0.1 Confirm worktree branch: `git branch --show-current` → `feat-one-shot-server-tf-ssh-key-4166`.
- [x] 0.2 Confirm precedent step body: `grep -A 2 "Generate CI SSH key" .github/workflows/scheduled-terraform-drift.yml` → 3-line `ssh-keygen` + `printf CI_SSH_PUB=` block.
- [x] 0.3 Confirm `hcloud_ssh_key.default` is excluded from apply allow-list: `grep -c "hcloud_ssh_key.default" .github/workflows/apply-web-platform-infra.yml` → 1 (header comment only).
- [x] 0.4 Confirm saved-plan pattern in use: `grep -n "out=tfplan" .github/workflows/apply-web-platform-infra.yml` + `grep -n "apply.*tfplan$" .github/workflows/apply-web-platform-infra.yml` both return matches.
- [x] 0.5 Confirm `actionlint` is on PATH: `which actionlint && actionlint --version`.
- [x] 0.6 Diff-verify byte equivalence against scheduled-terraform-drift.yml's run-block (see plan P0.6).

## Phase 1 — Workflow edit (single commit)

- [x] 1.1 Insert new step `Generate ephemeral SSH public key for var.ssh_key_path` immediately after `Install Doppler CLI` (around line 132). See plan Reference Implementation block for exact patch.
- [x] 1.2 Add `-var="ssh_key_path=${CI_SSH_PUB}" \` to the `terraform plan` invocation, immediately after `-out=tfplan \` and before the first `-target=` line.
- [x] 1.3 Confirm the apply step at line 302-303 is UNCHANGED.

## Phase 2 — Local verification

- [x] 2.1 `actionlint .github/workflows/apply-web-platform-infra.yml` → exit 0.
- [x] 2.2 Extract the new step's `run:` block via awk + `bash -n` on the snippet (see plan P2.2).
- [x] 2.3 Smoke-test `ssh-keygen -t ed25519 -f /tmp/probe_ci_ssh_key -N "" -q` locally to confirm runner-shape sanity.
- [x] 2.4 Verify all 7 AC sub-points (AC1-AC7) pass with `grep` per the plan's verification commands.

## Phase 3 — PR, merge, and post-merge verification

- [ ] 3.1 Commit: `fix(infra): add ephemeral SSH key step to apply-web-platform-infra workflow (#4166)`. PR body MUST include `Closes #4166`.
- [ ] 3.2 Mark PR ready, request CODEOWNERS review on `.github/workflows/`.
- [ ] 3.3 After merge, the apply workflow auto-triggers on `main`. Operator approves the `web-platform-infra-apply` environment gate.
- [ ] 3.4 Verify the run reaches the `Terraform apply` step (past the previously-failing plan step). Use `gh run view <run-id> --log-failed 2>&1 | grep -c "Invalid function argument"` → 0.
- [ ] 3.5 If apply succeeds end-to-end, close #4166 with the run-link.
- [ ] 3.6 If apply fails for a NEW unrelated reason (next gate in the cascade), file a follow-through issue per the `#4147 → #4150 → #4166 → ?` pattern.

## Phase 4 — Compound learnings

- [ ] 4.1 If anything was learned (Terraform plan-time semantics, saved-plan `-var=` rejection, runner /tmp behavior), drop a learning under `knowledge-base/project/learnings/integration-issues/` or `knowledge-base/project/learnings/best-practices/`.
