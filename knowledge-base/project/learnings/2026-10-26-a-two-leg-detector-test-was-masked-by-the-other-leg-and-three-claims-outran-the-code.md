# Learning: a two-leg detector's test row was masked by the other leg, and three claims outran the code

## Problem

PR #11164 (#10924 P4b) added a config-declared "content trigger" to the plugin-generic affected-test gate: when a diff adds a configured string under configured globs, a passing run also runs a declared command. The scan has two legs, tracked (`git diff`) and untracked (`git ls-files --others` plus `grep`). After two review rounds, a 7-seat fix-round panel and 19 more mutants, the contract suite was green at 453/0 and the repo ratchets were green. Two things were still wrong:

- A mutant dropping `--` from the untracked-leg `grep` (so a pattern starting with `-` parses as options) survived. The row that exists to pin it (X1) ran the untracked case in the SAME repo where the tracked case had already committed a match, so the tracked leg answered `ran` and the untracked leg never decided anything.
- A single fresh-eyes verifier found three claims that outran the code: the contract doc said the command runs under the shared wall-clock budget, but the inert exit precedes the budget arming (so it was unbounded there); the doc said a `.` segment glob is refused, but a bare `.` and a trailing `/.` were accepted; a comment said `grep -a` gave NUL parity with the tracked `--text` leg, but under `-q` GNU grep exits 0 on a binary match either way.

## Solution

- Give each leg of a multi-leg detector its own fixture repo with nothing committed that the other leg could satisfy. Re-run the surviving mutant; it must go red (it did: `scan-error`, not `ran`).
- Fix each claim at its source and pin it with a row that a one-line revert reddens: arm the budget on the inert exit (row I2, killed by removing the arming), refuse `.` and `*/.` (rows ct13-dot and ct13-trailingdot), reword the `-a` comment and the W7 label to say what it proves. A mutant that is equivalent on this host (dropping `tr -d '\000'` on GNU awk 5.4) is labelled equivalent with its reason, not left as an unexplained survivor.
- Cover probe-list shrinkage with one row per probe shape (`.h*`, `x/*.z`, `Q*`) and the adapter-arm `--explain --full` exit, which only the delegated arm had been driving.

## Key Insight

A test for leg B of an "A or B" detector proves nothing if leg A can already answer from state the fixture created earlier. Ask of every multi-leg detector row: with this leg's code deleted, what else in the fixture still produces the same verdict? The same applies to docs: a sentence that states a bound (a budget, a refusal list) is a claim about the code, and the verifier's job is to run the bound, not read the sentence.

## Session Errors

- **Mutants that did not land / vacuous mutants / a fixture that did not reproduce the race.** Recovery: corrected anchors, many short lines instead of one long line. **Prevention:** assert each mutation landed (`count == 1`, `diff -q` against a pristine backup) and treat baseline-identical as un-run; already in the review Sharp Edges.
- **`CT_BRANCH` env prefix leaked into later rows; `E1:` label collision; `printf '%b'` ate a backslash.** Recovery: moved the prefix inside the substitution, renamed to `CTE1`, wrote the file with `printf '%s'`. **Prevention:** put per-row env prefixes inside the `$(...)` that needs them and grep the suite for duplicate row labels before adding one.
- **Q3 survived because X1's untracked row was masked by a committed tracked match.** Recovery: separate repo `R_X1U`. **Prevention:** one fixture repo per detector leg; run the mutant that removes each leg's distinguishing code.
- **Three claims outran the code (budget on inert exit, dot-segment refusal, `-a` parity).** Recovery: code and row fixes, comment reworded. **Prevention:** run the verifier pass against the DOC's claims, and for each bound a doc states, drive the exit site that is supposed to enforce it.
- **Dedup ledger not persisted before the fix round.** Recovery: reconstructed a rolled-up ledger into `session-state.md`. **Prevention:** write the ledger at synthesis, as `risk-tier-and-fix-rounds.md` already requires.
- **Shell cwd reset after a command.** Recovery: absolute paths. **Prevention:** none beyond the existing absolute-path rule.
- **Plan phase: two filing-gate refusals, a slow cold `--print-selection`, three lint first-draft failures.** One-off; fixed in place.

## Tags
category: test-failures
module: plugins/soleur/scripts/affected-tests
