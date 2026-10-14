---
module: System
date: 2026-09-19
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "ship battery red on `lint-shell-trace-credential-refusal-repo`: a regex variable named `S_PAT` read as a credential"
  - "ship battery red on `lint-trap-tempfile-ownership`: the hook suite's `mktemp -d` had no owning `trap … EXIT`"
  - "the wait-for-`measured_runs=0` launcher sat 110 minutes while four sibling worktrees started runs"
  - "`gh issue create --label action-required --label decision-challenge` refused: 'names no user-visible consequence'"
  - "preflight Check 4 resolver: 'dig is not installed' on a host whose prd Supabase URL is a custom domain"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [ship, test-battery, contention, repo-lints, preflight, decision-challenge, guardrails]
rule_id: wg-verified-work-ships-without-asking
related_issues: ["#8354", "#8330", "#8361", "#8366", "#8247", "#8135"]
synced_to: [ship, preflight, work]
---

# The shard I left for ship was the one that read every file

## Problem

PR #8354 (#8330) added a read-only arm to `.claude/hooks/pkill-self-match-guard.sh`. The
work phase ran the hook's own suite (128/0), the review round (10 seats), a mutation
battery and a doc-probe — every check that *names* the hook. AC12, `TEST_GROUP=scripts`,
was recorded in the plan as "run separately" and never ran.

The ship-phase full battery went red on two suites that name no file in the diff:

- `scripts/lint-shell-trace-credential-refusal-repo` — the hook's regex variable `S_PAT`
  matched the lint's credential-name heuristic (`_(TOKEN|KEY|SECRET|PASSWORD|PAT)$`) and
  was asked to carry an xtrace refusal.
- `scripts/lint-trap-tempfile-ownership` — the suite's A39 row allocates `mktemp -d` with
  no `trap … EXIT`, and the class-b population crossed its high-water (79 → 80).

Both are repo-wide lints: they walk every tracked shell file, so anything added under
`.claude/hooks/` is in their corpus whether or not a unit suite points at it. The shard
that was deferred was precisely the one that could see the new files.

Three more ship-phase frictions rode along:

- The Phase 4 launcher waited for `--capacity`'s `measured_runs=0`. On this host a fresh
  worktree started a run every 20–40 minutes, so the count went 3 → 1 → 3 and never reached
  zero in 110 minutes. Switching to the lock-queued form
  (`SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=25200`) acquired the
  `flock` after 87 minutes, with `LOCK_WAIT_HEARTBEAT` lines proving it was queued.
- The lint-fix commit invalidated that run (dirty tree). After merging `origin/main` and
  pushing, `battery-owed.sh` returned 42 — CI had verified the identical SHA — and that was
  the verdict; the local run was killed with `kill_mine` to free the lock.
- Ship 6/2.5 says to file the decision-challenge issue as `action-required` +
  `decision-challenge`; `guardrails.sh`'s filing gate refused until `meta/machinery` was
  added (a hook-scoped finding). That ledger is excluded from the operator digest, which
  is the surface 2.5 wanted — so the PR body's `## Model Dissents` section is what the
  operator actually sees.
- Preflight Check 4's canonical resolver needs `dig` for a custom-domain CNAME; the host
  has none. `resolvectl query --type=CNAME api.soleur.ai` and a raw UDP query to 1.1.1.1
  agreed on `<ref>.supabase.co`, which passed the canonical-hostname regex.

## Solution

- `S_PAT` → `S_RE` (it is a grep pattern, not a token); `trap 'rm -rf "$LIBLESS"' EXIT`
  on the suite's tempdir. Commit `4568a0833`; both lints green; suite unchanged at 128/0.
- Merge `origin/main`, push, `battery-owed.sh` → rc 42, stop the stale local run.
- `meta/machinery` on the dissent issue (#8366); dissents rendered in the PR body.
- CNAME via `resolvectl`, cross-checked; Check 4 PASS on distinct refs.

## Key Insight

A shard-scoped test run answers "did I break what I named?" A repo-wide lint answers
"does the tree still satisfy an invariant?" — and a new file is in that corpus by
existing. An AC that says "run separately" has not been run; it is the cheapest gate to
close at implementation exit and the most expensive one to discover at the last gate
(fix commit + main re-merge + a second CI cycle).

## Session Errors

1. **AC12 (`TEST_GROUP=scripts`) recorded as "run separately" and never executed** — Recovery: the ship battery caught both lints; fixed in `4568a0833`. — **Prevention:** an AC marked "run separately"/"at ship" is UNMET at work-phase exit — run the shard the diff maps to (work/SKILL.md now says so).
2. **`S_PAT` read as a credential by `lint-shell-trace-credential-refusal`** — Recovery: rename to `S_RE`. — **Prevention:** never suffix a non-secret variable with `_PAT`/`_TOKEN`/`_KEY`/`_SECRET`/`_PASSWORD` in a shell file; the lint's heuristic is the name.
3. **`mktemp -d` with no owning trap in the hook suite** — Recovery: `trap 'rm -rf "$LIBLESS"' EXIT`. — **Prevention:** every `mktemp` in a shell file registers a `trap … EXIT` (or `RETURN`) in the same scope; the trailing `rm -rf` does not count.
4. **Wait-for-`measured_runs=0` launcher unbounded (110 min)** — Recovery: lock-queued launch. — **Prevention:** after ~30 min of contention with NEW siblings arriving, queue inside the lock (ship/SKILL.md Phase 4 now says so).
5. **Local battery invalidated by the lint-fix commit** — Recovery: `battery-owed.sh` rc 42 after a main merge + push. — **Prevention:** merge `origin/main` BEFORE the first push once a fix is foreseeable, so the CI-verified path is available on the re-run.
6. **Decision-challenge issue refused by the filing gate** — Recovery: `--label meta/machinery`. — **Prevention:** ship 6/2.5 now names the exit and states that the PR body is the operator surface for hook-scoped dissents.
7. **`dig` absent for preflight Check 4** — Recovery: `resolvectl` + raw DNS cross-check. — **Prevention:** preflight Check 4 now prescribes `resolvectl query --type=CNAME` instead of SKIP when `dig` is missing.
8. **Own `-f` arm denied a `pgrep -af ship-battery-launch` liveness probe; `--body-file "$VAR/…"` refused by the issue gate** — Recovery: read the launcher's wait log / `list_runs`; literal path. — **Prevention:** one-offs; both gates' messages already carry the working form.
