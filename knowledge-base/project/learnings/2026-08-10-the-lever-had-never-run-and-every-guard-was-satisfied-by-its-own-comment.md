---
title: The lever had never run, and the guards that would have caught it were satisfied by their own comments
date: 2026-08-10
category: workflow-patterns
module: registry / review
issue: 7278
pr: 7343
tags: [review, mutation-testing, bash, doppler, credentials, worktree, fixtures]
---

# The lever had never run, and every guard was satisfied by its own comment

## Problem

PR #7343 shipped a read-only zot disk-inventory lever with an unusually careful PR body —
explicit epistemic bounds, a measured re-scope, a mutation battery reporting all five arms
load-bearing, 125 green assertions, and green CI. A 10-agent review found **five
merge-blockers**, the first of which was that **the lever had never executed at all.**

## The five, and what each teaches

### 1. A measurement obtained by a different path than the shipped one proves nothing

`doppler run --` injects the **whole** config. `soleur/prd` carries `ZOT_PUSH_USER` /
`ZOT_PUSH_TOKEN` alongside the three secrets the enumerator needs, so the script's own D7
entry guard (`refusing to start: ZOT_PUSH_* are populated`) fired on **100% of dispatches**
and the job exited 2 before probing the origin. The script's two requirements — pull+logs
PRESENT, push ABSENT — are unsatisfiable under whole-config injection.

The PR's headline numbers (266 blobs, 14.78 GB referenced, ~41 GB unaccounted) came from a
**hand-run prototype** over the same ingress. That is why nothing caught it: the prototype
and the shipped path shared a destination but not a credential-supply mechanism.

The near-miss is the real lesson. The comment directly above the call read *"All three live
in `soleur/prd` — MEASURED, not inferred."* That measurement was **correct and
incomplete**: it verified what was needed and never asked what else would be injected.

> Ask of any "I measured it" claim: measured through **which** path, and what else does that
> path carry?

Fix: `--only-secrets` (fail-closed by default), which also converts the ADR's
NON-MATERIALIZATION claim from an assertion into a structural property — the push credential
is never placed in the environment at all, rather than placed and then refused.

### 2. A counter incremented inside a command substitution is discarded — and the sibling that works is why the suite stays green

`link_next()` incremented `LINK_UNFOLLOWED`, but both call sites used
`nxt="$(link_next …)"` — a subshell. The increment vanished, the caller read the empty
result as "no more pages", and the sweep truncated while reporting
`enumeration_complete=true`.

The `MAX_PAGES` arms increment in the **parent** shell and work correctly. The suite's only
`Link` test exercised that arm. So the test passed and proved nothing about the arm the guard
was added for. The guard's own comment claimed *"a rejection is not silent"*; it was.

It needs no attacker: an **absolute** `Link` target is legal under RFC 8288 and the OCI
distribution spec, and the rooted-path check refuses it.

Fix: global-out (`LINK_NEXT_PATH`), mirroring `http_get`'s existing `HTTP_CODE`/`HTTP_BODY`
contract. Litmus: **if a function mutates state, it cannot return via stdout.**

### 3. A probe that keys on an issue's state must ask what that issue TRACKED

`registry-luks-blocker-6929.sh` gated PASS on #6929 being CLOSED. #6929's deliverable — a
guarded recut `workflow_dispatch` — shipped, so the issue closed. But **a vehicle existing is
not a conversion having happened**: the recut has never been fired.

Two things make this sharp:

- **The correct action armed the false all-clear.** Closing #6929 was right; its deliverable
  was genuinely on main. Doing the right thing is what made the probe fire.
- **No issue state anywhere encoded the posture.** #6895, which actually asserts
  "hcloud_volume.registry is plaintext ext4", is *also* closed.

Re-anchored on #7287 (the recut EXECUTION), with the PASS arm now saying it is a proxy and
telling the reader to confirm the recut ran. `encryption-posture-ledger.json` records
`live_verification: "unavailable"`, so a live at-rest probe is the real fix.

### 4. Fixture SHAPE and DIRECTION are coverage axes a mutation battery cannot reach

The PR arrived with a 5-arm battery reporting every arm load-bearing. An independent pass
found **12 of 13 mutations survived**. Every miss was shape or direction, not assertion
content:

| Axis | What was missing |
|---|---|
| Shape | Every fixture single-page, so first-page-only was indistinguishable from correct flattening |
| Reachability | The fixture built `Link` headers by **format string**, so the guard's whole input class was unreachable — deleting the guard left 125/0 green |
| Direction | Every masking assertion was secret-REMOVAL; none was signal-RETENTION, so an over-aggressive scrubber was invisible |

> N mutations of one shape is one mutation. Audit a battery's **axes**, not its count.

### 5. Assert-X and document-X collide

Two guard suites exited **0 with every assertion removed** (the only gate was `FAIL > 0`).
Four guard probes were satisfied by the comments describing them — including
`has_teardown_always`, where replacing the real `docker logout` with
`: # was: docker logout …` left the suite 52/52 while a push-authenticated docker session
survived to end-of-job.

