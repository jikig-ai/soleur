---
title: "fix(ship): phase-7 poll block's BEHIND auto-sync reports a failed git merge as pushed — capture rc before tail"
type: fix
date: 2026-09-19
slug: fix-ship-phase-7-poll-block-pipe-rc
branch: feat-one-shot-8339-poll-block-pipe-rc
issue: 8339
closes: 8339
priority: P2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(ship): phase-7 poll block's BEHIND auto-sync reports a failed `git merge` as pushed — capture rc before `tail`

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `knowledge-base/project/specs/feat-one-shot-8339-poll-block-pipe-rc/spec.md` exists on this one-shot branch.)

## Enhancement Summary

**Deepened on:** 2026-09-19
**Sections enhanced:** Proposed Solution, Technical Considerations, Observability, Guard Contract, Acceptance Criteria, Test Scenarios, Research Insights
**Research agents used:** test-design-reviewer, observability-coverage-reviewer, architecture-strategist, git-history-analyzer, legacy-code-expert, security-sentinel, spec-flow-analyzer, pattern-recognition-specialist, best-practices-researcher (plus the v1→v2 plan-review panel: DHH, Kieran, code-simplicity, CTO; and the ADR-083 advisor consult)

### Key Improvements

1. **A data-loss path the fix would have made reachable is closed.** Once the conflict arm is live, `git merge --abort` would also fire when `MERGE_HEAD` already existed (operator mid-resolution → `git merge` rc 128), resetting their staged work (security-sentinel P1 + spec-flow P0, both measured). The arm now checks `MERGE_HEAD` *before* merging and stops without touching an in-progress merge (scenario 6c).
2. **A non-conflict merge refusal (rc 2 dirty tree / untracked overwrite, rc 128) is told the truth.** No `MERGE_HEAD` after failure → "refused to start (not a conflict, nothing to abort)" + bounded `git status --short`, instead of an empty "Conflicted paths:" and a swallowed `--abort` failure (spec-flow P1, observability P2; scenario 6b).
3. **The fixture can express AND.** `run_scenario`'s single `must_match` ERE made mutation rows 3/4 vacuous (three agents, measured); it becomes a newline-separated list. Scenario 9 characterizes the success path (re-fetch + `pushed` line) so the `if/elif`→nested refactor cannot silently drop the re-fetch (legacy-code P1, measured with two mutants).
4. **Mock state crosses `$( )` via files, not variables** — for `git` AND `gh` (scenario 4b's `_dirty_seen` counter never flips today; measured). `MERGE_HEAD` is modelled as a file the merge mock creates and `--abort` removes.
5. **`fetch_failures=N/6` on the `behind_exhausted` line** so six fetch outages do not print "main moving faster than CI" (observability P2 under `hr-observability-as-plan-quality-gate`, second independent signal after CTO P2 → applied; DC-3 closed).

### New Considerations Discovered

- The fence also runs hosted: `apps/web-platform/server/inngest/functions/event-ship-merge.ts` spawns `claude --print … "Run /soleur:ship --headless"`; its failure reaches Sentry only via the bounded `stdoutTail` when the ship run exits non-zero. Layer-7 citation updated.
- Git-history corrections: the fixture was introduced by PR #4388 (commit `873ca0e49`) and de-orphaned by PR #4807 (commit `2e8797455`, header cites issue #4387); the piped chain entered ship in `a64161271` (PR #3984, 2026-05-19) and the mirror's `&&` chain in `873ca0e49` (PR #4388, six days later); #7828's rule landed in `96d8501fa`. PR #8320 merged 2026-09-18T23:08Z (2026-09-19 01:08 local).
- Grok's prescribed BEHIND path is `sync-pr-behind.sh` (`behindSyncInstructions("grok")`), not the fence; the `merge conflict` wake-pattern alignment is a bonus for a Grok that pastes the fence by hand, not a load-bearing contract.
- `printf '%s\n' "$sync_out"` is the safe display form (`echo "$sync_out"` eats a leading `-n`; measured). `$(…)` strips trailing newlines only; `tail -N` shows the same logical lines.

## Overview

The Phase 7 poll block that `soleur:ship` (canonical, inside the `<!-- phase-7-poll-block:start -->` fence) and `soleur:merge-pr` §5.2 (derived mirror) prescribe for the merge boundary has a BEHIND auto-sync arm whose three guards — `git fetch`, `git merge origin/main`, `git push` — are each piped through `| tail -N` for display. The `if`/`elif` tests read the pipeline's exit status, which is `tail`'s (always 0), so none of the three failure branches can ever be taken in the Monitor shell (which runs with `pipefail` off — measured: `bash -c 'set -o | grep pipefail'` prints `pipefail off`). A conflicting merge is therefore reported as "auto-sync N pushed", the worktree is left mid-merge with `MERGE_HEAD` present, and the remaining sync attempts are burned re-running `git merge` on an already-conflicted tree until the loop prints a `behind_exhausted` diagnosis for a condition that does not exist. Measured on PR #8320 (2026-09-18T23:03Z).

This plan captures the exit status of each of the three commands explicitly (not via `set -o pipefail`, which would change the semantics of every other pipe in a block that two skills copy), displays the captured output through `tail` afterwards, refuses to touch a merge that was already in progress, tells the truth when a merge is refused rather than conflicted, lands the identical sync arm in both the canonical block and the mirror, and adds RED-first fixtures to `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`.

**Load-bearing finding from plan-time prototyping (not in the issue):** the fixture harness sets `set -uo pipefail` at file scope, and the scenario subshell in `run_scenario` inherits it. Under `pipefail`, the *buggy* block takes the correct branch — so a fixture written naively against the harness as it stands today is GREEN on the defect it exists to catch. Verified in the scratchpad: with pipefail ON, the current block passes the new scenarios; with pipefail OFF (Monitor semantics), the current block fails them and the fixed block passes them. The scenario subshell must therefore run `set +o pipefail`, and the suite needs a self-check row proving it does.

## Problem Statement / Motivation

From #8339 (measured on PR #8320):

```text
23:03:20 [2/60] BEHIND detected — auto-sync attempt 1/6
Auto-merging plugins/soleur/skills/review/SKILL.md
Automatic merge failed; fix conflicts and then commit the result.
Everything up-to-date
23:03:26 [2/60] auto-sync 1 pushed
```

Inspected immediately after: `MERGE_HEAD` present, two paths in `--diff-filter=U`, remote head unchanged. Cause, in `plugins/soleur/skills/ship/SKILL.md` (fence, BEHIND arm):

```bash
    if ! git fetch origin main 2>&1 | tail -2; then
      ...
    elif ! git merge origin/main --no-edit 2>&1 | tail -5; then
      ...   # conflict branch: --abort + break — UNREACHABLE
    elif ! git push 2>&1 | tail -2; then
      ...   # "git push failed after merge" — UNREACHABLE
    else
      echo "... auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate"
```

The mirror in `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 has the same three pipes collapsed into one `&&` chain (`if git fetch … | tail -2 && git merge … | tail -5 && git push … | tail -2; then`) — same dead guard, and its single `else` arm conflates a fetch failure (which the canonical block treats as "skip this attempt") with a merge conflict (abort + stop). History: the chain entered ship in `a64161271` (PR #3984, 2026-05-19); the mirror's `&&` form entered in `873ca0e49` (PR #4388, 2026-05-25); neither was ever a non-piped form.

This is the `cmd | tail` shape `work/SKILL.md` already forbids from #7828 (commit `96d8501fa`: "never pipe a command whose exit code IS the result"), now measured inside the block that `ship` and `merge-pr` prescribe for the merge boundary.

## Proposed Solution

**Explicit rc capture, then display** — the issue's proposed form, applied to all three commands, in both blocks. Not `set -o pipefail`: that changes every other pipe in the block (`echo "$s" | grep -qE … && break`, `printf … | grep '^CONFLICT '`) and anything a later edit adds, in a block two skills copy and an LLM pastes into a Monitor.

Two guards the deepen pass added because the fix makes new paths reachable for the first time: a `MERGE_HEAD` precondition (never abort a merge this arm did not start) and a post-failure `MERGE_HEAD` branch (conflict vs. refused-to-start). Both were measured in a bare-origin repo: pre-existing `MERGE_HEAD` → `git merge` rc 128 and an unconditional `--abort` reverts a staged resolution; dirty tracked file / untracked overwrite → rc 2 with no `MERGE_HEAD`, `--abort` rc 128 "There is no merge to abort".

Replacement for the sync arm (canonical block; the mirror gets the same lines and keeps its own success echo `auto-sync ${behind_syncs}/${MAX_BEHIND_SYNCS} pushed`). `fetch_fails=0` is initialised on the line after the `prev=""; i=0; …` fingerprint line (never on it), and the `behind_exhausted` echo gains `(fetch_failures=${fetch_fails}/${MAX_BEHIND_SYNCS})` after `in ${elapsed}s`:

```bash
    # Capture each command's rc BEFORE displaying through `tail`: `cmd | tail`
    # returns tail's status (0), so `if ! cmd | tail` can never take its
    # failure branch (#8339). Explicit capture, not `set -o pipefail` — that
    # would change every other pipe in a block two skills copy. No `local`
    # prefix on the assignment: `local x=$(cmd)` would clobber $? with local's 0.
    if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      echo "[ship.phase7.sync_failed] kind=merge_in_progress — MERGE_HEAD exists on $BRANCH; not touching an in-progress merge. Stopping the poll."
      break
    fi
    sync_out="$(git fetch origin main 2>&1)"; sync_rc=$?
    printf '%s\n' "$sync_out" | tail -2   # display only — never test this pipe
    if (( sync_rc != 0 )); then
      fetch_fails=$((fetch_fails+1))
      echo "[ship.phase7.sync_failed] kind=fetch rc=$sync_rc — fetch origin main failed — skipping this sync attempt"
    else
      sync_out="$(git merge origin/main --no-edit 2>&1)"; sync_rc=$?
      printf '%s\n' "$sync_out" | tail -5
      if (( sync_rc != 0 )); then
        if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
          echo "[ship.phase7.sync_failed] kind=merge rc=$sync_rc — git merge origin/main failed — merge conflict, aborting sync. Conflicted paths:"
          git diff --name-only --diff-filter=U
          git merge --abort 2>&1 || echo "git merge --abort failed (rc=$?)"
          echo "Manual conflict resolution required on $BRANCH. Stopping the poll."
        else
          echo "[ship.phase7.sync_failed] kind=merge_refused rc=$sync_rc — git merge origin/main failed — refused to start (not a conflict, nothing to abort). Worktree state:"
          git status --short | head -20
          echo "Clear the worktree state on $BRANCH shown above, then re-run. Stopping the poll."
        fi
        break
      fi
      sync_out="$(git push 2>&1)"; sync_rc=$?
      printf '%s\n' "$sync_out" | tail -2
      if (( sync_rc != 0 )); then
        echo "[ship.phase7.sync_failed] kind=push rc=$sync_rc — git push failed after merge — auto-sync incomplete; the local merge commit is retained, nothing was aborted. Stopping the poll."
        break
      fi
      echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate"
      # (existing re-fetch of $s + MERGED/CLOSED break stays here, unchanged)
    fi
```

Notes on the shape (as shipped after the review panel — the block above is the v3 plan text; the review added the items marked ★):

- ★ **Capture form is `sync_rc=0; sync_out="$(cmd)" || sync_rc=$?`**, not the bare `x="$(cmd)"; rc=$?` above: a bare assignment's status IS the substitution's, so under an errexit host shell (a `set -euo pipefail` wrapper, `sync-pr-behind.sh`'s own style) the bare form kills the shell at the `git merge` assignment before `--abort` runs — the #8339 outcome by another route. Scenario 6f pins this under `set -e`.
- ★ **The precondition covers the whole sequencer set and detached HEAD** (`MERGE_HEAD`, `rebase-merge/`, `rebase-apply/`, `CHERRY_PICK_HEAD`, `REVERT_HEAD` under `--git-dir`; `symbolic-ref -q HEAD`), and the **abort is gated on `sync_rc == 1`** (git's documented conflict status): any other rc with `MERGE_HEAD` present is a merge that appeared during the fetch window (operator-started) and is reported as `merge_in_progress rc=N`, never aborted. Measured on real git: a rebase/cherry-pick conflict is `rc 128` with no `MERGE_HEAD` and was being described as "not a conflict, nothing to abort".
- ★ **Every tagged exit line is on stdout.** The Monitor tool streams stdout only (stderr lands in the output file and raises no notification), and ship arms the block without `2>&1` — so the pre-existing `>&2` on `required_failed` / `dirty` / `behind_exhausted` made those exits notification-invisible. The fixture captures stderr separately and asserts no `[ship.phase7.*]` line lands there.
- ★ **`behind_exhausted` branches on `fetch_failures == MAX_BEHIND_SYNCS`** (network/credential outage) vs the fast-moving-main recommendation; the DIRTY arm's classifying fetch failure is reported as `kind=fetch … retrying next tick` instead of a dirty exit; the worktree precondition compares `--is-inside-work-tree`'s OUTPUT to `true` (it prints `false` rc 0 in a bare repo) and sets `sync_ok=0`, which actually gates the arm.
- ★ `GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0` on the three git calls (a tracing session would put the credential-bearing remote URL into `sync_out`); the conflict branch also prints the merge output's `CONFLICT` lines (`rerere.autoupdate` can stage the resolution and empty `--diff-filter=U`); the same precondition landed in `plugins/soleur/scripts/sync-pr-behind.sh` (exit 9) with a real-git row.

- `var="$(cmd)"; rc=$?` — the assignment's status is the command substitution's status, so `$?` is `cmd`'s rc (BashFAQ/002; `local`/`export` prefixes clobber it, hence the comment). Same idiom the DIRTY arm already uses (`mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"`). Verified under `set -u; set +o pipefail` with the scenario mocks: every branch above is taken as designed; `bash -n` clean.
- All new failure lines go to **stdout** (the Monitor tool streams stdout only; the block's older tagged exits use `>&2` and are therefore not notification events — a pre-existing property this plan does not change). The `[ship.phase7.sync_failed] kind=… rc=…` prefix makes the four new exits greppable with the block's existing `[ship.phase7.<tag>]` grammar; the issue's verbatim substrings — `fetch origin main failed`, `git merge origin/main failed`, `Manual conflict resolution required`, `git push failed after merge` — are kept intact inside the lines.
- The conflict line contains the literal `merge conflict`; the Grok `AwaitShell` wake pattern in `plugins/soleur/lib/pr-merge-poll.ts` (`BEHIND detected|auto-sync.*pushed|BEHIND resolved|BEHIND unchanged|merge conflict`) matches it. This is bonus alignment: Grok's prescribed BEHIND path is `sync-pr-behind.sh` (`behindSyncInstructions("grok")`, `pr-merge-poll.ts:60-72`), and `pollInstructions()` (`harness.ts:323-395`) embeds no fence text. The `merge_refused`/`push`/`merge_in_progress` lines match no wake alternation; each is followed by `break`, which ends the shell, and AwaitShell returns on exit.
- Success lines are unchanged in both blocks (ship: `auto-sync ${behind_syncs} pushed — auto-merge will re-evaluate`; merge-pr: `auto-sync ${behind_syncs}/${MAX_BEHIND_SYNCS} pushed`). Both match `auto-sync.*pushed` and the fixture regex `auto-sync [0-9/]+ pushed`.
- `git merge --abort 2>&1 || echo …` replaces `2>/dev/null`: with the `MERGE_HEAD` branch the abort should always succeed, so a failure is now a printed anomaly rather than a swallowed one (`cq-silent-fallback-must-mirror-to-sentry`, bash analogue). The mock sentinel is read on stdout, so this does not affect scenario 6.
- Nesting replaces the `if/elif/elif/else` chain because each step's rc has to be captured *before* the next step runs; a helper function (`_tail_rc N cmd…`) would keep the chain flat but adds a name to the Monitor shell's namespace and one more thing for the mirror to drift on. Rejected on the minimalism ladder.
- **Alternative considered — `git -q` on all three commands and drop `tail` entirely** (DHH plan-review P0, measured: `-q` silences success output, keeps `CONFLICT`/`error:` lines and the rc). Not adopted: the operator's stated mechanism for #8339 is "capture the rc explicitly, then display via tail", `-q` drops the `Auto-merging <path>` / `Merge made by …` lines the operator reads in the stream, and the `MERGE_HEAD`/refused branches are needed either way. Recorded as DC-1 in `knowledge-base/project/specs/feat-one-shot-8339-poll-block-pipe-rc/decision-challenges.md`.
- **Deferred (P2, spec-flow row 3):** `git merge` → `Already up to date.` + `git push` → `Everything up-to-date` (both rc 0, HEAD unchanged) still prints `auto-sync N pushed` and burns an attempt. Tracked on #8383 with the consolidation; not folded here because it changes the success line every consumer keys on.

### Files to Edit

1. `plugins/soleur/skills/ship/SKILL.md` — inside the `<!-- phase-7-poll-block:start -->` … `:end` fence only: the BEHIND arm (currently the `if ! git fetch … | tail -2` / `elif … | tail -5` / `elif … | tail -2` / `else` chain), `fetch_fails=0` on the line after the `prev=""; …` line, and the `behind_exhausted` echo's `(fetch_failures=…)` suffix. Nothing else in the file: the fence comment header, the `MAX_POLL_MIN` derivation, the required-check scan, the DIRTY arm, and the incident-PIR gate (§5.5, `OUTAGE_RE`, tracked separately by #8334) are all out of scope.
2. `plugins/soleur/skills/merge-pr/SKILL.md` — §5.2, inside its `<!-- phase-7-poll-block:start --> mirror` fence: same three edits (arm, `fetch_fails=0`, `behind_exhausted` suffix), keeping merge-pr's own success echo and re-fetch. Also update the §5.2 prose sentence "this mirror is not directly tested" — after this plan scenarios 3/6/6b/6c/7/8/9 run against the mirror too.
3. `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — see Technical Considerations and Guard Contract. The fence-anchored `extract_block()` awk and the three-token fingerprint loop are NOT modified; the header comment (lines 1–11, "five scripted scenarios") is updated to list the new rows.

### Files to Create

None.

## Technical Considerations

- **The harness must reproduce the Monitor shell's option set.** `run_scenario` gains `set +o pipefail` as the first statement of its `( … )` subshell (the subshell scopes it; the file-level `set -uo pipefail` still governs the harness's own bookkeeping). All 18 existing assertions were re-run with this change plus the v3 block in the scratchpad: 18 pass. `errexit` is not asserted: the harness never sets `-e`, and if it ever did, `sync_out="$(git merge …)"` would exit the subshell before the sentinel and the live rows would redden on their own.
- **`must_match` becomes a newline-separated list, one `pass`/`fail` line per pattern.** The current single `grep -qE "$must_match"` cannot express AND; written as an alternation, mutation rows 3 and 4 stay GREEN on the mutant (measured by three agents). Replace the must-match branch with `while IFS= read -r pat; do [[ -z "$pat" ]] && continue; if grep -qE "$pat" "$logfile"; then pass "[$label] matched: $pat"; else fail "[$label] did NOT match: $pat (rc=$rc)"; <dump>; fi; done <<< "$must_match"`. Existing single-pattern callers are unchanged. Labels of dual-block rows carry the block: `6-merge-conflict-in-sync:ship` / `:merge-pr`.
- **The self-check mocks file must be written with a QUOTED heredoc.** Every existing mocks file uses an unquoted `<<EOF`, which expands `$?` at file-creation time in the harness shell — a self-check body written that way literally contains `echo "harness-pipefail-status=0"` and passes regardless of the subshell's options (Kieran plan-review, verified). Use `<<'EOF'` (or escape `\$?`).
- **Both blocks get scenario coverage.** `run_scenario` takes the block file as a 5th argument (`local block="${5:-$BLOCK_FILE}"`); the mirror extraction gains the same `sed 's/<number>/4387/g'` the canonical extraction has (sourced verbatim, `gh pr view <number>` parses `<number>` as an input redirect and `$s` degrades to `fetch-error:` on tick 1 — needed for execution, not for `bash -n`, which the mirror already passes). The behavioural proof that the mirror is actually executed is scenario 3 run against `$MIRROR_FILE` with must-match `auto-sync 6/6 pushed` and must-not-match `auto-sync 6 pushed` — a discriminator the canonical block cannot produce.
- **Mock state must cross `$( … )` via files, for `git` AND `gh`.** The block runs `gh pr view` and all three sync commands inside command substitutions, so a shell-variable counter set inside a mock is lost (measured: scenario 4b's `_dirty_seen=1` never flips; the row passes on the "DIRTY forever" path — `behind_exhausted` is printed — not the "DIRTY once, then BLOCKED" path it documents). Each scenario exports `MOCK_STATE="$(mktemp -d)"` (created and removed by `run_scenario`) and mocks touch/remove files in it. Fix 4b in the same commit: the `gh` mock flips on `[[ -e "$MOCK_STATE/dirty_seen" ]]` and the row gains `ship\.phase7\.behind_exhausted` in its must-not-match (RED today, GREEN once state actually flips — the proof the mock carries state).
- **One shared `git` mock for scenarios 6/6b/6c/7/8/9 with per-scenario knobs**, so every forbid (`MOCK: git merge --abort observed` in 7/8/9) is on a sentinel the mock can actually emit. Dispatch on `"$1 ${2:-}"` with these cases, in this order (the `rev-parse -q` case MUST precede the `rev-parse *` glob, or `git rev-parse -q --verify MERGE_HEAD` answers "test-branch" rc 0 and the precondition always fires):
  - `"rev-parse -q") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] ;;`
  - `"rev-parse "*) echo "test-branch" ;;` (covers `--abbrev-ref HEAD`, which AC2's regex hard-codes, and `--is-inside-work-tree`)
  - `"fetch origin") (( ${MOCK_FETCH_RC:-0} )) && echo "fatal: unable to access 'origin'"; return "${MOCK_FETCH_RC:-0}" ;;`
  - `"merge origin/main")` — `case "${MOCK_MERGE:-ok}"`: `ok` → `Merge made by the 'ort' strategy.`; `conflict` → `CONFLICT (content): Merge conflict in foo.md` + `Automatic merge failed; …`, `: > "$MOCK_STATE/MERGE_HEAD"`, `return 1`; `refused` → `error: Your local changes would be overwritten by merge.`, `return 2` (no `MERGE_HEAD`).
  - `"merge --abort") echo "MOCK: git merge --abort observed"; rm -f "$MOCK_STATE/MERGE_HEAD" ;;` — sentinel on **stdout** (a stderr sentinel would have been swallowed by the old `2>/dev/null`; keep it on stdout regardless).
  - `"diff --name-only") [[ -e "$MOCK_STATE/MERGE_HEAD" ]] && echo "foo.md" ;;` (state-dependent, so 6b's empty list is expressible)
  - `"status --short") echo " M f" ;;`
  - `"push "|"push") (( ${MOCK_PUSH_RC:-0} )) && echo "error: failed to push some refs to 'origin'" || : > "$MOCK_STATE/pushed"; return "${MOCK_PUSH_RC:-0}" ;;` (bare `git push` has no `$2`; `${2:-}` is required under `set -u`)
  - `*) return 0 ;;`
  - `gh() { "pr view") [[ -e "$MOCK_STATE/pushed" ]] && echo "MERGED CLEAN" || echo "OPEN BEHIND" ;; … }` — flips after a push was observed, which scenario 9 needs.
- **The default `git` mock in `run_scenario` must also answer `rev-parse -q` with rc 1** (`rev-parse) [[ "${2:-}" == "-q" ]] && return 1; echo "test-branch" ;;`), or scenarios 3 and 4b (which use the default mock and reach the BEHIND arm) would trip the new `merge_in_progress` precondition. Measured: with this one-line change the existing 18 assertions pass against the v3 block.
- **`break` must be observed, not inferred.** With `gh pr view` stubbed to `OPEN BEHIND` and `sleep` a no-op, a block that does not `break` runs to `behind_exhausted` and then `Merge poll timed out` inside a second. Every stopping scenario forbids `ship\.phase7\.behind_exhausted|Merge poll timed out`; scenario 9 forbids `\[2/60\]` (the re-fetch saw MERGED and broke before tick 2).
- **Anchor `merge conflict` to the new line, not as a bare token** (`cq-assert-anchor-not-bare-token`): the DIRTY arm already prints `[ship.phase7.dirty] PR is DIRTY (merge conflict)`. Scenario 6 must-matches `git merge origin/main failed — merge conflict, aborting sync\. Conflicted paths:` and `kind=merge rc=1` — the latter also makes mutation row 7 (ORDER) observable by value (`rc=0` in the dump).
- **Grok harness.** Nothing in the fix uses a bashism beyond what the block already uses (`(( ))`, `mapfile` — bash 4+, pre-existing); no `harness.ts` change. No TS test asserts on sync-arm text (`harness.test.ts`, `pr-merge-poll.test.ts`, `workflow-fidelity.test.ts` assert on prose tokens and `sync-pr-behind.sh` only).
- **Real exit codes, measured 2026-09-19 in a throwaway bare-origin repo (git 2.x):** content conflict → rc 1 with `MERGE_HEAD`; `--abort` → `MERGE_HEAD` gone; pre-existing `MERGE_HEAD` → rc 128 `You have not concluded your merge`; dirty tracked file or untracked-would-be-overwritten → rc 2, no `MERGE_HEAD`, `--abort` rc 128; `git fetch origin <missing-ref>` → rc 128; `git push` with no upstream → rc 128. The arm tests `!= 0` and then branches on `MERGE_HEAD`, so every non-zero code lands in a truthful branch.
- **`git merge-tree --write-tree` ignores the worktree**, so the DIRTY→BEHIND fallthrough reports "clean" in exactly the cases where the real `git merge` then refuses with rc 2 — this repo's root currently carries ~40 untracked files, so the refused branch is live, not theoretical.
- **`plugins/soleur/scripts/sync-pr-behind.sh` has the same three `| tail` pipes but runs under `set -euo pipefail` (line 10), so its guards DO see the git rc.** Not a defect; it is the third copy of this arm (#8383). Repo-wide sweep (pattern-recognition): no other `if … | tail` verdict pipe exists outside the two fences without `pipefail`; `plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh:71` has the shape under `pipefail` (safe).

## User-Brand Impact

- **If this lands broken, the user experiences:** a `soleur:ship` / `soleur:merge-pr` Monitor stream that either still prints "auto-sync N pushed" over a conflicted worktree (regression of the bug), a poll that stops on a non-failure (over-correction), or — the newly reachable case — an `--abort` that discards their in-progress conflict resolution. No end-user surface of the web platform is touched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the same bytes (stdout+stderr via `2>&1`) reach `tail -N` in both shapes (measured byte-identical); git already anonymizes credentials in `fatal: unable to access` URLs; `sync_out` lingers only as an unexported shell variable.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the diff touches only two SKILL.md bash blocks and their bash fixture; no auth, payment, migration, or customer-data path is read or written.`

