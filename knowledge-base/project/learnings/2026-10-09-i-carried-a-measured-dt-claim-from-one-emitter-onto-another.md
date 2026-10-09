# Learning: a measured `dt` claim is per-emitter — I carried "dt is ingest time" onto an emitter that sets its own

## Problem
PR #9784 (retire the Inngest plaintext AOF backstop) added a destroy gate whose Hetzner corroboration
checks that the wiped evidence row's time lies between a non-live attach and the later detach. Round 2
wrote that the row time is "Better Stack's top-level `dt` (ingest time), which the sender cannot
influence" into the gate lib, ADR-142, the record, three runbooks and the PR body. The sentence came from
the review brief and from `betterstack-log-query.md`, which measured it (#8759) for the **Vector-shipped**
inngest source. The wipe host is a different emitter: it HTTP-POSTs a JSON body that itself carries a
top-level `"dt"`. Whether Better Stack keeps that value or stamps receive time was never measured.
The fresh-eyes verification seat found it; nothing in the 13-seat panel or two fix rounds did.

## Solution
State the row time as the top-level `dt` column with its source UNMEASURED for this emitter; call the
window a plausibility bound on a self-attested time and Hetzner's action history the independent
evidence; add it to the UNMEASURED-until-first-run lists (cloud-init comment, runbook); append a
dated clarification to ADR-142 and the destruction record rather than editing the dated text.
A cheaper design would select `ingest_time` explicitly (`SELECT dt, ingest_time, raw`); not done here
because the query wrapper is shared.

## Key Insight
A measurement is a fact about one source. When a new emitter joins a set (here: an HTTP-POST host next to
a Vector-shipped source) the sentence survives the move and the evidence does not. Before copying a
"column X means Y" claim, name the emitter it was measured on and check the new emitter's payload for a
field that overrides X.

## Session Errors
1. **Inherited the "ingest time" framing from the brief and a sibling runbook.** Recovery: verification
   seat; prose corrected at 6 sites + append-only clarifications. **Prevention:** grep the emitter's own
   payload for the column before asserting what the column measures (added to
   `betterstack-log-query.md`).
2. **A delegated fix agent (W2) twice ended its turn on a tool call with no report, once leaving the gate
   suite 26 rows red.** Recovery: SendMessage to the agent, then a second brief with the green-suite
   requirement. **Prevention:** a fix-agent brief states "do not stop with the suite red; the final
   message is the report", and the lead measures the suite itself before trusting a completion notice.
3. **R2's `&&` probe command was refused by preflight Check 10** (shell-active reject). Recovery: single
   `grep -cPz` with `expected_output` 1. **Prevention:** probe commands are single verbs, no operators.
4. **`producer | grep -q` SIGPIPE fail-open in the wipe census, fixture-relative-assert sites, the
   guard-vacuity ledger, probe-row census, and `generated-at` manifest conflicts** — each caught by an
   existing gate or suite on the first run. **Prevention:** none new; existing rules cover them.
5. **Load-induced timeouts of the notice suite and a blocked `rm -rf` in a compound shell.** One-offs;
   CI adjudicated the former.
6. **Stop-hook "unkept promise" blocks (three).** Closing text used first-person future tense while
   waiting on background agents. **Prevention:** end a wait with only the `<stop>BLOCKED: …</stop>` tag.

## Tags
category: logic-errors
module: infra/inngest-backstop-retire
