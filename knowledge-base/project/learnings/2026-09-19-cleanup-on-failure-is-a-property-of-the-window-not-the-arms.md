---
module: System
date: 2026-09-19
problem_type: test_failure
component: testing_framework
symptoms:
  - "A generator that cleans up on every named failure arm still left five files behind on the one failure that fired before its trap existed — next run 66, forever"
  - "FORCE_COLOR=1 in the environment made both bite-proof anchors match nothing: a correct install rolled back as 72, a real leak read 71"
  - "The 71 and 73 arms could each be deleted with the suite 76/76 green"
  - "Nine review seats on one host converged on the same logic-path defects and none saw GNU-only tools, discarded tool stderr, or a missing run lock"
  - "A constrained subagent executing the skill prose found six unfollowable sentences the nine seats reading it did not — and its own dry run wrote synthetic deny/bypass rows into the live incident ledger"
root_cause: missing_validation
resolution_type: test_fix
severity: high
synced_to: [review, qa, plan]
tags: [cleanup-window, trap-ordering, ansi-anchors, stateless-stub, coverage-consult, environment-shape, prose-dry-run, bite-proof, constraint-scaffold]
---

# Cleanup on failure is a property of the window, not the arms — and nine same-host lenses share an environment-shape blind spot

## Problem

#8288 / PR #8352 taught `constraint-scaffold.sh` to prove its emitted gate bites (pass →
fail → pass on a detached worktree of HEAD) and to remove every artifact it emitted when the
proof fails. The script's header said so honestly — "a 71/72/73/74 REMOVES every artifact …
an INT/TERM mid-bite does the same" — and the SKILL.md and ADR-071 amendment overclaimed it as
"never a half-installed gate".

Six of nine review seats independently measured the gap: the five executables were emitted,
THEN the merge-base was computed, and a founder repo without `origin/main` (default branch
`master`, or unfetched) died 69 **after the emits and before any trap was installed**. Five
untracked files left; the next run exited 66 "already present"; the 66 message pointed at
`--refresh-baseline`, which hit the same 69. The message was on stderr, which agent runtimes
swallow. The test-design seat found two more classes the batteries had not reached, and the
coverage consult found five that no seat saw.

## Solution

### The window, not the arms

```bash
# BEFORE: cleanup lived inside the worktree helper's trap window only
capture_baseline_mergebase   # computes merge-base -> die 69 here, five files already on disk
prove_bite                   # 71-74 clean up via verdict_fail

# AFTER: preconditions before the first write; one handler armed across the whole window
resolve_base_ref             # origin/main, else origin/HEAD; neither -> 69 with nothing written
check_tmpdir_outside_repo    # 69 before the first write
CLEANUP_ARMED=1
trap '_wt_cleanup' EXIT
trap '_wt_cleanup interrupted; trap - EXIT; exit 143' INT TERM
take_run_lock
mkdir -p "$TARGET/scripts" …  # FIRST WRITE
… emits … capture_baseline_mergebase … prove_bite
release_run_lock
CLEANUP_ARMED=0; trap - EXIT INT TERM   # only after the bite passed
emit_readme; emit_pointer
```

`with_detached_worktree` installs the same handler and only clears it when nobody outside
holds the window (`CLEANUP_ARMED`). `die` now prints `FAILED (<code>): <msg>` on stdout for
every code; "interrupted" is said only on a signal. Pinned by a comment-stripped source pin
(`arm < first write < prove_bite < disarm < emit_readme`) and by behavioural rows — S-noorigin
(69, porcelain empty, re-run is 69 not 66), S-originhead, S-mktemp, S-int130, S-lock. RED
against the pre-fix script: 79/14, exactly the new rows.

### What the batteries missed, and who found it

