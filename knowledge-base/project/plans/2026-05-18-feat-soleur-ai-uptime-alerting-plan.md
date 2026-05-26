---
title: "feat(infra): alerting/monitoring for soleur.ai (PR-β of 2026-05-18 cert outage post-mortem)"
date: 2026-05-18
status: in-progress
tags: [infra, terraform, cloudflare, sentry, betterstack, monitoring, alerting, post-mortem]
related:
  - "#3974 (the ACME-aware HTTPS upgrade fix)"
  - "#3986 (the inline-into-seo_page_redirects fix)"
  - "#3976 (the operator runbook for cert recovery — CLOSED)"
---

# feat(infra): alerting/monitoring for soleur.ai (PR-β of 2026-05-18 cert outage post-mortem)

## Background

On 2026-05-18 we recovered from a soleur.ai GitHub Pages cert outage. Root cause: a Cloudflare ruleset rule was 301-redirecting `/.well-known/acme-challenge/*` before Let's Encrypt could complete its HTTP-01 challenge, so the cert silently expired without renewal. **We had ZERO observability** — no uptime check, no cert-expiry poll, no alert on the ACME carve-out regressing.

PR #3974 + #3986 closed the **fix half** of the post-mortem (the ACME-aware ruleset). This PR (β) closes the **alerting/monitoring half**. A sibling PR (γ, running in parallel) handles daily cert-state polling — explicitly **out of scope** here to avoid duplicate work.

The two halves together codify: "next time the ACME carve-out regresses, we hear about it within minutes — not at the next renewal failure 60 days later."

## Goal

Add four monitoring/alerting resources to the existing `apps/web-platform/infra/` Terraform roots (do NOT create a new root — `hr-every-new-terraform-root-must-include-an` requires drift detection + PR-time validation for new roots, and the existing roots already have these):

1. **Three Sentry uptime checks** — primary visibility on the public surfaces of soleur.ai.
2. **One Sentry uptime check on the ACME carve-out probe** — alert when status != 404 (proves Rule 10 of `cloudflare_ruleset.seo_page_redirects` is still firing).
3. **One BetterStack uptime monitor on the apex** — multi-region, independent second-source uptime signal so we are not blind if Sentry itself is degraded.
4. **One Cloudflare notification policy on origin 5xx rate** — catches recurrence of the 526-class "CF edge can't verify origin cert" incident.

## User & Brand Impact (hr-weigh-every-decision-against-target-user-impact)

**Target user:** Soleur operators (today: deruelle, 1-person ops); secondarily, alpha-cohort users hitting soleur.ai.

**Brand impact of doing nothing:**
- The 2026-05-18 outage was visible to every alpha user attempting to land on soleur.ai for ~24h before discovery via a hand-curl. For an early-stage developer-tool brand whose pitch is "the agent-native platform", the single worst signal is "their own marketing site is down and nobody at the company knows." This is a brand-survival-threshold-class risk.
- The ACME carve-out is a single Cloudflare ruleset expression away from regressing. A pure-text `seo-rulesets.tf` edit that drops the `and not (...)` clause would silently re-introduce the outage in 60-89 days (next cert renewal). No CI check catches that — only a live probe does.

**Brand impact of this PR (positive):**
- Three independent signals (Sentry primary, BetterStack secondary, ACME probe) means a single-vendor outage at Sentry OR BetterStack still leaves us with surviving signal. Defense in depth on the OBSERVABILITY layer mirrors the defense-in-depth we already have on the TRAFFIC layer (multiple CF tokens, narrow scopes).
- The ACME probe specifically catches the regression class that caused the outage. It is **load-bearing** — without it, the next regression would go undetected until the next certificate renewal attempt fails (60-89 days later in the worst case).
- The 5xx notification policy catches a different failure class than uptime: a partial degradation where the apex serves SOME 200s but 526s spike. Uptime-only monitors would false-green if the probe hit the 200 path; the 5xx rate alert closes that gap.

