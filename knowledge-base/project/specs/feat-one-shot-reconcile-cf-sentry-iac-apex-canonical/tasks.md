<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The Phase 3b operator `terraform apply` targets sentry_uptime_monitor.soleur_www,
     deliberately excluded from apply-sentry-infra.yml auto-apply scope (cron-monitors only,
     by design — uptime-monitors.tf:19-26). All changes are .tf edits to managed IaC roots.
     No dashboard clicks, SSH, or package installs. See plan Phase 2.8 ack. Q2 tracks auto-apply. -->
---
title: "Tasks — Reconcile Cloudflare/Sentry IaC to apex canonical"
plan: knowledge-base/project/plans/2026-05-29-fix-reconcile-cf-sentry-iac-apex-canonical-plan.md
issue: "#4577"
lane: cross-domain
---

# Tasks: Reconcile CF/Sentry IaC to apex canonical

## Phase 0 — Preconditions (read-only)

- [x] 0.1 Re-run live probes; confirm `www -> 301 -> apex` and apex `200` still hold. STOP if direction flipped. **(verified 2026-05-29: apex 200, www→apex 301, www/pages/agents.html→www/agents/→apex/agents/)**
- [x] 0.2 Capture baseline `terraform plan` for both roots (canonical Doppler+R2 triplet) — read-only, attribute the post-edit diff. **(captured: see 0.3 verdict)**
- [x] 0.3 Replace-vs-modify probe: determine if `target_url.value` change is `~` (in-place) or `-/+` (force-replace); record verdict in PR body; note `[ack-destroy]` requirement if force-replace. NOTE: destroy-guard (`destroy-guard-filter-web-platform.jq`) inspects `cloudflare_ruleset.*.rules` for deletes AND counts rule-array length — edit rules IN PLACE only (no reorder/transient-remove), keep count at 10. **(verdict: `~` in-place. `Plan: 0 to add, 2 to change, 0 to destroy`; rules 10→10; actions `['update']` → no `[ack-destroy]`.)**

## Phase 1 — Edit seo-rulesets.tf

- [x] 1.1 Flip all 9 redirect rules: `expression` host -> **both-host `http.host in {"soleur.ai" "www.soleur.ai"}`** (evidence-based deviation from apex-only — see AC deviation note) AND `target_url.value` `https://www.soleur.ai/<slug>/` -> `https://soleur.ai/<slug>/` (slugs: agents, skills, vision, community, getting-started, legal, pricing, changelog, legal/terms-and-conditions).
- [x] 1.2 Rule 10 (HTTPS catch-all): NO target/action change; keep ACME host set `{"soleur.ai" "www.soleur.ai"}`. Add one-line comment that target is host-preserving/canonical-agnostic.
- [x] 1.3 `seo_response_headers` RSS rule (`/blog/feed.xml`): flip host to apex (apex-only — feed body served only at apex); update comment.
- [x] 1.4 Rewrite stale header comments ("(A) Apex/www mismatch … 301s every apex URL to www") to the apex-canonical regime.

## Phase 2 — Edit sentry/uptime-monitors.tf

- [x] 2.1 `soleur_www`: keep `url = "https://www.soleur.ai/"`; change `assertion_json` to `equals 301` (redirect-health) per Phase 2 Decision. Do NOT make it a duplicate of `soleur_apex`.
- [x] 2.2 Rewrite comments (WHY-FOUR-MONITORS block + ASSERTION SEMANTICS + "CF-canonical post-#3974").

## Phase 3 — Apply

- [x] 3.0 `terraform validate` both roots **(both pass)**; commit + open PR (`Ref #4577`, `Ref #4573`; record Phase 0.3 verdict in body).
- [ ] 3a CI auto-applies seo-rulesets on merge (`apply-web-platform-infra.yml`, `-target=…seo_page_redirects`/`…seo_response_headers`). Add `[ack-destroy]` to merge commit ONLY if Phase 0.3 = force-replace.
- [ ] 3b Operator applies `sentry_uptime_monitor.soleur_www` from Sentry root via canonical triplet + `SENTRY_AUTH_TOKEN`; halt if plan touches anything else.

## Phase 4 — Post-apply verification (curl, no SSH)

- [ ] 4a Curl 9 legacy www `.html` paths -> each `location: https://soleur.ai/<slug>/`; terms-of-service -> `/legal/terms-and-conditions/`.
- [ ] 4b ACME probe `https://soleur.ai/.well-known/acme-challenge/probe` -> 404.
- [ ] 4c Confirm `soleur_www` monitor healthy with equals-301 assertion (Sentry read-only API).
- [ ] 4d `gh issue close 4577` after verification passes.

## Deferred (file tracking issues)

- [x] Q1 Codify www->apex canonicalizer in Terraform — **filed #4584** (`domain/engineering` + `priority/p3-low`).
- [x] Q2 Extend `apply-sentry-infra.yml` auto-apply to `sentry_uptime_monitor.*` — **filed #4585** (`domain/engineering`).
