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
