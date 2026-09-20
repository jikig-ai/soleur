---
title: "The gate I built to resolve a run could be redirected by one env var"
date: 2026-09-20
category: security-issues
module: git-data
issue: 8010
pr: 8388
tags: [guard-design, review-panel, seam, anchor-assertion, instrument-verification]
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
  assert **both directions** over every set member; `E2d` asserts every bracketed token the
  gate emits is classified in exactly one set — the parity mechanism three hand-maintained
  copies (gate, probe, probe suite) lacked.
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

Five verification commands in this session returned confident wrong answers rather than errors:

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

## Addendum — the SHIP round found eleven more, and the panel could not have seen any of them

The body above ends at the nine-seat panel. Shipping the same branch then surfaced eleven further
defects, and the pattern is sharper than "more review finds more bugs": **each was invisible to the
instrument the work had chosen, and visible only to an instrument the work had not yet run.** That is
one claim, demonstrated four different ways.

### 1. The mandated advisor consult found three, all in code the REVIEW ROUND had added

- **The token-set parity assertion was blind to 11 of 21 tokens.** `E2d` matched only *literally*
  bracketed emits, so every token reaching the verdict line through the generic `HOLD [${_tok}]`
  sites was invisible — exactly the sites where the panel's P1 #2 had lived. Demonstrated by moving
  `RUN_NO_EVIDENCE_ARTIFACT` between the two sets: suite stayed green.
- **The #8210 probe hand-copied the could-not-measure set and had already drifted**, missing
  `RUN_FLOOR_UNREADABLE` — a token this very PR adds. A Guard 5 instrument failure would have
  rendered `NOT YET` ("the gate looked and the answer was no") instead of `CANNOT ESTABLISH`. The
  gate's own comment claimed consumers were checked against `git_data_rung2_token_sets`; true of
  `infra-validation.yml`, false of the probe. **A capability claim about a consumer is a claim about
  that consumer's code, not about the mechanism you built for it.**
- **The downgrade ack stated a `'#'` rule its code did not implement** — the helper read the
  comment-stripped body, so `…:see #8399` became the reason `"see"`, non-empty, accepted. The Sentry
  ack had refused this by name since Phase 2 and was pinned by `M3c`; this arm had neither.

### 2. The AC sweep found three acceptance criteria asserting the opposite of what shipped

FR15 ("`infra-validation.yml` is not modified" — the review round modified it), FR5 (a three-binary
tooling list that was already five), and FR14 (tooling pinned AFTER Guard 4).

**None was machine-asserted, so nothing could red.** A prose AC that contradicts the tree is
invisible to every gate and ships as a true-looking record.

FR14 was not merely stale — **the planned order was itself a fail-open.** The live-hash step calls
`sha256sum` before Guard 4, so at FR14's position the gate would have hashed the template with an
unchecked binary: P1 #3 (`find` absent from the list) one step further along. The suite pinned the
TOKEN and not the POSITION, which is why it drifted silently. `T1-ORDER` now pins it.

### 3. The full battery found two that no file-selected suite could return

`TEST_GROUP=all` → 457/465. `lint-trap-tempfile-ownership` (this PR's new `mktemp`, whose
escape-hatch marker sat outside `escaped()`'s one-line window) and `battery-tag-authorship` (the
probe's `git fetch` without `--no-tags`; the line predates this PR, but registering the probe's
suite pulled the file into the battery closure).

**A repo-global ratchet references no changed file, so no file-based suite query can ever return
it.** The gate's own suite read 236/0 throughout. This is the argument for the unsharded battery
being non-negotiable at ship, and it is not a matter of diligence: the selection is *correct* and
still structurally blind.

### 4. CI found one that no local run could reproduce

`R14-control` needed NO bearer in play and took that from the ambient environment. On a workstation
neither `GH_TOKEN` nor `GITHUB_TOKEN` is set, so the premise held by accident; CI exports
`GITHUB_TOKEN`, so the gate HAD a credential to drop, retried the one-shot 401 anonymously, and
RELEASED — precisely the "passes against an implementation that ignores a 401" outcome the control
exists to reject. 236/0 locally, 235/1 in CI.

