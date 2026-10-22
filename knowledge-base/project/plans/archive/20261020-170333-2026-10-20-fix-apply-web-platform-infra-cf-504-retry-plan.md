---
title: "infra-apply: terraform plan fails hard on transient Cloudflare 504s (no provider-read retry)"
type: fix
date: 2026-10-20
slug: fix-apply-web-platform-infra-cf-504-retry
branch: feat-one-shot-10643-tf-plan-504-retry
issue: 10643
closes: 10643
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# infra-apply: terraform plan fails hard on transient Cloudflare 504s (no provider-read retry)

## Overview

The post-merge `Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)` run 39364009152 failed three consecutive attempts (~03:30–04:05 UTC 2026-10-20, `main@57dda4c24`) at the `Terraform plan (allow-list, non-SSH resources only)` step: all four Cloudflare Zero Trust resource reads in `apps/web-platform/infra/tunnel.tf` (`cloudflare_zero_trust_access_application.deploy` :135, `cloudflare_zero_trust_access_service_token.deploy` :143, `cloudflare_zero_trust_access_application.ssh` :186, `cloudflare_zero_trust_access_service_token.ci_ssh` :199) returned `received gateway timeout response (HTTP 504)` and `terraform plan` exited 1.

The provider already retries 5xx — the 504 error string is emitted by the vendored `cloudflare-go` client only *after* its retry loop exhausts. The real defect is that the retry budget is the v4 default (`retries = 3`, `min_backoff = 1`, `max_backoff = 30` ≈ 7s of backoff per request), far too shallow for a multi-minute upstream degradation. The fix tunes `retries`/`min_backoff`/`max_backoff` on every `provider "cloudflare"` block, which covers reads *and* writes on every caller of the root (the apply workflow, `apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml`, PR `infra-validation.yml`, and ad-hoc invocations) with zero workflow-YAML churn.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Hypotheses

Fired by Phase 1.4 (`504`, `timeout` in the description). L3→L7 order; each layer carries a verification artifact or an explicit opt-out.

