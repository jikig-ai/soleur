---
title: "ops: separate the CI/eval Anthropic key from production and alert on credit exhaustion"
type: feat
date: 2026-09-23
slug: ops-separate-ci-eval-anthropic-key-credit-alert
branch: feat-one-shot-8505-ci-eval-anthropic-key
issue: 8505
closes: 8505
priority: p2
domain: operations
brand_survival_threshold: none
requires_cpo_signoff: false
---

# ops: separate the CI/eval Anthropic key from production and alert on credit exhaustion

## Enhancement Summary

**Deepened on:** 2026-09-23. **Reviewers:** runtime-claim verifier, terraform-architect,
security-sentinel, code-simplicity-reviewer. A reduced panel was used deliberately: the planning
subagent had just hit an API session limit (HTTP 429), so the fan-out was capped at 4.

### Key improvements
1. **The marker design is confirmed against source.** `reportSilentFallback(null, …)` takes the
   `captureMessage` branch, and `SilentFallbackOptions` carries `tags` (`observability.ts`,
   `SilentFallbackOptions`). `mirrorToSentry` has **no** `captureMessage` branch, so the message path
   is never duplicated. `Client.captureException` short-circuits on `checkOrSetAlreadyCaught`
   (`@sentry/core` 10.59.0). The probe calls `postAnthropicMessage` with `markerSource: CRON_NAME`, so
   moving the report into the transport keeps the probe covered.
2. **Terraform upsert is resolved.** `doppler_secret` Create *is* `resourceSecretUpdate` (a
   `ChangeRequest` upsert, provider v1.21.2), and `github_actions_secret` Create is
   `CreateOrUpdateRepoSecret` (PUT). No `import {}` block is needed. Phase 4.1 is closed.
3. **Precondition `error_message` must be static.** Terraform hard-errors when an `error_message`
   references a sensitive value, so no interpolation is allowed.
4. **Key custody hardened (security P1).** The MCP redact proxy is name-keyed (a11y-tree
   `- role "name": value` lines only) and has no content pattern for `sk-ant-…`. Any non-tree string
   returned or thrown by `browser_run_code_unsafe` passes unredacted. The capture script therefore
   wraps everything in `try/catch`, returns only a validated integer, and writes with
   `{mode: 0o600, flag: "wx"}` (atomic mode, no chmod TOCTOU). The pattern is added to
   `agent-browser/SKILL.md` §Credential safety.
5. **Distinctness script hardened (security P2).** Hash via stdin (`printf '%s' "$v" | sha256sum`,
   `printf` is a builtin), never as an argv of an external binary. The test asserts the synthesized
   value is absent from stdout **and** stderr.

### Review decisions (and what was not taken)
- **New ADR kept, not an ADR-033 amendment** (simplicity suggested amending). The ADR-033 amendment is
  claimed by sibling PR #8611, so amending it here would collide. The partition decision is also
  orthogonal to ADR-033's subject (cron spawn substrate).
- **Variables move to `infra/variables.tf`** (terraform-architect): all 51 root variables live there,
  and `seo-config-rules.test.ts` treats out-of-file variables as drift. Rebasing over #8611's append is
  a trivial conflict. AC7's `variables.tf` clause is dropped.
- **`value`, not the deprecated `plaintext_value`,** on `github_actions_secret` (6.12.1 marks
  `plaintext_value` `Deprecated: "Use value."`). The `supabase_access_token` precedent is left alone.
- **`-target` coverage** is enforced by `plugins/soleur/test/terraform-target-parity.test.ts`
  §"Non-SSH resource coverage (#5566)" (`expect(uncovered).toEqual([])`). No new parity test is needed.
- **C4, ledger row and runbook kept.** The C4 tests and the expense-ledger convention are repo gates.
  The runbook is written for this mint, with a short "reuse for #8614" note rather than a parameterized
  procedure (simplicity).
- **Scope boundary restated:** ~15 claude-eval subprocess crons pass the operator key into a spawned
  CLI and classify credit via `classifyEvalFatal`. They are not a new chokepoint here (Cut List), and
  the canary on the same balance pages within the hour.
- **Unverified:** that `frequency_minutes = 1440` is accepted by `jianyuan/sentry` 0.15.7. It is
  settled by `terraform validate` on the Sentry root in the work phase; fall back to the largest
  accepted value if rejected.
- **AC5 rewritten:** credit was topped up at ~15:05 UTC on 2026-09-23, so no live exhaustion exists
  post-merge.

## Overview

CI and manual eval runs (promptfoo grids, `claude-code-action` jobs, the `ci.yml` real-turn gates)
bill the same Anthropic key the production paths use. An eval run can therefore drain the org's
prepaid balance and take the production crons, the email-triage summarizer and the credit canary
down with it, and a CI-side leak exposes a production credential.

This plan does three things:

1. **Separate key, bounded spend.** Mint a CI/eval key inside a new Anthropic Console workspace
   (`soleur-ci-eval`) that carries a monthly **workspace spend limit**, so CI and evals can never take
   more than the cap from the org balance. The Console step is attempted with the plugin Playwright
   MCP. The only human action is the Console login, if the persistent browser profile has no live session.
2. **Terraform distributes it.** A new `apps/web-platform/infra/anthropic-ci-key.tf` writes the key
   into Doppler `ci/ANTHROPIC_API_KEY` and the GitHub Actions repo secret `ANTHROPIC_API_KEY`, and
   refuses (precondition) to write a value equal to the production key. A fingerprint script proves
   the acceptance criterion without printing any value.
3. **A named, routed credit-exhaustion marker.** Every production path that calls Anthropic with the
   operator key reports credit exhaustion under one Sentry marker
   (`feature=anthropic-credit`, `op=anthropic-credit-exhausted`, `source=<path>`), and a new
   `sentry_alert` emails the operator. The alert does not depend on the cron monitor, which is
   currently muted and has no alert workflow.

This unblocks #8497 (a powered B5 rerun needs a budget-isolated key) and the automated half of #8499.

## Research Reconciliation — Issue vs. Codebase

