# ADR-194: A full-gate refusal binds to a condition the runner MEASURES, not one an agent DECLARES

- **Status:** Accepted. True the moment the code merges — no soak window, no time-gated criterion.
- **Date:** 2026-08-19
- **Supersedes in practice:** the `SOLEUR_SUBAGENT=1` refusal's *reachability* claim, not the
  refusal itself. That code path is retained byte-identical; what changes is that the runner no
  longer depends on it being armed by something outside the repository.
- **Relationship to ADR-133:** **complementary.** ADR-133 gave `test-all.sh` an `flock` advisory
  lock so concurrent full-gate runs serialise. This ADR is about the runs that should never have
  *started* — a lock queues them, it does not refuse them.
- **Relationship to ADR-181/ADR-177:** both describe `rc=4` as the REFUSED class. That taxonomy is
  unchanged; this ADR adds a second producer of it.

## Context

`scripts/test-all.sh` has refused a full-gate run when `SOLEUR_SUBAGENT=1` is set without
`SOLEUR_ALLOW_FULL_GATE=1` since #7441. The guard is correct and covered by tests.

**Nothing sets `SOLEUR_SUBAGENT=1`.** Measured 2026-08-19 across every occurrence in the
repository: ADR prose, learnings, archived plans, five skill sentences, and tests that export it
for their own arm. There is no setter on any spawn path, so the antecedent has never held in normal
operation and the refusal has never fired for the case it was written for.

Two skill documents asserted the mechanism as a fact about the harness — *"spawned agents … are
spawned with `SOLEUR_SUBAGENT=1` in their environment"* — and a third said `test-all.sh`
*"enforces this mechanically … because a paragraph in a prompt is agent discretion and this is
not."* In practice it **was** agent discretion, because the mechanical half was unreachable. An
unenforceable claim presented as mechanical enforcement is worse than an honest convention: it
stops the next reader from checking.

Worse, `plugins/soleur/test/fanout-suite-scope.test.sh` asserted `"$rel tells the lead to export
SOLEUR_SUBAGENT=1"` while matching prose that said the harness set it. A test stood behind the
claim without testing it.

## Decision

**1. A refusal antecedent must be a condition the runner can OBSERVE from inside its own process,
not one a caller must volunteer.** An antecedent only an agent can set is agent discretion wearing
a guard's clothes, and its failure mode is silent: the guard reports nothing, because it never runs.

**2. The full-gate refusal therefore binds to `tc_preamble`'s measured sibling count.**
`tc_preamble` already resolves how many *other* worktrees are running `test-all.sh`, by walking
`/proc` and excluding this run's own ancestors and process group. It already banners
`SIBLING_RUN_DETECTED`. It now exports that count as `TC_SIBLING_RUN_COUNT`, and `test-all.sh`
refuses on it.

**3. The refusal lives at the call site, not in the reporter.** `tc_preamble` remains a measurement
function that always returns 0. Burying policy inside it is how the next reader ends up trusting a
comment that is no longer true — its banner block was explicitly documented as *"All are advisory:
nothing here changes the run's outcome"*, and that comment was rewritten in the same commit.

**4. Ordering is part of the decision, not an implementation detail.** The refusal fires AFTER
`tc_preamble` (which computes the count) and BEFORE `tc_acquire`. Refusing after `tc_acquire` would
make a run that should never have started wait up to `TC_LOCK_TIMEOUT` (900 s) to be told so, and
take the advisory lock a legitimate sibling is queued on. A refused run must cost nothing.

**5. The change is ADDITIVE.** `SOLEUR_SUBAGENT`'s refusal is retained byte-identical as the
portable, manual, and Grok-path override. `rc=4` now has two producers; the message names which
tripped.

**6. A sanctioned invocation carries the hatch.** `lefthook.yml`'s `bun-test` pre-commit hook and
`plugins/soleur/scripts/grok-pre-push-gate.sh` both invoke the full gate deliberately, and both set
`SOLEUR_ALLOW_FULL_GATE=1`. The refusal targets an *opportunistic* second battery, never the gate a
commit or push is required to pass.

## Why the harness-identity design was rejected

The obvious repair — since no variable can be *set* on the spawn path, *read* one the harness
already sets — was measured **available** and rejected on two independent grounds. It is recorded
here rather than in a rejected-alternatives table because the measurement is the load-bearing part
and a future reader will otherwise re-derive it.

