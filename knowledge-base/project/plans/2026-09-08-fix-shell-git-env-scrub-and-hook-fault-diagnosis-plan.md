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

Both premises survived validation; neither survived unchanged. The corrections are the substance of
this plan rather than footnotes to it, and two of them shrank the work by an order of magnitude:

- The shell scrub wrapper #7822 proposes was **already considered and explicitly cut** by the merged
  #7833 plan, and the sweep it implies is **already tracked as #7849** — where it is not merely
  deferred but has a *named exit condition*. Measured against that condition, the sweep this plan
  owes is **three files**, not the twenty-five the issue's framing implies.
- The classifier defect in #7275 is **deeper than the issue states**. The issue reads the `else`
  branch as collapsing two causes. Measured here, the variable that branch switches on is never
  populated: `PIPESTATUS` does not survive the command substitution it is read after, so `jq_rc` is
  unconditionally `0`, the `internal` arm is dead code, and *every* zero-output failure is labelled
  `unparseable`. The file's comment that "jq's exit code already makes the only distinction that
  matters" describes a discriminator the code never reads.

This plan repairs that discriminator, splits the reason enum onto it, brings the telemetry into
conformance with a decision ADR-157 already made, and closes the shell containment gap along the
line the repository has already chosen — without rebuilding what was cut or re-doing what is owned.

## Research Insights

### Premise Validation (Phase 0.6)

| Premise (as given) | Verified? | Finding |
|---|---|---|
| #7822 and #7275 are open and unresolved | **Holds** | Both `OPEN`, no closing PR references. |
| TS half of #7822 shipped: `plugins/soleur/test/lib/git-clean-env.ts` | **Holds, and is superseded** | It exists, but has since been succeeded by `plugins/soleur/test/lib/git-fixture-env.ts`, which adds a discovery ceiling, config hardening, identity pinning and a non-`GIT_`-prefixed execution-vector list. The reference design is `git-fixture-env.ts`. |
| The shell half is untouched | **Refuted in part** | A shell tier exists: `plugins/soleur/test/test-helpers.sh` carries a fail-loud **tripwire** (`exit 97`) over nine git-location variables, sourced by 47 suites. Three entry points already `unset` the same nine. What does not exist is a shell *scrub helper* — and the #7833 plan cut that deliberately. |
| jq rc 5 and rc 0 both fall through the same `else` | **Holds, and understates it** | The return code is never read at all. See R6. |
| `rule-metrics-aggregate.sh` exits non-zero after writing | **Holds; the id list has drifted** | Reproduced at exit 5 against a copy of the live log. 12 orphan ids now, not the 7 the issue lists. |
| ADR-194 cleanup and the ship Incident-PIR gate are out of scope | **Respected** | Neither is touched, planned, or referenced as work. |

Cited-mechanism check against the ADR corpus found four binding decisions: **ADR-156** (hook stdin is
model-controlled and untrusted), **ADR-157** (a hook that cannot parse its input asks), **ADR-165**
(posture splits by *reason class*), **ADR-193** (anti-vacuity floor contract), plus **ADR-091**
(rule metrics have a local producer). The merged plan
`knowledge-base/project/plans/archive/20260904-163540-2026-09-04-fix-test-fixture-git-env-scrub-plan.md`
is the governing prior art for the #7822 half.

### Property List (Phase 0.6b)

- **P1** A shell fixture's `git` write lands in the fixture repository, never in the caller's.
- **P2** A case that asserts "there is no repository here" observes the absence of a repository.
- **P3** Containment adoption does not regress: the uncovered set never grows.
- **P4** Containment is demonstrable under a hostile environment, not merely believed.
- **P5** When a hook's guards are disarmed, the record names the cause and its owner.
- **P6** When a contracted field has the wrong JSON type, the record names the shape, never content.
- **P7** A hook gating a destructive or infrastructure operation does not silently skip its guards.
- **P8** A non-zero `hook_self_fault` count over a window reaches someone.
- **P9** The aggregator writes its metric without leaving a rejected artifact behind.

### Cut List (Phase 0.6b)

