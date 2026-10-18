# Learning: operator-only production authorization stalled a non-technical operator, and a brief's HOLDS list was treated as the operator's

## Problem

On 2026-10-15 the founder gave this instruction, quoted exactly:

> "the CTO should own the decision and be able to proceed autonomously to complete the arc/epic, please also improve our workflow and skills to that effect as Soleur users aren't technical so they wouldn't know what to do anyway. Let's also see if the CTO skill should be improved or new skills created under the CTO so the process is higher quality and autonomous"

The wrong prior default was that every production-mutating act (merging a change to the live product, dispatching a deploy
workflow, a revert) needed a per-command go-ahead from the operator (`hr-menu-option-ack-not-prod-write-auth`, ADR-084's closed
operator-only list). That default assumes an operator who can judge a command. Soleur's users cannot, so the question either
stalls the epic or is answered by reflex, which is the exact failure the rule exists to stop. The same assumption sat in resume
briefs: a brief's `HOLDS` list, and its wording "ask the operator", were treated as the operator's even when each hold was a
checkable fact (a PR merged, no deploy run in flight, a run green). The hold in this session's own brief, "do not merge while the
registry host replace workflow runs", is a machine-checkable predicate, not a person's decision.

## Solution

Recorded operator consent plus a drift guard, recorded in ADR-289 (the first draft called this a "two-key" model; review showed the two artifacts are produced by the same agent identity, so they are not independent):

- **A Standing Delegation (the consent).** The operator is asked once, in plain language, at epic start. The calling skill writes an
  epic-issue comment through `delegation-verify.sh render`: marker on line 1, a verbatim quote, a `Confirmation:` line, numbered
  Scope items, a complete Excluded list, an expiry of at most 30 days. Deleting or editing the comment revokes it.
- **A CTO Production Envelope (the drift guard).** A committed section naming the exact command, blast radius, `Gate:`
  preconditions, verification, abort, a named rollback and stop conditions. The executed command is a byte-identical full line of
  it and must match a closed allowlist of four command shapes (merge, ready, workflow dispatch, create), so a "Yes" cannot be
  stretched to an arbitrary command.
- **One chokepoint.** `delegation-verify.sh` holds every validity check; the Technical-Ruling Gate, the hold evaluator
  (`hold-gate-eval.sh`) and the CTO's pre-execution call all call it. Anything it cannot evaluate keeps today's
  behaviour: the hold stands, the question is asked, the gate fails.
- **Holds become predicates.** `soleur:go` routes a brief that carries an epic reference (`#N`) AND a `HOLDS:` list to the CTO; each hold gets
  `Gate:` lines (`pr-merged`, `no-inflight-run`) that ship Phase 6 evaluates mechanically.
- **Receipts.** After each delegated act the CTO posts a receipt comment on the epic and records the row
  `Authorized by delegation <url>, envelope <path>, ran <ISO UTC>` in `decision-challenges.md`. The ship gate checks a receipt
  only for rows that carry `ran`, so recording that row (the CTO's job, not the calling skill's) is what turns the check on. The
  receipt must be created inside the delegation's life, not in the future and after the `ran` instant, never edited, posted by a
  person (not a bot), from an OWNER, MEMBER or COLLABORATOR, matching exactly, and serve one row only. It proves a receipt
  exists and matches, not what ran.
- **Still the operator's:** money, legal exposure, brand, scope, user-data loss, force-push to main, bypassing checks or
  rulesets, editing the delegation, lock-out credential rotation, third-party systems, any act with no named rollback.

## Key Insight

1. **A default that needs expertise the user does not have is a stall, not a safeguard.** Design the control around what the
   user can actually judge (outcomes, money, scope) and move the technical judgment to the agent that can make it, inside a
   record the user can revoke.
2. **A hold is a predicate or it is a person.** If a hold can be written as a checkable fact, evaluate it mechanically and fail
   closed; if it cannot, say plainly that it needs a person. Prose evaluation by the model is the failure the holds guard against.
3. **Name the residual instead of overclaiming.** The delegation is posted through the same `gh` identity as the agent, so the
   quote, the cap and edit-as-revocation are tamper-evidence, not prevention, and a pair of artifacts written by one agent is not
   two independent keys. ADR-289 states that, states the flip conditions, and points at #10361 for the receipt that restores
   independence.
