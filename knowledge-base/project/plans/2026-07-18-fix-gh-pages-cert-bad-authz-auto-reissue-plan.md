<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix(infra): auto-remediate GitHub Pages cert bad_authz (proxy-toggle reissue, self-heal)"
date: 2026-07-18
type: bug
classification: ops-remediation
lane: single-domain
status: planned
branch: feat-one-shot-6657-gh-pages-cert-bad-authz
related_issues: [6657, 3976, 3974, 3986]
precedent_incident: "2026-05-18 soleur.ai marketing site Cloudflare 526 — GitHub Pages LE cert bad_authz on renewal"
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(infra): auto-remediate GitHub Pages cert `bad_authz` — proxy-toggle reissue + self-heal (#6657)

🐛 **P1 / action-required / infra-drift.** Auto-filed 2026-07-18 by `cron-gh-pages-cert-state`.

> **IaC-routing note (Phase 2.8 reviewed):** this plan's entire purpose is to REPLACE the #3976 manual GitHub-Pages-console step with a fully scripted, IaC-routed remediation. Any vendor-console wording below is either a *quoted/refuted* reference to the old runbook or the single genuine vendor-authorization gate (App-manifest permission re-acceptance) that `apps/web-platform/infra/github-app.tf` already documents as an unavoidable GitHub web-authorization limit. See `## Infrastructure (IaC)`.

## Overview

The `soleur.ai` GitHub Pages custom-domain TLS certificate is stuck in ACME state **`bad_authz`** ("The ACME authorization is in a bad state. We need to start over." — GitHub's own `https_certificate.description`). The cert covers `soleur.ai` + `www.soleur.ai`, expires **2026-08-16** (~28 days out). The site is **currently serving `HTTP/2 200` on the still-valid May cert** — there is **no live outage yet**, but every GitHub auto-retry re-fails, so the cert will not renew and will hard-expire on Aug 16, at which point Cloudflare (Full/Full-Strict SSL, origin = GitHub Pages) returns **526** exactly as in the 2026-05-18 incident.

The issue points at the runbook from **#3976** (the May-2026 recovery runbook), whose reissue step (`PM5`) is marked **`type: manual`** with `manual_because: "GH Pages Settings UI is not API-equivalent for cert-reissue trigger"`. **That claim is refuted for the trigger itself** (see Research Reconciliation): the remove-then-re-add gesture IS reproducible via `PUT /repos/{owner}/{repo}/pages` (`cname: null` → re-set), which needs **`Administration: write`** — a permission the Soleur GitHub App **already grants** (`github-app-manifest.json`). Soleur operators are non-technical (`hr-weigh-every-decision-against-target-user-impact`, `feedback_never_defer_operator_actions`), so this plan delivers a **fully scripted, self-healing remediation with zero manual console steps**, exhausting automation per `hr-exhaust-all-automated-options-before` and `hr-verify-repo-capability-claim-before-assert`.

### Live diagnostic evidence (captured 2026-07-18, this session — read-only probes)

| Probe | Result | Meaning |
|---|---|---|
| `gh api /repos/jikig-ai/soleur/pages` → `.https_certificate.state` | `bad_authz` | confirmed; `expires_at: 2026-08-16`; domains `[soleur.ai, www.soleur.ai]` |
| `curl -I https://soleur.ai/` | `HTTP/2 200` | site serving on the still-valid May cert — **no outage; 28-day runway** |
| `curl http://soleur.ai/.well-known/acme-challenge/<nonexistent>` | `404` (not `301`) | **CF ACME carve-out is INTACT** — this is NOT a May-style redirect-interception recurrence |
| `curl http://www.soleur.ai/.well-known/...` | `404` | www carve-out also intact |
| `cloudflare-settings.tf` `always_use_https` | `"off"` | May remediation still in place; no drift on the toggle |
| `dig soleur.ai A` | `188.114.97.2`, `188.114.96.2` | **apex resolves to Cloudflare anycast (PROXIED), NOT GitHub's `185.199.x`** |
| `dns.tf` `cloudflare_record.github_pages` / `.www` | `proxied = true` | apex A-records + www CNAME are orange-clouded |
| `dig soleur.ai CAA` | (empty) | no CAA restriction — any CA permitted; not a blocker |
| `_github-pages-challenge-jikig-ai` TXT | present (`dns.tf:329`) | domain-ownership verification record exists |

## Root Cause — hypotheses (honest dispositions per the ultrathink probe-first discipline)

**The deciding datum — GitHub/Let's Encrypt's internal reason the authorization went bad — is NOT observable from the repo or any operator-side probe.** GitHub exposes only the terminal string `bad_authz`. Therefore no hypothesis below may read CONFIRMED from indirect evidence; the honest verdicts are LIKELY / UNKNOWN, and the remediation is empirical (act, then observe whether the state progresses to `issued`). This section is a hypothesis apparatus, not a proof.

| # | Hypothesis | Evidence for | Evidence against | Disposition |
|---|---|---|---|---|
| **H1** | **Cloudflare proxy (orange cloud) masks GitHub's `185.199.x` origin IPs, so GitHub's domain-config/HTTP-01 validation cannot complete → `bad_authz` on every renewal attempt.** | apex is `proxied=true` and `dig` returns CF anycast; the **2026-05-18 postmortem line 53 documents this exact blocker** ("GH Pages domain-config check failed because CF proxy returned 104.x/172.x anycast IPs instead of GH's expected 185.199.108-111.153 … temporarily disabled CF proxy"); framework research confirms GitHub HTTP-01 renewal "does NOT work" reliably while proxied. | The May cert WAS eventually issued while the steady state is proxied — proving proxying is not a permanent block, only a provisioning-window block. | **LIKELY (primary).** Highest explanatory power; empirically reproduced last incident. Still UNKNOWN as literal cause of *this* authz because GitHub's internal reason is invisible. |
| **H2** | **Stale/stuck ACME order** — GitHub's message literally says "we need to start over"; the order is wedged and a fresh order (remove/re-add cname) clears it. | GitHub's own description; the carve-out + DNS + CAA are all healthy, so a nudge may be all that's needed. | If H1 holds, a nudge WITHOUT a DNS-only window will just re-fail. | **PLAUSIBLE.** The remediation performs the "start over" regardless; H1 and H2 are not mutually exclusive — H2's nudge is necessary, H1's proxy-window is likely also necessary. |
| **H3** | **Let's Encrypt rate-limit** (5 failed-validations/hour and/or 50 duplicate-certs/domain/week) keeps the order wedged; GitHub's repeated auto-retries under H1 may have tripped it. | GitHub auto-retries on a renewal schedule; repeated H1 failures accumulate against the failed-validation limit. | Not directly observable. | **POSSIBLE (bounds retry cadence).** Forces the remediation to be *capped + cooled-down*, never a tight loop. |
| **H4** | May-style **redirect interception** of the ACME path (the original 2026-05-18 cause). | — | **REFUTED by live probe:** the ACME path returns `404`, not `301`; `always_use_https="off"`; Rule 10 carve-out intact. | **REFUTED.** Do not re-fix the May cause. |
| **H5** | **CAA record blocks the CA.** | — | **REFUTED:** `dig soleur.ai CAA` is empty (any CA allowed). | **REFUTED.** |
| **H6** | DNS points away from GitHub / missing verification. | — | apex A-records target `185.199.x` (behind proxy) and the `_github-pages-challenge` TXT is present. | **REFUTED.** |

**Working conclusion (to falsify, not assume):** the remediation must (a) perform the "start over" cname re-add (H2) **while** (b) presenting GitHub/LE a DNS-only apex+www so the origin-IP/HTTP-01 validation can complete (H1), (c) with a hard attempt-cap + cooldown so a wedged order does not burn the LE rate-limit budget (H3). If, after a DNS-only reissue, the state does NOT progress past `bad_authz`, H1+H2 are falsified for this incident and the routine escalates to an `action-required` issue with the full attempt log (never a silent loop).

## Research Reconciliation — claim vs. codebase reality

| Claim (from #3976 runbook / #6657) | Reality (verified this session) | Plan response |
|---|---|---|
| "GH Pages Settings UI is not API-equivalent for cert-reissue trigger" (#3976 `manual_because`) | The **trigger** IS API-reproducible: `PUT /pages` `cname:null` → re-set `cname:"soleur.ai"` (GitHub docs; the console remove/re-add gesture). Needs `Administration: write`, which the App **has**. | Build the reissue as an App-token API sequence. Retire the "manual" framing for the trigger. |
| "cert-reissue automation … requires `pages: write` AND a PAT, NOT the workflow's `GITHUB_TOKEN`" (2026-05-18 poll plan Non-Goal) | That was about a **GHA `GITHUB_TOKEN`**. This runtime uses an **App installation token** with `Administration: write` already granted — a different, sufficient credential. `PUT /pages` is `administration`; `DELETE /pages/builds` is unnecessary (it rebuilds the site, does not reissue the cert). | Use `generateInstallationToken({ permissions: { administration: "write" }, repositories: ["soleur"] })`. **Phase 0 verifies the live grant** (manifest ≠ installation grant, the #4173 class). |
| Runbook `PM5`: "`gh api -X DELETE /repos/.../pages/builds` to re-trigger" | `DELETE /pages/builds` re-runs the **site build**, it does **not** re-order the cert. | Do not use it for reissue. |
| Issue label `infra-drift` implies Terraform drift | The cron statically applies `["action-required","infra-drift"]` to **every** trip (`cron-gh-pages-cert-state.ts` issue-handling). No Terraform drift is implied. | Note only; not a signal. |

## Solution — staged, empirical, self-healing

A new bounded remediation routine (`reissueGhPagesCert`) that runs the **postmortem-proven** recovery order (see learning `2026-02-16-github-pages-cloudflare-wiring-workflow.md`: DNS-only → set custom domain → poll → re-proxy):

1. **Pre-flight (read-only, fail-loud):** re-read `GET /pages` state; verify operator-controllable preconditions still healthy (ACME path `404` over HTTP on apex+www; `always_use_https="off"`; CAA empty/permissive; `_github-pages-challenge` TXT present). If a precondition an operator can't auto-fix is broken (e.g., a CAA appears), skip remediation and file the issue with the specific blocker.
2. **DNS-only window (H1):** via the **Cloudflare API** (token from Doppler `prd_terraform`, same creds `dns.tf` uses), set `cloudflare_record.github_pages` (4 apex A-records) + `cloudflare_record.www` to **`proxied=false`**. This is a *transient* operational toggle that returns to the TF-declared `proxied=true` steady state — no persisted `.tf` change (see §Infrastructure). The still-valid May cert keeps direct hits working during the window (no outage).
3. **Start over (H2):** `PUT /pages` `cname:null`, wait ~30–60s, `PUT /pages` `cname:"soleur.ai"` — forces a fresh ACME order. Re-read after each PUT to confirm it applied (GitHub PATCH-silent-success class, learning `2026-04-10`).
4. **Poll (bounded):** `GET /pages` every ~60s up to a cap (~15 min) for `state ∈ {approved, issued}`. Emit a Sentry breadcrumb per poll with `{state, elapsedMs}`.
5. **Restore proxy (always, even on failure — `finally`):** set apex+www back to `proxied=true`. Assert the CF live state equals `proxied=true` at exit (never leave origin IPs exposed — the security-regression brake).
6. **Verdict + observability:** on `issued` → success (Sentry breadcrumb + heartbeat OK; the poll cron will auto-close #6657 on its next healthy read). On timeout/failure → structured Sentry P0 with the discriminating fields + file/append the `action-required` issue with the full attempt log. **Respect H3:** at most one reissue attempt per invocation, and self-heal auto-invocation is cooldown-gated (default ≥ 24h between attempts, hard cap N per week) so a wedged order cannot burn LE's 5/hour · 50/week budget.

**Two invocation surfaces (both console-free):**
- **Scripted/CI trigger (primary rollout):** a new manual-trigger event `cron/gh-pages-cert-reissue.manual-trigger`, auto-allowlisted via `EXPECTED_CRON_FUNCTIONS`, fireable through the existing `POST /api/internal/trigger-cron` (HMAC, no SSH, no dashboard — precedent `admin-ip-refresh`). This is how #6657 gets remediated in-session.
- **Self-heal (auto):** `cron-gh-pages-cert-state` (the daily poll), when it detects a **state-tripped** `bad_authz`/`failed` (not merely an expiry warning) AND preconditions are healthy AND the cooldown has elapsed, **auto-invokes the reissue routine before filing/commenting the issue**. Only if remediation is exhausted/blocked does it fall back to the `action-required` issue (current behavior, now with attempt logs).

> **Rollout caution (mirrors the 2026-05-18 poll plan):** ship the reissue routine wired but with self-heal auto-invocation behind a conservative cooldown + attempt-cap, and **validate end-to-end against the live #6657 incident via the manual trigger first** (the runway to Aug 16 makes this safe). Deepen-plan/plan-review to confirm whether auto-invoke ships enabled on first merge or dispatch-only-first.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts` — the remediation Inngest function (registration mirrors `cron-gh-pages-cert-state.ts`: fn+account concurrency=1, `retries: 1`, **no `cron:` schedule** — event-triggered only via `cron/gh-pages-cert-reissue.manual-trigger` + internal invoke). Handler in `step.run` units per ADR-033 I1; poll uses `step.sleep`. Pure, injectable helpers (`checkReissuePreconditions`, `setApexProxied(bool)`, `reissueViaCnameToggle`, `pollCertState`) so they unit-test without live IO (the `checkCert` purity pattern).
- `apps/web-platform/server/gh-pages-cert-reissue.ts` (or a `_cert-reissue-shared.ts` sibling) — the pure remediation logic + a thin Cloudflare-API client (`listApexRecords`, `patchRecordProxied`) reusing the `prd_terraform` CF token. (Exact module split is a deepen-plan/`code-architect` call.)
- `apps/web-platform/test/server/inngest/cron-gh-pages-cert-reissue.test.ts` — vitest unit tests (path under `test/**/*.test.ts` to match `vitest.config.ts` `include`). Mock Octokit + CF client; cover: precondition-healthy→reissue→issued; precondition-broken→skip+issue; poll-timeout→restore-proxy+P0; **`finally` restores `proxied=true` even when reissue throws**; cooldown gate; rate-limit-aware cap.

## Files to Edit

- `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-gh-pages-cert-reissue"` to `EXPECTED_CRON_FUNCTIONS` (auto-updates the manual-trigger allowlist + drift-guard count). Note: this changes the expected function-registry count — update `function-registry-count.test.ts` and any Inngest inventory expectation in the same PR.
- `apps/web-platform/server/inngest/routine-metadata.ts` — add the `cron-gh-pages-cert-reissue` metadata row (domain Engineering, ownerRole CTO, `scheduleLabel: "Event-triggered (reissue remediation)"`, `manualTrigger: "allowed"`).
- `apps/web-platform/server/inngest/functions/index.ts` (or wherever functions are registered/served) — register `cronGhPagesCertReissue`.
- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts` — the poll cron: on **state-tripped** `bad_authz`/`failed` with healthy preconditions + elapsed cooldown, invoke the reissue routine before the file/comment path. Keep the expiry-only warning path unchanged (never auto-reissue merely because expiry < 21d and state is `issued`).
- `apps/web-platform/test/server/inngest/cron-gh-pages-cert-state.test.ts` — extend source-shape anchors for the new self-heal branch.
- `apps/web-platform/infra/uptime-alerts.tf` / `apps/web-platform/infra/sentry/*.tf` — declare a Sentry issue-alert (or reuse the existing paging path) for the reissue-P0 op-slug so an *exhausted/failed* remediation pages (no-SSH discoverability). Verify against the existing `soleur_acme_probe` regression alarm to avoid a duplicate.
- (Conditional, Phase 0 outcome) `apps/web-platform/infra/github-app-manifest.json` — **only if** Phase 0 proves the live installation grant lacks `Administration: write` for `PUT /pages`. Adding a manifest permission requires founder re-acceptance via GitHub's web authorization flow (vendor-authorization gate, runbook Step 2.1, drift-guarded by `cron-github-app-drift-guard.ts`). **Expected NOT needed** (manifest already declares `administration: write`), but the split is pre-planned per the operator-mint-sequencing Sharp Edge.

## Infrastructure (IaC)

### Terraform changes
- **Steady state unchanged:** `dns.tf` keeps `cloudflare_record.github_pages` + `.www` at `proxied = true`; `cloudflare-settings.tf` keeps `always_use_https = "off"`. **No persisted `.tf` change** for the proxy toggle — the toggle is a *transient operational remediation* that begins and ends in the declared state, so post-remediation `terraform plan` shows **no drift** (this is an AC).
- **Sentry-as-IaC:** the reissue-P0 issue-alert is declared in `infra/sentry/` (auto-applied by `apply-sentry-infra.yml` on push to `main`). Full-root plan since #6589 — declaring the resource applies it; verify no unintended destroy.
- Providers: existing `cloudflare` + `sentry` providers; no new provider. CF token + zone id come from Doppler `prd_terraform` (`TF_VAR_cf_api_token*`, `cf_zone_id`) — the same creds the runtime reads for the imperative toggle.

### Apply path
- (b) **cloud-init + no bootstrap needed** for code: the Inngest function ships in the `apps/web-platform/**` container image; a merge to `main` restarts the container via `web-platform-release.yml`, syncing the new function — no separate operator restart (automation-feasibility gate). The Sentry alert applies via `apply-sentry-infra.yml`.
- **Blast radius:** the transient DNS-only window drops CF proxy protection (WAF/DDoS + origin-IP hiding) on apex+www for the provisioning window (~5–15 min). Acceptable because (i) the still-valid cert keeps traffic working, (ii) the window is bounded, (iii) the `finally` restore + exit-assert guarantees return to `proxied=true`. Documented as a Sharp Edge.

### Distinctness / drift safeguards
- **Race with `apply-web-platform-infra.yml`:** that workflow auto-applies on any `infra/*.tf` merge and would flip apex+www back to `proxied=true` mid-window. Mitigation: the reissue routine holds the DNS-only window only briefly and re-proxies in `finally`; it must NOT run concurrently with an infra apply. Deepen-plan to decide whether a lightweight lease/guard is warranted (likely not — window is short, infra applies are merge-gated, not continuous).
- **CF SSL mode:** `/work` Phase 0 confirms the zone SSL mode (Full vs Full-Strict); irrelevant during the DNS-only window (traffic bypasses CF) but relevant to the 526 clock — documented, not changed.

### Vendor-tier reality check
- No new paid Sentry seat if the P0 reuses the existing paging surface; confirm against the free-tier monitor count noted in the 2026-05-18 poll plan (the poll monitor was the 9th). Reissue paging should be an *issue-alert on an existing project*, not a new monitor/uptime resource, to avoid tier pressure.

## Observability

```yaml
liveness_signal:
  what: reissue routine emits a Sentry breadcrumb per phase (preflight/dns-only/put-cname/poll/restore) + a terminal outcome event; the daily poll cron's existing Sentry heartbeat (slug scheduled-gh-pages-cert-state) remains the state liveness beat
  cadence: on-invocation (event-triggered) for reissue; daily 03:00 UTC for the poll heartbeat
  alert_target: Sentry (org jikigai-eu) issue-alert on the reissue-P0 op-slug; existing cron-monitor for the poll heartbeat
  configured_in: apps/web-platform/infra/sentry/*.tf (declared) + reportSilentFallback/mirrorP0Deduped emit sites in the reissue handler
error_reporting:
  destination: Sentry via reportSilentFallback (recoverable) / mirrorP0Deduped (P0 exhausted-remediation) — cq-silent-fallback-must-mirror-to-sentry
  fail_loud: true (a swallowed remediation failure is forbidden; the catch mirrors to Sentry AND the issue-handling fallback still fires)
failure_modes:
  - mode: reissue reaches poll cap without state in {approved, issued}
    detection: terminal Sentry event op=gh-pages-cert-reissue outcome=poll_timeout with {finalState, attempts, elapsedMs}
    alert_route: Sentry issue-alert -> founder; + action-required issue appended with attempt log
  - mode: LE rate-limit suspected (reissue no-ops due to cooldown/cap)
    detection: Sentry event outcome=rate_limit_cooldown with {lastAttemptAt, attemptsThisWeek}
    alert_route: Sentry (warn); no issue spam (cooldown is expected backoff)
  - mode: CF proxy toggle failed to restore (proxied still false at exit)
    detection: exit-assert throws -> mirrorP0Deduped outcome=proxy_restore_failed with {records, proxiedState}
    alert_route: Sentry P0 -> founder (security regression, origin IPs exposed) — highest severity
  - mode: precondition unfixable (CAA appeared / TXT missing / carve-out regressed)
    detection: Sentry event outcome=precondition_blocked with {failedPrecondition}
    alert_route: action-required issue naming the specific blocker
logs:
  where: Better Stack Logs source 2457081 (Inngest node Vector ship) + Sentry breadcrumbs
  retention: per existing Better Stack + Sentry retention
discoverability_test:
  command: "gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'  AND Sentry issue search op:gh-pages-cert-reissue"
  expected_output: "issued (post-remediation); Sentry shows the terminal outcome event with discriminating fields — NO ssh required"
```

**Affected-surface probe (§2.9.2 — cron worker is a blind surface):** every reissue outcome emits ONE structured Sentry event whose fields (`outcome ∈ {issued, poll_timeout, rate_limit_cooldown, proxy_restore_failed, precondition_blocked}`, `finalState`, `attempts`, `elapsedMs`, `proxiedStateAtExit`, `preconditionResults`) **discriminate all competing failure hypotheses in one event** — so the root cause of any future recurrence is decided the moment it fires, not after N blind fixes.

## Architecture Decision (ADR / C4)

This introduces a **new autonomous-infra-remediation pattern**: an Inngest cron that mutates **live Cloudflare DNS proxy state + GitHub Pages cert configuration** to self-heal a vendor-managed TLS failure. This extends the cron substrate (ADR-033) with a write-to-live-infra capability it did not previously have.

### ADR
- **Create ADR-`<next>`** (provisional ordinal — `/ship` re-verifies against `origin/main`; sweep `plans`+`specs`+ACs on any renumber): *"Autonomous GitHub Pages cert remediation: cron-driven transient CF-proxy toggle + App-token cert reissue."* Decision: a bounded, capped, `finally`-safe remediation routine may transiently flip apex+www CF proxy to DNS-only and re-order the LE cert via the App's `Administration: write` grant, returning to the TF-declared steady state; self-heal is cooldown-gated to respect LE rate-limits; operator handoff only on exhaustion. `## Alternatives Considered`: (a) leave manual per #3976 (rejected — non-technical operators), (b) DNS-only reissue **without** proxy toggle (rejected — H1 predicts re-fail while proxied), (c) persist `proxied=false` in TF (rejected — drops CF protection permanently).

### C4 views
Reviewed all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration for this change:
- **External human actors:** none new (the actor is the automated cron).
- **External systems:** `cloudflare` (system, `model.c4:234`) and `github` (system) are **already modeled**; GitHub Pages is not a distinct element. New **relationships**: `inngest`/`api` → `cloudflare` (DNS-record proxy toggle) and the existing `api → github` edge (`model.c4:396`) gains a Pages-cert-admin capability.
- **Containers/data stores:** none new.
- **Access-relationship changes:** the cron gains **write** access to CF DNS proxy state (previously read-only vendor interactions from this surface).

**C4 task (in-scope):** add/annotate the `inngest -> cloudflare` (DNS proxy toggle for cert remediation) edge and extend the `api -> github` edge description to include Pages cert reissue, plus the `view … include` line if the edge is not already rendered. Run `c4-code-syntax.test.ts` + `c4-render.test.ts` after editing. (Not "no C4 impact" — a new write relationship to Cloudflare is added.)

### Sequencing
The decision is true on merge (no soak gate). ADR authored now at `status: accepted`.

## User-Brand Impact

**If this lands broken, the user experiences:** if the remediation fails to restore `proxied=true`, `soleur.ai`/`www` briefly serve direct from GitHub Pages with CF WAF/DDoS + origin-IP hiding removed (security regression); if it fails to reissue, the cert hard-expires 2026-08-16 and the **public marketing site returns Cloudflare 526** to every visitor (the exact 2026-05-18 outage). If the self-heal loops without a cap, it can exhaust Let's Encrypt's rate-limit budget and *delay* recovery by up to a week.
**If this leaks, the user's data / workflow / money is exposed via:** N/A — no user PII or regulated data on this surface; the exposure vector is infra (origin IP + dropped edge protections during a mis-restored window), mitigated by the `finally` restore + exit-assert.
**Brand-survival threshold:** `aggregate pattern` — a site-wide public-brand TLS outage affecting all visitors (not a single-user data incident). No CPO sign-off required; `user-impact-reviewer` runs at review-time per the threshold.

## Domain Review

**Domains relevant:** Operations (COO), Engineering (CTO). Product: NONE.

### Operations (COO)
**Status:** assessed (inline — infra/vendor lens). **Assessment:** A hosting/vendor-TLS reliability fix squarely in Operations' remit (GitHub Pages + Cloudflare + Let's Encrypt). Concerns folded into the plan: (i) no recurring manual operator step (fully scripted), (ii) LE rate-limit budget respected via cooldown/cap, (iii) no new recurring vendor expense (reuses existing Sentry/CF/GitHub App), (iv) the transient CF-protection drop is bounded and auto-restored. Recommend the reissue-P0 pages the founder only on *exhaustion*, not on routine cooldown backoff.

### Engineering (CTO)
**Status:** assessed (inline). **Assessment:** Extends ADR-033 cron substrate with a live-infra write capability — ADR-worthy (above). Concerns: Inngest `step.run` memoization (side-effecting toggle + reissue must be structured so replay is safe — CF toggle and PUTs in `step.run`, poll in `step.sleep`; do NOT split write-then-verify across steps such that replay skips the write, per learning `2026-06-14`); scoped least-privilege token (`administration:write` + `repositories:["soleur"]`); manifest-vs-installation grant verified in Phase 0 (#4173 class).

### Product/UX Gate
Skipped — **NONE**. No files under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`; no user-facing surface. The mechanical UI-surface override did not fire.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 — Reissue routine exists + registered.** `cron-gh-pages-cert-reissue.ts` exports `cronGhPagesCertReissue`; registered in the functions index; `id: "cron-gh-pages-cert-reissue"`; event trigger `cron/gh-pages-cert-reissue.manual-trigger`; no `cron:` schedule; fn+account concurrency=1; `retries: 1`.
- **AC2 — Manifest + allowlist parity.** `"cron-gh-pages-cert-reissue"` ∈ `EXPECTED_CRON_FUNCTIONS`; `function-registry-count.test.ts` and Inngest inventory expectations updated to the new count; `isAllowlistedManualTrigger("cron/gh-pages-cert-reissue.manual-trigger")` returns true (derived, not a second hardcoded list).
- **AC3 — `finally` proxy-restore is unconditional.** Unit test proves that when `reissueViaCnameToggle` throws mid-window, `setApexProxied(true)` still runs and the exit-assert confirms `proxied=true` for all apex A-records + www (the security-regression brake).
- **AC4 — Least-privilege token.** The reissue mints `generateInstallationToken({ permissions: { administration: "write" }, repositories: ["soleur"] })`; unit/source anchor asserts the scoped mint (not an unscoped full-installation token).
- **AC5 — Poll bounded + rate-limit-aware.** Poll cap and per-invocation single-attempt + cooldown constants exist and are asserted; a unit test proves a second invocation within the cooldown no-ops with `outcome=rate_limit_cooldown` (does NOT hit the GitHub/CF APIs).
- **AC6 — State-tripped self-heal gate (not expiry).** The poll cron auto-invokes reissue only when `state ∉ {approved, issued}` (i.e., `bad_authz`/`failed`) AND preconditions healthy AND cooldown elapsed; a unit test proves an *expiry-only* warning (`state=issued`, `days<21`) does NOT auto-reissue.
- **AC7 — Observability event discriminates outcomes.** Every terminal path emits exactly one structured Sentry event with `outcome`, `finalState`, `attempts`, `elapsedMs`, `proxiedStateAtExit`, `preconditionResults`; source/unit test asserts each `outcome` enum arm is reachable and mirrored (`reportSilentFallback`/`mirrorP0Deduped`).
- **AC8 — No persisted TF drift from the toggle.** `dns.tf` still declares `proxied=true` for apex+www; a source assertion confirms the routine does NOT write `.tf` (imperative CF-API only). Post-remediation `terraform plan` (Phase 0 dry probe or documented) shows no proxy diff.
- **AC9 — ADR + C4 shipped.** ADR-`<n>` file exists with Decision + Alternatives; `model.c4`/`views.c4` updated for the new `inngest→cloudflare` proxy-toggle edge + extended `api→github` cert-admin description; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC10 — Typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/server/inngest/cron-gh-pages-cert-reissue.test.ts test/server/inngest/cron-gh-pages-cert-state.test.ts` green.
- **AC11 — Read-only preconditions verified live in Phase 0.** Phase 0 output pins: live `state=bad_authz`; App installation grant includes `administration:write` (scoped-token mint succeeds OR `X-Accepted-GitHub-Permissions` on a dry request confirms); CF token can list/patch the apex records (dry read). If the App grant is missing, the manifest-change split (Files to Edit conditional) activates.
- **AC12 — PR body uses `Ref #6657`, not `Closes`.** Per the ops-remediation class (`Closes` would false-resolve at merge, before the live reissue runs). Issue #6657 is closed by the poll cron's next healthy read after the live remediation, or by a post-merge `gh issue close` step.

### Post-merge (operator) — automated, no console
- **PM1 — Fire the live reissue for #6657.** Via `POST /api/internal/trigger-cron` with `cron/gh-pages-cert-reissue.manual-trigger` (scripted; HMAC secret read-only from Doppler; the `trigger-cron` skill path — no SSH, no dashboard). `Automation: feasible` (existing allowlisted endpoint; App token has the grant; CF token available). **Not an operator console step.**
- **PM2 — Verify recovery (self-verifying).** `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` progresses `bad_authz → approved/issued` within ~15 min; `curl -sSI https://soleur.ai/` and `https://www.soleur.ai/` return `HTTP/2 200`; the daily poll cron auto-closes #6657 on its next healthy read. All API-verifiable — no dashboard eyeball (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **PM3 — Confirm no CF drift.** `terraform plan` (prd_terraform triplet) shows apex+www at `proxied=true` (no diff) after remediation.

## Test Scenarios

1. Preconditions healthy + `bad_authz` → DNS-only → cname toggle → poll returns `issued` → restore proxy → `outcome=issued`. (happy path)
2. `reissueViaCnameToggle` throws after DNS-only set → `finally` restores `proxied=true`, exit-assert passes, `outcome` reflects failure + P0. (AC3)
3. Poll never reaches `issued` within cap → restore proxy → `outcome=poll_timeout` + action-required issue with attempt log. (H1+H2 falsified path)
4. Second invocation within cooldown → immediate no-op, `outcome=rate_limit_cooldown`, zero GitHub/CF calls. (H3 / AC5)
5. Precondition broken (simulated CAA present / TXT missing) → skip remediation, `outcome=precondition_blocked`, issue names the blocker. (AC7)
6. Expiry-only warning (`state=issued`, `days=10`) → poll cron warns, does NOT auto-reissue. (AC6)
7. Proxy-restore fails at exit → `mirrorP0Deduped` P0 `proxy_restore_failed`. (highest-severity brake)

## Sharp Edges

- **A `## User-Brand Impact` that is empty/TBD fails `deepen-plan` Phase 4.6.** (Filled above; threshold `aggregate pattern`.)
- **Do NOT re-fix the May-2026 cause.** The ACME redirect interception (H4) and CAA (H5) are REFUTED by live probe — the carve-out + `always_use_https=off` are intact. A plan that "hardens the carve-out" is fixing the wrong layer.
- **cname-toggle WHILE proxied likely re-fails.** The DNS-only window (H1) is load-bearing; do not ship a reissue that skips it on the theory that "start over" alone suffices.
- **`finally` restore is non-negotiable.** Any early return / throw between DNS-only-set and proxy-restore must still restore `proxied=true` — leaving origin IPs exposed is a worse regression than the cert outage.
- **Inngest `step.run` memoizes return values, not side effects** — the CF toggle + PUTs must not be split across steps such that a replay skips the write (learning `2026-06-14`). The poll must use `step.sleep`, not a busy loop.
- **LE rate-limit budget** (5 failed-validations/hr, 50 dup-certs/domain/week): the routine is single-attempt-per-invocation + cooldown-gated. A tight auto-retry loop would *delay* recovery by up to a week.
- **Race with `apply-web-platform-infra.yml`** flipping proxy back mid-window: window is short + merge-gated; deepen-plan to confirm no lease needed.
- **Manifest ≠ installation grant (#4173).** Phase 0 must verify the *live* `administration:write` grant, not just the manifest declaration; if missing, activate the manifest-change + founder-re-acceptance split (the only conceivable operator gate, and a one-time authorization acceptance, not a recurring console step).
- **`gh api` array/object params:** use `--input -` heredoc, never `--field` (learning `2026-04-10`); re-read `GET /pages` after each `PUT` (PATCH-silent-success).
- **Test paths must match `vitest.config.ts` `include` (`test/**/*.test.ts`)** — a co-located `functions/*.test.ts` is never run.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Leave #3976's `PM5` manual (operator uncheck/recheck) | Rejected | Non-technical operators; violates `hr-exhaust-all-automated-options-before` + the never-defer feedback. The claim it *must* be manual is refuted. |
| DNS-only reissue without the proxy toggle (cname toggle only) | Rejected as sole path | H1 predicts re-fail while proxied; postmortem shows the domain-config check needs GitHub's IPs visible. Kept as an internal fast-path only if a future probe shows proxying is not the blocker. |
| Persist `proxied=false` in `dns.tf` | Rejected | Permanently drops CF WAF/DDoS + origin-IP hiding — a standing security regression. Toggle must be transient. |
| A GitHub Actions workflow (mint App JWT in CI, run the script) | Rejected as primary | Duplicates the App-token minting already available in the Inngest runtime; the Inngest function + `trigger-cron` gives a console-free scripted path with better observability. Kept as a fallback consideration for deepen-plan. |
| Full self-heal enabled on first merge with no cooldown | Deferred to deepen-plan | Risk of LE rate-limit burn; recommend cooldown-gated + validate-via-manual-trigger-first (mirrors the 2026-05-18 poll plan's dispatch-first caution). |

## Open Code-Review Overlap

None — checked open `code-review`-labelled issues against the planned file set (new `cron-gh-pages-cert-reissue.*`, `cron-manifest.ts`, `routine-metadata.ts`, `cron-gh-pages-cert-state.ts`, `dns.tf` (read-only), `infra/sentry/*`); no open scope-out touches these paths. (Re-run the `gh issue list --label code-review` grep at deepen-plan if the file set changes.)