**Brand impact of NOT shipping the ACME probe (the most novel item):**
- Without it, every observability investment in this PR has a 60-day half-life. The 526s-rate alert and the apex uptime checks would have fired during the actual 2026-05-18 outage, yes — but they would NOT have caught the silent ruleset edit that CAUSED the outage. The probe is the only signal that tells us "the carve-out is still alive **before** the cert expires."

**Brand impact of false positives (cost-side):**
- A flaky third-party endpoint OR a Sentry-side probe-host issue could fire a false-positive page on the ACME probe. Mitigated by `downtime_threshold = 3` (three consecutive 200/301 reads required) and a 5-minute interval — so 15 minutes of sustained regression before paging.
- The Cloudflare 5xx policy uses CF's default alerting threshold (no operator-tuning surface in v4 provider beyond `alert_type`). Operator can mute via the Cloudflare dashboard if it proves noisy; we will iterate based on the first 30 days of fire history.

## Constraints

- **Reuse existing TF roots.** `apps/web-platform/infra/` for BetterStack + Cloudflare resources. `apps/web-platform/infra/sentry/` for Sentry resources (existing root with its own state key + provider auth). Both are existing roots — no new root, hard rule `hr-every-new-terraform-root-must-include-an` satisfied by reuse.
- **Cloudflare provider is pinned to `~> 4.0`**. Use v4 syntax (`email_integration { id = ... }` block) for `cloudflare_notification_policy`, matching the existing `service_token_expiry` resource in `tunnel.tf:75-85`. Do NOT use v5 `mechanisms = {}` map syntax.
- **Sentry provider is pinned to `0.15.0-beta2`** (beta). `sentry_uptime_monitor` is documented as beta-status in the provider docs but is supported and has a stable resource schema (all required attributes available: `url`, `method`, `interval_seconds`, `timeout_ms`, `environment`, `assertion_json`). Beta-status note must appear in the `.tf` file header so a future maintainer knows the schema may shift on provider stable release.
- **BetterStack provider already declared** at `apps/web-platform/infra/main.tf:35-38` (`betterstackhq/better-uptime ~> 0.20`). Reuse — do not re-declare.
- **Doppler credentials live at `prd_terraform / BETTERSTACK_API_TOKEN`** (already wired through `variables.tf:142-146` → `main.tf:47-49`). No new credentials needed.
- **Auto-apply boundary is conservative.** `.github/workflows/apply-sentry-infra.yml` auto-applies *only* `sentry_cron_monitor.*` resources via explicit `-target=` flags. `sentry_uptime_monitor.*` is NOT auto-applied — operator runs `terraform apply` manually after merge, same posture as `sentry_issue_alert.*`. Document this in the new file's header. Extending auto-apply to uptime monitors is a clean follow-up, deferred per `wg-when-deferring-a-capability-create-a`.
- **Cite #3976 / #3974 / #3986 in the PR description** as the precedent for why this PR exists.
- **Do NOT add cert-poll workflows** — that is PR-γ's scope.
- **Follow all AGENTS.md hard rules**, in particular: `hr-always-read-a-file-before-editing-it`, `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-no-dashboard-eyeball-pull-data-yourself`.

## Files Touched

```
apps/web-platform/infra/uptime-alerts.tf                 (NEW — BetterStack + Cloudflare 5xx notif)
apps/web-platform/infra/sentry/uptime-monitors.tf        (NEW — 4× sentry_uptime_monitor)
knowledge-base/project/plans/2026-05-18-feat-soleur-ai-uptime-alerting-plan.md  (this file)
```

No changes to `main.tf`, `variables.tf`, the existing `seo-rulesets.tf`, or the apply-sentry-infra workflow.

## Resource Inventory

### 1. `apps/web-platform/infra/sentry/uptime-monitors.tf` (NEW)

Four `sentry_uptime_monitor` resources, all in the `web-platform` project on the `jikigai-eu` org:

