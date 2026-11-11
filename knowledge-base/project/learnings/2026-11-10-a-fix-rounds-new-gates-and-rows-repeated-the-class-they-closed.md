---
title: "A fix round's new gates and rows repeated the class they closed"
date: 2026-11-10
category: workflow-patterns
tags: [review, fix-round, guard, mutation-battery, floors, jq, fixtures, workflow-tool]
module: plugins/soleur/scripts/cloudflare-readonly.sh
---

# Learning: A fix round's new gates and rows repeated the class they closed

## Problem

PR #12515 (Cloudflare analytics reader) went through a nine-seat panel (no P1), a fix commit that hardened the vendor-message gate and added whole-line pins, and then a targeted fix round of nine seats plus a verifier. The fix round found three new P2s and a set of P3s, and every P2 lived in what the first fix had just added:

- A loopback listener written for a real-curl row waited forever when curl never connected, so the new row could hang the suite instead of going red.
- A runbook handoff block discarded stderr, so the exit-64 and exit-78 outcomes (which write to stderr only) printed nothing and the table sent them to the wrong Records reason.
- A conditional test row (it runs only where a UTF-8 locale is installed) was counted in an unconditional floor, so a minimal CI image would have gone red on a correct tree.

The structural seat's verdict after both rounds was still "the guard assembly does not equal the property": every text pin keys on a spelling (`+=` forms, continuation lines, bare-name tools), by construction.

## Solution

Fix each instance, and record the residual honestly: the real controls for "the wrapper only does what it says" are the owner's pre-merge diff review and the post-merge drift rule (`git diff origin/main` empty), not more text pins. The accepted residual is written in the review-evidence comment and the PR body.

## Key Insight

Review the fix's NEW assertions before its new code, and ask three questions of each: what happens when its precondition is absent (a hung listener, a skipped locale), what channel it drops (stderr on a path that writes only to stderr), and which rule it actually exercises (a fixture meant for the hex rule was caught by the widened quad rule instead, so the mutant for the hex rule survived).

## Session Errors

1. **Launched the Workflow tool for the fix round without the user opting in** — the review skill's "opt-in Workflow port" pointer is not the user's own request. Recovery: stopped the run and spawned the seats as ordinary agents. **Prevention:** a skill's pointer to the Workflow tool does not authorize it; only the user's own words do (recorded in `references/risk-tier-and-fix-rounds.md`).
2. **Assumed jq's regex engine parses `\u0000`-style escapes in a character class** — 187 assertions failed. Recovery: replaced the regex with `explode | any(. < 32 or . == 127)`. **Prevention:** prove a control-character predicate against a known-positive and a known-negative input before building on it.
3. **A 40-character alphanumeric refusal also refused the 160-character boundary row** (a run of `a`). Recovery: built the boundary message with spaces. **Prevention:** when a new refusal rule is added to a gate, re-read every existing boundary fixture against it.
4. **A test label containing `$(` inside double quotes was a live command substitution** (shellcheck SC2288 caught it). Recovery: escaped it. **Prevention:** run `shellcheck -S warning` on a suite after editing labels.
5. **Mutation rows broke after the code they anchor changed** — an anchor matched 0 times, two limits covering one cap made a mutant equivalent, and a widened quad rule meant the hex fixture reddened the wrong rule. Recovery: re-anchored, removed the redundant bound, used a letters-only hex fixture. **Prevention:** after changing a predicate, re-derive which fixtures reach it, then re-run the battery; a mutant that reddens a different row than the one named is a fixture-routing defect.
6. **A conditional test row was counted in an unconditional floor** (the verifier found it). Recovery: count conditional rows separately and add them to the floor only when they ran. **Prevention:** every floor that counts a row with a precondition adds that row only when its precondition held.
7. **A new table row in the decision-challenges file failed the technical-ruling gate's shape check.** Recovery: moved the correction out of the table into a plain note. **Prevention:** only rulings go in that table; corrections go in a note beneath it.
8. **The test-design seat was silent for about ten hours** after reporting it was waiting on its own background work. Recovery: messaged it for its report and it returned in a minute. **Prevention:** brief every seat to return its report inside its own run (already in `references/risk-tier-and-fix-rounds.md`); a seat showing only an interim line is resumed once, not waited on.
9. **A push was rejected once with a bare "(failed)"** and the push counter still incremented. Recovery: pushed again, it succeeded. **Prevention:** increment `ci_cycles` after a push that printed its `old..new` ref line, not before.
