# Tasks — fix: stop the daily false page from the Anthropic cost-report cron

Plan: `knowledge-base/project/plans/2026-07-20-fix-anthropic-key-missing-false-page-plan.md`
Issue: #6297 · Branch: `feat-one-shot-6297-anthropic-key-missing-false-page` · Lane: `cross-domain`

> Phase numbering intentionally skips 3 — the day-31 severity escalation was cut at plan-review.
> See `decision-challenges.md` DC-1.

## Phase 0 — Preconditions (read before editing)

- [x] 0.1 Read `apps/web-platform/server/inngest/functions/cron-anthropic-cost-report.ts` in full.
- [x] 0.2 Read `apps/web-platform/server/observability.ts` — confirm `warnSilentFallback` logs via
      `logger.warn` (pino 40) and emits `Sentry.captureMessage(..., { level: "warning" })`.
- [x] 0.3 Read `apps/web-platform/test/server/inngest/cron-anthropic-cost-report.test.ts` — note the
      `vi.mock("@/server/observability", …)` factory exports **only** `reportSilentFallback`.
- [x] 0.4 Read `apps/web-platform/server/claude-cost-marker.ts` — note the dedicated pino instance and
      its `base: { component: "claude-cost" }`.
- [x] 0.5 Read `scripts/followthroughs/cert-reissue-markers-6698.sh` (the probe model) and
      `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` lines 17-25.

## Phase 1 — D1: make the key-missing branch non-paging

- [x] 1.1 **RED.** Add `warnSilentFallbackSpy` to the `vi.hoisted` block **and** to the
      `vi.mock("@/server/observability")` factory. *(Skipping the factory yields a `TypeError`
      instead of a clean assertion failure.)*
- [x] 1.2 **RED.** key-missing test: assert `warnSilentFallback` called with `null` +
      `op: "anthropic-admin-key-missing"`, `reportSilentFallback` **not** called, and the message
      carries the content anchor `daily cost report is dark`.
- [x] 1.3 **RED.** 401 and 403 tests: assert `reportSilentFallback` called with an `Error` +
      `op: "anthropic-admin-key-invalid"`, and `warnSilentFallback` **not** called.
- [x] 1.4 Confirm the new tests FAIL. Capture output for the PR body (AC1).
      Captured by reverting the 1.5 swap in-place (`warnSilentFallback` → `reportSilentFallback`)
      and re-running: **1 failed | 12 passed (13)**, failing at
      `cron-anthropic-cost-report.test.ts:193` on
      `expect(reportSilentFallbackSpy).not.toHaveBeenCalled()` —
      *"expected vi.fn() to not be called at all, but actually been called 1 times"*, with the
      received call carrying `op: "anthropic-admin-key-missing"`. The RED lands on the exact
      assertion the fix targets, not on a collateral failure. File restored byte-identical after.
- [x] 1.5 **GREEN.** Add `warnSilentFallback` to the `@/server/observability` import in the cron; swap
      the key-missing branch's `reportSilentFallback(null, …)` → `warnSilentFallback(null, …)`.
      Leave `feature` / `op` / `message` / `extra` values unchanged.
- [x] 1.6 Verify no change to schedule, concurrency, retries, 401/403 arm, 429/5xx rethrow,
      `isFinalAttempt`, or the success path (AC5).

## Phase 2 — D2a: carry the dark-window age

- [x] 2.1 `claude-cost-marker.ts`: add optional `days_since_first_dark?: number` to
      `ClaudeCostDailyMarker`, with the comment documenting that it does **not** reset across a
      mint-then-rotate cycle.
- [x] 2.2 Cron: add `const FIRST_DARK_FIRE = "2026-07-10"` and exported
      `daysSinceFirstDark(now: Date = new Date()): number` (whole UTC days, floored at 0).
- [x] 2.3 Pass `days_since_first_dark` on the key-missing marker call and in the
      `warnSilentFallback` `extra`.
- [x] 2.4 Unit-test `daysSinceFirstDark` with explicit `Date` args (pre-date → 0; 2026-07-20 → 10).
- [x] 2.5 Assert the `status:"ok"` payload does **not** carry the field (AC9).

## Phase 4 — D2b: self-closing follow-through tracker

- [x] 4.1 Create `scripts/followthroughs/anthropic-admin-key-6297.sh` (mode 0775), modelled on
      `cert-reissue-markers-6698.sh`. `#!/usr/bin/env bash`, `set -uo pipefail` (**not** `-e`).
