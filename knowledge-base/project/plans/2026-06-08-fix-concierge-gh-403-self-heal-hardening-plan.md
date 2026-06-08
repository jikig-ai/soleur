---
title: "Fix Concierge gh-403 — harden installation self-heal (transient-probe robustness + non-silent skip mirroring + directive contradiction)"
date: 2026-06-08
type: fix
branch: feat-one-shot-concierge-gh-403-self-heal
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: [4946, 4498]
status: planned
---

# fix: Harden Concierge GitHub-App installation self-heal (residual gh-403 bugs)

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Bug A (membership-probe robustness) — now bound to an in-repo canonical retry precedent; verify-the-negative pass on security claims; precedent-diff gate.
**Passes run:** mandatory gates 4.6 (User-Brand Impact ✓), 4.7 (Observability ✓), 4.8 (PAT-shaped halt — no hits ✓), 4.9 (UI-wireframe — no UI surface ✓); 4.4 Precedent-Diff; 4.45 verify-the-negative + post-edit self-audit. (Domain-leader Task spawn unavailable in this environment — inline grounded passes substituted; the security-sentinel / data-integrity-guardian / architecture-strategist triad runs at `/soleur:plan-review` and `/soleur:review`, mandatory here per the single-user-incident exit-gate rule.)

### Key Improvements
1. **Bug A retry is no longer novel** — it MUST reuse the canonical backoff idiom already in `apps/web-platform/server/github-api.ts:22-89` (`MAX_RETRIES=2`, `BASE_DELAY_MS=1000`, retry on `status >= 500 && attempt < MAX_RETRIES`, AND `isRetryable(err)` for thrown timeouts/`ECONNRESET`, fresh `AbortSignal` per attempt). `isRetryable` (`github-api.ts:29-51`) already classifies the `AbortSignal.timeout` `DOMException name:"TimeoutError"` throw as retryable — exactly the uncaught-throw failure mode in Bug A.
2. **Transient-class boundary has a precedent** — `checkRepoAccess` (`github-app.ts:767`) already uses `if (response.status >= 500) return "degraded"`. The membership probe's `indeterminate` class = `>= 500` (+ thrown `isRetryable`), `not-member` = `404`/`302`, `member` = `204`.
3. **Sibling retry constants already exist** in `github-app.ts:591-592` (`INSTALL_TOKEN_MAX_RETRIES=2`, `INSTALL_TOKEN_BASE_DELAY_MS=1000`) and the 401-retry loop at `:631-651` — Bug A should follow the SAME idiom for consistency, not introduce new constants with different values.
4. **Verify-the-negative confirmed** the two load-bearing security claims (see Research Insights).

### New Considerations Discovered
- The canonical `fetchWithRetry` in `github-api.ts` already solves "fresh AbortSignal per attempt" + body-drain-before-sleep (socket-leak avoidance). The simplest fix may be to route the membership probe THROUGH the existing retry helper rather than hand-rolling a loop inside `findRepoOwnerInstallationForUser` — evaluate at /work which is cleaner (helper reuse vs. local loop), but do not invent a third retry shape.

🐛 The hosted Concierge runs `gh` inside its sandbox and 403s ("`POST https://api.github.com/graphql: Forbidden`") on org-repo operations because the dispatch keeps a **wrong (cross-account/personal) installation token** instead of promoting to the entitled repo-owner installation. PR #4946 already built the self-heal + entitlement gate + mint-time observability + reproduce harness; this plan closes the **three residual gaps** that let the wrong-installation token still win silently.

## Premise Validation (Phase 0.6 — ran before any research)

The prompt's ARGUMENTS premise is **substantially stale** — most of the prescribed scope already shipped in **PR #4946** (`da138f1dc`, merged to `main`; learning `knowledge-base/project/learnings/security-issues/2026-06-04-concierge-403-wrong-installation-and-owner-match-needs-entitlement-gate.md`). Verified against `origin/main` files in the worktree:

