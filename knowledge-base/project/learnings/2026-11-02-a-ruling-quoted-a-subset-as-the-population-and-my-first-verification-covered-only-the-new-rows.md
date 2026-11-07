# Learning: a ruling quoted a subset as the population, and my first verification covered only the new rows

## Problem

Ref #10865, #10861, #10448 (PR #11847). Re-ruling the observation-window wall ceilings (210/270 -> 240/285) and guarding the s4-drain floor produced four things that all read green and were not:

1. The CTO ruling, the ADR-276 amendment and the runbook log all cited "the whole post-PR5 population of 372 jobs". The history review seat re-pulled every non-cancelled `ci.yml` run since PR5 and read **1,015** jobs; the 372 were a subset (the CTO's listing stopped short). The ruling survived (both populations have max 284 s and p95 under 240 s), but the daily p95 range, the "since 10-31" figure and the billed-minutes mean (3.52-3.63 claimed, 3.37 measured) were wrong, and an append-only ADR cannot be edited later. A "recheck trigger is live" sentence also applied a whole-population trigger to a single day's slice.
2. My first verification run used `--rows 109-117` (only the new mutant sites). The same commit had made `drain-timestamp-regex-broad`'s old string match twice (the new sentinel regex line contains it) and had added a `--argjson n` operand the argv allowlist did not know. Both surfaced only in a later full `--rows 1-124` run.
3. `row_ow_edge_pass` asserted `! grep -q 'wall p95'` to mean "no ceiling note", but the PASS line itself reads `wall p95 ...s max ...s`.
4. Review surfaced guards pinning a literal line rather than the property: the sentinel did not check the response was PR 11226, the permission pin was a loose awk, and no fixture sat at the 240/285 boundary.

## Solution

- Re-derived the series from both datasets (the CTO's `jobs.tsv`, the seat's `walls.txt`), confirmed the 372 are a subset of the 1,015, and rewrote the ADR amendment and runbook log with the full-population figures, dropping the misapplied trigger sentence.
- Ran the full mutant range plus the unconditional share after every change that adds lines to the probe, and fixed the three breakages (unique old string, allowlist, PASS-line grep).
- Hardened the guards: the sentinel requires `.number == 11226`, the permission pin parses the YAML, and boundary rows pass at exactly 240/285 and fail at 241/286, each with a mutant that is killed for the right reason.

## Key Insight

A ruling is a claim about a measured set, and the set is part of the claim. When a figure travels from the author who measured it into an append-only record, re-derive it against an independent count of the population before it lands, and state the query. Likewise, a verification range chosen from "what I just added" cannot see what the addition broke elsewhere: after any edit that adds lines to a file that existing mutants anchor on, run every anchor's uniqueness check and the full range, not the new rows.

## Session Errors

1. **Subset quoted as the population in an ADR and runbook** - Recovery: history seat re-pulled 1,015 jobs; re-derived from both datasets and rewrote the text. **Prevention:** when quoting a series into a decision record, compare the count against an independent enumeration (`gh api --paginate ... | wc -l`) and print the query; never carry a figure from a ruling comment into an append-only file unverified.
2. **Partial verification range (109-117) missed two breakages my own commit caused** - Recovery: full-range run found them; fixed the old string and the allowlist. **Prevention:** after adding a line that an existing `ow_mutate` old string could also match, `grep -c` every `^ow_mutate` old string against the probe, then run the full OW range, not only the new sites.
3. **A row asserted absence of a phrase the PASS line contains** - Recovery: assert `^PASS: the window held` and the absence of `is over 240 s`/`is over 285 s`. **Prevention:** before asserting `! grep -q '<phrase>'` on probe output, grep the probe's PASS and status lines for the same phrase.
4. **Review-trailer script rejected `--agents-ran 9 --agents-expected 8`** - Recovery: counted the seats and passed matching numbers. **Prevention:** count the seats from the spawn list, not from memory; the script derives mode from the two counts.
5. **The CTO ruling comment posted to #10865 carries the subset figures** - Recovery: not yet done; a correction comment needs the operator's fresh go (standing hold on posting to #10865). **Prevention:** post rulings only after the figures they cite are verified against an independent count.

## Tags
category: workflow-issues
module: ci-pr-affected observation-window probe
