# A rollback recipe nobody had run, and a baselined file touched without its --changed lint

**Issues:** #9252 (zot pin), #9390 (docker.pkg.github.com deny) · **PR:** #9795 · **Date:** 2026-10-09

## Problem

A two-part infra change (bump the zot pin v2.1.20 to v2.1.22; add a third name to the hosts-file GHCR
deny at seven byte-identical sites; deliver both through one registry-host replace) went through a
13-seat review panel, a 4-seat targeted fix round and one verification seat. The fix itself was small
and correct. What the process found was in what the change *touched* and *claimed*:

1. **CI went red on two repo-wide ratchets the local gate could not see.** Touching `ci-deploy.sh`
   (a file in the Rule E credential-header baseline) made `lint-shell-trace-credential-refusal.py
   --changed` apply to its whole body: an existing `curl -H "X-Signature-256: ..."` in the peer
   fan-out put the HMAC signature on a command line any local user can read. Fixing that exposed the
   next rule on the same line: a curl that now carries a credential on stdin must also be
   transport-confined (`--disable` first, `--noproxy '*'`). Separately the plan this branch adds
   declares `credentials_required`, which moved a corpus-baseline count 49 to 50. Phase 0.5 check 6.5
   of `soleur:work` says to run the `--changed` lint *before starting* when a diff touches a
   baselined file; it was not run, and the full affected gate (`test-all.sh --affected`) could not be
   obtained because four other worktrees were queued on the lock behind a 4h+ holder.
2. **The plan's `## Rollback` and the sidecar's recovery recipe said "revert the four values".** A
   review seat executed it (`git revert --no-commit` of the branch's commits in a scratch detached
   worktree, then the gates the revert PR must pass): applying only the four values leaves
   `zot-image-staleness.test.sh` at 9 passed / 6 failed (sidecar digests, version, follower claim
   comments and the previous-known-good block all disagree with the pin). The recipe also pointed at
   a plan that will be archived, said the host pulls zot from the public registry (false since the
   boot-asset change), and omitted the two kill-switch marker lines the revert commit needs.
3. **A stale block had been spliced into the plan file** (an older copy of the plan body, from the
   Enhancement Summary to Observability, at the Encryption Posture heading), so the file carried
   duplicate H2s and a truncated heading. Found at work start by listing headings.
4. **Prose claims added by the fix**: the follow-through script tied upstream zot#4235 / #4236 (a
   quadratic-gc fix) to a "one repo never completes, scheduler panic" symptom neither the issue nor the
   PR describes; the store-compat row said v2.1.20 "logged nothing" where the same call sites exist in
   v2.1.20; the plan cited the disk-fill heartbeat as the page for "zot does not start", but that
   heartbeat keeps pinging while zot is down.

## Solution

- Moved the signature header to curl's stdin config (`--config -` fed from a process substitution),
  added `--disable --noproxy '*'`, removed the Rule E baseline entry for the file, and pinned it with
  two rows that execute the real function against a curl stub (argv has no signature and no 64-hex
  run; stdin is exactly the HMAC computed in the test; URL, body, content type, one call). Mutation
  check: reverting to `-H` puts the signature back in argv and the rows go red. The docker
  `--config` single-source guard now excludes the `fan_out_to_peers` body instead of every bare
  `--config -`.
- Bumped the `credentials_required` baseline with the dated, justified entry its test demands.
- Rewrote the recovery as a wholesale `git revert` of the squash commit (verified by simulation:
  staleness 15/15 and deny parity 29/29 on the reverted tree), with the tag-qualified values and the
  marker requirement, in the sidecar rather than in a plan.
- Removed the spliced block; corrected the heartbeat citation, the follow-through wording and the
  store-compat claim.

## Key Insight

**A rollback section is the one part of a plan that is first executed during an incident, so it is the
part most likely to be wrong; execute it once, in a scratch worktree, before merge.** The check is
cheap (`git revert --no-commit <the branch's commits>` in a detached worktree, then run the gates the
revert PR must pass) and it found a defect no reader of the prose did. The same shape applies to
every "to undo this, do X" sentence an author writes.

**Touching a baselined file owes its whole debt in the same PR, and the lint that says so only runs in
CI.** `ci.yml` runs `--changed --base origin/main`, which bypasses the baselines for every touched
file; nothing runs that form locally (it is not in `lefthook.yml`), and the full gate that would have
surfaced it was unobtainable. When the gate is unobtainable, the substitute is the specific lints the
diff's files are baselined in, run by hand before the first push.

