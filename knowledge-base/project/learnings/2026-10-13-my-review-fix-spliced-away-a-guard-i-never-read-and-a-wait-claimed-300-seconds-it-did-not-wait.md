# Learning: a review fix that splices a test file between two markers deletes what sits between them, and a "300 s" claim about a counted loop needs the loop timed

## Problem

PR #10210 (#10138) added a bounded, fail-closed wait for a late Hetzner volume attachment to the git-data bootstrap
(`_gd_attach_wait`) and a deliberate late attachment to the rung-2 rehearsal. A ten-seat review panel, one CTO ruling,
a five-seat fix round and a verification seat found the following, none of which a green local suite reported.

1. **The loopback suite lacked the helper.** The plaintext-count unit gained a call to `_gd_attach_wait`, defined above
   the unit. `git-data-plaintext-snapshot-loopback.test.sh` extracts that unit by sentinel and builds its prelude from
   `log()` only, so every arm would have died at `command not found` in CI. The plan said "re-run, no edit expected": an
   audit claim about a consumer nobody had grepped.
2. **A "300 s" bound that was about 150 s.** The helper charged 10 s per pass but ran `settle` plus `sleep 5`. The plan,
   the ADR and the log all said "about the bound". Five seats refuted it independently, one by timing the extracted
   helper (bound 30 took 15 s).
3. **My own fix deleted an unrelated guard.** To prune the rehearsal suite's new guard I spliced between the guard's
   first line and the floor comment. That span also held an unchanged, main-baseline arm (the job-budget arm: every
   step bounded, ceiling at least the sum, each poll inside its step). I had read the diff with `grep '^[-+]'`, which
   drops the context lines, so the arm never appeared as deleted code. The floor moved by +8 against a +10 itemisation,
   and the two missing rows hid in that gap. Three seats found it. The same splice shape removed the `mutant()` helper
   and rows 6-13 from the plan-shape suite; that one announced itself (`mutant: command not found`).
4. **Pins that read as coverage.** Crash-credited-as-kill mutation rows, a heredoc loop pinned by text only (so `sleep 0`,
   a lost counter, `&& break` turned `|| break` all stayed green), and a rehearsal guard that no longer pinned the delay
   command, the 240 cap or the LUKS stagger.
5. **The design was larger than the requirement.** The plan's CTO rulings added an env seam, a second wait site that a
   first boot cannot reach, and in-loop settles. The simplicity seat's question ("what does the seam give that a stubbed
   `sleep` does not?") led to a CTO ruling deleting about 500 lines.

## Solution

- Added the helper to the loopback prelude and an instrument guard that fails loudly when it is missing.
- Made counted time equal real time (`sleep 10` per 10-s charge, no settle) and documented 300 s as a lower bound.
- Restored the deleted arm from the commit that had it, and re-derived the floor from a measured run (143).
- Added a runtime row that EXTRACTS and RUNS the heredoc loop with stub `sleep`/`blockdev`/`udevadm`/`timeout`, with
  five mutants that each assert their own sleep and settle counts, plus a refusal when a block device still reports
  size 0 before the single-shot probes that gate `luksFormat`.
- The CTO restored the three rehearsal pins and the four plan-shape refusal rows that the pruning had dropped.

## Key Insight

Two checks catch most of this class and both are cheap. After any edit that REMOVES or REPLACES a span of a test
file, read `git diff origin/main --numstat` and the DELETED lines unfiltered (never `grep '^[-+]'`, which hides the
context lines an enclosing splice also removes), and compare the deleted-line count to what you meant to delete. And
before writing "no edit expected" for a consumer of a changed unit, grep for every extractor of that unit (by sentinel
and by function name) and say what you found. A claim of the form "wall time is approximately the bound" about a
counted loop is a measurement, not an inference: run the loop with the clock and the stubs removed.

## Session Errors

