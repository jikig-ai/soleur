---
title: "ADR-031 — Sentry alert and cron monitor configuration as IaC"
status: accepted
date: 2026-05-15
plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
spec: knowledge-base/project/specs/feat-sentry-monitors-alerts-adapt/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md
issue: 3814
supersedes: none
related:
  - ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md
  - ADR-029-rename-at-boundary-userid-pseudonymisation.md
  - ADR-030-multi-tenant-deploy-substrate.md
---

# ADR-031 — Sentry alert and cron monitor configuration as IaC

## Status

Accepted (2026-05-15).

## Context

Sentry split "Alerts" into **Monitors** (detection) and **Alerts** (routing) in
2026. Vendor's "no action required" advisory is rejected because:

1. **Auto-migration risk.** A pre-2026 Metric Alert and its routing rule may
   have decoupled, leaving threshold breaches with no paging path. Brand-survival
   threshold is `single-user incident` per the plan's User-Brand Impact section.
2. **Article 30 inventory drift.** New monitor classes (log-condition,
   custom-metric, span-attribute) push past the existing PA8 §(c) inventory
   unless explicitly enumerated and carved out.
3. **Scheduled-workflow detection gap.** 35 scheduled GitHub Actions workflows
   currently have zero "did this run?" detection. #3236 enumerates 5
   secret-touching workflows whose silent failure breaches the threshold.

The starting point is `apps/web-platform/scripts/configure-sentry-alerts.sh`
(176 lines, idempotent, env-var-driven) — a hand-rolled REST upserter for the
4 auth observability issue-alert rules. The script works but cannot model the
new monitor types and offers no drift detection for the rules it manages.

## Cluster / Host Glossary

Sentry's EU footprint splits along **three orthogonal routing axes** — URL slug
(which dashboard / API subdomain you reach), database cluster (which physical
EU ingest cluster serves DSN POSTs), and token-membership scope (which orgs an
`SENTRY_AUTH_TOKEN` can read or write). Conflating any two — most pointedly,
assuming `<org-slug>.sentry.io/api/0/organizations/<slug>/` returning 401 means
"the slug names an unowned third-party org" rather than "the token's membership
scope does not include this slug" — was the root inference failure that drove
the 2026-03-28 → 2026-05-16 ingest routing confusion documented in PIR
`knowledge-base/engineering/operations/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`
(see Phase 9 Gate-3b correction; both `jikigai` and `jikigai-eu` orgs were
operator-owned EU-database orgs throughout, per Sentry support replies
2026-05-19, and the duplicate `jikigai` org was canceled vendor-side on
2026-05-21). All future Sentry-touching work in this repo MUST reference this
glossary by name when choosing a host AND verify token-membership scope before
inferring ownership from any HTTP status.

| Host class      | Hostname(s)                                         | Serves                                                                                                                       | Does NOT serve                                                                            |
|-----------------|-----------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| **Ingest**      | `o<id>.ingest.de.sentry.io`, `o<id>.ingest.us.sentry.io` | DSN POSTs (`/api/<project_id>/store/`, `/api/<project_id>/envelope/`); cron-checkin beacons; CSP report-uri POSTs            | Settings UI; REST API; dashboard. Path-only POST sinks — no GET/PUT semantics.            |
| **Dashboard**   | `sentry.io`, `<org-slug>.sentry.io`, `eu.sentry.io` | Web UI: org settings, project settings, alerts, monitors, issue triage. **EU-region dashboard host is `eu.sentry.io`** (NOT `de.sentry.io`). | Ingest POSTs (event upload goes to `*.ingest.*.sentry.io`).                               |
| **API**         | `<org-slug>.sentry.io/api/0/...` (org-scoped), `eu.sentry.io/api/0/...` (region-wide / slug-less only), `us.sentry.io/api/0/...`, `sentry.io/api/0/...` (legacy global) | REST API: `/organizations/{slug}/`, `/projects/{org}/{project}/`, `/releases/`, `/users/me/`. **Org-scoped paths (`/organizations/<slug>/`, `/projects/<slug>/...`) MUST use the org-subdomain `<org-slug>.sentry.io/api/`** — see learning `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`. The `eu.sentry.io/api/` regional host silently rewrites slugs ending in `-eu` to the literal `eu` org via an `activeorg`-cookie hijack (302 → 401 cascade). Use it ONLY for slug-less endpoints (`/users/me/`, `/auth/*`). The bare `sentry.io/api/0/...` host is the legacy global API surface still probe-looped by `apps/web-platform/scripts/sentry-monitors-audit.sh` as a fall-through. | Event ingest (path-disjoint from `/api/<project_id>/store/`).                             |