## Session Errors

1. **A duplicated stale block was spliced into the plan file by the planning subagent.** — Recovery:
   listed H2s, deleted the stale copy, re-checked headings unique. — **Prevention:** at the start of
   `soleur:work`, run `grep -E '^## ' <plan> | sort | uniq -d` and read the plan's heading list once;
   a duplicate or truncated heading means a bad splice, not a design.
2. **Did not run `lint-shell-trace-credential-refusal.py --changed --base origin/main` although the
   diff touched a Rule-E-baselined file (work Phase 0.5 check 6.5).** — Recovery: CI failed
   `lint-bot-statuses`; paid the debt in `ci-deploy.sh`. — **Prevention:** the lint is unwired
   locally (CI only). Run it by hand whenever `git diff --name-only origin/main...HEAD` intersects
   `scripts/lint-shell-trace-credential-refusal*.baseline.txt`, especially when the full gate is
   queued out; a pre-push wiring does not exist (lefthook has no pre-push stage).
3. **Fixing the Rule E violation exposed Rule D on the same curl (transport confinement).** — Recovery:
   added `--disable --noproxy '*'`. — **Prevention:** after satisfying one rule of a multi-rule lint,
   re-run the whole lint, not the one rule; a credential that moves to stdin makes the curl
   "credentialed" for the next rule.
4. **The `credentials_required` corpus baseline moved because the new plan declares the field.** —
   Recovery: baseline 49 to 50 with a justification entry. — **Prevention:** a plan whose Observability
   discoverability test needs a vendor credential bumps this baseline in the same PR; grep
   `BASELINE_DECLARED_PROBES` when writing such a plan.
5. **The new `--config -` tripped the docker `--config` single-source guard in `ci-deploy.test.sh`.** —
   Recovery: scoped the exemption to the `fan_out_to_peers` body (first version stripped every bare
   `--config -`, which a review seat showed also hides a docker `--config -`). — **Prevention:** an
   exemption added to a guard should remove the one construct from the scan, not widen the pattern.
6. **A mutation-check stub's `cat` read inherited stdin and hung the check.** — Recovery: `timeout 2
   cat` and `< /dev/null`. — **Prevention:** any stub that consumes stdin in a test of a mutant that
   may stop feeding it must be bounded.
7. **Two `setsid nohup` / `( ... &)` detached gate launches vanished with an empty log and no process.**
   — Recovery: a harness-tracked `run_in_background` command that writes the rc itself. —
   **Prevention:** if a detached run shows no process and a 0-byte log within seconds, stop
   re-launching it the same way.
8. **The affected gate was queued behind four sibling worktrees' full-gate runs (holder 4h+).** —
   Recovery: killed my queued run, ran the specific suites directly, relied on CI's full battery. —
   **Prevention:** known (`--capacity` first); do not wait on the lock, run the diff's own suites plus
   the lints its files are baselined in.
9. **Hook-blocked commands (`git stash list` in a chained command; `pgrep -f`; `ps | awk '<pat>'`).** —
   Recovery: rewrote without them. — **Prevention:** already hook-enforced; use `list_runs` /
   `kill_mine` and an rc file.
10. **Edit scripts asserted a missing anchor twice (a comment that wraps across lines; a regex-escaped
    anchor).** — Recovery: the assert-before-write pattern aborted with nothing written; re-anchored. —
    **Prevention:** none needed beyond the existing assert-before-write.
11. **Prose I added over-attributed an upstream fix and cited the wrong heartbeat.** — Recovery: review
    seats falsified both; corrected. — **Prevention:** the existing rule (name the command that falsifies
    each claim the diff's prose adds) applies to follow-through script comments and runbook citations
    too; grep the resource names a runbook cites against the `.tf` that defines them.
12. **CI logs were unreadable until the whole run finished (`gh run view --log-failed`), costing three
    round trips.** — Recovery: `gh api .../actions/jobs/<id>` named the failing step immediately. —
    **Prevention:** already in the review skill (step-level API first); read it.
13. **Local `ci-deploy.test.sh` flaked on a different canary-timing row each run at load average
    14-31.** — Recovery: re-ran once, then left CI as the arbiter (502/502 earlier at lower load). —
    **Prevention:** under sibling contention, a different failing row per run is a load signature;
    do not chase it, and do not report it as a pass either.

## Tags
category: workflow-issues
module: apps/web-platform/infra
