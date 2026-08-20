---
title: "Make the deferred suites' anti-vacuity floors survive their own helpers, and make the subagent full-gate refusal reachable"
date: 2026-08-19
slug: fix-vacuity-floor-and-subagent-gate
branch: feat-one-shot-7580-7553-vacuity-floor-subagent-gate
issue: 7580
closes: [7580, 7553]
lane: cross-domain
type: fix
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
adr: ADR-194 (provisional), amendment to ADR-193
---

> Spec carries no `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain`
> (TR2 fail-closed). The Domain Review sweep below records the actual finding.

## Overview

Two defects in the test harness, both the same shape: **a control that cannot fire under the fault
it exists to catch.**

**#7580** — bash suites whose anti-vacuity floor reports its verdict *through the suite's own
`fail`/`bad` helper*. Because the floor runs through the machinery it is meant to outlive,
neutering that helper silences the assertion rows and the floor together, and the suite prints a
clean total and exits 0. ADR-193 fixed ten sibling suites to a three-property contract on
2026-08-16; this work applies that contract to the suites still carrying the defect.

**#7553** — `scripts/test-all.sh` exits 4 when `SOLEUR_SUBAGENT=1` is set without
`SOLEUR_ALLOW_FULL_GATE=1`. The guard is correct and covered. Nothing anywhere in the repository
sets `SOLEUR_SUBAGENT=1`, so its antecedent never holds and the refusal has never fired. Two skill
documents assert the mechanism as a fact about the harness.

Both were re-measured from scratch during planning, and **both premises moved under the brief.**
The Research Reconciliation section below is load-bearing: the population is larger than eight, one
named suite is already compliant, and the ratchet the brief expects to shrink is derived in a way
that makes it structurally incapable of shrinking. Read that section before the phases.

> **Every `path:N` coordinate in this plan is a PLAN-TIME (2026-08-19) reading, and the PR this
> plan describes moves most of them.** They are kept as written so the plan stays a faithful record
> of what was read when the decisions were made; do not "refresh" them, and do not cite them
> onward. Where a coordinate is load-bearing for a later reader it has been restated as a content
> anchor below (`cq-cite-content-anchor-not-line-number`). Resolve anything else by grepping the
> quoted text.

## Research Reconciliation — Brief vs. Codebase

Every row was measured on this branch on 2026-08-19 with the command shown. These are not
adjustments of emphasis; three of them change what the work is.

| Brief claim | Measured reality | Plan response |
|---|---|---|
| "The eight measured NO_FIRE suites" (hardcoded list) | **Eleven.** Running the guard's own classifier over the deferred directories yields `floor does NOT fire: 11`. Seven of the brief's eight are in it; four suites the brief never names are also NO_FIRE. | Scope the work to the **derived** set, never the list. Phase 0.2 re-derives it at implementation time; the plan's eleven are a dated snapshot, exactly like the brief's eight. |
| `apps/web-platform/infra/doppler-download-error-channel.test.sh` is NO_FIRE | **It FIRES.** Absent from both the NO_FIRE and CONSTRUCTION lists in the probe run, therefore classified FIRES — already compliant. | **Dropped from scope.** Touching it would be churn against a suite that already satisfies the contract. |
| `MAX_CONSTRUCTION_FAILURES` "sitting at exactly 17" | **It is 15** (`scripts/guard-vacuity-floor.test.sh:398`). The figure 17 survives only in that file's own prose at lines 462-463 and 473, which is stale against its own code. | Treat 15 as the number. The brief's *conclusion* is unaffected and still binding: `n_construct` measured 15 against a cap of 15 — **zero headroom, confirmed**. Do not touch it. Fix the stale comment as a drive-by. |
| "`MAX_DEFERRED` is shrink-only. Covering these suites lowers it." | **False.** `n_deferred` is derived at `:209` by a *directory* regex over floor-bearing suites (`DEFERRED_DIRS`), not by whether a floor fires. A hardened suite is still floor-bearing (the shape detector matches the `-lt` comparison either way) and still sits in a deferred directory. `n_deferred` measured 47 against `MAX_DEFERRED=47` and **will still be 47 after every suite is fixed.** | Do not attempt to lower `MAX_DEFERRED`; it is not the instrument. See the next row for what actually verifies the work. |
| (unstated) The guard will verify the fix | **It will not.** The mutation loop at `:360-367` reads `< "$COVERED"` only, and all eleven suites are outside `COVERED_DIRS`. Every one of the guard's arms returns an identical verdict before and after this work. | **This is the plan's central design problem.** Phase 2 adds a per-scope arm over the *deferred* population so the fix is mechanically visible. This is precisely the "per-scope ratchet first" the brief names as the prerequisite for widening — and it needs no change to `COVERED_DIRS` and no change to `MAX_CONSTRUCTION_FAILURES`. |
| (unstated) ARM 10's conservation checks will cover the new work | **They will not.** `CONSERVING` is built at `:626-629` from `< "$COVERED"`. New conservation checks in deferred suites are neither counted (ARM 10) nor structurally validated (ARM 10b/10c/10d). | Extend the per-scope arm to carry the conservation structure checks over the deferred scope too. |
| "set `SOLEUR_SUBAGENT=1` on the agent-spawn path" | **No repo-controlled spawn path exists.** Agent spawning happens only via the model calling the `Task` tool; `plugins/soleur/lib/harness.ts` is a pure string formatter whose `AgentSpawn` interface has no env field. Eleven candidate mechanisms enumerated, all blocked — see Research Insights §Mechanism enumeration. | Two repairs were considered. (a) *Read* a variable the harness already sets — measured available (`CLAUDE_CODE_CHILD_SESSION=1`, `AI_AGENT=claude-code_2-1-228_agent`, both present in a spawned agent's Bash environment and absent from the `claude` process's own environ). **Rejected**: it would refuse every spawned agent's `lefthook` pre-commit, and its fail-open mode is structurally untestable. (b) **SELECTED** — bind the refusal to a condition the runner already *measures*, `tc_preamble`'s sibling count. See Phase 3e. |
| "Spawned agents ... are spawned with `SOLEUR_SUBAGENT=1` in their environment" (`review/SKILL.md:159`, `work/SKILL.md:292`) | **False as a statement of fact.** Measured from inside two independent spawned agents: `SOLEUR_SUBAGENT` is UNSET in both. | Correct both sentences — unconditional under every repair path, and done in Phase 3a. |
| (unstated by the brief) #7553's concurrency harm is unmitigated | **Already mitigated, and it has its own accepted ADR.** `scripts/test-all.sh` calls `tc_acquire "test-all"` (plan-time `:688`) — a real `flock`-based advisory lock in `scripts/lib/test-contention.sh:569` — and calls bare `tc_preamble` just above it (plan-time `:681`), which already *detects and names* sibling runs (`[contention] siblings: N other worktree(s) running test-all.sh`, banner `SIBLING_RUN_DETECTED`). This is **ADR-133**. Concurrent local full-gate runs already serialise. | **This materially reduces #7553's value and must be stated plainly.** The residual harm the refusal would prevent is *a subagent waiting on the lock and then running a battery it should never have started* — wasted wall-clock, not corrupted measurement. The brief's stated justification ("concurrent full-gate runs inflate each other's timings, which corrupts any timing-derived verdict") is **already addressed**. Recorded as **UC-2**; see the revised Phase 3. Note the lock is CI-exempt (`LOCK_SKIPPED_CI` at `test-contention.sh:593`), but CI runs no spawned agents, so the exemption is not a gap. |
| "their 33 CONSTRUCTION cases would push that cap to ~50 and ARM 2 stops discriminating" | **Both halves falsified.** The deferred scope carries **16** construction failures, not 33, so promotion would move the cap 15 → **31**, not ~50. And ARM 2 is `n_construct -le MAX_CONSTRUCTION_FAILURES`: a ratchet at 31 catches the 32nd suite exactly as sharply as a ratchet at 15 catches the 16th. **Sensitivity to the next regression is 1 at every magnitude** — the cap's absolute value changes how it reads, not what it discriminates. | The brief's constraint is retained as the plan's default because it is the operator's stated direction, but its stated *rationale* does not survive measurement, and a reviewer proposed the simpler alternative it forbids. Recorded as **UC-3**; see Alternatives and `decision-challenges.md`. |

### Measurement commands

```bash
# Guard baseline, unmodified, on this branch (RC=0, 19 passed / 0 failed):
bash scripts/guard-vacuity-floor.test.sh
#   repo-wide floor-bearing : 104
#   covered (mutation-arm)  : 57      deferred (declared)     : 47
#   unclassified (must be 0): 0       floor fires             : 42
#   floor does NOT fire     : 0       mutant not constructible: 15

# The deferred population, classified by the guard's OWN classifier. A copy of the guard with
# COVERED_DIRS repointed at the four deferred directories and REPO_ROOT pinned:
#   covered (mutation-arm)  : 45      floor fires             : 18
#   floor does NOT fire     : 11      mutant not constructible: 16
```

