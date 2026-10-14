---
title: "A mechanical rewrite of 800 test lines needs a shell-aware classifier — about one in five hits is data or an executed string, and a regex tokenizer misreads the rest"
date: 2026-10-07
category: test-failures
module: scripts/grep-q-drain-codemod.py + .claude/hooks/grep-q-pipe-guard.test.sh
issues: [9217]
---

# Code versus data before a transform

## Problem

Wave B of the `grep -q` sweep rewrites `<producer> | grep -q P` to `<producer> | grep -c >/dev/null P` across 804
test-harness lines. The rewrite is one letter plus one redirect, so a reviewer can prove each converted line is
faithful. What no diff reader can prove is that the line SHOULD have been converted: a hook-input fixture
(`run_case 'T1' 'while ps | grep -q zz; do :; done' deny`), a source-text pin of a carrier that still has the shape, and a
deliberate SIGPIPE demonstration all match the sweep's pattern and all stop meaning what they mean once converted.
Measured on `origin/main` `411f034290` (command: the codemod's dry run, `python3 scripts/grep-q-drain-codemod.py apply`):
of S1's 107 in-scope lines, 98 are plain code, 5 are quoted hook inputs, 3 are `-m` (output-bearing, still an early
exit) and 1 is a demo.

## What the first classifier got wrong (all caught by reading the dry run's queue, not by a test)

- **A prefix probe is the wrong instrument for "where did the tokenizer lose balance".** Re-tokenizing growing prefixes
  of `devin-matcher-parity.test.sh` reported "unbalanced" at the first line inside any multi-line command, which is
  every prefix that ends mid-pipeline. The useful signal is the stack at EOF with each frame's opener position
  (it named line 378 in one step; the position bookkeeping was removed again once the frames below went).
- **`${rule#Bash(}` is a pattern, not a subshell.** Inside a `${...}` the `(` must not open a frame, or the closing `}`
  never pops and the rest of the file reads as quoted. Five hits in one file went to the queue as `unsure`. The review's
  simplicity pass then showed the parameter, bare-parenthesis and backtick frames bought nothing on the real population
  (the dry run over all 827 sites diffs to nothing without them), so the tokenizer tracks only quotes, `$(` and `$((`; fewer frame
  types means fewer ways to end unbalanced.
- **A tail scan for a stdout redirect has to use the same code/quote map.** The first version searched the text after the
  match for `>` and refused two lines whose `>` sat inside the single-quoted pattern (`'soleur:__probe__->nonexistent_phase'`,
  a tagger-line pattern ending in `github\.com>`). The dry run showed them as `X:stdout-redirected`; reading the lines showed they
  were not redirects. Only a code-context `>` that is not `2>`..`9>` counts, and it must stop at the end of the command.
- **The demonstration-suspect rule is over-inclusive on purpose.** Files whose text names sigpipe, EPIPE, false-FAIL or
  broken pipe are never auto-applied. In S1 that routed 7 hits in 5 files to a human; reading them showed four files only
  mention the word in a comment, so they were applied with an explicit `--reviewed-suspect PATH` and the fifth
  (`iac-plan-write-guard.test.sh`, T6) got the `# sigpipe-demo: intentional` marker instead. The earlier partial pair run
  had shown the rule's value: two suites (`iac-plan-write-guard` T6, `scan-workflow-mutation` D1a/D2) failed after a blind
  conversion because the converted line was the thing the row demonstrates.

## What works

- Take the population from the guard itself (its `SWEEP_*` strings, its pathspec, its comment and marker filters) so the tool
  and the guard cannot disagree about what a site is. The dry run's `POPULATION: 827 lines` (on `origin/main`; 725 once this slice's 102 hits are gone) equals the guard's own
  `DEFERRED:` sum (804 test-shaped + 23 production).
- Print what was refused with a reason (`QUEUE path:line:tier:reason`). The queue is the first thing a reviewer reads; it is
  what caught every misclassification above.
- Refuse on unsure: an unbalanced tokenizer distrusts the whole file, not the line.

## Prevention

When a rewrite tool has to decide "code or data", its dry run must list every refusal with its reason, and the first pass
over a real population must be read line by line before `--write`. A green suite after a blind conversion is not evidence for
data lines.

## Review additions