| Resource name | URL | Expected | Interval | Timeout | Notes |
|---|---|---|---|---|---|
| `soleur_apex` | `https://soleur.ai/` | 200 (or 200-299) | 300s | 10000ms | Apex — primary, GH Pages-fronted; this is the URL alpha users hit. |
| `soleur_www` | `https://www.soleur.ai/` | 200 (or 200-299) | 300s | 10000ms | www — secondary, CF-canonical. Apex 301s to www post-PR #3974. |
| `soleur_changelog_deep` | `https://soleur.ai/changelog/` | 200 (or 200-299) | 600s | 10000ms | Deep path — guards against the "root serves 200 but every other page 404s" failure mode (Eleventy build half-broken). 10min interval (cheaper than 5min, still well under any plausible mean-time-to-fix). |
| `soleur_acme_probe` | `https://soleur.ai/.well-known/acme-challenge/probe` | **404** | 300s | 10000ms | **Load-bearing.** Alerts when status != 404. 200 means CF cached something funky on that path; 301 means Rule 10's ACME carve-out regressed and the next cert renewal will silently fail. Either way, alert. |

**Assertion shape (v0.15.0-beta2 provider):**

For the 200-class checks:
```hcl
assertion_json = provider::sentry::assertion(
  provider::sentry::op_and(
    provider::sentry::op_status_code_check("greater_than", 199),
    provider::sentry::op_status_code_check("less_than", 300),
  )
)
```

For the ACME probe (alert when NOT 404):
```hcl
assertion_json = provider::sentry::assertion(
  provider::sentry::op_status_code_check("equals", 404)
)
```

Sentry treats the assertion as the **success condition** — it fires an alert (creates an issue) when the assertion is FALSE. So `equals 404` means: this probe is healthy when CF serves 404 (the "no real challenge token" response), and we alert when it serves anything else.

**Common attributes for all four:**
- `organization = var.sentry_org` (defaults to `jikigai-eu`)
- `project = var.sentry_project` (defaults to `web-platform`)
- `environment = "production"`
- `method = "GET"`
- `downtime_threshold = 3` (three consecutive failed checks before paging — absorbs single-probe-host hiccups)
- `recovery_threshold = 1` (one success returns to healthy — symmetric with `sentry_cron_monitor` defaults in this repo)

**Why no `owner = { team_id = ... }`:** The existing `sentry_issue_alert.*` resources omit `owner` and rely on default routing (project members). Uptime monitors will inherit the same project-level notification routing without an explicit team assignment. Adding `owner` would require a `sentry_team` resource that does not currently exist in the root — out of scope.

### 2. `apps/web-platform/infra/uptime-alerts.tf` (NEW)

#### 2a. `betteruptime_monitor "soleur_apex"`

Second-source apex uptime check. Multi-region by default (BetterStack's `regions` attribute defaults to all four when omitted).

```hcl
resource "betteruptime_monitor" "soleur_apex" {
  monitor_type        = "status"           # 2XX expected
  url                 = "https://soleur.ai/"
  pronounceable_name  = "soleur dot ai apex"

  check_frequency     = 180                # 3 minutes — denser than Sentry to catch fast transients
  request_timeout     = 10                 # seconds
  confirmation_period = 60                 # require 60s of failure before declaring incident
  recovery_period     = 60                 # 60s of success to auto-resolve
  follow_redirects    = true               # apex 301s to www post-PR #3974 — follow it

  email = true                             # free tier — email-only
  call  = false
  sms   = false
  push  = false

  team_name = "Your team"                  # literal name of the only team in the workplace, see inngest.tf:120-129
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null

  verify_ssl = true                        # belt-and-suspenders: catches cert expiry as a separate failure mode

  # Operator-tunable. Defaults to false (active).
  paused = false
}
```

**Optional `betteruptime_policy.uptime`** (count-gated on `betterstack_paid_tier`, defaults false → not provisioned). Mirrors the `betteruptime_policy.inngest` pattern at `inngest.tf:140-156`:

```hcl
resource "betteruptime_policy" "uptime" {
  count = var.betterstack_paid_tier ? 1 : 0
  name           = "soleur-uptime-policy"
  incident_token = null
  repeat_count   = 3
  repeat_delay   = 60
  steps {
    type        = "escalation"
    wait_before = 0
    urgency_id  = null
    step_members {
      type = "current_on_call"
    }
  }
}
```

#### 2b. `cloudflare_notification_policy "soleur_ai_5xx"`

Page-level 5xx-rate alert on the soleur.ai zone. Catches the 526-class "CF edge can't verify origin cert" incident, plus generic origin-error spikes.

```hcl
resource "cloudflare_notification_policy" "soleur_ai_5xx" {
  account_id  = var.cf_account_id
  name        = "soleur.ai origin 5xx rate spike"
  description = "Page-level alert on origin 5xx errors for the soleur.ai zone. Catches recurrence of the 2026-05-18 cert outage class (526 / origin cert validation failures) plus other origin-side degradation. Precedent: cloudflare_notification_policy.service_token_expiry (tunnel.tf:75-85)."
  alert_type  = "http_alert_origin_error"
  enabled     = true

  email_integration {
    id = var.cf_notification_email
  }
}
```

**Why `http_alert_origin_error` and not `http_alert_edge_error`:** the 2026-05-18 incident was a 526 (Cloudflare edge → origin TLS handshake failed because the GitHub Pages origin cert was expired). 526 is classified as an origin error from CF's POV, not an edge error. `http_alert_edge_error` covers CF-internal 5xx (502/520/521 when CF itself can't route), which is rarer and would mostly be a CF-side issue we couldn't fix anyway. Filing both is tempting but doubles email noise for low marginal signal — start with origin-error and add edge-error in a follow-up if the real production fire mix shows we are missing edge-error events.

