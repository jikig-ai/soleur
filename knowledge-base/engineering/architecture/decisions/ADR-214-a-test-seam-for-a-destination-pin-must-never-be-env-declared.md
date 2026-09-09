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

Closing that needs an allowlist. The apparent obstacle was that roughly a dozen suites set
`BETTERSTACK_QUERY_HOST` to a stub value (measured: `stub`, `h`, `x`, `dummy-host`,
`synthetic.example.invalid`, `127.0.0.1`, empty), and a pin refusing those looked like it would
break them all.

**That premise was largely false, and it is corrected here rather than left standing.** Measured at
review: **nine of the eleven never reach the real script.** They set the variable and then route
around it entirely — each through its own script-substitution seam (`INNGEST_ZOT_BOOT_QUERY_BIN`,
`FLIP_ROLLOUT_QUERY_BIN`, `CI_DEPLOY_SENTRY_BQ`, `ZOT_LOG_7440_QUERY_BIN`) or a sandbox stub. Their
stub host only satisfies the *caller's* own presence guard. All eleven were executed on the pinned
branch at rc=0. The decision below is unchanged — it is about what a seam may be, not about how many
suites needed one — but a reader must not infer that nine suites were left broken.

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
the **system-level** one does not.

**And the seam is far wider than two files.** An earlier draft of this ADR named
`BETTERSTACK_QUERY_SH` alone and called it "a strict superset". Measured at review:
**12 distinct env-declared script-substitution variables across 17 files, all production** —
`BETTERSTACK_QUERY_SH`, `BETTERSTACK_QUERY_SCRIPT`, `ZOT_BQ_OVERRIDE`, `CI_DEPLOY_SENTRY_BQ`,
`FLIP_ROLLOUT_QUERY_BIN`, `HOSTNAME_MISLABEL_BQ`, `INNGEST_6407_BQ_OVERRIDE`,
`INNGEST_SERVING_QUERY_BIN`, `INNGEST_ZOT_BOOT_QUERY_BIN`, `REGISTRY_PREFLIGHT_QUERY_CMD`,
`ZOT_DISK_SAMPLE_QUERY_CMD`, `ZOT_LOG_7440_QUERY_BIN` (a wider pattern finds 14). This is not a
residual with two exceptions. **It is the repo's established convention** for testing anything
downstream of `betterstack-query.sh`.

**So the corollary must say why a script seam is permitted where a host seam is not**, or it reads
as an arbitrary exception to a practice with a dozen precedents and will not survive contact with
the next author:

> A **script** seam substitutes the code under test. Any reviewer reading
> `QUERY="${BETTERSTACK_QUERY_SH:-…/betterstack-query.sh}"` sees immediately that the real thing is
> not running, and the shipped artifact is unweakened — the guard is still in the file, still
> executes on every production path, and nothing about the substitution is silent.
>
> A **host** seam leaves the real code running and redirects only where its live credential goes.
> The guard is present, the run looks normal, and the only thing that changed is the destination of
> the secret. That is the difference: the first is visibly not-the-real-thing; the second is
> invisibly not-the-real-guarantee.

That distinction is the whole content of the decision, and it is why the twelve shipped script
seams are not counter-examples to it. They remain a real system-level residual — an actor who can
set `BETTERSTACK_QUERY_HOST` can equally set one of the twelve and receive the inherited
credentials in a script of their choosing, with the host pin fully intact — and closing them is out
of scope for #7898, recorded in that PR's Non-Goals.

**Four classifier gaps stay open** (an earlier draft said two), all filed rather than fixed here,
because #7898's AC5 forbids touching the classifier's predicates in that PR:

- `ACQUIRES` does not know `read -rs`, so Rule C offers a *conditional* xtrace arm to
  `provision-doppler.sh`, whose Doppler personal token is bound by `read -rs` **after** the prologue
  runs — a guard that is vacuous by construction. It cannot see `set -a; source .env; set +a`
  either, which is the same defect in three `community/*-setup.sh` files.
- Rule D matches the literal token `curl`, so a call through `"$CURL_BIN"` (or any variable
  indirection) is unclassified. No current offender uses that seam.
- `ACQUIRES` also requires a `_TOKEN|_KEY|_SECRET|_PASSWORD|_PAT` suffix, so a runtime-minted
  credential under any other name — `ACCESS_JWT=$(…)` in `bsky-community.sh` — is invisible to it.
- `CURL_AUTH_HEADER` matches `Authorization|X-API-Key|Private-Token` only, so a vendor-specific
  auth header (`X-Environment-Key`, Flagsmith) does not mark a call credentialed. Measured: that is
  why the one unconfined `curl` among the fifteen went unreported until review.

Both are recorded in #7898 with upgrade triggers.
