# Tasks — fix(infra): probe web-1 uptime over a single-level hostname

Plan: `knowledge-base/project/plans/2026-07-06-fix-web1-uptime-single-level-hostname-plan.md`
Lane: cross-domain · Brand-survival threshold: none

## Phase 1 — Rename the CF-proxied probe record

- [ ] 1.1 `apps/web-platform/infra/dns.tf` `cloudflare_record.web_host`: change
      `name = "${each.key}.app"` → `name = each.key` (line 36).
- [ ] 1.2 Update the block comment (dns.tf:22-31) from `web-<n>.app.soleur.ai` to the
      single-level hostname; state the Universal-SSL `*.soleur.ai` one-label-depth reason.

## Phase 2 — Point the monitor at the single-level hostname

- [ ] 2.1 `apps/web-platform/infra/uptime-alerts.tf` `betteruptime_monitor.web_host`: change
      `url = "https://${each.key}.app.soleur.ai/health"` → `https://${each.key}.soleur.ai/health` (line 91).
- [ ] 2.2 Update the comment (uptime-alerts.tf:80) referencing `web-<n>.app.soleur.ai/health`.
- [ ] 2.3 Confirm `paused = false` (line 109) is left unchanged.

## Phase 3 — Guard sweep (verification, expected no-op)

- [ ] 3.1 Run the guard grep over `apps/web-platform/infra/**/*.{tf,tftest.hcl,test.sh,sh}` for
      `.app.soleur.ai/health` / `web-[0-9].app` / `${each.key}.app`; confirm only the two edited
      `.tf` files remain (now single-level). Update any stray hit to single-level in this PR.
- [ ] 3.2 Confirm `for_each` filter `if v.monitored` unchanged on both resources (no web-2 create).
- [ ] 3.3 `cd apps/web-platform/infra && terraform fmt -check` on both files.

## Phase 4 — Ship

- [ ] 4.1 Verify both resources remain in the main `-target` set of `apply-web-platform-infra.yml`
      (`cloudflare_record.web_host` + `betteruptime_monitor.web_host`, NOT the SSH set).
- [ ] 4.2 PR body: document the auto-apply deploy path; note the out-of-scope Better Stack recipient
      change (operator-done UI setting) and that Sentry monitors are single-level/unaffected.
- [ ] 4.3 Post-merge (auto): `curl https://web-1.soleur.ai/health` → 200; Better Stack monitor active.
