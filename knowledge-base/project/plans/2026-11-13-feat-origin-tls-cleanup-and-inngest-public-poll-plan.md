---
title: "feat(origin-tls): make strict the baseline rule, retire the origin-TLS switches, move the Inngest sdk_url poll to the public host"
date: 2026-11-13
slug: feat-origin-tls-cleanup-and-inngest-public-poll
branch: feat-origin-tls-inngest-poll-10479-10538
issue: 10479
closes: [10479, 10538]
pr: 12737
type: security
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# Origin TLS cleanup and Inngest public-host poll

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-13 (proportionate pass: the machine is saturated, so two focused agents rather than a fan-out)
**Sections enhanced:** 8 (Research Reconciliation, Phase 6.5, Phase 7 FU-1, Research Insights premise, Implementation Phases 1 and 3, Downtime & Cutover (new),
Infrastructure, Files to Edit)
**Agents used:** a verify-the-negative sweep (general-purpose, standard tier) and
`soleur:engineering:research:framework-docs-researcher` (Inngest `--sdk-url` poll semantics). Plan review before
deepen: `soleur:engineering:review:architecture-strategist`, `soleur:engineering:review:code-simplicity-reviewer`,
`soleur:product:cpo` (sign-off), reduced from the five-seat single-user-incident panel for machine load.

### Key Improvements

1. Gate 4.55 fired: a `## Downtime & Cutover` section now states that the merge-time PUT has no `flexible` window
   (zero-downtime by construction) and that the Inngest host replace is a bounded, owner-gated window outside this PR.
2. Every negative claim the plan leans on was re-verified against code: no push workflow other than the main apply
   can apply the ruleset or the Inngest host (`scheduled-terraform-drift.yml` only plans; `registry-host-replace-dispatch.yml`
   wakes on `variables.tf` but its render gate decides); the bootstrap-image mint reads only `inngest.tf`, `vector.tf`
   and the build recipe; no middleware or Cloudflare rule treats `/api/inngest` differently by method, user agent or
   bot score (dashboard-only managed WAF settings are not visible from the repo).
3. The alert SQL's numeric `uptime_s` extract is flagged as novel in this file (precedent exists only for `match` and
   `extract`), so its live count is the proof it parses; the push-probe target list grows from six to seven.
4. Inngest v1.45.1 source (pinned CLI, commit `9059f14a`) changes what "leg 2 closed" means: the poll is a signed
   `PUT <url>` (body `{"url": ...}`, `X-Inngest-Signature`), sent by `pollSDKs` to EVERY stored `app.Url`, not only
   the `--sdk-url` seed; apps are keyed by app name (`UpsertAppByName`), so the new URL updates the app rather than
   adding one; the HTTP client verifies certificates against system roots with no skip flag; a 10 s client timeout
   and up-to-60 redirects. Inferred, not verified: the old `http://10.0.1.10:3000/api/inngest` placeholder row
   survives in Postgres across the replace and keeps being pinged in plain HTTP. FU-1 therefore gains a measured exit
   condition (below), and the row-6 conversion cannot rest on the replace alone.

### New Considerations Discovered

- Historical comments naming "Flexible SSL for web platform" in `tests/scripts/lib/preapply-entrypoint-gate.sh` and
  `apply-web-platform-infra.yml` describe the 2026-07-20 adoption incident, not the current rule, and stay unchanged;
  ADR-130 and ADR-136 likewise.
- PR #12733 re-read during deepen: still OPEN (mergeStateStatus CLEAN), so Phase 4 still waits on it.

## Overview

One PR closes two security issues.

- **#10479 (Cloudflare to origin).** The zone already serves `app.soleur.ai` in `strict` (measured 2026-11-13 about
  06:50Z, read-only: zone SSL mode `strict`; config-settings entrypoint version 7 with 5 rules, two of them the
  temporary ORIGIN-TLS canary and strict rules, both enabled; 0 page rules; `origin-tls-probe.sh --require-tls` x3
  returned 200 TLSv1.3 `TLS-ON-ORIGIN-HOP`). This PR folds that end state into the one long-lived rule (the adopted
  rule, ref `dcb85b75bc3c4f4aa2a8c13a080bf854`, becomes `ssl = "strict"` for `(http.host eq "app.soleur.ai")`),
  deletes the two temporary rules and their two Terraform switches (5 to 3 rules, one whole-list PUT, no `flexible`
  window), and brings every pin, runbook, ADR, ledger row and published legal sentence in line. The merge itself is
  the production write (push apply of `cloudflare_ruleset.seo_config_settings`, acked by an `[ack-destroy]` line).
- **#10538 (Inngest `sdk_url` poll, leg 2).** Remedy (c): `sdk_url` becomes `https://app.soleur.ai/api/inngest`
  (`--poll-interval 60` kept), the same path the step calls already take (public-CA TLS to the edge, strict TLS to the
  origin). This is a declared-config change only: `hcloud_server.inngest` is not a push-apply target, so the live host
  keeps the private plain-HTTP poll until the owner's later `inngest-host-replace` dispatch. A new Better Stack logs
  alert pages when a serving dedicated host reports an empty or unreadable registry.

All technical and legal rulings were made before planning and are recorded in
`knowledge-base/project/specs/feat-origin-tls-inngest-poll-10479-10538/decision-challenges.md` (CTO and CLO agent
rulings, 2026-11-13). Five forks found during planning were ruled by one batched CTO spawn and appended there. This
plan does not reopen any ruling.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| "Add a Better Stack alert ... for 3 consecutive probes" | The probe runs hourly (`OnUnitActiveSec=1h`); new native logs alerts are capped at `query_period` 900 s (`apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`: "the API refuses a new alert above 900"). Three consecutive hourly rows need about 3 h of lookback. | CTO ruling (new fork F1): one native alert over a 900 s window that fires on ONE serving row with `uptime_s > 900` and a non-positive `registry_fns`. Not-serving rows stay with the existing probe heartbeat. |
| Alert lives "in uptime-alerts.tf or wherever logtail_exploration_alert lives" | All `logtail_exploration_alert` resources live in `apps/web-platform/infra/betterstack-logs-alerts.tf`; its header lists a 7-step add-an-alert checklist. | New resources go in `betterstack-logs-alerts.tf` and follow all 7 steps. |
| "Update comments in inngest-bootstrap.sh / cloud-init-inngest.yml" | `inngest-bootstrap.sh` is a `cp` carrier of the bootstrap image (any content change mints a `vinngest` tag, a build and a pin-bump); `cloud-init-inngest.yml` comments ride inside `user_data` (32,768 B Hetzner cap; budget measured 40 B over its floor on 2026-11-01). | CTO ruling (F2): neither file is edited. The corrected wording goes in `inngest-host.tf` comments, with a note that the carrier comment is stale until that file next changes for a real reason. |
| "Verify no push-apply target touches hcloud_server.inngest" | Verified by grep: the per-merge `-target` list in `.github/workflows/apply-web-platform-infra.yml` (from about line 453) names neither `hcloud_server.inngest` nor its dependents (`hcloud_server_network.inngest`, `network.tf`; `hcloud_volume_attachment.inngest_redis_luks`, `inngest-redis-luks.tf`); they appear only in the dispatch-only `inngest-host` and `inngest-host-replace` jobs. CTO confirmed. | Recorded as a premise; AC9 re-runs the grep at work time. |
| "workflow/Doppler-to-TF_VAR wiring for the two variables (grep ENABLE_ORIGIN_TLS)" | No workflow sets either switch (`seo-config-rules.test.ts` already asserts that). The only wiring is `doppler run --name-transformer tf-var` over Doppler `prd_terraform`, where both secrets are currently `true`. Measured locally (Terraform 1.9.8, scratch root under `/var/tmp/oneshot-10479/tfvar-probe`): an undeclared `TF_VAR_*` environment variable is ignored with no warning and exit 0. CI applies with 1.10.5. | Deleting the variables leaves the two Doppler secrets inert, not breaking. Their deletion is owner housekeeping (a Doppler write), tracked in follow-up FU-3, not a merge blocker. |
| `tfplan-origin-tls-cleanup.json` replay "expected 0:2:0:2:1" | The fixture exists, but its `after` state keeps the old expression (`app.soleur.ai` + `lb-staging.soleur.ai`) and the old description. | Regenerate it to the final shape (strict, `http.host eq "app.soleur.ai"`, new description); the expected tuple stays `0:2:0:2:1` without an ack and `0:2:0:2:0` with one. |
| `cloudflare-readonly.sh` "baseline B" | The header pins `rule_count is 5`, `enabled_ssl_rules is 2`, ref dcb85b75 `ssl=flexible`; `plugins/soleur/test/cloudflare-readonly.test.sh` derives `TF_SSL` from `seo-config-rules.tf` while EXCLUDING `"strict"` lines, and a `tn` row forbids the text `enabled_ssl_rules is 1 AND`. After the cleanup the file holds one `strict` and one `full` ssl line, so the unchanged derivation would yield 1, which the `tn` row forbids. | The test's `TF_SSL` derivation counts every ssl line (2); the header becomes `enabled_ssl_rules is 2 ... ref dcb85b75... with ssl=strict ... AND rule_count is 3`. |
| Ledger row 7 `enforced_at` | Still says "container publishes 80:3000 and 3000:3000; no 443 listener" and cites the rule described "Flexible SSL for web platform". | Rewritten with the row conversion (origin-tls.ts listener, 443 publish, new rule description). |
| `#9139` as the hop-1 tracker | `#9139` is CLOSED (it re-scoped the step-call leg). Hop 1 (Inngest server to the Cloudflare edge, certificate check) is still unmeasured. | The ledger cites `#9139` for the leg and the new follow-up FU-1 for the hop-1 measurement the CLO requires before the live act. |
| "domains.md SSL Mode" and "Last Updated" | Also stale: `knowledge-base/engineering/architecture/nfr-register.md` row "Cloudflare edge -> web-host origin" (Not Implemented, "target 2026-11-12"). | Added to Files to Edit. |
| "the same path the step calls already take" (remedy (c)) | Verified against the pinned CLI v1.45.1 source: the poll is a signed `PUT` to every stored app URL with Go's default certificate verification; Cloudflare Browser Integrity Check could in principle challenge a non-browser user agent, but the step calls from the same client already pass through the same host, and `bot-management.tf` allows automated traffic (`sbfm_definitely_automated = "allow"`). | Kept; a stale private app row is the new residual (FU-1 item 7b). |
| C4 | `model.c4` edge `inngest -> api` says the `--sdk-url` (`http://10.0.1.10:3000/api/inngest`) is the registration poll; editing `model.c4` forces a `model.likec4.json` regeneration. | CTO ruling (F4): unchanged here (the live host still polls the private URL); edited in the row-6 conversion PR (FU-1). |

## Research Insights

**Premise Validation.** Checked 2026-11-13: #10479 OPEN, #10538 OPEN (labels `action-required`, `deferred-scope-out`),
#9139 CLOSED, draft PR #12737 OPEN (BLOCKED: draft), PR #12733 OPEN (re-read 2026-11-13 during deepen: OPEN, mergeStateStatus CLEAN, not merged; another session's ledger renewal: it touches only
`scripts/encryption-posture-ledger.json` rows 6 and 7 and adds
`knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`; it sets row 6 `expires_on`
2026-11-20 and row 7 `expires_on` 2026-11-19). `collision-precheck.sh` for both issues: `SOLEUR_COLLISION exit=10
prs=12737,12733 foreign=none` - #12737 is this PR; #12733 is the known overlap the CTO ruled on (this PR rebases after
it and never edits it). All cited paths exist on `origin/main`. ADR corpus check for the mechanisms: ADR-321 item 10
already names this cleanup as the planned end state (rule count 5 to 3, `[ack-destroy]`); ADR-100 Decision 1 named a
private VIP as the multi-replica `--sdk-url`, which remedy (c) supersedes (the CTO ruled (c) over (a) and (b)); no ADR
rejected a public `--sdk-url`. Baseline measured 2026-11-13: `python3 scripts/lint-encryption-posture.py --repo-root .` FAILs on `origin/main` with 2 failing checks (rows 6 and 7, `expires_on` 2026-11-12 in the past); #12733 clears row 6 and this PR's row-7 conversion clears row 7, so this branch's `encryption-posture` check is red until it rebases on #12733.

**Property List** (Phase 0.6b).

1. P1 - Every Cloudflare-to-origin request for `app.soleur.ai` is made in `strict` (certificate and hostname
   verified) by ONE permanent rule, with no switch that can silently return it to `flexible`.
2. P2 - The rule list shrinks 5 to 3 in one atomic write with no `flexible` window, and the destroy guard requires an
   explicit, reviewed acknowledgement for it.
