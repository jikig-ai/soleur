<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix: scheduled-ruleset-bypass-audit cron egress — full GitHub /meta CIDR coverage"
type: bug-fix
classification: ops-remediation
brand_survival_threshold: single-user incident
lane: cross-domain
requires_cpo_signoff: true
date: 2026-06-14
branch: feat-one-shot-scheduled-ruleset-bypass-audit-cron
sentry_monitor_slug: scheduled-ruleset-bypass-audit
sentry_monitor_id: 5ccb1e67-fb90-4863-97d3-f8fd23287b37
sentry_incident: 5516336
---

## Enhancement Summary

**Deepened on:** 2026-06-14
**Sections enhanced:** Hypotheses, Files to Edit, Apply path, Sharp Edges, Open Code-Review Overlap, Acceptance Criteria
**Research agents used:** Network-Outage Deep-Dive (Explore), Precedent-Diff/Apply-Path (Explore), Verify-Negative/Sibling (Explore)

### Key Improvements (verified, with citations)
1. **Apply path confirmed:** `.github/workflows/apply-web-platform-infra.yml` EXISTS (name "Apply web-platform infra …"), triggers on `push` to `main` with path filter `apps/web-platform/infra/**` (lines 64-75). `terraform_data.cron_egress_firewall` folds the CIDR file into `triggers_replace` (server.tf:729) and file-provisions it (server.tf:777-780). Auto-apply on merge is real.
2. **cloud-init needs NO separate edit (correction):** the CIDR file is templated into cloud-init via `cron_egress_allowlist_cidr_b64` (cloud-init.yml:211, server.tf:47) — editing `cron-egress-allowlist-cidr.txt` auto-refreshes both the file-provisioner AND the fresh-host cloud-init render. The earlier "mirror into cloud-init.yml" step is removed.
3. **nft overlap is a non-issue (correction):** the loader does an atomic `flush set` + `add element` (cron-egress-nftables.sh:118-128), so re-runs never hit "element already exists." The new Azure `/32`s (20.x / 4.x) sit in different `/8`s than the existing `/20`+`/22` blocks → no interval OVERLAP. Only an exact-duplicate line would matter; `sort -u` of the union handles it. Sharp Edge corrected.
4. **Strong existing verification artifact:** the post-apply remote-exec already probes container→`api.github.com` reachability AND a negative `https://example.com` drop (server.tf:838) — the apply FAILS if the firewall is inert or if an allowlisted host is unreachable. Cited in Phase 3/4.
5. **#5278 (OAuth probe) is a related-but-distinct symptom (correction):** cron-oauth-probe dials `github.com` (the OAuth authorize *page*, not `api.github.com`) PLUS app.soleur.ai/Supabase (cron-oauth-probe.ts:175,305-307). `github.com` is ALSO LB-rotated, so the full-`/meta` CIDR fix helps it — but it is NOT "another api.github.com-only cron." Claim softened; Phase 0 verifies #5278's actual blocked DST before asserting shared cause.

### New Considerations Discovered
- The Sentry heartbeat dials `SENTRY_INGEST_DOMAIN` (a *separate* dynamically-resolved allowlist host), and runs only AFTER the GitHub steps — confirming the alert is a *missed* (not *failed*) check-in, which is the firewall-drop signature, not an auth/error signature.
- Phase 0 must add explicit "NOT YET VERIFIED" markers for the DNS-pin and TLS layers (the L3-DNS and L7-TLS hypotheses are sound but currently logic-only, not artifact-backed).

---

# 🐛 fix: `scheduled-ruleset-bypass-audit` cron stopped checking in — incomplete GitHub egress CIDR coverage

## Overview