| Proposed mechanism | Property | Disposition |
|---|---|---|
| `env -u GIT_DIR … -u GIT_OBJECT_DIRECTORY`, as literally specified in #7822 | P1 | **CUT.** A six-name list, where the repository already deploys a **nine**-name list at all three entry points (`scripts/test-all.sh:232`). Adopting it verbatim would *reduce* coverage — it omits `GIT_TEMPLATE_DIR`, and `git-fixture-env.ts` records a measurement showing an inherited `GIT_TEMPLATE_DIR` makes `git init` copy a hook that the fixture's own commit then **executes**. |
| A canonical shell `git-fixture-env.sh` body | P1 | **CUT — already cut upstream**, by name, in the #7833 plan: *"`test-all.sh` + the tripwire already cover every shell suite; a second byte-for-byte canonical body beside `assert_fixture_dir()` is the drift this plan exists to end."* Not reversed here. |
| A lint over every test file that spawns git | P3 | **CUT as scoped.** The same plan cut the file-scale design in favour of guarding entry points: *"26 `run:` lines … plus 2 files under `scripts/hooks/` … against ~900 files for the cut design."* |
| A **per-file** containment guard over "shell suites that create a git fixture" | P3 | **CUT — unsound, not merely redundant.** Three reasons, from the CTO review: (i) its verdict would conflate two different properties, since the tripwire *aborts* rather than contains, and a guard certifying "contained **or** refuses to run" certifies neither; (ii) its assembly would be a regex heuristic wearing ADR-193's clothes — two defensible predicates over the same property returned 41 and 66 members, and the wider one conscripts non-test scripts such as `scripts/learning-retrieval-bench.sh`; (iii) every recorded recurrence (#1090, 2026-04-03 ×2, #7833) entered through an **entry point**, never a test file, so it would guard a class with zero incidents. Replaced by the ratchet below. |
| A **monotone adoption ratchet** on the uncovered count | P3 | **KEEP.** One committed integer, asserted non-increasing. Stable under predicate drift — a drifting predicate moves both sides of the comparison — with no per-file verdict and no false conscription. |
| Repo-wide conversion of 25–39 suites | P1 | **CUT — belongs to #7849**, and a sweep of near-identical diffs is the rubber-stamp review #7849 gave as its own reason (c) for deferring. |
| Tripwire adoption for the suites inside #7849's *named exit condition* | P1, P3 | **KEEP — measured at 3 files.** See below. |
| Positive non-repo preconditions in the vacuity cases | P2 | **KEEP.** No layer covers this: an env scrub only makes those cases accidentally-green-for-the-right-reason. The assertion must evidence its own premise. |
| A shell regression test under a hostile env | P4 | **KEEP.** Guard 1 does this for TS only. |
| Capture the `HOOK_INPUT_REASON` value | P5 | **KEEP — but the prerequisite is repairing the discriminator**, which no proposal names. |
| Record the JSON *type* of each field | P6 | **KEEP; a conformance gap, not a new decision.** ADR-157 already decided it: *"Telemetry carries no payload content. Field name, JSON type, and length."* |
| A new incident-row field for the type vector | P6 | **CUT.** `hook_input_report` already computes `reason_key="${reason%%:*}"` so "an `internal:<jq stderr>` detail stays out of the aggregation key". The channel exists, is commented, and is unused. |
| Unconditional `hook_input_should_ask` for destructive hooks | P7 | **KEEP as a decision, re-axed onto the reason class** per ADR-165. |
| A new escalation channel | P8 | **CUT.** `summary.hook_input_fault_count` and its `WARNING:` line already exist. The gap is a consumer. |
| A new `AGENTS.md` rule | — | **CUT, and it cannot land.** `scripts/lint-agents-rule-budget.py` reports `B_ALWAYS=46000 >= 44000` — at the ratchet. |

### The sweep is #7849's own exit condition, and it is three files

The brief framed the sweep as residual work on #7822. It is not: it is the *named exit condition*
of issue #7849, whose re-evaluation trigger 2 reads, verbatim:

> **The fixture helpers are consolidated so scrubbing happens in exactly one place** — e.g. if
> `plugins/soleur/test/*.test.sh` reaches full `test-helpers.sh` adoption (measured 2026-09-04:
> 41 of 73 suites source it). At that point Guard 3's shell arm becomes a true chokepoint and this
> issue can be closed as unnecessary.

Measured today: **81** suites match that glob and **47** source `test-helpers.sh` — adoption has
risen from 41/73. Of the 34 that do not, exactly **three** create a git fixture *and* issue a git
write verb:

- `plugins/soleur/test/gitleaks-merge-commit.test.sh`
- `plugins/soleur/test/harvest-debt.test.sh`
- `plugins/soleur/test/roadmap-reconcile.test.sh`

That is the whole mechanical sweep this plan owes. Everything wider stays with #7849, with the
measured counts written into it.

### Value-Proposition Measurement (Phase 0.6c)

Correctness, not cost, so this gate does not bind. The number worth pinning is the **ratchet
baseline**, because it is the artifact that must not drift: the count of `plugins/soleur/test/*.test.sh`
suites that create a git fixture, issue a git write verb, and carry neither the tripwire nor a
prefix scrub. Measured **3** today, and the ratchet asserts it never rises.

### Applicable institutional learnings

- `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
  — the original #1454 discovery. **Exclusion by prefix, never a name list.**
- `knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md`
  — reclassifies the class to `data_loss/high`: *"the helper that must be re-derived per file will
  eventually be re-derived wrongly, and prose does not stop that."*
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md`
  — a floor reports via `printf >&2` + `exit 1` directly, never through the suite's own verdict
  helpers; the population is **derived, never listed**. Binding on Guard 5 and the ratchet.
- `knowledge-base/engineering/operations/post-mortems/fixture-git-env-live-repo-write-postmortem.md`
  — the incident record for the branch-tip rewrite.

### Related issues and PRs

`#7822`, `#7835` (sibling, open, better measured), `#7849` (open; owns the wider sweep, and this plan
advances its exit condition rather than pre-empting it), `#7833` (closed by the merged plan that
built the current layering), `#7275`, `#7164` (shipped the detector), `#7942` (open code-review; see
§Open Code-Review Overlap).

## Research Reconciliation — Spec vs. Codebase

