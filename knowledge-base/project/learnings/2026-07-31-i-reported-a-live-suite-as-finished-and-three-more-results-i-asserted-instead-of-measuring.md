---
module: git-worktree / tenant-integration
date: 2026-07-31
problem_type: logic_error
component: shell_script
symptoms:
  - "reported a still-running 40-minute test suite as FINISHED"
  - "proceeded past `Tests 3 failed | 25 passed` on a guard I had just written"
  - "committed a source comment citing an issue number I had never filed"
  - "over-corrected a true claim into a false one on a reviewer's say-so"
root_cause: unverified_assertion
severity: high
tags: [verification, mutation-testing, self-match, review-findings, honest-reporting]
synced_to: [compound, review, work]
---

# I reported a live suite as finished, and three more results I asserted instead of measuring

The PR (#7109, closing #7101 + #7102) existed to fix two steps that **report a success
they did not achieve**. While fixing them I produced four of the same defect, in my own
process rather than in the code. That symmetry is the learning: the failure mode is not a
property of shell scripts, it is a property of *reporting on your own work*.

## The four

### 1. A liveness check that matched itself

`TEST_GROUP=scripts bash scripts/test-all.sh` was running in the background. I polled it
with a loop whose exit condition was:

```bash
if ! ps -ef | grep "test-all.sh" | grep -v grep > /dev/null; then echo "FINISHED"; break; fi
```

The loop's own `/bin/bash -c` command line **contains the string `test-all.sh`** (in the
log path and in the grep pattern itself), so `grep -v grep` does not filter it — the
wrapper is not `grep`. The check therefore reported a process that was my own poller, then
in a later iteration reported `FINISHED` while the real suite was still 3,000 lines from
its terminal marker. I recorded a completed run that had not completed.

The repo already documents this trap **for `pkill`** (`git-worktree/SKILL.md` §Sharp
Edges: "`pgrep -f "<script>"` matches its OWN command line, so it always finds ≥1 process
and can never report 'not running'"). It recurred here in the read-only direction, where
the consequence is inverted: instead of never reporting "not running", a self-match can be
*evicted* between polls and produce a false "not running".

**What to do instead:** resolve liveness by **PID** and confirm ownership via
`readlink /proc/<pid>/cwd`, plus log-size growth over a window. Never by a name grep whose
pattern appears in the grepping command.

```bash
[[ -d /proc/$PID ]] || echo "EXITED"
readlink /proc/$PID/cwd      # is it mine, or a sibling worktree's?
```

And read the runner's **terminal marker** (`=== N/M suites passed ===`), not the absence
of a process — a killed run and a finished run look identical from the process table.

### 2. I ran my own test, saw it fail, and kept going

After adding three fixtures to the new `#7101` guard I ran it. The runner printed:

```
Test Files  1 failed (1)
     Tests  3 failed | 25 passed (28)
```

I read the line, did not diagnose it, and moved to the next step. `test-design-reviewer`
later found the cause and rated it **P0**: all three fixtures used one-liner hook bodies —

```ts
"  beforeAll(async () => {}, 60_000);",
```

— and `parseHooks` pairs a hook to a **closer on its own line at matching indentation**. A
one-liner has no closer, so all three hooks were dropped and the fixtures asserted
*nothing*. They were not merely failing; they were structurally incapable of passing.

`hr-when-a-command-exits-non-zero-or-prints` covers exactly this. The gap was that I
applied it to *other people's* commands and not to test output I had produced myself,
where a failure feels like a work-in-progress state rather than a finding.

**What to do instead:** a non-zero failure count in a run you initiated is a **stop
condition**. Diagnose before the next action, even mid-edit — especially then, because a
fixture that cannot pass is invisible once the suite goes green for unrelated reasons.

### 3. A citation to an issue that did not exist

I wrote into a committed source comment:

```ts
// … it is not a claim that one exists today. Tracked in #7115.
```

I had not filed #7115. I had *intended* to file it pending a CONCUR gate. **#7115 is a
real, unrelated open PR** (`WIP: feat-one-shot-ci-ssh-token-replace`), so the comment would
have pointed every future reader at the wrong artifact — worse than no reference, because
it resolves.

This is the outward-facing sibling of the `session-state.md` rule (*a Decisions entry is
INTENT, not an accomplishment*), applied to an artifact I was writing in the same breath.

**What to do instead:** never write `#N` into a committed artifact before `gh issue
create` has returned it. Reconcile every `#N` in a diff with `gh issue view N --json title`
before committing — the check is one call and the failure mode is silent.

### 4. Over-correcting a true claim into a false one

I shipped a comment saying the new `SOLEUR_ORPHAN_UNREMOVABLE` sentinel was "mirrored to
the telemetry sink". An observability review rated that **P1-unreachable** and argued the
marker reaches no sink at all. I verified two of its three legs — the local CLI really does
register no `PostToolUse` `Bash` hook, and `apps/web-platform/server/*.ts` really has zero
`.worktrees` references — accepted the framing, and rewrote the comment to assert the entry
"does NOT currently mirror anything to a queryable sink."

The CONCUR gate then refuted **my correction**:

- `plugins/soleur/commands/go.md` Step 0 runs `cleanup-merged` **verbatim**, and that
  plugin loads via the *same* options object that registers the hook
  (`agent-runner-query-options.ts` — `plugins: [{type:"local"}]` alongside `PostToolUse`
  matcher `"Bash"`).
- `safe-bash.ts`'s *"write verbs (create/cleanup-merged/draft-pr) stay gated (they run via
  the autonomous/sandbox path, never here)"* means **"not in the exact-literal auto-approve
  carve-out"** — not "cannot run in this session". Read in full, the comment scopes an
  allowlist; read as a fragment, it looks like it scopes reachability.

