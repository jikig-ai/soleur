---
title: Reduce's transaction model swallowed a pino row into an unscrubbed blob — and the guard's data edits broke three pins the guard itself never saw
date: 2026-10-29
category: integration-issues
tags: [vector, reduce, pii-scrub, sentry-cron-monitor, review-catches, pr-11494]
---

# Learning: two classes from the observability right-sizing review

## Problem 1 — a `reduce` transform is a transaction model, not a shape match

The PR added `transforms.app_container_compaction` (Vector `reduce`) to join
multi-line app-container log rows before `pii_scrub_*`. The header comment
modeled it as "lines matching `starts_when` open a group; `ends_when` closes
it; other lines pass through." **Wrong.** Once a group is open for a
`group_by` key, EVERY same-key event merges until an end fires — a
single-line pino row emitted mid-dump is absorbed into a blob that then
fails `parse_json` at `pii_scrub_drop_userdata`, demoting it to the
string-only backstop, whose regex set covered neither `"userId":` JSON form
nor the Art-9 key set the structured stages strip. Under routine interleaved
container logging (inspect blobs on stderr + pino JSON on stdout sharing one
group key), user-content keys ship raw to Better Stack — silently, tagged
`+string` like any normal non-JSON row.

Two companion mis-models in the same comment: `expire_after_ms` is an IDLE
flush that resets per event — at ~1.2 rows/s an unclosed group never expires
(the real bounds are `end_every_period_ms` and `max_events`); and
`group_by` pins to a KEY, not "one emitter" — all of the container's
emitters share it.

**Fix shape that worked:** extend the string backstop with key-shape rules
(`["\x22\x27]?(key)["\x22\x27]?\s*[:=]\s*…`) covering the same Art-9 +
userId/credential set the structured stages handle — a demoted blob then
still gets schema-key scrubbing regardless of which boundary condition
produced it. Column-0 anchors (`^\{`/`^\}`) additionally stop indented
`},` nested closers from fragmenting groups.

## Problem 2 — editing a guard's DATA trips the literal pins on the data

The .tf re-partition (42 monitors → unrouted map) and vector.toml rewiring
broke THREE byte-exact pins the diff never touched:
`validate-vector-config.yml`'s collectors grep, `vector-terminator-filter.test.sh`'s
`OTHERS` list, and `vector-pii-scrub.test.sh`'s literal `inputs = [...]` grep.
All three asserted the OLD wiring and went red on a green-looking diff.

The elegant resolution, when it exists: restore the pinned edge rather than
edit the pin. Reordering compaction BEFORE `app_container_warn_filter` put
`warn_filter` back in `pii_scrub_drop_userdata.inputs` — both test pins
stayed green unmodified AND the level filter started covering reassembled
blobs (strictly deeper cut). The pin that genuinely had to change (the
collectors list) pinned a *spelling* — updating it to the new list preserved
the guard's purpose.

## Key insight

When a diff rewires a pipeline graph or re-partitions a guard-bounded set,
grep the repo for literal pins of the OLD shape BEFORE assuming the diff is
self-contained — the fixtures asserting the previous wiring are the first
red. And a guard that validates merged/transformed OUTPUT is blind to the
demotion path that produced it: the PII fix had to live in the backstop that
every failure shape lands in, not in any one boundary condition.

## Tags

vector-reduce, transaction-model, pii-scrub-demotion, literal-pins,
guard-window-membership, silent-failure
