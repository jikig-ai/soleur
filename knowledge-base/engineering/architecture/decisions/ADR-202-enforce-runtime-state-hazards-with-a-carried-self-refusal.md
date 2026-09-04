# ADR-202: Enforce a runtime-STATE hazard with a self-refusal the artifact carries, gated at commit time

- **Status:** Accepted
- **Date:** 2026-09-04
- **Issue:** [#7797](https://github.com/jikig-ai/soleur/issues/7797)
- **Ordinal note:** `origin/main` topped out at ADR-200, but ADR-201 was already
  claimed by a pushed branch. A `main`-only check would have collided; the probe
  quantified over all 71 `origin/*` refs.

## Context

Issue #7797 recorded two live API tokens printed into an agent transcript by
`bash -x`. Shell tracing echoes commands *after expansion*, so a secret leaks the
moment it is bound to a variable — before it reaches any command.

The repository has two families of enforcement available for a hazard like this,
and no recorded criterion for choosing between them: ~20 PreToolUse hooks that
intercept at the harness boundary, and ~54 commit-time lints that walk the
tracked tree. This decision is the criterion. It is written at that altitude
deliberately: the next author facing the same fork should find a rule, not a
note about one lint.

## Decision

> Where a hazard is a property of runtime **STATE**, enforce it with a
> self-refusal that the artifact carries, gated at commit time by a walker over
> every member of the population — not with a boundary interceptor that must
> enumerate the ways to reach that state. The interceptor is the **complement**,
> scoped to what is never committed.

Applied to #7797: every tracked shell script that binds a live credential
**must carry** a `case "$-" in *x*)` refusal in its prologue, enforced by
`scripts/lint-shell-trace-credential-refusal.py`. Stated as an obligation, not
as an accomplished fact: of 154 in-scope scripts, 24 carry it today (23 added
here, plus `cutover-verify.sh`, which already did) and 130 are enumerated in the
baseline as deferred (24 + 130 = 154). A Decision sentence in the indicative would assert a
coverage property the artifact does not yet provide.

### Why the state predicate wins

`case "$-" in *x*)` asks *is tracing on*. It is complete by construction. A
boundary interceptor must instead enumerate the ways to turn tracing on, and
that list cannot be proven complete. Measured on bash 5.3.9, eight forms enable
tracing and **two carry no `-x` token at all**:

| Form | `-x` in argv? | Leaks expanded args? |
|---|---|---|
| `bash -x`, `sh -x`, `-eux`, `-o xtrace` | yes | yes |
| `set -x` / `set -o xtrace` in-script | yes | yes |
| `env SHELLOPTS=xtrace` | **no** | yes |
| `env BASH_ENV=<file with set -x>` | **no** | yes |

`BASH_XTRACEFD=N` is deliberately **not** in that table: measured, it does not
enable tracing at all (`$-` stays `hB`, no trace output). It only *redirects* a
trace some other form already enabled — which is why it belongs to the redaction
argument below rather than to the enumeration of enablers. An earlier draft
counted it as a third no-token enabler; that was wrong, and the correction
shrinks the enumeration without touching the decision.

`BASH_XTRACEFD` independently rules out the mitigation alternative: the trace
can be sent to an arbitrary file descriptor, so redacting stdout and stderr does
not bound the channel.

`-v` / `--verbose` is excluded by measurement — it echoes raw source text, not
expanded values, so it cannot leak an environment-sourced secret.

### Why commit time, not the harness boundary

A GitHub Actions log is a transcript. A harness hook is structurally blind to
it, while a lint is not — `lint-diagnosis-claims.sh` already scopes
`.github/workflows`, `.github/actions`, `scripts` and `apps/web-platform/infra`.
Five hand-written `set -x` warnings already sit unenforced across three
workflows (`apply-web-platform-infra.yml` at three anchors,
`apply-github-infra.yml`, `apply-deploy-pipeline-fix.yml`).

The commit-time walker is also **opt-out** rather than opt-in:
`--changed --base REF` scans a new script the moment it is committed, which is
better new-code coverage than an interceptor that only fires if someone happens
to invoke the script through the harness.

### The complement, not a rejection

The PreToolUse hook owns the residual the lint cannot reach: ad-hoc
`bash -c '…'` and scripts written but never committed. That is where #7797
actually happened, so the interceptor is **sequenced second and scoped**, never
dropped. Filed as a follow-up rather than built here, because its value is only
what remains after the lint.

## Consequences

- A point-in-time assertion is not an invariant, so the lint carries a **second
  rule**: no trace-enabling token *below* the refusal. Measured — a `set -x`
  under a fully compliant preamble still leaks every subsequent bind, and it is
  the shape all five workflow comments are warning about.
- Rule B is the guard's one drifting dimension and is named as such
  (`TRACE_TOKENS`). Rule A quantifies over no spelling list at all.
- **The refusal must not leak while refusing.** The first draft guarded with
  `[ -n "${VAR:-}" ]`, which expands the value, so xtrace printed
  `+ '[' -n <TOKEN> ']'`. `${VAR:+x}` is the same predicate with the value never
  on a command line. Any future variant must preserve that property; the suite
  asserts it functionally and mutation-proves the assertion can fail.
- **The escape hatch is sound only for an INHERITED credential.** A script that
  ACQUIRES its credential has the variable empty at the refusal, so a conditional
  hatch is open by construction and the fetch is then traced — measured live in
  `fresh-host-boot-trail.sh`. Those files refuse unconditionally; the lint tells
  the two classes apart and requires the right form for each. This was found by
  review after the conditional form had already shipped to 21 scripts.
- **The refusal must cover every credential the file references.** Rules A and B
  check placement and what follows; neither checks that the guard names the right
  variable. Six of the 21 remediated scripts guarded one credential and consumed
  another, and one printed a Better Stack password in cleartext while "passing".
  Rule C closes it, so the mismatch cannot recur.
- **A guard that blocks a recovery path gets deleted.** For the inherited class
  the refusal permits tracing when the credential is unset, and says so. This is
  the direct lesson of
  `knowledge-base/project/learnings/2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md`,
  from this issue's own lineage.
- Exit **78** (`EX_CONFIG`), not 64. 64 is `EX_USAGE` across 57 files here, and
  78 is *already* this repo's `EX_CONFIG` — `scripts/sentry-issue.sh` uses 78 for
  HTTP 403 and 77 (`EX_NOPERM`) for 401. An earlier draft of this ADR said 78 was
  unused; it is not, and the existing precedent is the better argument. Under
  `sweep-followthroughs.sh` any non-0/1 exit maps to TRANSIENT, the fail-safe
  direction; the runbook names 78 so it is not misread as a network flake.
- The deferred population is an **enumerated path list**, not an integer. A
  count cannot say *which* files, so nobody can pick up the next ten. Drawdown
  trigger: any PR that edits a listed script must remediate it, enforced by
  `--changed`.

### Named residual holes

- A `BASH_ENV`-installed `DEBUG` trap gives per-command echo with **no bit** in
  `$-` or `SHELLOPTS`. `BASH_ENV` is inside the stated threat model, so this is
  a hole in it, not out of scope.
- xtrace does not cross `exec` or a child invocation, so a traced **parent**
  leaks a callee's argv while the callee's preamble sees a clean `$-`. Argv
  hygiene is the only defense for that shape — which corrects #7797's framing
  that the argv→stdin sweep buys nothing here.
- The `SHELLOPTS` arm is unreachable in bash (an env-supplied `SHELLOPTS`
  already sets `x` in `$-`). Kept as belt-and-braces and commented as such so
  the next reader does not delete the load-bearing `$-` arm instead.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **PreToolUse(Bash) hook** (the issue's own proposal, and this plan's v1) | Cannot see CI logs; depends on an unprovable enumeration of trace spellings, two of which carry no `-x` token. Filed as the complement. |
| **Extend the lint to CI `run:` bodies** (this plan's v2) | Cut. Detecting "enables tracing" in YAML is exactly the enumeration the decision above rejects, with no `$-` to lean on, against a live population of **zero** trace-enabling steps. Filed as its own guard with its own contract. |
| **Redact the trace output** as the GENERAL mechanism | Not available: `BASH_XTRACEFD` sends the trace to an arbitrary fd, so no stdout/stderr filter bounds the channel. **This does not forbid a targeted redaction on a specific, known channel** — the same PR strips `^\+` lines in `sweep-followthroughs.sh` before probe output reaches a public issue comment. That is defense-in-depth on one enumerated sink, not a substitute for the carried refusal, and the two are complementary rather than contradictory. |
| **Reuse `redact-engine.py` (ADR-095) as the detector** | Wrong predicate. It finds secrets present as *literals in a file*; the at-risk scripts read them from the environment and contain no literal, so it returns clean for exactly the dangerous case. |
| **Require the refusal in every script** | Fails the third property — the ~673 credential-free scripts must stay freely traceable, and a gate that blocks ordinary debugging gets routed around. |

## Related

- [ADR-198](ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md)
  and commit `223da596f` — the same credential class via the **argv** vector.
  Distinct: argv hygiene closes `ps` / `/proc/<pid>/cmdline`; this closes the
  trace. PR #7793 shipped both for one script, and reading them as duplicates
  would retire the wrong one.