| Prompt premise (ARGUMENTS) | Reality on `main` | Plan response |
| --- | --- | --- |
| "self-heal `findRepoOwnerInstallationForUser` fails SILENTLY at the orchestration level (no Sentry mirror)" | The orchestration probe (`cc-dispatcher.ts:1424-1434`) **already** wraps failures in `reportSilentFallback` (Sentry mirror). | Premise partially stale. Residual: the **deliberate "promotion skipped" decision** (membership probe ≠ 204, or org-type stored install, or `alreadyCorrect`) emits **nothing queryable** — see Bug B. |
| "no log + mirror of stored installationId / repo owner / probe outcome / effective installationId" | Only a single `log.info` on the **success** path (`cc-dispatcher.ts:1413-1421`); skips/aborts emit nothing. `log.info` is **breadcrumb-only** in Sentry (logger.ts:71-82 captures events only at `error`/`fatal` with an `Error`). | Bug B — route skip/abort decisions through `reportSilentFallback` so they become a queryable Sentry event, not a breadcrumb. |
| "robust membership probe distinguishing 404 not-a-member from transient 5xx/network with retry" | **Not done.** `github-app.ts:560` collapses every non-204 (incl. 5xx) into `null`; `githubFetch` uses `AbortSignal.timeout` so a timeout **throws uncaught** in `findRepoOwnerInstallationForUser` (the try/catch wraps only the token mint, not the `memberCheck`). No retry. | Bug A — the strongest residual. |
| "tighten `GH_403_PROMPT_DIRECTIVE` so the concierge never tells the user to confirm/install/re-consent" | **Directive self-contradicts.** Its final sentence (`cc-dispatcher.ts ~278-282`): *"The one sanctioned next step you may offer: if the 403 persists across retries, ask the user to confirm the Soleur GitHub App is installed on the repository's owner account."* This is **exactly** the screenshot-reported behavior. | Bug C. |
| "reuse `scripts/spike/reproduce-gh-403.ts`; extend the two named tests" | Harness + both tests exist and pass. The directive test (`cc-dispatcher-gh-403-directive.test.ts`) does **not** assert absence of the install-confirmation sentence — it passes while Bug C ships. | Extend, do not recreate. |

**Cited-symbol verification (all confirmed present on `main`):** `findRepoOwnerInstallationForUser` (`github-app.ts:529-561`), orchestration block (`cc-dispatcher.ts:1372-1449`), `GH_403_PROMPT_DIRECTIVE` (`cc-dispatcher.ts:260`, appended at `:1565`), `getInstallationAccount` (`:260`), `findOrgInstallationForUser` (`:401-457`), `generateInstallationToken` mint-log (`:678-685`), `reportSilentFallback` (`observability.ts:184`, accepts `err: unknown` → a `null` err routes to `Sentry.captureMessage`). No external GitHub issue is cited by reference; the screenshot is the only evidence. **No stale file/symbol paths.** Premise: research proceeds against the three narrowed residual bugs, not the disproven "app not installed" or "no observability at all" framings.

## Overview

Three residual defects keep a wrong-installation token alive after PR #4946:

- **Bug A — transient membership-probe error is indistinguishable from "not a member".** `findRepoOwnerInstallationForUser` (`github-app.ts:529-561`) returns the owner install **only** on `memberCheck.status === 204`. A genuine 404 (not a member → correctly deny promotion) and a transient 500/502/503/`AbortSignal.timeout` throw both collapse to "deny" → the stored wrong install is kept → 403. There is no retry and the timeout throw is **uncaught inside the function** (the local try/catch wraps only `generateInstallationToken`). A user who IS an entitled org member gets a 403 purely because GitHub's `/orgs/{owner}/members/{login}` 5xx'd or timed out for ~3s.
- **Bug B — the "promotion skipped" decision is observability-dark.** When the probe denies promotion (404), or the stored install is org-type, or it's already correct, the orchestration silently keeps the stored install. Only the **success** path logs (and that is a breadcrumb-only `log.info`). On-call cannot answer "why did this dispatch keep the wrong install?" from Sentry. Violates `cq-silent-fallback-must-mirror-to-sentry` for the deny/skip branches.
- **Bug C — the directive contradicts its own prohibition.** `GH_403_PROMPT_DIRECTIVE` forbids re-consent advice, then immediately sanctions *"ask the user to confirm the Soleur GitHub App is installed on the repository's owner account"* — the precise message the screenshot reported and that scope item (3) bans.

