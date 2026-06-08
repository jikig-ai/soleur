---
feature: shortform-feature-tweets
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 5021
plan: knowledge-base/project/plans/2026-06-08-feat-shortform-feature-tweets-plan.md
---

# Tasks — Short-Form Feature Tweets

## Phase 0: Preconditions (/work)
- [ ] 0.1 Verify `gh pr view <n> --json labels,title,url` and `gh pr diff <n> --name-only` field shapes against a real PR.
- [ ] 0.2 Confirm cumulative description budget headroom and the 1024-char per-skill limit in `plugins/soleur/test/components.test.ts` (cap currently 1984, zero headroom).
- [ ] 0.3 Re-read `plugins/soleur/skills/postmerge/SKILL.md` Phase 3 (L91 success / L93 warn branches) to place `HEALTH_VERIFIED`.

## Phase 1: Eligibility filter (brand-critical floor)
- [ ] 1.1 Write failing tests `scripts/lib/tweet-eligibility.test.sh`: eligible feature PR; each deny-label; each deny-path; **collision feature+user-facing+security → excluded**; **collision feature+user-facing + `**/migrations/**` → excluded**; unlabeled → excluded; gh-error → excluded.
- [ ] 1.2 Implement `scripts/lib/tweet-eligibility.sh <pr>`: labels via `gh pr view --json labels`, paths via `gh pr diff --name-only`; require `user-facing`+`type/feature`; deny labels/paths short-circuit to excluded regardless of allow-set; fail-closed on error/empty.
- [ ] 1.3 Green: all eligibility tests pass.

## Phase 2: feature-tweet skill
- [ ] 2.1 Create `plugins/soleur/skills/feature-tweet/SKILL.md` (description ≤25 words, ≤1024 chars).
- [ ] 2.2 Flow: idempotency check (existing `pr_reference`) → eligibility → fetch PR → generate ≤3 numbered tweets per brand-guide `### X/Twitter` + `#### Ship Tweets` with sanitization → read author from `site.json` → write draft file (`status: draft`, `channels: x`, `pr_reference`, publish comment) → structural assertion → lint.
- [ ] 2.3 Structural assertion (skill-owned): require non-empty title + `status: draft` + `channels: x` + `## X/Twitter Thread` heading; abort + leave no file on miss.

## Phase 3: postmerge hook
- [ ] 3.1 Set `HEALTH_VERIFIED=true|false` in both Phase-3 branches of postmerge SKILL.md.
- [ ] 3.2 Add Phase 3.8 (after 3.7): eligibility-first; if eligible + `HEALTH_VERIFIED=true` → invoke skill + surface draft path in Phase 7 report; if eligible + false → print catch-up instruction; ineligible → no-op.
- [ ] 3.3 Document the explicit one-tweet-per-PR v1 contract + merge-pr-bypass recovery.

## Phase 4: brand-guide voice
- [ ] 4.1 Add `#### Ship Tweets (feature-launch)` under `### X/Twitter` cross-referencing Audience Voice Profiles + Value Proposition Framings.

## Phase 5: extractor count-assertion
- [ ] 5.1 Add test to `test/content-publisher.test.ts`: 1-tweet→1, 3-tweet→3.

## Phase 6: stale-draft visibility + budget
- [ ] 6.1 Edit `campaign-calendar/SKILL.md`: "Stale Draft" group for `draft` files > N days (default 7), oldest-first.
- [ ] 6.2 Bump `SKILL_DESCRIPTION_WORD_BUDGET` by the new description word count with `// #5021` comment (primary; sibling-trim fallback).

## Phase 7: Verify
- [ ] 7.1 Run `./node_modules/.bin/vitest run test/content-publisher.test.ts plugins/soleur/test/components.test.ts` (or package runner) — green.
- [ ] 7.2 Run `bash scripts/lib/tweet-eligibility.test.sh` — green.
- [ ] 7.3 Manual: generate one sample draft on an eligible PR; review sanitization (no PII/customer/diff detail); lint clean.
- [ ] 7.4 All Pre-merge ACs checked.

## Post-merge (operator)
- [ ] Operator approval gate: review surfaced draft → set BOTH `publish_date` + `status: scheduled` → existing cron publishes.
