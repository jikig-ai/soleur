# Verification record

## RED before the prose fix (commit 9df7938e32)

17b and 17c were GREEN on both blocks against the unchanged fences, and the only failures were the 4
prose pins. That makes 17b/17c executable proof of the diagnosis: the delivered fence already resolves
the root with the variable unset or pointing at a decoy.

## Review round (9 agents, report-only at 86cf0ee85a)

Five seats converged on one gap: the notice gave an agent that read the file from disk no legitimate
root source and no fallback, and it diverged from the ADR-179 A20 notice. The test-design seat found 9
of 15 extra mutations surviving: nothing pinned which root each delivered row saw, which rows ran,
where the prose sits, or the regen arm under a spaced root. All fixed inline in 8f834562f6. The
plan's self-imposed 800-byte cap is exceeded (ship grew 1,324 bytes in total); the enforced 274,000
ceiling holds (`lint-skill-body-budget.py --base origin/main` OK).

Declined: a compaction hook re-supplying the root (re-invoking the Skill tool re-delivers it); the
A20 print-first `echo` check (a Monitor command runs in a fresh shell, so a check in the agent's own
shell says nothing about it).

## Mutation battery after the review fixes (pristine-copy restore, landing asserted per row)

Control: 451 pass, 0 fail (`MIN_VERDICTS=451`, the exact total).

| Row | Mutation | Result |
|---|---|---|
| M1/M2 | ship / mirror binding reads `$CLAUDE_PLUGIN_ROOT` | KILLED (17-subst, 17b, 17c; parity token for M2) |
| M3 | ship binding requires presence (`:?`) | KILLED (13b, 17c) |
| M4 | token unquoted in ship binding | KILLED (17-subst, 17b, 17c) |
| M5/M6 | ship drops "never guess" / merge-pr paragraph deleted | KILLED (17-prose) |
| A | environment overrides the literal after the binding | KILLED (17b only) |
| B+A | A plus 17b's decoy blanked | KILLED (17b env pin) |
| D | one delivered row dropped | KILLED (17-rows set, floor) |
| O, O2 | unset check reads the environment; plus 17c root blanked | KILLED (17c, 17d; 17c env pin) |
| K | prose check pointed at ship twice, plus M6 | KILLED (17-prose file set) |
| F | notice instruction inverted | KILLED (17-prose) |
| G, H | notice moved to end of file / into a fence comment | KILLED (17-prose region) |
| I | ship resolver call unquoted | KILLED (17d) |
| R | in-fence recovery loses "never a path built from the working directory" | KILLED (13b) |
| J | `--help` probe unquoted | KILLED (17b, 17c) |
| H1, H2, H3 | substitution replaces nothing / EVIL_ROOT emptied / space removed | KILLED |

Not mutated: the harness's own `pass`/`fail` dispatch (covered by the file's existing positive
controls) and the mock layer.

## Other checks (post-review tree)

- Fences: both differ from `origin/main` only in the unset reason, identically in the two blocks.
- `plugin-root-anchoring.test.ts` 47/47; `plugin-root-anchor-debt.sh` anchor-debt-files=0.
- `harness-parity` + `components` 1449/0; markdownlint clean; shellcheck clean.
- Ratchets run directly: fixture-relative-assert, fixture-dir-operand-assert, lint-shell-capture-exit
  (baseline), lint-trap-tempfile-ownership, guard-vacuity-floor — all rc 0.
- `test-all.sh --affected` was queued behind sibling worktrees' runs (ticket 26), so it was stopped.
  The substitute set above was chosen by shape; CI's full battery is the merge gate.

## QA: constrained dry run of the prose

A subagent with no delivered skill text followed both paragraphs from disk. It found no contradiction
but three gaps, all fixed before ship: the in-fence recovery did not forbid the checkout's own
`plugins/soleur` (which passes every fence check), did not say to stop the running Monitor before
re-arming, and "re-invoke the skill" read as re-running ship from Phase 0 (merge-pr lacked the option).
Scenario 13b now pins the recovery text in both blocks' runtime output.
