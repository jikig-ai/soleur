---
title: "fix(infra): import the app.soleur.ai/health Better Stack monitor as a database-readiness keyword alarm, and reconcile live Better Stack inventory against Terraform"
date: 2026-09-15
slug: fix-health-monitor-supabase-keyword-import
branch: feat-one-shot-7884-health-monitor-supabase-keyword
issue: 7884
closes: none
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
pr: 8216
lane: cross-domain
---

# fix(infra): database-readiness keyword alarm on /health + live Better Stack inventory reconcile

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-15
**Sections enhanced:** Overview, Research Insights, Hypotheses, Technical Approach, Implementation Phases, Observability, Architecture Decision, Guard Contract, Acceptance Criteria, Risks
**Agents used (deepen pass):** framework-docs-researcher (Terraform v1.10.5 import source), security-sentinel, test-design-reviewer, observability-coverage-reviewer, a verify-the-negative + post-edit self-audit sweep. Earlier plan-time panel: repo-research-analyst ×2, learnings-researcher, framework-docs-researcher, functional-discovery, CTO ×2, terraform-architect, spec-flow-analyzer ×2, architecture-strategist, DHH, Kieran, code-simplicity, CPO, scoped advisor consult.

### Key Improvements

1. **H-F resolved from Terraform source.** v1.10.5 `expandResourceImports` skips an import only when the address is in the (refreshed) state, so after a vendor-side deletion the gated import is re-attempted against a missing object and the plan most likely aborts. The import block therefore gets a tracked removal once adoption is verified, and the gate variable is the interim off-switch.
2. **Marker grammar hardened against vendor text.** All vendor-sourced fields (`url`, `name`, `detail`) now come last and quoted, ids must be numeric, invisible/bidi characters are stripped, fields are capped at 200 chars, and the workflow extracts routing tokens only from the machine prefix. Per-arm host+path pin, page cap and seen-URL set added.
3. **Escalation and issue routing are tested.** A small workflow-body suite (python `yaml.safe_load` + `gh` stub, precedent `plugins/soleur/test/token-drift-workflow-causes.test.sh`) covers the fail-closed lookup, the whole-token escalation key and the `infra-drift` label. Subject precedence and keyless-marker escalation are decided.
4. **Guard 1 can no longer be satisfied by a silent downgrade.** The expected branch is a constant set from the Phase 0.2 result, not read from the declaration.
5. **Probe script is specified to the repo's credential rules** (write token, `--disable --noproxy '*'`, header on stdin, xtrace refusal, unique run-id name, sweep re-checks each object before deleting).
6. **Observability layer citations added**, plus the apply-failure mode (`notify-apply-failure` job) and the rc-1 masking fix (the issue step also runs when rc 1 carries MISMATCH markers).

### New Considerations Discovered

- PR #8215 merged during planning; the post-mortem is on `origin/main` and its #7884 action-item row is updated by this PR.
- A persistent 429 on the monitors arm silently suspends disarm detection (rc 0, check-in ok); recorded as a residual.

## Overview

Better Stack monitor `4226366` (`https://app.soleur.ai/health`) was created by hand on
2026-03-28 and is declared in no Terraform root. It is a `status` monitor, and `/health`
answers HTTP 200 whatever the database state, so during the 2026-09-15 prd Supabase
outage (14:16Z-15:45Z, ~89 min) it stayed green and nothing paged.

This plan does three things, in dependency order:

1. **Import + keyword.** Declare the monitor as `betteruptime_monitor.app_health` in
   `apps/web-platform/infra/uptime-alerts.tf`, adopt the live object through a gated
   declarative `import {}` block (the `seo-config-rules.tf` precedent, including its
   `for_each` off-switch), add its `-target=` line to the per-merge apply, and change it in
   the SAME apply from `status` to `keyword` with `required_keyword = "\"supabase\":\"connected\""`.
   `/health` keeps returning 200. A pre-merge vendor probe gates the keyword half (Phase 0.2).