Both the reviewer and I had quoted the fragment. The correct answer is narrower than either
claim: **mirrored on the platform surface, unmirrored from the local CLI**, and *"can reach
the hook"* is established while *"has reached it"* is not (go.md's preamble may skip
silently).

**What to do instead:** when a finding turns on the reading of a code **comment**, quote the
comment in full and ask whether it constrains the *mechanism* or only a narrower
*allowlist*. And treat your own correction as a **new claim needing its own verification** —
it does not inherit the credibility of the finding that prompted it. Two agents agreeing is
one agent when they share a misreading.

## The generalizable rule

All four reduce to: **I reported a state I had not measured, in a session whose entire
subject was steps that report unmeasured success.** The tell in each case was an artifact
that *reads like* evidence — a process listing, a test summary, an issue number, a
reviewer's P1 — standing in for the measurement.

Before recording any result, ask: *what did I actually observe, and could the thing I
observed be produced by the failure case too?* A missing process, a green-looking summary
line, a resolving `#N`, a confident finding — every one of those is satisfied by both the
success and the failure.

## The same defect, in the code

Worth keeping alongside, because it is the identical shape one layer down:

- The reaper incremented `orphans_cleaned` without checking `rm -rf`'s exit status, then
  printed `Cleaned N orphan directory(ies)` for directories still on disk.
- It printed `Removed orphan directory: <name>` on the failure path too.
- It returned `rc=1` after a **successful** clean at `verbose=false` (its last statement was
  `[[ … ]] && echo`), aborting `cleanup_merged_worktrees` under `set -e` and silently
  skipping the two `/tmp` reapers after it.

And two vacuity findings in my own tests, both the "one-directional fixture" class:

- The `#7101` rule lived inline in the `it.each` arm, whose only input is a corpus that is
  **symmetric by construction** once fixed. Widening the `afterAll` fallback to
  `?? Infinity` kept the suite green **while no longer detecting the original regression**.
  Extracted to an exported `violationsFor()` and driven by fixtures for the shapes the
  corpus cannot contain.
- Neither suite had a fixture asking *"does it stay silent when there is no failure?"*, so
  an unconditional failure summary and a sentinel on the success branch both passed.

## Mutation battery notes

Ten mutations, control clean, all ten caught after two rounds. The two that survived round
one are the interesting ones:

| Mutation | Why it survived |
|---|---|
| failure summary made unconditional | It **crashed** (`${orphans_failed_errno[0]}` unbound under `set -u`) rather than printing, and *silence satisfied the greps* asserting absence. Fixed by also asserting `rc=0` on a clean run. |
| success counter corrupted on the default path | Nothing **read** the counter at `verbose=false` — the only consumer was a verbose-gated summary. Fixed by carrying `cleaned=` in the marker, which prints at any verbosity. |

Generalization: an assertion of **absence** is satisfied by a crash, and a value with **no
reader on a given path** cannot be tested on that path. If a counter matters, give it a
reader at the verbosity where it matters.