**Implications for Terraform + audit tooling:**

- **Provider `base_url`** in `apps/web-platform/infra/sentry/main.tf` for EU
  region MUST be `https://<org-slug>.sentry.io/api/` (the org-subdomain) — NOT
  `https://eu.sentry.io/api/`. The regional host's slug-rewrite bug (see API
  row above + learning `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`)
  silently 401s every Terraform read/write for orgs whose slug ends in `-eu`.
  Setting it to `https://de.sentry.io/api/` produces silent 404s (ingest-only
  host has no `/api/0/...` surface). The org-subdomain is the only base_url
  shape that works for slug-scoped operations regardless of org slug.
  **Transition note (2026-05-16, updated 2026-05-17 for the slug-rewrite
  finding, updated 2026-05-21 for the token-scope correction):**
  `apps/web-platform/infra/sentry/main.tf` now uses
  `"https://${var.sentry_org}.sentry.io/api/"` (org-subdomain pattern) under
  `var.sentry_region == "de"`, landed by PR-β #3945 atomic with the tfstate
  drop + serial re-import sequence. The `de.sentry.io` and `eu.sentry.io`
  regional hosts are reserved for slug-less endpoints (`/users/me/`, `/auth/*`)
  per the API row above.
- **Audit script `api_host`** (`apps/web-platform/scripts/sentry-monitors-audit.sh`)
  region-probe loop MUST include `eu.sentry.io` (and prefer it over `sentry.io`
  for EU-resident orgs) — `de.sentry.io` will return 404 for every API call.
- **Operator-minted user tokens** are created via the dashboard host
  (`https://eu.sentry.io/settings/account/api/auth-tokens/`), not the ingest host.
- **DSN cluster substring** in `NEXT_PUBLIC_SENTRY_DSN` (e.g.
  `https://<key>@o<id>.ingest.de.sentry.io/<project_id>`) is the authoritative
  residency signal (per learning `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`)
  — it identifies the **ingest** cluster, which on the EU footprint is `de`-prefixed
  even though the controlling org's API + dashboard live at `eu.sentry.io`. This
  asymmetry is the glossary's reason for existing.

## Decision

Adopt Sentry as Infrastructure-as-Code via the `jianyuan/terraform-provider-sentry`
provider, scoped to:

- **Import** the 4 existing `auth-*` issue-alert rules into Terraform state
  using `terraform import` — names match `configure-sentry-alerts.sh`
  byte-for-byte to preserve operator dashboard queries.
