---
date: 2026-09-03
category: workflow-patterns
module: model-launch-review, byok-cap-enforcement
issues: [7774, 6942, 6934, 7773]
tags: [guards, mutation-testing, model-launch, cost-caps, review]
---

# Every check I shipped was narrower than the name it carried

## Problem

Anthropic released Claude Fable 5.1. The model-launch sweep looked like a one-line change:
add `claude-fable-5=claude-fable-5-1` to `AUTOFIX_PAIRS` and re-run the auditor.

Soleur has **no `claude-fable-5` literal in runtime config** — Fable reaches the codebase only
as the harness `model: fable` alias (ADR-083's advisor consult), which carries no version and
follows to 5.1 on its own. So there was nothing to swap, and that was the trap: the work was
entirely in the auditor, and adding the obvious pair is what breaks it.

Ten review agents plus the deterministic lints found eight defects. **Six were in code this PR
added**, including a guard written an hour earlier that could not fire.

## The unifying shape

Every defect reduced to one sentence: **a check that certifies something narrower than its
name.** Not one of them was visible by reading, and every one was green.

| Check | Name claims | Actually certified |
|---|---|---|
| `collect_config_hits` selection | "this file carries a stale id" | "this file contains the id as a substring" |
| `[2b]` presence probe | "the id is in the pinned CLI bundle" | "some longer string containing it is somewhere in the npm scope" |
| `[2b]` version line | "measuring the installed tree" | "a pin string was parseable" (fired with no install at all) |
| exit-70 divergence guard | "selection and display agree" | "the pipeline exited zero" |
| Layer-2 cost ceiling | "per-spawn spend" | "lifetime spend for this action class" |
| `PER_SPAWN_COST_CEILING_CENTS` | "$2.60 per click" | ~$1.73, while showing the founder $2.60 |

## Key insights

### 1. The boundary asymmetry was already live — the new pair only made it unavoidable

The `--fix` sed has been boundary-anchored since the script was created; **selection was a bare
alternation**. I wrote in the code comment and the commit message that `claude-fable-5` being a
strict prefix of `claude-fable-5-1` was the *cause*. It was not. Measured on `origin/main`,
with no fable involved:

```
# a config file carrying claude-opus-4-7-20260101
detect -> rc=10  |  --fix prints "fixed" (file unchanged)  |  detect -> rc=10   (forever)
```

Any **dated** variant already produced the permanently-red drift cron. The general invariant is
"selection and rewriting must share one boundary"; dated ids were its standing violation. Fable
is the first pair whose stale id is a strict PREFIX of its target, so the mismatch fires on the
id that is **current** rather than only on a longer variant nobody had written yet.

The correction makes the fix broader than I claimed — and a reader who internalised my original
sentence would watch for prefix-shadowed pairs and miss the general case.

### 2. `assert_single_hop` passes on the shape it looks like it should catch

The table already had a fail-fast invariant against chaining (`4-7=4-8` alongside `4-8=5`). It
compares each RHS against every LHS. `claude-fable-5-1` is not a source id, so the guard passes
while the defect it exists to prevent — a permanently-red cron auto-filing issues it cannot fix
— reappears via prefix-shadowing instead of chaining.

**Litmus:** an invariant is a claim about a *set*. Ask which members of the set it quantifies
over, not whether it fires on the example you have.

### 3. A probe scoped to a namespace is not a probe of the package

`[2b]` grepped `node_modules/@anthropic-ai/` and reported "present in the pinned CLI bundle".
Measured in this repo: `claude-agent-sdk` and `claude-agent-sdk-linux-x64` **both** contain
`claude-sonnet-5`. So the answer was satisfiable by the agent SDK while `claude-code` lacked the
id entirely — a false PASS on the exact #6934 silent-`max_tokens`-halving it exists to catch.

The version label made it worse: it printed the *stub's* version over a measurement spanning
five independently-versioned packages.

### 4. A guard that tests the exit code tests the wrong thing when the tool exits 0 to be unhelpful

I added an exit-70 guard so a selection/display divergence would be named rather than dying
silently under `pipefail`. It tested the pipeline's status. But `grep -o` on a file it considers
binary prints `binary file matches` to **stderr**, yields no stdout, and exits **0** — so on the
one realistic divergence the guard stayed silent, the report printed a bare `[]`, and the audit
exited 0.

The root cause was upstream: selection had no `-I`, so binaries were selectable at all, and
`--fix` would then `sed -i` one. That path is reachable by following this skill's *own* SKILL.md,
which tells the operator to unpack `claude-code-linux-x64` and grep it.

Fixing selection (`grep -I`) closed selection, display and rewrite in one place; the guard now
triggers on emptiness as well as rc.

### 5. Every name around the cost ceiling claimed per-spawn scope; only the query did not

`turn-${n}-precheck-cost-ceiling` summed `audit_byok_use` on `founder_id` + `agent_role` with
**no time bound**, and `agent_role` is `agent.spawn.requested:${actionClass}` — an action
**class**, constant across every spawn a founder ever makes of it.

So Layer 2 was a lifetime per-(founder, class) accumulator. Once a founder crossed 260¢ on a
class, every later spawn of that class failed at turn 1 with `cost_ceiling_exceeded`,
**permanently** — and `audit_byok_use` is WORM (migration 037 raises P0001 on UPDATE/DELETE), so
the balance could not be trimmed.

The step name, the constant name, the failure message (`per-spawn cost ceiling reached at turn N`)
and the notification's `whichWindow: "spawn"` all already said per-spawn. A windowed sibling
existed 200 lines away in the Today cost route. Only the enforcement query disagreed.

**Anchor from the DB, never `new Date()`:** Inngest replays re-execute the function body, so a
wall-clock anchor re-derives a different window on every retry and makes the ceiling
non-deterministic. `step.run` memoizes the DB read.

### 6. A ruling is worth more than a decision when the fork is about meaning

Correcting the Sonnet rate ($3/$15 → $2/$10, after Anthropic cancelled the scheduled increase)
raised whether `PER_SPAWN_COST_CEILING_CENTS = 260` had to move with it. Two symmetric-looking
answers; the difference is what the constant *means*.

Routed to the `cto` agent rather than deciding it inside a pricing sweep. Ruling: Layer 2 is a
**real-dollar promise** — ADR-041 justifies it as a single-click guarantee, `costBreakerCopy`
renders it to the founder as "your $2.60 per-run spending limit", and Layer 3
(`LEADER_MAX_TURNS × LEADER_MAX_TOKENS`, ≈$0.33) is what bounds work. So 260 stands and the
correction makes the ceiling finally mean its label.

Scaling 260 → 173 "to preserve the work budget" would have ratified the pre-correction ~$1.73 —
a number produced by a defect, that nobody ever chose.

The ruling also found a **second false citation** nobody asked about: `constants-ssot.test.ts`
has never existed in this repo, yet the constant's docstring *and* ADR-041's sentinel table both
cite it as the drift-guard.

### 7. The CONCUR gate correctly refused my scope-out

I proposed filing the Layer-2 defect as `deferred-scope-out`, arguing the WORM ledger meant
locked-out founders needed a remediation path, which pushed it past the cost-of-filing gate.

`code-simplicity-reviewer` DISSENTed, and the argument was decisive: **windowing at
`action_sends.created_at` excludes every historical row by construction**, so a previously
locked-out founder starts their next spawn at zero. The remediation was a phantom that the
proposed fix dissolves — my justification for exceeding the gate was contained inside the fix I
was proposing. It also noted that "too semantically weighty for a model-launch PR" was
inconsistent with a PR already amending ADR-041 and rewriting the ceiling's docstring.

**Gate:** when a filing's claim to exceed the cost gate rests on work the fix itself removes,
that is not a scope-out. Ask what remains to be done *after* the proposed fix lands.

### 8. A one-axis mutation battery is one mutation

I mutated the anchoring out of `collect_config_hits`, watched the new regression test go red,
and called the test load-bearing. It was — on that axis. `test-design-reviewer` found **nine
survivors across five axes I never touched**:

- **fixture direction** — every fixture asserted must-be-clean; dropping `|$` from `ID_BOUNDARY`
  made `--detect` report `model-drift: none`, exit 0, on real drift, at 17/17 green
- **the rewriter** — three independent sed mutations each corrupted real source
  (`claude-opus-4-7-20260101` → `claude-opus-5-20260101`; an eaten closing quote), all green,
  because every fixture reaching the sed held its stale id alone and quoted
- **dispatch** — no assertion floor; a no-op `expect` Proxy passed 17/17 having asserted nothing
- **fixture cardinality** — every audit-mode fixture had exactly one in-scope file, so the
  report loop could drop all but the first
- **`[2b]`** — zero coverage; inverting its comparison prints the reassuring line silently

**Enumerate the AXES a battery edits, not the count it reports.** N mutations of one shape is
one mutation. After closing them: M1–M10 all caught, landing-asserted against a pristine copy,
green control first, on a sandbox copy.

### 9. Cheap deterministic gates and the agent panel have disjoint yield

`lint-shell-capture-exit` — a baseline-gated lint, not part of the panel — found a real defect
in code I had written an hour earlier, and it was also the cause of the `test-scripts` CI
failure. On a guard-shaped PR, run the repo's lints **after each guard-shaped commit**, before
the panel that costs orders of magnitude more.

Its fix carried its own trap: the lint accepts `x=$(cmd) || true`, but here the exit code is
load-bearing (rc 1 = no match, rc ≥ 2 = the scan failed). `|| true` would flatten rc to 0 and
re-open the #5100 scan-failed-vs-clean conflation the function exists to prevent. The correct
form is the lint's third option, `if out=$(cmd); then … else rc=$?; fi`.

### 10. The fix for a too-narrow guard was itself a too-narrow guard — caught only by review

Later the same day, PR #7785 repaired a *different* instance of this class: `.dockerignore`
prunes `test/`, Next 16 widened `next build`'s type-check set to colocated `lib/**/*.test.ts`,
and a build-INCLUDED file's import of a build-EXCLUDED module broke eight releases. The existing
containment guard stayed green because its window was narrower than its name on two axes at once
(context-root `*.config.ts` only; relative specifiers only).

I widened it. The widened version opened with:

```ts
const BUILD_INCLUDED_DIRS = ["app", "components", "hooks", "lib", "server"];
```

That is the same defect, one level up, written by the person who had just spent a day naming it.
`e2e/` (16 files) has no `.dockerignore` line at all, so it is build-included and type-checked;
root `middleware.ts` and `instrumentation.ts` likewise. None was in the array. A single
`@/test/helpers/...` import added to an e2e file would have reproduced #7756 past a green guard
named "docker context import containment".

Two things follow, and the second is the one that generalises:

**A hand-maintained list inside a guard is a window, and windows are what this class is.** The
remedy is not a longer list — it is to DERIVE the set from the same predicate the system uses.
The roots now come from `fs.readdirSync(APP_ROOT)` filtered through `isExcludedFromContext()`,
the guard's own matcher, so a new directory joins the guarded set by existing.

**"Wrote the learning" is not "cannot repeat it."** I had the shape stated in prose, in a
post-mortem table, and in this file, and still typed the array. What caught it was an
adversarial reader on the diff — not recall. Budget the review, not the memory.

### 11. Two of my new assertions were satisfiable by machinery that checked nothing

The same review found the anti-vacuity measures I had added were themselves vacuous:

| assertion | why it pinned nothing |
|---|---|
| `expect(files.length).toBeGreaterThan(200)` | ~820 files actually walked, so dropping `server/` (316) still passed — a 4x coverage collapse inside the floor |
| `expect(offenders).toEqual([])` | `resolveAlias` lacked `index.tsx`, so 18 real edges resolved to `null` and the sweep `continue`d past them |

The second is the sharper one. **"No offenders found" is satisfied perfectly by a resolver that
resolves nothing** — an unresolvable specifier is an UNCHECKED specifier, and the emptiness reads
identically either way. The fix is a separate assertion that resolution is *total*, so a
skipped edge reds rather than counts as a pass.

For the floor: a flat number against a population you did not measure is a guess. Replace it with
a CONSERVATION check against an independent enumerator (here `fs.readdirSync({recursive: true})`
versus the guard's own hand-rolled walk) — agreement between two different code paths is evidence;
a magic constant is not. My first attempt was a per-root `> 5` floor, which false-failed on
`docs/`, a legitimately TS-free in-context directory. Conservation handles zero correctly and a
floor never will.

Both survived my own first mutation battery (M3, M4) and were closed only after it. Insight 8's
rule — enumerate the AXES, because N mutations of one shape is one mutation — is what surfaced
them; the axes here were "the resolver" and "the population", neither of which my first battery
touched.

### 12. A correct conclusion inherited from a sibling block, whose stated reason had gone stale

My `.dockerignore` comment justified avoiding a bare `!test/helpers/` bang by citing the
`_plugin-vendored` block twelve lines below, which records that a bare directory bang is
recursive. Review checked the citation instead of accepting it: that block's stated RULE —
"children are reachable only when the dir itself is also banged back in" — no longer holds on
buildkit. Deleting its `!_plugin-vendored/` line leaves the children in context.

The conclusion I drew was right and I had measured it independently with a minimal `docker build`.
What was wrong was pointing the next reader at an explanation that would mislead them. This is
compound's "inherited SENTENCE" gate firing on a real case: the words survived the move into a new
context, the evidence did not. The comment now cites the measurement and explicitly warns that the
block below is stale.

## Unresolved

The audit script reproducibly selects a binary file that my standalone `grep` reproducibly does
**not** match — same pattern, same file, verified across the alternation × recursive 2×2, both
locales, GNU grep 3.12. I fixed the behaviour through the script (the real instrument) and
verified it there, but I never explained the divergence. Recording it rather than implying the
2×2 settled it. If this recurs, suspect a `grep` shim on the interactive PATH (the repo already
documents a ugrep/GNU-grep hazard elsewhere).

## Session Errors

1. **Stopped after review instead of continuing to compound → ship.** The operator had to ask
   "why did you stop?". — Recovery: resumed the lifecycle tail. — **Prevention:**
   `rf-never-skip-qa-review-before-merging` and review Step 6 both already say review is not a
   stopping point; the failure was treating "CI is running" as a turn boundary. Waiting on CI is
   not a handoff — the trailer, compound and ship all run while it does.
2. **Skipped the review-evidence trailer.** Step 6.3 says emit it ALWAYS, not conditional on
   step 2 — and `/ship` reads that boolean. — **Prevention:** emit the trailer immediately after
   the last review fix commits, before any status narration.
3. **Introduced a `lint-shell-capture-exit` finding → `test-scripts` CI red.** — **Prevention:**
   run the repo lints after each guard-shaped commit (see insight 9).
4. **Shipped a hand-maintained directory array as the fix for a hand-maintained window.** —
   Recovery: derived the set from the context matcher. — **Prevention:** when a guard needs "the
   set of X the system treats as Y", derive it from the system's own predicate; treat any literal
   array inside a guard as a finding to justify, not a default.
5. **Wrote two assertions that could not fail** (a floor 4x below the real population; an
   emptiness check a null-returning resolver satisfies). — **Prevention:** for every new
   assertion, name the mutation that would red it *before* committing, and put it in the battery.
   An emptiness assertion always needs a companion totality assertion.
6. **Nearly shipped a recursive `!test/helpers/` directory bang** that would have pulled 26 files
   including `esbuild` and `claude-agent-sdk` importers into the type-checked context —
   reproducing the class in a new place inside the PR fixing it. — Recovery: caught by a minimal
   empirical `docker build`. — **Prevention:** for `.dockerignore`, `.gitignore` and any other
   pattern language with non-obvious recursion, MEASURE with the real tool; do not reason from a
   sibling comment.
7. **Cited a sibling comment block whose stated rule was stale.** — **Prevention:** compound's
   inherited-sentence gate, applied to comments as well as prose: run the command that falsifies
   the claim you are about to cite.
8. **Wrote guessed issue numbers (#7786/#7787) into the PIR before filing them.** — Recovery:
   filed for real (#7788/#7789) and corrected every citation. — **Prevention:** file first, then
   write the number; never draft a placeholder that looks like a real reference.
4. **The exit-70 guard could not fire.** — **Prevention:** for any guard, name the input that
   should trip it and run that input, rather than reasoning that the branch is reachable.
5. **Three defects in the `[2b]` block I edited.** — **Prevention:** editing a block makes its
   whole surface reviewable, not just the lines changed.
6. **Called a single-axis mutation "load-bearing".** — **Prevention:** insight 8.
7. **Wrote a false causal claim into code comments and the commit message.** — **Prevention:**
   for every causal claim prose ADDS, name the command that falsifies it and run it. One
   `git show origin/main:… && bash … --detect` would have caught it.
8. **Proposed a scope-out whose premise the fix dissolves.** — **Prevention:** insight 7.
9. **Misread `rc=$?` after a pipe** (got `tail`'s status, reported a lint as failing when it was
   a usage error); **ran the window-closure lint without `--allowlist`** and read rc=1 as a
   finding. — **Prevention:** capture rc into a variable before any pipe, and invoke a lint the
   way `test-all.sh` invokes it rather than bare.
10. **Spawned the review panel before committing an inline fix**, against the skill's own sharp
    edge; one agent reported it as uncommitted drift. — **Prevention:** commit pre-review fixes
    first (one-off; the rule already exists).
11. **Unexplained grep/script divergence** — see Unresolved above.
12. **One mutation row had a wrong anchor** (landing-fail, correctly reported as such rather than
    as a survivor). — One-off; the landing assertion did its job.

## Prevention

- For any guard, state the property in one sentence and the check's SCOPE in another, then ask
  whether the second covers the first.
- Enumerate a mutation battery's **axes**, not its count.
- Run cheap deterministic lints after each guard-shaped commit, ahead of the agent panel.
- When a name (step, constant, message, field) claims a scope, check the *query/predicate*
  independently — the names agreeing with each other is not evidence.
- Route meaning-of-a-constant forks to the owning domain agent for a binding ruling.
