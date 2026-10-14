# Learning: stubs that check argv SHAPE never pin the VALUE, and a declaration for a glob-registered suite degrades `--affected` to full

## Problem

#7243 (the #6416 class: a mirror step gated on the bridge outcome emitted nothing when the bridge soft-failed) was a ~50-line workflow fix plus a suite that extracts and runs the step's real `run:` body. The first green suite (33/33, nine mutation rows) still let a seat neutralise the checksum gate, drop `curl -f`, move the extract directory and change the pinned crane URL and hash, all at 33/33 green.

Why: every PATH stub answered by exit code and ignored argv. "`sha256sum` was called and failed" proves the degrade arm routes a failure; it says nothing about whether the line passes `-c -`, or which hash it verifies. The mutation battery could not see it either, because every row perturbed the workflow toward an obviously-broken spelling, and each was scored through the same argv-blind stubs.

The fix that worked: stubs that validate the contract and refuse (exit 64 plus a `REFUSE` log line the arms assert absent), with the pinned crane URL and hash read from a SECOND file (`reusable-release.yml`) so the stub cannot agree with whatever the workflow under test says; a stub that creates the archive and requires it to exist, so a download path decoupled from the checksummed path is refused; an EXIT trap with an asserted-absent archive per arm; and per-mutant expected-label attribution so a mutant must fail the check it is named for rather than any check.

A second, separate defect class from the same PR: adding `AFFECTED_*_PATHS` for a suite registered by the `SUITE_GLOBS` glob (no `run_suite` row, so no new label) is not a registration-only edit. `test-all.sh` classes it `INDEX-UNBOUND` and degrades the whole affected gate to the FULL battery (`AFFECTED_FALLBACK reason=runner-changed`), which a sibling full run then refuses (rc=4). The declaration is still needed: without it the census reports the suite UNCLASSIFIED and a workflow-only diff would not select it.

## Key Insight

A stub is part of the assertion. If it ignores argv it asserts "the command ran", and a battery scored through it can never reach the argv or the value. Make the fake REJECT what the real tool would reject, take the pinned value from an independent file, and give every verdict decision (`bad_count`, `bad_has`, `count_pfx`) its own self-test that it can say no.

## Session Errors

1. **Argv-blind stubs shipped in the first green suite (P1).** Recovery: validating stubs + REFUSE log + independent pin source. **Prevention:** when authoring a PATH-shimmed suite, make every stub `exit 64` on a contract violation and assert the refusal log empty; the work skill's "PATH-shimmed fake that dispatches on `$1` only" bullet already names this, apply it at authoring time rather than after review.
2. **Harness read the body file from the per-arm directory instead of the evaluation directory (first run: 11 of 21 checks failed).** Recovery: one global `BODY_FILE`. **Prevention:** run the canonical arm once and read one arm's stderr before trusting a red wall; one-off.
3. **`fixture-relative-assert` ratchet reddened after the rewrite (11 new sites: redirects into `$d` and `$VF`).** Recovery: canonical `assert_fixture_dir` statements in each writing window. **Prevention:** re-run the ratchets after ANY rewrite of a `*.test.sh`, not only after the first draft (work skill step 6.6 covers new files; it does not say "again after a rewrite").
4. **The suite's `retry()` returned a constant 1, so the degrade line's `rc=` was never measured.** Recovery: keep the last status. **Prevention:** copy a sibling's retry (`return "$rc"`) instead of re-deriving; the sibling workflows already had it.
5. **`PJ_TRIPLES` needed two bumps (261 to 262 to 263) plus a drains-floor ratchet and a row-order fix.** Cause: the census counts (suite, verb, producer file) triples, and naming a second file for an independent pin adds a triple. **Prevention:** after adding a second referenced workflow to a suite that stubs `sha256sum`, run `.claude/hooks/grep-q-pipe-guard.test.sh` before the commit.
6. **The local `--affected` gate degraded to a full battery and was refused (rc=4) under a sibling full run.** Recovery: ran the diff's consumer suites and the ratchets, left the full battery to CI (ADR-183). **Prevention:** a plan that adds a suite for a workflow-YAML subject should state up front that local `--affected` will degrade to full, and name the consumer-suite substitute.
7. **Stale background monitors and a process-count probe blocked by the `pgrep -f` self-match hook.** One-off; the hook did its job.
8. **An untracked `prefix-red.log` in the specs directory** carried a suite revision that no longer matched the committed suite. Recovery: regenerated the pre-fix RED from the committed suite against `origin/main`'s workflow (rc=1, 16 failures) and deleted the stale file. **Prevention:** never keep verification evidence as a file beside a guard that is still being edited.

## Tags

category: test-failures
module: ci-workflows
