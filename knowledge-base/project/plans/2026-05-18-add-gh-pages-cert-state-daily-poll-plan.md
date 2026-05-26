---
title: "feat(infra): daily GitHub Pages cert-state poll with Sentry heartbeat + auto-issue (PR-γ)"
date: 2026-05-18
type: feature
classification: ci-ops
lane: single-domain
status: planned
branch: feat-one-shot-cert-state-poll
related_workflows:
  - .github/workflows/scheduled-gh-pages-cert-state.yml
  - .github/workflows/apply-sentry-infra.yml
  - .github/workflows/scheduled-cf-token-expiry-check.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
related_issues: [3976, 3974, 3986]
precedent_incident: "2026-05-18 soleur.ai GitHub Pages cert silent expiry — zero advance warning"
requires_cpo_signoff: false
---

# feat(infra): daily GitHub Pages cert-state poll with Sentry heartbeat + auto-issue (PR-γ)

## Summary

On **2026-05-18** the soleur.ai marketing site went 526 because the GitHub Pages-managed Let's Encrypt cert silently expired. Recovery shipped as **PR #3974** (Terraform: ACME-aware HTTPS upgrade) and **PR #3986** (inline ACME rules into the seo_page_redirects ruleset to dodge the Cloudflare phase rule cap), and the operator runbook landed in **issue #3976**. The class-level finding was that NOTHING in the org polls GitHub Pages cert state — GitHub publishes `https_certificate.state` and `https_certificate.expires_at` on `GET /repos/{owner}/{repo}/pages`, but no alert reads it. **Had we polled daily, we would have had 21 days of advance warning instead of zero.**

This PR (PR-γ in the post-incident triplet) adds that poll as a new scheduled workflow `scheduled-gh-pages-cert-state.yml`, firing daily at 03:00 UTC, alerting via Sentry Crons heartbeat (existing `.github/actions/sentry-heartbeat` composite — used by 7 other scheduled-*.yml) on either of:

1. `state` not in `{approved, issued}`
2. `expires_at < now() + 21 days`

When either condition trips, the workflow ALSO auto-files a GitHub issue (idempotent via title-prefix dedup, mirrors the `scheduled-cf-token-expiry-check.yml` pattern) labeled `action-required` + `infra-drift`, body inlining the recovery runbook lifted from issue #3976 (PM5 step — the actionable "trigger Pages cert reissue" section).

Companion PR-β (running in parallel) adds uptime + 5xx alerting via Terraform — explicitly out of scope here.

## User-Brand Impact

**If this lands broken, the user experiences:** the soleur.ai marketing site silently going dark again the next time GitHub's ACME order fails or the cert hits 90-day expiry — exactly the 2026-05-18 failure mode this PR is preventing. The new poll's failure modes (false-negative: workflow ran but cert state regressed without firing the issue; false-positive: cert is healthy but issue still files) are CI-only and operator-visible — they do NOT touch any user-facing surface (`https://soleur.ai/`, `https://www.soleur.ai/`, `https://app.soleur.ai/`). The 21-day warning window is wide enough that even one missed daily fire (margin: `checkin_margin_minutes = 240` in the Sentry monitor) still leaves >2 weeks of operator response time.

**If this leaks, the user's data/workflow/money is exposed via:** N/A. The workflow reads a public GitHub endpoint (`/repos/{owner}/{repo}/pages` — same data visible in repo Settings → Pages to anyone with `metadata: read` on the repo) via the workflow's built-in `${{ github.token }}` (no new secret, no user data). The issue body inlines only operator-runbook text (cert state values, no PII, no credentials). Sentry receives a ping-only heartbeat (no payload).

**Sensitive-path scope-out:** `apps/web-platform/infra/sentry/cron-monitors.tf` matches `apps/[^/]+/infra/` (preflight Check 6 sensitive-path regex). This PR modifies it in the same shape as PR #3964/#3971 — adding ONE new `sentry_cron_monitor` resource for the new scheduled workflow — no schema/runtime/secret change. `threshold: none, reason: adds a single sibling cron-monitor resource using the established template (8 existing resources in cron-monitors.tf), no IaC behavior change beyond surface-area expansion.`

## Acceptance Criteria

