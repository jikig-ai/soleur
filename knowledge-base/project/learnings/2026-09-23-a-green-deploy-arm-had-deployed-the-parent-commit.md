---
title: "A green deploy arm had deployed the parent commit, and the ship phase recorded no errors at all"
date: 2026-09-23
category: workflow-issues
tags: [ship, deploy, ci, head_sha, git-shallow, compound, session-errors]
issues: [8211, 8511, 7924, 8510, 8518]
prs: [8564]
---

# A green deploy arm had deployed the parent commit

Three ship-phase errors from PR #8511 (host-key pinning, merged 2026-09-22, merge
`0aa119838b`), captured while landing PR1 of #8211. The first two were known to the operator
as prose; measuring them changed what each one is.

## 1. A green release run deployed a different commit

**Measured.** Three `Web Platform Release` runs carry `head_sha=0aa119838b` — #8511's merge SHA.
Run `35726731583` (12:21:56Z) reported deploy success AND live-verify success. Its
`resolve-target` log shows it checked out and deployed `ec68b3ec42`, which `git merge-base
--is-ancestor` confirms is PR #8543's commit, the **parent** of the merge. Only run
`35728123127` (12:35:39Z) deployed `0aa119838b`.

**Why it happens.** A `workflow_run` run's `head_sha` is main's tip when the *triggering* CI
completed, not the commit the deploy applies. A lagging arm therefore gets stamped with the
newer merge's SHA while deploying the older one. Selecting the first SHA-matching run and
reading its green would have declared #8511 deployed while production ran #8543's build.

**The trap is that both runs are green and both carry the right SHA.** Nothing about the arm
reports the mismatch; the only witness is its own `resolve-target` log.

**Prevention:** `plugins/soleur/skills/postmerge/SKILL.md` Phase 3.7 already carries the
resolve-target-log identity check (landed 2026-09-20), but it exists only as copy-pasted bash
inside prose. Extract it into a tested script so it cannot be skipped or mistyped during a
live ship.

## 2. A fix verified against the latest failure, past checks that were already red

**Measured.** Commit `bad66fb9c0` says in its own body that two ratchets were red on the
branch's last completed run (`74b8f8d`, 2026-09-21T19:58Z) and still red at HEAD — over twelve
hours and an intervening merge later. That fix commit's own CI run was `cancelled`, because the
next commit was pushed 20 seconds after it. That next run, `35718638506`, came back `failure`
with `test-scripts (1/3)`, `(2/3)`, `(3/3)` and `test` all failing. No later commit mentions
those checks. The final head is all-green.

So the branch went green without anyone diagnosing the failure that appeared in between. The
fix was checked against the two ratchets it targeted, not against what broke on the next run.

**And the artifact that should have caught it recorded nothing.** The archived
`session-state.md` for that feature carries only `## Plan Phase` with `### Errors: None`. A
ship phase with three distinct errors produced an artifact asserting there were none, which is
worse than an empty one: it reads as a clean session.

**Prevention:** `plugins/soleur/skills/ship/SKILL.md` pre-merge gate — diff check NAMES across
the branch's whole CI run history, not just the current head, before declaring ready to merge.

## 3. The shared repo went shallow, and the cause is still unknown

**What is measured.** `.git/shallow` is now absent, consistent with the recorded `git fetch
--unshallow`. `git reflog` for 12:4x on 2026-09-22 is empty. A scan of ~200 recent Actions runs
found nothing created between 12:30 and 12:49 that day, which points away from CI and toward a
local invocation. #7924 records the detection gap: `scripts/lib/repo-write-boundary.sh`'s
`_repo_state` never sampled `.git/shallow`, so a `--depth=1` fetch into the live repo — shared
across every worktree through the git common dir — was invisible to the write-boundary guard
and to `git status`. PR #8510 closed that gap, merging at 15:27:13Z, two hours and thirty-nine
minutes AFTER 12:48. `apps/cla-evidence/scripts/ccla-add.sh:337` still performs a `--depth=1`
ledger fetch.

**What is not measured: which process did it.** A local `ccla-add.sh` run is the plausible
candidate and nothing more. No log ties any process to 12:48. Recording it as the cause would
be naming a cause nobody observed — the defect class this repo's own markers exist to prevent.

**Prevention:** `apps/cla-evidence/scripts/ccla-add.sh` — never fetch `--depth=1` against a
live checkout; confirm #8510's redirect to scratch repos covers ad hoc invocation, not only the
CI-reachable batteries.

## Session Errors (PR1 of #8211)

