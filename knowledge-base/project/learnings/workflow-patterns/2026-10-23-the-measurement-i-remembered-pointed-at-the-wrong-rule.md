---
title: "The measurement I remembered pointed at the wrong rule; the deny class carried the fix"
date: 2026-10-23
category: workflow-patterns
issue: 10819
pr: 10863
synced_to: [plan-sharp-edges, one-shot]
tags: [measurement-provenance, guard-envelope, cwd, deny-class, plan-review, correlation]
---

# Learning: a remembered measurement named a rule I could not reproduce, and the fix did not need it

## Problem

A plan carried this measurement from a probe run before a context compaction:

> `cwd=sessionDir` → allow; `cwd=workdir` → `ask`, rule `recursive-delete-workdir`.

The fix was built on the general claim, which was sound: the Bash guard envelope carried the session
directory, so a `shell` call with a per-call `workdir` was judged against the wrong directory.

The specific rule was not reproducible. At three different cwds, `rm -rf *`, `rm -rf .` and
`rm -rf ../sess` were all **allowed**. The guard's own matcher for the workdir rule is
`(( glob == 0 )) && anc_or_eq "$RP" "$SIMCWD"`, so the class exists in the code — but the command
that produced the recorded `ask` was never written down, and I could not find it.

What *was* reproducible, end to end through the plugin and the real guard script:

```text
rm -rf *   with capture workdir=$HOME   → effect=deny  rule=recursive-delete-home
rm -rf *   with no capture (session)     → effect=allow (no rule matched)
```

Same command, same event shape, different directory alone. The home rule resolves the glob
directory and compares it to `$HOME`; the session checkout is neither home nor an ancestor of it, so
the pre-fix envelope made the deny unreachable.

## Why it matters

1. **A measurement without its command is a memory, not evidence.** The rule name and the verdict
   survived the compaction; the input that produced them did not. Reproducing it would have taken
   one line in the original record.
2. **The claim was still true, and the load-bearing arm was a different one.** The plan asserted the
   `ask` was lost; the measured loss is the `deny`. Shipping the remembered version would have put
   a false mechanism in a PR whose subject is false records — and a reviewer reproducing it would
   have found the plan wrong while the code was right.
3. **The weaker measurable arm was the worse failure.** A lost `ask` is a prompt the operator never
   got. A lost `deny` is `rm -rf *` against `$HOME` with no prompt of any class. Building the QA
   probe around the arm I could reproduce made the PR's headline claim stronger, not weaker.

## Rule

When a plan inherits a measurement across a compaction, re-run it before shipping, and **record the
exact command alongside the verdict**. If it does not reproduce, do not delete the finding quietly
and do not keep the claim: write down that it did not reproduce, name what did, and check whether
the fix depends on the unreproducible part. Here it did not — the wiring is the same for every
cwd-dependent rule — so the correction cost one paragraph and removed a false sentence.

## Secondary: the review found the defect the tests could not

The unusable-workdir branch set `effect = "ask"` and returned **before** the guards ran, and before
the existing "an arriving deny is never relaxed to an ask" guard. A model-controlled `workdir` could
therefore suppress a credential deny or a home-wipe deny — the exact class the PR existed to protect,
reintroduced by the protective branch. No test saw it: every fixture used `effect: "allow"`.

The panel round that catches this is not "does the diff look right" but "what does each new branch
do to the invariants the file already states". The fix was three lines (run the guards against the
session directory, keep an arriving deny, and let only their declining become the prompt) and two
tests that fail if either half is removed.

## Evidence

- `plugins/soleur/opencode/plugin.ts` — `decidesBash`, `resolveWorkdir`, `decisionCwd`,
  `applyDecision`, the capture binding and the module's INVARIANTS block.
- `plugins/soleur/test/opencode-plugin.test.ts` — "the per-call workdir reaches the guard envelope
  (#10819)", 27 rows, each mutation-red proof recorded in the PR body.
- QA probe (not committed): capture `workdir=$HOME` → `deny recursive-delete-home`; no capture →
  allow. Same for the plan's measurement record.
