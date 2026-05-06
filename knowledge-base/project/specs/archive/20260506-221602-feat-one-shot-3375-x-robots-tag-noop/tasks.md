# Tasks: Document X-Robots-Tag api.soleur.ai no-op

Derived from: `knowledge-base/project/plans/2026-05-06-fix-x-robots-tag-api-noop-comment-plan.md`
Issue: #3375

## Phase 1 — Extend the inline comment

- [ ] 1.1 Read `apps/web-platform/infra/seo-rulesets.tf` (current rule for `api.soleur.ai` at lines ~257-275 inside `cloudflare_ruleset.seo_response_headers`).
- [ ] 1.2 Add a multi-line `#` comment block immediately above the `rules { ... }` declaration for the `api.soleur.ai` rule, covering: (a) current no-op state with date stamp, (b) load-bearing fact (DNS-only CNAME bypasses CF edge), (c) curl evidence, (d) contrast with proxied `deploy.soleur.ai`, (e) why the rule is retained (auto-fires on future orange-cloud flip), (f) re-evaluation criteria, (g) link to tracking issue placeholder `#<NEW>`, (h) practical risk assessment (low — 401/404/403 surface, no body to index).
- [ ] 1.3 Optionally extend the header-block comment at lines ~230-248 to one-line note that one of the three rules is currently a no-op.
- [ ] 1.4 Run `terraform fmt apps/web-platform/infra/` — confirm the comment edit passes formatter.
- [ ] 1.5 Run `terraform validate` from `apps/web-platform/infra/` — confirm syntax.

## Phase 2 — Create re-evaluation tracking issue

- [ ] 2.1 Run `gh issue create --label infrastructure --label seo --milestone "Post-MVP / Later" --title "infra: Re-evaluate api.soleur.ai X-Robots-Tag no-op (proxy or remove)" --body "<body>"`. Body must cite issue #3375, the seo-rulesets.tf rule, and the two re-evaluation criteria (Supabase header-injection feature OR operator proxies api.soleur.ai through soleur.ai's edge).
- [ ] 2.2 Capture the new issue number from `gh issue create` output.
- [ ] 2.3 Update the inline comment in `seo-rulesets.tf` from `Tracking issue: #<NEW>` to `Tracking issue: #N` (the captured number).

## Phase 3 — Verify and commit

- [ ] 3.1 Run `terraform fmt apps/web-platform/infra/` once more — comment must still pass formatter.
- [ ] 3.2 Run `terraform validate` again — confirm parse.
- [ ] 3.3 Run `terraform plan` against prd_terraform Doppler config from `apps/web-platform/infra/`. Expected: zero diff OR comment-only drift on `cloudflare_ruleset.seo_response_headers`. Any rule add/remove/reorder/expression mutation = STOP and investigate.
- [ ] 3.4 Run `bun test` from repo root (or the project's test command) — confirm no regressions (this is a comment-only change so tests should be unaffected).
- [ ] 3.5 Re-run `curl -sI -X GET https://api.soleur.ai/` and confirm response is unchanged (still no `x-robots-tag` — this is the EXPECTED state).
- [ ] 3.6 Re-run `curl -sI -X GET https://deploy.soleur.ai/` and confirm `x-robots-tag: noindex, nofollow` is still present (sibling rule non-regression).
- [ ] 3.7 Commit: `docs(infra): document api.soleur.ai X-Robots-Tag no-op (DNS-only CNAME bypasses CF edge) (#3375)`.
- [ ] 3.8 PR body uses `Closes #3375`.

## Phase 4 — Post-merge (operator)

- [ ] 4.1 If `terraform plan` showed comment-only drift on the resource: run `terraform apply -auto-approve` from `apps/web-platform/infra/` against the prd_terraform Doppler config (per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`, show the exact command first and wait for explicit go-ahead before running with `-auto-approve`).
- [ ] 4.2 If `terraform plan` showed zero diff: skip the apply.
- [ ] 4.3 Verify post-apply state: `curl -sI -X GET https://api.soleur.ai/` still returns no `x-robots-tag` (expected no-op state); `curl -sI -X GET https://deploy.soleur.ai/` still returns `x-robots-tag: noindex, nofollow` (sibling rule unchanged).
