---
date: 2026-07-03
category: best-practices
module: apps/web-platform/infra, plugins/soleur/skills/git-worktree, scripts/followthroughs
tags: [vacuous-test, verification, observability, soak, bash, infra, shellcheck, review]
pr: 5935
issue: 5934
---

# Learning: "PASS is not proof" — three vacuous-green traps in infra verification

## Problem

Building the durable char-device `.git/config.lock` substrate fix (#5934), three
independent gates reported GREEN/PASS while **not actually exercising the thing they
claimed to verify**. Each would have shipped a false signal; each was caught by a
*different* mechanism (shellcheck, an observability review agent, an architecture
review agent) — none by the passing test/gate itself.

### Trap 1 — Source-time config freeze makes per-case test overrides vacuous
`git-lock-chardevice-sweep.sh` resolved `ROOT="${GIT_LOCK_SWEEP_ROOT:-/mnt/data/workspaces}"`
at **module (source) time**. The test sources the script, then sets
`GIT_LOCK_SWEEP_ROOT="$per_case_dir"` per case — but `ROOT` was already frozen, so every
override was a silent no-op. The discover/idempotent/absent cases passed **because the
frozen default `/mnt/data/workspaces` does not exist on the test host** (`[[ -d ]]` → no-op),
NOT because the `-type c` scope filter worked. The tell: shellcheck **SC2034**
("GIT_LOCK_SWEEP_ROOT appears unused") on the *test* — the override was assigned but never
read, because the read happened at source time before the assignment.

### Trap 2 — A soak that queries a sink the signal is never written to PASSes vacuously
The AC10 non-recurrence soak queried **Sentry** for the in-sandbox
`SOLEUR_GIT_LOCK_UNREMOVABLE type=chardevice` line. But that line is emitted only to blind
agent-sandbox stdout and is **not mirrored to any queryable sink** (this host's `vector.toml`
has no Sentry sink at all — only Better Stack). The Sentry query could therefore *never*
return >0 → the soak exited 0 (PASS) unconditionally → the follow-through sweeper would
**auto-close #5934 while completely blind to a recurrence**. Caught by
`observability-coverage-reviewer`, not by the soak (which even self-disclosed the risk in a
comment — disclosure is not soundness).

### Trap 3 — A documented "quiescent window" safety invariant that is factually false
The sweep's comment + ADR-081 + plan all claimed it runs in a "quiescent window — old
container stopped, canary not yet running", with "ordering is the concurrency-safety
mechanism." Tracing `ci-deploy.sh` showed the **old production container is still live** at
sweep time (it is not stopped until the blue-green cutover ~250 lines later). The sweep is
safe anyway — but for a *different* reason: the `-type c` filter (a live git writer's lock is
always a REGULAR file, never a char device). A future maintainer re-validating the ADR-068
shared-git-data assumption would have reasoned from the false invariant. Caught by
`architecture-strategist` + `security-sentinel` (converged).

## Solution

- **Trap 1:** resolve config at **call time** via getters (`sweep_root()`/`sweep_state()`/
  `sweep_maxdepth()` reading `${GIT_LOCK_SWEEP_*:-default}` inside the functions), mirroring
  `agent-runner-sandbox-config.ts`'s `WORKSPACES_ROOT` resolver. The test's per-case overrides
  now take effect and the cases exercise real fixtures.
- **Trap 2:** repoint the soak to the signal that **is** wired — the host-side
  `SOLEUR_CHARDEV_SWEEP_{DONE,FAILED}` markers via Better Stack (`scripts/betterstack-query.sh`).
  PASS only when the sweep ran ≥1× (DONE) AND zero FAILED; **fail-safe TRANSIENT** (never a
  false close) on any query/auth failure or zero-DONE.
- **Trap 3:** re-ground the safety claim in the actual invariant (the `-type c` filter) across
  the code comment, ADR, and plan; add a runtime TOCTOU re-assert (`-c` + resolved-path-under-root)
  since the volume is genuinely live.

## Key Insight

**A GREEN test / PASS gate / "safe" comment is a hypothesis about the mechanism, not proof it
fired.** For any verification artifact, ask "what would make this pass WITHOUT the thing under
test being true?" — and eliminate that path:
- **Vacuous test:** does the fixture actually reach the code under test, or does a default /
  guard / frozen binding short-circuit it? (shellcheck SC2034 on a test's env-stub is a free
  tell that the stub is never read.)
- **Vacuous gate:** does the signal the gate queries actually get **written to the sink the
  gate reads**? A post-deploy soak that greps a sink the signal never reaches always PASSes.
  Make such gates **fail-safe** (TRANSIENT/inconclusive, never PASS) when the signal path is
  unproven, so they can never false-close a tracker.
- **False invariant:** does the documented safety mechanism (ordering / quiescence / "stopped
  container") match the actual execution sequence? Trace it; the real load-bearing invariant is
  often a content/type filter, not the timing the comment claims.

## Session Errors

1. **Planning subagent: IaC-routing hook blocked the plan Write twice** (forwarded from
   session-state.md) on negative-sense trigger substrings. — Recovery: neutralized phrasing +
   sanctioned ack marker. — Prevention: owned by the IaC-routing gate's negative-sense handling;
   out of scope here.
2. **Deepen-plan network-outage gate false-positived on "unreachable"** (forwarded). — Recovery:
   reworded. — Prevention: gate-owned.
3. **TaskCreate called with a `tasks` array** — the tool takes single `subject`/`description`. —
   Recovery: adapted to plan-file checkboxes for progress tracking. — Prevention: one-off; the
   error message is self-correcting.
4. **shellcheck SC2034 surfaced a vacuous test (source-time config freeze).** — Recovery:
   call-time resolvers. — Prevention: Trap 1 above; treat SC2034 on a test's env-stub as a
   vacuous-fixture signal, not noise.
5. **AC10 soak was vacuous (unwired Sentry sink).** — Recovery: repoint to wired Better Stack
   markers + fail-safe TRANSIENT. — Prevention: Trap 2 above; already caught by
   `observability-coverage-reviewer` (verify signal reaches the queried sink).
6. **Documented "quiescent window" safety invariant was false.** — Recovery: re-ground in the
   `-type c` filter across code/ADR/plan + TOCTOU re-assert. — Prevention: Trap 3 above.
7. **Premature `rm -rf` of a temp dir while a background pristine-test still ran there** —
   corrupted that run's CWD (`getcwd` errors). — Recovery: the clean signal (doppler failure
   reproduced on pristine) was already captured before deletion. — Prevention: covered by the
   existing "verify a background process has exited before touching its working dir" learning.
8. **shellcheck lint** (SC2209 `branch=rm`, SC2178 `forced` name-collision, SC2034 sourced-var
   false-positives). — Recovery: quote/rename/disable-with-rationale. — Prevention: run
   shellcheck on new bash before committing (already the deterministic gate for bash PRs).
