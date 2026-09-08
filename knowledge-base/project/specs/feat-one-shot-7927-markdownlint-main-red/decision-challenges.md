# Decision challenges — feat-one-shot-7927-markdownlint-main-red

Surfaced during planning for #7927. Recorded rather than resolved interactively, because
planning ran headless inside the one-shot pipeline. `/ship` renders these into the pull request
body and files an `action-required` issue.

## 1. Scope of the markdownlint exclusion (taste, two advisories disagreed)

**The question.** Should `knowledge-base/project/{learnings,brainstorms}` — 2,676 files — be
fixed and gated, or excluded along with `plans/` and `specs/`?

**The engineering advisory said include them.** The linter that disqualifies a plans-and-specs
sweep (`lint-infra-no-human-steps.py`, 208 failing files) does not glob `learnings/` or
`brainstorms/`, and all 2,233 tracked learnings pass `lint-fixture-content` today, so the sweep
is landable. Its argument: an excluded directory with a follow-up issue has no forcing function
and will rot.

**The simplicity advisory said exclude them.** None of the plan's four stated properties
distinguishes them from plans and specs — property 1 is satisfied by exclusion as well as by
fixing, and property 4 speaks only about files the gate covers. Including them costs 2,676
swept files and 343 hand-fixed errors, and because `weakness-digest.md` lives under
`knowledge-base/project/` it also drags in a change to the bot-PR composite action to earn a
synthetic check-run green that is otherwise sound by unreachability.

**Decided: exclude.** The simplicity argument holds against the property list, and the
unreachability consequence is a real second-order simplification, not a preference. The
engineering concern about rot is real and is carried as a tracked deferral with its measured
figures, so the next decision is informed rather than re-argued from scratch.

**What would change the answer.** A rendering defect actually observed in a learning, or the
plans-and-specs deferral being taken up (at which point the whole corpus moves together).

## 2. Whether the scope decision warrants an ADR (taste)

**The engineering advisory said yes** — exempting 86% of the Markdown corpus from a required
gate is a decision that will be re-litigated from an incomplete record.

**The simplicity advisory said no**, using the plan's own reasoning for cutting a different
ADR: the question is asked while reading `.markdownlintignore`, an ADR sits one indirection
further from it, and nothing forces the ADR to track the ignore file.

**Decided: no ADR.** The acceptance criteria require the ignore file to carry the blocking
linter and the measured counts inline, and the bot-PR unreachability derivation is recorded in
`scripts/required-checks.txt` and the ruleset Terraform comment, which is where their consumers
read them and is the shape `rule-body-lint` already uses.

**What would change the answer.** A second exemption being added later for a different reason —
at that point the exemptions have a policy, and a policy is ADR-shaped.

## 3. MD001 kept, against the plan's bundled removal (implementation, measured)

**The plan disabled MD025 and MD001 together**, on the stated ground that doing so "removes 116
of 438 residual errors" — a volume argument for the pair, plus a coherence argument that applies
only to MD025 (its sibling MD041 is already off, so the corpus never promises a document opens
with one H1).

**Re-measured at the gate: the pair is 15 errors, not 116** — MD025 is 10 across 9 files, MD001
is 5. Whatever scope produced 116, it is not the one the gate sweeps. That is a 7.7x
overstatement of the only argument MD001 had, so the bundle does not survive its own premise.

**Decided: disable MD025, keep MD001 and fix its five sites by hand.** MD025's coherence
argument stands without the volume. MD001 has no equivalent — a heading that jumps h2 to h4 is a
document-structure defect, not a house-style preference — and five edits is a cheap fix, not a
reason to switch a rule off repo-wide. Turning off a rule is permanent and silent; fixing five
sites is neither.

**What would change the answer.** MD001 firing on a legitimate pattern this corpus depends on —
none of the five is such a case; all five are genuine level skips.

## 4. M5 asserts equivalence, not failure (implementation)

**The Guard Contract expected M5 to FAIL** on a working-directory assertion, so that the gate
could not silently lose `.markdownlintignore` and report on the whole tree.

**The implemented script cannot reach that failure.** It resolves its own root from
`BASH_SOURCE` and changes into it, so the scope file is found no matter where the script is
invoked from. The hazard the assertion was written to catch is absent by construction.

**Decided: M5 asserts that a subdirectory invocation is byte-identical to a root one.** Writing
the row as the contract specifies would have required *adding* a failure mode in order to test
for it, pinning the weaker design. The property the contract wanted — scope cannot be lost to
the caller's CWD — is what the row now proves, and it proves it positively.

**What would change the answer.** The script gaining any CWD-relative path, at which point the
failing assertion becomes reachable and should be restored.
