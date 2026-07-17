---
title: "feat(observability): nightly source-vs-live Better Stack heartbeat reconcile in the drift workflow"
date: 2026-07-17
type: feat
branch: feat-one-shot-6549-heartbeat-live-reconcile
issue: 6549
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# feat(observability): nightly source-vs-live heartbeat reconcile (#6549 item 2)

> Spec lacks a `spec.md` (direct one-shot→plan path) — `lane:` defaulted to `cross-domain` (TR2 fail-closed). Infra + CI + plugin-lib change; no product/UI surface.

## Overview

Add a **live-reading reconcile job** to `.github/workflows/scheduled-terraform-drift.yml` that pulls Better Stack `GET /api/v2/heartbeats` and reconciles the **live** `paused`/existence state of each monitored heartbeat against the executable `MANIFEST` in `plugins/soleur/lib/heartbeat-manifest.ts`.

It hard-fails (posts to the drift-workflow's existing GitHub-issue reporting surface + emits a `SOLEUR_*` stdout marker) on either mismatch class:

- **(a) live-paused-but-fed** — a heartbeat that is `paused` in live Better Stack while its manifest row declares a **working feeder** (`feeder.kind ∈ {cron,timer}`). This is the exact registry-9-days-dark shape (#6537).
- **(b) present-in-HCL-but-absent-live** — a heartbeat declared in `.tf`/`MANIFEST` (with **no `count` gate**) that is **absent** from live Better Stack. This is the `soleur-git-data-prd` shape (#6548).

This closes the gap the static `heartbeat-reprovision-parity.test.ts` guard cannot: `lifecycle { ignore_changes = [paused] }` plus these resources being untargeted means the `.tf` `paused` value is only a **lower bound** on live state — a live-paused or live-missing monitor is invisible to any source-only test. The reconcile only **READS**; it never unpauses anything.

### Why this is the right shape (premise validation)

- **#6549 is OPEN**, `closedByPullRequestsReferences: []`. This PR delivers **item 2 only**; item 1 (the two `alerts-github-webhook.tf` heartbeats) is `count = 0` under `betterstack_paid_tier = false` and is left untouched. Check the item-2 box, reference the PR, **do NOT Close #6549**.
- **#6548 is OPEN.** Its ask #1 ("confirm whether `betteruptime_heartbeat.git_data_prd` is missing from state vs the provider") is exactly what condition (b) surfaces on this job's first run. Reference #6548 as context; the build-vs-delete disposition of `git_data_prd` is deliberately deferred pending the first run. **Do NOT Close #6548.**
- ADR-117 (`executable-heartbeat-arming`) explicitly documents "the states this does NOT cover" — the live-paused / live-absent states. This job is the complement that covers them; the ADR is **amended**, not superseded (Phase 2.10).
- The `betterstack` external system in `knowledge-base/engineering/architecture/diagrams/model.c4:266` **already** documents git-data as "unfed … and absent from live Better Stack despite having no count gate (#6548)" and registry-liveness as "paused until #6537's feeder ships" — this job operationalizes what the C4 already narrates.

## Research Reconciliation — Spec vs. Codebase

| Claim (from brief) | Codebase reality (verified) | Plan response |
|---|---|---|
| "reconcile live `paused`/existence against MANIFEST" | MANIFEST rows are keyed by **resource label** (`registry_prd`); live Better Stack keys by the `name =` attribute (`soleur-registry-prd`). MANIFEST carries **no** live name. | Reconcile parses each `betteruptime_heartbeat` `.tf` block for `name =` (the live name), `paused`, and `count =` presence — matching MANIFEST rows to live heartbeats by that name. No new MANIFEST field required. |
| "fail on … a heartbeat present in HCL but ABSENT live" | The two `alerts-github-webhook.tf` heartbeats are `count = var.betterstack_paid_tier ? 1 : 0` — **intentionally absent** under the free tier. | Condition (b) **excludes any heartbeat block with a `count =` meta-argument** (the item-1 carve-out). All four in-scope heartbeats (`inngest_prd`, `registry_prd`, `registry_disk_prd`, `git_data_prd`) have no `count` gate and are evaluated. |
| "read Better Stack API creds from Doppler `prd_terraform`, read-only token" | `variable "betterstack_api_token"` (Doppler `BETTERSTACK_API_TOKEN`, **Read & write**) feeds the provider at `main.tf:66`. No read-only token exists in Doppler today. | v1 reuses `BETTERSTACK_API_TOKEN` read **raw** via `doppler secrets get --plain` (the AWS-cred pattern, not `--name-transformer tf-var`). See Design Decision D1 for the read-only-token trade-off + fast-follow. |
| "reuse the existing sanitized-issue-post reporting surface" | The issue-post is **inline shell** in the drift-check job (lines 125-197), keyed to `steps.plan.outputs`; not a composite action. | The new job **replicates** the create-or-update-deduped-issue pattern with a distinct label/title; the email (`notify-ops-email`) and Sentry check-in (`sentry-heartbeat`) composite actions are reused as-is. |
| "nightly" | The workflow is `on: workflow_dispatch`, Inngest-dispatched twice-daily (`0 6,18 * * *`) via `cron-terraform-drift.ts` (ADR-033: Inngest is the single scheduling substrate). | The reconcile job **rides the same twice-daily dispatch** — no new `schedule:` trigger, no new Inngest function. "Nightly" ≈ the existing twice-daily cadence. |

## Design Decisions

### D1 — Auth: reuse `BETTERSTACK_API_TOKEN` for v1; read-only token is a documented fast-follow

The brief prefers a **read-only** token (least privilege). Trade-off resolved as follows:

- **v1 reads the existing `BETTERSTACK_API_TOKEN`** (Doppler `soleur/prd_terraform`, already present) raw via `doppler secrets get BETTERSTACK_API_TOKEN --plain`, masked with `::add-mask::`. Rationale: (1) `GET /api/v2/heartbeats` is read-only in effect; (2) the token already exists, so the **#6548-diagnostic first run is never blocked on an operator mint** (the never-defer-operator principle — Soleur's operator is non-technical); (3) it is read via `--plain`, **not** a `TF_VAR_*`, so it gates **no** terraform apply (no auto-apply-sequencing hazard).
- **Least-privilege hardening** (mint a dedicated `Read`-scoped Better Stack token → store as `BETTERSTACK_API_TOKEN_READONLY` in `prd_terraform` → swap the one Doppler secret name the reconcile step reads) is a **one-line follow-up**, filed as a tracking issue (Phase 6 deferral gate), NOT a merge blocker. The mint is an authenticated `betterstack.com/settings/global-api-tokens` dashboard action — presumptively Playwright-automatable; /work MAY attempt it, but must not block the diagnostic on it.

> Plan-review / deepen-plan MAY elevate the read-only token to a pre-merge requirement; if so, /work attempts the Playwright mint first and only falls back to reuse if a genuine human gate is reached.

### D2 — Separate job, riding the same workflow (not a matrix step)

The drift-check job is a `matrix` over two directories; a reconcile step there would run per-directory. Add a **separate job `heartbeat-live-reconcile`** in the same workflow (own `setup-bun`, own reporting, own Sentry monitor). It runs on every `workflow_dispatch` of `scheduled-terraform-drift.yml` — i.e. the same twice-daily Inngest dispatch.

### D3 — Three-outcome semantics (flake tolerance)

The reconcile **script** exits with a tri-state mirroring the drift job's exit-code contract, and the workflow branches on it (capture `rc=$?` explicitly to a variable, `set +e` around the call, never pipe the exit through `tail`/`grep` — learning `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`):

| Script exit | Meaning | Marker | Workflow action | Sentry check-in |
|---|---|---|---|---|
| `0` | **OK** — all in-scope heartbeats reconcile | `SOLEUR_HEARTBEAT_RECONCILE_OK` | none | `ok` |
| `0` | **UNREACHABLE** — Better Stack 5xx/429/timeout/network after retries exhausted | `SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE` | `::warning::`, **no page** | `ok` (job ran) |
| `2` | **MISMATCH** — confirmed condition (a) and/or (b) | `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<x> live=<paused\|absent> reason=<fed-but-paused\|absent-live>` | create/update deduped issue + email (creation-only) | `ok` (reconcile ran; issue/email are the mismatch signal) |
| `1` | **ERROR** — auth (401/403), token absent, malformed response | `SOLEUR_HEARTBEAT_RECONCILE_ERROR` | `::error::` + email | `error` |

- **Transient (5xx/429/timeout/network)** must NOT page: retry up to **3 attempts** with exponential backoff (1s/2s/4s) and a per-request timeout (`AbortController`, ~10s). Depth-bounded — learning `2026-03-09-depth-limited-api-retry-pattern.md`. If all retries exhausted → UNREACHABLE (exit 0). The `::warning::` annotation makes it operator-visible (non-silent, satisfying `cq-silent-fallback-must-mirror-to-sentry`).
- **Auth (401/403)** is **not** transient — a persistently misconfigured token is a real problem → exit 1 → `::error::` + email + Sentry `error`. (Distinct from a mismatch.)
- **MISMATCH** keeps the Sentry monitor `ok` (mirrors the drift job: drift = exit 2 = "success path, downstream filer handles the issue" → `?status=ok`). The GitHub issue + email are the mismatch signal; the Sentry monitor is a pure **liveness** signal (did the reconcile run?).

### D4 — Reporting reuses the drift-workflow surface

- **GitHub issue:** create-or-update a **deduped** issue (label `heartbeat-reconcile-mismatch`, title `infra: Better Stack heartbeat live-reconcile mismatch`), sanitized `SOLEUR_*` output in a `<details>` block — mirroring the drift job's inline pattern (`scheduled-terraform-drift.yml:125-197`). Dedup (comment on the existing issue, do not re-create) prevents spam during the #6548 disposition window.
- **Email:** the `notify-ops-email` composite action, gated to fire **only on issue creation** (first detection or when the mismatch set changes) — NOT on every twice-daily recurrence — to avoid alert fatigue while `git_data_prd` remains unresolved.
- **Strip CR/LF before any `::error::`/`::notice::` annotation** (`${var//[$'\n\r']/}`) — log-injection safety (Sharp Edge; learning re annotation injection).

### D5 — Code layout (pure logic + thin CLI + TDD)

- `plugins/soleur/lib/heartbeat-live-reconcile.ts` — **pure, network-free** module: `parseHeartbeatBlocks(tfText)` (brace-matched `betteruptime_heartbeat` blocks → `{ resourceName, liveName, sourcePaused, countGated }`, comment-stripped like the parity test's `stripComments`) + `reconcileHeartbeats(manifest, discovered, live)` → `Violation[]`. Unit-testable without a token.
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts` — thin CLI: read token from env, `fetch` `GET https://uptime.betterstack.com/api/v2/heartbeats` with `Authorization: Bearer <token>` (follow `pagination.next` until null), retry/backoff, call the pure reconcile, print `SOLEUR_*` markers, set exit code.
- `plugins/soleur/test/heartbeat-live-reconcile.test.ts` — RED-first (`cq-write-failing-tests-before`), synthetic fixtures only (`cq-test-fixtures-synthesized-only`): covers condition (a), condition (b), the `count`-gate carve-out (webhook rows never flagged absent), OK path, and a synthetic live-API JSON fixture.

> The parity test's own `parseHeartbeats` (which captures only `paused`) is deliberately **not** refactored — it is a load-bearing green test and the new parser additionally needs `name`/`count`. Duplication is intentional and minimal-blast-radius; a future consolidation is a scope-out, not a blocker.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) the reconcile false-**passes** and a heartbeat silently sits paused/absent again — the exact 9-day-dark-registry recurrence this job exists to prevent — or (b) it false-**fails** and pages the founder on healthy infra twice a day, training them to ignore the alert and re-hiding real outages.

**If this leaks, the user's monitoring-plane access is exposed via:** the `BETTERSTACK_API_TOKEN` appearing unmasked in GitHub Actions logs (read/write access to Better Stack monitors). Mitigated by `::add-mask::` on the token immediately after the `doppler secrets get --plain` read, and the token never being echoed.

**Brand-survival threshold:** `aggregate pattern` — this is an **internal observability guard** for the founder's own infra; it touches no end-user data and has no per-user blast radius. The failure class it guards (blind monitoring) is a reliability pattern, not a single-user incident. No CPO sign-off required; `user-impact-reviewer` not required at review time.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

0.1. Confirm the Better Stack API contract against docs (`docs.betterstack.com` Uptime API) — endpoint `GET /api/v2/heartbeats`, `Authorization: Bearer <token>`, response `data[].attributes.{name,paused}`, `pagination.next`. The MANIFEST comment at `heartbeat-manifest.ts:148` ("LIVE is paused=false … self-pulled from /api/v2/heartbeats") already confirms `attributes.paused` exists; verify the pagination + auth-header shape and pin `<!-- verified: 2026-07-17 source: <url> -->` in the script.
0.2. Confirm `bun` runs the script importing the pure manifest **without external deps** (the manifest + new lib import only bun builtins). Add a `bun install --frozen-lockfile` step defensively (learning `2026-03-18-bun-test-segfault-missing-deps.md`); pin bun via `.bun-version` like `ci.yml:431`.
0.3. Confirm `secrets.DOPPLER_TOKEN` is scoped to `prd_terraform` (the drift-check job already uses it with `DOPPLER_CONFIG: prd_terraform`) — reuse it; **no new GitHub secret** (learning `2026-03-29-doppler-service-token-config-scope-mismatch.md`).

### Phase 1 — Pure reconcile lib + RED tests (TDD)

1.1. Write `plugins/soleur/test/heartbeat-live-reconcile.test.ts` FIRST (RED) — assertions per D5.
1.2. Implement `plugins/soleur/lib/heartbeat-live-reconcile.ts` (`parseHeartbeatBlocks` + `reconcileHeartbeats`) to GREEN. `countGated = /\bcount\s*=/.test(commentStrippedBlockBody)`; `sourcePaused` defaults `false` when absent (mirror the parity parser's conservative reading).

### Phase 2 — CLI script

2.1. `plugins/soleur/scripts/reconcile-live-heartbeats.ts`: env-token read, paginated `fetch` with 3-retry backoff + 10s per-request timeout, 401/403→exit 1, transient-exhausted→exit 0+UNREACHABLE, mismatch→exit 2, else exit 0. Emit structured `SOLEUR_*` markers (D3). NEVER echo the token.

### Phase 3 — Workflow job

3.1. Add job `heartbeat-live-reconcile` to `.github/workflows/scheduled-terraform-drift.yml`: `checkout` → `setup-bun` (SHA-pinned, `bun-version-file: .bun-version`) → `bun install --frozen-lockfile` → Install Doppler CLI → read + mask `BETTERSTACK_API_TOKEN` (`doppler secrets get --plain`, `DOPPLER_CONFIG: prd_terraform`) → run script capturing `rc=$?` (`set +e`, output to file) → branch on rc.
3.2. Reporting steps (mirror drift-job pattern, distinct label/title): `Ensure heartbeat-reconcile-mismatch label`, `Create or update reconcile issue` (dedup, sanitized output), `notify-ops-email` (creation-only gate), final `sentry-heartbeat` check-in to slug `scheduled-heartbeat-reconcile` (`if: always()`, `continue-on-error: true`, `status` = `error` on rc=1 else `ok`). SHA-pin all external action refs; strip CR/LF before annotations.

### Phase 4 — Sentry cron monitor (IaC)

4.1. Add `resource "sentry_cron_monitor" "scheduled_heartbeat_reconcile"` to `apps/web-platform/infra/sentry/cron-monitors.tf`, mirroring `scheduled_terraform_drift` (`schedule = { crontab = "0 6,18 * * *" }`, `checkin_margin_minutes = 60`, `failure_issue_threshold = 1`) — margin sized for the Inngest-dispatch cadence, not GHA-schedule jitter (learning `2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md`).
4.2. Update `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` (+ any sibling census in `cron-substrate-imports.test.ts`) so the new monitor slug ↔ workflow-check-in parity holds. Grep `apps/web-platform/test scripts/` for any hardcoded monitor count/slug census and update.

> `apply-sentry-infra.yml` is **full-root, auto-applied on push to `main`** touching `infra/sentry/**` (no `-target=` allowlist since #6589). Adding a monitor is a **pure create** — no `[ack-destroy]`, no operator step, no `-target` update. See `## Infrastructure (IaC)`.

### Phase 5 — ADR amendment + C4

5.1. **Amend ADR-117** (`executable-heartbeat-arming`) via `/soleur:architecture`: add the live-reconcile to `## Decision` as the complement covering the live-paused/live-absent states its static guard explicitly does not, and add "live-reconcile in CI" vs "extend the static test to read live state" to `## Alternatives Considered`. (New-ADR fallback ordinal if amendment is rejected: **ADR-122** — verified next-free; treat as provisional per ship's ordinal-collision gate.)
5.2. **C4:** READ all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. The `betterstack` external system exists (model.c4:266) and already narrates the git-data/registry states. Enumerate the new edge: **GitHub Actions CI → Better Stack (`GET /api/v2/heartbeats`, read-only heartbeat reconcile)**. If a CI→betterstack read edge for the heartbeats API is not already modeled (the existing CI-poll edge is the **Logs** source via `betterstack-query.sh`, a different surface), add the element/edge + the `views.c4` `include` line so it renders, and run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. If already covered, cite the exact line and record "no C4 impact" with the enumeration.

### Phase 6 — Wire-up, verify, ship prep

6.1. Local: `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` (GREEN) + `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` (still GREEN — untouched). Typecheck the new TS.
6.2. Dry-run the reconcile locally against live Better Stack (read-only, using a locally-exported token) to confirm it flags `git_data_prd` absent (condition b) and passes the three armed heartbeats — capturing the actual `SOLEUR_*` output for the PR body.
6.3. On #6549: check the **item-2** checkbox, add "addressed by PR #<n>", leave OPEN. On #6548: comment linking the PR as the diagnostic surface, leave OPEN.
6.4. File the D1 read-only-token follow-up issue (deferral tracking). PR body uses `Ref #6549` / `Ref #6548` (NOT `Closes`).

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_heartbeat_reconcile` (slug `scheduled-heartbeat-reconcile`). Provider: existing `sentry` provider (`main.tf`). **No new sensitive variable** — `BETTERSTACK_API_TOKEN` already exists in Doppler `prd_terraform` and is read at workflow runtime, not by terraform.

### Apply path
- **Auto-applied full-root plan.** `apply-sentry-infra.yml` fires on push to `main` touching `infra/sentry/**` and applies FULL-ROOT (since #6589). Merging this PR creates the monitor. Zero downtime, blast-radius = one new monitor (pure create).

### Distinctness / drift safeguards
- Pure create → the `sentry-destroy-required` / `[ack-destroy]` gate does not fire (no delete). The new monitor is covered by the same destroy-guard/scope tests going forward; Phase 4.2 keeps the IaC-parity census green.

### Vendor-tier reality check
- Sentry cron monitors exist on the current tier (11+ already declared in `cron-monitors.tf`) — no paid-tier gate. Better Stack: **no new resource** — the reconcile is a read-only API consumer, not a provisioned monitor.

## Observability

```yaml
liveness_signal:
  what: "scheduled-heartbeat-reconcile Sentry cron check-in (final sentry-heartbeat step, if: always())"
  cadence: "twice daily (0 6,18 UTC) — rides the drift workflow's Inngest dispatch"
  alert_target: "Sentry cron monitor (failure_issue_threshold=1 opens an issue on a missed check-in); second-source vendor"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf + scheduled-terraform-drift.yml final step"
error_reporting:
  destination: "deduped GitHub issue (label heartbeat-reconcile-mismatch) + notify-ops-email + SOLEUR_* stdout marker"
  fail_loud: "yes — script exits 2 on mismatch / 1 on error; ::error:: on job error; ::warning:: on unreachable"
failure_modes:
  - {mode: "live-paused-but-fed (condition a)", detection: "reconcile compares live attributes.paused vs manifest feeder.kind in {cron,timer}", alert_route: "issue + email + exit 2 + SOLEUR_..._MISMATCH"}
  - {mode: "present-in-HCL-absent-live (condition b, git_data shape)", detection: "reconcile live-name lookup miss for a non-count-gated heartbeat", alert_route: "issue + email + exit 2 + SOLEUR_..._MISMATCH"}
  - {mode: "Better Stack API unreachable (transient 5xx/429/timeout)", detection: "3-retry backoff exhausted", alert_route: "::warning:: + SOLEUR_..._UNREACHABLE, NO page, Sentry ok"}
  - {mode: "auth/config error (401/403, token absent)", detection: "script exit 1", alert_route: "::error:: + email + Sentry error"}
  - {mode: "reconcile job stops firing", detection: "missed scheduled-heartbeat-reconcile Sentry check-in", alert_route: "Sentry cron failure_issue_threshold opens an issue"}
logs:
  where: "GitHub Actions run logs (structured SOLEUR_* markers) + the deduped GitHub issue body"
  retention: "GitHub Actions default retention"
discoverability_test:
  command: "gh run list --workflow=scheduled-terraform-drift.yml && gh issue list --label heartbeat-reconcile-mismatch && bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts"
  expected_output: "reconcile job present + green; mismatch issue OPEN iff a mismatch exists; unit tests GREEN"
```

**2.9.2 blind-surface probe:** this reconcile is itself a blind CI cron. Its `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH` marker is **structured** (`name=`, `live=paused|absent`, `reason=fed-but-paused|absent-live`) so a single emitted event **discriminates condition (a) vs (b) vs unreachable** in one line — the in-surface discriminator, not a host-side inference.

## Domain Review

**Domains relevant:** engineering (infra/observability) only.

No business-domain (product/marketing/sales/finance/legal/ops/support) implications — this is an internal infra/observability tooling change with no user-facing surface, no `components/**` / `app/**/page.tsx` files, no regulated-data surface. The mechanical UI-surface override does not fire (no UI-surface path in Files to Edit). **Product/UX Gate: NONE.** Engineering concerns (CTO lens) are covered by the plan-review eng panel + deepen-plan + the IaC gate (Phase 2.8) and Observability gate (Phase 2.9).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `plugins/soleur/lib/heartbeat-live-reconcile.ts` exports `parseHeartbeatBlocks` + `reconcileHeartbeats`; `reconcileHeartbeats` returns a condition-(a) violation for a live-paused heartbeat whose manifest feeder.kind in {cron,timer}, and a condition-(b) violation for a non-count-gated heartbeat absent from the live payload.
- [ ] A `count`-gated heartbeat (the two webhook rows) is **never** flagged by condition (b) — asserted by a synthetic fixture in `heartbeat-live-reconcile.test.ts`.
- [ ] `plugins/soleur/test/heartbeat-live-reconcile.test.ts` is GREEN; `heartbeat-reprovision-parity.test.ts` remains GREEN (unmodified).
- [ ] `scheduled-terraform-drift.yml` has a `heartbeat-live-reconcile` job that reads `BETTERSTACK_API_TOKEN` via `doppler secrets get --plain` (`::add-mask::`ed), runs the script, and on rc=2 creates/updates a deduped issue labelled `heartbeat-reconcile-mismatch` — verified by reading the job YAML.
- [ ] Transient path: the script retries ≤3× with backoff and exits **0** (UNREACHABLE) on exhausted 5xx/timeout — asserted by a unit test injecting a failing fetch; auth 401/403 exits **1** — asserted separately.
- [ ] `sentry_cron_monitor.scheduled_heartbeat_reconcile` added to `cron-monitors.tf` with `checkin_margin_minutes = 60`, `schedule.crontab = "0 6,18 * * *"`; `sentry-monitor-iac-parity.test.ts` GREEN.
- [ ] ADR-117 amended (or ADR-122 created); all three `.c4` files read, the CI→betterstack heartbeat-read edge added-or-cited-as-present, `c4-code-syntax.test.ts` + `c4-render.test.ts` GREEN.
- [ ] PR body uses `Ref #6549` / `Ref #6548`, includes a `## Changelog`, `semver:minor` label; no `Closes`.

### Post-merge (operator/automated)
- [ ] Item-2 checkbox on #6549 checked, PR referenced, #6549 **OPEN**; #6548 commented, **OPEN**. (Automated via `gh` in Phase 6.3.)
- [ ] `apply-sentry-infra.yml` auto-applies the new monitor on merge (verify the run went green; no `[ack-destroy]` needed). (Automated verification via `gh run list`.)
- [ ] First reconcile run surfaces `git_data_prd` absent (condition b) to the `heartbeat-reconcile-mismatch` issue — the #6548 diagnostic. (Verify via `gh issue list`.)
- [ ] D1 read-only-token follow-up issue filed.

## Test Scenarios

1. **Condition (a):** live payload has `soleur-registry-prd` with `paused:true`; manifest `registry_prd` feeder.kind=`timer` → violation `fed-but-paused`.
2. **Condition (b):** live payload omits `soleur-git-data-prd`; `.tf` block has no `count =` → violation `absent-live`.
3. **Item-1 carve-out:** live payload omits `soleur-github-webhook-sig-failures-prd`; `.tf` block has `count = var.betterstack_paid_tier ? 1 : 0` → **no** violation.
4. **OK:** all four in-scope heartbeats present + (armed ones) unpaused → empty violations, exit 0.
5. **Unreachable:** injected fetch throws/500 on all 3 attempts → exit 0, UNREACHABLE marker, no issue.
6. **Auth:** injected 401 → exit 1, ERROR marker.

## Hypotheses

Not applicable — this is a build (new reconcile job), not a diagnosis of a live outage. The feature description's "5xx/timeout" tokens refer to **flake-tolerance logic being written**, not an SSH/network outage being diagnosed; the Phase-1.4 network-outage checklist (firewall/DNS/sshd order) does not apply — no host diagnosis, no sshd/fail2ban hypothesis. (Keyword false-positive, noted per the gate.)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no issue bodies referencing `scheduled-terraform-drift.yml`, `heartbeat-manifest`, `cron-monitors.tf`, or `heartbeat-reprovision-parity`.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6.** This section is filled (threshold: `aggregate pattern`).
- **The reconcile is expected to fail on `git_data_prd` on first run** and to keep flagging it until #6548 is dispositioned (build the probe cron or delete the heartbeat). This is the intended forcing function, mirroring the parity test's "reds on purpose." Dedup + creation-only email keep it from becoming twice-daily spam.
- **Verify the Better Stack API contract against docs, not memory** (Sharp Edge: vendored-service behavior is measured, not derived). Pin the `<!-- verified: -->` annotation.
- **Do NOT touch the two `alerts-github-webhook.tf` heartbeats or their MANIFEST rows** — item 1 is out of scope. The `count`-gate carve-out is what keeps them out; if a future reviewer proposes checking them, that is item 1 (paid-tier-gated), a separate PR.
- **`sentry-monitor-iac-parity.test.ts` will red** if the new monitor slug is not mirrored between `cron-monitors.tf` and the workflow check-in — update it in the same PR (Phase 4.2).