**An arm whose premise is ambient is not a control. It is a coin flip that lands the same way on the
machine where it was written**, and it fails first on the machine that matters. The row now clears
both variables, restores them, and FAILS BY NAME if the clear did not take.

### 5. And preflight found the Observability block's own probe could not run

`discoverability_test.command` named the 236-assertion suite with a prose `expected_output`. Check 10
executes the declared command in a bubblewrap sandbox under a 15 s cap: killed at `rc=124` with arms
still passing, and no matcher can compare stdout to a sentence. **A declared verification that cannot
run where it is consumed verifies nothing** — this plan's own thesis, applied to its own plan.

## Session Errors — the ship round

1. **Ran `sync-pr-behind.sh 8393` by absolute path from a different worktree.** The script derives
   its repo root from its OWN location and ignores the PR argument for branch selection, so it
   merged `main` into my branch and pushed it. No damage (that sync was owed anyway) but #8393 went
   unsynced while I believed it had.
   **Prevention:** a script that takes an identifier as an argument does not necessarily ACT on it.
   Run repo-scoped scripts from the worktree they are meant to act on, and verify the push line names
   the branch you intended.
2. **Merged `main` into a STALE local worktree** for #8393 (`d7b279c39` vs the PR head
   `79dc3b433`); the push was rejected as non-fast-forward.
   **Prevention:** `git fetch <branch>` + `git reset --hard origin/<branch>` before syncing a branch
   whose worktree this session did not create.
3. **Launched the full battery before the tree was final.** The AC sweep then forced an edit, so the
   queued run was killed and relaunched.
   **Prevention:** the AC sweep is a tree-changing step — run it BEFORE starting the battery, not in
   parallel with it.
4. **`bunx vitest` on a `bun:test` suite** → "2 failed, no tests", read as a real failure for one
   cycle. Already recorded in the body above; it recurred in the same session.
   **Prevention:** it is in this very file. Check the suite's import before choosing the runner.
5. **`ls … && python3 lint.py` short-circuited** so a Python lint ran under `bash`, producing syntax
   errors that looked like a broken lint.
   **Prevention:** never gate an interpreter invocation on an `ls` whose success also selects the
   interpreter.
6. **Read UTC CI timestamps as local time** and briefly concluded I was looking at a stale run.
   **Prevention:** compare `date -u` against the log's `Z` stamps before concluding a run is stale.
7. **A monitor filter excluded uppercase `EXPECTED` only**, so self-tests labelled "expected" in
   lowercase were reported as new failures.
   **Prevention:** when a suite self-labels expected failures, discriminate on the suite-level shape
   (`^\[FAIL\] <path> (<N>ms)$`), never on prose.
8. **Diagnosed a red `deploy-script-tests` before establishing which tree it described.** A
   `pull_request` check runs against `refs/pull/N/merge`, not the branch head; on a fast-moving
   `main` those differ, and the red described a tree that no longer existed. Confirmed by testing all
   three — `main`, the head, and the live merge ref — all 113/0. It cleared on re-run.
   **Prevention:** before treating a `pull_request` check as a verdict on your branch, fetch
   `refs/pull/N/merge` and test THAT tree.

## Prevention (workflow-level)

- **Budget the ship round as a review round.** Eleven defects surfaced after a nine-seat panel
  signed off. The panel was not deficient — it read the diff, and these live in the interaction
  between the diff and an environment (an exported token, a repo-global ratchet, a sandbox cap, a
  merge ref).
- **When a fix adds a consumer, re-derive the producer's capability claim.** The gate's parity
  comment was true when written and false by the time the probe shipped.
- **Pin the POSITION, not just the TOKEN, wherever ordering is load-bearing.** `T1` asserted a
  missing binary is reported and said nothing about when; the when was the fail-open.
