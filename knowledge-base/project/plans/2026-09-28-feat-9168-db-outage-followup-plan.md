---
title: "9168 — DB-outage paging path + bounded Supabase auto-restart"
date: 2026-09-28
slug: 9168-db-outage-followup
branch: feat-9168-db-outage-followup
issue: 9168
lane: cross-domain
brand_survival_threshold: single-user incident
closes: [9168]
---

# Plan: page a human on DB outage + auto-restart on the proven Postgres-hang signature

## Overview

Second identical Supabase Postgres hang in 13 days (09-15, 09-28): the
`app_health` keyword monitor detected it at +7 min but paged only an inbox
(email-only), and recovery needed an operator-acknowledged Management API
restart performed by a human who was never told anything was wrong. This plan
(A) makes monitor incidents reach the operator's phone via the free-tier Slack
integration plus a measured `push` flip, and (B) removes the human from the
recovery path for the proven signature via a bounded auto-restart watchdog,
plus (C) a Micro→Small compute bump through the `supabase/supabase` Terraform
provider, a 09-28 postmortem, a drafted Supabase support ticket, and ADR-259.

## Research Insights

**Premise validation (Phase 0.6 / brainstorm):** every claim in #9168 verified
live — `app_health` is `email=true, call/sms/push=false, policy_id=null` (API
read 2026-09-28); `TF_VAR_BETTERSTACK_PAID_TIER` absent from Doppler
`prd_terraform`; PRs #8216/#9099 merged; 09-15 postmortem exists; no 09-28
postmortem exists yet; `/api/v2/slack-integrations` returns `{"data":[]}` (no
Slack integration connected); `/api/v2/on-calls` shows a default calendar with
zero users. Two operator corrections folded back: the `supabase/supabase`
provider DOES exist upstream (v1.9+ manages `instance_size` via the
billing/addons PATCH) — my earlier "no provider" claim conflated "absent from
our root" with "doesn't exist"; and the status page IS live at
`soleur-ai.betteruptime.com` (the archived spec's `Issue: TBD` was a stale
signal, not evidence of unshipped).

**Property list (Phase 0.6b):** (a) alert reaches a human device —
existing `push`/`call`/`sms` attrs and `policy_id` wiring are dormant, Slack
integration absent; (b) recovery on proven signature without human-in-loop —
no Supabase restart automation exists anywhere (`git grep` confirms; nearest
precedent is the Inngest-watchdog label→dispatch chain); (c) compute size is
IaC-manageable — `supabase_project.instance_size` exists upstream but the
provider is undeclared in the root; (d) incident evidence is durable — the
postmortem + ticket draft + ADR artifacts have no existing owner.

**Cut list:** nothing cut — every mechanism named in the issue buys a property
not already covered. The `betteruptime_outgoing_webhook` path was considered
and rejected: raw webhook payloads are not Slack-format-compatible, and the
native Slack integration is the free-tier channel Better Stack actually
supports.

