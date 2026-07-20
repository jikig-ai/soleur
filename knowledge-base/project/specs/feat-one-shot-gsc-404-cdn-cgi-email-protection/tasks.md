# Tasks — fix GSC "Not found (404)" `/cdn-cgi/l/email-protection`

Derived from
`knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md`
(post-plan-review + post-deepen-plan).

**Read the plan's Decision and Sharp Edges before starting.** The decision was **reversed
at deepen-plan**: the remedy is a host-scoped Cloudflare Configuration Rule, **not** a
`Disallow: /cdn-cgi/` in robots.txt. Google explicitly advises against robots-blocking
404s, and this repo already has a learning about the trap that creates.

**Do NOT**, under any circumstances:

- add `Disallow: /cdn-cgi/` to `plugins/soleur/docs/robots.txt` (rejected — Option B);
- disable Email Obfuscation zone-wide via `cloudflare_zone_settings_override` (rejected — Option A);
- add a `/cdn-cgi/` check to `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`
  (distributed plugin skill; would break consumer sites and the green 21-test suite);
- add a `scripts/followthroughs/` probe for `api.soleur.ai` (would auto-close #3379).

---

## Phase 0 — Preconditions

- [x] 0.1 Confirm branch: `git branch --show-current` →
      `feat-one-shot-gsc-404-cdn-cgi-email-protection`
- [x] 0.2 Capture the **baseline census** so AC9 has a before/after. Expected today:
      `/`=0, `/getting-started/`=2, `/pricing/`=1, `/legal/privacy-policy/`=20,
      `/legal/terms-and-conditions/`=7.
      ```bash
      UA="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
      for p in "" "getting-started/" "pricing/" "legal/privacy-policy/" "legal/terms-and-conditions/"; do
        n=$(curl -sS -A "$UA" "https://soleur.ai/$p" | grep -o 'cdn-cgi/l/email-protection' | wc -l | tr -d ' ')
        echo "/$p -> $n"
      done
      ```
      Use `grep -o … | wc -l`, never `grep -c` (counts lines, undercounts on minified HTML).
- [x] 0.3 Confirm baseline suite green: `cd apps/web-platform && npm run test:ci`
- [x] 0.4 Read `apps/web-platform/infra/seo-rulesets.tf` (comment density + `cloudflare.rulesets`
      provider alias) and `apps/web-platform/test/seo-rulesets-noindex.test.ts`
      (brace-counting text-parse approach to mirror). Per `hr-always-read-a-file-before-editing-it`.
- [x] 0.5 Confirm the provider alias name and `var.cf_zone_id` in
      `apps/web-platform/infra/main.tf` / `variables.tf`.

## Phase 1 — RED: source guard

- [x] 1.1 Create `apps/web-platform/test/seo-config-rules.test.ts` (**vitest**;
      `apps/web-platform/vitest.config.ts` `unit` project includes `test/**/*.test.ts`).
      Mirror the sibling `seo-rulesets-noindex.test.ts` text-parse approach — `readFileSync`
      + brace-counting, **not** an HCL parser.
- [x] 1.2 Assert `apps/web-platform/infra/seo-config-rules.tf` declares a `cloudflare_ruleset`
      with `phase = "http_config_settings"` and `kind = "zone"`.
- [x] 1.3 Assert a rule with `action = "set_config"` and `email_obfuscation = false`,
      `enabled = true`.
- [x] 1.4 **Blast-radius assertions (load-bearing — both directions).**
      Positive: expression contains `soleur.ai` AND `www.soleur.ai`.
      Negative: expression contains **none** of `app.soleur.ai`, `deploy.soleur.ai`,
      `api.soleur.ai`. The bounded scope is the property that distinguishes this from the
      rejected zone-wide Option A — assert it explicitly.
- [x] 1.5 Assert the new resource address appears in the `-target=` allow-list in
      `.github/workflows/apply-web-platform-infra.yml`. Without this the rule is committed
      but never applied — the silent-no-op class #3379 already documents.
- [x] 1.6 Confirm RED:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts`

## Phase 2 — GREEN: the Terraform rule

- [x] 2.1 Create `apps/web-platform/infra/seo-config-rules.tf` per plan §Phase 2 step 4.
      **Verify every attribute name against the pinned provider (4.52.7) before writing** —
      do not copy the plan's illustrative block blindly.
- [x] 2.2 Carry a comment block explaining why: the GSC 404, the 30 hrefs, why not
      robots.txt (Google's "don't block 404s" + the `2026-06-14` learning), why host-scoped
      not zone-wide. Match the comment density of `seo-rulesets.tf`.
- [x] 2.3 Add the resource to the `-target=` allow-list in `apply-web-platform-infra.yml`.
- [x] 2.4 **Sweep every guard suite** asserting on that list — orphan suites are the ones
      plans reliably miss:
      `git grep -ln 'cloudflare_ruleset\|\-target=' scripts/ apps/web-platform/infra/*.test.sh`
      Update every hit.
- [x] 2.5 Confirm GREEN:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts`
- [x] 2.6 Confirm the gate can FAIL (AC2): flip `email_obfuscation` to `true` → test fails;
      add `app.soleur.ai` to the expression → test fails; restore → passes. Do not skip.
- [x] 2.7 Full suite green: `cd apps/web-platform && npm run test:ci` — especially the 3
      existing `api.soleur.ai` tests in `seo-rulesets-noindex.test.ts`.
- [x] 2.8 `terraform fmt -check` + `terraform validate` in `apps/web-platform/infra/`.
      Use the canonical Doppler triplet (raw `AWS_*` exports for the R2 backend, then
      `--name-transformer tf-var`) — see
      `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.
      Without `tf-var`, ~13 required variables fail to resolve.

## Phase 2.9 — PREREQUISITE: token scope widen (BLOCKING, discovered at /work)

**The plan and its review panel missed this.** The `cloudflare.rulesets` alias token
(`var.cf_api_token_rulesets`) did not carry the Configuration-Rules permission that the
`http_config_settings` phase requires, so the resource as planned would commit, enter the
auto-apply `-target=` list, and then **403 on apply** — the silent-no-op class #3379 already
documents on this zone.

Verified by live probe against Doppler `soleur/prd_terraform`:

| Probe | Result |
|---|---|
| `http_config_settings` entrypoint | **403** `request is not authorized` |
| `http_request_dynamic_redirect` entrypoint (control) | **200** |

Every other CF token in `prd_terraform` was probed against `http_config_settings` — all 403.
No token holds `User API Tokens:Edit` (all 403 on `GET /user/tokens`) and there is no Global
API Key, so the widen requires the Cloudflare dashboard.

Routed to the `soleur:engineering:cto` agent per the architectural-fork rule (two competing
in-repo precedents: widen-existing per #5092 vs. mint-narrow-alias per `cf_api_token_r2`).
**Ruling: widen the existing token** — same API family and zone; widening moves no secret
material, so it adds no no-default root variable, whose absence would fail the WHOLE
merge-triggered apply rather than just this resource.

- [x] 2.9.1 Update the `cf_api_token_rulesets` description in `variables.tf` (it IS the
      scope ledger) and the `cloudflare.rulesets` consumer list + decision rule in `main.tf`.
- [ ] 2.9.2 **BLOCKED** — append Configuration Rules (zone, soleur.ai) to the token in the
      Cloudflare dashboard. Browser transport unavailable this session (Playwright MCP
      disconnected; `agent-browser` daemon wedged across 3 attempts — `os error 11`, then
      `os error 2`, then a 100s timeout). Classified `attempted-blocked-on-tool`, **not**
      operator-only. Tracked with full attempt evidence + resume recipe in **#6755**.
- [ ] 2.9.3 Run the mandatory retained-scope probe set (4 probes: config_settings,
      dynamic_redirect, cache_settings, account rulesets) — see ADR-128 for the exact
      commands. All must be non-403; a 404 on an entrypoint is a PASS (phase exists, no
      ruleset yet), only 403 is a failure. Widening mutates a live credential four
      production concerns depend on — this converts that risk into a pre-merge gate.
- [ ] 2.9.3b **Entrypoint-enumeration probe** (added at review — the one unverified
      destructive edge). A `kind = "zone"` ruleset OWNS its phase entrypoint, which is a
      whole-list replacement, and `terraform plan` reports "1 to add" only because the
      resource is absent from STATE — it cannot see rules created via the Cloudflare
      dashboard. Before the first apply, `GET /zones/<zone>/rulesets/phases/
      http_config_settings/entrypoint` with the widened token and confirm 404 or an empty
      `result.rules` array. If it returns existing rules, STOP: applying would silently
      delete them. (This probe needs the widened token, so it rides on 2.9.3.)
- [ ] 2.9.4 Paste the four status codes into the PR body, then mark ready.

**Do not mark PR #6746 ready until 2.9.2–2.9.4 are green.**

## Phase 3 — Plan review of the apply

- [x] 3.1 `terraform plan` → confirm **1 to add, 0 to change, 0 to destroy** (AC4).
- [x] 3.2 Confirm no excluded resource (`hcloud_server.web`, `hcloud_volume.workspaces`,
      volume attachments, SSH keys) appears — `-target` is transitive on dependencies.

## Phase 4 — Follow-ups (do not fold into the diff)

- [ ] 4.1 File the **28-day GSC re-check** issue (AC12), due merge+28d: re-check the
      "Not found (404)" report, confirm all four rows cleared. Note GSC has no API for
      validation state, but the AC9 census **is** automatable if recurrence is a concern.
- [ ] 4.2 Optionally file the "Book intro" CTA → booking-link conversion follow-up
      (`decision-challenges.md` §Also noted). Low priority, separate concern.

## Phase 5 — Ship

- [x] 5.1 AC6: `git diff --name-only origin/main...HEAD` contains **no**
      `plugins/soleur/docs/robots.txt` — the rejected Option B must not leak back in.
- [ ] 5.2 PR body uses **`Ref #3379`**, not `Closes`.
- [ ] 5.3 Ensure `/ship` surfaces `decision-challenges.md` into the PR body and files the
      `action-required` issue.
- [ ] 5.4 Post-merge operator steps are AC8–AC12. **AC9 is load-bearing** — it is the only
      proof Cloudflare honours the rule; source assertions cannot establish it. AC11 (GSC
      "Validate Fix") is genuinely human-only (no API); justification is inline in the plan.

---

## Acceptance criteria mapping

| AC | Task |
|---|---|
| AC1 (rule assertions incl. scope) | 1.2, 1.3, 1.4 |
| AC2 (gate can fail) | 2.6 |
| AC3 (full suite green) | 0.3, 2.7 |
| AC4 (clean 1-add plan) | 3.1, 3.2 |
| AC5 (-target + guard sweep) | 2.3, 2.4, 1.5 |
| AC6 (no robots.txt in diff) | 5.1 |
| AC7 (`Ref #3379`) | 5.2 |
| AC8–AC12 (post-merge operator) | 0.2 baseline, 5.4 |
