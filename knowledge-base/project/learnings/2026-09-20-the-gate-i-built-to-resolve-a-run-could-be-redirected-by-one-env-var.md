---
title: "The gate I built to resolve a run could be redirected by one env var"
date: 2026-09-20
category: security-issues
module: git-data
issue: 8010
pr: 8388
refs: [8388, 8412, 8397]
tags: [guard-design, review-panel, seam, anchor-assertion, instrument-verification, acceptance-criteria, ci-vs-local, control-arm, discoverability-test, ci-ratchets, env-inheritance]
---

# The gate I built to resolve a run could be redirected by one env var

## Problem

#8010: `git_data_rung2_rehearsal_gate` asserted the SHAPE of an attestation, never that a
rehearsal passed. A four-line hand-written file naming a nonexistent run released the last
mechanical hold on birthing the host that stores every connected user's source code.

The fix resolves the Actions run the evidence names, re-hashes the tree that run booted, and
requires the run to have uploaded an evidence artifact. It shipped 217/217 green, with a
mutation battery, and a nine-seat review panel then found **three P1s in it** — every one a
member of the defect class the PR existed to close.

## Root cause: a guard's own escape hatches are the least-reviewed code in the diff

### 1. The announced seam was one of TWO routes into the fetch

I built `SOLEUR_RUNG2_RUN_FETCH` as a double-gated, self-announcing test seam, and wrote in
the comment directly above it that "one leaked env var in a pull_request-triggered workflow
cannot redirect the gate's only network call."

One line above that comment sat:

```bash
GIT_DATA_RUNG2_API_BASE="${GIT_DATA_RUNG2_API_BASE:-https://api.github.com/...}"
```

Three seats independently pointed a local server at it. Measured: the bearer arrived **in
cleartext over `http://`**, a fabricated body supplied step C's entire "the run is real,
successful, `workflow_dispatch`, on main" verdict, and `_seam_note` stayed **empty** — so the
`RELEASED` line was byte-identical to a live measurement. Two `env:` lines on the
`pull_request`-triggered freshness step both exfiltrate the job token and forge the verdict.

Every other defence protected the **transport** (`--disable`, `--noproxy '*'`, no `-L`, the
xtrace clear). None protected the **destination**.

**The generalizable shape:** when you build a deliberate, hardened escape hatch, the hatch
gets the scrutiny and its undefended *sibling* gets none — because the sibling doesn't look
like an escape hatch. It looks like a default.

### 2. The annotation inverted the vocabulary it was built to keep separate

The PR's thesis is that could-not-measure tokens and measured refusals "never share wording."
`_git_data_rung2_annotate` had no membership filter, and all three call sites pass whatever
token the helper returned — so `RUN_NOT_MAIN`, `RUN_NOT_SUCCESS`, `RUN_NOT_FOUND` and four
more printed **"could not MEASURE"** on the one surface an operator reads.

The suite could not see it. `E2`, the only arm asserting "a measured refusal does not
annotate," used a fixture that refuses at **step B** — which has no annotate call site at all.
A negative control whose input never reaches the code under test is not a control.

### 3. `find` was load-bearing and absent from the tooling list

The symlink/hardlink sweep over the archived tree depends on `find`. The tooling ABORT checked
`jq curl tar`. Shadowing `find` stopped the refusal firing and the gate hashed the tree anyway.
A tooling list is a claim about what a library CALLS; mine was a claim about what I remembered.

## Solution

- `GIT_DATA_RUNG2_API_BASE` is now a `readonly` https constant with no override.
- `_git_data_rung2_annotate` filters on exported token sets (`git_data_rung2_token_sets`), and
  emits `REFUSED` for the measured half. `E2` re-pointed at a step-C fixture; `E2b`/`E2c`
  assert **both directions** over every set member; `E2d` asserts every **literally** bracketed
  token in the gate's source is classified in exactly one set. Corrected 2026-09-20 (see the
  Addendum): that is 10 of 21 — the 11 reaching the verdict line through the generic
  `HOLD [${_tok}]` sites are outside its haystack, so `E2d` is NOT the cross-copy parity
  mechanism this bullet originally claimed. That parity arm now lives in the #8210 probe suite.
- `find` and `sha256sum` added to the tooling list.
- **Guard 5** (a `soleur:engineering:cto` ruling): a change-triggered monotonic run-id floor.
  Steps D and E are hash-EQUALITY checks, so reverting the payload and citing the genuine older
  run that booted it RELEASES honestly — and that payload is already in our history at
  `f64b0ebc2^`. Ancestry was correctly cut at plan time (a revert commit is a *descendant*); a
  floor read from the version the file REPLACES costs nothing while nothing moves.