- [x] 4.2 **P0 — field isolation.** PASS requires **both** `SOLEUR_CLAUDE_COST_DAILY == true` **and**
      `component == "claude-cost"`. A marker-name-only match is satisfiable by the webhook echo of
      this PR/issue body and would false-close the tracker. Add a contamination fixture arm and
      mutation-prove it.
      **Shipped method supersedes the planned one.** The plan specified matching both *byte-forms*
      of `"component":"claude-cost"` (unescaped for `--grep`/`raw LIKE`, escaped for `grep -F` over
      JSONEachRow stdout). Review found that two-stage byte-matching defeatable by an embedded
      newline: stage 1 materializes `\n` inside `raw` as a real newline, stage 2 re-tokenizes on
      physical lines, so a forged line *inside* a multi-line `raw` is evaluated as a top-level log
      line — a false PASS that would auto-close #6297 with the key unminted. The probe instead
      decodes `raw` once and requires both as **top-level JSON keys** in a single-pass `jq` filter
      that fails closed on trailing garbage. Strictly stronger, and mutation-proven by fixture 5c +
      arm 7 (which splits the filter back into two stages and requires the fixture to flip).
      See commit `b12cd46b8` and the committed learning file.
- [x] 4.3 Pin `--since 48h` (Better Stack retention is 3 days).
- [x] 4.4 Exit contract: `0` = field-isolated `"status":"ok"` row; `1` = **regression**, defined as
      window contains an `"status":"ok"` row AND the most recent field-isolated row is
      `"status":"key-missing"`; `2` = still key-missing with no prior ok / query or auth failure /
      missing `betterstack-query.sh` / zero producer rows.
- [x] 4.5 Secret guard must use `if [[ -z "${VAR:-}" ]]; then …; exit 2; fi` — **never**
      `: "${VAR:?msg}"` (aborts with status 1 = FAIL). Do not copy `ghcr-minter-live-6031.sh:28`.
- [x] 4.6 Zero-row path: cross-check Sentry (independent Layer-2 transport) and print the divergence;
      emit `STALLED:` once ≥7 prior zero-row sweeper comments exist, still exiting 2.
      **The counter must come from `gh issue view`, not an in-process variable** — the probe is
      stateless under `env -i` (`sweep-followthroughs.sh:101`), so an in-process count is
      unimplementable and would silently never fire.
- [x] 4.7 Update #6297: remove `priority/p3-low`; add `priority/p2-medium` + `follow-through`; keep
      `deferred-automation` label **and** the literal body string.
- [x] 4.8 Add the `<!-- soleur:followthrough … -->` directive with **all five** secrets —
      `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,SENTRY_AUTH_TOKEN,GH_TOKEN`
      — and `earliest=2026-07-20T00:00:00Z`. Omitting `GH_TOKEN`/`SENTRY_AUTH_TOKEN` makes 4.6's two
      mitigations unreachable while every other AC still passes.
- [x] 4.9 **Playwright-first (blocking).** Attempt the Console mint at `console.anthropic.com` →
      Settings → API keys. Record a `playwright-attempt:` evidence line. Only if a *named* human gate
      (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card/hardware-token) is reached may the operator
      text ship. Do **not** assert operator-only from the docs FAQ alone.
