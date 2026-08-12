# Plan — make the local suite runner decline irrelevant batteries

Synthesized fixture. Nothing here is copied from a real plan. It carries outage
vocabulary (`post-mortem`) alongside ONLY `produc*` substrings, and deliberately
carries no other member of that regex's alternation — no bare `prod`, no
`production`, no `deployed`, no `live`, no `customer`, no host name. Every such
token below is written inside backticks, which the gate strips before matching;
an unbackticked one would stop this fixture testing the substring class and make
it pass for the wrong reason. Four separate leaks were caught while writing it.

The six items come from the 2026-01-02 test-pipeline post-mortem, which measured a
local gate run on one workstation. Nothing about it reached a released surface.

## Why the guards here are suspect

A guard written by the same author, in the same session, against the same mental
model that produced the plan inherits that model's blind spot. This plan is the
evidence: the review panel found three defects and all three are instances of it.

Two of the suites form a producer/consumer pair — one builds the directory the
other reads — so a memo keyed on the tracked tree would let the consumer certify a
stale artifact the producer never rebuilt. The same shape reproduced twice more
before it was named.

## Scope

The product surface is untouched. This changes one shell script, one data file and
three suites. The AGENTS rule this adds constrains where a future rule belongs.
