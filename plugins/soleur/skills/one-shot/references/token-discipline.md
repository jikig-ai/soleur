# Token discipline

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

Loaded from [one-shot/SKILL.md](../SKILL.md) — moved verbatim (byte-ceiling extraction, #9403). **Read at pipeline start, before Step 0.**

Soleur bills its operators for these tokens. **This does NOT license skipping a step.** Every
step in the anti-bypass protocol above runs, `soleur:deepen-plan` included — `PLAN_PIPELINE_PREFIX`
in `workflow-fidelity.ts` is the contract and it is not negotiable here. What follows is how
to run those steps without waste.

**The measured cost driver is not the panel size — it is rework and restatement.** On PR
#7325 the classifier was CORRECT to pick the full panel (103 added source lines across 23
files); the cost came from three habits below, each of which multiplies.

1. **Do not restate.** Prose is review surface priced per token, and copies drift. Write the
   rationale once at the artifact that owns the decision, then point at it with a content
   anchor (`work/SKILL.md` §single-source). On #7325 ~300 lines across 7 files was the bulk
   of the review surface, and two copies of one probe table CONTRADICTED each other before
   any reviewer saw them.
2. **Verify a measurement before it propagates**, at the granularity you will claim it
   (`work/SKILL.md`). One false fact reached 4 files, 2 issue comments, and a review agent's
   top finding; the re-probe that falsified it took 15 seconds.
3. **Spawn the agent set ONCE, complete** (`review/SKILL.md`). A late gap-closer costs a whole
   extra fix → CI → correction round.
4. **Re-run a suite only when its inputs changed.** A green full-suite run against commit A
   still covers commit B when B touches only docs — verify the delta with targeted suites and
   say which commit the full run covered. **On RESUME, this heuristic inverts: a verification
   claim you inherited (a handoff, a prior session's summary, `session-state.md`) is a statement
   about a tree that may no longer exist — re-run it before relying on it.** #7397 resumed on
   "bun shard rc=0 (2419/0)"; that shard was RED, reddened by a commit made after the claim. See `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.
5. **Bound every command's output.** `git grep` over a tree containing generated JSON returns
   megabytes on one "line": use `':!*.json'`, `--name-only`, `| cut -c1-200`.
6a. **A fan-out agent in a SHARED worktree is write-only — the lead commits.** Two
   agents holding one `.git/index.lock` deadlock, and the failure does not look like a
   deadlock: `git commit` simply never returns while lefthook runs, so it reads as a slow
   gate. Worse, killing the wrapper leaves the suite runs it spawned ORPHANED and still
   consuming the machine — resolve those by each process's own working directory before
   signalling anything. Give fan-out briefs an explicit "run no git write commands"
   constraint and apply every result yourself from one known SHA. This is the *committer*
   half of the reader-side contamination note in `review/SKILL.md` §Sharp Edges. **Why:**
   #7829 — a PR-1 agent was told to commit while the lead committed; ~20 minutes lost to a
   lock neither side owned, plus three orphaned full-gate runs.

6. **Delegate wide reads to a subagent** (`cm-delegate-verbose-exploration…`) — keep the
   conclusion, not the file dumps.
7. **Poll with a bounded, anchored pattern — on the marker's SHAPE, plus the rc file.** Match
   `^=== [0-9]+/[0-9]+ suites passed ===$` and read the rc file, never a bare token that also
   appears in a PASS line, and never `pgrep` a pattern your own poll command contains. Polling
   the *green* spelling `N/N` only is safe against a false green but not against a false
   dismissal: a run with a terminated suite is `N<M`, so the poll never matches, the `Monitor`
   runs out its clock, and `{no marker, clock timeout}` is byte-for-byte the harness-reap
   signature that `work/SKILL.md` says to walk away from. **Since ADR-181, `N/N` is not even the
   ordinary LOCAL spelling** — a diff touching neither heavy battery nor `apps/web-platform/infra/`
   declines three suites, so a healthy local run reads `N-3/N`. Poll the marker's SHAPE and read
   the rc file. The four cases: marker + rc 0 = green; marker + rc 3 = a suite was terminated
   (UNRESOLVED — coverage not obtained, re-run that suite in isolation); **no marker + rc 4 =
   REFUSED before anything ran** — either `SOLEUR_SUBAGENT=1` was exported (a convention; the
   harness does NOT set it, so this does not fire merely because you are a spawned agent), or a
   sibling full-gate run is already in flight (#7553, the case that actually fires). The message
   names which. Either way: run your own targeted suites, not the gate; no marker + no rc file = harness reap, not
   your diff.

8. **A full gate reads the LIVE tree: either stop editing the worktree until it ends, or run it
   from a detached worktree at the SHA being certified — and a Monitor that re-greps a growing file
   must emit only lines past its last count, resolve the runner's PID by `/proc/<pid>/cwd` (never
   the `setsid` wrapper's), and heartbeat inside its own ceiling.** **Why:** #8210 — two full-gate
   runs were edited underneath (one 11 commits behind HEAD by the time it reported), so a green from
   either certified nothing and a red charged three reds to the branch that one cause explained;
   one Monitor re-echoed every matched line each loop, one watched a wrapper PID that exited at
   once, and one emitted only after a 40-minute inner loop so two silent expiries read as stalls.

**Report cost honestly.** If a run was disproportionate, say so and name the cause — the
operator paid for it and cannot see the breakdown.
