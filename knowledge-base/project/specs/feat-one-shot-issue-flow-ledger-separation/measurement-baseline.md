# Issue-flow measurement baseline

The artifact the success criterion is checked against. Every figure carries the
command that produced it, so the four-week re-check re-runs rather than recalls.

**Re-check falls due: 2026-10-08** (four weeks after 2026-09-10).

## Open-issue total — three readings, recorded as a band

| Reading | Value | When |
|---|---|---|
| Source write-up | 1,456 | 2026-09-10, write-up authored |
| Session-start recount | 1,459 | 2026-09-10, `/soleur:go` entry |
| Planning-time recount | 1,455 | 2026-09-10, plan Phase 0.4 |
| Implementation recount | 1,457 | 2026-09-10, this document |

```bash
gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:open" --jq '.total_count'
```

Four readings inside one working day spanning 1,455–1,459. That spread **is** the
finding, not noise to reconcile away: the backlog moves by single digits per hour.
Recorded as a band so no later reader treats any single value as exact, and so a
four-week delta smaller than ~5 is read as UNRESOLVED rather than as progress.

**Baseline of record for AC26: 1,455** (the planning-time reading, the lowest of
the four — chosen so a later drop must be real to register).

## Eight-week flow — the write-up and a live re-derivation DISAGREE

| Quantity | Write-up | Live re-derivation | Command |
|---|---|---|---|
| Opened | 1,134 | **976** | `search/issues?q=...+is:issue+created:>=2026-07-16` |
| Closed | 563 | **478** | `search/issues?q=...+is:issue+closed:>=2026-07-16` |
| Net | +571 | **+498** | derived |
| Filed per week | ≈142 | **122** | `opened / 8` |

Both are labelled "the last 8 weeks"; they anchor that window differently. The
live figures were re-derived on 2026-09-10 with `date -u -d '8 weeks ago'`
= `2026-07-16`.

**AC25's baseline of record is 122 filed/week, not 142.**

This is load-bearing and is the reason the disagreement is recorded rather than
averaged. AC25 declares success when the post-merge filed-per-week figure is
*below* the baseline. Taking 142 would have declared success at any rate under
142 — including the current, unimproved 122. A criterion that its own starting
state already satisfies measures nothing. The conservative reading is therefore
the baseline, and the generous one is recorded only to explain why it was not
used.

The ratio is unchanged either way: **976/478 = 2.04 filed per closed**, against
the write-up's 1,134/563 = 2.01. The diagnosis does not depend on the window.

## Composition

| Quantity | Value | Command |
|---|---|---|
| Older than the 8-week window | 831 (57%) | `...+is:open+updated:<2026-07-16` |
| Never commented | 331 | `...+is:open+comments:0` |
| `domain/engineering` : `domain/product` | 626 : 39 | 1,000-issue sample (write-up) |
| PRs overriding net-issue-flow | 98 | PR-body `gate-override` scan (write-up) |

## Budget authorities at merge time

| Authority | Before | After | Command |
|---|---|---|---|
| `B_ALWAYS` | 45,999 | **45,836** | `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` |
| Reject ratchet | 46,000 | 46,000 | same |
| Skill descriptions | 2,400 / 2,400 | unchanged | `bun test plugins/soleur/test/components.test.ts` |

The `2>&1` is load-bearing: WARN and REJECT print to stderr.

Effective headroom before this change was **one byte**, which is why the rule
reconciliation was designed byte-negative by construction rather than trimmed
opportunistically afterwards.

## What the four-week re-check must NOT conclude

- **A flat open total is not failure.** Expiry contributes nothing to the open
  total during the first 90 quiet days after the backfill, and the machinery
  sweep additionally cannot fire before its not-before date. At week four the
  expected expiry contribution is **zero**. A flat total at week four means
  "expiry has not started", never "the plan failed" (AC26a).
- **A drop is not automatically a rate improvement.** The measurement reports
  expiry closes separately precisely so a stock sweep is never mistaken for a
  rate change (AC26).
- **Filed-per-week has no close term** and cannot be masked by any close,
  expiry or otherwise. That is why the success criterion is a filing count
  rather than a net.
