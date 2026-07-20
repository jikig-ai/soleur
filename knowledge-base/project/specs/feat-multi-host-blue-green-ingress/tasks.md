# Tasks — Multi-host blue-green ingress prerequisites (ADR-068 GA)

Plan: `knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md`
Lane: cross-domain · Threshold: single-user incident (CPO sign-off) · Refs #5887 #5877 #5274

## Phase 1 — Unwedge CI, zero reboot (normal PR)
- [x] 1.1 Edit `apps/web-platform/infra/server.tf`: `hcloud_server.web` `lifecycle.ignore_changes += placement_group_id` with a temporary-GA-deferral comment (names the GA removal trigger; notes web-2 already in the group). — verified via `terraform validate` + live plan `31 add, 1 change, 0 destroy`.
- [x] 1.2 Add `terraform-target-parity.test.ts` static guard: `hcloud_server.web` `ignore_changes` includes `placement_group_id` (guards future silent removal that would re-trip `reboot_updates`). — RED→GREEN, 1942 plugins tests pass.
- [x] 1.3 Amend ADR-068: reboot-deferral + deferred GA ingress design (CF LB v4, monitor reachability-only) + no-live-weight-before-GA invariant.
- [ ] 1.4 PR body: `Ref #5887` (NOT `Closes`); note the zero-reboot verification (`31 add, 1 change, 0 destroy`).
- [ ] 1.5 Review gate: grep-verify no `cloudflare_load_balancer*` added (done); run user-impact-reviewer (single-user threshold).

## Phase 1 — Post-merge (operator, automated)
- [ ] 1.6 Confirm both apply pipelines green on `main` (`gh run list`, no dashboard).
- [ ] 1.7 Confirm `moved-block-wedge-5887.sh` PASS → #5887 auto-closed.

## Phase 2 — Warm web-2 standby (operator maintenance-window apply; gated on expense approval)
- [ ] 2.1 COO/CFO: approve + record web-2 20 GB volume (~€0.88/mo) in `knowledge-base/finance/expenses.md`.
- [ ] 2.2 State reconciliation (read-only): confirm `hcloud_server.web["web-2"]` in state; plan shows `0 to destroy` + no web-1 placement/reboot diff.
- [ ] 2.3 `-target` apply: private net + subnet + `hcloud_server_network.web[*]` + `hcloud_volume.workspaces["web-2"]` + attachment (canonical raw-AWS_* + tf-var invocation).
- [ ] 2.4 Deploy app to web-2; verify `GET http://10.0.1.11:3000/health` = 200 + `supabase:connected` (private IP only).
- [ ] 2.5 Verify safe end-state: web-1 serves 100% via unchanged A record; web-2 warm, in no serving pool.

## Follow-ups (GA-blocking; separate issues/plan)
- [ ] F1 File `/health` deep-readiness endpoint issue (Sharp Edge C1) — required before web-2 can be pooled.
- [ ] F2 GA cutover plan/window: LB (verify CF record→LB migration behavior) + router owner-side relay activation + git-data LUKS cutover + remove `ignore_changes=[placement_group_id]` → drain → reboot web-1 → restore.