| Claim (from the issues / the brief) | Codebase reality | Plan response |
|---|---|---|
| **R1.** #7822 lists 10 of "~25" shell suites. | Two defensible predicates over the same property return **41** and **66** members. The spread is the finding: no per-file predicate here is canonical. | Report both readings. Do not build a guard whose verdict depends on which predicate is chosen. |
| **R2.** "The shell half is untouched." | A tripwire (47 suites) and three entry-point scrubs exist. | Reframe from "build the shell half" to "advance the adoption that is already underway". |
| **R3.** The shell scrub wrapper is the suggested fix. | The #7833 plan **cut** exactly that, by name. | Do not build it. |
| **R4.** A lint over test files is the only thing that stops recurrence. | The chosen mechanism guards **entry points**; every recorded recurrence entered through one. | Ship a non-increasing adoption ratchet, not a per-file lint. |
| **R5.** The TS half is done. | Two of the eight files #7835 names are converted; twelve TS test files still create a git fixture with no `gitFixtureEnv`. | **Acknowledge, do not fold in.** #7849 owns this; recorded so it is not silently dropped (AC15). |
| **R6.** The jq classifier collapses rc 5 and rc 0. | It never reads a return code. `raw="$( … \| jq … ; printf 'X')"` then `jq_rc=${PIPESTATUS[1]:-0}`: the pipeline runs in a subshell, the parent's `PIPESTATUS` is `(0)` with length 1, so `jq_rc` is **always 0** and the `jq_rc == 3` arm is unreachable. Measured on bash 5.3.9 / jq 1.8.1; independently re-derived at CTO review. | Repair the discriminator **first and alone**; the split is inert without it. |
| **R7.** jq rc 5 means the document is invalid. | Confirmed directly: `''`→0, `garbage {{`→5, `{"a":"x"`→5, `[1,2,3]`→5, compile error→3. | Map rc 0-with-no-output → `empty`, rc 5 → `baddoc`, rc 3 → `internal`. |
| **R8.** The 7 faults/day are current. | **Zero** `hook_self_fault` rows exist in the retained log or either archive; the 2026-08 archive is not retained. | Do not claim a rate. The fix is forward-looking, and the evidence loss is itself an argument for P8. |
| **R9.** The orphan gate lists 7 ids. | **12** now. Seven are hook-emitted, three are rule-shaped and in no registry, and `scripts/retired-rule-ids.txt` is **not consulted** by the aggregator. | Fix the gate's notion of *known*, not the list — which drifts by construction. Deferred; see §Deferral. |
| **R10.** The gate's harm is a rejected aggregate in the tree. | It also short-circuits **before rotation**, so an orphan starves rotation of the shared telemetry sink — plausibly contributing to R8. | Carry into the deferred issue as part of the defect. |
| **R11.** `hook_self_fault` comes from `hook-input.sh`. | Also `context-reviewed-gate.sh`, `grep-rewrite.sh` and `prod-write-defer-gate.sh` — the last **denies** (fail-closed). | The consumer must count the `kind`, not the `hook-input-` prefix. The `prod-write-defer-gate` precedent is evidence for §Architecture Decision. |
| **R12.** Splitting the enum needs an aggregator change. | **Measured false.** A log containing only `hook-input-empty` and `hook-input-baddoc` runs to exit 0 with `orphan_rule_ids == []` and `hook_input_fault_count == 2`, and the existing WARNING line already renders `[empty=1 baddoc=1]`. | No aggregator edit for the split. The diagnostic surface appears for free. |
| **R13.** The C4 count-parity suite is missing. | It exists at `plugins/soleur/test/c4-count-parity.test.sh` — the earlier `apps/web-platform/test/` path was wrong. | Path resolved at plan time; no lookup handed to `/work`. |

## Open Code-Review Overlap

**#7942** — *"Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run in no
gate"* — matches `scripts/test-all.sh` in this plan's edit list. The batteries are
`git-fixture-env.mutation.sh` and `hook-git-env-coverage.mutation.sh`: the batteries for the guards
this work builds behind.

**Disposition: fold in.** This plan adds a mutation battery of its own, and ADR-193 requires one.
Shipping it into the same ungated hole would reproduce the defect being closed, and Guard 5's
contract would be unverified. `Closes #7942` joins PR 3's body. Verified: `SUITE_GLOBS` carries
`plugins/soleur/test/*.test.sh` (`scripts/test-all.sh:78`), which is why `.test.sh` files need no
registration and `*.mutation.sh` — which does not match that glob — is exactly the hole.

No other open code-review issue matches any planned path.

## User-Brand Impact

**If this lands broken, the user experiences:** a `git commit` that silently rewrites their branch
tip and truncates their index — the damage recorded in
`knowledge-base/engineering/operations/post-mortems/fixture-git-env-live-repo-write-postmortem.md`
(16 stray commits, index cut from ~14,000 entries to 2) — or, from the riskier half, a corrupted
`HOOK_FILE_PATH` in the library every PreToolUse hook parses through, which would misroute or
silently disarm guards on every Bash tool call.

**If this leaks, the user's workflow is exposed via:** the type vector written to
`.claude/.rule-incidents.jsonl` and rolled into the committed `rule-metrics.json`. Hook stdin is
model-controlled and may carry credentials in a `Bash` command string. The vector carries **only**
members of jq's closed type set (`string`, `number`, `boolean`, `array`, `object`, `null`) — never a
value, and never a length that could act as an oracle. Enforced structurally, since the jq program
emits bad-path values empty by construction, and asserted by AC13.

**Brand-survival threshold:** single-user incident

CPO sign-off is required at plan time before `/work` begins; `user-impact-reviewer` is invoked at
review time.

## Delivery shape — three PRs

The riskiest change is small and sits under everything else, so it ships alone. This is the CTO
review's recommendation, adopted.

| PR | Contents | Risk |
|---|---|---|
| **1** | Phase B1 only — repair the discriminator, plus the byte-exactness and static-compile assertions. | **High.** The library is sourced by ~30 hooks, ~19 firing per Bash tool call. |
| **2** | Phases B2–B4: the enum split, the type vector, the ask posture, the new ADR + ADR-157 errata + ADR-165 row split, hooks README, the C4 sentence. `Closes #7275`. | Medium |
| **3** | Phases A1–A4: vacuity repairs, the three-file tripwire adoption, the ratchet, the shell regression test, mutation-battery registration. `Closes #7822 #7835 #7942`. | Low |

`hook-input.sh` is why PR 1 is alone: ADR-157's own core argument is that a persistent fault there is
unrecoverable *because the repair is itself a Bash call*. That argument applies to this change.

## Implementation Phases

### Phase 0 — preconditions (measure; do not assume)

1. Re-run the `PIPESTATUS`-through-command-substitution probe and paste the table into PR 1. If
   `jq_rc` is not always 0 on the machine of record, **stop**: R6 has not reproduced.
2. Re-run the jq return-code table against the installed jq and paste it.
3. Re-derive the ratchet baseline (currently 3) and the `plugins/soleur/test/*.test.sh` adoption
   count (currently 47/81). If either has moved, the sweep list and the baseline move with it.
