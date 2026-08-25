# Decision Challenges — feat-one-shot-7580-7553-vacuity-floor-subagent-gate

Surfaced during planning on a headless pipeline run, so recorded here rather than asked. `ship`
Phase 6 renders this into the PR body and files it as an `action-required` issue.

---

## UC-1 — Should #7553's fix be an identity check at all, or a concurrency lock?

**Class:** User-Challenge (ADR-084) — it proposes dropping the direction the operator stated.
**Raised by:** the Step 4.5 scoped strong-model consult, independently of the plan author.
**Status:** **RESOLVED 2026-08-19 by the operator** — option 2 ("add the lock as well"), in its
narrowed form: correct the false claims *and* make the sibling detection refuse rather than queue.
The identity mechanism (M12) is NOT built in this PR and moves to a follow-up. See plan Phase 3e.

Recorded here rather than deleted: the reasoning below is what the decision was made against, and
`ship` Phase 6 renders it into the PR body so a reviewer sees the fork that was taken and why.

### The operator's stated direction (the default)

Issue #7553 and the pipeline brief both frame the work as: *nothing sets `SOLEUR_SUBAGENT=1`, so
arm the guard on the agent-spawn path so the existing refusal can fire.* The plan follows this,
selecting Mechanism 12 — read `CLAUDE_CODE_CHILD_SESSION`, which the harness already injects into
every spawned agent's Bash environment — because all eleven ways of *setting* a variable on the
spawn path were measured blocked.

### The challenge

Replace identity detection with `flock` mutual exclusion in `scripts/test-all.sh`. The stated harm
is *concurrent* full-gate runs corrupting each other's timings; that is a mutual-exclusion problem,
and a lock addresses it directly.

**Arguments for the challenge:**

- It deletes the plan's riskiest phase outright. Phase 0.1's three-way branch exists only because
  Mechanism 12 rests on one unmeasured bit (is the discriminator also set in the lead session?).
  With a lock there is nothing to measure and no way to brick `lefthook` pre-commit or the Grok
  pre-push gate by widening a condition against an untested assumption.
- It is testable in CI. Spawn two processes, assert the second is refused. The identity binding is
  *structurally* untestable — CI never runs inside a spawned agent, so no automated route can ever
  confirm the harness still sets the variable.
- It does not depend on undocumented harness-internal state. The plan itself already names the
  fail-open mode: if a Claude Code upgrade stops setting `CLAUDE_CODE_CHILD_SESSION`, the refusal
  silently reverts to today's unreachable state with no alarm.
- The repo already has lock/lease primitives (`session-state.sh` `with_lock`), so this is not a new
  dependency.

**Arguments against (why the plan did not take it unilaterally):**

- It solves a *different* problem than the one the issue states. The refusal's own message says
  *"Spawned agents run only the suites targeting the files they were given."* The intent is that a
  subagent never starts the battery; a lock lets it start and then queue. N-1 subagents pay the
  wait, and the one that wins the lock still burns a full battery it should not have run.
- Dropping operator-requested scope is one of ADR-084's four never-Mechanical classes.
- **The two are not mutually exclusive.** A lock is a sound belt-and-braces addition alongside the
  identity check under either Phase 0.1 branch, and is the natural terminus if branch (c) fires
  (neither variable discriminates).

### What is needed from the operator

One of (**answered: option 2, narrowed — see Status above**):

1. **Keep the plan as written** — identity check, with the Phase 0.1 probe as the gate. (Default.)
2. **Add the lock as well** — identity check refuses early, lock catches whatever slips through.
   Costs one extra phase; removes the fail-open residual risk.
3. **Replace with the lock only** — drops the identity check and #7553's stated framing. The two
   false skill sentences still get corrected (that is unconditional under every branch).

Note that option 3 is also where Phase 0.1 branch (c) lands on its own if the measurement shows no
usable discriminator — so choosing it up-front mainly saves the probe, not the work.