4. **Do not skip the probe and then write as if you ran it.** The `updated_at` behaviour for reactions was never probed with a
   write on this repository; the verifier takes the strict reading. A read-only look at `cli/cli` found 8 of 8 reacted comments
   with `updated_at` equal to `created_at`, which the ADR cites as an observation only.
5. **A rule that grows an exception must say so in its own sentence.** The amended rule kept "menu acks and prior approvals do
   NOT extend to new commands" beside a path that is exactly a prior approval extended to new commands; the sentence now reads
   "outside a recorded delegation".

## Prevention

- When a plan offers an operator-only gate, ask whether the user can judge it; if not, it needs a recorded delegation plus an
  envelope, or a mechanical predicate, not a question.
- A skill that needs the operator once does it with one plain-language question at the start and writes the record through the
  verifier's `render`, then reads it back through `verify`; a record that does not verify is deleted.
- Never ask the operator a technical question (`hr-technical-fork-is-not-an-operator-question`); spawn the CTO.

## Session Errors

- **A background monitor can expire or fire spuriously.** A watch armed on a long wait either reached its time limit before the
  event or fired on text that was not the event. **Prevention:** arm the watch on a state the check itself re-reads (not on
  matching log text), give it a limit longer than the worst observed wait, and treat any fire as "re-read the state", not as
  the event having happened.
- **A merge-gate hook rejected a merge whose PR number was not the first operand.** `.claude/hooks/ship-kb-archive-gate.sh` needs
  the PR number as a bare operand right after `gh pr merge` (flags such as `--squash --auto` may follow). **Prevention:** put the
  number immediately after `gh pr merge` and the flags after it. (An earlier draft of this entry claimed a hook accepts only
  `gh pr merge <N> --squash`; no repo hook does, and `.claude/settings.json` allows `Bash(gh pr merge:*)`.)
- **The merge queue took about 58 minutes.** The wait is far longer than a typical step. **Prevention:** plan merge-queue time as a first-class phase (tens of minutes, not seconds) and do other verification
  while it runs.
- **A heartbeat cadence made the probe wait.** The heartbeat's cadence set when the state probe ran, so the probe had to wait for it. **Prevention:** probe on the event or at a short bounded interval, and do not let a heartbeat be the
  only thing that triggers a read.

- **The first design admitted by denylist what the rule said was a closed set.** The verifier's command check was eight text patterns, so
  quoted spellings (`g''it push`, `--admi""n`), `kubectl apply` and `rm -f -r` verified as delegable while the rule, the ADR and
  the reference all said "merge/dispatch/revert only". Seven review seats converged on it independently. **Prevention:** when a
  document names a CLOSED set, the enforcing code is a positive allowlist grammar with a character-class gate, and a denylist is only
  a second layer; write the escape rows (a corpus the guard must refuse) before the mutation rows.
- **Scope text was never bound to the command, and the epic was never bound to the envelope.** Only the existence of "Scope item N"
  was checked. **Prevention:** a record that authorizes an act must be tied to that act by content (the target token) and to the
  work it belongs to (the epic number), not by an integer that merely exists.
- **The pre-arming hold re-check was placed after the step that archives the files it reads.** Nothing local could see it because each
  file was internally right; the consistency seat found that Phase 6.45 moves the plan and rulings away before the check ran.
  **Prevention:** when adding a step to a pipeline, trace every path it reads against the steps that move or delete them, and keep
  the wiring block byte-identical in every place that quotes it (a test asserts the equality).
- **A fix round introduced new gaps in the guards it added.** The second batch narrowed the tool-name denial (`timeout 5 kubectl ...`
  verified again) and let a comment marker inside a fenced block hide executable lines; the single verification pass caught both.
  **Prevention:** a fix to a guard gets the same escape-row treatment as the guard; re-run the previous round's reproductions
  against the fixed code, side by side with the old version.
- **A stub hid a field the real tool does not have.** `gh pr list --json authorAssociation` does not exist; the suite's stub accepted
  it and only a live run failed. **Prevention:** a stub for an external CLI rejects the flags and JSON fields the real tool rejects,
  and one live read-only run happens before the suite is trusted.
