---
module: System
date: 2026-09-19
problem_type: logic_error
component: tooling
symptoms:
  - "a self-matching poller with an ERE group or an awk `&&` fell open on a quote-blind terminator cut"
  - "the hook's own remedy `grep -c PAT | grep -v grep` read as filtered — a count cannot be filtered"
  - "`ps aux | grep PAT | awk '{print $2}' | xargs kill` was allowed: a no-regex awk was read as a filter"
  - "`ps -C bash -o comm` denied: the value `bash` was read as a BSD flag bundle"
  - "a 100 kB command with one benign pipeline cost 4.8 s: `${rest#*\"$m\"}` is quadratic in the offset"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [hooks, self-match, pipeline-parsing, mutation-testing, bash-performance, guard-review]
rule_id: cq-assert-anchor-not-bare-token
related_issues: ["#8330", "#8231", "#7994", "#8354"]
synced_to: [review]
---

# I simulated the regex correctly and segmented the pipeline by eye

## Problem

#8330 asked the self-match guard to cover the read-only spelling: `ps <args> | grep <pat>`
counting itself because the Bash tool wrapper's argv carries `<pat>`. The plan replaced the
issue's "pattern appears elsewhere" heuristic with a **simulation** — extract each stage's
regex and run it against `bash -c <command>` — and that part was right on every fixture the
plan wrote and on its 13-row mutation battery.

Everything that went wrong was in the part that FEEDS the simulation: how the hook decided
where a pipeline starts, where it ends, and what each stage IS. Ten review seats found one P1
and ten P2s, and every one reduced to three structural roots plus one performance root:

1. **Pipeline segmentation was done on raw text.** `pl="${pl%%[;&)\n]*}"` cut at the first
   terminator character wherever it sat, including inside the matcher's own quoted literal.
   So every ERE group (`'(test-all|zzqq)'`), every awk program with `&&` or `)`, the
   `&` of `2>&1`, `|&`, and a newline after `|` all severed the stage, left an unterminated
   quote, and fell OPEN. The `ps` boundary regex likewise had no bash keywords, so
   `while ps … | grep -q`, `until ! ps …`, `if ps …` — the canonical wait-for-quiet
   loop shapes, two of them in this repo's own learnings — never triggered.
2. **grep was modelled as a pure line filter.** A later `grep -v grep` was simulated as
   filtering the wrapper line, but after `grep -c` the stream is a NUMBER. The deny reason
   itself prescribed `| grep -v grep`, so an agent applying the remedy to a `-c` poller was
   waved through with the count still inflated.
3. **An awk stage with no `/re/` was read as "wrapper filtered".** The plan wrote that rule
   for the argv-slot recipe (`$1=="bash" && $2=="x"`), and it is right for that shape. It is
   wrong for a projection: `ps aux | grep PAT | awk '{print $2}' | xargs kill` — the most
   common form of exactly the defect the hook exists for — went from deny to allow when the
   awk was appended. Neither the plan's TDD rows nor its battery had a projection fixture.
   The `ps` flag classifier had the same shape one level down: a value token (`-C bash`,
   `-u jean`) was re-read as a BSD letter bundle, so `ps -C bash -o comm` (name-only, cannot
   self-match) was denied whenever the value happened to contain `a`, `u` or `x`.
4. **The walk's cost scaled with the command, not the pipeline.** `${rest#*"$m"}` — shortest
   prefix removal with a leading `*` — is quadratic in the match offset (measured 2.8 s at
   80 kB); the lib was sourced before the pre-trigger (+12–19 ms on every Bash call, when the
   plan claimed +0.17 ms); and a group-free `.{1,32767}.{1,32767}b` reached 4.2 GB inside the
   2 s timeout.

## Solution

- A quote-aware `split_pipeline` that walks the text after `ps` once, honouring `'…'` and
  `"…"`, treating `|`/`|&` (and a newline after them) as stage separators, `>&`/`<&` as
  redirects, and stopping at the first UNQUOTED `;` `&&` `||` `&` `)` backtick or newline.
  A `|` inside a quoted pattern is now the ERE alternation it is — and it self-matches, so
  the plan's A22 allow flipped to a deny.
