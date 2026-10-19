---
title: "chore: Schedule test-suite-weight-warn distribution draft for 2026-10-20 publication"
type: chore
date: 2026-10-19
slug: chore-schedule-test-suite-weight-warn-draft
branch: feat-one-shot-schedule-test-weight-tweet
issue: none
closes: none
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
detail_level: MINIMAL
---

# chore: Schedule test-suite-weight-warn distribution draft for 2026-10-20 publication

The distribution-content draft `knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md`
is complete and ready to publish. This change flips its YAML frontmatter to the scheduled
state so the daily `cron-content-publisher` Inngest function posts it on the next run.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-19
**Sections enhanced:** Research Insights, Test Scenarios
**Research agents used:** none — no Task/Agent tool in this planning subagent; all
verification ran inline (gate checks, corpus greps, both linters, `gh` PR/issue probes,
skill-convention cross-checks).

### Key Improvements

1. Executed both linters at plan time (`validate-tweet-draft.sh` rc=0, `lint-distribution-content.sh` rc=0)
   and recorded that the validator's post-edit exit-1 is by design (it asserts `status: draft`).
2. Confirmed the draft matches the `feature-tweet` SKILL.md template verbatim and the
   `social-distribute` scheduling procedure (set `publish_date`, flip `status` to `scheduled`).