- **AC1 — Workflow file exists at canonical path.** `.github/workflows/scheduled-gh-pages-cert-state.yml` exists; `name:` is `"Scheduled: GH Pages cert state"`; `on:` includes both `workflow_dispatch:` (manual trigger for end-to-end validation) and `schedule: - cron: '0 3 * * *'` (daily 03:00 UTC).
- **AC2 — Polls only soleur.ai's serving repo.** Workflow polls `GET /repos/${{ github.repository }}/pages` exactly once per fire — `github.repository` resolves to `jikig-ai/soleur` (the only repo in the org serving GitHub Pages with a custom domain; CNAME = `soleur.ai`, verified at `plugins/soleur/docs/CNAME`). No other Pages-served domain exists in the org; if one is later added, a new resource block + workflow follows the same shape.
- **AC3 — Trip conditions match spec.** Workflow exits non-zero (and posts `?status=error` to the Sentry heartbeat) when EITHER `state` not in the set `{approved, issued}` OR `expires_at < now() + 21d`. Both conditions evaluated in the same step; either flips `HEARTBEAT_STATUS` to `error` and triggers the issue-file branch.
- **AC4 — Sentry heartbeat fires on every run.** The workflow's final step `uses: ./.github/actions/sentry-heartbeat` with `status: ${{ steps.poll.outputs.heartbeat_status || 'error' }}` under `if: always()`. The composite action is the existing reusable one used by `scheduled-oauth-probe`, `scheduled-realtime-probe`, `scheduled-daily-triage`, `scheduled-skill-freshness`, `scheduled-content-vendor-drift`, and 2 sister workflows (per `grep -rln "uses:.*sentry-heartbeat" .github/workflows/`).
- **AC5 — Sentry cron-monitor IaC resource added.** `apps/web-platform/infra/sentry/cron-monitors.tf` gains a `sentry_cron_monitor.scheduled_gh_pages_cert_state` resource matching the template of the 8 existing sibling resources: `name = "scheduled-gh-pages-cert-state"` (Sentry-slug-equal to MONITOR_SLUG), `schedule = { crontab = "0 3 * * *" }`, `checkin_margin_minutes = 240` (4-hour margin absorbs daytime GHA cron jitter; daily cadence leaves >2 weeks response time on missed-fire), `max_runtime_minutes = 10`, `failure_issue_threshold = 1` (daily cadence — a single miss is itself noteworthy, matches sibling daily monitors), `recovery_threshold = 1`, `timezone = "UTC"`. The corresponding `terraform apply` invocation in `.github/workflows/apply-sentry-infra.yml` gets the new `-target=sentry_cron_monitor.scheduled_gh_pages_cert_state \` line added to the targeted-plan list.
- **AC6 — Auto-issue is idempotent via title-prefix dedup.** When trip condition is met, the workflow uses `gh issue list --search "in:title \"[cert-poll] soleur.ai cert state\""` to find existing open issues. If one exists → `gh issue comment` with the current `state` + `expires_at` + UTC timestamp; if none → `gh issue create` with title `[cert-poll] soleur.ai cert state = <STATE> (expires <DATE>)` and labels `action-required,infra-drift`. Pattern lifted verbatim from `scheduled-cf-token-expiry-check.yml` lines 87–138.
- **AC7 — Issue body inlines runbook from #3976.** The auto-filed issue body inlines the PM5 step from issue #3976 verbatim (`Trigger GitHub Pages cert reissue` — `gh api -X DELETE /repos/jikig-ai/soleur/pages/builds` + `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` verification block + expected `bad_authz → authorized → issued` progression). Body also cross-references #3976, PR #3974, PR #3986, and the 2026-05-18 incident date as the precedent.
- **AC8 — Auto-recovery: closes stale issue when cert returns healthy.** When the next poll observes `state ∈ {approved, issued}` AND `expires_at >= now() + 21d`, ANY open issue matching the title prefix is auto-closed with a comment containing the current healthy state + `days_remaining`. Mirrors the cf-token-expiry pattern (lines 130–138).
- **AC9 — Concurrency + permissions are scoped minimally.** `concurrency: { group: scheduled-gh-pages-cert-state, cancel-in-progress: false }` (no overlap risk on a daily cron, but matches the sibling pattern). `permissions:` declares `issues: write` (file/comment/close) and `metadata: read` (the `/repos/{owner}/{repo}/pages` endpoint requires `metadata: read` per GitHub Pages API docs). No `contents: write`, no `actions: write`, no other surface.
- **AC10 — No new secrets introduced.** Workflow reuses `${{ github.token }}` for the `gh api` + `gh issue` calls, and the existing Sentry repo secrets (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`) for the heartbeat. Zero new secret-vault entries required.
- **AC11 — Workflow self-tests via `workflow_dispatch` before cron lands.** Per the `scheduled-cf-token-expiry-check.yml` pattern (cron initially commented out, manual-dispatch only until end-to-end validation), the cron line MAY land commented-out on first merge IF the operator wants to validate manually first — BUT per AC5 the Sentry monitor resource MUST land active on the same PR (the monitor wouldn't fire until a fresh check-in arrives — first check-in IS the first manual `workflow_dispatch` run). **Default chosen for this PR:** cron line LIVES active on first merge (it's a daily fire, low blast radius, the value is the 21-day warning starting NOW). The `apply-sentry-infra.yml` cron-target list ALSO gets updated in the same PR to keep IaC ↔ workflow shipped together.
- **AC12 — Precedent is cited.** PR description AND the new workflow's leading header comment cite issue #3976, PR #3974, PR #3986, and the 2026-05-18 incident — framing the value prop as "21-day warning instead of zero" exactly per the user's framing.

