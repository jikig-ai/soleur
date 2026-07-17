<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "chore: read-only Better Stack token for the heartbeat live-reconcile"
issue: 6635
parent: 6549
branch: feat-one-shot-6635-betterstack-readonly-token
type: chore
classification: least-privilege-hardening
lane: single-domain
brand_survival_threshold: none
date: 2026-07-18
---

# 🔧 chore: read-only Better Stack token for the heartbeat live-reconcile (#6635)

> No `knowledge-base/project/specs/feat-one-shot-6635-betterstack-readonly-token/spec.md`
> was present at plan time. `lane: single-domain` set directly (accurate — one
> workflow file + one Doppler secret + one vendor token; no cross-domain surface).

## Enhancement Summary

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

**Deepened on:** 2026-07-18
**Sections enhanced:** verification-hardened (anchors, citations, IaC-routing exception)

### Key Improvements
1. **Line anchors verified live** — the reconcile step's Doppler read is at
   `scheduled-terraform-drift.yml:293`, its comment at `:297`, the `BETTERSTACK_API_TOKEN="$TOKEN"`
   script-env mapping at `:299` (all confirmed by `grep -n`; the swap touches only `:293`/`:297`).
2. **Citations verified live** — `#6537` CLOSED (the "9-days-dark" heartbeat blind spot),
   `#6548` OPEN (the diagnostic-first-run rationale), `#6549` OPEN (parent). All match the
   narrative role they are cited in.
3. **Negative claims confirmed** — `git grep BETTERSTACK_API_TOKEN -- '*.tf'` returns **zero**;
   the sibling read/write token lives directly in Doppler (outside Terraform), exactly the
   mechanism this plan uses for the readonly token (Phase-2.8 exception justified in the
   Infrastructure section).
4. **Runtime auth verification made a gate** — the Read scope's authorization of
   `GET /api/v2/heartbeats` is *exercised* pre-merge (Phase 3), not assumed.

### Deepen-plan gate results
- 4.6 User-Brand Impact: PASS (present; threshold `none`; edited file is NOT a sensitive-path
  per the canonical regex — `scheduled-terraform-drift.yml` matches none of doppler/secret/token/
  deploy/… — so the scope-out bullet is optional, and present anyway).
- 4.7 Observability: PASS (all 5 fields non-placeholder; `discoverability_test.command` is
  `gh workflow run …` — no SSH).
- 4.8 PAT-shaped variable halt: PASS (no `var.*_token`/`TF_VAR_(GITHUB|GH)_*`/`ghp_*` match;
  `BETTERSTACK_API_TOKEN` is a vendor API token, not a GitHub PAT).
- 4.9 UI-wireframe halt: N/A (no UI-surface file).
- 4.4 scheduled-work / 4.5 network-outage / 4.55 downtime-cutover: N/A (rides the existing
  Inngest dispatch; no SSH/network symptom; no serving surface taken offline).

### Research Insights — Better Stack Read-scope contract
The reconcile's ONLY call is `GET https://uptime.betterstack.com/api/v2/heartbeats` with
`Authorization: Bearer <token>` (script comment, `<!-- verified: 2026-07-17 -->` against
`apply-web-platform-infra.yml:1950`). A Better Stack **Read**-scoped global API token is
designed to authorize GET reads; the residual risk is only that the vendor's "Read" scope is
narrower than the heartbeats endpoint expects. Phase 3 closes this by exercising the token
against the live endpoint (script rc in {0,2}) rather than trusting the scope label — the
`FetchResult kind:"auth"` (401/403) → rc=1 path makes any scope shortfall LOUD, never silent.

## Overview

The `heartbeat-live-reconcile` job in `.github/workflows/scheduled-terraform-drift.yml`
reads Better Stack `GET /api/v2/heartbeats` using `BETTERSTACK_API_TOKEN` (Doppler
`soleur/prd_terraform`, **Read & write** scope). The reconcile only READS, so it should
use a dedicated **Read**-scoped token. This is a deliberate least-privilege fast-follow
from the #6549-item-2 reconcile (D1) — **not a defect**. v1 deliberately reused the
read/write token so the #6548 diagnostic first run was never blocked on an operator mint.