- **A parallel commit swept another agent's staged files into an unrelated commit.** Concurrent agents on one worktree each ran a plain
  `git commit`. **Prevention:** every concurrent writer commits with an explicit `-- <paths>` pathspec and never `git add -A`.
- **A scratch directory was assumed to exist.** Writing a file into the session scratchpad failed until `mkdir -p`. **Prevention:**
  create the directory in the same command that writes into it.
- **A queued full-gate run sat behind other sessions for half an hour while the tree was about to change.** **Prevention:** a gate
  queued behind a lock is killed (own-process-group only) and re-queued once the tree stops changing, because the ship phase runs
  the affected gate on the final tree anyway.
- **The plan's pre-merge baseline for the registry host was stale.** The PR body's recorded boot id belonged to a host replaced the
  day before; the live baseline was read again immediately before the merge. **Prevention:** read the live value inside the
  go/no-go window, never carry a recorded one forward.

### Triage

| Item | Recurring? | Disposition |
|---|---|---|
| Denylist for a closed set | recurring | fixed inline (allowlist, escape rows) |
| Scope/epic binding | recurring | fixed inline (V2, V3) |
| Hold re-check after archive | one-off for this order, class recurring | fixed inline (moved to the start of Phase 6.45) |
| Fix round introduces gaps | recurring | covered by the verification pass; rule text in review skill already names it |
| Stub hides a field | recurring | fixed inline (stub rejects the field; live run) |
| Parallel commit sweep | recurring | convention (`--` pathspec), no new rule |
| Scratch dir missing | one-off | none |
| Gate queued behind others | recurring | none new: `--capacity` and own-pgroup kill already exist |
| Stale recorded baseline | one-off | none |

### Ship-phase errors (added at ship, 2026-10-16)

1. **A stray git identity (a one-letter author name with a throwaway address) appeared in the SHARED repository config** (all worktrees read it), so four commits were authored as `s` and the required CLA check failed on an unsigned committer. Source not found: none of this branch's suites write it, and the config file's mtime fell inside a session restart. Restored the real identity, rebuilt the four commits under it and force-pushed this branch with a lease. **Prevention:** after any session restart or test run, `git config --local --get-regexp '^user\.'` before the first commit, and check `git log origin/main..HEAD --format=%an | sort -u` before pushing; a fixture that needs an identity must set it on its own temp repo with `git -C "$d" config`, never on the cwd repo. *(One-off to this host; no new rule.)*
2. **A fix for one ratchet (anchor links to the plugin root) broke another (SKILL.md byte ceilings)**: four lifecycle skills went over by 11 to 44 bytes. **Prevention:** a fix that rewrites text inside a lifecycle SKILL.md re-runs `lint-skill-body-budget.py --base <merge-base>` before the commit; the cheaper fix was to stop the linked reference from carrying the plugin-root token, so callers keep their relative links. *(Covered by the existing Merge-Base-Relative Lints gate; the miss was running it before the fix round, not after.)*
3. **A sibling PR took the ADR ordinal during the pipeline** (288), found only by the sync's `check-adr-ordinals.sh`. **Prevention:** already the ship ADR-Ordinal Collision Gate; renumbered to 289 with a scoped sweep that left the sibling's citations alone.
4. **The first affected-set gate on the final tree was red on nine repo-wide ratchets** that a file-selected suite set cannot see (work skill already names this class). All nine were this PR's own new suites and docs. **Prevention:** none new; run the nine ratchet suites (`guard-vacuity-floor`, `lint-orphan-test-suites`, `test-affected-kb-consumers`, `fixture-relative-assert`, `fixture-dir-operand-assert`, `battery-tag-authorship-mutations`, `lint-shell-capture-exit`, `ci-head-verdict`, the plugin bun suite) before the first push when a PR adds test suites.
5. **A session restart dropped the Doppler keyring token**, so the post-merge reads that need Better Stack could not run. **Prevention:** none possible from the agent side; the loss is reported rather than worked around.

## Tags

category: workflow-patterns
module: cto-autonomy, standing-delegation, hold-evaluation