| Finding | Found by asking | Fix |
|---|---|---|
| `FORCE_COLOR=1` decorates depcruise's `error <rule>:` lines; both anchors match 0; a correct install rolls back as 72, a real leak reads 71 instead of 74 | test-design: "which producer SHAPE has the stub never instantiated?" | runner `export NO_COLOR=1` (template + parity-pinned dogfood); scaffold strips ANSI before the anchors; S-ansi (stub) + C1-color (real, `FORCE_COLOR=1`) |
| 71 arm and 73 arm each deletable with 76/76 green | test-design: arm-deletion mutants on a sandbox copy | a stateful stub (clean arm fails after a probe arm ran → 73) and a runner-logic stub (reachability baseline entry → the RUNNER refuses → 71); m5 → 2 reds, m6 → 1 red |
| `emit-fix-constraints.test.sh` asserted on the workflows a FAILED run left behind | running the sibling suites after the fix | it depended on the residue class the PR was closing; fixture gains `origin/main` + a stub so the run completes |
| Guard 4's `SOLEUR_*DEBUG` predicate matched 4 call-forms; 11 of the 12 real marker emits use pino `log.warn({ SOLEUR_X: true })` | four seats grepping the tree's actual emit forms | predicate widened to every form the tree uses; env reads excluded per line; 11 positive + 1 negative controls on a synthesized repo |

### What no seat saw — the coverage consult's five

Nine logic-path lenses ran on one Linux host, as one actor, against one well-formed repo. The
consult's single question — *which plausible defect CLASS is absent from this list?* — returned
six environment-shape classes; five verified against the script and were closed in one commit:

1. **Platform.** `realpath -m` ×3, `sed -i` with `\x1b`, `1{…d}` are GNU-only; on stock macOS
   (bash 3.2, BSD sed — a founder host per `preflight` Check 10) the generator aborted with exit
   1 and an empty stdout, outside its own exit matrix. → `pwd -P` helpers, `sed … > tmp && mv`,
   `d;}`.
2. **Root-cause discard.** `git worktree add … >/dev/null 2>&1` and depcruise `2>/dev/null`
   dropped the cause before the 68/69 message. → tool's last lines carried into the message.
3. **Concurrency.** A default run and a `--refresh-baseline` in one repo shared the baseline
   `mv` and each other's cleanup. → `mkdir` run lock in the git common dir with the owner pid.
4. **Shallow clone.** merge-base failure said "unrelated histories?"; now names
   `git fetch --unshallow`.