**Three mechanical steps** (the third is a one-line edit once the token exists):

1. Mint a dedicated **Read**-scoped Better Stack API token at
   `betterstack.com/settings/global-api-tokens`.
2. Store it as `BETTERSTACK_API_TOKEN_READONLY` in Doppler `soleur/prd_terraform`.
3. Swap the one `doppler secrets get` name the reconcile step reads
   (`BETTERSTACK_API_TOKEN` → `BETTERSTACK_API_TOKEN_READONLY`) in the workflow.

The change strictly REDUCES credential blast-radius. It touches no `.tf` file, gates no
`terraform apply`, and breaks no existing test (verified — see Research Reconciliation).

## Premise Validation

Checked at plan time; premise holds:

- **Issue #6635** — OPEN, not closed by any merged PR. `Ref #6549` (parent, OPEN). Valid.
- **Workflow exists**: `.github/workflows/scheduled-terraform-drift.yml`, job
  `heartbeat-live-reconcile`, step `Reconcile live heartbeats` (id `reconcile`).
  The `doppler secrets get BETTERSTACK_API_TOKEN --plain` read is at **line 293**;
  the comment naming the script's env contract is at **line 297**; the
  `BETTERSTACK_API_TOKEN="$TOKEN"` env mapping into the script is at **line 299**.
- **Consuming script**: `plugins/soleur/scripts/reconcile-live-heartbeats.ts` reads
  `process.env.BETTERSTACK_API_TOKEN` (line 247). Its **env contract is the name
  `BETTERSTACK_API_TOKEN`** — so the workflow's `BETTERSTACK_API_TOKEN="$TOKEN"`
  mapping (line 299) MUST stay; only the Doppler *source* name (line 293) changes.
- **Doppler state** (read live at plan time): `soleur/prd_terraform` **HAS**
  `BETTERSTACK_API_TOKEN` (read/write); **does NOT have** `BETTERSTACK_API_TOKEN_READONLY`
  (`Could not find requested secret`). The mint + store must happen before the swap
  goes live.
- **No repo capability claim to bound** — no external premise beyond the above.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| "Swap the one secret name the reconcile step reads" | The reconcile step reads the token from Doppler at workflow line 293 AND passes it to the script as env `BETTERSTACK_API_TOKEN` at line 299. The script's env contract is the *name* `BETTERSTACK_API_TOKEN`. | Change ONLY the `doppler secrets get` name (line 293). KEEP the `BETTERSTACK_API_TOKEN="$TOKEN"` script env mapping (line 299) — the script env name is unchanged. |
| Swap may break a workflow-parity test | `git grep BETTERSTACK_API_TOKEN` over `*.test.ts`/`*.test.sh` returns zero assertions on the Doppler secret *name*. `plugins/soleur/test/heartbeat-live-reconcile.test.ts` tests the reconcile *logic* (via injected token), not the workflow secret name. The 3 inngest parity tests assert function slugs, not the token name. | No test edit required. Add a post-swap runtime verification (see AC) rather than a static grep test. |
| Token is Terraform-managed infra | Better Stack **global API tokens** are account-level credentials with **no Terraform resource type** (the `jianyuan`/`betteruptime` provider models monitors/heartbeats/policies, not API tokens). The value lives in Doppler — the established secret store — exactly like the existing `BETTERSTACK_API_TOKEN`, which has **zero `.tf` references**. | No `.tf` change. Store directly in Doppler `prd_terraform` (see Infrastructure section for the Phase-2.8 exception rationale). |
| Old `BETTERSTACK_API_TOKEN` becomes unused | It is still read by `apply-web-platform-infra.yml` (lines 1968, 2182). Out of scope for this issue. | Leave `BETTERSTACK_API_TOKEN` in Doppler untouched. Do NOT delete/rotate it. |