4. Re-run the aggregator against a **copy** of the live log under `INCIDENTS_REPO_ROOT` and record
   the exit code and orphan list. Never against the real repo root — it writes before it rejects.
5. Confirm #7849, #7942 and #7835 are still open.

### Phase B1 — repair the discriminator (PR 1, alone)

`jq_rc` is always 0. Capture the return code **inside** the command substitution and carry it out in
the captured text, preserving the trailing-separator/sentinel pair the file documents as load-bearing.
No temporary file: the file rejects one on the hot path, and that reasoning stands.

**Use `$?`, not `PIPESTATUS`, inside the substitution.** jq is the last element of the pipeline, so
`$?` after it *is* jq's status. `PIPESTATUS[1]` would work today but encodes a positional invariant
that breaks silently the day anyone appends a filter.

**The return code is subordinate to the slot count.** A payload value containing U+001E emits a
**raw RS byte** through jq — reproduced at consult, where a two-slot program produced four separators
— so anything appended after the last separator is forgeable by the payload. The fix is precedence,
not escaping:

1. Strip the sentinel, split on RS, and **check the slot count first**.
2. Count correct → success. The return code is 0 by construction and is never read.
3. Count wrong → only now read the trailing digits as the return code, requiring `^[0-9]+$`.

A forged RS byte can then only break the count, which is *already* a fault (`separator`), and can
never make a real failure look like success. This preserves the file's correct statement that the
slot count — not jq's exit code — is the normative parse-failure detector.

**The corruption hazard this phase must not ship.** If the return code lands on the wrong side of the
sentinel it appends to `_hi_s[5]`, i.e. `HOOK_FILE_PATH`. The record count stays exactly 6, so a
slot-count assertion **passes while every hook's `HOOK_FILE_PATH` is silently corrupted on the happy
path**. AC5 exists solely to close this, and it is why PR 1 ships alone.

Replace the comment *"jq's EXIT CODE already makes the only distinction that matters"*: it is the
artifact that let the dead branch survive review for the life of the file.

### Phase B2 — split the reason enum (PR 2)

| Condition | Reason | Owner | Reachable in production? |
|---|---|---|---|
| rc 0, no output | `empty` | the caller sent nothing | **yes** |
| rc 5 | `baddoc` | the payload is not valid JSON | **yes** |
| rc 3 | `internal` | our program failed to compile | **no — by construction** |
| any other non-zero | `internal` | never blamed on the payload | only under a broken jq |

**`internal` ships as a documented defensive default, not as a peer the suite pretends to exercise.**
rc 3 is a jq *compile* error, and with one constant program plus the exactly-one-`jq` contract
assertion, no production input reaches it. Asserting it as a reachable runtime member would reproduce
the dead-code shape this work removes. It is exercised only in the mutation battery, which breaks the
program deliberately.

**Add a static compile assertion regardless** — a contract-test case asserting `_HOOK_INPUT_JQ`
compiles. A compile failure is a build-time property of a constant program, and catching it once in
CI is strictly better than discovering it once per production session. It is the only thing that
catches `internal` before it ships.

Rule ids become `hook-input-empty` / `hook-input-baddoc`. **Measured:** a log containing only those
two runs the aggregator to exit 0 with `orphan_rule_ids == []` and `hook_input_fault_count == 2`, and
the existing WARNING line already renders the split:

```
WARNING: 2 PreToolUse hook input-contract fault(s) — a hook could not parse its stdin
and ran with guards disarmed [empty=1 baddoc=1].
```

No aggregator edit is required, and the diagnostic surface #7275 asks for appears for free.

### Phase B3 — the type vector (ADR-157 conformance, PR 2)

Extend the single jq program so the status token carries the shape on the bad path — `ok`, or
`bad:<type>,<type>,<type>,<type>,<type>` over the five contracted slots. The record count stays at
exactly **6**, so the slot-count detector, the field-order contract and the exactly-one-`jq`
assertion are untouched.

The vector rides into telemetry through the existing detail-suffix channel: `HOOK_INPUT_REASON`
becomes `nonstring:string,array,null,string,null`, `hook_input_report` already strips at the first
colon for the aggregation key, and `command_snippet` already carries the full reason. Types only.

### Phase B4 — the ask posture, decided on the reason axis (PR 2)

Scope unconditional escalation to the intersection of the model-controlled reason classes and the
hooks that gate destructive or infrastructure operations. `jq_missing` is excluded on ADR-157's
self-referential-repair argument; `internal` fails open loudly because it is our bug.

### Phase A1 — the adoption ratchet (PR 3)

Replace the per-file guard with a monotone ratchet: one committed integer recording the number of
`plugins/soleur/test/*.test.sh` suites that create a git fixture, issue a git write verb, and carry
neither the tripwire nor a prefix scrub. The guard asserts the live count is **not greater** than the
baseline, and fails closed if its enumeration yields zero members.

It is stable under predicate drift because a drifting predicate moves both sides of the comparison,
it issues no per-file verdict, and it conscripts nothing.

### Phase A2 — adopt the tripwire in the three measured suites (PR 3)

`gitleaks-merge-commit.test.sh`, `harvest-debt.test.sh`, `roadmap-reconcile.test.sh` — the exact
members of #7849's named exit condition that create a git fixture. Drop the baseline to 0 and record
the new adoption count in #7849.

### Phase A3 — make the vacuity cases prove their own premise (PR 3)

The tripwire prevents the inversion but does not make the assertion self-evidencing; a scrub only
makes these cases accidentally-green-for-the-right-reason. Each case that asserts "no repository
here" gains a positive precondition — `git rev-parse --git-dir` must **fail** in the fixture
directory — before the subject is invoked, so the case fails loudly rather than silently changing
subject.

