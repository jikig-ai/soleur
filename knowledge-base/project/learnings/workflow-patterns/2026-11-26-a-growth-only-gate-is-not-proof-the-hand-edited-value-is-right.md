---
title: "A growth-only gate is not proof a hand-edited value is right: drill every exit of an agent-run recipe"
date: 2026-11-26
category: workflow-patterns
tags: [ci, sharding, regenerate-shard-manifest, runbook, drift-gate, review]
related: [knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md, knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md, scripts/regenerate-shard-manifest.py]
---

## Problem

#12780 (docs half, PR #13071) documented a one-row re-price of `scripts/suite-durations.tsv`:
measure the merge_group median with the generator in scratch, hand-edit the row, then gate the
edit with the drift gate (`--baseline-durations`). The plan's drill (AC7) proved the gate
refuses a 3x growth, accepts a decrease and stamps `--allow-growth`. Review still found a P1 and
three P2s in the recipe text:

- The drift gate is a growth-only ratchet: it never compares the edited value with the measured
  one and never refuses a decrease. When a label is untimed in every kept run, the scratch
  regen emits it at the floor (`src=floor`), the recipe copied that value into the `measured`
  row, and the gate passed it — the floor-to-measurement laundering ADR-240 forbids. The same
  hole admitted a typo, a deliberate under-price, and the wrong row from `grep -F <label>`
  (31 labels are substrings of other labels).
- On the `--allow-growth` path the in-tree write rewrites the table's own `generated-at`,
  `default-weight-ms` and `growth-acked` headers and prints `wrote … parity delta`, not the
  `already in parity — untouched` the recipe said it "must" print, so an executing agent would
  read success as failure and commit without the new stamp.
- The figures "re-derived 4 floor rows, moved 14 legs" were written into four files with no
  recorded run, and the 140/45 figures were attributed to the wrong planning effort.

## Solution

- Step 1 reads the row by exact label (`awk -F'\t' -v l=… '$1 == l'`), stops unless it is
  `measured` from at least 3 timed runs, and prints the per-run values with the generator's own
  skip set (`FAIL`, `KILLED`, `TRIPWIRE`, `skip=`).
- Step 2 diffs the edited committed row against the generator's row; it must print nothing.
- Step 4 documents both output shapes and every header line the ack path changes; step 5
  commits them and pastes step 4's stdout as the reviewer's evidence (nothing in CI re-runs it).
- The ADR-242 amendment narrows ADR-312's "accepted v1 hole" by name, and the measurements were
  re-run and re-attributed (#12778's plan archive for 140/45).

## Key Insight

A gate that bounds one direction (growth) certifies nothing about the other, so a recipe that
calls a hand edit "sanctioned when the gate accepts it" needs a second check that ties the value
to its measurement. And an agent-executed recipe is verified only by running each of its exits
in a scratch clone — the refusal path, the ack path and the "no measurement" path — and
comparing the tool's printed output with the strings the prose quotes. The plan's drill ran the
gate; review ran the recipe.

## Session Errors

1. **Planning subagent and a deepen agent died on `EAI_AGAIN`** — Recovery: plan recovered from
   disk, deepen re-run inline. — Prevention: none (transient network).
2. **Affected local gate refused rc=4** (comment-only `test-all.sh` edit took the runner-changed
   fallback; sibling full-gate runs in flight) — Recovery: ran the consumer suites that reference
   the changed files. — Prevention: already ruled acceptable in `decision-challenges.md`; CI is
   the full-battery gate.
3. **Substitute-suite loop exceeded the 600 s foreground bound** — Recovery: re-run in the
   background with per-suite rc lines. — Prevention: start multi-suite loops in the background.
4. **`test-all-affected.test.sh` ran 7 min past `timeout 600`** (TERM did not stop the tree while
   a sibling worktree ran the same suite) — Recovery: killed only this worktree's pid; recorded
   rc=137 as unresolved, CI runs it. — Prevention: use `timeout -k 10 600` in ad-hoc loops.
5. **A report-only review seat ran `git fetch` in the worktree** — Recovery: only the tracking ref
   moved; tree clean. — Prevention: say "no git writes, including fetch" in the seat brief.
6. **A fix-round seat left a scratch `git clone --shared` it could not remove** (hook blocked
   `rm -rf` on a checkout) — Recovery: the lead inspected and removed it. — Prevention: the lead
   lists `/var/tmp/rev*` after every seat returns.
7. **The recipe's first draft laundered an untimed row's floor into `measured` and misquoted the
   ack-path output** — Recovery: review fix rounds 1 and 2. — Prevention: plan sharp-edge bullet
   routed with this learning (name what the gate cannot refuse; drill every exit in scratch).
8. **Measurement figures written into four files without a recorded run** — Recovery:
   reproduced in scratch by two seats and re-worded with the command's inputs. — Prevention: a
   number written into an ADR carries the command that produced it in the plan's verified section.
9. **An inherited attribution (#12441 P.2) copied from the issue body** — Recovery: corrected to
   #12778's plan archive. — Prevention: resolve every `#N` cited for a measurement to the artifact
   that holds it before writing it.

## Tags

category: workflow-patterns
module: scripts/regenerate-shard-manifest.py, ci-test-scripts-sharding runbook
