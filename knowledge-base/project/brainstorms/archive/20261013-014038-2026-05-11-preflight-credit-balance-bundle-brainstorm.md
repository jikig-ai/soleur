---
name: Preflight credit-balance + compound-promote loop validation (bundle)
date: 2026-05-11
issues: [3604, 3605]
parent_pr: 3559
branch: feat-preflight-credit-balance-3605
draft_pr: 3606
status: ready-for-plan
---

# Preflight credit-balance soft-skip + first compound-promote loop validation

Bundle scoping for #3604 (follow-through: first weekly compound-promote cron tick
validates loop) and #3605 (bug: anthropic-preflight hard-fails on HTTP 400
"credit balance is too low"). Both surfaced post-merge of #3559.

## What We're Building

Two independent tracks, sharing context but not code:

- **Track A — #3604 validation (no code).** Operator topped up Anthropic credits
  on 2026-05-11. Trigger `scheduled-compound-promote.yml` via
  `workflow_dispatch` on `main` to exercise the end-to-end loop on real data.
  Either outcome qualifies as validated: (1) a cluster qualifies and a draft PR
  opens with `self-healing/auto` label and all gates green, or (2) no cluster
  qualifies and `promotion-log.md` is unmodified with the preflight job logging
  a clean no-op.

- **Track B — #3605 fix (this branch).** Extend the existing HTTP 400 soft-skip
  branch in `.github/actions/anthropic-preflight/action.yml` to match the
  credit-balance error message in addition to the spend-cap one. Operationally
  identical class (API unreachable for billing reasons), so identical code path
  and warning surface.

## Why This Approach

- **Independent tracks.** Track A validates a separate concern (the loop
  works on real data) from Track B (preflight classifies the third
  operational-failure class correctly). Coupling them in one PR would gate
  validation signal on review cycle time.
- **Stack OR over separate branch.** The two messages represent the same
  operational class — API unavailable for billing reasons, action is identical
  (soft-skip + warn). A separate branch would imply different handling,
  which is false. One-line diff, anchored on literal substrings (no regex
  metachar surface — both patterns are plain English).
- **No Sentry mirror.** `cq-silent-fallback-must-mirror-to-sentry` targets
  *silent* fallbacks. The existing soft-skip branches emit `::warning::` which
  surfaces in the workflow run UI and in `email-on-failure` aggregation — not
  silent. Matching the established #2715 pattern keeps the composite action
  free of `SENTRY_DSN` input plumbing.
- **Manual dispatch suffices for #3604.** The scheduled trigger and
  `workflow_dispatch` invoke the same workflow file and same gates. Waiting
  ~7 days for the scheduled tick adds nothing the manual run doesn't already
  cover; only the cron trigger itself is unexercised, which is a separate and
  much lower-risk concern.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Code shape (#3605) | Stack OR in existing HTTP 400 branch | Same operational class → same path. One-line diff, literal-substring grep, no regex surface. |
| Sentry mirror | Skip | `::warning::` is not silent; matches #2715 pattern; avoids `SENTRY_DSN` input plumbing in a composite action. |
| #3604 acceptance | Manual `workflow_dispatch` + green run | Same code path as scheduled cron. Draft PR opened OR clean no-op (`promotion-log.md` unchanged) both qualify. |
| Sequencing | Dispatch #3604 first, fix #3605 second | Independent risks → parallel tracks. Don't gate validation signal on review-cycle time. |
| Issue strategy | Bundle scope across both existing issues | Two OPEN issues already track the work. No umbrella issue. Brainstorm + spec are the single source of truth. |

## Non-Goals

- **No Sentry mirror retrofit** on spend-cap or 5xx branches. Surface-level
  consistency, not correctness — defer indefinitely unless a future silent
  failure proves the warning surface insufficient.
- **No new action input** for `SENTRY_DSN`. Keeps the composite action's
  contract stable.
- **No cron-trigger validation.** Manual dispatch exercises everything except
  the cron expression; the cron itself is GitHub Actions infrastructure, not
  our code. Out of scope.
- **No expansion to other 400 messages.** Only the two documented
  billing-class messages are matched. Future 400 classes (rate limits, model
  not found, invalid request) remain hard failures by design — those are
  bugs in our payload, not upstream operational issues.

## User-Brand Impact

Operator-facing only; no end-user data path. Worst case if the fix ships as
designed: alert noise from spurious red workflows continues on credit-low days
(unchanged from today, just rarer). Worst case if the regex over-matches: a
genuine API outage with a 400 body containing one of the two literal strings
gets soft-skipped, masking the loop's silent decay. Mitigation: literal
substring match (no metachars), both strings are operator-billing English
that won't appear in upstream API-outage 4xx bodies.

`USER_BRAND_CRITICAL=false` — keywords in framing answer negated user-data
and auth exposure. Trio spawn (CPO+CLO+CTO) skipped per Phase 0.1.

## Open Questions

None. Both tracks are ready for execution.

## Resume Plan

Track A — execute in Phase 4 of this brainstorm via `gh workflow run`.
Track B — proceed to `/soleur:plan` on this branch (or skip plan and one-shot
the 1-line fix since requirements are fully clear).
