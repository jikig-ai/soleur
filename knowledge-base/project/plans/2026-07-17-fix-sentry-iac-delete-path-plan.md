---
title: "fix(infra): Sentry IaC delete path is a silent no-op — full-root apply + PR-time plan gate"
date: 2026-07-17
issue: 6589
pr: 6582
branch: feat-sentry-monitor-spend
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-sentry-monitor-spend/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-17-sentry-monitor-spend-brainstorm.md
learning: knowledge-base/project/learnings/2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md
plan_review: 7-agent panel (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto-devex, fable advisor) — v1 → v2
---

# Sentry IaC delete path — plan (v2, post-review)

## Overview

**The win is not the $42/mo. It is the per-monitor tax and a delete path that works.**

| flow | before | after |
|---|---|---|
| add a monitor | resource block **+** a `-target=` line **+** a parity-test entry **+** a registry count | resource block |
| retire a monitor | **impossible** (silently no-ops) | delete the block **+** `[ack-destroy]` |

`.github/workflows/apply-sentry-infra.yml` plans Terraform against a hand-maintained
`-target=` allowlist, so removing a resource block never destroys the live resource.
PR #6034 added a block **and** its target line; PR #6074 removed **both together** — the
intuitive edit — and orphaned a monitor that is live today, billing $0.78/mo, carrying a
12-day unresolved incident. The workflow's own comment documents the identical leak from
#4929. Monitor count went **8 → 49 in two months, never once decreasing.**

### The measured artifact (Open Question 1 — CLOSED at plan time)

A read-only full-root `terraform plan` was run against live state (2026-07-17):

```
delete: 2   sentry_issue_alert.kb_tenant_mint_silent_fallback
            sentry_cron_monitor.scheduled_ghcr_token_minter
no-op:  75
create:  0
destroy-guard-filter-sentry.jq → {resource_deletes: 2, nested_deletes: 0}
state: 50 cron / 23 issue_alert / 4 uptime | .tf: 49/22/4 | -target=: 49/18/4
```

Proves: **no duplicate-create risk** (all 22 declared alerts, including the 4 untargeted
import-only ones, are in state and plan as no-op); exactly **2** latent destroys, both known
orphans; the destroy filter **already counts correctly on a full-root plan**.

### v2's central correction: full-root ALONE does not fix the bug

`apply-sentry-infra.yml:42-45` triggers on **`push: main` only — there is no PR-time plan.**
So full-root by itself yields: *remove a block → merge → the apply job goes red **after**
merge → the monitor stays live and billing.* **End state byte-identical to #6074**, only now
the failure is loud in a place nobody watches, on a closed PR. And `[ack-destroy]` must sit
in the **merge commit**, authored in GitHub's squash UI — the author cannot pre-stage it from
the branch, and nothing tells them before they click.

**Therefore Phase 3 adds a `pull_request` plan job.** That is the change that actually
removes the footgun; the `-target=` deletion is necessary but not sufficient.

## Research Reconciliation — Spec vs. Codebase

