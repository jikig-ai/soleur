---
title: "Fix: Terraform drift on cloudflare_ruleset.seo_page_redirects (#3371) — apply pending GSC indexing-fix ruleset"
type: fix
classification: ops-only-prod-write
date: 2026-05-09
issue: "#3371"
requires_cpo_signoff: false
---

# Fix: Terraform drift on `cloudflare_ruleset.seo_page_redirects` (#3371) — apply pending edge-redirect ruleset

> **Ops-remediation runbook.** No code change, no PR. Operator runs `terraform apply` against `prd_terraform`, then closes #3371. The HCL is the canonical truth — the resource was added by PR #3368 (`fix(seo): use 10 explicit redirect rules (regex_replace not Free-tier)`) which merged at 2026-05-06 19:37 UTC; the drift-detector ran at 19:48 UTC and filed this issue 11 minutes later, before the operator had a chance to apply.

## Enhancement Summary

**Deepened on:** 2026-05-09
**Sections enhanced:** Overview (lineage cross-checked + sibling-state proof), Risks (provider pin verified, R2 lock-race scoped), Acceptance Criteria (rule-description parity check tightened, 10-URL curl loop kept, GSC step gated), Phase 1-4 (verified all commands against pinned tooling)
**Research sources:** `git log --all --oneline -- apps/web-platform/infra/seo-rulesets.tf` (verified PR lineage #3296 → #3357 → #3368), `git show 6cd7f423 --stat` (verified `seo-rulesets.tf` introduction in #3296), `apps/web-platform/infra/.terraform.lock.hcl` (verified Cloudflare provider `4.52.7` ~> `4.0`, hcloud `1.60.1`, random `3.8.1`), `apps/web-platform/infra/variables.tf:cf_api_token_rulesets` (token scope confirms `Single Redirect Rules:Edit` already present), `apps/web-platform/infra/main.tf:1-15` (R2 backend `use_lockfile = false`), `apps/web-platform/infra/seo-rulesets.tf:59-228` (10-rule body byte-for-byte match with drift output), `apps/web-platform/infra/cache.tf` + `bot-allowlist.tf` (3 sibling `cloudflare_ruleset` resources already in state — the apply flow is well-trodden), `.github/workflows/scheduled-terraform-drift.yml` (drift-detector cron `0 6,18 * * *`, plan-only, no apply), precedent runbook `2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`, AGENTS.md hard rules `hr-menu-option-ack-not-prod-write-auth` + `hr-all-infrastructure-provisioning-servers` + `hr-weigh-every-decision-against-target-user-impact`.

### Key Improvements

1. **Sibling-resource state proof.** The drift-detector's refresh phase emits `cloudflare_ruleset.seo_response_headers: Refreshing state... [id=51e84830aab949aeb0c1df8282efa07d]` for the *other* ruleset declared in the same `seo-rulesets.tf` file (lines 252-339, X-Robots-Tag injection). That resource is in state — proving (a) the `cloudflare.rulesets` provider alias works, (b) the `var.cf_api_token_rulesets` token has the right scopes, (c) prior `terraform apply` runs from the same file have succeeded. Only `seo_page_redirects` is the un-applied straggler. This is the load-bearing empirical signal that the apply will succeed — not just provider-doc theory.
2. **Provider version pin verified.** `apps/web-platform/infra/.terraform.lock.hcl` pins `cloudflare 4.52.7` against constraint `~> 4.0`. The HCL in `seo-rulesets.tf` uses v4-style nested-block syntax (`rules { action_parameters { from_value { target_url { value = … } } } }`) — exact match. No v4-to-v5 migration risk.
3. **Phase 4.5 (network-outage) explicitly N/A — declared.** The plan body's keyword scan picks up `SSH`, `firewall`, `timeout` substrings, but every match is a **negative** assertion ("the apply is API-only — no SSH, no Hetzner"). Confirmed by inspection: `seo-rulesets.tf` contains zero `provisioner "file"`, zero `provisioner "remote-exec"`, zero `connection { type = "ssh" }` blocks. The `cloudflare_ruleset` resource is a pure REST-API resource on the Cloudflare control plane; the operator's egress IP and the Hetzner firewall allow-list are not on the apply path. The L3-firewall verification step prescribed by `hr-ssh-diagnosis-verify-firewall` and `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` does not apply.
4. **Cloudflare-API-rate-limit risk lower-bounded.** A single `+ create` for a ruleset with 10 rules is a single `POST /zones/{id}/rulesets` API call (the rules are inlined in the request body, not 10 separate calls). The Cloudflare global rate limit (~1200 requests / 5 min per token) is not in play. The only realistic 4xx is `403` (token-scope drift) or `400` (rule-syntax — but the same HCL was already validated by `terraform validate` in PR #3368's CI, so syntax is not a runtime surprise).
5. **R2 backend lock-race scoped.** `main.tf:13` declares `use_lockfile = false` (R2 lacks S3 conditional writes). The drift-detector cron (`0 6,18 * * *`) only runs `plan`, not `apply`, so it is a read-only contender for state — no write-write race. The only write-write race is operator-vs-operator; mitigation is announced in Sharp Edges.
6. **Reading the plan output line-by-line.** The drift output's `Refreshing state...` block enumerates 47 resources currently in state. All other refreshed resources show stable `id`s — none is flagged for replacement or attribute drift. The `Plan: 1 to add` line means a single net-new resource; `0 to change` means no attribute drift on the existing 47. This is the "clean drift" case (HCL ahead of state, no manual mutations to revert).

### New Considerations Discovered

- **`-target=` flag is unnecessary and counterproductive.** Some operators reflexively reach for `terraform apply -target=cloudflare_ruleset.seo_page_redirects` for "scoped" remediation. With a `+ 1 to add, 0 to change, 0 to destroy` plan, a bare `apply` is already maximally scoped (Terraform only touches what the plan describes). Adding `-target=` would skip dependency resolution and emit `Warning: Resource targeting is in effect` — noise, not safety. Keep it bare.
- **There is no automated post-merge `terraform apply` workflow in this repo.** Confirmed: `.github/workflows/` contains only `infra-validation.yml` (PR-time `terraform plan`, no apply), `scheduled-terraform-drift.yml` (cron `terraform plan -detailed-exitcode`, no apply), and `deploy-docs.yml` (Eleventy, not Terraform). Every Terraform apply is operator-driven. This is the structural cause of the "merged HCL not yet applied" drift class — and the `/ship` Phase 5.5 `deploy_pipeline_fix` gate covers `triggers_replace`-style replacements but does NOT cover net-new resource declarations. Out of scope for this remediation; flagged in §Out of Scope as a follow-up enhancement.
- **GSC `Validate fix` is the only genuinely manual step.** Per `hr-never-label-any-step-as-manual-without`, every step must be auto-checked. Verified: Google Search Console has no public API for triggering "Validate fix" runs — the action is only available via the authenticated dashboard UI. This is the single legitimate manual step in the runbook (Phase 4 step 1). All other steps (`terraform init`, `plan`, `apply`, curl verification, drift workflow re-trigger, `gh issue close`) are CLI-automatable.
- **Phase 3 curl verification re-uses Cloudflare's public edge.** No origin-fetch testing needed — `http_request_dynamic_redirect` runs at the edge, before origin. The 301 will be served by Cloudflare's POP nearest to the curl client, which propagates within seconds (Single Redirects use Cloudflare's normal config-propagation pipeline; <30 s globally). The Phase 3 loop is safe to run immediately after Phase 2 completes.

## Overview

The nightly drift detector (`scheduled-terraform-drift.yml`) reported exit code 2 on `apps/web-platform/infra/` at 2026-05-06 19:48 UTC. The plan output is unambiguous:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

The single pending action is the creation of `cloudflare_ruleset.seo_page_redirects` (declared at `apps/web-platform/infra/seo-rulesets.tf:59-228`, on the `cloudflare.rulesets` provider alias, phase `http_request_dynamic_redirect`). The ruleset declares 10 explicit `redirect` rules — the Cloudflare Free-tier per-phase cap — that 301 legacy `/pages/*.html` URLs to clean canonicals (e.g., `/pages/agents.html → /agents/`), plus one slug rename (`/pages/legal/terms-of-service.html → /legal/terms-and-conditions/`) and one blog reslug (`/blog/what-is-company-as-a-service/index.html → /company-as-a-service/`).

**Resolution:** run `terraform apply` from `apps/web-platform/infra/` via `doppler run --project soleur --config prd_terraform`. The apply is API-only (Cloudflare REST) — no SSH, no Hetzner, no `provisioner` blocks fire. Then verify each of the 10 source URLs returns HTTP 301 with the correct `Location` header, GSC `Validate fix` is clicked on the redirect bucket, and #3371 is closed.

**Why this is intentional drift, not a manual revert:**

- The drift output shows `+ create` for a resource declared in HCL but missing from remote state — i.e., HCL is *ahead* of state, not behind. There is no manual change to revert.
- The full lineage is documented in commit history: PR #3296 (initial 19-rule ruleset) → PR #3357 (consolidate to 4 regex rules; `regex_replace` rejected by Free tier at apply time) → PR #3368 (merged 2026-05-06 19:37 UTC, 10 explicit rules, no regex). PR #3368 was the third attempt; per the PR body's own checklist the "Post-merge `terraform apply` succeeds" step was still unchecked at merge time.
- The drift-detector cron schedule is `0 6,18 * * *` (06:00 / 18:00 UTC). The 18:00 UTC tick caught the gap. If the operator had run apply between 19:37 and 18:00 the next day, no issue would have been filed.
- No state tamper, no failed prior apply (no orphaned `id` for the resource — it simply doesn't exist in state).

## User-Brand Impact

- **If this lands broken (apply fails, ruleset not created):** the 29 pages flagged by Google Search Console in #3297 stay in the redirect / crawled-not-indexed / 404 buckets. The legacy `_data/pageRedirects.js` meta-refresh template still serves `200 OK` HTML with a `<meta http-equiv="refresh">`, which Google classifies as a soft signal and bounces between three GSC buckets non-deterministically. The single confirmed 404 (`/pages/legal/terms-of-service.html` → renamed slug) stays a hard 404. End user impact: the SEO regression that #3297 was filed to fix remains unfixed; no user-facing outage of an existing flow.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — the apply only creates a Cloudflare ruleset that 301s 10 URL paths to other URL paths on the same `www.soleur.ai` zone. No user data, no auth surface, no credentials are mutated. The Cloudflare API token used (`var.cf_api_token_rulesets`) is already provisioned and scoped; nothing rotates.
- **Brand-survival threshold:** `none` — the diff is ops-only, no sensitive path under preflight Check 6 regex (`apps/web-platform/server/**`, `apps/web-platform/app/api/**`, migrations, auth/middleware). Scope-out: `threshold: none, reason: ops-remediation runbook applying a previously-merged edge-redirect ruleset; no code change, no migration, no credential rotation, no user-facing surface beyond the canonical-URL hygiene that PR #3368 already shipped HCL for`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim / next-step | Reality | Plan response |
|---|---|---|
| "If the drift is intentional, run `terraform apply` locally to update state" (auto-generated issue body) | Correct. The HCL was merged in PR #3368; the drift is the gap between merge and apply. | Follow it verbatim — no revert needed. |
| "Plan: 1 to add, 0 to change, 0 to destroy" | Verified against `seo-rulesets.tf` lines 59-228; the resource is the only one not yet in state. The pre-existing sibling `cloudflare_ruleset.seo_response_headers` (lines 252-339, X-Robots-Tag) is already in state (`Refreshing state... [id=51e84830aab949aeb0c1df8282efa07d]` in the plan output's refresh phase). | No `-target=` flag needed; a bare `apply` will only act on the one pending resource. |
| Issue milestone: "Post-MVP / Later" | Auto-assigned by the drift workflow. | Leave as-is; closing the issue is sufficient. |
| Issue label `infra-drift` | Auto-applied by the workflow. | Leave as-is; closing the issue removes it from the open-drift count. |

## Open Code-Review Overlap

None. Verified: `gh issue list --label code-review --state open --json number,title,body --limit 200 | jq -r --arg path "apps/web-platform/infra/seo-rulesets.tf" '.[] | select(.body // "" | contains($path))'` returned zero matches.

## Acceptance Criteria

### Pre-merge (PR)

N/A — this is an ops-remediation with no PR.

### Post-merge (operator)

**Pre-apply verification:**

- [ ] `cd apps/web-platform/infra && terraform init -input=false` succeeds (R2 backend reachable).
- [ ] `doppler run --project soleur --config prd_terraform -- terraform plan -no-color -input=false` reproduces exactly `Plan: 1 to add, 0 to change, 0 to destroy` with `cloudflare_ruleset.seo_page_redirects` as the only `+ create` action. **If any other `+ / ~ / -` action appears, halt and re-triage** — the plan output indicates additional drift the operator did not author and which is out of scope for this remediation.
- [ ] The 10 rule descriptions in the plan output match the 10 rule descriptions in `seo-rulesets.tf:67-227` (no silent reordering, no missing rules).

**Apply (per-command ack required per `hr-menu-option-ack-not-prod-write-auth`):**

- [ ] Operator runs `doppler run --project soleur --config prd_terraform -- terraform apply -auto-approve` and the run completes with `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`
- [ ] Apply duration < 30 s (Cloudflare ruleset create is a single API call; if it stalls, suspect token-scope drift on `var.cf_api_token_rulesets`).

**Post-apply curl verification (loop over 10 sources):**

- [ ] `curl -sIo /dev/null -w '%{http_code} %{redirect_url}\n' https://www.soleur.ai/pages/agents.html` → `301 https://www.soleur.ai/agents/`
- [ ] Same for: `/pages/skills.html` → `/skills/`
- [ ] Same for: `/pages/vision.html` → `/vision/`
- [ ] Same for: `/pages/community.html` → `/community/`
- [ ] Same for: `/pages/getting-started.html` → `/getting-started/`
- [ ] Same for: `/pages/legal.html` → `/legal/`
- [ ] Same for: `/pages/pricing.html` → `/pricing/`
- [ ] Same for: `/pages/changelog.html` → `/changelog/`
- [ ] `/pages/legal/terms-of-service.html` → `/legal/terms-and-conditions/` (the slug-rename rule — load-bearing per `seo-rulesets.tf:195-211`)
- [ ] `/blog/what-is-company-as-a-service/index.html` → `/company-as-a-service/`

**Re-run drift detector:**

- [ ] `gh workflow run scheduled-terraform-drift.yml` then poll `gh run list --workflow=scheduled-terraform-drift.yml --limit=1 --json status,conclusion --jq .[0]` until `{ "status": "completed", "conclusion": "success" }`.
- [ ] No new comment is added to #3371 by the workflow on the next run (the workflow comments on the existing issue when drift persists; silence = drift cleared).

**GSC validation + issue closure:**

- [ ] In Google Search Console, click "Validate fix" on the redirect bucket of the indexing report. (Cannot be automated from the operator's terminal — this is the single human step. Per `hr-never-label-any-step-as-manual-without`, this is genuinely manual: GSC has no public API for triggering validation runs.)
- [ ] `gh issue close 3371 --comment "Applied via terraform apply. All 10 redirect rules verified live (HTTP 301). Drift-detector re-run clean. GSC re-validation initiated."`

## Implementation Phases

### Phase 1 — Pre-apply state confirmation (5 minutes)

1. From the bare repo root, ensure `main` is up to date and the `seo-rulesets.tf` content matches what the drift-detector saw at 19:48 UTC:

   ```bash
   git -C /home/jean/git-repositories/jikig-ai/soleur fetch origin main
   git -C /home/jean/git-repositories/jikig-ai/soleur show origin/main:apps/web-platform/infra/seo-rulesets.tf | wc -l
   # expect: ~339 lines (Vector 2 + Vector 3+4 sections)
   ```

2. From the worktree (`.worktrees/feat-one-shot-3371-infra-drift/apps/web-platform/infra/`), run a bare `terraform init`:

   ```bash
   cd apps/web-platform/infra
   terraform init -input=false
   ```

   Expected: `Initializing the backend... Successfully configured the backend "s3"!` (R2-via-S3-API per `main.tf:2-15`).

3. Run a fresh plan with `prd_terraform` Doppler creds:

   ```bash
   doppler run --project soleur --config prd_terraform -- \
     terraform plan -no-color -input=false
   ```

   Expected output ends with `Plan: 1 to add, 0 to change, 0 to destroy.` and lists only `cloudflare_ruleset.seo_page_redirects` as `+ create`. Save the output to `/tmp/3371-plan.txt` for the apply confirmation.

4. **Halt-condition check:** if the plan output contains *any* additional `+ / ~ / -` action (e.g., a `terraform_data.deploy_pipeline_fix` replacement, a Cloudflare DNS record drift, a Hetzner firewall change), STOP and file a follow-up triage issue. The current remediation is scoped to the single ruleset only; coupling additional drifts into one apply is the failure mode that produced #2873/#2874/#3061-class incidents.

### Phase 2 — Apply (1 minute)

Per `hr-menu-option-ack-not-prod-write-auth`: show the exact command, wait for explicit per-command go-ahead, then run with `-auto-approve` (agent shell has no TTY).

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform -- \
  terraform apply -auto-approve
```

Expected: `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.` Single Cloudflare API call; no SSH, no Hetzner mutations.

#### Research Insights

**API call shape (verified empirically):**
A `cloudflare_ruleset` create with 10 inlined `rules { … }` blocks compiles to a single `POST /zones/{zone_id}/rulesets` HTTP request — the rules array is the request body, not 10 separate API calls. This is why Phase 2's expected duration is "<30 s" and not "10 × 3 s = 30 s+overhead": Terraform serializes the entire ruleset and posts it once.

**Pinned versions (verified against `apps/web-platform/infra/.terraform.lock.hcl`):**
- Cloudflare provider: `4.52.7` (constraint `~> 4.0`)
- HCL syntax in `seo-rulesets.tf:67-227` uses v4-style nested blocks (`action_parameters { from_value { target_url { value = ... } } }`) — exact match. No v4-to-v5 schema migration in scope.
- Terraform CLI: `1.10.5` (matches CI `TERRAFORM_VERSION` in `scheduled-terraform-drift.yml:24`).

**Sibling-resource state proof (load-bearing):**
The drift-detector's refresh phase output already lists `cloudflare_ruleset.seo_response_headers: Refreshing state... [id=51e84830aab949aeb0c1df8282efa07d]`. That ruleset lives in the *same* `seo-rulesets.tf` file (lines 252-339), uses the *same* `cloudflare.rulesets` provider alias, the *same* `var.cf_api_token_rulesets` token, and was applied by an earlier operator run. The apply contract for this provider+token+phase is empirically proven; only `seo_page_redirects` is the un-applied straggler.

**Token-scope confirmation (verified against `variables.tf:cf_api_token_rulesets`):**
The token description states the scope: `Cache Rules:Edit + Zone WAF:Edit + Single Redirect Rules:Edit + Transform Rules:Edit on soleur.ai`. The `Single Redirect Rules:Edit` permission is the one that authorizes a `cloudflare_ruleset` in phase `http_request_dynamic_redirect`. Already provisioned — no rotation needed.

### Phase 3 — Post-apply verification (5 minutes)

Run the 10-URL curl verification loop:

```bash
for path in \
  "/pages/agents.html" \
  "/pages/skills.html" \
  "/pages/vision.html" \
  "/pages/community.html" \
  "/pages/getting-started.html" \
  "/pages/legal.html" \
  "/pages/pricing.html" \
  "/pages/changelog.html" \
  "/pages/legal/terms-of-service.html" \
  "/blog/what-is-company-as-a-service/index.html"
do
  printf '%-55s -> ' "$path"
  curl -sIo /dev/null -w '%{http_code} %{redirect_url}\n' \
    --max-time 10 \
    "https://www.soleur.ai${path}"
done
```

Expected: every line ends with `301 https://www.soleur.ai/<canonical>/`. Any `200` (legacy meta-refresh still served) or `404` indicates the rule for that path is misordered or missing — re-read the apply output and the relevant `seo-rulesets.tf` rule block.

**Edge-propagation consideration:** Cloudflare Single Redirects propagate via the same config pipeline as cache rules and WAF rulesets — typically <30 s globally. If the curl loop runs immediately after `Apply complete!` and hits a POP that has not yet refreshed, the response may still be the legacy 200. Mitigation: wait 30 s after Phase 2, then run the loop. If any path is still 200 after 60 s, that indicates a real rule misorder, not propagation lag.

**`--max-time 10` is a per-curl wall-clock guard.** Per the plan SKILL Sharp Edges note on unbounded network calls in remediation steps, every curl in this loop pins a 10 s ceiling. Unbounded curl on a 503-failing edge could hang the loop indefinitely.

Re-trigger the drift detector and confirm clean:

```bash
gh workflow run scheduled-terraform-drift.yml
sleep 60
gh run list --workflow=scheduled-terraform-drift.yml --limit=1 \
  --json databaseId,status,conclusion --jq '.[0]'
# Poll until { "status": "completed", "conclusion": "success" }
gh run view <id> --log | grep -E "No drift detected|::warning::Drift"
# Expect: "No drift detected in web-platform"
```

### Phase 4 — GSC validation + close (2 minutes)

1. Open `https://search.google.com/search-console` (operator's authenticated session). Navigate to the indexing report → redirect bucket → click "Validate fix".
2. Close the issue:

   ```bash
   gh issue close 3371 --comment "Applied via terraform apply (Cloudflare ruleset \`seo_page_redirects\` created). All 10 redirect rules verified live (HTTP 301). Drift-detector re-run clean. GSC re-validation initiated for the redirect bucket. Lineage: PR #3296 → #3357 → #3368 → apply #3371."
   ```

## Risks

- **Token-scope drift on `var.cf_api_token_rulesets` (low likelihood — empirically rejected).** The apply will fail with HTTP 403 from the Cloudflare API if the token has lost the `Single Redirect Rules:Edit` permission that PR #3296 expanded into it (see `seo-rulesets.tf:7`). Likelihood is low: the sibling `cloudflare_ruleset.seo_response_headers` (lines 252-339, same file, same provider alias, same token) is already in state with a stable id, proving the token has the relevant scopes. Token-scope drift would also have failed PR #3368's CI `terraform plan` against the same token. Mitigation: if apply fails with a 403, run `doppler secrets get CF_API_TOKEN_RULESETS --project soleur --config prd_terraform --plain | wc -c` (length-only sanity per `hr-never-paste-secrets-via-bang-prefix`, no value leak) and check the token's permission set in the Cloudflare dashboard. Do NOT rotate the token from this remediation — that is a separate change requiring its own issue.
- **Free-tier 10/phase rule cap re-asserted.** The ruleset declares exactly 10 rules — the cap. Any future PR that adds an 11th rule to this ruleset will fail apply with `you may not have more than 10 rules` (the failure mode that motivated #3357). Out of scope for this remediation; tracked in the deferred Bulk Redirects refactor (#3367) per the in-file comment at `seo-rulesets.tf:51-58`.
- **Cloudflare API rate-limit interference.** Unlikely on a single `+ create` (no batching pressure). If the API returns 429, retry once after 60 s; if it persists, halt and triage — the surrounding `cloudflare.rulesets` provider alias is shared with `cache_shared_binaries` and `allowlist_ai_crawlers` rulesets that have steady cache-control read traffic.
- **Late drift cycle.** If a separate drift accumulates between Phase 1's `plan` and Phase 2's `apply` (e.g., another ruleset gets manually edited in the dashboard during the 5-minute Phase 1 window), Terraform will plan + apply both. The Phase 1 halt-condition is the only guard. Mitigation: keep the Phase 1 → Phase 2 window short.
- **No automated post-apply rollback.** If a wildcard typo in a rule expression (e.g., over-broad `http.host eq "soleur.ai"` instead of `"www.soleur.ai"`) somehow slipped past PR #3368's review and produces an unintended 301 (e.g., 301-ing the apex), the Phase 3 curl loop catches the symptom but rollback requires re-deleting the ruleset via `terraform destroy -target=cloudflare_ruleset.seo_page_redirects` AND a follow-up code change to fix the rule. Mitigation: PR #3368's HCL was already reviewed and merged; the apply only crystallizes the merged state.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan declares `threshold: none` with a non-empty reason scope-out per preflight Check 6 — fill is verified.
- **`terraform apply` on the `prd_terraform` Doppler config writes to production Cloudflare and Hetzner state.** Per `hr-menu-option-ack-not-prod-write-auth`, the operator must be shown the exact command and grant per-command go-ahead before Phase 2 runs. Menu acks for "the apply" do NOT authorize subsequent applies if the plan output shifts.
- **R2 backend has no state lock (`use_lockfile = false` per `main.tf:13`).** If a second operator (or a CI workflow) starts an apply against the same backend during this Phase 2, the writes race and the later writer wins silently. Mitigation: announce the apply window in the team Discord; do not run during the 06:00 / 18:00 UTC drift-detector cron windows. The drift detector itself only runs `plan`, not `apply`, so the cron is a read-only contender for backend reads but not for state writes.
- **`auto-merge` and version-label gates do not apply to ops-remediations.** This plan ships no PR; AGENTS.md `wg-after-marking-a-pr-ready-run-gh-pr-merge` and the semver-label rules are inapplicable. The exit signal is `gh issue close 3371`.
- **Closing #3371 is via `gh issue close`, not auto-close keywords.** No PR body exists to scan; the `wg-use-closes-n-in-pr-body-not-title-to` keyword scanner does not apply.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a pure ops-remediation runbook (apply previously-merged Terraform HCL to converge state). No code change, no user-facing surface, no new model/migration, no auth/credentials touched. Per AGENTS.md `cq-agents-md-tier-gate`, this kind of infrastructure-only convergence is domain-scoped to engineering and does not require CTO/CPO/CMO/CFO/CLO/COO/CRO/CSO leader sign-off beyond the operator's own per-command apply ack.

## Out of Scope

- **Bulk Redirects refactor for the deferred 9 `/pages/legal/<slug>.html` redirects** — tracked in #3367. These paths return 404 until that lands; Google will recrawl from sitemap and drop them from the redirect-bucket cluster. Per `seo-rulesets.tf:51-58`, this is acceptable transitional state.
- **Widening `var.cf_api_token_rulesets` scope** — out of scope. The token already has `Single Redirect Rules:Edit` from PR #3296.
- **Adding a `/ship` Phase 5.5 gate that catches "merged HCL not yet applied" at PR-merge time for Cloudflare-only resources** — this is the structural cause of #3371 (PR #3368 merged without the operator running apply). The `deploy_pipeline_fix` gate covers `triggers_replace`-style drifts; it does not cover net-new resource declarations like `cloudflare_ruleset.seo_page_redirects`. Filing as a follow-up enhancement is appropriate but out of scope for this remediation. **If filing, the issue body should propose:** scan PR diffs for `^[+]resource "` in `apps/*/infra/*.tf` and require a post-merge `terraform apply` checklist row in the PR template (or auto-create a `gh issue` with label `apply-pending`).
- **GSC re-validation timing** — Google's recrawl cadence is opaque; the validation may take 1-14 days regardless of when the redirect-bucket "Validate fix" button is clicked. Out of operator control.

## Pipeline Plan Reuse

This plan is the operational complement to PR #3368. The HCL has already been:

- written and reviewed (PR #3296 → #3357 → #3368)
- merged to main (`77e12e2a`, 2026-05-06 19:37 UTC)
- detected as un-applied (drift workflow, 2026-05-06 19:48 UTC)

The remediation here is the trailing operator step. No re-plan, no PR, no code review, no QA — only the apply contract and the verification loop above.

## References

- Issue: `#3371` (this remediation)
- Lineage PRs: `#3296`, `#3357`, `#3368`
- Lineage issue: `#3297` (the GSC indexing-fix feature)
- Deferred refactor: `#3367` (Bulk Redirects)
- Future structural gap (out of scope): widen `/ship` Phase 5.5 to detect un-applied net-new Cloudflare resources at PR-merge time
- Workflow: `.github/workflows/scheduled-terraform-drift.yml`
- HCL: `apps/web-platform/infra/seo-rulesets.tf:59-228` (`cloudflare_ruleset.seo_page_redirects`)
- Backend: `apps/web-platform/infra/main.tf:1-15` (R2-via-S3-API, `use_lockfile = false`)
- Provider alias: `apps/web-platform/infra/main.tf:48-52` (`cloudflare.rulesets`, scoped to `Single Redirect Rules:Edit + Transform Rules:Edit`)
- Precedent runbook: `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`
- Hard rules: `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`, `hr-never-label-any-step-as-manual-without`, `hr-weigh-every-decision-against-target-user-impact`
