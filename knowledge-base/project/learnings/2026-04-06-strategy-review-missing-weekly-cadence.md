# Learning: Strategy review script missing weekly cadence

## Problem

The `scripts/strategy-review-check.sh` script's `case` statement (lines 68-78) maps `review_cadence` frontmatter values to day counts. It handled `monthly` (30), `quarterly` (90), `biannual` (180), and `annual` (365) but not `weekly`. Two documents (`knowledge-base/product/roadmap.md` and `knowledge-base/marketing/content-strategy.md`) had `review_cadence: weekly`, which fell to the `*` default, incrementing the error counter twice and causing exit 1.

The "Strategy Review" GitHub Actions workflow failed on 2026-04-06 with `errors=2`.

## Root Cause

When `review_cadence: weekly` was added to document frontmatter, the script's case statement was not updated to handle it. The `*` default correctly treats unknown cadences as errors (fail-fast), but the supported cadence set was incomplete.

## Solution

Added `weekly) cadence_days=7 ;;` as the first case entry in the `case` statement.

Verified locally with `DATE_OVERRIDE=2026-04-06` -- script exited 0 with `errors=0`, correctly processing both weekly documents.

## Key Insight

When a script validates frontmatter values against a hardcoded set, adding new valid values to documents without updating the script creates silent workflow failures. The fail-fast behavior is correct, but the supported value set must stay in sync with what documents actually use.

## Related

- `knowledge-base/project/learnings/2026-03-23-strategy-review-cadence-system.md` -- documents the cadence system design
- `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` -- documents replacing hardcoded case statements with directory-driven approaches
- `scripts/provision-plausible-goals.sh` -- another script with case statement that could have the same gap

## Tags

category: workflow
module: strategy-review-check
