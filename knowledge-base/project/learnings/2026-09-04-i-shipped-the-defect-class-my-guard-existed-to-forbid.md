---
title: "I shipped the defect class my guard existed to forbid, nine times"
date: 2026-09-04
category: workflow-patterns
module: scripts
issue: 7797
tags: [guards, mutation-testing, vacuity, secrets, xtrace, measurement, review]
---

# Learning: I shipped the defect class my guard existed to forbid

## Problem

Issue #7797 recorded two live API tokens printed into an agent transcript by
`bash -x`. Shell tracing echoes commands *after* expansion, so a secret leaks the
moment it is bound — before it reaches any command.

The fix is a carried self-refusal (`case "$-" in *x*)`) in every script that
binds a credential, gated at commit time by a walker over the whole population
(ADR-202). The guard's whole thesis is stated in its own ADR: **enforce a
property, never an enumeration — because an enumeration cannot be proven
complete.**

A review panel then found the guard's assembly was narrower than that property in
**nine independent ways, seven of them introduced by this PR**. Every one was
green beforehand. I wrote a guard against "assembly narrower than the property"
and committed that exact defect while building it.

## Root cause

**Every assertion I wrote was checked against the implementation I had just
written, rather than against the property I had just stated.** That single
substitution explains all nine:

- The suite asserted the guard *exists* and *exits 78*. It never asserted the
  property — *no credential value appears in the trace*. So reverting
  `${VAR:+x}` to `${VAR:-}` in any of 22 production copies re-shipped the
  original #7797 leak at **rc=0**. Only the fixture was ever leak-probed.
- The escape hatch was written for the class I had in front of me (a credential
  *inherited* from the environment). For a script that *acquires* its credential,
  the variable is empty at the guard, the hatch opens by construction, and the
  fetch is then traced — live, in a script I had "remediated".
- Six of 21 guards named the wrong credential, because my remediation used a
  narrower detector than the lint's own `SECRET_SIGNALS`.
  `anthropic-admin-key-6297.sh` printed a Better Stack password in cleartext
  under `bash -x` while the lint reported it clean.
- The lint emitted a remedy containing a `YOUR_CREDENTIAL` placeholder — a
  guard that tells you how to satisfy it and hands you text that can never
  guard anything real.

Three assertions could not fail at all: `H1` grepped for a literal that its own
grep line contained (so deleting the entire floor block left it passing); `H4`
was rejected one gate *earlier* than the gate it named; and the emitted remedy
was checked for lint-compliance but never for leak-safety.

## Solution

Rule C now rejects a value-expanding predicate and an uncovered credential;
files whose credential set is not statically knowable must refuse
unconditionally; a zero-file scan refuses rather than reporting OK. The suite
grew 28 → 39 assertions, and **every new assertion was proven falsifiable by
mutating the thing it guards and watching the suite go red** before it was
committed.

## Key insight

**A guard's assertions must be derived from the property, written down before
the implementation, and each one proven to fail.** An assertion written after
the code, by reading the code, can only restate the code — it inherits every
blind spot it was supposed to catch, and it inherits them invisibly, because it
passes.

The corollary that actually bites: *the author of a guard is the worst-placed
person to assert it*, precisely because they know what it does. The mutation
battery is not a nice-to-have on top of a suite; it is the only thing that
distinguishes an assertion from a restatement.

## Measured facts worth keeping

**Bash renders array appends unexpanded, but expands at the invocation.**
Measured on bash 5.3.9:

| Shape | Trace output | Leaks |
|---|---|---|
| `scalar="$SECRET"` | `+ scalar=SEKRIT` | yes |
| `arr+=("$name=${!name}")` | printed **unexpanded** | **no** |
| `out=$("${arr[@]}" "$cmd")` | `++ env … TOKEN=SEKRIT …` | yes |

So "where does this secret leak?" is **not** answerable by reading the binding
site. I assumed the `${!name}` append in `sweep-followthroughs.sh` was the leak;
it is not. The leak is the invocation, where *every* forwarded secret lands on
one line — which then reaches a public issue comment.

**`BASH_XTRACEFD` does not enable tracing.** Measured: `$-` stays `hB`, no trace
output. It only *redirects* a trace some other form already enabled. I had it in
the ADR's table of enablers and counted it as a third no-token form; the correct
count is two. The decision survives; the enumeration did not.

**Masking is applied to the log stream, not to an API payload.** A value
registered via `::add-mask::` still reaches a GitHub *issue comment* in clear.
This is why the `tests/` exclusion exempting `preapply-entrypoint-gate.sh` was a
live hole: it binds a Cloudflare token, and a workflow posts its `2>&1` capture
verbatim into a public comment on #6767.

