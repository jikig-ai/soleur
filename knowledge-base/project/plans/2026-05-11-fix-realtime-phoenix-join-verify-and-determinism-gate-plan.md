---
title: Close #3049 — verify cross-tenant Realtime isolation contract holds; land #3060 CI determinism gate
date: 2026-05-11
type: fix + ci-hardening
related_issues: [3049, 3060, 3052, 3021]
related_prs: [3058]
classification: verification + ci-infra
requires_cpo_signoff: false
---

# Close #3049 — verify cross-tenant Realtime isolation; land #3060 CI determinism gate

## Overview

Issue #3049 was filed on 2026-04-29 by `/ship` Phase 7 as the verification follow-through for the cross-tenant Realtime isolation integration test deferred at PR #3021's ship time. The investigation issue #3052 closed the same day via PR #3058, which polyfilled `globalThis.WebSocket = ws` BEFORE `createClient()` to push `@supabase/realtime-js@2.99.2`'s factory into its `type: 'native'` branch on Node <22.

**The fix has been on `main` since 2026-04-29 (commit `de7de012`).** What #3049 asks for is integration-level confirmation that the contract holds — running the test in an environment where Phoenix JOIN handshake completes and INSERT/UPDATE/DELETE leak assertions return zero. That confirmation has not been re-asserted on a public PR since the original ship and the issue is past SLA (`needs-attention` label, Phase 4 milestone overdue).

This plan does three things:

1. **Re-verify** the test passes against dev from this worktree (Phase 1 — local).
2. **Implement #3060's nightly determinism gate** (Phase 2 — adds `.github/workflows/scheduled-realtime-probe.yml`) so the polyfill workaround does not silently rot under future supabase-js bumps. Approach choice is documented in §Design Decisions.
3. **Close out** #3049 + #3060 with linked run URLs in the PR body and an updated learning-file breadcrumb.

The hypotheses listed in the inbound brief (Phoenix `vsn` mismatch, Cloudflare WS quirk, supabase-js version pin, apikey-in-join-payload) were all investigated in the original #3052 → #3058 cycle. The root cause is documented in `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md` and is NOT any of those four — it is the Node-without-native-WebSocket factory branch returning `{ type: 'unsupported' }` since `realtime-js@2.99.x`. Browsers do not hit it because `globalThis.WebSocket` is always defined. The plan does NOT re-litigate root cause — it asserts the contract still holds and hardens against silent regression.

## Research Reconciliation — Brief Hypotheses vs. Codebase Reality

The pipeline brief lists four hypotheses to investigate. All four were investigated under #3052 and ruled out before #3058 shipped. Documenting here so the next reader does not redo the work:

| Brief Hypothesis | Reality (verified 2026-04-29) | Plan Response |
|---|---|---|
| Phoenix `vsn` protocol mismatch | URL contains `vsn=1.0.0`; broker accepts it (browser path works against the same broker). Ruled out — JOIN never sent in shell. | No-op. |
| Cloudflare WS http1.1/http2 quirk | `curl -sI -H 'Upgrade: websocket'` returns HTTP 101 with `sb-project-ref` header — CF routing is fine. Phoenix-level handshake never fires because `realtime-js`'s factory returns `unsupported` BEFORE the WS upgrade attempt on Node <22. Ruled out — CF is downstream of the bug. | No-op. |
| supabase-js version pin | `@supabase/supabase-js@2.99.2` + `@supabase/realtime-js@2.99.2` installed. The race that landed in `v2.88.0` ("handle websocket race condition in node.js") did NOT cover this exact factory path on Node 21.7.3. A bump is not the fix; the polyfill is. Ruled out as the load-bearing variable. | No-op for this PR. **Phase 2 adds a nightly probe specifically to catch a future supabase-js bump that re-triggers the race or makes the polyfill unnecessary.** |
| `apikey` in JOIN payload | The JOIN payload already includes the auth token; broker does not require apikey in payload. Ruled out — JOIN is never sent in shell. | No-op. |

The Phase 2 nightly probe is the structural defense against any of these four assumptions becoming wrong in the future — it does not require diagnosing which one drifted.