**Why no `filters = { zones = [var.cf_zone_id] }`:** The provider v4 schema supports zone filters, but for an account that only has the soleur.ai zone today (verified — sole `cf_zone_id` reference across the root), the filter is redundant and adds churn risk on future apply if the filter shape changes. Re-evaluate when a second zone lands.

## Test Scenarios (`soleur:qa` invocation source)

These are the post-merge / post-apply verifications. QA skill consumes this section to drive Phase 5.5 checks. NOT all checks can run pre-merge (Cloudflare/Sentry/BetterStack are live SaaS — `terraform plan` is the pre-merge gate; live verification is post-apply).

### TS-1: `terraform validate` and `terraform fmt -check` pass on both roots

```bash
cd apps/web-platform/infra && terraform fmt -check && terraform init -backend=false -input=false && terraform validate
cd apps/web-platform/infra/sentry && terraform fmt -check && terraform init -backend=false -input=false && terraform validate
```

Both must exit 0. This is the only check that runs in CI (`infra-validation.yml`).

### TS-2: `terraform plan` is reviewable

Pre-merge, run `terraform plan` against both roots from a workstation with prd_terraform credentials. Confirm:
- Exactly 4 `sentry_uptime_monitor` resources to be created.
- Exactly 1 `betteruptime_monitor` resource to be created.
- Exactly 1 `cloudflare_notification_policy` resource to be created.
- ZERO destroys on existing resources.

### TS-3: Live ACME probe still returns 404 (manual, pre-apply)

```bash
curl -sI 'https://soleur.ai/.well-known/acme-challenge/probe' | head -1
```

Expected: `HTTP/2 404`. If it returns 200 or 301 today, the ACME carve-out is ALREADY regressed — abort apply and surface to the operator as a real-incident-in-progress rather than a planned change.

### TS-4: Each Sentry uptime monitor visible in dashboard (post-apply)

After `terraform apply` in `apps/web-platform/infra/sentry/`, the operator navigates to `https://jikigai-eu.sentry.io/insights/uptime/` (or whatever the current dashboard URL is — Sentry uptime is in beta per the provider docs) and confirms 4 monitors listed with the expected URLs, intervals, and "Active" status. `hr-no-dashboard-eyeball-pull-data-yourself` — also pull via:

```bash
curl -sH "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/uptime/" | \
  jq '.[] | {name, url: .urlIntervalSeconds // .url, status}'
```

(Sentry API path is beta; substitute the documented endpoint if the above 404s.)

### TS-5: BetterStack monitor visible in dashboard (post-apply)

