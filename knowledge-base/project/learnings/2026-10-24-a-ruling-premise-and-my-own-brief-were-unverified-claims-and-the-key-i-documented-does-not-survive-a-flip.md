# Learning: a ruling's cost premise, my own brief and a new telemetry key's scope were all claims nobody ran, and a green mutation matrix covered one axis

## Problem

The second flip of the Inngest scheduler link to https (epic #10205, item #10136, ADR-294, run 39977793262, 2026-10-23) failed at the host-side
self-gate: `INNGEST_LINK: class=selfgate_failed level=error rc=56 http=000 attempts=3` on web-1, deploy reason `inngest_link_selfgate_failed`,
before any canary ran. The event named only the last attempt's curl exit code and HTTP code, so the failed stage was unreadable. The fleet reverted
to http (measured: `class=resolved state=http_default scheme=http` at 15:26:10Z on web-1 and 15:26:44Z on web-2), and a read-only handshake probe at
15:49Z showed the listener up (`unverified_rc=60`), which does not reproduce rc 56 and does not establish a cause.

Issue #10934 (PR #10935) makes the event name the stage: `phase=<connect|handshake|verify|ca_file|request|status|unknown> tcp= tls= verify=` appended
after the unchanged `rc= http= attempts=` prefix, derived from one curl `-w '%{http_code} %{time_connect} %{time_appconnect} %{ssl_verify_result}'`
line per attempt (times decide the phase; the exit code only for 124, 77 and 60, because one wire event prints rc 52 on curl 8.5.0 and rc 56 on 7.81 and
8.23). The same closed-enum token is written to the deploy state as `inngest_link_selfgate_phase`. The pass verdict (rc 0 and first token 200, decided
first) did not change.

## Solution

- `ci-deploy.sh`: `_inngest_link_selfgate_phase` (pure helper), one shared `_inngest_link_time_nonzero` used by both the phase and the tcp/tls counters,
  `IFS=' ' read -r`, per-attempt resets, and a separate `sgp` append in `write_state` checked by `_gak_enum` (absent key unless the gate failed).
- Honest test doubles: one shared profile table and printer (`test-fixtures/curl-w-profiles.sh`) sourced by both curl stubs; the printer exits 99 and
  drops a sentinel on an unknown `-w` variable or profile; a real-curl differential (H6) against local TLS listeners; a mutation matrix (M22a-M23e) run by
  a three-step `kill_mut_sg` (named rows green on the pristine block, the mutation kills them, the anchor is unique in the self-gate text).
- Docs: a decode table in the runbook (`Reading selfgate_failed`), a deploy-status row, an ADR-294 addendum with the measured per-host rows, and an
  evidence file with the curl measurements on 7.81, 8.5.0 and 8.23.

## Key Insight

1. **A ruling's cost premise is a claim, and a dissent that contradicts it goes back to the owner with verified facts.** The CTO first ruled "accept the
   run-log limit and file a follow-up" on the premise that surfacing the phase in the run log needs a new state field, a new reader in the release workflow,
   a `cat-deploy-state.sh` change and a flip-script change (more than 4 files and 100 lines). The code-simplicity reviewer's CONCUR gate dissented; reading
   `web-platform-release.yml` (its non-zero-exit branch prints `jq .` of the whole state body) and `cat-deploy-state.sh` (base state passes through
   verbatim, the `github_app_key_*` precedent) refuted the premise, and the CTO amended the ruling to a ten-line `write_state` append. The dissent was
   routed to the owner with the verified facts instead of being argued by the lead.
2. **Scope a new telemetry surface by every workflow that can overwrite it or fail to print it.** The key was documented as a fallback read ("read the state
   key when Better Stack is empty"). It is the last deploy's state: the release run prints it, but the flip run's `track.sh` prints only `reason=` and
   `exit_code=`, and a failed flip's best-effort `Revert to http` step redeploys the fleet and rewrites the state about 90 seconds later. Four seats found it
   independently in round 2 (agent-native, observability, user-impact, architecture); the verifier found the last over-claim (that the revert always erases
   it: the revert can end incomplete or be cancelled).
3. **A brief is a claim too.** My brief to the docs agent said the key appears in the "release/flip run log's `jq .` dump"; only the release workflow dumps
   the body. The agent read `track.sh` and corrected it, and said so in its report. Before writing a fact into a brief, run the command that settles it.
4. **A battery that arrives green covers the axes its author edited.** The author's own 20-row matrix was sound (all 20 kills failed for the intended
   reason) and 12 further mutants survived on axes it never touched: stale per-attempt resets (`vv=0`, `http=none`), an unsanitised `verify` field, the
   wiring of the pass verdict (`== 2*`, `== 200*`, the timers), a decode-table check satisfied by bare words in prose, an enum list pinned for one token
   only, a global set inside the loop. Overlapping comparator arms back each other up, so "per-arm independence" was not the property and a wontfix was the
   right call; the property is "a drifting table goes red".
5. **A queue entry clears `autoMergeRequest`.** A monitor that treats `autoMergeRequest == null` as "disarmed" fires on every enqueued PR. Watch the merge
   queue entry itself (position and state) and debounce a one-poll API miss before reporting `not-in-queue`.
6. **Evidence a doc cites must be re-run after the commits that change it.** The "H6 ran 6/6 on real curl 8.5.0, 252 passed" line predated the fix commits
   that changed H6; the evidence file now records the post-fix runs (274 passed at `4500ff682c`, 281 at `c2ac316a14`) and says the earlier figure is stale.

Related: `2026-10-22-docker-keeps-env-file-and-dash-e-entries-and-the-mock-could-not-show-it.md` (the same defect shape one PR earlier: a mock that models part
of the real tool), and the plan `knowledge-base/project/plans/2026-10-23-fix-inngest-selfgate-name-failing-phase-plan.md`.

## Session Errors

1. **The pre-merge hook merged `origin/main` into PR #10874's branch and pushed it when the merge was armed, against the owner's standing "rebase, never
   merge main in" rule.**
   - **Recovery:** reset to the earlier head, rebased onto origin/main, force-pushed with lease.
   - **Prevention:** the hook's sync merge is designed behaviour (#9401, #10958 track the sync script); the conflict with the standing rule is an owner
     policy question, so check `git log origin/main..HEAD` for a merge commit after every `gh pr merge` and rebase it away. Tracked, not filed here.
2. **The merge queue ejected #10874 as UNMERGEABLE on a probe-counter conflict with sibling PR #10846.**
   - **Recovery:** rebased, resolved the counter (75 plus one), re-armed.
   - **Prevention:** the PR body had named the conflict; resolve a predicted counter conflict at the last rebase before arming.
3. **My merge monitors read a cleared `autoMergeRequest` as "AUTO-MERGE DISARMED" and a one-poll API miss as "not-in-queue".**
   - **Recovery:** rebuilt the monitor to watch the queue entry and debounce one miss.
   - **Prevention:** see Key Insight 5.
4. **A guessed Better Stack field name (`.MESSAGE`; the field is `.message`) returned an unreadable dump on the first read.**
   - **Recovery:** printed the row's remaining fields and read `message`.
   - **Prevention:** print one row's keys before writing the extraction.
5. **A ruling premise and a fact in my own brief were unverified (Key Insight 1 and 3).**
   - **Recovery:** the CONCUR dissent and the docs agent each corrected one by reading the code.
   - **Prevention:** run the command that settles a premise before writing it into a ruling request or a brief.
6. **Prose ran ahead of evidence twice: round 1 (the #10880 attribution, "web-2 is not readable", the stale state-key fallback, unqualified curl-build
   claims) and the verifier's last find (the revert always erases the key).**
   - **Recovery:** two docs fix rounds and one inline wording commit (`6bfc034515`).
   - **Prevention:** scope every new telemetry claim by the workflows that can overwrite or fail to print it, and grep each corrected noun repo-wide.
7. **Hook refusals and tool slips: `gh issue create` was refused twice (milestone, then the filing exit), `TaskStop` was called once with a stray
   parameter, a `cd` into a worktree removed by cleanup failed once, and GitHub API calls hit transient TLS timeouts and EOFs.**
   - **Recovery:** added the missing flags and retried; no state was lost.
   - **Prevention:** one-off; none needed.
8. **Sandbox runs lacked `knowledge-base/` and `.git`, so the S9 decode row and two ci-deploy rows read red in the sandbox.**
   - **Recovery:** pointed `INNGEST_LINK_TEST_RUNBOOK` at the live runbook; reported the two ci-deploy rows as environment-only.
   - **Prevention:** put the override in every seat brief that runs the resolver suite in a sandbox (done in the round-2 brief).
9. **The first container run as root with the worktree `.git` unmounted gave artefacts (a mutant not killed, a git-grep rc 128, two skips).**
   - **Recovery:** discarded it and re-ran as a non-root user with the repo mounted at its host path.
   - **Prevention:** run the container check as the CI user with the repo at its real path, as the later runs did.

## Tags

category: workflow-issues
module: apps/web-platform/infra (ci-deploy.sh, Inngest link self-gate)
tags: inngest, selfgate, curl-write-out, deploy-state, ruling-premise, mutation-battery, merge-queue
