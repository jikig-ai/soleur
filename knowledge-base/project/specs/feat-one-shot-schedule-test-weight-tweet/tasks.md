# Tasks — chore: Schedule test-suite-weight-warn distribution draft for 2026-10-20

Plan: `knowledge-base/project/plans/2026-10-19-chore-schedule-test-suite-weight-warn-draft-plan.md`
Branch: `feat-one-shot-schedule-test-weight-tweet`

## Phase 1 — Schedule the draft

- [ ] 1.1 Edit `knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md` frontmatter only:
  - `publish_date: ""` → `publish_date: "2026-10-20"`
  - `status: draft` → `status: scheduled`
  - Do not touch any other frontmatter field or body content.

## Phase 2 — Verify

- [ ] 2.1 Run `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/2026-10-19-test-suite-weight-warn.md` — expect exit 0.
- [ ] 2.2 Confirm `grep -cE '^publish_date: "2026-10-20"$' <file>` → `1` and `grep -cE '^status: scheduled$' <file>` → `1`.
- [ ] 2.3 Confirm `git status --short knowledge-base/marketing/distribution-content/` shows only the one file modified.
- [ ] 2.4 Parse-equivalence assertion (CTO ruling 2026-10-19): replicate the publisher's `get_frontmatter_field` extraction (`scripts/content-publisher.sh`, ~lines 96-106) against the file and assert byte-equal `status` = `scheduled` and `publish_date` = `2026-10-20`, `^status: scheduled` anchored at column 0, and `publish_date >= $(date +%Y-%m-%d)` (host-local) at ship time. Covers the whitespace/quote failure class invisible to diff review.

## Notes

- `scripts/lib/validate-tweet-draft.sh` was run at plan time (2026-10-19): exit 0. It asserts `status: draft` and MUST NOT be re-run expecting success after the flip — post-edit it exits 1 by design.
- Merge-timing caveat (plan Research Insights): this PR must land on `main` before 2026-10-20 14:00 UTC or the publisher's next run flips the file to `stale`.
- `knowledge-base/marketing/campaign-calendar.md` is auto-generated — do not hand-edit.