| Suite | Vacuity |
|---|---|
| `.claude/hooks/guardrails.test.sh` | **whole-suite, and the one that cannot wait.** `decision_of()` runs the hook from a `mktemp -d` CWD precisely so branch resolution comes back empty and the orthogonal block-commit-on-main gate no-ops — isolation added by #5192 after these fixtures passed on a feature branch and failed on main-CI. An inherited `GIT_DIR` restores branch resolution, the isolation is void, and the suite's result becomes branch-dependent again: the exact regression the comment says it prevents. |
| `.claude/hooks/session-rules-loader.test.sh` | four discrete non-repo fixtures (T13, T23, T30, T31) |
| `scripts/check-pa-22.test.sh` | self-documented: *"A sandbox that is not a git repo makes the SUT resolve to the REAL worktree, which would both void the case and read the live corpus."* |
| `scripts/lint-legal-registers.test.sh` | one operand case plus twelve dependent red-arms |
| `scripts/skill-security-scan-step-body.test.sh` | the root-commit arm, where `HEAD^1` would resolve against the caller's real HEAD |
| `apps/web-platform/infra/workspaces-luks-loopback.test.sh` | the `fatal:`-shape fsck arms |

`apps/web-platform/test/ci/service-role-allowlist-gate.test.sh` is a **distinct shape** — it
deliberately mutates the *live* index with `git add -f` and has no fixture repo, so under a hostile
env its cleanup `git rm --cached -f` may not undo what it did. Handle it individually; do not batch it.

### Phase A4 — the shell containment regression test (PR 3)

The shell counterpart of Guard 1: build a victim repository, set a hostile `GIT_DIR` and
`GIT_INDEX_FILE`, drive a swept suite through a **child process** started under that environment,
and assert the victim's HEAD, ref set and staged-file list are unchanged **as a triple**. The triple
is required: with `GIT_DIR` scrubbed, an absolute `GIT_INDEX_FILE` still retargets `git add` while
HEAD stays put.

### Phase A5 — register the mutation batteries (PR 3, closes #7942)

Register every `plugins/soleur/test/*.mutation.sh` into `scripts/test-all.sh`, and assert the
registered set equals the tracked set so the next battery cannot enter the same hole.

## Deferral (`wg-defer-only-after-inline-triage`)

**The `rule-metrics-aggregate.sh` orphan gate (R9, R10) is deferred to a new tracking issue**, filed
in the same pass. Triaged inline, not dropped: it is reproduced, well-diagnosed, and its remedy is
specified below. It is deferred because it belongs to **none** of #7822, #7835 or #7275 — it is a
different subsystem, reworking its notion of "known" is the fiddliest work in the plan, and it is the
change most likely to mask a real orphan if rushed alongside a hook-library repair.

The issue must carry: reject **before** the write (today it writes, then exits 5, then never reaches
rotation — so an orphan starves rotation of the shared telemetry sink); derive "known" from the
three authorities rather than an accreting per-prefix allowlist (`AGENTS.md` ids, plus
`scripts/retired-rule-ids.txt` which the aggregator does not consult at all, plus hook-declared ids);
preserve the documented load-bearing pair, whereby an exclusion that removes an id from
`orphan_rule_ids` must not remove its only readout; and the 12 measured orphan ids.

**Phase B6 (consume the signal) is deferred with it, and its design must change.** As a hard CI gate
it is unclearable by CI: ADR-091 makes the producer local, so any contributor whose local hooks
faulted once commits a red metric and `main` stays red until someone runs `/compound` locally. It
must be a threshold-and-delta signal that files an issue, or it must name who clears it and how.
Recording this now prevents it being built the wrong way later.

## Files to Create

| Path | Why |
|---|---|
| `plugins/soleur/test/shell-fixture-containment.test.sh` | Phase A1's ratchet, and Phase A4's hostile-environment regression case. |
| `.claude/hooks/lib/hook-input-classification.mutation.sh` | Guard 5's mutation battery, driving the real `hook_parse_input`. |

## Files to Edit

| Path | Why |
|---|---|
| `.claude/hooks/lib/hook-input.sh` | B1–B4. |
| `.claude/hooks/hook-input-contract.test.sh` | Guard 5's assertions; byte-exactness; the static compile assertion. |
| `.claude/hooks/README.md` | The reason enum and the posture table. |
| `scripts/test-all.sh` | A5: register every `*.mutation.sh`. **The new `.test.sh` needs no registration** — `SUITE_GLOBS` already carries `plugins/soleur/test/*.test.sh` (`scripts/test-all.sh:78`), and the array's own comment warns that a second copy of the list is the mutation it exists to catch. `*.mutation.sh` does not match that glob, which is precisely #7942. |
| `plugins/soleur/test/{gitleaks-merge-commit,harvest-debt,roadmap-reconcile}.test.sh` | A2: adopt the tripwire. |
| The six vacuity-bearing suites listed in A3, plus `service-role-allowlist-gate.test.sh` individually | A3. |
| `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md` | **Errata only** — correct its factual claim that the exit-code distinction is made. |
| `knowledge-base/engineering/architecture/decisions/ADR-165-what-ask-means-on-a-harness-with-no-ask-state.md` | The `unparseable` row splits into `empty` and `baddoc`. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | The `hooks` container description asserts a uniform ADR-157 posture that B4 falsifies. |

`plugins/soleur/test/test-helpers.sh`, `lefthook.yml`, `scripts/hooks/pre-push`,
`plugins/soleur/test/lib/git-fixture-env.ts` and `scripts/rule-metrics-aggregate.sh` are **not**
edited: the first four are prior art this plan builds behind, and the fifth is deferred above.

## Acceptance Criteria

### Pre-merge — PR 1 (B1)