| Spec/v1 claim | Reality (verified) | v2 response |
|---|---|---|
| TR1: 1 file (`sentry-monitor-iac-parity.test.ts`) asserts `-target=` membership | **11 consumers.** Six op-contract tests assert it *by name* — e.g. `"is wired into the apply-sentry-infra.yml -target list (else it never applies)"` — each asserting the **inverse** of FR3's thesis. All match vitest's `include` glob, so **AC9 could not pass** as v1 stood. The #4591 failure class. | **Files to Edit widened 3 → 11.** |
| v1 Phase 4.1: source the scope guard's types from `*.tf` — "strengthens the invariant" | **False in exactly the direction of the bug.** Under full-root the plan universe is **state ∪ config**. A type in state with no remaining block is invisible to a `.tf`-only extractor — *precisely the class this PR destroys*. Had `kb_tenant_mint_silent_fallback` been the last `sentry_issue_alert`, the guard would omit that type, pass **vacuously**, and let an array-of-blocks destroy through unchecked. | Extractor source = `types(*.tf) ∪ types(terraform state list)`. Preserve empty→FAIL. |
| v1: amend ADR-031's `## Decision` to replace `-target=` scoping | ADR-031 records changes as **dated appended amendments**. The **2026-07-13 #6374 amendment** (`:276-289`) — four days old, born from a **P1 where an alarm ran ~14h unseen** — elevates `-target=` membership to a named invariant: *"Guarding only clause (a) would pass while the monitor never materialised; **both clauses are load-bearing**."* FR3 retires clause (b). v1 never mentioned it. | **Append** `Amendment (2026-07-17, #6589)`; do NOT rewrite `## Decision`. Must explain *why* retiring clause (b) is safe. |
| v1 Phase 4.6: register-citation guard | **Keys off an accidental substring.** `article-30-register.md:303` cites `scheduled-github-app-drift-guard.**yml**` — the *workflow filename*. A slug-in-file grep matches the filename, not a citation of the monitor. v1's own reconciliation table said this, then specified a guard contradicting it. N=1; `[ack-destroy]` + AC7 already cover it. | **CUT** (both panels fired). Phase 4.6, AC8, and the new guard file deleted. |
| v1 AC5: "exactly 2 deletes / 0 creates / 75 no-ops" | **Count, not identity** — a *different* pair satisfies `count==2`. v1's "or 4 deletes if 5b proceeds" left 2 addresses unnamed: a plan destroying `soleur_apex` + `scheduled_oauth_probe` satisfied AC5 verbatim. | Assert the delete **SET**. |
| v1 AC1: `onDemandMaxSpend==7500 && onDemandSpendUsed==4222` proves the cap is a ceiling | **Proxy.** `onDemandSpendUsed` is the *usage* meter — unchanged by a cap raise **by construction**, so it cannot falsify "the cap charged us." | Drop the proxy clause. |
| v1 Phase 6: Class D → `alert_route: apply-sentry-infra.yml step failure` | **False.** Every orphan branch in `sentry-monitors-audit.sh:433-461` only `printf`s. All `exit 1`s are token gates (`:89-164`) / API failures (`:230,:270`). Class D would inherit print-only — a detector wired to nothing. | Phase 6 adds an explicit non-zero exit. |
| v1 AC13 + soak enrollment | **Arithmetic inverted and unsatisfiable.** 5b blocked → **$40.44**; 5b proceeds → **$38.88**. v1's default `$38.88` *assumed the phase it declared BLOCKED*; its `$37.32` alternative is unreachable. The threshold `<= 3900` would **FAIL daily forever**. Also `secrets=SENTRY_IAC_AUTH_TOKEN` is wrong — the sweeper exports `SENTRY_AUTH_TOKEN`. | **CUT** (both panels): Sentry's own budget notification is the detector — it is what fired this investigation. |
| v1 Phase 5b (destroy 2 never-checked-in monitors) | Not Class D at all — `cron-monitors.tf:557,922` **declare** both, so `missingMonitor` covers them. "Dead or unwired producers?" is a different question. | **CUT to a follow-up.** Keeps 5a a clean 2-address destroy. |
| v1: `paths:` filter unchanged | `paths:` (`:44-52`) lists 3 of 5 `.tf` files. Phase 4.2 deletes `missingTarget` — the only gate for declared-but-never-applied. Under full-root that gate has no replacement. | Widen `paths:` → `apps/web-platform/infra/sentry/**` (Phase 3.3). |

## Premise Validation (Phase 0.6)

Verified live: **#6589**, **#6590**/**#6591**, **#4296**, **#3958** (CLOSED — PAYG-exhaustion
precedent), **#4929**, **#6034**/`774c9007e`, **#6074**/`0323ac43c`, **#4682**, **#6374** (the
ADR-031 amendment FR3 retires a clause of), **#4585**, **#4364**. **ADR-031** read in full
including all dated amendments. No stale premises.

**Phase 1.4 (network-outage gate): does NOT fire.** `apps/web-platform/infra/sentry/` contains
zero `provisioner`/`connection { type = "ssh" }` blocks — the Sentry provider is pure HTTP API.

## Open Code-Review Overlap

**None.** All 61 open `code-review` issues queried; each of the 11 planned paths matched against
every issue body via standalone `jq --arg`. Zero hits.

## User-Brand Impact

*(Carried forward verbatim from the brainstorm per Phase 2.6.)*

**Brand-survival threshold:** `single-user incident`.

**Artifact:** the Sentry cron + uptime monitor set for Soleur production.

**Vector:** silent, total loss of missed-run detection. At renewal, if PAYG cannot cover all
active monitors, **every monitor deactivates at once** and check-ins are silently dropped —
workflows keep running while alerting dies, with no error surfaced.

**Monitors whose silence is a single-user incident:** `soleur_acme_probe`, `soleur_apex`,
`scheduled_inngest_health` (its header records a P1 that ran ~14h unseen, #5542, *because this
monitor did not exist*), `scheduled_oauth_probe`, `scheduled_membership_health`,
`cron_email_ingress_probe`, `cron_egress_resolve`, `scheduled_github_app_drift_guard`.

**New in this plan:** FR3 converts "destroy is impossible" into "destroy works". The PR-time
plan gate (Phase 3.4) is what keeps that from becoming a new incident class.

## Implementation Phases

### Phase 1 — raise the PAYG cap (ships alone, first; no code)

Only lever that averts all-or-nothing renewal deactivation; draws **$0**. Next cliff
**2026-08-16** (`onDemandPeriodEnd`); headroom **9 monitors**.

Note for Phase 2.8: this step has **no Terraform resource** — the `jianyuan/sentry` provider
exposes no on-demand-budget resource, so there is no `.tf` to route it through. It is a vendor
billing setting, gated behind the automation ladder below per
`hr-exhaust-all-automated-options-before` + `hr-never-label-any-step-as-manual-without`.