1. **Workflow dispatch 422 on a required `reason` input** (pre-compaction) — Recovery: re-dispatched with only `reason`
   added — Prevention: read the workflow's `inputs:` block before composing a dispatch command.
2. **Two decision-challenges rows failed the technical-ruling gate** — Recovery: reworded to "Ruled by CTO agent, date: ..."
   — Prevention: copy the ruled-row shape from an existing row.
3. **The cryptsetup stub's `${*#prefix}` stripped per positional parameter** (pre-compaction) — Recovery: `_argv="$*"` —
   Prevention: expand `"$*"` into a variable before prefix-stripping in a stub.
4. **Mutation rows reused fixture state and `AW_SET` leaked from AM5 into AM6** — Recovery: reset the fixture and the
   variable per row — Prevention: reset every harness variable at the END of the row that sets it, not at the start of
   the next.
5. **A python splice nested a `<<'PY'` heredoc inside a `<<'PY'` heredoc** — Recovery: wrote the script to a file —
   Prevention: use a distinct terminator for the outer heredoc whenever the body embeds another.
6. **My splice deleted an unrelated, unchanged guard** — Recovery: restored the span from the commit that had it —
   Prevention: after any splice, `git diff origin/main --numstat` and read the deleted lines; assert the removed text
   equals the text you meant to remove; never read a diff through a `^[-+]` filter.
7. **A prune removed the `mutant()` definition and rows 6-13** — Recovery: restored from the committed file — Prevention:
   same as 6; run the suite before moving on (it named the defect).
8. **`grep -qxF "-k 2 10 ..."` parsed the pattern as an option** — Recovery: `--` — Prevention: `grep -- "$pat"`
   whenever the pattern can start with a dash.
9. **A sed ERE mutation arm had `$((...))` unescaped and did not land** — Recovery: escaped `\$\(\(`, relied on the
   suite's own landed-check — Prevention: write the mutation with a python exactly-one replace, not sed.
10. **Two SC2319 fixes, the first aimed at the wrong line** — Recovery: diffed shellcheck findings against `main` by
    source-line TEXT, not line number — Prevention: when a count is 1 over baseline, diff the findings by text.
11. **markdownlint ignores plan and spec directories and prints its usage when handed only ignored files** — Recovery:
    linted the ADR and runbooks, where the one MD032 was — Prevention: read the exit code and the first line, not just
    the output volume.
12. **The runcmd rehearsal starved on its hard-coded 420 s apt budget on this host (three runs)** — Recovery: a temporary
    copy with 1500 s, removed afterwards, 108/0 — Prevention: none in the repo (420 s is a deliberate margin under the
    600 s suite bound); report a starved fixture as "no claim", never as a pass.
13. **The plan shipped a seam, a second wait site and in-loop settles that review then deleted** — Recovery: CTO ruling,
    deletion, floors re-measured — Prevention: when a test seam's only justification is wall-clock cost, check whether
    the suite already stubs `sleep` before ruling the seam in.
14. **A plan/ADR claim "real wall time ≈ the bound" for a counted loop that charged 10 s and slept 5 s** — Recovery:
    `sleep 10`, no settle, docs say "lower bound" — Prevention: time the loop with the stubs removed before writing a
    duration into a plan.
15. **A helper call was added inside an extracted unit and a sibling suite extracting the same unit was not updated** —
    Recovery: prelude patched, instrument guard added — Prevention: `grep -rln '<unit sentinel>'` across the repo
    when touching an extracted unit, and put the result in the plan instead of "no edit expected".
16. **Shell cwd drifted into `apps/web-platform/infra`** — Recovery: absolute paths — Prevention: none needed beyond
    absolute paths.
17. **The stop hook fired on closing text that named a future action** — Recovery: a one-line `Paused:` statement of
    what was awaited — Prevention: when waiting on background seats, end with the `Paused:` label.

## Tags

category: workflow-issues
module: git-data bootstrap, review fix rounds, test harness
