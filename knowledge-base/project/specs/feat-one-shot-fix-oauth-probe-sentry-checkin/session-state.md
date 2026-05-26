# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-18-fix-scheduled-oauth-probe-sentry-checkin-plan.md
- Status: complete

### Errors
None.

Notable plan-time catches handled inline during deepen-plan:
- User-Brand Impact gate fired on the `apps/web-platform/infra/sentry/cron-monitors.tf` sensitive-path regex hit at `threshold: none`; canonical `threshold: none, reason:` scope-out bullet added (would have failed `preflight` Check 6 at ship time).
- Cited PR #3814 did not resolve (`gh pr view 3814` → 404); corrected to PR #3811 (`feat: adapt Sentry integration to Monitors/Alerts split`) in both AC15 and the Open Code-Review Overlap section.
- AC10 operator-surface "grep sweep" replaced with plan-time enumerated file:line pairs after grep-walking `knowledge-base/engineering/`, `apps/web-platform/infra/sentry/README.md`, and root docs. Three additional sites surfaced and added to `Files to Edit`: `oauth-probe-failure.md:237`, `github-app-drift.md:339`, plus an explicit scope-out for `legal/audits/sentry-migration-audit-2026-05-15.md:13` (historical artifact).
- AC4 clarified that Sentry's documented heartbeat form is GET (`curl "${URL}?status=ok"`); POST retained for repo-consistency. Avoids /work-time pivot.
- AC6 noted that in heartbeat-only mode `max_runtime_minutes` has no effect (Sentry detects only missed runs, not overages); retained for schema/sibling-consistency against `jianyuan/sentry v0.15.0-beta2`.

### Decisions
- **Scope held at single workflow + its monitor + the directly-referenced runbook(s).** Seven sister workflows share the same `|| true`-wrapped in_progress → CHECKIN_ID → PUT silent-fail shape; sister-workflow rollout filed as a post-merge follow-up (label `code-review` + `priority/p2-medium`).
- **Cadence: `*/15 * * * *` → `0 * * * *`; monitor `checkin_margin_minutes 5 → 30`.** Grounded in 12 measured GHA fires showing median ~65 min daytime, ~3–4 h overnight gaps. Margin covers daytime jitter; overnight degradations remain real-signal at `failure_issue_threshold = 2`.
- **Heartbeat shape (single end-of-job check-in) replaces two-step in_progress → ok.** Drops the silent-fail trap (empty CHECKIN_ID → skipped ok), the tmpfile, and the `|| true`. Preserves `continue-on-error: true` at YAML tier while making curl exit-code observable in the step log.
- **Brand-survival threshold: none with explicit scope-out** for the `cron-monitors.tf` sensitive-path hit. Observability-tier change; user-facing probe behavior preserved bit-for-bit.
- **#3236 (cross-workflow heartbeat review) folded as `Closes #3236`** in PR body. Nominally resolved by PR #3811, never `gh issue close`'d; this PR makes the resolution real.

### Components Invoked
- Skill: `soleur:plan`
- Skill: `soleur:deepen-plan`
- Tools: Bash (gh CLI, grep sweeps, terraform lockfile read, telemetry emit), WebFetch ×3 (Sentry Crons HTTP docs), WebSearch ×1, Read/Edit/Write.
- Reference learnings consulted: `2026-05-15-sentry-iac-billing-and-quirks.md`, `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`, `2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md`, `2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`.
