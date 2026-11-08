# Cause receipt — why 90 of 300 recent main commits routed `no-run` (#10862)

**Verdict: H4 — the runs existed; the `?head_sha=` filtered run listing (search-backed) dropped
~30% of existing runs at collect time (2026-10-22 ~15:30–18:49Z).** The locus is one level
upstream of `ci_runs`'s client-side `FULL_EVENTS` filter: the drop happened inside GitHub's
run listing, not in the script. Established read-only on 2026-11-07 (issue comment); every
number below is re-derived in this session per the plan's "re-derive, do not trust" rule.

## Discriminating evidence (re-run 2026-11-08)

`window-coverage.txt`:

```text
git rev-list --first-parent --since=2026-10-09T23:23:34Z --until=2026-10-22T13:23:40Z origin/main | wc -l
300
gh api --paginate 'repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=push&branch=main&created=2026-10-09T00:00:00Z..2026-10-22T23:59:59Z&per_page=100'
353 push-run head_shas, all 300 window SHAs covered (comm -12 = 300)
```

`sample-reads.txt`: the exact `?head_sha=` call on window SHAs returns 2 runs each today
(`push` + `merge_group`), and `commits/<sha>/check-runs` answers 223 entries on the newest —
the runs were never absent; the index omitted them at collect time.

Population re-derived identical to the retained numbers: 300 units = 207 clean + 90 `no-run` +
3 `list-over-limit`; mg runs 416 / refused 73 (per the 2026-11-07 comment's re-derivation).

## Per-hypothesis dispositions

- **H1 refuted** — a deleted push run cannot reappear; all 300 window SHAs have runs today.
- **H2 refuted** — check-runs exist for the window SHAs; runs were created at landing.
- **H3 refuted** — the runs sit under `head_sha` = the first-parent commit itself (the queue's
  temp commit IS the squash commit that lands).
- **H4 supported** — `?head_sha=` is a search parameter; the index dropped ~30% of existing
  runs at collect time. Same failure class as
  `knowledge-base/engineering/operations/post-mortems/2026-09-24-release-deploy-arm-false-skip-on-lagging-runs-search-postmortem.md`,
  at outage scale rather than minutes-scale lag.
- **H5 refuted** — every first-parent commit is its own push `head_sha`; no multi-commit
  batching signature.

## Decision-rule arm and the fix shipped

Plan's decision rule → H3/H4 arm: **re-read through the true run; keep the window.** Shipped:

1. `ci_runs` treats an empty `?head_sha=` answer as non-authoritative: one retry, then
   corroboration through the commit-keyed `commits/{sha}/check-runs` + `actions/runs/{id}`
   reads (the #8770 retry/corroborate precedent). `runs_via` on each unit records which read
   answered: `head-sha`, `head-sha-retry`, `check-runs`, `corroborated-no-run`.
2. The criterion-a evidence re-run runs on a fresh window (runbook §4) — receipts under
   `receipts/rerun/`.

## Known residual (recorded, not fixed)

`ejections` reads `?event=merge_group&created=…`, the same search-index class, and its
`total_count == len(runs)` guard cannot see a dropped entry (the count is index-computed too).
There is no per-sha non-search read to pin a merge_group window listing against, so this arm is
documented here rather than patched in this PR. — CTO ruling, decision-challenges.md row 4.

Residual (added at review): the same completeness caveat holds on the collect side — corroboration fires only on an empty filtered listing, so a partial drop under a non-empty listing is undetectable by construction (conservative direction: kept failures only grow the worst-case numerator).
