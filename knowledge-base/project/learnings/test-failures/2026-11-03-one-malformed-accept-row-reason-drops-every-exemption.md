---
title: "one malformed accept-row reason drops EVERY exemption — the ratchet floods `new-pair` while the real error is a single `stale-accept - - -` line"
date: 2026-11-03
category: test-failures
tags: [ci-pr-affected, accept-rows, ratchet-repair, s4-drain]
synced_to: [soleur:work]
---

# Learning

## Problem

A drain round appended 104 accept rows to
`scripts/ci-pr-affected-audit.accept.tsv` — and the ratchet's next report
flooded with **330 `new-pair` findings**, as if the drain had deleted every
exemption it had just written. The actual cause was one grammar detail: 27 of
the new rows carried col-5 reasons like `assertion literal:`, `argument
string:`, `API-path literal:`, `fixture JSON string:` — every one missing the
mandatory `false-positive: ` prefix.

## Root cause (seat-verified)

`load_accept` (`scripts/ci-pr-affected-replay.py:1485`) validates row-by-row
and raises `ValueError` on the **first** malformed row — col 5 must match
`^false-positive: \S` (:1523). In `ratchet_run` that raise is *caught*:

```python
try:
    accept = load_accept(apath, None if a.accept else root)
except ValueError as e:
    accept_err = str(e)          # accept stays {} — every exemption gone
```

So a single non-conforming reason silently empties the entire exemption map:
the census runs with `accept={}`, every previously-exempt pair resurfaces as
`new-pair`, and the parse error surfaces only as one
`stale-accept\t-\t-\t-<err>` line (:2046) — alphabetically buried inside the
same `stale-accept` finding class, drowned by hundreds of new-pair entries.
By contrast `audit --accept <file>` calls `load_accept` *unwrapped* (:2108),
so the same file errors rc 2 there — the flood shape is ratchet-specific.

## Rule

When the ratchet's live-pair count balloons far beyond the diff's footprint,
**check reason-column conformity before triaging any pair**:

```bash
# 1. The parse error surfaces here, not in the new-pair section:
grep -P '^stale-accept\t-\t-\t-' <ratchet-report>
# 2. Or validate the file directly — rc 2 names the failing row:
python3 -I scripts/ci-pr-affected-replay.py audit \
  --accept scripts/ci-pr-affected-audit.accept.tsv
awk -F'\t' 'NF==5 && $5 !~ /^false-positive: /' \
  scripts/ci-pr-affected-audit.accept.tsv
```

Every col-5 reason must start `false-positive: ` followed by the closed kind
grammar (`false-positive: <kind>: <file:line>: <evidence>` — runbook
`ci-pr-affected-activation.md`). Freeform kind prefixes
(`assertion literal:`, `argument string:`) are the failure this learning
records; the parser accepts *any* text after the `false-positive: ` head, so
the head is the load-bearing token, not the kind vocabulary.

## Companion diagnostic: `--all-refs` for boundary-line anchors

The ratchet's `new-pair` report truncates each pair's ref list (at most 3
boundary lines per pair). `audit --all-refs` prints **one `ref` line per
boundary line** with anchor hash + ordinal — the exact values a col-3/col-4
accept row needs:

```bash
python3 -I scripts/ci-pr-affected-replay.py audit \
  --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs \
  | grep '^ref'
```

This is how the drain found the replay-shard self-mention anchors: suites
`ci-pr-affected-replay-{a,b,c}` name `accept.tsv`/`baseline.tsv` inside
expectation strings and arg literals *within the SUT's own source*, and each
mention line produces its own `(anchor, ordinal)` pair needing its own row.

## Session Errors

1. **27 accept rows written with non-conforming col-5 prefixes** — Recovery:
   rewrote every prefix to `false-positive: <kind + reason>` and added the 15
   self-mention anchor rows (49b4907b7b); ratchet back to `exit=0
   live=1481=baseline1481`. Prevention: validate with `audit --accept` (or the
   awk col-5 check above) immediately after writing accept rows, before the
   next ratchet run; on any pair flood, grep `stale-accept\t-\t-` first.
2. **A reviewer-initiated inline rebase onto moved main invalidated the
   earlier drain fixpoint** — Recovery: re-ran the post-rebase audit and
   drained the fresh reveal (stale row + 104 accept rows, 82ea2d2d89).
   Prevention: the audit fixpoint must be re-verified after EVERY rebase —
   post-rebase reveal ≠ pre-rebase reveal; see the merged-tree learning
   `../../2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`.
3. **Budget-only PR #11965's `test` aggregate failed at "Aggregate shard
   results" in ~2s** — Recovery: the failure is the draft-light contract, not
   a defect; the ready_for_review run runs the full battery. Prevention:
   documented in `../workflow-issues/2026-11-03-draft-prs-fail-the-test-aggregate-by-design-and-ceiling-raises-ship-alone.md`.
4. **Guard-1 stream-diff showed edge losses on a widen-only change** —
   Recovery: ruled bug-correction (the lost `^dir/` edges were phantom edges
   minted by the `||`-residue bug being fixed). Prevention: adjudication
   heuristic in `2026-11-03-a-widen-only-derive-fix-can-lose-edges-the-bug-itself-minted.md`.

## Evidence

PR #11958 commits `82ea2d2d89` (the 104-row drain that introduced the bad
prefixes) and `49b4907b7b` (prefix normalization + 15 anchor rows; commit
message records the 330-pair flood and the `exit=0 live=1481 baseline=1481`
fixpoint). Sibling mechanisms: the reason *content* must enumerate every
real-tree read arm (`2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms.md`);
anchor-keyed rows go stale on sibling merges
(`../../2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`);
every boundary line needs its own row
(`2026-10-30-audit-accept-rows-need-every-boundary-line-and-regen-pricing-can-break-committed-invariants.md`).

## Tags

category: test-failures
module: ci-pr-affected
