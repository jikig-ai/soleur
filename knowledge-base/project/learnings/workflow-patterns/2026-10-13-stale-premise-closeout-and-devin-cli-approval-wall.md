# Learning: A nightly-failure issue can be a verify-and-close, and a staged bootstrap is surface-bound

## Problem

Two related sequencing traps surfaced in one integration-CI follow-through session (PR #10191, issue #10094):

1. **A "legs are red" issue was already fixed when picked up.** #10094 reported the
   slot-trigger and worktree-lease nightly legs red on run 38130672233. That run
   executed `main` @ `31ada28352` — five hours *before* PR #10001 merged the fix
   (stale test fixtures asserting a pre-mig-133 120 s contract against dev's live
   240 s function bodies). Planning against the issue's premise would have produced
   a fix for a non-defect; the correct work was verify + close + fold in the two
   scope-outs (#3373, #3221) the same evidence satisfied.

2. **A staged operator-bootstrap cannot run its write stages on Devin CLI.**
   `bootstrap.sh --stage <write> --apply` exits 75
   (`SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED surface=unknown`) because the approval
   receipt is minted by a Claude Code PreToolUse hook when the harness shows the
   operator the exact command — Devin CLI executes with no such prompt. An arc
   ordered bootstrap-first (#10058 → #9995) stalls at its first step on this
   surface.

## Solution

- **Premise-check a CI-failure issue against the run's headSha before planning a
  fix.** `gh run view <run> --json headSha,createdAt` + the suspected fix PR's
  `mergedAt` decides fix vs. verify-and-close in one minute. When the run predates
  the merge, the work is evidence collection (re-run legs, probe the live
  substrate), not a diff — and `pg_proc.prosrc` plus step-conclusion queries are
  the cheap probes.
- **Treat a staged bootstrap's surface requirement as an arc-ordering input.**
  `#N` in an issue's `auto_command` is not executable everywhere: read
  `SOLEUR-STAGE` lines for the write classes and check the session's surface
  (Claude Code + Soleur plugin = receipt-capable; Devin CLI/web = exit 75 wall)
  *before* promising the unblock order. Sequence the runnable fix issues first;
  the bootstrap waits for an attended Claude Code session.
- **Run staged scripts from a worktree, never the bare root.** A generated
  bootstrap calls `git check-ignore` on its `.env` sibling; from a `core.bare=true`
  CWD that exits 64 `SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED` — a false alarm caused by
  the working directory, not the ignore state.

## Key Insight

An issue's symptom text is a claim about a SHA, not about `main` today — the
failing run and the fix can coexist on the timeline. Deliberate non-fix, recorded
so it isn't re-litigated: the *class* (fixtures silently drifting behind
migrations) needs no new guard — the legs going red when dev's function body
drifted from the fixtures was the alarm working; #10001's named constants
(`STALE_*_AGE_S`) pin the contract the suite asserts, and a future migration that
changes it will red the leg again by design. And "the script is attended"
is a property of the *harness*, not just the operator: the approval mechanism is
a hook the surface either fires or doesn't, so surface capability belongs in the
same breath as the operator's availability.

## Session Errors

- **Ran `bootstrap.sh` from the bare-repo CWD** (via the `/home/jean` bind mount
  of `/data`): `SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED` exit 64 — `git check-ignore`
  needs a work tree. Recovery: created detached worktree `.worktrees/bootstrap-10058`
  and ran there. Prevention: staged scripts always run from a worktree; on this
  host the repo root is bare, so create a detached `--detach <path> main` first.
- **Staged write stage refused on Devin CLI:** `exit 75 surface=unknown` — no
  approval-receipt hook on this surface (issue #10208). Recovery: honest stop —
  reported "needs Claude Code with Soleur on your computer" per the staged
  contract; did not retry. Prevention: check the receipt surface before ordering
  an arc around a bootstrap step.
- **`test-all.sh --affected` red on `test-all-weight-drift` C8 under sibling
  contention** (nested bare-invocation arm refused, rc=4): isolated re-run after
  the gate cleared went 50/50 green — a contention flake, not a diff defect
  (issue #10209). Prevention: per the contention banner, confirm via isolated
  re-run before accepting a suite red under `CAPACITY_CONTENDED` conditions.
- **Planning subagent lacked a Task/Agent tool** (Devin subagent context): all
  prescribed fan-outs ran inline and were recorded in the plan Notes — surfaced,
  not hidden. Prevention: parent pipelines on Devin should expect spawned
  subagents to have `run_subagent`-less contexts; inline fallback is the recorded
  norm (#9855-era learnings carry the same note).