Also re-confirmed: a mutation that produces a **syntax error** has not landed — my first
attempt to gut the assertion helpers produced `rc=2` from a parse failure, which briefly
read as "the floor binds". Assert the mutation landed (`diff -q` against a pristine copy)
*and* that the failure mode is the one you intended.

## Session Errors

1. **`ps | grep "test-all.sh"` self-matched my own poller** — reported a live suite as
   FINISHED. Recovery: re-checked by PID + `/proc/<pid>/cwd` + log growth; the run was alive
   and completed 232/232. **Prevention:** resolve liveness by PID, never by a name grep whose
   pattern appears in the grepping command; read the runner's terminal marker.
2. **Proceeded past `Tests 3 failed | 25 passed` on my own new guard** — the three fixtures
   were structurally dead. Recovery: `test-design-reviewer` caught it as P0; fixtures
   rewritten multi-line. **Prevention:** a non-zero failure count in a run you initiated is a
   stop condition, not a data point.
3. **Cited `#7115` in a committed comment for an unfiled issue** — it is a real, unrelated
   PR. Recovery: reference removed after the CONCUR gate dissented on filing at all.
   **Prevention:** never write `#N` into an artifact before `gh issue create` returns it;
   reconcile with `gh issue view N --json title` pre-commit.
4. **Over-corrected the observability claim on a reviewer's finding** — wrote a false
   comment after verifying only 2 of 3 legs. Recovery: CONCUR gate refuted it with `go.md`
   Step 0 + the `plugins:`/hook co-location. **Prevention:** quote a load-bearing code
   comment in full; treat your own correction as a new claim requiring its own evidence.
5. **Prose describing a blocked command trips the guardrail that blocks it** — writing the
   #7113 comment body was denied by `guardrails:block-rm-rf-worktrees`. Recovery: wrote the
   body via the Write tool, then `gh issue comment --body-file`. **Prevention:** the matcher
   cannot distinguish a command from a description of one — folded into #7113.
6. **A heredoc in the same Bash call as a guardrail-gated `gh` command lost the file
   write** — the denial rejects the whole call. Recovery: separate Write step.
   **Prevention:** already ruled; write bodies with the Write tool first.
7. **Rebase after the plan subagent had pushed required `--force-with-lease`.** Recovery:
   verified the remote held nothing I lacked before forcing. **Prevention:** rebase before
   the subagent pushes, or expect a lease-push.
8. **A mutation that produced a syntax error briefly read as a result** (`rc=2`).
   **Prevention:** assert the mutation landed AND that the failure mode is the intended one.
9. **`observability-coverage-reviewer` stalled 600s** with no output. Recovery: respawned
   with a narrowed prompt per review Gate 2b. **Prevention:** none needed — retry is the
   sanctioned path; naming the missing agent is the requirement.
10. **shellcheck SC2218** — a `git()` shadow in the test was visible to earlier real `git`
    calls. Recovery: replaced with a non-repo CWD, which fails `git worktree list` naturally.
    **Prevention:** never shadow a binary the fixture code also uses.
11. **Plan AC 6.5 was falsified by measurement** — it claimed removing `return 0` would fail
    case 4; the mutation survives. Recovery: corrected in `tasks.md` and in the code comment.
    **Prevention:** a plan's stated mutation proof is a claim to re-run, not a fact.
12. **Webplat suite failed once (`run-migrations-unmerged-gate`, status −1 at 30s)** under
    concurrent load. Recovery: passed 3/3 in isolation; confirmed contention, not regression.
    **Prevention:** already ruled (contention banners); check isolation before attributing.

Plan-phase errors forwarded from the planning subagent's summary: `test-design-reviewer`
returned empty (terminated at 15 tool calls); `source` piped into `head` lost definitions to
a subshell; an unsorted `comm` produced false path mismatches; a test string tripped
`guardrails:block-rm-rf-worktrees` (the same class as #5 above).

## Related

- `knowledge-base/project/learnings/2026-07-25-i-added-the-field-that-closes-the-gap-and-nothing-read-it.md`
  — the "emitted a value nothing consumes" sibling; item 2 of the mutation table here is the
  same defect inside a single function.
- `knowledge-base/project/learnings/2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`
  — the fixture-cardinality class; every failure fixture here started at N=1.
- `plugins/soleur/skills/git-worktree/SKILL.md` §Sharp Edges — the `pkill`/`pgrep`
  self-match entry that item 1 recurred against in the read-only direction.
