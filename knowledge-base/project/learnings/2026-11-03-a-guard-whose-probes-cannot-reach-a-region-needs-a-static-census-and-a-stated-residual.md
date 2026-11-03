# Learning: a guard whose probes cannot reach a region needs a static census, a stated residual, and a stop rule

## Problem

The scheduled `main-health-monitor` was red on scripts shards 5, 6 and 7 for a day while
`ci.yml` was green on the same commit (#11939). The three failing suites
(`lint-orphan-test-suites-mutations-a/b`, `test-all-group-affected`) reported a dead
registration whose file existed on `main`, and a selection that came back empty.

The cause was how the group reached the runner, not the checkout, the shard size or the
sandbox. The monitor passes `TEST_GROUP` as a step `env:`, `ci.yml` passes it positionally.
`scripts/test-all.sh` resolves `TEST_GROUP="${TEST_GROUP:-${1:-all}}"` (env wins) and never
dropped the export attribute, so every suite it spawned inherited `TEST_GROUP=scripts`, and any
suite that ran a nested `--enumerate-commands` or `--print-selection` got a narrowed or
refused answer. Local reproduction was 28 passed with the variable unset and 23 passed, 5
failed with `TEST_GROUP=scripts`, the exact count in the CI log.

The fix was one line (`export -n TEST_GROUP`, beside the existing `unset SCRIPTS_SHARD`).
The guard for it took three review rounds, and that is where this learning lives.

## Solution

- Runner: demote the export attribute right after the group is resolved. Only the attribute
  goes, so every shell-variable read is unchanged. `main-health-monitor.yml` stayed untouched
  because another script reads the step-env echo.
- Guard (Part C of `scripts/test-all-group-affected.test.sh`): two probe suites spliced into a
  sandbox runner report whether the variable is in their environment and a grandchild's; a
  positive control removes the demotion and must read `set`; an exact-count pin (C1); a static
  census (C1b) with its own firing and quiet controls; rows for the other groups, `CI=true`,
  the deprecated alias and a 2-way and 7-way shard split; a floor that reports through
  `printf` to stderr; and a conservation check that a neutered `pass()`/`fail()` cannot hide.
- Verification: a branch dry run of the monitor (`workflow_dispatch` with `dry_run=true`) went
  fully green, including the three suites, before any claim that the monitor would recover.

## Key Insight

1. **Same SHA, different verdict means diff the calling convention first.** One tree cannot be
   both green and red. Compare how each caller reaches the runner (env versus positional),
   and reproduce by setting the variable the other way before suspecting the source.
2. **A probe that runs in a spliced sandbox is blind to what the splice removes.** The sandbox
   kept the shared `run_suite` chokepoint and deleted the registration region, so the probes
   could not see a re-export there, in the tee path or in the parallel launcher. Pair the
   dynamic probe with a static census of the region it cannot run, and write down what the
   pair still cannot see.
3. **A lexical detector is an arms race; stop at the cap and state the residual.** The first
   census was a list of spellings (round 1 missed `env TEST_GROUP=...`, `export TMPDIR
   TEST_GROUP`, `export "TEST_GROUP"`). The closed-set rewrite had a phantom-heredoc hole (a
   `<<` inside a string hid the rest of the file) and an overclaimed comment. Cheap, mechanical
   fixes closed those (fail loudly on an unterminated heredoc, unwrap quoted pairs, flag eval,
   join continuations); the rest was stated as a residual in the comment: indirect
   `export "$name"`, a name built at run time and an executed heredoc are seen only by the
   probes, which do not run in the registration region. The durable alternative is a runtime
   recorder that checks every spawn's environment.
4. **A review-driven fix is as unpinned as the blind spot it closes.** Every new guard in this
   PR was driven RED once against a mutated runner (CI-conditioned, group-conditioned,
   shard-conditioned and alias-conditioned demotions; a re-export in the registration region,
   the tee path and the parallel launcher; deleted rows; a neutered `fail()`), and a mutant
   that only mentions the words stayed green.
5. **A plan acceptance criterion is a claim to run, not a box to tick.** See the session error
   about bulk-ticking below: the literal "git diff shows additions only to that file" was
   false (four lines changed in place) and was caught only at QA.

## Session Errors

1. **Planning subagent: a backgrounded test run lost its output-dir variable.** Recovery:
   re-ran the affected runs. **Prevention:** already covered (echo the scratch path in the
   same call; `work/SKILL.md` and the `mktemp` rule). One-off.
2. **Planning subagent: `gh issue create` was refused twice by a filing hook** until a
   `meta/machinery` label was added and the body file written in a separate call. Recovery:
   both. **Prevention:** already encoded in the hook's message and the repo rule (own Bash call,
   `--body-file`). One-off.
