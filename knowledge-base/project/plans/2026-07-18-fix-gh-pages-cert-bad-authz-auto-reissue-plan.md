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

## Enhancement Summary

**Deepened on:** 2026-07-18. **Hard gates:** 4.6 User-Brand Impact ✓ (`aggregate pattern`), 4.7 Observability ✓ (5/5 fields, no-ssh), 4.8 PAT-shaped ✓ (none), 4.9 UI-wireframe ✓ (no UI surface). **Live verifications:** #3974/#3986 MERGED; #3976 CLOSED issue; ADR next ordinal on fresh `origin/main` = **ADR-125** (provisional); 50 Inngest cron functions confirm ADR-033 Inngest path is canonical (not GH Actions).

### Key deepen findings folded in (incl. 2-agent plan review — architecture-strategist + code-simplicity)
1. **[BLOCKING → redesigned] `finally` restore is NOT Inngest-replay-safe.** A JS `try…finally` cannot span step boundaries: `step.sleep` suspends via a control-flow throw that runs `finally` **prematurely** (restoring the proxy on the first poll pass, before the cert validates), then the resumed run finds the toggle-off `step.run` memoized/skipped → the DNS-only window never re-opens → silent timeout. **Redesign:** toggle+reissue in step 1 → `step.sleep` poll loop → an **unconditional final restore step** → **plus an `onFailure` lifecycle handler** that idempotently restores state on throw/exhaustion (the body's final step does NOT run on throw). Cite **ADR-077** (routine replay-safety contract). AC3 now asserts restore via the step/`onFailure` path, not a JS `finally` (a naive finally test gives false confidence).
2. **[BLOCKING → fixed] Restore must be symmetric — cname AND proxy.** The forward path is `PUT cname:null` → re-set. If the routine throws *between* the two PUTs, restoring only `proxied=true` leaves the **custom domain unset** (site drops to `*.github.io`, CF origin 526s) — a *worse* outage. The restore captures the pre-existing `{cname, proxied}` and restores BOTH.
3. **[scope cut] v1 = manual-trigger reissue ONLY; self-heal auto-invoke DEFERRED behind a default-OFF Flagsmith flag (ADR-038).** Both reviewers converged: auto-firing an unproven remediation from a 03:00 cron (drops CF WAF/DDoS 5–15 min, burns scarce LE budget, mutates live infra) is over-reach, AND the cooldown apparatus needed a **cross-invocation persistence store the plan never specified** (Inngest is stateless). Deferring removes that hole. v1 satisfies "scripted/CI-driven, no console" via the manual trigger alone. Follow-up issue tracks flag-gated self-heal.
4. **[gap] The real racer is the `cron-terraform-drift` detector, not just the merge-apply.** During the DNS-only window live≠declared (`proxied=false` vs `=true`) → the drift detector pages / opens a corrective apply. Adopt the **ADR-089 freeze-lock**; `cron-terraform-drift` + `apply-web-platform-infra.yml` honor it for the `github_pages`/`www` records while held.
5. **[framing] AP-001 exception, not compliance-by-no-drift.** "no `.tf` change ⇒ `terraform plan` clean" conflates drift-absence-at-rest with provisioning-path compliance; a runtime process `PATCH`-ing live CF DNS IS the off-Terraform live mutation AP-001/ADR-019 govern. ADR-125 must register an **explicit narrow exception (new AP-019 row)** — transient, self-reverting, lock-guarded — not claim compliance.
6. **CF DNS-edit token scope is load-bearing.** `cf-cache-purge.ts`'s `CF_API_TOKEN_PURGE` is cache-purge-scoped and CANNOT edit `proxied`. Phase 0 verifies a DNS:edit token in the runtime; if absent, provision a scoped `cloudflare_api_token` + `doppler_secret` (IaC). HTTP-client precedent = `cf-cache-purge.ts` (Bearer + `AbortController` timeout + `reportSilentFallback`); keep helpers in the one function file (no speculative client module).
7. **Zero-downtime confirmed** (`## Downtime & Cutover`); ADR ordinal **ADR-125** (provisional, fresh `origin/main`); Outcome enum gains a `reissue_failed`/partial-toggle-abort arm.

> **IaC-routing note (Phase 2.8 reviewed):** this plan's entire purpose is to REPLACE the #3976 manual GitHub-Pages-console step with a fully scripted, IaC-routed remediation. Any vendor-console wording below is either a *quoted/refuted* reference to the old runbook or the single genuine vendor-authorization gate (App-manifest permission re-acceptance) that `apps/web-platform/infra/github-app.tf` already documents as an unavoidable GitHub web-authorization limit. See `## Infrastructure (IaC)`.

> **⚠️ SUPERSEDED IN PLACES (CTO ruling + multi-agent review, 2026-07-18) — authoritative sources are ADR-125, `session-state.md`, and the shipped code.** Two plan-body claims below were corrected during implementation:
> 1. **The ADR-089 "freeze-lock" (Finding #4, Solution step 0, `## Distinctness`, AC8b) is DESCOPED to v2 (#6677).** ADR-089 has no runtime implementation (it is an edit-time PreToolUse path-prefix guard, unreadable from the Inngest/GHA runtimes). v1 ships lock-free with a documented residual-race Sharp Edge + the P0 backstop. All "acquire/honor the ADR-089 freeze-lock" lines are v2 work, not v1.
> 2. **Observability uses `reportSilentFallback` (feature tag), not `mirrorP0Deduped`, and events are queried by `feature=cron-gh-pages-cert-reissue` — NOT `op=gh-pages-cert-reissue`** (no event carries that `op`). `mirrorP0Deduped` is GDPR-Art-33-breach-specific (userId/conversationId dedup keys) and does not fit a cron pager. Wherever this plan says `mirrorP0Deduped` or `op=gh-pages-cert-reissue`, read `reportSilentFallback` / `feature=cron-gh-pages-cert-reissue`.
> 3. **The mutating apply racer CAN revert the records** — `cloudflare_record.github_pages`/`.www` ARE in the `apply-web-platform-infra.yml` `-target` list (`:343-345`); the mitigation is fail-closed→P0→re-fire + avoiding infra merges during the window, not allowlist exclusion (see ADR-125 Consequences).

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

**Working conclusion (to falsify, not assume):** the remediation must (a) perform the "start over" cname re-add (H2) **while** (b) presenting GitHub/LE a DNS-only apex+www so the origin-IP/HTTP-01 validation can complete (H1), (c) as a single bounded attempt per invocation (v1 is human-gated, so no auto-loop can burn the LE rate-limit budget — H3). If, after a DNS-only reissue, the state does NOT progress past `bad_authz`, H1+H2 are falsified for this incident and the routine escalates to an `action-required` issue with the full attempt log (never a silent loop).

## Research Reconciliation — claim vs. codebase reality

| Claim (from #3976 runbook / #6657) | Reality (verified this session) | Plan response |
|---|---|---|
| "GH Pages Settings UI is not API-equivalent for cert-reissue trigger" (#3976 `manual_because`) | The **trigger** IS API-reproducible: `PUT /pages` `cname:null` → re-set `cname:"soleur.ai"` (GitHub docs; the console remove/re-add gesture). Needs `Administration: write`, which the App **has**. | Build the reissue as an App-token API sequence. Retire the "manual" framing for the trigger. |
| "cert-reissue automation … requires `pages: write` AND a PAT, NOT the workflow's `GITHUB_TOKEN`" (2026-05-18 poll plan Non-Goal) | That was about a **GHA `GITHUB_TOKEN`**. This runtime uses an **App installation token** with `Administration: write` already granted — a different, sufficient credential. `PUT /pages` is `administration`; `DELETE /pages/builds` is unnecessary (it rebuilds the site, does not reissue the cert). | Use `generateInstallationToken({ permissions: { administration: "write" }, repositories: ["soleur"] })`. **Phase 0 verifies the live grant** (manifest ≠ installation grant, the #4173 class). |
| Runbook `PM5`: "`gh api -X DELETE /repos/.../pages/builds` to re-trigger" | `DELETE /pages/builds` re-runs the **site build**, it does **not** re-order the cert. | Do not use it for reissue. |
| Issue label `infra-drift` implies Terraform drift | The cron statically applies `["action-required","infra-drift"]` to **every** trip (`cron-gh-pages-cert-state.ts` issue-handling). No Terraform drift is implied. | Note only; not a signal. |

## Solution — staged, empirical, self-healing

A new bounded remediation routine (`reissueGhPagesCert`) that runs the **postmortem-proven** recovery order (see learning `2026-02-16-github-pages-cloudflare-wiring-workflow.md`: DNS-only → set custom domain → poll → re-proxy):

**Inngest-replay-safe step structure (ADR-077 — the `finally` design was rejected at review; see Sharp Edges):**

0. **Acquire the ADR-089 freeze-lock** on the `github_pages`/`www` DNS records (so `cron-terraform-drift` + `apply-web-platform-infra.yml` defer while the window is open). Released in the final restore step + `onFailure`.
1. **Pre-flight (read-only, fail-loud) + stuck-state allowlist gate:** re-read `GET /pages`. **Abort early unless `state ∈ {bad_authz, failed}`** — never touch a cert that is `issued`/`approved` or mid-renewal (`new`/`authorization_pending`/`dns_changed`/… — a cname-toggle on a healthy in-flight order can *manufacture* a new `bad_authz`). Then verify auto-fixable preconditions healthy (ACME path `404` on apex+www; `always_use_https="off"`; CAA empty/permissive; `_github-pages-challenge` TXT present). Capture the **pre-existing `{cname, proxied}`** for symmetric restore. If a precondition it can't fix is broken (CAA appears, TXT missing), skip with `outcome=precondition_blocked`.
2. **Step 1 (single `step.run`): DNS-only + start-over.** Via the **Cloudflare API** (DNS:edit token — see §Files), set the 4 apex A-records + www CNAME to `proxied=false`; **abort→restore if the toggle is partial** (any record fails); then `PUT /pages cname:null` → wait ~30–60s → `PUT /pages cname:"soleur.ai"`. Re-read after each PUT (PATCH-silent-success, learning `2026-04-10`). A 4xx/403 here → `outcome=reissue_failed`, fall through to restore. All in ONE step so a retry of this step is the *only* thing that re-orders the cert (bounded by `retries:1`).
3. **`step.sleep` poll loop (bounded):** `GET /pages` every ~60s up to ~15 min for `state ∈ {approved, issued}`. `step.sleep` is the ONLY suspension point — nothing side-effecting lives in a `try` that spans it.
4. **Final restore step (unconditional, idempotent):** restore the captured `{cname, proxied}` on apex+www; assert live state matches; release the lock. **Idempotent** so it is safe to also run from `onFailure`.
5. **`onFailure` lifecycle handler:** on any throw/retry-exhaustion, run the SAME idempotent restore (captured `{cname, proxied}`) + lock release — because the body's final step does NOT run on a throw. This is the real security-regression brake (a JS `finally` is not — it fires prematurely at the first `step.sleep`).
6. **Verdict + observability:** on `issued` → success (breadcrumb + the poll cron auto-closes #6657 on its next healthy read). On timeout/`reissue_failed`/`proxy_restore_failed`/`precondition_blocked` → structured Sentry P0 + append the `action-required` issue with the attempt log. Single reissue attempt per invocation (`retries:1`); the manual trigger is human-gated so no cross-invocation cooldown store is needed in v1.

**v1 invocation = manual trigger only (console-free); self-heal auto-invoke DEFERRED (flag-gated follow-up):**
- **Scripted/CI trigger (v1):** a new manual-trigger event `cron/gh-pages-cert-reissue.manual-trigger`, auto-allowlisted via `EXPECTED_CRON_FUNCTIONS`, fired through the existing `POST /api/internal/trigger-cron` (HMAC, no SSH, no dashboard — precedent `admin-ip-refresh`). This remediates #6657 in-session and validates the routine end-to-end against the live incident (safe given the 28-day runway).
- **Self-heal auto-invoke (v2, DEFERRED):** having the daily poll cron auto-invoke reissue on a stuck state is the autonomous-recurrence capability. It is **out of scope for v1** and tracked by a follow-up issue: it needs (a) a **default-OFF Flagsmith runtime flag** (ADR-038) + kill-switch, (b) a **cross-invocation cooldown persistence store** (Inngest is stateless — the v1 plan deliberately avoids inventing one), and (c) the freeze-lock coordination proven under manual use first. The poll cron's issue-filing behavior is unchanged in v1 (its issue body now references the scripted trigger instead of a console step).

### Research Insights (deepen)

**Precedent-diff (Phase 4.4) — every pattern-bound behavior has a sibling to mirror, none is novel:**
- **Inngest function registration** → mirror `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts` (fn+account concurrency=1, `retries:1`, `step.run` per IO, `_cron-shared` token mint). No novel substrate.
- **Cloudflare HTTP client** → mirror `apps/web-platform/server/cf-cache-purge.ts`: `fetch(https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${id}, { method:"PATCH", headers:{Authorization:"Bearer "+token}, body: JSON.stringify({proxied:false}) })` with an `AbortController` timeout and `reportSilentFallback` on non-2xx/timeout/network. The record-list step is `GET /zones/{zone}/dns_records?type=A&name=soleur.ai` + the www CNAME. **Token-scope caveat above** (`CF_API_TOKEN_PURGE` is cache-only).
- **GitHub App scoped token** → mirror `generateInstallationToken` scoped-mint callers in `server/github-app.ts` (least-privilege `permissions` + `repositories:["soleur"]`).
- **Bounded poll** → `step.sleep` between reads (not a busy loop); `GET /pages` re-read; PATCH-silent-success re-verify per learning `2026-04-10`.

**Cloudflare DNS record PATCH shape (verify against pinned provider/API at /work):** the proxied flag is per-record; the apex is **4 A-records** (`for_each` in `dns.tf`) — the toggle must PATCH **all four** plus the www CNAME, and the exit-assert must confirm all five are back to `proxied=true` (a partial restore is a silent security hole). This is why AC3 asserts the full set, not a single record.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts` — the remediation Inngest function AND its pure helpers in **one file** (mirror `cron-gh-pages-cert-state.ts`, which keeps `checkCert` inline; YAGNI — no separate module/CF-client class). Registration: fn+account concurrency=1, `retries: 1`, **no `cron:` schedule** (event-triggered via `cron/gh-pages-cert-reissue.manual-trigger` + internal invoke), **`onFailure` handler** for idempotent restore + lock-release. Structure per ADR-077: toggle+reissue in one `step.run`, poll via `step.sleep`, unconditional final restore step. Pure injectable helpers (`assertStuckState`, `checkReissuePreconditions`, `setRecordsProxied(records,bool)`, `reissueViaCnameToggle`, `pollCertState`, `restoreState(captured)`) unit-test without live IO. The CF DNS PATCH helper mirrors `cf-cache-purge.ts` inline — do NOT build a standalone client (one consumer).
- `apps/web-platform/test/server/inngest/cron-gh-pages-cert-reissue.test.ts` — vitest unit tests (path under `test/**/*.test.ts` to match `vitest.config.ts` `include`). Mock Octokit + CF fetch; cover Test Scenarios 1–8, incl. **restore fires via the final step AND via `onFailure` on a simulated throw** (NOT a JS-`finally` assertion), symmetric `{cname,proxied}` restore, partial-toggle abort, and the stuck-state allowlist gate.

## Files to Edit

- `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-gh-pages-cert-reissue"` to `EXPECTED_CRON_FUNCTIONS` (auto-updates the manual-trigger allowlist + drift-guard count). Note: this changes the expected function-registry count — update `function-registry-count.test.ts` and any Inngest inventory expectation in the same PR.
- `apps/web-platform/server/inngest/routine-metadata.ts` — add the `cron-gh-pages-cert-reissue` metadata row (domain Engineering, ownerRole CTO, `scheduleLabel: "Event-triggered (reissue remediation)"`, `manualTrigger: "allowed"`).
- `apps/web-platform/server/inngest/functions/index.ts` (or wherever functions are registered/served) — register `cronGhPagesCertReissue`.
- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts` — **v1: text-only.** Update the auto-filed issue body to reference the scripted reissue trigger (`cron/gh-pages-cert-reissue.manual-trigger` via `trigger-cron`) instead of the #3976 console step. **Do NOT wire auto-invoke in v1** (deferred — see Solution). No logic change to the trip/expiry paths.
- **Drift-lock honor (ADR-089):** `cron-terraform-drift` + `apply-web-platform-infra.yml` (or their shared lock check) must skip/defer the `github_pages`/`www` proxied records while the reissue freeze-lock is held. Confirm the ADR-089 substrate exposes a check these consumers can honor; if the lock is record-scoped-new, add it.
- **(v2, deferred — follow-up issue, NOT this PR):** Flagsmith flag `gh_pages_cert_selfheal` (default OFF) + kill-switch; the poll-cron auto-invoke branch; the cooldown persistence store.
- `apps/web-platform/infra/uptime-alerts.tf` / `apps/web-platform/infra/sentry/*.tf` — declare a Sentry issue-alert (or reuse the existing paging path) for the reissue-P0 op-slug so an *exhausted/failed* remediation pages (no-SSH discoverability). Verify against the existing `soleur_acme_probe` regression alarm to avoid a duplicate.
- `knowledge-base/engineering/architecture/principles-register.md` — add the **AP-019** row (last is AP-018): the sanctioned transient runtime CF-DNS toggle exception to AP-001.
- `knowledge-base/engineering/architecture/decisions/ADR-125-*.md` + `model.c4` + `views.c4` — the ADR/C4 deliverables (Phase 5).
- **CF DNS-edit token (Phase 0 outcome).** The reissue routine's `proxied` toggle needs a **DNS:edit zone-scoped** Cloudflare token in the app/Inngest runtime env. `cf-cache-purge.ts`'s `CF_API_TOKEN_PURGE` is cache-purge-scoped and insufficient. Phase 0 checks whether the runtime already holds a DNS-edit token (e.g., `CLOUDFLARE_API_TOKEN`); if not, add a scoped `cloudflare_api_token` resource (DNS:edit on the zone) + a `doppler_secret` publishing it to `prd`, in `dns.tf` (or a new `cf-cert-reissue-token.tf`) — IaC-routed per `hr-tf-variable-no-operator-mint-default`, no manual mint. Distinct token so a leak is DNS-edit-only, not account-wide.
- (Conditional, Phase 0 outcome) `apps/web-platform/infra/github-app-manifest.json` — **only if** Phase 0 proves the live installation grant lacks `Administration: write` for `PUT /pages`. Adding a manifest permission requires founder re-acceptance via GitHub's web authorization flow (vendor-authorization gate, runbook Step 2.1, drift-guarded by `cron-github-app-drift-guard.ts`). **Expected NOT needed** (manifest already declares `administration: write`), but the split is pre-planned per the operator-mint-sequencing Sharp Edge.

## Infrastructure (IaC)

### Terraform changes
- **Steady state unchanged:** `dns.tf` keeps `cloudflare_record.github_pages` + `.www` at `proxied = true`; `cloudflare-settings.tf` keeps `always_use_https = "off"`. **No persisted `.tf` change** for the proxy toggle — the toggle is a *transient operational remediation* that begins and ends in the declared state, so post-remediation `terraform plan` shows **no drift** (this is an AC).
- **Sentry-as-IaC:** the reissue-P0 issue-alert is declared in `infra/sentry/` (auto-applied by `apply-sentry-infra.yml` on push to `main`). Full-root plan since #6589 — declaring the resource applies it; verify no unintended destroy.
- Providers: existing `cloudflare` + `sentry` providers; no new provider. CF token + zone id come from Doppler `prd_terraform` (`TF_VAR_cf_api_token*`, `cf_zone_id`) — the same creds the runtime reads for the imperative toggle.

### Apply path
- (b) **cloud-init + no bootstrap needed** for code: the Inngest function ships in the `apps/web-platform/**` container image; a merge to `main` restarts the container via `web-platform-release.yml`, syncing the new function — no separate operator restart (automation-feasibility gate). The Sentry alert applies via `apply-sentry-infra.yml`.
- **Blast radius:** the transient DNS-only window drops CF proxy protection (WAF/DDoS + origin-IP hiding) on apex+www for the provisioning window (~5–15 min). Acceptable because (i) the still-valid cert keeps traffic working, (ii) the window is bounded, (iii) the final restore step + `onFailure` handler (ADR-077) guarantee return to the captured `{cname, proxied}`. Documented as a Sharp Edge.

### Distinctness / drift safeguards
- **Two racers, both covered by the ADR-089 freeze-lock:** (1) `apply-web-platform-infra.yml` (auto-applies on `infra/*.tf` merge → would flip `proxied=true` mid-window, silently defeating H1); (2) — the confirmed gap from review — the recurring **`cron-terraform-drift`** detector, which sees live≠declared during the window and would **page and/or open a corrective apply**. The reissue **acquires the ADR-089 freeze-lock** on the `github_pages`/`www` records; both consumers honor it (defer apply / suppress drift-page while held). Released in the final step + `onFailure`.
- **This is a sanctioned AP-001 exception, not compliance-by-no-drift:** the runtime CF-DNS toggle is registered as **AP-019** in `principles-register.md` (transient, self-reverting, lock-guarded) so the drift detector and future reviewers see a carve-out rather than an unexplained bypass.
- **CF SSL mode:** `/work` Phase 0 confirms the zone SSL mode (Full vs Full-Strict); irrelevant during the DNS-only window (traffic bypasses CF) but relevant to the 526 clock — documented, not changed.

### Vendor-tier reality check
- No new paid Sentry seat if the P0 reuses the existing paging surface; confirm against the free-tier monitor count noted in the 2026-05-18 poll plan (the poll monitor was the 9th). Reissue paging should be an *issue-alert on an existing project*, not a new monitor/uptime resource, to avoid tier pressure.

## Downtime & Cutover

**Trigger check (Phase 4.55):** the remediation mutates the edge config of a serving surface (apex/www CF proxy). It is **NOT** an infra reboot/replace (no `hcloud_server` change), DB lock, or container swap — but the proxy toggle touches availability, so this section proves the zero-downtime path.

- **Offline-inducing operation:** none by design. Flipping apex+www to `proxied=false` (DNS-only) routes visitors **directly to GitHub Pages**, which still serves the **still-valid May cert (to 2026-08-16)** — so browsers get a valid TLS response throughout the window. Re-enabling `proxied=true` is a metadata flip with sub-minute propagation (`ttl=1`).
- **Zero-downtime path (default, chosen):** DNS-only → reissue → poll → re-proxy, executed while a valid cert is still live. No maintenance window, no visitor-facing TLS error. The final restore step + `onFailure` handler bound the window and guarantee return to the protected steady state.
- **Residual risk (bounded, not downtime):** during the DNS-only window CF WAF/DDoS + origin-IP hiding are absent (~5–15 min). This is a *protection* reduction, not an *availability* outage. Mitigated by the short window + P0 alarm if restore fails. If the cert had ALREADY expired (post-Aug-16), the DNS-only window would still be non-disruptive (direct GitHub hit) — but a Full-Strict CF origin fetch would already be 526ing, so remediating BEFORE expiry (the 28-day runway) is strictly better; this is why the plan remediates now, not at the deadline.

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
  - mode: reissue trigger failed (4xx/403 on either cname PUT, or partial apex toggle aborted)
    detection: Sentry event outcome=reissue_failed with {phase, httpStatus, recordsToggled}
    alert_route: Sentry issue-alert -> founder; restore step + onFailure still run
  - mode: restore failed to reassert captured {cname, proxied} (via final step OR onFailure)
    detection: restore-assert throws -> mirrorP0Deduped outcome=proxy_restore_failed with {records, cname, proxiedState}
    alert_route: Sentry P0 -> founder (security regression: origin IPs exposed AND/OR custom domain unset) — highest severity
  - mode: (v2, deferred) LE rate-limit / cooldown no-op — only exists once self-heal auto-invoke ships
    detection: Sentry event outcome=rate_limit_cooldown with {lastAttemptAt, attemptsThisWeek}
    alert_route: Sentry (warn); no issue spam
  - mode: precondition unfixable (CAA appeared / TXT missing / carve-out regressed)
    detection: Sentry event outcome=precondition_blocked with {failedPrecondition}
    alert_route: action-required issue naming the specific blocker
logs:
  where: Better Stack Logs source 2457081 (Inngest node Vector ship) + Sentry breadcrumbs
  retention: per existing Better Stack + Sentry retention
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://soleur.ai/
  expected_output: "200"
  # No-SSH liveness of the brand surface the cert protects (200 now on the valid
  # May cert; 526 if it hard-expires). The reissue routine's own outcome is
  # discovered via Sentry: search feature:cron-gh-pages-cert-reissue (needs auth,
  # so it is not the preflight-runnable probe); the cert state itself via
  # `gh api /repos/jikig-ai/soleur/pages --jq .https_certificate.state`.
```

**Affected-surface probe (§2.9.2 — cron worker is a blind surface):** every reissue outcome emits ONE structured Sentry event whose fields (`outcome ∈ {issued, poll_timeout, reissue_failed, proxy_restore_failed, precondition_blocked}` (+`rate_limit_cooldown` once v2 self-heal ships), `finalState`, `attempts`, `elapsedMs`, `phase`, `httpStatus`, `cnameAtExit`, `proxiedStateAtExit`, `preconditionResults`) **discriminate all competing failure hypotheses in one event** — including the API-failure and partial-toggle cases most likely in practice — so the root cause of any future recurrence is decided the moment it fires, not after N blind fixes.

## Architecture Decision (ADR / C4)

This introduces a **new autonomous-infra-remediation pattern**: an Inngest cron that mutates **live Cloudflare DNS proxy state + GitHub Pages cert configuration** to self-heal a vendor-managed TLS failure. This extends the cron substrate (ADR-033) with a write-to-live-infra capability it did not previously have.

### ADR
- **Create ADR-125** (provisional ordinal — derived from fresh `origin/main`, last = ADR-124; `/ship` re-verifies and sweeps `plans`+`specs`+ACs on any renumber): *"Event-triggered GitHub Pages cert remediation: replay-safe CF-proxy toggle + App-token cert reissue, as a narrow AP-001 exception."* Decision: a bounded remediation routine may transiently flip apex+www CF proxy to DNS-only and re-order the LE cert via the App's `Administration: write` grant, restoring the captured `{cname, proxied}` steady state via an **unconditional final step + `onFailure` handler** (NOT a JS `finally` — replay-unsafe). It **references ADR-077** (routine replay-safety contract) as the governing structure and **ADR-089** (freeze-lock) for drift-detector/apply coordination. v1 is manual-trigger only; self-heal auto-invoke is a deferred, Flagsmith-gated (ADR-038, default OFF) follow-up.
  - **`## Decision` must frame this as an explicit narrow exception to AP-001 / ADR-019, NOT "compliant because no `.tf` drift".** A runtime process `PATCH`-ing live Cloudflare DNS IS the off-Terraform live-infra mutation AP-001 governs; the self-revert mitigates *drift*, not the *provisioning path*. Register a **new AP-019 row** in `principles-register.md` (last row is AP-018): "transient, self-reverting, lock-guarded runtime CF-DNS toggle for GH-Pages cert renewal — sanctioned exception, so `cron-terraform-drift` and future reviewers see a carve-out."
  - `## Alternatives Considered`: (a) leave manual per #3976 (rejected — non-technical operators), (b) DNS-only reissue **without** proxy toggle (rejected — H1 predicts re-fail while proxied), (c) persist `proxied=false` in TF (rejected — standing security regression), (d) `-target`ed TF apply for the toggle instead of CF API (rejected — fights the same drift/apply race, slower), (e) JS `finally` restore (rejected — fires prematurely at the first `step.sleep`, ADR-077).

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
**If this leaks, the user's data / workflow / money is exposed via:** N/A — no user PII or regulated data on this surface; the exposure vector is infra (origin IP + dropped edge protections during a mis-restored window), mitigated by the idempotent final restore step + `onFailure` handler.
**Brand-survival threshold:** `aggregate pattern` — a site-wide public-brand TLS outage affecting all visitors (not a single-user data incident). No CPO sign-off required; `user-impact-reviewer` runs at review-time per the threshold.

## Domain Review

**Domains relevant:** Operations (COO), Engineering (CTO). Product: NONE.

### Operations (COO)
**Status:** assessed (inline — infra/vendor lens). **Assessment:** A hosting/vendor-TLS reliability fix squarely in Operations' remit (GitHub Pages + Cloudflare + Let's Encrypt). Concerns folded into the plan: (i) no recurring manual operator step (fully scripted), (ii) v1 is single-attempt + human-gated so LE rate-limit budget is respected without an auto-loop (the cooldown store is a v2 concern), (iii) no new recurring vendor expense (reuses existing Sentry/CF/GitHub App), (iv) the transient CF-protection drop is bounded and auto-restored. Recommend the reissue-P0 pages the founder only on *exhaustion*.

### Engineering (CTO)
**Status:** reviewed (architecture-strategist, plan-review). **Assessment:** Extends ADR-033 with a live-infra write capability — ADR-worthy (above), framed as an AP-001 exception (AP-019). **Blocking finding resolved:** the `finally` restore is replay-unsafe (`step.sleep` runs it prematurely); redesigned to a final restore step + `onFailure` per ADR-077. **Race resolved:** ADR-089 freeze-lock covers both `apply-web-platform-infra` and the `cron-terraform-drift` detector. **Scope resolved:** self-heal auto-invoke deferred behind a default-OFF Flagsmith flag (ADR-038). Remaining: scoped least-privilege token (`administration:write` + `repositories:["soleur"]`); manifest-vs-installation grant + DNS:edit CF token verified in Phase 0.

### Product/UX Gate
Skipped — **NONE**. No files under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`; no user-facing surface. The mechanical UI-surface override did not fire.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 — Reissue routine exists + registered.** `cron-gh-pages-cert-reissue.ts` exports `cronGhPagesCertReissue`; registered in the functions index; `id: "cron-gh-pages-cert-reissue"`; event trigger `cron/gh-pages-cert-reissue.manual-trigger`; no `cron:` schedule; fn+account concurrency=1; `retries: 1`.
- **AC2 — Manifest + allowlist parity.** `"cron-gh-pages-cert-reissue"` ∈ `EXPECTED_CRON_FUNCTIONS`; `function-registry-count.test.ts` and Inngest inventory expectations updated to the new count; `isAllowlistedManualTrigger("cron/gh-pages-cert-reissue.manual-trigger")` returns true (derived, not a second hardcoded list).
- **AC3 — Replay-safe symmetric restore (via final step + `onFailure`, NOT `finally`).** Source anchors confirm: toggle+reissue live in ONE `step.run`; the poll uses `step.sleep`; restore is an unconditional final step AND an `onFailure` handler; there is **no JS `try…finally` spanning `step.sleep`**. A unit test drives a simulated throw and proves the `onFailure` restore reasserts the captured `{cname, proxied}` for **all 4 apex A-records + www** (both fields, not just `proxied`). `restoreState` is idempotent (safe to run from both paths).
- **AC4 — Least-privilege token.** The reissue mints `generateInstallationToken({ permissions: { administration: "write" }, repositories: ["soleur"] })`; unit/source anchor asserts the scoped mint (not an unscoped full-installation token).
- **AC5 — Single-attempt, no hidden state (v1).** Source asserts `retries:1` and **exactly one** reissue attempt per invocation; a unit/source check confirms v1 introduces **no cross-invocation cooldown store** (the human-gated manual trigger is the rate-limit boundary). The `rate_limit_cooldown` outcome + cooldown store belong to the deferred v2 self-heal follow-up, not this PR.
- **AC6 — Preflight stuck-state allowlist (abort otherwise).** A unit test proves the routine **aborts early with no CF/GitHub writes** unless live `state ∈ {bad_authz, failed}` — including the case `state=issued` (already healthy) and an in-flight intermediate (`authorization_pending`/`dns_changed`), which must NOT be toggled.
- **AC7 — Observability event discriminates outcomes.** Every terminal path emits exactly one structured Sentry event with `outcome`, `finalState`, `attempts`, `elapsedMs`, `proxiedStateAtExit`, `preconditionResults`; source/unit test asserts each `outcome` enum arm is reachable and mirrored (`reportSilentFallback`/`mirrorP0Deduped`).
- **AC8 — Toggle is CF-API only (no `.tf` write).** `dns.tf` still declares `proxied=true` for apex+www; a source assertion confirms the routine never writes `.tf`. (Post-remediation `terraform plan` no-drift is verified in PM3, not duplicated here.)
- **AC8b — Drift-lock honored.** Source/test confirms the reissue acquires the ADR-089 freeze-lock on the `github_pages`/`www` records and that `cron-terraform-drift` + `apply-web-platform-infra` consult it (no drift-page / no corrective apply on those records while held).
- **AC9 — ADR + C4 + AP-019 shipped.** ADR-125 file exists with `## Decision` framing the AP-001 **exception** (not compliance-by-no-drift) + `## Alternatives` incl. the rejected `finally`; a new **AP-019 row** exists in `principles-register.md`; `model.c4`/`views.c4` updated for the `inngest→cloudflare` DNS-toggle edge + extended `api→github` cert-admin description; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC10 — Typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/server/inngest/cron-gh-pages-cert-reissue.test.ts test/server/inngest/cron-gh-pages-cert-state.test.ts` green.
- **AC11 — Read-only preconditions verified live in Phase 0.** Phase 0 output pins: live `state=bad_authz`; App installation grant includes `administration:write` (scoped-token mint succeeds OR `X-Accepted-GitHub-Permissions` on a dry request confirms); CF token can list/patch the apex records (dry read). If the App grant is missing, the manifest-change split (Files to Edit conditional) activates.
- **AC12 — PR body uses `Ref #6657`, not `Closes`.** Per the ops-remediation class (`Closes` would false-resolve at merge, before the live reissue runs). Issue #6657 is closed by the poll cron's next healthy read after the live remediation, or by a post-merge `gh issue close` step.

### Post-merge (operator) — automated, no console
- **PM1 — Fire the live reissue for #6657.** Via `POST /api/internal/trigger-cron` with `cron/gh-pages-cert-reissue.manual-trigger` (scripted; HMAC secret read-only from Doppler; the `trigger-cron` skill path — no SSH, no dashboard). `Automation: feasible` (existing allowlisted endpoint; App token has the grant; CF token available). **Not an operator console step.**
- **PM2 — Verify recovery (self-verifying).** `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` progresses `bad_authz → approved/issued` within ~15 min; `curl -sSI https://soleur.ai/` and `https://www.soleur.ai/` return `HTTP/2 200`; the daily poll cron auto-closes #6657 on its next healthy read. All API-verifiable — no dashboard eyeball (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **PM3 — Confirm no CF drift.** `terraform plan` (prd_terraform triplet) shows apex+www at `proxied=true` (no diff) after remediation.

## Test Scenarios

1. Stuck (`bad_authz`) + preconditions healthy → DNS-only → cname toggle → poll returns `issued` → final restore step reasserts `{cname,proxied}` → `outcome=issued`. (happy path)
2. A throw occurs after DNS-only set (before/after the second PUT) → **`onFailure`** reasserts the captured `{cname, proxied}` (BOTH fields, all 5 records); assert restore ran via `onFailure` (not JS `finally`). (AC3, Finding 1)
3. Poll never reaches `issued` within cap → final restore step runs → `outcome=poll_timeout` + action-required issue with attempt log. (H1+H2 falsified path)
4. Live `state=issued` (already healthy) OR `state=authorization_pending` (in-flight) → preflight aborts with **zero CF/GitHub writes**. (AC6 stuck-state allowlist — prevents manufacturing a new `bad_authz`)
5. Precondition broken (simulated CAA present / TXT missing) → skip, `outcome=precondition_blocked`, issue names the blocker. (AC7)
6. Partial apex toggle (record 3 of 5 fails) OR 4xx/403 on a cname PUT → abort → restore captured state → `outcome=reissue_failed` with `{phase, httpStatus}`. (Observability enum)
7. Restore step/`onFailure` itself fails to reassert `{cname,proxied}` → `mirrorP0Deduped` P0 `proxy_restore_failed`. (highest-severity brake)
8. Freeze-lock held → a concurrent `cron-terraform-drift`/infra-apply on `github_pages`/`www` defers/suppresses. (AC8b)

## Sharp Edges

- **A `## User-Brand Impact` that is empty/TBD fails `deepen-plan` Phase 4.6.** (Filled above; threshold `aggregate pattern`.)
- **Do NOT re-fix the May-2026 cause.** The ACME redirect interception (H4) and CAA (H5) are REFUTED by live probe — the carve-out + `always_use_https=off` are intact. A plan that "hardens the carve-out" is fixing the wrong layer.
- **cname-toggle WHILE proxied likely re-fails.** The DNS-only window (H1) is load-bearing; do not ship a reissue that skips it on the theory that "start over" alone suffices.
- **A JS `try…finally` restore is WRONG for Inngest (review-confirmed, blocking).** `step.sleep` suspends via a control-flow throw that runs `finally` **prematurely** at the first poll — restoring the proxy before the cert validates, then the memoized toggle-off never re-runs → silent timeout. Restore MUST be an unconditional **final step** + an **`onFailure` handler** (idempotent), per ADR-077. There is no existing `onFailure` precedent in `functions/` — this is a new pattern; verify the SDK's `onFailure`/lifecycle signature against the pinned `inngest` version at /work.
- **Restore must be symmetric: `{cname, proxied}`, not just proxy.** A throw between `PUT cname:null` and the re-set leaves the custom domain unconfigured (worse than `bad_authz`). Capture the pre-existing pair and restore both; assert all 4 apex A-records + www.
- **Preflight stuck-state allowlist, not a denylist.** Gate on `state ∈ {bad_authz, failed}` — `state ∉ {approved, issued}` wrongly includes healthy in-flight orders (`authorization_pending`, `dns_changed`, …) and a toggle there can *manufacture* a new `bad_authz`.
- **LE rate-limit budget** (5 failed-validations/hr, 50 dup-certs/domain/week): v1 is single-attempt per human-gated invocation (no auto-loop). The v2 self-heal auto-invoke needs a real cooldown store (Inngest is stateless) — that's why it's deferred, not shipped with an unspecified store.
- **Drift-detector is a racer too (not just merge-apply).** `cron-terraform-drift` sees live≠declared during the window; hold the ADR-089 freeze-lock and have both it and `apply-web-platform-infra` honor it. Register the toggle as an AP-001 exception (AP-019), don't claim compliance-by-no-drift.
- **Manifest ≠ installation grant (#4173).** Phase 0 must verify the *live* `administration:write` grant, not just the manifest declaration; if missing, activate the manifest-change + founder-re-acceptance split (the only conceivable operator gate, and a one-time authorization acceptance, not a recurring console step).
- **`gh api` array/object params:** use `--input -` heredoc, never `--field` (learning `2026-04-10`); re-read `GET /pages` after each `PUT` (PATCH-silent-success).
- **Test paths must match `vitest.config.ts` `include` (`test/**/*.test.ts`)** — a co-located `functions/*.test.ts` is never run.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Leave #3976's `PM5` manual (operator uncheck/recheck) | Rejected | Non-technical operators; violates `hr-exhaust-all-automated-options-before` + the never-defer feedback. The claim it *must* be manual is refuted. |
| DNS-only reissue without the proxy toggle (cname toggle only) | Rejected as sole path | H1 predicts re-fail while proxied; postmortem shows the domain-config check needs GitHub's IPs visible. Kept as an internal fast-path only if a future probe shows proxying is not the blocker. |
| Persist `proxied=false` in `dns.tf` | Rejected | Permanently drops CF WAF/DDoS + origin-IP hiding — a standing security regression. Toggle must be transient. |
| A GitHub Actions workflow (mint App JWT in CI, run the script) | Rejected as primary | Duplicates the App-token minting already available in the Inngest runtime; the Inngest function + `trigger-cron` gives a console-free scripted path with better observability. |
| JS `try…finally` restore | **Rejected (review, blocking)** | Not replay-safe: `step.sleep` runs `finally` prematurely → proxy restored before validation → window collapses (ADR-077). Replaced by final step + `onFailure`. |
| Self-heal auto-invoke shipped in v1 | **Deferred to a flag-gated follow-up** | Over-reach (autonomous live-infra mutation from a 03:00 cron) + needs an unspecified cross-invocation cooldown store; both reviewers converged. v1 manual-trigger satisfies the requirement. Tracked by the deferral issue below. |

**Deferral tracking (`wg-when-deferring-a-capability-create-a`):** `/work` (or `/ship`) MUST file a follow-up issue for **v2 self-heal auto-invoke** — scope: default-OFF Flagsmith flag `gh_pages_cert_selfheal` (ADR-038) + kill-switch, cross-invocation cooldown persistence store (respect LE 5/hr·50/wk), poll-cron auto-invoke branch, freeze-lock coordination under autonomous timing. Re-evaluation criterion: after the manual path has succeeded ≥1× against a live incident. Milestone per `knowledge-base/product/roadmap.md`.

## Open Code-Review Overlap

None — checked open `code-review`-labelled issues against the planned file set (new `cron-gh-pages-cert-reissue.*`, `cron-manifest.ts`, `routine-metadata.ts`, `cron-gh-pages-cert-state.ts`, `dns.tf` (read-only), `infra/sentry/*`); no open scope-out touches these paths. (Re-run the `gh issue list --label code-review` grep at deepen-plan if the file set changes.)