**Exclusion should key on role, not path.** `tests/scripts/lib/*-gate.sh` are
production CI gates, not tests. The discriminator is a positive identity the
executed role owns — a shebang plus the exec bit — never the absence of
something. Measured: of 17 files there, exactly one is an executed unit, and it
was the leaking one.

## Session Errors

- **Pipeline exit-code masking, four times.** `| tail` / `| head` swallowed the
  rc, so I reported a failing markdown-lint as passing, a failed commit as
  `COMMIT_EXIT=0`, a rejected push as `PUSH_EXIT=0`, and a `--write-baseline`
  refusal as `rc=0` when it was 2. **Prevention:** none to add — `work/SKILL.md`
  already carries this rule in full, and names the exact
  `cmd | grep …; echo "rc=$?"` shape that "will happily hide a non-fast-forward
  `git push`". I then hid a non-fast-forward `git push` with it. The rule is
  already-enforced at the strongest tier available for a shell idiom; the
  failure was **compliance, not coverage**, and adding a second copy of a rule I
  read past four times would buy nothing. The operative fix is behavioural:
  capture `rc=$?` from the bare command on its own line before any pipe or
  expansion.
- **Measured new fixtures from their repo path**, where `fixtures/` is excluded
  by the lint's own rules, read `rc=0`, and concluded the rule did not fire.
  **Prevention:** when a lint excludes a directory, its own fixtures must be
  staged outside that directory before measuring; assert the staging, not the
  verdict.
- **A population figure went stale twice between measuring and writing** (153 →
  154 the moment a carve-out landed one commit later). **Prevention:** state the
  identity as an arithmetic check the reader can run (`carrying + deferred ==
  in_scope`), not as three independent integers.
- **Left five files with a raw newline inside a `printf` format string**, from a
  botched patch, uncommitted across a context-compaction boundary — they were
  nearly committed unreviewed. **Prevention:** before staging, scan the changed
  set for the artifact class the patch tool can produce; `git status` alone does
  not tell you *why* a file is dirty.
- **A Python patch helper was called with the wrong argument count, twice**,
  aborting mid-sweep. Both times the write happened last, so the file was left
  untouched. **Prevention:** keep the `write_text` after every assertion — the
  fail-safe ordering is what turned a bug into a no-op.
- **Three false measurements pre-compaction**: "the trace vector is undefended"
  (`cutover-verify.sh` already self-refused), "the argv→stdin sweep buys zero
  trace protection" (xtrace is not inherited across `exec`, so a traced parent
  leaks a callee's argv), and "warns at two anchors" (five, across three
  workflows — my own earlier grep had shown all five). **Prevention:** re-read
  the output already in the transcript before asserting a count from memory.
- **Claimed the placeholder remedy was deleted** when it was still reachable
  through an `or` fallback. **Prevention:** assert the absence over the *emitted
  output* across every branch, not over the source you just edited.
- **Assumed the array append was the leak site.** I asserted that
  `env_args+=("$name=${!name}")` leaks under xtrace and started designing around
  it; bash prints array appends unexpanded, so it does not. The leak is the
  invocation two lines later. **Prevention:** run the three-line probe before
  reasoning about a trace shape — a five-second measurement replaced a wrong
  premise that had already reached a commit message draft.
- **Asserted `BASH_XTRACEFD` as a trace enabler** in the ADR's table, the plan
  and the lint header. It only redirects an already-enabled trace.
  **Prevention:** every row of a capability table is a claim needing its own
  command; I measured seven of eight rows and inherited the eighth.
- **Wrote three assertions that could not fail** (`H1` grepped a literal its own
  grep line contained; `H4` was rejected one gate before the gate it named; the
  emitted remedy was never leak-probed). **Prevention:** an assertion is not
  finished until its mutation has been run and the suite observed red — the
  battery is what separates an assertion from a restatement.
- **Stopped at the end of `/review` and never opened a PR.** The branch sat
  pushed-but-unshipped through twelve commits until the operator asked. This is
  already covered by `wg-verified-work-ships-without-asking` and the review
  skill's own lifecycle-handoff protocol — the failure was compliance, not a
  missing rule. **Prevention:** treat "I recommend shipping" as a step to
  execute, not a question to ask, once the blockers I named are closed.

## Related

- [ADR-202](../../engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md)
  — the decision this work implements.
- [my guard blocked the recovery and missed the hazard](2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md)
  — same lineage: a guard keyed on a proxy, wrong in both directions.
- [every defect the panel found was in my verification, not my fix](2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md)
  — the same substitution one PR earlier. That it recurred here, in the PR whose
  subject is that exact class, is the finding.
