---
title: An exec line exact-match pinned by a live-host probe forces a conditional-branch edit, never a rewrite
date: 2026-10-27
category: best-practices
component: apps/web-platform/infra/git-data-transport-wrapper.sh
synced_to: [soleur:plan]
tags:
  - exact-match-pin
  - live-host-probe
  - pin-inventory
  - conditional-branch
  - git-data
related:
  - https://github.com/jikig-ai/soleur/issues/8211
  - https://github.com/jikig-ai/soleur/pull/11342
  - knowledge-base/project/plans/archive/20261027-191424-2026-10-27-fix-git-data-store-shallow-push-plan.md
  - knowledge-base/project/learnings/test-failures/2026-10-27-shallow-fetch-red-trigger-is-a-shallow-store-not-a-deep-ref.md
---

# Learning: an exec line exact-match pinned by a live-host probe forces a conditional-branch edit, never a rewrite

## Problem

The brief for #8211 asked for `-c receive.shallowUpdate=true` on the wrapper's
receive-pack exec argv "ONLY — the upload-pack exec line stays unchanged". The
wrapper has ONE shared exec line for both verbs
(`exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"`), so the
naive reading — edit the line — collides with three pin sites. The load-bearing
one is not in the diff's own test suite: `apps/web-platform/infra/git-data-cutover.sh:689`
carries `pin_ex`, a production fence-intactness probe that SSHes to the LIVE
host and `grep -qxF`s the literal against the DEPLOYED wrapper. Rewriting the
line would have kept every local suite green while flipping every production
fence probe to exit 18 `transport_pin_mismatch` on its next run — the
fix-forward's own defect class, caught at design time only because the plan ran
a pin inventory first.

## Solution

Preserve the pinned literal VERBATIM as the generic branch and add a conditional
arm for the new case:

```bash
if [ "$verb" = "git-receive-pack" ]; then
  exec git -c "core.hooksPath=${HOOKS_DIR}" -c receive.shallowUpdate=true receive-pack "$repo_real"
fi
exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"
```

and mirror the same conditional in the test-only DRYRUN echo. All three pin
sites stay green with zero pin edits: the `grep -qxF` live-host probe, the T11
`grep -qE '^exec git …$'` literal pin, and the P2 parity pin whose `sed -i
'/^exec git -c "core.hooksPath=/d'` mutation arm still deletes every matching
exec line including the new branch.

## Key Insight

Before rewriting ANY line, inventory what exact-matches it: grep the repo for
the literal, and specifically for `grep -qxF` / `grep -qE '^…$'` pin sites and
for probes that run the match on a LIVE host. A pin's blast radius is where the
match RUNS, not where it lives — the probe reads the deployed file, so the
invariant is "the literal still exists in the new file", not "the diff kept it".
Exact-line pins force additive/branch edits; rewrites are only safe after the
pin census comes back empty. The same inventory catches co-change obligations a
brief never names (`git-data-transport-wrapper.test.sh`'s T2/T11 expectations and
its exact-count floor moved with the wrapper in this diff).

## Session Errors

- **`CLAUDE_PLUGIN_ROOT` unset in the subagent's exec shells** (forwarded from
  the plan phase; recurred in QA+compound) — Recovery: resolved the plugin root
  by IDENTITY per the cloud-mode fallback. — **Prevention:** resolve
  `CLAUDE_PLUGIN_ROOT` by identity in exec shells; never assume the export.
- **No Task/Skill/agent-spawn capability in the subagent harness** (forwarded) —
  Recovery: in-process gates ran and the plan disclosed it; parent discharged
  the two-spawn consult allowance. — **Prevention:** verify spawn capability
  before prescribing agent fan-outs in a plan.
- **None in the QA phase itself** — all four suites green on first run.

## Tags

category: best-practices
module: apps/web-platform/infra