## Observability

The defect *is* an observability defect (a verdict line that could not be believed), so the section is written even though the touched files are skill prose plus a test.

```yaml
liveness_signal:
  what: "ship-phase-7-poll-fixtures.test.sh scenarios 6/6b/6c/7/8/9 (both blocks), scenario 3 on the mirror, and the pipefail self-check row — executed on every PR in the `scripts` group of scripts/test-all.sh (plugins/soleur/test/*.test.sh glob, line 78)"
  cadence: "per PR / per push to main"
  alert_target: "red `test-scripts` required check on the PR"
  configured_in: "scripts/test-all.sh (SUITE_GLOBS) + .github/workflows/ci.yml matrix job"

error_reporting:
  destination: "layer 7 (customer-hosted CLI, cli-stdout-artifact): the Monitor stream itself is the only channel on the CLI surface and the fix makes its failure lines reachable (`hr-observability-layer-citation`). Hosted path: apps/web-platform/server/inngest/functions/event-ship-merge.ts spawns `claude --print … /soleur:ship --headless`; there the block's line reaches Sentry only inside the bounded reportSilentFallback extra.stdoutTail when the claude-eval exits non-zero (layer 1 sentry-correlation on the Inngest fn) — a poll `break` alone does not make that exit non-zero"
  fail_loud: "`[ship.phase7.sync_failed] kind=merge|merge_refused|merge_in_progress|push rc=N — …` followed by `Stopping the poll.`; the loop exits instead of printing `auto-sync N pushed`"

failure_modes:
  - mode: "merge conflict during BEHIND auto-sync"
    detection: "captured `sync_rc != 0` after `git merge` AND `MERGE_HEAD` present; conflicted paths printed from `git diff --name-only --diff-filter=U`, then `git merge --abort` (its failure printed, not swallowed) and `break`"
    alert_route: "Monitor notification line (layer 7, cli-stdout-artifact) + loop exit"
  - mode: "merge refused to start (dirty tracked file, untracked overwrite, unrelated histories) — rc 2/128, no MERGE_HEAD"
    detection: "captured `sync_rc != 0` after `git merge` AND `MERGE_HEAD` absent; `kind=merge_refused` + bounded `git status --short | head -20`; no `--abort`, no `--diff-filter=U`"
    alert_route: "Monitor notification line (layer 7) + loop exit"
  - mode: "a merge was already in progress when the arm ran (operator mid-resolution)"
    detection: "`git rev-parse -q --verify MERGE_HEAD` before the merge; `kind=merge_in_progress`; nothing is aborted"
    alert_route: "Monitor notification line (layer 7) + loop exit"
  - mode: "push rejected after a clean merge (non-fast-forward, protected ref, auth, no upstream)"
    detection: "captured `sync_rc != 0` after `git push`; `kind=push rc=N`; the local merge commit is retained and the line says so"
    alert_route: "Monitor notification line (layer 7) + loop exit"
  - mode: "fetch failure (network / auth)"
    detection: "captured `sync_rc != 0` after `git fetch`; `kind=fetch rc=N — skipping this sync attempt`; `fetch_fails` incremented; the attempt is counted and the loop continues; after 6, `behind_exhausted` carries `fetch_failures=6/6` so a fetch outage is not read as 'main moving faster than CI'"
    alert_route: "Monitor notification line (layer 7); `behind_exhausted` with the fetch_failures discriminator"
  - mode: "the fix regresses in either block (a future edit re-introduces `git X | tail` inside a conditional)"
    detection: "scenarios 6/6b/6c/7/8 run against both extracted blocks under `set +o pipefail`; any dead guard prints `pushed` and reddens `test-scripts`"
    alert_route: "red required check on the PR"

logs:
  where: "Monitor tool notification stream of the ship/merge-pr session (Claude Code) or AwaitShell output (Grok Build); durable post-session readback (the stream line is not the only evidence): `git rev-parse -q --verify MERGE_HEAD` rc 1, `git status --porcelain` empty, `origin/<branch>` SHA unchanged, PR still `OPEN BEHIND` — the observables scenario 10 (real git) asserts"
  retention: "session transcript lifetime; the git-state readback persists in the worktree"

discoverability_test:
  command: "bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh"
  expected_output: "ship-phase-7 fixture: N pass, 0 fail (N ≥ 18 + the rows this plan adds), including `pass: [6-merge-conflict-in-sync:ship] matched: MOCK: git merge --abort observed`, the `:merge-pr` twin, `pass: [9-success-path:ship] …`, `pass: [10-real-git-conflict] MERGE_HEAD absent after abort`, and `pass: [0-harness-pipefail-off] matched: harness-pipefail-status=0`"
```