**Key measurements:** Better Stack free tier = Slack + email only (live
pricing 2026-09-28); Responder seat $29–34/mo declined by operator;
`expenses.md` Responder deferral trigger (#3960, "first incident with
user-visible latency from email-only routing") has fired — recorded in ADR.
Supabase Small = ~$15/mo vs Micro $10/mo covered by the Pro credit (+$5/mo
net). GHA `schedule:` measured to drift 2–7h (ADR-248) — so the watchdog's
primary trigger MUST NOT be `schedule:` alone. The dispatch clock runs in the
web process, which stays up through this failure class (Postgres hangs; the
Node process keeps serving `/health` with `supabase:error`).

**Research reconciliation:** no contradictions between leader assessments and
repo research. Repo-research note that "push may be free-tier-compatible" is
handled by measuring `push=true` on `app_health` at apply (#7798 precedent) —
not assumed.

**Open-PR overlap (Phase 1.7.5):** open PRs touching supabase/infra files
(#9179, #9051, #8820, #8192, #7390) — none touch `uptime-alerts.tf`,
`watchdog-dispatch-table.ts`, or the files this plan edits. No collision.

## Files to Create

- `.github/workflows/scheduled-supabase-watchdog.yml` — the watchdog:
  `workflow_dispatch` + `schedule:` fallback (`*/5`),
  `concurrency: supabase-watchdog` with `cancel-in-progress: false` (the mutex
  — serializes runs regardless of which host dispatched, per advisor consult),
  `issues: write` permission. Steps: fetch Management API health (3 reads
  spaced ~60s), run classifier, **dark-launched behind a `WATCHDOG_ARMED`
  env gate — ships detect-only first** (`wg-dark-launch-deploy-gates`: a new
  prod-write mechanism is observed on real signals before it acts), then
  conditionally POST restart, file/update labeled audit issue, Sentry
  check-in. Dispatch auth is the GitHub App token (`generateInstallationToken`
  per `hr-github-app-auth-not-pat`), never a PAT.
- `scripts/supabase-watchdog-classify.sh` — pure classifier:
  health-responses + corroborating-signal read → `hang-signature` |
  `healthy` | `ambiguous` | `probe-unavailable`. Bearer-on-stdin transport per
  `supabase-logs-query.sh`.
- `scripts/supabase-watchdog-classify.test.sh` — unit tests incl. the
  `probe-unavailable`-never-restarts case, the missing-corroboration case,
  and the give-up path.
- `apps/web-platform/server/inngest/functions/cron-supabase-watchdog-dispatch.ts`
  — Inngest cron emitting `workflow_dispatch` for the workflow every 5 min
  (the `cron-main-health-monitor.ts` pattern). Holds NO Supabase credential —
  dispatches only. Registered in `cron-manifest.ts`.
- `knowledge-base/engineering/operations/post-mortems/prd-supabase-database-unreachable-2026-09-28-postmortem.md`
- `knowledge-base/engineering/operations/ticket-drafts/supabase-postgres-hang-recurring-2026-09.md`
  — minimized evidence pack for the operator's dashboard submission.
- `knowledge-base/engineering/architecture/decisions/ADR-259-*.md`
  (ordinal provisional — ship gate re-verifies next-free).
- `apps/web-platform/infra/supabase-project.tf` — `import` block +
  `supabase_project.prd` **pinned to all live values, `instance_size =
  "micro"`** (drift-free zero-diff import; the Small flip is a separate
  follow-up apply — see Apply path).
- `apps/web-platform/infra/.terraform.lock.hcl` diff — the new provider's
  lockfile entry (CI runs `init -lockfile=readonly`,
  `apply-web-platform-infra.yml`).

## Files to Edit

- `apps/web-platform/infra/uptime-alerts.tf` — `push = true` on
  `app_health` only (measured first; revert-on-422 plan in PR body).
- `apps/web-platform/infra/main.tf` — add
  `supabase = { source = "supabase/supabase", version = "<pin ≥7d old>" }` to
  `required_providers` (they live in `main.tf`, not `versions.tf` — this root
  has none) and `provider "supabase" { access_token =
  var.supabase_access_token }`. Env-var auth does NOT work: CI injects only
  `TF_VAR_*` (`doppler run --name-transformer tf-var`), and
  `var.supabase_access_token` already exists (`variables.tf`, sourced from
  Doppler `prd_terraform`) — no new sensitive var.
- `apps/web-platform/server/inngest/cron-manifest.ts` — register the dispatch
  cron (whatever registration contract the manifest imposes).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — Sentry cron monitor for
  the watchdog workflow (margin budget per the file's convention).
- `.github/workflows/apply-web-platform-infra.yml` — `-target` allowlist entry
  for `supabase_project.prd` (parity: `terraform-target-parity.test.ts`;
  untargeted plans skip imports silently — measured at
  `seo-config-rules.tf`'s import precedent).
- `knowledge-base/engineering/operations/runbooks/app-database-readiness-alarm.md`
  — Slack as primary channel; auto-restart behavior; note ops@ invite.
- `knowledge-base/engineering/architecture/diagrams/model.c4` +
  `views.c4` — add `slack` external system, `betterstack -> slack` and
  `slack -> founder` edges; add `github -> supabase` Management-API edge
  (the watchdog; also corrects the existing unmodeled Management-API callers);
  update the `betterstack -> founder` edge prose (email → Slack+push).
- `knowledge-base/operations/expenses.md` + `knowledge-base/finance/cost-model.md`
  — Small compute +$5/mo net recorded when the flip lands.

## Domain Review

Carried forward from the brainstorm (`## Domain Assessments`):

- **Product (CPO):** GO with conditions — the silence is the brand damage;
  eliminate "user learns we're down before we do".
- **Legal (CLO):** GO with conditions — Art. 32(1)(c) compliance-positive; ADR
  must record the restart-authorization delegation + audit trail + circuit
  breaker; ticket payload minimized; note unsigned Better Stack DPA (#7529).
- **Engineering (CTO):** GO with conditions — Slack is the $0 path; measure
  `push` on one monitor; watchdog on GH substrate, restart only on the proven
  signature; compute is mitigation not fix.
- **Operations (COO):** GO with conditions — Small defensible at +$5/mo;
  expenses.md/cost-model.md rows updated; operator steps: Slack OAuth, ticket
  submission, ops@ invite acceptance.

## User-Brand Impact

- **Artifact:** the `app.soleur.ai` availability surface and its paging path.
- **Vector:** a silent outage — a user finds the product dead while we don't
  know; for an autonomous-engineering product the detection failure is the
  story.
- **Threshold:** `single-user incident` — CPO sign-off captured via the
  brainstorm domain assessment (carried forward above);
  `soleur:engineering:review:user-impact-reviewer` remains the review-time
  gate.

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in from scheduled-supabase-watchdog.yml each run
  cadence: every 5 min (Inngest-dispatched workflow_dispatch; schedule: fallback)
  alert_target: sentry_cron_monitor (new row in cron-monitors.tf) -> Sentry issue -> email (+ Slack once wired)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: Sentry (heartbeat error check-in) + GitHub issue labeled supabase-auto-restart
  fail_loud: a run that detects the hang signature files/updates the audit issue AND posts an error check-in; a missing check-in pages via the monitor margin

failure_modes:
  - mode: Postgres hang signature present
    detection: classifier exits hang-signature after 3 consecutive matching reads
    alert_route: restart issued + audit issue + Slack (via app_health monitor firing too)
  - mode: watchdog itself dead (dispatch clock or Inngest down)
    detection: missing Sentry check-in inside margin
    alert_route: Sentry cron monitor alert
  - mode: restart issued but services never recover
    detection: post-restart re-probe still UNHEALTHY
    alert_route: give-up branch files priority issue + Slack alert
  - mode: probe unavailable (Management API down / token invalid)
    detection: classifier exits probe-unavailable; NEVER restarts
    alert_route: audit issue + error check-in

logs:
  where: GHA run logs + Sentry check-in payloads + audit-issue history
  retention: GHA 90d; Sentry per project retention

discoverability_test:
  command: bash scripts/supabase-watchdog-classify.sh --self-test
  expected_output: "hang-signature"
```

## Encryption Posture

New cross-component connection: GHA runner → `api.supabase.com` Management API
(health GET + restart POST), and GHA runner → Slack is NOT added (Slack is
Better Stack→Slack vendor-side).

```yaml
in_transit:
  - connection: GHA runner -> api.supabase.com (Management API)
    enforced_at: scripts/supabase-watchdog-classify.sh (pinned host, --noproxy '*', --disable, bearer-on-stdin — same contract as scripts/supabase-logs-query.sh)
    tls: HTTPS TLS >= 1.2 (curl default verification)
    cert_verification: on
    does_not_defend: a stolen SUPABASE_ACCESS_TOKEN (bearer token is the credential; a leak grants project admin — mitigated by GHA secret scoping, not stored in repo)
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — restart-signature classifier

**Property.** A restart is issued only when EVERY consecutive health read in
the window shows the proven hang signature — `db`, `auth` and `rest` UNHEALTHY
while the pooler reports a healthy state — AND an independent corroborating
signal agrees (app `/health` reporting `supabase` non-`connected`, or the
`app_health` Better Stack monitor currently down): the Management API is a
single failure surface, so signature + corroboration must both hold. No other
combination, incompleteness, corroboration absence, or probe failure may
trigger a restart.

**Assembly.** The single chokepoint is `supabase-watchdog-classify.sh`'s
verdict — every restart path in `scheduled-supabase-watchdog.yml` consumes
only that verdict; there is no second restart path. The property quantifies
over all health-service verdicts the Management API can return
(UNHEALTHY/ACTIVE_HEALTHY/COMING_UP/UNREACHABLE/missing-key) crossed with the
corroborator's states (down / up / unreadable), not just the 09-28 observed
set. Runs serialize on the `concurrency: supabase-watchdog` group
(`cancel-in-progress: false`) and the workflow re-reads the last restart
timestamp from the audit issue before writing — the issue is the audit trail,
the concurrency group is the mutex.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Classifier treats `pooler UNHEALTHY` + db/auth/rest UNHEALTHY as hang-signature | RED — total-outage shape must not match |
| 2 | A mid-window read returns `COMING_UP` or a missing `db` key | RED — signature broken mid-window cancels restart |
| 3 | Signature holds but the corroborator is absent/healthy (app /health returns `supabase: connected`) | RED — single-surface agreement never restarts |
| 4 | Fixture returns HTTP 200 with a wholly-healthy body | PASS — healthy never restarts |
| 5 | Remove the ≥3-reads sustained check (single read decides) | RED — suite must pin the window, not just the signature |
| 6 | Classifier exits 0 with an empty/unparseable response | RED-equivalent: exit must be non-zero AND verdict `probe-unavailable` (an exit-0 hang-verdict on garbage is the vacuous arm) |
| 7 | Cooldown marker says a restart happened <cooldown ago and a second hang is seen | RED — no second restart inside cooldown |
| 8 | `WATCHDOG_ARMED` unset and signature + corroboration hold | RED on the write path: run must end detect-only (audit issue + check-in, zero restart POST) |

**Anchor.** The classifier's signature table lives in the test file's fixture
set — an edit weakening the signature AND its fixture in one commit is caught
by review + the mutation-row discipline, not by a stored hash (no external
anchor applies to a pure predicate).

## Infrastructure (IaC)

### Terraform changes

- `uptime-alerts.tf` — `push = true` on `betteruptime_monitor.app_health`
  (already in the `-target` allowlist, `apply-web-platform-infra.yml`).
- `main.tf` — add `supabase = { source = "supabase/supabase", version = "<pin
  ≥7d old>" }` to `required_providers` (they live in `main.tf`, not
  `versions.tf` — this root has none) and `provider "supabase" { access_token
  = var.supabase_access_token }`. Env-var auth does NOT work in CI: the apply
  injects only `TF_VAR_*` (`doppler run --name-transformer tf-var`).
  `var.supabase_access_token` already exists (`variables.tf`) sourced from
  Doppler `prd_terraform` — no new sensitive var. Commit the
  `.terraform.lock.hcl` diff (CI `init -lockfile=readonly`).
- `supabase-project.tf` — one-time `import { to = supabase_project.prd, id =
  "ifsccnjhymdmidffkzhl" }` (literal ref — matches `dns.tf` precedent;
  `SUPABASE_PROJECT_REF` lives in Doppler `prd` not `prd_terraform`), plus:

  ```hcl
  resource "supabase_project" "prd" {
    organization_id         = "vttwegzidmuaiefjlysl" # measured /v1/organizations
    name                    = "soleur-web-platform"  # measured /v1/projects/<ref>
    region                  = "eu-west-1"            # same read
    database_password       = "unmanaged-9168"       # never applied — see lifecycle
    instance_size           = "micro"                # pin LIVE; Small flip is a follow-up PR
    legacy_api_keys_enabled = true                   # measured /api-keys/legacy
    lifecycle { ignore_changes = [database_password] }
  }
  ```

  **Critical (terraform-architect finding):** post-import, state holds
  `database_password = null` (the API never returns it) while the provider's
  Update PATCHes a dedicated db-password endpoint on any diff — so
  `ignore_changes = [database_password]` is mandatory or the first apply
  rotates the live DB password and breaks every stored DSN. Same logic pins
  `name`/`organization_id`/`region`/`legacy_api_keys_enabled` to live values
  measured pre-merge.
- `apply-web-platform-infra.yml` — append `-target=supabase_project.prd`;
  a `-target` set excluding an import's `to` skips it silently (measured
  precedent), so the line is required, and untargeted plans (drift detector,
  `infra-validation.yml` gate) will otherwise plan the import forever.

### Apply path

Two merges:

1. **This PR:** provider + import pinned to live `instance_size = "micro"` +
   `push = true` — zero-downtime, expected "1 to import" only.
2. **Follow-up:** flip `instance_size = "small"` — the ~2 min resize, applied
   while the operator watches (tracked in #9168 checklist / ADR-259).

Pre-merge Phase-0 verification — **already measured at plan time**
(2026-09-28, existing PAT): `GET /v1/projects/ifsccnjhymdmidffkzhl` →
`name: "soleur-web-platform"`, `organization_id: "vttwegzidmuaiefjlysl"`,
`region: "eu-west-1"`, `status: ACTIVE_HEALTHY`, postgres 17.6 ga;
`GET /v1/organizations` → org slug `vttwegzidmuaiefjlysl` ("Jikig AI");
`GET …/billing/addons` → only `custom_domain` (`cd_default`), i.e. **no
compute addon selected = live `instance_size = "micro"`**, and the PAT's scope
reaches the billing endpoint; `GET …/api-keys/legacy` → `{"enabled": true}`.
The resource block can therefore be written fully concrete, no placeholders.

### Distinctness / drift safeguards

- `supabase_project.prd` MUST be imported, never created — the `import` block
  pins the existing project ref.
- `database_password` uses a never-applied placeholder + `ignore_changes`
  (see above); `SUPABASE_DB_PASSWORD` is NOT pulled into `prd_terraform` for
  this.
- Dev/prd distinctness: provider block covers only the prd project; no dev
  import (no dev outage history).
- Secret values: `SUPABASE_ACCESS_TOKEN` stays in Doppler — never written to
  `.tf`.
- The one-time `import {}` block is removed in the follow-up PR post-apply
  (repo convention per ADR-222; an orphaned import makes a vendor-side
  deletion abort every untargeted plan).

### Vendor-tier reality check

- Better Stack: `push = true` may 422 or no-op on the current plan — measured
  on `app_health` alone first; revert documented in the PR body.
- Supabase provider: `instance_size` updates PATCH `billing/addons` and
  require Pro (held) + a token whose scope reaches billing addons — proven by
  the pre-merge `GET …/billing/addons` read; if refused, the flip degrades to
  a documented operator dashboard step recorded in ADR-259.
- `legacy_api_keys_enabled` MUST be pinned to the measured live value (expect
  `true`) — if unset/unpinned the provider's Update can PUT the legacy-keys
  endpoint and disable JWT keys the app uses.

## Architecture Decision (ADR/C4)

- **ADR:** create **ADR-259** (provisional ordinal — ship gate re-verifies):
  "DB-outage paging via Slack + bounded auto-restart on the proven Supabase
  hang signature" — records the Responder-deferral discharge, the
  pre-authorized prod-write delegation (deviation from
  `hr-menu-option-ack-not-prod-write-auth`), the signature/cooldown/give-up
  contract, the Micro→Small rationale, and the unsigned-DPA note (#7529).
- **C4 views:** Container view — new `slack` external system element +
  `betterstack -> slack` "incident alerts" + `slack -> founder` "mobile push"
  edges; new `github -> supabase` "Management API health probe + restart"
  edge; amend `betterstack -> founder` prose (adds Slack/push channel);
  verify `views.c4` `include` lines so new elements render. Checked against
  all three `.c4` files: `slack` element absent (grep); `github`, `supabase`,
  `betterstack`, `founder` present; no `github -> supabase` edge exists despite
  two existing Management-API callers (model gap fixed by this edit).
- **Sequencing:** ADR-259 is authored in this PR at `status: accepted` for the
  alerting portion and documents the auto-restart delegation as accepted —
  both ship together.

## Acceptance Criteria

- [ ] AC1: `terraform plan` post-merge shows `betteruptime_monitor.app_health`
  with `push = true` and `supabase_project.prd` imported **pinned to live
  values incl. `instance_size = "micro"`** — expected "1 to import", no other
  diffs (`-target` scoping). The `small` flip is a follow-up PR.
- [ ] AC2: `supabase-watchdog-classify.test.sh` green, covering:
  signature+corroboration → restart verdict; signature-without-corroboration →
  no restart; pooler-also-unhealthy → no restart; probe-unavailable → never
  restart; mid-window recovery → no restart; cooldown → no second restart;
  `WATCHDOG_ARMED` unset → detect-only even on a full signature.
- [ ] AC3: `scheduled-supabase-watchdog.yml` carries `workflow_dispatch` +
  `schedule:` triggers and `concurrency: supabase-watchdog` with
  `cancel-in-progress: false`; the workflow re-reads the audit issue's last
  restart timestamp before writing; dispatch auth is GitHub App token.
  Dark-launch: `WATCHDOG_ARMED` unset → zero restart writes, ever.
- [ ] AC4: A new Sentry cron monitor covers the watchdog; the runbook's
  "which alarm" table and `apply-web-platform-infra.yml` `-target` allowlist
  are updated; `terraform-target-parity.test.ts` stays green.
- [ ] AC5: Postmortem (09-28), ticket draft, and ADR-259 committed; issue
  #9168 references them; model.c4/views.c4 updated with slack + github→supabase
  edges and C4 validation tests pass.
- [ ] AC6: No new secrets in the repo; `SUPABASE_ACCESS_TOKEN` /
  `SUPABASE_PROJECT_REF` reused from Doppler; token never in argv (bearer-on-
  stdin transport).
- [ ] AC7: expenses.md + cost-model.md updated for the Small compute delta and
  the Responder deferral's fired-trigger note.
- [ ] AC8: `lifecycle { ignore_changes = [database_password] }` present on
  `supabase_project.prd` and `legacy_api_keys_enabled`/`name`/`region`/
  `organization_id` pinned to the values measured by the pre-merge Management
  API reads.

## Test Scenarios

- Given db+auth+rest UNHEALTHY & pooler healthy for 3 consecutive reads AND
  app `/health` reports `supabase` non-connected, when the workflow runs
  armed, then a restart POST is issued and an audit issue is filed.
- Given the full signature but `/health` reports `connected`, when the
  workflow runs, then no restart (corroboration absent → audit note only).
- Given the same services UNHEALTHY but pooler also UNHEALTHY, when the
  workflow runs, then no restart (ambiguous → audit issue only).
- Given a Management API 401/timeout, when the workflow runs, then
  `probe-unavailable`, an error check-in, and NO restart call.
- Given the full signature with `WATCHDOG_ARMED` unset (dark-launch), when the
  workflow runs, then detect-only: audit issue + check-in, zero restart POST.
- Given a restart issued <cooldown ago and the signature re-appears, when the
  workflow runs, then no second restart and the audit issue notes the cooldown.
- Given K consecutive post-restart failures, when the give-up threshold hits,
  then escalation to a priority issue + Slack ping, and no further restarts.
- Given `push = true` apply refuses on the current plan, when the apply fails,
  then the revert step restores `push = false` and the ADR records the
  measurement.
- **API verify (post-merge):** `curl -s https://app.soleur.ai/health | jq -r
  .supabase` expects `connected`; Better Stack monitor read-back shows
  `push: true` on 4226366 (readonly token, runbook's own probe).

## Success Metrics

- MTTD→human-aware < 5 min (Slack) vs ~16 min (this incident).
- MTTR for the proven signature ≈ probe + restart ≈ 10 min without a human,
  vs 37 min.
- Zero unattended restart loops (cooldown + give-up bound).

## Dependencies & Risks

- Better Stack Slack connect is an operator OAuth step (dashboard) — the
  alerting half's value lands only after it; tracked in the issue checklist.
- Supabase provider `instance_size` PATCH may need a billing-scope token —
  fallback is a documented operator dashboard step (recorded in ADR-259, and
  the import still lands the project under IaC).
- The compute apply incurs ~2 min downtime — sequenced as its own `-target`
  apply.
- ADR-259 ordinal is provisional (ship gate re-verifies).

## References & Research

- Issue: #9168; brainstorm:
  `knowledge-base/project/brainstorms/2026-09-28-9168-db-outage-alerting-autorestart-brainstorm.md`;
  spec: `knowledge-base/project/specs/feat-9168-db-outage-followup/spec.md`.
- Prior incident: `post-mortems/prd-supabase-database-unreachable-2026-09-15-postmortem.md`;
  runbook `runbooks/app-database-readiness-alarm.md`; ADR-222 (monitor
  adoption); ADR-248 (dispatch-clock vs schedule: drift); ADR-204
  (vendor-isolation + measure-first convention); ADR-079/ADR-249 (prod-write
  authorization posture); ADR-169 (independence criterion — the Management
  API is control-plane, satisfying it).
- Precedent workflows: `.github/workflows/scheduled-inngest-health.yml`
  (external watchdog shape, dispatch-clock triggers comment),
  `apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts`
  (Inngest→workflow_dispatch pattern),
  `apps/web-platform/scripts/postgrest-reload-schema.sh` (Management-API
  transport contract).
- Transport/auth: `SUPABASE_ACCESS_TOKEN` + `SUPABASE_PROJECT_REF` already in
  Doppler `prd` and `prd_terraform`; read-only Better Stack token already
  exercised (monitor/policy/integration probes this session).