- **Create** 8 net-new `sentry_cron_monitor` resources, one per scoped
  scheduled workflow currently on a `schedule:` block, with vendor-hosted
  heartbeat via the existing Sentry trust boundary (closes #3236). The
  plan originally enumerated 9; `scheduled-cf-token-expiry-check` is
  deferred (manual-dispatch only) and gets a 9th resource when its
  schedule re-lands.
- **Defer** migration from `sentry_issue_alert` (deprecated in v0.15-beta) to
  the new unified `sentry_alert` resource until provider GA.
  **Amendment (2026-05-29, #4610):** re-confirmed at v0.15.0-beta2 — `sentry_alert`
  is monitor-bound (`monitor_ids` + `trigger_conditions` both required, no `project`
  attr), so the 4 project-wide auth frequency rules cannot migrate without dropping
  live paging; defer stands until stable v0.15.0. Deprecation warning is documented
  as accepted in `issue-alerts.tf`. Evidence: plan `2026-05-29-refactor-sentry-issue-alert-to-sentry-alert-migration-plan.md`.
- **Defer** enabling new monitor classes (log-condition, custom-metric) until
  `apps/web-platform/server/sentry-scrub.ts` is extended to cover their event
  channels — enforced by Phase 6 GDPR-gate + AC9.

### Provider source

`jianyuan/sentry` v0.15.0-beta2 (released 2026-05-06). The competing
`getsentry/sentry` is a stale fork (last push 2024-06-24). Pinned to the exact
beta version; re-evaluate on first stable v0.15.0 release. **If the PR sits
open for >2 weeks, re-run Phase 0.1 of the plan** before merge.

### Per-app root

New Terraform root at `apps/web-platform/infra/sentry/`, sibling to the main
`apps/web-platform/infra/` root. Same R2 backend bucket, distinct state key
`web-platform/sentry/terraform.tfstate`. `use_lockfile = false` per R2's lack
of S3 conditional writes — same posture as the main root.

### Authentication / secret-store divergence

Sentry secrets stay in **GitHub repository secrets**, not Doppler:

- `SENTRY_IAC_AUTH_TOKEN` — provider auth, used by `terraform plan|apply` in
  `.github/workflows/apply-sentry-infra.yml`. The env var exposed to the
  terraform provider inside the workflow step is still named `SENTRY_AUTH_TOKEN`
  (the canonical Sentry provider env var); only the GitHub-secret-name has
  changed to make the IaC-specific role explicit and to permit independent
  rotation from the runtime `web-platform-ci` integration.
- `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` —
  DSN-derived (see plan Phase 0.8), consumed by the per-workflow check-in
  steps. Not read by Terraform.

This diverges from spec TR2 (which assumed Doppler). Rationale: keeping the
Sentry vendor's existing wiring contract uniform with the GitHub-Actions
runtime where the workflows execute reduces moving parts. R2 backend creds
remain in Doppler `prd_terraform` per the existing pattern in
`scheduled-terraform-drift.yml:54-65`.

**Why a dedicated Internal Integration, not the runtime `web-platform-ci`
token, and not an Org Auth Token (revised 2026-05-19):**

- The runtime `web-platform-ci` token covers `org:read`, `project:read`,
  `project:write`, `project:releases`, `org:ci` — wider than read-only but
  narrower than IaC needs. It lacks `alerts:write` for `sentry_issue_alert`
  rules, and reusing it for IaC would couple two distinct lifecycles
  (runtime check-ins + ad-hoc IaC applies) onto a single auth secret,
  defeating independent rotation.
- Sentry **Org Auth Tokens** have been narrowed to a single available scope
  (`org:ci` — source-map upload + release creation + code mappings); they
  no longer carry sufficient permission for project/alert/monitor
  resources. Path (c) in the 2026-05-19 triad re-spawn is empirically
  dead. Falsified at `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`
  Appendix B.
- Therefore the IaC token is provisioned as a **dedicated Internal
  Integration** named `iac-terraform-prd` on `jikigai-eu`, with permission
  set: Project=Admin, Issue & Event=Read, Organization=Read,
  Alerts=Read & Write, CI=checked, everything else No Access. This yields
  `auth.scopes = [alerts:read, alerts:write, event:read, org:read,
  project:admin, project:read, project:write]` — least-privilege for IaC
  while keeping `monitor:*` derivable via the `project:write` umbrella.
- Integration creation logs to the Organization Audit Log
  (`sentry-app.add`), providing §5(2) evidence of who provisioned the IaC
  identity — a property Personal Tokens do not have.

### Local-token source for operator runs

GitHub Actions exposes secret VALUES only inside workflow steps. For local
execution (Phase 2.1 audit, Phase 5 import), the operator can fetch the
same `SENTRY_IAC_AUTH_TOKEN` value from Doppler `soleur/prd` (where it is
mirrored for runtime introspection convenience), or mint a separate
personal token from
`https://jikigai-eu.sentry.io/settings/account/api/auth-tokens/` with
scope `project:read` + `monitor:read` (audit) and `project:write`
(import). Operator-personal tokens are never committed.

### DE region support

The Sentry EU API + dashboard live at `eu.sentry.io`; `de.sentry.io` is an
**ingest-only** host that does not serve API or settings UI (audit/import
calls return 404). The canonical EU API base_url is therefore
`https://eu.sentry.io/api/` — set on the Terraform provider config in
`apps/web-platform/infra/sentry/main.tf` whenever `var.sentry_region = "de"`.
See `Cluster / Host Glossary` above for the full host-class split and the
Sentry-residency cascade learning at
`knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`
for the failure mode this prose corrects.

### Auto-apply on push-to-main (cron + uptime monitors)

`.github/workflows/apply-sentry-infra.yml` fires on push to `main` when
`apps/web-platform/infra/sentry/cron-monitors.tf` changes. It runs
`terraform apply -target=sentry_cron_monitor.* -auto-approve` so the 8
monitors exist within ~2 minutes of merge, closing the window where check-in
curls would 404. Issue-alert resources stay import-only post-merge per AC13.

**Amendment (2026-05-29, #4585):** the auto-apply scope now also includes the
4 `sentry_uptime_monitor.*` resources (`uptime-monitors.tf`), previously
operator-applied. The workflow uses the **saved-plan shape**
(`terraform plan -target=... -out=tfplan` → destroy-guard on
`terraform show -json tfplan` → `terraform apply tfplan`), not the inline
`-apply -target` form described above — the `-target=` allow-list lives in the
plan step only, and apply consumes the saved `tfplan` so plan-targets ==
apply-targets. `sentry_uptime_monitor` exposes zero array-of-blocks (all
attrs scalar; `assertion_json` is a function-built string), so the
destroy-guard's `nested_deletes: 0` posture stays correct without a per-type
jq clause. `sentry_issue_alert.*` remains import-only.

**Amendment (2026-05-30, #4656):** two BYOK Art. 33 hardening notes.
(1) `sentry_issue_alert.byok_art_33_breach` now uses `action_match = "any"` over
three event-lifecycle conditions (`first_seen_event` + `reappeared_event` +
`regression_event`) — the **only** rule in `issue-alerts.tf` using `"any"` (the
6 others use `"all"`); required because the three lifecycle states are
mutually-exclusive, so `"all"` would be unsatisfiable. (2) A read-only
post-apply liveness control (`apps/web-platform/scripts/assert-byok-rules-exist.sh`)
asserts both BYOK rules exist in Sentry by name after every apply, fail-closed.
It is deliberately existence-by-name (not filter-shape): the filters are
TF-owned and re-asserted on each apply, so a post-apply existence check is the
minimal sufficient signal for the apply-time mis-wire failure mode.

**Amendment (2026-06-03, #4849):** a third apply-created issue-alert rule,
`sentry_issue_alert.chat_message_save_failure`, joins the auto-apply `-target`
set. It is the chat write-absence liveness alert — pages on any
interactive-message INSERT failure in `dispatchSoleurGo` via `op IS_IN`
{`tenant-mint.persistUserMessage`, `persistUserMessage.workspaceRead`,
`persist-user-message`} + `feature == cc-dispatcher` (`filter_match = "all"`,
`action_match = "any"` like `byok_art_33_breach`). Same apply-created posture
(`lifecycle.ignore_changes = [environment]` only). Its name is added to
`assert-byok-rules-exist.sh` `EXPECTED_RULES` (the script is now generically
"issue-alert detector liveness"), and a cross-artifact contract test
(`test/sentry-chat-alert-op-contract.test.ts`) pins the op/feature filter values
against the emit site in `cc-dispatcher.ts`. No guard/jq/scope-guard edit: it is
the already-covered `sentry_issue_alert` type. Apply-created issue-alert count is
now 3 (`byok_art_33_breach`, `byok_cap_exceeded`, `chat_message_save_failure`);
the 4 `auth-*` rules remain import-only.

**Amendment (2026-06-17, #5495) — read-only inline-read credential class.** This ADR's
credential taxonomy (`Authentication / secret-store divergence` above) now records a third
class alongside the IaC token and the runtime check-in token: a **read-only Internal
Integration `inline-read-prd`** with the minimal permission set **Issue & Event = Read,
Organization = Read, everything else No Access** → scopes `[event:read, org:read]`. Its token
`SENTRY_ISSUE_RO_TOKEN` lives in **Doppler `soleur/prd`** (not GitHub secrets — unlike the IaC
token — because it is consumed by an inline CLI under `doppler run`, mirroring
`SENTRY_ISSUE_RW_TOKEN`). It backs `scripts/sentry-issue.sh`, a GET-only inline reader for
no-SSH agent debugging (issue-detail + latest-event by id). Rationale: the issue/event
endpoints require `event:read`, which `SENTRY_API_TOKEN`/`SENTRY_AUTH_TOKEN` lack (they 403 on
`/issues/<id>/`); reusing the `event:admin` `SENTRY_ISSUE_RW_TOKEN` for a read path is
over-scoped, so a least-privilege read token is the data-minimisation-aligned posture
(CLO; Art. 30 PA-08 touched). **Mint path:** the Sentry provider exposes no Terraform token
resource, so the token is minted by Soleur automation — Playwright against the `eu.sentry.io`
dashboard (primary; the `POST …/sentry-apps/` API path needs `org:admin`, which no existing
token carries and which public docs do not confirm), not an operator UI step. **Host:** the
org-subdomain `jikigai-eu.sentry.io` per the Cluster/Host Glossary (NOT `de.sentry.io`, which
is ingest-only). **Scope note:** the inline read CLI is a **read path, not a sixth/seventh
observability layer** — `observability-coverage-reviewer` must not accept it as a
`failure_modes:` layer citation. Runbook
`knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`.

**Amendment (2026-07-13, #6374) — GHA-workflow-heartbeat-slug parity guard extends the
`-target` allowlist invariant.** The existing Inngest-cron parity guard
(`sentry-monitor-iac-parity.test.ts`) was one-way (`server/inngest/functions/` slugs →
`cron-monitors.tf`) and explicitly EXCLUDED GHA-workflow heartbeat slugs. The #6374 P1
outage (a `[ci/inngest-down]` alarm ran ~14h unseen) root-caused to exactly that gap: the
`scheduled-inngest-health.yml` workflow POSTed a Sentry heartbeat to the slug
`scheduled-inngest-health`, but no `sentry_cron_monitor` resource carried that `name`, so
Sentry silently dropped the error check-in and the operator was never paged. The parity test
now ALSO asserts every `.github/workflows/*.yml` `monitor-slug:` has BOTH (a) a matching
`sentry_cron_monitor.name` in `cron-monitors.tf` AND (b) that resource in the
`apply-sentry-infra.yml` `-target=` allowlist — because the auto-apply builds a SAVED plan
against an explicit `-target` set (2026-05-29 amendment above), a monitor absent from that
list is declared-but-never-applied (green CI, dark alarm). Guarding only clause (a) would
pass while the monitor never materialised; both clauses are load-bearing. This makes
"heartbeat into the void" and "applied nowhere" structurally impossible for GHA workflows,
mirroring the Inngest-cron guard.

## Consequences

### Positive

- **Deterministic state.** The 4 issue-alert rules' configuration is now
  expressible in code; drift is detectable via `terraform plan` and routable
  through the existing `scheduled-terraform-drift.yml` matrix (follow-up).
- **Vendor-hosted heartbeat.** Closes #3236 without standing up a separate
  cron-pinger service or changing CI infrastructure.
- **Import-not-recreate posture.** Imports preserve operator-keyed names
  byte-for-byte; Phase 0.5 grep verifies post-merge invariance.

### Negative

- **Beta-provider risk.** v0.15.0-beta2 may yank or change `*_v2` attribute
  shapes. Mitigated by exact-version pin + `lifecycle.ignore_changes` on
  `[conditions_v2, filters_v2, actions_v2, environment, frequency]` for the
  4 imported rules. Re-evaluate at first stable v0.15.0.
- **Dual secret-store posture.** Operators must remember Sentry secrets are
  in GH Actions, not Doppler. Mitigated by README.md cheatsheet at the root.
- **Scope leakage risk.** Future "while we're here" PRs may try to migrate to
  `sentry_alert` (the new beta unified resource) prematurely. NG9 of the plan
  explicitly forbids this until provider GA.

## Escape hatches

If any of the following triggers fire, revert Phase 5 of #3814:

- **DE region smoke test fails.** Phase 0.1.5 does not return a non-empty
  `data.sentry_organization.this.internal_id` against the scratch project.
- **terraform plan shows non-trivial drift on >1 of 4 imported rules.**
  v2-attribute drift is expected and handled by `ignore_changes`; novel
  drift (e.g., the provider rejecting our `name` field) is not.
- **3+ retries fail on `terraform import`** — the provider's import handler
  is incompatible with our rule shape.

Escape-hatch action: leave `configure-sentry-alerts.sh` as source of truth,
mark this ADR `status: rejected`, revert the `apps/web-platform/infra/sentry/`
directory and `.github/workflows/apply-sentry-infra.yml`, and re-evaluate
on next provider release.

## Validation gate

This ADR is validated by:

- **AC7:** `terraform fmt -check` clean; `terraform init -backend=false &&
  terraform validate` passes.
- **AC13:** First `terraform import` of all 4 rules followed by `terraform plan`
  is no-op (modulo lifecycle-ignored v2 drift).
- **AC14/AC15:** API-GET (per `hr-no-dashboard-eyeball-pull-data-yourself`)
  confirms the 8 cron monitors exist and the first scheduled run of each
  workflow produces a recognized check-in.
- **AC16:** One full `reusable-release.yml` cycle ships under Terraform
  management with the audit artifact uploaded.

## DHH dissent (kept for re-evaluation)

DHH-style review at plan time argued for cutting Phase 5 entirely: leave the
working 176-line script alone for 4 unchanging rules; wait for a second
Sentry change before paying IaC ceremony. The decision rejected this for the
current PR because (a) #3815 multi-tenant DPA work assumes the IaC foundation,
(b) the 8-workflow Crons scope closes #3236 independently (a 9th workflow
joins when `scheduled-cf-token-expiry-check` re-schedules). **Re-evaluate
trigger:** if the escape-hatch criteria above fire, the dissent becomes the
operative reframe.

See plan §"Open Questions" OQ4 for the full dissent text and re-evaluation
criteria.