1. **AC1 (the discriminator is real, driven through stdin).** Two cases injected as *stdin*, not by
   stubbing jq — the exactly-one-`jq` contract forbids a second invocation, so the fault must be
   induced at the payload: empty stdin observes rc 0, a truncated document (`{"a":"x"`) observes
   rc 5. **Both must fail against the pre-B1 code**, and the PR body carries before/after readings.
   Shipping B1 without this reproduces the original defect class — a discriminator nobody reads.
2. **AC2 (precedence holds under a forged separator).** A payload whose `tool_input.command` contains
   a literal U+001E yields `separator` — never a success, and never a forged return code. The slot
   count is read before the trailing digits, and the digits are accepted only against `^[0-9]+$`.
3. **AC3 (the slot contract is intact).** The happy path emits exactly 6 records, field order
   unchanged, and the existing exactly-one-`jq` assertion still passes.
4. **AC4 (the static compile assertion exists).** A contract-test case asserts `_HOOK_INPUT_JQ`
   compiles, and fails when a token in it is broken.
5. **AC5 (byte-exactness — the corruption gate).** For a fixed happy-path envelope, all five of
   `HOOK_CMD`, `HOOK_TOOL_NAME`, `HOOK_CWD`, `HOOK_SESSION_ID` and `HOOK_FILE_PATH` are
   byte-identical pre- and post-B1, **including a value with a trailing newline and a value ending
   in the literal `X`**. The `X` case is the one a naive `${raw%X}` strip breaks, and AC3 cannot see
   this failure because the record count stays 6.

### Pre-merge — PR 2 (B2–B4)

6. **AC6 (the enum splits on the reachable members).** Empty stdin yields `empty`; `garbage {{`
   yields `baddoc`; the two are distinguishable by `rule_id`. `internal` is asserted only in the
   mutation battery.
7. **AC7 (no reason is unclassified).** Every producible `HOOK_INPUT_REASON` is a member of the
   documented enum; a value outside it fails the contract test.
8. **AC8 (the type vector names the shape).** An array `tool_input.command` yields a reason whose
   detail suffix names `array` in slot 1, and `rule_id` remains `hook-input-nonstring`.
9. **AC9 (the aggregator is undisturbed).** A log carrying the new ids runs to exit 0 with
   `orphan_rule_ids == []`, and the WARNING line renders the per-reason breakdown.
10. **AC10 (the decision is recorded).** A new ADR exists declaring `Extends: ADR-156, ADR-157,
    ADR-165` and `Supersedes: nothing`; ADR-157 carries an errata note only; ADR-165's `unparseable`
    row is split. The ordinal is re-verified against every `origin/*` ref immediately before merge.

### Pre-merge — PR 3 (A1–A5)

11. **AC11 (the ratchet holds and is not vacuous).** The guard reports its examined count, asserts
    the uncovered count is not greater than the committed baseline, and **fails closed when its
    enumeration yields zero members**.
12. **AC12 (the sweep is complete against its own predicate).** The three named suites source
    `test-helpers.sh`, and the baseline is updated to the new measured value in the same commit. The
    predicate is pinned in the guard, so the count is falsifiable rather than a claim.