3. P3 - Every repo artifact that pins the old shape (tests, fixtures, wrapper baseline, runbooks, ADRs) states the
   new shape, so no pin goes green on a stale claim.
4. P4 - The declared Inngest registration poll travels over TLS with certificate verification on every hop.
5. P5 - The declared change cannot reach the live Inngest host except through the owner's gated replace.
6. P6 - A serving dedicated host whose registry is empty or unreadable pages without SSH.
7. P7 - The encryption-posture ledger describes live state: row 7 measured TLS, row 6 still an exception pending the
   owner's act.
8. P8 - The published wording claims Cloudflare-to-origin TLS only when it is true and measured per host, and the
   rollback path corrects it the same day.
9. P9 - The owner's residual acts (replace, hop-1 measurement, row-6 and C4 conversion, Doppler housekeeping, port 80)
   are tracked, not lost.

**Cut List** (mechanisms in the ask already covered or not buying a property).

- `inngest-bootstrap.sh` comment edits -> P3 -> covered by `inngest-host.tf` comments; the edit would mint a no-op
  image release (CTO F2).
- `cloud-init-inngest.yml` comment edits -> P3 -> same; rides in `user_data` near the 32 KB cap (CTO F2).
- A "3 consecutive probes" window -> P6 -> not buildable under the 900 s ceiling; one serving row with an uptime
  floor buys P6 (CTO F1).
- A workflow or Doppler TF_VAR wiring change -> none exists (only `--name-transformer tf-var`); nothing to cut or
  build.
- A C4 edit -> P7 analogue for diagrams -> deferred to the row-6 conversion PR (CTO F4).
- Not cut: the alert. The probe heartbeat's shared classifier (`scripts/inngest-dedicated-host-classify.sh`, healthy =
  `server_active=active` AND `http_code=200`) ignores `registry_fns`, so P6 is unbought on `origin/main` today
  (`scripts/inngest-host-state.sh` requires `registry_fns > 0` but is diagnostic, not paging).

**Value-proposition measurement.** Not applicable (no cost or performance saving is claimed).

**Relevant files (anchors, not line numbers, are authoritative).**

- `apps/web-platform/infra/seo-config-rules.tf` - resource `cloudflare_ruleset.seo_config_settings`; rules "ADOPTED
  RULE" (ref dcb85b75), email obfuscation, apex `full` (ADR-194), "ORIGIN-TLS CANARY", "ORIGIN-TLS STRICT FLIP"; the
  header block "ROLL FORWARD, NEVER REVERT".
- `apps/web-platform/infra/variables.tf` - `variable "enable_origin_tls_canary_rule"`, `variable "enable_origin_tls_strict"`.
- `apps/web-platform/test/seo-config-rules.test.ts` - `ADOPTED_SSL_EXPRESSION`, `flexibleSslRule()` (selects by
  `ssl = "flexible"`), `canaryRule()`/`strictRule()` (by description prefix), "exactly five rules", the
  `describe("... origin-TLS canary + strict-flip rules (ADR-321)")` block, "the probe sends the same header the canary
  rule matches", the LB-monitor precondition test.
- `apps/web-platform/infra/ssl-full-mitigation.test.sh` - the fallback awk that excludes the adopted app rule
  expression and the `http.host eq` ORIGIN-TLS forms.
- `apps/web-platform/infra/origin-tls-probe.sh` + `.test.sh` - `--canary` (rows C1b to C4).
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` `t_origin_tls_rules_toggle_not_remove` (T65) +
  `tests/scripts/fixtures/tfplan-origin-tls-{merge,flip-on,rollback,canary-off,canary-off-strict-on,cleanup,old-dynamic-rollback}.json`.
  The anti-vacuity floor is a floor, not an equality, so replacing a fixture does not move it.
- `plugins/soleur/scripts/cloudflare-readonly.sh` (header "Records mapping", B) +
  `plugins/soleur/test/cloudflare-readonly.test.sh` ("drift pin (#10479, Ref #10205)").
- `.github/workflows/cf-lb-overlay.yml` - the `staging-record` / `staging-overlay` / `staging-teardown` arms
  (lb-staging.soleur.ai, `apps/web-platform/infra/lb-staging/`). The Origin CA certificate covers `app.soleur.ai` only
  (ADR-321 decision 2), so once `lb-staging` leaves the rule a re-run of a staging arm meets zone `strict` and would
  get 526.
- `apps/web-platform/infra/inngest-host.tf` - `locals { ... sdk_url = "http://10.0.1.10:3000/api/inngest" }` and its
  comment ("Single stable --sdk-url to the ACTIVE web backend's private interface"); `hcloud_server.inngest` (no
  `ignore_changes = [user_data]`, so the next replace delivers it).
- `apps/web-platform/infra/inngest-userdata-budget.sh` - stub map `sdk_url = "http://10.0.1.10:3000/api/inngest"`
  ("byte-identical copies of the real values"). Old and new URLs are both 33 bytes, so the stored size is unchanged.
- `apps/web-platform/test/server/inngest/exec-placement-forward.test.ts` Guard 4 ("inngest-host.tf sdk_url's host IS
  the pin", must-PASS "pin / sdk_url / web-1 private_ip must agree").
- `apps/web-platform/server/inngest/exec-placement.ts` (`EXEC_HOST_PRIVATE_IP` doc comment names `sdk_url`),
  `apps/web-platform/server/inngest/execution-placement.ts` (header: "which Cloudflare routes to web-1 only"; stale
  since web-2 serves at LB weight 1), `apps/web-platform/lib/auth/resolve-origin.ts` (header "Measured on prod: the
  dedicated inngest host's --sdk-url sync poll (http://10.0.1.10:3000/api/inngest, ~120/hr)"),
  `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (comment), `.github/workflows/workspaces-luks-verify.yml`
  (comment "the --sdk-url http://10.0.1.10:3000/api/inngest in inngest-host.tf is the registration poll").
- `apps/web-platform/app/api/inngest/route.ts` - `SERVE_HOST = "https://app.soleur.ai"`, `serveOrigin`/`servePath:
  "/api/inngest"`: every registration already reports the public URL, so the new poll URL equals the registered app
  URL (no second app identity).
- `apps/web-platform/infra/betterstack-logs-alerts.tf` - header "TO ADD ANOTHER LOGS ALERT (seven steps)",
  `local.inngest_luks_wrong_volume_sql` (the two-leg SQL the new alert copies), `logtail_exploration_alert.inngest_luks_wrong_volume`.
- `apps/web-platform/infra/inngest-bootstrap.sh` (read only) - the probe body: `registry_fns` is
  `.data.functions | length` from `http://127.0.0.1:8288/v0/gql`, `__UNREADABLE__` when `http_code != 200`, jq is
  missing, or the answer is not numeric; the emit line `SOLEUR_INNGEST_SERVER_PROBE http_code=... server_active=...
  uptime_s=... host_role=... registry_fns=... data_luks=...`.
- `scripts/encryption-posture-ledger.json` `connections[6]` (leg 2 poll) and `connections[7]` (CF edge to origin);
  `scripts/lint-encryption-posture.py` (structural checks; `disclosed_as` is `path:anchor`, resolved by `text.find`).
- Legal set (from the legal research pass): `docs/legal/privacy-policy.md` Section 11 bullet "**Encryption in
  transit:**" and `**Last Updated:**`; `docs/legal/data-protection-disclosure.md` 8.1(c) and `**Last Updated:**`;
  byte-identical passages in `plugins/soleur/docs/pages/legal/{privacy-policy,data-protection-disclosure}.md`;
  `apps/web-platform/lib/legal/legal-doc-shas.ts` (SHA-256 of the raw `docs/legal/<doc>.md` bytes, regenerated with
  `sha256sum`; checked by `apps/web-platform/scripts/check-tc-document-sha.sh` and
  `apps/web-platform/test/legal-doc-shas-guard.test.ts`); `knowledge-base/legal/article-30-register.md` 2026-10-29
  #10479 markers in PA-1 (g), PA-2 (g), PA-3 (g), PA-4 (g), PA-13 (g)(14) and Cross-Cutting "Encryption in transit";
  `knowledge-base/legal/data-processing-agreement-template.md` §9 Security and Schedule 4 item 1;
  `knowledge-base/operations/domains.md` row "SSL Mode"; `docs/legal/gdpr-policy.md` has no transit claim (no change).
  Gates: `apps/web-platform/test/legal-doc-consistency.test.ts` (heading sequence + Last Updated parity),
  `scripts/lint-legal-mirror-drift-baseline.sh`, `scripts/lint-legal-registers.sh`.

**Institutional learnings applied.**

- `2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md` - a clean plan can hide a whole-list
  delete; the `ref` pin and the T65 replay are the evidence, not the plan summary.
- `2026-09-27-an-import-block-breaks-terraform-test-and-a-count-ack-reaches-every-destroy.md` - `[ack-destroy]` is a
  boolean over `destroy_count`: it acks every destroy in the same plan, hence the CTO's "merge alone, no other
  `apps/web-platform/infra` PR in the same queue batch".
- `2026-11-06-a-single-merge-ack-needs-a-recovery-line-and-i-wrote-two-claims-the-panel-measured.md` - a superseded
  acked run fails closed; the runbook carries the recovery line (re-merge path, never a dispatch).
- `2026-11-08-a-merge-that-edits-registry-cloud-init-auto-replaces-the-registry-host-...md` - read every workflow's
  `on.push.paths`, not just the apply workflow. Done: `registry-host-replace-dispatch.yml` wakes on `variables.tf`
  (deliver=false: `sdk_url` is not a registry render input); `mint-inngest-bootstrap-tag.yml` wakes on
  `inngest-host.tf` (no carrier change, no tag); `web-platform-release.yml` releases on any `apps/web-platform/**`
  change (a normal release; comment-only server edits); `validate-vector-config.yml` and `infra-validation.yml` are
  validation only.
- `2026-06-11-restart-recovery-push-driven-not-poll-driven.md` - re-registration after a `--sdk-url` change is
  push-driven; the runbook step after the owner's replace keeps the explicit `PUT https://app.soleur.ai/api/inngest`.
