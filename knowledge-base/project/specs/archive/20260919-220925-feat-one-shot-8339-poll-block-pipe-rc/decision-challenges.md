# Decision challenges — feat-one-shot-8339-poll-block-pipe-rc

Taste / User-Challenge findings from the headless `plan` → `plan-review` pass for #8339,
persisted per ADR-084 (single-signal context: the consolidator's judgment, not the
Step 4.5 both-signals gate). The operator's stated direction is the default in every
entry; nothing here was applied to the plan. `ship` Phase 6 renders this into the PR
body as informational statements.

---

## DC-1 — Use `git -q` and drop `tail` instead of capturing the rc

**Date:** 2026-09-19
**Classification:** User-Challenge (DHH plan-review P0 vs. the operator's stated mechanism)
**Status:** open — plan keeps the operator's mechanism

- **What you said:** "Small fix: capture the rc of `git fetch`, `git merge`, and `git push` explicitly (not pipefail), then display via tail." (#8339 body and the one-shot mandate.)
- **What the signal recommends:** delete the `| tail` instead of guarding around it — `if ! git fetch -q origin main 2>&1; then` / `elif ! git merge -q --no-edit origin/main 2>&1; then` / `elif ! git push -q 2>&1; then`. The original flat `if/elif/elif/else` chain then reads the real exit code; three lines per block instead of ~25, no `sync_out`/`sync_rc` idiom, no nesting, no blank-line-on-empty-output quirk.
- **Why:** measured in a bare-origin repo: `-q` silences success output on all three commands and still prints `CONFLICT …` / `Automatic merge failed` (rc 1) and `error: failed to push` (rc 1). The `tail` existed only to trim progress noise, and `-q` trims it at the source. Simplicity and DHH both scored the capture scaffolding as the heaviest part of the change.
- **What context we might be missing:** `-q` also suppresses the `Auto-merging <path>` and `Merge made by the 'ort' strategy` lines the operator reads in the Monitor stream (the #8339 transcript shows them), and `git push -q` hides the remote's post-receive messages on success. The fixture rows hold under either form (only the mock dispatch keys change: `"merge -q"` instead of `"merge origin/main"`).
- **If we're wrong, the cost is:** two blocks carry ~20 lines of capture scaffolding that a three-flag change would have avoided; nothing functional — both forms satisfy properties 1–3.

## DC-2 — Tag the new failure lines and add a next-step line each

**Date:** 2026-09-19
**Classification:** Taste (CTO devex lens; operator-visible message shape)
**Status:** partially applied at deepen-plan 2026-09-19 — the observability-coverage reviewer independently required the `[ship.phase7.<tag>]` grammar under `hr-observability-layer-citation` (second signal → promoted); the plan's lines now carry `[ship.phase7.sync_failed] kind=merge|merge_refused|merge_in_progress|push|fetch rc=N` prefixes and state the worktree condition (`the local merge commit is retained, nothing was aborted`; `Clear the worktree state on $BRANCH shown above, then re-run`). The issue's verbatim substrings are kept inside each line. NOT applied: the DIRTY-arm-style `Resolve locally: git merge origin/main, then git push` sentence on the conflict line — still open for the operator.

- **What you said:** the messages `fetch origin main failed …`, `Manual conflict resolution required on $BRANCH. Stopping the poll.`, `git push failed after merge — auto-sync incomplete. Stopping the poll.` (the issue's own verification language; the plan preserves them verbatim).
- **What the signal recommends:** prepend `[ship.phase7.sync_conflict]` / `[ship.phase7.sync_push_failed]` so the new exits are greppable like the block's other exits (`[ship.phase7.required_failed]`, `[ship.phase7.dirty]`, `[ship.phase7.behind_exhausted]`), and append one next-step line each: `Resolve locally: git merge origin/main, then git push` (the DIRTY arm already ends with a `Resolve locally:` line) and `Local branch is ahead by the sync merge commit: inspect the git push output, then git push`.
- **Why:** the poll stops but does not say what to do next; the push-failure case leaves an unpushed local merge commit with no hint.
- **What context we might be missing:** the fixture rows and #8339 match on the verbatim prefixes; tags and trailing lines are additive and would not break them, but they widen the diff beyond what the issue asked for.
- **If we're wrong, the cost is:** an operator reads `Stopping the poll.` and has to work out the recovery from the preceding `git` output — the same position as today's DIRTY-exit minus its `Resolve locally:` hint.

## DC-3 — Count fetch failures separately from BEHIND syncs

**Date:** 2026-09-19
**Classification:** Taste (CTO devex lens; scope widening)
**Status:** CLOSED — applied at deepen-plan 2026-09-19. The observability-coverage reviewer raised the same change independently under `hr-observability-as-plan-quality-gate` ("a verdict line that cannot be believed" — the class this fix exists to remove), which is the two-signal promotion ADR-084 prescribes. Plan v3 adds `fetch_fails` (initialised on the line after the fingerprint line) and `(fetch_failures=${fetch_fails}/${MAX_BEHIND_SYNCS})` on the `behind_exhausted` echo; scenario 8 asserts `fetch_failures=6/6`; the mirror carries it via parity token `fetch_failures=`. #8383 keeps only the consolidation and the `Already up to date` no-op-push item.

- **What you said:** the fix is scoped to making the three failure branches reachable; a fetch failure "skips this sync attempt" (existing message, existing counting).
- **What the signal recommends:** a separate `fetch_fails` counter included in the `behind_exhausted` line, so six network/auth failures do not print the "origin/main is moving faster than this PR's CI cycle" diagnosis.
- **Why:** scenario 8 asserts exactly this path; after the fix a fetch outage reaches `behind_exhausted` with a misleading recommendation (settle-then-admin-merge).
- **What context we might be missing:** the pre-fix block never reached this arm on a fetch failure at all (the guard was dead and the merge/push ran); the misdiagnosis is a newly reachable state, not a regression.
- **If we're wrong, the cost is:** one misleading operator line after six consecutive fetch failures, each of which was already printed as `fetch origin main failed (rc=N)` above it.