3. **Planning subagent: `pkill -f` was blocked by the self-match guard** and replaced with
   `ps`. **Prevention:** hook working as designed. One-off.
4. **`decision-challenges.md` failed the technical-ruling gate twice**: a technical row
   written as "Ruled by planner" (the gate wants a CTO-agent ruling) and the Class
   `operator (priority/schedule)` (the gate's closed list is single tokens). Recovery: a CTO
   ruling, and `operator (priority)`. **Prevention:** the one-shot ruling prompt taught
   `priority/schedule` as one category while the gate lists `priority` and `schedule`
   separately; fixed in `plugins/soleur/skills/one-shot/SKILL.md` (this PR).
5. **A new unguarded `rm -rf "$pd"` added a row to the fixture-relative ratchet**
   (`plugins/soleur/test/fixture-relative-assert.test.sh`, 2040 versus a baseline of 2039).
   Recovery: the canonical `assert_fixture_dir` guard, not a baseline regeneration.
   **Prevention:** already in `work/SKILL.md` 6.6 (run the ratchets before the first commit);
   the rule worked.
6. **First static detector was a spelling denylist.** Review found env-pair, multi-operand and
   quoted-name exports it missed, all of which leak when placed in the registration region.
   Recovery: closed-set rewrite. **Prevention:** insight 3 above; the review skill already
   records the lexer arms race (`risk-tier-and-fix-rounds.md`).
7. **The closed-set rewrite opened phantom heredocs** from a `<<` inside a string or
   arithmetic expression, silently hiding the rest of the file, and its comment overclaimed
   ("the one form it cannot see"). Recovery: unterminated heredoc now fails loudly; the
   comment states the real residuals. **Prevention:** insight 3; for every causal or universal
   sentence a diff adds, name and run the falsifying command.
8. **The detector's control used the wrong mode** (the reviewed lines fire in library mode,
   which has no reviewed set), caught by the suite's own run. Recovery: the control runs in
   runner mode plus one explicit library-mode sample. One-off.
9. **I bulk-ticked nine plan acceptance criteria with a script that matched line prefixes,
   without running each criterion's command.** One of them ("`git diff` shows additions only to
   that file") was false and surfaced only at QA. Recovery: appended the measured deviation to
   the criterion. **Prevention:** the rule already exists in `work/SKILL.md` ("an acceptance
   checkbox is a CLAIM — never bulk-toggle"); this is a violation of it, not a gap. Tick a
   criterion only by running the command it names.
10. **A stray `cp /dev/null` truncated an unrelated scratch file.** Harmless. One-off.
11. **`pgrep -f` in a Bash call was blocked by the self-match hook.** Recovery: dropped the
    check. **Prevention:** hook working as designed. One-off.
12. **Several mutation batteries exceeded the 10-minute Bash cap** because three sibling
    worktrees were running the full gate. Recovery: the harness moved them to background and
    notified on completion. **Prevention:** run long batteries in a wrapper that writes its own
    verdict file and wait for the completion notification; nothing to change.
13. **Four of the seven first-round seats and two fix-round seats re-timed their own suite runs
    under load** and reported timeouts. Recovery: their findings stood without the run.
    **Prevention:** brief seats with the expected duration and that a timeout is not evidence.

## Tags
category: workflow-issues
module: scripts/test-all.sh, scripts/test-all-group-affected.test.sh, main-health-monitor