## Key insights

### A guard's escape hatch has siblings, and the siblings are undefended

Grep every env var, config key and default the guard reads, and ask of each: *if an attacker
sets this, what does the verdict become, and does the verdict SAY so?* The one you designed as
a seam is the one you hardened.

### `tr -d` takes a byte SET, not a sequence

Fixing the GNU-only `sed 's/\xe2\x80\xa8//g'` (BSD sed matches the literal characters, so both
Unicode separators survive on the workstation path `--disable` exists for), I reached for
`tr -d '\342\200\250\342\200\251'`. That deletes those bytes **individually** — an em-dash is
`\342\200\224`, so every multi-byte character in the message would have been mangled. Caught by
a fixture asserting an em-dash SURVIVES, not just that the separators are gone.

**A strip assertion needs a retention fixture shaped like the risk.** "The bad bytes are gone"
is satisfied by "all the bytes are gone."

### The fixes for a review round are as unpinned as the blind spots they close

Two of my own fixes were wrong on the first re-run, and one fixture pair tested nothing:

- Guard 5's floor helper read the **current** commit's content, not the version it replaced
  (F2/F4/F5/F6 all RELEASED).
- `N1b` — the arm asserting the env override is gone — was defeated by the comment I wrote
  explaining what was removed, which quotes the old spelling. `cq-assert-anchor-not-bare-token`,
  **inverted into a false FAIL**. Both haystacks are now comment-stripped.
- `F4`/`F5` compared `80000800` against `80000800`, because `F3`'s *acked* downgrade
  legitimately lowers the floor. Correct ratchet behaviour, broken fixtures.

A review-driven fix is written after the tests exist, so nothing forces coverage for it.
Mutate each one back out in the same commit.

### An instrument's silence is not a measurement

