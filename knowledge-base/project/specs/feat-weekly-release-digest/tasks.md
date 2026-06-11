# Tasks: Weekly Community Release Digest (#5080)

Derived from `knowledge-base/project/plans/2026-06-10-feat-weekly-release-digest-plan.md`
(post-5-agent-review, single PR, PR-2 extras cut → #5136).

## Phase 0 — Preconditions (probes, no code)

- [x] 0.1 Discord probes (read-only): record `#releases` channel id; probe `MANAGE_WEBHOOKS`
      (`GET /channels/<id>/webhooks`) AND message-read (`GET /channels/<id>/messages?limit=1`)
- [x] 0.2 Confirm `ANTHROPIC_API_KEY` present in Doppler prd (read-only)
- [x] 0.3 Confirm release-notes shape via `gh api repos/jikig-ai/soleur/releases?per_page=5`

## Phase 1 — Failing tests first

- [x] 1.1 Create `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts`
      (vitest; relative `./_cron-shared` import; no `*/N` in JSDoc)
- [x] 1.2 Heartbeat assertion mechanism: shape-valid Sentry env + mocked fetch `?status=error`,
      OR `vi.mock("./_cron-shared")` + call-args assertion
- [x] 1.3 Encode Test Scenarios 1–8 (window boundary `(start, end]`; partition fixtures
      `vinngest-v1.1.12` + `telegram-v0.1.1`; sanitize incl. email/Co-Authored-By; curate
      fallback in-step; single renderer escape-then-truncate; post failure → ok:false SENT;
      quiet week; constant↔brand-guide byte sync)

## Phase 2 — Handler (3 step.runs + handler-level catch)

- [x] 2.1 `fetch-releases`: minted token `permissions: { contents: "read" }, repositories: ["soleur"]`;
      window math inline (pure); partition `/^v\d/` + `/^web-v\d/`; sanitize inline
      (author/@handle/email/Co-Authored-By strip; security down-detail regex incl.
      xss/rce/injection; body truncation)
- [x] 2.2 `curate`: direct Anthropic call, concrete ID `claude-sonnet-4-6`, never-downgrade
      ADR-053 comment citing #5106; prompt rules as authoritative module constant (NO file
      read); LLM returns `{highlights}` only; failure caught IN-step → fallback marker
- [x] 2.3 `post-discord`: single renderer over `{highlights, remainder}` (quiet week = empty
      highlights); escape BEFORE truncate; `allowed_mentions: {parse: []}`; username
      "Soleur Releases"; POST via new shared `postDiscordWebhook` helper in `_cron-shared.ts`;
      `DISCORD_RELEASES_WEBHOOK_URL` ONLY (no fallback); missing/empty/non-2xx → THROW
      (preserves `retries: 1`)
- [x] 2.4 Handler-level try/catch (cron-weekly-analytics TAIL precedent): catch → best-effort
      `postSentryHeartbeat({ ok: false, sentryMonitorSlug, cronName, logger })` → return
      error result (never rethrow); success → ok:true iff POST 2xx
- [x] 2.5 Registration: `retries: 1`, cron-platform concurrency, `0 15 * * 5` + manual-trigger
      event (cron syntax NOT in JSDoc header)

## Phase 3 — Five-registry lockstep + egress evidence

- [x] 3.1 `app/api/inngest/route.ts` import + entry; count test 52→53
- [x] 3.2 `cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS` entry
- [x] 3.3 `function-registry-count.test.ts` route-count bump
- [x] 3.4 `cron-monitors.tf`: `cron_weekly_release_digest` (name byte-identical; crontab
      `0 15 * * 5`; margin 30 / runtime 10 / thresholds 1 / UTC; header comment)
- [x] 3.5 `apply-sentry-infra.yml` `-target` line (preceding line ends with `\`)
- [x] 3.6 `cron-egress-allowlist.txt` evidence comments for api.anthropic.com + discord.com

## Phase 4 — Brand guide + compliance + hygiene

- [x] 4.1 Add copywriter-authored `#### Release Digest` subsection verbatim after
      brand-guide.md:283; unit test asserts constant byte-sync (AC10)
- [x] 4.2 `compliance-posture.md` Anthropic vendor-row scope note (AC12, `grep -ci`)
- [x] 4.3 ADR-053 header typo fold-in (self-titles "ADR-051")

## Phase 5 — Provisioning (pre-merge, in-session)

- [x] 5.1 Create `#releases` webhook via bot API (URL parsed in-shell, never echoed)
- [x] 5.2 If 403 (N/A — MANAGE_WEBHOOKS present, no 403): grant path or operator click-path (secret → Doppler directly, never chat)
- [x] 5.3 Doppler prd write `DISCORD_RELEASES_WEBHOOK_URL` (explicit operator ack first)
- [x] 5.4 Verify AC11 live-webhook probe (`GET /webhooks/{id}/{token}` → 200 + channel_id)
- [x] 5.5 Rotation runbook line incl. `gh workflow run web-platform-release.yml` redeploy

## Phase 6 — Post-merge (after `gh pr ready` + merge)

- [ ] 6.0 Gate: BOTH `web-platform-release.yml` AND `apply-sentry-infra.yml` success for the
      merge commit BEFORE any trigger (create-conflict hazard)
- [ ] 6.1 Cadence announcement: operator-approved copy → #general + #releases; DM offer to
      affected member; outcome recorded in ship summary
- [ ] 6.2 Verification trigger: digest asserted via bot message read; monitor config + check-in
      via Sentry API (`apps/web-platform/scripts/sentry-monitors-audit.sh`)
- [ ] 6.3 `gh issue edit 5080`: Phase 4 milestone, priority/p2-medium

## Phase 7 — Deferral tracking

- [x] 7.1 Deferred-scope-out issue #5136 created (role/majors/persistence; re-evaluation
      criteria + reviewer-endorsed shapes) — done at plan time 2026-06-10

## Exit gates

- [ ] AC1–AC13 pre-merge green (see plan); `tsc --noEmit` + full vitest suite
- [ ] AC14–AC17 post-merge verified
