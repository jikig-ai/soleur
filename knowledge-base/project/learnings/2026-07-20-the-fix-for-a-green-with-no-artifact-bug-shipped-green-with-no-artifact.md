---
module: cron-community-monitor
date: 2026-07-20
problem_type: logic_error
component: inngest_function
symptoms:
  - "monitor posts GREEN Sentry check-in with no committed digest"
  - "livenessOk initialised true left the bug class reachable on the first attempt"
  - "mutation battery green while two enforced properties were untested"
root_cause: fail_open_default
severity: high
tags: [fail-closed, observability, mutation-testing, cron, vacuous-test, adr-drift]
issues: [6714, 6713, 6720]
pr: 6726
synced_to: [work, review]
---

# The fix for a GREEN-with-no-artifact bug shipped GREEN-with-no-artifact

## Problem

`cron-community-monitor` posted a GREEN Sentry check-in every day from 2026-07-14 to 07-19 while committing **no digest at all**. The monitor was not broken — it faithfully reported the thing it was asked to report, and it was asked to report the wrong thing. Its colour came from `resolveOutputAwareOk` ("did a labelled GitHub **issue** land"), which is a correct *persistence* gate but not a liveness signal: the artifact the operator consumes is the committed `<date>-digest.md`.

The fix (#6714) added a `livenessOk` signal asserting the committed artifact. **It did not close the bug class.**

`livenessOk` was initialised `true` and falsified only by an OBSERVED negative. So a throw anywhere between `verify-output` and the persistence gate left `heartbeatOk` true and `livenessOk` never falsified:

```
failed = threw && !heartbeatOk   // true && !true  =>  false
```

No retry fired, and the run posted a **terminal GREEN with nothing committed, on the first attempt** — verbatim the shape the same PR's own ADR-126 forbids.

## Root cause

A fail-open default on a signal whose entire job is to *assert* something, protected by a plausible-sounding justification that was never checked.

The comment defending the default named a concrete hazard: honest falsification would make `finalizeOutputAwareHeartbeat` retry, and the Inngest replay would run against a `spawnCwd` the `finally` already deleted, firing a false `workspace-lost` event. Both halves were false:

- **The hazard already existed on `main`.** `if (collectorSignalRed) heartbeatOk = false` is set *before* the persistence gate, so a collector-red run that then throws already produces `threw && !heartbeatOk` → retry → replay against the deleted workspace. The fail-open default bought nothing `main` had not already lost.
- **The harm was understated, not overstated.** `failure()` calls `commentOnScheduledIssue`, posting *"PR withheld: safe-commit failed at stage `workspace-lost`"* with a runbook pointer onto the operator's issue — sending a non-technical operator to a runbook for a fault that did not occur.

## Solution

Two parts. The first alone does not work: in the exploit `livenessOk` is `true`, so changing only the retry behaviour leaves the colour predicate unchanged.

**1. Fail-closed.** `livenessOk` is initialised `false` and set true only by an observed positive, so every throw that never reaches the persistence branch leaves the run RED by construction — no `reachedPersistenceGate` bookkeeping to get wrong.

```ts
let livenessOk = false;               // was: true
if (commitResult.status === "committed") {
  if (commitResult.paths?.includes(digestPath)) {
    livenessOk = true;                // the only positive
  } else if (commitResult.paths === undefined) {
    livenessOk = commitResult.resumed === true;   // R21: undetermined != absent
  }
  // else: committed something, but not today's digest -> stays RED
}
```

**2. Separate the colour from the retry.** `finalizeOutputAwareHeartbeat` conflated "what colour do we post" with "can a replay recover this". They are independent, and for a producer whose workspace is destroyed in its own `finally` the second answer is *always no* (`setup-workspace` is memoized, so a replay reads back a deleted path).

```ts
// _cron-shared.ts — additive, `!== false` so omitting it is byte-identical
const failed = threw && !heartbeatOk && retryEligible !== false;
```

The widening that looked cross-cutting was **6 lines**: `cron-safe-commit-parity.test.ts` constrains only the gate literal, not the helper signature, so 7 of 8 cohort callers were untouched by omission.

## Key insights

**A signal whose job is to ASSERT an artifact must be fail-closed.** An unobserved artifact is an unasserted artifact. Initialising true and falsifying on observed negatives inverts the burden of proof onto the failure path — which is exactly where observation is least reliable.

**When a comment justifies a weakened default by naming a hazard, grep whether that hazard already exists on `main`.** A hazard that predates your change is not a cost your weakening avoids. This is the cheapest possible check and it falsified the entire argument.

**Two conflated questions force a false trade.** The fail-open default only looked necessary because one boolean answered both "what colour" and "should we retry". Separating them dissolved the dilemma. Before accepting a scope argument ("that helper is shared by 8 crons"), *measure* the blast radius — here it was an optional field and zero behavioural change for the other callers.

**A verdict and its reasoning are separately evaluable.** DC-1's decision (retain marker 4) survived review while *both* of its stated arguments died: one was circular (citing an ADR authored in the same diff as an external constraint), the other backward-looking (the marker could not have helped in the gap days because it did not exist). The right answer rested on an argument nobody had made — instrumenting a branch a *prior* decision deliberately retained is not YAGNI.

**An ADR asserting behaviour the code no longer has is worse than no ADR.** ADR-126 declared the fail-open default deliberate and correct, so it had to be amended in the same commit, with the old default recorded as a *rejected* alternative carrying its reachability proof.

## The mutation-battery class recurred — for the third time in five days

This is the part that matters most, because it is now a pattern rather than an incident. See [[2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it]] and [[2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of]].

I ran mutation batteries and they were green. A reviewer prompted specifically to *"find what my battery missed — do not re-run my mutations"* found four vacuities, **two of them in the property the PR exists to enforce**:

| Vacuity | Surviving mutation | Consequence |
|---|---|---|
| Every `paths` fixture had ONE element | `paths[0] === digestPath` | 21 tests green; `includes` and positional compare indistinguishable |
| No wrong-date near-miss | `paths.some(p => p.endsWith("-digest.md"))` | a **stale** digest kept the monitor GREEN — the date anchor is the whole point of #6714 |
| Table's comment *claimed* exhaustiveness | appended a 6th emitter at `info`, no fail-open, carrying `user_email` | 16/16 passed |
| `attempt` field shipped untested | `attempt: 0` constant | nothing failed — in the very commit fixing the above |

Derived rules:

- Whenever production calls `.includes` / `.some` / `.filter`, **at least one fixture needs ≥2 elements**, or the predicate silently degenerates to equality and is never tested as membership.
- A near-miss fixture is mandatory for any *anchored* property (a date, a prefix, an id). Without one, relaxing the anchor to its shape passes.
- **A table that claims exhaustiveness in a comment must assert its cardinality against the producer** — `expect(TABLE.length).toBe(Object.keys(mod).filter(k => k.startsWith("emit")).length)`. A comment is not a quantifier.
- **Mutation batteries must cover the FIELDS you add, not just the logic you change**, and a varying field must be asserted on a **non-zero** value — a zero fixture cannot distinguish the real value from a hardcoded constant.

Because this class has now recurred three times in five days despite being documented twice, the disposition is a **mechanical gate, not a fourth learning**: the self-graded battery should be replaced by a reviewer whose brief is explicitly "find what the battery missed", which is what caught all four here.

**A dead branch that reads as load-bearing** is the same family. The first R21 carve-out (`else if (resumed && !paths) livenessOk = true`) could not change any outcome — with it deleted, `paths === undefined` also failed the next condition, so the test stayed green either way. Mutation found it; the fix was to make the discriminator the actual semantic (`paths === undefined`) so `resumed` became load-bearing.

## Verify a review finding against the artifact before acting on it

Both directions occurred in this session:

- The test-design agent's multi-element finding cited `collector-status.jsonl` as landing in the allowlisted community directory. Production writes it to `.soleur-collector-status/`, which the code explicitly notes is **outside** `COMMUNITY_MONITOR_ALLOWED_PATHS`. The **gap was real** (the allowlist is the whole directory, so other files can land beside the digest) but the **cited example was not** — fixed with a realistic fixture rather than the suggested one.
- Inversely, agent *convergence* was right where a single agent's rationale was wrong: three agents independently reached the `deduped`-is-redundant conclusion, and that one held.

## Session Errors

**Resumed session's file was broken, not merely incomplete** — six symbols used with no imports, and `livenessOk` computed but never applied, so the whole feature was dead code that could not compile. — Recovery: added imports, applied the signal. — **Prevention:** on resume, TYPECHECK the resumed files before extending them; "mid-write" is a stronger claim than "incomplete", and a resumed artifact is unverified until the compiler says otherwise.

**`matched_issue` typed required but never passed** (TS2345); the value was unobtainable without widening a 9-consumer helper. — Recovery: dropped the field and documented why. — **Prevention:** design marker payloads from what the call site can actually supply, not from what would be nice to have.

**Assumed the fixture's `cronName` was the production name** (`cron-community-monitor` vs `cron-test-fixture`). — Recovery: read `baseConfig`. — **Prevention:** read the fixture's config before asserting on values it produces.

**Used `npx vitest` / `npx tsc` instead of the pinned `./node_modules/.bin/`.** — Recovery: switched. — **Prevention:** already an existing rule; it was violated before the skill body surfaced it. The pinned-binary rule belongs in the first command, not the third.

**Zero-parameter `vi.fn()` typed `mock.calls` as a zero-length tuple** → TS2493, suite green / tsc red. — Recovery: rest param. — **Prevention:** any `vi.fn()` whose `.mock.calls` are indexed needs `(..._args: unknown[]) =>`.

**Foreground `test-all.sh` timed out at 10 minutes.** — Recovery: backgrounded with an explicit rc file. — **Prevention:** background long suites from the start; the suite takes >10 min by design.

**FALSE RED from a sibling worktree's concurrent `test-all.sh`** — 4 `skill-security-scan` failures caused by another session's simultaneous run colliding on the scanner's shared `.scan-meta.json` paths. — Recovery: confirmed three ways (isolated re-run 22/0, the CI `skill-security-scan` gate SUCCESS, clean 193/193 once the sibling finished) rather than dismissed as flake. — **Prevention:** parallel worktrees are this repo's documented workflow, so this is reproducible, not exotic. Before treating a full-suite failure as real, run `ps -ef | grep test-all | grep -v grep` and check `/proc/<pid>/cwd` for a sibling worktree; a shared-path suite failing while CI is green is contention until proven otherwise.

**Backgrounded wrapper's rc file came back empty**, and the harness reported the trailing `echo`'s exit 0 rather than the suite's. — Recovery: re-ran and gated on file contents. — **Prevention:** gate the waiter on `[ -s "$rc" ]`, never `[ -f "$rc" ]`, and never trust a background notification's exit code for a compound command.

**`/tmp` tmpfs hit ENOSPC** (4 GB, shared across concurrent sessions), losing harness output mid-command. — Recovery: moved logs to `/var/tmp` (real disk, 550 GB free) and removed my own consumed logs. — **Prevention:** write large logs to `/var/tmp`, not `/tmp`, whenever a session may run alongside siblings.

**Referenced a non-existent spy (`readCollectorStatusSpy`)** for a module-local function that no sibling `vi.mock` can intercept. — Recovery: added a `throwOn` parameter to the fake `step`. — **Prevention:** for a function defined in the module under test, the injected collaborator (here the fake `step`) is the only seam; mocking a sibling module cannot reach it.

**Duplicated a block in `decision-challenges.md`** while replacing a large prose section. — Recovery: removed the stale copy. — **Prevention:** `grep -c` the anchor after any large prose replacement.

**Shipped marker 3's `attempt` field untested** — mutating it to a constant failed nothing. — Recovery: added a call-site assertion on a non-zero attempt, then re-mutated to confirm. — **Prevention:** see the field-coverage rule above.

**Review-found defects (all mine):** the fail-open `livenessOk`; the dead R21 branch; the redundant `deduped` field; an ADR-029 comment naming the wrong residual risk (Vector re-applies the userId HMAC downstream — the real gap is the `redact` **key** set); "~38 consumers construct" mislabelled (~5x overstated; 38 is the *reference* count, 12 sites across 7 files construct); and the four test vacuities. — **Prevention:** the count/citation-accuracy rules already exist; what caught these was routing an explicit "verify every numeric claim against the artifact" instruction into the review prompt, which is cheap and should be default for comment-dense diffs.

## Related

- ADR-126 — a cron's liveness signal must assert the artifact operators consume
- [[2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it]]
- [[2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of]]
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]]
- Follow-ups: #6734 (tempfile sweep), #6736 (argv sweep), #6737 (cohort audit), #6738 (pre-existing stderr leak), #6739 (predicate asymmetry)