1.1 **Attempt automation in order — do NOT defer to a human before both fail.** Measured:
   `customers/` GET = **200**, `ondemand-budgets/` GET = **403**, so expect the write to 403.
   (a) API write with `SENTRY_IAC_AUTH_TOKEN`. **This is a prod billing write — per
   `hr-menu-option-ack-not-prod-write-auth`, the brainstorm menu selection is NOT write
   authorization. Get explicit confirmation first.**
   (b) On 403 → drive the Sentry billing settings page with Playwright; record
   `playwright-attempt: navigated <URL>; reached <named human gate>`.
   (c) Only a *reached* human gate (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card) justifies
   deferring this to a person. `automation-status: UNVERIFIED`.
1.2 **If (c) — the deferral path:** Phase 1 is **decoupled from this PR**. AC1 is post-merge and
   the cap raise becomes an `action-required` issue per
   `wg-block-pr-ready-on-undeferred-operator-steps`. **The PR must not become unshippable because
   a vendor gated a billing form.**

### Phase 2 — correct the expense ledger (no code)

2.1 `knowledge-base/operations/expenses.md:37` — `Amount` `40.00` → **`71.22`**.
2.2 Replace *"~$11 expected PAYG (estimate: 14 backfilled × ~$0.78; verify actual draw on the
   2026-06-17 invoice)"* with `$29 base + $42.22 PAYG (49 × $0.78 + 4 × $1.00, monitor-count-driven,
   fixed) = $71.22`. Closes the row's own unresolved TODO. Required by
   `wg-record-recurring-vendor-expense-before-ready` before PR-ready.

### Phase 3 + Phase 4 — the contract change and its 11 consumers (**ONE commit**)

Producer and consumers of a contract line must land together. All 11 consumers fail **loud**
(not vacuously) on an empty target set, but the destructive apply fires on the merge commit
regardless of intra-PR structure — so they revert together or not at all.

**Phase 3 — the contract**
3.1 Delete the 71 `-target=` lines (`apply-sentry-infra.yml:196-261`). Keep `[ack-destroy]`
   (`:297-306`) and `[skip-sentry-apply]` (`:84-91`) **byte-for-byte** (TR4).
3.2 Delete the stale `kb_tenant_mint_silent_fallback` comment (`:186-192`).
3.3 Widen `paths:` (`:44-52`) → `apps/web-platform/infra/sentry/**`. Under full-root,
   `missingTarget` (deleted in 4.2) was the only gate for declared-but-never-applied; the path
   filter must cover every `.tf` or a `versions.tf`/`variables.tf` change silently skips the apply.
3.4 **Add a `pull_request` job** on the same paths running the read-only full-root plan. Fail with:
   `this PR destroys N Sentry resource(s): <addresses>. The merge commit must contain a line
   [ack-destroy].` **This is the change that removes the footgun** — it converts a post-merge red
   into a pre-merge instruction. Without it the end state is #6074 with extra steps.
3.5 **Symmetric create counter.** `destroy-guard-filter-sentry.jq` already walks `resource_changes`
   and emits `resource_deletes`; add `resource_creates` (~3 lines). Gate: fail when a created
   address has **no matching added `resource` block** in the triggering diff
   (`git diff -- apps/web-platform/infra/sentry/*.tf`). Adding a monitor passes silently; a create
   arising from state/config divergence (a Sentry-side UI delete made outside Terraform, or a
   failed import) fails closed. Reserve `[ack-create]` as the override for the unmatched case only
   — **a blanket `[ack-create]` would fire on the normal add-a-monitor flow and train
   ack-blindness, eroding `[ack-destroy]` with it.**
   *Rationale for adding rather than documenting:* this incident's etiology is literally "a known
   hole documented in prose in the workflow's own comment that nobody re-checked". Accepting a
   documented create-hole repeats that pattern one line lower.

**Phase 4 — the 11 consumers**
4.1 `tests/scripts/test-destroy-guard-sentry-scope-guard.sh:35-48` — extractor source becomes
   **`types(*.tf declared) ∪ types(terraform state list)`**. Preserve empty→FAIL. **Parameterize
   the input** (`SENTRY_TF_DIR="${SENTRY_TF_DIR:-$REPO_ROOT/apps/web-platform/infra/sentry}"`) —
   today `WORKFLOW` is hardcoded (`:32-33`) with no injection point, so AC6 is otherwise untestable.
4.2 `sentry-monitor-iac-parity.test.ts:134-206` — delete `applyTargetResourceIds()` + `missingTarget`.
   **Keep `missingMonitor`.**
4.3 `function-registry-count.test.ts:27,35,44,55` — count from `.tf`, not the `-target=` regex.
4.4 **Six op-contract tests** — each asserts `-target=` membership, i.e. the inverse of FR3.
   Convert each to *"declared in `issue-alerts.tf`"* (the invariant they actually care about is
   "this alert materialises", which full-root makes automatic):
   `sentry-inbox-action-required-alert-op-contract.test.ts:45,49` ·
   `sentry-kb-sync-silent-failure-alert-op-contract.test.ts:107-113` ·
   `sentry-kb-sync-protected-fallback-alert-op-contract.test.ts:90-96` ·
   `sentry-zot-mirror-fallback-alert-op-contract.test.ts:321-325` ·
   `sentry-web-terminal-boot-fatal-op-contract.test.ts:81-85` ·
   `sentry-outbound-email-alert-op-contract.test.ts:59-63`
4.5 `tests/scripts/test-destroy-guard-counter-sentry.sh:17-34` — **delete** the stale 20-line
   `-target=` re-capture recipe. Do not refresh a comment describing a mechanism that no longer exists.
4.6 `destroy-guard-filter-sentry.jq:8,31-36` — update CURRENT SCOPE. **Note the widened lifecycle
   assumption:** full-root takes `sentry_issue_alert` coverage from 2 → 22, so the filter's
   "`ignore_changes` means they never appear in a plan diff" comment now carries 20 more resources.
   Live evidence covers it today (75 no-ops); make it an explicit AC5 sub-assertion, not a comment.
4.7 Stale prose describing the allowlist as live mechanism: `.github/workflows/infra-validation.yml:37-39`
   and `apps/web-platform/infra/sentry/uptime-monitors.tf:21-27`.

### Phase 5 — destroy the dead resources (2 paths; 5b cut to follow-up)

5a. **Consequence of Phase 3's apply** (in state, no block):
   `sentry_cron_monitor.scheduled_ghcr_token_minter` ($0.78/mo, 12-day incident) +
   `sentry_issue_alert.kb_tenant_mint_silent_fallback` ($0). Needs `[ack-destroy]` on the merge
   commit. Also FR4's remediation.
5b. **CUT → follow-up.** `scheduled_ux_audit` / `scheduled_architecture_diagram_sync` (zero
   `environments[]` ever, but **declared** — so never Class D).
5c. **API delete** — uptime **id `1422253`** ($1.00/mo). State has 4 uptime, `.tf` has 4, **live has
   5**: never Terraform-managed, so Terraform cannot destroy it. **Executor:** a one-line
   `curl -X DELETE` in the post-merge step. **Probe the token's `monitor:admin` DELETE scope first**
   — the same token 403'd on `ondemand-budgets/`, so scope is not assumable. If 403 → Playwright →
   escalate (same ladder as 1.1).

### Phase 6 — Class D orphan detection

6.1 `apps/web-platform/scripts/sentry-monitors-audit.sh` — add **Class D** (live monitor with no
   `.tf` block) after `monitor_slugs` (~`:290`); report alongside A/B/C (`:433-461`). Already
   invoked at `apply-sentry-infra.yml:155-171`.
6.2 **Fail-closed (load-bearing).** Every existing orphan branch only `printf`s; all `exit 1`s are
   token gates (`:89-164`) / API failures (`:230,:270`). Class D **must exit non-zero**, or it is a
   detector wired to nothing and AC10 measures a signal into the void.
6.3 **TR3:** read liveness from `environments[].lastCheckIn`, **NOT** the list endpoint's
   `lastCheckIn` — that field does not exist there and yields a false "never checked in" for every
   monitor. (Hit and self-corrected during this investigation.)
6.4 Preserve the 4-gate token check (`:93-166`) + DSN residency guard (`:168-220`).
6.5 Emit `SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=<slug> created=<date> last_checkin=<date> cost_usd=<n>`
   to stdout (TR5).

## Acceptance Criteria

### Pre-merge (PR)

- **AC2** — `expenses.md:37` `Amount` reads `71.22`; Notes carry `49 × $0.78 + 4 × $1.00 = $42.22`
  and no longer contain `verify actual draw on the 2026-06-17 invoice`.
- **AC3** — `grep -cE '^\s*-target=' .github/workflows/apply-sentry-infra.yml` → **0**.
- **AC4** — `bash tests/scripts/test-destroy-guard-regex-parity.sh` passes (the `[ack-destroy]`
  regex is unweakened). *(v1's `grep -c 'ack-destroy'` count cut as paraphrase — the parity test
  IS the check.)*
- **AC5** — a read-only full-root plan's **delete SET** equals exactly
  `{sentry_cron_monitor.scheduled_ghcr_token_minter, sentry_issue_alert.kb_tenant_mint_silent_fallback}`
  — identity, not cardinality:
  `jq -r '[.resource_changes[]|select(.change.actions==["delete"])|.address]|sort|.[]'`.
  **AND** `resource_creates == 0`. **AND** all 22 `sentry_issue_alert` addresses are `no-op` (the
  widened `ignore_changes` assumption from 4.6).
- **AC6** — `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` passes with the
  `.tf ∪ state` extractor, and **FAILs** when `SENTRY_TF_DIR` points at an empty dir (the
  empty→FAIL posture, made testable by 4.1's parameterization — a guard that passes on empty is
  broken).
- **AC7** — `scheduled_github_app_drift_guard` remains in `cron-monitors.tf` and active in Sentry
  (CLO constraint; `article-30-register.md:303` claims drift "is detected hourly").
- **AC11** — **the regression test for #6074**, rewritten to what CI can check without live creds
  or R2 state: no `-target=` appears in any `terraform plan`/`apply` invocation in
  `apply-sentry-infra.yml`; the scope guard sources types from `.tf ∪ state`; **and** a
  synthesized-fixture plan JSON with a removed block, fed through `destroy-guard-filter-sentry.jq`,
  returns `resource_deletes: 1`. *(v1's version needed live Sentry + R2 — unimplementable in PR CI.)*
- **AC14** — the Phase 3.4 `pull_request` job fails on a synthesized destroying plan with a message
  naming the destroyed addresses **and** the literal `[ack-destroy]`, and passes otherwise. *(The AC
  for the fix that actually removes the footgun — AC4 only proves the gate exists, not that it is
  discoverable, which was the whole bug class.)*

*Runner note:* `tests/scripts/*.sh` are **not** vitest-collected — AC4/AC6/AC11's bash guards run via
`bash <path>`; vitest suites run via `cd apps/web-platform && npm run test:ci`. Typecheck:
`cd apps/web-platform && npm run typecheck`. **Not** `npm run -w …` (root `package.json` has no
`workspaces` field).

*Cut as ceremony (DHH + code-simplicity):* AC9 (`test:ci`/typecheck pass — CI's job, not an AC),
AC12 (asserts vendor auto-resolve behaviour), AC8 (dies with Phase 4.6), AC13 (dies with the soak
cut), AC1's `onDemandSpendUsed` clause (a proxy that cannot falsify its claim).

### Post-merge

- **AC1** — `GET /api/0/customers/jikigai-eu/` → `onDemandMaxSpend == 7500`. *(Moved from pre-merge:
  Phase 1 ships independently and must not block the PR.)*
- **AC10** — `sentry-monitors-audit.sh` reports **0** Class D orphans after Phase 5. *(Moved from
  pre-merge: 5a applies on the merge commit and 5c is a post-merge API call. Independent of the 5b
  cut — both 5b monitors are **declared**, hence never Class D.)*

## Domain Review

**Domains relevant:** Engineering, Finance, Operations, Product, Legal *(carried forward from the
brainstorm's `## Domain Assessments`; CPO sign-off inherited from the Phase 0.1 triad — the approach
is unchanged from what CPO+CLO+CTO framed).*

**CTO** — no double-counting; no alert rule binds `monitor_ids`; #4682 refuted the meta-watchdog
alternative. **CFO** — ledger understates Sentry by $375/yr; largest product-COGS line (~29%);
monitor PAYG alone is 2.7× the host it monitors. **COO** — Better Stack costs 2.5× Sentry per
heartbeat; do not migrate; the cliff is at renewal, all-or-nothing. **CPO** — "raise budget or
prune?" is a false trade; the lifecycle gap is structural. **CLO** — no legal exposure; one binding
constraint (AC7); the register cites the *workflow*, and the monitor detects its silence.

### Product/UX Gate
**Tier:** none — no UI surface (independent mechanical scan of Files-to-Edit: no
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, no UI-surface terms).
`ux-design-lead` / `cmo` not activated (no UI or market surface). **Pencil available:** N/A.

## GDPR / Compliance Gate (Phase 2.7)

Fired on expansion trigger **(b)** (single-user-incident threshold). Canonical regex matched **zero**
Files-to-Edit → all five mandatory v1 checks had no surface. **No Critical, no Important.** FR6's
destroy targets carry zero legal-corpus citations (the `ux-audit` hit is `ux-audit-bot@jikigai.com`,
a bot's email). Its one Suggestion (a register-citation guard) was **rejected at plan-review** — it
would key off an accidental substring (the register cites the workflow *filename*), and
`[ack-destroy]` + AC7 already cover the single matching resource.

## Infrastructure (IaC) — Phase 2.8

### Terraform changes
**None to `infra/sentry/*.tf`** — no `import` blocks needed (state is complete; verified). Workflow
only. Provider `jianyuan/sentry`; auth via **raw `SENTRY_AUTH_TOKEN` env** — the provider reads it
directly, and `--name-transformer tf-var` mangles it to `TF_VAR_sentry_auth_token`, after which the
provider fails with `failed to perform health check`. (Same class as the raw-AWS-creds caveat; this
bit me at plan time and is recorded so /work does not rediscover it.)

### Apply path
`[ack-destroy]` + `[skip-sentry-apply]` unchanged (TR4). **New:** a `pull_request` plan job (3.4) so
destroys are visible *before* merge. Sequence: PR-time plan → account for every create AND destroy →
merge with `[ack-destroy]` → push-to-main apply. Blast radius: 2 resource deletions, both dead.

### Distinctness / drift safeguards
Class D (Phase 6) closes live→IaC. `resource_creates` (3.5) closes the create direction.
**NOT mitigated — accepted:** `main.tf:16` sets `use_lockfile = false` (R2 has no S3 conditional
writes), so full-root widens the *unlocked* write window from ≤71 addresses to the whole state key.
"Do not run a manual apply while CI is applying" is an **instruction, not a control**. Acceptable
given the single-writer path-filtered CI path; do not record it as mitigated.

### Vendor-tier reality check
`monitorSeats.reserved = 1`, `uptime.reserved = 1` — live-verified. **No purchasable reserved volume
exists** ([getsentry/sentry#73359](https://github.com/getsentry/sentry/issues/73359), closed
unshipped). Issue alerts are not monitor-billed. Phase 1's cap raise has **no Terraform resource** in
the `jianyuan/sentry` provider — it is a vendor billing setting, which is why it carries the
automation ladder in Phase 1.1 rather than a `.tf` change. *Prices from a live API read on
2026-07-17; re-verify at the provider's pricing page before future budget decisions.*

## Observability (Phase 2.9)

```yaml
liveness_signal:
  what: sentry-monitors-audit.sh Class D orphan count (fail-closed per Phase 6.2)
  cadence: every apply-sentry-infra.yml apply-job run (push to main touching infra/sentry/**)
  # The load-bearing signal is the non-zero EXIT -> GitHub Actions job-failure
  # notification. The SOLEUR_SENTRY_CLASS_D_ORPHAN marker is a human-readable
  # detail line in that failed job's LOG, NOT a Better Stack event: SOLEUR_* is a
  # host-journald convention (vector.toml scopes every source to the Hetzner
  # host's SYSLOG_IDENTIFIER), and this script runs on a GitHub Actions runner
  # whose stdout no vector source ships. Corrected at review — the earlier
  # "SOLEUR_ marker -> Better Stack" claim was a signal-into-the-void.
  alert_target: apply-job failure -> GitHub Actions notification (the marker is a detail line in the job log)
  configured_in: apply-sentry-infra.yml step "Sentry audit-gate (4-gate destination-controllability)"
error_reporting:
  destination: GitHub Actions step failure (exit != 0); stdout SOLEUR_ marker in the job log
  fail_loud: true
failure_modes:
  - mode: live monitor exists with no .tf resource AND not in state (Class D orphan)
    detection: sentry-monitors-audit.sh Class D check, WITH the state half injected
      (SENTRY_STATE_REQUIRED=1) — fires only in the apply job; pre-merge callers pass
      no state half, so Class D is advisory (warn) there
    alert_route: apply-sentry-infra.yml apply-job failure (non-zero exit); the
      SOLEUR_SENTRY_CLASS_D_ORPHAN marker is a detail line in that failed job's log
  - mode: plan proposes a CREATE with no matching added resource block
    detection: destroy-guard-filter-sentry.jq resource_creates + diff-match gate (Phase 3.5)
    alert_route: apply job failure; no blanket override (diff-matched)
  - mode: a PR removes a resource block and the author does not know to ack
    detection: Phase 3.4 pull_request plan job (plan_pr), verdict via sentry-destroy-required
    alert_route: PR check failure; the plan_pr step log names the destroyed addresses
      and the literal [ack-destroy]. NOTE the aggregator's own message is generic
      ("gate FAILED closed"); the address list lives in the plan_pr step log.
  - mode: PAYG cap re-approached (monitor count creeps back)
    detection: Sentry's own budget notification (the alert that fired this investigation)
    alert_route: vendor email to the founder
logs:
  where: GitHub Actions run logs (the only sink for this script's stdout — see alert_target)
  retention: GH Actions 90d
discoverability_test:
  command: >-
    curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN"
    https://sentry.io/api/0/customers/jikigai-eu/ | jq '.onDemandMaxSpend'
  expected_output: '7500'
```

No `ssh` in any command. Phase 2.9.1 (soak enrollment) **does not fire** — the soak-gated AC was cut.
Phase 2.9.2 (blind surface) does not apply.

## Architecture Decision (ADR/C4) — Phase 2.10

### ADR — **append** to `ADR-031-sentry-as-iac.md`; do NOT rewrite `## Decision`

`-target=` is **not** ADR-031's core mechanism. Its `## Decision` (`:96-119`) is *"adopt the
jianyuan provider; import 4, create 8, defer 2"*; scoping lives in `### Auto-apply on push-to-main`
(`:204-222`) as an apply-path detail. Not superseded → amend. But the file records every change as a
**dated appended amendment** (`:112`, `:224`, `:238`, `:252`, `:276`), so append rather than edit in
place — editing erases the record of why the retired clause existed.

**Append `Amendment (2026-07-17, #6589)`** naming and retiring **clause (b)** of the 2026-07-13
#6374 amendment (`:276-289`): *"every `.github/workflows/*.yml` `monitor-slug:` has BOTH (a) a
matching `sentry_cron_monitor.name` in `cron-monitors.tf` AND (b) that resource in the
`apply-sentry-infra.yml` `-target=` allowlist… both clauses are load-bearing."*

**Why retiring clause (b) is safe — state this explicitly, or a future reader will conclude #6589
broke a P1-derived invariant:** clause (b) existed because a `-target=`-scoped apply made
*declared ≠ applied*, so a monitor could be declared-but-never-applied (green CI, dark alarm — the
#6374 P1, an alarm unseen ~14h). Under full-root, **declared ≡ applied by construction**. The
invariant clause (b) protected is *preserved*; only its enforcement mechanism becomes unnecessary.
The amendment must also record that `paths:` was widened to `infra/sentry/**` (Phase 3.3), which is
what keeps "declared ⇒ applied" true for every `.tf`.

Record the rejected alternatives: **(1)** hand-maintained allowlist (status quo — deletion is a
silent no-op; fired twice: #4929, #6074); **(2)** derive `-target=` from `terraform state list` ∪
declared addresses — rejected, **identity-equal to no `-target` at all** (Terraform's plan universe
*is* state ∪ config); **(3)** CI guard on block-removal-without-ack — rejected as primary (lints a
footgun instead of removing it), though Phase 3.4's PR-time plan job delivers its intent without
hand-maintained state.

`ADR-118` is the next free ordinal if `/ship` prefers a standalone record; treat any ordinal as
**provisional** and re-verify against `origin/main` before merge.

### C4 views
**No C4 impact** to elements or edges. Enumeration supporting that (all three of `model.c4`,
`views.c4`, `spec.c4` read, not grepped):
- **External human actors:** `founder` — paged via `sentry -> founder`. Unchanged.
- **External systems:** `sentry` (`model.c4:269`, `#external`) and `github -> sentry` ("Terraform
  provider apply") — both already modeled. No new vendor.
- **Containers / data stores:** none touched; the R2 state bucket is unchanged.
- **Access relationships:** unchanged — GitHub still applies Terraform to Sentry; Sentry still pages
  the founder.
- **Prose falsification:** `grep -rn 'target=\|allowlist\|allow-list' *.c4` → **zero**. But
  `model.c4:271` enumerates the workflow's `paths:` filter as
  "issue-alerts.tf/cron-monitors.tf/uptime-monitors.tf" — **Phase 3.3 widens that filter**, so the
  description must be updated in the same PR. **Added to Files to Edit.**
- The 5b cut removes v1's `model.c4:271` "one per scheduled workflow" watch item.

### Sequencing
The ADR amendment lands in **this** PR, with Phase 3.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Full-root alone relocates the footgun** — apply is `push: main`-only, so a bad delete goes red *after* merge and the orphan survives (byte-identical to #6074). | **Phase 3.4's `pull_request` plan job** — the highest-leverage change in this plan. AC14. |
| **The `.tf`-only scope-guard source is vacuous in the direction of the bug** — a state-only type is invisible; had `kb_tenant_mint_silent_fallback` been the last `sentry_issue_alert`, the guard would pass green while an array-of-blocks destroy went unchecked. | Phase 4.1: source = `.tf ∪ state`. Preserve empty→FAIL. AC6. |
| **An unwanted CREATE has no gate** (the filter counts deletes only); post-`-target=` the 4 formerly-untargeted alerts are in scope, and divergence materializes as an unreviewed create — the same billing leak in mirror image. | Phase 3.5: `resource_creates` + diff-match gate. Not blanket `[ack-create]` (would fire on the normal add-a-monitor flow and train ack-blindness). |
| Full-root surfaces unanticipated destroys. | **Measured:** exactly 2, both dead. AC5 asserts the **set**. Re-run at merge time. |
| The 4 untargeted import-only alerts are not in state → duplicate creates. | **Refuted:** state has 23 vs 22 declared; all 22 plan as no-op. |
| Removing the scope bound weakens the destroy filter. | **Refuted:** root declares exactly 3 types; `sentry_issue_alert` is the only array-of-blocks type and its clause exists. Verified `{resource_deletes: 2, nested_deletes: 0}`. The widened `ignore_changes` assumption (2 → 22) becomes an explicit AC5 sub-assertion. |
| Retiring #6374's clause (b) looks like breaking a P1-derived invariant. | The ADR amendment states *why* it is safe: full-root makes declared ≡ applied, so the invariant is preserved by construction; Phase 3.3's `paths:` widening keeps that true. |
| `use_lockfile = false` — full-root widens the unlocked write window to the whole state key. | **Not mitigated; accepted.** Prose instruction only. Recorded honestly. |
| FR1's write is scope-blocked (403) and quietly becomes a human task. | `automation-status: UNVERIFIED`; API→Playwright ladder with evidence; **Phase 1.2 decouples it from this PR**. |

## Files to Edit

1. `.github/workflows/apply-sentry-infra.yml` — remove 71 `-target=` lines (`:196-261`); remove stale comment (`:186-192`); widen `paths:` (`:44-52`); **add the `pull_request` plan job**; keep `[ack-destroy]`/`[skip-sentry-apply]` byte-for-byte.
2. `tests/scripts/lib/destroy-guard-filter-sentry.jq` — add `resource_creates`; update CURRENT SCOPE (`:8,31-36`).
3. `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` — source `.tf ∪ state`; parameterize `SENTRY_TF_DIR` (`:32-48`).
4. `tests/scripts/test-destroy-guard-counter-sentry.sh` — **delete** the stale `-target=` recipe (`:17-34`).
5. `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` — drop `applyTargetResourceIds()` + `missingTarget` (`:134-206`); keep `missingMonitor`.
6. `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — drop `-target=` regex (`:27,35,44,55`).
7–12. The six op-contract tests (`sentry-inbox-action-required-…:45,49`, `sentry-kb-sync-silent-failure-…:107-113`, `sentry-kb-sync-protected-fallback-…:90-96`, `sentry-zot-mirror-fallback-…:321-325`, `sentry-web-terminal-boot-fatal-…:81-85`, `sentry-outbound-email-…:59-63`) — assert "declared in `issue-alerts.tf`" instead of `-target=` membership.
13. `.github/workflows/infra-validation.yml:37-39` — stale allowlist prose.
14. `apps/web-platform/infra/sentry/uptime-monitors.tf:21-27` — stale allowlist prose.
15. `apps/web-platform/scripts/sentry-monitors-audit.sh` — Class D + **non-zero exit** + `SOLEUR_` marker.
16. `knowledge-base/operations/expenses.md:37` — Amount + Notes.
17. `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — **append** `Amendment (2026-07-17, #6589)`.
18. `knowledge-base/engineering/architecture/diagrams/model.c4:271` — the `paths:` enumeration, now widened.

## Files to Create

**None.** *(v1's register-citation guard and follow-through probe were both cut at plan-review.)*

## Follow-ups to file

- **OQ4 / Phase 5b** — are `scheduled-ux-audit` / `scheduled-architecture-diagram-sync` producers dead or merely unwired? Both are IaC-declared with **zero check-ins ever**. (~$1.56/mo.)
- **Growth gate** — `reserved = 1` means every new scheduled workflow is an uncapped $0.78/mo. Class D catches orphans; **nothing gates growth**. (CTO devex flag.)
- **Fold the scope guard into the counter test?** After 4.1 it largely restates the jq filter's own scope comment — a 4th guard file may not earn its keep. (CTO devex flag.)

## Open Questions

1. ~~Does full-root surface latent state destroys?~~ **CLOSED** — exactly 2, both known, measured.
2. ~~Are the 4 untargeted import-only alerts in state?~~ **CLOSED** — yes; 0 creates.
3. Creation mechanism of uptime id `1422253` — untraced; Sentry-only. Does not block 5c.
4. Does the IaC token carry `monitor:admin` DELETE scope for 5c? **Unverified** — the same token 403'd on `ondemand-budgets/`. Phase 5c must probe before assuming.
5. Does budget-deactivation inherit pause's alert-suppression? Docs never confirm; #3958 is our only evidence. Does not block — either way the failure is silent.

## Session Errors (plan authoring)

1. **I under-swept the `-target=` consumers (3 named; 11 real).** My *first* grep of the session
   listed all six op-contract test files — I saw them, did not follow up, and then let two research
   agents narrow the list without re-checking my own earlier output. Kieran caught it; it would have
   made AC9 unpassable and shipped a red PR. **Prevention:** when a plan enumerates consumers of a
   contract, the file list must come from a fresh `git grep -l` at plan-write time and be reconciled
   against every earlier grep in the session — never from a subagent's summary alone. This is the
   #4591 failure class the plan skill already warns about.
2. **My Phase 4.1 "strengthens the invariant" claim was false in the direction of the bug.** Under
   full-root the plan universe is state ∪ config; a `.tf`-only extractor is blind to exactly the
   state-only resources this PR exists to destroy. Caught by architecture-strategist.
   **Prevention:** when changing what a guard reads, ask "what is in the new source's *complement*?"
3. **I specified a register guard that contradicted my own reconciliation table** — the table said
   the register cites the *workflow filename*; the guard substring-matched the *monitor slug*.
   Caught independently by DHH and code-simplicity. **Prevention:** a guard's key must be re-derived
   from the citation it claims to enforce, not from the slug that happens to be nearby.
4. **Two research agents disagreed on a countable fact** (issue-alert `-target=` count: 2 vs 18).
   The anchored grep (`grep -oE '^\s*-target=sentry_[a-z_]+'`) settled it at 18. **Prevention:**
   `cq-assert-anchor-not-bare-token` — when agents disagree on a count, re-derive it with an
   anchored pattern rather than picking a side.
5. **The IaC-routing hook blocked three plan writes on an incidental idiom** — a hyphenated phrase
   meaning "outside the normal channel", used to describe a Sentry-side UI delete, never to describe
   a human task. The third block was self-inflicted: the Session Errors entry *documenting* the
   trigger quoted the trigger, so the write explaining the block re-triggered it. **Prevention:**
   `.claude/hooks/iac-plan-write-guard.sh` pattern (b) is a whole-phrase scan of plan *prose* — when
   it fires, first check whether the match is incidental word choice rather than reaching for the
   `iac-routing-ack` opt-out (an unnecessary ack records a `bypass` in rule telemetry and weakens a
   real signal), and describe trigger phrases rather than quoting them.
</content>
