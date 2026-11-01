# Tasks — feat-one-shot-6027-web2-pool-spread

Plan: `knowledge-base/project/plans/2026-11-01-feat-web2-pool-spread-ga-lb-plan.md`
Issue: #6027 (epic) | PR: #11766 | lane: cross-domain | threshold: single-user incident (requires_cpo_signoff)

## Phase 1 — cloudflare-lb.tf (monitor + drained origin + steering + notification)

- [ ] 1.1 `cloudflare_load_balancer_monitor.web`: `type = "https"` → `"http"`; add `port = 80`; keep `path = "/health"`, `expected_codes = "200"`, method/timeout/retries/interval/consecutive pins unchanged. Rewrite the firewall comment — :80 is the listener; :443 is permitted-but-unbound. (AC1)
- [ ] 1.2 `cloudflare_load_balancer_pool.web_1`: append `origins { name = "web-2", address = hcloud_server.web["web-2"].ipv4_address, enabled = true, weight = 0 }`; add `origin_steering { policy = "random" }` (pending ruling row — if the CTO ruling differs, apply it here). (AC2, AC3)
- [ ] 1.3 Rewrite B2 comments at cloudflare-lb.tf:10-11, 35, 52, 62, 65, 70 — "structurally absent" → "drained member (weight 0) until the #6027 window flip"; LB `steering_policy = "off"` comment names pool-level semantics. (AC2, AC3)
- [ ] 1.4 Add `cloudflare_notification_policy.web_lb_health` (`alert_type = "load_balancing_health_alert"`, `enabled = true`, `filters` pinning the web pool_id + event_source + new_health, `email_integration { id = var.cf_notification_email }`). (AC4)

## Phase 2 — cf-lb-overlay arm + gate extension

- [ ] 2.1 `.github/workflows/cf-lb-overlay.yml`: add `arm` choices `ga-monitor-fix` + `ga-pool-update`; new `mode` input (choice `drain`/`serve`, consumed only by ga-pool-update). (AC5)
- [ ] 2.2 New `ga-monitor-fix` job — clone the ga-overlay skeleton (`environment: web-platform-infra-apply`, R2 backend, init/plan/show/grade/apply/continuity), `-target=cloudflare_load_balancer_monitor.web`, confirm literal `FIX-GA-LB-MONITOR`, grade via `cf_lb_gate_ga_monitor_update`, post-apply pool-health assertion. (AC5, Guard 1)
- [ ] 2.3 New `ga-pool-update` job — same skeleton, `-target` on pool + LB, confirm `UPDATE-GA-LB-POOL`, grade via `cf_lb_gate_ga_pool_update <plan> <mode>`; `mode=serve` runs `lb-weight-gate-with-marker.sh` fail-closed BEFORE plan (env injection per the gate's contract; marker read via `prd_workspaces_luks_marker` token — #9358 prerequisite). (AC5, Guard 2)
- [ ] 2.4 `tests/scripts/lib/cf-lb-overlay-gate.sh`: `cf_lb_gate_ga_monitor_update` (update-only on monitor + pinned after-shape) + `cf_lb_gate_ga_pool_update` (update-only on {pool,LB}; origins ⊆ plan-resolved {web-1,web-2} IPs; mode-arg weight pin); widen `cf_lb_gate_ga` origins pin to the two-IP set. (AC6, Guards 1-2)
- [ ] 2.5 `tests/scripts/test-cf-lb-overlay-gate.sh`: fixtures + assertions for both new graders incl. mutation-matrix rows (repointed origin refused; drain-mode weight>0 refused; serve-mode missing no-op entry refused; https/443 monitor refused; empty plan refused). (AC7)

## Phase 3 — committed-config guard + parity + docs

- [ ] 3.1 `lb-weight-gate.test.sh` Condition C: replace C.3-sweep's structural-absence assertion with the drained-shape invariant (web-2 origins block must carry `weight = 0`; no web-2 in `default_pool_ids`; keep C.1b/C.1c/C.2); keep `MIN_CASES` accounting. (AC8, Guard 3)
- [ ] 3.2 `ga-pool-update` arm carries `-target=cloudflare_notification_policy.web_lb_health` beside the pool/LB targets (NOT routine apply — pool-reference transitivity trap); bump `BASELINE_DECLARED_PROBES` 89→90 in `plugins/soleur/test/preflight-discoverability-test.test.ts`. (AC4, AC12)
- [ ] 3.3 ADR-068 dated amendment: monitor transport fix (http/:80 — replaces the 443 premise); drained-origin pooling per §(b) replacing F3's structural-absence reading; `origin_steering` declaration per ruling row. (AC9)
- [ ] 3.4 `model.c4`: `cloudflare` description gains the LB role (pool {web-1, web-2-drained}, A-record fallback); serving-edge prose covers the two-origin set; run `c4-code-syntax.test.ts` + `c4-render.test.ts`. (AC9)
- [ ] 3.5 `cf-lb-a-record-gaplessness-verify.md` runbook: document the two new arms, confirm literals, mode input, and post-apply pool-health verdict semantics. (Docs)

## Phase 4 — follow-through enrollment + verification

- [ ] 4.1 `scripts/followthroughs/ga-lb-pool-soak-6027.sh`: exit 0 iff CF pool health shows all origins `healthy:true` AND `app.soleur.ai/health` is 200 AND zero new Better Stack incidents in `[deploy_ts, deploy_ts+7d]`; `deploy_ts` derived from the tracker's `earliest` (post-deploy-incident-soak.sh pattern); read-failure → CANNOT ESTABLISH. (AC10)
- [ ] 4.2 Verify `decision-challenges.md` rows persisted (steering, arm partition, weight, dissolved DC fork, CPO sign-off, window-PR scope). (AC11)
- [ ] 4.3 Run suites: `lb-weight-gate.test.sh`, `test-cf-lb-overlay-gate.sh`, `terraform-target-parity.test.ts`, `web-host-provisioner-parity.test.sh`, c4 tests; `actionlint` on cf-lb-overlay.yml; `precommit-guard.sh`. (AC12)
- [ ] 4.4 Verify `git diff origin/main -- apps/web-platform/infra/server.tf` is EMPTY (window-PR scope) and the routine plan shows `reboot_updates = 0` (no `[skip-web-platform-apply]` needed). (AC13)
- [ ] 4.5 Confirm zero mutation acts: no `terraform apply`, no `gh workflow run`, no CF/Hetzner writes — AC14.

## Gated follow-through (post-merge, NOT this PR — tracked in plan §Gated Follow-Through)

- [ ] F1 Dispatch `arm=ga-monitor-fix` → web-1 `healthy:true` in pool-health API.
- [ ] F2 Dispatch `arm=ga-pool-update -f mode=drain` → both origins healthy; web-2 zero traffic.
- [ ] F3 (window, #6027): gate chain + runtime-bind probe → weight 0→1 + `ignore_changes` removal (first diffs) → drain → `ga-pool-update -f mode=serve` → placement attach reboot on drained host → restore → AC4 + AC11 soak → ADR-068 status flip.
- [ ] F4 Tracker issue: `<!-- soleur:followthrough script=scripts/followthroughs/ga-lb-pool-soak-6027.sh earliest=<flip+7d> secrets=CF_API_TOKEN,CF_ACCOUNT_ID,BETTERSTACK_API_TOKEN -->` + `follow-through` label. Operator prerequisite at enrollment: create GH secrets `CF_API_TOKEN` + `CF_ACCOUNT_ID` (values from Doppler `soleur/prd_terraform`) — absent, the sweeper Guard 3 reports REQUIRED SECRET MISSING by design.