- `2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` and the `inngest_luks_wrong_volume`
  comments (#8846/#8874) - anchor on `SYSLOG_IDENTIFIER = 'inngest-server-probe'` and the marker at message position 1;
  webhook payloads quote the marker.
- `2026-11-06-an-absence-alert-on-a-zero-filling-evaluator-must-count-the-missing-...md` - `treat_as_zero` reads silence
  as health; the dead-probe case stays with `betteruptime_heartbeat.inngest_server_probe`.
- `2026-06-15-two-legal-mirror-gates-and-always-build-mcp-registered-list-desync.md` - re-pinning `LEGAL_DOC_SHAS` is
  not enough; the heading-sequence and date-parity gate must also pass.

**Conventions (CLAUDE.md / AGENTS.md).** `hr-all-infrastructure-provisioning-servers` (no SSH; the host change rides
the owner's replace), `hr-no-ssh-fallback-in-runbooks`, `hr-observability-layer-citation`,
`cq-cite-content-anchor-not-line-number` (rules cited by description or ref), `wg-use-closes-n-in-pr-body-not-title-to`,
`hr-technical-fork-is-not-an-operator-question`, `wg-block-pr-ready-on-undeferred-operator-steps` (owner acts go to
follow-up issues, not a PR checklist), `cq-test-fixtures-synthesized-only` (the T65 fixtures are offline replays with
provider config stripped, no live data).

**External research.** Not run: the codebase carries the measured Cloudflare and Inngest behaviour this plan relies on
(ADR-321, ADR-243, the T65 replays, the 2026-11-07 flip record), and the standing-delegation rules forbid the ad-hoc
vendor reads that would add to it. Community and functional discovery (Phase 1.5/1.5b) not run: the plan adds no
plugin capability and every stack it touches (Terraform, bash, TypeScript) is covered by built-in agents.

## Rulings applied

From `decision-challenges.md` (2026-11-13), unchanged: cleanup end state (one whole-list change, 5 to 3); `[ack-destroy]`
on its own line in the commit that removes the rules, merge alone; rollback = forward PR to `flexible`, never `git
revert`; port 80 stays open; #10538 remedy (c), no flag, the owner's replace is the gate and follows the verified
cleanup apply and #10479 closing; observability reuse plus one alert; ledger row 7 converts here, row 6 stays an
exception; CLO wording conditions; rebase after #12733 and never edit it; `Closes` for both issues with a new tracking
issue for the residual.

New this session (CTO agent, 2026-11-13; appended to `decision-challenges.md`): F1 alert shape; the stale-registry
follow-up (must merge before the owner's replace); F2 leave `inngest-bootstrap.sh` and `cloud-init-inngest.yml`
untouched; F3 three per-host readings within 24 h before merge, merge waits if the host-attributed reading is
unverified; F4 C4 unchanged here.

## Implementation Phases

Order matters only where stated. Every test run is ONE suite file at a time (`bash <file>` or `npx vitest run
<file>` from `apps/web-platform`); never `test-all.sh`, `run-registered-suites.sh` or an affected-battery runner (the
machine is saturated). Scratch goes under `/var/tmp`.

### Phase 0 - Preconditions (read-only)

1. `git fetch origin main` and check whether PR #12733 has merged (`gh pr view 12733 --json state,mergedAt`). If it
   has, rebase this branch on `origin/main` before touching the ledger. If it has not, do Phases 1 to 3 and 5 to 7
   first, and do Phase 4 (ledger) only after it merges; ship waits on it (CTO ruling "Overlap with PR #12733").
2. Re-run the merge-apply safety grep and record the result in the PR body: the per-merge `-target` list of
   `.github/workflows/apply-web-platform-infra.yml` contains no `hcloud_server.inngest`,
   `hcloud_server_network.inngest` or `hcloud_volume_attachment.inngest_redis_luks`.
3. Re-read the live ruleset through the wrapper (Class R) and keep the output in `/var/tmp/oneshot-10479/`:
   `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh config-entrypoint` (expect
   5 rules, version 7 or later, ref dcb85b75 `flexible`, both ORIGIN-TLS rules enabled). A count or order that differs
   from `seo-config-rules.tf` stops the work: the whole-list PUT at merge would erase a dashboard edit.

### Phase 1 - #10479 cleanup (tests first)

1. RED: update `apps/web-platform/test/seo-config-rules.test.ts` to the target shape before editing Terraform:
   - `ADOPTED_SSL_EXPRESSION = '(http.host eq "app.soleur.ai")'`; a new `ADOPTED_SSL_DESCRIPTION` constant
     (`"Strict SSL for app.soleur.ai (ADR-321, #10479)"`).
   - Replace `flexibleSslRule()` with `adoptedSslRule()` selected by `ref = "dcb85b75bc3c4f4aa2a8c13a080bf854"` (the
     ssl value is what changed, so it can no longer be the selector).
   - "exactly three rules"; "the adopted rule is strict, enabled, ref-pinned, expression and description exact".
   - New property tests: exactly one rule sets `ssl = "strict"` and it is
     the adopted rule; every other ssl-setting rule is the apex `full` rule on the canonical marketing expression (a
     later `set_config` rule matching the app host would override the adopted one, since the last match wins).
   - Delete the `describe("... origin-TLS canary + strict-flip rules (ADR-321)")` gate rows that pin the switches,
     keeping three tombstone rows: no `var.enable_origin_tls_` reference anywhere under `apps/web-platform/infra/`,
     neither variable declared in `variables.tf`, no rule description starting `ORIGIN-TLS`. Keep "no tfvars file" and
     "no workflow sets either switch" (they still guard a re-introduced switch) and the LB-monitor precondition test.
   - Replace "the probe sends the same header the canary rule matches" with: `origin-tls-probe.sh` no longer contains
     `x-origin-tls-probe`, and no rule expression mentions it.
2. GREEN: `apps/web-platform/infra/seo-config-rules.tf` - edit the adopted rule (`ssl = "strict"`, expression
   `(http.host eq \"app.soleur.ai\")`, description as above, `ref` and order unchanged); rewrite its comment block
   (no longer "reproduced verbatim": state that it was adopted from the dashboard on 2026-07-20, made strict by this
   change, and that a return to `flexible` is a reviewed forward PR that triggers the same-day wording correction);
   delete the CANARY and STRICT FLIP rule blocks and their comment blocks; update the header comments that describe
   the five-rule list, the switches and "lb-staging". `apps/web-platform/infra/variables.tf` - delete both variable
   blocks and their comments.
3. `apps/web-platform/infra/ssl-full-mitigation.test.sh` - THREE sites exclude the app rules (architecture review):
   the main selector, the fallback selector and the count of other ssl rules. In all three, drop the old
   `in {"app.soleur.ai" "lb-staging.soleur.ai"}` literal and the canary literal, and keep one exact match on
   `(http.host eq "app.soleur.ai")` (now the adopted rule) so the apex `full` rule stays the sole match.
4. `apps/web-platform/infra/origin-tls-probe.sh` - retire `--canary`: delete its `case` branch so it falls to the
   existing catch-all `*)` usage error (exit 64); delete the header text and the `x-origin-tls-probe` request header; update the
   "WHAT A PASS PROVES" paragraph (the zone and the adopted rule are both `strict`, so a pass now proves Cloudflare
   accepted the certificate for that request). `origin-tls-probe.test.sh` - replace rows C1b to C4 with a row that
   `--canary` exits 64 and sends nothing, keep every `--require-tls` row.
5. T65 fixture: regenerate `tests/scripts/fixtures/tfplan-origin-tls-cleanup.json` as an offline real plan, the way
   the existing fixtures were made (test file comment above `t_origin_tls_rules_toggle_not_remove`): in a scratch root
   under `/var/tmp/oneshot-10479/t65/` holding only `cloudflare_ruleset.seo_config_settings` and the pinned provider
   `cloudflare/cloudflare` 4.52.7, plan the before configuration (5 rules, both enabled) from empty state, build a
   prior state from its planned values, plan the after configuration (this PR's 3 rules) against it with
   `-refresh=false` and a dummy token, `terraform show -json`, strip `configuration.provider_config` and any
   provider block. Expected through the real filter: `0:2:0:2:1` with an empty head message, `0:2:0:2:0` with
   `$'chore: cleanup\n\n[ack-destroy]\n'`. If the provider cannot be downloaded in this environment, derive the
   `after` block from the current fixture with `jq` (rule 0: expression, description) and say so in the commit
   message and the test comment. Add one T65 row asserting the fixture's `after.rules` length is 3 and the dcb85b75 rule is `strict` on
   `(http.host eq "app.soleur.ai")` (a `jq` read of the fixture; the guard filter reads counts only). Keep the other
   six origin-TLS fixtures as historical filter regressions and reword
   the T65 header comment from "the rules are ALWAYS PRESENT" to "were always present until the cleanup".
6. `plugins/soleur/test/cloudflare-readonly.test.sh` (RED first) - `TF_SSL` counts every ssl line in
   `seo-config-rules.tf` (drop the `grep -cvE '"strict"'` exclusion) and add a row that derives the dcb85b75 rule's `ssl` value from
   `seo-config-rules.tf` and requires the header to state `with ssl=<that value>` (so a rollback edits only the header); update the comment above it. Then `plugins/soleur/scripts/cloudflare-readonly.sh` header B:
   `Records ok ONLY when enabled_ssl_rules is 2 AND one of those rules has ref dcb85b75bc3c4f4aa2a8c13a080bf854 with
   ssl=strict (the other is the ssl = "full" rule on soleur.ai and www) AND rule_count is 3; anything else ...`;
   delete the two-switch paragraph; add a dated-snapshot note (2026-11-13: rule_count 5 to 3, the adopted rule
   flexible to strict). Header text only: no code path changes. This file is one of the two paths Class R item 4
   names; its first live read with the new header is after the merge (its own "run from origin/main" rule).
7. `.github/workflows/cf-lb-overlay.yml` - a comment block above the `staging_record` job: since #10479 the adopted
   rule covers `app.soleur.ai` only, the zone is `strict`, and the Origin CA certificate names `app.soleur.ai` only,
   so a re-run of a staging arm would get 526 on `lb-staging.soleur.ai`; reviving the staging arms needs a
   host-scoped rule or a certificate that names the host, in its own reviewed PR. Comment-only (no job change).
8. Run, one file at a time: `npx vitest run test/seo-config-rules.test.ts` (from `apps/web-platform`), `bash
   apps/web-platform/infra/ssl-full-mitigation.test.sh`, `bash apps/web-platform/infra/origin-tls-probe.test.sh`,
   `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`, `bash plugins/soleur/test/cloudflare-readonly.test.sh`,
   and `terraform fmt -check` plus `terraform validate` in `apps/web-platform/infra` only if an init is already cached
   (no backend init against R2 from this machine). Census of other suites that read `seo-config-rules.tf` (from
   `git grep -c 'seo_config_settings\|seo-config-rules' -- tests/ scripts/ plugins/soleur/test/ apps/web-platform/test/ apps/web-platform/infra/*.test.sh`):
   `ssl-full-mitigation-mutation.test.sh` (its `m2b_flexible` / shadow rows edit the apex rule, not the adopted one;
   it is a heavy mutation battery with its own CI leg since #12654, so run it once only if the machine allows, else
   say in the PR body that CI's mutation leg carries it), `pr5-anchor-integrity.test.sh`,
   `seo-page-redirects-ruleset.test.ts` and `scripts/followthroughs/gsc-404-cdn-cgi-census-6746.sh` (no old-shape
   pin found at plan time; run the first two once).
9. Commit this phase on its own, with a message that carries a line containing exactly `[ack-destroy]`, for example:

   ```text
   feat(origin-tls): strict becomes the adopted rule; remove the canary and strict-flip rules (ADR-321, #10479)

   [ack-destroy]

   Removes two rules from cloudflare_ruleset.seo_config_settings (5 -> 3, nested_deletes 2, replayed in T65).
   ```

   The repository squash message is COMMIT_MESSAGES, so this line reaches the merge commit; the apply workflow matches
   `(^|\n)\[ack-destroy\]($|\n)` over the merge message. A PR-body line does not reach it.

### Phase 2 - #10538 declared change

1. RED: `apps/web-platform/test/server/inngest/exec-placement-forward.test.ts` Guard 4, rewritten, not deleted:
   - "inngest-host.tf sdk_url is the public serve URL": the literal is exactly
     `sdk_url = "https://app.soleur.ai/api/inngest"` and it equals `SERVE_HOST + "/api/inngest"` as read from
     `app/api/inngest/route.ts` (one source of truth for the registered app URL).
   - The 10.0.1.10 pin now binds to the volume holder only: `EXEC_HOST_PRIVATE_IP` = `variables.tf` web-1
     `private_ip` = the `workspaces_luks` attachment host (existing rows kept).
   - The must-PASS row asserts `{EXEC_HOST_PRIVATE_IP, web1ip}` agree and `sdk_url` is the public URL.
   - Update the file header line "Guard 4 the 10.0.1.10 pin is one source of truth across exec-placement.ts,
     infra/inngest-host.tf sdk_url, ...".
2. GREEN: `apps/web-platform/infra/inngest-host.tf` - `sdk_url = "https://app.soleur.ai/api/inngest"`; rewrite its
   comment: remedy (c) of #10538 (CTO and CLO rulings 2026-11-13), same path as the step calls (public-CA TLS to the
   edge, `strict` to the origin), poll interval stays 60 s, the URL equals the registered serve URL so no second app
   identity appears, the value reaches the live host only at the owner's `inngest-host-replace` (no push-apply
   target), and the carrier comment in `inngest-bootstrap.sh` ("polls the co-located web-platform") is out of date
   until that file next changes for a real reason (CTO F2 must-do 3). Do not edit `inngest-bootstrap.sh` or
   `cloud-init-inngest.yml`.
3. `apps/web-platform/infra/inngest-userdata-budget.sh` - the stub `sdk_url` literal follows (33 bytes either way).
4. Comments only: `apps/web-platform/server/inngest/exec-placement.ts` (`EXEC_HOST_PRIVATE_IP` is the ADR-119 volume
   holder; it no longer equals the `sdk_url` host; Guard 4 drift list), `apps/web-platform/server/inngest/execution-placement.ts`
   (the LB steers each step call to either serving web host; the declared `--sdk-url` is the public serve URL from
   this change, live after the owner's replace), `apps/web-platform/lib/auth/resolve-origin.ts` (the private-IP
   rejections stop once the live host polls the public URL; until then they continue), `apps/web-platform/test/server/inngest/function-registry-count.test.ts`,
   `.github/workflows/workspaces-luks-verify.yml` (comment at the `--sdk-url` mention).
5. Run, one at a time: `npx vitest run test/server/inngest/exec-placement-forward.test.ts`,
   `npx vitest run test/server/inngest/function-registry-count.test.ts`, `npx vitest run lib/auth/resolve-origin.test.ts`,
   `bash apps/web-platform/infra/inngest-userdata-budget.sh` (expect the same stored size and headroom as before),
   `bash apps/web-platform/infra/inngest-host.test.sh`, `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh`
   (its loopback `sdk_url` pin is the rehearsal root's own and must stay green).

### Phase 3 - The registry alert (`betterstack-logs-alerts.tf`, the seven-step checklist)

1. Step 1, live-probe the predicate first (Class R: `SELECT count()` only, through `scripts/betterstack-query.sh`,
   written by the agent): (a) the full predicate over 24 h -> expected 0; (b) positive control: the same predicate
   with the positive-integer test flipped (rows whose `registry_fns` IS a positive integer) -> expected about 24 per
   day; (c) population control: emitter + marker + `host_role=dedicated ` -> expected about 24. Record the three counts
   in the resource comment with the date, as the sibling alerts do. Query mechanics (`scripts/betterstack-query.sh`
   header): pass the SQL in SINGLE quotes - the script itself substitutes the `$BS_TABLE` and `$BS_TABLE_S3` tokens,
   and double quotes would expand them, empty, in the caller's shell (the `doppler run -- cmd "$VAR"` trap); a
   24 h window must UNION the `remote($BS_TABLE)` hot table (about 40 minutes) with `s3Cluster(primary, $BS_TABLE_S3)`,
   or the count is silently short. The same applies to the Phase 8 per-host counts.
2. Step 2-3: `locals { inngest_registry_empty_sql = <<-SQL ... SQL }`, `logtail_exploration.inngest_registry_empty`
   and `logtail_exploration_alert.inngest_registry_empty` (name `soleur-inngest-registry-empty-prd`). SQL shape, per
   CTO F1 and its must-do 1: leg A = `SYSLOG_IDENTIFIER = 'inngest-server-probe'`, marker at message position 1,
   `host_role=dedicated `, `server_active=active `, `http_code=200 `, `uptime_s` extracted and `> 900` (`uptime_s` is the host's `/proc/uptime`, so the floor covers a freshly replaced host; `uptime_s=unknown` reads 0 and stays quiet, a recorded residual), and NOT
   `match(message, 'registry_fns=[1-9][0-9]* ')` (negated over the field, so a missing or renamed field fires); leg B
   = the phone-home vector-down row (`shipper = 'cloud-init-phone-home'`, `stage = 'inngest-server-probe-vector-down'`)
   with the same field tests on `detail`. Copy the SHAPE of `inngest_luks_wrong_volume_sql`, not its body: leave out
   `local.inngest_luks_wrong_volume_alias` (it reads `hcloud_volume.inngest_redis_luks.id`, which would give every
   merge apply a second path to the sole-copy LUKS volume, ADR-282, the G2e rows of `terraform-target-parity.test.ts`)
   and leave out its `detail = ''` branch (a not-serving or fieldless row belongs to the heartbeat, per ruling F1). Precedent (deepen 4.4): negated `match(...)` and `extract(...)` already appear in
   `registry_clientip_not_rfc1918_sql`; a numeric extract such as `toUInt64OrZero(extract(msg, 'uptime_s=([0-9]+) '))`
   has NO precedent in this file (only `toInt64(...)` casts exist), so it is novel and its live count (step 1) is the
   proof it parses. Alert: `alert_type = "threshold"`, `operator = "higher_than"`, `value = 0`,
   `check_period = 300`, `query_period = 900`, `confirmation_period = 0`, `recovery_period = 7200`,
   `on_missing_data = "treat_as_zero"`, `paused = false`, email and push on, call and sms off, the
   `escalation_target` ternary of the siblings, `metadata.runbook` = the new runbook anchor, and an `incident_cause`
   that says: a serving dedicated Inngest host owns no functions or cannot read its registry (the public sdk_url poll
   may be failing after a replace); it does NOT detect a stale non-zero registry (FU-1 adds that field).
3. Step 4: two `-target=` lines (`logtail_exploration.inngest_registry_empty`,
   `logtail_exploration_alert.inngest_registry_empty`) in the per-merge plan allowlist of
   `apply-web-platform-infra.yml`, beside the `inngest_step_524` pair.
4. Step 5: a "Standing alarms over this source" row in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
   and a runbook section "Registry-empty alert (#10538)" in `inngest-server.md` (what fires it, the read-only triage
   without SSH: `scripts/inngest-host-state.sh` and the `SELECT count()` reads, the push re-registration
   `PUT https://app.soleur.ai/api/inngest`, and the replace-window reading).
5. Step 6: one more `values = [local.vector_prd_source_id]` in the exploration count asserted by
   `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`.
6. Step 7: a drift guard `apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh` (modelled on
   `inngest-luks-wrong-volume-alert.test.sh`; see Guard 3 below) and its `run: bash` step in
   `.github/workflows/infra-validation.yml` plus any runbook path it reads in that workflow's `paths:` filters.
7. Run, one at a time: the new guard, then EVERY suite that enumerates logs alerts, derived by grep rather than
   from this list (sharp edge: an allow-list extension is asserted by guards outside the named filter):
   `git grep -ln 'logtail_exploration' -- apps/web-platform/test/infra apps/web-platform/infra/*.test.sh plugins/soleur scripts tests`
   (about 20 files under `apps/web-platform` today, plus `plugins/soleur/scripts/inngest-alerts-push-probe.ts`, whose
   `TARGETS` list is six hardcoded `[type, name]` pairs ("all SIX" in its header; the test refers to "index 4 of 6")
   and must gain this `push = true` alert as the seventh, with the header wording updated, plus
   `plugins/soleur/test/inngest-alerts-push-probe.test.ts`). Also run `plugins/soleur/test/terraform-target-parity.test.ts`. Update any census or count that moves. The last alert addition (#8611, `inngest_step_524`) had to
   edit `betterstack-send-failed-alert-mutation.test.sh` and `registry-store-not-luks-alert.test.sh`; expect the
   same two, plus `logs-alert-query-period-ceiling.test.sh` and `betterstack-alert-structure.test.sh` to run green.

### Phase 4 - Ledger (`scripts/encryption-posture-ledger.json`, after #12733 is on main)

1. `connections[7]` (Cloudflare edge to origin) becomes a measured TLS row:
   - `enforced_at`: `seo-config-rules.tf` (the `set_config` rule described "Strict SSL for app.soleur.ai (ADR-321,
     #10479)", ref dcb85b75, `http.host eq app.soleur.ai`); `apps/web-platform/server/origin-tls.ts` (the `:443`
     listener on the Cloudflare Origin CA certificate, `ORIGIN_TLS_REQUIRED`); `ci-deploy.sh` and `cloud-init.yml`
     (the `443:3443` publish); `app/api/inngest/route.ts` (`serveOrigin`); `dns.tf` and `cloudflare-lb.tf`.
   - `tls`: browser to edge TLS; edge to web hosts TLS 1.3 under `strict`, verifying the Origin CA certificate and the
     `app.soleur.ai` hostname, measured per host on <the F3 reading date> (LB pool page per origin, Better Stack
     per-host listening rows, 20 public probes); hop 1 of the step-call leg (dedicated Inngest host to the edge) is TLS
     against a public CA per the SDK contract and not yet measured against the deployed build (#9139; FU-1).
   - `cert_verification: "on"`; the `exception` block is removed (this also removes the 2026-11-19 cliff #12733 set).
   - `disclosed_as: "docs/legal/privacy-policy.md:Encryption in transit"`.
   - `does_not_defend`: Cloudflare terminates TLS at the edge and sees requests and responses in plaintext (a
     disclosed processor, Privacy Policy 5.8); port 80 is still open on the web hosts behind the Cloudflare IP
     allowlist, and a forward change of the adopted rule back to `flexible` (the rollback path) would return this hop
     to plain HTTP; without Authenticated Origin Pulls any client on Cloudflare's IP ranges can connect to the origin
     (connect, not observe); hop 1 of the step-call leg is unmeasured.
2. `connections[6]` (leg 2 poll) stays an exception (`tls` none, `cert_verification` off, `expires_on` as #12733 set
   it, not touched). Append to `justification`, after #12733's text: "fires on the merge of PR #12737, which changes the
   declared configuration to remedy (c): sdk_url https://app.soleur.ai/api/inngest (public-CA TLS to the Cloudflare
   edge, strict TLS to the origin). The live inngest host still runs the pre-merge plain-HTTP sdk_url until the owner's
   inngest-host-replace, not yet run or measured (tracked as #<FU-1>)." Append to `reevaluate_when`: "; or the owner's
   live act is measured". `tracking_issue`: `#<FU-1>` (#10538 closes with this PR). `enforced_at`: note that
   `inngest-host.tf` now declares the public URL and the live host keeps the private one until the replace.
3. Run `python3 scripts/lint-encryption-posture.py --repo-root .` and `bash scripts/lint-encryption-posture.test.sh`.

### Phase 5 - Legal wording (CLO ruling text, verbatim)

1. `docs/legal/privacy-policy.md` Section 11 bullet "**Encryption in transit:**": replace the claim sentences with the
   CLO text from `/var/tmp/oneshot-10479/clo-ruling.md` §3 ("Connections between your browser and Cloudflare ...
   Since November 7, 2026, Cloudflare forwards requests to our web servers over TLS and verifies our servers'
   certificate. We do not claim TLS for all server-to-server traffic ... some traffic between our web servers and our
   job scheduler ... We are evaluating TLS for those private-network links."), add the "*(Added <merge date>, ref
   #10479: this bullet previously read ...)*" note, keep the existing Corrected notes. `**Last Updated:**` becomes the
   merge date with a short note naming Section 11; the current entry moves to `Previous:`.
2. `docs/legal/data-protection-disclosure.md` 8.1(c): the sentences after the opening clause become the CLO text
   ("**FULFILLED as to AES-256-GCM ...** In transit: TLS for browser-to-Cloudflare connections and, since November 7,
   2026, TLS from Cloudflare to our web servers, with Cloudflare verifying the servers' certificate. ... **FULFILLED
   as to the Cloudflare-to-origin connection. NOT FULFILLED as to server-to-server transport.**") plus the Added note;
   `**Last Updated:**` as above.
3. Identical body edits in `plugins/soleur/docs/pages/legal/privacy-policy.md` and
   `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (byte-identical passages today), and their Last
   Updated lines.
4. `<merge date>` is the UTC day the PR is expected to merge, written at ship time; if the merge slips past that day,
   the date is corrected (and the SHAs re-pinned) in a commit before merge (Sharp Edges).
5. Re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts` for `privacy-policy` and `data-protection-disclosure`
   (`sha256sum docs/legal/<doc>.md`), in the same commit as the doc edits.
6. `knowledge-base/legal/article-30-register.md`: correct each affected cell (PA-1 (g), PA-2 (g), PA-3 (g), PA-4 (g),
   PA-13 (g)(14) including its "target 2026-11-12, hard stop 2026-11-19" and "plain HTTP if the zone mode is
   `flexible`" sentences, Cross-Cutting "Encryption in transit") and append `Superseded <merge date> (#10479)` under
   every 2026-10-29 #10479 marker; never delete a marker.
7. `knowledge-base/legal/data-processing-agreement-template.md`: §9 Security TOMs and Schedule 4 item 1 reconciled to
   the new Privacy Policy wording (TLS from Cloudflare to the web servers with certificate verification since
   2026-11-07; some server-to-server traffic, including between the web servers and the job scheduler, not
   TLS-encrypted).
8. `knowledge-base/operations/domains.md` "SSL Mode": Full (Strict) zone default; `app.soleur.ai` strict through the
   adopted Configuration Rule (described "Strict SSL for app.soleur.ai (ADR-321, #10479)", ref dcb85b75); measured
   2026-11-13 strict through two later rules before the cleanup; re-measured after the cleanup apply (Phase 9).
   Bump `last_updated`.
9. `knowledge-base/engineering/architecture/nfr-register.md` row "Cloudflare edge -> web-host origin": Implemented,
   with the measured state and #10479.
10. `docs/legal/gdpr-policy.md`: grep only (no transit claim; record "no change" in the PR body).
11. Absence greps, run after stripping the "*(Added ...)*" and "*(Corrected ...)*" notes: no live sentence still says
    "We do not currently claim TLS for the connection from Cloudflare", "NOT FULFILLED as to transport encryption
    beyond the Cloudflare edge" or "target 2026-11-12" in `docs/legal/`, the two mirrors, the Article 30 register or
    the NFR register.
12. Run, one at a time: `npx vitest run test/legal-doc-consistency.test.ts`, `npx vitest run test/legal-doc-shas-guard.test.ts`,
    `bash apps/web-platform/scripts/check-tc-document-sha.sh`, `bash scripts/lint-legal-mirror-drift-baseline.sh`,
    `bash scripts/lint-legal-registers.sh`.

### Phase 6 - ADRs and runbooks

1. ADR-321: a dated amendment item 13 (items 11 and 12 already exist: PR #12388 and PR #12434 rulings) "Cleanup (2026-11-13, #10479)": the adopted rule is `strict` for `http.host eq
   app.soleur.ai` (lb-staging dropped: no DNS record, and the certificate does not name it); both ORIGIN-TLS rules and
   both switches deleted; 5 to 3 in one whole-list PUT acked by `[ack-destroy]`; rollback is a forward PR to
   `flexible` (no switch remains by design), break-glass the owner's dashboard edit; any return to `flexible` corrects
   the published wording the same day (CLO); port 80 stays open (separate PR, FU-3); the per-host pre-merge evidence
   (F3) and its result. Update item 10's "The cleanup change has not been made" with a pointer to item 13.
2. ADR-100: amend Decision 1: the single stable `--sdk-url` is the public serve URL `https://app.soleur.ai/api/inngest`
   (remedy (c) of #10538; CTO and CLO rulings 2026-11-13); it supersedes the private VIP plan for N>1 (the Cloudflare
   LB in front of both replicas is the steering layer, and the poll URL equals the registered `serveOrigin`); add
   "private VIP behind --sdk-url" and options (a) web-side TLS listener and (b) poll removal to Alternatives
   Considered with the reasons from the ruling; state that the live host changes only at the owner's
   `inngest-host-replace`.
3. `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`: a dated Status line (cleanup merged,
   apply run, re-measure result); rewrite "Rollback" (a forward PR setting the adopted rule back to `flexible`, an
   in-place update with no deletes, plus the same-day correction of Privacy Policy Section 11, DPD 8.1(c) and ledger
   row 7); rewrite "Break-glass" (owner only: edit the adopted rule in the dashboard, then the forward PR so the next
   apply does not undo it); "After the flip has baked: the cleanup change" becomes "Cleanup (done <date>)" with the
   recovery line for a superseded acked run (re-merge path; a dispatch cannot ack); retire every `--canary` mention.
   **Simulate the rollback before writing it** (sharp edge: a rollback recipe nobody ran): in a scratch detached
   worktree under `/var/tmp/oneshot-10479/rollback-sim/`, set the adopted rule back to `ssl = "flexible"` and run the
   suites this PR touches once each (`seo-config-rules.test.ts`, `ssl-full-mitigation.test.sh`,
   `cloudflare-readonly.test.sh`, `lint-encryption-posture.py`). Guard 1 is meant to go RED there, so the recipe must
   list every file the forward PR edits with it (the Guard 1 constants, the wrapper header `ssl=flexible`, ledger row 7
   back to `cert_verification` off with an `exception` block carrying `tracking_issue` and `expires_on`, Privacy Policy
   Section 11, DPD 8.1(c), the two mirrors and `LEGAL_DOC_SHAS`) and say that the change carries no `[ack-destroy]`
   (no deletes). Write the recipe from what that run needed, then delete the scratch worktree. The recipe also says:
   after an owner dashboard break-glass, no `apps/web-platform/infra` PR may merge until the forward PR to
   `flexible` lands (every per-merge apply targets `cloudflare_ruleset.seo_config_settings` and would undo the
   dashboard edit), and that PR goes first in the queue. To keep the rollback to a header edit on the wrapper side,
   `cloudflare-readonly.test.sh` derives the expected `ssl` of the dcb85b75 rule from the `.tf` instead of a fixed
   `has_file "with ssl=strict"` row (Phase 1.6).
4. `knowledge-base/engineering/operations/runbooks/origin-tls-canary.md`: mark retired (dated), keep the history, point
   to item 13 of ADR-321.
5. `knowledge-base/engineering/operations/runbooks/inngest-server.md`: the new "Registry-empty alert (#10538)" section
   (Phase 3); a "Public sdk_url poll (#10538 remedy (c))" section for the owner's replace: preconditions in order
   (cleanup apply measured and #10479 closed, FU-1's sync-evidence field merged, hop 1 measured), the read-only
   post-replace checks (`registry_fns` and the new field, the explicit `PUT` re-registration, the stored app `url`
   rows, the private-IP rejections in `resolve-origin.ts` stopping, since v1.45.1 polls every stored app URL), and the CLO owner-record requirement if the act lands after 2026-11-20; fix
   the table rows that say the poll is "dated disposition to 2026-12-10, tracked as #10538".
6. Run `bash scripts/lint-legal-scope-block-placement.sh` only if Phase 5 or 6 touched a scope block; otherwise skip.

### Phase 7 - Follow-up issues (created during work, before ship; `--body-file` under `/var/tmp/oneshot-10479/`)

Each body carries a line `Mandated-By: wg-when-deferring-a-capability-create-a`, milestone "Post-MVP / Later".

- **FU-1** "inngest: deliver the public sdk_url poll (#10538 remedy (c)) - sync-evidence probe field, owner replace,
  hop-1 measurement, ledger row 6 and C4 conversion". Body: (1) a probe field that proves the server's last
  successful sync is recent (the CTO's stale-registry ruling; this PR's alert cannot see a stale non-zero registry),
  merged BEFORE the replace; (2) the owner's `inngest-host-replace` dispatch, only after the cleanup apply is measured
  and #10479 is closed (CLO condition); (3) hop 1 measured by a handshake or failure test against the deployed build;
  (4) a separate PR converting ledger row 6 with the measurement; (5) the C4 `inngest -> api` edge and
  `model.likec4.json`; (6) the Privacy Policy / DPD "between our web servers and our job scheduler" sentence revisited
  with the CLO once leg 2 is TLS - the published wording, the DPA template and the Article 30 register keep that
  carve-out until the hop-1 and leg-2 measurements are recorded (CPO condition 3); (7) if the act lands after 2026-11-20, the owner-typed record of CLO ruling §4
  (beginning "SIGNED BY OWNER (human, not an agent)"); (7b) leg 2 counts as closed only when the private-URL poll
  is MEASURED to have stopped: Inngest v1.45.1 `pollSDKs` pings every stored `app.Url`, so a stale
  `http://10.0.1.10:3000/api/inngest` app row persisted in Postgres would keep the plaintext `PUT` alive after the
  replace. Read-only checks first (the stored `url` of each app row through the host-local GQL the probe already uses,
  and a Better Stack `SELECT count()` of the `resolve-origin` rejection rows for that origin falling to 0); if the row
  persists, its removal is a planned step with its own ruling, before row 6 converts. Also watch the #7228 double-fire
  probe after the replace: the sync checksum includes the URL, so the first sync is not deduplicated; (8) refresh the
  stale carrier comment in
  `inngest-bootstrap.sh` when that file next changes. Related: epic #10390. Ledger row 6 `tracking_issue` points here.
- **FU-3** "security: close port 80 on the web hosts now that Cloudflare to origin is strict (follow-up of #10479)"
  (a second destroy and a deploy of the `-p 0.0.0.0:80:3000` publishes; also evaluate Authenticated Origin Pulls).
  Its body also carries the owner's housekeeping item: delete the inert `ENABLE_ORIGIN_TLS_CANARY_RULE` and
  `ENABLE_ORIGIN_TLS_STRICT` Doppler secrets (a Doppler write; harmless meanwhile, since Terraform ignores undeclared
  `TF_VAR_*`, measured on 1.9.8). There is no separate FU-2.
- **Conditional FU-4** (only if the F3 Playwright reading is unverified): the separate small PR adding a read-only
  `lb-pool-health` subcommand to `cloudflare-readonly.sh`, merged first; plus one `action-required` issue naming the
  Load Balancing read token to mint if no existing token can read it.

### Phase 8 - Pre-merge evidence (CTO F3; within 24 h before merge)

Record the readings, with UTC timestamps, as a bullet list under a `## Pre-merge evidence readings (F3)` heading
placed AFTER the rulings table in `decision-challenges.md` (never as a table row: the ruling gate accepts only the
classes `technical`, `taste` and `operator (<category>)`), and quote them in the PR body.

1. Host-attributed: a Playwright snapshot (`mcp__plugin_soleur_playwright__*`, wrapped profile, aggregate page only,
   no clicks) of the Cloudflare LB pool page for the `app.soleur.ai` pool showing origins web-1 and web-2 each healthy
   under the https/443 `allow_insecure = false` monitor. Unverified (no session, login page, or a page without
   per-origin health) means the merge waits and FU-4 starts.
2. Per host, through `scripts/betterstack-query.sh` with agent-written `SELECT count()` queries only, from a checkout
   where the wrapper matches `origin/main`: at least one `origin-tls: listening` row with `required: true` per host
   (`soleur-web-platform`, `soleur-web-2`) since its last start; the 24 h count of `failed the TLS handshake` rows per
   host.
3. 20 runs of `bash apps/web-platform/infra/origin-tls-probe.sh --require-tls`, all `TLS-ON-ORIGIN-HOP` exit 0.
4. Continuity since 2026-11-07 (CPO condition 1, backing the published "Since November 7, 2026"): re-read
   `cloudflare-readonly.sh config-entrypoint`, `ssl-mode` and `pagerules-ssl`. Expected, as read on 2026-11-13 at
   06:52Z (`/var/tmp/cf-readonly-10479-20261113T0652Z.log`): entrypoint `version` 7 with `last_updated`
   `2026-11-07T23:43:43.865194Z` (the flip write, so no ruleset write since), zone `ssl` `strict` with `modified_on`
   `2026-02-16T14:59:26.468406Z`, `ssl_rule_count` 0. Also attempt `change-history` (E; evidence only, expected
   `Unverified` until its token is relocated). If the entrypoint `last_updated` has moved, the published date is
   re-derived from the earliest verified reading after the move, with the CLO's agreement, before merge.
5. The PR body quotes the results (counts and statuses only, no vendor text).

### Phase 9 - Ship and post-merge (the merge is the production write)

0. Within about an hour before queueing the merge, re-read `cloudflare-readonly.sh config-entrypoint`: `rule_count`
   5 and the same `version` (7) and `last_updated` as Phase 0. Any change means a dashboard edit the whole-list PUT
   would erase: stop. If the PR's CI runs a plan-only job, its plan must show exactly 2 nested rule deletes for
   `cloudflare_ruleset.seo_config_settings` and no other destroy.
1. Merge alone: no other `apps/web-platform/infra` PR in the same merge-queue batch (an `[ack-destroy]` acks every
   destroy in the plan).
2. After the merge: read the push apply run (`gh run list --workflow apply-web-platform-infra.yml --branch main`,
   then the run's job steps) and confirm the destroy guard passed with the ack, the apply step succeeded and the two
   new alert resources were created. A red apply leaves the ruleset unchanged or partly applied: re-read it before
   anything else.
3. Re-measure (CLO condition 2): `cloudflare-readonly.sh ssl-mode` (strict) and `config-entrypoint` (`rule_count` 3,
   `enabled_ssl_rules` 2, ref dcb85b75 `ssl=strict`), 20 `origin-tls-probe.sh --require-tls` runs, and the three F3
   readings again; record them on #10479 as a comment.
4. Any red reading: the forward PR to `flexible` per the rewritten runbook. That PR carries the corrected legal
   wording, ledger row 7 and `LEGAL_DOC_SHAS` in its own diff (CPO condition 2), so the published claim and the
   live mode change in the same merge; only the owner's dashboard break-glass can precede it, and then the PR lands
   the same day (CLO).
5. The new alert counts as in place only after step 2 shows both alert resources created (CPO condition 3); until
   then no message, issue or runbook says the registry is monitored.

## Files to Edit

- `apps/web-platform/infra/seo-config-rules.tf`
- `apps/web-platform/infra/variables.tf`
- `apps/web-platform/test/seo-config-rules.test.ts`
- `apps/web-platform/infra/ssl-full-mitigation.test.sh`
- `apps/web-platform/infra/origin-tls-probe.sh`
- `apps/web-platform/infra/origin-tls-probe.test.sh`
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` (T65 comment)
- `tests/scripts/fixtures/tfplan-origin-tls-cleanup.json` (regenerated)
- `plugins/soleur/scripts/cloudflare-readonly.sh` (header only)
- `plugins/soleur/test/cloudflare-readonly.test.sh`
- `.github/workflows/cf-lb-overlay.yml` (comment only)
- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/inngest-userdata-budget.sh`
- `apps/web-platform/test/server/inngest/exec-placement-forward.test.ts`
- `apps/web-platform/server/inngest/exec-placement.ts` (comment only)
- `apps/web-platform/server/inngest/execution-placement.ts` (comment only)
- `apps/web-platform/lib/auth/resolve-origin.ts` (comment only)
- `apps/web-platform/server/origin-tls.ts` (header comment only: "`flexible` rule for app.soleur.ai", "(or the canary
  rule)"; cited by ledger row 7 `enforced_at`)
- `apps/web-platform/infra/cloudflare-lb.tf` (comment only: "still `flexible` for this host until the strict flip")
- `apps/web-platform/infra/lb-staging/main.tf` (header comment only) and
  `knowledge-base/engineering/operations/runbooks/cf-lb-a-record-gaplessness-verify.md` ("edge hop is unchanged
  (`flexible`)")
- `plugins/soleur/scripts/inngest-alerts-push-probe.ts` and `plugins/soleur/test/inngest-alerts-push-probe.test.ts`
  (the push-armed Inngest alert list gains the new alert)
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (the "Nth Logs alert" amendment every logs alert adds; the latest is the tenth, so check the count at work time)
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` (comment only)
- `.github/workflows/workspaces-luks-verify.yml` (comment only)
- `apps/web-platform/infra/betterstack-logs-alerts.tf`
- `.github/workflows/apply-web-platform-infra.yml` (two `-target=` lines)
- `.github/workflows/infra-validation.yml` (one `run:` step, `paths:` if needed)
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (exploration count)
- `apps/web-platform/test/infra/registry-store-not-luks-alert.test.sh` and any other logs-alert census the Phase 3
  step 7 grep finds moving (expected from the #8611 precedent)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `scripts/encryption-posture-ledger.json`
- `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`
- `plugins/soleur/docs/pages/legal/privacy-policy.md`, `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- `apps/web-platform/lib/legal/legal-doc-shas.ts`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/data-processing-agreement-template.md`
- `knowledge-base/operations/domains.md`
- `knowledge-base/engineering/architecture/nfr-register.md`
- `knowledge-base/engineering/architecture/decisions/ADR-321-origin-tls-terminates-in-the-app-container-with-a-cloudflare-origin-ca-certificate.md`
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`
- `knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md`
- `knowledge-base/engineering/operations/runbooks/origin-tls-canary.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/project/specs/feat-origin-tls-inngest-poll-10479-10538/decision-challenges.md` (F3 readings)

Not edited, by ruling: `apps/web-platform/infra/inngest-bootstrap.sh`, `apps/web-platform/infra/cloud-init-inngest.yml`,
`knowledge-base/engineering/architecture/diagrams/*.c4`, `model.likec4.json`, `docs/legal/gdpr-policy.md`, anything
PR #12733 adds.

## Files to Create

- `apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh` (drift guard for the new alert)

## Open Code-Review Overlap

3 open `code-review` issues mention files this plan touches; all are **acknowledged** (different concerns, left open):

- #10243 (review: nft comment correction on PR 8945) - names `cloud-init-inngest.yml`, which this plan no longer edits.
- #12582 (founder-visible stall surface for placement-refused Inngest step calls) - names `exec-placement`; this plan
  edits only a doc comment there.
- #11825 (harden `extractTfMonitorNames()` parse in the function-registry-count drift guard) - this plan edits only a
  comment in that file.

## Infrastructure (IaC)

### Terraform changes

- Root `apps/web-platform/infra` (R2 backend, existing): `cloudflare_ruleset.seo_config_settings` in place (5 to 3
  rules; provider `cloudflare/cloudflare` 4.52.7 via the `cloudflare.rulesets` alias, unchanged); two variables
  deleted; `local.sdk_url` value changed (feeds `hcloud_server.inngest` `user_data`, ForceNew, not push-applied);
  `logtail_exploration.inngest_registry_empty` + `logtail_exploration_alert.inngest_registry_empty` created
  (provider `logtail`, pinned as for the siblings). No new sensitive variable. Inputs come from Doppler `prd_terraform`
  as today; the two `ENABLE_ORIGIN_TLS_*` secrets become inert (FU-3).

### Apply path

- Ruleset and alert: (a) the per-merge push apply of `apply-web-platform-infra.yml` (targeted), acked by the
  `[ack-destroy]` line; no downtime by construction (traffic is already `strict` through the temporary rules, and the
  PUT keeps it `strict`). Blast radius if wrong: every `app.soleur.ai` user gets 525/526 or, worse, plain HTTP on the
  hop; the T65 replay, the seo-config property tests and the post-merge re-measure bound it.
- `hcloud_server.inngest`: (b) `terraform apply -replace` through the owner's gated `inngest-host-replace` dispatch,
  later, tracked in FU-1 (one Inngest outage window, the replace runbook's existing procedure). Not part of this merge.

### Host fan-out

No `terraform_data` SSH provisioner is added or edited. `hcloud_server.web[*]` is not touched.

### Distinctness / drift safeguards

The ruleset ID stays hardcoded with the zone a variable (fails closed on a re-pointed zone). The scheduled drift plan is
untargeted; after the merge it must show no diff for the ruleset. The ADR-136 pre-apply entrypoint gate does NOT
cover this change: it inspects only pure `["create"]` rows with `before == null`, so an in-place update prints "No
clobber surface". The destroy guard compares rule COUNTS and `[ack-destroy]` is a yes/no flag, so a rule added in the
dashboard after Phase 0 would be deleted silently under the same ack. Hence Phase 9 step 0 (a fresh entrypoint read
right before queueing) and the "exactly 2 nested deletes" check.
`dev != prd` is not affected (prd only). State already holds the ruleset; secret values in state are unchanged.

### Vendor-tier reality check

Better Stack free tier: no `betteruptime_policy` (the alert uses the siblings' `escalation_target` ternary); new logs
alerts above `query_period` 900 are refused (the alert uses 900); the free-tier alert-count cap is unmeasured (ADR-218):
if the create is refused, the apply goes red after the ruleset change, which Phase 9 step 2 reads.

## Downtime & Cutover

Deepen-plan Phase 4.55 fires: `inngest-host.tf` changes `hcloud_server.inngest` `user_data` (no
`ignore_changes = [user_data]`), so the host's next apply is a `-/+` replace.

1. **Offline-inducing operations and surfaces.**
   - (a) The ruleset PUT at merge: `app.soleur.ai`, every user.
   - (b) The later `inngest-host-replace`: the Inngest scheduler (crons and event-driven runs), not in this PR.
2. **Zero-downtime path, defaulted to.**
   - (a) is zero-downtime by construction. The live list already serves `strict` through the STRICT rule, and the
     one whole-list PUT moves the adopted rule to `strict` in the same write that deletes the temporary rules, so no
     request is ever evaluated in `flexible` (CTO ruling "no flexible window"). The per-request mode is the same before
     and after the write. Verification: Phase 9 steps 2 to 3. Rollback: the forward PR (Phase 6.3).
   - (b) has no zero-downtime path today. ADR-100 makes the Inngest server a singleton control plane (two
     schedulers would double-fire every cron), and the replace runbook's measured clean path is a bounded window:
     about 2.5 minutes of apply and 79 s from server creation to `bootstrap-done` on 2026-09-27, plus the gated
     `cutover-inngest.yml op=resume` (`inngest-server.md` §"Clean path"). Residual downtime is accepted only as that
     bounded window, in the owner's go, at the owner's chosen time, tracked in FU-1. This PR does not trigger it: there
     is no push-apply target for the host (AC9).
3. **Not a downtime path.** Merging does not restart the web hosts beyond the normal `web-platform-release.yml`
   release, which already ran many times under `strict` with `ORIGIN_TLS_REQUIRED=1` (runbook restart table).

## Observability

```yaml
liveness_signal:
  what: "Cloudflare edge->origin: origin-tls-probe.sh --require-tls (public), Better Stack app monitor on https://app.soleur.ai/health (uptime-alerts.tf), the LB https monitor per origin (cloudflare-lb.tf) with cloudflare_notification_policy.web_lb_health; Inngest registry: the hourly SOLEUR_INNGEST_SERVER_PROBE row (registry_fns) under the new logtail_exploration_alert.inngest_registry_empty and the existing betteruptime_heartbeat.inngest_server_probe"
  cadence: "app monitor and LB monitor 60 s; probe row hourly; alert check every 300 s over 900 s; heartbeat feeder every 15 min"
  alert_target: "Better Stack email + push to the team (paid tier: betteruptime_policy.uptime); Cloudflare LB health notification email; Sentry origin-tls-event rule"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf, apps/web-platform/infra/uptime-alerts.tf, apps/web-platform/infra/cloudflare-lb.tf, apps/web-platform/infra/sentry/ (origin-tls-event)"
error_reporting:
  destination: "Sentry (web-platform project, SENTRY_DSN) with tag feature:origin_tls from apps/web-platform/server/origin-tls.ts; Better Stack Logs source 2457081 for the probe rows and the origin-tls warn lines"
  fail_loud: "HTTP 525/526 at the edge for app.soleur.ai; origin-tls-probe.sh result=NOT-200 exit 1 or NO-TLS-ON-ORIGIN-HOP exit 3; incident soleur-inngest-registry-empty-prd"
failure_modes:
  - mode: "the cleanup PUT leaves app.soleur.ai in flexible (wrong expression, rule order, or a lost rule)"
    detection: "post-merge cloudflare-readonly.sh config-entrypoint (rule_count 3, enabled_ssl_rules 2, ref dcb85b75 ssl=strict) and origin-tls-probe.sh --require-tls exit 3; the scheduled drift plan"
    alert_route: "the post-merge verification in the shipping session; drift issue from scheduled-terraform-drift.yml"
  - mode: "the Origin CA certificate or the :443 listener fails on one host under strict"
    detection: "LB https monitor marks that origin unhealthy; Sentry feature:origin_tls; Better Stack origin-tls warn lines per host"
    alert_route: "cloudflare_notification_policy.web_lb_health email; Sentry origin-tls-event rule"
  - mode: "after the owner's replace, the public sdk_url poll fails and the serving host owns no functions"
    detection: "logtail_exploration_alert.inngest_registry_empty (serving row, uptime_s > 900, registry_fns not a positive integer)"
    alert_route: "Better Stack email + push"
  - mode: "after the owner's replace, the public poll fails but the Postgres-held registry stays non-zero (stale)"
    detection: "not detected by this PR; FU-1 adds the sync-evidence probe field before the replace"
    alert_route: "FU-1"
  - mode: "the probe goes silent"
    detection: "betteruptime_heartbeat.inngest_server_probe fed by scheduled-inngest-probe-heartbeat.yml"
    alert_route: "Better Stack heartbeat incident"
logs:
  where: "Better Stack Logs source 2457081 (Vector journald from the web hosts and the dedicated Inngest host); GitHub Actions logs of apply-web-platform-infra.yml"
  retention: "Better Stack plan retention (hot then s3 archive); GitHub Actions 90 days"
discoverability_test:
  command: "bash apps/web-platform/infra/origin-tls-probe.sh --require-tls"
  expected_output: "TLS-ON-ORIGIN-HOP"
```

## Encryption Posture

```yaml
at_rest: []   # no persistent store is added or changed
in_transit:
  - connection: "Cloudflare edge -> web hosts (app.soleur.ai), ledger connections[7]"
    enforced_at: "apps/web-platform/infra/seo-config-rules.tf (rule described 'Strict SSL for app.soleur.ai (ADR-321, #10479)', ref dcb85b75bc3c4f4aa2a8c13a080bf854); apps/web-platform/server/origin-tls.ts (:443 listener, ORIGIN_TLS_REQUIRED)"
    tls: "TLS 1.3 observed (TLS 1.2+ accepted by the listener), Cloudflare strict mode"
    cert_verification: "on"
    does_not_defend: "Cloudflare terminates TLS and sees plaintext; port 80 still open behind the Cloudflare IP allowlist and a forward PR back to flexible would re-open plain HTTP; no Authenticated Origin Pulls, so other Cloudflare-range clients can connect (connect, not observe); hop 1 of the step-call leg unmeasured"
    disclosed_as: "docs/legal/privacy-policy.md:Encryption in transit"
  - connection: "dedicated Inngest host -> web app sdk_url poll, ledger connections[6] (DECLARED after this PR: https://app.soleur.ai/api/inngest; LIVE until the owner's replace: http://10.0.1.10:3000/api/inngest)"
    enforced_at: "apps/web-platform/infra/inngest-host.tf (local sdk_url) via hcloud_server.inngest user_data"
    tls: "live: none (plain HTTP on 10.0.1.0/24, every 60 s); declared: public-CA TLS to the Cloudflare edge, then strict TLS to the origin"
    cert_verification: "off"
    does_not_defend: "live: a passive on-net attacker on 10.0.1.0/24 can read the HMAC-signed poll request and the public function metadata it returns; declared: Cloudflare sees the poll in plaintext at the edge, and hop 1 certificate checking by the Inngest CLI is unmeasured"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "the live host keeps the plain-HTTP poll until the owner's gated inngest-host-replace (CTO ruling: a row describes live state); accepted by the owner until 2026-11-20 per PR #12733's record"
  tracking_issue: "#10538"   # re-pointed to FU-1 in the ledger at work time, when FU-1 exists (#10538 closes with this PR)
  reevaluate_when: "the owner's live act is measured, a non-Jikigai peer joins 10.0.1.0/24, or the poll is exposed publicly or across networks"
  expires_on: "2026-11-20"
```

## Architecture Decision (ADR/C4)

### ADR

- Amend ADR-321 (new item 13, "Cleanup", 2026-11-13): strict is the baseline rule; switches removed; rollback is a
  forward PR; wording correction on any return to `flexible`.
- Amend ADR-218 with the "Nth Logs alert" entry for `inngest_registry_empty` (its convention for every new logs alert).
- Amend ADR-100 Decision 1: the single stable `--sdk-url` is the public serve URL; private VIP superseded; options (a)
  and (b) recorded in Alternatives Considered with the ruling's reasons.

### C4 views

No C4 change in this PR, by CTO ruling F4. Checked against all three files (`model.c4`, `views.c4`, `spec.c4`): the
external actors and systems involved (Cloudflare, the dedicated Inngest host `inngest`, the web app `api`/`webapp`,
Better Stack, Hetzner) are already modelled; the `cloudflare -> webapp` edge says "HTTPS", which this PR makes true
to the origin, so it is not falsified; the `inngest -> api` edge's sentence about the private `--sdk-url` stays true
of the live host until the owner's replace and is updated, with `model.likec4.json`, in the FU-1 row-6 conversion PR.
No element, actor or access relationship is added. `plugins/soleur/test/c4-count-parity.test.sh` is run once to
confirm no embedded count moved (this PR adds a Better Stack alert, and `model.c4` edge prose may count alerts).

### Sequencing

ADR-100's amendment describes the declared target and states that the live host changes only at the owner's replace
(status note "adopting" on that sub-decision until FU-1 records the measurement).

## Guard Contract

### Guard 1 — adopted rule is the only app-host SSL rule, and it is strict

**Property.** No request to `app.soleur.ai` can be fetched from the origin in any mode other than `strict`, because
exactly one rule in `cloudflare_ruleset.seo_config_settings` sets `ssl` for that host and it sets `strict`.

**Assembly.** Every `rules` block inside the `seo_config_settings` resource body, comment-stripped
(`extractRuleBlocks(extractResourceBody(...))` in `seo-config-rules.test.ts`); the chokepoint is that one resource,
since Cloudflare allows one ruleset per zone and phase. A second chokepoint exists outside the file: a dashboard-added
rule. Neither this test nor the ADR-136 gate (pure creates only) nor the count-based destroy guard sees it; only the
Phase 0 and Phase 9 step 0 live reads (`rule_count` 5 and an unchanged `version` right before the merge) do.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | adopted rule `ssl = "flexible"` | RED |
| 2 | adopted rule expression back to `(http.host in {"app.soleur.ai" "lb-staging.soleur.ai"})` | RED |
| 3 | a SECOND rule appended after the compliant adopted rule: `ssl = "flexible"`, expression `(http.host eq "app.soleur.ai")` | RED |
| 4 | the adopted rule's `ref` changed or removed | RED |
| 5 | dispatch: the resource renamed so `extractResourceBody` finds nothing (0 rules) | RED (the exact-count row fails, never "0 checked, pass") |
| 6 | the canary rule block re-added, disabled | RED (exact count) |

**Harness rows:** (a) a suite edit that makes `allRuleBlocks()` return `[]` must RED through the exact-length row;
(b) must-PASS: the real tree; must-PASS variant: reordering the email-obfuscation and apex rules (order is no longer
load-bearing for the app host) stays GREEN.

**Anchor.** The pinned expression, ref and description constants live in the test, edited in the same diff as the
`.tf`; what must also move for a weakening to pass is the live entrypoint (Phase 9 re-read through the wrapper) and
a new T65 row that asserts the regenerated cleanup fixture's `after.rules` has length 3 and that the rule with ref
`dcb85b75bc3c4f4aa2a8c13a080bf854` carries `ssl = "strict"` and the new expression (the filter itself reads only
counts, so without this row the fixture would anchor nothing about strict mode). If the `jq` fallback built the
fixture, that row is author-written and anchors nothing extra; the live re-read is then the only outside anchor.

### Guard 2 — Guard 4 of exec-placement-forward (sdk_url is the public serve URL; the pin follows the volume)

**Property.** The declared `sdk_url` is exactly the registered serve URL, and the exec-host pin `10.0.1.10` is bound to
the workspaces-LUKS volume holder, not to the poll.

**Assembly.** `inngest-host.tf` `local.sdk_url`; `app/api/inngest/route.ts` `SERVE_HOST` + `servePath`;
`exec-placement.ts` `EXEC_HOST_PRIVATE_IP` and `EXEC_FORWARD_URL`; `variables.tf` web-1 `private_ip`; `network.tf`
`hcloud_server_network.web`; `workspaces-luks.tf` `hcloud_volume_attachment.workspaces_luks`; `ci-deploy.sh` /
`cloud-init.yml` `SOLEUR_HOST_PRIVATE_IP`; `package.json` dev default.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | `sdk_url` back to `http://10.0.1.10:3000/api/inngest` | RED |
| 2 | `sdk_url = "http://app.soleur.ai/api/inngest"` (scheme downgrade) | RED |
| 3 | `SERVE_HOST` changed to another origin while `sdk_url` stays | RED |
| 4 | dispatch: `sdk_url` line removed (regex finds nothing) | RED (the "must declare a literal sdk_url" row) |
| 5 | a second pin literal drifts after a compliant first: `package.json` dev default `SOLEUR_HOST_PRIVATE_IP` set to 10.0.1.11 while `exec-placement.ts` stays 10.0.1.10 | RED (existing dev-script row) |
| 6 | `workspaces_luks` attachment repointed to web-2 | RED (existing row kept) |

**Harness rows:** a suite edit that reads `inngest-host.tf` from a wrong path must RED (file-read row); must-PASS: the
real tree; must-PASS variant: whitespace changes around `=` in the `sdk_url` line stay GREEN.

**Anchor.** `SERVE_HOST` is runtime code shipped to production; a test-only edit cannot make the served
registration URL match a wrong `sdk_url`.

### Guard 3 — registry-empty alert drift guard (`inngest-registry-empty-alert.test.sh`)

**Property.** The alert fires exactly on dedicated probe rows that are serving, past the uptime floor, and whose
`registry_fns` is not a positive integer, from the probe's own emitter or its phone-home fallback, and it is
applied at merge.

**Assembly.** `local.inngest_registry_empty_sql`, `logtail_exploration.inngest_registry_empty`,
`logtail_exploration_alert.inngest_registry_empty` (thresholds, `query_period <= 900`, runbook metadata), the two
`-target=` lines in `apply-web-platform-infra.yml`, the runbook section it links, the emitter literals in
`inngest-bootstrap.sh` (tag `inngest-server-probe`, marker, `registry_fns=` and `uptime_s=` field names) and the
phone-home `shipper` / `stage` literals; the needles are derived from those sources, not retyped.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the negation (`match(... 'registry_fns=[1-9]...')` un-negated) | RED |
| 2 | drop the `SYSLOG_IDENTIFIER` emitter conjunct | RED |
| 3 | drop leg B (phone-home) after a compliant leg A | RED |
| 4 | remove one of the two `-target=` lines (a second after the first compliant one) | RED |
| 5 | dispatch: point the guard at a renamed resource so it extracts no SQL | RED (non-empty extraction floor) |
| 6 | rename the probe's `registry_fns=` field in the emitter only | RED (derived-needle row) |
| 7 | the SQL gains a reference to `local.inngest_luks_wrong_volume_alias` or any `hcloud_volume` address (a copied leg) | RED (no-volume-reference row, ADR-282) |

**Harness rows:** a suite edit that replaces the extraction with an empty string must RED; must-PASS: the real tree;
must-PASS variant: the SQL reformatted across lines (the resource collapses whitespace) stays GREEN.

**Anchor.** The live alert in Better Stack: Phase 3 step 1 records live counts (predicate 0, positive control > 0) and
the scheduled drift plan compares the applied resource with the file.

## User-Brand Impact

- **If this lands broken, the user experiences:** every request to `app.soleur.ai` failing with a Cloudflare 525/526
  page (a bad PUT or an order error), or, silently, their session cookies, prompts, agent output and BYOK key at
  submission crossing the public internet in plain HTTP if the host fell back to `flexible`; for the Inngest part,
  scheduled agent runs not starting after the owner's later replace.
- **If this leaks, the user's data is exposed via:** a Cloudflare-to-origin hop that is plain HTTP while the Privacy
  Policy says it is TLS (a false published claim), readable by an on-path attacker between Cloudflare and Hetzner.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's session token read in transit while the policy claims TLS is a
  breach-and-misstatement incident on its own, not an aggregate pattern, so the stricter tier applies (as for the
  2026-11-05 origin-TLS listener plan). `requires_cpo_signoff: true` is set; CPO sign-off is required before
  `soleur:work`, and `soleur:engineering:review:user-impact-reviewer` runs at review.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Close #10479 and #10538 together in one PR" [brief] | frontmatter `closes`, Phase 9, Split Assessment | mapped |
| 2 | "adopted rule ref dcb85b75 -> `ssl = \"strict\"`, expression `(http.host eq \"app.soleur.ai\")`, new description; delete the ORIGIN-TLS CANARY and ORIGIN-TLS STRICT rules and variables" [brief] | Phase 1.2 | mapped |
| 3 | "Update every pin" (seo-config-rules.test.ts, ssl-full-mitigation.test.sh, origin-tls-probe, destroy-guard test + fixtures, cloudflare-readonly.sh baseline B, cf-lb-overlay.yml staging-arm note, workflow/Doppler wiring) [brief] | Phase 1.1, 1.3 to 1.7; wiring: Research Reconciliation row 5, FU-3 | mapped |
| 4 | "The commit removing the rules must carry a line containing exactly `[ack-destroy]`" [brief] | Phase 1.9 | mapped |
| 5 | "Port 80 stays open" [brief] | Phase 6.1, FU-3 | mapped |
| 6 | "Rollback = forward PR to flexible; runbook origin-tls-strict-flip.md and origin-tls-canary.md updated, plus CLO's \"any return to flexible corrects the published wording the same day\"" [brief] | Phase 6.3, 6.4 | mapped |
| 7 | "inngest-host.tf sdk_url -> `https://app.soleur.ai/api/inngest`, keep --poll-interval 60" [brief] | Phase 2.2 | mapped |
| 8 | "update pins (exec-placement-forward.test.ts Guard 4 rewritten not deleted, exec-placement.ts, inngest*.test.sh that pin the URL, inngest-userdata-budget.sh, comments in inngest-bootstrap.sh / cloud-init-inngest.yml / resolve-origin.ts / function-registry-count.test.ts)" [brief] | Phase 2.1 to 2.5 | mapped (inngest-bootstrap.sh and cloud-init-inngest.yml comments descoped — justification: CTO ruling F2, carrier mint and user_data budget) |
| 9 | "verify this claim in apply-web-platform-infra.yml" [brief] | Research Reconciliation row 4, Phase 0.2, AC9 | mapped |
| 10 | "Add a Better Stack alert ... on SOLEUR_INNGEST_SERVER_PROBE registry_fns wrong/__UNREADABLE__ for 3 consecutive probes, with a runbook link" [brief] | Phase 3 | mapped (one probe instead of three — justification: CTO ruling F1, 900 s ceiling) |
| 11 | "convert connections[7] (CF->origin) to measured TLS" [brief] | Phase 4.1 | mapped |
| 12 | "connections[6] stays an exception: append the CLO's ... sentence and the reevaluate_when addition; do NOT set its expires_on" [brief] | Phase 4.2 | mapped |
| 13 | "plan a NEW follow-up issue ... and point row 6's tracking_issue at it" [brief] | Phase 7 FU-1, Phase 4.2 | mapped |
| 14 | "Legal wording per the CLO ruling ... mirrors ..., Last Updated lines, legal-doc-shas.ts re-pin, Article 30 register Superseded markers, DPA template reconcile, domains.md SSL Mode, GDPR policy grep" [brief] | Phase 5 | mapped |
| 15 | "a probe of web-1 and web-2 separately within 24 h before merge — plan HOW without SSH ...; if no per-host read path exists, say so explicitly" [brief] | Phase 8; Sharp Edges (no sanctioned per-host Cloudflare read in the wrapper) | mapped |
| 16 | "ADR-321 and ADR-100 amendments; runbook inngest-server.md" [brief] | Phase 6.1, 6.2, 6.5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0.1 rebase on #12733 | "this PR rebases after it — never edit #12733" | asked |
| Phase 0.3 live ruleset read | — | inferred — justification: the merge is a whole-list PUT; a dashboard edit since 06:50Z would be erased (learning 2026-07-20) |
| Phase 1 test rows and tombstones | asks 2–3 | asked |
| `cloudflare-readonly.test.sh` derivation change | asks 3 ("cloudflare-readonly.sh baseline B") | asked — the drift pin forces it |
| Phase 2 files | asks 7–8 | asked |
| `execution-placement.ts`, `workspaces-luks-verify.yml` comment edits | — | inferred — justification: both state the private poll URL or "web-1 only" as fact; leaving them makes the repo contradict the new `sdk_url` |
| Phase 3 alert + 7-step wiring | ask 10 | asked — the checklist is the file's enforcement contract |
| `inngest-registry-empty-alert.test.sh` | ask 10 | asked — step 7 of the checklist |
| Phase 4 | asks 11–13 | asked |
| Phase 5 incl. `nfr-register.md` | ask 14 | asked; `nfr-register.md` inferred — justification: it carries the same stale "target 2026-11-12" claim the absence grep covers |
| Phase 6 | asks 6, 16 | asked |
| FU-1 | ask 13 | asked |
| FU-3 housekeeping item (Doppler secrets) | — | inferred — justification: deleting the variables leaves two inert Doppler secrets; a deferral needs a tracking issue |
| FU-3 | ask 5 | asked — "closing it is a separate PR" (CTO ruling) needs a tracker once #10479 closes |
| FU-4 (conditional) | ask 15 | asked — CTO F3 fallback |
| Phase 8 | ask 15 | asked |
| Phase 9 | ask 1 ("the merge is the production write", ruling) | asked |

### Split Assessment

- Subsystems touched: 8 — `apps/web-platform/infra`, `apps/web-platform/{server,lib,test}`, `tests/scripts`,
  `plugins/soleur`, `scripts`, `docs/legal`, `.github/workflows`, `knowledge-base`
- Planned files: 42 | Estimated changed lines: about 900 (much of it comments, legal text and one fixture)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the operator asked for "together in one PR", and the CTO ruled that the rule removal,
  its pins and the wording ship as one acked merge; splitting the wording from the rule change would publish a claim
  ahead of, or behind, the live state.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `seo-config-rules.tf` holds exactly 3 rules; the rule with ref `dcb85b75bc3c4f4aa2a8c13a080bf854` has
      `ssl = "strict"`, `enabled = true`, expression `(http.host eq "app.soleur.ai")` and the new description; no rule
      sets `flexible` or `off`; no `ORIGIN-TLS` description and no `var.enable_origin_tls_` reference remain under
      `apps/web-platform/infra/`; both variables are gone from `variables.tf`.
- [ ] AC2 `npx vitest run test/seo-config-rules.test.ts` passes, and each Guard 1 mutation row was run once by hand
      and went RED (recorded in the PR body as row number + result).
- [ ] AC3 `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` passes with the regenerated cleanup fixture
      reading `0:2:0:2:1` (no ack) and `0:2:0:2:0` (acked), and the new T65 row asserts the fixture's `after.rules`
      length 3 with the dcb85b75 rule `strict` on the new expression.
- [ ] AC4 `ssl-full-mitigation.test.sh`, `origin-tls-probe.test.sh` (with `--canary` exiting 64) and
      `plugins/soleur/test/cloudflare-readonly.test.sh` pass; the wrapper header states `enabled_ssl_rules is 2`,
      `ssl=strict` and `rule_count is 3`.
- [ ] AC5 A commit on the branch carries a line that is exactly `[ack-destroy]`
      (`git log origin/main..HEAD --format=%B | grep -cx '\[ack-destroy\]'` prints at least 1).
- [ ] AC6 `inngest-host.tf` declares `sdk_url = "https://app.soleur.ai/api/inngest"`; `git grep -n '10\.0\.1\.10:3000/api/inngest' -- ':!knowledge-base' ':!scripts/encryption-posture-ledger.json' ':!apps/web-platform/lib/auth/resolve-origin.ts'`
      returns nothing (the ledger row 6 `connection`, ADR history, the C4 files, audits and the resolve-origin comment
      legitimately keep the live URL; `resolve-origin.test.ts` uses `10.0.1.10:3000` without the path as an input); `inngest-bootstrap.sh` and `cloud-init-inngest.yml` are unchanged
      (`git diff origin/main -- <both>` empty).
- [ ] AC7 `exec-placement-forward.test.ts` passes with Guard 4 rewritten (Guard 2 rows each run RED once by hand);
      `inngest-userdata-budget.sh` reports the same stored size as on `origin/main`.
- [ ] AC8 `betterstack-logs-alerts.tf` declares `logtail_exploration(_alert).inngest_registry_empty` with
      `query_period = 900`; both `-target=` lines are in the per-merge allowlist; the new drift guard, the ceiling test
      and the send-failed mutation test pass; the live `SELECT count()` reads (predicate, positive control, population)
      are recorded in the resource comment.
- [ ] AC9 The merge-apply grep is re-run at work time and still finds no `hcloud_server.inngest`,
      `hcloud_server_network.inngest` or `hcloud_volume_attachment.inngest_redis_luks` in the per-merge `-target` list.
- [ ] AC10 Ledger: `connections[7].in_transit.cert_verification == "on"`, no `exception`, `disclosed_as ==
      "docs/legal/privacy-policy.md:Encryption in transit"`; `connections[6]` keeps its exception with `expires_on`
      exactly as on `origin/main` after #12733, the appended sentence and `reevaluate_when` clause, and
      `tracking_issue` = FU-1; `python3 scripts/lint-encryption-posture.py --repo-root .` exits 0.
- [ ] AC11 Legal: the Privacy Policy Section 11 bullet and DPD 8.1(c) carry the CLO text, identical in the mirrors;
      Last Updated changed in all four files; `LEGAL_DOC_SHAS` matches `sha256sum` of both docs; the legal consistency,
      SHA, mirror-drift and register lints pass; the absence greps (after stripping notes) return nothing; every
      2026-10-29 #10479 Article 30 marker has a `Superseded <merge date> (#10479)` line under it.
- [ ] AC12 ADR-321 item 13 and the ADR-100 Decision 1 amendment exist; `origin-tls-strict-flip.md` has the forward-PR
      rollback, the owner-only break-glass and the same-day wording-correction step; `origin-tls-canary.md` is marked
      retired; `inngest-server.md` has the alert section and the public-poll replace section; no runbook step uses SSH.
- [ ] AC13 FU-1 and FU-3 exist (milestone "Post-MVP / Later", a `Mandated-By:` line); FU-1 states that its
      sync-evidence field must merge before the owner's replace; the PR body says `Closes #10479` and `Closes #10538`.
- [ ] AC14 The three F3 readings are recorded under `## Pre-merge evidence readings (F3)` in `decision-challenges.md` with UTC timestamps within 24 h before the
      merge, and the host-attributed reading shows web-1 and web-2 each healthy; otherwise the PR is not merged.
- [x] AC15 CPO sign-off is recorded before `soleur:work` starts (Domain Review, approved with conditions, 2026-11-13).
- [ ] AC17 `technical-ruling-gate.sh --branch feat-origin-tls-inngest-poll-10479-10538` (ship skill `scripts/`) passes.

### Post-merge (agent-verified, read-only)

- [ ] AC16 The push apply run passed its destroy guard with the ack and applied; `cloudflare-readonly.sh`
      reads `rule_count` 3 / `enabled_ssl_rules` 2 / ref dcb85b75 `ssl=strict`; 20 probes pass; the result is a
      comment on #10479.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** Carried forward from the CTO agent rulings of 2026-11-13 in `decision-challenges.md` (end state,
shipping, rollback, port 80, remedy (c), no flag, observability, ledger rows, overlap with #12733) plus the five
planning-time rulings (F1 to F4 and the stale-registry follow-up). Not re-spawned beyond the one batched planning
ruling, per the brief.

### Legal

**Status:** reviewed
**Assessment:** Carried forward from the CLO agent ruling of 2026-11-13 (`/var/tmp/oneshot-10479/clo-ruling.md`):
the lapse is recorded, not backdated; remedy (c) meets the 2026-10-18 conditions once hop 1 is measured and #10479 is
closed, and the live act may not precede that; the wording may be claimed at merge with the per-host probe recorded
within 24 h before merge and a re-measure after the apply; the full replacement text for Privacy Policy Section 11
and DPD 8.1(c) is used verbatim. GDPR gate (Phase 2.7, fired by the single-user-incident threshold): no regulated-data
schema, migration, auth or API surface is changed; the legal-text edits narrow a disclaimer to match measured state;
no new processing, processor or transfer (Cloudflare is already disclosed in Section 5.8).

### Product (CPO sign-off for the single-user-incident threshold)

**Status:** reviewed
**Assessment:** CPO sign-off (agent), 2026-11-13: approved with conditions. (1) Back the published "Since November
7, 2026" with a continuity reading (folded into Phase 8 step 4: the entrypoint's `last_updated` is the flip write).
(2) A return to `flexible` carries the corrected wording in the same diff, and a slipped merge date is fixed before
the merge (Phase 9 step 4, Sharp Edges). (3) The job-scheduler carve-out stays in every legal surface until FU-1
records the measurements, and the alert is not claimed until the apply shows it created (FU-1 item 6, Phase 9
step 5).

### Product/UX Gate

Not applicable: no UI surface in Files to Edit or Files to Create.

## Test Scenarios

1. Given the edited ruleset, when `seo-config-rules.test.ts` runs, then the adopted rule is the only app-host SSL rule
   and it is strict (Guard 1 matrix rows each RED when applied).
2. Given the regenerated cleanup plan, when replayed through the real destroy-guard filter with an empty message,
   then the guard refuses (`0:2:0:2:1`); with an `[ack-destroy]` line, it passes (`0:2:0:2:0`).
3. Given `origin-tls-probe.sh --canary`, then exit 64 and no request is sent; given `--require-tls` against a local
   TLS-header server, then exit 0.
4. Given `inngest-host.tf` with `sdk_url` reverted to the private URL, then Guard 4 is RED.
5. Given the alert SQL, when the live predicate is counted over 24 h, then 0; when the positive control is counted,
   then about 24 per day.
6. Given the ledger, when `lint-encryption-posture.py` runs, then exit 0 with row 7 `cert_verification on` and no
   exception, and row 6 unexpired.
7. Given the legal edits, when the consistency, SHA and register lints run, then all pass.
8. Given the merge, when the push apply runs, then the destroy guard reports `destroy_count` 2 acked and the
   post-merge wrapper read shows 3 rules with the adopted rule strict.

## Sharp Edges

- **No sanctioned per-host Cloudflare read exists in the repo today.** `cloudflare-readonly.sh` has no LB pool-health
  subcommand (its six are ssl-mode, config-entrypoint, pagerules-ssl, change-history and two analytics reads), pool
  health is read only inside `cf-lb-overlay.yml` write arms and in `scripts/followthroughs/ga-lb-pool-soak-6027.sh`
  (generic `CF_API_TOKEN`, which Class R forbids; aggregate output; coupled to a 7-day soak and an incident count),
  both origins serve at LB weight 1 with no host-identity response header, so a public probe cannot attribute a
  result to a host. The only host-attributed reading available is the Playwright snapshot of the Cloudflare LB pool
  page (Class R item 3), which depends on a logged-in wrapped profile. If it is unverified, the merge waits (AC14) and
  FU-4 builds the reader.
- The merge is a production write to every user's traffic path. Do not batch another `apps/web-platform/infra` PR
  with it; do not re-run the apply by dispatch (a dispatch has an empty head message and cannot ack the deletes).
- `[ack-destroy]` acks every destroy in the plan. Before marking ready, read the PR's `terraform plan` output in the
  plan-only CI run (if one runs) and confirm the only destroys are the two nested rule removals.
- Rebase after PR #12733. Its row-6 and row-7 text is the base for Phase 4; a conflict there is resolved by keeping
  #12733's text and appending this PR's sentences (row 6) or replacing the row (row 7).
- `<merge date>` in the legal notes and Article 30 markers must be the actual merge day. If the queue slips past
  midnight UTC, fix the date (and re-pin `LEGAL_DOC_SHAS`) before the merge lands; never in a follow-up commit
  (CPO condition 2).
- The Inngest alert does not see a stale non-zero registry. FU-1 must merge before the owner's replace.
- A refused alert create (free-tier cap, unmeasured) turns the apply red after the ruleset write; read the ruleset
  state first, then fix the alert in a forward PR.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6. It is filled here.

## Non-Goals

- Closing port 80, Authenticated Origin Pulls (FU-3).
- The owner's `inngest-host-replace`, hop-1 measurement, row-6 and C4 conversion (FU-1).
- Deleting the two inert Doppler secrets (FU-3).
- Any edit to PR #12733 or its audit record.