## User-Brand Impact

**If this lands broken, the user experiences:** the twice-daily heartbeat live-reconcile
job errors on every fire. If the readonly token is absent or has insufficient scope, the
script returns rc=1 ERROR (token-absent, or 401/403 → `kind:"auth"`), emitting a loud
`::error::` — the failure is loud, not silent. The worst case is the reconcile watchdog
going offline, which would re-open the #6537 "9-days-dark" heartbeat-liveness blind spot —
but only if the failure were *silent*, which the existing rc=1 path prevents.

**If this leaks, the user's data is exposed via:** N/A in the sense that this change only
*reduces* exposure. The token is read raw via `doppler secrets get --plain`, masked with
`::add-mask::`, never becomes a `TF_VAR_*`, and gates no `apply`. A Read-scoped token is a
strictly smaller blast-radius than the current read/write token — that is the entire point.

**Brand-survival threshold:** none — internal ops infrastructure with no user-facing
surface; the change reduces credential privilege and all failure modes are loud (rc=1 paging
path already built in #6549 item 2).

- `threshold: none, reason: internal CI credential-scope reduction; no user-facing surface; failure modes are loud (rc=1 ::error::), and exposure strictly decreases.`

## Implementation Phases

### Phase 0 — Preconditions (/work)

0.1. Confirm `BETTERSTACK_API_TOKEN_READONLY` is still absent from `soleur/prd_terraform`
     (`doppler secrets get BETTERSTACK_API_TOKEN_READONLY --project soleur --config prd_terraform --plain` → expect `Could not find`). If it already exists (a prior partial run), skip Phase 1.
0.2. Confirm the workflow line numbers/anchors have not drifted: the reconcile step reads
     `doppler secrets get BETTERSTACK_API_TOKEN` and passes `BETTERSTACK_API_TOKEN="$TOKEN"`
     to `bun plugins/soleur/scripts/reconcile-live-heartbeats.ts`.

### Phase 1 — Mint the Read-scoped token (/work, Playwright-first)

1.1. **Attempt the mint via Playwright MCP** at `https://betterstack.com/settings/global-api-tokens`
     under the authenticated session. Create a token with **Read** scope only. Name it
     descriptively (e.g. `heartbeat-live-reconcile (read-only)`).
     `automation-status: UNVERIFIED — /work MUST run a Playwright attempt before any operator handoff.`
     A vendor dashboard under an authenticated session is presumptively automatable; only a
     real CAPTCHA/OTP/TOTP/passkey/push-MFA gate (with `playwright-attempt:` evidence) justifies
     an operator handoff.
1.2. Capture the minted token value (never echo it to logs; treat as a secret).

### Phase 2 — Store in Doppler (/work)

2.1. Store the value as `BETTERSTACK_API_TOKEN_READONLY` in `soleur/prd_terraform` via the
     Doppler CLI (additive; does not touch `BETTERSTACK_API_TOKEN`). This is the same
     out-of-band secret-store path by which the existing `BETTERSTACK_API_TOKEN` was
     provisioned (see Infrastructure section — NOT a `doppler_secret` Terraform resource).
     The local Doppler auth here is a `dp.ct.` config token — if it is read-only and the
     write fails on auth, that is a genuine write-auth gate: record it and fall back to an
     operator Doppler write for this single secret (do NOT proceed to Phase 4 until the
     secret exists).
2.2. Verify it stored: `doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain` returns a value.

### Phase 3 — Verify the Read token authorizes the reconcile's only call (/work)

3.1. Exercise the actual runtime path — do NOT trust the "Read scope covers GET /heartbeats"
     assumption:
     ```
     BETTERSTACK_API_TOKEN="$(doppler secrets get BETTERSTACK_API_TOKEN_READONLY --project soleur --config prd_terraform --plain)" \
       bun plugins/soleur/scripts/reconcile-live-heartbeats.ts; echo "rc=$?"
     ```
     Expect `rc=0` (OK) or `rc=2` (source-vs-live mismatch — both mean auth SUCCEEDED).
     `rc=1` with a `SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=auth` marker means the Read scope
     does NOT authorize `GET /api/v2/heartbeats` — STOP and re-mint with the scope Better Stack
     actually requires for that endpoint. (Alternatively a bounded `curl -sS -o /dev/null -w '%{http_code}'
     -H "Authorization: Bearer <tok>" --max-time 15 https://uptime.betterstack.com/api/v2/heartbeats`
     → expect `200`.)

### Phase 4 — Swap the workflow (/work)

4.1. In `.github/workflows/scheduled-terraform-drift.yml`, in the `Reconcile live heartbeats`
     step, change the Doppler read (line ~293) from `doppler secrets get BETTERSTACK_API_TOKEN`
     to `doppler secrets get BETTERSTACK_API_TOKEN_READONLY`.
4.2. Update the adjacent comment (line ~297) so the Doppler *source* reads readonly while
     documenting that the script's env contract name is unchanged (e.g. "The script reads the
     BETTERSTACK_API_TOKEN env, sourced from the Read-scoped BETTERSTACK_API_TOKEN_READONLY in
     Doppler, prints SOLEUR_HEARTBEAT_RECONCILE_* markers, and NEVER echoes the token.").
4.3. **Do NOT change** the `BETTERSTACK_API_TOKEN="$TOKEN"` env mapping on line ~299 — the
     script's `process.env.BETTERSTACK_API_TOKEN` contract is unchanged.

### Phase 5 — Verify the workflow post-merge (/ship / post-merge, no SSH)

5.1. `gh workflow run scheduled-terraform-drift.yml` (workflow_dispatch), then watch the
     `heartbeat-live-reconcile` job: the `reconcile` step must report `rc=0` or `rc=2`
     (auth succeeded), NOT `rc=1`. This is the live proof the swap works end-to-end.

## Sequencing (load-bearing)

The workflow is `workflow_dispatch`-only (Inngest-dispatched twice daily; the YAML edit does
**NOT** trigger any apply or auto-fire on merge). But the next twice-daily fire after merge
reads `BETTERSTACK_API_TOKEN_READONLY`. Therefore **the token MUST exist in Doppler before
the YAML swap merges** (Phases 1–3 before Phase 4 merge), or the next reconcile fire returns
rc=1 (token-absent) and pages. Because Phases 1–3 run in-session before the PR merges, there
is no dark window. If Phase 2 hits a genuine Doppler write-auth gate, hold the PR (do not
merge the swap) until the secret is provisioned.

## Infrastructure (IaC)

### Terraform changes
**None** — and this is a reviewed Phase-2.8 exception (`<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`
at the top of this plan). Rationale:

- Better Stack **global API tokens** are account-level credentials with **no Terraform
  resource type** in the `betteruptime`/`jianyuan` provider (which models monitors,
  heartbeats, policies — not API tokens). There is nothing for Terraform to `create`.
- The repo DOES manage some Doppler secrets via `doppler_secret` resources
  (`ci-ssh-key.tf`, `ghcr-*.tf`, `git-data*.tf`), but exclusively for **Terraform-DERIVED
  values** (`tls_private_key`/`random_password` outputs, `betteruptime_heartbeat` URLs)
  written into config **`prd`** (the app-runtime config). There is **no precedent** for a
  `doppler_secret` writing into **`prd_terraform`** — the CI bootstrap config that the
  Terraform run itself authenticates from.
- `BETTERSTACK_API_TOKEN_READONLY` is a **vendor-minted, operator-supplied input** to the
  CI/Terraform system, not an output of it — the same class as the existing
  `BETTERSTACK_API_TOKEN`, which has **zero `.tf` references** (verified). Modeling it as
  `doppler_secret { value = var.betterstack_api_token_readonly }` would require an
  operator-minted no-default variable in `prd_terraform` (tripping
  `hr-tf-variable-no-operator-mint-default`) whose value must be provisioned *before* the
  resource can apply — the identical chicken-and-egg the direct-store path avoids.

The precedent-consistent mechanism is: **mint at the vendor dashboard (Phase 1, Playwright)
→ store directly in Doppler `prd_terraform` (Phase 2)**, mirroring how `BETTERSTACK_API_TOKEN`
itself lives there.

### Apply path
Not applicable — no `terraform apply`. The credential is a Doppler-stored input read raw by
the reconcile step (`doppler secrets get --plain`); it never becomes a `TF_VAR_*` and gates
no plan/apply. The YAML edit does not fire any apply workflow on merge.

### Distinctness / drift safeguards
`dev`/`prd` distinctness: the reconcile is a prod-only observability job; the secret lives
only in `prd_terraform`. No dev counterpart. No Terraform state carries the token value (it
is never a TF var), so no `terraform.tfstate` exposure.

### Vendor-tier reality check
The reconcile only calls `GET /api/v2/heartbeats` (a read). Better Stack's free tier permits
reads of existing heartbeats; no paid-tier gate applies to minting a Read-scoped global API
token or to the reconcile's read call. (Unrelated to the `betterstack_paid_tier` gate on
`betteruptime_policy`/paid alerting resources.)

