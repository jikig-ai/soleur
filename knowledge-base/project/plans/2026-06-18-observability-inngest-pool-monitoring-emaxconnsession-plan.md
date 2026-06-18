---
title: "observability(inngest): connection-pool monitoring + EMAXCONNSESSION classification in the health watchdog"
type: feat
date: 2026-06-18
lane: cross-domain
issue: 5562
brand_survival_threshold: aggregate pattern
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: the only "infra provisioning" here is publishing an
     EXISTING account-scoped Supabase PAT to a GH Actions secret, which IS routed
     through Terraform (github_actions_secret resource sourced from a no-default
     TF_VAR — see ## Infrastructure (IaC)). The residual `doppler secrets set`
     references are the unavoidable out-of-band mint of an account-scoped Supabase
     PAT (sbp_…): Supabase exposes no creation API for account PATs, so the value
     cannot be minted by a doppler_secret/random_id resource — identical to the
     INNGEST_POSTGRES_URI (inngest.tf:162-176) and resend_receiving_api_key
     (variables.tf:157) out-of-band-minted patterns already accepted under
     hr-tf-variable-no-operator-mint-default. TF only PUBLISHES the value. -->

# observability(inngest): connection-pool monitoring + EMAXCONNSESSION classification in the health watchdog

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Architecture, Phase 2 (probe step), Phase 3 (repoint), Infrastructure (IaC), Acceptance Criteria, QG3
**Review agents used:** security-sentinel, observability-coverage-reviewer, code-simplicity-reviewer, verify-the-negative/realism pass (general-purpose, sonnet)

### Key Improvements
1. **Security hardening (P2/P3):** ported `scrub_pat()` (`sbp_…` redaction) from `postgrest-reload-schema.sh:61-67` — `strip_log_injection` does NOT redact a leaked PAT, and GitHub's exact-match secret masking can be defeated by `head -c 400` truncation; hardcoded `api.supabase.com` host (no env-override exfil seam); `head -c 400` truncation before scrub. New FR9.
2. **Repoint completeness (P2):** the realism pass enumerated all SIX downstream `steps.probe.outputs.*` references (`:117/:128/:132/:133/:161/:182`) — the original plan named four; `:133` is `failure_detail` (not `failure_mode`). New mechanical FR10 (`grep -c … == 0`).
3. **Simplification:** dropped the YAGNI `POOL_ALERT_PCT` env var (hardcoded `70`); reframed the LARP NFR4 to a concrete nfr-register post-condition; demoted PM2 + inspection-only NFR2 half out of the AC checklist (post-condition-only ACs).
4. **Runbook no-SSH-first (QG3):** the new pool subsection must lead with a no-SSH probe to pre-empt the `ship-runbook-ssh-gate.sh` PreToolUse gate (the sibling triage section leads with a host login — must not inherit).
5. **Routing clarity:** documented that `pool_pressure`/`pool_exhausted` are two labels on ONE alert route (not three control forks); `pool_probe_unavailable` is the soft probe-health mode.

### New Considerations Discovered
- The account-scoped Supabase PAT grants org-wide SQL (irreducible — Supabase has no project-scoped Management-API credential); blast-radius is bounded by GH-secret-store-only storage + read-only fixed query + the new redaction. Documented in User-Brand Impact + a TF-var comment.
- All cited refs verified live: commit `0a6665ea1` is on `main`; #5559/#5549 MERGED, #5558/#5450 CLOSED, #5562/#5560 OPEN; the `ci/inngest-pool` label does NOT exist yet (workflow creates it defensively, matching `:140`).
- deepen-plan Phase 4.8 PAT-var gate is a documented false-positive (Supabase token ≠ GitHub PAT; the rule is GitHub-write-scoped).

## Overview

The #5558 Supabase session-pool exhaustion (`EMAXCONNSESSION`, pool_size 15) was caught only as a generic `inngest-unhealthy` symptom, and the external watchdog (`.github/workflows/scheduled-inngest-health.yml`, #5549) would actively **mis-remediate** it: any probe failure is classified as `inngest_down`/`inngest_unhealthy` → auto-dispatches `restart-inngest-server.yml`, and a restart churns MORE session connections, deepening pool exhaustion. There is no leading-indicator monitoring of the connection pool itself.

This plan is **purely additive observability + IaC codification — NO live prod mutation**. It extends the existing watchdog workflow with two capabilities and codifies one config-drift fact in Terraform:

- **(a) Pool-utilization probe (leading indicator):** a new workflow step queries the dedicated inngest Supabase project (ref `pigsfuxruiopinouvjwy`) via the Management API and alerts when session count crosses ~70% of the session-pool cap — *before* `EMAXCONNSESSION`.
- **(b) `EMAXCONNSESSION` classification:** a new distinct `pool_exhausted` failure mode that ALERTS (files/comments the tracking issue, reports `error` to Sentry) but is **excluded** from the auto-restart gate, with a tracking-issue body pointing at the stale-session / `--postgres-max-open-conns 10` remediation, not a restart.
- **(c) Codify the pooler config drift:** during #5558 recovery the transaction/session pooler `default_pool_size` was raised to 30 live via the Management API. The real fix — the client-side `--postgres-max-open-conns 10` cap — is **already merged** (commit `0a6665ea1`, #5559). This plan documents the decision to **revert to the default and rely on the client cap**, codified as an out-of-band-resource comment block in `inngest.tf` (matching the existing `INNGEST_POSTGRES_URI` pattern). No live mutation here — the revert itself is a separate operator/follow-up action; this PR records the decision and the leading-indicator that makes the revert safe.

Separate PR from #5560 (durable-secrets-in-argv security work) and from any workflow/skills change.

## Problem Statement

The durable cutover (#5459/#5450) added a Postgres pooler + Redis dependency with **no capacity/utilization monitoring** — exactly what made #5558 a silent degradation. The watchdog (#5549) closes the "inngest is fully DOWN" blind spot but is blind to *partial* degradation from pool pressure, and worse, its single remediation lever (restart) is the wrong tool for `EMAXCONNSESSION`:

1. **No leading indicator.** Pool utilization climbs invisibly until inngest's connection attempts hit `pool_size` and the pooler returns `FATAL: max clients reached (EMAXCONNSESSION)`. The first signal today is a degraded durable backend, after the cliff.
2. **Mis-remediation on the cliff.** The Auto-dispatch step (`scheduled-inngest-health.yml:117`) is gated on `failure_mode == 'inngest_down' || failure_mode == 'inngest_unhealthy'`. A pool-exhaustion `500`/`EMAXCONNSESSION` currently lands as `inngest_unhealthy` (200 with no functions array) or `inngest_down` (500), triggering a restart. A restart re-opens all of inngest's pool connections at once, making `EMAXCONNSESSION` worse, not better.
3. **Silent live drift.** `default_pool_size=30` was set via the Management API during recovery and lives nowhere in IaC. The client-side cap (`--postgres-max-open-conns 10`, `inngest-bootstrap.sh:354`) now makes the raised server cap redundant, but nothing records that the server-side raise should be reverted to the project default.

## Research Reconciliation — Spec vs. Codebase

| Issue/task claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "the real fix is the client-side `--postgres-max-open-conns 10` cap **in v1.1.17**" | The cap-at-10 fix is **already merged**: commit `0a6665ea1` ("fix(inngest): cap --postgres-max-open-conns at 10", #5559); `inngest-bootstrap.sh:354` reads `--postgres-max-open-conns 10`. The current bootstrap-image pin is `v1.1.16` (cloud-init.yml:630), not v1.1.17 — the cap is an `inngest-bootstrap.sh` change that ships in the next image build, version label is incidental. | Task (c) decision is **revert-and-rely-on-client-cap**, not codify-30. The client cap is live, so the raised server cap is already redundant. Plan documents this in the `inngest.tf` comment; does not pin a v1.1.17 string. |
| "POST `…/database/query` with Bearer `SUPABASE_ACCESS_TOKEN`" — implies the token/mechanism is novel | Canonical precedent exists: `apps/web-platform/scripts/postgrest-reload-schema.sh:118,135-145` already POSTs `https://api.supabase.com/v1/projects/<ref>/database/query` with `Authorization: Bearer ${SUPABASE_PAT}`, captures body+`%{http_code}` via `-w`, `--max-time`, scrubs the token from error echoes. | Pool-probe step mirrors this curl shape verbatim. |
| "expose [SUPABASE_ACCESS_TOKEN] as a GH secret" — implies a simple operator `gh secret set` | `SUPABASE_ACCESS_TOKEN` is **not** an existing GH secret (existing: `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_PROJECT_REF`, anon key). It is an account-scoped PAT (`sbp_…`) minted out-of-band. The repo's IaC path for GH secrets is the `github_actions_secret` TF resource (`kb-drift.tf:111`, `doppler-write-token.tf:47`). | Expose via a **new `github_actions_secret` TF resource** sourced from a no-default TF variable (`hr-tf-variable-no-operator-mint-default`), NOT operator `gh secret set`. See Infrastructure (IaC) section. |
| inngest Supabase project ref = `pigsfuxruiopinouvjwy` | This is a **separate** Supabase project from the app's main project (`inngest.tf:166`: `project: soleur-inngest-prd ref: pigsfuxruiopinouvjwy`). The existing GH secret `SUPABASE_PROJECT_REF` is the **app** project, not inngest. | The pool-probe **hardcodes** `pigsfuxruiopinouvjwy` in the workflow (stable infra; do NOT resolve from `NEXT_PUBLIC_SUPABASE_URL`, which points at the app project). |
| session-pool cap = 15 | `inngest-bootstrap.sh:301` documents pooler `pool_size (15)`; the client cap (10) sits under it. The live `default_pool_size=30` drift means the *current* effective cap is 30, but the plan's revert decision targets the default 15. | Probe alert threshold is parameterized as an env var (`SESSION_POOL_CAP`, default 15) so the ~70% trip point tracks whichever cap is live without a code edit. |

## Proposed Solution

### Architecture

All three changes are additive. The watchdog workflow gains one probe step and one classification branch; the auto-restart gate is **narrowed** (pool_exhausted excluded); the tracking-issue body becomes failure-mode-aware. The IaC change is a comment block + one `github_actions_secret` resource + one variable.

```
scheduled-inngest-health.yml  (every 15 min, GH-hosted runner)
  └─ step: probe (existing)               → failure_mode ∈ {"", inngest_down, inngest_unhealthy}
  └─ step: pool-probe (NEW)               → reads pg_stat_activity session counts via Mgmt API
        ├─ total ≥ 70% of SESSION_POOL_CAP → failure_mode = pool_pressure  (warn, no restart)
        └─ HTTP 500 body ~ EMAXCONNSESSION → failure_mode = pool_exhausted  (alert, no restart)
        (only sets failure_mode if the upstream probe left it empty — never masks inngest_down)
  └─ step: Auto-dispatch restart (NARROWED) if inngest_down || inngest_unhealthy   ← pool_* EXCLUDED
  └─ step: File/comment tracking issue    → body branches on failure_mode (restart vs pool remediation)
  └─ step: Sentry check-in                → status = error when failure_mode != "" (unchanged formula; pool_* ⇒ error)
```

**Failure-mode precedence (load-bearing):** the existing `record_failure()` (`scheduled-inngest-health.yml:67`) records the *first* failure only. The pool-probe step must run **after** the existing inngest-health probe and only evaluate/set a pool failure mode when `failure_mode` is still empty — a genuinely-down inngest (`inngest_down`) must win over a pool reading, because (i) if inngest is down the pg_stat reading is a secondary symptom and (ii) `inngest_down` is the only mode that *should* restart. Conversely, when inngest is healthy but the pool is hot, the pool reading is the actionable signal.

**Two distinct pool modes:**
- `pool_pressure` — leading indicator: session count ≥ 70% of cap but `EMAXCONNSESSION` has not yet fired. Warn + file/update tracking issue; do NOT restart. This is the value of the whole feature — catch it *before* the cliff.
- `pool_exhausted` — the cliff: the Management API query itself returned a 500 whose body contains `EMAXCONNSESSION` (the pooler rejecting the probe's own connection), OR the count equals/exceeds the cap. Alert + file/update tracking issue with the stale-session remediation; do NOT restart.

Both are excluded from auto-restart. Both report `error` to Sentry (the existing `failure_mode == '' && 'ok' || 'error'` formula already covers this — no heartbeat-action change needed).

**Routing clarification (not three independent control paths):** `pool_pressure` and `pool_exhausted` are two *labels* on a single "pool-hot" alert route — they share the same `[ci/inngest-pool]` issue, the same restart-exclusion, and the same Sentry `error` status; the only difference is the issue title fragment ("pressure" vs "exhaustion") and the remediation emphasis. `pool_probe_unavailable` is a third *name* but a distinct soft probe-health mode. So the system has **three names, two alert routes (down-family restart vs pool-family alert), one soft probe-health mode** — not three forks of the gate. The gate and Sentry-status logic branch only on the down-family vs pool-family distinction.

### Implementation Phases

#### Phase 0 — Preconditions (verify-before-code)

- [ ] Confirm `SUPABASE_ACCESS_TOKEN` exists in Doppler `prd` (read-only): `doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain >/dev/null && echo present || echo MISSING`. If MISSING, the IaC variable will have no value at apply time → see "Apply path"/Risk R3 (operator mints + sets Doppler before the `github_actions_secret` resource can apply). Mint at https://supabase.com/dashboard/account/tokens, store via Doppler stdin (never argv — `hr-never-paste-secrets-via-bang-prefix`).
- [ ] Confirm the account that owns the PAT has read access to project `pigsfuxruiopinouvjwy` (the inngest project lives under org Jikig AI). A 401/403 from the Management API is *often a validation/scope signal, not pure auth* — the probe MUST print the response body on non-2xx for diagnosis (learning `2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md`).
- [ ] Re-confirm the canonical curl shape against `postgrest-reload-schema.sh:135-145` and adopt verbatim (body+`%{http_code}` via `-w $'\n%{http_code}'`, `--max-time`, `2>/dev/null` to keep the Authorization header out of `$response`).

#### Phase 1 — IaC: expose SUPABASE_ACCESS_TOKEN as a GH secret + codify pooler decision (`inngest.tf`, `variables.tf`)

1. **New no-default variable** in `apps/web-platform/infra/variables.tf` (mirror the `resend_receiving_api_key` shape at `variables.tf:157` — operator-minted PAT, no default per `hr-tf-variable-no-operator-mint-default`):
   ```hcl
   variable "supabase_access_token" {
     type        = string
     sensitive   = true
     description = "Supabase account-scoped Management-API PAT (sbp_…) used by scheduled-inngest-health.yml to read pg_stat_activity on the dedicated inngest project (ref pigsfuxruiopinouvjwy). Out-of-band-minted at supabase.com/dashboard/account/tokens; value from Doppler prd_terraform via TF_VAR_supabase_access_token. No default (hr-tf-variable-no-operator-mint-default)."
     # NO default.
   }
   ```
2. **New `github_actions_secret` resource** co-located in `apps/web-platform/infra/inngest.tf` (this token's sole consumer is the inngest watchdog; keeping the inngest observability surface in one file beats a new file-per-service split for a single resource):
   ```hcl
   resource "github_actions_secret" "supabase_access_token" {
     repository      = "soleur"
     secret_name     = "SUPABASE_ACCESS_TOKEN"
     plaintext_value = var.supabase_access_token
   }
   ```
   (No `doppler_secret`/`random_id` — the PAT is account-scoped and out-of-band-minted, exactly like `resend_receiving_api_key`; TF only *publishes* it to the GH Actions secret store from the TF_VAR.)
3. **Pooler-drift codification comment** in `inngest.tf`, appended to the `# Durable backend secrets (#5450)` block right after the `INNGEST_POSTGRES_URI` out-of-band paragraph (`inngest.tf:162-176`). Match that paragraph's prose style. Records: (i) `default_pool_size` was raised 15→30 live via the Management API during #5558 recovery; (ii) the real fix is the client cap `--postgres-max-open-conns 10` (now live, #5559 / `inngest-bootstrap.sh:354`); (iii) **decision: revert `default_pool_size` to the project default (15) out-of-band and rely on the client cap** — the leading-indicator probe in `scheduled-inngest-health.yml` makes the revert safe by alerting at ~70% before exhaustion; (iv) the pooler setting is intentionally NOT a TF resource (no Supabase provider is declared in `main.tf`, and the inngest project is provisioned out-of-band, ref `pigsfuxruiopinouvjwy`) — mirrors the `INNGEST_POSTGRES_URI` out-of-band pattern.

#### Phase 2 — Pool-utilization probe step (`scheduled-inngest-health.yml`)

Insert a new step **after** the existing `probe` step (id `probe`, ends `scheduled-inngest-health.yml:114`) and **before** the Auto-dispatch step. The step:

1. Reuses the same `strip_log_injection()` helper (re-declare inline; bash functions don't cross steps — it is re-declared per-step, mirroring how the existing step defines it at `:61-64`). Per `cq-regex-unicode-separators-escape-only`, copy the helper verbatim from `:61-64` (same `tr -d` charset + `sed` unicode separators). **ALSO port the `scrub_pat()` redaction** from the canonical `postgrest-reload-schema.sh:61-67` (`sed -E 's/sbp_[A-Za-z0-9]{20,}/sbp_REDACTED/g'`) — `strip_log_injection` only strips control/separator chars, it does NOT redact a leaked `sbp_…` token (a Supabase error echoing the auth header, a future `--verbose`, a truncation-split that defeats GitHub's exact-match secret masking). Every body/cause string is piped through BOTH (`scrub_pat "$(strip_log_injection "$body")"`) before any `::error::`/`::warning::`/`$GITHUB_OUTPUT`/issue-body write. [security-sentinel P2]
2. Skips silently (does not fail the run) when `failure_mode` from the prior step is non-empty AND equals `inngest_down`/`inngest_unhealthy` — a down inngest must keep its restart path. Carry the prior `failure_mode` via `steps.probe.outputs.failure_mode` into this step's env.
3. Reads `SUPABASE_ACCESS_TOKEN` (env, from `secrets.SUPABASE_ACCESS_TOKEN`), hardcoded `INNGEST_PROJECT_REF=pigsfuxruiopinouvjwy`, `SESSION_POOL_CAP` (env literal, default `15` — kept as an env var because the live cap is a genuinely moving value during the revert window per R6). The 70% trip percentage is a **hardcoded literal `70`** in the arithmetic (not an env var — no scenario in this plan changes it; a different percentage is a one-line edit at that time). [code-simplicity: dropped `POOL_ALERT_PCT`]
4. POSTs the canonical Management-API query (curl shape from `postgrest-reload-schema.sh:135-145`):
   ```
   POST https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query
   Authorization: Bearer $SUPABASE_ACCESS_TOKEN
   Content-Type: application/json
   {"query":"select state, count(*) from pg_stat_activity group by state"}
   ```
   `--max-time 15`, capture body + `%{http_code}` via `-w $'\n%{http_code}'`, `2>/dev/null`. **Hardcode the `api.supabase.com` host with NO env override** (mirror the canonical script's deliberate refusal of a `SUPABASE_API_HOST` seam at `postgrest-reload-schema.sh:112-117` — an env-overridable host is an exfil-via-redirect vector for the account-scoped PAT). Truncate the body with `tr '\n' ' ' | head -c 400` **before** sanitize/scrub (matching `:93,:96`), and run `scrub_pat` *after* truncation so redaction sees the final string. [security-sentinel P3]
5. Classifies (only sets `pool_failure_mode` if upstream `failure_mode` is empty):
   - HTTP `500`/`5xx` **and** `strip_log_injection(body)` contains `EMAXCONNSESSION` (case-sensitive `grep -F`) → `pool_exhausted`.
   - HTTP `2xx`: parse with `jq` (`jq -e 'type=="array"'` guard; fall through to a non-blocking warn on non-JSON per shell-hardening learning). Sum `count` across rows → `total`. If `total >= ceil(SESSION_POOL_CAP * 70/100)` → `pool_pressure` (use integer bash arithmetic only — `(( total * 100 >= SESSION_POOL_CAP * 70 ))` — never float under `set -euo pipefail`). If `total >= SESSION_POOL_CAP` → `pool_exhausted` (already at/over the cap even without an EMAXCONNSESSION yet).
   - HTTP `401`/`403` or other non-2xx without EMAXCONNSESSION → `pool_probe_unavailable` (a *soft* mode: warn + Sentry error so a broken probe is itself visible, but do NOT file the pool_exhausted remediation issue — print the response body for diagnosis). This closes the "the probe silently stopped working" dark-zone.
6. All untrusted values (`body`, `total`, any echoed cause) flow through `strip_log_injection` before `::error::`/`::warning::`/`$GITHUB_OUTPUT` (per `cq-silent-fallback…`, the GITHUB_OUTPUT-injection learning, and the existing `:109-111` pattern). Use `printf '%s\n'` (not bare `echo`) for `$GITHUB_OUTPUT` writes.

**Output contract (DECISION):** give the pool-probe step its own `id: poolprobe` and have it re-emit the **effective** `failure_mode`/`failure_detail` to `$GITHUB_OUTPUT` — overwriting only when it set a pool mode, else re-emitting the upstream value it carried in env. All downstream `if:`/`status:` conditions switch from `steps.probe.outputs.failure_mode` to `steps.poolprobe.outputs.failure_mode`. One source of truth; no third reconciliation step.

#### Phase 3 — Narrow the auto-restart gate + branch the tracking issue (`scheduled-inngest-health.yml`)

1. **Auto-dispatch gate (`:117`)** — unchanged predicate semantics but reads the combined output: `if: steps.poolprobe.outputs.failure_mode == 'inngest_down' || steps.poolprobe.outputs.failure_mode == 'inngest_unhealthy'`. Because the pool-probe never sets `inngest_down`/`inngest_unhealthy`, `pool_pressure`/`pool_exhausted`/`pool_probe_unavailable` are structurally excluded from restart. (Comment the exclusion explicitly so a future editor does not "helpfully" add pool modes to the gate.)
2. **File/comment tracking issue (`:127-158`)** — branch the issue body + title on failure-mode class:
   - `inngest_down`/`inngest_unhealthy` → existing title `[ci/inngest-down] …`, existing Auto-recovery body (restart dispatched).
   - `pool_pressure`/`pool_exhausted` → new title `[ci/inngest-pool] Inngest session-pool pressure/exhaustion` + label `ci/inngest-pool` (create defensively with `2>/dev/null || true`, color distinct from `ci/inngest-down`). Body MUST point at the **stale-session / `--postgres-max-open-conns 10`** remediation and explicitly say **do NOT restart** (a restart churns more pool connections). Reference `knowledge-base/engineering/operations/runbooks/inngest-server.md` (pool section) and #5558/#5559. Include the session-count breakdown (`total` + per-state) so the operator sees the trend.
   - `pool_probe_unavailable` → comment/append to the pool issue (or a dedicated `[ci/inngest-pool-probe] probe unavailable` note) with the response body — the probe being broken is its own alert.
   - Use a **separate** open-issue search per class (distinct title strings) so a pool issue and a down issue do not collide/auto-close each other.
3. **Auto-close (`:160-174`)** — when `failure_mode == ''` (healthy), also close any open `[ci/inngest-pool]` issue (healthy means pool is fine too). Keep the searches separate (two `gh issue list` + two `gh issue close`); do NOT union the title search (a union close-search would close the wrong issue — the union-AC trap class).
4. **Sentry check-in (`:176-185`)** — change `steps.probe.outputs.failure_mode` → `steps.poolprobe.outputs.failure_mode` in the status formula. No other change: any non-empty mode (including pool modes) reports `error`.

**Repoint completeness (load-bearing — realism pass):** the full set of downstream references that MUST switch `steps.probe` → `steps.poolprobe` is SIX lines, not four: `:117` (Auto-dispatch `if`), `:128` (File/comment `if`), `:132` (`FAIL_MODE` env), **`:133` (`FAIL_DETAIL` env — `failure_detail`, NOT `failure_mode`; the poolprobe step must also re-emit `failure_detail`)**, `:161` (Auto-close `if`), `:182` (Sentry status). After the change, `grep -c 'steps.probe.outputs.failure_mode' .github/workflows/scheduled-inngest-health.yml` MUST return `0` and `grep -c 'steps.probe.outputs.failure_detail' …` MUST return `0` (every reference repointed). [realism pass + observability-coverage P2]

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| **Codify `default_pool_size=30` as the source of truth** (task c, option A) | The client cap (`--postgres-max-open-conns 10`, #5559) is already live and makes the raised server cap redundant. Keeping 30 would codify a workaround that the real fix supersedes; reverting to the default 15 + relying on the client cap is the cleaner invariant. There is also no Supabase TF provider in `main.tf`, so codifying it as a *resource* would require adding a provider for a single pooler attribute on an out-of-band project — disproportionate. |
| **Monitor pool via a SECURITY DEFINER RPC from the app runtime** (learning `2026-06-02-supabase-disk-io-monitor-via-security-definer-rpc-not-management-api.md`) | That learning's concern is putting an *account-scoped PAT into the app container*. This watchdog is an **external GH-Actions** probe — the PAT lives only in the GH Actions secret store, never in the prod container. The Management API path is the right tool for an external watchdog (it runs even when inngest/the app is degraded), and the task explicitly mandates it. We cite the distinction so the reviewer does not flag a false security downgrade. The RPC path would also require the inngest project to expose an RPC and a service-role client for *that* project, which it does not have. |
| **Add a 4th probe attempt / longer retry to the existing inngest probe to "catch" pool errors** | Conflates two orthogonal signals. Pool pressure is a *count* read, not a liveness read; folding it into the liveness retry loop would re-introduce the mis-remediation (a pool error in the liveness loop classifies as `inngest_unhealthy` → restart). A separate step with its own classification is required. |
| **A new Inngest cron to self-monitor the pool** | An inngest cron cannot observe inngest's own pool exhaustion (the cron needs the pool to run) — the exact internal-blind-spot the external watchdog (#5549) exists to avoid. Override comment at `scheduled-inngest-health.yml:1-4` already codifies "this monitor MUST be external." |
| **Resolve the inngest project ref from `NEXT_PUBLIC_SUPABASE_URL`** | That URL is the **app** project, not the inngest project (`pigsfuxruiopinouvjwy`). Hardcode the stable inngest ref. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a *false* restart of `inngest-server` (if the pool gate were mis-wired to restart on `pool_exhausted`) — which deepens pool exhaustion and can stall durable crons (scheduled reminders, one-shots), or a *missed* alert (if the probe silently fails) that lets pool exhaustion degrade the durable backend invisibly, the #5558 class of silent degradation. No direct end-user UI surface — inngest is backend infrastructure.
- **If this leaks, the user's data/workflow is exposed via:** the new `SUPABASE_ACCESS_TOKEN` GH secret is an **account-scoped** Management-API PAT. If it leaked (e.g., echoed into a public Actions log via a missing `strip_log_injection`/`2>/dev/null`), an attacker could run arbitrary SQL against the inngest project via the Management API. Mitigations: token lives only in the GH secret store (TF-published, never in the container), curl `2>/dev/null` keeps the `Authorization` header out of captured output, and the query is a fixed read-only `pg_stat_activity` aggregate (no parameter interpolation from untrusted input).
- **Brand-survival threshold:** `aggregate pattern`. This is backend observability for an alpha-internal substrate; a single mis-fire is recoverable and not user-visible, but a *pattern* of mis-remediation or dark probes degrades the durable-cron substrate that user-facing workflows depend on. (Matches the `inngest.tf` header's stated `aggregate pattern` threshold for the inngest substrate.) No `requires_cpo_signoff`.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor check-in (scheduled-inngest-health) — already wired; pool modes report status=error through the same heartbeat"
  cadence: "every 15 min (the watchdog cron); a MISSING check-in also alerts (Sentry expects a ping per schedule)"
  alert_target: "operator email via Sentry cron monitor + GitHub tracking issue ([ci/inngest-pool] for pool modes)"
  configured_in: ".github/workflows/scheduled-inngest-health.yml:176-185 (Sentry check-in step) + new pool-probe step"

error_reporting:
  destination: "Sentry web-platform cron monitor slug scheduled-inngest-health (status=error on any non-empty failure_mode); GitHub issue [ci/inngest-pool]"
  fail_loud: "::error:: annotation 'Inngest pool probe: pool_exhausted/pool_pressure — total=N/cap=M'; Sentry status=error; a NEW [ci/inngest-pool] GitHub issue or comment"

failure_modes:
  - mode: "pool_pressure (session count >= 70% of SESSION_POOL_CAP, before EMAXCONNSESSION)"
    detection: "pool-probe step sums count(*) from pg_stat_activity via Management API; integer compare against cap*pct"
    alert_route: "GitHub [ci/inngest-pool] issue (warn, remediation = client-cap/stale-session, NOT restart) + Sentry error"
  - mode: "pool_exhausted (500 body contains EMAXCONNSESSION, OR total >= SESSION_POOL_CAP)"
    detection: "pool-probe step greps -F EMAXCONNSESSION in the 5xx response body / count compare"
    alert_route: "GitHub [ci/inngest-pool] issue with stale-session remediation + explicit do-NOT-restart; Sentry error; EXCLUDED from auto-dispatch restart gate"
  - mode: "pool_probe_unavailable (401/403/non-2xx without EMAXCONNSESSION, or non-JSON body)"
    detection: "pool-probe step sees non-2xx HTTP and no EMAXCONNSESSION; prints response body"
    alert_route: "Sentry error + GitHub note so a broken probe is itself visible (closes the dark-probe zone)"

logs:
  where: "GitHub Actions run log for scheduled-inngest-health (per-run); GitHub tracking issues [ci/inngest-pool] / [ci/inngest-down]"
  retention: "Actions logs ~90 days (GitHub default); tracking issues persist until auto-closed on healthy"

discoverability_test:
  command: gh api repos/jikig-ai/soleur/actions/workflows/scheduled-inngest-health.yml --jq .state
  expected_output: active
  # Single no-SSH command (no &&/$()/pipe) — confirms the watchdog workflow that
  # carries the pool probe is registered + dispatchable on the default branch.
  # Deeper end-to-end check (dispatch + read the pool-probe step output) post-merge:
  # gh workflow run scheduled-inngest-health.yml then inspect the run log.
```

## Infrastructure (IaC)

### Terraform changes

- **Files:** `apps/web-platform/infra/inngest.tf` (append: 1 `github_actions_secret` resource + the pooler-drift comment block), `apps/web-platform/infra/variables.tf` (append: 1 no-default sensitive variable `supabase_access_token`).
- **Providers (already declared, no new pins):** `integrations/github` (`main.tf` — App-installation auth, `hr-github-app-auth-not-pat`) for `github_actions_secret`; `hashicorp/random` and `DopplerHQ/doppler` already present. **No Supabase TF provider is added** — the inngest project is out-of-band (ref `pigsfuxruiopinouvjwy`); the pooler decision is documented as a comment, not provisioned.
- **Sensitive variable list:** `TF_VAR_supabase_access_token` — value sourced from Doppler `prd_terraform` (the `apply-web-platform-infra.yml` injection path), out-of-band-minted Supabase account PAT (`sbp_…`). No default (`hr-tf-variable-no-operator-mint-default`).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
> **`hr-github-app-auth-not-pat` gate note (deepen-plan Phase 4.8 false-positive, evaluated):** the Phase 4.8 regex (`var.*_token`) flags `var.supabase_access_token`, but that rule's body is scoped to *"Infra/CI **GitHub** writes auth via GitHub App, never PAT"*. This var is a **Supabase Management-API** token, not a GitHub credential — there is no GitHub App equivalent for the Supabase Management API. The GitHub write in this plan (publishing the secret) is the `github_actions_secret` resource, which DOES route through the App-auth `integrations/github` provider (`main.tf`). The Supabase PAT is the correct and only credential for `api.supabase.com`. Precedent: `var.hcloud_token`, `var.cf_api_token`, `var.doppler_token`, `var.betterstack_api_token`, `var.resend_receiving_api_key` are all existing accepted vendor-token vars in `variables.tf` under `hr-tf-variable-no-operator-mint-default` (none are GitHub PATs). Verified per `hr-verify-repo-capability-claim-before-assert`.

### Apply path

- **Path (c)-adjacent: a GH-secret publish + a comment — no resource replacement, no host mutation.** The `github_actions_secret` resource applies on the auto-applied `apps/web-platform/infra/*.tf` merge (`apply-web-platform-infra.yml` fires on any `infra/*.tf` change). **Sequencing risk (R3, load-bearing):** Terraform resolves *all* root variables before `-target` pruning, so a no-default `supabase_access_token` with no `TF_VAR_` value in Doppler `prd_terraform` would fail the **whole** merge-triggered apply, not just this resource. Therefore the operator MUST provision `TF_VAR_supabase_access_token` in Doppler `prd_terraform` (and `SUPABASE_ACCESS_TOKEN` in Doppler `prd` for the runbook/local-probe parity) **before** this PR merges. This matches the #5468/ADR-065 sequencing rule for no-default vars on auto-applied roots. If the PAT cannot be provisioned in-session, **split**: the workflow YAML change (no `*.tf` edit → does not trigger the infra apply) may merge first; the `inngest.tf`/`variables.tf` IaC lands in a follow-up PR that merges after `TF_VAR_*` provisioning. The workflow step degrades gracefully when `SUPABASE_ACCESS_TOKEN` is unset (records `pool_probe_unavailable`, not a hard failure), so a temporary gap is observable, not silent.
- Expected downtime/blast-radius: **none** — additive secret + additive workflow step; no resource replacement, no prod host mutation.

### Distinctness / drift safeguards

- `dev != prd`: the durable inngest backend is **prd-only** (`inngest.tf:144` — dev runs ephemeral `inngest dev`, no pooler). The pool probe is therefore prd-scoped; the GH secret + workflow run against the prd inngest project ref only. No dev pool to monitor.
- The `github_actions_secret` does NOT carry `lifecycle.ignore_changes` (mirrors `doppler-write-token.tf:47` / `kb-drift.tf:111`) — rotation flows by re-setting `TF_VAR_supabase_access_token` and re-applying.
- State note: `var.supabase_access_token` lands in `terraform.tfstate` (encrypted R2 backend) like every other sensitive var.

### Vendor-tier reality check

- Supabase Management API on org Jikig AI (Pro) — no paid-tier gate on `/database/query`. The inngest project is a ~$10/mo Micro-compute project (`inngest.tf:169`). No new vendor expense (the PAT is account-scoped, free).

## Architecture Decision (ADR/C4)

**No new ADR required; no C4 change.** This plan does not introduce or reverse an architectural decision — it adds observability to the existing durable-inngest substrate (ADR-030) and records a config-drift *revert* decision in a code comment (the substrate, ownership boundaries, and trust boundaries are unchanged).

**C4 completeness check (all three model files read):** `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` were enumerated for impact. The actors/systems involved are already-modeled or out-of-scope for the C4 boundary:
- **External human actor:** none new (the operator receiving the alert is the existing operator role).
- **External system/vendor:** the Supabase Management API (`api.supabase.com`) and the dedicated inngest Supabase project are **out-of-band infrastructure** (documented as comments in `inngest.tf`, ref `pigsfuxruiopinouvjwy`), deliberately not modeled as C4 containers — consistent with how the existing `INNGEST_POSTGRES_URI` out-of-band project is handled. GitHub Actions (the watchdog runner) is the existing external CI system. None of these are new boundary elements.
- **Container/data-store:** no app container or data-store touched (the probe reads the inngest project's `pg_stat_activity`, a runtime stat view, not an app schema).
- **Access relationship:** unchanged — the watchdog already reads the inngest substrate's health; this adds a pool-stat read along the same external-CI→inngest-substrate edge.

The pooler-revert decision is recorded where it is operationally actionable (the `inngest.tf` comment), not as an ADR — it is a config-value choice within ADR-030's already-decided durable-backend architecture, not a new decision a future engineer would be misled about by reading the ADR corpus.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was checked against the planned edit targets (`.github/workflows/scheduled-inngest-health.yml`, `apps/web-platform/infra/inngest.tf`, `apps/web-platform/infra/variables.tf`); no open code-review scope-out names these files. (If the `/work` phase finds one at implementation time, fold-in per the standard overlap disposition.)

## Domain Review

**Domains relevant:** Engineering (infra/observability)

### Engineering

**Status:** reviewed (plan-author assessment; CTO/terraform-architect carry-forward from research)
**Assessment:** Infra + CI observability change. terraform-architect concern (IaC gate, Phase 2.8) is satisfied — the GH secret routes through `github_actions_secret` (no operator `gh secret set`), the no-default var follows `hr-tf-variable-no-operator-mint-default`, and the pooler decision is documented as out-of-band per the established `INNGEST_POSTGRES_URI` pattern (no new provider). observability-coverage-reviewer concern (Phase 2.9) is satisfied by the `## Observability` 5-field block with a no-ssh discoverability test. No product/UX/legal/finance surface (no user data, no UI, no new vendor cost).

No Product/UX Gate: no `## Files to Create`/`## Files to Edit` path matches a UI-surface term (`components/**`, `app/**/page.tsx`, etc.). Mechanical override does not fire.

## Files to Edit

- `.github/workflows/scheduled-inngest-health.yml` — add pool-probe step (Phase 2); narrow auto-restart gate + branch tracking issue + extend auto-close + repoint Sentry status to combined output (Phase 3).
- `apps/web-platform/infra/inngest.tf` — add `github_actions_secret.supabase_access_token` resource + pooler-drift codification comment block (Phase 1).
- `apps/web-platform/infra/variables.tf` — add no-default `supabase_access_token` sensitive variable (Phase 1).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — new "session-pool pressure/exhaustion" subsection (QG3); the tracking-issue body links to it.

## Files to Create

- (none — the GH secret + variable co-locate in existing `inngest.tf`/`variables.tf`.)

## Acceptance Criteria

### Pre-merge (PR)

#### Functional Requirements

- [ ] **FR1 (pool probe exists):** `scheduled-inngest-health.yml` contains a new step that POSTs to `https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query` with `Authorization: Bearer` from `secrets.SUPABASE_ACCESS_TOKEN` and the body `select state, count(*) from pg_stat_activity group by state`. Verify: `grep -F 'pigsfuxruiopinouvjwy/database/query' .github/workflows/scheduled-inngest-health.yml` returns ≥1 AND `grep -F 'pg_stat_activity' .github/workflows/scheduled-inngest-health.yml` returns ≥1.
- [ ] **FR2 (EMAXCONNSESSION → pool_exhausted, not restart):** the auto-restart gate (`if:` on the Auto-dispatch step) matches ONLY `inngest_down`/`inngest_unhealthy`. Verify: `awk '/name: Auto-dispatch/{f=1} f&&/if:/{print; exit}' .github/workflows/scheduled-inngest-health.yml | grep -F pool_` returns empty (0 lines). (Flag-based awk per learning `2026-05-15-plan-ac-verification-commands-awk-self-match…` — start pattern `/name: Auto-dispatch/` differs from the `if:` end-token so no self-match.)
- [ ] **FR3 (pool tracking issue ≠ restart body):** the pool-mode tracking-issue body references `--postgres-max-open-conns` and the stale-session remediation and says do-NOT-restart, and uses a distinct label `ci/inngest-pool`. Verify: `grep -F 'postgres-max-open-conns' .github/workflows/scheduled-inngest-health.yml` ≥1 AND `grep -F 'ci/inngest-pool' …` ≥1.
- [ ] **FR4 (leading indicator threshold):** the probe computes a 70%-of-cap trip using integer arithmetic (no float). Verify: the step contains a `SESSION_POOL_CAP` env ref and an integer compare with the hardcoded `70` (`grep -F 'SESSION_POOL_CAP' …` ≥1 AND `grep -E '\(\(.*\* 70 ' …` ≥1; no `bc`/float).
- [ ] **FR5 (log-injection guard on untrusted body):** every echo of the Management-API response body into `::error::`/`::warning::`/`$GITHUB_OUTPUT` is wrapped by `strip_log_injection`. Verify: `grep -c 'strip_log_injection' .github/workflows/scheduled-inngest-health.yml` shows ≥2 declarations (existing + new step) AND the body variable is never echoed raw (inspection).
- [ ] **FR6 (combined failure_mode wired downstream):** the Sentry check-in status formula and the tracking-issue/auto-close `if:` read the combined output (the pool-probe step's output id `poolprobe`), so pool modes report Sentry `error` and never trigger restart. Verify: downstream `if:`/`status:` reference `steps.poolprobe.outputs.failure_mode`; a `pool_exhausted`/`pool_pressure` run reports Sentry `error` (dry-run/log inspection).
- [ ] **FR7 (IaC: GH secret via TF, not operator):** `inngest.tf` contains a `github_actions_secret` resource with `secret_name = "SUPABASE_ACCESS_TOKEN"` sourced from `var.supabase_access_token`, and `variables.tf` declares `supabase_access_token` with NO `default`. Verify: `grep -A2 'github_actions_secret\|supabase_access_token' apps/web-platform/infra/inngest.tf apps/web-platform/infra/variables.tf`.
- [ ] **FR8 (pooler-drift decision codified):** `inngest.tf` comment records (i) the `default_pool_size` 15→30 live drift, (ii) the revert-to-default-and-rely-on-client-cap decision, (iii) the `--postgres-max-open-conns 10` client-cap reference (#5559), and (iv) why it is out-of-band (no Supabase provider; ref `pigsfuxruiopinouvjwy`). Verify: `grep -F 'default_pool_size' apps/web-platform/infra/inngest.tf` ≥1 AND `grep -F 'pigsfuxruiopinouvjwy' …` matches the pooler comment.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **FR9 (PAT redaction at every print site — security P2):** the pool-probe step ports `scrub_pat()` (`sbp_…` → `sbp_REDACTED`) from `postgrest-reload-schema.sh:61-67` and pipes every body/cause through `scrub_pat "$(strip_log_injection …)"` before any `::error::`/`::warning::`/`$GITHUB_OUTPUT`/issue-body write; the body is truncated `head -c 400` before scrub; the `api.supabase.com` host is a hardcoded literal (no env override). Verify: `grep -F 'scrub_pat' .github/workflows/scheduled-inngest-health.yml` ≥1 AND `grep -F 'sbp_' …` shows the redaction regex AND `grep -cE 'SUPABASE_API_HOST|API_HOST' …` returns 0 (no host-override seam).
- [ ] **FR10 (combined-output repoint completeness — realism P2):** after the change, NO *downstream consumer* step (Auto-dispatch / File-issue / Auto-close / Sentry) reads the old probe output — every one reads `steps.poolprobe.outputs.*`. The ONLY remaining `steps.probe.outputs.*` references are the carry-forward env (`PRIOR_FAIL_MODE`/`PRIOR_FAIL_DETAIL`) INSIDE the poolprobe step itself, which is required (the poolprobe step must read the upstream verdict to honour `inngest_down` precedence — Phase 2 step 2). Verify: the only two `grep -n 'steps.probe.outputs' .github/workflows/scheduled-inngest-health.yml` hits are the `PRIOR_FAIL_*` env lines in the poolprobe step; every Auto-dispatch/File-issue/Auto-close/Sentry reference reads `steps.poolprobe`. (The earlier draft asserted `grep -c == 0`, which is wrong — it would force deleting the required carry-forward.)

#### Non-Functional Requirements

- [ ] **NFR1 (no live prod mutation):** the diff contains no `terraform apply`, no Management-API write/mutation (the only Management-API call is the read-only `select` query), no Doppler write, no SSH. Verify: `git diff origin/main -- .github apps/web-platform/infra | grep -iE 'apply -auto|ALTER |UPDATE |INSERT |ssh '` returns empty (the comment that *names* `default_pool_size` is allowed; it is not an `ALTER`).
- [ ] **NFR2 (token never logged):** curl uses `2>/dev/null` and the `Authorization` header is never echoed; the query is a fixed literal. Verify: `grep -F '2>/dev/null' .github/workflows/scheduled-inngest-health.yml` covers the pool-probe curl (grep-able half) — the redaction half is covered by FR9; no separate inspection-only checkbox.
- [ ] **NFR3 (HMAC/auth surfaces unchanged):** no change to the existing inngest-inventory probe's HMAC/CF-Access path. Verify: the existing `probe` step (`:52-114`) is unmodified except for the optional output-id repoint.
- [ ] **NFR4 (NFR register post-condition):** `knowledge-base/engineering/architecture/nfr-register.md` gains/updates a Reliability entry citing the pool leading-indicator probe (concrete post-condition, not "ran the assess skill"). `/soleur:architecture assess` is the *means*; the checkable result is the register edit.

#### Quality Gates

- [ ] **QG1 (workflow YAML + shell sanity):** `actionlint` if available (research found no current actionlint gate — fall back to `bash -c '<extracted run: snippet>'` syntax check of the new step + `python3 -c 'import yaml; yaml.safe_load(open("…"))'` for YAML). Do NOT use `bash -n` on the whole `.yml`.
- [ ] **QG2 (typecheck/test unaffected):** no `apps/web-platform/src` change; `inngest.test.sh` still passes if it asserts on `inngest.tf` (`bash apps/web-platform/infra/inngest.test.sh`).
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [ ] **QG3 (runbook updated, no-SSH-first):** `knowledge-base/engineering/operations/runbooks/inngest-server.md` gains a "session-pool pressure/exhaustion" subsection describing the `[ci/inngest-pool]` issue, the do-NOT-restart rule, and the stale-session / client-cap remediation (the tracking-issue body links to it). The subsection's **FIRST debug step MUST be a no-SSH probe** (read the `[ci/inngest-pool]` issue body via `gh issue view`, OR the read-only `pg_stat_activity` Management-API curl, OR `pg_terminate_backend` of stale sessions via the same `/database/query` path — all no-SSH); any host-level shell step sits under a `last-resort` heading after ≥3 no-SSH steps. This pre-empts the `ship-runbook-ssh-gate.sh` PreToolUse gate — the sibling `## Heartbeat-miss triage` section leads with a host login, which this subsection must NOT inherit. [observability-coverage P2 / `hr-no-ssh-fallback-in-runbooks`]

### Post-merge (operator / follow-up)

- [ ] **PM1 (Doppler provisioning — sequencing):** `TF_VAR_supabase_access_token` present in Doppler `prd_terraform` AND `SUPABASE_ACCESS_TOKEN` in Doppler `prd` BEFORE the `inngest.tf` change merges (Risk R3). If not in-session, split per Apply-path. Use `Ref #5562` in the PR body (not `Closes`) if any post-merge step remains; `Closes #5562` only once all in-PR ACs are green and the workflow change has merged.
> **PM2 (follow-up note, NOT an in-PR AC):** reverting the live `default_pool_size` 30→15 on the inngest project is a separate action recorded by FR8's decision comment; intentionally NOT done in this PR (NO live prod mutation), so it is unverifiable in-PR by construction. Track as a documented follow-up with re-eval criteria: revert only after the leading-indicator probe has run ≥1 healthy cycle confirming the client cap holds session count well under 15. (Kept as a note, not a checkbox, so the AC list stays post-condition-only.)

## Test Scenarios

### Acceptance Tests (RED targets)

- Given the inngest pool has `total < 70% of cap`, when the watchdog runs, then `failure_mode == ''`, Sentry status `ok`, no `[ci/inngest-pool]` issue, log line `Inngest pool OK: total=N (cap M, threshold K)`.
- Given `pg_stat_activity` returns `total >= ceil(cap*0.70)` but `< cap`, when the watchdog runs, then `failure_mode == pool_pressure`, Sentry `error`, a `[ci/inngest-pool]` issue is filed/commented with the client-cap remediation and do-NOT-restart, AND the Auto-dispatch restart step is SKIPPED.
- Given the Management API returns HTTP 500 with a body containing `EMAXCONNSESSION`, when the watchdog runs, then `failure_mode == pool_exhausted`, Sentry `error`, `[ci/inngest-pool]` issue with stale-session remediation, AND restart SKIPPED.
- Given inngest is genuinely down (existing probe sets `inngest_down`), when the pool-probe step runs, then it does NOT overwrite `inngest_down`, restart IS dispatched (regression guard: pool probe must not mask a real down).
- Given `SUPABASE_ACCESS_TOKEN` is unset/invalid (401/403), when the watchdog runs, then `failure_mode == pool_probe_unavailable`, Sentry `error`, the response body is printed for diagnosis, AND no false pool_exhausted remediation issue is filed, AND restart SKIPPED.

### Edge Cases

- Non-JSON 2xx body → `pool_probe_unavailable` (jq guard `type=="array"` fails) — warn, do not crash under `set -euo pipefail`.
- `EMAXCONNSESSION` appearing in a 2xx body (unlikely) → still classified `pool_exhausted` via the substring check.
- Log-injection: a crafted `state` value (it is a fixed enum from pg, but defense-in-depth) flows through `strip_log_injection` before any annotation.

### Integration Verification (for `/soleur:qa`)

- **API verify (read-only):** `SUPA=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain); curl -s --max-time 15 -X POST https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' -d '{"query":"select state, count(*) from pg_stat_activity group by state"}' | jq .` expects a JSON array of `{state,count}` rows. (Read-only; no cleanup.)
- **Workflow dry-run:** `gh workflow run scheduled-inngest-health.yml --ref <feature-branch>` then inspect the run log for the pool-probe step output. (`workflow_dispatch` already exists at `:36`, and the workflow is already on the default branch, so dispatch from the feature branch works.)

## Success Metrics

- A pool-pressure event is alerted (issue + Sentry) at ~70% of cap, *before* `EMAXCONNSESSION`, on at least one observed run (or synthetic test).
- Zero restarts dispatched for `pool_exhausted`/`pool_pressure` (verified by the gate exclusion).
- The `default_pool_size` revert decision is discoverable in `inngest.tf` by `grep default_pool_size`.

## Dependencies & Prerequisites

- Doppler `prd_terraform` must carry `TF_VAR_supabase_access_token` before the IaC change merges (Risk R3 / PM1).
- The PAT owner must have read access to project `pigsfuxruiopinouvjwy`.
- No code dependency on #5560 (durable-secrets-in-argv) or any skills change — separate PR.

## Risk Analysis & Mitigation

- **R1 — pool probe masks a real `inngest_down`.** Mitigation: pool-probe runs after the liveness probe and only sets a mode when `failure_mode` is empty; regression test guards it. (FR6 / test 4.)
- **R2 — token leak into public Actions log.** Mitigation: curl `2>/dev/null`, `strip_log_injection` on body, fixed read-only query, account-scoped PAT in GH secret store only (never container). (NFR2 / FR5.)
- **R3 — no-default TF var fails the whole auto-applied infra apply if Doppler `prd_terraform` lacks the value.** Mitigation: provision `TF_VAR_supabase_access_token` before merge; if not feasible in-session, split the PR (workflow YAML merges first — no `*.tf` trigger — IaC follows). (PM1 / Apply path.)
- **R4 — Management API 401 is a validation/scope signal, not pure auth.** Mitigation: probe prints the response body on non-2xx; `pool_probe_unavailable` is a soft mode, not a false restart. (learning `2026-06-16-supabase-mgmt-api-401…`.)
- **R5 — awk/union AC false-pass or issue auto-close collision.** Mitigation: flag-based awk in FR2; separate per-class issue title searches for file/close (no union search). (learning `2026-05-15-plan-ac-verification…`.)
- **R6 — threshold drift if `default_pool_size` is reverted 30→15.** Mitigation: `SESSION_POOL_CAP` is a workflow env literal (default 15) so the 70% point tracks the live cap; the comment in `inngest.tf` keeps the cap value discoverable. Set `SESSION_POOL_CAP=15` to match the post-revert default.

## Documentation Plan

- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — new "session-pool pressure/exhaustion" subsection (QG3); the tracking-issue body links to it.
- `inngest.tf` comment block (FR8) is self-documenting IaC.

## References & Research

### Internal References

- Watchdog workflow: `.github/workflows/scheduled-inngest-health.yml` (full — strip_log_injection `:61-64`, record_failure `:67`, retry loop `:80-107`, output `:109-114`, Auto-dispatch gate `:117`, tracking issue `:127-158`, auto-close `:160-174`, Sentry `:176-185`).
- Canonical Management-API curl: `apps/web-platform/scripts/postgrest-reload-schema.sh:112-159`.
- IaC patterns: `apps/web-platform/infra/inngest.tf:162-176` (out-of-band `INNGEST_POSTGRES_URI`), `:178-185` (ignore_changes note), `kb-drift.tf:111-115` + `doppler-write-token.tf:40-51` (`github_actions_secret`), `variables.tf:157` (`resend_receiving_api_key` no-default operator-PAT var shape), `main.tf` (providers — no Supabase provider).
- Client cap: `apps/web-platform/infra/inngest-bootstrap.sh:300-302,354` (`--postgres-max-open-conns 10`); commit `0a6665ea1` (#5559).
- Sibling probe pattern: `.github/workflows/scheduled-realtime-probe.yml` (retry loop, strip_log_injection, heartbeat).
- Sentry heartbeat action: `.github/actions/sentry-heartbeat/action.yml`.

### Learnings

- `knowledge-base/project/learnings/2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md` — print the response body; 401 ≠ pure auth.
- `knowledge-base/project/learnings/2026-06-02-supabase-disk-io-monitor-via-security-definer-rpc-not-management-api.md` — RPC-vs-PAT is a *runtime* concern; external watchdog with GH-secret PAT is the correct exception (cited in Alternatives).
- `knowledge-base/project/learnings/2026-03-05-github-output-newline-injection-sanitization.md` — `printf '%s\n'` + `tr -d '\n\r'` for untrusted `$GITHUB_OUTPUT`.
- `knowledge-base/project/learnings/2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md` — flag-based awk; no union search.
- `knowledge-base/engineering/operations/post-mortems/inngest-durable-redis-missing-outage-postmortem.md` — why silent durable-backend degradation is a brand risk.

### Related Work

- Issue: #5562 (this). Refs #5450 (durable cutover), #5558 (EMAXCONNSESSION root cause, CLOSED by #5559), #5549 (external watchdog, MERGED), #5559 (client cap 10, MERGED `0a6665ea1`).
- Separate PR from: #5560 (durable-secrets-in-argv).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled (`aggregate pattern`).
- The pool-probe step MUST run *after* the liveness probe and re-emit the combined `failure_mode` — wiring downstream `if:` to `steps.probe` (not `steps.poolprobe`) silently drops pool modes from Sentry/issue routing. FR6 guards this.
- `bash` functions do not cross GH-Actions steps — `strip_log_injection` is re-declared per-step, not hoisted. Copy verbatim from `:61-64` (`cq-regex-unicode-separators-escape-only`).
- Integer arithmetic only for the 70% trip (`(( total*100 >= cap*pct ))`) — float under `set -euo pipefail` aborts the step (shell-hardening learning).
