---
title: "A live positive validated the filter on one row, not the filter"
date: 2026-09-06
issue: 7823
pr: 7872
category: workflow-patterns
tags: [measurement, jq, review, runbook, observability, false-negative]
---

# A live positive validated the filter on one row, not the filter

## Problem

A runbook rewrite replaced two `ssh root@` flows with a Better Stack query. The query was
run **live against production**, returned a real record, and was written down as verified.

It was dropping most of the population. `.message` arrives in two shapes — Better Stack
auto-parses a JSON-valued `message` at ingest, so pino records land as OBJECT, while fd-2
crash lines stay STRINGS. The filter carried `select(type == "object")`. The single row
that matched happened to be in the object branch.

Measured afterwards: 182 of 182 string-shaped app-container rows in 24h, and the object
rows were a small minority of the sample.

**A live positive proves the filter works on that row.** Validating a *filter* needs the
population's shape distribution, not one success — and the successful run is the most
persuasive possible evidence for the wrong conclusion, because it is real, it is
production, and it is not a mock.

Gate: before recording a filter as verified, run it with the discriminating clause
REMOVED and compare counts. A filter that cannot be shown to exclude something has not
been shown to include the right thing.

## When N agents disagree, measure — and when they agree, find the shared premise

Two review agents reported `.message` is always a string, each citing `vector.toml`'s
`.message = encode_json(parsed_obj)`. A third reported it is an object, having queried
production. All three were partly wrong: both shapes exist, split by which scrub branch
the row took.

The two who agreed were not independent evidence — they had read the same config and
neither had measured the ingest side. Convergence raises confidence only when the errors
are independent; N reviewers sharing one mental model are one reviewer.

The resolution cost one query. Adjudicating between two readings of `vector.toml` would
have produced a confident wrong answer either way.

## The documented class recurred inside the fix, again

`//` in jq is a falsy-default, not an OR across keys. `review/SKILL.md` documents this
verbatim ("a falsy-default (`//` in jq, `||` in JS, `or` in Python) folds `false`/`0`/`""`
into the same branch as *absent*"). It was quoted into a review agent's prompt in this
same session — **after** it had already been written into the runbook.

The query read `select((.userIdHash // .workspaceIdHash // .worktreeIdHash) == $h)`, which
short-circuits on the first non-null key. A record carrying `userIdHash` for one actor and
`workspaceIdHash` for the target is matched by the old `grep -E` and missed by this. The
two keys co-occur on every record `git-data-replication.ts` emits, so it is the live shape,
and the failure direction is a false negative in a flow whose whole purpose is finding a
user's records.

Reading a class does not prevent it. Only a mechanical gate or a measurement does.

## Every instrument I checked my own work with needed checking

- A shape-census query used `(fromjson? | type)`. `fromjson?` yields **empty** on failure,
  which makes the enclosing conditional empty and silently drops every row — it printed
  nothing, which reads exactly like "no rows". `(fromjson? // null | type)` is correct.
- A `du -sh` reported 3.9 G for a directory whose children summed to 420 M. The real cause
  was a full tmpfs being released by a sibling process mid-measurement; the number was
  noise, not a finding.
- Two agent-prescribed CLI flags: `doppler run --only-secrets` exists; but
  `betterstack-assert-absence.sh --host` is **required**, and the invocation written from
  the agent's report omitted it, so the command would have exited 64. Prescribed flags need
  `--help`, whoever prescribed them.

- A post-merge monitor reported `DEPLOY_FAILED: Board status sync -> cancelled` on the merge
  commit. Three runs of that workflow fired at the **identical timestamp** on that SHA; two
  succeeded and one was cancelled by its own `concurrency.group`. Its `event` was **`issues`**,
  not `push` — it was triggered by the issue comments I had just posted, not by the merge. So
  the alarm was caused by my own commenting and raised by my own monitor, about a workflow that
  had succeeded twice. `cancelled` is not a failure conclusion: on a concurrency-grouped
  workflow it is the normal outcome for a superseded duplicate. A monitor watching a merge must
  filter to `event == "push"` and treat only `failure`/`timed_out` as failures, or it will page
  on its own side effects.

## Asserting a date inside a PR about an unmeasured premise

The PR's subject is that #7823's premise ("pino stdout is not shipped anywhere") is stale.
Its own commit message and a public issue comment both said "that was true when the issue
was written." One `git log -S` refutes it: the shipper landed 2026-06-02, the issue was
filed 2026-09-04 — stale by three months when filed.

The charitable reading was adopted because it was charitable, not because it was checked.

## The correction's correction, three rounds deep

The panel reviewed the pre-fix runbook and found three P1s. Self-review of the FIXES then found
three more — including one that is the documented class recurring inside the edit that was
fixing it.

`formatters.log()` was attributed to the wrong file. The fix matched on
`"lines emitted by \`formatters.log()\`"`. The surviving occurrence reads **"FIELD emitted by"**,
so the replace silently did not apply, and it was reported as fixed. Indexing a sweep by
remembered *wording* rather than by the *claim* — which this repo already documents, and which
is exactly one level up from the misattribution being corrected.

The sweep that works is `grep -n 'formatters\.log'` (the subject), which returns 5 sites, of
which one carried a file attribution. The sweep that failed was keyed on a sentence I had just
read and thought I remembered.

Two siblings in the same pass: a count in prose that did not match what followed it ("Three
details are load-bearing", introducing four), and grep-era wording left in the present tense
describing a mechanism the PR had replaced, three paragraphs below bullets that described the
same mechanism correctly in the past tense.

**The generalizable ordering:** on a PR whose deliverable is a correction, review the new
ASSERTIONS before the new content, and do it again after fixing the review's findings — the
fixes are written fastest, feel like bookkeeping, and are the least-read text in the diff. Three
consecutive rounds on one one-file docs PR each found defects only in the layer added by the
previous round.

## Key insight

Three of this session's defects were *corrections* that inherited the defect's framing, on
two consecutive PRs. The pattern is now specific enough to gate: **on a PR whose deliverable
is a correction, the replacement text is the highest-risk surface, and the most dangerous
sentence in it is the one that sounds like generosity toward whoever was wrong before.**
