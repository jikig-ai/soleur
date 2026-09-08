---
title: "Shell git-fixture containment, and a hook_self_fault signal that can name its cause"
date: 2026-09-08
slug: fix-shell-git-env-scrub-and-hook-fault-diagnosis
branch: feat-one-shot-7822-7275-shell-git-env-scrub-hook-fault-diag
issue: 7822
closes: 7822, 7275, 7835, 7942
type: fix
classification: test-infrastructure, hook-observability
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Two open defects share one shape: a control that is present, green, and unable to tell anyone what
it saw.

The first (#7822, with its more severe sibling #7835) is that shell test fixtures inherit `GIT_DIR`
from the git hook that runs them. Git resolves its repository from the environment before it falls
back to discovering one from the working directory, so a fixture that builds a temp repository and
commits into it can commit into the contributor's repository instead. A quieter harm rides along: a
case that runs a gate in a deliberately non-git directory, to prove the gate fails for want of a
repository, inverts under an inherited `GIT_DIR` — the directory is a repository, the gate succeeds,
and the case stays green while proving nothing.

The second (#7275) is that when a PreToolUse hook cannot parse its stdin it records the fault and
runs the tool call with its guards disarmed, and the recorded reason cannot distinguish the causes.

Both premises survived validation; neither survived unchanged. The corrections shrank the work
substantially, and they are the substance of this plan rather than footnotes to it:

- The shell scrub wrapper #7822 proposes was **already considered and explicitly cut** by the merged
  #7833 plan, and the sweep it implies is **already tracked as #7849** — where it is not merely
  deferred but has a *named exit condition*. Measured against that condition the sweep this plan
  owes is five files, not the twenty-five the issue's framing implies.
- The classifier defect in #7275 is **deeper than the issue states**. The issue reads the `else`
  branch as collapsing two causes. Measured here, the variable that branch switches on is never
  populated: `PIPESTATUS` does not survive the command substitution it is read after, so `jq_rc` is
  unconditionally `0`, the `internal` arm is dead code, and *every* zero-output failure is labelled
  `unparseable`. The file's comment that "jq's exit code already makes the only distinction that
  matters" describes a discriminator the code never reads.

A five-agent review then cut a third of what remained. Two proposed guards were removed — one whose
verdict certified "contained **or** refuses to run", the other whose ratchet could not detect the
regression it named — and the review's most valuable finding was that the containment regression
test, as first drafted, would have gone green by aborting before it tested anything.

## Research Insights

### Premise validation (Phase 0.6)

| Premise (as given) | Verdict | Finding |
|---|---|---|
| #7822 and #7275 are open and unresolved | **Holds** | Both `OPEN`, no closing PR references. |
| TS half of #7822 shipped via `plugins/soleur/test/lib/git-clean-env.ts` | **Holds, superseded** | Succeeded by `git-fixture-env.ts`, which adds a discovery ceiling, config hardening, identity pinning and a non-`GIT_`-prefixed execution-vector list. That is the reference design. |
| The shell half is untouched | **Refuted in part** | A shell tier exists: `plugins/soleur/test/test-helpers.sh` carries a fail-loud **tripwire** (`exit 97`), and three entry points already `unset` a nine-name list. What does not exist is a shell *scrub helper* — cut deliberately by the #7833 plan. |
| jq rc 5 and rc 0 fall through the same `else` | **Holds, understates it** | The return code is never read at all (R6). |
| `rule-metrics-aggregate.sh` exits non-zero after writing | **Holds; list drifted** | Reproduced at exit 5. Twelve orphan ids now, not the seven the issue lists. |
| ADR-194 cleanup and the ship Incident-PIR gate are out of scope | **Respected** | Neither is touched or referenced as work. |

Binding decisions found in the ADR corpus: **ADR-156** (hook stdin is model-controlled and
untrusted), **ADR-157** (a hook that cannot parse its input asks), **ADR-165** (posture splits by
*reason class*), **ADR-193** (anti-vacuity floor contract), **ADR-091** (rule metrics have a local
producer). The merged plan
`knowledge-base/project/plans/archive/20260904-163540-2026-09-04-fix-test-fixture-git-env-scrub-plan.md`
is the governing prior art for the #7822 half.

### Do not build these

Each was proposed by an issue or an earlier draft, and each is removed with a reason. This list
exists so the next pass does not re-derive them.

| Mechanism | Why not |
|---|---|
| `env -u GIT_DIR … -u GIT_OBJECT_DIRECTORY`, as literally specified in #7822 | A six-name list where the repo already deploys a **nine**-name list at all three entry points (`scripts/test-all.sh:232`). Adopting it verbatim *reduces* coverage: it omits `GIT_TEMPLATE_DIR`, and `git-fixture-env.ts` records a measurement where an inherited `GIT_TEMPLATE_DIR` made `git init` copy a hook that the fixture's own commit then **executed**. |
| A canonical shell `git-fixture-env.sh` body | Cut by name in the #7833 plan: *"`test-all.sh` + the tripwire already cover every shell suite; a second byte-for-byte canonical body beside `assert_fixture_dir()` is the drift this plan exists to end."* Not reversed here. |
| A lint over every test file that spawns git | Same plan cut the file-scale design in favour of guarding entry points: *"26 `run:` lines … plus 2 files under `scripts/hooks/` … against ~900 files for the cut design."* |
| A per-file containment guard over "shell suites that create a git fixture" | Cut at CTO review as **unsound**, not merely redundant: its verdict would conflate two properties (the tripwire *aborts*, it does not contain); its assembly would be a regex heuristic — three defensible predicates returned 42, 45 and 47 members for the same question — and every recorded recurrence (#1090, 2026-04-03 ×2, #7833) entered through an **entry point**, never a test file. |
| A monotone adoption ratchet replacing it | Cut at the following review round. After the sweep the baseline is 0, and `live <= 0` cannot detect the regression the ratchet names: raising a committed baseline from 0 to 5 leaves `0 <= 5` green. Its stated assembly was also self-contradictory — a committed integer is not "both sides computed by the same enumeration in the same run" — and it arrived with no mutation battery, in a plan that folds in #7942 precisely because ungated batteries are the defect. |
| Repo-wide conversion of 25–39 suites | Belongs to #7849; a sweep of near-identical diffs is the rubber-stamp review #7849 itself gave as reason (c) for deferring. |
| A new incident-row field for the type vector | `hook_input_report` already computes `reason_key="${reason%%:*}"` so "an `internal:<jq stderr>` detail stays out of the aggregation key". The channel exists, is commented, and is unused. |
| A new escalation channel | `summary.hook_input_fault_count` and its `WARNING:` line already exist. The gap is a consumer, and that consumer is deferred (see §Deferral). |
| A new `AGENTS.md` rule | Cannot land: `scripts/lint-agents-rule-budget.py` reports `B_ALWAYS=46000 >= 44000` — at the ratchet. |
| A static "the jq program compiles" assertion | Proposed at CTO review, cut at the next: AC1 drives real stdin through the real function, and a non-compiling `_HOOK_INPUT_JQ` fails AC1, AC5 and every hook on the first Bash call. The claim that it was "the only thing that catches `internal` before it ships" was false. |

### The sweep is #7849's own exit condition

The brief framed the sweep as residual work on #7822. It is not: it is the *named exit condition*
of issue #7849, whose re-evaluation trigger 2 reads, verbatim:

> **The fixture helpers are consolidated so scrubbing happens in exactly one place** — e.g. if
> `plugins/soleur/test/*.test.sh` reaches full `test-helpers.sh` adoption (measured 2026-09-04:
> 41 of 73 suites source it). At that point Guard 3's shell arm becomes a true chokepoint and this
> issue can be closed as unnecessary.

**Pin the predicate, because the count moved three times during planning.** 81 suites match the
glob. "How many source `test-helpers.sh`" returned 42, 45 and 47 under three defensible readings —
which is the evidence that killed the per-file guard, and is why no number here is ratcheted into
CI. The sweep set is every suite matching the glob that creates a git fixture, issues a git write
verb, and carries none of: a `source` of `test-helpers.sh`, an `exit 97` tripwire, or a `GIT_`
prefix scrub. Measured that way it is **five**:

- `plugins/soleur/test/gitleaks-merge-commit.test.sh`
- `plugins/soleur/test/harvest-debt.test.sh`
- `plugins/soleur/test/roadmap-reconcile.test.sh`
- `plugins/soleur/test/fixture-dir-operand-assert.test.sh` — the meta-gate for the *operand* class
  (#7652), carrying no protection against the *environment* class
- `plugins/soleur/test/proc.test.sh` — which also earns a vacuity entry below

`/work` re-derives with that exact predicate rather than trusting this list.

### Applicable institutional learnings

- `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
  — the original #1454 discovery. **Exclusion by prefix, never a name list.**
- `knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md`
  — reclassifies the class to `data_loss/high`: *"the helper that must be re-derived per file will
  eventually be re-derived wrongly, and prose does not stop that."*
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md`
  — a floor reports via `printf >&2` + `exit 1` directly, never through the suite's own verdict
  helpers; the case counter increments at the **call site**, never inside `$( )`, or conservation
  becomes a tautology that stays green under the fault it exists to catch.
- `knowledge-base/engineering/operations/post-mortems/fixture-git-env-live-repo-write-postmortem.md`
  — the incident record for the branch-tip rewrite.

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality | Plan response |
|---|---|---|
| **R1.** #7822 lists 10 of "~25" shell suites. | Three defensible predicates over the same property return different populations (42/45/47 adoption; 41 vs 66 candidates). | Report the spread as the finding. Never ratchet a number derived from a non-canonical predicate. |
| **R2.** "The shell half is untouched." | A tripwire and three entry-point scrubs exist. | Advance the adoption already underway; do not build a parallel mechanism. |
| **R3.** The shell scrub wrapper is the suggested fix. | The #7833 plan cut exactly that, by name. | Do not build it. |
| **R4.** A lint is the only thing that stops recurrence. | The chosen mechanism guards entry points; every recorded recurrence entered through one. | No new lint. The sweep plus the vacuity repairs are the deliverable. |
| **R5.** The TS half is done. | Two of the eight files #7835 names are converted; twelve TS test files still create a git fixture with no `gitFixtureEnv`. | Acknowledge, do not fold in — #7849 owns it. |
| **R6.** The jq classifier collapses rc 5 and rc 0. | It never reads a return code. `raw="$( … \| jq … ; printf 'X')"` then `jq_rc=${PIPESTATUS[1]:-0}`: the pipeline runs in a subshell, the parent's `PIPESTATUS` is `(0)` with length 1, so `jq_rc` is **always 0** and the `jq_rc == 3` arm is unreachable. Measured on bash 5.3.9 / jq 1.8.1; independently re-derived at CTO review. | Repair the discriminator first and alone. |
| **R7.** jq rc 5 means the document is invalid. | Confirmed directly: `''`→0, `garbage {{`→5, `{"a":"x"`→5, `[1,2,3]`→5, compile error→3. | rc 0-with-no-output → `empty`; rc 5 → `baddoc`; rc 3 and other non-zero → `internal`. |
| **R8.** The 7 faults/day are current. | **Zero** `hook_self_fault` rows exist in the retained log or either archive; the 2026-08 archive is not retained. | Do not claim a rate. The fix is forward-looking, and the evidence loss argues for the deferred consumer. |
| **R9.** The orphan gate lists 7 ids. | **12** now. Seven hook-emitted, three rule-shaped and in no registry, and `scripts/retired-rule-ids.txt` is **not consulted** by the aggregator. | Deferred; see §Deferral. |
| **R10.** Its harm is a rejected aggregate in the tree. | It also short-circuits **before rotation**, so an orphan starves rotation of the shared telemetry sink — plausibly contributing to R8. | Carried into the deferred issue. |
| **R11.** `hook_self_fault` comes from `hook-input.sh`. | Also `context-reviewed-gate.sh`, `grep-rewrite.sh` and `prod-write-defer-gate.sh`. **An earlier draft claimed the last of these already denies on a hook-input parse fault, and that is false** — on the envelope-parse axis it fails open exactly like every other hook; its `deny_self_fault()` covers a different fault class (its own decision inputs) under a different `rule_id`. There is therefore **no existing narrowing** of ADR-157 on the `.claude` side. | The deferred consumer counts the `kind`, which is a **rename** of `hook_input_fault_count`'s meaning, not a widening of the existing metric — recorded as such. And the deferred ask-posture work must argue its case on the merits, with no phantom precedent: a false citation propagates further than a missing one. |
| **R12.** Splitting the enum needs an aggregator change. | **Measured false.** A log carrying only `hook-input-empty` and `hook-input-baddoc` runs to exit 0 with `orphan_rule_ids == []` and `hook_input_fault_count == 2`, and the existing WARNING line already renders `[empty=1 baddoc=1]`. | No aggregator edit. The diagnostic surface appears for free. |
| **R13.** `.claude/hooks/*.test.sh` suites are tripwire-protected. | **False.** `grep -c 'exit 97'` returns 0 across all of them. Several carry an inline `assert_fixture_dir()`, which guards an empty or relative `-C` operand (#7652) and says nothing about an inherited `GIT_DIR`. | The remedy for hooks suites is the positive precondition, not a cross-tree `source`. |
| **R14.** The C4 count-parity suite is missing. | It exists at `plugins/soleur/test/c4-count-parity.test.sh`. | Path resolved at plan time. |

## Open Code-Review Overlap

**#7942** — *"Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run in no
gate"* — matches `scripts/test-all.sh` in this plan's edit list.

**Disposition: fold in.** This plan adds a mutation battery, and ADR-193 requires one. Shipping it
into the same ungated hole would reproduce the defect being closed. `Closes #7942` joins PR 2's body.
Verified: `SUITE_GLOBS` carries `plugins/soleur/test/*.test.sh` (`scripts/test-all.sh:78`), so
`.test.sh` files need no registration and `*.mutation.sh` — which does not match that glob — is
exactly the hole.

No other open code-review issue matches any planned path.

## User-Brand Impact

**If this lands broken, the user experiences:** a `git commit` that silently rewrites their branch
tip and truncates their index — the damage recorded in
`knowledge-base/engineering/operations/post-mortems/fixture-git-env-live-repo-write-postmortem.md`
(16 stray commits, index cut from ~14,000 entries to 2) — or, from the riskier half, a corrupted
`HOOK_FILE_PATH` in the library every PreToolUse hook parses through, which would misroute or
silently disarm guards on every Bash tool call, including the ones that block commits to main, block
`rm -rf`, and gate prod writes.

**If this leaks, the user's workflow is exposed via:** the reason string written to
`.claude/.rule-incidents.jsonl` and rolled into the committed `rule-metrics.json`. Hook stdin is
model-controlled and may carry credentials in a `Bash` command string. The reason carries only enum
heads from a closed set — never a field value, and never a length that could act as an oracle. This
is enforced structurally, since the jq program emits bad-path values empty by construction, and
asserted by AC10.

**Brand-survival threshold:** single-user incident

CPO sign-off is required at plan time before `/work` begins; `user-impact-reviewer` is invoked at
review time.

## Delivery shape — two PRs

| PR | Contents | Risk |
|---|---|---|
| **1** | Phases B1–B2: repair the discriminator and split the enum it discriminates on, with the byte-exactness gate. `Closes #7275`. | **High.** The library is sourced by 24 non-test hooks, 19 firing per Bash tool call (`hook-input.sh` states the 19 and why: #7165 registered `grep-rewrite.sh` on the Bash matcher). |
| **2** | Phases A1–A4: the vacuity repairs, the five-file sweep, the containment regression test, mutation-battery registration. `Closes #7822 #7835 #7942`. | Low |

B1 and B2 ship together because splitting them would land a correctly-read return code that nothing
consumes. They ship *apart from everything else* because ADR-157's own core argument is that a
persistent fault in this library is unrecoverable — the repair is itself a Bash call — and that
argument applies to this change.

**Two things this ordering costs, stated rather than left to be inferred.** First, the twice-realized
index truncation stays live through PR 1: the five uncontained suites and the seven vacuity-bearing
suites are exactly as they are today until PR 2 merges. That is the right trade — B1 is the only
change that could brick a session, and the containment gap is the pre-existing status quo, not a
regression this plan introduces — but it is a real window and it should be visible in the PR body.
Second, the PRs share no files, so the dependency is ordering only: PR 2's battery registration must
cover PR 1's battery, which is why the battery is created at a path PR 2's assertion reaches.

## Implementation Phases

### Phase 0 — preconditions (measure; do not assume)

1. Re-run the `PIPESTATUS`-through-command-substitution probe. If `jq_rc` is not always 0 on the
   machine of record, **stop** — R6 has not reproduced and the design must be re-derived.
2. Re-derive the sweep set with the pinned predicate. If membership moved again, the sweep moves.
3. Re-run the aggregator against a **copy** of the live incidents log under `INCIDENTS_REPO_ROOT`.
   Never the real repo root — it writes before it rejects.

### Phase B1 — repair the discriminator (PR 1)

`jq_rc` is always 0. Capture the return code **inside** the command substitution and carry it out in
the captured text. No temporary file: the file rejects one on the hot path, and that reasoning stands.

**Use `$?`, not `PIPESTATUS`, inside the substitution.** jq is the last element of the pipeline, so
`$?` after it *is* jq's status. `PIPESTATUS[1]` would work today but encodes a positional invariant
that breaks silently the day anyone appends a filter.

**Strip the return code before the split, not after.** This is prescribed rather than left to
`/work`, because the obvious alternative is measurably broken. Appending the return code after the
program's trailing separator and then splitting makes the happy path yield **seven** fields instead
of six, and — worse — makes the captured text never empty, so the zero-field arm where Phase B2 puts
the entire `empty` / `baddoc` split becomes **structurally unreachable**. Control would fall to the
`1..n-1` arm, whose comment reads *"means OUR program is broken … Never blamed on the payload"*, and
every model-sent junk payload would be recorded as `internal` — the exact inverse of the defect being
fixed.

The shape that avoids both, measured end to end (RS below is U+001E):

```bash
raw="$( { printf '%s' "$input" | jq -j "$_HOOK_INPUT_JQ" 2>/dev/null; \
          printf '\036%s' "$?"; printf 'X'; } )"
raw=${raw%X}
jq_rc=${raw##*$'\036'}   # after the LAST RS — ours, appended after jq exited
body=${raw%$'\036'*}     # jq's output, its own trailing separator intact
# split $body — the six-field contract is untouched, and n == 0 stays reachable
```

Measured on bash 5.3.9 / jq 1.8.1, against this exact shape, rather than argued:

| Payload | fields | rc | classification |
|---|---|---|---|
| happy envelope | **6** | 0 | success — the existing contract is unchanged |
| empty stdin | **0** | 0 | `empty` — the zero-field arm stays reachable |
| `garbage {{` | **0** | 5 | `baddoc` |
| `command` carrying an escaped RS | **7** | 0 | `separator`, and the rc is still read correctly |
| valid envelope **followed by** trailing garbage | 6 | **5** | see below |

Byte-exactness held on every shape AC4 names, and the whole probe ran under `set -euo pipefail`.

**State the true invariant, not a plausible one.** An earlier draft justified reading the count
first by claiming anything after the last separator is "forgeable by the payload". That is false:
the return code is written by `printf` *after* jq has exited, in the same subshell, so it is
unconditionally the final bytes, and a payload can only *inflate* the field count, never append past
the rc. The count is read first for a different and better reason — a forged separator then degrades
to `separator`, an already-loud fault, instead of shifting a value into the rc position. A rule
defended by a wrong reason is the shape the next reader simplifies away, which is how the dead
`jq_rc` branch survived for the life of this file.

**Two silent-success holes must close here, or P7 is false as written.** Both are pre-existing, and
both were found by measurement rather than reading:

- **A JSON `null` root parses as success with all five fields empty.** `null | .tool_input.command`
  yields `null`, which `d()` maps to `""`, so a null root escapes the `catch {}` that handles the
  other four non-object roots. `hook_parse_input` returns **0**, every guard keyed on `HOOK_CMD` or
  `HOOK_FILE_PATH` no-ops, and no incident row and no `ask` are produced. ADR-157 enumerates a
  non-object root under "anything else ⇒ ask". Require `type == "object"` on the root before the
  accessors, and add a contract case per non-object root.
- **A complete first record block followed by trailing garbage yields a correct count with rc 5.**
  Measured above. The return code must therefore be classified even when the count is right, as its
  own diagnostic class — the values are byte-exact so the guards may still run, but leaving it
  unclassified gives a payload a way to suppress the fault signal on every call, which is the very
  channel the deferred consumer is built on.

**Two further rules the code must state.** A trailing field failing `^[0-9]+$` is **never** a success
and is classified `internal` — collapsing it onto a payload class is the "broken gate hides as a bad
payload" failure this phase exists to end. And **the last command inside the substitution must be the
sentinel `printf`**: under `set -euo pipefail`, which several sourcing hooks use, a non-zero final
status kills the shell at the assignment, printing nothing and letting the tool proceed. That is
defect 2 reintroduced one line above where every test points.

**The corruption hazard this phase must not ship.** If the return code lands inside the field body it
appends to the last field — `HOOK_FILE_PATH` — while the count stays at six, so a count assertion
passes while every hook's `HOOK_FILE_PATH` is silently corrupted. The worst consumer is the **empty**
slot, not a populated one: `no-memory-write.sh` and `kb-domain-allowlist-guard.sh` both resolve
`TARGET="${HOOK_FILE_PATH:-$HOOK_CMD}"`, so an empty slot becoming `"0"` kills the `:-` fallback and
both guards inspect the literal `0` instead of the command — on every Bash call, with rc 0 and six
fields, so nothing anywhere reports it. AC4's envelope set is chosen to close exactly this.

Replace the comment *"jq's EXIT CODE already makes the only distinction that matters"*: it is the
artifact that let the dead branch survive review for the life of the file.

### Phase B2 — split the reason enum (PR 1)

| Condition | Reason | Owner | Reachable in production? |
|---|---|---|---|
| expected count, rc 0 | — (success) | — | yes |
| zero fields, rc 0 | `empty` | the caller sent nothing | **yes** |
| zero fields, rc 5 | `baddoc` | the payload is not valid JSON | **yes** |
| zero fields, rc 3 | `internal:rc3` | our program failed to compile | **no — by construction** |
| 1..n-1 fields | `internal:count` | our program is broken mid-stream | no |

**The two `internal` arms must be distinguishable, and this is not cosmetic.** A broken
`_HOOK_INPUT_JQ` emits nothing, so after B1 the captured text is the return-code digits alone and
the split yields **one** field, not zero — which lands in the pre-existing "our program is broken"
arm and assigns `internal` *without ever consulting the return code*. A mutation row asserting
"break the program → reason is `internal`" would therefore pass while the rc-3 arm this plan exists
to repair stayed dead. Emitting `internal:rc3` versus `internal:count` is what makes that row
discriminate, and the battery carries a positive control proving the rc-3 arm is reachable at all.

The reason head is unchanged for the aggregation key, because `hook_input_report` already strips at
the first colon. Rule ids become `hook-input-empty`, `hook-input-baddoc`, `hook-input-internal`.
**Measured:** a log carrying the new ids runs the aggregator to exit 0 with `orphan_rule_ids == []`
and `hook_input_fault_count == 2`, and the existing WARNING line already renders the breakdown:

```
WARNING: 2 PreToolUse hook input-contract fault(s) — a hook could not parse its stdin
and ran with guards disarmed [empty=1 baddoc=1].
```

No aggregator edit is required, and the diagnostic surface #7275 asks for appears for free.

### Phase A1 — the vacuity repairs (PR 2)

This is the semantic half, and it is the part no other layer covers: an entry-point scrub only makes
these cases accidentally-green-for-the-right-reason. Each case that asserts "no repository here"
gains a precondition that evidences its own premise.

**The precondition needs a positive control, or it inherits the defect it fixes.** A bare "`git
rev-parse --git-dir` must fail" is satisfied by `git` missing from PATH, by the directory not
existing, and by a permission error — all while the case is as vacuous as before. The assertion is
therefore three-part, run **under the subject's own environment and working directory**: the same
command must *succeed* in a known repository, must *fail* in the fixture directory, and the failure
text must name `not a git repository`.

**Do not batch by remedy — the mechanisms differ.** Two suites need something other than repo-ness:

| Suite | Vacuity, and what the precondition must actually assert |
|---|---|
| `.claude/hooks/guardrails.test.sh` | **Whole-suite, and the one that cannot wait.** `decision_of()` runs the hook from a `mktemp -d` CWD precisely so **branch resolution comes back empty** and the orthogonal block-commit-on-main gate no-ops — isolation added by #5192 after these fixtures passed on a feature branch and failed on main-CI. Repo-ness is neither necessary nor sufficient for that: a detached HEAD in a real repository also yields an empty branch. The precondition asserts the **branch resolution is empty**, and that the gate is observed to no-op. |
| `scripts/skill-security-scan-step-body.test.sh` | The root-commit arm asserts `HEAD^1` cannot resolve. Under an inherited `GIT_DIR` it resolves against the caller's real HEAD. The precondition asserts **`HEAD^1` is unresolvable**, not that the directory is not a repository. |
| `.claude/hooks/session-rules-loader.test.sh` | Four discrete non-repo fixtures (T13, T23, T30, T31). Repo-ness precondition applies. |
| `scripts/check-pa-22.test.sh` | Self-documented: *"A sandbox that is not a git repo makes the SUT resolve to the REAL worktree, which would both void the case and read the live corpus."* Prefer asserting the SUT's own resolution names the fixture. |
| `scripts/lint-legal-registers.test.sh` | One operand case plus twelve dependent red-arms. |
| `apps/web-platform/infra/workspaces-luks-loopback.test.sh` | The `fatal:`-shape fsck arms. |
| `plugins/soleur/test/proc.test.sh` | Surfaced late, by the citation audit rather than by the vacuity sweep — which is the point. It opens `NOGIT="$(mktemp -d -t proc-nogit…)"` as a deliberately non-git directory, in a suite three earlier passes classified only by its git-write shape. |

`apps/web-platform/test/ci/service-role-allowlist-gate.test.sh` is a **distinct shape** — it
deliberately mutates the *live* index with `git add -f` and has no fixture repository, so under a
hostile environment its `git rm --cached -f` cleanup may not undo what it did. Handle it
individually; do not batch it.

For `.claude/hooks/` suites the remedy is the precondition and nothing else. Per R13 no suite there
carries the tripwire, the 42 files that source `test-helpers.sh` live almost entirely under
`plugins/soleur/test/`, and the established pattern in the hooks tree is an inline byte-pinned copy
rather than a cross-tree `source` that would drag in an assertion framework those suites do not use.

### Phase A2 — adopt the tripwire in the five measured suites (PR 2)

The members of #7849's named exit condition. **Sourcing is not purely additive** and the diff must
account for it: `test-helpers.sh` carries `set -euo pipefail` and a `PASS`/`FAIL`/`SKIPPED` harness,
while `gitleaks-merge-commit.test.sh` and `harvest-debt.test.sh` run `set -uo pipefail` (no `-e`) and
`harvest-debt.test.sh` defines no counters at all. Adopting the helper changes failure semantics in
at least two of the five; verify each still passes rather than assuming the source line is inert.

Record the new adoption count in #7849. This is adoption bookkeeping that advances #7849's exit
condition — it is not containment, because under the only runner that reaches these suites the
entry-point scrub has already removed every variable the tripwire would fire on.

### Phase A3 — the containment regression test (PR 2)

The shell counterpart of Guard 1, and the one test here that can reproduce the incident it closes.

**The oracle must include the child's exit code, or the test is false-green.** A swept suite sources
`test-helpers.sh`, so under a hostile `GIT_DIR` the tripwire fires and the child exits 97 *before
running any git write*. The victim is then trivially unchanged and the test passes — and it keeps
passing if an entry point's `unset` is removed, which is the single most likely real regression.
Asserting only the victim's state certifies "contained **or** refuses to run", which is precisely the
reasoning that got the per-file guard cut.

Two arms, therefore:

- **Refusal arm.** Tripwire armed, hostile environment set: assert the child exits **97**.
- **Containment arm.** Tripwire disarmed via `SOLEUR_GIT_TRIPWIRE_ALLOW=1`, hostile environment set:
  assert the child exits **0** *and* the victim's HEAD, ref set and staged-file list are unchanged.
  This is the arm where the scrub is actually under test.

The victim's three observables are compared as a triple, not HEAD alone: with `GIT_DIR` scrubbed an
absolute `GIT_INDEX_FILE` still retargets `git add` while HEAD stays put. The victim path passes an
`assert_fixture_dir`-class operand guard, and the hostile `GIT_DIR` must never resolve under `$PWD`.

### Phase A4 — register the mutation batteries (PR 2, closes #7942)

Register every tracked `*.mutation.sh` in `scripts/test-all.sh` — **repo-wide, derived from
`git ls-files '*.mutation.sh'`, not scoped to one directory.** Batteries already exist outside
`plugins/soleur/test/`, and `scripts/lint-orphan-test-suites.sh` states the principle this plan must
not violate in the very PR that cites it: the producer is the whole repo, because *"every
directory-scoped version of it has eventually been outgrown by a suite added one directory over"*.

**State the mechanism, because `SUITE_GLOBS` is not obviously the right home.** That array is
consumed by `lint-orphan-test-suites.sh`, which diffs it against `git ls-files '*.test.sh'`, and its
own comment rejects a glob matching nothing. A `*.mutation.sh` entry matches zero `*.test.sh` files
by construction, so A4 must either extend the linter's producer to a second suffix or register
batteries through a separate mechanism — and say which. Then assert the
registered set equals the tracked set so the next battery cannot enter the same hole. Bring
`*.mutation.sh` into `scripts/guard-vacuity-floor.test.sh`'s derived population as well — that guard
derives from tracked `*.test.sh`, so the batteries sit outside it, and leaving them there would
reproduce this plan's own defect class one layer up.

## Deferral (`wg-defer-only-after-inline-triage`)

**The `rule-metrics-aggregate.sh` orphan gate (R9, R10) is deferred to a new tracking issue**, filed
in the same pass. Triaged inline, not dropped: it is reproduced, diagnosed, and its remedy is
specified. It is deferred because it belongs to none of #7822, #7835 or #7275 — a different
subsystem, whose notion of "known" is the fiddliest work in scope and the change most likely to mask
a real orphan if rushed alongside a hook-library repair.

The issue carries: reject **before** the write (today it writes, exits 5, and never reaches
rotation — so an orphan starves rotation of the shared telemetry sink); derive "known" from the three
authorities rather than an accreting per-prefix allowlist (`AGENTS.md` ids, plus
`scripts/retired-rule-ids.txt` which the aggregator does not consult at all, plus hook-declared
ids); preserve the documented load-bearing pair, whereby an exclusion that removes an id from
`orphan_rule_ids` must not remove its only readout; and the 12 measured orphan ids.

**The signal consumer (#7275 Ask 3) is deferred with it, and its design must change.** As a hard CI
gate it is unclearable by CI: ADR-091 makes the producer local, so any contributor whose local hooks
faulted once commits a red metric and `main` stays red until someone runs `/compound` locally. It
must be a threshold-and-delta signal that files an issue, or it must name who clears it and how.
Recording this now prevents it being built the wrong way later.

**The type vector (#7275 Ask 1, second half) is deferred to the same issue.** `HOOK_INPUT_REASON`
already names the class (`nonstring`); the vector adds a `:string,array,null,…` suffix. It would
require editing `_HOOK_INPUT_JQ` — the constant program whose fragility is the entire reason PR 1
ships alone — for a path that has fired **zero** times in the retained log (R8). ADR-157 does decide
that telemetry carries the type, so this is a real conformance gap; it is conformance debt on an
unfired path rather than a defect, and it is cheaper and safer once the classifier below it is sound.
See `decision-challenges.md` — this diverges from the stated scope and the operator should see it.

## Files to Create

| Path | Why |
|---|---|
| `plugins/soleur/test/shell-fixture-containment.test.sh` | Phase A3's two-arm regression test. Auto-registers via `SUITE_GLOBS`. |
| `plugins/soleur/test/hook-input-classification.mutation.sh` | The Guard mutation battery, driving the real `hook_parse_input`. **Deliberately under `plugins/soleur/test/`, not beside the library it exercises** — an earlier draft placed it at `.claude/hooks/lib/`, outside the `plugins/soleur/test/*.mutation.sh` glob Phase A4 registers, so the plan's own battery would have escaped the very gate it adds to close #7942. |

## Files to Edit

| Path | Why |
|---|---|
| `.claude/hooks/lib/hook-input.sh` | B1–B2. |
| `.claude/hooks/hook-input-contract.test.sh` | The new reason heads, the field-count convention, byte-exactness. |
| `.claude/hooks/README.md` | The reason enum. |
| `scripts/test-all.sh` | A4: register every `*.mutation.sh`. The new `.test.sh` needs no registration — `SUITE_GLOBS` already carries `plugins/soleur/test/*.test.sh` (`scripts/test-all.sh:78`), and the array's own comment warns that a second copy of the list is the mutation it exists to catch. |
| `scripts/guard-vacuity-floor.test.sh` | A4: bring `*.mutation.sh` into the derived population. |
| `scripts/rule-metrics-aggregate.sh`, `scripts/rule-metrics-aggregate.test.sh` | AC12, **documentation only**: the inline enum roster and the `hook-input-unparseable` fixture name an enum member this plan retires. No behavioural change; the orphan gate stays deferred. |
| The five sweep suites (Phase A2) | Adopt the tripwire. |
| The seven vacuity-bearing suites plus `service-role-allowlist-gate.test.sh` (Phase A1) | Preconditions. |
| `knowledge-base/engineering/architecture/decisions/ADR-157-…md` | **Errata only** — correct its factual claim that the exit-code distinction is made. |

`plugins/soleur/test/test-helpers.sh`, `lefthook.yml`, `scripts/hooks/pre-push`,
and `plugins/soleur/test/lib/git-fixture-env.ts` are **not** edited — they are prior art this plan
builds behind.

`scripts/rule-metrics-aggregate.sh` and its test **are** edited, for documentation only (AC12): the
script carries an inline enum roster naming `hook-input-unparseable`, and the test writes a fixture
by that id. Retiring the id without touching either would leave the enum's only cross-subsystem
documentation describing an enum that no longer exists — the same doc-rot the ADR-157 errata fixes.
Its **behaviour** is untouched, and its orphan gate stays deferred.

Because the ask posture is deferred with the type vector, **no new ADR is claimed** and the
ordinal-collision class does not arise. ADR-157 receives a factual correction, not a decision change.

## Acceptance Criteria

### PR 1 (B1–B2)

1. **AC1 (the discriminator is real, driven through stdin).** Two cases injected as *stdin*, not by
   stubbing jq — the exactly-one-`jq` contract forbids a second invocation, so the fault must be
   induced at the payload: empty stdin observes rc 0, a truncated document (`{"a":"x"`) observes
   rc 5. **Both must fail against the pre-B1 code**, with before/after readings in the PR body.
2. **AC2 (the zero-field arm stays reachable).** Empty stdin and `garbage {{` both produce **zero**
   fields after the return code is stripped, and are classified `empty` and `baddoc` respectively.
   This is the assertion that catches the strip-after-split design, in which the captured text is
   never empty, the zero-field arm is dead, and every payload fault is misreported as `internal`.
3. **AC3 (the six-field contract is unchanged).** A happy-path envelope yields exactly **6** fields
   after the strip — the same number as before B1 — with field order unchanged and the existing
   exactly-one-`jq` assertion still passing.
4. **AC4 (byte-exactness — the corruption gate).** For happy-path envelopes all five published
   globals are byte-identical pre- and post-B1. Each shape targets a distinct failure of the *new*
   return-code strip, not only the old sentinel strip:
   - `file_path` = `/tmp/aX` — breaks a naive `${raw%X}`.
   - `file_path` = `/tmp/f1` — a value **ending in a digit**, which an over-eager `${raw%[0-9]}`
     truncates.
   - `command` = `5` — a value that is **entirely digits**.
   - `command` = `ls\n` — a trailing newline, which the separator/sentinel pair shields and which B1
     inserts new content beside.
   - **an absent `file_path`, so slot 5 is empty.** This is the highest-value shape and the one an
     earlier draft omitted: `no-memory-write.sh` and `kb-domain-allowlist-guard.sh` both resolve
     `TARGET="${HOOK_FILE_PATH:-$HOOK_CMD}"`, so an empty slot becoming `"0"` kills the `:-` fallback
     and both guards silently inspect `0` instead of the command, on every Bash call, with rc 0 and
     six fields. Assert `HOOK_FILE_PATH` is byte-identically **empty**, and assert both guards still
     resolve `TARGET` to the command on that payload.
   - a payload carrying **both** an `X`-terminated value and an escaped RS, so the strip and the
     forge are exercised together rather than only apart.
5. **AC5 (a forged separator cannot manufacture a return code).** A `command` carrying an escaped RS
   yields seven fields and is classified `separator`; the return code is still read correctly,
   because it is appended after jq exits and is unconditionally the final bytes. A *raw* unescaped RS
   is invalid JSON and takes the zero-field arm instead — both shapes are asserted, since they take
   different arms.
6. **AC6 (a non-object root is never a silent success).** Each of `null`, `5`, `"str"`, `[1,2,3]` and
   `true` as the document root produces rc 1 and a classified reason. `null` is the load-bearing
   case: today it returns **0** with all five fields empty, so every guard no-ops with no incident
   row and no `ask` — which falsifies P7 and ADR-157's own enumeration of "a non-object root ⇒ ask".
7. **AC7 (a return code is classified even when the count is right).** A valid envelope followed by
   trailing garbage yields six fields with rc 5. It is recorded as its own diagnostic class rather
   than discarded — otherwise a payload can suppress the fault signal on every call while the guards
   run normally.
8. **AC8 (a non-numeric trailing field is never a success).** It is classified `internal`, never
   `unparseable` or `baddoc`: blaming the payload for our own broken output is the collapse this
   phase exists to end.
9. **AC9 (the library survives `set -euo pipefail`).** `hook_parse_input` is driven from a harness
   running `set -euo pipefail` and **returns** on every fault path rather than killing the shell.
   The contract test asserts the last command inside the command substitution is the sentinel
   `printf`, which is what keeps the assignment's exit status zero.
10. **AC10 (the enum splits on the reachable members).** Empty stdin yields `empty`; `garbage {{`
    yields `baddoc`; the two are distinguishable by `rule_id`.
11. **AC11 (the two `internal` arms discriminate).** A deliberately broken `_HOOK_INPUT_JQ` is
    reported as `internal:rc3`, distinguishable from the `internal:count` produced when the program
    emits a partial record block. A positive control proves the rc-3 arm is reachable. Without the
    pair, a "break the program → reason is `internal`" assertion passes via the count branch while
    the repaired discriminator stays unproven.
12. **AC12 (the aggregator is undisturbed).** A log carrying the new ids runs to exit 0 with
    `orphan_rule_ids == []`, and the WARNING line renders the per-reason breakdown. The aggregator's
    inline enum roster and its `hook-input-unparseable` test fixture are updated in the same PR, so
    the enum's only cross-subsystem documentation does not describe an enum that no longer exists.

### PR 2 (A1–A4)

13. **AC13 (the sweep is complete against a pinned predicate).** The five named suites source
    `test-helpers.sh` and each still passes — the `set -e` and counter-harness changes are verified,
    not assumed, since `test-helpers.sh` carries `set -euo pipefail` and a `PASS`/`FAIL` harness that
    two of the five do not currently use. The predicate is written into the PR body so the count is
    falsifiable.
14. **AC14 (containment is demonstrated, and refusal is not mistaken for it).** The A3 test's
    **refusal arm** asserts the child exits 97; its **containment arm**, run under
    `SOLEUR_GIT_TRIPWIRE_ALLOW=1`, asserts the child exits 0 *and* the victim's HEAD, refs and staged
    list are unchanged. A version asserting only the victim state must be shown to pass with an
    entry-point `unset` removed — that is the false-green this AC exists to exclude.
15. **AC15 (vacuity is repaired, with a positive control).** Each named case asserts, under the
    subject's own environment and working directory, that the probe *succeeds* in a known repository
    and *fails* in the fixture directory with text naming `not a git repository`. A bare non-zero
    exit is insufficient — it is satisfied by `git` missing, by the directory not existing, and by a
    permission error. `guardrails.test.sh` instead asserts branch resolution is empty and the
    block-commit-on-main gate is observed to no-op; `skill-security-scan-step-body.test.sh` asserts
    `HEAD^1` is unresolvable. Each fails when its precondition does not hold, including under a
    hostile `GIT_DIR`.
16. **AC16 (telemetry carries no payload content, proven not sampled).** A canary
    `["curl","-H","Authorization: Bearer sk-LEAKCANARY"]` produces no occurrence of `LEAKCANARY` in
    `.rule-incidents.jsonl`, its rotated archive, stdout, stderr, or the `permissionDecisionReason`
    envelope — **paired with a positive control** asserting the run *did* write a
    `hook-input-nonstring` row, so the absence is evidence rather than silence. Canaries are placed
    in slot 1 and slot 5 (the only branching accessor) and as an object *key*, and a `baddoc` arm
    covers the one class where payload bytes exist near a sink at all: jq's stderr, which is why
    `2>/dev/null` on the jq call is itself contract and not tidiness.
17. **AC17 (the emitted envelope is always valid JSON).** `hook_input_emit_ask`'s stdout parses
    under `jq empty` for every producible reason. The reason is interpolated into a JSON string
    literal by `printf`, so a reason that ever stops being a closed-enum value could break the
    envelope — and a malformed envelope is silently ignored by Claude Code, meaning the tool runs
    with neither a prompt nor guards.
18. **AC18 (the batteries run, and are themselves guarded).** Every tracked `*.mutation.sh` in the
    repository — not merely those under `plugins/soleur/test/` — is reached by `scripts/test-all.sh`,
    the registered set equals the tracked set derived from `git ls-files '*.mutation.sh'`, and
    `*.mutation.sh` is inside `scripts/guard-vacuity-floor.test.sh`'s derived population.

### Post-merge (operator)

None. Every criterion is verifiable in-session or in CI.

## Guard Contract

One guard ships. The two earlier candidates were cut — see §Do not build these.

### Guard — hook-input reason classification

**Property.** For every distinguishable failure of the hook-input parse, the recorded reason names
the cause and attributes it to the correct owner — our program, the caller, or the payload — and no
input reaches a silent success, and the happy path's five field values are unchanged byte-for-byte.

**Assembly.** Every `return 1` path in `hook_parse_input`, plus the happy path and the non-object
roots, reached through the real function rather than a re-implementation. The chokepoint is
`hook_parse_input`; the battery drives it and never a copy of its logic.

**Mutant scoping is part of the contract, not an implementation detail.** `hook-input.sh` carries
**two byte-identical `HOOK_INPUT_REASON="internal"` assignments** — one in the zero-field arm, one in
the partial-block arm — and the token `unparseable` appears once as a classifier assignment and twice
more inside log strings in `hook_input_report`. A file-wide `sed` without `/g` rewrites the first
match; with `/g` it rewrites log text rather than the classifier. Every mutant is therefore
**line-range scoped to the arm under test, with its placement asserted** — `cmp` proving the file
changed proves nothing about where. The battery runs an unmutated GREEN control first and aborts if
the baseline is red, mirroring `git-fixture-env.mutation.sh`.

**Mutation matrix.**

| # | Mutation | Must redden because |
|---|---|---|
| M1 | **Replace** the in-substitution capture with `jq_rc=${PIPESTATUS[1]:-0}` after the substitution | this is the shipped defect, and today nothing reddens on it. Specified as a scoped block replacement, never an appended line — appended, it is a dead assignment and the mutant reports the baseline |
| M2 | Strip the return code **after** the split instead of before | the happy path becomes seven fields and the zero-field arm goes dead, so `empty` and `baddoc` become unreachable and every payload fault reads `internal`. This is the design error the phase exists to avoid, and no earlier draft had a row for it |
| M3 | Map rc 5 to `internal:rc3` | a payload fault attributed to us hides a real payload class |
| M4 | Collapse `internal:rc3` and `internal:count` to a bare `internal` | the two arms stop discriminating and M1's repair becomes unprovable — the count branch would satisfy a bare-`internal` assertion while the rc-3 arm stayed dead |
| M5 | Remove the root `type == "object"` requirement | a `null` root returns 0 with all fields empty and every guard no-ops silently — the one input shape that produces no reason at all |
| M6 | Invert the order: read the trailing digits **before** the field count | a forged separator could then shift a value into the return-code position |
| M7 | Loosen the digit guard from `^[0-9]+$` to `^[0-9]*$` | an empty match satisfies the guard and a non-numeric tail is read as a return code |
| M8 | Move the return code inside the field body | the last field gains trailing digits while the count stays at six — the corruption AC3 cannot see, and whose worst consumer is the *empty* slot |
| M9 | Reorder the substitution so the sentinel `printf` is not last | under `set -euo pipefail` the assignment's non-zero status kills the hook, which prints nothing and lets the tool proceed |
| M10 | Drop the trailing separator alone, then the sentinel alone | the file documents these as a load-bearing **pair**; removing either in isolation is invisible without a row per member |
| M11 | Remove the `command -v jq` arm | `jq_missing` is a documented enum member; without a row it has no coverage at all |
| M12 | Return zero fields but exit before assigning a reason | **the guard's own dispatch** — an unset reason must not read as a pass |

**Harness rows.**

| # | Edit | Expectation |
|---|---|---|
| H1 | Replace the driver's call to `hook_parse_input` with a stub returning a canned reason | must redden: the battery must exercise the real function |
| H2 | Assert only on the reason **head**, ignoring the detail suffix | must redden: M4 survives a head-only assertion |
| H3 | Delete the canary's **positive control** (the assertion that a `hook-input-nonstring` row was written) | must redden: without it the absence assertion passes when the harness never delivered the payload at all |
| H4 | Move the case-counter increment **inside** the verdict helpers | must redden: ADR-193 §2 — an increment inside both helpers makes `passes + fails == cases` a tautology that stays green under the exact fault it exists to catch. The increment lives at the call site and never inside `$( )` |
| H5 | Neuter the battery's verdict helper | the floor must still fail — it reports via `printf >&2` + `exit 1` directly (ADR-193 §1) |
| H6 | **Must-PASS, non-canonical:** a valid envelope with a `null` `file_path` and an absent `session_id` | absence and empty are legitimate per ADR-156, and `d()` maps both to the empty string, so the battery must not treat either as a fault |

## Observability

```yaml
liveness_signal:
  what: summary.hook_input_fault_count plus its per-reason breakdown in knowledge-base/project/rule-metrics.json
  cadence: every local /compound run (ADR-091 local-producer model)
  alert_target: the aggregator's WARNING line, which already renders the breakdown (measured)
  configured_in: scripts/rule-metrics-aggregate.sh
error_reporting:
  destination: .claude/.rule-incidents.jsonl (local), rolled into the committed rule-metrics.json
  fail_loud: yes — hook_input_report writes the incident and a stderr line on every fault path
failure_modes:
  - mode: a hook parses nothing and runs with guards disarmed
    detection: an incident row whose rule_id names the split reason (hook-input-empty / -baddoc / -internal / -nonstring)
    alert_route: the aggregator WARNING line
  - mode: the classifier is broken and every fault reads alike
    detection: the mutation battery's M1 and M2 rows
    alert_route: CI, on every PR touching the hook lib
  - mode: a non-object root disarms every guard with no record at all
    detection: AC6 — the one shape that today produces no reason
    alert_route: CI
logs:
  where: .claude/.rule-incidents.jsonl, intended to rotate to .claude/.rule-incidents-YYYY-MM.jsonl.gz
  retention: DEGRADED, and this plan does not fix it. Rotation runs AFTER the orphan gate's exit 5
    in scripts/rule-metrics-aggregate.sh, and R9 measures 12 live orphans — so rotation is currently
    short-circuited on this repository and no archive is being produced. That is R10, deferred, and
    it is the most plausible explanation for R8 (zero hook_self_fault rows retained anywhere).
    Claiming "monthly archives" here would restate the very fiction the plan is correcting.
discoverability_test:
  command: bash scripts/rule-metrics-aggregate.sh
  expected_output: |
    Run against a sandboxed INCIDENTS_REPO_ROOT seeded with one synthetic hook-input-baddoc row,
    it exits 0 and prints a WARNING line naming the fault count and the per-reason breakdown —
    i.e. the operator-visible path from "a guard was disarmed" to "someone can read it".
    A C4 parity run was the earlier value here and was a category error: it demonstrates nothing
    about whether a hook_self_fault is discoverable.
```

The `hook_self_fault` signal is an **observability-layer 7** concern: it originates in the shell hook
surface that executes on a contributor's own machine, where no server-side telemetry reaches. The
committed metric is the only channel crossing that boundary, which is why the deferred consumer reads
the committed artifact rather than adding a remote sink. Until that consumer lands, **P8 is not
delivered by this plan** — the WARNING line fires only inside a local `/compound` run, so a
contributor who goes a fortnight without one runs a fortnight of calls with no out-of-session notice.
Saying so is the point; an Observability block that implied otherwise would be the same defect class.

## Architecture Decision (ADR/C4)

**No new ADR, and no decision change.** The ask-posture work — the only part of this plan that would
have altered a recorded decision — is deferred alongside the type vector, so nothing here narrows
ADR-157's posture and no ordinal is claimed. ADR-157 receives an **errata note only**, correcting its
factual claim that the exit-code distinction is being made; that is a correction, not a decision, and
it belongs in place.

When the deferred work lands it must follow ADR-165's precedent — a **new** record declaring
`Extends: ADR-156, ADR-157` and `Supersedes: nothing`, never an in-place amendment, because ADR-156
carries that it "must never be superseded, it may be extended". The deferred issue records that, so
the next pass does not amend in place.

### C4 views

Checked against all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.

**Enumeration performed.** External human actors: none added or changed. External systems/vendors:
none — no inbound webhook, outbound API or third-party store. Containers and data stores touched: the
`hooks` container and the local incidents log, both already modelled. Actor↔surface access
relationships: unchanged.

**No C4 edit is required, and this is a change from an earlier draft.** The `hooks` container
description asserts the ADR-157 posture as uniform and confines the split-by-reason-class to the
`.openhands` side. That sentence would have been falsified by the ask-posture change — which is now
deferred — so the description remains accurate. The deferred issue carries the C4 edit with the work
that makes it necessary.

**Cardinality parity.** This change adds no monitor, workflow or heartbeat, so it moves no derived
cardinality — asserted, not assumed, by running `plugins/soleur/test/c4-count-parity.test.sh`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** A CTO consult, a scoped strong-model consult and a six-agent panel (architecture,
test-design, security, simplicity, citation-audit, user-impact) independently re-derived the `jq_rc`
defect and reshaped the plan substantially.

*Cut across the rounds:* a per-file containment guard (unsound — the tripwire aborts rather than
contains, and its assembly was a regex heuristic whose defensible spellings returned 41 vs 66
members); its replacement adoption ratchet (at baseline 0, `live <= baseline` cannot detect the
regression it names, and its assembly contradicted itself); a static compile assertion (already
covered by AC1); the type vector and the ask posture (deferred — both acquired concrete defects and
both edit the hot path); a whole `## Test Scenarios` section that was the mutation matrices restated.

*Found and fixed:* that carrying the return code after the split would make the zero-field arm
**structurally unreachable**, so every payload fault would be misreported as `internal` — the exact
inverse of the defect being repaired; that a JSON `null` root parses as a **silent success** with all
five fields empty, disarming every guard with no record at all; that a complete record block followed
by trailing garbage yields a correct count with rc 5, giving a payload a way to suppress the fault
signal; that the `HOOK_FILE_PATH` corruption a count assertion cannot see has its worst consumer in
the *empty* slot, where it kills the `:-` fallback in two live guards; that `set -euo pipefail`
requires the sentinel `printf` to remain the last command in the substitution; that the containment
regression test as first drafted would have gone green by aborting on the tripwire before testing
anything, and stayed green with an entry-point scrub removed; that the vacuity precondition had three
vacuity modes of its own; that the plan's own mutation battery sat outside the glob it added to close issue
7942; and that a precedent the ADR was to cite (`prod-write-defer-gate.sh` denying on a parse fault)
does not exist on that axis.

All findings are adopted. The measurements the panel re-ran reproduced exactly; the defects clustered
where the plan had stopped measuring and started arguing.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit`
matches no path under `components/**`, `app/**/page.tsx` or `app/**/layout.tsx`. Tier: NONE.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| PR 1 changes the parse path in a library sourced by 24 non-test hooks, 19 firing per Bash tool call, where a persistent fault is unrecoverable because the repair is itself a Bash call. | It ships apart from all other work, behind AC4's byte-exactness matrix and the full contract battery. |
| The field-count convention is ambiguous, so claims about what a count assertion can see are unverifiable. | AC3 requires the number to be written into the file and asserted, before any claim rests on it. |
| A mutation row passes for the wrong reason and certifies a dead discriminator. | AC5 and M3: the two `internal` arms are distinguishable, with a positive control proving rc-3 is reachable. |
| The containment test goes green by refusing to run. | AC9's two arms, with the child's exit code in the oracle, and an explicit demonstration that the single-arm version passes with a scrub removed. |
| The vacuity precondition is satisfied by `git` being absent or the directory missing. | AC11's positive control: succeed in a known repo, fail in the fixture with matching text, under the subject's own environment. |
| Sourcing `test-helpers.sh` changes failure semantics in suites that do not use `set -e` or its counters. | AC8 verifies each swept suite still passes rather than assuming the source line is inert. |
| A guard's own battery escapes the gate that guards batteries. | The battery is placed inside the registered glob, and A4 brings `*.mutation.sh` into the vacuity floor's derived population. |
| Deferring the type vector and the consumer leaves #7275's Asks 1 and 3 partly open. | Both are written into the deferred issue with their designs, and surfaced to the operator in `decision-challenges.md` rather than quietly dropped. |
| The plan cannot demonstrate the 7-faults/day rate. | Stated as R8 rather than papered over, and kept visible in the PR body because #7275's title asserts it. |