The `scheduled-ruleset-bypass-audit` Inngest cron (daily `13 6 * * *` UTC) reported a
**missed Sentry check-in** (monitor.incident 5516336). Last good check-in
`2026-06-13T06:13:02Z`; the `2026-06-14` 06:13 UTC fire never checked in (detected
2026-06-14 08:43 CEST = ~06:43 UTC, just past the monitor's 30-min margin).

**Root cause (evidence-grounded): the container egress firewall's GitHub CIDR
allowlist is incomplete.** This cron is *all-`api.github.com`* — every step
(`mint-installation-token` → `createProbeOctokit` + `generateInstallationToken`;
`audit-bypass-actors` → `@octokit/core`) dials `api.github.com`, and only after those
succeed does Step 3 POST the Sentry heartbeat. The egress firewall added in #5089
default-drops all container egress not on an allowlist. The clone-path hotfix #5244
(merged 2026-06-12) added a **static CIDR interval set** (`soleur_egress_allow_cidr`)
populated from `cron-egress-allowlist-cidr.txt` — but that file carries **only the four
large `/20`+`/22` ranges** (`140.82.112.0/20`, `185.199.108.0/22`, `192.30.252.0/22`,
`143.55.64.0/20`). GitHub's `/meta` `.git` **and** `.api` lists ALSO contain ~48 IPv4
`/32` addresses in the Azure `20.x.x.x` / `4.x.x.x` ranges that are **not** covered by
those four blocks. `api.github.com` round-robins DNS across BOTH pools. When a fire
lands on (or the per-tick single-IP resolver pins) a `20.x`/`4.x` address, the call is
neither pinned in the single-IP set nor matched by the CIDR set → **default-dropped** →
no GitHub call succeeds → no Sentry heartbeat → missed check-in.

This is exactly the intermittency observed: `2026-06-13` happened to dial a covered
`140.82.x` IP (green); `2026-06-14` landed on an uncovered range (red). The open
`[ci/auth-broken] Synthetic OAuth probe failed` (#5278) shares this GitHub-LB CIDR-coverage
gap — but note (deepen): cron-oauth-probe dials `github.com` (the OAuth authorize *page*,
not `api.github.com`) plus app.soleur.ai/Supabase; `github.com` is ALSO LB-rotated, so the
full-`/meta` fix helps it, but Phase 0 must confirm #5278's actual blocked DST before
asserting a shared cause.

**The fix:** make `cron-egress-allowlist-cidr.txt` carry the **complete** union of
GitHub's `/meta` `.git` + `.api` IPv4 ranges (the hosts the crons actually dial), so
`api.github.com` is covered regardless of which IP the LB returns. Reapply the firewall to
prod via the existing auto-on-merge Terraform path and verify the monitor recovers.

**This is a research/plan artifact only — no code is written in this phase.**

## Premise Validation

Checked at plan time (2026-06-14):
- **Cron substrate** (`apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`):
  confirmed all three steps hit `api.github.com`; Sentry heartbeat is Step 3, gated on
  Steps 1–2 succeeding. A blocked GitHub call therefore yields NO heartbeat at all (not
  a `?status=error`), which is precisely a *missed* check-in (not a *failed* one). ✅ holds.
- **Sentry monitor resource** (`apps/web-platform/infra/sentry/cron-monitors.tf:778`):
  `scheduled_ruleset_bypass_audit`, crontab `13 6 * * *`, margin 30, threshold 1. Matches
  the alert. ✅ holds.
- **CIDR file** (`apps/web-platform/infra/cron-egress-allowlist-cidr.txt`): carries 4
  ranges only. Live `curl https://api.github.com/meta | jq '.git,.api'` returns those 4
  PLUS ~48 `20.x`/`4.x` `/32`s. `getent ahostsv4 api.github.com` → `140.82.121.6`
  (covered TODAY) but DNS rotates. ✅ gap confirmed.
- **Recent commits ruled OUT as the 06-14 trigger:** #5268 (CIDR validation) and #5258
  (probe-cron retry) merged 2026-06-14 **11:07 / 11:16 UTC** — *after* the 06:13 UTC
  miss. They did not cause this incident (though #5268's reject-whole-file behavior is a
  forward risk this plan must respect — see Sharp Edges). #5244/#5247 (CIDR fix) merged
  2026-06-12, before the last GOOD run, so the firewall was live but incompletely scoped.
- **`hr-verify-repo-capability-claim-before-assert`:** the claim "CIDR set already covers
  api.github.com" was tested by grepping the committed file (4 ranges) against live
  `/meta` (52 ranges) — the claim is FALSE; do not bound the plan on it.

No stale external premises. Proceeding.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the alert / intuition) | Reality (verified) | Plan response |
| --- | --- | --- |
| "A missing egress CIDR entry blocks the cron" | TRUE but imprecise — it's not a *missing host* (`api.github.com` IS in the hostname allowlist); it's incomplete *CIDR* coverage for the host's full LB IP pool | Fix the CIDR file (the interval set), not the hostname file |
| "#5244 already fixed GitHub egress" | Partially — it covered `github.com` git-clone ranges but populated only the 4 big blocks, omitting ~48 `/meta` `.git`+`.api` `/32`s | Extend coverage to the full `/meta` union |
| "api.github.com resolves to 140.82.x (covered)" | TRUE right now, but DNS round-robins across `20.x`/`4.x` too | Cover all ranges; do not rely on the current single resolution |
| "The single-IP resolver (`soleur_egress_allow`) covers api.github.com" | FALSE for LB hosts — it pins ONE IP/tick; the connection frequently dials a different LB IP | Rely on the CIDR interval set for all GitHub hosts |

## User-Brand Impact

**If this lands broken, the user experiences:** the CI-Required-ruleset bypass-actors
drift audit silently stops running. An unauthorized widening of `bypass_actors` (someone
granted bypass on the protected `CI Required` ruleset) would go **undetected** — the
security control whose entire purpose is to catch that drift is dark. The operator (a
solo non-technical founder) has no other tripwire for this.

**If this leaks, the user's [workflow / repo integrity] is exposed via:** a bypassed CI
ruleset means unreviewed/unchecked code can merge to `main`, which auto-deploys to the
public `soleur.ai` production container. A single missed audit window is the gap an
attacker (or an accidental config change) needs.

**Brand-survival threshold:** single-user incident.

**Fail-open-bootstrap caveat (worst single-user outcome):** if a malformed line ever enters
the now-52-line CIDR file, the #5268/#5242 loader rejects the WHOLE file and `die`s before
installing the default-drop — leaving a FRESH host / cold-restarted container with no egress
containment (fail-open) until fixed. Mitigated by mechanical `/meta` generation, the
`bash -n` + `discoverability_test` pre-commit gate, the per-line `is_valid_ipv4_cidr`
validator, and the firewall drift-guard count check (all green pre-merge); the
`cron-egress-firewall.service` `OnFailure=` alarm pages on the `die`.

> CPO sign-off required at plan time before `/work` begins. The security control is
> brand-survival-load-bearing; `user-impact-reviewer` runs at review-time.

## Hypotheses (L3→L7 diagnostic order — `hr-ssh-diagnosis-verify-firewall`)

Per the network-outage checklist, firewall + DNS/routing are verified BEFORE any
service-layer hypothesis. **No host-shell fallback in any runbook step**
(`hr-no-ssh-fallback-in-runbooks`): every check below is via Sentry API, GitHub `/meta`,
repo grep, or the deploy webhook.

1. **L3 firewall allowlist (PRIMARY — confirmed):** `api.github.com`'s LB IP pool is
   partially outside `soleur_egress_allow_cidr`. Evidence: committed file has 4 ranges;
   `/meta` has 52 IPv4 ranges; ~48 uncovered. **This is the root cause.**
2. **L3 firewall apply drift (verify):** did the #5244/#5268 firewall change actually
   converge on the prod host? Check via the deploy webhook + the post-apply assert
   (`server.tf:821-827`). If the CIDR set is empty/stale on the host, that compounds (1).
3. **L3 DNS pin (rule out):** `soleur_egress_dns` pins resolvers; a DNS-resolution failure
   would show as `egress-dns-exfil` drops, not `egress-blocked`. Check `cron-egress-resolve`
   monitor health (it check-ins every minute) and Sentry `egress-blocked` events for
   `DST=20.` / `DST=4.` around 06:13 UTC on 06-14.
4. **L4/L7 (rule out):** Octokit/`gh` auth, App-JWT exp, rate-limit. #5258 already widened
   probe-cron retry; if a retriable transient were the cause it would surface as a
   `?status=error` heartbeat (a *failed* check-in), not a *missed* one. The alert is a
   MISS → the call never completed → firewall, not auth. (Keep as a secondary check.)

### Network-Outage Deep-Dive (deepen Phase 4.5 — `hr-ssh-diagnosis-verify-firewall`)

| Layer | Status | Verification artifact |
| --- | --- | --- |
| L3 firewall allow-list | **VERIFIED** | Committed CIDR file = 4 ranges; live `/meta` `.git`+`.api` = 52 ranges; 48 `20.x`/`4.x` `/32`s uncovered. `api.github.com` → `140.82.121.6` today but DNS round-robins across the Azure pool. ROOT CAUSE. |
| L3 DNS/routing | **HYPOTHESIS — verify in Phase 0 (NOT YET VERIFIED)** | A DNS-resolution failure manifests as `egress-dns-exfil` drops (cron-egress-nftables.sh:146-149), not `egress-blocked`; and the `cron-egress-resolve` monitor check-ins every minute. Phase 0 must confirm that monitor was GREEN at 06:13 UTC 06-14 (a red there would change the diagnosis). |
| L7 TLS/proxy | **HYPOTHESIS — deferable (NOT YET VERIFIED)** | A TLS/cert/proxy fault on `api.github.com` would surface as an Octokit error → Inngest retry → `?status=error` heartbeat (a *failed* check-in), not a *missed* one. The post-apply remote-exec ALSO `curl`s `https://api.github.com` from the container (server.tf:838) — a live reachability+TLS probe at apply time. |
| L7 application (auth/JWT/rate-limit) | **RULED OUT via logic** | Same missed-vs-failed distinction; #5258 already widened retry. Phase 0 secondary check: Sentry error-checkin count near 06:13 UTC = 0 confirms. |

**Gap to close before `/work`:** Phase 0 must produce the L3-DNS artifact (the `cron-egress-resolve` monitor's check-in status at 06:13 UTC 06-14). Everything else is artifact-backed or correctly logic-ruled-out.

## Files to Edit

- `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` — replace the 4-range list
  with the **complete** GitHub `/meta` IPv4 union (`.git` + `.api`, deduped against the 4
  big blocks), each line with an evidence comment + the `/meta` snapshot date. ~52 ranges.
  (Decision point in Phase 0: static-list vs generated — see below.)
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — extend the CIDR drift guard:
  assert the file contains representative `20.x`/`4.x` `/32` ranges (not just `140.82.112.0/20`),
  and add a behavioral assert that a known `api.github.com` Azure IP would be accepted.
  Keep the existing reject-whole-file validation asserts (#5268) green.
- `apps/web-platform/infra/server.tf` — IFF a hostname-count guard or post-apply assert
  needs widening for the new CIDR cardinality (verify lines 80-130, 719-830 at /work);
  the post-apply assert at :827 (`grep -qE '140[.]82[.]'`) should also assert a `20.` or
  `4.` element is present, proving the FULL set landed.
- ~~`apps/web-platform/infra/cloud-init.yml`~~ — **NO edit needed (deepen-verified).** The
  CIDR file is templated via `cron_egress_allowlist_cidr_b64` (cloud-init.yml:211 ⇐
  server.tf:47), so editing `cron-egress-allowlist-cidr.txt` auto-refreshes the fresh-host
  cloud-init render. Do NOT inline-duplicate the ranges here.
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` — add the
  "GitHub LB pool spans 140.82 + Azure 20.x/4.x; regenerate from /meta" remediation note.

## Files to Create

- (none expected) — this is a config + test + runbook edit. IF Phase 0 chooses the
  *generated* approach over a static list, a small generator script
  (`apps/web-platform/infra/scripts/gen-github-egress-cidr.sh`, idempotent, fetches
  `/meta`, writes the file) + its test would be created. Decide in Phase 0.

## Implementation Phases

### Phase 0 — Live diagnosis + approach decision (no writes)
1. **Confirm the firewall is the cause, not auth.** Pull the Sentry monitor/incident via
   the Sentry MCP or API (read-only): confirm the 06-14 fire is a *missed* check-in (no
   `?status=error` event), and search Sentry `egress-blocked` events for `DST=20.`/`DST=4.`
   GitHub IPs around 06:13 UTC. (`hr-no-dashboard-eyeball-pull-data-yourself` — query the
   data, do not eyeball the dashboard.)
2. **Confirm apply convergence.** Read the deploy webhook (`deploy.soleur.ai/hooks/deploy-status`,
   HMAC + CF Access via Doppler `prd_terraform`) to confirm the last infra apply; reconcile
   the post-apply CIDR assert. Use the webhook/API, not a host shell.
3. **Decide static-list vs generated.** Static list = simplest, but rots when GitHub
   rotates `/meta` (the `/32`s DO change). Generated = a tiny `/meta`-fetch script run at
   resolve-time or apply-time, self-healing. **Lean static for THIS fix** (fastest path to
   monitor recovery, lowest blast radius, matches the existing committed-file pattern) and
   file a follow-up issue for the generated/self-refreshing approach (deepen-plan + CTO to
   weigh). Record the decision.

### Phase 1 — RED test (`cq-write-failing-tests-before`)
Add the CIDR drift-guard asserts to `cron-egress-firewall.test.sh` that FAIL against the
current 4-range file. Concretely (deepen — current test only asserts the 4 big ranges at
:144 + behavioral accept at :209-214, zero Azure coverage):
- `assert_grep` presence of ≥1 Azure `20.x` `/32` AND ≥1 `4.x` `/32` in the CIDR file.
- `assert_cidr_accept` a representative `api.github.com` Azure IP (e.g. `20.201.28.151/32`).
- A line-count guard pinning the expected total CIDR entry count (mirrors the existing
  count-guard precedent at :338-341) so a future partial-revert fails CI.
Run the suite; confirm RED before editing the CIDR file.

### Phase 2 — GREEN: extend the CIDR file
Populate `cron-egress-allowlist-cidr.txt` with the full `/meta` IPv4 union (snapshot-dated,
evidence-commented). Re-run the firewall test suite (including the #5268 validation asserts)
→ all green. Mirror into `cloud-init.yml` if embedded.

### Phase 3 — Apply path (auto-on-merge; no operator host-shell step)
The `terraform_data.cron_egress_firewall` `triggers_replace` already folds the CIDR file
hash (`server.tf:728-729`); a merge to `main` re-fires the file provisioner + loader via
`apply-web-platform-infra.yml`. The post-apply assert proves the set populated. **Verify
this is the live apply mechanism at /work** (`hr-verify-repo-capability-claim-before-assert`)
— if the apply workflow name/trigger differs, correct it. No manual provisioning step.

### Phase 4 — Post-merge verification (automatable — `hr-no-dashboard-eyeball`)
- Trigger the cron on demand via `/soleur:trigger-cron`
  (`cron/ruleset-bypass-audit.manual-trigger`) and confirm a fresh `?status=ok` check-in
  lands on the Sentry monitor (poll the monitor via Sentry API).
- Confirm the Sentry incident 5516336 transitions to resolved/recovered after the next
  successful check-in (`recovery_threshold = 1`).
- Confirm no new `egress-blocked` events with GitHub DSTs.

## Observability

```yaml
liveness_signal:
  what: "scheduled-ruleset-bypass-audit Sentry Crons check-in (Step 3 heartbeat)"
  cadence: "daily 06:13 UTC (crontab 13 6 * * *)"
  alert_target: "Sentry monitor 5ccb1e67-fb90-4863-97d3-f8fd23287b37 (margin 30m, threshold 1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf:778; handler cron-ruleset-bypass-audit.ts:329"
error_reporting:
  destination: "Sentry — egress-blocked events (cron-egress-resolve.sh sentry_event); reportSilentFallback in handler"
  fail_loud: true
failure_modes:
  - mode: "GitHub call default-dropped (uncovered LB IP)"
    detection: "Sentry egress-blocked event with DST in 20.x/4.x; missed monitor check-in"
    alert_route: "Sentry monitor miss to issue; cron-egress-resolve egress_blocked event"
  - mode: "firewall apply did not converge (CIDR set empty/stale on host)"
    detection: "server.tf post-apply assert fails at apply time; deploy webhook shows failed apply"
    alert_route: "apply-web-platform-infra.yml job failure"
  - mode: "GitHub rotates /meta /32s, static list goes stale"
    detection: "future egress-blocked events with new GitHub DSTs not in the file"
    alert_route: "Sentry egress-blocked to re-run /meta snapshot (follow-up: generated approach)"
logs:
  where: "Sentry (egress-blocked events, handler reportSilentFallback); kernel journald egress-blocked (host-only, NOT shipped to Better Stack — surfaced via Sentry event only)"
  retention: "Sentry default (90d)"
discoverability_test:
  command: "comm -23 <(curl -s --max-time 10 https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(\":\")|not)' | sort -u) <(grep -vE '^[[:space:]]*(#|$)' apps/web-platform/infra/cron-egress-allowlist-cidr.txt | sort -u)"
  expected_output: "(empty — every GitHub /meta .git+.api IPv4 range is an exact line in the committed CIDR file)"
```

## Acceptance Criteria

### Pre-merge (PR)
- [x] `cron-egress-allowlist-cidr.txt` contains every IPv4 range in GitHub's `/meta`
      `.git` + `.api` union as of the snapshot date (verified with the `discoverability_test`
      command above → empty output / zero uncovered lines).
- [x] `cron-egress-firewall.test.sh` asserts presence of ≥1 Azure `20.x` AND ≥1 `4.x`
      `/32` range, and a behavioral accept of representative `api.github.com` Azure IPs;
      the full suite (incl. #5268 validation asserts) is green (138/0).
- [x] The #5268 reject-whole-file validator still passes on the new file (every line
      validated against the strict IPv4-CIDR shape — no comments-as-CIDR, no trailing `\r`).
- [x] NO `cloud-init.yml` edit (deepen-verified: templated via `cron_egress_allowlist_cidr_b64`
      — editing the file is sufficient for fresh-host parity).
- [x] `server.tf` post-apply assert proves a NON-`140.82` GitHub range is present in the set
      (extended the `:827` `grep -qE '140[.]82[.]'` with a delimiter-anchored `(20|4).` element
      assert — display-agnostic + expansion-safe, validated against both nft render forms).
- [x] PR body uses **`Ref #<tracking>`**, NOT `Closes` (ops-remediation:
      the monitor recovers post-apply, after merge — closing at merge would be false-resolved).

### Post-merge (operator — all automatable; `Automation:` justification per step)
- [ ] Firewall re-applied on merge via `apply-web-platform-infra.yml` (Automation: auto-on-merge).
- [ ] Manual cron trigger via `/soleur:trigger-cron` lands a `?status=ok` check-in
      (Automation: trigger-cron skill + Sentry API poll).
- [ ] Sentry incident 5516336 shows recovered after the next check-in (Automation: Sentry API).
- [ ] No new `egress-blocked` events with GitHub DSTs in the 24h after apply (Automation: Sentry API).

## Domain Review

**Domains relevant:** Engineering (CTO). No regulated-data surface is touched.

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Pure infra-config + test + runbook change against an already-provisioned
firewall. The durable-vs-static-list tradeoff (Phase 0 decision) is the only real
architecture call; lean static for fast recovery, defer the self-refreshing generator to a
follow-up. No new infrastructure, no new vendor, no new secret — Phase 2.8 IaC routing is
satisfied by the existing `terraform_data.cron_egress_firewall` auto-apply path.

### Product/UX Gate
**Tier:** none — no files under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`.

## Infrastructure (IaC)

This edits an EXISTING Terraform-managed surface; no new root, no new resource.

### Terraform changes
- `apps/web-platform/infra/server.tf` `terraform_data.cron_egress_firewall` already hashes
  `cron-egress-allowlist-cidr.txt` into `triggers_replace` (:728-729) and file-provisions it
  to `/etc/soleur/cron-egress-allowlist-cidr.txt` (:778). Editing the file content re-fires
  the provisioner + loader. No new variables, no new providers.

### Apply path
(b) idempotent loader re-run on merge (deepen-verified). `apply-web-platform-infra.yml`
(name "Apply web-platform infra …", trigger `push`→`main`, path filter
`apps/web-platform/infra/**`, lines 64-75) re-runs the `terraform_data.cron_egress_firewall`
provisioner, which file-provisions the CIDR file (server.tf:777-780) and runs
`cron-egress-nftables.sh`, atomically flush+repopulating the static CIDR interval set
(loader Phase 1.5). Zero downtime (additive accept rule). The post-apply remote-exec
**proves enforcement**: it `curl`s `https://api.github.com` from the container (must
succeed) AND `https://example.com` (must be dropped) (server.tf:838) — the apply FAILS if
the firewall is inert or an allowlisted host is unreachable. **No operator host-shell step**
— `hr-all-infrastructure-provisioning-servers` + `hr-no-ssh-fallback-in-runbooks`. The only
host-shell in scope is the committed Terraform provisioner (not a manually-typed operator
step). Phase 2.8 reviewed: no NEW manual provisioning (ack at top of file).

**Precedent-diff:** this fix follows the EXACT pattern #5244 established (static CIDR
interval set, file-provisioned, hash in `triggers_replace`, post-apply `140.82.` assert) —
it only completes the IP-range coverage that #5244 started. No novel mechanism; the
precedent is `git show 13275b956` + server.tf:719-843.

### Distinctness / drift safeguards
- `cloud-init.yml` ⇄ committed file parity AC prevents fresh-host drift.
- The #5268 reject-whole-file validator is the fail-loud guard against a malformed line
  half-installing the firewall.
- Static-list staleness is the residual risk → tracked by the `discoverability_test` (CI
  can run it) + the follow-up generated-approach issue.

### Vendor-tier reality check
N/A — GitHub `/meta` is a free public endpoint; no paid-tier gate.

## Test Scenarios

1. `cron-egress-firewall.test.sh` RED before file edit (Azure-range assert fails) → GREEN
   after.
2. `discoverability_test` command → zero `UNCOVERED:` lines after the edit.
3. #5268 validation: feed a deliberately-malformed line → loader `die`s (reject-whole-file)
   — confirm the new content does not trip it.
4. Post-apply (prod): manual cron trigger → `?status=ok` → incident recovers.

## Open Code-Review Overlap

None — no open code-review issues touch `cron-egress-allowlist-cidr.txt`,
`cron-egress-firewall.test.sh`, or the firewall `server.tf` block. The related #5278 OAuth
probe failure shares the GitHub-LB CIDR-coverage gap (it dials the LB-rotated `github.com`,
not only `api.github.com`) — `Ref #5278` in the PR body and verify whether it recovers
post-apply; do NOT `Closes` it blind (its blocked DST must be confirmed in Phase 0 first).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **#5268 reject-whole-file is load-bearing here:** the new CIDR file has ~52 lines instead
  of 4 — every single one MUST be a strictly valid `o.o.o.o/p` (≤255 octets, ≤32 prefix, no
  trailing `\r`, no comment-on-CIDR-line). One malformed line `die`s the loader → fail-open
  bootstrap → OnFailure alarm. Generate the list mechanically from `/meta` and run the
  `discoverability_test` + a `bash -n`/shellcheck before committing.
- **The `discoverability_test` command had a stdin-stealing bug (deepen-caught):** the
  first-draft form `... | sort -u | while read c; do grep -qF "$c" file ...; done` silently
  returned 0 UNCOVERED against the broken 4-range file because the inner `grep` consumed the
  `while` loop's stdin. The corrected form uses `comm -23 <(meta) <(file)` (exact-line set
  difference, no loop). Verified live at plan time: corrected form → 48 UNCOVERED on the
  current file. Use the corrected form in CI; never a `grep`-inside-`while-read` over a pipe.
- **`/meta` `/32`s rotate:** the static list WILL go stale eventually. This is why the
  follow-up generated approach matters; do not market the static list as permanent.
- **Do not "fix" by adding `api.github.com` to the hostname allowlist** — it is ALREADY
  there. The single-IP resolver is the wrong layer for an LB host; the CIDR interval set is
  the right one.
- **Overlap is NOT a concern (deepen-corrected):** the loader does an atomic `flush set` +
  `add element` (cron-egress-nftables.sh:118-128), so loader re-runs never hit "element
  already exists." The new Azure `/32`s (`20.x` / `4.x`) live in different `/8`s than the
  existing `/20`+`/22` blocks → no interval OVERLAP. The ONLY residual risk is an *exact
  duplicate line* in the file; build the union with `sort -u` and the
  `discoverability_test` will confirm coverage. (Earlier dedupe-vs-overlap worry retracted.)

## Deferred / Follow-up

- **Filed #5284** — "infra: self-refreshing GitHub `/meta` CIDR generator for cron egress
  firewall (replace static snapshot)" (milestone: Post-MVP / Later). Re-eval criterion: the
  static list goes stale (a new `egress-blocked` GitHub DST appears).
- **Noted (pre-existing, not in scope):** `apply-web-platform-infra.yml` has no
  failure-notification step — a failed firewall re-apply surfaces only as a red GitHub
  Actions check. The recovery backstop for THIS fix is the daily `scheduled-ruleset-bypass-audit`
  Sentry monitor (30-min miss margin), which re-alerts on the next fire if the apply did not
  land — the same signal that surfaced this incident. A dedicated apply-failure alert is a
  cross-cutting observability improvement for all infra applies, separate from this CIDR fix.
