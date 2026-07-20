# Mutation evidence — net-issue-flow gate

Convention: a gate that cannot fail is the defect class this repo keeps
re-learning (the secret-scan "structurally-unfailable gates" fix merged
2026-07-19; the still-open "infra-validation cannot fail on main" and
"preflight Check 10 cannot verify run-triggered emitters"). A green test run is
NOT evidence. This file records the gate FAILING.

> **Marker safety.** The override marker is written throughout this file SPLIT
> across a line break so a literal `grep -qF` cannot match it:
> `<!-- gate-overr` + `ide: net-issue-flow -->`.
> The hook's corpus is the PR body ONLY — it does not expand linked
> `specs/**.md` files (the precedent hook does; inheriting that would let the
> gate find its own override marker in this very file and silently
> self-override, invisible to the acceptance criteria).

---

## 1. The blocking run (synthetic NET = +3, no override)

Command: `net-issue-flow.sh 999` against a stubbed `gh` returning a PR body
with zero close-keywords and three issues bare-referencing `#999`.

```text
PR #999 net-issue-flow:
  Closing: 0  (none)
  Filing:  3  (#7001 #7002 #7003)
  Net:     +3  (positive = backlog growth)

net-issue-flow: BLOCKED — this PR is net-positive (+3) on the issue queue.

Every PR must close at least as many issues as it files. Filing is free;
closing is expensive, and the queue grows by roughly the difference.

Resolve via one of:
  (a) Fix inline — fold the filed work into THIS PR. The cost-of-filing
      auto-flip (<=100 lines AND <=4 files) already covers most of it.
  (b) Close something — if a filed issue supersedes an open one, close it.
  (c) Override — add to the PR body:
        <!-- gate-overr
        ide: net-issue-flow -->
      plus a one-line justification per filed issue, or run with
      SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1.
>>> EXIT=1
```

**Exit code 1. The gate blocks.**

## 2. The passing run (same PR, override marker added)

```text
PR #999 net-issue-flow:
  Closing: 0  (none)
  Filing:  3  (#7001 #7002 #7003)
  Net:     +3  (positive = backlog growth)

net-issue-flow: OVERRIDDEN via the gate-override marker in the PR body.
  Net is +3; the override is recorded as a deliberate decision.
>>> EXIT=0
```

**Exit code 0. The escape hatch works, and is announced rather than silent.**

---

## 3. Mutation battery — 9 mutations, 9 killed

Each mutation was applied to `net-issue-flow.sh`, the suite re-run, and the
script restored. A SURVIVED row would mean the suite cannot detect that defect.

| # | Mutation | Result | Red assertions |
|---|----------|--------|----------------|
| 1 | threshold loosened to `NET > +1` | KILLED | 1 |
| 2 | block path `exit 1` → `exit 0` | KILLED | 2 |
| 3 | `--limit 500` dropped (falls back to 30) | KILLED | 1 |
| 4 | `--search` reintroduced | KILLED | 1 |
| 5 | `--state all` → `--state open` | KILLED | 1 |
| 6 | `--label deferred-scope-out` reintroduced | KILLED | 1 |
| 7 | numeric boundary removed (`#999` substring-matches `#9990`) | KILLED | 1 |
| 8 | `createdAt` filter removed | KILLED | 1 |
| 9 | override check replaced with `true` (always overrides) | KILLED | 2 |

Mutation 1 is the load-bearing one. It is the exact regression of loosening the
gate back to the originally-briefed `NET > +1` threshold — which, at the
measured ~132 merged PRs/week, would authorize +132 issues/week against an
observed +144/week: an ~8% reduction wearing the authority of a passing gate.
Case 4 of the suite pins the boundary at `>0` and reddens on that mutation.

Mutations 3–6 and 8 are the four independently-measured pass-biasing defects
plus the date filter. Any one of them left in place produces a BLOCKING gate
that silently always passes — strictly worse than the advisory surface it
replaces, because it also carries the authority of having passed.

## 4. Reproduce

```bash
bash plugins/soleur/test/net-issue-flow.test.sh   # 18 assertions, ALL PASS
```

The suite is auto-globbed into `scripts/test-all.sh:316`
(`plugins/soleur/test/*.test.sh`), so it gates on every run — verified, not
assumed. Registration-without-execution is its own documented failure class.