1. **L3 — firewall allow-list.** Not applicable to host egress: the failure is a GitHub-hosted runner → `api.cloudflare.com` conversation, and an HTTP 504 *response* proves the TCP connection, TLS handshake, and edge routing all succeeded. [verified: the 504 is an L7 artifact returned by Cloudflare's edge; no packet-loss hypothesis is compatible with receiving it]
2. **L3 — DNS / routing.** Same artifact: a 504 requires a resolved, routed, connected request. [verified by the response itself]
3. **L7 — TLS / proxy layer.** The response is Cloudflare's own edge reporting a timeout reaching its upstream Zero Trust service — the TLS path terminated correctly at the edge. [verified: `received gateway timeout response (HTTP 504)` is cloudflare-go's post-retry error text, `cloudflare.go` line ~270 in vendored v0.116.0]
4. **L7 — application layer (upstream).** Cloudflare's Zero Trust API path degraded across the incident window: four distinct ZT reads failed while no declared Cloudflare incident was posted — plausibly unreported upstream flakiness or an account/path-scoped condition (issue body). [verified by the failure log's resource census]
5. **Defect (ours, the fixable layer).** The provider's per-request retry budget (v4 defaults: 3 retries, ~7s total backoff) is too shallow to ride out a multi-minute upstream blip; every retried read still failed inside each of the three run attempts. [verified: cloudflare-go v0.116.0 `makeRequestWithAuthTypeAndHeadersComplete` retries `resp.StatusCode >= 500` up to `MaxRetries`, then emits the observed error]

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10643 --json state,title,closedByPullRequestsReferences`: **OPEN**, zero closing-PR references — premise holds, plan targets it.
- Cited artifacts exist on `origin/main`: `apps/web-platform/infra/tunnel.tf` (all four resources at the cited lines), `.github/workflows/apply-web-platform-infra.yml` (plan step at lines 435–691, `terraform plan` invocation line 476 under `doppler run --name-transformer tf-var`).
- Proposed mechanism vs ADR corpus: `grep -liE 'retry|504|cloudflare' knowledge-base/engineering/architecture/decisions/` — no ADR decides provider-call retry policy. ADR-257 (latched retrying *systemd unit* for Inngest provisioning) is a different substrate and does not constrain this. No rejected-alternative conflict.
- Own capability claims verified: `retries`/`min_backoff`/`max_backoff` exist on the locked schema (probe below); the infra `.test.sh` glob auto-registers (`run-registered-suites.sh` header, ADR-252: "presence IS registration"); `apps/cla-evidence/infra` uses the per-app `main.test.sh` hook executed by `infra-validation.yml` (workflow comment at the "Run per-app main.test.sh" step).

### Property List (Phase 0.6b)

1. `terraform plan` on the web-platform root survives a multi-minute Cloudflare API 5xx blip on provider reads without a hard failure.
2. The tolerance reaches *every* caller of the root — post-merge apply, `apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml`, PR `infra-validation.yml`, and ad-hoc invocations — not only the one workflow step named in the issue.
3. The tolerance is regression-pinned so a later edit cannot silently restore the ~7-second default budget.

### Mechanism Minimality — Cut List (Phase 0.6b)

| Cut mechanism | Property it would buy | Already covered by |
|---|---|---|
| Bounded `plan` retry loop in the workflow step (issue's stated fallback) | P1 | cloudflare-go's request loop already retries `StatusCode >= 500` per call — the fallback condition ("if provider-level retry doesn't cover data reads") is falsified at vendored source level |
| `CLOUDFLARE_RETRIES`-style env vars in the step's `env:` | P1, P2 partially | Provider-block attributes reach ad-hoc invocations and the apply step too; env reaches only that one step |
| Provider v5 upgrade to gain `max_retries` | P1 | v4's `retries`/`min_backoff`/`max_backoff` buy the identical property; v5 is a migration, not a knob |

### Evidence — the retry is already there; the budget is the defect

- Locked provider: `cloudflare/cloudflare` **4.52.7** (`.terraform.lock.hcl`, constraint `~> 4.0`, `apps/web-platform/infra/main.tf:23-26`).
- Vendored client: `github.com/cloudflare/cloudflare-go v0.116.0` (provider `go.mod` at tag v4.52.7).
- `cloudflare.go` v0.116.0 `makeRequestWithAuthTypeAndHeadersComplete`: `for i := 0; i <= api.retryPolicy.MaxRetries; i++` with `if respErr != nil || resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 { continue }` (line ~264), backoff `2^(i-1) * MinRetryDelay` capped at `MaxRetryDelay` (defaults `MaxRetries: 3`, `1s`, `30s` → ~7s total). The error text `received %s response (HTTP %d), please try again later` at line ~270 — with `StatusText(504)` = "Gateway Timeout" lowercased — is the *exact* string in the issue log. The observed failure is retry-budget exhaustion, not a missing retry.
- **Schema probe (live, 2026-10-20, per learning `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`):** scratch-dir `terraform init` on `cloudflare/cloudflare = 4.52.7` + `terraform providers schema -json` → provider block attributes include `retries`, `min_backoff`, `max_backoff`, `rps`. **`max_retries` does NOT exist on v4** — it is the v5-era name; the issue's parenthetical names the wrong version's spelling. Correct v4 spellings: `retries`/`min_backoff`/`max_backoff` (env: `CLOUDFLARE_RETRIES`/`CLOUDFLARE_MIN_BACKOFF`/`CLOUDFLARE_MAX_BACKOFF`).
- Backoff arithmetic for the chosen values (`retries = 6`, `min_backoff = 15`, `max_backoff = 120`): sleeps before retries 1–6 = 15+30+60+120+120+120 = **465s ≈ 7.75 min per request**, vs ~7s at default. Applies per API call; only failing calls pay it.
- The apply job's `timeout-minutes: 41` (workflow line 326) bounds the worst case: several sequential failing reads at ~8 min each stay inside the job budget; a sustained outage beyond per-request coverage still fails the plan — bounded failure is the intended residual.
- Sibling roots: `apps/web-platform/infra/{rung2-rehearsal,inngest-provision-rehearsal,git-data-root-key}` declare **no** cloudflare provider (only R2 backend endpoints) — out of scope. `apps/cla-evidence/infra/main.tf:25-27` declares **one** `provider "cloudflare"` block serving `cloudflare_r2_bucket`, `cloudflare_api_token`, and a `data "cloudflare_api_token_permission_groups"` read — same provider, same upstream, same defect class.
- Institutional learnings applied:
  - `2026-06-30-...provider-schema-probe...` — scratch-dir schema probe works offline; running it inside the real root fails with "Backend initialization required" and a 0-byte dump.
  - `2026-09-07-my-guard-pinned-the-three-attributes-the-vendor-already-refuses.md` — the guard pins what nothing else enforces. `terraform validate` already refuses unknown attribute *names*; the unenforced sibling is attribute **presence** (a dropped optional knob passes validate cleanly). The drift guard pins presence + above-default values, not schema validity.
- Research-agent fan-out unavailable in this environment (no Task/subagent tool): repo research, learnings, and web verification were performed inline; `soleur:engineering:discovery:functional-discovery` and community-discovery agents could not be spawned — assessed implausible for a provider-config knob on own infra machinery.

## Problem Statement / Motivation

Any post-merge window where Cloudflare's Access API is slow leaves `Apply web-platform infra` red on every PR landed during it, masking real apply regressions and forcing re-dispatch (`gh run rerun --failed`). The measured fix size is small (issue triage: p2-medium, `meta/machinery`).

## Proposed Solution

Set the v4 retry-policy trio on every `provider "cloudflare"` block in both Terraform roots that declare one:

- `apps/web-platform/infra/main.tf` — six blocks: default (:150), `zone_settings` (:158), `rulesets` (:189), `bot_management` (:201), `r2` (:211), `pages` (:222). The four failing Zero Trust reads all rode the *default* block, but a Cloudflare API slowdown is upstream of every alias — the same failure class would red a plan on rulesets/bot-management/R2/Pages reads. Uniform knobs, one comment block.
- `apps/cla-evidence/infra/main.tf` — one block (:25). Same provider, same upstream, same defect class; the fix is three lines plus the comment.

Values: `retries = 6`, `min_backoff = 15`, `max_backoff = 120` — ≈7.75 minutes of retry coverage per request (vs ~7s today). A short comment above the trio cites #10643 and the backoff math, and warns that the v5 provider renames this knob to `max_retries` so a future v5 migration does not silently re-shallow the budget.

## Technical Considerations

- **Reads *and* writes are covered.** The retry loop wraps every API call including mutating ones. A create/update that 504s *after* applying server-side can surface a duplicate-exists style error on retry — a visible, recoverable failure (a re-run reconciles state), strictly better than a hard 504 abort mid-plan. 4xx responses are never retried by this code path, so authorization/validation failures still fail fast.
- **`context.DeadlineExceeded` short-circuits** the loop (cloudflare-go v0.116.0, immediately after the `api.request` call): retries never extend past the request context deadline — bounded by Terraform's own operation context.
- **Client-side rate limiting unchanged.** `rps` stays at its default (4 rps); the change extends *patience*, not request rate.
- **Attributes over env vars.** `CLOUDFLARE_RETRIES`-style env vars would cover only the step that sets them; provider-block attributes reach every invocation of the root — CI plan, apply, the drift workflow, and ad-hoc invocations — and are committed, reviewed, and grep-able.
- **v4 spelling is load-bearing.** `max_retries` is the v5-era name and the 4.52.7 schema rejects it (`terraform validate` red). The plan pins `retries`/`min_backoff`/`max_backoff`.
- **Zero workflow-YAML bytes.** The retry lives in the provider, so `.github/workflows/apply-web-platform-infra.yml` (490 KB byte-budget-gated by `plugins/soleur/test/workflow-file-size.test.ts`) is untouched — the workflow-retry-loop alternative would have spent that budget.
- **Test registration is free.** `apps/web-platform/infra/run-registered-suites.sh` derives its suite list by filesystem glob (ADR-252): `apps/web-platform/infra/cloudflare-provider-retry.test.sh` is registered the moment it exists. `apps/cla-evidence/infra/main.test.sh` runs via the `infra-validation.yml` per-app hook.
- **NFR impact:** reliability/operational resilience of the IaC apply path; no user-facing latency or throughput change (healthy calls pay zero added time).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Provider retry knobs on all `provider "cloudflare"` blocks (chosen) | Covers reads and writes on every caller of both roots with a 3-line-per-block committed diff |
| Bounded `terraform plan` retry loop in the workflow step on 504-classified failure (issue's stated fallback) | Fallback only — the provider loop already covers reads; this adds YAML bytes to a budget-gated file, reaches only one step of one workflow, and a whole-plan retry re-runs ~190 `-target` evaluations vs per-request backoff. Re-open only if implementation verification finds a read path that bypasses the retrying client |
| `CLOUDFLARE_RETRIES`/`CLOUDFLARE_MIN_BACKOFF`/`CLOUDFLARE_MAX_BACKOFF` in step `env:` | Narrower reach (one step, not apply/ad-hoc invocations) for no savings over block attributes |
| Provider v5 upgrade for `max_retries` | Migration-scale change to buy a knob v4 already has; out of scope |
| Do nothing; rely on `gh run rerun --failed` | The incident this issue tracks; re-dispatch toil and red-masked regressions continue |

## Files to Edit

- `apps/web-platform/infra/main.tf` — add `retries`/`min_backoff`/`max_backoff` + a #10643 comment to each of the six `provider "cloudflare"` blocks (:150, :158, :189, :201, :211, :222).
- `apps/cla-evidence/infra/main.tf` — same trio + comment on the single block (:25).
- `apps/cla-evidence/infra/main.test.sh` — extend with assertions that the provider block carries the trio above defaults (runs via the infra-validation per-app hook).
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` — one-line note in the failure-arms framing: provider calls now retry 5xx up to ~8 min per request; a plan red on `HTTP 504` after this change means the upstream degradation outlasted that budget, so re-running the workflow is the documented remedy.

