---
title: "feat: purchase rundevoo.run and onboard zone to Terraform (phase 1: domain + safe DNS)"
date: 2026-11-19
slug: feat-rundevoo-run-zone-onboarding
branch: feat-rundevoo-run-test-app
issue: 12971
closes: 12971
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Overview

`rundevoo.run` is registered at Cloudflare Registrar as of 2026-11-19
(RDAP-verified: nameservers `laila.ns.cloudflare.com` /
`lennon.ns.cloudflare.com` — the zone was auto-created in-account, so no NS
cutover and no pending-zone clock). This plan onboards that zone to Terraform
under a new root `infra/rundevoo-run/` with a safe-by-default DNS posture —
null MX, `v=spf1 -all`, DMARC `p=reject`, DNSSEC — plus the repo machinery
every managed root carries (apply workflow, drift leg, destroy-guard set,
required-check trio, CODEOWNERS, encryption-posture ledger, ops/legal
ledgers). Phase 1 deliberately ships no site and no app; the product shape is
the deferred follow-up in #12972.

Spec: `knowledge-base/project/specs/feat-rundevoo-run-test-app/spec.md`.
Brainstorm: `knowledge-base/project/brainstorms/2026-11-19-rundevoo-run-test-app-brainstorm.md`.
Authoritative precedent: the archived jikigai plan
`knowledge-base/project/plans/archive/20261013-051752-2026-09-09-feat-jikigai-cloudflare-zone-terraform-plan.md`
— rundevoo.run skips its hard parts (Registrar auto-creates the zone
in-account; registrar-managed DNSSEC publishes the DS automatically — no
registrar-side DS step, no 48h drain, no 28-day pending clock).

## User-Brand Impact

- **Artifact:** the rundevoo.run domain + its DNS/zone posture — the public
  surface a future Jikigai product is published under.
- **If this lands broken, the user experiences:** a page served on
  rundevoo.run (or absence of hardening visible to any third party checking
  DNS) that does not match what the repo claims is deployed.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  email spoofed as @rundevoo.run (no null MX / permissive SPF / missing
  DMARC), arbitrary content served on a company-owned domain attributable
  to Jikigai SARL, or a lapsed registration picked up by a squatter (the
  brainstorm's named real failure mode — covered by auto-renew +
  `domains.md`/`expenses.md` ledgers).
- **Brand-survival threshold:** `single-user incident` (carried forward from
  the brainstorm — unchanged).