3. Verified cited provenance live: PR #10578 (`feat(test-review): unweighed subprocess-fan-out
   WARN rule…`) is MERGED — the tweet's "Just shipped" claim is accurate; issue #9771 is CLOSED.
4. Surfaced the merge-timing caveat: the file must reach `main` before 2026-10-20 14:00 UTC
   or the next run stale-flips it.

### New Considerations Discovered

- Deepen-plan halt gates 4.6–4.12 all pass: User-Brand Impact present with `none` threshold
  (non-sensitive path), pure-docs file set (Observability skipped), no PAT-shaped tokens,
  no UI surface, no store/connection, no guard deliverable, Scope Check compliant (1 unfenced
  section, all rows mapped, `Recommendation: single PR`).

## Overview

Set two frontmatter fields in the existing draft:

- `publish_date: ""` → `publish_date: "2026-10-20"`
- `status: draft` → `status: scheduled`

The publisher (`scripts/content-publisher.sh`, driven by
`apps/web-platform/server/inngest/functions/cron-content-publisher.ts`, cron
`0 14 * * *` UTC at `cron-content-publisher.ts:835`) scans
`knowledge-base/marketing/distribution-content/` each run and publishes files where
`status == "scheduled"` AND `publish_date == today` (`content-publisher.sh:884-896`). A
scheduled file whose `publish_date` is in the past is flipped to `status: stale`
(`content-publisher.sh:888-891`). Current UTC time at plan-writing is 2026-10-19 ~23:00 —
today's 14:00 UTC run already passed, so `2026-10-20` is the minimum date that publishes
rather than stales.

## Research Insights

**Premise validation (Phase 0.6):** all cited artifacts verified against the worktree.

- Draft file exists with `publish_date: ""` and `status: draft`
  (`2026-10-19-test-suite-weight-warn.md:4,6`) — confirmed.
- Cron registration `{ cron: "0 14 * * *" }` at
  `apps/web-platform/server/inngest/functions/cron-content-publisher.ts:835`; labeled
  "Daily 14:00 UTC" in `apps/web-platform/server/inngest/routine-metadata.ts:60` — confirmed.
- Publish gate `[[ "$status" == "scheduled" ]]` then `[[ "$publish_date" == "$today" ]]`,
  stale flip on `[[ "$publish_date" < "$today" ]]` at `scripts/content-publisher.sh:884-896`
  — confirmed.
- `get_frontmatter_field` (`content-publisher.sh:101`) strips surrounding double quotes, so
  the quoted form `publish_date: "2026-10-20"` parses to `2026-10-20` — the quoted style
  matches the file's existing `publish_date: ""` and corpus convention.
- `date -u` = 2026-10-19 22:5x UTC: today's run is past; `2026-10-20` (a Tuesday, matching
  the publisher's Tue/Thu slot convention in `content-promotion.ts`) is the correct value.
- Double-book scan: no other file under `distribution-content/` carries
  `publish_date: 2026-10-20` — no slot collision.
- Linter coverage: `scripts/lint-distribution-content.sh` (Liquid-marker guard, also wired
  as lefthook `distribution-content-liquid-guard` on `knowledge-base/marketing/distribution-content/*.md`,
  `lefthook.yml:494-497`) and `scripts/lib/validate-tweet-draft.sh` (draft-structure gate)
  both cover this file.

**Property List (Phase 0.6b):**

1. The draft is picked up by the next daily publisher run and posts to its declared channels.
2. The draft is NOT stale-flipped (its `publish_date` must not be `< today` at the run that sees it).

**Cut List (Phase 0.6b):** none — the ask proposes no new mechanism; the frontmatter flip
uses the existing publisher. Nothing to cut.

**Institutional learnings applied:**

- `2026-06-15-content-publisher-bluesky-is-single-post-x-is-threaded.md` — X splits on `N/`
  boundaries (280 chars each); Bluesky posts the whole `## Bluesky` section as ONE post,
  hard-truncated at 300 chars. Measured this draft: X posts are 196/168/173 chars, Bluesky
  section is 218 chars — all within limits, no truncation.
- The draft's own comment (`:11`) states the release mechanism: "To publish: set BOTH
  publish_date AND status: scheduled" — the plan does exactly that.

**Ordering constraint discovered (SpecFlow inline pass):**
`scripts/lib/validate-tweet-draft.sh:60-63` asserts `status: draft` and exits 1 on any other
value — it is the draft-TIME gate. It must be run BEFORE the frontmatter flip; running it
after `status: scheduled` fails by design, not by defect. Ran it at plan-write time
2026-10-19: exit 0 (draft is structurally sound: title present, `channels: x, bluesky`,
both sections non-empty). `lint-distribution-content.sh` also ran at plan-write time:
exit 0.

**Merge-timing caveat:** `status: scheduled` with `publish_date: 2026-10-20` must reach the
publishing checkout BEFORE 2026-10-20 14:00 UTC. If this PR lands on `main` after that run,
the file sits scheduled with a past date and the next run (2026-10-21 14:00 UTC) flips it to
`stale` — it would then need a re-schedule edit, not just a merge.

## User-Brand Impact

- **If this lands broken, the user experiences:** the already-drafted X thread + Bluesky post
  silently does not publish on 2026-10-20 — either a missed slot (recoverable by re-scheduling)
  or a `stale` flip if the merge lands after tomorrow's 14:00 UTC run.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff
  is two frontmatter fields on an artifact whose content is already final and publicly
  intended; the publish itself is the existing cron's job.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** a missed or delayed marketing post is a routine,
  reversible scheduling miss — the content is unchanged by this diff, so no single-user
  incident is reachable from it.

## Files to Edit

- `knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md` —
  frontmatter only: `publish_date: ""` → `publish_date: "2026-10-20"`,
  `status: draft` → `status: scheduled`.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` searched for the planned file path;
zero matches.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "set `publish_date: \"2026-10-20\"` and `status: scheduled` in its YAML frontmatter" | Files-to-Edit entry | mapped |
| 2 | "Verify the file passes scripts/lint-distribution-content.sh and scripts/lib/validate-tweet-draft.sh if those linters cover this file" | AC-2 + Test Scenarios | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Frontmatter edit on `2026-10-19-test-suite-weight-warn.md` | "set `publish_date: \"2026-10-20\"` and `status: scheduled` in its YAML frontmatter" | asked |
| Pre-edit run of `validate-tweet-draft.sh` | "Verify the file passes … scripts/lib/validate-tweet-draft.sh" | asked — ordered before the flip because the script asserts `status: draft` (validate-tweet-draft.sh:60-63) |
| Post-edit run of `lint-distribution-content.sh` | "Verify the file passes scripts/lint-distribution-content.sh" | asked |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base` (first path segment)
- Planned files: 1 | Estimated changed lines: 2
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: `knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md`
  frontmatter reads `publish_date: "2026-10-20"` and `status: scheduled`; all other
  frontmatter fields and body content are byte-identical to before the edit.
- [ ] AC-2: `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md`
  exits 0 after the edit (no Liquid/Jinja markers in body).
- [ ] AC-3: No other file under `knowledge-base/marketing/distribution-content/` is modified;
  `campaign-calendar.md` is NOT hand-edited (it is auto-generated from frontmatter).

## Domain Review

**Domains relevant:** none

The diff is scheduling metadata on an already-drafted, operator-approved artifact — no
marketing judgment (copy, positioning, channel mix) is exercised by this change; the
publish date was operator-directed and verified against cron semantics. (Note: domain-leader
subagent fan-out was unavailable in this planning context — assessment is inline.)

## Test Scenarios

- `bash scripts/lib/validate-tweet-draft.sh knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md`
  (pre-edit only — asserts `status: draft`) → exit 0. Already run at plan-write time
  2026-10-19: exit 0. Post-edit this script is EXPECTED to exit 1 with
  `invalid: 'status' must be 'draft'` — a deterministic negative check that also confirms
  the flip took. [integration — deterministic command]
- `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md`
  (post-edit) → exit 0. Already run at plan-write time 2026-10-19: exit 0.
  [integration — deterministic command]
- `grep -cE '^publish_date: "2026-10-20"$' knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md`
  → `1`; `grep -cE '^status: scheduled$' ...` → `1`. [integration — deterministic command]
- Given the file merged to `main` before 2026-10-20 14:00 UTC, when `cron-content-publisher`
  runs at `0 14 * * *`, then `publish_date == today` holds and the file posts to X + Bluesky
  and flips `status: published`. [manual/time-gated — cannot be exercised locally; the
  semantic is pinned by `content-publisher.sh:884-896`]

## Context

- Publisher gate + stale logic: `scripts/content-publisher.sh:884-896`
- Cron registration: `apps/web-platform/server/inngest/functions/cron-content-publisher.ts:835`
- Field parser (quote-stripping): `scripts/content-publisher.sh:101`
- The draft file itself documents the release mechanism in its body comment (`:11`).
- Lefthook pre-commit `distribution-content-liquid-guard` (`lefthook.yml:494-497`) re-runs
  the Liquid lint on the staged file automatically at commit time — the explicit run in
  AC-3 is belt-and-suspenders, not a substitute.

## References

- Learning: `knowledge-base/project/learnings/best-practices/2026-06-15-content-publisher-bluesky-is-single-post-x-is-threaded.md`
- Campaign calendar (auto-generated; do not edit): `knowledge-base/marketing/campaign-calendar.md`