13. **AC13 (types, never content).** A payload whose `tool_input.command` is
    `["curl","-H","Authorization: Bearer sk-LEAKCANARY"]` produces no occurrence of `LEAKCANARY`
    anywhere in `.rule-incidents.jsonl`, stdout or stderr, while the reason still names `array`.
    (Verified in PR 2's battery and re-asserted here against the committed metric.)
14. **AC14 (containment is demonstrated).** The A4 regression test drives a swept suite under a
    hostile `GIT_DIR` + `GIT_INDEX_FILE` and the victim's HEAD, refs and staged list are unchanged.
15. **AC15 (vacuity is repaired).** Each named case asserts non-repo-ness as a precondition and fails
    when that precondition does not hold. `guardrails.test.sh` is included.
16. **AC16 (the batteries run).** Every tracked `plugins/soleur/test/*.mutation.sh` is reached by
    `scripts/test-all.sh`, and the registered set equals the tracked set.
17. **AC17 (deferrals stay owned).** #7849 remains open and carries the updated adoption count and
    the twelve measured TS files; the new orphan-gate issue exists and carries R9, R10 and the B6
    design note; #7835 is closed only if its shell half is met, with its TS half re-pointed at #7849.
18. **AC18 (no rule-budget regression).** `scripts/lint-agents-rule-budget.py` reports a `B_ALWAYS`
    no larger than the pre-change reading. No new rule is added.

### Post-merge (operator)

None. Every criterion is verifiable in-session or in CI. The rate signal in R8 cannot be re-measured
until faults recur; that is what the deferred consumer exists to surface, and it is not an operator
step.

## Guard Contract

### Guard 4 — shell containment adoption ratchet

**Property.** The number of `plugins/soleur/test/*.test.sh` suites that create a git fixture, issue a
git write verb, and carry neither the tripwire nor a prefix scrub never rises above a committed
baseline.

**Assembly.** The comparison, not a per-file verdict. Both sides are computed by the *same*
enumeration in the *same* run, which is what makes the guard stable under predicate drift: a
predicate that widens moves the live count and the baseline together, and only a genuine regression
separates them. The chokepoint is that single enumeration; there is exactly one, and the guard fails
closed if it yields zero members.

**Mutation matrix.**

| # | Mutation | Must redden because |
|---|---|---|
| M1 | Remove `test-helpers.sh` from one swept suite | the uncovered count rises above the baseline — the regression the ratchet exists to catch |
| M2 | Add a **new** fixture-creating suite with no containment | the guard must judge members it never saw; a check that stops at the known set is the defect class |
| M3 | Raise the committed baseline without changing any suite | the baseline is a ratchet, not a dial; only a drop may be committed |
| M4 | Make the enumeration return zero members | **the guard's own dispatch** — "0 examined, exit 0" is vacuous |
| M5 | Compare against a hard-coded literal instead of the live enumeration | both sides must come from one enumeration, or drift silently passes |
| M6 | Compute the baseline side *after* the sweep mutates the tree | a ratchet is a property about **order**: the baseline is the committed prior value, and reading it post-mutation makes every regression self-approving. A delete-only battery would never test this |

**Harness rows.**

| # | Edit | Expectation |
|---|---|---|
| H1 | Neuter the suite's verdict helper | the floor must still fail — it reports via `printf >&2` + `exit 1` directly (ADR-193) |
| H2 | Make the enumeration succeed but every predicate return false | conservation (`passes + fails == cases`) fails first |
| H3 | **Must-PASS, non-canonical:** a suite using the inline tripwire copy rather than sourcing `test-helpers.sh` | the contract permits both spellings; a guard accepting only the canonical one rejects everything else |

### Guard 5 — hook-input reason classification

**Property.** For every distinguishable failure of the hook-input parse, the recorded reason names
the cause and attributes it to the correct owner — our program, the caller, or the payload — and the
happy path's five field values are unchanged byte-for-byte.

**Assembly.** Every `return 1` path in `hook_parse_input`, plus the happy path, reached through the
real function rather than a re-implementation. The chokepoint is `hook_parse_input`; the guard drives
it, never a copy of its logic.

**Mutation matrix.**

| # | Mutation | Must redden because |
|---|---|---|
| M1 | Restore `jq_rc=${PIPESTATUS[1]:-0}` after the substitution | this is the shipped defect, and today **nothing** reddens on it — the single most valuable assertion in this plan |
| M2 | Map rc 5 to `internal` | a payload fault attributed to us hides a real payload class |
| M3 | Break a token in `_HOOK_INPUT_JQ` | the static compile assertion must fail, and the runtime reason must be `internal` — never `unparseable` |
| M4 | Emit the field **value** instead of its type in the detail suffix | the secrecy property must never regress |
| M5 | Move the return code to the wrong side of the sentinel | `HOOK_FILE_PATH` gains trailing digits while the record count stays 6 — the corruption AC3 cannot see |
| M6 | Return 0 records but exit before assigning a reason | **the guard's own dispatch** — an unset reason must not read as a pass |

**Harness rows.**

| # | Edit | Expectation |
|---|---|---|
| H1 | Replace the driver's call to `hook_parse_input` with a stub returning a canned reason | must redden: the guard must exercise the real function |
| H2 | Assert only on the reason **head**, ignoring the detail suffix | must redden: M4 and the type-vector loss both survive a head-only assertion |
| H3 | **Must-PASS, non-canonical:** a valid envelope with a `null` `file_path` and an absent `session_id` | absence and empty are legitimate per ADR-156; the guard must not treat them as faults |

## Observability

```yaml
liveness_signal:
  what: summary.hook_input_fault_count plus its per-reason breakdown in knowledge-base/project/rule-metrics.json
  cadence: every local /compound run (ADR-091 local-producer model)
  alert_target: the aggregator's WARNING line today; a threshold-and-delta consumer in the deferred issue
  configured_in: scripts/rule-metrics-aggregate.sh
error_reporting:
  destination: .claude/.rule-incidents.jsonl (local), rolled into the committed rule-metrics.json
  fail_loud: yes — hook_input_report writes the incident and a stderr line on every fault path
failure_modes:
  - mode: a hook parses nothing and runs with guards disarmed
    detection: an incident row whose rule_id names the split reason (hook-input-empty / -baddoc / -nonstring)
    alert_route: the aggregator WARNING line, which already renders the breakdown (measured)
  - mode: the classifier itself is broken and every fault reads alike
    detection: Guard 5 M1 — the shipped defect drives the guard red
    alert_route: CI, on every PR touching the hook lib
  - mode: the return code corrupts HOOK_FILE_PATH on the happy path
    detection: AC5 byte-exactness, including a value ending in the literal X
    alert_route: CI, PR 1
  - mode: containment adoption regresses
    detection: Guard 4, against a committed baseline
    alert_route: CI, plus lefthook pre-commit via test-all.sh
logs:
  where: .claude/.rule-incidents.jsonl, rotated to .claude/.rule-incidents-YYYY-MM.jsonl.gz
  retention: monthly archives; note R8 — the 2026-08 archive is absent, which is why the August
    evidence for this very issue could not be re-read, and R10 names a mechanism that would explain it
discoverability_test:
  command: bash plugins/soleur/test/c4-count-parity.test.sh
  expected_output: exits 0, reporting count parity between model.c4 and the derived cardinalities
```

The `hook_self_fault` signal is an **observability-layer 7** concern: it originates in the shell hook
surface that executes on a contributor's own machine, where no server-side telemetry reaches. The
committed metric is the only channel crossing that boundary, which is why the deferred consumer reads
the committed artifact rather than adding a remote sink.

## Architecture Decision (ADR/C4)

### ADR

**Write a new ADR that extends; do not amend ADR-157 in place.** The repository's precedent for
exactly this move is ADR-165, which narrowed ADR-157's posture on the reason-class axis and did it as
a new record declaring `Extends: ADR-156, ADR-157` / `Supersedes: nothing`. ADR-156 itself carries
that it "must never be superseded, it may be extended." Editing an Accepted ADR's decision in place
destroys the record of what was decided, when, and on what evidence.

The split:

- **New ADR (Extends ADR-156, ADR-157, ADR-165).** Reason-class-scoped unconditional escalation for
  hooks gating destructive or infrastructure operations, with `jq_missing` excluded on ADR-157's
  self-referential-repair argument and `internal` failing open loudly because it is our bug. It cites
  `prod-write-defer-gate.sh` — which already emits `hook_self_fault` and **denies** — as an existing,
  unrecorded narrowing of the blanket rejection.
- **Errata on ADR-157 only.** Correct its factual claim that the exit-code distinction is being made.
  A correction, not a decision change, and it belongs in place.

**An ordinal is therefore claimed, and the collision class does apply.** ADR-157's own header records
a 156→157 renumber from exactly this collision. Enumerate across every `origin/*` ref — not
`origin/main` — and **re-run the probe immediately before merge**. When renumbering, sweep this
plan, `tasks.md` and any AC naming the ordinal in the same edit.

### C4 views

Checked against all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.

**Enumeration performed.** External human actors: none added or changed — no correspondent, reviewer
or recipient enters the system. External systems/vendors: none — no inbound webhook, outbound API or
third-party store. Containers and data stores touched: the `hooks` container ("Hook Engine") and the
local incidents log, both already modelled. Actor↔surface access relationships: unchanged; no
ownership or sharing boundary moves.

**One edit is required, and it is a correctness fix rather than an addition.** The `hooks` container
description asserts the ADR-157 posture as uniform and confines the split-by-reason-class to the
`.openhands` side. Phase B4 makes the split apply on the `.claude` side too, falsifying that
sentence.

**Cardinality parity.** This change adds no monitor, workflow or heartbeat, so it moves no derived
cardinality — but that is asserted, not assumed, by running `plugins/soleur/test/c4-count-parity.test.sh`
(located at plan time; the earlier `apps/web-platform/test/` path was wrong) and requiring it green.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO review independently re-derived the `jq_rc` defect and confirmed it, and
materially reshaped the plan. It cut the per-file containment guard as unsound — the tripwire aborts
rather than contains, so a guard certifying "contained or refuses to run" certifies neither; its
assembly would be a regex heuristic, evidenced by two defensible predicates returning 41 and 66
members; and every recorded recurrence entered through an entry point, not a test file. It replaced
that with the adoption ratchet. It found the `HOOK_FILE_PATH` corruption hole that a slot-count
assertion cannot see (now AC5), required the B1 split, corrected the ADR strategy from in-place
amendment to a new extending record, and identified that the deferred CI consumer would be unclearable
by CI under ADR-091's local-producer model. It also corrected the brief's framing: the sweep is the
named exit condition of #7849 rather than a violation of its deferral. All findings are adopted.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit`
matches no path under `components/**`, `app/**/page.tsx` or `app/**/layout.tsx`. Tier: NONE.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| B1 changes the parse path in a library sourced by ~30 hooks, ~19 firing per Bash tool call, where a persistent fault is unrecoverable because the repair is itself a Bash call. | B1 ships **alone** as PR 1, with AC5's byte-exactness gate — including the value ending in `X` — and the full contract battery green before anything else is touched. |
| The return code lands on the wrong side of the sentinel and corrupts `HOOK_FILE_PATH` while the record count stays 6. | Exactly AC5. This is the failure a slot-count assertion structurally cannot see, and it is why the byte-exactness case names the `X`-terminated value. |
| A payload forges an RS byte and manufactures a return code. | Precedence: the slot count is read first, and a forged separator can only produce `separator`, which is already a fault. Asserted by AC2. |
| Shipping `internal` as a peer enum member reproduces the dead-code shape being removed. | It ships as a documented defensive default, exercised only in the mutation battery, with a static compile assertion catching the real condition at build time. |
| A containment guard over a drifting per-file predicate conscripts unrelated scripts and ratchets an unstable number into CI. | The ratchet compares two counts from one enumeration; drift moves both sides. No per-file verdict is issued. |
| Splitting the reason enum could orphan new rule ids. | **Measured false** (R12): exit 0, `orphan_rule_ids == []`, breakdown rendered. Re-asserted by AC9. |
| #7822, #7835 and #7849 overlap; closing the wrong one loses the TS residual. | AC17 makes each disposition explicit and writes the measured counts into #7849 rather than leaving them implied. |
| The orphan-gate rework could mask a real orphan. | Deferred to its own issue with its remedy specified, rather than rushed alongside a hook-library repair. |
| The plan cannot demonstrate the 7-faults/day rate. | Stated as R8 rather than papered over, and kept visible in the PR body because #7275's title asserts it. |

## Test Scenarios

Every scenario is of the shape *mutation → guard reddens*, because the deliverable is guards.

1. Restore `jq_rc=${PIPESTATUS[1]:-0}` after the substitution → Guard 5 M1 reddens.
2. Move the return code to the wrong side of the sentinel → Guard 5 M5 reddens on a happy-path
   envelope whose `file_path` ends in `X`, while the record count stays 6.
3. Break a token in `_HOOK_INPUT_JQ` → the static compile assertion fails and the runtime reason is
   `internal`, not `unparseable`.
4. Feed empty stdin → `empty`; feed `garbage {{` → `baddoc`; the two produce different `rule_id`s.
5. Feed a `tool_input.command` value containing a literal U+001E → `separator`, never a success.
6. Feed an array `tool_input.command` carrying a canary secret → the reason names `array`, and the
   canary appears in no output or log.
7. Remove `test-helpers.sh` from a swept suite → Guard 4 M1 reddens.
8. Raise the committed baseline with no suite change → Guard 4 M3 reddens.
9. Make Guard 4's enumeration return zero members → Guard 4 M4 reddens rather than exiting 0.
10. Drive a swept suite under hostile `GIT_DIR` + `GIT_INDEX_FILE` → the victim's HEAD, refs and
    staged list are unchanged as a triple.
11. Run `guardrails.test.sh` under a hostile env → it aborts on the tripwire rather than silently
    restoring branch resolution and voiding its own isolation.
12. Remove a `*.mutation.sh` from the runner registration → the A5 assertion reddens.
