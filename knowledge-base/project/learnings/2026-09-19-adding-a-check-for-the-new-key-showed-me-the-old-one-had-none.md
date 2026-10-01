---
title: "Adding a fail-closed check for the new key is what showed me the old key never had one"
date: 2026-09-19
category: workflow-issues
tags: [guards, fail-open, mutation-testing, measurement, review, workflow-fsm]
issue: 8325
pr: 8382
adr: ADR-229
module: scripts/classify-workflow-transitions.sh, scripts/measure-plan-sharp-edges-turns.sh
---

# Adding a check for the new key showed me the old one had none

## Problem

PR #8382 resolved three operator rulings on the workflow FSM: declare
`postmerge -> work`, collapse `brainstorm`'s designed `compound` sub-step in the
offline classifier, and replace ADR-229's "plausibly large and **unmeasured**"
per-turn saving with a measured number.

All three landed and every gate was green. A six-seat review then found **31**
findings, **6 of them P1** — and every P1 was in my own work, with five of the six
in the *verification* rather than in the feature.

## The generalisable lesson

**A guard you add for a new thing is the instrument that measures whether the old
thing was ever guarded.** §2 required a fail-closed check that the derived view
carries a `sub_steps` object. Writing it took two lines. What it exposed was that
the *pre-existing* `transitions` key — the edge set the whole classifier exists to
read — had no such check at all:

```
$ jq 'del(.transitions)' view.json > stale.json
$ classify-workflow-transitions.sh --summary
undeclared=0 sessions=0 pairs=0 nonnode=0 substep=0 read=0 dropped=0   # rc 0
```

`undeclared=0` over an **empty edge set**, at exit 0 — the exact silent zero the
script's own header claims it fails closed on. It had only ever checked that the
file was *readable*. The asymmetry was invisible for as long as neither key was
checked; it became obvious the moment one was.

Corollary, same PR: the corpus was widened to rotated `.jsonl.gz` archives in an
earlier round and the *absence* guard was not widened with it, so an empty or
non-gzip archive set `found=1` before `zcat` produced anything — empty report,
rc 0, no null-reading marker.

**When you add a guard, ask what its SIBLINGS are and whether they have one.**

**And then it happened again, inside the fix.** The `transitions` check I added
in that round was CONTAINER-ONLY — `type == "object"` and nothing more — while
the `sub_steps` check written beside it already asserted its members, with a
FATAL line naming the reason: *a STRING value would pass a container-only check
and then collapse by SUBSTRING match*. I wrote that sentence and did not apply it
to the sibling two lines above. A ship-gate consult found it:

```
$ jq '.transitions = {"plan":"workshop"}' view.json > bad.json
$ classify-workflow-transitions.sh --summary
undeclared=0 sessions=1 pairs=1 ...                                   # rc 0
```

`"workshop" | index("work")` is `0`, so `plan -> work` reads as declared. The
suite agreed: case 26 drove five shapes at `sub_steps` (`missing`, `null`, `[]`,
string value, non-string member) and case 29 drove **two** at `transitions`. The
asymmetry survived the round whose whole subject was asymmetry, in both the code
and the test, because "add the same check to the sibling" and "add the same SHAPE
LIST to the sibling's case" are two separate acts and I only did the first.

**A sibling sweep is not done when the guards match — it is done when the shape
lists that DRIVE them match.** Grep the fixture loop, not the guard.

## Second lesson: a fix for a counter bug has two directions

The first review round found that `dropped=` could go **negative** — `read_lines`
came from a `grep -c` taken separately from jq's parse, so a transcript appended
to between the two reads made `parsed > read_lines`, and that negative
contribution silently cancelled a genuinely unparseable file elsewhere. I moved
the line count inside jq. Correct, and it introduced the *opposite* bug:

| | `grep -c .` | `$lines | length` |
|---|---|---|
| counts | non-empty lines | **every** line |
| 3 records + 2 blank lines | `dropped=0` | `dropped=2` |

`dropped=0` is the parse-integrity signal ADR-229 quotes the whole reading with.
No fixture had a blank line, so the suite was entirely on one side. A third
direction was open too: a survivor the parser cannot open contributes to
*neither* counter, so the integrity number got **better** when a file became
unreadable.

**Check a counter fix in both directions and name the input that moves it each
way.** The final shape counts non-empty lines for `dropped`, adds `unread=` for
files the parser never opened, and refuses a corpus that read lines and parsed
zero records — the sibling classifier's refusal, which had never been carried
over.

## Third lesson: a rolling-window reading is not a measurement

ADR-229 received: *"4 of the 6 extracted runs skipped the pass, which is itself a
finding against 'loads on ~95% of plan runs'"*.

It was false. `k` is **right-censored**: a plan run still in flight has no
catalogue Read yet and scores `post_skipped`. A re-run on the same machine the
same day scored all four as `post`, with k ∈ {38, 73, 81, 125}:

```
first reading:  runs=31 post=2 post_skipped=4 median_k=61
hours later:    runs=32 post=7 post_skipped=0 median_k=73
```

I had read a measurement artifact as a finding and written it into an ADR as a
recorded doubt about whether the extraction's directive fires at all. Local
transcript retention is three days, so the corpus is a rolling window and **a
re-run does not reproduce a prior reading**. The ADR now quotes deltas for the
classifier (the absolutes drift), rests the keep decision on every individual k
clearing break-even by ≥ 3.9× rather than on a two-sample median, and carries the
censoring caveat explicitly.

