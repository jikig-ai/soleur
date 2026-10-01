---
title: The gate that caught it was the one suite I had no reason to run
date: 2026-09-20
problem_type: workflow_issue
severity: high
module: soleur-ship
tags: [ci, test-battery, ship, postmerge, silent-failure, exit-codes]
symptoms:
  - "local suites green, CI red on a suite the diff never touched"
  - "battery-owed never returns 42 on a fast-moving main"
  - "a piped command's exit status read as success"
synced_to: []
---

# The gate that caught it was the one suite I had no reason to run

Post-merge companion to
`2026-09-19-the-fix-keyed-on-the-symptom-of-the-state-and-the-old-tags-were-never-notifications.md`.
That one covers building the fix for #8339; this one covers everything after the
pre-merge compound — ship Phase 4 through postmerge — on PR #8378 (merged
`4d46b72c8`).

## Problem

The branch changed three test suites and two skill fences. All three suites were
green locally. CI's `test-scripts (1/3)` shard went red on
`scripts/battery-tag-authorship` — a suite the diff never touches — with five
OFFENDER rows, every one of them inside the two fixture files this branch had
just written.

## Root cause

`battery-tag-authorship` walks the **battery closure**, not the diff. Any
git-network command reachable from a registered suite must declare itself, and
the new real-git fixture rows used bare `git fetch -q origin` / `git pull -q
origin main`. The fix was `--no-tags` — the gate's SUPPRESSED arm, and
semantically correct besides: these fixtures build their own origin in a tmp
sandbox and create no tags.

The reason it took CI to find it is the interesting part. Running the three
changed suites directly cannot reach it, because the gate **is a different
suite**. "I ran the tests I changed" is not a statement about the gates that
read what I changed.

Its mutation sibling compounded the signal: `battery-tag-authorship-mutations`
runs the same subject as its CONTROL, so one red subject voided all 21 mutation
rows — `CONTROL — unmutated subject is RED (rc=1). EVERY ROW BELOW IS VOID.`

## Key insight

**A diff's blast radius in the test suite is not the set of suites it edits.**
It is the set of suites whose *inputs* it changes — and for closure-walking
gates (tag authorship, trap ownership, fixture content, orphan registration)
that set is unbounded by the diff's own file list. The only reliable local
discriminator is the full battery; the only cheap one is to grep which gates
enumerate a closure and run those.

## Solution

```bash
# Before: the fixture's new real-git rows
git fetch -q origin
git pull -q origin main

# After: the gate's SUPPRESSED arm, and what the fixtures actually want
git fetch -q --no-tags origin
git pull -q --no-tags origin main
```

`battery-tag-authorship` 14/1 → **15/0 (offenders=0)**;
`battery-tag-authorship-mutations` control-void → **21/0**.

## Session Errors

**1. Local suites green, CI red on a closure-walking gate.** Ran the three
changed suites directly (191/0, 5/0, 61/0) and read that as coverage;
`battery-tag-authorship` found five OFFENDER rows in those same files.
**Recovery:** `--no-tags` on all five sites; re-ran both gate suites green.
**Prevention:** after changing any file reachable from a registered suite, run
the gates that walk the closure — not only the suites you edited. `bash
scripts/test-all.sh --enumerate scripts | grep battery-` names them in seconds.

**2. `battery-owed.sh` never converged on a fast-moving main.** Three CI cycles
went green on the head; each time `origin/main` had advanced before the shards
finished, so the ancestry precondition ("CI verified *this* tree") lapsed and
the gate re-reported OWED. **Recovery:** launched the local battery in parallel
with CI instead of serializing another attempt. **Prevention:** treat
`battery-owed` as an opportunistic saving, never a step to wait on. If the first
call returns OWED, start the battery immediately and let CI race it — the gate
needs a tree that stops moving, and a busy `main` does not provide one.

**3. Read `tail`'s exit code for a blocked commit — the very defect this PR
fixes.** `git commit --no-edit 2>&1 | tail -20; echo "rc=$?"` printed `rc=0`
while `skill-body-budget-lint` had refused the commit; `HEAD` was unchanged and
the success was nearly acted on. **Recovery:** re-ran as `c_rc=0;
c_out="$(git commit --no-edit 2>&1)" || c_rc=$?` → `rc=1` and the real
budget error. **Prevention:** never end a pipeline with the command whose status
you need. Capture first, display second — the same idiom this PR put into the
phase-7 fence. The defect class is live in ordinary agent shell work, not just
in the block that was fixed.

