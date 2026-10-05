# Session state — #7537 orphan process reaper

Written 2026-08-20, updated on resume. Branch `feat-one-shot-7537-orphan-process-reaper`,
worktree `.worktrees/feat-one-shot-7537-orphan-process-reaper`, draft PR 7641, closes #7537.

## Position in the pipeline

`/one-shot` Steps 0a/0a.5/0b/0c and **Steps 1-2 (plan + deepen-plan) are COMPLETE.**
Next step is Step 3 (`/work`). Nothing of the feature is implemented yet — the branch carries
planning artifacts only (`git diff origin/main...HEAD --name-only` = plan + tasks + this file).

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-08-20-feat-orphan-process-reaper-deleted-cwd-conjunction-plan.md`
- Status: **complete** — continued IN PLACE from the prior session's checkpoint; exactly one plan
  file matches this branch's `branch:` frontmatter selector, and it now carries
  `## Acceptance Criteria` (the completion predicate).
- Tasks derived to `knowledge-base/project/specs/feat-one-shot-7537-orphan-process-reaper/tasks.md`.
- Collision gate re-probed after planning per the post-plan clause: plan declares `closes: 7537`,
  #7537 is still OPEN, and planning did NOT re-target — so no unchecked ref was introduced.

### Errors

None from the registry — `soleur:plan`, `soleur:plan-review` and `soleur:deepen-plan` all resolved
and ran, so the prior session's halt condition did not recur. One self-inflicted error, caught and
repaired in-phase: the `skipped_foreign_uid` counter was cut on a simplicity recommendation, which
silently made mutation row M5 an equivalent mutant; the security review caught it and it was restored.

### Decisions

- **The issue's own conjunction identifies the WRAPPER, not the load.** Measured: 31 processes
  box-wide carry `fd/255` (30 bash + 1 `dbus-daemon`), and in the synthesized battery shape the
  `python3` child burning CPU shares the unlinked cwd inode but has NO `fd/255`. The issue's
  discriminator is preserved verbatim as an **anchor**; a confirmed anchor then authorizes a reap
  **set** sharing its cwd `dev:inode`, with every gate restated per member.
- **`st_nlink == 0` replaced the entire discriminator.** Measured 0 for a genuinely deleted cwd, 2
  for a healthy directory literally named `work (deleted)`. It obsoletes the `' (deleted)'` suffix
  test, the `%d:%i` comparison, and the two-stat window at once.
- **Trigger is `test-all.sh`'s preamble running `report`; nothing invokes `reap` automatically.**
  The first draft's cron-adjacent channel was refuted by reading the code.
- **Kill authority stayed off the hot path.** The CTO's "reap on day one" was not adopted as given —
  the conjunction has never been observed firing on a real orphan, so a reader's judgment gates
  every signal.
- **~1/3 of the implementation surface was cut** (stdout veto, two-strike state file, bespoke
  ledger, post-signal polls, exit code 10, live `report` registration, Guard 2), then ~10 new
  mutation axes were added from the security and test-design passes.

### Components Invoked

`soleur:plan`; `soleur:plan-review`; `soleur:deepen-plan`; agents `repo-research-analyst`,
`learnings-researcher`, `cto`, `spec-flow-analyzer`, `dhh-rails-reviewer`, `kieran-rails-reviewer`,
`code-simplicity-reviewer`, `architecture-strategist`, `security-sentinel`, `test-design-reviewer`,
`observability-coverage-reviewer`, plus a general-purpose verify-the-negative pass; scripts
`lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `probe-verb-gate.sh`; `gh` probes and
direct `/proc` measurement on this box.

## Environment hazard

`git commit` hangs forever on this box: `commit.gpgsign=true` + `gpg.format=ssh` routes to
GNOME Keyring's agent (`SSH_AUTH_SOCK=/run/user/1001/gcr/ssh`), which raises a GUI passphrase
prompt nothing can answer. `ssh-add -l` returns 0 in this state, so it is useless as a check.
Workaround: `git -c commit.gpgsign=false commit`. Filed as issue 7644. Nine commits from other
sessions were wedged when this was written — **do not kill them**, they are other sessions'
in-flight work.

## Collision gate — already resolved, do not re-litigate

PR 7538 surfaced in both the `linked:issue` and body-text probe sets and shares
`scripts/test-all.sh` with #7537's body. It is a **citation, not a collision**: 7538 closes
three sibling issues from the same incident class, never touches `scripts/tmpfs-guard.sh`, and
the path overlap traces to #7537 enumerating its siblings ("one of four items in that class").

Separately: `apps/web-platform/infra/orphan-reaper.sh` already exists on main. It is a 33-line
reaper for stale `.orphaned-*` workspace **directories** on the prod web host — a pure name
collision. Do not reuse that name; pick one that says "process".

## Binding constraints (from the issue body — read it with `gh issue view 7537`)

- Detector keys on deleted `cwd` **plus** deleted `BASH_SOURCE`/`fd 255`.
- Explicitly EXCLUDE `exe` — a `claude` self-update unlinks the running binary (~11 live hits).
- NEVER match on stdout/stderr alone: that shape **is** this repo's own `scripts/tmpfs-guard.sh`
  cron instance (verbatim pid 704313 case in the issue, 75s old and healthy). A reaper keyed on
  it kills the tmpfs guard on its next cron tick.
- Fail toward **leaving the process alive** on any unreadable `/proc` entry, unparseable link,
  or ambiguity.
- Own-uid only, no sudo, matching `tmpfs-guard.sh`'s posture. Do not change that script's
  fd-skip behaviour — it is file-scoped and correct for live runs.
- Zero hits from the four-way conjunction on the probed box is evidence of **specificity** in a
  sample containing no orphan. It is **not** evidence of sensitivity. Prose must preserve this.

## Test obligations (all binding)

- Positive arm, synthesized per `cq-test-fixtures-synthesized-only`: a process whose cwd
  directory and executing script are both unlinked after launch — must be flagged.
- Negative arm, the real false positive: the `tmpfs-guard.sh` cron shape (deleted stdout, live
  cwd, live script) — must NOT be flagged.
- Mutation battery: every new check mutated out individually, suite confirmed to redden. Prior
  art to read first:
  `knowledge-base/project/learnings/2026-08-14-every-defect-was-a-guard-that-could-not-fail-and-no-instrument-found-more-than-two.md`
  — the preceding PR in this area shipped nine guards that could not be driven red.
