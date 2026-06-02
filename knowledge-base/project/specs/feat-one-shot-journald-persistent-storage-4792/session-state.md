# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-journald-persistent-storage-4792/knowledge-base/project/plans/2026-06-02-feat-persistent-bounded-journald-prod-inngest-host-plan.md
- Status: complete

### Errors
None. (Two non-blocking IaC-routing hook flags on ssh/systemctl prose, resolved via iac-routing-ack opt-out after confirming apply path is Terraform-routed via terraform_data + remote-exec. Task tool unavailable in pipeline subagent, so research ran inline.)

### Decisions
- ONE prod host (hcloud_server.web, cx33); soleur-inngest-prd is only a Vector host_name tag; inngest.tf has no server resource.
- Apply path = SSH terraform_data provisioner (disk_monitor_install precedent), NOT the deploy_pipeline_fix HTTPS webhook (webhook only writes file payloads, cannot restart journald + flush).
- Three-part coupled fix: journald drop-in + cloud-init write_files/runcmd (fresh-host parity) + terraform_data SSH provisioner (live-prod apply, since server.tf:56 has ignore_changes=[user_data]). Cloud-init half must-not-ship-alone.
- Sizing: Storage=persistent + SystemMaxUse=1G + SystemKeepFree=2G + RuntimeMaxUse=200M; authoritative / size deferred to Phase 0 read-only df / probe.
- L3 firewall: firewall.tf gates SSH:22 to var.admin_ips only; apply succeeds iff operator/CI egress IP in admin_ips.
- Closure semantics: Ref #4792 (ops-only-prod-write class); closure is a post-apply gh issue close step.

### Components Invoked
- gh issue view / gh pr view, soleur:plan, soleur:deepen-plan (gates 4.4-4.8), inline infra reads, artifacts committed + pushed.