**4. Gated on the wrong `workflow_run` deploy arm.** Selected "the workflow_run
arm on the merge sha" and got **Deploy Documentation to Cloudflare Pages**,
whose `deploy` job is the docs site; concluded `deploy=success` and began
polling `/health` for a `build_sha` that would never appear. **Recovery:**
re-queried by workflow, found `Web Platform Release` with
`deploy=skipped` (0 `apps/web-platform/` paths), and stopped the poll.
**Prevention — and the sharper point: the skill already prescribed the correct
query and I hand-rolled a looser one.** `postmerge/SKILL.md:337` selects the arm
with `select(.path == ".github/workflows/web-platform-release.yml")`; I
substituted `gh run list --json event` filtered on `event=workflow_run`, which
is ambiguous because several workflows produce a `workflow_run` arm carrying a
job named `deploy`. This is *already-enforced* — no new rule is owed. Run the
command the phase gives you; a paraphrase of a prescribed query drops the
predicate that made it correct.

**5. Merge-base budget-ceiling collision.** `main` added 641 B to
`ship/SKILL.md` and this branch 5691 B; each fits under the 274000 ceiling
alone, the merge did not (274605). A diff cannot raise its own ceiling — it is
read from the merge base by construction — so 647 B had to come back out at
merge time, under time pressure, from prose that had already passed review.
**Recovery:** condensed this PR's own additions and folded a now-triply-redundant
older list into the new numbered steps. **Prevention:** when a diff adds >2 KB to
a ceilinged file, check headroom against the ceiling *at plan time*, not at
merge. `ship/SKILL.md` now sits 42 bytes under and `postmerge/SKILL.md` 2 bytes under — tracked in #8419, which also records that route-to-definition is structurally blocked for both.

**6. `rule-metrics.json` conflicted on all three syncs, with opposite correct
resolutions.** Twice ours was newer (all counts ≥ main's), once main's was
(newer `generated_at`, a key we lacked). A fixed `--ours` habit would have
silently discarded real data on the third. **Recovery:** compared `generated_at`
each time and took the dominating side. **Prevention:** for any
counter-aggregate file, resolve by comparing the embedded timestamp, never by a
standing side preference.

**7. Monitor filters matched suites' own self-labelled control lines.** Runner
greps for `^[FAIL]` repeatedly fired on `(EXPECTED, not a defect)`,
`expected to FAIL`, `positive control … (this FAIL line is expected)` —
three re-arms of filter churn. **Recovery:** anchored the pattern and excluded
the self-labelling idioms. **Prevention:** one-off; the rc file is the verdict,
so prefer watching it over in-log `[FAIL]` text.

**8. `monitor-supersede` reported expired monitors as live.** Its liveness read
is transcript-derived and listed four monitors that had already announced
expiry; one `TaskStop` returned `No task found`. **Recovery:** ignored the
stale rows after confirming via the expiry notices. **Prevention:** trust the
expiry notification over the supersede listing; tracked in #8420.

## Prevention (summary)

- Blast radius in the suite = suites whose **inputs** changed, not suites edited.
- `battery-owed` is an optimisation, not a step — race it, never wait on it.
- Capture rc, then display. Never `cmd | tail` when the status matters.
- Run prescribed queries verbatim; a paraphrase silently drops the load-bearing predicate.
- Check ceilinged-file headroom at plan time.
- Resolve counter aggregates by `generated_at`.

## Routing disposition

Items 3 and 4 are **already-enforced** — 3 is the fix this PR shipped into the
phase-7 fence; 4 is prescribed verbatim at `postmerge/SKILL.md:337` and was
deviated from, not missing. Items 1 and 2 belong in `ship/SKILL.md` Phase 4 and
could **not** be routed there: the file has 42 bytes of headroom under its
ceiling, and `postmerge/SKILL.md` has 2. That blockage is #8419; item 8 is
#8420.