| Issue / brief claim | Reality (verified 2026-09-23) | Plan response |
|---|---|---|
| "CI/eval bill the same key as production" | **True.** `ANTHROPIC_API_KEY` has one SHA-256 fingerprint (`c95e2853ab74…`, len 108) across Doppler `ci`, `prd`, `prd_cla`, `prd_ghcr`, `prd_git_data`, `prd_kb_drift_walker`, `prd_scheduled`, `prd_terraform`, `prd_workspaces_luks`. `ci` holds its own literal copy; the `prd_*` branches inherit from `prd`. The GitHub repo secret `ANTHROPIC_API_KEY` (set 2026-07-30, not in Terraform) feeds `ci.yml`, `claude-code-review.yml`, `fix-constraints-stage-a.yml`, `scheduled-machinery-drain.yml` and `test-pretooluse-hooks.yml`. | Mint a new CI key; keep production's. Terraform takes ownership of both CI slots (Doppler `ci` and the GitHub secret). |
| Sibling #8611's plan: "credit exhausted → credit-probe heartbeat RED → operator email (existing)" | **False as a paging claim.** The Sentry monitor `scheduled-anthropic-credit-probe` is **muted** (`isMuted: true`, env production `status: error`). Its detector (id 1425262) has **`workflowIds: []`**, and so do **all 59** cron-monitor detectors in the org. No workflow emails on a monitor failure. | Route through a `sentry_alert` on the issue stream, which does not depend on the monitor's mute or workflow state. The fleet-wide monitor-routing gap is filed separately (see Deferrals). |
| The probe "calls reportSilentFallback op=anthropic-credit-exhausted" | **The call exists, but its tagged event never reaches Sentry.** In 30 days, Discover shows **0** events with `feature:cron-anthropic-credit-probe` and **569** credit-balance events, all tagged `feature=pino-mirror` with no `op` tag. Cause: `reportSilentFallback` runs `logger.error({err})` **before** `Sentry.captureException(err, {tags})`. The pino hook in `server/logger.ts` (`mirrorToSentry`) captures the same Error instance first, and `@sentry/core`'s `checkOrSetAlreadyCaught` (`__sentry_captured__`) then drops the second, tagged capture. | The new reporter uses the **message path** (`err = null`, so `captureMessage` runs and the pino hook has no `err` to capture). The tag-loss defect affects every Error-path `reportSilentFallback` in the fleet, so it gets its own issue (see Deferrals). |
| "credit balance is too low" observed in the production web-platform container on 2026-09-19 | **True, and there are two non-canary paths, not one.** WEB-PLATFORM-3X (`400 {…Your credit balance is too low…}`, frame `eS.generate` = Anthropic SDK `APIError.generate`, first seen 2026-09-19T14:52) is the email-triage summarizer (`server/email-triage/summarize.ts`, called from `email-on-received.ts`). WEB-PLATFORM-79 (`Anthropic API 400: …`) is the shared HTTP transport `postAnthropicMessage` (compound-promote, weekly-release-digest). Both reach Sentry only as `feature=pino-mirror` with the raw vendor body. | Report at the two choke points: the transport's non-ok branch in `_cron-shared.ts` and a try/catch around the SDK call in `summarize.ts`. |
| "Add a monitored marker (or Sentry mirror)" | The hourly canary already exists. It pages nothing today because of the two defects above. | Do not add a canary. Fix the report path and add the route. |
| "Mint a key with its own spend limit" | Anthropic has **no per-key spend limit**. Spend limits are **per workspace**, set on the workspace's *Spend limits* tab in the Console only; the Admin API can create workspaces but cannot set their limits (platform.claude.com/docs/en/manage-claude/workspaces, fetched 2026-09-23). The prepaid balance is **org-wide**, and org limits always apply. No `ANTHROPIC_ADMIN_KEY` exists in any Doppler config. | Create a workspace with a spend limit and mint the key inside it. This is Console-only, so it is the Playwright step. |

## Research Insights

**Premise validation (Phase 0.6).**
- #8505 is OPEN. #8497, #8499 and #8614 are OPEN. PR #8611 (`feat-anthropic-spend-reduction`) is OPEN, and its Files to Edit list was read so this plan stays out of its area.
- Cited paths exist on `origin/main` (20c6f2c149): `server/inngest/functions/cron-anthropic-credit-probe.ts`, `_cron-shared.ts` (`ANTHROPIC_CREDIT_EXHAUSTED_RE` at the "Single source of truth for the FATAL-class" block, `postAnthropicMessage`, `AnthropicApiError`), `server/email-triage/summarize.ts` (`summarizeEmail`), `infra/sentry/cron-monitors.tf` (`sentry_cron_monitor.scheduled_anthropic_credit_probe`, `failure_issue_threshold = 1`).
- The probe premise is **partially stale**: the canary runs and classifies correctly, but its marker is lost and its monitor routes to no one (evidence in the Reconciliation table).
- ADR corpus check: ADR-033 I2 ("operator ANTHROPIC_API_KEY only; never founder BYOK") and I8 (classify-fatal) stand. ADR-108 (cost-attribution markers) is unaffected. No ADR rejects per-consumer workspaces or keys.

**Property List (Phase 0.6b).**
- **P1.** The key CI and manual evals bill (Doppler `ci/ANTHROPIC_API_KEY` and the GitHub Actions secret `ANTHROPIC_API_KEY`) is not the key held by any `prd*` Doppler config, proven by fingerprint comparison without printing values.
- **P2.** CI/eval spend cannot take more than a fixed monthly amount from the org-wide prepaid balance.
- **P3.** A credit-exhaustion failure on any operator-key production path (canary, HTTP-transport crons, email-triage summarizer) reaches Sentry as one named marker that carries its originating source.
- **P4.** That marker notifies the operator, whatever the cron monitor's mute or workflow state.
- **P5.** The CI key reaches its consumer slots through Terraform, and the Console mint procedure can be reused by #8614.
- **P6.** The expense ledger records the CI workspace and its cap.

**Cut List (Phase 0.6b).**
- *New credit canary* → P3/P4 → the hourly `cron-anthropic-credit-probe` already probes. Only its report path and routing are broken.
- *New `SOLEUR_*` Better Stack marker plus logtail alert* → P3 → `reportSilentFallback` already writes the structured pino line (with `feature`/`op`) to Better Stack, and logtail alerts are #8611's area. The Sentry route covers P4.
- *Credit classification inside the claude-eval spawn substrate* → P3 → `classifyEvalFatal` already classifies it, `_cron-claude-eval-substrate.ts` is #8611's file, and the canary shares the same key and balance, so it reports the same exhaustion within the hour.
- *Classifying `domain-router.ts` / `agent-runner.ts`* → those calls use the **user's BYOK key**. A user's own exhausted credit is not operator exhaustion, and labelling it so would be a false page.
- *Rotating the production key now* → the key sat in GitHub secrets. #8614 mints a new spend-limited key for the prd crons, which retires this one. That work stays in #8614, and this plan adds a comment there naming the retirement (see Deferrals).
- *Fixing the fleet-wide tag loss in `reportSilentFallback`* → it would revive every dormant tag-filtered alert rule at once. That blast radius needs its own enumeration, so it gets a new issue. This plan's reporter does not depend on the fix.
- *Anthropic Admin API automation* → the Admin API cannot set workspace spend limits, and no admin key exists. The Console is the only route.

**Value-proposition measurement (Phase 0.6c).** No cost-saving claim. The cap is a ceiling, not a saving.

