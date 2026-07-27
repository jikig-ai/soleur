---
title: "A check that cannot report is indistinguishable from a check that passed"
date: 2026-07-27
category: test-failures
module: tests/scripts, scripts, .github/workflows
tags: [fail-open, vacuous-test, mutation-testing, gate-invocation, instrumentation, env-parsing, actionlint, tmpfs, citations, verification]
symptom: "Eight independent green/pending signals, each of which was asserting nothing"
root_cause: "A check that cannot emit a failure — never invoked, aimed at the wrong target, silently reinterpreted, or hung — is observationally identical to one that passed"
related_prs: [6989, 6986]
related_issues: [6977, 6982, 6986, 6997, 7002, 6789]
---

# A check that cannot report is indistinguishable from a check that passed

## Problem

Shipping the gated `git-data-host-create` birth route (#6977) turned up **eight**
separate checks that were reporting success while asserting nothing. They are not
eight bugs. They are one bug wearing eight costumes, and the costume is always the
same colour: **green, or still-running — never red.**

That is what makes the class expensive. A wrong answer gets investigated. A
*confident* answer does not.

> **The spine:** a check that cannot emit a failure is observationally identical to
> one that passed. Verification therefore has two obligations, and passing is only
> the second. First prove the check *can* fail; then care that it didn't.

## The eight instances

### 1. A gate that is never CALLED

The parity test asserted the presence of `source` lines. In bash, `source` only
**defines** functions — it never runs them. Three separate mutations each left the
suite **102/0 green**:

- neutering the gate invocation
- deleting the interlock invocation entirely
- adding `if: ${{ false }}` to the interlock step

**Fix:** assert the *invocation*, and that the step cannot be skipped. All six such
mutations are now pinned RED.

```bash
# Not evidence — this only defines the function:
source "${GITHUB_WORKSPACE}/tests/scripts/lib/git-data-birth-readiness-gate.sh"
# Evidence — this runs it and can fail:
if ! git_data_birth_readiness_gate "${WORKSPACE}/…/cloud-init-git-data.yml"; then exit 1; fi
```

### 2. Instrumentation aimed at the wrong mount

`scripts/test-all.sh` exported `TMPDIR=/var/tmp` near the top, then sourced
`test-contention.sh`, which binds **at source time**:

```bash
TC_TMPDIR="${TC_TMPDIR:-${TMPDIR:-/tmp}}"
```

So the #6789 contention janitor measured **disk-backed `/var/tmp`** — hundreds of GB
free, healthy forever — instead of the `/tmp` tmpfs it exists to watch. Fixed by
pinning `TC_TMPDIR=/tmp` *independently* of `TMPDIR`. Verified in the live runner:
the preamble now prints `tmp /tmp: 29% used`.

The sharpest detail: #6986's `scratch-root.sh` had **already documented this exact
hazard in prose** ("repointing TC_TMPDIR would silently blind that instrumentation").
The prose existed, was accurate, and did not prevent it. Prose is not a gate.

### 3. A flag silently reinterpreted as DATA

`scripts/lib/scratch-root.test.sh` isolated its environment with:

```bash
env "HOME=$TMP_ROOT" --unset=TMPDIR bash -c '…'   # WRONG
```

GNU `env` **stops option parsing at the first `NAME=VALUE` operand**. So
`--unset=TMPDIR` was not an option at all — `env` defined a variable *literally named*
`--unset` with value `TMPDIR`, unset nothing, and **exited 0**.

The assertion "the resolver does NOT export `TMPDIR`" was therefore asserting a
property of the **ambient environment**, not of the module. It passed for as long as
`TMPDIR` happened to be absent; the moment a harness exported it, the *untouched* test
went red. Correct form puts options first:

```bash
env --unset=TMPDIR "HOME=$TMP_ROOT" bash -c '…'   # RIGHT
```

Swept the repo for `env NAME=VALUE … -opt` — this was the only occurrence.

### 4. A linter that HANGS

Bare `actionlint` never completed. At **13.5 minutes** it sat at **0.0% CPU**, state
`Sl`, blocked in `futex_do_wait` — **hung, not slow**. "Still running" is
indistinguishable from "still working", so it never presents as a failure.

Bisected: 68 of 69 workflows lint in under 3 s; `cutover-inngest.yml` (1753 lines)
hangs. Isolated to the **shellcheck integration** (`-shellcheck=` → rc 0 instantly;
`-pyflakes=` → still hangs). actionlint 1.7.7. Pre-existing on main, byte-identical,
and **nothing in CI invokes actionlint**. Filed #7002.

### 5. A half-applied ergonomic fix

The PR added an automatic `TMPDIR` default to `test-all.sh`, justified as *"removes
the footgun instead of documenting it a seventh time."* But `test-all.sh`'s own
epilogue points at `run-registered-suites.sh` — the one runner it structurally cannot
cover — which still required a manual prefix.

I walked straight into it: dropped the prefix, got **71/72 with rc 1**, and briefly
read a full RAM disk as a regression. Measured root cause: several infra suites copy
the whole **162 MB** `.terraform` provider tree *per mutation*
(`credential-persist-home-guard` ≈ 13 copies ≈ 2 GB) against a ~4 GiB tmpfs. It
reproduces with the runner **completely idle**, so it is capacity, not contention.

The plan was internally inconsistent about this: its Test Strategy claimed *"`TMPDIR`
is handled by Phase 3.3 rather than hand-typed"* for a table **including**
`run-registered-suites.sh`, but Phase 3.3 scoped only `test-all.sh`. Fixed in
`2091b655e` — the fix makes the plan's stated strategy true rather than aspirational.

### 6. A committed ADR asserting a mitigation nothing tracked

ADR-149 stated *"a follow-on issue covers retrofitting"* the extracted preamble. **No
such issue existed.** The mitigation read as handled and was backed by nothing.

Both counts were also wrong — the ADR said "five", the preamble header said "seven".
Re-derivation gives **eight** gates carrying neither the readability nor the
classifiability check, plus **three** holding equivalent *inline* checks whose
retrofit is pure deletion. Filed #6997, corrected both, and recorded the
re-derivation command **inside the ADR** so the next reader derives rather than trusts:

```bash
grep -l 'local plan_json' tests/scripts/lib/*gate*.sh | xargs grep -L plan_gate_assert_readable
```

### 7. Line-number citations that rot silently

This PR shifted `git-data-luks.tf` by 35 lines. `:79` now resolves to
`doppler_config.git_data_prd` (the volume moved to `:114`); `:90` to a bare `value =`
line (the attachment moved to `:125`).

Worst case: `workspaces-luks.tf` cited `git-data-luks.tf:44-50` for an operator
precondition **this PR deleted** — so it pointed at unrelated lines *and* asserted a
manual step git-data no longer has. Converted live citations to content anchors; left
dated plans and learnings alone as point-in-time records. This **vindicates** the
existing `cq-cite-content-anchor-not-line-number` rather than discovering it.

### 8. A first-token extractor exempting the DEFAULT enum member

The enum⇄description parity check took each `|`-segment's **first token**. Segment one
is `Which apply path? manual-rerun (default)` → first token `Which` → fails the
kebab-case filter → **whole segment dropped**. So `manual-rerun`, the default and
likeliest-to-matter option, was the one member never checked — while a comment claimed
it *"keeps its leading token."*

Fixed to the first **kebab-matching** token, plus the **converse** coverage assertion
(an option added to the enum but never documented), with word-boundary matching so
`inngest-host` cannot ride on `inngest-host-replace`. Both mutation-verified RED.

## Key Insight

Three tests each of these eight would have passed on the day they were written. What
they lacked was not correctness but **falsifiability**.

The generalizable rule: **before trusting a green check, make it go red on purpose.**
If you cannot construct the mutation that fails it, the check is decorative. This is
cheap — every fix above was verified by a single deliberate mutation and a restore —
and it is the only technique that distinguishes the eight failures here from real
passes, because *nothing in the output distinguishes them*.

Corollary for the hung case: **"pending" is a third state that must be timed out**, or
it silently becomes a permanent pass. Wrap long verifications in a timeout so an
absent answer surfaces as a failure rather than as patience.

## Prevention

- Assert **invocations**, never `source`/import lines. Definition is not execution.
- Bind instrumentation targets **independently** of general-purpose env vars, and
  re-verify the live output names the intended target (`tmp /tmp: …`, not `/var/tmp`).
- Put `env` **options before** `NAME=VALUE` operands; a misplaced option becomes a
  bogus variable and exits 0.
- Give every long verification a **timeout**; distinguish `0.0% CPU` (hung) from
  working before waiting.
- When an ergonomic default removes a footgun, apply it to **every runner the docs
  point at**, not just the one in scope.
- Never assert a mitigation in an ADR without a filed issue number; record the
  **re-derivation command** next to any count.
- Re-derive inherited numbers after a merge: they can **match and still mean something
  different** (see Session Errors #8).

## Session Errors

**Working-directory drift across parallel calls** — `pwd` returned the bare repo root
while I believed I was in the worktree, producing a `git show HEAD:` result that
contradicted the diff. Recovery: explicit absolute `cd` in every subsequent command.
**Prevention:** never rely on CWD persistence across independent Bash calls; pass an
absolute `cd` in each. Also guards `hr-when-in-a-worktree-never-read-from-bare`.

**Launched a second long run without stopping the first** — two runs wrote to the same
log paths while the newer began with `rm` of files the older still held open;
`infra.log` vanished while its `infra.rc` survived. Recovery: discarded both, re-ran
clean. **Prevention:** stop the prior task before relaunching; contended output is
worth *less* than no output, because it looks like data.

**A restore-trap reverted my own edit** — a mutation test's
`trap 'git checkout -- $WF' EXIT` silently discarded an earlier content-anchor edit to
the same workflow. Caught only by reading `git status` before commit. **Prevention:**
mutation-test a file you have already edited by snapshotting to a temp copy, never by
git-restoring it.

**Trusted the harness notification over the runner** — a completed background run
reported "exit code 0" while its own `infra.rc` said `1`; the notification reports the
trailing `echo`, not the runner. **Prevention:** always read the runner's own rc file
and summary.

**Ran the gate matrix against a stale tree** — the run started before my edits landed,
so its verdict described a tree that no longer existed. **Prevention:** re-run after
the last edit, or don't quote the numbers.

**Waited ~13 minutes on a hung linter** before checking whether it was running or
blocked. **Prevention:** check CPU/state before waiting (instance 4).

**Dropped a required `TMPDIR` prefix** and briefly misread a full RAM disk as a
regression. **Prevention:** fixed at the source in `2091b655e` (instance 5).

**Introduced a stray `>` and a typo into a shell comment** via an Edit — it would have
been a live redirect. Caught immediately by `bash -n`. **Prevention:** syntax-check
after editing shell files.

**A `grep` alternation returned nothing and I read the silence as a fact** — grepping
for `export TMPDIR` in the branch's `test-all.sh` produced no match, appearing to
contradict the diff that plainly added it. The empty result was an artifact of the
working-directory drift above, not evidence about the file. **Prevention:** an empty
grep is only evidence once you have confirmed you are grepping the file you think you
are; this is the same spine as the eight instances — a search that cannot match is
indistinguishable from a search that found nothing.

**Guessed a non-existent label** (`type/tech-debt`) on `gh issue create`. Recovery:
`gh label list` → `type/chore`. `gh` failed loud, so low cost.

**`gh issue create` blocked for a missing `--milestone`** — correct hook catch,
already enforced.

**Forwarded from `session-state.md`:** two writes blocked by `iac-plan-write-guard`
(both correct catches, resolved by rewording so the gate stayed armed);
`terraform-architect` returned a preamble with no findings; and **four task-brief
premises found false** — including a stale line citation propagated unverified, which
is precisely instance 7's defect class arriving one phase earlier.

## Related

- [The subshell bug I was fixing bit me three more times](./2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md) — #6986, same tmpfs substrate
- [My assertion pinned the text, not the shell that runs it](./2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it.md) — the nearest prior instance of this spine
- [cloud-init comment is a live host input](./2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md)
- ADR-149 — git-data host birth route and readiness interlock
- Issues #6997 (preamble retrofit, eight gates), #7002 (actionlint deadlock)
