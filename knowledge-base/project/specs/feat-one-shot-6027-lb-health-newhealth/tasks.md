# Tasks — fix: web_lb_health new_health Down → Unhealthy (epic #6027 AC4)

Plan: `knowledge-base/project/plans/2026-11-02-fix-lb-health-alert-new-health-plan.md`
Branch: `feat-one-shot-6027-lb-health-newhealth`

## Phase 1 — vocabulary correction

- [ ] 1.1 `apps/web-platform/infra/cloudflare-lb.tf` — inside the `filters` block of
  `cloudflare_notification_policy.web_lb_health`, change `new_health = ["Down"]` to
  `new_health = ["Unhealthy"]` and rewrite the adjacent comment: documented vocabulary is
  `{Unhealthy, Healthy}` (verified against CF docs + API Error 17108 on run 41504420340);
  `Healthy` recovery paging stays deliberately out of scope (flap-vs-sustained never verified).
- [ ] 1.2 `plugins/soleur/test/preflight-discoverability-test.test.ts` — append the `92 -> 93`
  PLACEMENT/TRUTH/NO SUBSTITUTE comment entry in the `#7393 G` describe block for this plan's
  `credentials_required` declaration, and bump `BASELINE_DECLARED_PROBES` to `93`.

## Phase 2 — verification (pre-merge)

- [ ] 2.1 `terraform fmt -check apps/web-platform/infra/cloudflare-lb.tf` exits 0.
- [ ] 2.2 `rg 'new_health'` prints `new_health = ["Unhealthy"]`; `rg '\["Down"\]'` exits 1 on the
  file (bare `"Down"` in the comment's history sentence is permitted).
- [ ] 2.3 `bash tests/scripts/test-cf-lb-overlay-gate.sh` green.
- [ ] 2.4 `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` green (G1 counts
  the new declaration).
- [ ] 2.5 PR body references `Ref #6027` — never `Closes #6027` (remediation + window flip open).

## Phase 3 — post-merge (operator, authorization-bound)

- [ ] 3.1 Re-dispatch `cf-lb-overlay.yml` with `arm=ga-pool-update mode=drain
  confirm=UPDATE-GA-LB-POOL reason="<cite this PR>"` — the remnant `{policy:create}` plan passes
  `cf_lb_gate_ga_pool_update`, apply exits green, and `GET
  /accounts/{id}/alerting/v3/policies` shows `GA LB pool health (app.soleur.ai)` `enabled=true`
  (epic #6027 AC4). Automation: not feasible — the dispatch IS the per-command authorization.