The eleven measured NO_FIRE suites, as of 2026-08-19 (**a snapshot — re-derive in Phase 0.2**):

```
.claude/hooks/rule-incident-marker-capture.test.sh
.claude/hooks/ship-net-issue-flow-gate.test.sh
apps/web-platform/infra/git-data-render-strip-parity.test.sh          <- not in the brief
apps/web-platform/infra/git-data-rung2-rehearsal.test.sh
apps/web-platform/infra/git-data-template-strip.test.sh                <- not in the brief
apps/web-platform/infra/infra-config-apply.test.sh
apps/web-platform/infra/infra-config-handler-bootstrap.test.sh         <- not in the brief
apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh
apps/web-platform/test/infra/vector-pii-scrub.test.sh
plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh
plugins/soleur/skills/review/test/emit-review-trailer.test.sh          <- not in the brief
```

## Research Insights

### Premise Validation (Phase 0.6)

`gh issue view` confirms **#7580 OPEN** and **#7553 OPEN**, neither closed by any merged PR.
`gh pr view 7616` confirms an **OPEN draft** whose `headRefName` matches this branch. All eleven
paths cited by the brief exist on disk. ADR-193 exists at the cited path and its `## Decision`
mandates exactly the three properties the brief describes, so the proposed mechanism sits in an
ADR's *accepted* decision rather than its rejected-alternatives table. Four of the brief's factual
claims did not survive (see Reconciliation above); the two issue premises themselves did.

Adjacent open issues found and deliberately **not** resolved here: **#7517** (a bare
`[[ "$FAIL" -eq 0 ]]` final gate passes a suite that asserts nothing — the brief scopes this out
explicitly), **#7585** (no per-file promotion seam), **#7588** (the conservation population is
derived by message text).

### Property List (Phase 0.6b)

1. A suite whose verdict helpers are neutered must exit non-zero.
2. A suite whose verdicts are *discarded* (helpers stubbed, rows still counted) must exit non-zero.
3. A regression of (1) or (2) in the deferred directories must redden CI without anyone maintaining a list.
4. A full-gate run started from inside a spawned agent must be refused before anything runs.
5. A reader of `review/SKILL.md` or `work/SKILL.md` must not be told the harness does something it does not do.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property it would buy | What already covers it → verdict |
|---|---|---|
| Lower `MAX_DEFERRED` to reflect the fixed suites | (3) | Nothing — it is derived by directory and cannot move. **CUT**, replaced by the per-scope arm. |
| Promote the deferred directories into `COVERED_DIRS` | (3) | Blocked: their 16 CONSTRUCTION cases exceed the global cap of 15 with zero headroom, and ARM 4/5's double-count check rejects per-file promotion. **CUT** (this is #7585's seam). |
| Fix `doppler-download-error-channel.test.sh` | (1) | Its floor already FIRES. **CUT.** |
| A hardcoded list of the eleven suites inside the guard | (3) | ADR-193 §5: "The population is DERIVED, never listed." **CUT.** |
| Set `SOLEUR_SUBAGENT=1` via `.claude/settings.json` `env` | (4) | Measured to reach subagent Bash — but it is session-global, so it would refuse **the lead's own sanctioned gate run** on every invocation. **CUT on semantics, not capability.** |
| A new `PreToolUse` rewriter hook to inject the variable | (4) | ADR-162 permits exactly one `updatedInput` emitter, enforced at `.claude/hooks/hookeventname-coverage.test.sh:184`; `grep-rewrite.sh` holds the slot. **CUT.** |
| A test running `SOLEUR_SUBAGENT=1 bash scripts/test-all.sh` | (4) | Already covered by `fanout-suite-scope.test.sh` arms 1-3, and it proves the guard works, not that the spawn path arms it. **CUT** (this is the brief's named shape trap). |

### Mechanism enumeration for #7553 (the universal negative, enumerated before it is asserted)

| # | Mechanism | Status |
|---|---|---|
| M1 | `.claude/settings.json` `env` block | Works (measured) but session-global; cannot discriminate lead from subagent. Rejected on semantics. |
| M2 | `.claude/settings.local.json` | File does not exist; identical semantics to M1. |
| M3 | Agent-file frontmatter `env:` | No such key; `grep -rl "^env:" plugins/soleur/agents/` → zero. Blocked. |
| M4 | `Task` tool input | Schema is `{description, prompt, subagent_type}`. No env key. Blocked. |
| M5 | `PreToolUse` hook on a `Task` matcher | Not registered; `updatedInput` can only rewrite M4's three keys. Blocked. |
| M6 | A `SubagentStart` hook event | Not registered anywhere; no evidence it exists in CC 2.1.228. Blocked. |
| M7 | `PostToolUse` on `Task` (`agent-token-tee.sh`) | Fires after the subagent finishes, parent-side, telemetry only. Blocked by ordering. |
| M8 | `SessionStart` hook | Emits `additionalContext` prose, never env; hooks are children of `claude` so their exports die with them. Blocked. |
| M9 | `PreToolUse(Bash)` `updatedInput` rewrite | Measured working on a subagent's Bash call, but allowlist-blocked by ADR-162's single-rewriter invariant. Blocked. |
| M10 | Wrapper script / `harness.ts` adapter | `harness.ts` emits strings only; no process exists between the model and `Task`. Blocked. |
| M11 | Prompt prose telling the agent to export it | This *is* the agent discretion the issue names. Rejected by design. |
| **M12** | **Read a variable the harness already sets** | **Measured available, then REJECTED** — `lefthook` pre-commit blast radius + untestable fail-open. Moved to a follow-up. Superseded by binding the refusal to `tc_preamble`'s measured sibling count (Phase 3e), which needs no spawn-path cooperation at all. |

### Institutional learnings that change this plan

- `knowledge-base/project/learnings/2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md`
  — the exact defect class. Prescribes direct `printf >&2` + `exit 1`, and a meta-test that stubs
  `fail()` and asserts non-zero exit.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — the question every guard in this PR must answer: *"what is the cheapest edit that breaks the
  property this guard names, while leaving the guard GREEN?"* Drives the Guard Contract below.
- `knowledge-base/project/learnings/2026-08-14-every-defect-was-a-guard-that-could-not-fail-and-no-instrument-found-more-than-two.md`
  — **"run every suite under the environment it ships into — `CI=1`, `SOLEUR_SUBAGENT=1`,
  `TEST_GROUP=<shard>` — and treat any PASS-count change between environments as a finding."**
  Directly applicable: once Phase 3 lands, `CLAUDE_CODE_CHILD_SESSION` joins that list.
- `knowledge-base/project/learnings/2026-08-11-my-battery-reported-all-caught-and-eight-axes-were-untouched.md`
  — the #7441 post-mortem where an inherited `SOLEUR_SUBAGENT=1` made a sandbox exit before
  registration and **21 passes were the finding, not the 27 failures.** Any new refusal antecedent
  risks re-creating this: suites that shell out to `test-all.sh` must clear the *new* variable too.
- `knowledge-base/project/learnings/security-issues/2026-08-16-a-guard-asserting-absence-was-backwards-and-my-floors-counted-the-wrong-thing.md`
  — "Prefer a SET assertion over a COUNT for any all-members invariant. Slack in a floor is
  narrowing budget." Applied: the per-scope arm ratchets to **0**, not to a slack figure.

### Conventions and constraints carried from the codebase

- The canonical fixed shape is `scripts/marketplace-manifest-validate.test.sh`: floor at `:206-212`,
  conservation at `:220-230`, representative call site at `:84` (`ASSERTED=$((ASSERTED + 1))`
  *before* the assertion runs), final gate `[[ "$FAIL" -eq 0 ]]` at `:233`.
- **The conservation message must contain the literal `[FATAL] accounting`.** ARM 10 builds its
  population by grepping that exact string (`:628`). A differently-worded check is invisible to
  ARM 10b/10c/10d — this is issue **#7588**, and it is a live trap for every check this PR adds.
- Measured per-suite cost on three already-hardened siblings (commit `93e4effc2`):
  `net-issue-flow.test.sh` +115, `derive-app-domain-base.test.sh` +104/-4,
  `digest-oracle-guard.test.sh` +68/-2.
- Two suites dominate the size: `infra-config-apply.test.sh` (2520 lines, floor pinned at 251
  assertions) and `git-data-rung2-rehearsal.test.sh` (1490 lines, ~116 call sites). The realistic
  total is **~1200-1500 changed lines**, not the brief's ~700.

## Open Code-Review Overlap

One open `code-review` issue names a file this plan edits, out of 64 scanned:

- **#7098** — *"ci: audit the 56 `run:` bodies whose `set` omits -e against GitHub's inherited
  `bash -e`, then shape the lint"* — mentions
  `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`.
  **Disposition: Acknowledge.** #7098 is about `set -e` semantics in workflow `run:` bodies; this
  plan changes counter and floor structure inside the suite. The concerns do not intersect and
  folding #7098 in would import an audit of 56 unrelated call sites. The issue remains open.

Also acknowledged, not folded:

- **#7585** (no per-file promotion seam) — the per-scope arm in Phase 2 is adjacent but distinct:
  it verifies the deferred scope in place rather than building the promotion seam. **Acknowledge**;
  add a note to #7585 that the per-scope arm exists and narrows, but does not close, its scope.
- **#7588** (conservation population derived by message text) — **Acknowledge**, and comply: every
  conservation check added here uses the literal `[FATAL] accounting` wording so it is visible to
  the existing arms.
- **#7517** (bare `[[ "$FAIL" -eq 0 ]]` final gate) — **Acknowledge**, explicitly out of scope per
  the brief. Some suites in scope here also carry that shape; this plan does not change their final
  gate beyond what the floor/conservation contract requires.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — these are CI-side test suites and
a local test runner. The indirect artifact is the one that matters: a suite in this set that stays
vacuous can certify a real defect as green. `apps/web-platform/test/infra/vector-pii-scrub.test.sh`
guards PII scrubbing in the log pipeline and `infra-config-apply.test.sh` guards host config
application; a silently-vacuous run of either is how a defect in those surfaces reaches a user
wearing a green checkmark.

**If this leaks, the user's data is exposed via:** no new data path is created, read, or stored by
this change. The exposure vector is second-order and already present: an unnoticed vacuous
PII-scrub suite failing to catch a scrubbing regression in the vector log pipeline.

**Brand-survival threshold:** `aggregate pattern`. The harm accrues through a pattern of
undetected defects rather than a single user's incident, and no sensitive-path file (schema,
migration, auth flow, API route, `.sql`) is edited — only test suites, a shell runner, two skill
documents and guard scripts. No per-PR CPO sign-off is required at this threshold.

