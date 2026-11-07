#!/usr/bin/env python3
"""rebalance_whatif.py - Phase 4.0 paper check for the replay-arm rebalance (Ref #12013, #12231).

Question: with lever 1 (the star suites last) in place, can any contiguous re-split of the 599 gated sites across the three
replay arms shorten the pool phase by at least GATE_S seconds? Answered with a list-schedule over the treatment reading of
the previous PR (162 suites, 4 slots, walls as measured, lane tokens ignored, the one selected star suite removed because it
runs last and alone), NOT with a model of the real runner: a direction check only, no number from it is a result.

Per-site cost: each original arm's pooled wall divided by its site count (a: 1513 s / 193, b: 570 s / 193, c: 530 s / 213, the
ranges of scripts/test-all.sh at the base). A candidate split (i, j) cuts the 599 sites into 1..i, i+1..j, j+1..599; an arm's
wall is the sum of the per-site costs of its sites. The unconditional share of each arm (the ~100 passes that run whatever the
rows) is NOT separated here: it is a fixed cost per arm and would make three arms cost more than the model says, so the
predicted gain is an upper bound on what a re-split can buy.

Input: the treatment reading of the PREVIOUS PR (the replay arms registered first, no park), archived at
knowledge-base/project/specs/archive/20261106-151254-feat-one-shot-12013-replay-a-start-priority/measurements/treatment.suites.tsv.
The baseline assertion below only holds on that file (the readings of this PR have a different suite mix and walls).

Verdict (CTO ruling 2026-11-06, work phase): a re-split is worth measuring only if a split INSIDE the balance bound
(largest arm wall / smallest at most 1.5) beats lever 1 alone by at least GATE_S seconds of predicted pool end. The unbounded
best split is printed for information only.

Usage: rebalance_whatif.py <path to the archived treatment.suites.tsv>
"""
import csv, heapq, sys

GATE_S = 30
SITES = [(1, 193, 1513), (194, 386, 570), (387, 599, 530)]  # (first, last, pooled wall seconds) of the three arms at the base
STAR = "scripts/test-all-capacity-signal"
ARMS = ["plugins/soleur/test/ci-pr-affected-replay-a", "plugins/soleur/test/ci-pr-affected-replay-b", "plugins/soleur/test/ci-pr-affected-replay-c"]
APPROVAL = "apps/web-platform/test/approval-guard1-mutation"
WIDTH = 4


def schedule(jobs):
    free = [0] * WIDTH
    heapq.heapify(free)
    start = {}
    for label, wall in jobs:
        t = heapq.heappop(free)
        start[label] = t
        heapq.heappush(free, t + wall)
    return max(free), start


rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
jobs = [(r["label"], int(r["end_s"]) - int(r["start_s"])) for r in rows if r["label"] != STAR]
base_walls = dict(jobs)
assert [j[0] for j in jobs[:3]] == ARMS, "the arms must be registered first"

# per-site cost, indexed 1..599
cost = [0.0] * 600
for first, last, wall in SITES:
    for s in range(first, last + 1):
        cost[s] = wall / (last - first + 1)
prefix = [0.0] * 600
for s in range(1, 600):
    prefix[s] = prefix[s - 1] + cost[s]


def arm_walls(i, j):
    return [round(prefix[i]), round(prefix[j] - prefix[i]), round(prefix[599] - prefix[j])]


def pool_end(walls):
    rest = jobs[3:]
    return schedule([(ARMS[k], max(1, walls[k])) for k in range(3)] + rest)


base_end, base_start = schedule(jobs)
print(f"baseline (lever 1 alone): pool end {base_end} s; {APPROVAL.split('/')[-1]} starts {base_start[APPROVAL]} s; "
      f"sum of walls / {WIDTH} = {sum(w for _, w in jobs) / WIDTH:.0f} s; the model reproduces the treatment reading if these are 1611 / 945")
assert (base_end, base_start[APPROVAL]) == (1611, 945), "the baseline does not reproduce the reading: the check is void"

best = (10 ** 9, None)
n = 0
for i in range(1, 598):
    for j in range(i + 1, 599):
        n += 1
        e, _ = pool_end(arm_walls(i, j))
        if e < best[0] or (e == best[0] and best[1] and max(arm_walls(i, j)) < max(arm_walls(*best[1]))):
            best = (e, (i, j))
e, (i, j) = best
print(f"searched {n} contiguous splits")
print(f"best split 1-{i} / {i + 1}-{j} / {j + 1}-599: arm walls {arm_walls(i, j)} s, predicted pool end {e} s ({base_end - e:+d} s vs baseline)")
eq = (200, 399)
ee, _ = pool_end(arm_walls(*eq))
print(f"equal split 1-200 / 201-399 / 400-599: arm walls {arm_walls(*eq)} s, predicted pool end {ee} s ({base_end - ee:+d} s vs baseline)")
# The balance bound of AC8 (largest arm wall / smallest arm wall <= 1.5) as a constraint on the same search.
RATIO = 1.5
bal = (10 ** 9, None)
for i in range(1, 598):
    for j in range(i + 1, 599):
        w = arm_walls(i, j)
        if min(w) <= 0 or max(w) / min(w) > RATIO:
            continue
        e2, _ = pool_end(w)
        if e2 < bal[0]:
            bal = (e2, (i, j))
if bal[1]:
    e2, (i2, j2) = bal
    print(f"best split with arm walls within a {RATIO}x ratio: 1-{i2} / {i2 + 1}-{j2} / {j2 + 1}-599: arm walls {arm_walls(i2, j2)} s, "
          f"predicted pool end {e2} s ({base_end - e2:+d} s vs baseline)")
else:
    print(f"no contiguous split keeps the arm walls within a {RATIO}x ratio")
bal_gain = (base_end - bal[0]) if bal[1] else None
verdict = "PROCEED" if (bal_gain is not None and bal_gain >= GATE_S) else "PAPER-NEGATIVE (not landed)"
print(f"gate: a split within the {RATIO}x balance bound must predict a gain of at least {GATE_S} s -> {verdict}"
      f" (unbounded best: {base_end - e:+d} s, informational only)")