**Relevant files.**
- `apps/web-platform/server/observability.ts`: `reportSilentFallback` (the `logger.error` line comes before `captureException`, which is the tag-loss ordering).
- `apps/web-platform/server/logger.ts`: `mirrorToSentry` (captures `data.err` with `feature: "pino-mirror"`).
- `apps/web-platform/node_modules/@sentry/core/build/cjs/utils/misc.js`: `checkOrSetAlreadyCaught`.
- `apps/web-platform/infra/sentry/issue-alerts.tf`: 32 `sentry_alert`s. The email action convention is `target_type = "issue_owners"`, `fallthrough_type = "ActiveMembers"` (the BYOK rule's `NoOne` fallthrough resolves to nobody, per `sentry-byok-cap-alert-op-contract.test.ts`).
- `apps/web-platform/infra/sentry/alert-reference.json`: the reference `plan_pr` gates, read by `scheduled-sentry-alert-drift.yml`.
- `.github/workflows/apply-sentry-infra.yml`: a **full-root** plan; AC3 pins that no `-target=` exists, so the Sentry root needs no workflow edit.
- `.github/workflows/apply-web-platform-infra.yml`: an explicit `-target=` list. The new lines go directly after `-target=github_actions_secret.supabase_access_token`, away from the logtail block #8611 appends to.
- `apps/web-platform/infra/inngest.tf` (`github_actions_secret.supabase_access_token`): precedent for a TF_VAR-sourced GitHub secret. The value comes from Doppler `prd_terraform` through `doppler run --name-transformer tf-var`.
- `.github/actions/anthropic-preflight/action.yml`: soft-skips (`ok=false` plus `::warning::`) on HTTP 400 bodies matching `specified API usage limits|credit balance is too low`. Other 400 bodies fail the step loudly with the body shown.
- `apps/web-platform/scripts/*.test.sh`: auto-registered by `scripts/test-all.sh` `SUITE_GLOBS` (root `scripts/*.test.sh` is not).

**Institutional learnings applied.**
- `2026-07-10-shared-vendor-key-fingerprint-attribution-and-required-iac-secret-apply-gate.md`: fingerprint shared keys across configs, and a required no-default TF variable fails the whole auto-apply. That is why the new variables default to `""` and the resources are count-gated.
- `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`: `prd_*` branches inherit `prd`. `ci` is a separate environment root, so writing `ci` does not touch any `prd*` config.
- `best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md`: no `ignore_changes = [value]` on the new `doppler_secret`, so a hand edit of `ci` drifts and the next apply corrects it.
- `2026-05-15-sentry-iac-billing-and-quirks.md`: no new cron monitor is added (no seat cost). One `sentry_alert` is added.
- `2026-04-07-buttondown-onboarding-multi-account-playwright.md`: confirm the Console account and org before mutating. The runbook records the org id seen in the Console header.
- `agent-browser/SKILL.md` §"Credential safety": a freshly shown credential panel must be neither snapshotted unrouted nor screenshotted. Read the value into a 0600 file, use it, then shred it.

**External facts (cited).**
- Anthropic workspaces: per-workspace monthly spend limits exist (Console, *Spend limits* tab). You cannot set limits on the Default Workspace. Org limits always apply. The Admin API can create workspaces but has no spend-limit field. Service-account keys survive the removal of the creating user. Source: <https://platform.claude.com/docs/en/manage-claude/workspaces> (retrieved 2026-09-23).
- `@anthropic-ai/sdk` ^0.93.0: a 400 throws `BadRequestError` (a subclass of `APIError`) with `.status = 400`. `.message` is `"400 {json}"` and contains the vendor text; this matches WEB-PLATFORM-3X's title verbatim.
- `jianyuan/sentry` 0.15.7: native `event_frequency_count {interval, value}` (strict `>`; `value = 0` means at least 1 event) and `first_seen_event`. `frequency_minutes` values already taken: 5, 10–27, 30, 31, 60–63.
- `DopplerHQ/doppler` 1.21.2 and `integrations/github` 6.12.1 (pinned in `apps/web-platform/infra/.terraform.lock.hcl`). Whether `doppler_secret` create upserts an existing unmanaged `ci/ANTHROPIC_API_KEY`, or needs an `import {}` block, was **resolved at deepen**: both upsert on create (Enhancement Summary item 2).

**CLAUDE.md / AGENTS conventions carried.** `hr-all-infrastructure-provisioning-servers` (secrets through Terraform), `hr-tf-variable-no-operator-mint-default` (the justified exception is below), `hr-exhaust-all-automated-options-before` and `hr-never-label-any-step-as-manual-without` (Playwright attempt first), `hr-dev-prd-distinct-supabase-projects` (the distinctness pattern mirrored), `cq-silent-fallback-must-mirror-to-sentry`, `cq-test-fixtures-synthesized-only`, `hr-observability-as-plan-quality-gate`.

## Technical Approach

### Why the marker uses the message path

`reportSilentFallback(err: Error, …)` loses its `feature`/`op` tags in production because the pino
mirror captures the same Error instance first. `reportSilentFallback(null, {message, tags})` goes
through `Sentry.captureMessage`, and the pino hook only captures when `data.err instanceof Error`, so
nothing pre-empts it. The event keeps its tags and groups by the constant message into **one** Sentry
issue for all sources. This is deliberate. A code comment at the reporter cites the new tag-loss
issue, so the choice is not "fixed" back into the broken shape.

### Key custody during the mint

The Console shows a new key once. The value must go from the page to Doppler without entering the
transcript:

- **Primary.** Use `browser_run_code_unsafe` in the plugin Playwright MCP. The redact proxy is
  **name-keyed only** and does not catch a raw `sk-ant-…` string, so it is not a backstop here. The
  script reads the key element's text in the MCP's Node process, writes it with
  `fs.writeFileSync(path, v, {mode: 0o600, flag: "wx"})`, and wraps everything in `try/catch`, so that
  neither a thrown message nor the return value can carry the key. It returns only a validated integer
  byte length, or a fixed error code.
- **Fallback, if the run-code context cannot write files.** The documented `agent-browser` pattern:
  `agent-browser get text <sel>` redirected to the `0600` file.

Either way, a host-side one-liner then streams the file over stdin into Doppler
`prd_terraform/ANTHROPIC_API_KEY_CI` (the Terraform input slot, following the
`supabase_access_token` precedent), prints `sha256[:12]` of the file, and shreds it. No value is
echoed, screenshotted or snapshotted unrouted.

### Why an operator-minted TF variable is acceptable here

`hr-tf-variable-no-operator-mint-default` asks for a provider-side mint or credential reuse first.
Neither exists: there is no Anthropic Terraform provider, the Admin API cannot create API keys or set
workspace spend limits, and a reused key is exactly what this issue removes. Two mitigations cover the
rule's failure mode:

- `var.anthropic_api_key_ci` defaults to `""`, and both resources are `count`-gated on it, so an apply
  before the mint is a no-op rather than a failed auto-apply.
- A `lifecycle.precondition` refuses any value equal to the production key, or one without the
  `sk-ant-` prefix.

## Implementation Phases

### Phase 1 — Named credit marker (TDD: tests first, RED, then code)

1.1 **RED tests.**
- `apps/web-platform/test/server/anthropic-credit.test.ts` (new):
  - `isAnthropicCreditExhausted` returns true on the real body shapes (the SDK `"400 {…Your credit balance is too low…}"` message; the transport's scrubbed excerpt). It returns false on a 400 `invalid_request_error` with other text, on 429/500/529, and on `specified API usage limits` (a workspace or org cap is not an empty wallet; see Sharp Edges).
  - `reportAnthropicCreditExhausted({source})` calls `Sentry.captureMessage` exactly once with tags `{feature: "anthropic-credit", op: "anthropic-credit-exhausted", source}` and **never** calls `Sentry.captureException`.
  - A regression case wires the real `logger` plus a spy transport and asserts the tagged event survives (the pino hook has no `err` to pre-empt it).
- `apps/web-platform/test/server/inngest/cron-shared.test.ts`: `postAnthropicMessage` with a credit 400 reports once with `source = "cron:<markerSource>"` and still throws `AnthropicApiError`. A 429, a 500, or a non-credit 400 reports nothing.
- `apps/web-platform/test/server/email-triage/summarize.test.ts` (extend the existing suite, or create it at that path if absent): a `BadRequestError` carrying the credit text reports with `source = "email-triage"` and is rethrown unchanged (the caller's `retries: 1` semantics stay). A non-credit 400 does not report.
- `apps/web-platform/test/server/inngest/cron-anthropic-credit-probe.test.ts`: the credit case still returns `op: "anthropic-credit-exhausted"` and turns the heartbeat red. The probe no longer calls `reportSilentFallback` for credit itself; the transport reports once, so there is no double report. The auth-failure branch is unchanged.

1.2 **Code.**
- `apps/web-platform/server/anthropic-credit.ts` (new):
  - `ANTHROPIC_CREDIT_EXHAUSTED_RE` (moved here, and **re-exported** from `_cron-shared.ts` under the same name so `classifyEvalFatal` and its existing tests are untouched).
  - `isAnthropicCreditExhausted(text: string | undefined): boolean`.
  - `ANTHROPIC_CREDIT_EXHAUSTED_OP` / `…_FEATURE` literals.
  - `reportAnthropicCreditExhausted({ source, status? })`, which calls `reportSilentFallback(null, { feature, op, message: "Anthropic credit balance is too low — operator key exhausted", tags: { source }, extra: { status } })` and never forwards the vendor body.
  - A header comment cites the tag-loss issue.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts`: in `postAnthropicMessage`'s `!resp.ok` branch, when `isAnthropicCreditExhausted(rawBody)`, call `reportAnthropicCreditExhausted({ source: \`cron:${args.markerSource ?? "unknown"}\`, status: resp.status })` before the existing `throw`. Replace the regex definition with the re-export.
- `apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts`: drop the credit-branch `reportSilentFallback(new Error(…))` (the transport now emits the marker with `source=cron:cron-anthropic-credit-probe`). Keep the decision, `op` and heartbeat. Update the header comment's classification list.
- `apps/web-platform/server/email-triage/summarize.ts`: wrap `client.messages.create` in `try/catch`. On `err instanceof Anthropic.APIError && isAnthropicCreditExhausted(err.message)`, report with `source: "email-triage"`, then `throw err`.

### Phase 2 — Route the marker (Sentry IaC)

2.1 **RED.** `apps/web-platform/test/sentry-anthropic-credit-alert-op-contract.test.ts` (new, mirrors `sentry-byok-cap-alert-op-contract.test.ts`):
- Parse the `sentry_alert "anthropic_credit_exhausted"` block and assert its `feature`/`op` filter values equal the literals exported by `server/anthropic-credit.ts`. Read the source file; do not re-type the strings.
- Assert the action's `fallthrough_type` is `ActiveMembers`, not `NoOne`.
- Assert the triggers include both `first_seen_event` and `event_frequency_count`.

2.2 `apps/web-platform/infra/sentry/issue-alerts.tf`: add `sentry_alert.anthropic_credit_exhausted`.
- `monitor_ids = [data.sentry_project_issue_stream_monitor.web_platform.id]`.
- `trigger_conditions`: `first_seen_event`, `reappeared_event`, `regression_event`, and `event_frequency_count { interval = "1h", value = 0 }`.
- `action_match = "any"` semantics as in the siblings.
- Filter `logic_type = "all"` on `feature eq anthropic-credit` and `op eq anthropic-credit-exhausted`.
- Email action `issue_owners` / `ActiveMembers`.
- `frequency_minutes = 1440`, a free value. This re-pages at most once a day while exhaustion persists; an hourly page during a known outage is what got the canary monitor muted.
- Header comment: why message-path and why daily.

2.3 Regenerate `apps/web-platform/infra/sentry/alert-reference.json` with the same generator `plan_pr`'s reference gate uses (see `scheduled-sentry-alert-drift.yml` header / #8050), so the drift workflow's field diff stays green.

### Phase 3 — Fingerprint distinctness guard

3.1 **RED.** `apps/web-platform/scripts/anthropic-key-distinctness.test.sh` (new; auto-registered by `scripts/test-all.sh`). It uses a stub `doppler` on `PATH` serving **synthesized** values. Rows are in the Guard Contract below.

3.2 `apps/web-platform/scripts/anthropic-key-distinctness.sh` (new).
- Enumerate configs from `doppler configs -p soleur --json` and select `ci` plus every name matching `^prd($|_)`, derived rather than hard-coded.
- For each, read `ANTHROPIC_API_KEY` with `--plain` into a local variable and hash it via stdin (`printf '%s' "$v" | sha256sum`, where `printf` is a builtin). Never pass the value as an argument to an external binary, because it would land in argv/`ps`. Print `<config> <sha256[:12]>`, `<config> ABSENT`, or `<config> ERROR`.
- Exit 1 if `ci` is absent or equals any `prd*` fingerprint. Exit 2 on any Doppler error, or when fewer than one `prd*` config is enumerated (the anti-vacuity floor). Print `DISTINCT` and exit 0 otherwise.
- No `set -x`, no value on stdout or stderr, and `unset` after hashing.

### Phase 4 — Terraform wiring

4.1 **Upsert: resolved at deepen.** Both resources upsert on create (see Enhancement Summary item 2), so no `import {}` block is needed.

4.2 `apps/web-platform/infra/anthropic-ci-key.tf` (new; resources only). The two variables go in `infra/variables.tf` (repo convention, see Enhancement Summary):
- `variable "anthropic_api_key_ci"`: sensitive, default `""`. Sourced as `TF_VAR_anthropic_api_key_ci` from `prd_terraform/ANTHROPIC_API_KEY_CI`.
- `variable "anthropic_api_key"`: sensitive, default `""`. Already present as a TF_VAR because `prd_terraform` inherits `prd`'s `ANTHROPIC_API_KEY`. It is read **only** by preconditions, so it never lands in state.
- `locals { ci_key_set = nonsensitive(var.anthropic_api_key_ci != "") }`.
- `doppler_secret.ci_anthropic_api_key`: `count = local.ci_key_set ? 1 : 0`; `project = "soleur"`, `config = "ci"`, `name = "ANTHROPIC_API_KEY"`, `visibility = "masked"`, and **no** `ignore_changes`.
- `github_actions_secret.anthropic_api_key`: same count; `repository = "soleur"`, `secret_name = "ANTHROPIC_API_KEY"`, `value = var.anthropic_api_key_ci` (not the deprecated `plaintext_value`).
- Both carry `lifecycle { precondition { condition = var.anthropic_api_key_ci != var.anthropic_api_key && startswith(var.anthropic_api_key_ci, "sk-ant-")  error_message = "<static text, no interpolation>" } }`. An `error_message` that references either sensitive variable makes `terraform plan` hard-error.

4.3 `.github/workflows/apply-web-platform-infra.yml`: add `-target=doppler_secret.ci_anthropic_api_key` and `-target=github_actions_secret.anthropic_api_key` directly after `-target=github_actions_secret.supabase_access_token`. Coverage is enforced by `plugins/soleur/test/terraform-target-parity.test.ts` §"Non-SSH resource coverage (#5566)"; run it. `scheduled-terraform-drift.yml` plans the full root and re-evaluates the precondition each run, which is benign with static inputs.

### Phase 5 — Console mint (Playwright first) and the reusable runbook

5.1 Write `knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md` (new).
- **Parameters:** workspace name, monthly spend limit, alert threshold (80%), key name, Doppler TF-input slot, Terraform resources.
- **Records:** the Console-observed org id, workspace id (`wrkspc_…`), key id/name (never the value), the fingerprint, and who set the limit and when.
- **Steps:**
  1. Open the Console with the plugin Playwright MCP (persistent profile `soleur-playwright-mcp-profile`). If it is not signed in, the login is the single human action.
  2. *Settings → Workspaces → Create workspace*.
  3. *Spend limits* tab → monthly cap plus an alert.
  4. Create a **service-account** key scoped to that workspace (it survives user removal), falling back to a workspace key if service accounts are unavailable on the plan.
  5. Capture the value per "Key custody" above.
  6. Dispatch the apply, then run the fingerprint script.
- **Revocation:** archive the key in the Console, or archive the workspace to revoke all its keys.
- **#8614 reuse:** the same steps with workspace `soleur-prd-cron`, its own limit, and slot `prd_terraform/ANTHROPIC_API_KEY` handling as #8614 decides.

5.2 Run the runbook. Follow `plugins/soleur/skills/agent-browser/SKILL.md` §Credential safety for every snapshot on the key panel; screenshots of that panel are forbidden.
- Workspace `soleur-ci-eval`, monthly limit **$100** (CFO: floor $75, since one B5-sized grid is $48.85; treat the limit as a ceiling, not a budget), alert at 80%.
- Precondition check before any mutation: the Console header's org matches the org whose cost report the existing ADR-108 surface names. If it cannot be established, stop at the login gate.

5.3 If the Console step cannot finish in-session (the MCP is unavailable, or login cannot be completed), do not label it manual. Per `hr-ship-message-no-operator-checklist`, `soleur:ship` files a follow-through issue with an `auto_command:` block generated by `soleur:operator-bootstrap`, covering: the runbook steps, the slot write, `gh workflow run apply-web-platform-infra.yml`, and `bash apps/web-platform/scripts/anthropic-key-distinctness.sh`. The count-gated Terraform keeps merge safe either way.

### Phase 6 — Ledger, eval-harness pointer, ADR, C4

6.1 `knowledge-base/operations/expenses.md`, row 57 only ("Anthropic API (CI)"):
- Amount stays `0.00`, status stays `unmetered`. A cap is not a measurement, so the R&D subtotal and the operator-digest run-rate are unchanged (CFO).
- Add to notes: the `soleur-ci-eval` workspace, the $100/mo spend limit as an upper bound, and the promptfoo eval-harness as a draw surface. Refresh the stale `verify_by`.
- Add one row to "Vendor account limits": `Anthropic ci-eval workspace spend limit | $100/mo | 2026-09-23`.
- Bump `last_updated`.
- **Do not** touch `knowledge-base/finance/cost-model.md` (#8611's file; no figure changes).

6.2 `plugins/soleur/skills/eval-harness/README.md` Prerequisites: run eval grids under `doppler run -p soleur -c ci --` so manual evals bill the capped workspace, never a `prd*` key.

6.3 ADR (provisional **ADR-243**; the ordinal is re-verified by `soleur:ship`'s ADR-Ordinal Collision Gate, and #8611 claims ADR-241), *"Anthropic keys are partitioned by blast radius into spend-limited Console workspaces"*. It records:
- Decision: one workspace per consumer class (ci-eval now; prd-cron in #8614), each with a monthly spend limit; Terraform distributes each key from a `prd_terraform` input slot; the org balance stays shared.
- Alternatives considered: separate key in the Default Workspace (no cap possible; rejected); separate Anthropic org (separate billing; overkill); Admin API automation (cannot set limits; no admin key).
- Consequences: a workspace-cap hit is a distinct, soft-skipped CI failure class.

6.4 C4 (`knowledge-base/engineering/architecture/diagrams/`):
- `model.c4`: amend the `anthropic` description to state the workspace partition. Add `github -> anthropic "CI Claude turns (claude-code-action, ci.yml real-turn gates) on the ci-eval workspace key — spend-limited, never a prd key"` and `evalharness -> anthropic "promptfoo eval grids on the ci-eval workspace key (Doppler ci)"`.
- `views.c4`: add `anthropic` to the `components of platform.plugin` view include, so the `evalharness` edge renders.
- Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

## Files to Create

- `apps/web-platform/server/anthropic-credit.ts`
- `apps/web-platform/test/server/anthropic-credit.test.ts`
- `apps/web-platform/test/sentry-anthropic-credit-alert-op-contract.test.ts`
- `apps/web-platform/scripts/anthropic-key-distinctness.sh`
- `apps/web-platform/scripts/anthropic-key-distinctness.test.sh`
- `apps/web-platform/infra/anthropic-ci-key.tf`
- `knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md`
- `knowledge-base/engineering/architecture/decisions/ADR-243-anthropic-keys-partitioned-by-spend-limited-workspace.md` (ordinal provisional)
- `apps/web-platform/test/server/email-triage/summarize.test.ts` (verified at deepen: no summarizer suite exists)

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` (the regex re-export; the credit report in the `postAnthropicMessage` non-ok branch)
- `apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts`
- `apps/web-platform/server/email-triage/summarize.ts`
- `apps/web-platform/test/server/inngest/cron-shared.test.ts`
- `apps/web-platform/test/server/inngest/cron-anthropic-credit-probe.test.ts`
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`
- `.github/workflows/apply-web-platform-infra.yml` (two `-target=` lines only)
- `knowledge-base/operations/expenses.md` (row 57, one vendor-limits row, `last_updated`)
- `plugins/soleur/skills/eval-harness/README.md` (Prerequisites line only; no `description:` edit, so the budget check does not apply)
- `plugins/soleur/skills/agent-browser/SKILL.md` (§Credential safety: add the `browser_run_code_unsafe` capture pattern; the redact proxy does not cover run-code output)
- `apps/web-platform/infra/variables.tf` (append `anthropic_api_key_ci` and `anthropic_api_key`, both sensitive with `default = ""`)
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`

**Not edited (sibling #8611's area):** `_cron-claude-eval-substrate.ts`, `claude-cost-marker.ts`, `model-tiers.ts`, `app/api/inngest/route.ts`, `infra/betterstack-logs-alerts.tf`, `infra/main.tf` (`infra/variables.tf` is shared: append only, then rebase), `infra-validation.yml`, `scheduled-terraform-drift.yml`, `knowledge-base/finance/cost-model.md`, the ADR-033 amendment.

## Open Code-Review Overlap

1 open code-review issue touches these files:
- **#7098** (audit `run:` bodies whose `set` omits `-e`): names `apply-web-platform-infra.yml`. **Acknowledge.** This plan adds two `-target=` argument lines and no `run:` body shell, so it is a different concern.

## Infrastructure (IaC)

### Terraform changes

- **New** `apps/web-platform/infra/anthropic-ci-key.tf` in the existing web-platform root (R2 backend already configured). Providers are already pinned: `DopplerHQ/doppler` 1.21.2 and `integrations/github` 6.12.1 (App auth per `hr-github-app-auth-not-pat`).
- **Sensitive variables:**
  - `TF_VAR_anthropic_api_key_ci`, from Doppler `prd_terraform/ANTHROPIC_API_KEY_CI`, written by the Phase 5 capture.
  - `TF_VAR_anthropic_api_key`, already delivered by `prd_terraform`'s inheritance of `prd`; used only in preconditions.
- **New** `sentry_alert.anthropic_credit_exhausted` in `apps/web-platform/infra/sentry/issue-alerts.tf` (Sentry root, full-root apply by `apply-sentry-infra.yml` on merge).

### Apply path

- **Web-platform root:** auto-apply on merge through `apply-web-platform-infra.yml` with the two new `-target=` lines, then a `workflow_dispatch` re-apply once the slot is filled (if the mint lands after merge). Before the mint, count = 0, so the change is a no-op with no downtime. When created, the GitHub secret switches CI to the capped key on the next workflow run.
- **Blast radius:**
  - If the cap is hit, CI Claude steps soft-skip with a visible `::warning::`.
  - If the new key is revoked, CI Claude steps fail loud.
  - Production is untouched; no `prd*` config is written.
- **Sentry root:** full-root apply on merge. It creates one alert with no replacement of existing rules.

### Distinctness / drift safeguards

- **Precondition:** the CI value is not equal to the prd value, and it starts with `sk-ant-`.
- **Fingerprint script:** `apps/web-platform/scripts/anthropic-key-distinctness.sh` covers every `prd*` config, including ones Terraform does not see.
- **No `ignore_changes`** on `doppler_secret.ci_anthropic_api_key`: a hand edit of `ci` shows as drift and is reverted by the next apply.
- **State:** the CI key value lands in the web-platform `terraform.tfstate` (encrypted R2 backend; see Encryption Posture). The production key does not, because preconditions are not persisted.

### Vendor-tier reality check

- **Sentry:** `sentry_alert` has no seat cost (only cron monitors are seat-billed), and no monitor is added.
- **Anthropic:** workspaces are free (up to 100 per org). Spend limits are Console-only and cannot be set on the Default Workspace, which is why a new workspace is required.

## Observability

```yaml
liveness_signal:
  what: "cron-anthropic-credit-probe hourly 1-token canary (existing) — on exhaustion the shared transport now emits the named Sentry event feature=anthropic-credit op=anthropic-credit-exhausted source=cron:cron-anthropic-credit-probe"
  cadence: "hourly at :47 UTC"
  alert_target: "operator email via sentry_alert.anthropic_credit_exhausted (issue_owners, fallthrough ActiveMembers), at most once per 24h while exhaustion persists"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (sentry_alert.anthropic_credit_exhausted); apps/web-platform/server/anthropic-credit.ts (reportAnthropicCreditExhausted)"

error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) via reportSilentFallback(null, …) -> Sentry.captureMessage (layer: sentry-correlation); the same call's pino line reaches Better Stack source 2457081 (layer: pino)"
  fail_loud: "Sentry issue titled 'Anthropic credit balance is too low — operator key exhausted' with tags feature=anthropic-credit, op=anthropic-credit-exhausted, source=<cron:NAME|email-triage>"

failure_modes:
  - mode: "operator (prd) key credit exhausted"
    detection: "canary 400 body + transport/summarizer classifier -> named Sentry event"
    alert_route: "sentry_alert.anthropic_credit_exhausted -> operator email"
  - mode: "email-triage summarizer hits exhausted credit on an inbound email"
    detection: "summarize.ts catch -> reportAnthropicCreditExhausted(source=email-triage)"
    alert_route: "same sentry_alert -> operator email"
  - mode: "ci-eval workspace spend limit reached"
    detection: "anthropic-preflight 400 'specified API usage limits' -> ::warning:: annotation and ok=false; any other 400 body fails the step with the body shown"
    alert_route: "GitHub Actions run annotation (visible, not paged — the cap binding is intended behavior)"
  - mode: "ci key drifts back to equal a prd key (hand edit)"
    detection: "apps/web-platform/scripts/anthropic-key-distinctness.sh exits 1; terraform plan shows drift on doppler_secret.ci_anthropic_api_key"
    alert_route: "scheduled-terraform-drift issue for the TF-visible slot; the script at ship/post-merge for all prd* configs"

logs:
  where: "Better Stack Logs source 2457081 (soleur-inngest-vector-prd): app container pino ERROR lines with feature/op/source; Sentry issue stream for the named event"
  retention: "Better Stack source retention (hot + S3 archive); Sentry project retention"

discoverability_test:
  command: "bash apps/web-platform/scripts/anthropic-key-distinctness.sh"
  expected_output: "DISTINCT"
  credentials_required: "Doppler read on soleur/ci and every soleur/prd* config — the property is an equality comparison of secret values, and no unauthenticated endpoint exposes a secret or its hash"
```

## Encryption Posture

```yaml
at_rest:
  - store: "doppler_secret.ci_anthropic_api_key (Doppler soleur/ci) and Doppler soleur/prd_terraform ANTHROPIC_API_KEY_CI"
    mechanism: "provider-managed:Doppler-SOC2-Type-II"
    evidence: "Doppler security & compliance page https://www.doppler.com/security (retrieved_on 2026-09-23)"
    defends_against: "a seized or leaked Doppler storage medium or backup"
    does_not_defend: "a leaked Doppler service/personal token with read on ci or prd_terraform; a CI job that prints its env"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: vendor-internal storage; only the attestation is observable"
  - store: "github_actions_secret.anthropic_api_key (repo jikig-ai/soleur)"
    mechanism: "provider-managed:GitHub-Actions-secrets-libsodium-sealed-box"
    evidence: "https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions (retrieved_on 2026-09-23)"
    defends_against: "reading the secret through the API or UI once set; storage-medium exposure"
    does_not_defend: "any workflow step with secrets access exfiltrating the env value (a malicious action or a compromised dependency in a job that receives the secret)"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: GitHub never returns secret values"
  - store: "web-platform terraform.tfstate (R2 backend) holding var.anthropic_api_key_ci via the two resources"
    mechanism: "provider-managed:Cloudflare-R2-SOC2-Type-II"
    evidence: "the existing R2 backend attestation row used by the web-platform root (Cloudflare R2 encrypts objects at rest, AES-256; https://developers.cloudflare.com/r2/reference/data-security/, retrieved_on 2026-09-23)"
    defends_against: "R2 storage-medium exposure"
    does_not_defend: "a leaked R2 access key or any principal allowed to run terraform state pull"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: vendor-internal storage"
in_transit:
  - connection: "terraform (GitHub runner) -> Doppler API / GitHub API"
    enforced_at: "apps/web-platform/infra/main.tf (provider \"doppler\", provider \"github\" — HTTPS endpoints, default TLS verification)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised runner reading the value in process memory"
    disclosed_as: "not-publicly-claimed"
  - connection: "capture host -> Doppler API (slot write over stdin)"
    enforced_at: "knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md (capture step; Doppler CLI HTTPS)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a compromised operator host during the few seconds the 0600 scratch file exists"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — CI/prd Anthropic key distinctness script

**Property.** No `prd*` config in Doppler project `soleur` holds the same `ANTHROPIC_API_KEY` as the `ci` config, and a run that could not read every config never reports success.

**Assembly.** The single chokepoint is the config enumeration inside `anthropic-key-distinctness.sh`: every compared member flows from `doppler configs -p soleur --json`, filtered by `^prd($|_)`, plus `ci`. No hard-coded list. The comparison loop covers every enumerated member, and exit status is a function of the full loop, not of the first match.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Stub serves `ci` equal to `prd` | RED (exit 1) |
| 2 | Stub `doppler configs` returns zero `prd*` configs (the guard's own dispatch enumerates nothing) | RED (exit 2, not `DISTINCT`) |
| 3 | `prd` distinct, then a second member `prd_scheduled` equal to `ci` | RED (exit 1) |
| 4 | Stub `doppler secrets get` fails (non-zero) for one `prd*` config | RED (exit 2) |
| 5 | `ci` ABSENT | RED (exit 1) |
| 6 | Script edited to hard-code `prd` only and a new `prd_new` branch equals `ci` | RED via row 3's fixture shape (a derived list catches it; a hard-coded one does not) |

**Harness rows.** (a) Must-PASS: every config distinct, and a `prd_x` config that is ABSENT (the contract permits a `prd*` config without the key) → exit 0 with `DISTINCT`. (b) A suite edit that stubs `doppler` to always succeed with identical hashes must turn row 1's expectation red; the suite asserts the exit **code and** the `DISTINCT` literal, and fails on `0 passed`. (c) The suite asserts neither stdout nor stderr contains the synthesized value (`sk-ant-test-…`), and the script header states "no `set -x`".

**Anchor.** The script reads live Doppler state at run time. No stored hash exists to drift with it.

### Guard 2 — Credit marker reaches a routed Sentry rule

**Property.** Every operator-key credit-exhaustion 400 on a production path produces a Sentry event whose `feature`/`op` tags equal the filter of an enabled `sentry_alert` with an email action that resolves to a person.

**Assembly.** There are **two** emit chokepoints: `postAnthropicMessage`'s non-ok branch (`_cron-shared.ts`), which covers the canary, compound-promote and weekly-release-digest, and the `summarize.ts` catch, which covers the only SDK caller of the operator key. Both call the one reporter in `server/anthropic-credit.ts`, which owns the tag literals. The routing side is one resource block, `sentry_alert.anthropic_credit_exhausted`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename `op` literal in `anthropic-credit.ts` only | RED (op-contract test) |
| 2 | Reporter switched to `reportSilentFallback(new Error(…))` (the Error path, which loses its tags to the pino-mirror pre-capture) | RED (reporter test: `captureException` called / tags absent in the real-logger case) |
| 3 | Transport reports, but `summarize.ts` catch removed (the second chokepoint) | RED (summarize test) |
| 4 | Alert action `fallthrough_type = "NoOne"` | RED (op-contract test) |
| 5 | Classifier widened to report on `specified API usage limits` | RED (classifier test: a cap is not an empty wallet) |
| 6 | Probe keeps its own credit report AND the transport reports (double event) | RED (probe test: exactly one report) |

**Harness rows.** (a) Must-PASS: a 400 whose body is a non-credit `invalid_request_error` → no report, and the error is still rethrown. (b) The op-contract test reads the literal from the source module; a suite edit that re-types the string inline must be caught by a self-check asserting the imported value is non-empty and appears in the TF block exactly once.

**Anchor.** The tag literal and the TF filter are separate files in one diff. The integrity anchor outside the commit is `alert-reference.json`, gated by `plan_pr` against the Terraform plan, plus the live `scheduled-sentry-alert-drift` field diff.

### Guard 3 — Terraform precondition

**Property.** Terraform never writes a CI Anthropic key equal to the production key into Doppler `ci` or the GitHub secret.

**Assembly.** Both resources in `anthropic-ci-key.tf` carry the same precondition. No other Terraform resource writes either slot (grep `ANTHROPIC_API_KEY` across `*.tf` at implementation time and assert exactly these two writers).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `terraform plan` with `TF_VAR_anthropic_api_key_ci == TF_VAR_anthropic_api_key` (synthesized values, local `-target` plan against a stub backend or `terraform validate` plus a `terraform console` evaluation) | RED (precondition error) |
| 2 | Precondition removed from the second resource only | RED (grep assertion that both resources carry it) |
| 3 | Value without `sk-ant-` prefix | RED |

**Harness rows.** Must-PASS: two distinct synthesized `sk-ant-` values plan cleanly, and an empty CI value yields count 0 (no error). This is verified in the work phase and recorded in the PR body. The web-platform root has no `terraform test` harness, and `infra-validation.yml` is #8611's file, so no new CI suite is registered.

**Anchor.** Guard 1 checks live Doppler independently of this precondition.

## Architecture Decision (ADR/C4)

### ADR

Create provisional **ADR-243**, *Anthropic keys are partitioned by blast radius into spend-limited Console workspaces* (Phase 6.3), through `soleur:architecture`. The ordinal is re-verified at ship.

### C4 views

All three model files were checked. `anthropic` is modelled as an external system with edges from `engine` (BYOK), `claude` and `api` (Admin cost report).

- **Missing actor/system edges:** `github -> anthropic` (CI Claude turns) and `platform.plugin.evalharness -> anthropic` (eval grids).
- **Stale description:** `anthropic`'s description does not state the key/workspace partition.
- **Views:** the `components of platform.plugin` view does not include `anthropic`, so the evalharness edge would not render.
- **Unchanged:** Doppler is already modelled (`doppler -> engine`, `github -> doppler` token-drift), and no new container or data store is added.

The edits are in Phase 6.4, followed by the C4 syntax, render and count-parity tests.

### Sequencing

The ADR describes the state after the mint. If the mint slips post-merge (Phase 5.3), the ADR carries `status: adopting` until the fingerprint script prints `DISTINCT`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The operator key serves only operator-owned automation (Inngest crons, triage of the operator's inbox, the canary). End users run on their own BYOK keys (`agent-runner.ts` → `domain-router.ts`). The operator-visible failure would be CI Claude steps failing or soft-skipping, or a credit-exhaustion email that never arrives (today's state).
- **If this leaks, the user's workflow is exposed via:** no user data. A leaked CI key exposes up to the $100/month workspace cap of operator spend. A leaked production key is no longer reachable from CI once the GitHub secret switches.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: every touched path (operator-key transport, the operator inbox summarizer, CI secrets, Sentry routing) serves operator-owned automation, while end-user agent traffic bills the user's own BYOK key and never reads ANTHROPIC_API_KEY.`

## Acceptance Criteria

- [ ] **AC1 (P1).** `bash apps/web-platform/scripts/anthropic-key-distinctness.sh` prints `DISTINCT` and exits 0 against live Doppler after the mint and apply. Its per-config lines show the `ci` fingerprint differing from every `prd*` fingerprint (all 9 today, enumerated dynamically). The output is pasted into the PR body; no value appears.
- [ ] **AC2 (P1).** `terraform state list` (via the apply workflow log) shows `doppler_secret.ci_anthropic_api_key[0]` and `github_actions_secret.anthropic_api_key[0]`. `gh secret list` shows `ANTHROPIC_API_KEY` updated on or after the apply date.
- [ ] **AC3 (P2).** The runbook's record block names the workspace id (`wrkspc_…`), the $100/month spend limit and the 80% alert. A 1-token call with the CI key returns `anthropic-workspace-id` equal to that workspace id. The call is made in a subshell reading the key from Doppler `ci`, printing only the header.
- [ ] **AC4 (P3).** The unit, transport, summarizer and probe suites from Phase 1 pass. The real-logger regression case shows the tagged event survives.
- [ ] **AC5 (P3/P4).** The operator topped up credit at ~15:05 UTC on 2026-09-23 (a 1-token prd canary returned HTTP 200 at 15:06), so no natural exhaustion event is available post-merge. AC5 is therefore: (a) the unit-level evidence of AC4, including the real-logger case, plus (b) post-merge, the credit-probe run at the next :47 completes green and Sentry Discover shows **0** new `feature:pino-mirror` credit events after that run (recorded query count, not eyeballed). The first live marker is observed at the next real exhaustion; it is not simulated against production.
- [ ] **AC6 (P4).** `sentry_alert.anthropic_credit_exhausted` exists live, enabled, with `fallthroughType: ActiveMembers`. It is verified by the `scheduled-sentry-alert-drift` reference diff being green after apply, and by the op-contract test.
- [ ] **AC7 (P5).** `.github/workflows/apply-web-platform-infra.yml` contains exactly the two new `-target=` lines. `git diff origin/main -- apps/web-platform/infra/main.tf knowledge-base/finance/cost-model.md` is empty. `terraform-target-parity.test.ts` is green.
- [ ] **AC8 (P6).** `expenses.md` row 57 names `soleur-ci-eval`, the $100/month cap and the eval-harness surface. The amount stays `0.00`. The vendor-limits table carries the new row.
- [ ] **AC9.** The ADR file exists at its final ordinal. The C4 edits render. `c4-code-syntax`, `c4-render` and `c4-count-parity` are green.
- [ ] **AC10.** The two deferral issues (tag loss; cron-monitor routing) are filed and linked in the PR body, and #8614 carries a comment naming the production-key retirement.

## Domain Review

**Domains relevant:** Engineering, Operations, Finance

### Engineering (CTO lens: carried in this plan)

**Status:** reviewed
**Assessment:** The architectural decision is the per-consumer workspace partition (ADR-243). The high-leverage correctness finding is the fleet-wide `reportSilentFallback` tag loss, which is deferred with evidence and sidestepped locally by the message path. The work stays out of #8611's substrate and budget files.

### Operations

**Status:** reviewed
**Assessment (COO):** Mint the key and fill the slot before merge where possible; the count gate makes either order safe. Put the runbook next to the other rotation runbooks, recording org, workspace id, limit, key id and fingerprint, with the login as the only human step and a revocation section, reusable by #8614 by changing name, limit and slot. Rotate the old production key inside #8614 on a firm date, since it sat in repo secrets. Keep the ledger amount at `0.00 unmetered` and record the cap. Noted but out of scope: the Doppler row in `expenses.md` under-lists configs.

### Finance

**Status:** reviewed
**Assessment (CFO):**
- **Cap:** $100/month is sound as a ceiling (floor $75, since one B5 grid is $48.85). A second full grid in the same month will hit it, and CI Claude steps then soft-skip with a visible warning. Set an 80% workspace alert.
- **Ledger:** row 57 stays `0.00 unmetered`, so `cost-model.md` needs no edit.
- **Balance:** the prepaid balance is org-wide. The cap limits CI's share but gives production no reserve. Production's own ~$430/month draw can still exhaust it, and topping up or auto-reload is outside this PR.

### Product/UX Gate

Not applicable. No UI-surface file is in Files to Create or Files to Edit, and the mechanical override did not fire.

## Test Scenarios

- **Classifier.** Credit body → true; non-credit 400 → false; `specified API usage limits` → false; 429/500/529 → false.
- **Transport.** Credit 400 → one report plus a thrown `AnthropicApiError`; the network error path (redacted rethrow) → no report.
- **Summarizer.** `BadRequestError` credit → report plus rethrow; a non-`APIError` throw → no report plus rethrow.
- **Probe.** Credit → one marker (from the transport), a red heartbeat and `op` returned; auth failure → unchanged path.
- **Op contract.** Literal parity, `ActiveMembers`, triggers present.
- **Distinctness script.** The Guard 1 matrix plus harness rows.
- **Terraform.** Guard 3 rows (work-phase evidence in the PR body).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Separate key in the Default Workspace | No spend limit can be set on the Default Workspace, so P2 fails. |
| Terraform `data "doppler_secrets" "ci"` as the source of the GitHub secret | Puts all 25 `ci` secrets into state, which the repo avoids for the same reason it avoids a `prd` data-source mirror (`inngest-betterstack-token.tf` header). It also gives no drift correction on `ci`. |
| Fix the fleet tag loss in `reportSilentFallback` here | It revives every dormant tag-filtered alert at once. The blast radius needs its own enumeration (deferral issue). |
| Unmute the credit-probe monitor | Its detector has no workflow, so unmuting still pages no one. The new alert is independent of it. |
| New Better Stack logtail alert on the credit literal | That is #8611's file, and it duplicates the Sentry route. |

## Deferrals (tracking issues, filed at plan finalization)

1. **reportSilentFallback Error-path events lose their feature/op tags.** The pino mirror pre-captures the same Error instance, and `@sentry/core` `checkOrSetAlreadyCaught` drops the tagged capture. Evidence: 0 of 569 credit events carry the probe's tags in 30 days. Re-evaluate: before any new tag-filtered `sentry_alert` on an Error-path emitter. The fix needs an enumeration of the rules it revives.
2. **Cron-monitor failures route to no alert workflow.** All 59 monitor detectors have `workflowIds: []`, and 5 monitors are muted (credit-probe, follow-through, bug-fixer, daily-triage, content-generator). Re-evaluate: when any cron's health is expected to page via its monitor.
3. **#8614 comment.** Its new workspace key retires the production key that sat in GitHub Actions secrets. Rotate on #8614's first funded window.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it with `none` and a reason.
- `specified API usage limits` (org or workspace cap) is **not** credit exhaustion. Do not widen `ANTHROPIC_CREDIT_EXHAUSTED_RE`. A cap hit on the CI key is intended behavior and must never page as "operator credit exhausted".
- Never switch the reporter to an `Error` argument "for a stack trace". That is the exact shape that loses tags (Guard 2 row 2).
- `count` on a sensitive-derived boolean needs `nonsensitive()`. Do not use `for_each` with it.
- The production key is available to Terraform as `TF_VAR_anthropic_api_key` only through `prd_terraform`'s inheritance. Never reference it in a resource argument, or it lands in state.
- On the Console key panel, route every snapshot through the redactor and never take a screenshot. The value leaves the page only into the `0600` scratch file.
- The ADR ordinal is provisional. Sweep plan, tasks and the ADR filename together if it moves.