- A phantom heredoc opener (`(( x = 1 << 3 ))`) used to mark the rest of the file as a heredoc body without the tokenizer noticing,
  because the pending list was cleared at every newline; a heredoc whose delimiter never arrives now makes the file `unsure`.
- The unbounded-producer screen reads the text before the match on this line only. It now walks every continuation line above it,
  refuses a loop- or group-headed pipe (`done | grep -q`), and knows `tail -n 5 -f`, `--follow`, `logs -f`, `watch`, `ping`,
  `dmesg -w` and `/usr/bin/yes`. A converted pipe whose producer never ends hangs instead of taking SIGPIPE.

## Fix-round additions

- The closer rule above shipped dead for `}` and `)`: it was written `(done|fi|esac|\}|\))\b`, and `\b` needs a word character on one side, so a
  head cut at the pipe (a closing brace or parenthesis plus a space) never matched. Only `done` and `fi` were refused. Use `(?!\w)` after an alternation that mixes words and
  punctuation, and give every alternative its own refusal fixture row (a pass on `done` says nothing about `}`). The same fix round added `;` to
  the unbounded-word tail (`{ yes; } | grep -q`), `until` and `for ((`, and bounded the `tail`/`logs` gaps to 200 characters so a long line
  cannot make the screen quadratic.
- Each refusal fixture row needs a bounded twin that must still convert (`{ echo a; echo b; } | grep -q a`), or a screen that refuses every
  group passes the set.
- A failure message is code too. The refusal check's message named an unbounded producer in backticks inside double quotes, so the
  check ran `yes` the moment it FAILED (never while green). A mutation battery turned that into a 14 GB bash and took the host's memory.
  Run any battery under `ulimit -v`, one mutant at a time, and grep the failure strings you add for unescaped backticks and `$(`.

## Session Errors

Triage (recurring = fixed inline here or tracked; one-off = noted only):

1. **`\b` after an alternation of `}`/`)`/words made the group-closer refusal dead for two of its four heads** (introduced by fix round 1, found by two seats) — Recovery: `(?!\w)` plus one refusal fixture row per head and a bounded-group twin. Prevention: one fixture row per alternative of any alternation; a pass on one alternative says nothing about the rest. Recurring, fixed inline.
2. **A failure message quoted a command in backticks inside double quotes, so a FAILING check ran `yes` and bash buffered its endless output (14 GB in 16 s); the mutation battery took the host's memory twice** — Recovery: backticks removed, grep for unescaped backticks and `$(` in every `sweep_probe_fail+=(` string, battery rerun under `ulimit -v 6000000`, one mutant at a time. Prevention: batteries run under a memory cap and a watchdog; a failure string is code. Recurring, fixed inline.
3. **An in-place mutation battery edited the tracked codemod with no restore guard, so an interrupted session left it mutated** — Recovery: backup copy plus `cmp` before and after, `try/finally` restore. Prevention: mutate a copy, or restore in a `finally` and `cmp` against a kept copy before trusting the tree. Recurring, fixed in the battery.
4. **A process search by full command line, a foreground sleep, and a duplicate Monitor were each refused or redundant** — Recovery: search by process name plus `/proc/<pid>/cwd`, a Monitor until-loop, `TaskStop` on the duplicate. One-off.
5. **A `cd /var/tmp` inside a command reset the shell's working directory to the main checkout for later calls** — Recovery: absolute worktree paths on every command. One-off.
6. **A verification seat found the earlier fix-round reports missing from the scratchpad** — Recovery: judged round 1 from its commit message and diff. Prevention: copy seat reports a later seat must read into the spec directory. One-off.
7. **The closing text promised an action and the stop hook rejected it** — Recovery: did the action in the same turn. One-off.
8. **Forwarded from the plan phase:** two research-agent claims were wrong (`lint-orphan-test-suites` is advisory; `grep -c` exits 1 on a zero count like `grep -q`), the plan-time write guard blocked a draft once on a literal phrase, and a prototype pair run was stopped at 64 of 162 on a contended host. All recorded in the plan. One-off.

No `AGENTS.md`, skill or hook edit comes out of this: `plugins/soleur/skills/work/SKILL.md` sits about 60 bytes under its ceiling, and the lessons above are domain-scoped to test authoring, so they live here.
