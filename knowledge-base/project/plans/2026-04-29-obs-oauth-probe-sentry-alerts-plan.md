---
title: "obs(auth): synthetic OAuth probe + Sentry alert rules for sign-in regressions"
type: feat
date: 2026-04-29
issue: 2997
related_prs: [2975, 2994, 3007]
related_issues: [2979, 2982, 3001]
requires_cpo_signoff: false
---

# obs(auth): synthetic OAuth probe + Sentry alert rules for sign-in regressions

Closes #2997.

## Overview

Issue #2997 tracks the **proactive enforcement layer** for the auth regression class
exposed by the #2979 → #2994 chain. PR #2994 added Sentry mirroring on every Supabase
auth failure path (`feature:auth, op:{exchangeCodeForSession, signInWithOAuth,
signInWithOtp, verifyOtp, callback_no_code, getUser_null_after_exchange}`), so the
error class is now **observable** in Sentry. But observability without paging means
the founder still needs to notice a Sentry event — exactly the gap that allowed the
#2979 build-arg regression to ship for hours before a user complaint surfaced it.

This plan closes that gap with two complementary detection layers:

1. **Synthetic OAuth probe** — a scheduled GitHub Action that hits the prod auth surface
   every 15 minutes from the cloud and files/comments on a P1 tracking issue + emails
   ops on failure. Detects DNS, redirect, and provider-availability regressions before
   any user is impacted.
2. **Sentry alert rules** — three issue-alert rules (configured via Sentry REST API)
   that page ops via email when real user traffic experiences elevated auth failures.
   Catches regressions the synthetic probe misses (per-user broken loops, downstream
   classifier drift, provider-side outages affecting only a subset of users).

The plan is **infrastructure-only** — no code paths in `apps/web-platform/` change.
The work lands as: one new workflow YAML, one new shell script for Sentry alert
configuration (idempotent), one new ops runbook, and the corresponding ship-time
post-merge step to invoke the alert-config script.

## Research Reconciliation — Spec vs. Codebase

The issue body referenced a few elements that need verification against current `main`:

