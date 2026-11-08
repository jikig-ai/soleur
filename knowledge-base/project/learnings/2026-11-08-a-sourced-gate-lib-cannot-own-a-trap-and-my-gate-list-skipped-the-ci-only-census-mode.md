# Learning: a sourced gate lib cannot own a trap, the ratchet has a CI-only mode, and an "equivalent" mutant was a missed input

PR #12414 (A-0: web-2 weight default 1 + the relay hello key mint). Review of a green local gate run still found defects, none in the headline change.

## Problem

1. The serve-mode wrapper in a sourced shell lib needed a private temp copy of a plan file. `mktemp` plus a `# lint-trap-ownership: ok` annotation silenced the per-site rule, but the file joined the census of trap-less tempfile owners (36 to 37), which `--check-highwater` enforces in CI only. My pre-push gate list ran the lint in default mode, so the ratchet went red unseen; two review seats found it.
2. I labelled a surviving mutation (the wrapper's default `case` arm falling through) "equivalent" on the argument that the inner grader refuses the same verbs. A test-design seat showed a `["read"]` pool entry reaches the remnant branch, because the grader's change filter drops `read` as well as `no-op`. The label had hidden the one fixture that mattered.
3. Guards added during the fix (F8 "literal inside the plan command", F6/V2 "count occurrences", the stray-reference check) were each deletable with the suite green, because they were written after the tests and had no row that reddened without them.
4. The 17-seat review wrote transcripts until the volume holding the harness tmp dir hit its quota and every Bash call failed for about two hours.

## Solution

- Do not use `mktemp` in a sourced lib: write the copy beside the plan file and open it exclusively (`dd conv=excl`, which also refuses a symlink; `oflag=excl` is not a flag), under umask 077 in a subshell, removing it on every normal path. This avoided both the trap (a lib must not replace the caller's EXIT trap) and the census growth, and the ratchet only moves down so the code is what changes.
- Pin each term of a predicate with its own fixture at the shape where it would otherwise be admitted (module-addressed, indexed, deposed, importing, `read`, two entries), and pin per-arm refusal text, because a refusal that returns 0 or prints nothing reads as a pass.
- Every new guard gets a mutant in the same commit (same-line duplicates, heredoc defaults, a literal moved after the pipe or into an echo), and the harness's pristine copy lives outside the scanned tree.

## Key Insight

The census/ratchet modes a CI job runs are part of the gate list; read the CI step, not the lint's default mode. An "equivalent mutant" is a claim about the input space and needs the enumerated inputs next to it, the same as any universal claim.

## Session Errors

- **Brief premise false (release push arm stays out)** — Recovery: CTO ruling 7, disclosed in the PR body. Prevention: verify a path-filter claim with `gh run list --workflow <release> --json headSha,event` matched on full SHA before writing it into a brief.
- **Gate list omitted `--check-highwater`** — Recovery: wrapper rewritten without mktemp. Prevention: derive the pre-push list from the CI steps that run the same script (`grep -n 'lint-trap-tempfile-ownership' .github/workflows/*.yml`), including each flag.
- **"Equivalent" mutant label wrong** — Recovery: fixture pn13 and a rewritten work-log line. Prevention: write the enumerated input shapes beside any equivalence claim; a `read`/`no-op` filter drops two verbs, not one.
- **New guards deletable at green** — Recovery: fix-round mutants (F8m3-m8, F6m1, V2m1-3, T4 clause table). Prevention: mutate every guard you add in the commit that adds it.
- **Mutation battery harness bugs** (loop variable shadowing the caller's file variable; sandbox missing an archived file so the control was red) — Recovery: fixed and re-run with a green control. Prevention: `local` every loop variable in helpers; read the control line before any row.
- **Tmp-volume quota exhausted by subagent transcripts** — Recovery: waited for space to be freed; nothing deleted. Prevention: scratch and logs in `/var/tmp` via `mktemp`; spawn fewer, shorter-lived seats on a nearly full volume. (Harness-level; not fixed here.)
- **Hook blocks** (`git stash list`, a commit sharing a call with `export TMPDIR`, `rm` inside `bash -c`) — Recovery: reissued as separate plain calls. Prevention: stage in its own call, commit in the next.

## Tags

category: workflow-issues
module: infra-gates, review
