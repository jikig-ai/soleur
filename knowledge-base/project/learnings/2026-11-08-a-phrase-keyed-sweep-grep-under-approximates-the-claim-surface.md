# Learning: a stale-claim sweep verified by phrase grep retires only the phrasings it enumerates — the same claim in a variant shape survives on the highest-salience surface

## Problem

A prose sweep (#11711 doc amendments, PR #12391) replaced every occurrence the plan's inventory listed of "an agent never dispatches rotate" and its siblings ("no agent runs it", "only the owner dispatches"). The plan called the inventory complete, the AC1 verification grep was built from the same phrase set, the work phase reported AC1 clean — and `scripts/key-rotate.sh`'s `kk_stop_tail` still printed `(no agent dispatches a rotate)` into every post-write-failure stop sentence, the step summary, and the notify-filed `action-required` issue body. Four separate enumerations (plan inventory, AC1 grep pattern, tasks list, decision-challenges scope ruling) shared the same blind spot because each was derived from the previous one's phrasing. The claim was the SAME; the surface was the one the sweep existed to clean (an agent triaging the failure issue reads "no agent dispatches" while the ADR says "an agent may dispatch under the go").

The seat that caught it did not grep for phrases — it read the file for meaning and found a fifth phrasing (`no agent dispatches a rotate`) plus two normative references that carried the claim in conditional form (`technical-ruling-delegation.md:188` "a credential rotation stays the owner's own dispatch"; `standing-delegation.md:446` "without a typed go").

## Solution

Applied in the fix round: the AC1 grep was widened to the variant set (`no agent dispatch`, `agent dispatches`, `only you dispatch`, `required-reviewer approval` near `infra-privileged`) plus a case-insensitive superseded check; every residual hit was then CLASSIFIED (supersession quote, test unwant-needle, unrelated subject) rather than counted to zero.

The durable rule for claim-sweeps: **the verification predicate must be derived from the claim's semantic content, not from the phrasings the inventory already found.** Concretely: (1) after the phrase grep, run a repo-wide grep for every *word-piece* of the claim in any order near the protected subject (`agent` + `dispatch`/`runs`/`never`/`only` within a line of `rotate`/`key-rotate`/`converge`), and classify every hit; (2) sweep the files the amended documents LINK for the same claim — the delegation reference docs carried the superseded rule as their own normative sentence, and the runbook links them; (3) a "clean" report must name the residual-hit classes it accepted, not just the count.

## Key Insight

An inventory and the grep that verifies it are not independent evidence when the grep is generated from the inventory — they are the same measurement taken twice. A sweep of a CLAIM (a rule, a policy, an authorization boundary) needs at least one pass that searches by meaning: near-word grep, or a reader that knows nothing of the inventory's phrasing. And emitted-surface prose (stop sentences that land in issues) is a higher-salience miss than a comment: check the strings a recovery session READS FIRST.

## Session Errors

1. **Post-census rescan scripts failed silently twice** — a `while read` loop's inner `gh` calls consumed the outer stdin (only the first issue scanned), and a jq type error (`number + " "`) was swallowed by `2>/dev/null`, each reporting DONE with zero hits while known-raw comments persisted. **Prevention:** detach inner-call stdin (`< /dev/null`), never `2>/dev/null` a command whose output IS the measurement, and always verify a scanner against at least one KNOWN-positive input before trusting its zero.
2. **A mid-review suite run was baselined on mid-edit state** — the key-rotate suite started before the qualifier-alignment edits settled; its result was void per the baseline-mutation rule and the run was killed + restarted clean. **Prevention:** when seats run report-only on a pushed SHA, apply all lead fixes BEFORE starting verification suites, or re-run after the last write.
