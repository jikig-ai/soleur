---
title: "My probe accepted more positive evidence than its absence queries could see"
date: 2026-09-24
category: security-issues
module: scripts/followthroughs
issue: 7761
pr: 8690
tags: [followthrough, betterstack, probe, false-pass, absence, test-stub, mutation-battery]
---

# Learning: a PASS built from "positive evidence + no drift" is only as wide as the narrowest query

## Problem

The #7761 follow-through probe's PASS auto-closes a P1 security tracker. After the Inngest cutover it
could never PASS, and it posted a false FAIL. There were two root causes:
- a pre-cutover answer key;
- a decoder that dropped every object-shaped `message` row.

The rewrite fixed both. The live read went PASS and the new 223-assertion suite was green. The
nine-seat review then reproduced **seven false-PASS paths** on the first GREEN head. Every one had
the same shape: the probe accepted **positive evidence** over a wider shape, scope or time than its
**absence** queries could see. The positive evidence was a heartbeat in LIVE, an owning resume row,
or a stamped image. The absence queries were no drift, no refusal, and no pre-boundary row on this
machine.

| Positive evidence accepted over… | …while the absence query only saw | False-PASS input |
|---|---|---|
| string- **and** object-shaped rows (decoder) | object-shaped rows (quoted `LIKE` terms) | string-shaped `flushall-failed` |
| every host's refusal rows on a newest-first page | this host's rows, with no page-full check | 500 newer foreign refusals |
| `start_ts > boundary` (host clock) | `dt >= boundary` (warehouse clock) | a run that started just before the boundary |
| machine M "now" | M's rows in the hour before the boundary | M silent for more than 1h, then the sidecar moved |
| "some stamped heartbeat exists" | — (no "no unstamped heartbeat" check) | an old-image emitter beside a stamped one |
| resume rows from any machine (exempt) | — | a second machine's resume |
| "≥ 2 heartbeat rows" | — | one heartbeat delivered twice, or stopped 1.9h ago |

The test suite was blind to the time-window members because its query stub **shape-checked
`--since`/`--until` and never filtered on them**. Every time window the probe relied on could be
deleted with the suite still green. Every fixture was also a single-machine world, so machine
selection and machine binding were never discriminated.

## Solution

- **Make every PASS predicate as narrow as the absence query that backs it:**
  - Refuse a PASS when LIVE shows string-shaped or unparseable flip rows (`message_shape_unsupported`).
  - Drift considers every row the `dt`-bounded query returns.
  - Refusals are tag-isolated, anchored on the message start, and page-full gated.
  - ANY unstamped post-boundary heartbeat is `stale_image`.
  - More than one `_MACHINE_ID` since the boundary is refused.
  - The boundary check queries M's own `_MACHINE_ID` over 30 days.
  - Liveness counts DISTINCT heartbeats, requires the newest to be recent, and measures its deadline
    from the resume.
- The test stub honours `--since`/`--until` by each row's `dt`, like the real `dt >= / dt <=`. It has
  a self-check row proving the window excludes rows.
- Fixtures include two machines, old-image emitters, duplicated heartbeats and stopped timers.
- The re-run battery was 53 rows: 53/53 caught with the named fixture's own FAIL line, 0 survivors.

## Key Insight

For any guard of the form **"evidence X exists AND violation Y is absent"**, write down the scope of
X and the scope of Y along the same axes:
- shape;
- tenant/host;
- time (whose clock?);
- machine;
- page completeness.

Wherever X's scope exceeds Y's, a false PASS lives there. And a **fake that answers regardless of a
dimension of the request cannot test any predicate on that dimension**. If the real reader filters by
time, the stub must too, or every time bound in the SUT is unpinned.

## Session Errors

1. **Plan phase (forwarded).** A PreToolUse hook blocked `gh issue create` twice: the body files did not exist yet, then the machinery label was missing. A Python splice aborted on an anchor that did not match. `lane:` defaulted because the branch has no spec.md. — Recovery: filed #8697 and #8698 correctly. — **Prevention:** already hook-enforced; write the body file first.
2. **A verification loop reported a red suite green.** `echo "$(basename $t) RC=$?"` printed `basename`'s status. `cutover-inngest-workflow.test.sh` was red (exact floor 753 vs 755 dispatched). — Recovery: re-ran with `rc=$?` on its own line; set `_EXACT_FLOOR=759`. — **Prevention:** existing rule (work/SKILL.md §"Never read a suite's verdict from an echo that contains a command substitution"); no new rule.
3. **An inspection harness relocated the suite without `FLIP_ROLLOUT_TEST_TARGET`**, and a later `ls -d /var/tmp/ctl.*` glob matched an unrelated file. — Recovery: re-ran with the seam and an exact `mktemp` path. — **Prevention:** capture `mktemp -d` output into a variable and never re-derive it by glob.
4. **The battery's pristine control was red on a relocated copy.** A test read the live pin file through `REPO_ROOT`. — Recovery: the fixture pin moved to the top of the suite. — **Prevention:** a suite that supports a relocated-target seam must pass every file its target resolves by `BASH_SOURCE`.
5. **Battery instrument defects.**
   - A harness row searched for the PASS label, so it reported a false SURVIVED.
   - An F11 row was verdict-equivalent.
   - The last row's stale anchor crashed the script, and the background wrapper's "exit 0" notification hid it.

   Recovery: fixed each row and re-ran the whole battery to its `SURVIVORS=` line. **Prevention:** a battery's verdict is its final summary line, never the notification; key harness rows on the FAIL label.
6. **The `rm -rf` hook blocked a command whose variable was empty.** — Recovery: used a fresh `mktemp -d` path. — **Prevention:** hook-enforced.
7. **The hook blocked `git stash list`.** — Recovery: `git show origin/main:<path>` instead. — **Prevention:** hook-enforced.
8. **I bulk-toggled the tasks.md checkboxes, including the unmet post-merge item 3.6.** — Recovery: `git checkout` of the file, then ticked each item individually. — **Prevention:** existing work/SKILL.md rule; never `sed 's/- \[ \]/- [x]/'`.
9. **The PR body draft contained "The fix #7761"**, which GitHub's parser reads as a closing reference. — Recovery: reworded, then grep-scanned the body and commits. — **Prevention:** run ship's auto-close scan over the body draft before `gh pr edit`.
10. **The first GREEN head shipped 7 false-PASS paths.** — Recovery: the review round (this learning). — **Prevention:** route to the follow-through convention (below).
11. **The local scripts-shard gate queued at position 2–3 twice** behind sibling worktrees. — Recovery: killed it; ran all 44 consumer suites of the changed reader plus the ratchets. The merge gate is CI's required `test`. — **Prevention:** none needed; this is ADR-133 behaving as designed.
12. **The plan prescribed an inert CI wiring.** `AFFECTED_INFRA_RUNNER_PATHS` is never consulted by `test-all.sh` for a probe-only diff. — Recovery: dropped the entry in review. — **Prevention:** route to plan sharp-edges (below).
13. **An API 429 cut the session off mid-battery.** — Recovery: the coordinator resumed it; the battery was re-run from a committed SHA. — **Prevention:** commit before any long battery (done).
14. **shellcheck:** SC1010 (`done` passed as a word argument) and SC2034. — Recovery: quoted `"done"`; renamed the jq var to `$steady`; `for _ in`. — **Prevention:** run `shellcheck -S warning` before the RED commit.