```bash
curl -sH "Authorization: Bearer $BETTERSTACK_API_TOKEN" \
  "https://uptime.betterstack.com/api/v2/monitors" | \
  jq '.data[] | select(.attributes.url == "https://soleur.ai/") | {name: .attributes.pronounceable_name, status: .attributes.status}'
```

Expected: one entry, status `up` after the first check (within 3 minutes of apply).

### TS-6: Cloudflare notification policy visible (post-apply)

```bash
curl -sH "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/alerting/v3/policies" | \
  jq '.result[] | select(.name == "soleur.ai origin 5xx rate spike")'
```

Expected: one entry, `enabled: true`, `alert_type: "http_alert_origin_error"`.

### TS-7: ACME-probe-regression simulation (deferred — operator-driven, NOT in CI)

To verify the ACME probe actually catches a regression, the operator can (in a controlled test window) temporarily remove the `and not (...)` ACME-exclusion clause from Rule 10 of `seo_page_redirects` and apply. Sentry should fire within 15 minutes (3 consecutive failed 300s-interval checks). After confirming the fire, revert. This is **NOT** automated — running this in CI would intentionally break production. Operator decision whether to run this once after merge as a "smoke test" or to trust the assertion logic.

## Implementation Phases

### Phase 1: Read precedent files (DONE — pre-plan)

Confirmed:
- `apps/web-platform/infra/main.tf:35-49` declares betterstackhq and Doppler providers.
- `apps/web-platform/infra/tunnel.tf:75-85` is the v4 `cloudflare_notification_policy` precedent.
- `apps/web-platform/infra/seo-rulesets.tf:240-254` is Rule 10 of `seo_page_redirects` — the ACME carve-out we are guarding.
- `apps/web-platform/infra/sentry/` is an existing Terraform root (separate state key per `main.tf:7`).
- `apps/web-platform/infra/sentry/cron-monitors.tf` is the precedent shape for Sentry resources in this root.
- `.github/workflows/apply-sentry-infra.yml` auto-applies `sentry_cron_monitor.*` ONLY (via explicit `-target=` flags) — uptime monitors will be operator-applied, same posture as issue alerts.
- `sentry_uptime_monitor` schema verified against `terraform providers schema -json` against pinned provider v0.15.0-beta2.
- `betteruptime_monitor` schema verified the same way.
- `cloudflare_notification_policy` alert types enumerated from provider docs; `http_alert_origin_error` is the canonical 5xx-from-origin signal.

### Phase 2: Author the two new `.tf` files

1. Write `apps/web-platform/infra/sentry/uptime-monitors.tf` with the 4 `sentry_uptime_monitor` resources + an operator-apply note in the header (mirroring the issue-alerts.tf header style).
2. Write `apps/web-platform/infra/uptime-alerts.tf` with the BetterStack monitor + conditional policy + Cloudflare notification policy.

Both files include extensive in-file comments citing #3976 / #3974 / #3986 and explaining the load-bearing-ness of the ACME probe.

### Phase 3: Local validation

```bash
cd apps/web-platform/infra && terraform fmt -check && terraform init -backend=false -input=false && terraform validate
cd apps/web-platform/infra/sentry && terraform fmt -check && terraform init -backend=false -input=false && terraform validate
```

If either fails, fix and rerun. Do not commit if validate fails.

### Phase 4: Commit + push + PR

Two commits (one per root) keep blame scoped:
1. `feat(infra): add sentry uptime monitors for soleur.ai apex/www/changelog + ACME probe`
2. `feat(infra): add betterstack apex monitor + cloudflare origin-5xx notification policy`

PR body cites #3976 / #3974 / #3986 explicitly and lists the four resources.

### Phase 5: Review (soleur:review)

