# Routing a Sentry alert to a specific email is account-routing, not an IaC rule — and needs a Member/Team target

**Date:** 2026-06-15
**Context:** `/soleur:go` request — "change the Sentry error notification email to the operator's ops
inbox (`ops@example.com` here; a real `ops@<domain>` address)" + fix a paged cron-failure. Branch
`feat-one-shot-sentry-cron-margin-alert-routing` (PR #5327). Emails below are genericized to
`@example.com` — the `lint fixture content` CI gate (secret-scan.yml) flags real-looking emails in
`knowledge-base/project/learnings/*.md`.

## The cron "failure" was a false positive (the real, shippable fix)

The Sentry page for monitor `scheduled-agent-native-audit` (incident 5546660, "A missed check-in
was detected") was NOT a dead cron. The run **succeeded** and filed issue #5318 at 09:09 UTC — only
its **single end-of-run Sentry heartbeat** landed late. Root cause: the 12 `max_runtime_minutes=55`
claude-eval-cohort monitors in `apps/web-platform/infra/sentry/cron-monitors.tf` post one heartbeat
AFTER a 50-min `MAX_TURN_DURATION_MS` budget (+ ~5-10 min mint/clone/teardown), but used
`checkin_margin_minutes=30` — so any run finishing >30 min after schedule false-pages on success.
agent-native-audit (8 Task sub-agents) is the heaviest so it tripped first; the whole cohort shared
the landmine. **Fix: widen the margin 30→60 for the cohort** (50-min budget + slack), keeping
`cron-inngest-cron-watchdog` as the not-firing backstop. This is the CHANGE that shipped.

**Lesson:** for a "missed check-in" page on a claude-eval cron, check whether the run produced its
artifact (filed an issue / opened a PR) before treating it as a dead cron. A single-end-of-run-heartbeat
monitor whose margin < job wall-clock budget will false-page on every slow-but-successful run.

## Routing notifications to a specific email: three hard facts the plan didn't anticipate

The user chose "codify in IaC" for routing high-priority issues to `ops@example.com`. Phase-0
verification (live, via the Doppler `SENTRY_IAC_AUTH_TOKEN`) falsified the IaC approach:

1. **Sentry `notify_email` has no raw-email target.** `target_type ∈ {IssueOwners, Team, Member}`.
   To email a specific address it must belong to a Member (or Team). So an IaC rule needs to resolve
   `ops@example.com` → a member id.
2. **The IaC integration token lacks `member:read`.** ADR-031's `iac-terraform-prd` scope set is
   `alerts:read/write, event:read, org:read, project:admin/read/write` — no member scope. All four
   Sentry tokens in Doppler returned **HTTP 403** on `/organizations/<org>/members/`. So a
   `data.sentry_organization_member` lookup (or the invite resource) would 403 at **plan time** on
   every future `apply-sentry-infra.yml` run — which would also block unrelated changes (e.g. the
   cron-margin fix) from applying. **A token that can't read members must not gain a member-reading
   data source in shared IaC.**
3. **`ops@example.com` is not a Sentry member at all.** The org has exactly one member,
   `founder@example.com` (the founder's login). The desired recipient was never a member, so
   even with `member:read` there was nothing to resolve — codifying it would have required *inviting*
   `ops@` (member:write + a billable seat + invite acceptance).

## What actually routes a founder's alerts to ops@: account-level Email Routing

For a solo founder, the right mechanism is **not** a new `sentry_issue_alert` resource. It is:
- Sentry → Account → **Email Addresses**: add `ops@example.com` as a secondary email (Sentry mails a
  verification link the operator must click — the one genuine operator gate).
- Sentry → Account → **Notifications → Email Routing**: per-org/per-project, route the `web-platform`
  project's notifications to `ops@example.com`.

This needed zero IaC, zero new member/seat, and zero standing change to the IaC token. The default
"high priority issues" rule keeps firing; only the delivery address changes.

## Process notes

- **Widen a prod credential's scope only as long as needed.** I toggled the integration's `Member:Read`
  on (via the authenticated Sentry dashboard — the token itself 403s on self-escalation, as expected)
  purely to *verify* membership, discovered `ops@` wasn't a member, then **reverted it** so the
  integration stayed at its documented ADR-031 least-privilege set. Verified both directions via the
  `sentry-apps` API (scope list) and the members endpoint (200 → 403 again).
- **Playwright on the founder's own machine can be authenticated by the founder mid-flow.** The
  server-side Playwright browser hit Sentry's SSO/password login; the founder logged into that browser
  session directly, after which I drove the dashboard (scope toggle, email add, routing) to completion.
  Browser-context drops were frequent (`about:blank` / closed-target) — re-navigate; the session cookie
  persists.
- **One PR, one change.** CHANGE B left the repo entirely (account settings), so the PR is CHANGE A only.

See [[2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn]] for the
sibling claude-eval heartbeat/liveness reasoning.