- The `ps` boundary is judged on a bounded context window with a regex that admits shell
  keywords, `{`, backtick, env-assignments and prefix words (`LC_ALL=C ps`, `timeout 5 ps`,
  `/bin/ps`, `\ps`); the matcher word is normalised the same way (`\grep`, `command grep`,
  `/usr/bin/grep`, `rg`).
- `-c/-o/-l/-L/-q` (and their long forms) END the walk with the verdict so far; a no-regex
  awk also ends the walk with the verdict so far instead of filtering. `classify_ps` is one
  pass in which every value-taking option consumes its value.
- `${rest/ps*/}` + substring for the literal scan (6 ms at 100 kB vs 262 ms for
  `${rest%%ps*}` and 2.8 s for `${rest#*ps}`); `LC_ALL=C` scoped to the arm; the lib
  sourced only after a cheap pre-trigger; a 4 s per-hook budget; `ulimit -v 256M` around the
  simulation grep.
- 62 new suite rows, one per branch the first battery sampled once or never; the floor is
  exact (126), so deleting any single row breaches it; telemetry rows assert a DELTA on the
  sandbox ledger rather than overriding `INCIDENTS_REPO_ROOT` per call (an empty override
  from a failed `mktemp` resolves to the operator's REAL ledger — the 2026-09-03 class).

## Key Insight

**The simulation was the hard-looking part and it was right; the tokenizer around it was
the easy-looking part and it was wrong four ways.** When a guard's design has a clever core
(run the real regex against a model of the real corpus), review attention goes to the core.
The failures live in the plumbing that decides what reaches the core: where a stage begins
and ends, what a stage's first word is, which flags change what the stage OUTPUTS. Every one
of those is a grammar question, and a grammar reviewed against the one spelling it was
written for (`ps -eo args | grep -c 'x'`) is exactly the guard-written-against-one-spelling
shape the issue itself named — reproduced inside the fix.

Two corollaries the round measured:

- **A plan-stated design rule at a SEAM is a claim to fixture in both directions.** "An awk
  with no `/re/` is the argv-slot recipe → filtered" was true of the only awk-without-regex
  fixture the plan had. The TDD rows were RED-first, the battery was 13/13 — and the row
  that falsifies the rule (`grep PAT | awk '{print $2}'`) was never imagined because the
  rule was written FROM the fixture. Ask of every "X means Y" rule: what else produces X?
- **My own instruments were wrong five times before the panel's findings were.** A
  `timeout … command grep` (rc 127 on a builtin) made every pipeline fail open through a
  green suite; perl replacements interpolated `$CMD` to empty and three rows went RED for
  the wrong reason; a `suite | grep -q` under `pipefail` read SIGPIPE as a flipped row; a
  perf script pointed at a missing hook printed `2ms` and read as fast; a battery rewrite
  left a syntax error that silently dropped 19 of 28 rows. None of them errored — each
  answered. Run every instrument against a known positive AND a known negative before
  reading its verdict, and count the rows it reported against the rows it was given.

## Session Errors

1. **(forwarded) The live `-f` arm denied two planning-session Bash calls** whose text carried
   the spelling. — Recovery: Write-tool scripts, split-variable probes. — **Prevention:** on any
   branch editing a hook that greps command text, route every edit/probe that must contain the
   guarded spelling through a file written by the Write tool; the plan's Sharp Edge said so and
   it still bit five times (items 1 and 6).
2. **(forwarded) Duplicate Monitor watchers** were superseded and stopped. — One-off.
   **Prevention:** one Monitor per task directory.
3. **`timeout … command grep` → rc 127 → every pipeline fail-open, all 19 D rows allow** on the
   first GREEN attempt. — Recovery: `type -P grep` and exec the binary. — **Prevention:**
   `timeout` execs its argument; a builtin or a shell function cannot sit there — resolve the
   binary with `type -P` (same for `timeout` itself).
4. **Battery perl replacements interpolated `$CMD`/`$psflags` to empty**, so M3/M4/M8/M10 went
   RED with 21 failures — the wrong reason (the mutant was a syntax-preserving no-op). —
   Recovery: `\$` in every replacement. — **Prevention:** after each mutation, assert the
   intended CONSTRUCT landed (grep the mutated line), not just that md5 changed; a row whose
   failure count equals the "arm deleted" count is a broken mutant, not a kill.
5. **`run_suite | grep -qE` under `set -o pipefail` reported the M13 companion FLIPPED** — the
   documented SIGPIPE class, in my own harness. — Recovery: capture to a variable, herestring.
   — **Prevention:** `grep -q` never behind a pipe, in instruments too.
6. **The live `-f` arm denied three more of my own calls** (`gh issue comment --body-file`, a
   python-heredoc doc fix, the review/SKILL.md replacement text). — Recovery: bodies written via
   the Write tool. — **Prevention:** as item 1; tracked by #7994 (comment posted).
7. **The doc-probe "positive control" premise was wrong**: the learning section's poller sits in
   inline backticks, so it is allowed by the boundary rule regardless of the heredoc — the
   control could not fire. — **Prevention:** before recording a control, confirm the fixture
   reaches the branch the control is meant to prove (here `strip_heredocs`); the fenced A6
   fixture is the one that does.
8. **The plan's "no-regex awk = wrapper filtered" rule was a P1** carried from plan through TDD
   and battery. — Recovery: the walk ends with the verdict so far. — **Prevention:** a rule
   written from one fixture needs a second fixture on the other side of the seam; ask "what
   else produces this shape".
9. **First perf fix `${rest%%ps*}` measured 262 ms at 100 kB** (fnmatch per position) —
   better than 2.8 s, still 10x the 6 ms `${rest/ps*/}` idiom. — **Prevention:** micro-benchmark
   three idioms before choosing; bash pattern ops differ by two orders of magnitude on the same
   task.
10. **A boundary-triage `case` was added to dodge regex-compile cost**; the simplicity seat
    measured it bought nothing (956 → 936 ms on the synthetic) and it was a second copy of the
    boundary set. — Recovery: cut. — **Prevention:** measure before adding a pre-filter; a
    pre-filter that must stay in sync with the thing it pre-filters is a new invariant.
11. **A perf script pointed at a wrong path printed `new=2ms` for every case** — a missing hook
    reads as a fast one. — **Prevention:** a benchmark harness must assert the hook it timed
    produced a verdict (deny/allow), never only a duration.
12. **A battery rewrite left a dangling fragment → syntax error mid-run**; 9 of 28 rows
    reported, the rest lost silently. — Recovery: counted rows, repaired, re-ran. —
    **Prevention:** `bash -n` the battery after editing it, and compare rows-reported to
    rows-defined.
13. **AC11/AC13 went FAIL after the review edits** (the anchored clause was reworded; a new
    file joined the diff). — Recovery: amended the ACs explicitly with a review-round note. —
    **Prevention:** an AC that fails after a legitimate change is amended in the plan with the
    reason, never satisfied by a looser check.
14. **The full gate was refused (sibling run in flight)**; per-suite fallback ran 19 consumer
    suites + ratchets; `lint-window-closure-assertion.py` red is pre-existing on `origin/main`
    (same two files). — **Prevention:** compare a red ratchet against `git archive origin/main`
    before treating it as this branch's.
15. **4,000 bare `ps` tokens in 20 kB still cost ~2 s** — bash copies the remainder once per
    token (O(n·k)); named in the header, bounded by the 4 s budget. — **Prevention:** state the
    residual cost class in the header rather than chase it; no one types that shape.

## Prevention

- **Guard-shaped diff: run the cheap deterministic instruments BEFORE the panel.** shellcheck
  found one defect here; the structural-enumeration seat's 330-shape map found the classes
  the ten adversarial seats each sampled one instance of.
- **For any text-segmenting guard, write the tokenizer first and fixture its grammar**: one
  row per terminator, per quoting form, per prefix word, per output-mode flag — then the
  simulation. The first battery had 13 rows on the simulation and zero on the tokenizer.
- **Feed the guard its own remedy text.** Every recipe the deny reason prescribes must be
  ACCEPTED by the guard, and every recipe must be correct in the failure DIRECTION of its
  context (a count context turns a loud kill failure into a silent "done": `kill -0 $!`
  under setsid, `pgrep -a <name>` on a `bash x.sh` runner).

## Related

- #8330 (this), #8231 (the incident), #7994 (guards fire on documentation about themselves —
  five instances this branch), #7525 → `proc.sh`
- `2026-09-18-every-instrument-i-waited-on-was-counting-itself.md` — the incident record
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md`