Standard `/soleur:review`. Reviewers will check:
- v4 vs v5 Cloudflare syntax (already covered in Constraints).
- Sentry assertion semantics (success = assertion-true; alert fires when assertion-false).
- That the ACME probe URL is *not* a real challenge token (`/probe` is a synthetic path that ALWAYS 404s today — verified pre-plan).
- That `paused = false` on the BetterStack monitor is correct (vs. the `paused = true` posture on `betteruptime_heartbeat.inngest_prd` — heartbeats need to be paused pre-deploy; uptime monitors don't, since the URL is already live).

### Phase 6: QA (soleur:qa)

Runs TS-1 and TS-2 inline. TS-3 (live ACME probe) MUST run. TS-4/5/6 run post-apply by the operator — they are documented here for the runbook, not blocking on this PR's merge.

### Phase 7: Ship (soleur:ship)

Standard ship flow. After merge to main, **the operator** runs `terraform apply` in `apps/web-platform/infra/sentry/` AND `apps/web-platform/infra/` to materialize the new resources. (Cron monitors auto-apply; uptime monitors do not, per the existing workflow's `-target=` scope.)

Post-apply, runbook the operator through TS-4/5/6 to confirm the resources are live and reporting.

## Open Questions / Deferred

- **Q1:** Should we also add a `sentry_uptime_monitor` on `https://www.soleur.ai/changelog/` (in addition to apex+changelog)? **Decision:** No, deferred. The apex+www pair plus the one deep path covers the "apex breaks but www works" and "root 200 but content 404" classes. A second deep-path probe on www adds marginal signal and a 4th line item to the Sentry dashboard noise. Re-evaluate after 30 days of operating data.
- **Q2:** Should we extend `.github/workflows/apply-sentry-infra.yml` to auto-apply uptime monitors? **Decision:** Deferred per `wg-when-deferring-a-capability-create-a`. Open a follow-up issue post-merge titled "auto-apply sentry_uptime_monitor in apply-sentry-infra.yml" and capture the same `-target=` enumeration pattern. Why deferred: extending CI is its own review surface (gate-call-graph closure, kill-switch coverage) and would bloat this PR's diff. The operator-driven apply path is documented in the new file's header.
- **Q3:** Should we add Slack/PagerDuty mechanisms to the Cloudflare notification policy? **Decision:** No, follow precedent. The existing `service_token_expiry` policy in `tunnel.tf` uses `email_integration` only. Same posture here. Multi-channel is an org-wide upgrade, not a per-policy decision.
- **Q4:** Should the BetterStack monitor use a `monitor_group_id`? **Decision:** No groups exist yet in the workplace. Adding one is a separate decision (it shows up in the BetterStack dashboard as a folder). Defer until a second monitor lands and the operator wants grouping.

## Risk Notes

- **R1 (low):** Sentry uptime is in beta. The provider may rename attributes on stable release. Mitigation: file header comment flagging beta status; subscribe to provider release notes via the existing `terraform init -upgrade` cadence.
- **R2 (low):** Cloudflare `http_alert_origin_error` may be noisy if GH Pages has occasional 5xx blips. Mitigation: 30-day operate-and-tune period; mute or add filters if false positives dominate. Cost of being too noisy << cost of missing the next cert outage.
- **R3 (very low):** A future edit to `seo-rulesets.tf` Rule 10's expression that REMOVES the ACME-exclusion clause would regress the carve-out silently — but the ACME probe SPECIFICALLY catches this. The probe IS the mitigation for this risk; this PR closes the loop.

## Acceptance Criteria

- [ ] `apps/web-platform/infra/sentry/uptime-monitors.tf` exists with 4 `sentry_uptime_monitor` resources (apex, www, changelog, acme-probe).
- [ ] `apps/web-platform/infra/uptime-alerts.tf` exists with 1 `betteruptime_monitor`, 1 conditional `betteruptime_policy`, 1 `cloudflare_notification_policy` (origin-5xx).
- [ ] Both roots `terraform validate` cleanly.
- [ ] Both roots `terraform fmt -check` clean.
- [ ] PR body cites #3976 / #3974 / #3986 as precedent.
- [ ] PR body uses `Closes #N` only if a tracking issue is opened for this PR (none required — this PR is itself the closure of the post-mortem alerting half).
- [ ] In-file comments explain ACME probe load-bearing-ness AND the assertion semantics (alert on NOT-404).
- [ ] No changes to `seo-rulesets.tf` (PR-β alerts on it, does not edit it).
- [ ] No new CI workflows added in this PR (auto-apply extension deferred to follow-up per Q2).
