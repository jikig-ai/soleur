<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: every change in this plan is a Terraform .tf edit applied
  through an existing IaC root (apps/web-platform/infra/ + apps/web-platform/infra/sentry/).
  The single "operator runs terraform apply" step (Phase 3b) targets
  sentry_uptime_monitor.soleur_www, which is DELIBERATELY excluded from the
  apply-sentry-infra.yml auto-apply scope (that workflow auto-applies cron-monitors.tf
  ONLY, by design — see uptime-monitors.tf:19-26). Folding uptime monitors into
  auto-apply is tracked as Deferred Q2. No dashboard clicks, no SSH, no manual
  package installs — the operator step IS a Terraform apply against a managed root.
-->
---
title: "Reconcile Cloudflare/Sentry IaC to apex canonical"
date: 2026-05-29
type: fix
classification: ops-only-prod-write
issue: "#4577"
ref: "#4573"
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: Reconcile Cloudflare/Sentry IaC (seo-rulesets.tf, sentry/uptime-monitors.tf) to apex canonical ♻️

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Reconciliation, Phase 0.3, Sharp Edges (verified against code, not memory)
**Research agents used:** inline verification (Task subagents unavailable in pipeline context) — live curl probes, `gh` PR/issue resolution, `grep`/`sed` against IaC + workflow + destroy-guard filter.

### Key Improvements (deepen pass)
1. **Verified-negative pass:** confirmed Rule 10's `target_url.expression` is `concat("https://", http.host, …)` — host-preserving, NO `www` literal (`seo-rulesets.tf:250`). The plan's "do not touch Rule 10" instruction is provably correct.
2. **Destroy-guard interaction confirmed load-bearing:** `tests/scripts/lib/destroy-guard-filter-web-platform.jq` explicitly inspects `cloudflare_ruleset.*.rules` for delete actions (line 6) and even names `seo_page_redirects.rules[10]` (line 13), counting rules-array length via `cf_ruleset_rules_count`. A correct in-place flip keeps the count at 10 (no trip); a misimplemented flip-as-delete WOULD trip the guard. Phase 0.3's empirical replace-vs-modify check is the right gate.
3. **`-target=` count verified = 81** (`apply-web-platform-infra.yml`); `seo_page_redirects` + `seo_response_headers` both present (lines 249–250) → seo-rulesets auto-applies on merge. Confirmed.
4. **All cited PR/issue numbers resolved live** (`gh`): #3296/#3297 (GSC fixes), #3974/#3986 (ACME inline), #3357/#3368 (Free-tier cap), #3378/#3379 (api.soleur.ai no-op) — all merged/closed except #3379 (open, correctly cited as the no-op tracker). #4573/#4577 are open issues; `Ref` (not `Closes`) is correct.

### New Considerations Discovered
- The destroy-guard counts the rules array — so even though a flip is in-place, the implementer must NOT restructure the ruleset (e.g., reordering or temporarily removing rules) in a way that shows a transient delete in the plan diff.
- Gate 4.6 (User-Brand Impact), 4.7 (Observability 5-field), 4.8 (no PAT-shaped vars) all PASS.

## Overview

PR #4573 flipped the **soleur.ai docs site** canonical host from `www` → bare apex (config + prose under `plugins/soleur/docs` + `eleventy.config.js`). The live edge already serves the apex-canonical regime:

```
GET https://soleur.ai/            → 200          (verified 2026-05-29)
GET https://www.soleur.ai/        → 301 → https://soleur.ai/
GET https://soleur.ai/changelog/  → 200
GET https://www.soleur.ai/changelog/ → 301 → https://soleur.ai/changelog/
```

But the Terraform **IaC-of-record still encodes the OLD www-canonical regime** and was untouched by #4573:

- `apps/web-platform/infra/seo-rulesets.tf` — 9 `redirect` rules in `cloudflare_ruleset.seo_page_redirects` match `http.host eq "www.soleur.ai"` and target `https://www.soleur.ai/...` (lines 78–214). Plus the Rule 10 HTTPS catch-all (host-preserving, no host literal in its target — see Reconciliation) and 3 `seo_response_headers` rules that reference `www.soleur.ai` (line 357 RSS feed; 262/355 comments).
- `apps/web-platform/infra/sentry/uptime-monitors.tf` — the `soleur_www` monitor probes `https://www.soleur.ai/` with a 2xx success assertion and a stale comment calling www "CF-canonical post-#3974" (lines 12, 76–78).

**The fix:** flip the 9 SEO redirect rules apex-ward (both the `expression` host match AND the `target_url.value`), update `seo_response_headers` comments + the RSS-feed rule host, and correct the `soleur_www` uptime monitor (its 2xx assertion is **already broken** against the live edge — see User-Brand Impact), then let CI apply `seo-rulesets.tf` and operator-apply the Sentry root, both with post-apply `curl` verification.

### Two findings that reshape the issue's framing (both live-verified, see Research Reconciliation)

1. **`seo-rulesets.tf` is NOT operator-gated — it auto-applies on merge.** `cloudflare_ruleset.seo_page_redirects` and `seo_response_headers` are both in the `-target=` allowlist of `.github/workflows/apply-web-platform-infra.yml` (lines 249–250), which fires on push to `main` with paths `apps/web-platform/infra/**`. So merging the seo-rulesets change applies it automatically via CI. The issue's "operator-gated production `terraform apply`" framing is true only for the **Sentry root** (`uptime-monitors.tf`).
2. **The www→apex 301 itself is NOT in this repo's Terraform.** There is no Bulk Redirect, Page Rule, or host-canonicalization rule anywhere under `apps/web-platform/infra/`. The 9 SEO rules redirect `www → www` (path-only rewrite); Rule 10 is host-preserving HTTPS upgrade. The `www → apex` 301 is **out-of-band Cloudflare config** (dashboard-created Redirect Rule / Page Rule, unmanaged by IaC). This plan does **not** create that canonicalizer — it only stops the SEO rules from contradicting it. Flagged as a follow-up (Deferred Q1).

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (verified 2026-05-29) | Plan response |
|---|---|---|
| "live edge does www→apex 301 (apex serves 200)" | TRUE. `www/` → 301 → `soleur.ai/`; apex → 200. The stale IaC comments in seo-rulesets.tf/uptime-monitors.tf describe the OLD apex→www regime and are themselves drift. | Flip rules apex-ward; rewrite stale comments. |
| "9 SEO 301 redirect rules … redirecting to https://www.soleur.ai/… targets (lines ~78–214)" | TRUE. 9 rules, each `http.host eq "www.soleur.ai"` → `https://www.soleur.ai/<slug>/`. | Flip both `expression` host AND `target_url.value` to apex for all 9. |
| "plus a Rule 10 catch-all" | Rule 10 is an HTTPS-upgrade catch-all whose target is `concat("https://", http.host, …)` — **host-preserving, no `www` literal in the target**. Its expression names `www.soleur.ai` only inside the ACME carve-out host set `{"soleur.ai" "www.soleur.ai"}`. | **Do NOT change Rule 10's target.** Keep the ACME host set as-is (must still cover www so the legacy www cert path is not broken). Documented as "reviewed, no change" — flipping it would break HTTPS upgrade on non-apex hosts (app/deploy). |
| "uptime-monitors.tf probes https://www.soleur.ai/ (lines ~12, ~78)" | TRUE. `soleur_www` monitor, 2xx assertion. Against the live edge, www now returns **301** → the assertion `(>199 AND <300)` is **already FALSE** → this monitor is firing or about to fire spurious pages. | Repoint to apex OR convert to an explicit `equals 301` redirect-health assertion (see Decision in Phase 2). |
| "terraform apply … operator-gated production mutation" | Only the **Sentry root** is operator-applied (`apply-sentry-infra.yml` auto-applies `cron-monitors.tf` only). `seo-rulesets.tf` **auto-applies on merge** via `apply-web-platform-infra.yml` `-target=cloudflare_ruleset.seo_page_redirects`. | Split AC into Pre-merge (PR) / Post-merge: seo ruleset verified after CI apply; Sentry uptime monitor operator-applied via canonical TF triplet. |
| (implicit) "the www→apex 301 lives in these rules" | FALSE. No host-canonicalization redirect exists in IaC; it is out-of-band CF config. | Flag as Deferred Q1 (codify the www→apex canonicalizer in Terraform). Out of scope here. |