This repo had **already fixed exactly this** for a sibling probe in the same file
(`comments_on_7339`, whose comment records that the bare-substring form "passed 52/52") and
had not swept the two siblings beside it.

## Session Errors

- **Session-start `cleanup-merged` timed out** (exit 143, 120s) — Recovery: proceeded; it had already cleaned one worktree. **Prevention:** none needed; the skill says skip silently on first error.
- **`gh pr diff 6937` failed with `unexpected EOF`** — Recovery: re-derived the changed paths from local git objects via the merge commit. **Prevention:** for any `gh` call whose answer exists locally, prefer the local object store; a network flake must never read as "no data".
- **6 of 10 review agents stalled on a 600s watchdog** — Recovery: RESUMED (not respawned) in batches of 3 with backoff; resumed agents retained partial findings, and the single most important finding (the doppler injection) came from a resumed agent mid-thread. **Prevention:** spawn large panels report-only and in batches; a dead agent is resumable and a fresh spawn loses its transcript.
- **`agent-native-reviewer` never resumed — shipped at 9/10 coverage** — Recovery: stated the gap explicitly rather than reporting full coverage. **Prevention:** name missing agents in the summary and the trailer; the agents that die are not the ones you needed least.
- **Worktree reaped mid-session (1st time), lease EXPIRED** — the lease was acquired at session start with `SOLEUR_EXPECTED_DURATION_MIN=240`, and this session ran well past four hours. Recovery: commit objects survive unreferenced, so `git branch <name> <sha>` pins them before gc. **Prevention:** a long review-and-fix pass outlives the default lease; re-acquire on a long session rather than assuming the initial grant covers it.
- **Worktree reaped again (2nd time), NO lease at all** — the recovery worktree was created with a raw `git worktree add` because `worktree-manager.sh create` uses `git worktree add -b` and cannot adopt an EXISTING branch, which is exactly the recovery case. Raw `add` acquires no lease, so any sibling's `cleanup-merged` could reap it. Recovery: same object-pinning, then re-push. **Prevention:** see Route-to-Definition — after any manual `git worktree add`, call `acquire_lease` explicitly.
- **`git config --worktree core.bare false` failed** (`extensions.worktreeConfig` disabled) — Recovery: verified work-tree ops worked anyway. **Prevention:** verify the capability, do not assume the extension is on.
- **Captured `head`'s exit code as `status_rc=$?`** — Recovery: re-ran with output redirected and rc captured directly. **Prevention:** never read `$?` after a pipeline unless you mean the last stage.
- **First mutation battery ran against a RED control** — copying a `BASH_SOURCE`-rooted guard suite out of the repo broke its `REPO_ROOT` derivation. **Prevention:** a red baseline voids every row; build the sandbox with `git archive` at the same relative depth and require a GREEN control before reading any mutation result.
- **New suite failed 10/15 on first run** — `json.dumps`' default `": "` separators build an envelope no production emission produces, so the anchor correctly refused it. **Prevention:** derive fixture SHAPE from the production artifact; a fixture that fails its own anchor is testing itself.
- **The deadline test's key assertion was vacuous twice** — at `DEADLINE_S=1` the trip fired before any manifest was fetched, so "the marker carries what it measured" passed on an empty marker. **Prevention:** when an arm asserts "X survived", confirm X existed before the trip; order the fixture so a SUCCESSFUL operation precedes the failing one.
- **Missing per-app `bun install`** — `apps/web-platform` died at 138ms with `vitest: not found`. **Prevention:** replicate BOTH halves of `install_deps` (root and the `apps/*/` loop) when standing a worktree up by hand.
- **An `until` waiter exited on its own timeout reporting exit 0** and was briefly read as completion. **Prevention:** wait on the PID (`until ! kill -0 <pid>`), not on a log pattern that may never appear.
- **A comment edit left a dangling sentence fragment** in the workflow YAML. **Prevention:** re-read the block after any multi-line comment rewrite.
- **Reported "the state defect does not reproduce" while under-evidenced** — the conclusion was right, but the mechanism only surfaced later from main's own addendum (it DID reproduce until 2026-08-06, cleared by a targeted apply). **Prevention:** when a defect "does not reproduce", look for what CHANGED, not just for the current reading.
- **`rm -rf` blocked by the guardrail** (correctly) — Recovery: used `mktemp -d`. **Prevention:** none; the guard did its job.
- **PR closed and branch deleted twice mid-session** by the operator's account — Recovery: pinned objects locally, stopped, and asked rather than reopening a third time. **Prevention:** when an outward-facing action is undone by another actor, stop and ask; do not drive a restore loop.

## Key Insight

Every one of the five blockers is the same shape: **a check that certified something other
than the property it named.** A guard satisfied by its own comment, a counter that never
counted, a probe keyed on the wrong fact, a fixture that could not express the input class,
a credential measurement that asked the wrong question.

And each was invisible to the strongest signal available — a green suite, a green CI, and
the author's own mutation battery — because all three measure the checks, and the checks were
what was wrong.

The generalisable move: for every check, name the mutation that satisfies it while violating
the property. If you cannot name one, you have not tested the check.