## Observability

```yaml
liveness_signal:
  what: heartbeat-live-reconcile job runs on every twice-daily Inngest dispatch of scheduled-terraform-drift.yml; drift-check job emits a Sentry check-in (monitor-slug scheduled-terraform-drift).
  cadence: 06:00 / 18:00 UTC (Inngest cron-terraform-drift.ts dispatch)
  alert_target: Sentry cron monitor (drift-check job); reconcile mismatch -> GitHub issue
  configured_in: .github/workflows/scheduled-terraform-drift.yml
error_reporting:
  destination: GitHub Actions annotations (::error:: / ::warning::) + heartbeat-reconcile-mismatch GitHub issue (rc=2)
  fail_loud: true  # rc outside {0,1,2} normalized to rc=1 ::error:: (never greens the monitor); token-absent/auth -> rc=1 ERROR
failure_modes:
  - mode: readonly token absent from Doppler after merge
    detection: reconcile script prints SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=token-absent -> rc=1
    alert_route: ::error:: annotation on the reconcile step
  - mode: Read scope does not authorize GET /api/v2/heartbeats (401/403)
    detection: script FetchResult kind=auth -> SOLEUR_HEARTBEAT_RECONCILE_ERROR -> rc=1 (caught pre-merge by Phase 3)
    alert_route: ::error:: annotation on the reconcile step
  - mode: source-vs-live heartbeat mismatch (unchanged behavior)
    detection: rc=2 -> SOLEUR_HEARTBEAT_RECONCILE_MISMATCH markers
    alert_route: heartbeat-reconcile-mismatch GitHub issue (create/update/escalate)
logs:
  where: GitHub Actions run logs (reconcile step; RUNNER_TEMP/reconcile-output.txt, token never echoed)
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: gh workflow run scheduled-terraform-drift.yml && gh run watch --job heartbeat-live-reconcile
  expected_output: "reconcile step reports rc=0 or rc=2 (auth succeeded); not rc=1"
```