- **The plan's ADR ordinal was already taken.** It specified ADR-238; that ordinal is used on
  `origin/feat-8322-affected-test-gate`. Caught by probing all `origin/*` refs before authoring.
  Shipped as ADR-239. **Prevention:** already the documented class (branch-picked ordinals are
  provisional until re-checked against fresh `origin/main` immediately before merge); the probe
  is in the plan's own task list and it worked.
- **The plan's legal citation named the wrong register entry.** It said to mark PA-2 (g)(13),
  which is a Storage orphan-path audit. `grep -c repoint_luks_mount` returns exactly 3, at
  PA-36 (g)(1), PA-1 (g)(13) and PA-2 (g)(17). **Prevention:** grep the mechanism, not the
  remembered citation — index by subject, never by phrasing.
- **The plan's census arithmetic did not hold on the tree.** It claimed two named exemptions
  leave exactly four store-acting payloads; `git-data-luks-reopen.sh` is a fifth `file()`
  payload and neither exemption. Resolved by making the qualifier mechanical (a payload is
  store-acting iff it reads `GIT_DATA_REPO_ROOT`). **Prevention:** derive a guarded set from
  the tree; never hardcode its cardinality in prose.
- **My own contract prescribed a command that would fail at boot.** Contract C5 wrote `env -i
  PATH=/usr/bin:/bin … runuser`, but `runuser` lives in `/usr/sbin` on Ubuntu, so the bare
  spelling resolves against a PATH that cannot find it. Caught by an implementation agent.
  **Prevention:** when pinning an `env -i` PATH, resolve every binary named in that command
  against it.
- **A must-PASS row was passing for the wrong reason.** The transport-wrapper accepted case fed
  `/dev/null`, so `git-upload-pack` advertised and died rc 128 — indistinguishable from a
  refusal by exit code. **Prevention:** a must-PASS row whose subject can exit non-zero for an
  unrelated reason needs an assertion on the reason, not the code.
- **I conflated two similarly-named linters.** I ran `lint-shell-capture-exit.py --changed
  --base origin/main`; `--changed` belongs to `lint-shell-trace-credential-refusal.py`. The
  argument parser rejected it loudly, so nothing was mis-measured. **Prevention:** read the
  runner's own invocation (`grep run_suite scripts/test-all.sh`) rather than recalling a flag.
- **A commit's battery queued 30+ minutes behind five sibling worktrees.** Staging a `.ts` file
  triggers lefthook's full battery, which serialises on a repo-global lock; three sibling gate
  runs held it, one for over two hours. Resolved by killing only this worktree's processes
  (verified by `/proc/<pid>/cwd`, including the `flock` waiter, which survives killing the
  runner) and re-committing with `LEFTHOOK_EXCLUDE=bun-test`. **Prevention:** run
  `scripts/test-all.sh --capacity` BEFORE a commit that stages `.ts`, not after it hangs.
- **My monitor was silent for its full 30 minutes and I read nothing from it.** The filter
  matched output strings, but lefthook buffers per command, so a queued battery emits nothing
  at all — silence looked identical to progress. **Prevention:** when watching a queued job,
  monitor liveness (file growth, process state) rather than only content patterns.
- **Six agents died mid-flight on an account-level weekly rate limit.** Their partial work
  survived on disk and resumed cleanly because each brief told the resumed agent to audit the
  tree before editing. Not a workflow defect. **Prevention:** none needed; the resume-by-audit
  brief shape is what made it recoverable, and is worth keeping.

## Triage

| Item | Recurring? | Disposition |
|---|---|---|
| Deploy arm selected by `head_sha` | recurring | file-tracked — extract the identity check into a tested script (postmerge) |
| Fix not re-checked against earlier CI failures | recurring | file-tracked — ship pre-merge gate diffs check names across run history |
| `session-state.md` says `Errors: None` for a session with errors | recurring | file-tracked — same ship gate |
| Repo went shallow, cause unknown | recurring | file-tracked — `ccla-add.sh` ad hoc path (#7924/#8510 follow-up) |
| Plan cited the wrong register entry | one-off | recorded; the grep-the-mechanism habit already exists |
| Plan's census arithmetic stale | one-off | fixed inline by deriving the set |
| Contract's `runuser` PATH | one-off | fixed inline |
| Vacuous must-PASS row | one-off | fixed inline |
| Linter flag conflation | one-off | recorded |
| Battery queued behind sibling gates | recurring | recorded — `--capacity` before staging `.ts` is already documented |
| Monitor silent on a queued job | recurring | recorded — widen to liveness, documented in the Monitor tool's own guidance |
| Agents killed by rate limit | one-off | external |