2. **Live inventory reconcile.** Extend the existing twice-daily source-vs-live Better Stack
   reconcile (`plugins/soleur/scripts/reconcile-live-heartbeats.ts`, job
   `heartbeat-live-reconcile` in `scheduled-terraform-drift.yml`) with a monitors arm and an
   `unmanaged-live` class for monitors AND heartbeats, reported through the existing mismatch
   issue (now also labeled `infra-drift` when an unmanaged object is present) plus email, and a
   measured live object count every run. It also fixes a pre-existing defect the new arm would
   otherwise inherit: templated `for_each` heartbeat names never match live, so the reconcile
   has reported two false `absent-live` rows every run since July (#6645, #8140).
3. **Record it.** Rewrite the `uptime-alerts.tf` quota header and #7884 bullet, resolve
   ADR-204's Residual gap, add ADR-222 (provisional ordinal), amend ADR-117 for the exact
   `for_each` resolution, add a forward pointer in ADR-149, update the C4 model, and add a
   runbook for the new alarm.

The operator decisions of 2026-09-15 (import + keyword; live-vs-declared guard; docs) set the
direction of this plan and are not re-litigated. Plan review suggested splitting the reconcile
into a second PR; that changes the operator's stated scope for this PR and is recorded in
`knowledge-base/project/specs/feat-one-shot-7884-health-monitor-supabase-keyword/decision-challenges.md`
rather than applied.

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask | Reality (measured) | Plan response |
|---|---|---|
| "ADR-149 and uptime-alerts.tf disagree on whether heartbeats pool against the 10-object cap" | Confirmed. ADR-149 (Alternatives row "Target the heartbeat too", reason (c)) reads "a vendor-page reading of a single shared pool of ten"; the `uptime-alerts.tf` header says heartbeats "are NOT pooled". The pricing page reads "10 monitors & heartbeats". Live on 2026-09-15: **4 monitors + 9 heartbeats = 13 objects**. | Neither reading is asserted. The reconcile prints `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=<n> heartbeats=<n> total=<n>` every run; the tf header, ADR-222 and a one-line ADR-149 pointer cite the marker, not a cap. |
| "#5566 guard (terraform-target-parity.test.ts) must cover the new resource" | The #5566 test extracts EVERY `resource "<type>" "<name>"` in comment-stripped `apps/web-platform/infra/*.tf` and requires a `-target=` in the non-dispatch apply job or an `OPERATOR_APPLIED_EXCLUSIONS` entry. Learning `2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md` predates that widening and is stale on this point. | Adding `-target=betteruptime_monitor.app_health` satisfies it with no test edit. An AC runs the test. |
| "infra/www-apex-canonicalizer.test.sh pins attributes" | Path is `apps/web-platform/infra/www-apex-canonicalizer.test.sh`; it brace-extracts only `betteruptime_monitor.soleur_www_redirect`. | No edit; run it and its `-mutation` battery as regression gates. |
| "Find the scheduled drift workflow" | `scheduled-terraform-drift.yml` (Inngest-dispatched `workflow_dispatch`, 06:00/18:00 UTC). Its `heartbeat-live-reconcile` job already reads Better Stack with `BETTERSTACK_API_TOKEN_READONLY`, files `heartbeat-reconcile-mismatch` issues, emails via Resend and checks in to Sentry monitor `scheduled-heartbeat-reconcile`. | Extend that job and its one issue family; no new job, workflow or issue family. |
| "Flag any id not in the Terraform state/declarations" | The reconcile job has no tfstate access. Its join key today is the declared `name`. | Declarations. Monitors match on declared literal `url`; heartbeats on declared `name` with `for_each`/`count` resolved from literal variable defaults. Live ids ride in every marker. |
| Import mechanism "e.g. #6606" | #6606 (Sentry uptime monitor 1422253) is OPEN and unimplemented; the Sentry root is full-root. The applied in-repo precedent for this `-target`-scoped root is `import {}` in `seo-config-rules.tf` (#6746), gated by `var.adopt_seo_config_entrypoint` because `mock_provider` does not mock `import` blocks and the credential-free `terraform test` leg (`tests/web-hosts-eu-pin.tftest.hcl`, run by `infra-validation.yml`) would otherwise read the real provider and fail. That ungated-by-default block has coexisted with the dispatch jobs' different `-target` sets since July. | Gated `import {}` with a new bool default `true`, set `false` in the tftest. #6606 is related, not a duplicate. |
| Keyword attribute names; in-place vs replace | Provider `BetterStackHQ/better-uptime` pinned `0.20.17`: `monitor_type = "keyword"`, `required_keyword` (string). `resource_monitor.go` at tag v0.20.17 has **zero** `ForceNew`; `monitorUpdate` PATCHes `/api/v2/monitors/<id>` with changed fields only; importer is passthrough. Vendor doc "Update an existing monitor" lists `monitor_type` as updatable. | In-place `~ update` on the imported id. Phase 0.3 requires `Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.` and no `-/+`; any other reading stops Phase 1. |

## Research Insights

### Premise Validation (Phase 0.6)

- #7884: OPEN, labels `priority/p1-high`, `infra-drift`, milestone `Post-MVP / Later`; not closed by any PR.
- #6606: OPEN (Sentry analogue). #8215: was OPEN at plan start and **MERGED during the deepen pass** (commit `8749d4f06` on `origin/main`); it adds `knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md`, whose Action Items table carries a `#7884 … open` row and whose 5-Whys say "Another occurrence now pages once #7884 lands". This branch predates the merge, so /work starts by merging `origin/main`; this plan creates no post-mortem file and only updates that row's status (Phase 3.8).
- The post-mortem timeline (read from the PR branch) verifies the load-bearing premise: during the outage `/health` returned `status: ok` with **`supabase: error`** (15:33Z, 4 reads); recovery read `supabase: connected` (15:45:16Z). A keyword monitor on `"supabase":"connected"` would have failed from the first check after 14:16Z. One flap at 15:44:44Z (`supabase: error` once) is the blip class `confirmation_period` absorbs.
- `apps/web-platform/server/index.ts` `/health` branch: `res.writeHead(200, …); res.end(JSON.stringify(health))` — always 200, compact JSON. `server/health.ts` `buildHealthResponse`: `status: "ok"` hardcoded; `supabase: supabaseOk ? "connected" : "error"`; `checkSupabase` = GET `${serverUrl()}/rest/v1/users?select=id&limit=1` with the service-role key and `AbortSignal.timeout(2000)`; catch → false.
- Live body: `{"status":"ok","version":"0.274.4","build_sha":"2ff3e159…","supabase":"connected","sentry":"configured","uptime":3245,"memory":237}`; `cf-cache-status: DYNAMIC`.
- Live monitor 4226366 (READONLY token): `monitor_type status`, `check_frequency 180`, `request_timeout 30`, `confirmation_period 0`, `recovery_period 180`, `follow_redirects true`, `remember_cookies true`, `verify_ssl true`, `http_method get`, `regions [eu,us,as,au]`, `email true`, `call/sms/push false`, `critical_alert false`, `required_keyword null`, `policy_id null`, `expiration_policy_id null`, `team_name "Your team"`, `paused false`, `status up`, `updated_at 2026-09-09T17:00:34Z`.
- Live monitor URLs are byte-identical to the declared literals for the three managed monitors: `4422675 https://soleur.ai/`, `4638251 https://app.soleur.ai/`, `4904867 https://www.soleur.ai/`; plus `4226366 https://app.soleur.ai/health`. Declared monitor URLs are unique; `github_webhook_failures` (`https://soleur.ai/api/webhooks/github`) is `count = var.betterstack_paid_tier ? 1 : 0`, default `false`.
- `web-platform-release.yml` deploy verification parses `/health` with `jq -r '.supabase // empty'` and requires `connected`; unaffected.
- `var.web_hosts` has a literal default map (keys `web-1`, `web-2`; values are nested objects; `validation {}` blocks follow). No `TF_VAR_web_hosts`/`WEB_HOSTS` in Doppler `prd_terraform`; the apply job passes only `-var=ssh_key_path=…`.
- Existing reconcile run locally, read-only, 2026-09-15 (rc=2): `name=soleur-git-data-prd reason=absent-live` (real, owned by #6548); `name=soleur-web-zot-consumer-${each.key} reason=absent-live` and `name=soleur-web-nic-guard-${each.key} reason=absent-live` (**false** — live has `-web-1`/`-web-2`). Open mismatch issues #6645 (124 comments) and #8140 (same title, 2026-09-14 06:00Z: the lookup is fail-open, so a failing `gh issue list` leaves `EXISTING` empty and creates a duplicate).
- The existing escalation compares `grep -oE 'name=[^ ]+'` tokens with `grep -qF` against issue history; a name with spaces truncates and substring-matches older rows.
- `plugins/soleur/test/heartbeat-live-reconcile.test.ts` pins request URLs: the "no logtail_exploration_alert declared" case asserts `seen` equals exactly `["https://uptime.betterstack.com/api/v2/heartbeats"]` (the monitors arm changes that expectation); the redirect-refusal case asserts the initial heartbeats URL (unchanged if no query string is added).
- Web-platform drift plan noise: six `infra: drift detected in web-platform` issues in ~7 weeks (#7099, #7144, #7316, #7667, #7904, #8179), each auto-closed by `apply-deploy-pipeline-fix.yml` after an apply.
- Telemetry alerts live: `soleur-monitor-send-failed-prd` (declared) and `Output utilization high` (id 2536305877, paused, undeclared). Outside this plan's monitors+heartbeats scope; filed in Phase 4.
- Consumers of the reconcile's prose or markers found outside Files to Edit: `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md` (quotes the logs_alert MISMATCH prefix, which stays intact), `ADR-141`, `apps/web-platform/infra/sentry/cron-monitors.tf` and `function-registry-count.test.ts` (describe the job as heartbeat reconcile). `scripts/regenerate-c4-model.sh` exists and `plugins/soleur/test/c4-model-freshness.test.sh` fails on a stale `model.likec4.json`.
- Active roadmap milestone: `Phase 4: Validate + Scale`.
- Latest ADR ordinal across all `origin/*` refs: ADR-221 (a pushed branch); ADR-222 is provisional.

### Property List (Phase 0.6b)

- **P1** A prd database outage — the `/health` body not containing a connected Supabase check — opens a Better Stack incident that emails the existing recipients within ~6 min.
- **P2** `/health` keeps returning HTTP 200 in every database state.
- **P3** Monitor 4226366 is converged by the per-merge apply — declared, `-target`ed, visible to the #5566 guard — and keeps its id and history.
- **P4** A live Better Stack monitor or heartbeat that no Terraform declaration accounts for self-reports as an issue labeled `infra-drift` plus email within one drift cycle (≤12 h), with no SSH.
- **P5** Live object counts are measured from the API and printed every run; no cap is assumed.
- **P6** (plan-added) A declared monitor whose live `monitor_type`, `required_keyword` or `paused` differs from its declaration is reported, so the database alarm cannot be silently disarmed between infra merges. Justified by the drift-plan noise above; it reads fields the list response already returns.

### Cut List (Phase 0.6b and plan review)

- `/health` returns 503 on database failure → breaks P2.
- A new inventory script, job, workflow or second issue family → P4/P5 are bought by extending the existing reconcile, its issue and its email.
- tfstate-based id matching → literal URL (monitors) and resolved name (heartbeats) are stable join keys.
- `lifecycle.ignore_changes` on the imported monitor → config owns every declared attribute.
- A `betteruptime_policy` for this alarm → free tier; same email path as siblings.
- A C4 count-parity clause → no Better Stack counts are embedded in `model.c4`.
- Regex expansion of `${…}` → exact resolution from literal variable defaults; anything else fails closed.
- `duplicate-live` and `monitor-absent-live` classes → folded into `unmanaged-live` (with `dup=url`) and the existing `absent-live`.
- `git ls-files` census of declarations outside the infra dir → zero exist; no property needs it.
- `has_unmanaged`/`uptime_clean` outputs, a separate unmanaged issue step and a close-on-clean step → the existing issue step routes all rows. (Deepen pass kept one output, `has_mismatch`, so an arm ERROR cannot hide mismatch rows, and reinstated a narrow issue-step test over the extracted `run:` body — the escalation key is the defect class behind #8140 and a precedent harness exists.)
- Import-id and gate-default mutation rows in Guard 1 → the adoption is one-time; Phase 0.3 and `terraform test` cover it.
- Consecutive-UNREACHABLE escalation → existing contract (no page on vendor 5xx) stays.
- A comment on #6606 → no property.

### Value-proposition measurement (Phase 0.6c)

Not a cost/performance plan. The value is detection time: ~60 min to the first human signal and ~81 min to diagnosis on 2026-09-15, against P1's ~6 min bound.

### Relevant file paths

- `apps/web-platform/infra/uptime-alerts.tf`; `apps/web-platform/infra/seo-config-rules.tf` (gated `import {}`); `apps/web-platform/infra/variables.tf` (`variable "adopt_seo_config_entrypoint"` comment; `variable "web_hosts"`; `variable "betterstack_paid_tier"`); `apps/web-platform/infra/tests/web-hosts-eu-pin.tftest.hcl`; `apps/web-platform/test/seo-config-rules.test.ts`
- `.github/workflows/apply-web-platform-infra.yml` (`-target=betteruptime_monitor.soleur_www_redirect \` in the per-merge `apply` job); `.github/workflows/infra-validation.yml` (`fmt`, `validate`, `terraform test`)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `.github/workflows/scheduled-terraform-drift.yml` (`heartbeat-live-reconcile:` job)
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts`; `plugins/soleur/lib/heartbeat-live-reconcile.ts`; `plugins/soleur/test/heartbeat-live-reconcile.test.ts`
- `apps/web-platform/server/health.ts`; `apps/web-platform/server/index.ts`; `apps/web-platform/test/server/health-supabase.test.ts`
- ADR-204, ADR-117 (`### Amendment (2026-07-17, #6549 item 2)`), ADR-149, ADR-218 (§5 records its own arm)
- `knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md`; `knowledge-base/engineering/architecture/diagrams/model.c4`; `scripts/regenerate-c4-model.sh`

### Institutional learnings applied

- `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` — guard-suite list derived by grep: parity test, canonicalizer, destroy-guard filter, tftest; only the tftest needs an edit.
- `security-issues/2026-07-23-new-tf-resource-in-target-scoped-apply-root-and-unprotected-env-autocreate.md` — no `-target=` line, no apply.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` — prove the keyword can fire (negative probe).
- `best-practices/2026-07-17-derive-replicated-literal-and-nonvacuous-drift-guard.md` — the contract test reads the keyword from the `.tf`.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`, `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — dispatch and harness rows.
- `best-practices/2026-05-29-uptime-monitor-fuse-must-tolerate-self-inflicted-deploy-windows.md` — vendor timer, not pause/resume.

### External references

- Provider source `https://raw.githubusercontent.com/BetterStackHQ/terraform-provider-better-uptime/v0.20.17/internal/provider/resource_monitor.go`: no `ForceNew`; `team_name` DiffSuppress once an id exists; `regions`, `remember_cookies`, `confirmation_period`, `critical_alert`, `ssl_expiration`, `domain_expiration`, `maintenance_days` Optional+Computed; `http_method` default GET, case-insensitive suppress; `expiration_policy_id` has no `omitempty`, so every PATCH sends `null` (live is null).
- `https://betterstack.com/docs/uptime/keyword-monitor/`: "look for a specified keyword or phrase in the page response. The keyword lookup is case-insensitive."
- `https://betterstack.com/docs/uptime/api/update-an-existing-monitor/`: `monitor_type` updatable.
- `https://betterstack.com/docs/uptime/api/create-a-new-monitor/`: HTTP `request_timeout` 2,3,5,10,15,30,45,60 s; `confirmation_period` max 86400.
- `https://betterstack.com/docs/uptime/api/pagination/`: `pagination.next`.
- `https://developer.hashicorp.com/terraform/language/import`: import blocks are idempotent once the address is in state.

### Functional overlap (Phase 1.5b)

No community skill or agent covers the combination; build in-repo.

### Conventions

Terraform only (`hr-all-infrastructure-provisioning-servers`); no SSH (`hr-no-ssh-fallback-in-runbooks`); workflow-filed issues carry a milestone; `cq-union-widening-grep-three-patterns` for the violation-type change; `cq-assert-anchor-not-bare-token` for contract assertions; production writes need explicit authorization (`hr-menu-option-ack-not-prod-write-auth`).

## Hypotheses

The feature text matched the network-outage trigger ("unreachable", "timeout"). The path this plan changes is Better Stack probe → Cloudflare edge → app → Supabase REST; no host firewall or SSH is on it. L3→L7 first:

1. **L3 firewall allow-list** — opt-out with artifact: the probe terminates at Cloudflare anycast (`dig +short app.soleur.ai` → `104.26.11.163`, `104.26.10.163`, `172.67.73.132`), and the existing monitor on the same URL reads `status up` (API above), so no allow-list sits between the vendor and the edge.
2. **L3 DNS/routing** — verified: the three Cloudflare addresses; three consecutive `curl` reads returned `200` in 0.30-0.38 s.
3. **L7 TLS/proxy** — verified: `curl -sIv https://app.soleur.ai/health` → TLS 1.3, certificate verified, `HTTP/2 200`, `server: cloudflare`, `content-type: application/json`, `cf-cache-status: DYNAMIC`.
4. **L7 application** — verified from code and the post-mortem timeline: the body flips `connected`→`error` on a failed or >2 s REST check while the status stays 200.

| # | Hypothesis | Evidence | Status |
|---|---|---|---|
| H-A | Better Stack's keyword check matches the quoted compact-JSON substring in the raw body | Docs: "phrase in the page response", case-insensitive; nothing on JSON or quotes | UNKNOWN — Phase 0.2 |
| H-B | status→keyword is an in-place PATCH that keeps id 4226366 | Provider: no `ForceNew`; vendor doc lists `monitor_type` updatable | Expected; confirmed by Phase 0.3 and the post-apply GET |
| H-C | The workspace accepts a `keyword` monitor | #7798 measured `expected_status_code` only; 13 live objects against a "10" pricing reading | UNKNOWN — Phase 0.2. A quota refusal does NOT answer H-C |
| H-D | The keyword monitor also fails when the app is down / 5xx / timing out | A Cloudflare 52x page, a timeout or a TLS failure yields no body containing the phrase | Holds by construction for this endpoint |
| H-E | A single 2 s check timeout would page without a confirmation window | `checkSupabase` timeout; 15:44:44Z single-read flap | Mitigated by `confirmation_period = 180` |
| H-F | After a vendor-side deletion of 4226366, the gated import block aborts the plan (vs. a quiet `+ create`) | Terraform v1.10.5 `internal/terraform/node_resource_plan.go` `expandResourceImports` removes an import only `if state.ResourceInstance(el.Key) != nil` ("skipping import address … already in state"); refresh drops a 404'd object (`monitorRead` → `SetId("")`), so the import is re-attempted and the passthrough importer's read of a missing id yields an import error | LIKELY abort (source-derived, not measured). Mitigations: reconcile reports `absent-live` first; gate variable is the off-switch; the import block and variable are removed by a tracked follow-up once AC17 passes |

### Network-Outage Deep-Dive (deepen-plan 4.5)

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | Opt-out with artifact | The probe path terminates at Cloudflare anycast (three CF addresses from `dig`); the existing monitor on the URL reads `status up` via the API. No host firewall or SSH provisioner is on any resource this plan applies (`betteruptime_monitor` has no `connection`/`provisioner`). |
| L3 DNS/routing | Verified | `dig +short app.soleur.ai` → 104.26.11.163, 104.26.10.163, 172.67.73.132; three `curl` reads 200 in 0.30-0.38 s. |
| L7 TLS/proxy | Verified | `curl -sIv` → TLS 1.3, cert verified, `server: cloudflare`, `cf-cache-status: DYNAMIC`. |
| L7 application | Verified | `health.ts`/`index.ts` code read; post-mortem timeline shows `supabase: error` with status 200 during the outage. |

No gaps before implementation.

## Technical Approach

### Monitor declaration (uptime-alerts.tf, variables.tf, tftest)

```hcl
# apps/web-platform/infra/uptime-alerts.tf  (sketch — /work writes the final comments)
import {
  for_each = var.adopt_app_health_monitor ? toset(["adopt"]) : toset([])
  to       = betteruptime_monitor.app_health
  id       = "4226366"
}

resource "betteruptime_monitor" "app_health" {
  monitor_type       = "keyword"
  url                = "https://app.soleur.ai/health"
  pronounceable_name = "soleur app database readiness"

  # Compact JSON, exactly as server/index.ts serializes buildHealthResponse().
  required_keyword = "\"supabase\":\"connected\""

  check_frequency     = 180
  request_timeout     = 10
  confirmation_period = 180
  recovery_period     = 180
  follow_redirects    = true

  email = true
  call  = false
  sms   = false
  push  = false

  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null

  verify_ssl = true
  paused     = false
}
```

```hcl
# apps/web-platform/infra/variables.tf
variable "adopt_app_health_monitor" {
  type    = bool
  default = true
}
```

`tests/web-hosts-eu-pin.tftest.hcl` sets `adopt_app_health_monitor = false` beside `adopt_seo_config_entrypoint = false`. The variable comment says why the gate exists (mock_provider does not mock imports) and what `false` means: before adoption it plans a CREATE of a second monitor on the same URL (reported by the reconcile as `unmanaged-live dup=url`); after adoption the import is already skipped and `false` changes nothing.

Value choices, each stated in the block comment:

- `confirmation_period = 180` (live 0): one more failing check must follow the first. Worst case ≈ 180 s to observe + 180 s confirmation ≈ 6 min.
- `recovery_period = 180` (kept): at least one cadence, so an intermittently failing database is not dismissed on every green check.
- `request_timeout = 10` (live 30): sibling convention; `/health` is bounded by the 2 s REST timeout.
- `pronounceable_name` renamed from `app.soleur.ai/health` so the inbox subject names the failure. The reconcile matches monitors by URL, so the rename never reads as unmanaged.
- Attributes omitted (`remember_cookies`, `regions`, `http_method`, `critical_alert`, `ssl_expiration`, `domain_expiration`, `maintenance_days`) are Optional+Computed or default-suppressed; live values produce no diff.
- Paging is email only, like every sibling (`call`/`sms`/`push` false). Detection time therefore includes reading the inbox; ADR-222 states it.

### Apply path

Merge → `apply-web-platform-infra.yml` (push, `paths: apps/web-platform/infra/**`) → targeted plan including `-target=betteruptime_monitor.app_health` → `1 to import, 0 to add, 1 to change, 0 to destroy` → apply. The destroy guard scores no `betteruptime_*` action. A refused PATCH would fail the whole `apply` step on that run and on every later infra merge (the `~ update` re-plans each time), skipping the job's later implicit-`success()` steps (token sync, SSH bridge, bridge apply) — which is why Phase 0.2 is a merge gate. Such a failure is not silent: the workflow's `notify-apply-failure` job (`needs: [preflight, apply]`, `always()`) emails ops through `notify-ops-email` on every non-green push run, naming the failing step.

### Live inventory reconcile (lib + script + workflow)

`plugins/soleur/lib/heartbeat-live-reconcile.ts`:

- **Declarations resolve exactly.** New `resolveInfraVariables(infraDir)` brace-extracts each `variable "<X>" { default = … }` in the infra dir and returns top-level map keys for a literal map default and the value for a literal bool default (nested object values and trailing `validation {}` blocks are skipped by brace depth). `parseHeartbeatBlocks` and new `parseMonitorBlocks` use it:
  - `for_each = var.<X>` with a map default → one declared instance per key; `${each.key}` in `name` is substituted. Any other interpolation, `for_each` over a non-variable, or a variable without a literal map default → `UnresolvableDeclaration`.
  - `count = var.<X> ? 1 : 0` with a bool default → 1 or 0 instances. Any other `count` shape → `UnresolvableDeclaration`.
  - Monitor `url` must be a literal string; otherwise `UnresolvableDeclaration`. Two declared instances with the same URL → `UnresolvableDeclaration` (ambiguous).
- **Violation type becomes a discriminated union** (`kind: "heartbeat" | "logs_alert" | "monitor" | "unmanaged"`) instead of widening optional fields; `reconcileHeartbeats`' existing kinds keep their shape.
- `reconcileHeartbeats` iterates concrete names (fixing the `${each.key}` false `absent-live`; a templated fed row reports `fed-but-paused` per concrete name). An instance resolved to 0 by `count` is not expected live (the existing count-gated carve-out, now evaluated rather than assumed).
- New `reconcileMonitors(declared, live)`:
  - `absent-live` (existing reason, monitor kind) — a declared instance with no live monitor on its URL.
  - `monitor-config-drift` — exactly one live monitor on a declared URL whose `monitorType`, `requiredKeyword` or `paused` differs; `null` and `""` keywords compare equal; one row per field.
  - `unmanaged-live` — a live monitor whose URL matches no declared instance, or every live monitor on a URL that has ≥2 (`dup=url`; none picked as managed).
- New `findUnmanagedHeartbeats(declared, live)`: `unmanaged-live` per live heartbeat whose name is no declared instance's name, or every one of ≥2 sharing a name (`dup=name`).
- `ViolationReason` gains `"unmanaged-live" | "monitor-config-drift"`.

`plugins/soleur/scripts/reconcile-live-heartbeats.ts`:

- `fetchPaged`'s `mapAttrs` receives the row `id`. On the monitors and heartbeats arms a row whose `id` is not `^[0-9]+$`, or (monitors) whose `url` is not a string, is `error` (rc 1, never skipped).
- `MONITORS_URL = https://uptime.betterstack.com/api/v2/monitors`; no query string (pagination follows `pagination.next`). The monitors arm always runs; heartbeats unmanaged detection runs inside the heartbeats arm.
- **Pagination pin per arm.** `isAllowedUrlFor` additionally requires `parsed.port === ""` and a pathname equal to that arm's `/api/v2/monitors` or `/api/v2/heartbeats`, so a `pagination.next` cannot switch endpoints. `fetchPaged` keeps a seen-URL set and a 50-page cap; a repeated URL or the cap → `error` (rc 1).
- `UnresolvableDeclaration` → `SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=unresolvable-declaration resource=<type.name>` (rc 1).
- All arms print their markers before codes combine (ERROR 1 > MISMATCH 2 > OK 0); header comment updated.
- **Vendor-text sanitization.** `oneLine`'s class gains `​-‏‪-‮⁦-⁩﻿` (escapes only, `cq-regex-unicode-separators-escape-only`); each vendor field is capped at 200 chars; inside quoted fields `"` is percent-encoded as `%22` (not stripped, so `required_keyword` drift stays legible).
- **Marker grammar.** One `surface=` spelling per arm (`heartbeats`, `logs_alert`, `monitors`). Machine fields first; every vendor-sourced field (`url`, `name`, `detail`) last and double-quoted. Routing tokens (`reason=`, `resource=[a-z_]+\.[a-z0-9_]+`, `id=[0-9]+`, `surface=`) are read only from the text before the first `"`:
  - existing heartbeat rows, unchanged prefix, one machine field appended before nothing vendor-sourced (the name there is our `.tf` literal): `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<n> live=absent|paused reason=absent-live|fed-but-paused resource=<type.name>`
  - existing logs_alert rows: prefix unchanged; `resource=<type.name>` inserted immediately before `detail="…"` so the vendor text stays last
  - `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=heartbeats reason=unmanaged-live id=<id> [dup=name] name="<n>"`
  - `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=<id> [dup=url] url="<url>" name="<n>"`
  - `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=<type.name> url="<url>"`
  - `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=<id> resource=<type.name> field=<f> detail="declared=<v> live=<v>"`
  - `SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=<n> live=<n> matched=<id,id,…>`
  - `SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=monitors detail="<d>"` / `SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=<kind> detail="<d>"`
  - `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=<n> heartbeats=<n> total=<n>` — only when both uptime reads succeeded.
  - Invariant (tested): every MISMATCH line carries exactly one `resource=` or `id=` routing token before its first `"`.

`.github/workflows/scheduled-terraform-drift.yml`, `heartbeat-live-reconcile` job (existing steps, no new steps):

- The reconcile step writes one more output, `has_mismatch` (`true` when any line matches `^SOLEUR_HEARTBEAT_RECONCILE_MISMATCH `). The label and issue steps gate on `rc == '2' || (rc == '1' && has_mismatch == 'true')`, so an arm ERROR in the same run no longer hides real mismatch rows from the issue.
- "Create or update reconcile issue": the existing-issue lookup runs under `set -euo pipefail`, so a failing `gh issue list` fails the step instead of creating a duplicate. Escalation keys are the `resource=…`/`id=…` tokens taken from each MISMATCH line's pre-quote prefix and compared as whole tokens (`grep -qE "(^|[[:space:]])${key}([[:space:]]|\$)"`) against the issue history; a MISMATCH line with no key escalates (fail safe). The decode list gains `unmanaged-live` and `monitor-config-drift`. When any `reason=unmanaged-live` routing token is present the step runs `gh issue edit <n> --add-label infra-drift` (new issues are created with both labels). The fenced markers are introduced as "untrusted vendor data". Body next steps for an unmanaged object: have an agent adopt it (`/soleur:one-shot` on the issue — declare it with an `import {}` block + resource + `-target=` line, the #7884 pattern) or delete it if abandoned; either path first re-reads the object by id through the API and checks its URL/name, and no delete runs on an issue-supplied id alone (`hr-bulk-delete-per-item-live-infra-role-check`).
- "Ensure heartbeat-reconcile-mismatch label exists": same gate as the issue step; also ensures `infra-drift` exists.
- "Prepare reconcile email content": one plain sentence per class above the raw markers. Subject precedence: rc 1 → the existing `[ERROR]` subject (with "issue filer failed" when `steps.reconcile_issue.outcome == 'failure'`); else a `monitor-config-drift` token → `[ALARM DISARMED] Better Stack monitor config drift`; else an `unmanaged-live` token → `[INFRA-DRIFT] Better Stack object live but unmanaged by Terraform`; else the existing mismatch subject. The `$GITHUB_OUTPUT` heredoc delimiter becomes random (`EOF_$(openssl rand -hex 8)`).
- Email step and Sentry check-in conditions gain `steps.reconcile_issue.outcome == 'failure'` (email sent; Sentry status `error`), so a failed filer is never silent.
- First run after merge escalates every existing row once (prior history carries no `resource=` tokens); stated in the ADR-117 amendment.
- Test: `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`, following `plugins/soleur/test/token-drift-workflow-causes.test.sh` (python `yaml.safe_load` extracts the step's `run:` body and `if:` strings; a `gh` stub on `PATH` logs its argv; `RUNNER_TEMP`/`GITHUB_OUTPUT` are temp files). Discovered by `scripts/test-all.sh` via the existing `plugins/soleur/test/*.test.sh` glob. Rows in Guard 3.

### Keyword contract test

`apps/web-platform/test/server/health-keyword-monitor-contract.test.ts` (vitest `unit` project, `test/**/*.test.ts`). A pure `checkHealthKeywordContract({ tfTexts, indexText, connectedBody, failedBodies, expectedBranch })` returning violations as `{ rule: string }[]`, exercised on the real files and on injected strings (Guard 1). A `loadInfraTf(dir)` helper returns every `*.tf` in the directory. The checker reads the keyword from the declaration, the real-file run builds bodies via `buildHealthResponse()` with `fetch` mocked 200 / 503 / throw, and it inspects only the brace-extracted `/health` branch of `index.ts` (exactly one `pathname === "/health"` anchor; every `writeHead(` call in the branch counted). `EXPECTED_BRANCH` is a constant in the test file set from the Phase 0.2 decision (`"keyword"` or `"status"`) — never derived from the declaration, so a later PR cannot downgrade the alarm by editing the declaration alone. Each matrix row asserts the exact `rule` list it produces.

## Implementation Phases

### Phase 0 — Preconditions (measure before building)

0.0 Merge `origin/main` into the branch: PR #8215 (the post-mortem this plan updates) landed after the branch point.

0.1 Re-read live monitor 4226366 and the monitor/heartbeat lists with `BETTERSTACK_API_TOKEN_READONLY` (Doppler `soleur/prd_terraform`). Stop the monitor half if 4226366 is gone or no longer `status`.

0.2 **Keyword probe — merge gate for the keyword half.** Precedent: #7798 Phase 0 (cited in `uptime-alerts.tf`: "Free-tier acceptance of the type was MEASURED at #7798 Phase 0 (HTTP 201)"). The probe is a reversible production-vendor write: one notification-free monitor, created and deleted inside one script run, touching no existing object. /work runs it under that precedent; if this session's permission policy refuses the write, that refusal is recorded and the `status` branch applies.
  - Credential handling: the write token is `BETTERSTACK_API_TOKEN` (Doppler `soleur/prd_terraform`), read once with `doppler secrets get … --plain` into a variable and never echoed. The script opens with the xtrace refusal used by `scripts/betterstack-ingest-probe.sh` and never enables `set -x`. Every call is `curl --disable --noproxy '*' --proto '=https' --max-redirs 0 -sS -H @- <literal https://uptime.betterstack.com/api/v2/monitors…>` with the `Authorization` header fed on stdin (token out of argv). The script is ad hoc (scratchpad), so these rules are stated here rather than left to the commit-time credential lint.
  - Precheck sweep: list monitors (all pages); for each whose `pronounceable_name` starts with `soleur-probe-7884-`, re-check `url == https://app.soleur.ai/health`, `monitor_type == keyword`, and `email/call/sms/push` all false before deleting; anything else with that prefix stops the script.
  - POST one monitor `soleur-probe-7884-<run-id>` (run-id = UTC timestamp) on `https://app.soleur.ai/health`: `monitor_type keyword`, `required_keyword "\"supabase\":\"connected\""`, `check_frequency 180`, `request_timeout 10`, `confirmation_period 0`, `email/call/sms/push false`, `critical_alert false`, no `policy_id`, `team_name "Your team"`. Print the id immediately.
  - `trap` on EXIT/INT/TERM re-checks the id is numeric, deletes it and confirms GET → 404; a failed confirmation exits non-zero. Read-only precheck of workspace integrations (outgoing webhooks, Slack) if the API lists them; if any would relay incidents, skip the `down` arm and treat the probe as not run.
  - Poll (GET, ≤ 10 min) until `last_checked_at` is set; record `status` (expect `up`).
  - PATCH `required_keyword "\"supabase\":\"soleur-probe-never\""`; poll until `last_checked_at` advances past the PATCH time; record `status` (expect `down`).
  - Recorded in the PR body: POST status, both readings, id, 404 confirmation.
  - **Decision rule.** POST 201, first reading `up`, second `down` → Phase 1 declares `keyword`. Anything else — quota refusal (H-C unanswered), type refusal, a reading that differs, or the write not permitted → Phase 1 declares `monitor_type = "status"` with no `required_keyword`; the PR title and body state that database outages remain undetected; ADR-222 is authored `adopting`; `gh issue create` files "flip app_health to keyword (database outage alarm)" with the probe evidence, `priority/p1-high`, milestone `Phase 4: Validate + Scale`; #7884 stays open. No keyword declaration merges unproven.

0.3 Targeted read-only plan, mirroring the apply job: bare `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` exported from `doppler secrets get … -p soleur -c prd_terraform --plain`; Terraform `1.10.5`; `terraform init -input=false -lockfile=readonly`; `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -input=false -target=betteruptime_monitor.app_health -var=ssh_key_path=<abs>/apps/web-platform/infra/tests/dummy-id_ed25519.pub` (no `-out`; `main.tf` sets `use_lockfile = false`). Run after the Phase 1 edits exist locally. Required: `Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.`; no `-/+`; attribute diff limited to `monitor_type`, `required_keyword`, `confirmation_period`, `request_timeout`, `pronounceable_name` (on the `status` branch: `confirmation_period`, `request_timeout`, `pronounceable_name`). Anything else stops Phase 1 until each extra attribute is declared to its live value or explained.

0.4 ADR-222 ordinal re-probe across all `origin/*` refs; re-run immediately before merge.

### Phase 1 — Monitor import + keyword (RED first)

1.1 Write `apps/web-platform/test/server/health-keyword-monitor-contract.test.ts` with the Guard 1 matrix; run RED.
1.2 Add `variable "adopt_app_health_monitor"` to `variables.tf`, `adopt_app_health_monitor = false` to `tests/web-hosts-eu-pin.tftest.hcl`, and the gated `import {}` block + `betteruptime_monitor.app_health` to `uptime-alerts.tf`.
1.3 Add `-target=betteruptime_monitor.app_health \` directly after `-target=betteruptime_monitor.soleur_www_redirect \` in the per-merge `apply` job of `.github/workflows/apply-web-platform-infra.yml`.
1.4 Rewrite the `uptime-alerts.tf` header from "Live quota measured 2026-09-07 …" through the #7884 bullet: counts measured 2026-09-15 (4 monitors + 9 heartbeats), both cap readings named as unresolved, `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` named as the measurement, #7884 recorded as resolved by `app_health`; keep #7883. Point the apex block's "Free-tier BetterStack caps the workplace at 10 monitors" at the same marker.
1.5 `terraform fmt -check -recursive`, `terraform validate`, `terraform test` for the root; contract test GREEN; `terraform-target-parity.test.ts`, `www-apex-canonicalizer.test.sh`, `www-apex-canonicalizer-mutation.test.sh`, `seo-config-rules.test.ts` GREEN.

### Phase 2 — Reconcile (RED first)

2.1 Extend `plugins/soleur/test/heartbeat-live-reconcile.test.ts` with the Guard 2 matrix (rows 1-19, the marker-key property, H1-H6), update the "no logtail_exploration_alert declared" case's exact `seen` list to include `https://uptime.betterstack.com/api/v2/monitors`, and add `real infra dir resolves` — runs declaration discovery on the real `apps/web-platform/infra` and asserts no `UnresolvableDeclaration` (so a refactor fails the PR, not the 06:00 run). Run RED.
2.2 Implement the lib, then the script.
2.3 RED first: `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` with Guard 3 (W1-W7, H1-H2). Then workflow edits in the existing steps (`has_mismatch` output and gates, lookup under `pipefail`, whole-token escalation key, decode list, `infra-drift` label, untrusted-data framing, subject precedence, random heredoc delimiter, failure conditions). `actionlint .github/workflows/scheduled-terraform-drift.yml`; extract each changed `run:` body with `python3 -c 'import yaml…'` and `bash -n` it.
2.4 Local read-only run with the Phase 1 declarations in the working tree: `BETTERSTACK_API_TOKEN="$(doppler secrets get BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform --plain)" bun plugins/soleur/scripts/reconcile-live-heartbeats.ts`. Expected: no `${each.key}`; `soleur-git-data-prd absent-live resource=betteruptime_heartbeat.git_data_prd` remains (#6548); `OK surface=monitors … matched=` lists `4226366` (the positive control that the arm reads the #7884 object on either branch); `INVENTORY` present; zero `unmanaged-live`; on the `keyword` branch also `monitor-config-drift id=4226366` rows (live is still `status`). Paste in the PR body.

### Phase 3 — Records

3.1 ADR-222 (provisional) via `/soleur:architecture`: "Better Stack is the database-readiness pager, reading the `/health` body; every live Better Stack uptime object is Terraform-declared or reported." Two decision sections. Alternatives: 503 on DB failure; separate `/ready` endpoint; Sentry uptime assertion; tfstate id matching; asserting a cap. Consequences: keyword literal coupled to serialization (pinned by the contract test); gated import block, H-F (likely abort, source-derived) and its tracked removal; email-only paging, so detection includes inbox latency; residual gaps — a Better Stack outage leaves database readiness without a second alarm; a single web host losing Supabase while its sibling is healthy alternates checks and may not trip the confirmation window (Supabase is shared, so rare); checks oscillating near the 2 s timeout can open and close incidents repeatedly; vendor 5xx or a persistent 429 on the reconcile never pages and silently suspends unmanaged and disarm detection (visible only as a missing `INVENTORY` line). On the `status` branch the ADR status is `adopting` and its title's paging clause is marked pending.
3.2 ADR-117: `### Amendment (2026-09-15, #7884)` — exact resolution of `for_each`/`count` declarations from literal variable defaults (a Doppler `--name-transformer tf-var` override — `WEB_HOSTS`, `BETTERSTACK_PAID_TIER`, `ADOPT_APP_HEALTH_MONITOR` — would bypass it; none exists, stated as a limit), the `resource=` field appended to rows, and the one-time re-escalation after merge.
3.3 ADR-204: `## Residual gap` #7884 paragraph → its resolution (links ADR-222); `## Consequences` "4 monitors of 10 on the free tier" → measured 4 + 9 and the marker.
3.4 ADR-149: one sentence after reason (c) pointing at `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` as the measurement that supersedes "a vendor-page reading".
3.5 Runbook `knowledge-base/engineering/operations/runbooks/app-database-readiness-alarm.md` (frontmatter like `www-redirect-alarm.md`): TL;DR `curl -s --max-time 10 https://app.soleur.ai/health | jq -r .supabase`; "which alarm is this?" table (`soleur app database readiness` / `soleur app dashboard` / `soleur dot ai apex`); what is asserted; diagnosis with no SSH — dev-project control probe, Supabase Management API health, `scripts/supabase-logs-query.sh` (`supabase-log-query.md`), and the service-role-key cause (`supabase-db-credential-rotation.md`); remediation — a project restart is a production write that needs explicit operator authorization per `hr-menu-option-ack-not-prod-write-auth`; the H-F remedy (set `adopt_app_health_monitor` default `false` in a PR) step by step; a link to the post-mortem (on `origin/main` since #8215).
3.6 C4: `model.c4` `betterstack -> hetzner` gains the database-readiness keyword probe; `github -> betterstack` reconcile sentence gains `GET /api/v2/monitors`, `unmanaged-live`, `monitor-config-drift` and the INVENTORY marker; `betterstack -> founder` gains the database alarm in what pages. Run `bash scripts/regenerate-c4-model.sh`; then `bash plugins/soleur/test/c4-model-freshness.test.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh`.
3.7 Prose sweep: `git grep -n 'heartbeat-live-reconcile\|reconcile-live-heartbeats'` — update statements that describe the job as heartbeats-only in `ADR-141`, `apps/web-platform/infra/sentry/cron-monitors.tf` and `function-registry-count.test.ts` where they would now be false; leave historical plan/spec files.
3.8 Post-mortem (on `origin/main` since #8215): in `knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md` Action Items, set the #7884 row's status to reflect this PR — `resolved by #8216 (keyword alarm)` on the keyword branch, `in progress: imported as status; keyword follow-up #<n>` on the `status` branch.

### Phase 4 — Issue housekeeping (automated)

4.1 `gh issue create` "Better Stack Logs alert `Output utilization high` (id 2536305877) is live but undeclared", `--milestone "Post-MVP / Later"`, labels `infra-drift`, `domain/engineering`.
4.2 Comment on #8140 that it duplicates #6645 (the fail-open lookup fixed here) and close it `not planned`; comment on #6645 that the `${each.key}` rows were false and are fixed by this PR.
4.3 On the `status` branch only: the follow-up issue from the decision rule.
4.4 `gh issue create` "Remove the app_health adoption import block and adopt_app_health_monitor once adoption is verified" (H-F: the block most likely aborts every plan in the root after a vendor-side deletion; removal also closes the Doppler tf-var override path), `priority/p2-medium`, milestone `Post-MVP / Later`, body citing AC17 as the precondition and naming the tftest override and Guard-free removal (a PR deleting both lines + the tftest override).

## Files to Edit

- `apps/web-platform/infra/uptime-alerts.tf`
- `apps/web-platform/infra/variables.tf`
- `apps/web-platform/infra/tests/web-hosts-eu-pin.tftest.hcl`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/workflows/scheduled-terraform-drift.yml`
- `plugins/soleur/lib/heartbeat-live-reconcile.ts`
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts`
- `plugins/soleur/test/heartbeat-live-reconcile.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md`
- `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md`
- `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json` (regenerated)
- Prose sweep candidates (edit only where now false): `knowledge-base/engineering/architecture/decisions/ADR-141-encryption-posture-layer-b-live-reconcile-deferred.md`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `apps/web-platform/test/server/inngest/function-registry-count.test.ts`

## Files to Create

- `apps/web-platform/test/server/health-keyword-monitor-contract.test.ts`
- `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-222-better-stack-database-readiness-pager-and-live-inventory.md` (ordinal provisional)
- `knowledge-base/engineering/operations/runbooks/app-database-readiness-alarm.md`

Pipeline-written files that may also appear in the diff: `knowledge-base/INDEX.md`, `knowledge-base/project/specs/feat-one-shot-7884-health-monitor-supabase-keyword/{tasks.md,session-state.md,decision-challenges.md}`.

## Open Code-Review Overlap

1 open scope-out touches these files: #7098 (audit `run:` bodies whose `set` omits `-e`; names `apply-web-platform-infra.yml`). **Acknowledge:** this plan adds one `-target=` continuation line and no `run:` body change to that workflow; the audit is a repo-wide lint concern with its own cycle.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `/health` returns 503 when Supabase fails | Breaks deploy liveness and LB probes (P2). |
| New `/ready` endpoint for a status monitor | New app surface + deploy for a property the body already carries. |
| `terraform import` CLI in a dispatch job | Imperative, state-only, invisible to review. |
| Ungated `import {}` | Breaks the credential-free `terraform test` leg; no off-switch. |
| Keep the gated `import {}` permanently | Terraform v1.10.5 re-attempts a skipped import once refresh drops a deleted object, so the block would most likely abort every plan in the root; it is removed by a tracked follow-up after AC17 (it must exist for the adoption apply itself). |
| Delete 4226366 and create a fresh keyword monitor | Loses 5.5 months of check history. |
| Match live objects by tfstate ids | Needs state access and a second credential surface. |
| Match monitors by name; regex-expand templated names | Renames read as unmanaged; loose patterns absorb look-alikes. |
| A separate issue family, routing outputs and close step for unmanaged objects | More workflow state than the property needs; the existing issue + `infra-drift` label + email carry it. |
| Split the reconcile into a second PR | Changes the operator's stated scope for this PR; recorded as a decision challenge. |
| Assert the free-tier cap | The live count of 13 contradicts one reading. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the next prd database outage leaves app.soleur.ai sign-in and every data-backed page failing with no alarm (the 2026-09-15 shape, ~89 min).
- **If this lands on the `status` branch, the user experiences:** the same — the 2026-09-15 outage shape stays undetected until the keyword follow-up PR merges; the PR and ADR say so.
- **If this lands broken the other way, the user experiences:** nothing directly, but a permanently firing `soleur app database readiness` alarm trains the inbox to ignore Better Stack, which hides the next real outage.
- **If this lands broken in the apply, the user experiences:** infra merges whose later apply steps (tunnel, bridge apply) stop running until the config is fixed — the Phase 0.2 gate exists to prevent this.
- **If this leaks, the user's workflow is exposed via:** nothing user-scoped — markers and issue bodies carry monitor/heartbeat names, URLs and vendor ids (already public in the repo's `.tf`), never the token; vendor text is quoted and sanitized.
- **Brand-survival threshold:** `single-user incident` — carried from the post-mortem (PR #8215).

CPO sign-off: approve with conditions (Domain Review). `user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "Better Stack keyword monitor betteruptime_monitor.app_health ('soleur app database readiness') on https://app.soleur.ai/health; reconcile liveness via the existing Sentry cron monitor scheduled-heartbeat-reconcile"
  cadence: "180 s checks with 180 s confirmation; reconcile twice daily (06:00/18:00 UTC, Inngest-dispatched)"
  alert_target: "Better Stack email to the account owner and betteruptime_team_member.ops (ops@jikigai.com); reconcile: heartbeat-reconcile-mismatch issue (plus infra-drift label for unmanaged objects) + Resend email to ops; Sentry cron issue on a missed or error check-in"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf; .github/workflows/scheduled-terraform-drift.yml (heartbeat-live-reconcile job)"

error_reporting:
  destination: "Better Stack incident + email for the alarm; SOLEUR_HEARTBEAT_RECONCILE_* markers in the workflow log, issue and email; Sentry cron monitor scheduled-heartbeat-reconcile"
  fail_loud: "Keyword absent for two consecutive checks opens an incident; reconcile rc=1 emails [ERROR] and checks in error; a failed issue filer emails and checks in error; config drift emails [ALARM DISARMED]; unmanaged objects email [INFRA-DRIFT]"

failure_modes:
  - mode: "prd Supabase unreachable, REST check over 2 s, or service-role key invalid (body supabase:error)"
    detection: "keyword monitor fails; incident after confirmation_period"
    alert_route: "Better Stack email (owner + ops@)"
    layer: "external synthetic check (Better Stack uptime monitor); no in-repo layer — deliberate carve-out, as ADR-204"
  - mode: "app.soleur.ai down / Cloudflare 52x / TLS failure / /health slower than 10 s"
    detection: "keyword absent; also betteruptime_monitor.app and the Sentry uptime monitors"
    alert_route: "Better Stack email; Sentry issue alert email"
    layer: "external synthetic check (Better Stack uptime monitor); no in-repo layer — deliberate carve-out, as ADR-204"
  - mode: "/health serialization change makes the keyword unmatchable"
    detection: "health-keyword-monitor-contract.test.ts fails before merge"
    alert_route: "PR check failure"
    layer: "workflow run log (PR check)"
  - mode: "vendor-side edit disarms the alarm (type, keyword, paused)"
    detection: "reconcile reason=monitor-config-drift"
    alert_route: "reconcile issue + [ALARM DISARMED] ops email; next infra merge apply re-converges"
    layer: "workflow run log (SOLEUR_HEARTBEAT_RECONCILE_* markers, ::error::/::warning::) + Sentry cron monitor scheduled-heartbeat-reconcile"
  - mode: "hand-created or duplicated Better Stack monitor or heartbeat"
    detection: "reconcile reason=unmanaged-live with id"
    alert_route: "reconcile issue labeled infra-drift + [INFRA-DRIFT] ops email"
    layer: "workflow run log (SOLEUR_HEARTBEAT_RECONCILE_* markers, ::error::/::warning::) + Sentry cron monitor scheduled-heartbeat-reconcile"
  - mode: "monitor 4226366 deleted vendor-side"
    detection: "reconcile surface=monitors reason=absent-live, then unmanaged-live or a restored id after the next apply (H-F)"
    alert_route: "reconcile issue + ops email"
    layer: "workflow run log (SOLEUR_HEARTBEAT_RECONCILE_* markers, ::error::/::warning::) + Sentry cron monitor scheduled-heartbeat-reconcile"
  - mode: "reconcile cannot read Better Stack (401/403/malformed), a declaration is unresolvable, or the script crashes"
    detection: "rc=1 in the reconcile step; unresolvable declarations also fail the PR via the real-infra-dir test"
    alert_route: "[ERROR] ops email + Sentry cron check-in status error"
    layer: "workflow run log (SOLEUR_HEARTBEAT_RECONCILE_* markers, ::error::/::warning::) + Sentry cron monitor scheduled-heartbeat-reconcile"
  - mode: "Better Stack API 5xx/429 after retries"
    detection: "SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE and no INVENTORY line (no page, existing contract; residual in ADR-222)"
    alert_route: "workflow warning annotation"
    layer: "workflow run log (::warning::); residual — a persistent 5xx/429 suspends unmanaged and disarm detection with no page (ADR-222)"
  - mode: "adoption import or keyword PATCH refused, or the import aborts the targeted apply (H-F)"
    detection: "workflow run log ::error:: in the apply step of apply-web-platform-infra.yml"
    alert_route: "notify-apply-failure job -> notify-ops-email to ops on every non-green push run"
    layer: "workflow run log + notify-ops-email"
  - mode: "Phase 0.2 probe monitor left behind (trap delete failed)"
    detection: "next probe run pre-sweep; reconcile surface=monitors reason=unmanaged-live with the probe id"
    alert_route: "reconcile issue labeled infra-drift + [INFRA-DRIFT] ops email"
    layer: "workflow run log (SOLEUR_HEARTBEAT_RECONCILE_* markers, ::error::/::warning::) + Sentry cron monitor scheduled-heartbeat-reconcile"

logs:
  where: "GitHub Actions logs for scheduled-terraform-drift.yml (reconcile-output.txt echoed) and apply-web-platform-infra.yml; Better Stack check history for monitor 4226366"
  retention: "GitHub Actions logs 90 days; Better Stack check history per vendor plan"

discoverability_test:
  command: "curl -s --max-time 10 https://app.soleur.ai/health | grep -o '\"supabase\":\"connected\"'"
  expected_output: "\"supabase\":\"connected\""
```

## Encryption Posture

```yaml
at_rest: []   # no persistent store is introduced or changed
in_transit:
  - connection: "Better Stack probe -> Cloudflare edge (app.soleur.ai/health)"
    enforced_at: "apps/web-platform/infra/uptime-alerts.tf:betteruptime_monitor.app_health verify_ssl"
    tls: "HTTPS, TLS 1.2+ at the Cloudflare edge (measured TLS 1.3)"
    cert_verification: on
    does_not_defend: "the Cloudflare-to-origin and origin-to-Supabase legs, which this monitor does not see; Better Stack reading the public health body"
    disclosed_as: not-publicly-claimed
  - connection: "GitHub Actions runner -> uptime.betterstack.com (/api/v2/monitors, /api/v2/heartbeats)"
    enforced_at: "plugins/soleur/scripts/reconcile-live-heartbeats.ts:isAllowedUrlFor"
    tls: "HTTPS only; exact-host pin; redirects refused"
    cert_verification: on
    does_not_defend: "a compromised runner or a leaked read-only token (read scope, masked in logs)"
    disclosed_as: not-publicly-claimed
```

## Infrastructure (IaC)

### Terraform changes

- Root: `apps/web-platform/infra` (existing; R2 backend; no new root).
- Resources: `betteruptime_monitor.app_health`, adopted via `import { for_each = var.adopt_app_health_monitor ? toset(["adopt"]) : toset([]); to = betteruptime_monitor.app_health; id = "4226366" }`.
- Variables: `adopt_app_health_monitor` (bool, default `true`; not secret; no Doppler value). Existing `betterstack_api_token`, `betterstack_paid_tier` unchanged.
- Provider: `BetterStackHQ/better-uptime` `~> 0.20`, lockfile `0.20.17` (unchanged). CI Terraform `1.10.5`; `required_version >= 1.7` covers `for_each` on `import`.
- Workflow allow-list: `-target=betteruptime_monitor.app_health` in the per-merge `apply` job.
- Test harness: `tests/web-hosts-eu-pin.tftest.hcl` sets the gate `false`.

### Apply path

Existing merge-triggered `apply-web-platform-infra.yml`: import and in-place update in one targeted apply. No host, no downtime; blast radius is one monitor. Failure branches: Technical Approach → Apply path. Other planners of this root (`apply-deploy-pipeline-fix.yml`, dispatch jobs, the untargeted drift plan) run with the same gated import; the ungated-by-default seo import block has coexisted with them since July, and after the adoption apply the address is in state.

### Distinctness / drift safeguards

- Better Stack has one workspace (no dev/prd split).
- No `ignore_changes`. `team_name` is DiffSuppressed once an id exists.
- Vendor-side edits to alarm-critical fields are reported by `monitor-config-drift`, independent of the noisy drift plan.
- The reconcile resolves `for_each`/`count` from literal variable defaults; a Doppler `TF_VAR_*` override would bypass that (none exists; stated in ADR-117).

### Vendor-tier reality check

Better Stack free tier. Keyword acceptance is measured at Phase 0.2 and gates the keyword half. The object count does not change (the monitor already exists; the probe is created and deleted). Cap semantics are unresolved and measured by the INVENTORY marker.

## Architecture Decision (ADR/C4)

### ADR

- **Create** ADR-222 (provisional; re-probed before merge and at `/ship`'s ADR-Ordinal Collision Gate): Better Stack as the database-readiness pager via the `/health` body, and the declared-or-reported rule for live Better Stack uptime objects.
- **Amend** ADR-117: exact declaration resolution and the `resource=` marker field.
- **Amend** ADR-204: Residual gap → resolution; Consequences quota sentence → measured counts.
- **Amend** ADR-149: one forward pointer from reason (c) to the INVENTORY marker.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Checked:

- External system `betterstack` — modeled; no new element.
- `hetzner` (web hosts serving app.soleur.ai) — edge `betterstack -> hetzner` gains the keyword database-readiness probe.
- `github -> betterstack` — reconcile sentence gains the monitors read, the new classes and the marker.
- `betterstack -> founder` — gains the database alarm in what pages.
- Supabase — the app → Supabase relationship already exists; the monitor does not call Supabase.
- Views: `betterstack` is already in both view include lists; no view change.
- Derived cardinalities: none for Better Stack in `model.c4`; `c4-count-parity.test.sh` and `c4-model-freshness.test.sh` must pass.

### Sequencing

Everything ships in this PR. On the Phase 0.2 `status` branch, ADR-222 is authored `adopting` and the keyword flip is the follow-up issue.

## Guard Contract

### Guard 1 — health keyword monitor contract

**Property.** Exactly one Terraform-declared Better Stack monitor watches `https://app.soleur.ai/health`, its type is the committed `EXPECTED_BRANCH`; on the keyword branch its required keyword occurs in the served `/health` body exactly when the Supabase check succeeds; on either branch `/health` answers HTTP 200 in every database state.

**Assembly.** (1) EVERY comment-stripped `*.tf` returned by `loadInfraTf("apps/web-platform/infra")`: every `resource "betteruptime_monitor"` block whose `url` is the health URL (census); (2) `apps/web-platform/server/health.ts` `buildHealthResponse` on the connected arm and both failed arms (non-2xx, thrown fetch); (3) `apps/web-platform/server/index.ts`, the single brace-extracted `/health` branch, every `writeHead(` call and the serializer call in it; (4) the `EXPECTED_BRANCH` constant. Chokepoints: the declaration's keyword literal (read, never copied), the one serialization site, and the constant.

**Mutation matrix** (each row asserts the exact `rule` list):

| # | Mutation | Expected |
|---|---|---|
| 1 | `required_keyword = "\"supabase\": \"connected\""` (space after colon) | RED `keyword-absent-connected` |
| 2 | Injected connected body with `"supabase":"ok"` | RED `keyword-absent-connected` |
| 3 | Injected failed body containing `"supabase":"connected"` | RED `keyword-present-failed` |
| 4 | `/health` branch: `JSON.stringify(health, null, 2)` | RED `serializer-not-compact` |
| 5 | `/health` branch gains a second `res.writeHead(503` inside an `if` | RED `status-not-always-200` |
| 6 | `EXPECTED_BRANCH = "keyword"` and the declaration says `monitor_type = "status"` with no `required_keyword` | RED `branch-downgraded` |
| 7 | `monitor_type = "keyword"` with no `required_keyword` | RED `keyword-missing` |
| 8 | `required_keyword = local.kw` | RED `keyword-unresolvable` |
| 9 | A second health-URL `betteruptime_monitor` in a DIFFERENT `.tf` (temp dir with two files through `loadInfraTf`) | RED `census-not-one` |
| 10 | Infra texts with zero health-URL blocks | RED `census-not-one` |
| 11 | `index.ts` with zero or two `pathname === "/health"` anchors | RED `health-branch-not-one` |

Harness rows: (H1) stub `buildHealthResponse` so every arm returns the same object → the real-file run goes RED; (H2) one real-file proof: a temp copy of `health.ts` with `supabaseOk ? "ok" : "error"`, loaded through the same builder path, goes RED, then the real file is GREEN; (H3) must-PASS: attributes reordered plus a comment line containing `monitor_type = "status"` → GREEN; (H4) must-PASS: an unrelated monitor block with a different URL → GREEN; (H5) must-PASS: `EXPECTED_BRANCH = "status"` with a status declaration → GREEN.

**Anchor.** Keyword literal and serialization live in different files; one diff can change both consistently and stay green, which is correct because the monitor then still tracks the database. A downgrade must also edit `EXPECTED_BRANCH`, which a reviewer sees in the test diff. The outside anchor for the vendor's matching is the Phase 0.2 probe and the post-merge read-back (AC17).

### Guard 2 — Better Stack live inventory reconcile

**Property.** Every live Better Stack uptime monitor and heartbeat is accounted for by exactly one resolved Terraform declaration in the web-platform root (monitors by literal URL, heartbeats by resolved name), every declared instance is live, every declared monitor's live type, keyword and paused state equal its declaration, and every outcome is printed as a marker whose routing tokens vendor text cannot forge — never silently skipped.

**Assembly.** Live: every page of `GET /api/v2/monitors` and `GET /api/v2/heartbeats` through the single `fetchPaged` chokepoint (per-arm host+port+path pin, seen-URL set, page cap). Declared: every comment-stripped `betteruptime_monitor` / `betteruptime_heartbeat` block in `RECONCILE_INFRA_DIR/*.tf` through `resourceBlocks`, with `for_each`/`count` through the single `resolveInfraVariables` resolver. Emission: `runReconcile`'s full marker list, the `oneLine` sanitizer, and the combined code. Reconcile is dependency-injected (`runReconcile(infraDir, opts, manifest, { reconcileMonitors })`) so harness rows can replace it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Live monitors gain `{id: "9", url: "https://example.soleur.ai/"}` | RED — `surface=monitors reason=unmanaged-live id=9`, rc 2 |
| 2 | A second live monitor on `https://app.soleur.ai/health` after the compliant first | RED — `unmanaged-live dup=url` for both ids |
| 3 | The unmanaged monitor only on page 2 | RED — still reported |
| 4 | Monitors endpoint `data: []` while declarations exist | RED — `surface=monitors reason=absent-live` per declared instance |
| 5 | Live heartbeat `soleur-web-zot-consumer-web-1-old` | RED — `unmanaged-live` |
| 6 | Live heartbeat `soleur-web-zot-consumer-web-3` | RED — `unmanaged-live` |
| 7 | Declared keyword monitor live with `monitor_type: status` / different `required_keyword` / `paused: true` | RED — one `monitor-config-drift` row per field |
| 8 | Declaration present only inside a `#` comment | RED — live object `unmanaged-live` |
| 9 | Heartbeat `name = "soleur-${local.x}"` | RED — rc 1 `unresolvable-declaration` |
| 10 | Heartbeat `for_each = local.hosts` | RED — rc 1 `unresolvable-declaration` |
| 11 | Heartbeat `count = 2` | RED — rc 1 `unresolvable-declaration` |
| 12 | Two declared monitors on the same URL | RED — rc 1 `unresolvable-declaration` |
| 13 | Monitors read 401 while heartbeats read OK | RED — rc 1; no `INVENTORY` line |
| 14 | Monitors endpoint 5xx after retries | `UNREACHABLE surface=monitors`, no `OK surface=monitors`, no `INVENTORY` |
| 15 | Monitors row whose `id` is `"9x"`, or without a string `url` | RED — rc 1 |
| 16 | Monitors arm finds `unmanaged-live` while the heartbeats arm ERRORs | rc 1 AND both the heartbeats ERROR marker and the monitors `unmanaged-live` marker printed |
| 17 | `count = var.betterstack_paid_tier ? 1 : 0` block (default `false`) and a live monitor on its URL | RED — `unmanaged-live` |
| 18 | Vendor name `x id=1 reason=monitor-config-drift` on an unmanaged monitor (and a name with U+202E) | the line's pre-quote routing tokens are exactly `surface=monitors reason=unmanaged-live id=<real>`; no bidi char survives |
| 19 | `pagination.next` pointing at `/api/v2/heartbeats` on the monitors arm, or repeating its own URL | RED — rc 1 |

Plus a property assertion over every fixture's output: each MISMATCH line has exactly one `resource=` or `id=` token before its first `"`.

Harness rows: (H1) inject `reconcileMonitors: () => []` → rows 1, 2, 4, 7, 17 must go RED; (H2) must-PASS: live `soleur-web-zot-consumer-web-1`, `-web-2`, `soleur-web-nic-guard-web-1`, `-web-2` with templated declarations over a `web_hosts`-shaped default (nested object values + `validation {}` blocks) → GREEN; (H3) must-PASS: shuffled live arrays with unknown extra attributes → GREEN; (H4) must-PASS: live monitor renamed (same URL, type, keyword) → GREEN; (H5) must-PASS: status monitors whose live `required_keyword` is `""` or `null` against an undeclared keyword → GREEN; (H6) must-PASS and non-vacuous: the real `apps/web-platform/infra` resolves with no `UnresolvableDeclaration`, its declared monitors include `https://app.soleur.ai/health`, every templated heartbeat resolves to ≥1 instance, and no resolved name contains `${`.

**Anchor.** The declared set comes from the same commit as the code, so a PR could declare a hand-made object's URL to silence the arm. Declaring it without an `import {}` makes the next apply create a second object on that URL, which row 2 reports — the outside anchor is live vendor state.

### Guard 3 — reconcile issue-step routing

**Property.** Every MISMATCH row reaches the reconcile issue even when another arm errors, each new routing key re-emails exactly once, unmanaged rows add the `infra-drift` label, and the issue step can neither create a duplicate nor fail silently.

**Assembly.** The `run:` bodies and `if:` strings of the reconcile step (`has_mismatch` write), the label step, "Create or update reconcile issue", "Prepare reconcile email content", the email step and the Sentry check-in in the `heartbeat-live-reconcile` job — extracted by `yaml.safe_load` in `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`, run against a `gh` stub that logs argv, with temp `RUNNER_TEMP`/`GITHUB_OUTPUT`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| W1 | `gh issue list` stub exits 1 | step exits non-zero; no `gh issue create` logged |
| W2 | History has `resource=betteruptime_heartbeat.git_data_prd`; current row has `resource=betteruptime_heartbeat.git_data` | `escalate=true` |
| W3 | Same key present at end of line / end of text in history | `escalate=false` |
| W4 | Current `id=9`, history `id=94` | `escalate=true` |
| W5 | A second new key after a first known key in the same run | `escalate=true` |
| W6 | A `reason=unmanaged-live` row, existing issue | `gh issue edit <n> --add-label infra-drift` logged; with no existing issue, create carries both labels |
| W7 | Parsed `if:` strings: label/issue steps lack `rc == '1' && … has_mismatch`, or email/Sentry steps lack `steps.reconcile_issue.outcome == 'failure'` | RED |

Also asserted: a MISMATCH row with no key escalates; subject precedence rc1 > `monitor-config-drift` > `unmanaged-live` > default. Harness rows: (H1) a `gh` stub that logs nothing → W1, W6 must go RED; (H2) must-PASS: a vendor name containing spaces, `id=1` and backticks inside quotes → routing uses only the real pre-quote tokens.

**Anchor.** Routing lives in the workflow file the test extracts from; a PR editing both could weaken both. The live anchor is AC18's post-merge script run and the existing issue history (#6645).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/health-keyword-monitor-contract.test.ts test/server/health-supabase.test.ts test/server/health.test.ts test/seo-config-rules.test.ts` passes; the contract test asserts its own Guard 1 row count in-file and `EXPECTED_BRANCH` equals the Phase 0.2 decision.
- [ ] AC2 `.github/workflows/apply-web-platform-infra.yml` per-merge `apply` job carries `-target=betteruptime_monitor.app_health`; `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes.
- [ ] AC3 For `apps/web-platform/infra`: `terraform fmt -check -recursive`, `terraform validate` and `terraform test` pass (the `infra-validation.yml` jobs are green on the PR).
- [ ] AC4 Phase 0.2 result recorded in the PR body (POST status, `up` then `down` readings, id, 404 confirmation — or the recorded refusal), and the declared `monitor_type` in `uptime-alerts.tf` matches the decision rule's branch.
- [ ] AC5 Phase 0.3 output recorded in the PR body: `Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.`, no `-/+`, attribute diff limited to the branch's named attributes.
- [ ] AC6 `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` passes with every Guard 2 row (1-19), H1-H6 and the updated `seen` expectation.
- [ ] AC7 `actionlint .github/workflows/scheduled-terraform-drift.yml` is clean, every changed `run:` body passes `bash -n` after extraction, and `bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` passes with every Guard 3 row.
- [ ] AC8 Phase 2.4 local read-only run output in the PR body: no line containing `${each.key}`; `OK surface=monitors` with `4226366` in `matched=`; an `INVENTORY` line whose counts equal the lengths of the two live lists read through all pages in the same minute; zero `unmanaged-live`.
- [ ] AC9 `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` and `bash apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh` pass.
- [ ] AC10 The `uptime-alerts.tf` header no longer asserts that heartbeats "are NOT pooled" or that the www monitor "is the 4th of 10"; it names `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` and records #7884's resolution (read the comment block, not a bare-token grep).
- [ ] AC11 ADR-204 `## Residual gap` no longer describes 4226366 as unmanaged and links ADR-222; its `## Consequences` no longer says "4 monitors of 10"; ADR-117 carries `### Amendment (2026-09-15, #7884)`; ADR-149 carries the INVENTORY pointer.
- [ ] AC12 ADR-222 exists with the Phase 3.1 content (status `adopting` on the `status` branch); its ordinal is free across all `origin/*` refs immediately before merge; `bun test plugins/soleur/test/adr-frontmatter-ordinal-guard.test.ts` passes.
- [ ] AC13 `knowledge-base/engineering/operations/runbooks/app-database-readiness-alarm.md` exists; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes; it contains no `ssh ` command, covers the service-role-key cause and the H-F remedy, and links the post-mortem.
- [ ] AC14 `model.c4` edges updated per Phase 3.6; `bash plugins/soleur/test/c4-model-freshness.test.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] AC15 PR body uses `Ref #7884`, not `Closes`; on the `status` branch the PR title and body state that database outages remain undetected until the follow-up.
- [ ] AC16 Phase 4 actions done: Logs-alert issue exists with a milestone; #8140 closed as a duplicate of #6645 with a comment; the import-block removal issue (Phase 4.4) exists; on the `status` branch, the keyword follow-up issue exists with milestone `Phase 4: Validate + Scale` and `priority/p1-high`; the post-mortem #7884 row status is updated (Phase 3.8).

### Post-merge (automated, `/ship` postmerge)

- [ ] AC17 The `apply-web-platform-infra.yml` run whose head commit contains the merge commit concludes `success`; its apply log contains `betteruptime_monitor.app_health` import and `Modifications complete`. Then `GET /api/v2/monitors/4226366` (READONLY token), polled for at least 360 s after the apply's completion, returns the declared `monitor_type`, `required_keyword` (keyword branch), `pronounceable_name "soleur app database readiness"` and `confirmation_period 180`, with `last_checked_at` later than completion + 180 s and `status: "up"`.
- [ ] AC18 After AC17: `BETTERSTACK_API_TOKEN="$(doppler secrets get BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform --plain)" bun plugins/soleur/scripts/reconcile-live-heartbeats.ts` prints `OK surface=monitors` with `4226366` in `matched=`, an `INVENTORY` line, and no `unmanaged-live`, `monitor-config-drift` or `${each.key}`.
- [ ] AC19 Keyword branch: `gh issue close 7884` with a comment linking the apply run and the AC17 read-back. `status` branch: comment only; #7884 closes with the follow-up PR.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO (structural + devex), terraform-architect, architecture-strategist, spec-flow-analyzer (two passes), DHH, Kieran, code-simplicity, and a scoped advisor consult. Applied: gated import block (the ungated form breaks `terraform test`); Phase 0.3 invocation corrected; ForceNew fork pre-decided (verified none; `-/+` stops Phase 1); keyword half gated on a single-monitor pos→neg probe with an orphan sweep; exact `for_each`/`count` resolution from literal defaults, including nested map defaults; monitors matched by literal URL (removes the rename window); duplicates reported without picking; discriminated violation type; one `surface=` spelling per arm and every monitors-arm marker defined; `resource=` appended to existing rows so escalation has a key; fail-closed issue lookup and failure-triggered email/Sentry; config drift gets an `[ALARM DISARMED]` subject; real-infra-dir test so parser breaks fail the PR; the existing `seen` test expectation listed; `null`/`""` keyword equality; AC timing (≥360 s, `last_checked_at`), token env var, pagination and C4 freshness corrections; `status`-branch Guard 1 variant and AC8 control via `matched=`; ADR shape (ADR-222 for both new rules, ADR-117 for resolution, ADR-149 pointer); prose sweep of heartbeats-only descriptions. Cut on convergence of the simplification and correctness panels: the separate unmanaged issue family, three routing outputs, the close-on-clean step (it could never fire), the YAML workflow test harness (it could not evaluate `if:` and needed `yq`), the declarations census, `duplicate-live`/`monitor-absent-live` as separate classes, import-id/gate-default mutation rows, and the #6606 comment. Surfaced, not applied (see `decision-challenges.md`): splitting into two PRs; renaming the alarm to "soleur app database down"; cutting P6.

### Product (CPO sign-off)

**Status:** reviewed — approve with conditions
**Assessment:** Conditions applied: C1 the probe is attempted, not silently skipped (Phase 0.2); C2 the `status`-branch follow-up goes on `Phase 4: Validate + Scale`, `priority/p1-high`; C3 a `status`-branch PR and ADR say database outages remain undetected, and #7884 stays open; C4 User-Brand Impact names the `status`-branch exposure. C5 (email is not a page): recorded in ADR-222 Consequences; push stays off, matching every sibling. Shipping import-as-status alone is acceptable only under C1-C3.

### Deepen pass (2026-09-15)

**Status:** reviewed
**Assessment:** security-sentinel — vendor text could forge routing tokens (`url` unquoted; token regex quote-blind) and invisible/bidi characters survived `oneLine`; probe sweep name mismatch and unchecked deletes; no transport confinement prescribed; pagination could switch endpoints or loop. All folded (marker grammar, sanitizer, per-arm pin, page cap, probe credential rules, untrusted-data framing, re-read-before-act remedy, random heredoc delimiter, `%22` encoding). test-design-reviewer (7.4/10) — Guard 1 branch derived from the declaration allowed a silent downgrade (now `EXPECTED_BRANCH`); rows 2-3 were not drivable (now injected bodies + one real-file proof); per-row rule ids; extractor rows; non-vacuous H6; split rows; escalation-key workflow suite reinstated narrowly (W1-W7) with subject precedence and keyless escalation decided. observability-coverage-reviewer — layer citations added; apply-failure and probe-orphan modes added with `notify-apply-failure`; rc-1 masking fixed with `has_mismatch`; 429 residual recorded. framework-docs-researcher — Terraform v1.10.5 import skip is state-keyed, so H-F is likely-abort; import-block removal tracked (Phase 4.4). Verify-the-negative/self-audit — all negative claims confirmed; no surviving references to cut mechanisms; row/AC counts consistent. PR #8215 merged mid-pass; Phase 3.8 added.

No Product/UX gate: no UI surface in Files to Create/Edit.

## Test Scenarios

- Contract test: Guard 1 rows 1-11, H1-H5.
- Issue-step suite: Guard 3 rows W1-W7.
- Reconcile unit tests: Guard 2 rows 1-19, H1-H6; existing cases still pass (fed-but-paused, absent-live, logs_alert arm, host pinning, redirect refusal, retry/unreachable) with the one updated `seen` list.
- Workflow: `actionlint`; extracted `run:` bodies `bash -n`.
- Terraform: `validate`, `test` with the gate off; Phase 0.3 targeted plan with the gate on.
- Live, read-only: AC8 before merge; AC17/AC18 after.

## Risks & Mitigations

- **Workspace refuses the keyword type or matches differently.** Phase 0.2 gate; `status` branch with P1 follow-up otherwise.
- **Refused PATCH wedges later infra merges.** Prevented by the same gate; the remedy is reverting `monitor_type` in a PR.
- **Import block after vendor-side deletion (H-F, likely abort per Terraform source).** Reported by the reconcile; any aborted apply emails via `notify-apply-failure`; the gate variable is the off-switch (runbook steps); the block and variable are removed by the Phase 4.4 follow-up once AC17 passes.
- **Vendor text forging routing tokens or hiding in invisible characters.** Quoted-last vendor fields, pre-quote token extraction, numeric ids, bidi strip, 200-char cap; Guard 2 row 18 and Guard 3 H2.
- **Deploy windows.** Container restarts give Cloudflare 52x for seconds; `confirmation_period = 180` exceeds them.
- **False `unmanaged-live`.** Exact resolution, URL matching, H2/H4/H5 must-pass rows, and AC8 on live data before merge.
- **Parser breaks on a harmless refactor.** Guard 2 H6 fails the PR before the scheduled run sees it.
- **Duplicate or silent issue filing.** Fail-closed lookup plus failure-triggered email and Sentry error; #8140 closed.
- **One-time email burst after merge.** Every existing row re-escalates once because history lacks `resource=`; stated in ADR-117.
- **Probe leaves an orphan monitor.** Sweep-first, trap, id printed; the new arm would report a survivor as `unmanaged-live`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- The keyword literal is compact JSON with escaped quotes in HCL; `JSON.stringify` output has no spaces. A change to `/health` serialization is a change to the paging contract (Guard 1).
- The existing reconcile row prefixes are a wire contract quoted by ADR-218 and `monitor-send-failed-alert.md`; new fields are appended, never inserted.
- `mock_provider` does not mock `import` blocks; any import block in this root needs a gate variable set `false` in the tftest.
- Import targets are validated before `-target` pruning (`seo-config-rules.tf` comment): a bad import id aborts the whole targeted apply on the adoption run. Phase 0.3 is the pre-merge check.
- The post-mortem was added by PR #8215, merged during planning; this branch must merge `origin/main` before editing or linking it (Phase 0.0).