## Current State (Verified 2026-05-11)

Verified locally before writing this plan:

```text
$ node --version
v21.7.3

$ cd apps/web-platform && doppler run -p soleur -c dev -- \
    env SUPABASE_DEV_INTEGRATION=1 \
    ./node_modules/.bin/vitest run test/conversations-rail-cross-tenant.integration.test.ts

 ✓ ConversationsRail cross-tenant Realtime isolation > user A receives ZERO payloads from user B's INSERT  2106ms
 ✓ ConversationsRail cross-tenant Realtime isolation > user A receives ZERO payloads from user B's UPDATE  2148ms
 ✓ ConversationsRail cross-tenant Realtime isolation > user A receives ZERO payloads from user B's DELETE (RLS-bypass case)  4141ms
 Test Files  1 passed (1)
      Tests  3 passed (3)
   Duration  11.44s

$ doppler run -p soleur -c dev -- node ./scripts/realtime-probe.mjs
[probe] polyfill: applied (globalThis.WebSocket = ws)
[probe 316ms] SUBSCRIBED 
[probe 317ms] CLOSED
```

The contract holds today on dev. The integration test is opt-in via `SUPABASE_DEV_INTEGRATION=1` and runs only on operator machines. Without a CI probe, a future `supabase-js`/`realtime-js` bump can silently re-trigger the race (or the documented workaround becomes unnecessary, leaving dead polyfill code in `test/helpers/`) and we would not know until the next operator ran the integration test by hand. Issue #3060 was filed specifically to track this gap.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user-facing impact at land time — this is verification + CI infrastructure. The polyfill itself is already in `main` and is what protects cross-tenant isolation against regression. If the new nightly workflow is misconfigured (e.g., uses prd creds), the worst case is a noisy CI failure email.

**If this leaks, the user's [data / workflow / money] is exposed via:** No new exposure surface. The polyfill MUST NOT be imported from `lib/`, `app/`, or `server/` — already a constraint of the existing fix (see learning file §"Why this is contained to test/probe paths"). This plan does not change that boundary.

**Brand-survival threshold:** `none` — reason: this PR adds a nightly CI probe and re-asserts an existing test's verdict. No prod code path changes, no new data-handling surface, no auth/credentials/payments touch. Sensitive-path regex does not match (no `apps/web-platform/lib/**`, `app/**`, `server/**`, `supabase/migrations/**`, or `infra/**` edits).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — Integration test passes against dev locally (3/3 in <30s) from this worktree. Paste the test runner output in the PR body. (Already verified 2026-05-11; will re-run after any further code edits.)
- [ ] AC2 — `apps/web-platform/scripts/realtime-probe.mjs` reaches SUBSCRIBED in <2s in default-polyfill mode against dev. (Already verified 2026-05-11; will re-run after any further code edits.)
- [ ] AC3 — `apps/web-platform/scripts/realtime-probe.mjs --no-polyfill` reproduces `TIMED_OUT` at ~10s against dev (Mode B baseline still holds — this is the regression-detector signal the nightly will assert).
- [ ] AC4 — `.github/workflows/scheduled-realtime-probe.yml` exists and:
   - Targets dev only (`-c dev`); MUST NOT reference prd (per `hr-dev-prd-distinct-supabase-projects`).
   - Runs the probe 5× consecutively; any single `TIMED_OUT` or non-`SUBSCRIBED` exit fails the step.
   - Per-curl/per-node timeout pinned (probe script's internal joinTimeout is already 10s; workflow's `timeout-minutes` is 10).
   - File/comment-or-close tracking-issue pattern mirrors `scheduled-oauth-probe.yml` (open issue with label `ci/realtime-broken`; comment on existing; auto-close stale on green).
   - `notify-ops-email` step on failure (matches OAuth probe pattern).
   - Permissions: `contents: read, issues: write` only.
   - All untrusted values (probe output, supabase-js version string) flow through env vars + `strip_log_injection` before any `::error::`/`::warning::` echo.
