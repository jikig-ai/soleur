---
title: "Tasks — alpha-tester cohort program"
feature: feat-alpha-tester-value-loop
issue: "#8880"
plan: knowledge-base/project/plans/2026-09-25-feat-alpha-tester-cohort-program-plan.md
date: 2026-09-25
---

# Tasks

## Phase 0: Immediate (operator, parallel — NOT gated on this PR)

- [ ] 0.1 File tester #1's overdue 2-week checkpoint (aggregate KB growth + self-reported usage, disclosed as such)
- [ ] 0.2 Execute #7459 terms re-notify (TC 2.5.0→2.5.1)
- [ ] 0.3 Create beta-CRM contact for Skouer (owner-authenticated RPC path — platform is serving)
- [ ] 0.4 C9 controller/processor re-run per #7348 (precondition to tester #2's first session)
- [ ] 0.5 Retro problem interview with tester #1, flagged post-exposure (never pooled with #1440)

## Phase 1: Plugin decision capture + welcome fix

- [ ] 1.1 `plugins/soleur/scripts/emit-decision.sh` — allowlisted JSONL emit to `.soleur/decisions.jsonl`; `.soleur/.gitignore` self-guard; `printf >>` append (no lock); ~5MB rotate; kill-switch; `--selfcheck` → `SOLEUR_EMIT_OK`; bash-3.2/macOS-safe (no flock/jq/GNU-isms)
- [ ] 1.2 `plugins/soleur/scripts/emit-decision.test.sh` — write/ignore/rotate/kill-switch/selfcheck/concurrent-append coverage
- [ ] 1.3 `plugins/soleur/commands/go.md` — prose emit line after routing decision (`route_decision`, single-writer) + coverage disclosure
- [ ] 1.4 `plugins/soleur/hooks/welcome-hook.sh` — drop the `plugins/soleur` dir guard; keep Codex bail + sentinel dedupe
- [ ] 1.5 `plugins/soleur/test/welcome-hook.test.ts` — re-pin to new semantics + second-repo sentinel test

## Phase 2: Onboarding flow v2

- [ ] 2.1 `alpha-tester-onboarding.md` v2 — hosted path steps, Slack channel step, `arm-checkpoint.sh` arming (date-embedded ids, operator @mention), quiet protocol + `nudged_at`, tester-#1 repair checklist, recruitment update (screening question, non-CC first, channel:framing, stall fallback), day-0 emit verify, cohort_key runbook record, exit-interview section (#1443: WTP $49 + testimonial opt-in + nudge disclosure)
- [ ] 2.2 `scripts/arm-checkpoint.sh` — POSTs `checkpoint-tester-N-<date>` + `cohort-quiet-tester-N` via `/api/internal/schedule-reminder` (env-read secret); prints armed ids
- [ ] 2.3 `plugins/soleur/docs/alpha-tester-setup.md` — tester-facing setup doc (Anthropic key walkthrough, OTP/spam note, OAuth steering, GitHub skip path, 3 starter prompts, Slack link)
- [ ] 2.4 Welcome-message block updated (copywriter drop-in; immutable legal paragraphs verbatim)
- [ ] 2.5 `knowledge-base/marketing/recruitment-messaging-templates.md` — screening question appended to each DM variant

## Phase 3: Cohort instrumentation

- [ ] 3.1 Migration `141_users_cohort_key.sql` + `.down.sql` — column + CHECK `^[a-z0-9-]+$` + LAWFUL_BASIS annotation + COMMENT
- [ ] 3.2 `app/api/admin/cohort/route.ts` PATCH (ADMIN_USER_IDS + service client, lowercase normalize) + test
- [ ] 3.3 `app/api/admin/analytics/route.ts` + `lib/analytics.ts` — `?cohort=` scope; `.in("user_id", …)` before the 10k cap; extend funnel/metrics tests
- [ ] 3.4 `cohort-quiet` in CHECK_REGISTRY — quiet predicate: `GREATEST(created_at,last_active) ≥ 3d` non-failed OR zero-conversations + signup_age ≥ 3d; plus `cohort_key IS NULL` recent-signup list; company-level output to `report_to_issue`
- [ ] 3.5 `plugins/soleur/scripts/alpha-metrics.sh` + `.test.sh` — aggregates + `SOLEUR_EMIT_ABSENT`/`SOLEUR_EMIT_EMPTY`; awk/grep/sed only
- [ ] 3.6 `plugins/soleur/skills/cohort-status/SKILL.md` — runbook-table tally + gh-issue stage + derived reminder ids; UNREADABLE-on-failed-read; issue-title sanitizer; description ≤30 words; README counts
- [ ] 3.7 `ADR-251-*` (provisional) — decision-log substrate, surface→instrument table, residency pin, frozen allowlist
- [ ] 3.8 `model.c4` — plugin/hooks container gains `.soleur/` sink line; C4 tests pass

## Phase 4: Repair verification sweep

- [ ] 4.1 Verify each Phase-0 item closed; update runbook repair checklist
- [ ] 4.2 Confirm tester #2 preconditions green (#7348 C9, #7459 closed, CRM record exists)
