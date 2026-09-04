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
carries a `case "$-" in *x*)` refusal in its prologue, and
`scripts/lint-shell-trace-credential-refusal.py` requires it.

### Why the state predicate wins

`case "$-" in *x*)` asks *is tracing on*. It is complete by construction. A
boundary interceptor must instead enumerate the ways to turn tracing on, and
that list cannot be proven complete. Measured on bash 5.3.9, eight forms enable
tracing and **three carry no `-x` token at all**:

| Form | `-x` in argv? | Leaks expanded args? |
|---|---|---|
| `bash -x`, `sh -x`, `-eux`, `-o xtrace` | yes | yes |
| `set -x` / `set -o xtrace` in-script | yes | yes |
| `env SHELLOPTS=xtrace` | **no** | yes |
| `env BASH_ENV=<file with set -x>` | **no** | yes |
| `BASH_XTRACEFD=N` | n/a | yes, redirected off stdout/stderr |

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
- **A guard that blocks a recovery path gets deleted.** The refusal permits
  tracing when the credential is unset, and says so in its own message. This is
  the direct lesson of
  `knowledge-base/project/learnings/2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md`,
  from this issue's own lineage.
- Exit **78** (`EX_CONFIG`), not 64 — 64 is `EX_USAGE` at 57 sites in this repo.
  Under `sweep-followthroughs.sh` any non-0/1 exit maps to TRANSIENT, which is
  the fail-safe direction; the runbook now names 78 so it is not misread as a
  network flake.
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
| **PreToolUse(Bash) hook** (the issue's own proposal, and this plan's v1) | Cannot see CI logs; depends on an unprovable enumeration of trace spellings, three of which carry no `-x` token. Filed as the complement. |
| **Extend the lint to CI `run:` bodies** (this plan's v2) | Cut. Detecting "enables tracing" in YAML is exactly the enumeration the decision above rejects, with no `$-` to lean on, against a live population of **zero** trace-enabling steps. Filed as its own guard with its own contract. |
| **Redact the trace output** | Not an available mechanism: `BASH_XTRACEFD` sends the trace off stdout and stderr entirely. |
| **Reuse `redact-engine.py` (ADR-095) as the detector** | Wrong predicate. It finds secrets present as *literals in a file*; the at-risk scripts read them from the environment and contain no literal, so it returns clean for exactly the dangerous case. |
| **Require the refusal in every script** | Fails the third property — the ~673 credential-free scripts must stay freely traceable, and a gate that blocks ordinary debugging gets routed around. |

## Related

- [ADR-198](ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md)
  and commit `223da596f` — the same credential class via the **argv** vector.
  Distinct: argv hygiene closes `ps` / `/proc/<pid>/cmdline`; this closes the
  trace. PR #7793 shipped both for one script, and reading them as duplicates
  would retire the wrong one.
