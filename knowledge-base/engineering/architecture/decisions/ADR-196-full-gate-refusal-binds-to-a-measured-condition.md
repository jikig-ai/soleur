# ADR-196: A full-gate refusal binds to a condition the runner MEASURES, not one an agent DECLARES

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

**6. The two GIT-HOOK invocations carry the hatch; the skill-prescribed gate runs deliberately do
not.** `lefthook.yml`'s `bun-test` pre-commit hook and `plugins/soleur/scripts/grok-pre-push-gate.sh`
both invoke the full gate deliberately and both set `SOLEUR_ALLOW_FULL_GATE=1`, because a refusal
there blocks committing or pushing outright and leaves the operator no action but to re-run the same
command with the hatch. The pipeline's own gate runs are the opposite case and are left unhatched on
purpose: `work` Phase 2's three `TEST_GROUP=` shard commands and `ship` Phase 4's `TEST_GROUP=all`
run carry no hatch, and each of those two skill documents already tells its reader what `rc=4` means
at that call site and what to do about it. There a refusal is both correct and actionable — wait for
the sibling, or re-run with the hatch having decided the second battery is worth its cost.
"Sanctioned" is therefore not the discriminator; *"is a refusal actionable at this call site?"* is.

**7. A measured count must be measured by THIS process.** `tc_preamble` exports
`TC_SIBLING_RUN_COUNT`, so a nested `test-all.sh` inherits it — including one whose own
`tc_preamble` was neutered by a test sandbox and therefore measured nothing at all. A policy
reading the bare count cannot distinguish *"I measured 4 siblings"* from *"an ancestor measured 4
and told me"*, which is the DECLARED antecedent this ADR exists to move away from, re-entering
through an environment variable rather than a prompt. `tc_preamble` therefore stamps
`TC_SIBLING_RUN_COUNT_PID` with its own `$$` and does **not** export it; the refusal requires that
stamp to equal the current process. An inherited count carries no stamp and cannot refuse, while a
nested runner that performs its own measurement sets its own stamp and refuses correctly.

This was not hypothetical and it is not detectable in CI. Two suites drive `test-all.sh` as their
SUT and neuter `tc_preamble` in their sandboxes; both were refused on their parent's measurement
whenever any sibling worktree happened to be running a battery. Single-variable A/B with the
sandbox procfs pinned, on suites this branch does not touch — measured against the tree **BEFORE
the provenance stamp landed**, which is the only tree on which the right-hand column reproduces:

| suite | own measurement | `TC_SIBLING_RUN_COUNT=4` inherited (pre-stamp) |
|---|---|---|
| `scripts/test-all-killed-classification.test.sh` | 77 passed, 0 failed | 40 passed, 37 failed |
| `scripts/test-all-infra-coverage-notice.test.sh` | 118 passed, 0 failed | 38 passed, 81 failed |

Re-deriving the right-hand column at HEAD returns the LEFT-hand one: `TC_SIBLING_RUN_COUNT=4` alone
now yields 77 passed, 0 failed, because the stamp is precisely what makes an inherited count inert.
That is the fix working, not the table being wrong — but a reader who re-runs the command without
this note concludes the numbers were fabricated, so the tense is load-bearing.

CI runs with no siblings, so the count is `0` there and the inherited-count path is unreachable —
the required `test` context stays green either way. The failure is visible only under the
parallel-worktree workflow, which is also the only condition under which the refusal does anything
at all. A guard whose failure mode is invisible to the gate that would catch it needs its
regression pinned deliberately: `plugins/soleur/test/fanout-suite-scope.test.sh` builds a sandbox
with `scripts/lib/test-contention.sh` withheld — which is exactly how `test-all.sh` reaches its
no-op `tc_preamble` stub in the wild — and asserts an inherited count does not refuse.

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

**Eleven mechanisms for SETTING the variable were enumerated and all blocked.** The full M1–M11
enumeration, with the measurement behind each verdict, is in the implementation plan under
*"Mechanism enumeration for #7553"*
([2026-08-19-fix-vacuity-floor-and-subagent-gate-plan.md](../../../project/plans/2026-08-19-fix-vacuity-floor-and-subagent-gate-plan.md)).
Abridged to eight below: `.claude/settings.local.json` and the `PreToolUse(Bash)` `updatedInput`
variant fold into their neighbours, and `PostToolUse` on `Task` — parent-side, and fired after the
subagent has already finished — is blocked by ordering and is omitted here. `.claude/settings.json`
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
- **Decision 7's predicate is fixtured in BOTH directions, which it was not at first.** The
  inherited-count arm leaves `TC_SIBLING_RUN_COUNT_PID` UNSET, so it is satisfied by every
  predicate that is false-on-unset: measured, replacing `== "$$"` with
  `-n "${TC_SIBLING_RUN_COUNT_PID:-}"` left the suite at 36 passed, 0 failed, and no fixture
  anywhere SET the variable. That degrades the decision from *"I measured this"* to *"someone
  measured this"* — the DECLARED antecedent this ADR removes, re-entering through the very guard
  meant to close it. A second arm now drives a stamp that is SET but names a foreign pid, and it
  must run against the no-library sandbox: with a live `tc_preamble` both variables are
  overwritten by a real measurement before the refusal is reached, so a full-sandbox arm passes
  under the mutation and proves nothing.