`soleur:engineering:review:user-impact-reviewer` will be invoked at review
time (handled by the review skill's conditional-agent block).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR7: "destroy-guard triple" | Four mechanisms, not three: jq filter + counter test + `EXPECTED_SITES` regex-parity registry + required-check trio (+ CODEOWNERS rows, `merge_group` producer) | Plan enumerates all of them (Phase 1) |
| FR7: drift matrix entry | `scheduled-terraform-drift.yml` carries a hardcoded 3-leg matrix, no autodiscovery | Add a literal 4th leg (Phase 1) |
| FR2: R2 backend "copied from cla-evidence" | Confirmed verbatim; `use_lockfile=false` is load-bearing (R2 lacks conditional writes); single-writer enforced by apply workflow `concurrency` | Backend block copied with only `key` changed |
| FR4: zone-scoped token via bootstrap | Do NOT declare `cloudflare_api_token` in the root — its `data.cloudflare_api_token_permission_groups` read needs `User → API Tokens → Read`, which the Tier-A PR-plan credential lacks (this is exactly why `cla-evidence/infra/.pr-plan-skip` exists) | Token minted inside `bootstrap.sh` via `POST /user/tokens` + self-revoke; root declares only `cloudflare_zone`, `cloudflare_record`, `cloudflare_zone_dnssec` |
| FR10: `TF_VAR_*` in `prd_terraform` | Zone-scoped write token (`Zone:Read` + `Zone:DNS:Edit` + `Zone:DNSSEC/Zone-Settings:Edit`) there is Tier-A-reachable — accepted precedent (jikigai plan, Art. 30 PA-15 §(g)(4)); blast radius is one parked zone | Follow precedent; record acceptance in Art. 30 amendment |
| FR3: provider `~> 4.0` | Lockfile precedent pins 4.52.7 | Pin `~> 4.0`; dump local schema before authoring records (FR3) |
| `tenant-provisioning-runbook.md` inspected during brainstorm | Not on `origin/main` — not load-bearing | Not cited by this plan |
| FR1: purchase is "the only operator step" | Bootstrap needs a second sanctioned step: an operator-pasted 1h dashboard-minted ephemeral admin token (`User → API Tokens → Edit` + `Zone → Zone → Read` scopes), per the cla-evidence bootstrap contract — no standing credential carries that permission | Spec claim corrected: two operator steps (purchase done; one 1h token paste at Phase 0) |

## Research Insights

- **Relevant files:** `apps/cla-evidence/infra/main.tf` (R2 backend +
  provider retry block `retries = 6, min_backoff = 15, max_backoff = 120`),
  `apps/cla-evidence/infra/bootstrap.sh` + `apps/cla-evidence/scripts/_cf-admin-token.sh`
  (ephemeral-admin mint + self-revoke), `.github/workflows/apply-sentry-infra.yml`
  (apply-workflow shape: `merge_group:`, full-root plan, `sentry-destroy-required`
  always-run aggregator, concurrency group), `.github/workflows/scheduled-terraform-drift.yml`
  (hardcoded matrix), `tests/scripts/lib/destroy-guard-filter-web-platform.jq`
  (filter rule text), `apps/web-platform/infra/dns.tf` (record conventions,
  `cloudflare_zone_dnssec` precedent), `infra/github/ruleset-ci-required.tf`
  (required-check contexts), `scripts/encryption-posture-ledger.json`
  (`non_store_types`), `scripts/required-checks.txt`,
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`,
  `tests/scripts/test-destroy-guard-regex-parity.sh` (`EXPECTED_SITES`),
  `plugins/soleur/test/infra-validation-detect.test.sh` (sentinel census),
  `tests/scripts/test-infra-privileged-tier-census.sh` (reference-keyed
  auto-census — constrains `environment:` usage), `plugins/soleur/test/required-checks-canonical-parity.test.sh`
  (trio lockstep).
- **Institutional learnings:** `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`;
  `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md`;
  `integration-issues/2026-04-10-context7-terraform-provider-version-mismatch.md`
  (dump local schema, don't trust docs).
- **Premise Validation (Phase 0.6):** #12971 OPEN; #7995 OPEN (jikigai.com
  still unresolved — cited precedent holds); all cited files exist on
  `origin/main` except `tenant-provisioning-runbook.md` (not load-bearing);
  collision precheck `prs=none` (foreign `test-all.sh` processes belong to
  `feat-one-shot-mq-battery-shards` — unrelated); `git grep rundevoo
  origin/main` empty — no functional overlap.
- **Property List (Phase 0.6b):** P1 zone managed as code reproducible from
  empty state; P2 mail-spoof hardening; P3 drift detection; P4 destroy
  protection; P5 zone-scoped credential with no standing admin token; P6
  ownership/expense/compliance record.
- **Cut List (Phase 0.6b):** none — every proposed mechanism maps to a
  property; no existing mechanism covers the new zone (the root cannot fold
  into `apps/web-platform/infra` per spec TR1 + the isolation decision).
- **Conventions:** record names as literal FQDNs (`rundevoo.run`, not `@` —
  CF normalizes and causes perpetual diffs); `ttl = 1`, `proxied = false`.

## Files to Create

| File | Purpose |
|---|---|
| `infra/rundevoo-run/main.tf` | R2 backend (`key = "rundevoo-run/terraform.tfstate"`), provider `cloudflare/cloudflare ~> 4.0` with **`api_token = var.cf_api_token_rundevoo`** (explicit var binding works under `doppler run --name-transformer tf-var` in every shared leg — env-var auth is NOT available there), `required_version >= 1.7`, retry block |
| `infra/rundevoo-run/variables.tf` | `cf_account_id` (from `prd_terraform` `CF_ACCOUNT_ID`), `cf_api_token_rundevoo` (`sensitive`, **no default**; its description carries the `THIS DESCRIPTION IS THE SCOPE LEDGER` convention from `apps/web-platform/infra/variables.tf:397` so a future resource needing a new permission group can't silently 403) |
| `infra/rundevoo-run/zone.tf` | `cloudflare_zone.rundevoo_run` (`type = "full"`; **no `jump_start`** — create-time-only attribute, meaningless-to-harmful on an `import {}`-adopted zone) + committed `import {}` block with the literal zone id (comment its failure mode: a deleted/recreated zone changes the id and every plan hard-fails until the block is edited) + `cloudflare_zone_dnssec` |
| `infra/rundevoo-run/dns.tf` | Null MX (`type="MX"`, `priority=0`, `content="."` — RFC 7505), apex `TXT "v=spf1 -all"`, `_dmarc` `TXT "v=DMARC1; p=reject"` |
| `infra/rundevoo-run/bootstrap.sh` | Ephemeral-admin mint of `CF_API_TOKEN_RUNDEVOO` (zone-scoped `Zone:Read` + `Zone:DNS:Edit` + `Zone:DNSSEC/Zone-Settings:Edit` — `Zone:DNS:Edit` alone cannot `GET /zones/{id}` and the first plan would 403) via `POST /user/tokens`, writes to Doppler `prd_terraform`; **`trap`-based self-revoke on EXIT** (not end-of-success only — precedent revokes only on success and leaves a standing admin token on partial failure), revoke-minted-token-on-failure, read-back verify **with the minted token** — `GET /zones/{id}` + `GET /zones/{id}/dns_records` + `GET /zones/{id}/dnssec` (a `/user/tokens/{id}/verify` call proves validity, not coverage — ADR-130 "live probe, never the permission label") — and the Doppler write; revoke-on-remint; discovers + prints zone id |
| `infra/rundevoo-run/README.md` | Root docs: backend, credential tiers, how to re-run bootstrap |
| `infra/rundevoo-run/.terraform.lock.hcl` | Committed lockfile — both workflows run `terraform init -lockfile=readonly`; generated at Phase 0 item 5 |
| `infra/rundevoo-run/.gitignore` | `.terraform/`, `*.tfvars` (mirrors `apps/cla-evidence/infra/.gitignore`) |
| `.github/workflows/apply-rundevoo-infra.yml` | Mirror of `apply-sentry-infra.yml`: `push` to main path-filtered on `infra/rundevoo-run/**` + the workflow + filter + counter + verdict + squash-ack scripts + `pull_request:` **unfiltered (no `paths:`)** — the required check must report on every PR + `merge_group:` + `workflow_dispatch`; secret-free `detect-changes` job; `plan_pr` fork-refusal + squash-ack predictor call; apply job guarded `(push || workflow_dispatch) && github.ref == 'refs/heads/main'`; `rundevoo-destroy-required` always-run aggregator; `environment: infra-privileged` on the apply job; concurrency group |
| `scripts/rundevoo-destroy-gate-verdict.sh` | Aggregator verdict script (sibling: `scripts/sentry-destroy-gate-verdict.sh`, invoked by the workflow) |
| `tests/scripts/test-rundevoo-destroy-gate-verdict.sh` | Unit suite for the verdict script |
| `tests/scripts/lib/destroy-guard-filter-rundevoo.jq` | Filter: `cloudflare_zone`, `cloudflare_record`, `cloudflare_zone_dnssec` clauses counting `"delete"` **and** `"forget"`; no recursive `walk()`; nested-array shrinkage clauses **only where the Phase-0 schema dump shows a nested-block surface exists** (MX/TXT records have none — document the absence if dropped, don't ship vacuous clauses) |
| `tests/scripts/test-destroy-guard-counter-rundevoo.sh` | Counter suite pinning `EXPECTED_TESTS` with `-ne` (sibling mechanism name, `test-destroy-guard-counter-sentry.sh:513`) |
| `scripts/rundevoo-squash-ack-detect.sh` | PR-time `[ack-destroy]`-in-squash predictor (per-gate copy of `scripts/sentry-squash-ack-detect.sh`, invoked by `plan_pr`) — without it a legitimately-destroying PR has no remediation path |
| `tests/scripts/test-rundevoo-squash-ack-detect.sh` | Unit suite for the predictor |
| `scripts/rundevoo-dns-set-equality.sh` | Set-equality probe: `GET /zones/:id/dns_records` vs the declared `cloudflare_record` set (declared set read from `terraform state`/`terraform output`, zone id from the committed `import {}` block) — runs in the drift leg gated `if: matrix.directory == 'infra/rundevoo-run'`; doubles as the Phase-3 whole-list check |
| `tests/scripts/test-rundevoo-dns-set-equality.sh` | Unit suite for the probe |

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/scheduled-terraform-drift.yml` | Add 4th matrix leg `infra/rundevoo-run` (hardcoded matrix); `token_drift` step stays gated to `apps/web-platform/infra`; `STACK_NAME` sed yields `infra/rundevoo-run` correctly |
| `scripts/required-checks.txt` | `rundevoo-destroy-required` row **with the ADR-139/#6049 justification block** (per-gate unreachability disposition: `bot-pr-with-synthetic-checks` ALLOWED_PATHS ∩ `infra/rundevoo-run/**` = ∅ — mirrors the sentry block ~lines 223-244) |
| `scripts/ci-required-ruleset-canonical-required-status-checks.json` | `rundevoo-destroy-required` entry |
| `infra/github/ruleset-ci-required.tf` | `rundevoo-destroy-required` context entry + matching comment convention (sibling: `sentry-destroy-required` ~line 169) — edits a second auto-applied root; parallel-safe, distinct state keys (see Sharp Edges) |
| `scripts/encryption-posture-ledger.json` | Add `cloudflare_zone` to `non_store_types` (alphabetical slot near other zone types) — currently absent, lint fails closed without it |
| `.github/CODEOWNERS` | Rows for `/infra/rundevoo-run/`, the workflow, the jq filter, the counter test → `@deruelle` (pattern lines ~149-177, 220-223) |
| `tests/scripts/test-infra-privileged-tier-census.sh` | Reference-keyed auto-census (no row to add) — but the mirrored workflow must satisfy its rules: Tier-B-holding jobs declare a literal `environment:` in the tier_b set; PR-triggered jobs can't hold Tier-B (apply job gets `environment: infra-privileged`, plan_pr does not) |
| `scripts/test-all.sh` | `run_suite` registration for `test-destroy-guard-counter-rundevoo.sh` + `test-rundevoo-destroy-gate-verdict.sh` + `test-rundevoo-squash-ack-detect.sh` + `test-rundevoo-dns-set-equality.sh` (pattern ~line 6879) |
| `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` | Regenerated — **generated files, not hand-edited** (regen path in `test-all.sh`) |
| `scripts/lib/test-affected-paths.sh` | Declared edges for the two new suites (~lines 1923-2058) |
| `tests/scripts/test-destroy-guard-regex-parity.sh` | `EXPECTED_SITES` rows for the new workflow + new counter suite + `rundevoo-squash-ack-detect.sh` — **NOT the verdict script** (sentry's carries no canonical regex and is deliberately not a member); update the "seven sites" header count (7→10) and scope-pin loop |
| `scripts/pr-fanout-ledger.txt` | Row for `apply-rundevoo-infra.yml` (mirrors sentry row ~line 60: job count / `paths=no` / `cancel=no` + consequence + `no cancel:` justification) — `pr-fanout-ledger.test.sh` reds any unfiltered `pull_request:` workflow with no row; also enrolls the workflow in `cancel-superseded-pr-runs.yml` reaping |
| `scripts/required-check-wallclock-bounds.tsv` | Row for `rundevoo-destroy-required` — seed = sibling bound (`sentry-destroy-required	180	120	0.30`), documented as a seed choice since a new check has no measured p90 |
| `knowledge-base/operations/domains.md` | Row: `rundevoo.run \| Cloudflare \| 2027-11-19 \| laila.ns.cloudflare.com / lennon.ns.cloudflare.com \| parked; Terraform-managed (infra/rundevoo-run); null MX + SPF -all + DMARC reject; #12971` |
| `knowledge-base/operations/expenses.md` | Recurring row `rundevoo.run \| Cloudflare \| domain \| 21.20 \| active \| 2027-11-19`; One-Time row for the initial 1-yr registration |
| `knowledge-base/legal/article-30-register.md` | Dated amendment/new PA recording §0 scope conclusion + the `CF_API_TOKEN_RUNDEVOO` credential posture (PA-15 §(g)(4) precedent) |

## Implementation Phases

### Phase 0 — Bootstrap credential (pre-merge, agent-run)

1. Dump the local provider schema (`terraform providers schema -json` against
   the pinned ~> 4.0 / 4.52.7 lock) and verify: `cloudflare_record` accepts
   `content = "."` for `type = "MX"` (RFC 7505 null MX), and the
   `cloudflare_zone` + `cloudflare_zone_dnssec` attribute shapes. Do not
   author records against docs — the version-mismatch learning applies.
2. Author `infra/rundevoo-run/` files (above).
3. Run `bootstrap.sh` (agent-driven; second and last operator step is — sources `apps/cla-evidence/scripts/_cf-admin-token.sh`; record the cross-app coupling in the root README)
   pasting a **1h dashboard-minted ephemeral admin token** with scopes
   `User → API Tokens → Edit` + `Zone → Zone → Read` — the script documents
   them, like `apps/cla-evidence/infra/bootstrap.sh:21-23`):
   discover the zone id via `GET /zones?name=rundevoo.run` (requires the Zone
   Read scope — without it the list returns empty), mint a zone-scoped
   `Zone:Read` + `Zone:DNS:Edit` + `Zone:DNSSEC/Zone-Settings:Edit`
   token scoped to `com.cloudflare.api.account.zone.<zone_id>`,
   write `CF_API_TOKEN_RUNDEVOO` to Doppler `prd_terraform` (ADR-065: the var
   must exist before the IaC merges), read-back verify, then
   `trap`-on-EXIT self-revoke of the admin token (any failure after mint also
   revokes the minted token id — no orphan credentials).
4. Commit the `import { to = cloudflare_zone.rundevoo_run, id = "<zone_id>" }`
   block with the literal zone id — this is what makes `terraform apply` from
   empty state reproduce the zone with zero extra steps (G2).
5. Local `terraform init` + `terraform plan -refresh=false` sanity (bounded
   placeholder vars as the PR-plan leg does); commit `.terraform.lock.hcl`.
   Then **one real `terraform plan` with the minted token before pushing** —
   the `-refresh=false` placeholder run cannot observe import/`jump_start`
   interactions. Push-ordering gate: the Doppler write (item 3) must land
   before any push containing `infra/rundevoo-run/**`, else the PR plan leg
   reds on the missing required variable; the committed
   `.terraform.lock.hcl` must land in the same first push or
   `init -lockfile=readonly` fails before plan.

### Phase 1 — Workflow + guard wiring (same PR)

6. `apply-rundevoo-infra.yml` mirroring `apply-sentry-infra.yml` (full-root
   plan, no `-target`; `rundevoo-destroy-required` always-run aggregator;
   **`pull_request:` unfiltered** so the required check reports on every PR —
   the #5585 lesson at `apply-sentry-infra.yml:92-98`; `merge_group:`;
   `workflow_dispatch` escape; `[skip-*]` kill switch; concurrency group;
   apply job guarded to main push/dispatch only; `environment:
   infra-privileged` on the apply job; `doppler run --name-transformer
   tf-var` over `prd_terraform` via `infra-credentials` composite —
   **every consumer leg maps `CLOUDFLARE_API_TOKEN` explicitly from
   `CF_API_TOKEN_RUNDEVOO` with no fallback to the broad `cf_api_token`**
   (a default picking up the broad token greens CI while masking the
   under-scoped mint); fork-refusal step copied verbatim
   (`pull_request` carries no secrets; never `pull_request_target` on
   untrusted `.tf`)).
7. Drift leg: 4th entry in `scheduled-terraform-drift.yml` matrix.
8. Destroy-guard set: jq filter (carries the `plan_ok` key — distinguishes
   "no destructive changes" from "nothing was read"; document the
   `resource_creates` omission — no import-only untargeted surface here),
   counter test, `EXPECTED_SITES` rows (workflow + counter + squash-ack
   script), required-check trio (`required-checks.txt` + ADR-139 block,
   canonical JSON, `ruleset-ci-required.tf`), CODEOWNERS,
   `pr-fanout-ledger.txt` row, `required-check-wallclock-bounds.tsv` seed
   row, suite registrations (test-all.sh, regenerated TSVs,
   test-affected-paths.sh).
9. `cloudflare_zone` → `non_store_types` in `encryption-posture-ledger.json`;
   run `scripts/lint-encryption-posture.py` green.

### Phase 2 — Ledgers + compliance records (same PR)

10. `domains.md` row, `expenses.md` recurring + one-time rows, Art. 30
    register dated amendment (record §0 scope conclusion + token posture).
11. Update issue #12971 checklist state if the body tracks phase items.

### Phase 3 — Post-merge verification (workflow-driven)

12. After merge: `apply-rundevoo-infra.yml` runs (imports the zone via the
    committed `import {}` block, creates records + DNSSEC);
    `apply-github-infra.yml` applies the ruleset trio.
13. Verify via Cloudflare REST API (`GET /zones/:id/dns_records`), not `dig`
    alone — anycast edge lags; assert **set equality** (no record exists that
    Terraform doesn't declare — the whole-list blind spot).
14. `dig MX rundevoo.run` → null MX; `dig TXT rundevoo.run` → `v=spf1 -all`;
    `dig TXT _dmarc.rundevoo.run` → `p=reject`; DNSSEC `status` on the zone.
15. Confirm the drift leg plans green on its next scheduled run (the
    zone-scoped token must support a **refreshing** plan — reinforcing the
    no-`cloudflare_api_token` constraint). Expected transient: a scheduled
    drift dispatch between merge and a completed first apply reports
    spurious drift — self-healing once the apply lands.
16. **G1 verification (spec G1 / issue AC 1):** verify the registrar
    posture — `auto_renew` on and registrant entity Jikigai SARL — via the
    Cloudflare registrar API (dashboard attestation recorded in `domains.md`
    if the API surface doesn't expose registrant detail).
17. **Retroactive open-PR unblocking:** once `apply-github-infra` applies the
    ruleset trio, `rundevoo-destroy-required` is required on every PR —
    including ones opened before the check existed, which sit "Expected —
    Waiting". Post synthetic check-runs on each open PR's head SHA:
    `gh api repos/{owner}/{repo}/check-runs -f name=rundevoo-destroy-required
    -f head_sha=<sha> -f status=completed -f conclusion=success` over
    `gh pr list --state open --json headRefOid` (dispatching the workflow on
    PR branches does NOT work — the branch lacks the new workflow file).
    Already-queued merge-queue entries need re-queue, not a check-run.

## Infrastructure (IaC)

### Terraform changes

- New root `infra/rundevoo-run/` (files above); provider `cloudflare/cloudflare ~> 4.0`;
  `required_version >= 1.7`; R2 backend `soleur-terraform-state` key
  `rundevoo-run/terraform.tfstate`, `use_lockfile = false`.
- Sensitive vars: `TF_VAR_cf_api_token_rundevoo` ← Doppler `prd_terraform`
  `CF_API_TOKEN_RUNDEVOO` (zone-scoped `Zone Read` + `DNS Write` + `Zone
  Settings Write` token, minted by bootstrap — DNS Write covers the
  `/zones/{id}/dnssec` PATCH per the API reference, so no separate DNSSEC
  group exists to request).
- `account_id` is a **literal** in `zone.tf` (measured 2026-11-19: the zone
  lives in the `66d4f93f…` "Soleur" account, NOT prd_terraform's
  `CF_ACCOUNT_ID` `4d5ba6f0…` — the R2/state/tunnel account; soleur.ai sits
  in the same Soleur account). No `cf_account_id` var — a literal bound to
  the zone id fails closed on account change and needs no new secret.
- `infra/github/ruleset-ci-required.tf` gains one `context` entry —
  second auto-applied root; **parallel-safe, distinct state keys** (the two
  workflows' concurrency groups differ, so they genuinely run concurrently —
  benign because `use_lockfile=false` only matters within a root).

### Apply path

Committed `import {}` block + post-merge apply workflow — the zone
pre-exists (Registrar created it), so Terraform adopts it declaratively on
first apply. Blast radius: one parked zone; no downtime concept (no service).

### Distinctness / drift safeguards

- Zone-scoped token cannot touch soleur.ai (ADR-130 retained-scope probe
  in `bootstrap.sh`'s verify step: `GET /zones/{soleur_ai_zone_id}` expects
  **4xx** — a `GET /zones?name=soleur.ai` list call returns 200 with
  `result: []`, not 403, so the probe must fetch the specific zone id).
- Secret token value lands in `terraform.tfstate` on the existing R2 state
  store (recorded in Encryption Posture).
- Drift leg is the standing distinctness check between declared and live DNS.

### Vendor-tier reality check

Cloudflare Registrar + zone on the existing account/plan; no free-tier quota
affects zone records or DNSSEC. DNSSEC DS publication is automatic because
Cloudflare is the registrar (the jikigai hard case does not apply).

## Observability

```yaml
liveness_signal:
  what: scheduled-terraform-drift.yml 4th matrix leg running terraform plan -detailed-exitcode with refresh against the live zone
  cadence: the workflow's existing schedule
  alert_target: workflow failure → GitHub Actions notification (existing route; no new pager for a parked zone)
  configured_in: .github/workflows/scheduled-terraform-drift.yml
error_reporting:
  destination: GitHub Actions run logs (apply-rundevoo-infra.yml, scheduled-terraform-drift.yml)
  fail_loud: terraform plan/apply non-zero exit reddens the run; destroy aggregator requires [ack-destroy]
failure_modes:
  - mode: zone records edited/removed outside Terraform (dashboard change to managed state)
    detection: drift leg plan -detailed-exitcode exit 2
    alert_route: workflow run failure
  - mode: additive drift (out-of-band record ADDED — plan cannot see it: plan only covers state ∪ config)
    detection: set-equality probe step in the drift leg — `GET /zones/:id/dns_records` vs declared `cloudflare_record` set
    alert_route: drift leg run failure
  - mode: zone-scoped token expires/revoked
    detection: drift leg + apply both fail on 401/403
    alert_route: workflow run failure; bootstrap.sh re-mints
  - mode: zone deleted/forgotten in state or account
    detection: destroy-guard filter counts delete+forget on cloudflare_zone; apply re-imports via import{} block
    alert_route: rundevoo-destroy-required required check
logs:
  where: GitHub Actions run logs
  retention: GHA default
discoverability_test:
  command: gh run list --workflow scheduled-terraform-drift.yml --limit 1
  expected_output: scheduled-terraform-drift
```

## Task Design

New autonomous-task surface: `.github/workflows/apply-rundevoo-infra.yml` and
the 4th `scheduled-terraform-drift.yml` leg.

- **Trigger surface:** `push` to main path-filtered on `infra/rundevoo-run/**`
  + the workflow + the jq filter + counter test; `merge_group:` (required for
  the ruleset trio's merge-queue coverage); `workflow_dispatch` escape hatch.
- **Kill switch:** `[skip-*]` convention mirrored from sibling apply
  workflows.
- **Concurrency:** workflow `concurrency` group — the single-writer
  mechanism compensating for `use_lockfile = false` on R2.
- **Pattern note (domain #2+):** this is the first landing of the
  per-domain-root pattern; at the second landing, evaluate one shared apply
  workflow with per-domain static-named aggregator jobs (required contexts
  must be static — a matrix can't mint them) rather than a third byte-copy.
- **Blast radius on misfire:** the *Cloudflare data plane* is bounded by
  the zone-scoped token — but the apply job's `environment:
  infra-privileged` loads the full `soleur-infra-privileged/prd` set
  including `TF_STATE_AWS_*` = **read/write on the whole
  `soleur-terraform-state` bucket** (all roots' state). Separate state key is
  a namespace split, not a credential-perimeter split — precedent-consistent
  (every apply job shares it); stated here so the claim isn't over-read.
  The apply is full-root (no `-target`), so a misfire converges toward
  declared state.
- **Census updates:** `tests/scripts/test-infra-privileged-tier-census.sh`
  (reference-keyed auto-census — no rows, but the workflow must satisfy its
  Tier-B `environment:` rules); `EXPECTED_SITES` + header count in
  `test-destroy-guard-regex-parity.sh`; `test-all.sh` `run_suite` +
  regenerated `suite-shard-legs.tsv`/`suite-durations.tsv` +
  `test-affected-paths.sh` edges for the two new suites
  (`lint-orphan-test-suites.sh` reds unregistered suites);
  `infra-validation-detect.test.sh` sentinel set intentionally untouched (no
  `.pr-plan-skip` — the root must plan under the Tier-A credential).

## Encryption Posture

```yaml
at_rest:
  - store: terraform.tfstate on R2 (soleur-terraform-state, key rundevoo-run/terraform.tfstate)
    mechanism: R2 server-side encryption (existing store — contains CF_API_TOKEN_RUNDEVOO)
    evidence: existing backend precedent apps/cla-evidence/infra
    defends_against: state-store read exposing the zone token in cleartext at rest
    does_not_defend: Tier-A Doppler read of prd_terraform (accepted, PA-15 §(g)(4) precedent); live-state read by anyone holding the token
    disclosed_as: Art. 30 amendment + this section
    live_verification: drift leg authenticates against live zone each run
in_transit:
  - connection: GHA runner / local agent → Cloudflare API + R2 backend
    tls: provider/SDK TLS
    cert_verification: on
    does_not_defend: token leakage into run logs if not masked (mitigated: doppler secrets are masked; token never echoed by bootstrap.sh)
    disclosed_as: this section
```

## Guard Contract

### Guard 1 — destroy-guard filter `destroy-guard-filter-rundevoo.jq`

**Property.** Any terraform plan JSON that deletes, forgets, or shrinks a
`cloudflare_zone`, `cloudflare_record`, or `cloudflare_zone_dnssec` resource
for rundevoo.run requires an explicit `[ack-destroy]` acknowledgement before
apply.

**Assembly.** The filter is the chokepoint: `apply-rundevoo-infra.yml`'s
detect-changes job pipes every plan JSON through it before apply; the counter
test `test-destroy-guard-counter-rundevoo.sh` pins minimum assertion counts
per clause so a silently-emptied clause cannot stay green; the parity test's
`EXPECTED_SITES` pins the `[ack-destroy]` site set.

**Mutation matrix:**

| Mutation | Expected |
|---|---|
| plan JSON deletes `cloudflare_zone.rundevoo_run` | filter counts it → destroy gate demands `[ack-destroy]` (RED without) |
| plan JSON has `action: "forget"` on `cloudflare_zone` (state-drop, no delete) | counted — a forget-only clause misses it (RED without) |
| `cloudflare_record` count shrinks via nested-array shrinkage (not a delete action) | shrinkage clause catches it (RED without) |
| filter file emptied to `0` assertions | counter suite `EXPECTED_TESTS -ne` reds (harness row) |
| `[ack-destroy]` moved inside a sentence (`[ack-destroy]ing`) | regex-parity `(^|$'\n')\[ack-destroy\]($|$'\n')` literal does not match — site not counted (harness row) |
| a no-destroy plan JSON | must-PASS: gate green without ack |

**Anchor.** `EXPECTED_SITES` and `EXPECTED_TESTS` are reviewed registry
values — a weakening must move both the filter and its independently reviewed
counter/parity pins in one diff; CODEOWNERS routes all of them to `@deruelle`.

### Guard 2 — drift leg (`scheduled-terraform-drift.yml` matrix)

**Property.** Any live-state difference between the rundevoo.run zone and the
declared Terraform reddens the scheduled run.

**Assembly.** The matrix leg is the chokepoint — it runs
`terraform plan -detailed-exitcode` **with refresh** under the real
zone-scoped token from `prd_terraform`, **plus the
`rundevoo-dns-set-equality.sh` step** gated `if: matrix.directory ==
'infra/rundevoo-run'` (`GET /zones/:id/dns_records` vs the declared
`cloudflare_record` set, `CLOUDFLARE_API_TOKEN` mapped inside the `doppler
run` wrapper): a refreshing plan structurally cannot see *added* out-of-band
records (it covers state ∪ config only), so the leg must carry the
enumeration probe to cover the whole-list property.

**Mutation matrix:**

| Mutation | Expected |
|---|---|
| live DNS record edited out-of-band (dashboard edit) | plan exit 2 → RED |
| `cloudflare_api_token` resource or permission-groups data source added to the root | plan under the zone-scoped token fails permanently → RED (and TR5 violation caught by census) |
| matrix leg removed while root remains | the leg is a pinned registry row — removal reddens the workflow's own matrix (harness row) |
| green drift run on conforming state | must-PASS |

**Anchor.** The matrix is a hardcoded list inside the workflow — a diff that
removes the leg edits the guard's own dispatch in the same CODEOWNERS-covered
file; the leg is not self-certifying because its membership is reviewed.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Product (NONE tier — no UI surface)

### Engineering

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** CTO mapped the zone-onboarding path: new TF root + R2 backend
+ zone-scoped token, reusing the deferred jikigai plan as the checklist;
Registrar purchase makes the zone auto-appear in-account, skipping the NS
cutover and 28-day pending clock that killed jikigai.com (#7995). The
`.pr-plan-skip` trap (no `cloudflare_api_token` resource in the root) is the
top implementation flag.

### Legal

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** CLO mapped the legal baseline: Jikigai SARL registrant, null
MX + SPF `-all` + DMARC `p=reject` as the spoof-hardening floor, Art. 30
register record, trademark knock-out search deferred as a later check.
No DPA change — Cloudflare is an existing sub-processor.

### Operations

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** COO confirmed the Cloudflare Registrar precedent (soleur.ai:
$140/2yr, ~$70/yr renewal; rundevoo.run ~$21.20/yr at-cost), auto-renew ON,
`domains.md` + `expenses.md` ledger rows.

### Product/UX Gate

**Tier:** none (mechanical UI-surface override did not fire — no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files lists)
**Decision:** N/A — infrastructure change, no user-facing surface. The
product-shape question is explicitly deferred to #12972.
**Brainstorm-recommended specialists:** none carried forward requiring
invocation.

**Agents invoked (this plan):** none — all findings carried forward from the
brainstorm's `## Domain Assessments` (CPO + CLO + CTO + COO + repo-research +
learnings agents, run 2026-11-19).

## GDPR / Compliance

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Gate triggered by brand-survival `single-user incident` (trigger (b)).
V1 checks against this plan's scope: no new schema columns (Art. 6, Art.
5(1)(e) — N/A), no FK to `users` (Art. 17 — N/A), no new non-EEA vendor —
Cloudflare is already a sub-processor/DPA'd (Chapter V — N/A), no Art. 9
columns (N/A).

**Scope conclusion (to record in the Art. 30 amendment):** a parked domain
with null MX and no site processes no personal data of data subjects; the
entry records the surface, the §0 scope-negative conclusion, and the
`CF_API_TOKEN_RUNDEVOO` credential posture rather than a full PA — unless the
register's §0 limb test resolves otherwise (final call recorded in the
amendment text itself).

## Architecture Decision (ADR/C4)

No new architectural decision: this lands the pattern the archived jikigai
plan already decided (per-company-domain TF root + zone-scoped token +
ephemeral-admin bootstrap). It is the *first landing* of that pattern, not a
new decision — the plan file is the record, mirroring how the jikigai plan
served as its own decision record.

### C4 views

No C4 impact. Checked the model's element declarations and all three files
(`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`):
(a) external human actors — none new (parked domain serves no users);
(b) external systems — `cloudflare` is already modeled as the
DNS/CDN/R2/tunnel vendor (model.c4 ~line 446); a second zone is another
instance of the same modeled system, not a new element; (c)
containers/data-stores — none new (R2 state backend already exists);
(d) relationships — none change. Derived cardinalities: no edge prose counts
domain zones, so `c4-count-parity` is unaffected by adding a zone.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "I want to purchase rundevoo.run domain which will be a test app on which we run soleur" | FR1 (purchase — completed at Cloudflare Registrar) + Phases 0-3 | mapped — test-app surface deferred to #12972 per settled brainstorm direction |
| 2 | "`dig MX rundevoo.run` returns null MX; TXT shows `v=spf1 -all` and DMARC `p=reject`; DNSSEC enabled." [issue #12971] | `dns.tf`, `zone.tf` (Phase 0 item 2) + AC 3-6 | mapped |
| 3 | "Drift-detection matrix includes the new root; destroy-guard, counter test, CODEOWNERS rows present; `lint-encryption-posture.py` green." [issue #12971] | Phase 1 items 7-9 | mapped |
| 4 | "`domains.md` and `expenses.md` rows added; Art. 30 register entry recorded." [issue #12971] | Phase 2 item 10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `infra/rundevoo-run/*.tf` | "purchase rundevoo.run domain" + "Terraform" (issue title) | asked |
| `apply-rundevoo-infra.yml` | "Drift-detection matrix includes the new root" (apply workflow is the mechanism the drift leg + destroy gate hang on) | inferred — justification: required-check aggregator must be produced by a workflow; spec FR6 prescribes it |
| destroy-guard filter + counter + parity rows | "destroy-guard, counter test, CODEOWNERS rows present" | asked |
| required-check trio rows | "destroy-guard, counter test, CODEOWNERS rows present" — the aggregator is only a gate if it is a required check | inferred — justification: without the trio the aggregator reports nothing blocking |
| `encryption-posture-ledger.json` row | "`lint-encryption-posture.py` green" | asked (the lint fails closed on unknown `cloudflare_zone`) |
| privileged-tier census conformance | — | inferred — justification: `test-infra-privileged-tier-census.sh` auto-censuses; the workflow must satisfy its `environment:` rules or it reds |
| `bootstrap.sh` | "purchase … domain" + ADR-065 var-before-merge | inferred — justification: `hr-tf-variable-no-operator-mint-default` forbids operator-minted defaults; bootstrap is the precedent pattern |
| ledger + Art. 30 rows | "`domains.md` and `expenses.md` rows added; Art. 30 register entry recorded" | asked |

### Split Assessment

- Subsystems touched: 4 — `infra/`, `.github/`, `tests/`, `knowledge-base/` (+ `scripts/`, `plugins/soleur/test/` adjacent)
- Planned files: ~17 | Estimated changed lines: ~400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: subsystem count trips the threshold, but the change is one atomic deliverable (a managed root is meaningless without its apply workflow + required check) — **single PR**, matching the jikigai plan's own shape.

## Acceptance Criteria

- [ ] `infra/rundevoo-run/` exists with R2 backend (`use_lockfile=false`), provider `~> 4.0`, committed `import {}` block; `terraform apply` from empty state reproduces zone + all records with no extra steps.
- [ ] No `cloudflare_api_token` resource or `data.cloudflare_api_token_permission_groups` in the root; no `.pr-plan-skip` sentinel.
- [ ] `dig MX rundevoo.run` returns `0 .`; `dig TXT rundevoo.run` shows `v=spf1 -all`; `dig TXT _dmarc.rundevoo.run` shows `p=reject`; `cloudflare_zone_dnssec` enabled and DS live (registrar-published).
- [ ] `scheduled-terraform-drift.yml` has a 4th matrix leg; the leg plans green with refresh.
- [ ] Destroy-guard set complete: `destroy-guard-filter-rundevoo.jq` (with `plan_ok` key), `test-destroy-guard-counter-rundevoo.sh`, `rundevoo-destroy-gate-verdict.sh` + `rundevoo-squash-ack-detect.sh` + `rundevoo-dns-set-equality.sh` with unit suites, `EXPECTED_SITES` rows (workflow + counter + squash-ack; header count 7→10), `rundevoo-destroy-required` in all three required-check surfaces (`required-checks.txt` row carries the ADR-139 justification block), CODEOWNERS rows.
- [ ] Registrations: `test-all.sh` `run_suite` rows, regenerated `suite-shard-legs.tsv`/`suite-durations.tsv`, `test-affected-paths.sh` edges — `lint-orphan-test-suites.sh` green; `pr-fanout-ledger.txt` + `required-check-wallclock-bounds.tsv` rows present.
- [ ] `apply-rundevoo-infra.yml` fires `pull_request:` unfiltered so `rundevoo-destroy-required` reports on every PR.
- [ ] Drift leg includes the `if: matrix.directory == 'infra/rundevoo-run'` set-equality probe step.
- [ ] `apply-rundevoo-infra.yml` present with `merge_group:`, full-root plan, always-run aggregator, dispatch escape, concurrency group.
- [ ] `cloudflare_zone` in `encryption-posture-ledger.json` `non_store_types`; `scripts/lint-encryption-posture.py` green.
- [ ] `test-infra-privileged-tier-census.sh` and `required-checks-canonical-parity.test.sh` green with the new workflow/rows.
- [ ] `domains.md` + `expenses.md` rows (recurring $21.20/yr, renewal 2027-11-19; one-time registration) present; Art. 30 register dated amendment recorded.
- [ ] Registrant entity is Jikigai SARL and auto-renew is ON (verified via registrar API or dashboard attestation recorded in `domains.md`).
- [ ] `CF_API_TOKEN_RUNDEVOO` exists in Doppler `prd_terraform` before any push containing `infra/rundevoo-run/**` (ADR-065); retained-scope probe shows the token reaches rundevoo.run and gets a 4xx fetching the soleur.ai zone id.
- [ ] `infra/rundevoo-run/.terraform.lock.hcl` + `.gitignore` committed; `terraform init -lockfile=readonly` succeeds.

## Sharp Edges

- **The zone token needs three groups, not one.** `Zone:DNS:Edit` alone
  cannot `GET /zones/{id}` — mint `Zone:Read` + `Zone:DNS:Edit` +
  `Zone:DNSSEC/Zone-Settings:Edit`, and verify coverage by live probe with
  the minted token (`GET /zones/{id}`, `/dns_records`, `/dnssec`), never by
  the permission label (ADR-130).
- **`CLOUDFLARE_API_TOKEN` is the env var the provider reads** — every
  consumer leg (plan_pr, apply, drift, set-equality probe) maps it
  explicitly from `CF_API_TOKEN_RUNDEVOO`, with no fallback to the broad
  `cf_api_token` (a silent fallback greens CI on the wrong credential).
- **No `cloudflare_api_token` resource in the root.** Its permission-groups
  data source needs `User → API Tokens → Read`, which `Zone:DNS:Edit` lacks —
  that is why `cla-evidence/infra` carries `.pr-plan-skip`. Declaring it makes
  every PR plan and every drift run permanently red and trips the sentinel
  census (TR5).
- **Apex record names are literal FQDNs** (`rundevoo.run`), never `@` —
  perpetual-diff trap per `apps/web-platform/infra/dns.tf` comments.
- **Verify `content = "."` for the null MX** against the locally dumped
  4.52.7 schema before authoring (FR3); provider docs drift
  (`integration-issues/2026-04-10-context7-terraform-provider-version-mismatch.md`).
- **Destroy-guard must count `"forget"`** alongside `"delete"` — a state-drop
  of the zone is the incident and passes every gate otherwise.
- **`EXPECTED_SITES` is a hardcoded registry** — adding the workflow +
  counter suite without its rows reddens the parity test; the canonical
  literal is `(^|$'\n')\[ack-destroy\]($|$'\n')`.
- **Two auto-applied roots are touched in one merge** — `apply-rundevoo-infra`
  (new root) and `apply-github-infra` (ruleset trio). The merge enqueues
  both; do not re-dispatch or race them. If the required-check trio lands in
  the ruleset before the workflow exists to produce
  `rundevoo-destroy-required`, every subsequent PR reds — keep workflow +
  trio in the same merge (this PR does exactly that).
- **Self-wedge recovery:** once the trio lands, a broken rundevoo root
  makes `rundevoo-destroy-required` red on every PR *including the fix PR*.
  Recovery levers: (a) `gh pr merge --admin` (bypass actors already on the
  ruleset); (b) a revert PR removing the context — it touches only
  `infra/github/*.tf` + `scripts/*.txt|json`, outside the rundevoo detect
  anchors → `detect=false` → synthetic PASS → merges cleanly. The rollback
  path is not self-blocking.
- **Token rotation:** `CF_API_TOKEN_RUNDEVOO` carries no expiry — on a leak
  signal, re-run `bootstrap.sh` (revoke-on-remint rotates it). Reachability ≠
  privilege: the token is Tier-A-readable in `prd_terraform` but writes only
  this zone's DNS (recorded in the Art. 30 amendment).
- **Assert set equality via the Cloudflare REST API**, not `dig` — `dig`
  cannot enumerate records, and the anycast edge lags tens of seconds
  post-apply.
- **A plan whose `## User-Brand Impact` section is empty or omits the
  threshold fails `deepen-plan` Phase 4.6** — it is filled above.
- **Bootstrap writes to Doppler `prd_terraform`** (`CF_API_TOKEN_RUNDEVOO`)
  before merge (ADR-065 sequencing); the token is Tier-A-reachable — accepted
  per the jikigai/PA-15 §(g)(4) precedent and recorded in the Art. 30
  amendment.
- **`pull_request:` must be unfiltered** — a `paths:`-filtered PR leg makes
  `rundevoo-destroy-required` never report on untouched PRs; every PR wedges
  "Expected — Waiting" once the ruleset lands (#5585).
- **Second operator step is the 1h ephemeral admin token** (dashboard-minted,
  `User → API Tokens → Edit` + `Zone → Zone → Read`) — no standing credential
  can mint API tokens; the spec's "purchase is the only operator step" was
  corrected in Reconciliation.
- **Bootstrap partial-failure hardening:** precedent self-revokes only on
  success — use `trap ... EXIT` for the admin token, revoke the minted
  zone token on any post-mint failure, read-back verify the Doppler write,
  revoke the previous token on remint.
- **Census/registration surfaces that must move in the same diff:**
  `test-all.sh` `run_suite` + regenerated shard/duration TSVs +
  `test-affected-paths.sh` edges (`lint-orphan-test-suites.sh` reds
  unregistered suites); `test-destroy-guard-regex-parity.sh`
  (`EXPECTED_SITES` + header count); required-check trio lockstep
  (`required-checks-canonical-parity.test.sh`); `required-checks.txt` row
  needs its ADR-139 justification block.
  `infra-validation-detect.test.sh` and
  `test-infra-privileged-tier-census.sh` need no rows — the former pins the
  sentinel set (leave untouched), the latter auto-censuses but constrains the
  workflow's `environment:` usage.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Fold the zone into `apps/web-platform/infra` | Spec TR1: the merge-apply resolves every root variable before `-target` pruning; mixing a second company's domain into the production surface couples blast radii |
| `cloudflare_api_token` in Terraform | Requires account-scoped read the zone token lacks → `.pr-plan-skip` → TR5 violation (research flag #1) |
| State-only `terraform import` in bootstrap | Committed `import {}` block is declarative and survives state loss; chosen instead |
| Public landing page / "coming soon" | Out of scope for phase 1 (product shape deferred to #12972); a parked domain serves nothing |

## Deferred Follow-ups

- Product-shape brainstorm for rundevoo.run — **#12972** (already filed);
  add the brainstorm decision-10 standing constraints to its body (no
  outbound email, no real personal data, deploy only via PR-merge→CI).
- Trademark knock-out search on "rundevoo" — a later legal check (named in
  the brainstorm's deferred list); scope includes confusion with
  Cognition's Devin mark, not just registrability.
- Verify soleur.ai registrant entity is Jikigai SARL — housekeeping noted in
  the brainstorm.