## Architecture Decision (ADR/C4)

### ADR

Two records, both in-scope tasks of this plan — not follow-ups.

1. **ADR-194 (provisional ordinal) — "A full-gate refusal binds to a condition the runner can
   MEASURE, not to one an agent must DECLARE."** New decision. It records: that no repo-controlled
   spawn path exists (the M1-M11 enumeration), so `SOLEUR_SUBAGENT`'s antecedent has never held and
   the refusal has never fired; that the repair is therefore **not** to find a variable to read
   (M12 — `CLAUDE_CODE_CHILD_SESSION`/`AI_AGENT` were measured present in spawned agents, and are
   recorded in the rejected-alternatives table with the reason), but to bind the refusal to
   `tc_preamble`'s already-measured sibling count; that `SOLEUR_SUBAGENT` is *retained* unchanged as
   the portable manual override and the Grok path, so the change is additive; and — load-bearing —
   **why the measured condition beats the injected one**: it is observable from inside the process,
   so it needs no spawn-path cooperation, has no fail-open mode when a vendor changes an
   undocumented variable, and is testable in CI by starting a real sibling. The rejected M12 branch
   is recorded with its two disqualifying findings: the `lefthook` pre-commit blast radius, and the
   structurally untestable fail-open mode.
   The ordinal is **provisional**: 194 was verified free across all 61 `origin/*` refs on
   2026-08-19, but `/ship`'s ordinal-collision gate must re-derive it immediately before merge, and
   any renumber must sweep this plan, `tasks.md`, and every AC that names the ordinal.

2. **An amendment to ADR-193** adding a `## Consequences` bullet for the per-scope deferred arm:
   ADR-193 says the deferred corpus is "deferred and counted, not forgotten", and this work makes
   the deferred corpus *mutation-classified* rather than merely counted. The amendment records that
   the deferred scope now carries its own shrink-only NO_FIRE ratchet, independent of the global
   `MAX_CONSTRUCTION_FAILURES`.

### C4 views

**No C4 impact**, and here is the enumeration that conclusion rests on. All three model files were
read in full (`model.c4` 691 lines, `views.c4` 74, `spec.c4` 54), not keyword-grepped:

- **(a) External human actors** — `founder`, `betaContact` ("Beta Tester / Prospect"), and the
  untrusted `contributor`. This change adds no correspondent, reviewer, or recipient, and alters no
  actor's description. The `contributor` description covers PR-head execution boundaries; nothing
  here changes which boundary a PR head executes under.
- **(b) External systems / vendors** — `anthropic`, `github`, `soleurMarketplace`, `cloudflare`.
  No inbound webhook, outbound API, or third-party store is added, removed, or re-pointed.
- **(c) Containers / data stores touched** — none. The change edits test suites, a local shell
  runner (`scripts/test-all.sh`), guard scripts and two markdown skill files. `hooks`
  ("Hook Engine") and `claude` ("Agent Runtime") are modeled, but neither gains or loses a
  responsibility: this work *reads* an environment variable the runtime already injects and adds no
  hook.
- **(d) Actor↔surface access relationships** — unchanged. No ownership, tenancy, or sharing edge
  moves.

The CI test harness is not a modeled element in any of the three files, and this change does not
introduce one — a per-scope ratchet inside an existing guard script is below Component granularity.
No element description is falsified by the change, so no `.c4` edit and no `views.c4 include` line
is required, and the C4 validation suites (`c4-code-syntax.test.ts`, `c4-render.test.ts`) are
untouched.

## Guard Contract

The deliverable of this plan **is** guards, so the mutation matrices below were derived from the
design, before the code. Each row is an edit that MUST drive the named guard RED.

### Guard 1 — the per-scope deferred NO_FIRE arm (`scripts/guard-vacuity-floor.test.sh`)

**Property.** *Every floor-bearing suite in the declared deferred directories exits non-zero when
its assertion machinery is neutered.* Not "the deferred set is counted" — counted is what it
already is, and counting is what failed to notice eleven vacuous floors.

**Assembly.** Structural, not a member list. The chokepoint is the existing `classify_suite`
function applied to the `$DEFERRED` file produced at `:209` by the `DEFERRED_DIRS` regex — the
same derivation that already produces `n_deferred`. There is exactly one such chokepoint, and the
arm must consume `$DEFERRED` itself rather than a copy: a second list would be the snapshot that
drifts. `DEFERRED_DIRS` currently names five directory prefixes; the arm quantifies over whatever
that regex yields, never over five.

**Mutation matrix.**

| # | Mutation | Must drive RED because |
|---|---|---|
| 1 | Revert any one hardened suite's floor to call its own `fail`/`bad` helper | That suite reclassifies NO_FIRE; the ratchet at 0 is exceeded. This is the regression the arm exists to catch. |
| 2 | Add a **second** newly-vacuous floor-bearing suite in a deferred directory, after suite 1 is already compliant | Catches an arm that stops at the first member. A check that reports the first offender and returns cannot see the second. |
| 3 | Neuter the arm's **own dispatch** — make the classification loop read an empty list (e.g. point it at a temp file that is never populated) | The arm would report `0 NO_FIRE` and pass while classifying nothing. Guarded by a companion floor asserting the deferred population classified is `>= n_deferred`, itself reported directly. |
| 4 | Delete the `printf >&2` + `exit 1` from a hardened suite's conservation check, leaving the comparison | Conservation stops being enforced; the structural check over the deferred scope must redden. |
| 5 | Move a hardened suite's `cases` increment from the call site into `pass()` | Re-creates the tautology ADR-193 §2 names. The structural in-helper check over the deferred scope must redden. |
| 6 | Change a hardened suite's conservation message so it no longer contains `[FATAL] accounting` | The suite silently leaves the conservation population (#7588). The arm must notice a suite that has a conservation check the population cannot see. |

**Harness rows** — edits to the *suite* (the guard file itself), not to the subjects:

| # | Harness edit | Expected |
|---|---|---|
| H1 | Set the per-scope ratchet to a slack value (e.g. 5) while 0 suites are NO_FIRE | Must be rejected by review as narrowing budget; the arm's own negative control asserts the ratchet is 0. |
| H2 | Remove the `cases=$((cases + 1))` accompanying the new arm | The guard's own conservation identity (`passes + fails == cases`) must redden — the guard is itself a suite under ADR-193's contract. |
| **H3 (must-PASS, non-canonical)** | Introduce a deferred suite that satisfies the contract using **third naming** (`tally`/`good`/`bad_n`, mirroring the existing ARM 9 fixture) | Must stay GREEN. Proves the arm accepts a compliant shape it did not author, rather than rejecting everything. |
| **H4 (must-PASS, non-canonical)** | A deferred suite whose floor legitimately reads a threshold bound on a preceding line | Must stay GREEN — the backward slice-widening ADR-193 describes must still apply in the deferred scope. |