## Files to Edit / Add

| Path | Action | Why |
|---|---|---|
| `.github/workflows/scheduled-gh-pages-cert-state.yml` | **ADD** | The poll itself. Modeled on `scheduled-cf-token-expiry-check.yml` (closest shape: external-state poll → conditional issue-file + Sentry heartbeat). |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | **EDIT** | Add `sentry_cron_monitor.scheduled_gh_pages_cert_state` resource (one new block matching the sibling template). |
| `.github/workflows/apply-sentry-infra.yml` | **EDIT** | Add `-target=sentry_cron_monitor.scheduled_gh_pages_cert_state \` to the targeted-plan list so the new resource gets applied on next merge to main. |

## Sharp Edges

1. **`metadata: read` vs `pages: read`.** The `/repos/{owner}/{repo}/pages` endpoint is documented under "Pages" but the token permission is the broader `metadata: read` (fine-grained PAT scope; for `GITHUB_TOKEN` in Actions, this is implicit). Verified in the GitHub REST API docs: the endpoint requires the token to have read access to the repo's metadata; no `pages` scope toggle exists on the workflow `permissions:` block. We declare `metadata: read` explicitly even though it's already the default.
2. **`expires_at` may be `null` for non-issued states.** When `state == "bad_authz"` (the 2026-05-18 case) GitHub returns `null` for `expires_at`. The state-condition trip fires first and bypasses the date arithmetic; the workflow MUST short-circuit (`if state-not-healthy → flip status, skip date math`) rather than `date -d "null"` throwing. Tested via `gh api /repos/jikig-ai/soleur/pages | jq` against the live endpoint pre-merge (current state should be `issued` post-PR-#3986 recovery — verify in /work step).
3. **Auto-issue body must use literal heredoc with escaped backticks.** The PM5 code block embedded in the issue body contains backticks; the surrounding `BODY=$(cat <<ISSUE_BODY ... ISSUE_BODY)` uses an unquoted-LHS heredoc which DOES NOT shell-expand inside (the un-quoted form `<<ISSUE_BODY` enables `$VAR` expansion; the quoted form `<<'ISSUE_BODY'` disables it). The cf-token-expiry workflow uses the unquoted form to interpolate `$EXPIRES_AT`, `$DAYS_REMAINING`, `$GH_REPO` — we follow the same pattern, just with our own variables.
4. **No `incident` label exists in this repo.** Per `gh label list --limit 200`: `action-required`, `infra-drift`, `priority/p0-critical`, `compliance/critical` are the available critical-ops labels. The user's task said "Label: `incident` (or whatever the repo's incident label is — check `.github/labels.yml` or existing incident issues)". `.github/labels.yml` does not exist (no central label config). We use `action-required,infra-drift` — `action-required` matches the cf-token-expiry precedent (operator must rotate / investigate) and `infra-drift` flags the IaC observability surface. The `gh label create` defensive pre-create call (cf-token pattern, line 119) is replicated for both labels with `2>/dev/null || true` so first-run on a fresh fork still files cleanly.
5. **Sentry monitor billing pre-flight.** Per the 2026-05-15 sentry-iac-billing-and-quirks learning, NEW `sentry_cron_monitor` resources consume from the project's monitor seat quota. The 8 currently-active monitors in `cron-monitors.tf` + this 9th + the `scheduled-cf-token-expiry-check` reserved seat (currently breadcrumb-only) = 10 monitors. Sentry's free-tier plan allows 5; the project must be on a plan supporting ≥10. The `apply-sentry-infra.yml` apply step will surface a clear error if quota is exceeded (`429 Quota exceeded` from the provider). Flagged for operator review — if a seat upgrade is needed, this is THE point to surface it (the cost-of-inaction is 2026-05-18 happening again).
6. **`actions/checkout` not needed.** The workflow runs `gh api` + `gh issue` (server-side) and `uses: ./.github/actions/sentry-heartbeat` (local composite action). The composite action's `uses: ./.github/actions/...` form REQUIRES `actions/checkout` to have run earlier in the same job — verified by reading PR #3971's rollout commits. Workflow MUST include `actions/checkout` as step 1 (with `persist-credentials: false` since the workflow doesn't push) before any `uses: ./.github/actions/sentry-heartbeat` call.

## Test Scenarios

The workflow does not have unit tests (it's a GH Actions YAML — exercised via `workflow_dispatch` in CI). Verification is two-pronged:

### Scenario 1: dry-run via `workflow_dispatch` against the live API (post-merge)

After merge, operator triggers via `gh workflow run scheduled-gh-pages-cert-state.yml`. Expected:

- Step `poll` logs: `Cert state: issued; expires at <DATE>; days_remaining: <N>`.
- Step `poll` outputs `heartbeat_status=ok` (since post-PR-#3986 the cert is healthy).
- Step `Sentry heartbeat` succeeds (curl exit 0, `?status=ok` POSTed).
- No issue filed.
- If a stale issue from a prior trip is open, it gets auto-closed (AC8).

### Scenario 2: forced-trip via mocked state (yamllint + dry-run)

We verify trip logic statically by setting `STATE_OVERRIDE=bad_authz` (an env var the workflow accepts ONLY when `github.event_name == 'workflow_dispatch'`, gating the override to manual-only invocation):

- Step `poll` short-circuits the date math (Sharp Edge #2), logs `Cert state: bad_authz — alert condition tripped`.
- Step `poll` outputs `heartbeat_status=error`.
- `Sentry heartbeat` POSTs `?status=error`.
- `gh issue create` fires with the expected title/body/labels (dedup-search returns 0).
- On the second forced-trip run, `gh issue comment` fires (not create) — dedup confirmed.
- Operator manually closes the test-only issue with a comment noting "Manual `workflow_dispatch` smoke-test issue — closing".

The `STATE_OVERRIDE` knob lives behind `if: github.event_name == 'workflow_dispatch'` — cron-driven fires CANNOT trip the override. This is the canonical CI-safe pattern: smoke-test the alert path without waiting 90 days for a real cert expiry.

## Out of Scope

- **Uptime + 5xx alerting** (PR-β, running in parallel). The Sentry uptime check on `https://soleur.ai/` + `https://www.soleur.ai/` + ACME-probe path is PR-β's deliverable per the post-incident triplet split in issue #3976's "Follow-up PRs" section.
- **Multi-repo Pages-poll fan-out.** Only `jikig-ai/soleur` serves a custom domain via GitHub Pages (verified at `plugins/soleur/docs/CNAME` — single CNAME = `soleur.ai`). If a second Pages-custom-domain repo is later added to the org, this workflow's `github.repository` substitution makes it trivially-portable (copy + change cron offset + add monitor resource), but until that day, fan-out is YAGNI.
- **Cert reissue automation.** The auto-filed issue's runbook is operator-driven (PM5 — `gh api -X DELETE /repos/{owner}/{repo}/pages/builds` requires a higher-scope token than the workflow has — Pages-builds delete requires `pages: write` AND a PAT, NOT the workflow's `GITHUB_TOKEN`). Auto-reissue is a future enhancement once the operator-side rotation policy is settled.

## References

- **Precedent incident:** 2026-05-18 soleur.ai apex cert silent expiry — recovered via PR #3974 + PR #3986; runbook at issue #3976.
- **Sentry HTTP Crons heartbeat docs:** `docs.sentry.io/product/crons/getting-started/http/`.
- **GitHub Pages API:** `docs.github.com/en/rest/pages/pages#get-a-github-pages-site` — exposes `https_certificate.state` and `https_certificate.expires_at`.
- **Pattern source:** `.github/workflows/scheduled-cf-token-expiry-check.yml` (external-state poll → conditional issue-file + Sentry heartbeat — the canonical template for this class of workflow).
- **Composite action:** `.github/actions/sentry-heartbeat/action.yml` (introduced by PR #3964/#3971, used by 7 sister workflows).
- **IaC pattern:** `apps/web-platform/infra/sentry/cron-monitors.tf` (8 existing `sentry_cron_monitor` resources serve as the sibling template).