Same class, cheaper instances in the same PR: `~450 MB of hidden memcpy`
(measured: ~36 KB of rows total, so ~17 MB) and `92 ADRs carry Amendment blocks`
(measured: 53 of 233). Both were written from reasoning that felt like recall.

## Fourth lesson: verification that cannot fail

Three guards in this PR could not have failed, and each looked fine:

1. **`SHELLOPTS=xtrace bash "$SUT"` is inert.** `SHELLOPTS` is readonly, so the
   assignment errors to the caller's stderr and the child runs *untraced*. The
   case text claimed "(xtrace inherited)" and ADR-229's Verification section
   repeated it. `set +x` — the first executable line of a script whose contract is
   that no transcript byte reaches either stream — was never exercised. `BASH_ENV`
   pointing at a file containing `set -x` is the working vector, and the case now
   carries a positive control that the vector fired.

2. **The suite was invisible to the vacuity meta-guard.** A literal here-doc
   opener inside a *fixture string* made `guard-vacuity-floor.test.sh`'s detector
   treat every following line as here-doc body, so the suite's own anti-vacuity
   floor was never found and the file scored `NOT_IN_POPULATION` — the meta-guard's
   closure assertions were satisfied vacuously for it. Removing the literal took
   firing floors 139 → 140. (Then the *comment explaining this* tripped the same
   detector, which is its own small lesson.)

3. **Nothing pinned the key SET of either collection.** Every invariant
   constrained the *shape* of an entry; none said which entries exist. A fully
   mirrored `qa: ["ship"]` entered green, and for `DECLARED_SUB_STEPS` a
   rule-legal `plan: ["compound"]` (key is a node ✓, value is a node ✓, value is
   not a declared successor ✓) passed every check while silently deleting every
   real `plan -> compound` pair from the reading.

## Session Errors

- **Wrote `post_skipped=4` into ADR-229 as a finding against the ~95% claim.** It
  was censoring, not skips; a re-run hours later scored all four `post`.
  Recovery: re-ran the script, rewrote the passage around deltas and per-run k.
  **Prevention:** before quoting any reading of a rolling-window corpus as a
  finding, re-run it once and state whether the two agree; if they differ, the
  number is a snapshot and must be labelled one.
- **A Python batch edit asserted mid-way and wrote nothing.** The script builds
  the whole string and writes at the end, so a failed assertion means *no* edit
  landed — and the suite's unchanged green read exactly like a landed edit.
  Recovery: `git diff --stat` showed an empty diff. **Prevention:** after any
  scripted multi-edit, assert the ARTIFACT changed (`git diff --stat`, or grep
  the new anchor) — never infer that an edit applied from a passing suite, which
  answers "does the tree pass", never "did my edit apply".
- **A jq comment appended to the end of a line swallowed its closing syntax.**
  `#` runs to end of line, so appending a note after `))` ate the rest of the
  expression; the only symptom was `unread=1` and a summary of zeroes.
  **Prevention:** never append a `#` comment to a line inside a heredoc'd jq
  program — put the note in the script header above the program.
- **Traded a negative-direction counter bug for a positive one.** See above.
  **Prevention:** for any counter fix, name the input that moves it in each
  direction and fixture both.
- **Wrote a warning comment using the literal it warns about.** The here-doc
  detector immediately swallowed the comment describing the here-doc detector.
  **Prevention:** when documenting a pattern a scanner keys on, describe it in
  prose rather than spelling it.
- **Began applying review fixes while a seat was still reading the worktree.**
  The code-quality seat reported a bash syntax error that was a transient
  snapshot of my mid-edit tree. Recovery: re-derived every one of its findings
  against HEAD before acting. **Prevention:** `review/SKILL.md` tells the PANEL to
  be report-only; it should bind the LEAD too — spawn, then touch nothing until
  every seat returns.
- **Added a fail-closed check for `transitions` that was container-only, in the
  round whose subject was that exact asymmetry.** The `sub_steps` check beside it
  already asserted its members and its FATAL text named the substring-collapse
  mode; `{"plan":"workshop"}` passed the new check and matched `plan -> work`.
  Found by the ship-gate advisor consult, not by the suite — case 29 drove two
  shapes where its sibling case 26 drove five. Recovery: `length > 0` + member
  type assertion on the guard, case 29 widened to all six shapes, both clauses
  mutation-proven (31/1 each). **Prevention:** when adding a guard to a sibling,
  diff the two guards' fixture SHAPE LISTS, not just the guards.
- **Quoted two figures from reasoning rather than measurement** (`~450 MB`,
  `92 ADRs`). **Prevention:** the existing rule already covers this; the gap is
  that it is applied to numbers in *code* and not to numbers in *rationale
  comments*.
- **`semgrep --config=p/bash` 404s**, so the SAST seat's run was vacuous for a
  bash-dominant diff and `shellcheck` was the real deterministic gate.
  **Prevention:** tracked separately — `review/SKILL.md` names a registry pack
  that does not exist.
- Forwarded from the plan phase: two `sleep`-based waits killed by the host
  low-memory guard (no effect); a banned process-grep spelling inside a comment
  string refused by the Bash guard and rephrased (the guard working as designed);
  `playwright` MCP failed to connect (unused).

## Prevention

- When adding a fail-closed check for a new key, grep its siblings and ask
  whether each has one. The new check is the measuring instrument.
- When a corpus is widened (a new file class, a new root), widen the *absence*
  guard in the same commit.
- A counter fix has two directions. Name the input for each.
- A rolling-window reading needs a second reading before it becomes a claim.
- For any guard you add during review, mutate it back out and confirm the suite
  reddens — a review-driven fix is written after the tests exist, so nothing
  forces coverage for it.