## User-Brand Impact

**If this lands broken, the user experiences:** a docs visitor following a legacy `www.soleur.ai/pages/<slug>.html` link gets sent to a www target that the out-of-band canonicalizer then 301s to apex — a **double-redirect chain** (`www/pages/X.html` → `www/X/` → `apex/X/`), live-confirmed today: `GET https://www.soleur.ai/pages/agents.html` → `301 → https://www.soleur.ai/agents/`. Flipping the rules collapses this to one hop. If the flip is done wrong (e.g., expression flipped to apex but target left www), the rule never matches www traffic and the legacy `.html` paths 404 at apex.

**If this leaks, the user's data is exposed via:** N/A — this is an indexing/redirect-hygiene change. No PII, no auth, no regulated-data surface. Rule 10's HTTPS-upgrade behavior (which carries cross-subdomain credentials over TLS) is explicitly **not modified**.

**Brand-survival threshold:** aggregate pattern — a regressed redirect direction degrades Google Search Console coverage across the docs corpus over days/weeks (the original #3296 GSC-indexing failure mode), not a single-user incident. Note: the `soleur_www` uptime monitor is **already mis-asserting** against the live 301, so leaving it unfixed is an active false-page source for the operator.

## Files to Edit

1. **`apps/web-platform/infra/seo-rulesets.tf`**
   - 9 redirect rules (lines 74–218): change each `expression` from `http.host eq "www.soleur.ai"` → `http.host eq "soleur.ai"`, and each `target_url.value` from `https://www.soleur.ai/<slug>/` → `https://soleur.ai/<slug>/`. The 9 slugs: `agents`, `skills`, `vision`, `community`, `getting-started`, `legal`, `pricing`, `changelog`, `legal/terms-and-conditions` (from `…/legal/terms-of-service.html`).
   - **Rule 10 (lines 240–254): NO CHANGE** to action/target. Keep the ACME carve-out host set `{"soleur.ai" "www.soleur.ai"}` intact. (Add a one-line comment noting the host-preserving target is canonical-agnostic by design.)
   - `seo_response_headers` RSS rule (line 357): change `http.host eq "www.soleur.ai"` → `http.host eq "soleur.ai"` for `/blog/feed.xml` (apex is now where the feed is canonically served). Update comment line 262.
   - Rewrite the stale header comments at lines 12–19 (the "(A) Apex/www canonical mismatch … Cloudflare 301s every apex URL to www" block describes the OLD regime — now inverted) and the Background note.
2. **`apps/web-platform/infra/sentry/uptime-monitors.tf`**
   - `soleur_www` monitor (lines 70–87): per Phase 2 Decision, EITHER repoint `url` to `https://soleur.ai/` with the 2xx assertion (making it a duplicate of `soleur_apex` — reject), OR keep `url = "https://www.soleur.ai/"` and change `assertion_json` to an explicit `equals 301` redirect-health check (recommended — it then guards that www-canonicalization keeps working). Rewrite the line 76–78 comment ("CF-canonical post-#3974" → "www 301s to apex; this monitor guards the redirect stays a 301").
   - Update the WHY-FOUR-MONITORS comment block (lines 10–17) to reflect apex-primary / www-redirect-health.

## Files to Create

None (pure edit of two existing TF files; no new resources, no new vars, no new infra surface).

## Implementation Phases

### Phase 0 — Preconditions (read-only, no prod write)

0.1. Re-run the live probes from Overview (`curl -sI --max-time 15`) and confirm www→apex 301 + apex 200 still hold at implementation time. If the direction has flipped back, STOP and re-triage (the out-of-band canonicalizer may have been changed).

0.2. **Drift freshness gate (per `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` Gap 2):** before editing, capture the current `terraform plan` for both roots against live state (read-only) so the post-edit plan diff is attributable. Use the canonical triplet (Phase 3).

0.3. **Replace-vs-modify probe (load-bearing — destroy-guard interaction):** confirm whether Cloudflare treats a `cloudflare_ruleset.rules[*].action_parameters.from_value.target_url.value` change as in-place (`~`) or force-replacement (`-/+`). `.github/workflows/apply-web-platform-infra.yml` runs a destroy-guard (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) — **verified 2026-05-29** to explicitly inspect `cloudflare_ruleset.*.rules` for `delete` actions (filter line 6, names `seo_page_redirects.rules[10]` at line 13) and to count rules-array length (`cf_ruleset_rules_count`). A correct in-place flip keeps the rule count at 10 → no trip. But if the plan diff shows the ruleset's rules being deleted/recreated (e.g., Cloudflare forcing replacement, or an implementer restructuring the rules block), the auto-apply **halts** pending `[ack-destroy]` on the merge commit. Determine the verdict from the Phase 0.2 plan output (`terraform show -no-color tfplan`); record it in the PR body. **Implementer constraint:** do NOT reorder or transiently remove rules — edit `target_url.value` + `expression` in place only.

### Phase 1 — Edit seo-rulesets.tf

Apply the edits in Files to Edit #1. Flip both `expression` host and `target_url.value` for all 9 rules together (expression-only or target-only flips are the two failure modes — see User-Brand Impact). Leave Rule 10 untouched.

### Phase 2 — Edit sentry/uptime-monitors.tf

**Decision (carry into the edit):** the `soleur_www` monitor must NOT become a silent duplicate of `soleur_apex`. Recommended: keep `url = "https://www.soleur.ai/"` and switch its `assertion_json` to an explicit single-op `equals 301` redirect-health assertion (`provider::sentry::assertion(provider::sentry::op_status_code_check("equals", 301))`), mirroring the `soleur_acme_probe` pattern at lines 168–170. This converts a now-broken 2xx probe into a positive guard that www-canonicalization keeps redirecting. Rewrite the surrounding comments. (Alternative — repoint to apex with 2xx — is rejected: it duplicates `soleur_apex` and loses redirect-health coverage.)

### Phase 3 — Apply (split by root)

**3a. seo-rulesets.tf — auto-applied by CI on merge.** No operator apply needed. On merge to `main`, `apply-web-platform-infra.yml` runs `terraform plan` + apply scoped to `-target=cloudflare_ruleset.seo_page_redirects -target=cloudflare_ruleset.seo_response_headers` (among 81 targets) using the in-workflow Doppler `prd_terraform` + R2 backend creds. **If Phase 0.3 found a force-replacement**, the merge commit message MUST include `[ack-destroy]` on its own line, AND the destroy must be reviewed as safe (ruleset replacement is non-destructive to traffic only if CF recreates atomically — verify in the plan diff; if not atomic, escalate to operator before merging).

**3b. sentry/uptime-monitors.tf — operator-applied (post-merge).** `apply-sentry-infra.yml` auto-applies `cron-monitors.tf` ONLY; uptime monitors are operator-applied. Canonical invocation (from the Sentry root `apps/web-platform/infra/sentry/`):

```bash
# R2 backend creds RAW (name-transformer would mangle them):
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
# Sentry auth token (GitHub repo secret SENTRY_IAC_AUTH_TOKEN in CI; local
# internal-integration token for operator — see ADR-031 §local-token):
export SENTRY_AUTH_TOKEN=<iac-terraform-prd internal-integration token>
terraform init -input=false
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -no-color -input=false -out=tfplan \
    -target=sentry_uptime_monitor.soleur_www
terraform show -no-color tfplan   # confirm: 1 to change, 0 to add/destroy
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -input=false tfplan
```

Halt condition: if the plan shows any `+`/`-` action or touches a resource other than `sentry_uptime_monitor.soleur_www`, STOP and file a follow-up triage issue (do not widen the apply).

### Phase 4 — Post-apply verification (curl, no SSH)

```bash
# 4a. After CI applies seo-rulesets (3a): legacy www .html paths now 301 to APEX target.
for slug in agents skills vision community getting-started legal pricing changelog; do
  printf '%-16s ' "$slug"; curl -sI --max-time 15 "https://www.soleur.ai/pages/${slug}.html" \
    | grep -i '^location:' || echo "NO LOCATION"
done
# Expected each: location: https://soleur.ai/<slug>/   (apex, not www)
# terms-of-service rename:
curl -sI --max-time 15 "https://www.soleur.ai/pages/legal/terms-of-service.html" | grep -i '^location:'
# Expected: location: https://soleur.ai/legal/terms-and-conditions/

# 4b. ACME carve-out (Rule 10) still pass-through (unchanged, but verify no collateral):
curl -sI --max-time 15 "https://soleur.ai/.well-known/acme-challenge/probe" | grep -i '^HTTP'
# Expected: 404 (matches soleur_acme_probe monitor assertion)

# 4c. After operator applies Sentry (3b): confirm monitor state in Sentry (read-only API).
#     The soleur_www monitor should now assert equals-301 and be healthy (www → 301).
```

## Acceptance Criteria

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
> **Implementation deviation (2026-05-29, evidence-based — flagged for review).** Phase 1 originally prescribed an **apex-only** expression (`http.host eq "soleur.ai"`). During Phase 0 live probing this was found to **contradict the plan's own Phase 4a verification AC + User-Brand Impact** ("www legacy `/pages/*.html` → `https://soleur.ai/<slug>/` in ONE hop"). The hop chain `curl -sIL https://www.soleur.ai/pages/agents.html` proves the SEO redirect rule fires *before* the unmanaged (out-of-band, dashboard-created) www→apex canonicalizer (hop 1 → `www/agents/`, host preserved). An apex-only expression would make www `/pages/*.html` stop matching the SEO rule → fall through to the canonicalizer → `apex/pages/X.html` → then the apex SEO rule → `apex/X/` = **2 hops**, with the first-hop `location:` being `https://soleur.ai/pages/agents.html`, FAILING Phase 4a. **Resolution:** each of the 9 rules matches **both hosts** (`http.host in {"soleur.ai" "www.soleur.ai"}`) with the apex target, so www legacy traffic collapses to the clean apex URL in one hop AND apex `/pages/*.html` (currently stale 200s) also consolidates. The ACs below are updated to the both-host form. The RSS response-header rule stays **apex-only** (the feed body is served only at apex; www 301s away with no body to index). This deviation does not add, remove, or reorder any rule — Rule 10 and rule count (10) are untouched (`terraform plan` confirmed in-place).

### Pre-merge (PR)

- [x] `seo-rulesets.tf`: the 9 redirect-rule `expression` lines no longer match the OLD `http.host eq "www.soleur.ai"` form — `grep -c 'http.host eq "www.soleur.ai" and http.request.uri.path eq "/pages' seo-rulesets.tf` returns 0; the both-host form `grep -Fc 'in {\"soleur.ai\" \"www.soleur.ai\"} and http.request.uri.path eq \"/pages/' seo-rulesets.tf` returns 9. **(verified — 0 / 9)**
- [x] `seo-rulesets.tf`: no `target_url { value = "https://www.soleur.ai/` remains — `grep -c 'value = "https://www.soleur.ai/' seo-rulesets.tf` returns 0; `grep -c 'value = "https://soleur.ai/' seo-rulesets.tf` returns 9. **(verified — 0 / 9)**
- [x] Rule 10 (HTTPS catch-all) expression + target UNCHANGED — the ACME-specific `grep -F 'starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\")' seo-rulesets.tf` returns 1 and the `concat("https://", http.host` target line is untouched. (NOTE: the bare `http.host in {...}` host-set now appears 10× — 9 redirect rules + Rule 10 — so the ACME-specific grep is the correct UNCHANGED check, not the bare host-set count.) **(verified — `terraform plan` shows Rule 10 absent from the diff)**
- [x] `seo_response_headers` RSS rule host flipped to apex; stale prose removed — `grep -ci '301s every apex' seo-rulesets.tf` returns 0. **(verified — 0)**
- [x] `uptime-monitors.tf`: `soleur_www` `assertion_json` is an explicit `equals 301`; `grep -ci 'CF-canonical post-#3974' uptime-monitors.tf` returns 0. **(verified — equals-301 present, 0)**
- [x] `terraform validate` passes in BOTH roots (`apps/web-platform/infra/` and `apps/web-platform/infra/sentry/`). **(verified — both "Success! The configuration is valid")**
- [x] Phase 0.3 replace-vs-modify verdict recorded in PR body — **empirical `terraform plan` against live prd state: `Plan: 0 to add, 2 to change, 0 to destroy`; both rulesets `update in-place` (`~`); `rules` count 10→10; actions `['update']` only → destroy-guard NOT tripped, no `[ack-destroy]` required.**
- [ ] PR body uses `Ref #4577` and `Ref #4573` (NOT `Closes` — per ops-remediation class, issue closes post-apply; see Sharp Edges).

### Post-merge (operator + CI)

- [ ] CI `apply-web-platform-infra.yml` run on the merge commit succeeded (seo rulesets applied). `Automation: CI auto-apply on merge (push to main, paths infra/**).`
- [ ] Phase 4a curl loop: all 9 legacy www `.html` paths return `location: https://soleur.ai/<slug>/` (apex). `Automation: feasible — curl, baked into Phase 4.`
- [ ] Phase 4b: ACME probe still 404.
- [ ] Operator applied `sentry_uptime_monitor.soleur_www` via Phase 3b triplet; plan showed `1 to change, 0 add/destroy`. `Automation: operator-applied — Sentry uptime monitors are not in apply-sentry-infra.yml auto-apply scope (only cron-monitors.tf). Folding uptime monitors into auto-apply is Deferred Q2.`
- [ ] `gh issue close 4577` after Phase 4 verification passes (post-apply, per ops-remediation `Ref`-not-`Closes` pattern).

## Domain Review

**Domains relevant:** Engineering (CTO) — infrastructure/IaC change only.

No Product/UX, Marketing, Legal, Finance, Security (no auth/PII/regulated surface), or Data implications. The SEO/indexing concern is an engineering-hygiene matter (GSC coverage), already owned by issue #3297's lineage. Rule 10's credential-over-TLS behavior is explicitly out of scope (unchanged). No domain-leader Task spawn warranted for a redirect-target + monitor-assertion flip.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/seo-rulesets.tf` — modify `cloudflare_ruleset.seo_page_redirects` rules 1–9 (target + expression host) and `seo_response_headers` RSS rule host. Provider: `cloudflare/cloudflare` via alias `cloudflare.rulesets` (token `var.cf_api_token_rulesets`, scope incl. Single Redirect Rules:Edit + Transform Rules:Edit). No new vars.
- `apps/web-platform/infra/sentry/uptime-monitors.tf` — modify `sentry_uptime_monitor.soleur_www` assertion + url/comments. Provider: `jianyuan/sentry@0.15.0-beta2` (beta; `sentry_uptime_monitor` is beta — re-validate schema on provider bump). Auth: `SENTRY_AUTH_TOKEN` (repo secret `SENTRY_IAC_AUTH_TOKEN` in CI / local internal-integration token), base_url `https://${var.sentry_org}.sentry.io/api/`. No new vars.

### Apply path

- **seo-rulesets.tf:** **CI auto-apply on merge** via `apply-web-platform-infra.yml` `-target=cloudflare_ruleset.seo_page_redirects` + `…seo_response_headers`. Blast radius: 2 zone rulesets on `soleur.ai`. Expected in-place `~` (confirm Phase 0.3); zero downtime — CF ruleset updates are atomic at the edge.
- **uptime-monitors.tf:** **operator-applied** post-merge (Sentry root, `-target=sentry_uptime_monitor.soleur_www`). Blast radius: 1 monitor. Zero traffic impact (observability resource). This is the genuine operator-`terraform apply` exception acknowledged at the top of this file — the resource is deliberately outside `apply-sentry-infra.yml` auto-apply scope (Deferred Q2 tracks folding it in).

### Distinctness / drift safeguards

- Two distinct R2 state keys (`web-platform/terraform.tfstate` vs `web-platform/sentry/terraform.tfstate`) — roots never share locks. No `dev`/`prd` collision (this is prd-only docs infra).
- Destroy-guard (`destroy-guard-filter-web-platform.jq`) covers `ruleset.rules` — Phase 0.3 verdict gates whether `[ack-destroy]` is needed on the merge commit.
- Secret values (CF tokens, Sentry token) land in `terraform.tfstate` on the encrypted R2 backend — no change to that posture.
- The out-of-band www→apex canonicalizer remains unmanaged (Deferred Q1) — a future `terraform apply` cannot regress it because it is not in state; but it also cannot be drift-detected. Documented risk.

### Vendor-tier reality check

- CF Free-tier zone: dynamic-redirect rules capped at 10/phase (already at the cap — this change modifies existing rules, adds none, so the cap is not approached). `regex_replace()` in target requires Business/WAF Advanced — not used (explicit per-slug rules retained).
- Sentry `sentry_uptime_monitor` is beta — no paid-tier gate needed for a uptime monitor on the existing project.

## Observability

```yaml
liveness_signal:
  what: "soleur_apex + soleur_changelog_deep uptime monitors (200 assertion); soleur_www (equals-301 redirect-health post-change)"
  cadence: "300s (apex/www), 600s (changelog deep)"
  alert_target: "Sentry issue -> existing uptime alert policy (betteruptime_policy.uptime / Sentry project web_platform)"
  configured_in: "apps/web-platform/infra/sentry/uptime-monitors.tf"
error_reporting:
  destination: "Sentry (issue created when assertion evaluates FALSE)"
  fail_loud: "true - soleur_www currently mis-asserts 2xx against a live 301 (active false-page source); this change makes it assert the correct 301"
failure_modes:
  - mode: "redirect direction regresses to www (out-of-band canonicalizer changed, or these rules re-flipped)"
    detection: "Phase 4a curl loop in PR verification; GSC coverage drift over days"
    alert_route: "manual curl (PR gate) + GSC (slow)"
  - mode: "soleur_www stops returning 301 (www-canonicalization broken)"
    detection: "soleur_www equals-301 assertion fires"
    alert_route: "Sentry uptime alert policy"
  - mode: "ACME carve-out (Rule 10) regresses -> cert renewal fails"
    detection: "soleur_acme_probe equals-404 assertion (unchanged by this plan)"
    alert_route: "Sentry uptime alert policy"
logs:
  where: "CI apply log (apply-web-platform-infra.yml run on merge commit); terraform plan/apply stdout for operator Sentry apply"
  retention: "GitHub Actions default (90d); R2 state history"
discoverability_test:
  command: "for slug in agents skills vision community getting-started legal pricing changelog; do curl -sI --max-time 15 https://www.soleur.ai/pages/${slug}.html | grep -i '^location:'; done"
  expected_output: "each line: location: https://soleur.ai/<slug>/ (apex host)"
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` matched against `seo-rulesets.tf` and `uptime-monitors.tf` returned zero (checked 2026-05-29). Issue #4577 itself is labeled `deferred-scope-out`, not `code-review`.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Repoint `soleur_www` monitor to apex with 2xx assertion | Rejected | Duplicates `soleur_apex`; loses redirect-health coverage of the www→apex hop. |
| Codify the www→apex canonicalizer (Bulk Redirect / Redirect Rule) in this PR | Deferred (Q1) | Out of scope — the issue is about reconciling existing rules, not adding the canonicalizer. The 10/phase Free-tier cap and Bulk-Redirects-via-`cloudflare_list` refactor (noted at seo-rulesets.tf:54) make it a non-trivial separate change. File tracking issue. |
| Fold Sentry uptime monitors into `apply-sentry-infra.yml` auto-apply | Deferred (Q2) | Already flagged as a clean follow-up in uptime-monitors.tf header (lines 19–26). Keep operator-apply posture for this PR. |
| Delete the 9 legacy `/pages/*.html` rules entirely (legacy paths) | Rejected | They still receive Googlebot + inbound-link traffic; the redirects are load-bearing for GSC coverage (#3296 lineage). |

### Deferred items — tracking issues required

- **Q1:** Codify the out-of-band www→apex canonicalizer in Terraform (currently unmanaged dashboard config; IaC cannot drift-detect it). Re-eval: when the Bulk-Redirects refactor (seo-rulesets.tf:54) lands. File issue, label `domain/engineering` + `priority/p3-low`.
- **Q2:** Extend `apply-sentry-infra.yml` auto-apply to `sentry_uptime_monitor.*` (currently cron-monitors only). File issue, label `domain/engineering`.

## Sharp Edges

- **`seo-rulesets.tf` auto-applies on merge** (not operator-gated) — the merge IS the prod mutation for the CF side. The destroy-guard halts the auto-apply if the ruleset change is a force-replacement (Phase 0.3); a `[ack-destroy]` on the merge commit line is required only in that case. Do not assume the issue's "operator-gated" framing applies to this file.
- **Flip BOTH `expression` host AND `target_url.value` together** for each of the 9 rules. Expression-only flip = rules never match www traffic → legacy `.html` 404s at apex. Target-only flip = www→www redirect persists (no improvement). Live today: `www/pages/agents.html` → `301 → www/agents/` (then out-of-band → apex), a 2-hop chain the correct flip collapses to 1 hop.
- **Rule 10 is host-preserving — do NOT flip it.** Its target `concat("https://", http.host, …)` is canonical-agnostic; its only `www` literal is in the ACME carve-out host set, which MUST keep covering www (the www cert path). Touching it risks breaking HTTPS upgrade on `app`/`deploy` subdomains and cert renewal.
- **`soleur_www` 2xx assertion is already broken** against the live 301 — this is an active false-page source, not a latent risk. The equals-301 conversion fixes a live alerting bug.
- **Sentry uptime apply uses a 3-token env, not the 2-var CF triplet:** beyond `AWS_*` (R2) + `--name-transformer tf-var` (Doppler), the Sentry root needs `SENTRY_AUTH_TOKEN` exported separately. Operator must use the `iac-terraform-prd` internal-integration token locally (ADR-031 §local-token). base_url is the org-subdomain, NOT `eu.sentry.io` (slug-rewrite trap — see sentry/main.tf comment).
- **ops-remediation issue-link discipline:** PR body uses `Ref #4577` / `Ref #4573`, NOT `Closes` — the CF apply lands on merge but the Sentry apply + full curl verification are post-merge; `gh issue close 4577` runs after Phase 4. `Closes` would false-resolve at merge before the Sentry monitor is applied.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `aggregate pattern`.)
