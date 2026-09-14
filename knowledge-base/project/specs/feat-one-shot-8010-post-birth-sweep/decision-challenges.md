# Decision challenges — feat-one-shot-8010-post-birth-sweep

Persisted headlessly by `plan` (Plan Review, ADR-084 routing). Each entry argues that the brief's stated direction should change; none was applied. `ship` Phase 6 renders these into the PR body and files the `action-required` issue.

## UC-1 — The ≤100-line budget cuts known-false prose by arithmetic (DHH, P2)

- **Stated direction:** the brief bounds the sweep at ≤100 changed lines and orders pure-prose items (3, 4, 2) behind the operator-visible/behavioural ones.
- **Challenge:** a stale-prose sweep's job is "no false sentence survives"; dropping items 3/4/2 because a diff counter crossed 100 leaves known-false prose in place. Estimated A+B+C ≈ 103 diff lines — the overflow is one runbook snippet (item 2).
- **Plan's disposition:** the bound is kept as the brief states it; Tier C is taken in order 3 → 4 → 2 while the single post-B measurement stays ≤ 100, and anything cut is named on #8010 with its location. Raising the bound to ~110 would let everything land in one PR.
- **Decision needed:** keep ≤100 (default) or allow ~110 for this PR.

## UC-2 — Redeploy mechanism: organic path-trigger (item 18) vs. explicit dispatch as primary (CTO advisor + DHH + code-simplicity)

- **Stated direction:** brief (e) — "The merge of this PR touching `apps/web-platform/infra/**` triggers the Web Platform Release deploy arm … verify the deploy job concluded success and `/health` build_sha advanced".
- **Challenge:** with `variables.tf` verified accurate, the only `apps/web-platform/**` path in the PR is a comment-only fix in `git-data-rung2-rehearsal.test.sh` (item 18). Three reviewers called riding a directory-prefix pathspec a coincidental trigger and asked for `gh workflow run web-platform-release.yml -f bump_type=patch` as the primary mechanism.
- **Plan's disposition:** organic trigger kept as primary (it is the brief's stated shape and item 18 is a genuine stale comment); the redeploy is verified BY MERGE SHA as a first-class postmerge deliverable, with the dispatch fired only when no release run exists for that SHA. Reason the dispatch cannot be unconditional: `reusable-release.yml`'s idempotency step keys on the NEXT computed tag, so a dispatch after a published run mints an extra patch release.
- **Decision needed:** confirm organic-with-verified-fallback, or drop item 18 and make the dispatch the sole mechanism (one extra `Manual version bump` release, no infra-path change).