## Guard Contract

### Guard 1 — BEHIND sync-arm branches are reachable and truthful (scenarios 6/6b/6c/7/8/9 on both blocks, 10 on real git)

**Property.** In the Phase 7 poll block as sourced by a shell with `pipefail` off: a non-zero `git merge` with `MERGE_HEAD` present produces `git merge --abort` and terminates the loop; a non-zero `git merge` without `MERGE_HEAD` reports `merge_refused`, aborts nothing, and terminates; a pre-existing `MERGE_HEAD` reports `merge_in_progress`, aborts nothing, and terminates; a non-zero `git push` reports `git push failed after merge` and terminates; a non-zero `git fetch` skips the attempt, counts it, and continues; a successful sync prints the success line and re-fetches state before the next tick — and `auto-sync … pushed` is never printed on any failure path.

**Assembly.** The BEHIND auto-sync arm of BOTH fenced blocks: `plugins/soleur/skills/ship/SKILL.md` between `<!-- phase-7-poll-block:start -->` and `:end`, and `plugins/soleur/skills/merge-pr/SKILL.md` between its own copies of the same markers. The chokepoint is `extract_block()` in `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — every scenario sources what that awk extracts, so a sync arm outside the fence (the third copy, `plugins/soleur/scripts/sync-pr-behind.sh`, is tracked by #8383) is NOT covered. There are exactly two members; `run_scenario` is parameterized on the block file so the rows run once per member, scenario 3 on the mirror asserts a mirror-only output (`auto-sync 6/6 pushed`), and the mirror-parity token check asserts the member shape did not silently change.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the `git merge` capture in ship's block to `elif ! git merge origin/main --no-edit 2>&1 \| tail -5; then` | RED — 6:ship: `MOCK: git merge --abort observed` missing, `auto-sync 1 pushed` present (measured against the current block) |
| 2 | Revert the `git push` capture to `elif ! git push 2>&1 \| tail -2; then` | RED — 7:ship: `git push failed after merge` missing |
| 3 | Delete the `git merge --abort …` line from the conflict branch | RED — 6: `MOCK: git merge --abort observed` missing (its own must-match line, now that `must_match` is a list) |
| 4 | Delete the `break` after the conflict/refused branches | RED — 6 and 6b: `ship.phase7.behind_exhausted` / `Merge poll timed out` present |
| 5 | Apply the fix to ship's block only; leave merge-pr's `&&` chain | RED — 6/6b/6c/7/8 `:merge-pr` fail as rows 1/2, and parity tokens `sync_out="$(git merge origin/main --no-edit 2>&1)"` / `merge conflict, aborting sync` / `kind=merge_refused` are missing from the mirror |
| 6 | Change the fetch-failure arm to `break` instead of falling through | RED — 8: `behind_exhausted` and `fetch_failures=6/6` missing |
| 7 | Move `sync_rc=$?` one line down (after the `printf … \| tail`) | RED — 6/7/8: `kind=merge rc=1` etc. read `rc=0`; the ORDER row — the property is where the rc is read |
| 8 | Collapse the post-failure `MERGE_HEAD` branch back to an unconditional abort | RED — 6b: `Manual conflict resolution required` present and `MOCK: git merge --abort observed` present (forbidden) |
| 9 | Delete the `MERGE_HEAD` precondition before `git merge` | RED — 6c: `kind=merge_in_progress` missing, abort sentinel present; 10: `git diff --cached --name-only` empty after the run (the staged resolution was discarded) |
| 10 | Delete the post-push re-fetch + `MERGED\|CLOSED` break | RED — 9: `\[2/60\]` present (loop ran a second tick after MERGED) |
| 11 | Change the success echo to `auto-sync 1 synced …` | RED — 9: `\[1/60\] auto-sync 1 pushed — auto-merge will re-evaluate` missing |
| 12 | Drop `fetch_fails=$((fetch_fails+1))` | RED — 8: `fetch_failures=6/6` missing (prints `0/6`) |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Remove `set +o pipefail` from the `run_scenario` subshell | RED — the pipefail self-check row (`false \| true; echo "harness-pipefail-status=$?"`, quoted heredoc) prints `=1`; without this row, rows 1/2/7 would go GREEN on the buggy block (measured) |
| H2 | Drop the `sed 's/<number>/4387/g'` from the mirror extraction | RED — 6:merge-pr sees `fetch-error:` on tick 1 and breaks before the BEHIND arm |
| H3 | Point the mirror rows at `$BLOCK_FILE` (parameter drift) | RED — 3:merge-pr: `auto-sync 6/6 pushed` missing, `auto-sync 6 pushed` present |
| H4 | Write the self-check mocks with an unquoted `<<EOF` heredoc | RED — AC4 requires the row to have been driven RED once by removing `set +o pipefail` before commit; with an unquoted heredoc that RED cannot be produced, which is the tell |
| H5 | Revert `must_match` to a single ERE and join 6's patterns with `\|` | RED — mutation row 3 can no longer redden (AC2 requires one `pass … matched:` line per pattern, ≥ 5 for scenario 6) |
| H6 | Put the `"rev-parse "*` glob before the `"rev-parse -q"` case in the shared mock | RED — 6/7/8/9: `kind=merge_in_progress` printed on tick 1 (precondition always true) |
| H7 | Model `MERGE_HEAD` / `dirty_seen` / `pushed` as shell variables instead of files under `$MOCK_STATE` | RED — 9: `\[2/60\]` present (the `gh` flip never happens); 4b: `behind_exhausted` present |
| P1 | Must-PASS, non-canonical: existing scenarios 1/2/3/4/5 under the new subshell and default-mock change | GREEN — 18/18 existing assertions unchanged (measured against the v3 block) |
| P2 | Must-PASS, non-canonical: scenario 9 on the CURRENT block | GREEN — the success path is unchanged by the bug; scenario 9 is a characterization net, not a defect detector, and is GREEN before and after the edit |

## Acceptance Criteria

- [x] AC1 — RED first, checkable by commit order: in `git log --oneline origin/main..HEAD`, the commit that adds the harness changes and scenarios 0/3:merge-pr/6/6b/6c/7/8/9/10 precedes the first commit that edits either SKILL.md, and that first commit's `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` run ends with `fail` > 0 with 6/6b/6c/7/8 red on both blocks, 9 and the self-check green (the summary line is quoted in the PR body) (`cq-write-failing-tests-before`). *Measured 2026-09-19: 31 pass / 54 fail. 4b was GREEN in that run — its mock fix (file-backed `dirty_seen`) and its new forbid landed in the same commit; the forbid alone was measured red against the pre-branch variable-flag mock (17 pass / 1 fail).*
- [x] AC2 — scenario 6, per block, `must_match` as a newline-separated list: `MOCK: git merge --abort observed`; `git merge origin/main failed — merge conflict, aborting sync\. Conflicted paths:`; `^foo\.md$`; `Manual conflict resolution required on test-branch\. Stopping the poll\.`; `kind=merge rc=1`. Must-not-match: `auto-sync [0-9/]+ pushed|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call`. Scenario 6b (`MOCK_MERGE=refused`): must-match `kind=merge_refused rc=2`; `refused to start`; `^ M f$`; must-not-match the 6 list plus `MOCK: git merge --abort observed|Manual conflict resolution required`. Scenario 6c (`MERGE_HEAD` pre-created in `$MOCK_STATE`): must-match `kind=merge_in_progress`; must-not-match the 6 list plus `MOCK: git merge --abort observed|Manual conflict resolution required|Merge made by`.
- [x] AC3 — scenario 7 (`MOCK_PUSH_RC=1`), per block: must-match `kind=push rc=1`; `git push failed after merge`; must-not-match `auto-sync [0-9/]+ pushed|MOCK: git merge --abort observed|ship\.phase7\.behind_exhausted|Merge poll timed out|UNEXPECTED gh call`. Scenario 8 (`MOCK_FETCH_RC=1`), per block: must-match `kind=fetch rc=1`; `fetch origin main failed`; `ship\.phase7\.behind_exhausted`; `fetch_failures=6/6`; must-not-match `auto-sync [0-9/]+ pushed|MOCK: git merge --abort observed|git push failed after merge`. Scenario 9 (all knobs default), per block: must-match `\[1/60\] auto-sync 1 pushed — auto-merge will re-evaluate` (ship) / `\[1/60\] auto-sync 1/6 pushed` (merge-pr); must-not-match `\[2/60\]|auto-sync attempt 2/|ship\.phase7\.behind_exhausted|Merge poll timed out|MOCK: git merge --abort observed|UNEXPECTED gh call`. Scenario 3 additionally runs against the mirror: must-match `auto-sync 6/6 pushed`, must-not-match `auto-sync 6 pushed`. (Scenarios 6/6b/6c/7/8 are RED on the current block; 3 and 9 are GREEN on both — measured.)
- [x] AC4 — scenario 0 (harness self-check) sources a mocks file written with a QUOTED heredoc whose body is `false | true; echo "harness-pipefail-status=$?"` (plus a `gh` returning `MERGED CLEAN` on tick 1) and asserts `harness-pipefail-status=0`; the PR body quotes the one run where removing `set +o pipefail` made this row print `=1` (rows H1/H4).
- [x] AC5 — the mirror-parity token loop (existing `for token in …` over `$MIRROR_FILE`) gains, on a fresh `\` continuation line: `'sync_out="$(GIT_TRACE=0 git merge origin/main --no-edit 2>&1)" || sync_rc=$?'` (the `|| sync_rc=$?` capture form and the `GIT_TRACE=0` prefix are review additions — see Proposed Solution notes), `'merge conflict, aborting sync'`, `'kind=merge_refused'`, `'kind=merge_in_progress'`, `'git push failed after merge'`, `'fetch_failures='`; the existing tokens are untouched (`git merge --abort` is NOT added — it is already in the pre-fix mirror and cannot discriminate).
- [x] AC6 — `run_scenario` accepts the block file as its 5th argument, iterates a newline-separated `must_match` (one `pass`/`fail` per pattern), creates/removes `MOCK_STATE` per row, and the mirror extraction line carries `sed 's/<number>/4387/g'`; the default `git` mock answers `rev-parse -q` with rc 1; scenario 4b's `gh` flips on `[[ -e "$MOCK_STATE/dirty_seen" ]]` and its must-not-match gains `ship\.phase7\.behind_exhausted`.
- [x] AC7 — `bash -n` is asserted for the mirror file as it already is for the canonical (one added `pass`/`fail` line).
- [x] AC8 — diff scope, one check: `git diff -U0 origin/main -- plugins/soleur/skills/ship/SKILL.md | grep '^@@'` shows hunks only inside the `<!-- phase-7-poll-block:start -->` … `:end` line range (2228–2363 on `origin/main`; recompute after the edit) *plus, after the review panel, the prose that documents the fence (the Phase 7 intro sentence, the "Auto-sync on BEHIND" steps, the "Push failure" bullet, and the stale "15-minute" strings) — a fence whose prose describes a mechanism it no longer uses is the same drift class*; `git diff origin/main -- plugins/soleur/skills/ship/SKILL.md | grep -c OUTAGE_RE` = 0 (the §5.5 incident-PIR gate is untouched, #8334); merge-pr's hunks fall inside its fence (377–465 on `origin/main`) plus the prose at lines 372/374; `plugins/soleur/scripts/sync-pr-behind.sh` (+ its test) gains the same never-touch-an-in-progress-merge precondition (review P2 — the third copy carried the unconditional `--abort`, which #8383's body had wrongly called "correct on its own"); and `git diff origin/main -- plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh | grep -E "^[-+].*(in_block|for token in 'MAX_BEHIND_SYNCS' )"` prints nothing (extractor and fingerprint loop untouched — the trailing quote+space excludes the parity loop's `'MAX_BEHIND_SYNCS=6'`).
- [ ] AC9 — full suite green after the fix: `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` ends `0 fail`, and `TEST_GROUP=scripts bash scripts/test-all.sh` is green (the fixture is picked up by the existing `plugins/soleur/test/*.test.sh` glob — no runner registration change; `scripts/lint-orphan-test-suites.sh` derives its globs from `test-all.sh`).
- [x] AC10 — `scripts/lint-guard-contract.py` passes on this plan file.
- [x] AC11 — Retroactive application as a REPEATABLE suite row, scenario 10 (`10-real-git`), requested in #8339 under `wg-when-fixing-a-workflow-gates-detection`: the suite sources `plugins/soleur/test/test-helpers.sh` at file top (arms the #7833 git-location tripwire — this repo is a linked worktree, so an inherited `GIT_DIR`/`GIT_INDEX_FILE` would make the throwaway `git init` write into the real repo) and builds the fixture under `git_fixture_env`: bare `origin` + clone `a` (`base` on main, `feat` branch editing `f`) + clone `b` (pushes a conflicting `main`), all under `mktemp -d -t ship-phase7-realgit.XXXXXX` (same TMPDIR as `$BLOCK_FILE`; the `-p "$(dirname …)"` form is not provable-absolute to `fixture-scan.py`), never the worktree. The row is its own subshell (not `run_scenario`, so no `git` mock is ever installed — the plan's `REAL_GIT=1` knob was unnecessary), sources the extracted **ship** block in `$tmp/a` with `gh` a marker-file stub (`OPEN BEHIND` then `MERGED`), `sleep`/`date` shadowed, a guarded `cd "$tmp/a" || exit 2`, and asserts: stream must-match `kind=merge rc=1`, `^f$`, `Manual conflict resolution required on feat`; must-not-match `auto-sync [0-9/]+ pushed`; afterwards `git -C "$tmp/a" rev-parse -q --verify MERGE_HEAD` → rc 1, `git -C "$tmp/a" status --porcelain` empty, `origin/main` and `origin/feat` SHAs unchanged from before the run. A second sub-row pre-stages a resolution (`git merge origin/main` → conflict, `echo resolved > f && git add f`) and re-runs the arm: must-match `kind=merge_in_progress`, and `git diff --cached --name-only` is still non-empty afterwards (row 9's real-git observable — the staged work survived; note the PRE-fix arm never reached `--abort` here either, since its pipe swallowed rc 128, so sub-row B discriminates only the naive rc-captured + unconditional-abort fix). *Review additions (PR #8378 panel):* sub-row C rejects the push with a pre-receive hook and asserts `kind=push`, local HEAD advanced to a two-parent merge commit; sub-row D stops a rebase on a conflict and asserts `kind=merge_in_progress`, `rebase-merge` still present, `UU f` still unmerged; sub-row E detaches HEAD and asserts `kind=detached_head`, HEAD unchanged; sub-row A additionally asserts the local HEAD unchanged. The row runs in < 1 s with no network.

## Test Scenarios

Existing scenarios 1, 2, 3, 4, 5 are unchanged in content and must still pass under `set +o pipefail`; 4b is corrected (file-backed `dirty_seen`, `behind_exhausted` forbidden); 3 additionally runs against the mirror.

- **Scenario 0 — harness self-check.** Given a mocks file (quoted heredoc) whose body is `false | true; echo "harness-pipefail-status=$?"` plus a `gh` that returns `MERGED CLEAN` on tick 1, then the output contains `harness-pipefail-status=0`.
- **Scenario 6 — merge conflict in sync (RED on current block).** Given `gh pr view` returns `OPEN BEHIND` until a push is observed, `MOCK_MERGE=conflict` (the merge mock prints the CONFLICT lines, creates `$MOCK_STATE/MERGE_HEAD`, exits 1), `git diff --name-only` prints `foo.md` while `MERGE_HEAD` exists, and `git merge --abort` prints the sentinel on stdout and removes `MERGE_HEAD`, when the block is sourced with pipefail off, then the five AC2 must-match lines are present and neither `pushed` nor `behind_exhausted` nor `Merge poll timed out` appears. Both blocks.
- **Scenario 6b — merge refused, not a conflict (RED on current block).** Given `MOCK_MERGE=refused` (prints `error: Your local changes would be overwritten by merge.`, exits 2, creates no `MERGE_HEAD`), then `kind=merge_refused rc=2`, `refused to start`, and the bounded status line ` M f` are printed; no abort sentinel, no `Manual conflict resolution required`, no `pushed`. Both blocks.
- **Scenario 6c — merge already in progress (RED on current block).** Given `$MOCK_STATE/MERGE_HEAD` exists before the block is sourced, then `kind=merge_in_progress` is printed on tick 1 and the loop exits; no merge is attempted (`Merge made by` absent), no abort sentinel, no `pushed`. Both blocks.
- **Scenario 7 — push fails after clean merge (RED on current block).** Given `MOCK_PUSH_RC=1`, then `kind=push rc=1` and `git push failed after merge` are printed; no `pushed`, no abort sentinel, no `behind_exhausted`. The worktree condition the mocks cannot see — a local merge commit retained, nothing aborted — is stated in the line itself. Both blocks.
- **Scenario 8 — fetch fails, attempt is skipped (RED on current block).** Given `MOCK_FETCH_RC=1`, then `kind=fetch rc=1 — fetch origin main failed` is printed six times, no abort sentinel, no `git push failed`, no `pushed`, then `[ship.phase7.behind_exhausted] … (fetch_failures=6/6)` and the loop times out. Both blocks.
- **Scenario 9 — success path characterization (GREEN before and after).** Given all knobs default (fetch/merge/push succeed; push drops `$MOCK_STATE/pushed`; `gh` flips to `MERGED CLEAN` once that file exists), then `[1/60] auto-sync 1 pushed — auto-merge will re-evaluate` (mirror: `[1/60] auto-sync 1/6 pushed`) is printed and the loop exits before tick 2 (`[2/60]` absent). This is the net under the `if/elif`→nested refactor (mutants 10/11 measured RED).
- **Scenario 10 — real git, conflict aborts cleanly and an in-progress merge is untouched.** See AC11. Measured today with the recipe: real rc 1 conflict with `MERGE_HEAD` present, `--abort` clears it; pre-existing `MERGE_HEAD` → rc 128 and an unconditional abort reverts a staged `f=resolved` to `f=feat` (the row's second sub-row asserts the fixed arm no longer does this).
- **Regression (issue transcript).** The #8320 transcript shape (`Automatic merge failed` followed by `auto-sync 1 pushed`) is exactly scenario 6's forbidden pairing.

## Success Metrics

- The next `soleur:ship` / `soleur:merge-pr` run that hits a real conflict during BEHIND auto-sync stops with the conflicted path named instead of printing `pushed` (re-eval trigger named in #8339); a run that finds a merge already in progress leaves it alone.
- `test-scripts` stays green with the new rows; suite runtime stays ≈ 1 s (measured 1.04 s today; the new rows are all no-sleep, scenario 10 is < 1 s of local git).

## Dependencies & Risks

- **Risk: harness pipefail masking (the vacuity trap).** Mitigated by the self-check row (AC4, quoted heredoc) and by AC1 requiring the RED run before the fix. If the RED run comes back green, the subshell is still running under pipefail — stop and fix the harness, do not "fix" the block.
- **Risk: mock-state trap.** A `rev-parse` glob that answers `-q --verify MERGE_HEAD` (H6) or a variable-based state flag (H7) makes the precondition fire on every tick or the `gh` flip never happen; both are matrix rows.
- **Risk: mirror drift.** Scenarios execute against the mirror, scenario 3:merge-pr asserts a mirror-only output, and AC5's tokens make a half-applied fix red.
- **Risk: `printf '%s\n' "$sync_out" | tail -N` prints one empty line when `$sync_out` is empty** (`git push` with nothing to say). Cosmetic; accepted.
- **Risk: `set -u` in the fixture.** `sync_out`/`sync_rc`/`fetch_fails` are always assigned before use; the mock `git` uses `${2:-}` (bare `git push`).
- **Risk: scenario 10's real `git init` from a linked worktree.** Mitigated by sourcing `test-helpers.sh` (tripwire + `git_fixture_env`), `GIT_CONFIG_NOSYSTEM=1`/`GIT_CONFIG_GLOBAL=/dev/null` via that helper, temp dir under the scratch path, and a guarded `cd` (`cd "$tmp/a" || { fail …; return; }`) — the block is never sourced unless the cwd is the throwaway clone and `command -v gh` resolves to the stub.
- **Out of scope, explicitly:** #8334 (`OUTAGE_RE` negation in the incident-PIR gate), #7472 (Phase 7 silent on non-required check failures — same block, different arm; acknowledged, not folded), #8383 (consolidating the three copies of the sync arm into one executable; also carries the `Already up to date` no-op-push P2 from spec-flow row 3).
- Depends on nothing; blocks nothing. Draft PR #8378 exists for this branch.

## Research Insights

### Premise Validation (Phase 0.6)

- #8339: OPEN, labels `type/chore`, `deferred-automation`, `meta/machinery`, `closedByPullRequestsReferences: []` — premise holds.
- #8320: MERGED 2026-09-18T23:08:03Z (commit `5396a71db`); it measured the bug and resolved its own conflict by hand; it does not touch either SKILL.md (git-history-analyzer, file diff verified) — the three `| tail` lines are still present in both fences.
- Draft PR #8378 (`WIP: feat-one-shot-8339-poll-block-pipe-rc`) OPEN, isDraft, on this branch.
- Fence + extractor present: `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` `extract_block()` anchors on `<!-- phase-7-poll-block:start -->` / `:end`; suite currently 18 pass / 0 fail in 1.04 s. Introduced as `ship-phase-7-poll-fixtures.sh` by PR #4388 (commit `873ca0e49`, 287 lines) — the same commit that introduced the mirror's `&&` chain; PR #4807 (commit `2e8797455`, 2026-06-02) de-orphaned it (fence-anchored extractor + `.test.sh` rename so `test-all.sh` discovers it; the file header cites issue #4387 as context). `run_scenario`'s subshell has not changed since. *(Corrected at review: the plan's earlier text credited #4807 with the introduction.)*
- Mechanism vs ADR corpus: no ADR concerns pipe exit-status capture; `work/SKILL.md` (#7828 block, commit `96d8501fa`) already prescribes "never pipe a command whose exit code IS the result — redirect and read `$?`", so the proposed mechanism is the repo's stated convention, not a new one.
- Monitor shell semantics measured: `bash -c 'set -o | grep pipefail'` → `pipefail off`.

### Property List / Cut List (Phase 0.6b)

Properties:

1. A failed `git merge` in the BEHIND arm is reported, aborted, and stops the poll — never "pushed".
2. A failed `git push` after a clean merge is reported as `git push failed after merge` and stops the poll.
3. A failed `git fetch` skips the attempt (counted) without stopping the poll.
4. The fixture observes the block under the Monitor shell's semantics (pipefail off), so it is RED on the current block.
5. Canonical and mirror carry the same sync arm (no drift).
6. *(added at deepen-plan)* The arm never aborts a merge it did not start, and never calls a merge refusal a conflict.

Mechanisms kept: explicit rc capture (1–3); `MERGE_HEAD` precondition + post-failure branch (6 — the fix makes these paths reachable for the first time; the minimalism ladder's carve-out for "error handling that prevents data loss" applies); `set +o pipefail` + quoted-heredoc self-check (4); scenarios on both blocks + file-backed mock state + list-form `must_match` + parity tokens (5, and the observability of 1–3/6); scenario 9 (characterization net for the refactor); scenario 10 (real-git observables the mocks cannot see); `fetch_fails` discriminator (truthful `behind_exhausted`, `hr-observability-as-plan-quality-gate`).

Cut list: block-level `set -o pipefail` → 1–3 → cut, changes every other pipe in a block two skills copy (issue agrees). Helper function `_tail_rc` → 1–3 → cut, same line count and one more name to drift. Call-count assertions → 1 → cut, counters are lost inside `$( … )`. **Cut at plan-review (v2):** checked-in negative-control copy of the buggy block → 4 → cut, same property as the self-check at ~30× the cost (DHH, simplicity); comment-stripped arm `diff` → 5 → cut into executed rows + tokens (DHH, simplicity, Kieran); negative-shape grep guard → no property → cut (DHH, simplicity); `errexit` self-check → 4 → cut, under `-e` the live rows redden on their own (simplicity); aligning mirror echo lines → no property → cut. **Cut at deepen-plan (v3):** `git -q` rewrite → operator's stated mechanism → DC-1; extracting the Grok wake regex from `pr-merge-poll.ts` into the fixture (test-design rec 5) → couples the suite to a TS literal that `pr-merge-poll.test.ts` already pins → not adopted; `Already up to date` no-op detection (spec-flow row 3) → changes the success line every consumer keys on → #8383.

### Prototype measurements (scratchpad, 2026-09-19)

| Block | pipefail | 6 | 6b | 6c | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|
| current ship | off | RED | RED | RED | RED | RED | GREEN |
| current ship | on | GREEN (vacuity trap) | — | — | GREEN | — | — |
| v3 ship | off | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN |
| current merge-pr | off | RED | — | — | RED | — | — |
| v2 merge-pr | off | GREEN | — | — | GREEN | — | — |

Existing 18 assertions under `set +o pipefail` + default-mock `rev-parse -q` fix, against the v3 block: 18 pass. Mutants 10/11 (re-fetch deleted; success echo renamed) against the v3 block with scenario 9: RED (legacy-code-expert). Real git: conflict rc 1 + `MERGE_HEAD`; pre-existing `MERGE_HEAD` rc 128 and unconditional abort discards a staged resolution; dirty tree rc 2 without `MERGE_HEAD`; `echo "$x"` with `x=-n` prints nothing while `printf '%s\n'` prints `-n`.

### Repo research

- CI wiring: `scripts/test-all.sh:78` glob `'plugins/soleur/test/*.test.sh'`, group `scripts`; `scripts/lint-orphan-test-suites.sh` derives globs from `test-all.sh` — editing an existing suite needs no registration.
- Local idiom for capture-then-display: `mt_out="$(git merge-tree --write-tree origin/main HEAD 2>&1)"` in the same block (both files); `out=$(cmd 2>&1) && rc=0 || rc=$?` in `apps/cla-evidence/scripts/inspect.test.sh`. Naming: `<step>_out` follows `mt_out`; `<step>_rc` is the repo-wide convention (`jq_rc`, `curl_rc`, `scan_rc`, …).
- Fixture helpers: `plugins/soleur/test/test-helpers.sh` (67 suites source it) provides the #7833 tripwire and `git_fixture_env <dir>`; `make_gh_stub` exists for PATH-based `gh` stubs.
- No doc outside the two SKILL.md files quotes the sync-arm lines verbatim; no TS test asserts on them.
- `plugins/soleur/lib/pr-merge-poll.ts` line 71: AwaitShell wake pattern; lines 60-72: Grok's BEHIND path is `sync-pr-behind.sh`.
- `plugins/soleur/scripts/sync-pr-behind.sh` lines 54/70/77 have the same pipe shape but under `set -euo pipefail` (line 10) — not a defect; third copy → #8383.
- Hosted consumer of the fence: `apps/web-platform/server/inngest/functions/event-ship-merge.ts` (`/soleur:ship --headless`), layer 1 `sentry-correlation` + `reportSilentFallback` bounded `stdoutTail`.
- Retroactive-application rule body: `plugins/soleur/skills/ship/SKILL.md` §5.5 (`wg-when-fixing-a-workflow-gates-detection`); the issue itself asks for the re-run.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` (#7828) — `cmd | tail` takes the pipe's status and destroys the evidence; read `$?` immediately after the command whose status matters.
- `knowledge-base/project/learnings/2026-05-15-red-tests-for-extractors-must-use-covered-code-path.md` — a RED fixture must inject the failure on the path the implementation actually reads; here that path is "pipefail off", which the harness did not provide.
- `knowledge-base/project/learnings/2026-03-14-bare-repo-helper-extraction-patterns.md` — subshells inherit the parent's `set` state; scope the override inside `( … )`.
- `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — toggling pipefail block-wide changes `grep`-in-pipeline semantics; the reason block-level pipefail was cut.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — harness rows, the ORDER row, and the AND-vs-OR `must_match` finding are instances of this class.
- `knowledge-base/project/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` — `git merge --abort` is the safe recovery for a merge *this arm started*; never stash mid-merge.

### Plan-review (v1 → v2) and deepen-plan (v2 → v3)

Advisor (ADR-083, curated payload): explicit capture is the right architecture; three of its four suggestions were later cut by plan-review as redundant with executed scenarios. Plan-review: Kieran found the unquoted-heredoc self-check vacuity, the multi-line `run_scenario` grep form, the stdout-vs-stderr sentinel trap; DHH/simplicity cut the negative-control fixture, the arm diff, and Guard 2; CTO raised message tags/next-steps (DC-2), the `fetch_fails` counter (DC-3), and the triplication (#8383). Deepen-plan: security-sentinel + spec-flow independently measured the `MERGE_HEAD` data-loss path (applied) and the non-conflict refusal (applied); test-design + architecture + legacy-code independently found the single-ERE `must_match` (applied); legacy-code found the `gh`-state `$( )` swallow and wrote scenario 9 (applied); observability-coverage added the hosted-path citation, durable readback, un-swallowed `--abort`, `fetch_failures` discriminator and the `[ship.phase7.sync_failed]` grammar (applied — the tags being a second independent signal on DC-2's tag half; DC-3 closed); architecture found the AC8/AC5 regex collision and the non-discriminating `git merge --abort` token (applied); git-history corrected the fixture's PR and the #8320 timestamp; pattern-recognition confirmed no third unguarded instance; best-practices confirmed the idiom (BashFAQ/002, ShellCheck SC2312).

### Functional overlap (Phase 1.5b)

Registries queried (2/3 reachable): `ship` (composio-community) and `github-triage` (trailofbits) overlap architecturally (PR lifecycle automation), not functionally with this bug fix. Nothing installed. Community discovery (1.5): no uncovered stack (bash + TypeScript repo).

## Open Code-Review Overlap

None — 65 open `code-review` issues scanned; none cite `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/merge-pr/SKILL.md`, or `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`. Adjacent open issues on the same block, acknowledged and not folded: #7472 (non-required check failures are silent — different arm), #8334 (`OUTAGE_RE` negation — explicitly out of scope per the run mandate), #8383 (filed by this plan — consolidation of the three sync-arm copies + the no-op-push P2).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (a bash block inside two engineering skills plus its fixture; no user-facing surface, no data, no vendor).

## References & Research

- Issue #8339; found on PR #8320 (merged 2026-09-18T23:08Z). Follow-up: #8383.
- Canonical block: `plugins/soleur/skills/ship/SKILL.md` (`<!-- phase-7-poll-block:start -->` fence, BEHIND arm; chain introduced in `a64161271`, PR #3984).
- Mirror: `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 (`&&` chain introduced in `873ca0e49`, PR #4388).
- Fixture: `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (`extract_block()`, `run_scenario()`, mirror-parity token list; introduced in `2e8797455`, PR #4807).
- Helpers: `plugins/soleur/test/test-helpers.sh` (`git_fixture_env`, tripwire).
- Convention: `plugins/soleur/skills/work/SKILL.md` #7828 block ("never pipe a command whose exit code IS the result"); BashFAQ/002 (<https://mywiki.wooledge.org/BashFAQ/002>); ShellCheck SC2312 (<https://www.shellcheck.net/wiki/SC2312>).
- Grok wake pattern and BEHIND path: `plugins/soleur/lib/pr-merge-poll.ts` (`pollInstructions()`, `behindSyncInstructions()`).
- Hosted consumer: `apps/web-platform/server/inngest/functions/event-ship-merge.ts`.
- Retroactive rule: `plugins/soleur/skills/ship/SKILL.md` §5.5 `wg-when-fixing-a-workflow-gates-detection`.