## Architecture Decision (ADR/C4)

**No architectural decision.** This is a credential-scope reduction (implementation detail of
the already-shipped #6549-item-2 reconcile), not a new/changed architectural boundary,
substrate, or trust-boundary. Checked the C4 model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4}` contain `Better Stack`
+ `heartbeat` elements): Better Stack is already modeled as an external system and the
reconcile→Better Stack read relationship already exists. Swapping *which* Doppler credential
authorizes the same existing read call adds no external actor, no external system, no data
store, and no access-relationship change. **No C4 impact; no ADR required.**

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references
`.github/workflows/scheduled-terraform-drift.yml` or the reconcile script.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `BETTERSTACK_API_TOKEN_READONLY` exists in Doppler `soleur/prd_terraform`
      (`doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain` returns a value; stored len=24).
- [x] The Read-scoped token authorizes the reconcile: running
      `reconcile-live-heartbeats.ts` with it returns rc in {0, 2} (NOT rc=1 auth) — got **rc=2**
      (source-vs-live mismatch, pre-existing; auth SUCCEEDED, `auth-error-lines=0`; direct
      `GET /api/v2/heartbeats` → 200).
- [x] `.github/workflows/scheduled-terraform-drift.yml` reconcile step reads
      `doppler secrets get BETTERSTACK_API_TOKEN_READONLY` (grep:
      `grep -c 'doppler secrets get BETTERSTACK_API_TOKEN_READONLY' .github/workflows/scheduled-terraform-drift.yml` == 1).
- [x] The workflow still passes `BETTERSTACK_API_TOKEN="$TOKEN"` into the script (env contract
      unchanged): `grep -c 'BETTERSTACK_API_TOKEN="\$TOKEN"' .github/workflows/scheduled-terraform-drift.yml` == 1.
- [x] No read/write `doppler secrets get BETTERSTACK_API_TOKEN ` (trailing space) read remains
      in the reconcile step:
      `awk '/name: Reconcile live heartbeats/,/name: Ensure heartbeat-reconcile-mismatch/' .github/workflows/scheduled-terraform-drift.yml | grep -c 'get BETTERSTACK_API_TOKEN '` == 0.
- [x] `BETTERSTACK_API_TOKEN` (read/write) is left untouched in Doppler and still read by
      `apply-web-platform-infra.yml` (not deleted/rotated; len=24 unchanged).
- [x] Existing suite green: `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts`
      (26 pass, 0 fail — swap does not touch reconcile logic). Also the 3 workflow-referencing
      inngest tests green (37 pass).
- [x] `actionlint .github/workflows/scheduled-terraform-drift.yml` — the reconcile step is clean;
      the only SC2086 `info` hits (lines 93, 140) are pre-existing in unrelated steps, untouched
      by this swap.

### Post-merge (operator/pipeline)
- [ ] `gh workflow run scheduled-terraform-drift.yml`; the `heartbeat-live-reconcile` job's
      `reconcile` step reports rc in {0, 2} — live proof the swap works. Automatable via
      `gh` CLI (no SSH).
- [ ] `Ref #6635` in the PR body (not `Closes` — this is a hardening whose live proof is the
      post-merge dispatch; close #6635 after the post-merge run is green).

