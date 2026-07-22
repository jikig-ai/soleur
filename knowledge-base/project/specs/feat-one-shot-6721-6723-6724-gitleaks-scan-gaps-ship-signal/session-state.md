# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-19-fix-three-structurally-unfailable-gates-plan.md
- Status: complete

## Work Phase
- Status: complete (tasks 60/64; the 4 open items are the full-suite gate result
  and three PR-body items owned by `/ship`)
- Branch synced with `origin/main` mid-work — main had moved
  `plugins/soleur/skills/review/SKILL.md`, the exact file the #6723 path
  carve-out anchors on, so AC11 was re-run against the merged tree rather than
  the pre-merge one.

### What the prior session's resume prompt got wrong
Recorded because the checkboxes are not a reliable progress signal:
- `tasks.md` read 0/64 while Phase 1 had already landed and Phase 2 was
  substantially written. Real progress was derived from `git log @{u}..HEAD`
  and `git diff`, per the resume prompt's own warning.
- The prompt listed "the Phase 1 merge-commit test file" as remaining; it was
  already committed at 276 lines.
- The plan asserted the `.openhands` hook copy was "byte-identical" to the
  `.claude` one. It is not (4200 vs 12437 bytes), and its Signal 2 had drifted —
  matching only the legacy `refactor:` subject. Verified rather than assumed.

### Errors
- **T-V2 was vacuous on first write.** Its fixture commit subject was
  `review: no findings`, which matches the legacy Signal 2 pattern, so removing
  trailer support from the hook left the test GREEN — it proved nothing about
  the trailer it was named for. Caught by mutation, not by review. Subject is
  now neutral; the mutation is caught.
- **Two DSN literals shipped in explanatory comments** (`gitleaks-rules.test.sh`
  :182 and :208). The fixtures were correctly runtime-assembled; only the prose
  explaining them was not. The 29/29 suite could not see it. Caught by the AC12
  baseline-vs-shipped working-tree comparison, and it mattered because this same
  PR adds `gitleaks dir` steps that would have redded on the introducing commit.
- **The first hook mutation battery reported UN-RUN twice** — nested
  shell/Python quoting mangled the patterns so neither edit landed. The
  landed-check caught it; without it, both would have been recorded as
  "SURVIVED" or "CAUGHT" on a file that was never modified.
- **A TypeScript sibling suite was missed by the touched-file loop.**
  `test/pre-merge-rebase.test.ts` was the 1 red suite of 194 at the full-suite
  exit gate. Every shell suite the change was written against was green, and
  the plan's own task 3.3.5 named this file — it was ticked without being
  done. Its bare-repo case seeded `todos/` on the filesystem WITHOUT
  committing, which the branch-scoped gate correctly stops honouring. The
  lesson is the existing one, re-confirmed: the touched-file loop is the inner
  loop, `test-all.sh` is the gate, and a plan task naming a file is not
  evidence the file was opened.
- **The background-task notification reported "exit code 0" while the suite had
  actually exited 1.** The command ended in `echo $? > rcf`, so the harness
  reported the trailing echo's status. Only reading the rc FILE surfaced the
  real result and the 193/194. A later run inverted it — notification said
  "failed exit 1" on a run that never wrote its rc file at all (killed when
  `/tmp`, a 4 GB tmpfs, filled with my own 211 MB verification clones; the
  casualty suite passed in isolation). Neither notification matched reality.
  The rc file was correct all three times.
- **P0, and the worst error of the session: my own PR failed its own
  secret-scan gate, and I nearly shipped it.** Commit `432081d46` carried the
  two DSN literals; I fixed them at the tip in a later commit, verified the
  CI-equivalent TREE scan was clean, and treated that as sufficient. It is not:
  `gitleaks git` scans a commit RANGE and reads the old blob, so
  `--no-merges origin/main..HEAD` returned rc=1 with both literals still live.

  This is the exact trap I had written into the runbook hours earlier ("a line
  waiver cannot clear a history finding"; "fixing the file the red gate names
  does not turn the gate green"). Writing the warning did not stop me applying
  the tip-fix reflex and then confirming it with the one scan shape that cannot
  see the problem. The tree scan's green was worse than no evidence — it was
  confirmation pointed at the wrong object.

  Found only because the operator challenged why UC-2 was parked; measuring
  UC-2 required a `-m --all` walk, which surfaced findings at commits I had not
  thought to scan — two of them mine. Nothing else in the pipeline would have
  caught it before CI.

  Fixed by rewriting the branch's history (reset --soft to origin/main, five
  clean commits, no merge), NOT by adding `.gitleaksignore` fingerprints —
  using the escape hatch this PR exists to make harder to abuse, to cover my
  own transient mistake, would have been the wrong instinct. The rewrite is
  provably content-only: tree hash `6d6fe7da9d8e406c7399afdf1333314243b8788d`
  identical before and after.

  **Generalisation worth keeping:** after fixing any secret-scan finding, the
  verification must use the SAME scan shape that produced it. A tree scan can
  never confirm a range finding is cleared.

### Decisions
- **#6723's "verified" candidate fix is insufficient and regressive.** Its
  `<[^>]+>` branch composes with the newly-permitted `@`/`:`, so a whole
  credential fits inside a "placeholder". Hardened to `<[^>@:]+>`; the path
  entry is anchored `^…$`.
- **#6721: took directions 1+2, not the issue's favoured 2-only.** `--cc`
  (offered as equivalent) is a silent no-op: 195 patch bytes, zero detections.
- **`-m` is NOT used on the PR/merge_group range.** The coupling question the
  plan recorded as INCONCLUSIVE was rebuilt with explicit preconditions and is
  now CONFIRMED: with `BASE_SHA = pull_request.base.sha` (main's tip), `-m`
  makes main-originated content count against the PR. `gitleaks dir` ships
  instead. Pinned by T7.
- **#6724's scope was larger than the issue.** The real `deny` gate is
  `pre-merge-rebase.sh`, with a third copy at `.openhands/`.
- **`fetch` moved above the gate but deliberately does not exit on failure** —
  keeping the fail-open-on-network behaviour at that position would have made
  "unplug the network" a universal gate bypass.
- **Hardening `xargs` with `-d '\n'` was considered and rejected on
  measurement**: the `--format=` + pathspec form emits no blank lines, and no
  `todos/` filename in the repo's entire history contains a space.
- **Bundling left intact** per operator direction; the split recommendation
  stays an open User-Challenge (UC-1), not silently applied.

### Open for the operator
- **UC-1** (split #6723 into its own PR) — UNRESOLVED, operator's bundling
  direction honoured.
- **UC-2** (`.gitleaksignore` instead of the path carve-out) — UNMEASURED. The
  inherited rejection premise does not hold here, but the alternative was not
  verified to the standard the plan holds itself to, so the anchored path entry
  ships.
- **AC18 impact: 17 of 18 open PRs will be denied at merge** until review runs
  or the trailer is emitted. This is the fix working, not a regression, but it
  is a real operational cost. Full table in `mutation-evidence.md`.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`, `soleur:work`, and agents
`security-sentinel`, `test-design-reviewer`, `architecture-strategist`,
`git-history-analyzer`.

### Not run
`soleur:plan-review` (DHH/Kieran/simplicity panel) — deepen-plan's agents
covered the substance-level classes. `/review`, `/compound` and `/ship` are the
remaining pipeline steps.