| Spec claim                                              | Reality                                                                                                                                                                                                                                                                            | Plan response                                                                                                                                  |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| "Pattern: copy from `.github/workflows/main-health-monitor.yml`" | No `main-health-monitor.yml` exists. Closest patterns: `scheduled-cf-token-expiry-check.yml` (probe + dedup'd issue file/comment), `scheduled-terraform-drift.yml` (probe + email via `notify-ops-email`), `post-merge-monitor.yml` (Discord notify).                              | Use `scheduled-cf-token-expiry-check.yml` as the issue-file-or-comment skeleton and the `./.github/actions/notify-ops-email` composite for the email leg. Document this in the new workflow's header comment. |
| Sentry mirroring exists on five op tags                 | Confirmed — `git show main:apps/web-platform/app/(auth)/callback/route.ts` has `op:exchangeCodeForSession, op:callback_no_code, op:getUser_null_after_exchange`; `login/page.tsx` has `op:signInWithOtp, op:verifyOtp`; `oauth-buttons.tsx` has `op:signInWithOAuth`. All tag `feature:auth`. | Alert rule queries can rely on these tags as-is; add a drift-guard test that fails if any auth-error site stops emitting `feature:auth`. |
| Email notification via `.github/actions/notify-ops-email` | Confirmed — composite action exists at `.github/actions/notify-ops-email/action.yml`, uses `RESEND_API_KEY` from secrets, sends to `ops@jikigai.com`.                                                                                                                              | Reuse as-is.                                                                                                                                   |
| Sentry `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` available | Confirmed via `gh secret list` (set 2026-03-28).                                                                                                                                                                                                                                  | Configuration script consumes these. No new secrets.                                                                                            |
| `feature:auth AND op:exchangeCodeForSession` Sentry query syntax | Sentry **search API does not support `AND`/`OR` operators** (per learning `sentry-api-boolean-search-not-supported-20260406.md`). Tag filters are space-separated and AND-ed implicitly: `feature:auth op:exchangeCodeForSession`.                                                  | Plan prescribes `feature:auth op:<verb>` (no `AND`); alert-config script uses Sentry **issue-alert** API (`POST /api/0/projects/{org}/{project}/rules/`) which DOES use a structured `conditions` + `filters` + `actions` payload — not the search query string. Filter-by-tag value is one of the standard filter types. |

## User-Brand Impact

**If this lands broken, the user experiences:** Nothing immediately — both layers are
read-only observability. A failed-to-create alert rule means future regressions don't
page ops; a broken probe means false issue files (noisy), false silence (user sees
broken sign-in before ops does), or both. **The probe must fail closed** — if the
probe itself errors (HTTP timeout, DNS flake), it should NOT close any pre-existing
`ci/auth-broken` issue, because absence of evidence is not evidence of absence.

**If this leaks, the user's data is exposed via:** No direct PII vector — the probe
hits unauthenticated public endpoints (`/login`, `/auth/v1/authorize`, `/auth/v1/settings`).
The Sentry alert rules read existing tagged events; the existing `feature:auth` events
already drop `error.message` per learning `2026-04-28-sentry-payload-pii-and-client-observability-shim.md`, so Sentry alerts cannot widen the
exposure surface beyond what's already mirrored. **Indirect risk:** if an alert email
body echoes a Sentry issue title that contains user input, the `ops@jikigai.com`
inbox sees it. Mitigation: alert-config payload uses Sentry's built-in email action
(no template freedom) — Sentry's email contains the issue title only, which we
control via `feature` + `op` tags (no untrusted free-text).

**Brand-survival threshold:** `none` — this is detection-layer infrastructure. The
sensitive surface (auth) was already covered by `## User-Brand Impact` in PR #2994's
plan; this plan extends the surveillance, not the attack surface. Per preflight
Check 6 Step 6.1, the diff touches `.github/workflows/**` (not a sensitive path) and
adds a `scripts/configure-sentry-alerts.sh` (also not sensitive). No `requires_cpo_signoff`.

> A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
> text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
> deepen-plan or `/work`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1**: New workflow `.github/workflows/scheduled-oauth-probe.yml` exists with `cron: '*/15 * * * *'` and `workflow_dispatch:` for manual runs.
- [ ] **AC2**: Workflow probes (in order) — `/login`, `/auth/v1/authorize?provider=google&redirect_to=...`, `/auth/v1/authorize?provider=github&redirect_to=...`, `/auth/v1/settings` — and asserts the four conditions in the issue body.
- [ ] **AC3**: All `curl` invocations include `--max-time 10` (per Sharp Edges — unbounded network calls in CI).
- [ ] **AC4**: On any probe failure, the workflow either creates a new `ci/auth-broken`-labelled issue (label pre-created with `gh label create` on first run) or comments on the existing open one (dedup via `gh issue list --label ci/auth-broken --state open`). Issue title is the stable-tagged `[ci/auth-broken] Synthetic OAuth probe failed` for dedup; body includes timestamp, failure mode (DNS/redirect-host/missing-provider), and the offending response code/headers.
- [ ] **AC5**: On any probe failure, the workflow invokes `./.github/actions/notify-ops-email` with `RESEND_API_KEY` from secrets and a subject prefixed `[Soleur Ops] OAuth probe failure: <mode>`.
- [ ] **AC6**: On a clean probe run, if a stale open `ci/auth-broken` issue exists, the workflow auto-closes it with a comment citing the green-probe timestamp and HTTP results (per `scheduled-cf-token-expiry-check.yml`'s stale-issue close pattern).
- [ ] **AC7**: Workflow has `concurrency: { group: scheduled-oauth-probe, cancel-in-progress: false }` so concurrent dispatches queue, not race.
- [ ] **AC8**: New shell script `apps/web-platform/scripts/configure-sentry-alerts.sh` is **idempotent** — running it twice produces zero net changes. Idempotency via `GET /api/0/projects/{org}/{project}/rules/` → match by rule `name` (e.g., `auth-exchange-code-burst`) → `PUT` if found else `POST`.
- [ ] **AC9**: The script configures three Sentry **issue-alert rules** with the thresholds from the issue body (≥5 in 10m for `op:exchangeCodeForSession`, ≥3 in 10m for `op:callback_no_code`, >3 in 5m per-user for any `feature:auth`). Per-user rule uses Sentry's `event.unique_user_count` filter, not free-text search. All three actions are `mail.MailAction` to `ops@jikigai.com`.
- [ ] **AC10**: Script consumes `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` from environment; aborts (exit 1) with a clear error if any is unset. Region routing: detect EU vs US from the auth token by hitting `/api/0/users/me/` once and recording the resolved hostname (matches the learning's `de.sentry.io` vs `sentry.io` split).
- [ ] **AC11**: New ops runbook at `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` documents the on-call playbook for each failure mode (DNS, redirect-host wrong, provider missing, settings 404), cross-linking to PR #2975's NEXT_PUBLIC_SUPABASE_URL guardrail and PR #2994's classifier.
- [ ] **AC12**: A new test (vitest) at `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` greps every auth call site (`exchangeCodeForSession`, `signInWithOAuth`, `signInWithOtp`, `verifyOtp`, `callback_no_code`, `getUser_null_after_exchange`) for `feature: "auth"` and the matching `op: "<verb>"`. **This is a drift-guard** — if a future PR adds an auth call site without the tags, this test fails. Implementation: walk `apps/web-platform/app/(auth)`, `apps/web-platform/components/auth`, `apps/web-platform/server/` for files containing the call symbols and assert `feature: "auth"` is present in the same file.
- [ ] **AC13**: PR body uses `Closes #2997`. Both `## User-Brand Impact` and `## Domain Review` sections are present in the plan and surface in the PR via the lifecycle.
- [ ] **AC14**: All CI checks pass (lint, typecheck, vitest, GitHub Actions YAML lint via `actionlint` if present).

### Post-merge (operator)

- [ ] **PM1**: Operator runs `apps/web-platform/scripts/configure-sentry-alerts.sh` once locally with `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` from `~/.sentryclirc` (or `gh secret view`-equivalent for the token). Verifies via Sentry UI that three rules now exist under the `soleur-web-platform` project.
- [ ] **PM2**: Operator dispatches the new workflow once via `gh workflow run scheduled-oauth-probe.yml` (per `wg-after-merging-a-pr-that-adds-or-modifies` — new workflows must be verified working). Polls `gh run view <id> --json status,conclusion` until done. Expected result: probe is green (no issue filed, no ops email).
- [ ] **PM3**: Operator confirms via Sentry UI that the three rules show `Last triggered: never` and have correct conditions/filters/actions. Sanity check: temporarily lower the `op:callback_no_code` threshold to 1, dispatch a single bad-state probe (manually crafted curl that hits `/callback` with no code) to confirm the rule fires + email arrives, then restore threshold via re-running `configure-sentry-alerts.sh`.
- [ ] **PM4**: Operator closes #2997 manually (Pre-merge `Closes #2997` already auto-closes at merge — this is a confirmation step, not a separate close).

## Files to Create

- `.github/workflows/scheduled-oauth-probe.yml` — the cron probe workflow.
- `apps/web-platform/scripts/configure-sentry-alerts.sh` — idempotent Sentry alert-rule configurator.
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` — drift-guard test that auth call sites carry `feature:auth` + `op:<verb>` tags.
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — on-call runbook.

## Files to Edit

None expected. The plan is purely additive. If a `package.json` script wants a convenience entry (`bun run sentry:configure-alerts`), that is a follow-up; the script is designed to be runnable directly via `bash apps/web-platform/scripts/configure-sentry-alerts.sh`.

## Open Code-Review Overlap

1 open scope-out touches files this plan reads but does NOT modify:

- **#3001** — `review: clear stale sb-*-auth-token-code-verifier cookies on OAuth callback failure`. Touches `apps/web-platform/app/(auth)/callback/route.ts`. **Disposition: Acknowledge.** This plan adds detection-layer infrastructure (CI workflow + Sentry alert config + drift-guard test). It does **not** modify `callback/route.ts`. #3001's concern (cookie hygiene) is orthogonal and remains correctly scoped to the next auth-flow PR per its own re-evaluation trigger. No action in this plan.

## Implementation Phases

### Phase 1 — Workflow + ops runbook (½ day)

Mostly mechanical, copies `scheduled-cf-token-expiry-check.yml`'s skeleton.

**1.1** Create `.github/workflows/scheduled-oauth-probe.yml`:

```yaml
name: "Scheduled: OAuth Probe"

on:
  schedule:
    - cron: '*/15 * * * *'
  workflow_dispatch: {}

concurrency:
  group: scheduled-oauth-probe
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  probe:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      failure_mode: ${{ steps.probe.outputs.failure_mode }}
      failure_detail: ${{ steps.probe.outputs.failure_detail }}
    steps:
      - uses: actions/checkout@<sha-pinned> # match other workflows
      - id: probe
        env:
          APP_HOST: app.soleur.ai
          API_HOST: api.soleur.ai
        run: |
          set -uo pipefail
          # set +e: we collect failure mode and emit it as output, not as exit.

          fail_mode=""
          fail_detail=""

          record_failure() {
            fail_mode="$1"
            fail_detail="$2"
          }

          # 1. /login is reachable
          code=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "https://${APP_HOST}/login" || echo "curl_error")
          if [[ "$code" != "200" ]]; then
            record_failure "login_unreachable" "GET https://${APP_HOST}/login -> HTTP ${code}"
          fi

          # 2. Google OAuth redirect lands on accounts.google.com
          if [[ -z "$fail_mode" ]]; then
            url="https://${API_HOST}/auth/v1/authorize?provider=google&redirect_to=https%3A%2F%2F${APP_HOST}%2Fcallback"
            line=$(curl -sI --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}' "$url" || echo "curl_error")
            http=${line%% *}
            redirect=${line#* }
            redirect_host=$(printf '%s' "$redirect" | awk -F/ '{print $3}')
            if [[ "$http" != "302" || "$redirect_host" != "accounts.google.com" ]]; then
              record_failure "google_authorize" "GET ${url} -> HTTP ${http}, redirect_host=${redirect_host}"
            fi
          fi

          # 3. GitHub OAuth redirect lands on github.com
          if [[ -z "$fail_mode" ]]; then
            url="https://${API_HOST}/auth/v1/authorize?provider=github&redirect_to=https%3A%2F%2F${APP_HOST}%2Fcallback"
            line=$(curl -sI --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}' "$url" || echo "curl_error")
            http=${line%% *}
            redirect=${line#* }
            redirect_host=$(printf '%s' "$redirect" | awk -F/ '{print $3}')
            if [[ "$http" != "302" || "$redirect_host" != "github.com" ]]; then
              record_failure "github_authorize" "GET ${url} -> HTTP ${http}, redirect_host=${redirect_host}"
            fi
          fi

          # 4. /auth/v1/settings exposes google/github as enabled
          if [[ -z "$fail_mode" ]]; then
            tmp=$(mktemp)
            trap 'rm -f "$tmp"' EXIT
            http=$(curl -s --max-time 10 -o "$tmp" -w '%{http_code}' "https://${API_HOST}/auth/v1/settings" || echo "curl_error")
            if [[ "$http" != "200" ]]; then
              record_failure "settings_http" "GET https://${API_HOST}/auth/v1/settings -> HTTP ${http}"
            elif ! jq -e . "$tmp" >/dev/null 2>&1; then
              record_failure "settings_invalid_json" "GET https://${API_HOST}/auth/v1/settings -> non-JSON body (HTTP ${http})"
            else
              for prov in google github; do
                enabled=$(jq -r --arg p "$prov" '.external[$p] // false' "$tmp")
                if [[ "$enabled" != "true" ]]; then
                  record_failure "settings_provider_disabled" "external.${prov}=${enabled}"
                  break
                fi
              done
            fi
          fi

          # Sanitize for ::output:: (CR/LF strip — see PR #3007 sharp edge)
          fail_detail_safe="${fail_detail//[$'\n\r']/}"
          {
            echo "failure_mode=${fail_mode}"
            echo "failure_detail=${fail_detail_safe}"
          } >> "$GITHUB_OUTPUT"

      - name: File or comment on tracking issue (failure)
        if: steps.probe.outputs.failure_mode != ''
        env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
          FAIL_MODE: ${{ steps.probe.outputs.failure_mode }}
          FAIL_DETAIL: ${{ steps.probe.outputs.failure_detail }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          # ... ensure label, dedup-search by stable title, file-or-comment
          # (mirrors scheduled-cf-token-expiry-check.yml lines 130-188)

      - name: Email notification (failure)
        if: steps.probe.outputs.failure_mode != ''
        uses: ./.github/actions/notify-ops-email
        with:
          subject: "[Soleur Ops] OAuth probe failure: ${{ steps.probe.outputs.failure_mode }}"
          body: |
            <p><strong>Failure:</strong> ${{ steps.probe.outputs.failure_mode }}</p>
            <p><strong>Detail:</strong> ${{ steps.probe.outputs.failure_detail }}</p>
            <p><a href="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}">Run log</a></p>
          resend-api-key: ${{ secrets.RESEND_API_KEY }}

      - name: Auto-close stale issue (probe green)
        if: steps.probe.outputs.failure_mode == ''
        env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
        run: |
          # Find any open ci/auth-broken issue with the stable title and close
          # it with a comment citing this run's timestamp.
          # ...
```

**1.2** Create `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`:

Sections: Overview, Failure modes (one per `fail_mode` value), Diagnostic commands
(`gh secret list | grep NEXT_PUBLIC_SUPABASE_URL`, `dig +time=5 +tries=2 +short CNAME api.soleur.ai`,
Sentry query for last 24h `feature:auth`), Remediation procedures (cross-link to PR #2975 and #2994).

**1.3** Pre-create the `ci/auth-broken` label with `gh label create ci/auth-broken --description "Synthetic CI probe detected an auth-flow regression" --color B60205 || true`. The workflow's first failure-path step does this defensively too.

### Phase 2 — Sentry alert configurator script (½ day)

**2.1** Create `apps/web-platform/scripts/configure-sentry-alerts.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT must be set}"

# Region detection — Sentry has US (sentry.io) and EU (de.sentry.io) ingest
# clusters, and the API hostname follows the same split. Probe /users/me/ on
# both and pick whichever returns 200.
api_host=""
for candidate in sentry.io de.sentry.io; do
  http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${candidate}/api/0/users/me/")
  if [[ "$http" == "200" ]]; then
    api_host="$candidate"
    break
  fi
done
[[ -n "$api_host" ]] || { echo "ERROR: Sentry token not valid against either US or EU ingest" >&2; exit 1; }

# upsert_rule <name> <conditions_json> <filters_json> <actions_json> <frequency_minutes>
upsert_rule() {
  local name="$1" conditions="$2" filters="$3" actions="$4" freq="$5"

  # Find existing by name
  local existing
  existing=$(curl -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/" \
    | jq --arg name "$name" '.[] | select(.name == $name) | .id // empty' | head -1)

  local payload
  payload=$(jq -n \
    --arg name "$name" \
    --argjson conditions "$conditions" \
    --argjson filters "$filters" \
    --argjson actions "$actions" \
    --argjson freq "$freq" \
    '{name: $name, actionMatch: "all", filterMatch: "all", conditions: $conditions, filters: $filters, actions: $actions, frequency: $freq}')

  if [[ -n "$existing" ]]; then
    curl -s --max-time 10 -X PUT \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/${existing}/" \
      -d "$payload" >/dev/null
    echo "[ok] Updated rule '${name}' (id=${existing})"
  else
    curl -s --max-time 10 -X POST \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/" \
      -d "$payload" >/dev/null
    echo "[ok] Created rule '${name}'"
  fi
}

email_action='[{"id":"sentry.mail.actions.NotifyEmailAction","targetType":"Member","targetIdentifier":null,"fallthroughType":"AllMembers"}]'
# Note: To send to ops@jikigai.com specifically (not all members), use
# "targetType":"Team" or use a Sentry-managed alert email distribution list
# tied to that mailbox. Verify in PM3 step. Alternative: use
# "id":"sentry.rules.actions.notify_event_service.NotifyEventServiceAction"
# with a Resend-backed webhook (already wired via notify-ops-email).

# Rule 1: exchangeCodeForSession burst (>=5 in 10 min)
upsert_rule "auth-exchange-code-burst" \
  '[{"id":"sentry.rules.conditions.event_frequency.EventFrequencyCondition","value":5,"interval":"10m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"},{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"op","match":"eq","value":"exchangeCodeForSession"}]' \
  "$email_action" \
  10

# Rule 2: callback_no_code burst (>=3 in 10 min — likely uri_allow_list drift)
upsert_rule "auth-callback-no-code-burst" \
  '[{"id":"sentry.rules.conditions.event_frequency.EventFrequencyCondition","value":3,"interval":"10m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"},{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"op","match":"eq","value":"callback_no_code"}]' \
  "$email_action" \
  10

# Rule 3: per-user broken loop (>3 events from same user in 5 min on feature:auth)
upsert_rule "auth-per-user-loop" \
  '[{"id":"sentry.rules.conditions.event_unique_user_frequency.EventUniqueUserFrequencyCondition","value":3,"interval":"5m"}]' \
  '[{"id":"sentry.rules.filters.tagged_event.TaggedEventFilter","key":"feature","match":"eq","value":"auth"}]' \
  "$email_action" \
  5
```

> **Verify before shipping** (per Sharp Edges — CLI-form verification): the exact
> JSON shape for `conditions`, `filters`, and `actions` against `POST /api/0/projects/{org}/{project}/rules/`.
> Sentry's REST API for issue alerts is documented at <https://docs.sentry.io/api/alerts/create-an-issue-alert-rule-for-a-project/>.
> The `id` strings above (`sentry.rules.filters.tagged_event.TaggedEventFilter`,
> `sentry.rules.conditions.event_frequency.EventFrequencyCondition`,
> `sentry.rules.conditions.event_unique_user_frequency.EventUniqueUserFrequencyCondition`,
> `sentry.mail.actions.NotifyEmailAction`) are the well-known internal class paths
> that the Sentry UI generates and that the API accepts; verify each against the
> docs at implementation time. A failed POST returns a JSON `detail` field — log it.

**2.2** Pin the script's `bun run` / `bash` invocation in the runbook (PM1 step).
The script is **NOT** wired into CI — Sentry alerts are configuration that lives
in Sentry's database; the script is a one-shot that the operator runs after merge.
Future automation could wire this into `web-platform-release.yml` post-deploy, but
that's out of scope here.

### Phase 3 — Drift-guard test (¼ day)

**3.1** Create `apps/web-platform/test/auth/sentry-tag-coverage.test.ts`:

```typescript
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { glob } from "fast-glob"; // verify: already a dep — check apps/web-platform/package.json

const REPO_ROOT = resolve(__dirname, "../../");

// Source of truth: every site that calls a Supabase auth verb must mirror to
// Sentry with feature:auth. Walk all relevant directories — never trust a
// hardcoded list (per Sharp Edges).
const AUTH_DIRS = [
  "app/(auth)",
  "components/auth",
  "server",
];

const AUTH_VERBS = [
  "exchangeCodeForSession",
  "signInWithOAuth",
  "signInWithOtp",
  "verifyOtp",
];

describe("auth Sentry tag coverage", () => {
  it("every file calling an auth verb mirrors to Sentry with feature:auth", async () => {
    const files = await glob(
      AUTH_DIRS.map((d) => `${REPO_ROOT}/${d}/**/*.{ts,tsx}`),
      { absolute: true },
    );
    expect(files.length).toBeGreaterThan(0); // sanity

    const offenders: string[] = [];
    for (const file of files) {
      const src = readFileSync(file, "utf8");
      const verbsInFile = AUTH_VERBS.filter((v) => src.includes(`.${v}(`));
      if (verbsInFile.length === 0) continue;
      // File calls at least one auth verb — assert it also reports to Sentry
      // with feature:auth tag. The check is intentionally loose (no per-verb
      // op:<verb> assertion) so legitimate refactors don't churn the test.
      // The op-tag is exercised at runtime via Sentry alert rule firing during
      // PM3 (manual sanity check).
      if (!/feature:\s*["']auth["']/.test(src)) {
        offenders.push(`${file} calls ${verbsInFile.join(",")} without feature:"auth" Sentry mirror`);
      }
    }
    expect(offenders, offenders.join("\n")).toEqual([]);
  });

  it("every auth verb is paired with a matching op tag in the same file", async () => {
    // Stricter: per-verb op:"<verb>" presence. Catches the "Sentry mirror added
    // but op tag wrong/missing" drift class.
    const files = await glob(
      AUTH_DIRS.map((d) => `${REPO_ROOT}/${d}/**/*.{ts,tsx}`),
      { absolute: true },
    );
    const offenders: string[] = [];
    for (const file of files) {
      const src = readFileSync(file, "utf8");
      for (const verb of AUTH_VERBS) {
        if (!src.includes(`.${verb}(`)) continue;
        const opRegex = new RegExp(`op:\\s*["']${verb}["']`);
        if (!opRegex.test(src)) {
          offenders.push(`${file}: calls .${verb}() but missing op:"${verb}" in Sentry mirror`);
        }
      }
    }
    expect(offenders, offenders.join("\n")).toEqual([]);
  });
});
```

> Verify `fast-glob` (or whatever glob dep is in use) against `apps/web-platform/package.json`
> at implementation time. The repo already uses `glob` patterns elsewhere; reuse the same
> dep to avoid adding a new one.

### Phase 4 — Runbook + spec wrap (¼ day)

**4.1** Fill `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` with:

- Triage flowchart per `fail_mode`.
- Cross-links: PR #2975 (build-arg guardrail), PR #2994 (classifier + Sentry mirror), PR #3007 (anon-key guardrail), Issue #2982 (provider-disabled UI gating).
- Manual diagnostic recipes:
  - `gh secret view NEXT_PUBLIC_SUPABASE_URL` (for `redirect_host` failures pointing at a placeholder).
  - `dig +time=5 +tries=2 +short CNAME api.soleur.ai` (DNS drift detection).
  - Sentry API recipe: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/projects/$ORG/$PROJECT/issues/?statsPeriod=24h&query=feature:auth"` (note: no boolean `OR`, per `sentry-api-boolean-search-not-supported-20260406.md`).

**4.2** Add a Re-evaluation criterion line to the runbook (per #2997 Section 3): "When auth flows have been stable for 60 days post-merge AND sign-in MAU > 100 users, ratchet thresholds down: `auth-exchange-code-burst` 5→3, `auth-callback-no-code-burst` 3→2, per-user 3→2." Link this back to a calendar reminder via `/soleur:schedule` (out of scope for this PR, called out in Non-Goals).

## Test Scenarios

### TS1 — Probe green path (happy path)

- Run workflow via `gh workflow run scheduled-oauth-probe.yml`.
- Expect: `failure_mode` empty in step output; no issue file/comment; no email; no run-level error annotations.
- If a stale `ci/auth-broken` issue exists, expect: workflow comments `Probe green at <ts>` and closes it.

### TS2 — Probe failure: login unreachable

- Manually edit the workflow's `APP_HOST` env to `app-nope.soleur.ai` and dispatch.
- Expect: `failure_mode=login_unreachable`; one new `ci/auth-broken` issue filed; one ops email arrives; subsequent failure dispatches add comments to the same issue (dedup).

### TS3 — Probe failure: redirect host wrong (regression of #2979)

- Manually edit `API_HOST` to a domain that returns a redirect to a non-Google host.
- Expect: `failure_mode=google_authorize` with `redirect_host=<wrong>` in detail; issue+email as TS2.

### TS4 — Probe failure: provider disabled

- Manually mock `/auth/v1/settings` to return `{"external":{"google":false,"github":true}}` (or run against a fixture URL).
- Expect: `failure_mode=settings_provider_disabled` with `external.google=false`.

### TS5 — Sentry rule idempotency

- Run `apps/web-platform/scripts/configure-sentry-alerts.sh` twice in a row.
- Expect: first run logs `Created rule '...'` × 3; second run logs `Updated rule '...' (id=N)` × 3 with no semantic state change. Verify by listing rules before and after via `GET /api/0/projects/{org}/{project}/rules/` — the count and rule IDs are identical between runs.

### TS6 — Sentry rule fires (manual sanity, PM3)

- Temporarily override `auth-callback-no-code-burst` threshold to 1 via env override or hand-edit, re-run the script.
- Trigger a synthetic `feature:auth op:callback_no_code` event by hitting `/callback` (no `code` query param) once.
- Expect: ops email arrives within Sentry's flush interval (~1 min).
- Restore threshold via re-running the script.

### TS7 — Drift-guard test catches a missing tag

- Locally remove the `feature: "auth"` line from `apps/web-platform/components/auth/oauth-buttons.tsx`.
- Run `bun test apps/web-platform/test/auth/sentry-tag-coverage.test.ts`.
- Expect: test fails with the offender list naming `oauth-buttons.tsx`.
- Restore the line; test passes.

### TS8 — Drift-guard test catches a missing op tag

- Locally rename `op: "signInWithOAuth"` to `op: "oauth"` in `oauth-buttons.tsx`.
- Run the same test.
- Expect: test fails on the second `it()` with `calls .signInWithOAuth() but missing op:"signInWithOAuth"`.

## Risks

- **R1 (Sentry API contract drift).** The exact JSON shape for the alert-rule POST is not pinned here — the script encodes well-known class paths but the API may return 400 if a class path was renamed. Mitigation: the script logs the response body on non-2xx and exits 1; the operator runs the script manually first time (PM1), and the script's failure surfaces immediately. **Verify the docs URL** at implementation time per Sharp Edges.
- **R2 (Probe noise from external incidents).** Google/GitHub/Supabase outages would trip the probe and file an issue every 15 min until resolved. Mitigation: dedup logic comments-on-existing instead of creating-new (AC4); the email is rate-limited by Resend's per-recipient throttling and we can extend dedup to "skip email if same `failure_mode` was emailed in the last 60 min" if needed (deferred to follow-up — not blocking). Track as part of the 60-day re-evaluation in the runbook.
- **R3 (Per-user rule false positives).** A user retrying sign-in 4 times in 5 min for legitimate reasons (e.g., wrong email) would trigger the per-user rule. Mitigation: the rule fires on `feature:auth` events broadly — Sentry already groups these by error fingerprint, so the alert fires only if 3+ distinct errors hit. If false-positives accumulate, ratchet up to 5 in 5 min during the 60-day re-evaluation.
- **R4 (Sentry email destination).** The Sentry built-in `NotifyEmailAction` sends to project members; if `ops@jikigai.com` is not a Sentry team member, the email goes to a different inbox. Mitigation: PM3's manual sanity-fire confirms the email lands at the expected inbox; if it doesn't, the script can be amended to use `NotifyEventServiceAction` pointing at a Resend webhook (existing `notify-ops-email` composite). Verify before claiming AC11/PM3 satisfied.
- **R5 (Probe runs in geographic isolation).** GitHub-hosted runners are typically in `us-east-1` / `us-west-2` / Azure regions. A regional Supabase outage affecting EU users only might not be visible to the probe. Mitigation: out of scope here; document in the runbook as a known limitation. Future hardening: matrix the probe across `runs-on: ubuntu-latest` and a self-hosted EU runner, or use a Cloudflare Worker scheduled trigger.
- **R6 (Sentry tag drift outside auth dirs).** The drift-guard test scans `app/(auth)`, `components/auth`, `server/`. If a future PR moves an auth call into `lib/`, the test goes silent. Mitigation: AC12's first `it()` is a "files calling verbs" check — if no files match, it asserts `>0`, which would catch the directory-relocation case as long as the test imports stay accurate. Periodic review during the 60-day re-evaluation.

## Non-Goals / Out of Scope

| Item                                                | Why deferred                                                                                                      | Tracking issue                       |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Wire `configure-sentry-alerts.sh` into CI auto-deploy | Adds a Sentry write per release, increases blast radius. PM1 manual run is sufficient for this PR.              | File a follow-up if alerts drift.    |
| Provider-disabled UI hiding (Apple, Microsoft)      | Tracked in #2982. The probe only checks `google` + `github` per spec.                                             | #2982                                |
| Enabling Apple/Microsoft providers at Supabase      | Operator decision, separate from observability.                                                                   | (none — explicitly scoped out)       |
| Alert dedup (skip email if same `failure_mode` <60 min) | Adds state; deferred until R2 manifests.                                                                          | Will file if observed.               |
| Cloudflare Worker scheduled trigger (geographic coverage) | Larger refactor, requires CF Workers infra in Terraform.                                                          | Will file if R5 manifests.           |
| 60-day threshold ratchet                            | Time-gated re-evaluation. Document in runbook + schedule via `/soleur:schedule` after merge.                      | Schedule reminder via `/soleur:schedule`. |

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO observability)

### Engineering / CTO

**Status:** reviewed (passive — CTO domain leader not invoked because brainstorm
was not run; assessing inline as the brainstorm carry-forward proxy).
**Assessment:** This is a CI/observability change. No production code paths in
`apps/web-platform/` change. Architectural concerns:

1. **Detection layering** — the synthetic probe and the Sentry alert rules are
   complementary, not redundant. Probe catches infrastructure regressions before
   any user is impacted; alerts catch user-impact regressions the probe misses.
   Both wired correctly.
2. **Idempotency** — the Sentry script must be safe to re-run; the upsert pattern
   (find-by-name → PUT or POST) achieves this without depending on a local state file.
3. **Drift-guard** — AC12's grep test is a TS-strict-ish guard against future
   regressions of the `feature:auth` tagging contract that the alert rules depend on.
4. **No new secrets** — reuses `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`,
   `RESEND_API_KEY` already in `gh secret list`.

### Operations / COO observability

**Status:** reviewed (inline). **Assessment:** ops@jikigai.com is the existing
on-call inbox. The plan reuses the existing `notify-ops-email` composite for the
probe failure path. Sentry alerts will route via Sentry's built-in email action
to the same address (verified during PM3). No new ops surface area.

### Product/UX Gate

Tier: NONE. This is infrastructure with zero user-facing surface change.

## Sharp Edges

- **CR/LF strip on annotations** — when `failure_detail` includes response headers
  with embedded newlines, write to `$GITHUB_OUTPUT` after `${var//[$'\n\r']/}`
  (per learning `2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`
  session error 6 — log injection vector via untrusted JSON values into GHA
  annotations).
- **Bounded curl** — every `curl` invocation in the probe and the Sentry script
  uses `--max-time 10` (per Sharp Edges — unbounded network calls in CI).
- **Sentry search syntax** — alert-rule **filters** use a structured JSON
  `conditions`/`filters` payload (NOT the search query string), so Sentry's
  `AND`/`OR` non-support (`sentry-api-boolean-search-not-supported-20260406.md`)
  doesn't apply here. Still, the runbook's diagnostic recipes use the search API,
  and those MUST avoid boolean operators.
- **Probe time budget** — workflow `timeout-minutes: 5` is generous given the four
  curl calls cap at 10 s each (~40 s worst case). Don't tighten without a margin
  for runner cold-start.
- **Email destination** (R4) — verify in PM3. If `NotifyEmailAction` doesn't land
  at `ops@jikigai.com`, switch to `NotifyEventServiceAction` pointing at a Resend
  webhook tied to `notify-ops-email`.
- **`fast-glob` vs `glob`** — verify which glob library `apps/web-platform`
  already uses before importing one into the test (per Sharp Edges — never
  prescribe a new test framework / dep without confirming the convention).
- **Closes vs Ref** — this PR is observability infrastructure that is operational
  AT MERGE TIME (no operator action mandatory for code paths to start working —
  the workflow runs as soon as it's on `main`). Use `Closes #2997` in the PR body.
  PM1-PM4 are post-merge **verification** steps, not remediation, so the
  `Closes` semantics are correct (extends `wg-use-closes-n-in-pr-body-not-title-to`,
  not the ops-remediation exception).
- **Drift-guard scope (R6)** — `AUTH_DIRS` enumerates the directories where
  Supabase auth verbs are currently called. If a refactor moves them, update
  this list in the same PR.

## References

- Issue #2997 — this work item.
- Issue #2979 — the regression that motivated the proactive layer (closed).
- PR #2994 — added Sentry mirroring on five auth ops; learning at
  `knowledge-base/project/learnings/best-practices/2026-04-28-sentry-payload-pii-and-client-observability-shim.md`.
- PR #2975 — `NEXT_PUBLIC_SUPABASE_URL` build-arg guardrails.
- PR #3007 — anon-key JWT-claims guardrails (also used in this plan's runbook).
- Issue #2982 — provider-disabled UI hiding (referenced as Out-of-Scope).
- Issue #3001 — stale `code-verifier` cookie sweep (acknowledged as overlap, not folded in).
- Existing patterns:
  - `.github/workflows/scheduled-cf-token-expiry-check.yml` — issue file/comment + close-stale skeleton.
  - `.github/workflows/scheduled-terraform-drift.yml` — `notify-ops-email` integration.
  - `.github/actions/notify-ops-email/action.yml` — Resend-backed ops email composite.
- Learnings:
  - `knowledge-base/project/learnings/integration-issues/sentry-api-boolean-search-not-supported-20260406.md` — Sentry search syntax limitations.
  - `knowledge-base/project/learnings/integration-issues/sentry-zero-events-production-verification-20260405.md` — sanity-check before relying on Sentry signal.
  - `knowledge-base/project/learnings/integration-issues/sentry-dsn-missing-from-container-env-20260405.md` — DSN env-var hardening.
  - `knowledge-base/project/learnings/best-practices/2026-04-22-passive-sentry-signal-closes-followthrough-verification.md` — passive-signal verification model.
- Sentry docs (verify at implementation time):
  - <https://docs.sentry.io/api/alerts/create-an-issue-alert-rule-for-a-project/>
  - <https://docs.sentry.io/product/alerts/create-alerts/issue-alert-config/>