### Guard 2 — the full-gate refusal antecedent (`scripts/test-all.sh`)

**Property.** *A full-gate run started while another full-gate run is already in flight is refused
before any suite runs, and before the advisory lock is taken.* The "without volunteering" clause
still holds and is still the whole point — but it is now satisfied by a condition the runner
**measures** (`sib_count`) rather than one an agent must **declare** (`SOLEUR_SUBAGENT`). That is
the substantive difference between this design and the one review killed: the antecedent is
observable from inside the process, so no spawn-path cooperation is needed and there is no
fail-open mode when a harness changes.

**Assembly.** Two reads, not one: the pre-existing `if [[ "${SOLEUR_SUBAGENT:-}" == "1" && … ]]` in `scripts/test-all.sh` (plan-time `:271`)
(`SOLEUR_SUBAGENT`, **unchanged**) and the new sibling refusal in the `tc_preamble`→`tc_acquire`
window at `:681-688`. The consumers of exit 4 are the four call sites enumerated in Research
Insights; all block on non-zero, so adding a second producer of exit 4 does not change their
contract. The arm quantifies over the *set of conditions that refuse a full-gate run*, which after
this change is `{SOLEUR_SUBAGENT set, sibling run detected}` — the arms must cover **both**
members, and must prove the second is additive rather than a replacement for the first.

**Mutation matrix.**

| # | Mutation | Must drive RED because |
|---|---|---|
| 1 | Delete the sibling refusal entirely | Restores today's queue-instead-of-refuse behaviour. The new CI sibling arm (T7) must fail. |
| 2 | Remove the `SOLEUR_SUBAGENT` refusal at `:271`, leaving only the sibling refusal | Drops the portable/Grok/manual path. The pre-existing arms 1-3 must fail — proving the change is **additive, not a swap**. |
| 3 | Invert the escape hatch so `SOLEUR_ALLOW_FULL_GATE=1` no longer overrides the sibling refusal | The hatch arm (T9) must fail; a guard with no sanctioned override is a guard the lead cannot use. |
| 4 | Change the refusal message so it no longer names the sibling count or worktrees | A refusal that will not say what tripped it turns a false positive into a mystery. Must redden. |
| 5 | Move the refusal to **after** `tc_acquire` | The refused run now waits up to `TC_LOCK_TIMEOUT` (900 s) to be told it should not have started, and takes the lock a legitimate sibling is queued on. T12 asserts no lock line precedes the refusal; must redden. |
| 6 | Make `tc_preamble` always export `TC_SIBLING_RUN_COUNT=0` | The measurement is neutered while the refusal still "exists" — the exact vacuity class this whole PR is about. T7 must fail. |

**Harness rows:**

| # | Harness edit | Expected |
|---|---|---|
| H1 | Delete the `env SOLEUR_SUBAGENT=` clearing from `run_arm` | Arms inherit an ambient `SOLEUR_SUBAGENT` and pass vacuously — the #7441 class. A control arm asserting the *normal* path reaches registration must redden. |
| **H2 (must-PASS)** | Run the normal arm with `SOLEUR_ALLOW_FULL_GATE=1` and a sibling present | Must stay GREEN and reach registration — the lead's sanctioned run is not collateral. |
| **H3 (must-PASS)** | Run with no sibling and no hatch | Must stay GREEN. A refusal that fires on the solo path would break every ordinary local run, and is the highest-cost false positive available here. |

### Guard 3 — the eleven hardened suites' own floors and conservation checks

**Property.** Per ADR-193: *a suite whose verdict helpers are neutered, or whose verdicts are
discarded, exits non-zero.*

**Assembly.** Each suite's own floor block and conservation block, plus every assertion call site
in that suite (the call-site increment is what makes conservation non-tautological). The assembly
is "every call site", enumerated per suite in Phase 1 by grepping the suite's verdict-helper
invocations — not by trusting the floor's pinned threshold, which is a count and can drift from
the real site set.

**Mutation matrix.**

| # | Mutation | Must drive RED because |
|---|---|---|
| 1 | Stub the suite's `fail`/`bad` to a no-op | Rows go quiet; conservation catches the discarded verdicts (`passes + fails < cases`) and exits 1 directly. |
| 2 | Delete a block of assertions so fewer than the floor run | The floor catches it and exits 1 directly, without routing through any helper. |
| 3 | Add a call site with a verdict but no `cases` increment | Conservation catches the other direction (`passes + fails > cases`) and says "harness bug", not "product failure". |
| 4 | Wrap a `cases` increment inside `$( )` | The subshell discards it; conservation reddens. ADR-193 §2 names this explicitly. |

**Harness rows:**