Five verification commands in this session returned confident wrong answers rather than errors
(the ship round added more — see the Addendum's session errors):

- `bunx vitest` on a `bun:test` suite → "2 failed, no tests", which reads as a real failure.
- `grep -c ... -r` → per-file counts, not a total.
- An actionlint baseline comparison whose output-format grep matched nothing → reported
  "0 findings" for a file with 9.
- Two attempts to prove the probe-suite verdict fix both hit an **earlier-exiting branch**
  (`EXACT`-mismatch → `printf` + `exit 1`), so neither exercised the trailing-test branch.
- The Phase 1.6 token-efficiency report printed **0 subagent tokens** and "no outliers" for a
  session that spawned 16 agents totalling ≈**2.45M** subagent tokens (summed from the
  completion notifications).

Run every instrument against a case whose answer you already know before reading its verdict.

## Session Errors

1. **`/tmp` tmpfs hit its quota mid-session** (5.5 GB of 09-18 mutation-test repo copies in a
   prior session's scratchpad). A `pwd` failed with `write error: Disk quota exceeded`, which
   read as a broken shell rather than a full disk.
   **Prevention:** when a trivial command fails inexplicably, check `df -h /tmp` before
   diagnosing the command. The tmpfs reaper does not reclaim the count-shaped leak (documented
   gap); large scratch trees belong in `/var/tmp`.

2. **PR #8393 was created with an empty body.** The heredoc writing the body file was in the
   same Bash call that hit the quota, so `gh pr create --body-file` succeeded against a
   zero-byte file.
   **Prevention:** write PR/issue body files with the Write tool in their own step, then assert
   `wc -c` before passing them to `gh`.

3. **`gh issue create --body-file` denied twice** — the filing gate cannot read a `$VAR` path
   *or* a `/tmp` path.
   **Prevention:** write the body with the Write tool to a repo-relative path and pass that
   literal path.

4. **Auto-merge blocked twice on #8393 by a close-keyword in prose.** "It does not **close
   #8210**" parses as a closing keyword; my first reword was written but `gh pr edit` was not
   re-run, so the second attempt failed for the same reason.
   **Prevention:** after every body edit, re-read the API field that carries the effect
   (`gh pr view --json closingIssuesReferences`), not the prose.

5. **`tr -d` used to strip a multi-byte sequence** — would have deleted `\342`/`\200` from every
   em-dash.
   **Prevention:** `tr` operates on byte sets; use string replacement for sequences, and pair
   every strip assertion with a retention fixture shaped like the risk.

6. **Guard 5's floor helper read the current commit instead of the one it replaced.**
   **Prevention:** for any "compare against the previous version" helper, the fixture must
   commit at least twice and assert the value comes from the EARLIER one.

7. **`N1b` defeated by its own explanatory comment.**
   **Prevention:** comment-strip the haystack at extraction time, once, so every later arm
   inherits the immunity instead of having to remember it.

8. **Claimed a measurement I never made** — asserted the probe-suite verdict fix was proven
   when both attempts hit an earlier-exiting branch. Corrected in the same turn.
   **Prevention:** before reporting a mutation result, confirm the mutant reached the branch
   under test (add a marker, or assert the branch's own output appears).

9. **`bunx vitest` run against a `bun:test` suite** — "2 failed, no tests" read as a real
   failure for one cycle.
   **Prevention:** check the suite's import (`bun:test` vs `vitest`) before choosing a runner.

10. **Malformed verification commands** (`grep -c ... -r`; an actionlint baseline grep matching
    nothing) produced answers rather than errors.
    **Prevention:** the instrument-verification rule in `review/SKILL.md` — known-positive and
    known-negative arms before reading any verdict.

11. **`mutate_suite` reported `rc=2 / failures='none'`** for two harness rows, hiding that the
    mutants had ABORTED rather than run green. The abort came from the F4/F5 fixture problem
    (byte-identical writes produced no commit → `_a_setup_fail`).
    **Prevention:** fixed — `mutate_suite` now reports the mutant's own tail on failure. A
    harness that cannot distinguish "ran green" from "aborted" asserts a wrong diagnosis.

12. **F4/F5 fixtures tested nothing** (see Key Insights).
    **Prevention:** when a guard is a ratchet, a fixture sequence must re-establish the
    high-water mark between rows that each lower it.

13. **Forwarded from the planning phase:** first commit rejected by `lint-infra-no-human-steps`
    (the word "reboot" beside an actor word); two attribution errors in its own draft (#8312 vs
    #8210 for the reset arm; the `actions: read` comment documenting the sibling `/jobs`
    endpoint), both caught by `git-history-analyzer`; one invalid `git status --cached`; one
    duplicate Monitor arm. One-off.

## Prevention (workflow-level)

- **Review-panel concurrency:** with ≥3 seats, spawn report-only and apply every fix yourself
  from one known SHA. Two seats in an earlier session reported the tree shifting under them.
- **Guard-shaped PRs get the structural-enumeration seat**, and it earned its place here: it
  produced the API-base finding as part of a *map* rather than as an adversarial sample, and
  the security seat then measured it independently.
- **Route design forks to `soleur:engineering:cto`**, not the operator. The downgrade-shape
  ruling sharpened a residual I had recorded as accepted into a mechanism that ships, and it
  found the exploit payload already committed in our own history.

## Addendum — 2026-09-20 (#8010 / PR #8412): the ship round, and how little of it was new

Shipping this branch surfaced **ten** further defects (3 + 3 + 2 + 1 + 1 across the groups below).
A four-seat review of the first draft of this addendum then found that **four of the five classes I
had written up as discoveries were already documented**, with anchors I had loaded in the same
session. That is the more useful finding, so it goes first.

### What was already written down

| What I "found" | Where it already lives |
| --- | --- |
| A hand-copied set drifts from its source, silently and green | `review/SKILL.md` — *"A guard that RESTATES the value it guards goes stale silently and fails GREEN"* |
| A comment claiming a sibling consumer is checked against this mechanism | `review/SKILL.md` — *"Self-claimed cross-artifact contract drift"* |
| Acceptance criteria that assert the opposite of what shipped | `2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md` §2 |
| A repo-global ratchet is unreachable from a diff-derived suite selection | `work/SKILL.md` — *"A REFUSED gate also owes the repo-global RATCHETS"*, **which already names `lint-trap-tempfile-ownership` as the instance** |
| A control whose premise is inherited from the environment | `review/SKILL.md` — *"A suite must clear EVERY env var the SUT branches on"*, including the litmus *"treat any PASS-count change as a finding"* |

The `R14-control` defect (236/0 locally, 235/1 in CI, on `GH_TOKEN`/`GITHUB_TOKEN`) is that last
litmus firing exactly as written. I reported it as a discovery. The instances are still worth
naming — `E2d`, the #8210 probe's stale copy, FR15/FR5/FR14, `lint-trap-tempfile-ownership`,
`battery-tag-authorship`, `R14-control` — but the classes are not new, and writing them up again
splits each rule's canonical home.

**The rule this violates is already in the corpus too:** *the disposition for a recurring
documented class is a mechanical gate, not another learning.*

### The one class with no prior statement

`soleur:preflight` Check 10 executes a plan's declared `discoverability_test.command` inside a
bubblewrap sandbox under a **15-second cap**, and compares stdout against `expected_output`. This
plan declared `bash tests/scripts/test-git-data-birth-readiness-gate.sh` — the 236-assertion suite —
with a prose `expected_output`. Measured at this PR's own ship gate: killed at `rc=124` with arms
still passing, and no matcher can compare stdout to a sentence.

Check 10 behaved exactly as specified. The gap is upstream: `plan/SKILL.md`'s **Reject conditions**
for `discoverability_test` cover `ssh`, the verb allowlist and placeholder text, and do not cover
a command that cannot finish inside the cap, or an `expected_output` that is not a matchable
literal. This PR adds both, mirrored into `deepen-plan` Phase 4.7 — so the class becomes a gate
rather than a fourth learning.

The durable shape: **a declared verification is only a verification if the thing that consumes it
can run it.** Replaced here by `scripts/git-data-rung2-gate-verdict.sh`, which prints the single
`RELEASED`/`HOLD [<TOKEN>]` line the plan's own `liveness_signal` already names as the signal, in
about a second.

### Residual, not closed

`E2d` still matches only the **10 literally-bracketed** tokens; the 11 reaching the verdict line
through the generic `HOLD [${_tok}]` sites are outside its haystack. Within its 10 it is sound — it
requires each token to score `_n_cannot + _n_meas -eq 1`, so one emitted and never declared reds it.
For the other 11 nothing does. The cross-file parity arm added to the #8210 probe suite catches a
token *moved between the declared sets* — moving `RUN_NO_EVIDENCE_ARTIFACT` reds 2/152 there while
the gate's own 236 stay green — but it, too, cannot see a token that was never declared at all.

Impact is triage accuracy, not release. Both consumers refuse either way:
`infra-validation.yml` `exit 1`s on both branches (the classification selects only the `::error::`
wording), and the #8210 probe picks exit 2 `NOT YET` vs exit 3 `CANNOT ESTABLISH`. A misclassified
token degrades what the operator is told; it cannot turn a HOLD into a RELEASE. Tracked in #8397
with the other rung-2 residuals.

### Session errors — the ship round

1. **Ran `sync-pr-behind.sh 8393` by absolute path from a different worktree.** The script derives
   its repo root from its OWN location and ignores the PR argument for branch selection, so it
   merged `main` into my branch and pushed it.
   **Prevention:** a script taking an identifier as an argument does not necessarily ACT on it —
   run repo-scoped scripts from the worktree they target, and read the push line's branch name.
2. **Merged `main` into a STALE local worktree** for #8393 (`d7b279c39` vs the PR head
   `79dc3b433`); the push was rejected as non-fast-forward.
   **Prevention:** `git fetch <branch> && git reset --hard origin/<branch>` before syncing a branch
   whose worktree this session did not create.
3. **Started the full battery before the tree was final.** Re-reading the plan's acceptance criteria
   against the tree then forced an edit, so the queued run was killed and relaunched.
   **Prevention:** re-read the ACs against the tree BEFORE Phase 4 — `ship/SKILL.md` has no
   AC-verification step, and the Phase 5.5 advisor consult is after Phase 4, so it is too late to
   absorb an edit.
4. **`ls … && python3 lint.py` short-circuited**, running a Python lint under `bash`.
   **Prevention:** never gate an interpreter invocation on a test whose success also selects it.
5. **Read UTC CI timestamps as local**, briefly concluding I had the wrong run.
   **Prevention:** compare `date -u` against the log's `Z` stamps before calling a run stale.
6. **A monitor filter excluded uppercase `EXPECTED` only**, so lowercase self-labelled expected
   failures read as new ones.
   **Prevention:** discriminate on the suite-level shape (`^\[FAIL\] <path> (<N>ms)$`), never prose.
7. **Treated a red `deploy-script-tests` as a defect before establishing which tree it described.**
   All three trees measured 113/0 and it cleared on re-run — a flake.
   **Prevention:** re-run a red check before reconciling trees; if it persists, `refs/pull/N/merge`
   is the tree under test (see `2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md`).
8. **Wrote "eleven" into three artifacts before anything counted the sections**, which sum to ten.
   It reached the learning, the commit message, and the PR title and body — seven sites — and was
   caught by a review seat, not by me.
   **Prevention:** this file's own body already says *verify a measurement ONCE, before it
   propagates*. For a count, state the arithmetic inline (`3 + 3 + 2 + 1 + 1`) so the claim carries
   its own check.
9. **Wrote up four documented classes as discoveries.** Before writing a learning, grep
   `plugins/soleur/skills/*/SKILL.md` and `knowledge-base/project/learnings/` for the class and
   cite it; a restatement splits the canonical home and is worse than silence.