**Approach:** add a 3-value probe outcome (`member` / `not-member` / `indeterminate`), retry only the transient (`indeterminate`) class, and surface every deny/skip via `reportSilentFallback` carrying `storedInstallationId`, resolved `owner`, `membershipProbeOutcome` (`204` / `4xx:<status>` / `error:<reason>`), and `effectiveInstallationId`. Delete the contradictory directive sentence. **No token value is ever logged** (`hr-github-app-auth-not-pat`). **No PATs, no service-role, no infra** — pure code change against an already-provisioned surface.

## Research Reconciliation — Spec vs. Codebase

(No spec.md exists for this branch — `knowledge-base/project/specs/feat-one-shot-concierge-gh-403-self-heal/` is empty. The "spec" is the prompt ARGUMENTS, reconciled in Premise Validation above. Net: 3 of 4 ARGUMENTS items were already shipped in #4946; this plan implements only the verified residual deltas.)

## User-Brand Impact

- **If this lands broken, the user experiences:** the Concierge cannot create/read GitHub issues in their connected org repo — every `gh` op 403s — and (Bug C) the agent tells them to go re-check / re-install the GitHub App, sending a non-technical Soleur user down a dead-end re-consent path for a problem the platform should have healed server-side. This is the exact screenshot failure.
- **If this leaks, the user's data/workflow is exposed via:** the inverse risk is the load-bearing one — over-eager promotion. The entitlement gate (PR #4946) exists precisely so an outside read-only collaborator cannot be promoted to an org's WRITE-capable installation token (cross-tenant privilege escalation). **The retry/robustness change MUST fail-closed: an `indeterminate` membership probe after retries denies promotion** (keeps the user's current install + honest 403), never grants. Bug A's fix narrows false-negatives (entitled members wrongly denied), it must NOT widen true-positives into a security hole.
- **Brand-survival threshold:** `single-user incident` — one founder dogfooding the Concierge hitting a permanent 403 + a misleading "go re-install the app" instruction is a brand-survival event; and any loosening of the entitlement gate is a cross-tenant security event. CPO sign-off required at plan time; `user-impact-reviewer` + `security-sentinel` at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (Bug A — RED first).** A new test asserts that when `/orgs/{owner}/members/{login}` returns a **transient** failure (500, then 204 on retry), `findRepoOwnerInstallationForUser` **returns the owner install** (retry recovered the entitled member). Fails against current `main` (current code 5xx → `null`).
- [ ] **AC2 (Bug A — fail-closed).** A test asserts that a **persistent** transient failure (500 on every attempt incl. retries) and an `AbortSignal.timeout` throw both **return `null`** (deny promotion, keep stored install) — and do **not** throw out of the function. Distinguishes Bug A's narrowing from a security loosening.
- [ ] **AC3 (Bug A — genuine non-member still denied).** A `404` (and a `302`) from the members probe returns `null` with **no retry** (404 is authoritative "not a member" — retrying is pointless and a latency tax). Asserts `fetch` was called exactly once for the members endpoint on a 404.
- [ ] **AC4 (Bug B — skip is mirrored).** When the membership probe denies promotion (404 → `null`), the orchestration calls `reportSilentFallback` exactly once with `feature: "cc-dispatcher"`, `op` naming the self-heal skip, and `extra` carrying `storedInstallationId`, `owner`, `membershipProbeOutcome` (a string like `"404"` / `"indeterminate"`), and `effectiveInstallationId` (== stored, since promotion denied). Assert the mirror fires for the **deny** branch, not only the **throw** branch.
- [ ] **AC5 (Bug B — no token in payload).** The `reportSilentFallback` `extra` payload (and every new `log.*` call added in this PR) is asserted to **never** contain a `ghs_`/`gho_`/`ghp_` token substring (`hr-github-app-auth-not-pat`). Mirrors the existing assertion in `github-app-mint-observability.test.ts`.
- [ ] **AC6 (Bug C — directive).** `cc-dispatcher-gh-403-directive.test.ts` is extended to assert the directive body **does NOT contain** the install-confirmation escape hatch. The test reads the directive as **source text** (`SRC.slice(idx, idx+1200)`), so the `" +\n  "` concatenation is visible — the negative-match phrase MUST live within a **single string segment** (no `+`/newline split). Verified against `cc-dispatcher.ts:260-271`: assert `body` does **not** match `/sanctioned next step/i` (segment on line 268) **and** does **not** match `/persists across retries/i` (segment on line 269). Do NOT use `/confirm the Soleur GitHub App is installed/` — that phrase is split across the line-269→270 concatenation boundary (`"...ask the user to confirm the Soleur GitHub App is " +\n  "installed on..."`) and would false-negative the assertion.
- [ ] **AC7 (Bug C — retained prohibitions).** The same test still asserts the directive retains `/speculate/i`, `/re-consent/i`, and `/change GitHub App permissions/i` (no regression of the prohibitions PR #4946 added).
- [ ] **AC8 (observability layer citation — `hr-observability-layer-citation`).** The plan/PR body states the discoverability path: the new deny/skip mirror is a `reportSilentFallback` → `Sentry.captureMessage` event (queryable in Sentry by `feature:cc-dispatcher op:<self-heal-skip-op>`), AND a pino `logger.error` line (Better Stack via the container-stdout mirror, `logger.ts`). A bare `log.info` would be **breadcrumb-only** and is explicitly rejected for the skip path.
- [ ] **AC9 (full suite + typecheck green).** `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-mint-observability.test.ts test/cc-dispatcher-gh-403-directive.test.ts <new-test-file>` passes, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.

### Post-merge (operator)

- [ ] **AC10 (no operator action).** None. Pure code change to an already-provisioned surface; the merge → `web-platform-release.yml` container restart is the deploy. **Automation: N/A — no operator step exists.** (Optional, not a gate: re-run `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx scripts/spike/reproduce-gh-403.ts` to re-confirm the live wrong-installation signature; read-only, dev creds.)

## Files to Edit

- `apps/web-platform/server/github-app.ts` — Bug A. Refactor the membership probe in `findRepoOwnerInstallationForUser` (529-561) to a small helper returning a 3-value outcome (`member` | `not-member` | `indeterminate`), wrapping the `memberCheck` `githubFetch` in try/catch, classifying `204→member`, `404`/`302`→`not-member`, `>= 500`/thrown→`indeterminate`, with retry on `indeterminate` only. **Reuse the canonical backoff idiom — do NOT hand-roll a third retry shape** (precedent-diff, §Research Insights): mirror `server/github-api.ts:62-89` (`for attempt 0..MAX_RETRIES`; retry when `status >= 500 && attempt < MAX_RETRIES` OR `isRetryable(err)`; `delay(BASE_DELAY_MS * 2 ** attempt)`; fresh `AbortSignal` per attempt; body-drain before sleep). `isRetryable` (`github-api.ts:29-51`) already returns `true` for the `AbortSignal.timeout` `DOMException name:"TimeoutError"` — import/reuse it rather than re-implementing transient classification. Match the existing constants (`INSTALL_TOKEN_MAX_RETRIES=2`, `INSTALL_TOKEN_BASE_DELAY_MS=1000`, `github-app.ts:591-592`) so the three retry sites stay consistent. **Evaluate at /work whether to route the probe through the existing `github-api.ts` retry helper instead of a local loop** (simpler if the helper accepts the members-probe shape). Surface the final outcome to the caller (return `{ installationId, outcome }`, or expose the outcome via the helper so the orchestration reads it for Bug B). **Apply the same 3-value classification to the sibling probe in `findOrgInstallationForUser` (401-457, line 447)** — identical transient-collapse bug. Sibling-query audit: `git grep -n '/members/' server/github-app.ts` confirms exactly three `/members/` sites — 447 (`findOrgInstallationForUser`), 556 (`findRepoOwnerInstallationForUser`), 330 (`verifyInstallationOwnership`). Sites 447 + 556 are in scope; **330 (`verifyInstallationOwnership`) is connect-time, NOT the dispatch 403 — out of scope; note it in the PR body as the deliberately-untouched third site** (its `!== 204` collapse is a pre-existing connect-time concern, defer with a tracking note if review wants it folded).
- `apps/web-platform/server/cc-dispatcher.ts` — Bug B + Bug C. (B) In the self-heal block (1396-1449): after resolving the probe outcome, route the **deny/skip** decisions (probe `not-member` or `indeterminate`; org-type stored install; `alreadyCorrect` is a no-op, not a skip — do not mirror it) through `reportSilentFallback` with the 4-field payload from AC4. Keep the existing success `log.info` (1413-1421). (C) Delete the contradictory final sentence from `GH_403_PROMPT_DIRECTIVE` (260-282) — the `"The one sanctioned next step you may offer…"` clause — ending the directive at "...state only what the error literally says."
- `apps/web-platform/test/github-app-mint-observability.test.ts` — Bug A tests (AC1/AC2/AC3/AC5). The file already mocks `fetch` + `logger` + `reportSilentFallback` and imports from `../server/github-app`; extend it with a `describe("findRepoOwnerInstallationForUser — transient probe robustness")` block. (Export `findRepoOwnerInstallationForUser` is already exported. If the new outcome helper needs direct testing, export it too.)
- `apps/web-platform/test/cc-dispatcher-gh-403-directive.test.ts` — Bug C tests (AC6/AC7), source-presence style (matches the file's existing AC5 framing).

## Files to Create

- `apps/web-platform/test/cc-dispatcher-self-heal-observability.test.ts` — Bug B (AC4/AC5). Asserts the orchestration's deny/skip path calls `reportSilentFallback` with the 4-field payload and never logs a token. **Test path note:** must live under `test/**/*.test.ts` (vitest `include` is `test/**/*.test.ts` for the node project per `vitest.config.ts:44`; a co-located `server/*.test.ts` would be silently skipped). The cc-dispatcher prompt assembly + self-heal live in a per-dispatch factory that is impractical to invoke whole; if the deny-branch decision cannot be unit-invoked, extract the **skip-mirror emit** into a tiny pure helper (e.g. `mirrorSelfHealSkip({ storedInstallationId, owner, membershipProbeOutcome, effectiveInstallationId })`) and unit-test that helper directly (behavioral, per the existing `buildConnectedRepoContext` export precedent), plus a source-presence assertion that the orchestration calls it on the deny branch.

## Observability

```yaml
liveness_signal:
  what: "Concierge self-heal promotion-skip rate (reportSilentFallback events tagged feature:cc-dispatcher, op:self-heal-skip)"
  cadence: per-dispatch (on-demand, not scheduled)
  alert_target: "Sentry issue search feature:cc-dispatcher op:self-heal-skip — manual triage; no paging alert (low-volume, single-tenant dogfood)"
  configured_in: "apps/web-platform/server/observability.ts reportSilentFallback → Sentry.captureMessage"
error_reporting:
  destination: "Sentry (captureMessage/captureException via reportSilentFallback) + pino logger.error → container stdout → Better Stack"
  fail_loud: true  # deny/skip is a captureMessage EVENT (queryable), not a breadcrumb-only log.info
failure_modes:
  - mode: "transient members-probe 5xx/timeout denies an entitled member (Bug A false-negative)"
    detection: "Sentry event membershipProbeOutcome:indeterminate with effectiveInstallationId == storedInstallationId"
    alert_route: "Sentry search; correlate with GitHub status"
  - mode: "promotion skipped, user keeps wrong install + 403"
    detection: "Sentry feature:cc-dispatcher op:self-heal-skip event carries storedInstallationId + owner + outcome"
    alert_route: "Sentry search by op tag"
  - mode: "over-eager promotion (security regression — entitlement gate loosened)"
    detection: "absence is the signal — AC2/AC3 unit gates + security-sentinel review; no runtime promotion on indeterminate"
    alert_route: "pre-merge test gate (AC2/AC3), not runtime"
logs:
  where: "Sentry events + pino (container stdout, Better Stack). NO ssh required."
  retention: "Sentry default project retention; Better Stack per plan"
discoverability_test:
  command: "open Sentry → search 'feature:cc-dispatcher op:self-heal-skip' (web UI, no shell)"
  expected_output: "self-heal-skip events with storedInstallationId / owner / membershipProbeOutcome / effectiveInstallationId fields; token value NEVER present"
```

## Test Scenarios

1. **Transient-recover:** members probe 500 → retry → 204 ⇒ owner install returned (AC1).
2. **Transient-persist:** members probe 500 on every attempt ⇒ `null`, deny, no throw (AC2).
3. **Timeout throw:** `memberCheck` `githubFetch` rejects (AbortSignal.timeout) ⇒ caught → `indeterminate` → `null`, no throw (AC2).
4. **Genuine non-member:** 404 ⇒ `null`, fetch called once (no retry) (AC3).
5. **302 non-member:** ⇒ `null` (AC3).
6. **Skip mirrored:** deny path ⇒ `reportSilentFallback` once with 4-field payload, no token substring (AC4/AC5).
7. **Directive:** body lacks install-confirmation/`sanctioned next step`, retains speculate/re-consent/change-permissions (AC6/AC7).

## Hypotheses

(Network-outage checklist NOT triggered — this is not an SSH/firewall/`502/503/504`-class infra outage; the 403 is an application-layer installation-selection bug whose root cause is already proven by the reproduce harness + PR #4946 learning. The directive forbids re-chasing the disproven "app not installed" hypothesis. The transient-error class in Bug A is an *application-layer* GitHub-API 5xx/timeout, handled by retry-then-fail-closed, not by an infra diagnostic.)

## Open Code-Review Overlap

Checked after Files-to-Edit was finalized: `gh issue list --label code-review --state open` → bodies grepped for `server/github-app.ts`, `server/cc-dispatcher.ts`, `GH_403_PROMPT_DIRECTIVE`, `findRepoOwnerInstallationForUser`.

- #2246 (kb polish from PR #2235 — types/dead-props) touches `github-app.ts` — **Acknowledge:** unrelated concern (KB banner/type cleanup), does not touch the membership-probe / self-heal lines. Remains open.
- #3243 (decompose `cc-dispatcher.ts` into modules) — **Acknowledge:** structural refactor; this PR's edits to the self-heal block + directive are small and localized, and folding a full module decomposition here would balloon scope. Remains open; the decomposition can absorb these lines later.
- #3242 (tool_use WS event raw name field) — **Acknowledge:** different code path (WS event shape), no overlap with the self-heal/directive lines. Remains open.

## Domain Review

**Domains relevant:** Engineering (security — cross-tenant entitlement), Product (user-facing directive copy + brand-survival threshold)

> Note: domain-leader sub-agent spawn (Task tool) is unavailable in this planning environment; the sweep below is an inline single-pass assessment. `deepen-plan` (next step) runs the security-sentinel / data-integrity-guardian / architecture-strategist triad — mandatory here because `brand_survival_threshold: single-user incident` (per the exit-gate rule: plan-review catches style/scope; deepen-plan domain agents catch substance-level security findings).

### Engineering — Security (Status: reviewed, inline)

**Assessment:** The load-bearing risk is **inversion of the entitlement gate**, not the 403 itself. Bug A's retry MUST be strictly fail-closed: `indeterminate` after one retry → deny promotion (keep stored install). The owner install may be returned ONLY from a confirmed `204`. This is asserted by AC2 (persistent-transient → null) and AC3 (404/302 → null, no retry) and must be re-confirmed by `security-sentinel` at review. No PATs, no service-role, no token logging (`hr-github-app-auth-not-pat` — AC5). The probe-outcome strings logged (`"204"`/`"404"`/`"indeterminate"`) carry no secret material. `reportSilentFallback` already pseudonymizes `userId` (Recital 26) at the emit boundary, so the new `extra` payloads inherit that.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI-surface file in Files-to-Edit/Create (all `server/` + `test/`). The mechanical UI-surface override did not fire. The change to `GH_403_PROMPT_DIRECTIVE` is **agent prompt copy** (a string the model reads), not a rendered UI surface — but it IS user-facing in effect (it shapes what the Concierge tells the user). Brand-survival threshold `single-user incident` ⇒ `requires_cpo_signoff: true` (frontmatter) and `user-impact-reviewer` at review time. CPO sign-off required at plan time before `/work`: the directive-copy deletion (Bug C) removes the misleading "go re-install the app" escape hatch — a product-voice decision the CPO/brainstorm framing already endorsed (PR #4946 forbade re-consent advice; this closes the contradiction). Confirm CPO ack on the copy deletion before `/work`.

#### Findings

The only product-facing artifact is the directive string. Deleting the contradictory final sentence aligns the directive with its stated intent and the brand goal (never send a non-technical user down a dead-end re-consent path). No new copy is authored; a sentence is removed. No wireframe/`.pen` applicable (no rendered surface).

## Infrastructure (IaC)

Skipped — no new infrastructure. Pure code change against an already-provisioned surface (`apps/web-platform/server/**` + `test/**`). No server, service, secret, vendor, cron, DNS, or persistent runtime process introduced. Deploy is the existing `web-platform-release.yml` container restart on merge to `main`.

## GDPR / Compliance Gate

Invoked-equivalent (inline): the edited files are GitHub-App-JWT **auth-token-selection** code, not a regulated-data schema/migration/PII surface. No new processing activity on personal data is introduced — the change selects which installation token to mint and adds observability metadata (installation ids, repo owner login, probe-status strings). `userId` in the new `reportSilentFallback` payloads is pseudonymized at the emit boundary (Recital 26, `observability.ts hashExtraUserId`). GitHub login/owner is already processed by the existing self-heal. No Art. 9 special-category data, no new lawful-basis question, no DSAR/Art. 30 trigger. **No Critical findings.** (Trigger (b) single-user-incident threshold fired the gate-consideration; outcome: no new regulated surface.)

## Research Insights

### Precedent-Diff (Phase 4.4) — retry/transient classification

The retry behavior is **pattern-bound** (it must classify transient vs authoritative HTTP outcomes and back off), and the repo has a canonical form. `git grep` results:

| Concern | Canonical precedent (verbatim) | Bug A adopts |
| --- | --- | --- |
| Retry loop shape | `server/github-api.ts:62` — `for (let attempt = 0; attempt <= MAX_RETRIES; attempt++)` with `MAX_RETRIES=2` (`:22`), `BASE_DELAY_MS=1000` (`:23`) | Same loop; reuse the helper if it fits the members-probe shape. |
| Transient HTTP boundary | `server/github-api.ts:70` — `if (response.status >= 500 && attempt < MAX_RETRIES)`; `server/github-app.ts:767` `checkRepoAccess` — `if (response.status >= 500) return "degraded"` | `>= 500` ⇒ `indeterminate` (retry). |
| Thrown timeout/network classification | `server/github-api.ts:29-51` `isRetryable(err)` — returns `true` for `DOMException name:"TimeoutError"` (the `AbortSignal.timeout` throw) and `ECONNRESET`/`ETIMEDOUT` | Import/reuse `isRetryable`; thrown + retryable ⇒ `indeterminate`. |
| Fresh signal per attempt + body drain | `server/github-api.ts:64,72` (fresh `AbortSignal`), `:46` (`await response.text().catch(()=>{})` before sleep) | Same — avoids reused-signal bug + socket leak. |
| Sibling retry constants | `server/github-app.ts:591-592` `INSTALL_TOKEN_MAX_RETRIES=2`, `INSTALL_TOKEN_BASE_DELAY_MS=1000`; 401-retry loop `:631-651` | Match values; keep the 3 retry sites consistent. |

**Pattern is NOT novel** — reviewers should scrutinize that Bug A reuses these, not that it invents a new shape. The single risk the precedent does NOT cover: fail-closed direction. The 401-retry and 5xx-retry precedents retry a *self* operation and surface the error; Bug A's retry gates an *authorization* decision, so the post-retry `indeterminate` must **deny** (return null), not surface-and-proceed. This inversion is the security-critical delta — see User-Brand Impact + Sharp Edges.

### Verify-the-Negative (Phase 4.45) — security claims probed against code

| Plan claim | Probe | Result |
| --- | --- | --- |
| "NO Supabase service-role in the self-heal" | `grep -n 'service.role\|getServiceRoleClient\|SUPABASE_SERVICE' server/cc-dispatcher.ts` | **Confirms** — only matches are comments asserting absence; no service-role client call exists. |
| "promotion derived ONLY from a User-type stored install" | `grep -n 'storedAccount.type === "User"' server/cc-dispatcher.ts` → `:1406` | **Confirms** — the gate is `if (!alreadyCorrect && storedAccount.type === "User")`; org-type stored install keeps the stored install (a Bug-B skip to mirror). |
| "owner install returned ONLY on confirmed 204" | `github-app.ts:560` `return memberCheck.status === 204 ? ownerInstall : null` | **Confirms** current code; the fix MUST preserve this invariant (204 is the only grant path) while adding retry on the deny side. |

### Post-edit self-audit (Phase 4.45)

No infrastructure/symbols were dropped or renamed by this plan (it edits existing functions + a string constant; adds tests). No dangling references to removed symbols. `reportSilentFallback` signature (`observability.ts:184`, `err: unknown`) confirmed to accept a `null`/non-Error first arg → routes to `Sentry.captureMessage` (the queryable-event path the skip mirror needs).

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Retry transient errors AND promote on persistent indeterminate (assume entitled) | **Rejected — security.** Violates the entitlement gate's whole purpose (#4946). Fail-closed is mandatory: indeterminate after retry → deny. |
| Add unbounded retry with exponential backoff | Rejected — a chat dispatch must not block on a flaky members probe; one short retry then fail-closed keeps the honest 403 fast (Sentry records the indeterminate). |
| Promote the `log.info` success line to also cover skips via `log.info` | Rejected — `log.info` is Sentry-breadcrumb-only (`logger.ts:71-82`); a skip must be a queryable `captureMessage` event → use `reportSilentFallback`. |
| Touch `verifyInstallationOwnership` (`:330`) members probe too | Out of scope — connect-time path, not the dispatch self-heal 403. Noted in PR body; deferral tracked if review wants it folded. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled with concrete artifact/vector/threshold.)
- The directive is a multi-line `" +\n  "` string concatenation and the test matches against **source text** — AC6's negative-match substring must live within a single string segment. VERIFIED: `confirm the Soleur GitHub App is installed` is **split** across the line-269→270 boundary and is NOT usable; use `sanctioned next step` (line 268) + `persists across retries` (line 269) instead. The Bug-C fix deletes the clause spanning source lines 268-271, ending the directive at "...with the correct installation automatically." (line 267).
- Fail-closed inversion risk: Bug A narrows false-negatives but MUST NOT widen promotion. Every new branch that returns the owner install must be reachable ONLY from a confirmed `204` (directly or post-retry). security-sentinel must confirm no path returns the owner install on `indeterminate`.
- New test files MUST live under `apps/web-platform/test/**/*.test.ts` (vitest node-project `include`); a co-located `server/*.test.ts` is silently skipped. Runner is **vitest**, not bun (`bunfig.toml` blocks bun discovery); typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces:` — `npm run -w` fails).
