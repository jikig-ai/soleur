# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-11-feat-web-postcutover-inngest-colocation-toggle-plan.md
- Status: complete

### Errors
None. One hook false-positive (`systemctl enable` prose flagged manual-infra) resolved via `iac-routing-ack: plan-phase-2-8-reviewed` opt-out — change routes entirely through Terraform + cloud-init, no manual steps.

### Decisions
- Gate mechanism: col-0 `%{ if web_colocate_inngest ~}` / `%{ endif ~}` right-strip directives wrapping the whole "Bootstrap Inngest server on first boot" runcmd item; verified via `terraform console` in both states. Indented directives corrupt the render — col-0 mandatory.
- `type = bool` load-bearing: `%{ if }` is truthy for any non-empty string; rollback passes `TF_VAR_web_colocate_inngest="false"`. Guarded by a static bool grep + a render leg passing string "false".
- Single terraform-render test authority: added one `setup-terraform` step to the `deploy-script-tests` CI job (was terraform-less → render would SKIP). AC3 trimmed to strip-only.
- No new ADR / no C4 edit: ADR-100 records the dedicated-scheduler decision; model.c4:377 already annotates the removed hosting edge. This PR is an implementation slice of epic #6178 (contextual, not Closes).
- SAFE-TO-MERGE: `hcloud_server.web` has `ignore_changes=[user_data,...]`; auto-apply is `-target`-scoped excluding `hcloud_server.web` → merge recreates no host. Dedicated host isolated (separate cloud-init-inngest.yml); inngest-bootstrap.sh untouched.

### Components Invoked
- soleur:plan, soleur:deepen-plan
- agents: architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer (all approve)