- [x] 4.10 Rewrite the #6297 operator section in plain language (§Operator Action). The operator
      pastes the key into **both** Doppler configs: `prd` as `ANTHROPIC_ADMIN_KEY` (what the cron
      actually reads) and `prd_terraform` as `TF_VAR_ANTHROPIC_ADMIN_KEY` (Terraform's input). A
      `prd_terraform`-only paste never reaches the cron and would leave the tracker TRANSIENT
      forever. Use the 6-row actor table in §Operator Action.
<!--
  Deferred-orchestrator prose. This describes the CONTENTS of a FUTURE IaC PR that
  is deliberately not opened: it cannot merge before the key exists (a no-default
  TF variable whose value is absent fails the whole auto-applied root, per ADR-065),
  and the key is un-mintable until the operator decides on the org account tier
  (#6297).

  The step this task DOES prescribe — file a tracking issue — is a `gh issue create`,
  which the agent performs; it is not a human-run infra step. And when the follow-up is
  actually authored, its apply runs through `apply-web-platform-infra.yml` — CI, not a
  human terminal — so the no-human-steps invariant holds there too.

  The two tokens the sentinel matched are both false positives: the actor is the
  possessive "the operator's value" (a value Terraform ADOPTS, pasted via the Doppler
  web UI — the sanctioned non-technical path), and the imperative is `-target … appl…`
  matching the CI workflow FILENAME `apply-web-platform-infra.yml` — i.e. the sentinel
  matched the name of the very automation that makes this non-human.

  REMOVE THIS REGION once #6771 lands (it narrows the imperative so a workflow
  filename cannot satisfy it). A carve-out that outlives its cause is a permanent
  blind spot in a P0 gate — this one exists only because the sentinel is currently
  unable to tell a filename from a command.
-->
- [x] 4.11 File the IaC follow-up issue/PR stub (do **not** open it for merge). It must carry **three**
      things together: the no-default sensitive `variable`, the `doppler_secret` with
      `lifecycle { ignore_changes = [value] }` (so TF adopts the operator's value), **and the matching
      `-target=` line in `apply-web-platform-infra.yml`** — without that line the resource is declared
      and never applied. Model on `inngest-betterstack-token.tf`.
      **Filed as #6765**, carrying all three elements plus the ADR-065 merge-order gate
      (secret-in-`prd_terraform`-first, IaC-second) and the `anthropic-admin-key-6297.sh`
      close criterion.

## Phase 5 — Records

- [x] 5.1 Amend ADR-108: add `days_since_first_dark` to `## Decision`; note the non-reset semantics in
      `## Consequences`. Do **not** create a new ADR ordinal.
- [x] 5.2 Update `betterstack-log-query.md` §"Querying Anthropic cost markers": document
      `days_since_first_dark`, the `component == "claude-cost"` field-isolation requirement (as a
      decoded top-level key — see 4.2's superseding method, not the planned byte-form match), and
      the **absent-vs-zero trap** — `JSONExtractInt` returns 0 both for an `ok` row
      (field omitted) and a genuine day-0 key-missing row, so queries must filter
      `status='key-missing'` first.
- [x] 5.3 File a tracking issue for the **14 of 39** pre-existing probes carrying the banned
      `${VAR:?}` form on an executable line (measured with AC10's comment-stripping method — the
      naive count of 19 includes 5 comment-only mentions), proposing the AC10 grep as a CI guard
      (`wg-when-an-audit-identifies-pre-existing`).
      **Filed as #6757** (denominator re-measured at filing time as 14 of **40**, not 39 — one
      probe was added between planning and filing; the numerator is unchanged).

## Phase 6 — Verification

- [x] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [x] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-anthropic-cost-report.test.ts`
      exits 0.
- [x] 6.3 Full-suite exit gate.
      Re-run after the AC14b fixtures landed (the earlier `196/196` predated them):
      `bash scripts/test-all.sh` → **196/196 suites passed**, exit 0, 602 assertions, 0 failures,
      including `[ok] scripts/anthropic-admin-key-6297` at 22/22. The suite *count* is unchanged
      because the new fixtures extend an already-registered suite rather than adding one.
- [x] 6.4 Walk all pre-merge ACs (AC1–AC19, incl. AC14b/AC14c). Confirm AC6 and AC10 use the `if … grep -q` / `if grep …` forms,
      not `grep -c` (exit-status inversion).
      **Walked. AC1–AC19 all MET; AC20–AC23 are post-merge (they need a producer row / post-fix
      Sentry events / a sweeper run).** Two started NOT MET and were fixed rather than waived:
      **AC1** — the RED existed but not *in the PR body*, where AC1 requires it; now added.
      **AC14b** — the Sentry `DIVERGENCE` and `STALLED` branches were reachable but *unexercised*:
      `run_probe` is `env -i` with only `BETTERSTACK_QUERY_*`, so both tokens were always unset and
      every zero-row fixture took the "skipped/unavailable" arm, with stdout discarded to
      `/dev/null`. Both mitigations exit 2 exactly like a plain TRANSIENT, so an exit-code-only
      harness cannot tell them apart. Closed with 11 stdout-asserting fixtures (8–12) driven by
      sandbox-local `gh`/`curl` stubs, mutation-proven three ways.
      **`grep -c` question: clean.** AC6 (`if … grep -qE`) and AC10 (`if grep -vE … | grep -nE`)
      both specify the `if`-tested form. Every `grep -c` in the shipped scripts captures stdout
      into a variable (`ROWS=$(… grep -c . || true)`, `HAS_OK=$(… grep -c '^ok$' || true)`) which
      then drives an arithmetic test — no `grep -c` exit status is tested anywhere.
- [x] 6.5 `bash -n` the probe; run the AC12 negative control (probe must not exit 0 against a window
      whose only matches are the webhook echo).
- [x] 6.6 PR body uses **`Ref #6297`**, not `Closes #6297`.
- [x] 6.7 Confirm zero files under `apps/web-platform/infra/` in the diff (whole tree, not just `*.tf` — the auto-apply `paths:` filter is `infra/**`).
