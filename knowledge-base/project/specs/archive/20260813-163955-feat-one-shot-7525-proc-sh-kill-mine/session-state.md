# Session State

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-08-13-feat-encode-pkill-recipe-as-proc-sh-plan.md`
- Status: **recovered from partial-artifact** — the planning subagent stalled (stream watchdog,
  no progress for 600s) after writing the plan body but before emitting its `## Session Summary`.
  Plan artifact: complete (selector=branch; frontmatter `branch:` matched).
- Plan artifact: complete (selector=branch)

### Errors

1. **Planning subagent stalled at 600s** (harness stream watchdog, not a plan defect). Recovered
   via the on-disk artifact selector — `## Acceptance Criteria` present, so planning had
   finished its expensive phases.
2. **Plan-review correctness arm did not land.** `## Plan Review` records the panel as
   `kieran-rails-reviewer` (correctness), `code-simplicity-reviewer` (YAGNI),
   `architecture-strategist` (placement), but the "Applied" bullets cover only the architecture
   and simplicity arms. The subagent's last emitted line was a statement that the correctness
   reviewer had returned five blocking defects and that it was verifying two of them before
   applying — it stalled there, so none were applied. A re-spawn of that single arm (not the
   whole panel — the other two arms' findings are already in the artifact) **stalled on the
   same 600s watchdog**, at the same point: verifying `run_suite`'s output shape, which AC5
   depends on. The arm was then completed **inline** against the runner source rather than
   spawned a third time. Two blocking defects found and fixed; both were self-defeating
   acceptance criteria (AC5, AC8) that would have failed against a correct implementation.
   See `## Plan Review` → "Correctness (applied on recovery)" in the plan.
   **Two consecutive subagent stalls at exactly 600s with no partial-output recovery is a
   harness signal, not a task property** — both agents were mid-`Bash` on ordinary reads of
   `scripts/test-all.sh`. Worth a follow-up if it recurs this session.
3. **`tasks.md` was never written** for this branch — the specs directory was empty on recovery.
   Not blocking: `/work` consumes the plan file.
4. **Session-start `cleanup-merged` timed out** at the 2-minute budget (26 live worktrees), and
   `worktree-manager.sh` emitted `SOLEUR_GIT_BARE_POISON git_dir=… extension=absent
   shared_bare=true wt_override=present branch=clean` on every invocation. Neither blocked this
   run — `branch=clean`, and worktree creation plus `draft-pr` both succeeded.

### Decisions

- **D1 — the helper ships inside the plugin payload:** `plugins/soleur/scripts/lib/proc.sh`,
  tested at `plugins/soleur/test/proc.test.sh`. Reversed from an earlier repo-root `scripts/lib/`
  draft on ADR-178 §2 (agent-executed `SKILL.md` is a consumer class) and ADR-179 evidence; the
  pointer lands in a shipped file, and a repo-root helper would repeat the #7409 exit-127 defect
  and be shadowable by a customer's own `scripts/`.
- **D2 — the suite lives at `plugins/soleur/test/`, not beside the library**, because shell globs
  do not cross `/` and `test-all.sh` covers `plugins/soleur/scripts/*.test.sh` but not
  `plugins/soleur/scripts/lib/*.test.sh`.
- **Two issue premises were falsified during planning and changed the deliverable:** (a) "register
  in `scripts/test-all.sh` by hand — nothing auto-discovers it" is wrong; the runner already globs
  the target directory, so hand-registration would double-run the suite and the plan proves
  auto-discovery instead (AC5); (b) "bracket-safe (`[t]est-all`)" is a `pgrep`/`grep` idiom with
  nothing to fool in a `/proc` walk — the property is kept but bought by self + full-ancestry +
  own-pgid exclusion.
- **D4 — mirror `test-contention.sh`'s `/proc` primitives, do not source it.** A shipped plugin
  file sourcing a repo-root library would reintroduce the ADR-178 defect; drift is pinned by
  code-anchored assertions (AC7).
- **D6 — `kill_mine` always prints `killed=N refused=M skipped_same_pgroup=P scanned=K`,** so
  "excluded by my own pgid guard" never renders identically to "nothing matched" and send the
  operator back to `pkill`.

## Review Phase

- Status: **BLOCK, resolved.** The panel found that the tool shipped the defect class it
  exists to close. Every finding was `pr-introduced`, so every one was fixed inline — no
  scope-out is available for a finding the PR itself introduced.
- Fix commit: `9891e5da5`.

### Panel

Classified **code** class, **design-risk yes**. 8 agents spawned report-only (with 8
concurrent agents and a fix-inline default, agents read each other's uncommitted edits and
misattribute them). `semgrep-sast` replaced by `shellcheck` — this is a bash-only diff and
OSS semgrep's tree-sitter bash parser matches ~0 rules, so its "0 findings" would be vacuous.

**All 8 agents died**: 7 on a session limit, 1 on the 600s stall watchdog. They were
**resumed from transcript**, not respawned — two had partial results that a fresh spawn would
have re-derived. Resumed in a batch of 3 (highest-value seats for a guard PR: structural
enumeration, test-design, security) rather than all 8, since 8 at once is what exhausted the
quota. Batches 2 and 3 were never run: `proc.sh` was substantially rewritten by the fixes, so
reviewing the pre-fix design would have been reviewing machinery that no longer exists.

### Findings (all fixed inline)

1. **P1 — row injection.** `_proc_scan` emitted `class<TAB>pid<TAB>cwd` and `kill_mine` parsed
   it back. A directory name may contain a newline, so a process whose cwd was a directory
   named `evil\nsignal\t31337\t/pwned` forged a `signal` row; pid 31337 reached the kill site
   never having matched the pattern. Reproduced independently before fixing. The carrier was
   correctly *refused* — the refusal path was the vector.
2. **P1 — pid never validated numeric.** `kill -0 -1` exits 0, so a forged `-1` builds
   `kill -TERM -1`. `/proc/0` also passed the glob, and `kill -TERM 0` signals the caller's
   process group.
3. **P1 — dry-run seam wrong in both directions.** `PROC_SH_DRY_RUN=true` performed a REAL
   kill; an inherited `=1` silently sent nothing.
4. **P1 — failed kill swallowed** and counted as `killed=1`.
5. **P1 (test) — the suite could not fail.** No assertion floor; and `mutate()` ran inside a
   command substitution so its `fail()` incremented `FAIL` in a **subshell** — the suite
   printed a FAIL and exited 0. That is the subshell defect `work/SKILL.md` documents,
   committed three lines from the pointer to the rule this PR adds.
6. Also fixed: ` (deleted)` cwd string-matched instead of refused; boundary accepted `/` and
   relative paths; nested worktrees under the boundary classified as ours; a pattern
   containing `/` could never match and reported `killed=0`; `mapfile -d` needs bash 4.4 while
   macOS ships 3.2 (silent total failure on a file that ships to customers);
   `timeout`/`env`-wrapped runs invisible.

### Errors made during the review pass

- **A backtick inside a double-quoted test label is command substitution.** Two labels
  executed their own contents; one produced a syntax error that masked a real wrapper-matching
  bug. Same trap `work/SKILL.md` documents for commit messages.
- **A grep assertion matched its own pattern string.** `AC11a` scanned this suite for
  `pkill|killall` and was satisfied by the literal inside the sibling assertion's own regex.
  Fixed by anchoring on command position **and** using the bracket trick — the one place it is
  the right tool, since this is a grep over source.
- **The first floor-verification instrument was broken.** Mutated copies were placed in a
  sandbox where `../scripts/lib/proc.sh` does not resolve, so all three runs aborted at the
  helper check and returned rc=1 that read exactly like the guard firing. A green control
  caught it. Copies must sit beside the real suite.

### Components Invoked

- `soleur:plan` (via isolated planning subagent)
- `soleur:deepen-plan` (invocation unconfirmed — the subagent stalled before its Session Summary;
  the artifact carries `## Research Insights` and `## Research Reconciliation`, so the research
  fan-out completed)
- `soleur:plan-review` — panel of `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`; architecture + simplicity applied by the subagent, correctness
  re-run inline on recovery
- `worktree-manager.sh create` / `draft-pr` → PR #7531