## Domain Review

**Domains relevant:** none

No cross-domain implications — an internal CI credential-scope reduction (engineering/infra).
Product/UX Gate: NONE (no UI-surface file in Files to Edit). No legal/finance/marketing/sales
/ops/support surface.

## Files to Edit
- `.github/workflows/scheduled-terraform-drift.yml` — one Doppler read-name swap (line ~293) +
  adjacent comment update (line ~297). Env mapping (line ~299) unchanged.

## Files to Create
- None.

## Out of scope / Non-Goals
- Swapping `apply-web-platform-infra.yml` (lines 1968, 2182) Better Stack reads to a read-only
  token — those live in apply-context steps and are a separate surface. (Potential fast-follow;
  not required by #6635 and not deferred-with-tracking here since #6635 is explicitly scoped to
  the reconcile step only.)
- Deleting or rotating the existing read/write `BETTERSTACK_API_TOKEN`.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, is `TBD`/placeholder, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled above (threshold: none, with reason).
- Do NOT change the `BETTERSTACK_API_TOKEN="$TOKEN"` env mapping (workflow line ~299) — the
  script's `process.env.BETTERSTACK_API_TOKEN` contract is the env *name*, independent of which
  Doppler secret sources the value. Changing it would break the script's read.
- Verify the Read scope actually authorizes `GET /api/v2/heartbeats` by *exercising* it
  (Phase 3), not by trusting the "Read covers GET" assumption — a wrong-scope token returns
  401/403 → rc=1 and would page on the first fire.
- Sequence the mint + Doppler store BEFORE merging the YAML swap; the next twice-daily fire
  reads the new secret name.