## Files to Create

- `apps/web-platform/infra/cloudflare-provider-retry.test.sh` — drift guard asserting every `provider "cloudflare"` block in `apps/web-platform/infra/main.tf` carries `retries`, `min_backoff`, and `max_backoff` set above the v4 defaults (3/1/30). Auto-registered by the `run-registered-suites.sh` glob.

## Implementation Phases

### Phase 1 — Provider retry knobs

- `apps/web-platform/infra/main.tf`: add the trio to all six `provider "cloudflare"` blocks with the shared comment (`retries = 6`, `min_backoff = 15`, `max_backoff = 120`; cite #10643; note the v5 `max_retries` rename).
- `apps/cla-evidence/infra/main.tf`: same trio + comment on the one block.
- Verify: `terraform fmt -check` clean on both files; re-run the scratch-dir schema probe to confirm the three attribute names on the locked 4.52.7 schema.

### Phase 2 — Drift guards

- Create `apps/web-platform/infra/cloudflare-provider-retry.test.sh`: enumerate `provider "cloudflare"` blocks in `main.tf` (fail if the enumeration finds zero), and assert each contains all three attributes with values above the defaults.
- Extend `apps/cla-evidence/infra/main.test.sh` with the same presence/value assertions for its block.
- Verify: `bash apps/web-platform/infra/cloudflare-provider-retry.test.sh` green on the fixed tree; drive it red against each Guard Contract mutation row before commit.

### Phase 3 — Runbook + close-out

- Add the retry-semantics note to `apply-web-platform-infra-red-run.md`.
- Verification bundle: `terraform fmt -check`, both suites green, `git grep -c` census of the trio across provider blocks matching expectations (7 blocks total).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a wrong attribute name fails `terraform validate` in `infra-validation.yml` before merge; a too-shallow value would silently restore the status quo the guard now pins (that failure shape is what the Phase 2 suite exists to catch).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the change sets three non-secret integers on provider blocks; no credential, data, or billing surface moves.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** this is CI/ops reliability on an already-privileged infra surface (`meta/machinery`); the worst landing is a red apply run, identical to today's failure mode — no single user is harmed.

`threshold: none, reason: the only sensitive paths touched are `apps/*/infra/*.tf` provider-config and test files carrying three non-secret retry integers — no user-facing artifact, credential, or data surface changes hands.`

## Observability

```yaml
liveness_signal:
  what: "Apply web-platform infra workflow run conclusion on main (post-merge apply path)"
  cadence: "per merge to main touching apps/web-platform/infra/** or the workflow"
  alert_target: "operator email via the notify-apply-failure job"
  configured_in: ".github/workflows/apply-web-platform-infra.yml (notify-apply-failure job, #7586)"

error_reporting:
  destination: "GitHub Actions run log + notify-apply-failure email"
  fail_loud: "::error::terraform plan failed (exit $rc) — after the retry budget exhausts; pre-change this fired inside ~7s of upstream 504s, post-change it means the degradation outlasted ~8 min/request"

failure_modes:
  - mode: "Cloudflare API 5xx burst longer than the per-request retry budget"
    detection: "plan step exits non-zero → run goes red → notify-apply-failure email (existing)"
    alert_route: "operator email; remedy is the red-run runbook (re-run once upstream settles)"
  - mode: "retry attribute typo / invalid name"
    detection: "terraform validate fails in infra-validation.yml on the PR — before merge"
    alert_route: "PR author via red check"
  - mode: "a later edit drops the trio on one block or adds an unknobbed alias"
    detection: "cloudflare-provider-retry.test.sh (web-platform) and cla-evidence main.test.sh fail in CI"
    alert_route: "PR author via red check"

logs:
  where: "GitHub Actions run log for the apply job; cloudflare-go retry sleeps log via api.logger when TF_LOG is set"
  retention: "GitHub Actions retention (~90 days)"

discoverability_test:
  command: grep -cE '^[[:space:]]*retries[[:space:]]*=' apps/web-platform/infra/main.tf
  expected_output: "6"
```

## Encryption Posture

No new persistent store and no new cross-component connection is introduced — the change adds three integer attributes to existing provider blocks. Detection fired on the `\.tf$` file match, so the (unchanged) surfaces are declared for completeness:

```yaml
at_rest:
  - store: "terraform.tfstate in cloudflare_r2_bucket.terraform_state_privileged (existing, unchanged)"
    mechanism: "provider-managed: Cloudflare R2 encryption at rest"
    evidence: "Cloudflare R2 documentation, 'encryption at rest' attestation (developers.cloudflare.com/r2, retrieved 2026-10-20)"
    defends_against: "raw R2 object access exposing state contents (including the service-token secrets tunnel.tf stores)"
    does_not_defend: "possession of valid R2 credentials or the backend access key; Cloudflare-side authorized reads"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable — provider-side property, no customer-facing toggle to probe"
in_transit:
  - connection: "terraform/cloudflare-go → api.cloudflare.com (existing, unchanged; retry timing only)"
    enforced_at: "apps/web-platform/infra/main.tf provider blocks + cloudflare-go default HTTPS client"
    tls: "https / TLS 1.2+"
    cert_verification: "on (Go crypto/tls default verification; no InsecureSkipVerify configured anywhere in the provider path)"
    does_not_defend: "a leaked cf_api_token (credential theft is orthogonal to transport), a compromised local CA store"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — cloudflare-provider-retry drift guard

**Property.** Every `provider "cloudflare"` block in `apps/web-platform/infra/main.tf` and `apps/cla-evidence/infra/main.tf` carries `retries`, `min_backoff`, and `max_backoff` set above the v4 defaults (3 retries / 1s / 30s), so the 504-retry budget cannot silently re-shallow to ~7s per request.

**Assembly.** The complete set of `provider "cloudflare"` blocks across `apps/web-platform/infra/main.tf` and `apps/cla-evidence/infra/main.tf` — enumerated at suite run time by pattern, never hardcoded to the current count of seven: the suite must assert the enumeration found at least one block per file (a block census of zero is a suite failure, not a green vacuity) and then evaluate every enumerated member. The chokepoint is the file pair itself — Terraform has no second injection site for provider configuration.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete `retries = 6` from one of the six web-platform blocks | RED — one member missing one required attribute |
| 2 | Add a seventh `provider "cloudflare" { alias = "x"; api_token = var.x }` block with no retry trio | RED — a second member after compliant firsts must be checked |
| 3 | Comment out every `provider "cloudflare"` line in `main.tf` (enumeration finds zero blocks) | RED — the guard's own dispatch: "0 checked" must never read green |
| 4 | Harness: mutate the suite's expected attribute name to the v5 spelling `max_retries` | RED — proves the suite reads real file content, not its own expectation |
| 5 | Must-PASS, non-canonical: reorder the three attributes inside a block and change intra-line spacing | PASS — order/spacing are permitted variation |

**Anchor.** The asserted attribute names are validated against the *locked* provider schema — `terraform providers schema -json` on `cloudflare/cloudflare = 4.52.7` (registry-pinned, outside this commit) — so a weakening that renamed or invented attributes collides with the vendor contract, and `terraform validate` in `infra-validation.yml` reds on unknown names. A single diff could weaken both `main.tf` and the suite's expected literals; that residue is bounded by this contract's review requirement plus the zero-block census row above.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "retry the plan step's provider reads — either the Terraform provider retry knobs (`max_retries` on the cloudflare provider block / `CLOUDFLARE_RETRIES`-style env) or a bounded `plan` retry loop in the workflow step on a 504-classified failure" | main.tf trio on all six web-platform blocks + cla-evidence block (the first arm of the either/or) | mapped |
| 2 | "workflow-level retry loop is the fallback if provider-level retry doesn't cover data reads" | none — Alternative Approaches row documents it as the re-open condition | descoped — justification: vendored cloudflare-go v0.116.0 retries `StatusCode >= 500` on every call including reads; the fallback condition is falsified at source level |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `retries`/`min_backoff`/`max_backoff` on six web-platform provider blocks | "retry the plan step's provider reads … the Terraform provider retry knobs" | asked |
| Same trio on `apps/cla-evidence/infra/main.tf` | — | inferred — justification: identical provider + identical upstream failure class on a sibling root; fixing only the named root leaves a known-identical defect red on the next Cloudflare blip |
| `cloudflare-provider-retry.test.sh` + `main.test.sh` assertions | — | inferred — justification: the property otherwise rots silently (optional attributes absent = valid HCL); the enforcement contract needs a drift pin per `2026-09-07` guard learning |
| `apply-web-platform-infra-red-run.md` note | — | inferred — justification: the runbook is the responder's map for exactly this red-run class; its failure-arm framing changes meaning once plan calls self-retry for ~8 min |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `apps/cla-evidence`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

| Issue | Disposition |
|---|---|
| #9705 — review: dead-probe heartbeat for inngest wrong-volume alert (body mentions `apply-web-platform-infra`) | **Acknowledge** — unrelated heartbeat-evidence scope-out; this plan changes provider retry config, not alert probes. Remains open. |
| #7098 — ci: audit `run:` bodies whose `set` omits `-e` | **Acknowledge** — audits `run:` bodies repo-wide; this plan makes zero workflow `run:` changes, so it neither fixes nor worsens that scope-out. Remains open. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change on own CI machinery. Product/UX Gate: no user-facing surface in Files to Edit/Create (mechanical UI-surface scan: zero matches) → NONE. Domain-leader fan-out unavailable in this environment (no Task tool); semantic sweep performed inline.

## Acceptance Criteria

- [ ] Each of the six `provider "cloudflare"` blocks in `apps/web-platform/infra/main.tf` sets `retries = 6`, `min_backoff = 15`, `max_backoff = 120`, with a comment citing #10643 and noting the v5-era `max_retries` rename.
- [ ] The single `provider "cloudflare"` block in `apps/cla-evidence/infra/main.tf` sets the same trio with the same comment.
- [ ] `terraform fmt -check` exits clean on both edited `.tf` files.
- [ ] `apps/web-platform/infra/cloudflare-provider-retry.test.sh` exists, is picked up by the `run-registered-suites.sh` glob, passes on the fixed tree, and reds on each Guard Contract mutation row.
- [ ] `apps/cla-evidence/infra/main.test.sh` asserts the trio on its provider block and passes.
- [ ] The attribute names are verified against the locked 4.52.7 schema via the scratch-dir `terraform providers schema -json` probe (all three keys present).
- [ ] `.github/workflows/apply-web-platform-infra.yml` is unmodified (zero byte-budget spend); no `-target` list changes.
- [ ] `apply-web-platform-infra-red-run.md` documents the new ~8-min/request retry semantics.
- [ ] `git grep -cE 'retries[[:space:]]*='` across both `main.tf` files returns 7 (six web-platform + one cla-evidence provider block).

## Test Scenarios

- **unit** — Given the fixed `main.tf`, when `cloudflare-provider-retry.test.sh` runs, then all blocks report the trio above defaults and the suite prints its pass summary.
- **unit** — Given one block missing `retries` (mutation row 1), when the suite runs, then it fails naming that block.
- **unit** — Given a seventh alias block without the trio (row 2), when the suite runs, then it fails on the new member.
- **unit** — Given zero enumerable provider blocks (row 3), when the suite runs, then it fails on the census rather than exiting 0.
- **unit** — Given the suite's expected-name constant mutated to `max_retries` (row 4), when the suite runs on the unmodified fixed tree, then it still fails — proving the assertions read the file, not the fixture.
- **integration** — Given the branch, when `bash apps/web-platform/infra/run-registered-suites.sh` runs the infra leg, then the new suite is discovered and green.
- **integration** — Given a PR containing the change, when `infra-validation.yml` runs `terraform validate` on both roots, then both validate clean (the three attributes are in-schema on 4.52.7 — verified by the schema probe in Research Insights).
- **e2e (live, unschedulable)** — Given a real Cloudflare 5xx window post-merge, then the apply run's plan step survives multi-minute blips; cannot be scheduled — `pyramid-justified: requires a live upstream degradation no fixture can faithfully reproduce; covered by design verification (vendored retry loop) plus the run-level rerun remedy for sustained outages`.

## Success Metrics

- A subsequent transient Cloudflare API degradation (minutes-scale) produces no red `Apply web-platform infra` runs attributable to `HTTP 504` provider reads.
- The ~7-second default budget is gone from every cloudflare provider block; a red run on `HTTP 504` post-change means the outage exceeded ~8 min/request — the documented residual for `gh run rerun --failed`.

## Dependencies & Risks

- **Sustained outage > ~8 min/request still fails the plan** — bounded and intended; the run-level rerun and red-run runbook remain the remedy. The observed ~35-min window exceeded any reasonable in-request budget.
- **Retry on mutating calls** — a write that 504s post-commit can surface a duplicate-exists error on retry; visible and recoverable, never silent.
- **Provider-version drift** — a future v4 bump changing attribute semantics is caught by the schema-probe AC + the drift suite; a v5 migration must rename to `max_retries` (comment in main.tf warns; out of scope here).
- **No workflow changes** — the byte-budgeted workflow file is untouched; `terraform-target-parity.test.ts` unaffected (no `-target` list changes).

## References & Research

- Issue: #10643 (triage: p2-medium, type/bug, domain/engineering, meta/machinery)
- Failed run: 39364009152 on `main@57dda4c24`, ~03:30–04:05 UTC 2026-10-20
- `apps/web-platform/infra/main.tf:150-225` — the six `provider "cloudflare"` blocks
- `apps/web-platform/infra/tunnel.tf:135,143,186,199` — the four resources that failed
- `.github/workflows/apply-web-platform-infra.yml:435-691` — the `Terraform plan (allow-list, non-SSH resources only)` step
- `cloudflare-go` v0.116.0 `cloudflare.go` — retry loop (`StatusCode >= 500` → `continue` up to `MaxRetries`; post-exhaust error at ~line 270)
- Provider 4.52.7 docs — `retries`/`min_backoff`/`max_backoff`/`rps` attributes (env `CLOUDFLARE_RETRIES`/`CLOUDFLARE_MIN_BACKOFF`/`CLOUDFLARE_MAX_BACKOFF`)
- Learnings: `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`; `2026-09-07-my-guard-pinned-the-three-attributes-the-vendor-already-refuses.md`
- Runbook: `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md`
- Suite registration: `apps/web-platform/infra/run-registered-suites.sh` (ADR-252 glob); `infra-validation.yml` per-app `main.test.sh` hook