| # | Harness edit | Expected |
|---|---|---|
| H1 | Neuter *every* helper at once (the guard's `command_not_found_handle` mutant) | The floor must still exit non-zero — this is exactly the guard's classification and is what moves the suite from NO_FIRE to FIRES. |
| **H2 (must-PASS)** | Run the suite unmodified | Must stay GREEN with `passes + fails == cases` holding exactly. A contract that only reddens is not a contract. |

## Observability

The affected surface is CI and the operator's local shell. No runtime service, sandbox, container
readiness gate, or cron worker is touched, so §2.9.2's blind-surface extension does not apply.

```yaml
liveness_signal:
  what: "scripts/guard-vacuity-floor.test.sh reports the derived population and the per-scope
         deferred NO_FIRE count on every run"
  cadence: "every PR, via the CI-required `test` context; and on every local `bash scripts/test-all.sh`"
  alert_target: "the PR's required check — a regression blocks merge"
  configured_in: ".github/workflows/ci.yml (scripts shard)"

error_reporting:
  destination: "non-zero exit + stderr naming every offending file by path"
  fail_loud: true   # the arm names each NO_FIRE suite; it never reports a bare count

failure_modes:
  - mode: "a hardened suite regresses to a fail()-routed floor"
    detection: "per-scope deferred arm reclassifies it NO_FIRE; ratchet of 0 exceeded"
    alert_route: "CI `test` context fails, naming the file"
  - mode: "a new vacuous floor-bearing suite lands in a deferred directory"
    detection: "same arm — the population is derived by directory regex, so a new file is swept"
    alert_route: "CI `test` context fails, naming the file"
  - mode: "a conservation check is added with non-canonical wording and is silently unpoliced (#7588)"
    detection: "the per-scope arm asserts every hardened suite's conservation message carries the
                literal `[FATAL] accounting`"
    alert_route: "CI `test` context fails, naming the file"
  - mode: "sibling detection silently stops matching (a /proc scan change, a renamed script), so
           the refusal never fires and concurrent batteries resume unnoticed"
    detection: "MECHANICALLY detectable, unlike the M12 design this replaced: the CI sibling arm
                (T7) starts a real sibling process and asserts exit 4, so a detection regression
                reddens CI directly. This is the concrete gain from choosing the measured
                condition over the harness-injected one."
    alert_route: "CI `test` context fails on the fanout-suite-scope sibling arm"
  - mode: "false-positive sibling detection refuses a legitimate solo run"
    detection: "T10/H3 assert the solo path reaches registration; the refusal message names the
                offending worktrees, so a false positive is self-diagnosing"
    alert_route: "CI `test` context, plus the refusal's own stderr naming what it saw"

logs:
  where: "CI job output for the `test` context; local stdout/stderr"
  retention: "GitHub Actions default log retention"

discoverability_test:
  command: "bash scripts/guard-vacuity-floor.test.sh"
  expected_output: "'floor does NOT fire     : 0' in the derived-population block, a passing
                    per-scope deferred arm, and a final 'Total: N passed, 0 failed' with RC=0"
```

## Implementation Phases

### Phase 0 — Measurement before assumption (blocking)

**0.1 — Superseded. There is no probe gate, because Phase 3 no longer branches on one.**

An earlier draft made the whole #7553 repair rest on a lead-session reading of
`CLAUDE_CODE_CHILD_SESSION`, with a three-way branch. Review killed that design on two independent
grounds, both since verified (see the Reconciliation rows and Risks):

1. **A single-session reading cannot establish a discriminator at all.** A discriminator is a
   *difference between two sessions*; reading one value from one session is not that. Worse, the
   plan had no way for the executing agent to know which kind of session it was in — and an
   implementing agent is itself a spawned agent, so it would read `1`, fall through to the
   fallback, find `AI_AGENT` also set, and land on "neither discriminates" **deterministically**,
   producing an output indistinguishable from a real measurement.
2. **Widening the antecedent has a workflow-breaking blast radius that the earlier draft missed
   entirely.** See Phase 3.

If the identity mechanism is ever revisited (it is now a follow-up, not this PR), the probe must be
**paired** — one reading from a lead session and one from a spawned agent, branching on the *delta*
— and it must be accompanied by the escape-hatch design Phase 3 describes. The measurements already
taken during planning stand as the spawned-side half:
`CLAUDE_CODE_CHILD_SESSION=1`, `AI_AGENT=claude-code_2-1-228_agent`, `SOLEUR_SUBAGENT=UNSET`,
observed independently from two spawned agents.

**0.2 — Re-derive the NO_FIRE population.** Do not work from this plan's list of eleven; it is a
2026-08-19 snapshot and the brief's own eight-suite snapshot went stale in three days. Copy
`scripts/guard-vacuity-floor.test.sh` to a scratch path, repoint `COVERED_DIRS` at the full
`DEFERRED_DIRS` prefix set, pin `REPO_ROOT` (the guard derives it from `BASH_SOURCE`, so a copy
outside the repo dies with `fatal: not a git repository`), and run it. The named NO_FIRE list is
the work list. Reconcile any delta against this plan in the PR body.

**0.3 — Runtime budget. Already measured at plan time; re-confirm only if the population moved
materially.**

```
/usr/bin/time -f "%e" bash scripts/guard-vacuity-floor.test.sh   -> COVERED_SCOPE_SECONDS=29.39  (57 suites)
/usr/bin/time -f "%e" bash <scratch copy over DEFERRED_DIRS>     -> DEFERRED_SCOPE_SECONDS=24.39  (45 suites)
```

The per-scope arm therefore costs **~24s on top of ~29s, for ~54s total**. That is not a budget
concern for the `scripts` CI shard, and it removes the constraint that would otherwise have forced
a single-pass design. Implement the arm in whichever shape is clearest — a second walk over
`$DEFERRED` is affordable.

**0.4 — Confirm the reference shape.** Read `scripts/marketplace-manifest-validate.test.sh:84`,
`:206-212`, `:220-230`, `:233`. Every hardened suite mirrors this, including the literal
`[FATAL] accounting` token.

### Phase 1 — Harden the derived NO_FIRE suites (#7580)

Per suite, in ascending order of size so the pattern is established on cheap files first:
`emit-review-trailer` (185) → `rule-incident-marker-capture` (182) → `infra-config-handler-bootstrap`
(284) → `git-data-template-strip` (309) → `ship-net-issue-flow-gate` (308) →
`git-data-render-strip-parity` (363) → `boundary` (579) → `vector-pii-scrub` (610) →
`web-host-provisioner-parity-mutation` (1041) → `git-data-rung2-rehearsal` (1490) →
`infra-config-apply` (2520).

For each:

1. **Enumerate the call sites by grep**, not by trusting the floor's pinned threshold. Suites use
   different helper vocabularies (`pass`/`fail`, `ok`/`no`, `ok`/`bad`, and `infra-config-apply`
   and `vector-pii-scrub` use neither) — derive the vocabulary per file before counting.
2. **Introduce an independent case counter** incremented at each call site, immediately *before*
   the assertion runs. Never inside a helper. Never inside `$( )`.
3. **Strip counter increments out of the verdict helpers** so they touch only verdict counters.
4. **Rewrite every floor** to report with `printf >&2` + `exit 1` directly. Note
   `web-host-provisioner-parity-mutation.test.sh` carries **three** floors (`FLOOR=44`,
   `PROBE_FLOOR=7`, `PROBE_RED_FLOOR=6`) — all three route through `ok`/`no` today and all three
   must be converted. `infra-config-apply.test.sh`'s floor reads `PASS + SKIPPED_ASSERTIONS`
   against `APPLY_MIN_ASSERTIONS=251`; preserve the declared-skip accounting rather than flattening
   it.
5. **Add the conservation check**, reported directly, **ordered before the floor** (ADR-193 §4), and
   carrying the literal `[FATAL] accounting` string, with both diagnostic directions named.
6. **Verify per suite**: run it unmodified (must be green, conservation exact); then run the
   guard's mutant classification against it (must be FIRES).

**Every one of the eleven has verdict helpers. Do not introduce a helper pair anywhere.** An earlier
draft of this plan claimed three suites had none, on the strength of a
`^(pass|fail|ok|no|bad)\(\)` grep. That grep was too narrow and the claim is measurably false —
which is precisely the mistake step 1 above exists to prevent, committed by the plan itself:

| Suite | Helper | Note |
|---|---|---|
| `infra-config-apply.test.sh:114` | `assert_eq()` (+ `assert_file_exists`, `assert_file_mode`) | ~151 `PASS=$((`/`FAIL=$((` sites |
| `vector-pii-scrub.test.sh:97` | `run_fixture()` | `PASS`/`FAIL`/`FAILS` counters at `:93-95` |
| `infra-config-handler-bootstrap.test.sh:36` | `assert()` | **already carries `TOTAL=$((TOTAL + 1))` inside the helper body** — the clearest ADR-193 §2 tautology in the eleven |

These are ordinary conversions at non-`pass`/`fail` names, not higher-risk ones, and they need no
extra commit ceremony. `infra-config-handler-bootstrap.test.sh` is 284 lines with the counter
already present in the wrong place — **do it first**, as the worked example for the other ten.

The general lesson, which ARM 10c's own comment already records: a literal helper-name alternation
silently exempts suites that name their counter something else. Derive the vocabulary per file.

**Most of the work is one repeated shape, so template it before starting.** At least four suites
carry an identical `_ran` derived-total pattern — `pass()`/`fail()` each increment their own verdict
counter, then the floor compares a *derived* `_ran` (i.e. `passes + fails`) against a literal:

```bash
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1));  printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
...
if [[ "$_ran" -lt 15 ]]; then      # git-data-render-strip-parity.test.sh:355
if [[ "$_ran" -lt 5  ]]; then      # git-data-template-strip.test.sh:300
if [[ "$_ran" -lt 12 ]]; then      # emit-review-trailer.test.sh:177
if [[ "$_ran" -lt 71 ]]; then      # git-data-rung2-rehearsal.test.sh:1482
```

A total derived from the verdicts is the tautology ADR-193 §3 names in its sharpest form: `_ran`
moves *with* the verdict, so stubbing `fail` drops the row and its count together and the floor is
satisfied under the exact fault it exists to catch. The conversion is mechanical and identical
across all four — replace the derived `_ran` with an independently-incremented call-site counter,
then the floor compares against *that*. Do one of these first, in full, and reuse it; the remaining
three are near-copies. `git-data-rung2-rehearsal.test.sh` is the same shape at ~116 call sites, so
it is the same edit repeated, not a harder edit.

### Phase 2 — Make the fix visible (the per-scope arm)

**This phase is the reason the work is verifiable at all**, and it is ordered *after* Phase 1's
first suite only so there is something for it to classify; the RED demonstration comes first.

**Three edits, not six.** An earlier draft specified four new arms; review established that one arm
plus a one-line population change reaches a strictly stronger state.

1. **One classification pass, unconditionally.** Change the loop at `:360-367` to walk `$COVERED`
   **and** `$DEFERRED` once, tagging each result with its scope. A single scope-tagged loop is less
   code than two loops regardless of runtime, so the Phase 0.3 timing measurement is recorded as a
   number and does **not** gate a design fork.
2. **One new arm** asserting, for the deferred scope, both:
   - `n_nofire_deferred == 0` (the property), and
   - the **exact bucket identity** `fires + nofire + construct == n_deferred`.

   The identity replaces the `>=` companion floor an earlier draft proposed. `classify_suite`
   returns exactly one of three verdicts for every input (`:339-355`), so the identity is legal —
   and it is strictly stronger than a floor: it catches an arm that classifies an *empty* list
   (mutation row 3) **and** one that double-counts, which `>=` cannot. It also honours the plan's
   own cited learning: prefer a set/identity assertion over a count with slack.

   Alongside it, **one** new constant — `MAX_DEFERRED_CONSTRUCTION = 16`, shrink-only. Its comment
   must state the reason it exists, or the next reader will simply raise it: **it closes a live
   escape path in this very PR.** A floor rewrite can move a suite from NO_FIRE into CONSTRUCTION
   rather than into FIRES, which would drive the NO_FIRE count to 0 while the property still fails.
   `MAX_CONSTRUCTION_FAILURES` (`:398`) cannot catch that — it is global and derived from
   `$COVERED`. Do **not** also add a `MIN_DEFERRED_FIRING`: with the exact identity plus these two
   ratchets, FIRES is already determined, and a redundant ratchet is one that gets "fixed" upward.
3. **One line for conservation, plus the comment rewrite.** The ARM 10b/10c/10d checks already
   exist and are correct (`:642-731`); all three iterate `< "$CONSERVING"`. The only thing missing
   is the population. Change `:629` so `CONSERVING` is built from `$COVERED` **and** `$DEFERRED`
   — the arms then extend for free. **Do not duplicate the arms**; 10d's brace-depth `awk` is the
   most delicate code in the guard and a parallel copy would drift. This is verified zero-risk on
   arrival: **no file in any deferred directory currently contains the literal `[FATAL] accounting`**
   (measured: 0), so `CONSERVING` is byte-identical today and grows only as Phase 1 lands.

   In the same edit, rewrite the ARM 5c comment block at `:450-482`: fix the stale `17`s at
   `:462-463` and `:473` to `15`, and replace the now-falsified claim that "the per-scope
   construction ratchet does not exist yet" — this PR is what makes it exist. Fixing the number
   without rewriting the claim leaves an accurate figure inside a stale argument.

**Leave `COVERED_DIRS`, `MAX_DEFERRED` and `MIN_FIRING_SUITES` untouched** (subject to UC-3 below).
**`MIN_CONSERVING` (`:633`) is the exception and must be RAISED** to its post-Phase-1 measured
value — widening `CONSERVING` to the deferred scope makes an 18 that was accurate stale-low by
eleven, and a shrink-only ratchet left un-raised silently fails to capture the gain.

**Ordering note (RED before GREEN) — and the red state never reaches `main`.** Commit the arm with
the ratchet at 0 *before* the bulk of Phase 1, observe it fail naming exactly the derived NO_FIRE
set, and **paste that failing output into the PR body as the RED evidence**. Then let each Phase 1
suite drive the count down. That sequence is what proves the arm discriminates; an arm introduced
at a ratchet of 11 passes on arrival and proves nothing.

The red state is a *within-branch* intermediate commit only. The PR does not go ready, and
therefore cannot merge, until the arm is green — so no unrelated PR is ever blocked by a
deliberately-failing required check on `main`. **If the campaign is split** (see the size risk),
the merged ratchet is set to the *achieved* count, never left at 0, and the RED evidence for the
remaining suites still ships in the PR body. Leaving a merged ratchet at 0 with suites outstanding
would create exactly the pressure to loosen the arm that the ratchet exists to resist.

**Upgrade trigger, recorded so the weaker arm does not fossilize.** This arm classifies the
deferred scope in place; it is not the same as promoting those directories into `COVERED_DIRS`.
The blocker is arithmetic and specific: the deferred scope carries **16** mutant-construction
failures against a **global** cap of **15** with zero headroom. File that headroom figure on
**#7585** as the explicit precondition for promotion, so a future reader can tell "covered" from
"classified by a sibling arm" and knows exactly what has to change first.

### Phase 3 — Tell the truth about the refusal, and ship a reachable one (#7553)

**The `SOLEUR_SUBAGENT` antecedent is NOT widened in this PR** — but #7553 does not close on prose
alone: **3e** below adds a mechanically-reachable refusal built on the sibling detection that
already exists, which is the operator's selected scope. The brief's step 1 ("set
`SOLEUR_SUBAGENT=1` on the agent-spawn path") is measured impossible — M1 through M11 are all blocked, and there is no
repo-controlled spawn path to set anything on. The brief's own step 2 is the sanctioned fallback,
and this phase executes it. Two findings, both verified, moved M12 from "the clever answer" to "a
follow-up that needs its own design":

- **Widening the antecedent would block every spawned agent's commits.** `lefthook.yml:234-237`
  registers a `bun-test` **pre-commit** hook, `glob: "*.{ts,tsx,js,jsx}"`, `run: bash
  scripts/test-all.sh`. A spawned agent committing a `.ts` file is the ordinary shape of the work
  and review fan-outs. Under a widened antecedent every one of those commits exits 4 and is
  refused. `plugins/soleur/scripts/grok-pre-push-gate.sh:123` has the same shape on pre-push. The
  earlier draft asked "is this invoker a spawn path?" — the correct question is **"is this invoker
  reachable from inside a spawned agent?"**, and for both git hooks the answer is yes and routine.
  Shipping M12 therefore requires an escape-hatch design (a hook-level `SOLEUR_ALLOW_FULL_GATE=1`,
  or a lefthook exemption) that is out of scope here.
- **The harm M12 targets is already mitigated.** `scripts/test-all.sh` (plan-time `:688`) calls
  `tc_acquire "test-all"`, an `flock` advisory lock (ADR-133), and `:681` calls `tc_preamble`,
  which detects and names sibling runs. Concurrent local full-gate runs already serialise, so the
  "corrupted timing measurement" justification no longer stands on its own.

**3a — Correct the false claims, across every file that carries them.** The earlier draft scoped
this to two sentences in two files; review found the same claim in at least five files and two
ADRs. Verified inventory:

| Location | Current text | Why it changes |
|---|---|---|
| `review/SKILL.md:159`, `work/SKILL.md:292` | "are spawned with `SOLEUR_SUBAGENT=1` in their environment" | Measured false from two spawned agents. |
| `review/SKILL.md` + `work/SKILL.md` — the sentence beginning *"…exits 4 when…"* in each (plan-time `:164` / `:298`) | test-all.sh "enforces this mechanically (it exits 4 when `SOLEUR_SUBAGENT=1`)" | True of the code, vacuous in practice — the antecedent never holds. |
| `work/SKILL.md` — the *"The lead runs this gate, not a delegate"* paragraph (plan-time `:805`) | "exits 4 … when `SOLEUR_SUBAGENT=1` is set" | Same vacuity; already in Files-to-Edit but had no phase step. |
| `ship/SKILL.md:345` | "ship reached from a spawned agent … **inherits exactly that variable**" | Directly false, and it is the one most likely to drive a wrong ship-time decision. |
| `one-shot/SKILL.md:68` | "rc 4 = REFUSED … because `SOLEUR_SUBAGENT=1` is set — you are a spawned agent" | Same falsehood, different wording — survives any `'are spawned with'` grep. |

Replace each with what is actually true: **`SOLEUR_SUBAGENT` is a convention a lead may export, not
something the harness sets; the mechanical protection against concurrent full-gate runs is
`tc_acquire`'s advisory lock (ADR-133).** Keep `rc=4`'s meaning documented — the exit path is real
and reachable by anyone who exports the variable deliberately.

**3b — Reconcile the prose-presence assertion.** `fanout-suite-scope.test.sh:174-182` greps the
skill files for `SOLEUR_SUBAGENT=1` and passes with the message *"$rel tells the lead to export
SOLEUR_SUBAGENT=1"* — describing an instruction the matched prose does not contain. Rewrite it to
assert the true contract. Correcting 3a's sentences breaks this grep; that is the correct outcome
and must land in the same commit.

**3c — Correct the two ADRs the change touches.** `ADR-177:217` states "cannot reach it because
the gate does not set `SOLEUR_SUBAGENT`" and `ADR-181:105` describes the same antecedent. Both stay
*true* under this phase (nothing is widened), so this is a citation/consistency pass, not a
correction — confirm and leave them, and note in ADR-194 that they were checked.

**3d — Leave the environment-litmus lists alone.** `review/SKILL.md:1282` and `:1348` tell a
reviewer to run suites under `SOLEUR_SUBAGENT=1` and `CI=1` and treat a PASS-count delta as a
finding. That advice remains correct and complete under this phase. It would have needed the new
variable added under M12 — noted here so the follow-up does not miss it.

**No hermeticity sweep is needed in this PR.** The three suites that clear `SOLEUR_SUBAGENT`
(`fanout-suite-scope.test.sh:85`, `test-all-infra-coverage-notice.test.sh:171,463`,
`test-all-killed-classification.test.sh:302,305`) keep working unchanged, because no new ambient
variable is introduced. That sweep — the earlier draft's self-declared highest-risk step — moves to
the follow-up along with M12.

**3e — Make the lock refuse rather than queue when it detects a sibling. (OPERATOR-SELECTED, in
scope for this PR.)**

Recorded as UC-1 in `decision-challenges.md` and put to the operator on 2026-08-19; they chose
"docs + make the lock refuse" over docs-only and over full M12. This phase is therefore **in scope**
and is the mechanical half of #7553 — without it, #7553 would close having changed only prose.

`tc_preamble` already measures the exact condition (`sib_count`, DISTINCT worktrees running
`test-all.sh`) and already emits `SIBLING_RUN_DETECTED`. Today it warns and `tc_acquire` then
queues behind the `flock`. This phase turns that measured condition into a refusal, delivering
#7553's stated intent — *a full-gate run that should not have started is stopped* — with **no**
dependency on undocumented harness internals and **no** fail-open mode.

1. **Export the measurement, keep the policy at the call site.** `tc_preamble` currently holds
   `sib_count` in a `local`. Export it as `TC_SIBLING_RUN_COUNT`. Do **not** put the refusal inside
   `tc_preamble`: it is a reporter, its banners are documented as advisory, and burying policy in a
   measurement function is what makes the next reader trust a stale comment. The refusal belongs in
   `test-all.sh` where the `SOLEUR_SUBAGENT` refusal already lives, so both policies are visible
   together.

2. **Place the refusal in the `tc_preamble`→`tc_acquire` window** — between the bare `tc_preamble` call and `tc_acquire "test-all"` in `scripts/test-all.sh` (plan-time `:681-688`).
   This ordering is load-bearing and is the same reasoning the existing refusal block states at
   `:269`: it must fire *after* the count exists but *before* `tc_acquire`, so a refused run never
   takes the advisory lock a legitimate sibling is queued on. Refusing after `tc_acquire` would make
   the refused run wait up to `TC_LOCK_TIMEOUT` (900 s) to be told it should not have started.

3. **Reuse `SOLEUR_ALLOW_FULL_GATE=1` as the hatch** — same variable, same semantics, so there is
   one override to learn rather than two. Exit **4**, the existing REFUSED code, whose four
   consumers all block on non-zero.

4. **Rewrite the falsified comment.** `test-contention.sh`'s banner block says "Named banners. All
   are advisory: nothing here changes the run's outcome." That stops being true. Rewrite it in the
   same commit — an accurate figure inside a stale argument is the failure mode this plan already
   fixed once at ARM 5c.

5. **Settle the `lefthook` blast radius with a measurement, not an assumption (AC11a).**
   `lefthook.yml:234-237` runs `bash scripts/test-all.sh` on every `*.{ts,tsx,js,jsx}` pre-commit.
   Under this phase a commit during any sibling run is refused. This is M12's blast radius in
   narrowed form — it fires only under genuine concurrency — but it is *not* zero, and it is the
   exact class of second-order breakage that killed M12. Preferred fix: set
   `SOLEUR_ALLOW_FULL_GATE=1` on the `bun-test` job, since a pre-commit gate is a sanctioned
   invocation, not an opportunistic battery. Demonstrate the chosen fix; do not assert it.

6. **Prove it in CI.** This is the arm M12 could never have: it needs no spawned agent, so CI can
   run it. Start a real sibling `test-all.sh` (a stub that sleeps, matching what `_tc_scan_procs`
   greps for), assert the second invocation exits 4 and names the sibling, then assert the hatch
   path reaches registration. T7/T9/T10/T11/T12 in Test Scenarios.

**Follow-up issue to file in Phase 4** (the honest remainder of #7553 — filing it is what makes
closing the issue legitimate rather than a paper close):

1. **Harness-identity detection (M12), if still wanted after 3e.** Must carry: a *paired*
   lead-vs-spawned probe, the lefthook/pre-push escape-hatch design, the hermeticity sweep, and the
   `review/SKILL.md:1282/1348` litmus update. Record that `CLAUDE_CODE_CHILD_SESSION` is
   undocumented harness-internal state with a structurally untestable fail-open mode. Note that 3e
   already covers the concurrency harm, so M12's remaining value is only the *non-concurrent* case
   (a lone subagent running a battery with no sibling present) — weigh that before building it.

### Phase 4 — Records

Write ADR-194 (re-verify the ordinal against freshly-fetched `origin/main` first), amend ADR-193's
Consequences, and post the acknowledgement notes on #7585 and #7588.

### Phase 5 — Full battery and ship

Run `bash scripts/test-all.sh` (as the lead, with the hatch if required). Per the learnings above,
also run the touched suites under the environment they ship into and treat any PASS-count delta
between environments as a finding, not noise.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/guard-vacuity-floor.test.sh` exits 0 and its derived-population block reports
   `floor does NOT fire : 0`.
2. The new per-scope deferred arm reports a deferred NO_FIRE count of **0** against a ratchet of
   **0**, and names its population size in the pass message.
3. Every suite in the Phase 0.2 derived list classifies **FIRES** under the guard's mutant
   construction. Verified by re-running the Phase 0.2 scratch probe and reading
   `floor does NOT fire : 0`.
4. Each hardened suite, run unmodified, exits 0 with `passes + fails == cases` holding exactly.
5. `grep -c '\[FATAL\] accounting' <suite>` returns `>= 1` for every hardened suite (the #7588
   visibility requirement).
6. `grep -n 'MAX_CONSTRUCTION_FAILURES=' scripts/guard-vacuity-floor.test.sh` still reports `15`,
   and `grep -n 'MAX_DEFERRED=' …` still reports `47` — neither ratchet was raised, and
   `COVERED_DIRS` is byte-identical to its pre-PR value.
7. No occurrence of `17` remains in the `MAX_CONSTRUCTION_FAILURES` explanatory comments.
8. The `SOLEUR_SUBAGENT` refusal antecedent — the `if [[ "${SOLEUR_SUBAGENT:-}" == "1" && … ]]` line in `scripts/test-all.sh` (plan-time `:271`) — is **byte-identical** to its pre-PR form —
   `SOLEUR_SUBAGENT` is not widened, no harness-internal variable is read. (Phase 0.1 is
   superseded; there is no probe and no probe output to record.)
9. `scripts/test-all.sh` refuses (exit 4) when `tc_preamble` measured `sib_count > 0` and
   `SOLEUR_ALLOW_FULL_GATE=1` is absent, proven by a CI-runnable arm that starts a real sibling
   process — **and** the pre-existing `SOLEUR_SUBAGENT` arms 1-3 still pass, proving the change is
   additive rather than a swap.
10. `scripts/test-all.sh` runs to registration when a sibling is present **and**
    `SOLEUR_ALLOW_FULL_GATE=1` is set (the lead's sanctioned run is not collateral), and also when
    no sibling is present and no hatch is set (the ordinary path is untouched).
11. The sibling refusal fires in the window **after** `tc_preamble` and **before** `tc_acquire`, so
    a refused run never takes the advisory lock a legitimate sibling is queued on. Verified by
    asserting the refusal emits no `[contention] lock` acquisition line.
11a. `lefthook.yml`'s `bun-test` pre-commit hook does not become unrunnable during a concurrent
    sibling run — either it carries the hatch or the refusal is scoped so a pre-commit invocation
    is not collateral. This is the blast-radius check that killed M12; it applies here in narrowed
    form and must be demonstrated, not asserted.
12. `grep -c 'are spawned with' plugins/soleur/skills/{review,work}/SKILL.md` returns 0 — the false
    factual claim is gone from both files.
13. `plugins/soleur/test/fanout-suite-scope.test.sh` asserts the true contract; its pass message no
    longer says "tells the lead to export" unless the prose it matches actually says so.
14. `bash plugins/soleur/test/fanout-suite-scope.test.sh` exits 0.
15. `ADR-194-*.md` exists, its ordinal is free on freshly-fetched `origin/main`, and it names the
    fail-open failure mode and the re-measurement trigger. ADR-193 carries the per-scope amendment.
16. Full battery `bash scripts/test-all.sh` is green.
17. PR body carries `Closes #7580` and `Closes #7553`.

### Post-merge (operator)

None. Every step above is automatable in-session; no vendor dashboard, no credential mint, no
infrastructure apply. There is no human-gated action at all: the Phase 0.1 probe that would have
required one was superseded, and the sibling refusal is verifiable entirely from CI.

## Test Scenarios

Beyond the mutation matrices in the Guard Contract:

| # | Scenario | Expected |
|---|---|---|
| T1 | Hardened suite, unmodified | Green; `passes + fails == cases` exactly |
| T2 | Hardened suite with `fail()` stubbed to `:` | Non-zero exit; conservation names "a verdict was discarded" |
| T3 | Hardened suite with an assertion block deleted below the floor | Non-zero exit; floor fires directly, no helper involved |
| T4 | Hardened suite with a verdict added and no `cases` increment | Non-zero exit; conservation names "harness bug", not product failure |
| T5 | Guard run with one suite reverted | RED, naming that file |
| T6 | Guard run with two suites reverted | RED, naming **both** files |
| T7 | `test-all.sh` started while a real sibling `test-all.sh` runs, no hatch | Exit 4; message names the sibling count and the offending worktree(s) |
| T8 | `test-all.sh` with `SOLEUR_SUBAGENT=1`, no hatch | Exit 4 (unchanged behaviour — the pre-existing antecedent is untouched) |
| T9 | `test-all.sh` with a sibling present **and** `SOLEUR_ALLOW_FULL_GATE=1` | Runs to registration |
| T10 | `test-all.sh` with no sibling and no hatch | Runs to registration (the ordinary path) |
| T11 | Two `test-all.sh` processes started concurrently in CI | Exactly one reaches registration; the other exits 4. This is the arm M12 could never have — it needs no spawned agent, so CI can run it |
| T12 | The refused run's output | Contains no lock-acquisition line — it must refuse *before* `tc_acquire`, not after queueing |

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **The sibling refusal makes `lefthook`'s `bun-test` pre-commit hook fail whenever any sibling run is in flight** — a lead committing a `.ts` file during another worktree's battery is refused | High | This is M12's blast radius in narrowed form: it fires only under genuine concurrency, not on every spawned agent. AC11a requires it be **demonstrated** unbroken, not asserted. Mitigations in preference order: (a) `lefthook.yml` sets `SOLEUR_ALLOW_FULL_GATE=1` on the `bun-test` job, since a pre-commit gate is a sanctioned invocation; (b) scope the refusal to full-gate invocations only. Decide in Phase 3e with the measurement in hand. |
| **`tc_preamble`'s banners are documented as advisory** — "All are advisory: nothing here changes the run's outcome" (`test-contention.sh`, above the banner block). Making a measured condition load-bearing silently falsifies that comment and any reader relying on it | Medium | The comment is rewritten in the same commit, and the refusal is placed in `test-all.sh` (not inside `tc_preamble`) so the preamble stays a pure measurement function and the policy stays visible at the call site. `sib_count` is exported as `TC_SIBLING_RUN_COUNT` rather than the refusal being buried in the reporter. |
| **False-positive sibling detection refuses a legitimate solo run** — `_tc_scan_procs` misattributing a nested or wrapper process would exit 4 with nothing actually running | Medium | `tc_preamble` runs before the first suite specifically so own-suite children cannot self-match (`test-contention.sh:311`), and it counts DISTINCT worktrees rather than raw pids. T10 asserts the solo path still reaches registration; the refusal message lists the offending worktrees so a false positive is self-diagnosing rather than mysterious. |
| **Population drift**: the derived NO_FIRE set moves again between planning and implementation, exactly as it did between the brief and this plan | Medium | Phase 0.2 re-derives and reconciles. The per-scope arm is derivation-based, so a suite that lands after the plan is swept automatically. |
| **Size**: ~1200-1500 changed lines, dominated by two suites of 1490 and 2520 lines | Medium | Per-suite commits in ascending size order. The shrink-only ratchet makes partial delivery safe: it lands at whatever count is achieved and prevents backsliding, so the four largest suites can become a follow-up without losing the gains — **provided** the ratchet is set to the achieved number, never left at 0 while suites remain. |
| ~~Guard runtime roughly doubles and pushes the `scripts` CI shard past budget~~ | **Closed at plan time** | Measured: 29.39s covered + 24.39s deferred = ~54s total. Not a budget concern; no design constraint follows from it. |
| **Suites with no verdict helpers** need a helper pair introduced before the counter can be separated from the verdict — a larger structural change than the other conversions | Medium | Those three are called out in Phase 1 and get their own commits. |
| A new conservation check worded differently is invisible to ARM 10b/10c/10d (#7588) | Low | AC5 greps for the literal `[FATAL] accounting` in every hardened suite; mutation row 6 asserts the arm notices. |
| ADR-194 ordinal is claimed by a sibling PR mid-pipeline | Low | Ordinal treated as provisional; re-derived at ship; any renumber sweeps this plan, `tasks.md`, and AC15. |

## Domain Review

**Domains relevant:** none.

No cross-domain implications detected — this is an infrastructure/tooling change confined to CI
test suites, a local shell runner, two guard scripts and two skill documents. The Product/UX
mechanical UI-surface override did **not** fire: no path in `## Files to Edit` matches
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, and no user-facing surface is
created or modified. GDPR gate: skipped — no schema, migration, auth flow, API route or `.sql` file
is touched, and none of the four expanded triggers fire (no new LLM processing of operator data, no
`single-user incident` threshold, no new cron reading `learnings/` or `specs/`, no new artifact
distribution surface). IaC gate: skipped — no server, service, secret, vendor, DNS record, TLS
cert, firewall rule or persistent runtime process is introduced; the `apps/web-platform/infra/`
paths in scope are bash test suites, not Terraform. Encryption-posture gate: skipped — no
persistent store and no new cross-component connection.

## Files to Edit

- `scripts/guard-vacuity-floor.test.sh` — per-scope deferred arm, deferred construction ratchet,
  extended conservation structure checks, stale-`17` comment fix
- `scripts/test-all.sh` — the sibling refusal in the `tc_preamble`→`tc_acquire` window (`:681-688`)
  and its exit-contract comment (`:15`). **The `SOLEUR_SUBAGENT` antecedent at `:271` is NOT touched.**
- `scripts/lib/test-contention.sh` — export `sib_count` as `TC_SIBLING_RUN_COUNT`; rewrite the
  "All are advisory" comment above the banner block, which this change falsifies
- `lefthook.yml` — the `bun-test` pre-commit hook (`:234-237`), per AC11a's blast-radius decision
- `plugins/soleur/test/fanout-suite-scope.test.sh` — new sibling-refusal arms, and the
  prose-presence assertion at `:174-182`
- `plugins/soleur/skills/ship/SKILL.md` — `:345` (the "inherits exactly that variable" falsehood)
- `plugins/soleur/skills/one-shot/SKILL.md` — `:68` (same falsehood, different wording)
- `plugins/soleur/skills/review/SKILL.md` — `:159`, `:164`
- `plugins/soleur/skills/work/SKILL.md` — `:292`, `:805`
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` — amendment
- The eleven suites from the Phase 0.2 derived list (see Reconciliation)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-194-*.md` (ordinal provisional)

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Lower `MAX_DEFERRED` to reflect the hardened suites | Measured impossible: `n_deferred` is directory-derived and is 47 before and after. |
| Promote the deferred directories into `COVERED_DIRS` | Their 16 CONSTRUCTION cases exceed the global cap of 15, which has zero headroom; ARM 4/5 reject per-file promotion. This is #7585's seam and is larger than this PR. |
| Ship the eleven fixes with no new guard arm | The work would be entirely unverified by CI — the exact class ADR-193 and the 2026-08-10 learning exist to prevent. |
| Put `SOLEUR_SUBAGENT: "1"` in `.claude/settings.json` `env` | Session-global; refuses the lead's own sanctioned gate run, collapsing the guard to a no-op with extra typing. |
| A new `PreToolUse` rewriter hook | ADR-162 permits exactly one `updatedInput` emitter, mechanically enforced; `grep-rewrite.sh` holds the slot. |
| Leave the skill sentences and only fix the guard | An unenforceable claim presented as mechanical enforcement stops the next reader from checking. Correcting them is unconditional under every repair path (Phase 3a). |
| Resolve #7517 (bare `[[ "$FAIL" -eq 0 ]]` gates) here | Separate unresolved design question; explicitly out of scope per the brief. |
| **Replace identity-detection entirely with an `flock` mutual-exclusion lock in `test-all.sh`** | **Raised by the Step 4.5 strong-model consult, and it is the strongest argument against this plan's chosen direction — recorded as a User-Challenge in `decision-challenges.md` rather than silently taken or silently dropped.** The case for it: the stated harm is *concurrent* full-gate runs, which is a mutual-exclusion problem; a lock solves it directly, is testable in CI by spawning two processes, deletes the entire Phase 0.1 risk branch, and does not rest on undocumented harness-internal state with a structurally untestable fail-open mode. The case against: the issue's stated intent is that a spawned agent should run *only its own suites*, not queue for a battery it should never have started — a lock serialises the wrong behaviour instead of refusing it, and N-1 subagents still pay the wait while the one that wins still burns the full battery wrongly. The two are also **not mutually exclusive**: a lock is a sound belt-and-braces addition under either Phase 0.1 branch, and is the natural terminus if branch (c) fires. Deciding to *drop* the operator's stated direction is not a call this plan makes on its own. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `/work`.
- **The population is a snapshot the moment it is written.** The brief's eight went stale in three
  days; this plan's eleven will too. Phase 0.2 re-derives, and the guard arm is derivation-based
  for the same reason. Never edit the list instead of re-deriving it.
- **A copy of `guard-vacuity-floor.test.sh` run from outside the repo dies with `fatal: not a git
  repository`** — it derives `REPO_ROOT` from `$(dirname "${BASH_SOURCE[0]}")/..` at `:51`. Pin
  `REPO_ROOT` in any scratch copy before running it.
- **`MAX_DEFERRED` and `MAX_CONSTRUCTION_FAILURES` both sit at exactly their measured values.**
  There is no headroom in either. Any change that adds a floor-bearing suite to a deferred
  directory, or a construction failure to the covered scope, reddens CI on arrival.
- The guard's own explanatory prose disagrees with its own code (`17` in comments vs `15` in the
  constant). Trust the constant; the comment is the stale copy.