`CLAUDE_CODE_CHILD_SESSION=1` and `AI_AGENT=claude-code_2-1-228_agent` were observed in the Bash
environment of two independent spawned agents and are absent from the `claude` process's own
environ, so they are per-call harness injections. Both would work.

- **Blast radius.** `lefthook.yml` registers a `bun-test` pre-commit hook with
  `glob: "*.{ts,tsx,js,jsx}"` running `bash scripts/test-all.sh`. A spawned agent committing a
  `.ts` file is the ordinary shape of work and review fan-outs. Under a widened antecedent every
  one of those commits exits 4. The right question is not *"is this invoker a spawn path?"* but
  *"is this invoker reachable from inside a spawned agent?"* — and for both git hooks the answer is
  yes and routine.
- **Structurally untestable fail-open.** CI never runs inside a spawned agent, so no automated
  route can confirm the harness still sets the variable. A Claude Code upgrade that stops setting
  it reverts the refusal to today's unreachable state, silently, with no alarm.

The measured condition has neither property: it needs no spawn-path cooperation, and CI can
exercise it by starting a real sibling.

**Eleven mechanisms for SETTING the variable were enumerated and all blocked** — `.claude/settings.json`
`env` (works, but session-global, so it would refuse the lead's own sanctioned run), agent-file
frontmatter (no such key), the `Task` tool input schema (no env field), a `PreToolUse` rewriter
(ADR-162 permits exactly one `updatedInput` emitter and `grep-rewrite.sh` holds the slot), a
`SubagentStart` event (does not exist), `SessionStart` (emits prose, not env; its exports die with
the hook process), a wrapper around `harness.ts` (a pure string formatter — no process exists
between the model and `Task`), and prompt prose (which is the agent discretion the issue names).

## Consequences

- The refusal is reachable for the first time. Its antecedent is established by the runner itself
  on every invocation.
- **It is testable in CI**, which the identity design could never be:
  `plugins/soleur/test/fanout-suite-scope.test.sh` synthesizes a procfs containing a sibling and
  asserts `rc=4`, plus a hatch arm, a solo negative control, and an additivity arm proving the
  `SOLEUR_SUBAGENT` path still refuses independently.
- **The ordering constraint in Decision #4 is asserted structurally, on source order** — not by
  grepping a refused run's output for a lock line. That was the first form and it was vacuous:
  `build_sandbox` neuters `tc_acquire`, so no lock line can ever appear in any arm's output.
  Measured: relocating the refusal past `tc_acquire` left the suite at 24 passed, 0 failed. A guard
  that cannot be driven red was not shipped in the PR that exists to remove them.
- **A residual gap, stated plainly.** The two git-hook invokers carry the hatch, so neither
  exercises the refusal. That is intended — they are sanctioned runs — but it means the refusal's
  real-world firing surface is a developer or agent starting an *ad hoc* battery, not the gates.
- **The non-concurrent case is not covered.** A lone spawned agent running the full battery with no
  sibling present is not refused. That was the original issue's framing, and it now has only the
  prose instruction. Whether it is worth further mechanism is deferred; note that ADR-133's lock
  plus this refusal already remove the *measurable* harm (timing corruption and timeout-induced
  false REDs), leaving wasted wall-clock.
- **Five skill documents were corrected** (`review`, `work` ×2, `ship`, `one-shot`) and
  `fanout-suite-scope.test.sh` now asserts what its grep can actually establish, plus a regression
  guard against the falsehood returning.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Set `SOLEUR_SUBAGENT=1` on the agent-spawn path (the issue's stated fix) | Measured impossible: eleven mechanisms, all blocked. No repo-controlled spawn path exists. |
| Read a harness-injected identity (`CLAUDE_CODE_CHILD_SESSION`) | Measured available, rejected: refuses every spawned agent's pre-commit, and its fail-open mode is structurally untestable from CI. See above. |
| Correct the false skill sentences and change nothing else | Leaves #7553 closing on prose alone, with its actual protection deferred indefinitely. The operator chose against this on 2026-08-19. |
| Replace the refusal entirely with `flock` mutual exclusion | ADR-133's lock already exists and already serialises. A lock lets the run *start* and then queue; the issue's intent is that it never start. The two are complementary, and both now apply. |
| Put the refusal inside `tc_preamble` | It is a reporter whose banners are documented as advisory. Policy buried in a measurement function is how a stale comment becomes load-bearing. |