- [ ] AC5 — `yamllint` + `actionlint` clean on the new workflow file (per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`: do NOT use `bash -n <file.yml>`).
- [ ] AC6 — `ci/realtime-broken` label exists (pre-create idempotently in the workflow `gh label create ... 2>/dev/null || true`, mirroring `ci/auth-broken` pattern).
- [ ] AC7 — Learning file `2026-04-29-supabase-phx-join-handshake-shell-environment.md` updated with a "Nightly CI determinism gate (issue #3060)" breadcrumb in §Related so future readers find the workflow from the learning, not just vice versa.
- [ ] AC8 — Probe script's `--no-polyfill` flag still functions for one-shot diagnostic use after any edits (workflow uses default-polyfill mode, but the diagnostic path must remain green).
- [ ] AC9 — PR body uses `Closes #3049` (one body line, intentional auto-close) and `Closes #3060` (one body line). Use `Ref #3052` and `Ref #3058` everywhere else per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] AC10 — PR body NOT title carries the auto-close keywords; PR title is `fix(realtime): close #3049 via nightly determinism gate (#3060)` without auto-close keyword in title to avoid the double-close trap from `wg-use-closes-n-in-pr-body-not-title-to`.

### Post-merge (operator/CI)

- [ ] PM1 — Trigger one manual run of `scheduled-realtime-probe.yml` via `gh workflow run scheduled-realtime-probe.yml`; poll via `gh run view <id> --json status,conclusion` until complete; confirm `conclusion: success`. Per `wg-after-merging-a-pr-that-adds-or-modifies`.
- [ ] PM2 — Link the green run URL in a comment on #3049 and #3060 as the proof artifact, then verify both are closed by `Closes #` (or close manually if auto-close did not fire).
- [ ] PM3 — Confirm the workflow appears in the dashboard alongside `scheduled-oauth-probe.yml` and `scheduled-cf-token-expiry-check.yml` (sanity check that the cron is registered).

## Implementation Phases

### Phase 1 — Re-verify the contract holds today (no code changes)

**Goal:** Document a fresh, dated green verdict on dev before adding the CI gate.

1. Run the integration test against dev (already done at plan time — log captured above). Re-run after any final edits.
2. Run `scripts/realtime-probe.mjs` default mode (polyfill on). Capture timing.
3. Run `scripts/realtime-probe.mjs --no-polyfill` to confirm Mode B baseline still reproduces `TIMED_OUT` (this is the regression-detector signal; if Mode B passes without the polyfill, the upstream race is resolved and the polyfill can be retired — but that is out-of-scope for this PR; file a follow-up).
4. Paste all three outputs into the PR body's "Verification" section.

### Phase 2 — Land #3060 nightly determinism gate

**Goal:** A scheduled GitHub Actions workflow that runs the probe 5× nightly against dev and opens/comments on a tracking issue on failure.

**Files to Create:**

- `.github/workflows/scheduled-realtime-probe.yml` — new workflow (template: `scheduled-oauth-probe.yml`).

**Files to Edit:**

- `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md` — add Phase 2 workflow as a "Nightly CI determinism gate (issue #3060)" line under §Related.

**Files to NOT Edit:**

- `apps/web-platform/test/helpers/node-websocket-polyfill.ts` — unchanged.
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts` — unchanged.
- `apps/web-platform/scripts/realtime-probe.mjs` — unchanged. The workflow consumes the existing script's contract; do NOT modify the script in this PR.
- `apps/web-platform/lib/**`, `apps/web-platform/app/**`, `apps/web-platform/server/**` — sensitive prod paths; explicitly out of scope.

**Workflow structure (mirror `scheduled-oauth-probe.yml` shape):**

```yaml
name: "Scheduled: Realtime Probe"

on:
  schedule:
    - cron: '0 7 * * *'   # 07:00 UTC daily (matches drift-detector cadence)
  workflow_dispatch: {}

concurrency:
  group: scheduled-realtime-probe
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  probe:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout
        uses: actions/checkout@<pinned-SHA>
        with:
          sparse-checkout: |
            apps/web-platform/scripts/realtime-probe.mjs
            apps/web-platform/package.json
            apps/web-platform/package-lock.json
            apps/web-platform/node_modules-marker  # see Phase 2.2
            .github/actions
          sparse-checkout-cone-mode: false

      - name: Setup Node
        uses: actions/setup-node@<pinned-SHA>
        with:
          node-version: '21.7.3'

      - name: Install ws (single dep) ...
      # OR: full `npm ci` if probe script imports anything beyond ws + supabase-js

      - name: Install Doppler CLI
        # standard pattern from sibling workflows

      - name: Run probe 5× consecutively
        id: probe
        env:
          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_CI }}
          # NEXT_PUBLIC_SUPABASE_URL + NEXT_PUBLIC_SUPABASE_ANON_KEY come from Doppler at runtime.
        run: |
          set -uo pipefail
          fail_mode=""
          fail_detail=""
          # strip_log_injection helper copied from scheduled-oauth-probe.yml
          # — keep verbatim until a shared composite action is extracted.

          for i in 1 2 3 4 5; do
            output=$(doppler run -p soleur -c dev -- \
              node apps/web-platform/scripts/realtime-probe.mjs 2>&1)
            if ! grep -q "SUBSCRIBED" <<<"$output"; then
              fail_mode="realtime_join_timeout"
              fail_detail="Run $i/5 did not reach SUBSCRIBED. Output: $(echo "$output" | tr '\n' ' ' | head -c 500)"
              break
            fi
          done

          fail_mode_safe=$(strip_log_injection "$fail_mode")
          fail_detail_safe=$(strip_log_injection "$fail_detail")
          {
            echo "failure_mode=${fail_mode_safe}"
            echo "failure_detail=${fail_detail_safe}"
          } >> "$GITHUB_OUTPUT"

          if [[ -n "$fail_mode_safe" ]]; then
            echo "::warning::Realtime probe failed: ${fail_mode_safe}"
            exit 1
          fi

      - name: File or comment on tracking issue (failure)
        # mirror scheduled-oauth-probe.yml lines 420-486:
        #   - label ci/realtime-broken (pre-create idempotent)
        #   - dedupe via `gh issue list --search '[ci/realtime-broken] ...'`
        #   - body via printf heredoc (no leading-whitespace traps)
        #   - link to learning file for diagnosis instructions

      - name: Email notification (failure)
        # mirror scheduled-oauth-probe.yml lines 488-498

      - name: Auto-close stale issue (probe green)
        # mirror scheduled-oauth-probe.yml lines 500-522
```

**Phase 2.1 — `DOPPLER_TOKEN_DEV_CI` secret check.** Before writing the workflow, verify the secret exists: `gh secret list | grep DOPPLER_TOKEN_DEV_CI`. If absent, document in the workflow's preamble that operator must `gh secret set DOPPLER_TOKEN_DEV_CI` after merge, and add a sibling step that gracefully fails with `secret_unset` mode (matching the `OAUTH_PROBE_GITHUB_CLIENT_ID` pattern at lines 285-290 of `scheduled-oauth-probe.yml`). Per `hr-never-paste-secrets-via-bang-prefix`: the operator sets the secret in a separate terminal, never via `!` prefix.

**Phase 2.2 — Dependency install strategy.** The probe script imports `@supabase/supabase-js` and `ws`. Choose ONE of:

(a) Full `npm ci` inside `apps/web-platform/` (~30-60s install; matches operator's local environment most closely).

(b) Minimal install: `npm install --no-save @supabase/supabase-js@2.99.2 ws@8.19.0` (faster, but version-drifts from `package-lock.json` and defeats the "catch supabase-js bumps" goal).

**Decision: option (a).** The whole point of this gate is to catch a supabase-js bump that re-triggers the race; we MUST install the same locked version the app does. Document in the workflow preamble: "This workflow installs the pinned `package-lock.json` versions deliberately — when `@supabase/supabase-js` is bumped via Dependabot/Renovate, the next nightly run is the canary."

**Phase 2.3 — Action SHA pinning.** All `uses:` actions pinned to commit SHA + version comment, matching `scheduled-oauth-probe.yml` style (`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`). Per `cq-action-sha-pin` if it exists; default repo convention either way.

**Phase 2.4 — strip_log_injection helper.** Copy the helper verbatim from `scheduled-oauth-probe.yml` lines 80-90. **DO NOT** extract to a shared composite action in this PR — the helper has been duplicated across `scheduled-oauth-probe.yml` for a reason (workflow self-containment, sparse-checkout simplicity). A follow-up issue can track DRY if it ever becomes painful.

**Phase 2.5 — Probe output capture.** The `realtime-probe.mjs` script writes `[probe NNNNms] SUBSCRIBED` on success and `TIMED_OUT`/`CLOSED` on failure. Capture stdout and grep for `SUBSCRIBED`. **DO NOT** rely on the script's exit code alone — script exits 0 on SUBSCRIBED, 3 on TIMED_OUT (verified in current source). Belt-and-suspenders: assert BOTH exit code 0 AND `SUBSCRIBED` token present. If they ever disagree, the failure mode is "script changed contract" not "race reproduced" — record as `probe_contract_drift` failure mode (distinct from `realtime_join_timeout`).

### Phase 3 — Learning-file breadcrumb

Add to `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md` under §Related:

```markdown
- `.github/workflows/scheduled-realtime-probe.yml` — nightly CI determinism gate (issue #3060). Runs the probe 5× against dev at 07:00 UTC daily; files a `ci/realtime-broken` tracking issue on any non-SUBSCRIBED.
```

### Phase 4 — PR Verification Plan

PR body MUST include:

1. Local integration test output (3/3 green, timing).
2. Local probe Mode A output (SUBSCRIBED <2s).
3. Local probe Mode B output (`--no-polyfill`, TIMED_OUT at ~10s — proves the bug still latent if polyfill removed).
4. `actionlint .github/workflows/scheduled-realtime-probe.yml` output (clean).
5. `yamllint .github/workflows/scheduled-realtime-probe.yml` output (clean).
6. After merge: link to first nightly run URL (or `workflow_dispatch` triggered run for immediate signal).

## Design Decisions

### D1 — Nightly probe vs. pre-merge integration job (issue #3060 §Asks)

Issue #3060 offered two options: (1) nightly probe, (2) pre-merge integration test on every PR. **Choosing (1).** Rationale:

- **Cost:** Pre-merge runs synthetic users via service-role on dev; rate-limit pressure scales with PR throughput. Nightly is bounded to 1 run/day.
- **Tightness of feedback loop vs. value:** The bug class we are guarding against is a `supabase-js`/`realtime-js` bump or upstream Realtime-broker change. Both are infrequent (weeks-to-months between bumps). A nightly gate catches them within 24h — more than tight enough.
- **Synthetic-user cleanup:** The integration test creates/destroys auth users. Running it 5× per CI invocation 50× per day amplifies cleanup-failure blast-radius. Probe-only (`channel('probe').subscribe`) needs zero auth-user create/destroy.
- **The right place for "every PR" gating is unit tests** — `node-websocket-polyfill.test.ts` already exists and runs in CI. The unit test asserts the polyfill's three behaviors deterministically. The nightly probe asserts the broker-side contract.

If the nightly fires 3+ true positives in 90 days, escalate to a hybrid (issue #3060's re-evaluation criterion).

### D2 — `realtime-probe.mjs` vs. running the integration test in CI

The probe is preferable for the nightly:

- **No auth dependency:** probe runs against the anon key only; no synthetic user create/destroy.
- **No DB-write side effects:** probe uses a `broadcast` channel, not `postgres_changes`. The integration test inserts/updates/deletes rows in `conversations`. Nightly CI should not be touching the dev database state.
- **Faster:** probe is <2s/run; integration test is ~11s + user setup.
- **The probe's `TIMED_OUT` signal IS the race detector.** That is the entire signal we need. The integration test asserts the wider contract (RLS + filter), but that contract is unit-tested + statically reasoned. The shell-environment race is what nightly is for.

### D3 — Why not extract the strip_log_injection helper

`scheduled-oauth-probe.yml` already contains this helper inline. Extracting to a composite action requires sparse-checkout of `.github/actions/`, which the OAuth probe already does. **Decision:** copy verbatim with a comment pointing at the source. Track DRY-up as a separate "platform" issue if/when a third workflow needs the same helper. Inline duplication of a 6-line helper across 2 workflows is better than two-PR delivery (composite-action PR + consumer PR) for one new workflow.

### D4 — Why this PR does NOT bump supabase-js

The fix-by-bump path was explicitly considered and ruled out in #3058's plan-review:

- `realtime-js@2.99.2`'s factory returns `unsupported` on Node <22 regardless of patch version.
- Bumping to a supabase-js that drops the `unsupported` branch (if one ever ships) is a coupled change with its own risk surface — auth API compatibility, RealtimeChannel type changes, etc.
- The polyfill is a 6-line helper with a unit test, zero prod-bundle risk (test-helpers-only path), and clear retirement criteria (the nightly going green without polyfill).

This PR holds that line.

## Test Scenarios

| # | Scenario | Test | Where |
|---|---|---|---|
| TS1 | Polyfill helper assigns when WebSocket undefined | `apps/web-platform/test/helpers/node-websocket-polyfill.test.ts` (already exists, 3/3 green) | Unit (vitest) |
| TS2 | Cross-tenant INSERT/UPDATE/DELETE return zero leaks | `conversations-rail-cross-tenant.integration.test.ts` (already exists, 3/3 green) | Integration (opt-in, dev) |
| TS3 | Probe Mode A reaches SUBSCRIBED in <2s | `scripts/realtime-probe.mjs` default mode | Manual + nightly CI |
| TS4 | Probe Mode B reproduces TIMED_OUT | `scripts/realtime-probe.mjs --no-polyfill` | Manual baseline (NOT in nightly — would always fail) |
| TS5 | Nightly workflow opens tracking issue on probe failure | Inject a forced-failure step locally via `act` or `workflow_dispatch` with a temporary `if: true` failure injection | Post-merge `gh workflow run` verification (PM1) |
| TS6 | Nightly workflow auto-closes stale tracking issue on green | After TS5, run again with the failure removed; assert the issue is closed | Post-merge sequential `gh workflow run` |

**No new unit/integration tests are added in this PR.** The nightly workflow's behavior is asserted by the post-merge `gh workflow run` step (PM1). Adding `act` coverage for the workflow itself is desirable but is a generic CI-test platform investment — track as follow-up if other workflows would benefit.

## Risks

### R1 — Doppler CLI install drift on GitHub-hosted runners

**Risk:** `curl -Ls --tlsv1.2 https://cli.doppler.com/install.sh` was deprecated in favor of `apt`-based install at some point; if the script breaks, the workflow's `doppler run` step fails with `command not found` rather than a probe-meaningful error.

**Mitigation:** Pin the Doppler install method to the exact pattern used in `scheduled-cf-token-expiry-check.yml` or `scheduled-content-vendor-drift.yml` (whichever installs the CLI). Inline the pinned install line; do NOT use `@latest`.

**Verification:** `grep -l "doppler" .github/workflows/*.yml` to find the canonical pattern at plan-implementation time.

### R2 — Dev project rate-limit on nightly anon-auth pings

**Risk:** Supabase free-tier dev project has request quotas; 5× probe runs/day is 35/week. Unlikely to hit, but not zero.

**Mitigation:** Probe uses no auth (`anon` key only), no DB writes, single ephemeral channel. Quota impact is negligible vs. the integration test's per-run user create/delete cost. Confirmed by reading the probe script source — no `from()` calls, no auth, just `.channel('probe').subscribe()`.

### R3 — Phoenix vsn protocol change on Realtime broker side

**Risk:** Supabase's Realtime broker could deploy a Phoenix v3 message format. The probe's failure mode would be the SAME `TIMED_OUT` signal — fail loud, not silent.

**Mitigation:** Already the design. The probe's `TIMED_OUT` is the canary regardless of which upstream variable drifts. Diagnosis is via the learning file's "When you should re-run this probe" section + Mode B baseline.

### R4 — Polyfill becomes unnecessary on Node 22+ runners

**Risk:** Node 22 ships native `globalThis.WebSocket`. If the workflow runner upgrades to Node 22, the polyfill is a no-op (it checks `typeof globalThis.WebSocket === 'undefined'` first) and the probe still passes. The polyfill helper would become dead code, but `cq-write-failing-tests-before` makes the unit test still pass.

**Mitigation:** Pin Node 21.7.3 in the workflow (matches operator workstation, matches the failing environment we want to protect against). When the team migrates to Node 22, that is a separate decision and the polyfill can be reviewed for retirement at that time.

### R5 — Nightly false-positives from intermittent dev outages

**Risk:** Supabase dev project has a maintenance window or transient outage during the 07:00 UTC cron tick. The probe trips, the workflow files a `ci/realtime-broken` issue, the operator wakes up to a phantom alert.

**Mitigation:** The probe runs 5× consecutively — a single 1s blip rarely catches 5 consecutive attempts. If the dev project is fully down, that IS something we want to know. Auto-close-on-green handles transient outages without operator intervention (matches OAuth probe pattern).

### R6 — `Closes #3060` could be premature

**Risk:** #3060's acceptance criteria require "after first scheduled/manual run completes successfully, link the run from this issue and close." If the first run fails, the PR's `Closes #3060` keyword has already fired and the issue is closed despite the gate not being green yet.

**Mitigation:** Per `hr-menu-option-ack-not-prod-write-auth` and the `wg-use-closes-n-in-pr-body-not-title-to` pattern for ops-remediation: split `Closes #3060` into the PR body conditional on PM1 succeeding. **Default plan stance: use `Ref #3060` in PR body and run `gh issue close 3060` manually after PM1 confirms success.** This is the same pattern as `type: ops-remediation` plans (Closes-after-apply, not Closes-at-merge). Same applies to #3049: use `Closes #3049` only if AC1-AC3 are documented in PR body with run output proving the contract green. Conservative default: `Ref #3049` + manual close after PM2 link.

### R7 — Plan's PR title "fix(realtime): ..." in title could trip auto-close if it includes `#3049`

**Risk:** Plan AC10 prescribes title `fix(realtime): close #3049 via nightly determinism gate (#3060)` — but the word "close" before "#3049" in the title would auto-close on merge regardless of whether the run is green (`wg-use-closes-n-in-pr-body-not-title-to` cites #3185 as the precedent).

**Mitigation:** Rewrite the title to avoid auto-close keywords entirely: `fix(realtime): nightly determinism gate (resolves #3049, #3060)`. The word `resolves` IS an auto-close keyword too (`close|fix|resolve` + s/d/sd). **Final title: `chore(realtime): nightly determinism gate for cross-tenant isolation`** — no auto-close keywords, no issue numbers in title. Body carries `Closes #3049` / `Closes #3060` on their own lines after the green runs are linked.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` against:

- `node-websocket-polyfill`
- `conversations-rail-cross-tenant`
- `realtime-probe`

Zero matches. No fold-in / acknowledge / defer decisions required.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — verification + CI infrastructure change. CTO is the implicit reviewer (engineering label), but the change is mechanical (mirror an existing workflow pattern), bounded to test/CI surfaces, and carries no architectural, product, marketing, legal, or financial implications. No domain leader spawn required.

Per `cq-agents-md-tier-gate` Step 1: this is a domain-scoped change (CI workflow + test-side verification). The relevant constraints already live in `scheduled-oauth-probe.yml` as working precedent, in `cq-test-fixtures-synthesized-only`, and in `hr-dev-prd-distinct-supabase-projects`. No AGENTS.md rule is needed.

## Files to Edit

- `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md` — add one line under §Related pointing at the new workflow (Phase 3).

## Files to Create

- `.github/workflows/scheduled-realtime-probe.yml` — new nightly workflow.

## Files Verified Present (not edited)

- `apps/web-platform/scripts/realtime-probe.mjs` — confirmed at this path; probe script consumed by workflow.
- `apps/web-platform/test/helpers/node-websocket-polyfill.ts` — confirmed; unchanged by this PR.
- `apps/web-platform/test/helpers/node-websocket-polyfill.test.ts` — confirmed; unchanged by this PR.
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts` — confirmed; unchanged by this PR.
- `.github/workflows/scheduled-oauth-probe.yml` — template source for new workflow.

## Out of Scope (Tracked or Acknowledged)

- **`supabase-js`/`realtime-js` version bump.** Out of scope. The nightly probe is the structural defense; a bump is a separate change with its own risk surface.
- **`act`-based pre-merge workflow self-test.** Out of scope. Track as a generic "test our scheduled workflows locally" platform issue if a third workflow needs it.
- **Extracting `strip_log_injection` to a shared composite action.** Out of scope. See D3.
- **Pre-merge integration job in CI.** Out of scope — issue #3060's option (2). See D1.
- **Polyfill retirement when Node ≥22 runners ship.** Out of scope. See R4.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with `threshold: none` + reason; deepen-plan should pass.
- Per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`: verify the new workflow YAML via `yamllint`/`actionlint`, NOT `bash -n` on the YAML file. `bash -n .github/workflows/scheduled-realtime-probe.yml` will fail on the YAML header (`name:`, `description:`-style) and mask whether the embedded shell is sound. For embedded-shell verification, extract the `run:` block and pipe to `bash -c`.
- Per `wg-use-closes-n-in-pr-body-not-title-to` and #3185 precedent: PR title MUST NOT contain `close|fix|resolve` followed by `#N`. AC10 forces a non-auto-close title.
- Per `hr-dev-prd-distinct-supabase-projects`: workflow MUST target `-c dev` only. Greppable assertion: `grep -E '\-c (prd|prod)' .github/workflows/scheduled-realtime-probe.yml` returns zero.
- Per `cq-when-a-plan-prescribes-dig` (if applicable): no `dig` in this workflow. `curl --max-time` is pinned inside the probe script's underlying ws library; no new curl call added.
- Per `wg-after-merging-a-pr-that-adds-or-modifies`: PM1 is the operator's responsibility immediately post-merge. Do NOT close #3049/#3060 until PM1 returns `conclusion: success`.

## Research Insights

- `scheduled-oauth-probe.yml` is the canonical template — file/comment dedup + email notify + auto-close-stale pattern is battle-tested.
- `realtime-probe.mjs` exit codes: `0` (SUBSCRIBED), `3` (TIMED_OUT), other non-zero (script error). Verified by reading the script.
- Doppler `dev` config has `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (used by the probe). Verified locally — `doppler run -p soleur -c dev -- node scripts/realtime-probe.mjs` works without `SUPABASE_SERVICE_ROLE_KEY` (probe doesn't need it).
- `actionlint` is installable via `brew install actionlint` or `go install github.com/rhysd/actionlint/cmd/actionlint@latest`. CI doesn't yet enforce it on every workflow, but plan AC5 requires local clean run.
- The learning file at `2026-04-29-supabase-phx-join-handshake-shell-environment.md` already has a §"When you should re-run this probe" section — the nightly automates two of its three triggers (supabase-js bump, Node upgrade), but the third (debugging "browser works, shell doesn't" symptoms) is still operator-initiated. No change needed there.

## Related

- Issue #3049 — this PR's primary close-out
- Issue #3060 — CI determinism gate (folded in as Phase 2)
- Issue #3052 — closed by PR #3058 on 2026-04-29
- PR #3058 — the polyfill fix (already on main)
- Plan `2026-04-29-fix-supabase-realtime-phx-join-timeout-from-shell-plan.md` — the original fix plan; this plan is the verification + hardening follow-through
- Learning `2026-04-29-supabase-phx-join-handshake-shell-environment.md` — root cause + workaround
- `scheduled-oauth-probe.yml` — template for the new workflow
