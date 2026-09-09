---
title: "ADR-214 — A test seam for a destination pin must never be env-declared"
status: accepted
date: 2026-09-09
tags: [security, credential-forwarding, destination-pin, test-seam, curl, betterstack, plugins]
related_adrs: [ADR-202]
related_issues: [7898, 7873]
---

# ADR-214: A test seam for a destination pin must never be env-declared

## Status

- **Status:** Accepted. Nothing here is soak-gated — the decision constrains how future code is
  written, and both sites that were about to violate it are corrected in the same PR.
- **Date:** 2026-09-09
- **Issue:** [#7898](https://github.com/jikig-ai/soleur/issues/7898) §6
- **Ordinal note:** re-derived across every pushed ref, not `origin/main` alone. `origin/main` and
  the local directory both top out at ADR-212, but ADR-213 already exists on a sibling branch, so
  `origin/main` alone would have collided. Population:
  `for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree -r --name-only "$r" -- knowledge-base/engineering/architecture/decisions; done`

## Context

`scripts/betterstack-query.sh` interpolates `BETTERSTACK_QUERY_HOST` into
`https://${HOST}?…` and attaches `-u "${USERNAME}:${PASSWORD}"`, so curl sends the ClickHouse read
credential preemptively as Basic auth on the first request, with no challenge. Before this PR the
only validation was a shape `case` that refused the userinfo/path/scheme family
(`real.host@evil.example`, `evil.example/x?`) and **accepted any bare host** —
`BETTERSTACK_QUERY_HOST=attacker.example` was taken and the credential went to it. `--disable` and
`--noproxy '*'` were intact and irrelevant, which is the same sentence `zot-inventory.sh`'s prologue
writes about `SSLKEYLOGFILE`.

Closing that needs an allowlist. The obstacle to an allowlist is that roughly a dozen suites drive
the script through a stub host (measured values include `stub`, `h`, `x`, `dummy-host`,
`synthetic.example.invalid`, `127.0.0.1`, and empty), and a pin that refuses those breaks them all.

The locally obvious repair is an opt-in environment variable — `BETTERSTACK_QUERY_HOST_TEST_PIN=0`,
or any `_ALLOW_` / `_TEST_PIN` spelling — that tests set and production does not. The script's own
comment block **forecast exactly that seam**, so the next person to open the file would have found
the design pre-endorsed by the artifact.

That is the decision this ADR makes, and it makes it the other way.

## Decision

> **A test seam for a destination pin must never be env-declared.** On this surface the environment
> is the adversary: anyone who can substitute the destination variable can set the declaration to
> match in the same breath, so an env-declared seam is a bypass available to precisely the actor
> the pin defends against. A test that needs a non-vendor destination shims `curl` — which
> exercises the guard — rather than declaring its way past it.

An env-declared seam does not weaken the pin a little. It removes it, for the only threat model
under which the pin was worth building: the guard's precondition is that the attacker controls the
process environment, and the seam is read from the process environment.

The shim is also the *better test*. A suite that sets `…_TEST_PIN=0` asserts the behaviour of a
script running with its guard disabled — the configuration production never uses. A suite that
shadows `curl` as a shell function runs the guard for real and observes what the guard decided,
which is why Guard 2's mutation matrix can require "refused, **and** the `curl` shim recorded zero
invocations". A declared seam cannot express that row at all.

### Where this is written down

The corollary is recorded in three places, chosen because they are where the next person reaching
for a seam is actually standing — not for redundancy:

1. This ADR.
2. `check_rule_d`'s docstring in `scripts/lint-shell-trace-credential-refusal.py`, beside the
   message that tells an author to add a destination pin — which is where an author reaching for
   a seam is standing when they are told to add one.

   *(This crossed a contradiction inside #7898's own plan: Phase 5.1 prescribes the docstring,
   while AC5's trailing clause reads "`git diff` must show that string and nothing else." The
   plan's `## Files to Edit` states the intent AC5 was meant to encode — "no predicate, regex or
   baseline-loading logic is touched" — and a docstring is not logic and cannot narrow a
   classifier, which is the property AC5 exists to protect. Resolved in favour of the stated
   intent: the docstring landed and AC5 was reworded to match. Filing a follow-up issue for a
   one-line comment would have tripped the cost-of-filing gate for no gain.)*
3. The comment block above the host check in `scripts/betterstack-query.sh`, which this PR rewrites
   anyway and which previously forecast the rejected design.

## Scope — what this ADR does NOT decide

**It does not restate the four confinement flags.** An earlier draft proposed a four-part doctrine
(xtrace refusal, `--disable` first, `--noproxy '*'`, destination pinning). All four are already
encoded *executably* in `scripts/lint-shell-trace-credential-refusal.py`, with two baselines, a
RED/must-PASS fixture corpus and a CI gate. An ADR narrating what a linter enforces is a second copy
that can drift, and when it drifts the reader has two sources disagreeing with no tiebreak. The
executable artifact is the stronger one. Only the seam corollary — which has no executable home —
belongs in the corpus.

## Consequences

**The pin narrows the adversary set; it does not close it.** `*.betterstackdata.com` accepts *every
Better Stack tenant*: the vendor mints per-team ClickHouse connection hosts under that apex, so
anyone who can sign up holds a hostname the allowlist takes, and `curl -u` sends Basic auth
preemptively with no challenge. The adversary set goes from *anyone* to *any Better Stack customer*.
Both known live values end `-connect.betterstackdata.com`, so a tighter
`*-connect.betterstackdata.com` — or a two-value equality — remains available if the tighter pin is
later wanted. Recorded so the residual is a decision rather than an accident.

**The system-level property is still false, and this ADR must not be read as claiming otherwise.**
Two production followthroughs resolve the query *script itself* through an env-settable path:
`scripts/followthroughs/git-data-rung2-evidence-capture.sh` and
`betterstack-roundtrip-latency-7855.sh` both carry
`QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"`. `BETTERSTACK_QUERY_SH`
is a **strict superset** of the seam this decision closes — an actor who can set
`BETTERSTACK_QUERY_HOST` can equally set `BETTERSTACK_QUERY_SH` and receive the injected credentials
in a script of their choosing, with the host pin fully intact. That is verbatim the objection used
to reject the env-declared pin seam, applied to a seam that already ships.

This is named rather than papered over. After this change the **script-level** property holds and
the **system-level** one does not. The corollary above is written to acknowledge those shipped
exceptions rather than to be contradicted by two files on the day it lands; closing
`BETTERSTACK_QUERY_SH` is out of scope for #7898 and is recorded in that PR's Non-Goals.

**Two classifier gaps stay open**, both filed rather than fixed here, because #7898's AC5 forbids
touching the classifier's predicates in that PR:

- `ACQUIRES` does not know `read -rs`, so Rule C offers a *conditional* xtrace arm to
  `provision-doppler.sh`, whose Doppler personal token is bound by `read -rs` **after** the prologue
  runs — a guard that is vacuous by construction. It cannot see `set -a; source .env; set +a`
  either, which is the same defect in three `community/*-setup.sh` files.
- Rule D matches the literal token `curl`, so a call through `"$CURL_BIN"` (or any variable
  indirection) is unclassified. No current offender uses that seam.

Both are recorded in #7898 with upgrade triggers.