- **`export -n` on the stamp is unfalsifiable through any exit code** and is asserted at the
  environment level instead. `$$` differs in a forked child whether or not the variable is
  exported, so the rc arms stay green with the line deleted AND with an explicit `export` added.
  The suite therefore sources the real library in a child, runs `tc_preamble`, and counts the
  name in the child's `env`: 0 today, 1 with `export -n` removed.
- **The ordering constraint in Decision #4 is asserted structurally, on source order** — not by
  grepping a refused run's output for a lock line. That was the first form and it was vacuous:
  `build_sandbox` neuters `tc_acquire`, so no lock line can ever appear in any arm's output.
  Measured **pre-fix, when the suite held 24 assertions**: relocating the refusal past
  `tc_acquire` left it at 24 passed, 0 failed. The suite now holds 36, so re-running that
  mutation today reds — the figure dates the observation, it is not the current total. A guard
  that cannot be driven red was not shipped in the PR that exists to remove them.
- **Where the refusal actually fires.** The two git-hook invokers carry the hatch, so neither
  exercises it. Everything else does. `work` Phase 2's three shard commands and `ship` Phase 4's
  `TEST_GROUP=all` run are prescribed **unhatched** by their own skill documents, so under the
  parallel-worktree workflow this repo documents, the refusal fires on the pipeline's own gates
  routinely — not only on a developer or agent starting an *ad hoc* battery. `package.json`'s
  `"test": "bash scripts/test-all.sh"` is a third unhatched invoker in the same class, so
  `npm test` is refused under a sibling too. What makes all three acceptable rather than defects
  is that a refusal is actionable at each of those call sites, and the two skill documents state
  what `rc=4` means at theirs (see Decision 6). An earlier draft of this ADR asserted the
  opposite — *"not the gates"* — and was refuted by reading the two skill files it was
  describing.
- **A residual gap, stated plainly.** The refusal cannot fire at all where
  `scripts/lib/test-contention.sh` is absent: `test-all.sh` installs no-op `tc_preamble`/`tc_acquire`
  stubs in that case, so no count is ever measured and no stamp is ever set. That is the same class
  as Decision 7 one level up — an antecedent that silently never holds — and it is the exact
  condition `fanout-suite-scope.test.sh`'s sandbox reproduces deliberately. It is accepted rather
  than closed: a tree missing that library is a broken checkout, and failing OPEN is the right
  behaviour for a policy whose only effect is to decline work.
- **The non-concurrent case is not covered.** A lone spawned agent running the full battery with no
  sibling present is not refused. That was the original issue's framing, and it now has only the
  prose instruction. Whether it is worth further mechanism is deferred; note that ADR-133's lock
  plus this refusal already remove the *measurable* harm (timing corruption and timeout-induced
  false REDs), leaving wasted wall-clock.
- **Four skill documents were corrected, at five sites** (`review`, `work` ×2, `ship`, `one-shot`) and
  `fanout-suite-scope.test.sh` now asserts what its grep can actually establish, plus a regression
  guard against the falsehood returning.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Set `SOLEUR_SUBAGENT=1` on the agent-spawn path (the issue's stated fix) | Measured impossible: eleven mechanisms, all blocked. No repo-controlled spawn path exists. |
| Read a harness-injected identity (`CLAUDE_CODE_CHILD_SESSION`) | Measured available, rejected: refuses every spawned agent's pre-commit, and its fail-open mode is structurally untestable from CI. See above. |
| Correct the false skill sentences and change nothing else | Leaves #7553 closing on prose alone, with its actual protection deferred indefinitely. The operator chose against this on 2026-08-19. |
| Replace the refusal entirely with `flock` mutual exclusion | ADR-133's lock already exists and already serialises. A lock lets the run *start* and then queue; the issue's intent is that it never start. The two are complementary, and both now apply. |
| Scope the refusal to full-gate (`TEST_GROUP=all`) invocations only, so a shard is never refused | Raised in the plan's risk table as mitigation (b) for the pre-commit blast radius, to be decided in Phase 3e. **Declined 2026-08-19.** Mitigation (a) — the `lefthook.yml` hatch — removed the motivating harm, and `TEST_GROUP` is not a proxy for cost: a shard contends for the same machine-global `/tmp` tmpfs and CPU as a full battery, which is the contention the refusal exists to prevent. Scoping would also have made the refusal unreachable from `work` Phase 2, which since ADR-183 is where most local runs happen. The consequence is accepted deliberately — a ~90 s shard IS refused while a sibling battery is in flight — and `work`'s own Phase 2 text documents `rc=4` at that call site. |
| Put the refusal inside `tc_preamble` | It is a reporter whose banners are documented as advisory. Policy buried in a measurement function is how a stale comment becomes load-bearing. |