5. **Hermeticity.** The new suites built 20+ fixture commits without `git-fixture-env.sh`; a
   developer `commit.gpgsign=true` would have reached every one. → sourced (and the Guard 4
   control repo too — `fixture-env-adoption`'s ceiling would otherwise have tripped at 26 > 25).

The sixth (founder hooks firing inside `worktree add`) verified pre-existing and was left:
same trust domain as `git checkout`, and `core.hooksPath=/dev/null` would also disable LFS
smudge. The captured stderr now names a failing hook.

### Reading versus executing the prose

QA ran a constrained subagent (no post, no write, no credentials) through the rewritten
`reproduce-bug` skill against a real issue. It found six sentences the nine seats had read
and passed: a Phase 1 exit criterion with no off-ramp for a local-only surface (literally
required a Better Stack query for a CLI hook), Phase 1 "inspect the code paths" contradicting
Phase 2 "stop reading code", a Phase 4 "do not proceed until reproduced" that is unsatisfiable
on a HEAD where the fix landed, a `${CLAUDE_PLUGIN_ROOT}` path with no stated behaviour when
unset, an ambiguous "render the table in symptom language" (one table or two?), and the hook
recipe buried in Phase 7 where a hook defect needs it in the Phase 2 ladder.

## Key Insight

- **Cleanup-on-failure is a property of the window between the first write and success, not
  of the failure arms you named.** Enumerate every exit site by its position relative to the
  first write (the structural-enumeration seat's table is the instrument), resolve every
  precondition before that write, and arm one handler across the whole window. A claim
  scoped to "these codes clean up" is true and useless when the failure that fires is a
  different one.
- **A text anchor on a tool's output is blind to decoration.** Ask what shape the producer can
  emit that the stub never has: colour, locale, a Windows separator, a wrapped line.
- **A stateless stub cannot pin a "returns to green" arm, and a stub whose baseline branch
  always prints `[]` cannot reach the runner's own refusals.** Give the stub builder a
  stateful flag and a runner-logic flag by default; the arm-deletion mutant is the litmus.
- **A pre-existing suite that is green on residue is a test of the defect.** Closing a
  residue class will break it; that break is the confirmation, not a regression.
- **Same-host, same-actor review panels share an environment-shape blind spot by
  construction.** The coverage consult's "which class is absent" question is cheap and
  yielded five verified defects here — it is mandatory at ≥6 findings for exactly this reason
  (see the 2026-09-14 redactor learning below).
- **Reading prose is not executing it.** A constrained dry run of a skill by a subagent is a
  QA instrument distinct from review; budget one for every skill-prose PR.
- **Before writing a listed-form predicate, measure the population's dominant call-form.**
  Four literal forms felt complete and covered one of twelve real sites.

## Prevention

- A plan's Guard Contract for any script that writes into a user's tree carries an exit-site
  table by position relative to the first write, and a row per precondition proving it
  resolves BEFORE that write.
- Stub builders expose `stateful` and `runner-logic` flags; every anchor on tool text has a
  decorated-output row; every new shell suite sources `git-fixture-env.sh`.
- QA for a skill-prose change runs a constrained dry run (no post / no write / no credentials)
  against a real, already-diagnosed issue and reports unfollowable sentences.
- Run the coverage consult whenever ≥6 findings survive; pass it the finding list and ask for
  the absent class, then verify each lead against the diff before acting on it.

## Session Errors

1. **(forwarded, plan) A background timer used a process-grep shape the hook blocks (full
   command line); replaced.** — Recovery: rewrote the poll. — **Prevention:** poll with the
   Monitor tool on a bounded, anchored pattern (`hr-monitor-not-run-in-background-for-polling`).
2. **(work) `sed s/8297/8351/` on a copied poll script also rewrote its worktree path; the
   Monitor dedup keyed on a timestamp fired every minute.** — Recovery: fixed the path, re-armed
   keyed on state. — **Prevention:** scope a `sed` to the token you mean, and key a Monitor dedup
   on the state string, never on a clock field.
3. **(work) A heredoc containing a literal process-grep string, an `rm -rf` under `/var/tmp`,
   and a `run_in_background` poll were each hook-blocked.** — Recovery: reworded, `mkdir -p`,
   Monitor. — **Prevention:** those hooks are the enforcement; write scratch setup as `mkdir -p`
   and poll with Monitor from the start.
4. **(work) `components.test.ts` rejected a backtick `` `scripts/…` `` file reference in ship
   notes.** — Recovery: markdown links. — **Prevention:** a `scripts/`/`references/` path in a
   SKILL.md body is a markdown link, never a code span (the lint is the enforcement).
5. **(work) The shard exit gate read `CAPACITY_CONTENDED` from 09:54 to 10:57 (two sibling
   full gates).** — Recovery: recorded as contention-refused, ran the consumer/vocabulary
   substitute set. — **Prevention:** `bash scripts/test-all.sh --capacity` before queueing; the
   full battery is ship Phase 4 / CI (ADR-183).
6. **(work) Review setup `merge-tree` rc 1: `PROMOTED_FILES` collided with #8312.** — Recovery:
   merged main, union resolution. — **Prevention:** run the merge-tree probe before spawning the
   panel (review §1 already says so); a promotion edit is the modal conflict.
7. **(work) `cleanup-merged` skipped a worktree because a lease file named a dead pid.** —
   Recovery: `kill -0` the pid, removed the lease. — **Prevention:** the lease reader should
   `kill -0` its owner before honouring it — worktree-manager subsystem, not this PR; check for
   an existing tracker before filing.
8. **(review) The first `git commit` queued the full battery behind two sibling flocks
   (`bun-test` fires on a staged `.ts`); the 600 s wrapper timed out; the queued tree held only
   `flock`/`sleep` (no suite running) and was terminated children-first; retried with
   `LEFTHOOK_EXCLUDE=bun-test`, the branch's precedent (41087135f).** — Recovery: as stated,
   exclusion cited in the commit body. — **Prevention:** before a commit that stages a `.ts`,
   read `--capacity`; if contended, exclude `bun-test` with the ADR-183 rationale in the body
   rather than queueing an hour behind siblings.
9. **(review) markdownlint MD031 on a new fence (no blank line after it).** — Recovery: added
   the line. — **Prevention:** run `markdownlint` on every edited `.md` before committing.
10. **(review) A python edit script with a tuple typo aborted at parse time, applying none of
    its edits; noticed only because the next command showed unchanged output.** — Recovery:
    rewrote the script to a file with per-replacement count assertions. — **Prevention:** assert
    each replacement's count and re-grep the target after any scripted edit.
11. **(review) `t="$(physdir …)"` under `set -e` aborted on a missing `TMPDIR` — the #7399(c)
    class; caught by the new S-mktemp row.** — Recovery: `|| t=""`. — **Prevention:** every
    command-substitution assignment whose failure is a legitimate state carries `|| var=""`.
12. **(review) The task notification reported exit 0 for a failed `git commit` (the wrapper's
    status).** — Recovery: verdict read from `git log -1` / `git status`. — **Prevention:** a
    notification is liveness, never verdict (work/SKILL.md); read the tree.
13. **(review) `fixture-relative-assert` moved twice (17 → 19) and `fixture-env-adoption`'s
    ceiling tripped (26 > 25) — repo-global ratchets invisible to file-selected suites.** —
    Recovery: converted the suite, regenerated the baseline in the same commit. — **Prevention:**
    re-run the ratchet set after every edit to a script or suite, not once at the end.
14. **(QA) The plan's integration scenario called #6501 "closed"; it is OPEN (fix landed in
    #6998).** — Recovery: recorded. — **Prevention:** `gh issue view <n> --json state` before
    asserting status (`hr-before-asserting-github-issue-status`).
15. **(QA/compound) The dry run drove the real `iac-plan-write-guard.sh` with a synthetic
    `ssh root@…` payload and the hook wrote 2 deny + 2 bypass rows for
    `hr-all-infrastructure-provisioning-servers` into THIS worktree's live incident ledger —
    `CLAUDE_PROJECT_DIR` pointed at scratch, but the ledger resolves from the hook's own location
    (`INCIDENTS_REPO_ROOT` is the seam). Found by the Deviation Analyst's incident ingest; the
    rule-metrics aggregate had already been staged with them.** — Recovery: removed the four
    synthetic rows, re-aggregated, corrected the rung-3 sentence. — **Prevention:** any test that
    drives a real hook sets `INCIDENTS_REPO_ROOT` to scratch; the reproduce-bug rung-3 sentence
    now says so.

## Related

- [2026-09-14 — I tested both endpoints and left the wire between them unpinned](2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md) — the ratchet rule (#13) and the seam-vs-wire framing.
- [2026-09-10 — every assertion I wrote to prove the fix could be satisfied while the defect was live](2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md) — prefix pins and re-driving survivors.
- [2026-09-07 — every instrument I built to check my own work could not tell clean from never-ran](2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md) — notification vs verdict (#12).
- [2026-09-14 — the plan capped the message before it redacted it](security-issues/2026-09-14-the-plan-capped-the-message-before-it-redacted-it-and-a-config-is-not-a-consumer-boundary.md) — why the coverage consult is mandatory at ≥6 findings.
- ADR-071 §Amendment 2026-09-19 (#8288); ADR-230.
- Issues #8288, #8352; deferrals #8379, #8380, #8381.
