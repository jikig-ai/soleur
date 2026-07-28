---
title: "fix: close three checks that cannot report — fail-open tfplan gates, a deadlocked linter, and SIGPIPE-decided assertions"
date: 2026-07-28
type: fix
lane: cross-domain
issues: [6997, 7002, 7024]
refs: [7005, 6992]
branch: feat-one-shot-6997-7002-7024-gate-preamble-actionlint-sigpipe
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
revision: v3 (post six-agent plan-review — see § Plan-Review Revisions)
---

# fix: close three checks that cannot report

`Closes #6997` · `Closes #7002` · `Closes #7024`

## Overview

Three defects, one shape: **a check that cannot report is indistinguishable from one that passed.**

- **#6997** — nine tfplan gates authorizing *destructive* production infrastructure operations cannot
  classify a degraded `terraform show -json`. The measured hole: an entry with `"actions": []` is invisible
  to **every** arm at once, so a real `hcloud_server.web["web-1"]` destroy scored `destroys=0` and **PASSED**.
- **#7002** — `actionlint` deadlocks and never returns on one workflow, so the repo's only workflow linter
  reports nothing at all.
- **#7024** — assertions whose exit status can be decided by SIGPIPE rather than by the thing they assert.

The real change is small: **two lines added to nine shell functions, one file moved, sixteen piped
`grep -q` converted, and two guards that reuse machinery already in the tree.**

*No `spec.md` exists for this branch (one-shot entered at plan, no brainstorm), so there is no `lane:` to
carry forward — defaulted to `cross-domain` (TR2 fail-closed).* All scope is shell / CI / test / docs.
**No product code.**

> **Read § Plan-Review Revisions before implementing.** Six reviewers falsified **five** of v1's premises,
> including two of its three "RED-first" claims and the derivation command the ADR publishes. Those are
> corrected below rather than quietly edited, because asserting an unmeasured property is this plan's own
> defect class.

---

## Verified Facts

Measured in this worktree at HEAD. **Corrections to earlier revisions are flagged, not silently fixed.**

### V1 — the fail-open set (#6997)

```bash
grep -l "local plan_json" tests/scripts/lib/*gate*.sh | xargs -r grep -LE '^\s*plan_gate_assert_readable'
```

Returns **11**. Twelve gates grade a plan document; `git-data-host-birth-gate.sh` is already on the preamble.

> **Two corrections to the command the ADR and the preamble header currently publish.**
>
> 1. **`xargs -r` is load-bearing.** Without it, an empty first stage leaves `grep -L` with no operands so it
>    **reads stdin** — measured: `printf '' | xargs grep -L PAT` printed `(standard input)` and exited 0. A
>    broken glob would hang or report clean: #7002's hang shape and #6997's vacuity shape, in the derivation
>    command for both.
> 2. **`grep -L plan_gate_assert_readable` GOES VACUOUS the moment this PR lands.** The Phase 3.2 guarded
>    source contains the literal string `if ! declare -F plan_gate_assert_readable`, which alone satisfies
>    `grep -L`. Verified on the already-retrofitted reference: `git-data-host-birth-gate.sh` contains
>    `plan_gate_assert_readable` **twice** — at `:73` (the guard) and `:120` (the actual call). **A gate that
>    sources the preamble and never calls it would pass.** Every use must anchor on the **call form**
>    `-E '^\s*plan_gate_assert_readable'`, which `if ! declare -F …` does not match. This is the plan's own
>    sourced-vs-invoked spine, violated in the command that polices it — Phase 5 fixes both published copies.

**Tier 1 — eight gates with no readability/classifiability check:** `git-data-host-replace`,
`inngest-host-replace`, `registry-host-replace`, `registry-luks-recut`, `registry-region-migrate`,
`web2-retire`, `workspaces-luks-cutover`, `workspaces-luks-recut`.

### V2 — what the retrofit actually buys (CORRECTED — v1's D1/D2 premise was FALSE)

**Every Tier-1 gate already aborts on a missing file and on unparseable JSON.** Measured against the
*unmodified* gates:

```
inngest_host_replace_gate  <missing>  → rc=1  "plan JSON not found: …"
registry_host_replace_gate <missing>  → rc=1  "plan JSON not found: …"
workspaces_luks_recut_gate <missing>  → rc=1  "plan JSON not found: …"
web2_retire_gate           <missing>  → rc=1  "plan JSON not found: …"
```

So **D1/D2 are not fail-open, and cannot be driven RED pre-retrofit.** v1 asserted they were and required
every arm RED — which would have halted Phase 3 on its first gate. Further, replace-style gates also fail
closed on `resource_changes: null`, because their verdict needs a *positive* count
(`inngest_server_replaced=1`) that a degraded plan cannot supply. The `null`-is-fail-open shape only bites
gates whose entire verdict is "count of bad things == 0".

**What the retrofit genuinely closes** is therefore narrower and must be stated honestly:
- **D5** — an entry with `"actions": []`, invisible to `any(…)` **and** `index("delete")` simultaneously.
  This is the **measured** hole (V4).
- **D6** — `.change` a scalar, which a negative-search `if jq -e …` reads as "condition false".
- **Uniformity** — nine gates get one audited fail-closed contract instead of nine hand-rolled ones with
  differing coverage, which is what lets a future gate inherit it.

**Consequence for the mutation design:** the gate's own pre-existing abort *also* carries the gate's own
name (`inngest_host_replace_gate: plan JSON not found:`), so a gate-name anchor **cannot** distinguish a
preamble abort from a gate abort. Arms must anchor on **preamble-distinctive** text
(`unclassifiable plan entry`, `Fail-closed: an unreadable plan is not evidence of a safe one`) *plus* the
gate name.

### V3 — blast radius is NOT uniform (CORRECTED — v1 undercounted call sites ~2×)

`grep -cE '^\s*if ! [a-z0-9_]+_gate ' .github/workflows/apply-web-platform-infra.yml` → **19**
(18 tfplan-gate calls + `git_data_birth_readiness_gate`, which grades a YAML file). v1 said "nine" — those
were the **`source` lines**, not the call sites. `stock_preflight_gate` alone accounts for **8**. A 20th
invocation of a different shape sits at `:712`
(`bash "${GITHUB_WORKSPACE}/tests/scripts/lib/preapply-entrypoint-gate.sh" --gate tfplan.json`).

- **`web2-retire-gate.sh` is sourced by NO workflow** (`grep -rn 'web2-retire-gate' .github/` → nothing);
  `destroy-guard-filter-web-platform.jq:69` says so: *"test-only … never by a workflow"*. **Blast radius zero.**
- **`stock-preflight-gate.sh` is the most-invoked gate in the repo (8×)** — more than any Tier-1 gate — while
  sitting in the tier v1 called "lower-priority readability". **Rank by call sites, not by label.**

*A floor of "≥ 9" — which v1 proposed — passes while missing half the corpus. Derive it, don't hardcode it.*

### V4 — the `"actions": []` hole is MEASURED

The preamble header records it: a happy 18-address birth plan that also carried
`hcloud_server.web["web-1"]` with `"actions": []` and `"after": null` — a destroy of the singleton behind
`app.soleur.ai` — scored `destroys=0, out_of_scope=0` and **PASSED**.

### V5 — the "tier 2" three are NOT pure deletion (contradicts the issue prose AND ADR-149)

| Gate | Readable | Classifiable | Residual hole |
|---|---|---|---|
| `web-host-birth-gate.sh` | equivalent | **negative search** | a jq **error** reads as "condition false"; no `length > 0`, so the measured hole is open |
| `web-host-replace-gate.sh` | equivalent | positive `all(…)` **plus `all(.change.actions[]; type == "string")`** | no `length > 0` → same measured hole |
| `stock-preflight-gate.sh` | **weaker** — `jq -e '.resource_changes'` is truthiness, not type | negative search, **scoped to `hcloud_server` only** | same jq-error-as-false hole |

**`web-host-replace-gate.sh` carries a check the helper does NOT** — retrofitting it onto today's helper
would **regress** it.

### V6 — the helper conjunct is genuinely additive (verified by running the predicates)

| fixture | current | with `and all(.change.actions[]; type == "string")` |
|---|---|---|
| `"actions": [["delete"]]` | **0 — the hole** | **1** |
| `"actions": []` | 1 | 1 |
| `"actions": ["create"]` | 0 | 0 |
| `"change": 42` | 1 | 1 |
| `"actions": "delete"` | 1 | 1 |

`(.change.actions | length) > 0` **already exists** at `plan-gate-preamble.sh:104`; the new conjunct does
**not** subsume it (`all` over an empty stream is vacuously `true`). jq's `and` short-circuits, so the
conjunct never raises on a scalar `.change`. **No legitimate terraform shape is newly rejected** —
`.change.actions` is a closed enum of strings — so the helper's one live consumer cannot flip PASS→ABORT.

### V7 — the ADR/header correction the issue asks for is ALREADY LANDED

ADR-149 `:241-242` already says "the **eight** gates" and cites #6997; the disproved
"pure deletion / changes no safety property" sentence is at `:247-248`; the header says TWELVE/FOUR/EIGHT.
**Do not "fix" what is already correct** — the remaining work is the inverse (Phase 5).

### V8 — #7002 root cause, proven by bisection

- `.github/workflows/cutover-inngest.yml` has **exactly one** `run:` step — **1597 lines / 118,068 bytes**
  (reproduced twice via PyYAML; a reviewer reported 118,722, not reproducible here — so **Phase 6 re-measures
  rather than hardcoding**).
- `timeout 25 actionlint <file>` → **rc=124**. `-shellcheck=` → **rc=0** instant. `F_GETPIPE_SZ` = **65536**.
- Bisect: 65,043 B completes; **65,564 B hangs.** **The threshold is exactly the pipe buffer.**
- **Not** output-side: shellcheck's findings total 444 bytes over stdin.
- **The unit is the STEP:** 1 × 117,954 → rc=124; 2 × 58,986 → rc=0; 3 × 39,954 → rc=0.
- actionlint **1.7.7**, shellcheck **0.10.0**. `grep -rn actionlint .github/workflows/` → **zero**.

### V9 — the Inngest cutover is LIVE and FAILING

Dispatched **twice on 2026-07-24**, both `failure`. Open follow-ups **#6940, #6921, #6753, #6488**.
`workflow_dispatch`-only → **no CI signal can detect a regression from restructuring it.**

### V10 — the cutover body is pure shell (CORRECTED — v1's "more fail-closed" claim was FALSE)

**Zero `${{ }}` expressions. Zero heredocs** of any form. Job has no `defaults:`, no `container:`; the
step's keys are exactly `['env','name','run']` — **`if:` and `timeout-minutes:` are on the JOB** (`:57`,
`:59`), not the step. No `$GITHUB_ENV`/`$GITHUB_OUTPUT`/`::add-mask::`/`shell:`/`working-directory:`.
Relative `bash scripts/betterstack-query.sh` calls survive because the working directory stays
`GITHUB_WORKSPACE`.

> **RETRACTED.** v1 claimed extraction was *"strictly more fail-closed"* because the script would carry an
> explicit `set -euo pipefail` where the step inherited `bash -e {0}`. **False** — the run body's **first
> line already is** `set -euo pipefail` (`:157`). Extraction is **posture-neutral**. The two real wins:
> **actionlint terminates**, and **shellcheck lints the body directly**. *Recorded rather than deleted
> because asserting an unmeasured safety improvement is this plan's own defect class.*

Extraction still dominates the multi-step split on the measured axes — cross-step state loss (3 helpers +
`FSM_FAIL_REASON` across 13 `case` arms) **does not arise**; `if:`-arm completeness **does not arise**;
helper drift **does not arise**; one byte-exact diff instead of 13 normalized ones.

### V11 — no call site suppresses rc, but the contract is unenforced

All 19 `if ! <gate>` sites are non-suppressing. **v1's stated reason for putting asserts inside the function
was also wrong:** `set -e` **is** re-enabled before every gate `source` (e.g. `:1288` immediately precedes
`:1293`), so a file-scope failure fails **closed**, not open. **The correct reason is that the asserts
consume `$plan_json`, a function parameter that does not exist at file scope.** Note the shapes that
actually suppress are `|| true`, `|| echo`, pipelines, un-negated `if <gate>`, and command substitution —
**not** a bare command.

### V12 — #7024: a latent shape, not a live fail-open (CORRECTED)

Mechanism: `grep -q` exits on first match and closes the pipe → producer takes SIGPIPE (141) → `pipefail`
propagates. **Negated** assertion → spurious FAIL; **positive** predicate → FALSE PASS.

> **CORRECTED.** v1 called `tests/scripts/test-sentry-full-root-apply.sh` a live fail-open. **It is not
> currently reachable.** Measured: `apply-sentry-infra.yml` is 39,221 bytes; after `_strip_comments`,
> **16,892 bytes** — against a **65,536**-byte pipe buffer. Ten runs with `-target=` injected at the **top**
> returned `0 0 0 0 0 0 0 0 0 0`; never 141. The producer's whole output fits the buffer with 48 KB spare,
> so `grep -v` finishes writing before `grep -q` can close the pipe. The same holds for `phase-16.test.sh`,
> where `$OUT` is a kilobyte-scale report.
>
> **The fix is still correct and still worth doing** — the shape is one file-growth away from live, it is
> free to fix, and `apply-sentry-infra.yml` is the #6074 guard on `terraform destroy` reachability. But the
> plan must not sell it as a measured live defect, and the ACs must not demand an unobtainable `rc=141` on
> real inputs.

Sites: `phase-16.test.sh` (`set -euo pipefail` L12) — **11**: L93, L202, L300, L302, L304, L306, L320,
L335, L337, L339, L356 (Scenario 15's four are L300/302/304/306). `test-sentry-full-root-apply.sh` — L57
`_has_executable_target`, called at `:60/:74/:90`; plus L116, L128-129, L139.

**Also:** issue #7024's **title has the direction backwards** — it says phase-16 fails OPEN and
sentry-full-root-apply CLOSED; the mechanism is the inverse (a negated assertion fails closed/flakes; a
positive predicate fails open). The PR body must record this.

### V13 — a `grep -q` guard EXISTS, is ALREADY IN CI, and #7024 is a SLICE of an open issue

- `.claude/hooks/grep-q-pipe-guard.test.sh` (#6992/#6998) with the wide pattern
  `'\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'` and its own non-vacuity probe.
- **Already CI-enforced** — `scripts/test-all.sh:474` globs `.claude/hooks/*.test.sh`. Extending coverage is
  a **one-line pathspec edit**. (`scripts/*.test.sh` is **not** auto-globbed and needs explicit `run_suite`.)
- Its header names the scope left open: *"scripts/ and plugins/ are NOT in scope yet — tracked in #7005."*
- **#7005 is OPEN.** Corpus re-measured with the wide pattern: `*.test.sh` **583** (not #7005's 157),
  `scripts/` **79**, `plugins/` **142**, repo-wide **800**. **#7024 is a slice of #7005.**
- **The pattern matches comments.** A file containing only `# NEVER write: echo "$x" | grep -q foo` scores 1;
  the learning file itself has 6 hits. The existing guard survives only because its pathspec is narrow — so
  any promotion into `scripts/` would make the lint **match its own probe line** (`:50`).

### V14 — the mutation harness ALREADY EXISTS, and fixtures are already duplicated 4×

`tests/scripts/test-git-data-host-birth-gate.sh` provides `mutate_and_check` (`:710`) and `mutate_layered`
(`:727`), each with a `cmp -s` byte-identical non-vacuity floor (`:715`/`:732`), under an explicit contract
(`:698-705`): **`LAYERED` — neuter it and the plan is still REJECTED, but its own signature disappears.**
That is exactly the semantics v1 spent forty lines specifying as a novel insight. Its delegated-input block
(`:668-679`) is **five** `check` calls — the reference for how many arms a retrofit needs.

`mk_plan`/`rc_entry` are already copy-pasted across **four** suites. Nine more copies would make 13.

### V15 — baseline and budget

- **`TEST_GROUP=scripts` is 225/225 green in 416.9 s** as of this session. **Zero pre-existing failures**, so
  `wg-when-tests-fail-and-are-confirmed-pre` offers no exemption: **any** red on this branch is ours.
- Guard layer today: **16 distinct `scripts/lint-*` tools** (25 files incl. `.test.sh`/`.highwater`);
  `test-all.sh` is 500 lines / 104 `run_suite` calls.
- `python3 scripts/lint-agents-rule-budget.py …` → `B_ALWAYS=22900` / 23000, already **WARN**.
- `.github/scripts/` holds **6 scripts, all `check-*`**, all PR-quality guards fed to a required check via
  `test/run-all.sh`. The plan's own cited precedents (`apply-sentry-infra.yml:299/308/321/605`,
  `apply-web-platform-infra.yml:712`) all point at **`scripts/`** or `tests/scripts/`, **never**
  `.github/scripts/`. `grep -c '\.github/scripts' scripts/test-all.sh` → **0** (swept by nothing).

### V16 — the 93 pre-existing actionlint findings

Over the other 68 workflows: **rc=1, 93 findings across 20 files.** SC2016 ×62 (67% — the documented benign
markdown-backtick shape), SC2129 ×9, SC2086 ×5, SC2222 ×4, SC2221 ×4, SC2015 ×2, SC2005 ×2, SC2001 ×2,
SC2155/SC2034/SC2012 ×1.

---

## Plan-Review Revisions (v1 → v3)

Six reviewers. **Both simplification reviewers fired on the same scope in which both correctness reviewers
then found defects** — the signal that the scope was over-architected. Cutting dissolved the bugs.

**Premises falsified (all verified before acceptance):**

| v1 claim | Measured reality |
|---|---|
| D1/D2/D3 are fail-open; every arm must be RED pre-retrofit | **All nine gates already abort on D1/D2**; replace-style gates also abort on D3 (V2). AC "every arm RED" was unachievable. |
| `test-sentry-full-root-apply.sh` is a live fail-open | **Unreachable** — 16,892 B producer vs 65,536 B buffer; 10/10 runs returned 0 (V12). |
| Nine gate call sites | **19** — v1 counted `source` lines (V3). A "≥ 9" floor would miss half. |
| Extraction is "strictly more fail-closed" | **False** — the body already starts `set -euo pipefail` (V10). |
| A file-scope `return 1` fails open | **False** — `set -e` is re-enabled before every source (V11). |
| `grep -L plan_gate_assert_readable` polices invocation | **It polices presence** — the `declare -F` guard line satisfies it (V1). |

**Cut (dissolving ~10 findings and ~2,000 lines):** `lint-gate-invocation-rc.sh` (census wrong, premise
wrong, hardcodes one file); `lint-workflow-run-block-size.py` (a **byte-count proxy** for a defect with a
**direct** `rc=124` signal — replaced by six lines in `ci.yml`); `lint-plan-gate-preamble-coverage.sh` (the
check is ~10 lines and belongs in the already-registered preamble suite); the `lint-grep-q-pipe.sh`
promotion + ratchet (the guard exists and is already in CI; the ratchet also contradicted Non-Goal 3, would
have been seeded 3.7× wrong, and would have matched its own probe); the new 250-line `web2-retire` suite
(blast radius zero); the 90-arm battery (→ ~4 arms/gate on the existing harness); Phase 1.0's type-scope
parameter design; 8 of 32 ACs.

**Added:** a shared `gate-suite-harness.sh` (V14 — dedupes 4 existing copies and removes nine chances at a
subtly-vacuous mutation arm); Phase 1.4's consumer-regression gate; `xargs -r`; the `^\s*` call anchor; `?`
on the offender filter; the checkout-step rename; the ADR given a producing phase and an AC.

**Held against a reviewer:** `scripts/lint-workflows.sh` kept (DHH) over code-simplicity's cut, but
shrunk, given no `.test.sh`, and made exit-0-on-findings. The architecture reviewer's `exit 1`-instead-of-
`return 1` proposal is **rejected** — pervasive test-harness complexity for a narrow risk; recorded in the
deferral issue.

---

## Research Reconciliation — Spec vs. Codebase

| Claim supplied with the task | Reality | Response |
|---|---|---|
| "ADR-149 says *five*, header says *SEVEN*; correct them." | **Already correct** (V7). | Prescribe the *post-retrofit* rewrite (Phase 5), plus the vacuity fix to the published command (V1). |
| "The 3 carry equivalent INLINE checks; retrofit is pure deletion." (issue **and** ADR-149) | **False** (V5, V4). | Re-tier; fold `web-host-birth` in; correct the ADR sentence. |
| "web2-retire … otherwise asserted nowhere." | True re: the suite, but **no workflow sources it** (V3). | Retrofit; assert in the existing consumer suite; rank last. |
| Unstated: the tier-2 three are lower priority. | **Inverted for `stock-preflight`** — 8× (V3). | Record in the deferral issue. |
| "actionlint exits 13 on findings in three files." | rc=**1**, **93 / 20 files** (V16). | Deferred with a census issue. |
| "never `grep -q` on a pipe, **per AGENTS.rest.md**" | **No such rule exists** (zero hits). | Cite the learning file; extend the existing guard; add no rule (V15). |
| Implicit: "build a guard and sweep." | **Guard exists, already in CI; #7005 open on 800 sites** (V13). | One-line pathspec edit; cross-link #7005. |
| Implicit: "split cutover-inngest.yml." | Cutover live and failing (V9); body pure shell (V10). | **Extract, don't split.** DC-1. |
| #7024's title: phase-16 OPEN, sentry CLOSED | **Inverted** (V12). | Record in the PR body. |

## Open Code-Review Overlap

**None.** All 61 open `code-review`-labelled issues checked against every planned path. Zero matches.

---

## User-Brand Impact

- **If this lands broken, the user experiences:** *(a)* an inert retrofit leaves the seven **live**
  destroy-guards unable to classify a degraded plan, so a `"actions": []` entry can hide a destroy of
  `hcloud_volume.workspaces` (every connected user's worktrees) or `hcloud_volume.git_data*` (every user's
  source code and history) while the gate prints PASS — the exact shape measured in V4; *(b)* a wrong
  extraction breaks the Inngest Phase-2 cutover, already failed twice, and Inngest is the durable-trigger
  layer (ADR-030), so scheduled and event-driven agent work stops; *(c)* an over-strict preamble blocks a
  legitimate apply — noisy but safe, the correct direction.
- **If this leaks, the user's data / workflow is exposed via:** no new exposure vector. Every touched
  surface is a pre-apply grader or a test harness. The *existing* exposure this closes is the inverse of a
  leak — an unauthorized destroy of the at-rest stores.
- **Brand-survival threshold:** `single-user incident`

---

## Non-Goals / Out of Scope

1. **The 93 actionlint findings — OUT, deferred after inline triage.** SC2016 ×62 is the documented benign
   shape; 62 `disable` annotations would swamp three real fixes. **SC2086 ×5 / SC2015 ×2** carry real
   correctness risk — pull one in only if it lands in a file this PR already touches. **File a tracked
   issue** with the census, proposing a highwater ratchet (precedent: `lint-trap-tempfile-ownership.highwater`,
   wired at `ci.yml:169`, whose header carries its own `--census` derivation command). `Refs #<N>`.
2. **Full retrofit of `stock-preflight-gate.sh` and `web-host-replace-gate.sh` — OUT.** **File a tracked
   issue** recording the residual holes, **that `stock-preflight-gate.sh` is sourced 8×** so its tier label
   understates it, a concrete re-evaluation trigger (*reopen when the helper has been green in `main` for one
   release cycle, or immediately on any classifiability abort in production*), and the two **rejected
   alternatives** (a type-scope parameter; `exit 1` instead of `return 1`) so neither is re-litigated.
3. **The remaining `| grep -q` corpus — OUT, tracked as #7005.** This PR fixes #7024's two named files and
   extends the existing guard's pathspec. **Comment on #7005** with the sites removed, the remainder
   re-scoped, and **the corrected corpus numbers** (583 `*.test.sh`, not 157 — #7005's figures predate the
   wide pattern). `phase-16.test.sh:294-295`'s `| head -1` is the same class and is left to #7005 —
   *deferred fail-open*, not safe.
4. **A gate-call-site rc lint — OUT, deferred.** The insight is real (a mutation battery cannot see the call
   site) but v1's version was miscalibrated. **File a tracked issue** with the corrected census (19 `if !`
   sites + the `bash …-gate.sh` shape at `:712`), scoped to `.github/workflows/**`, noting that a bare
   command is **not** a suppressing shape.
5. **A new AGENTS.md rule — DECLINED.** 100 bytes of headroom (V15); the shape is mechanically detectable;
   #6992 already made this call.
6. **A second `grep -q` guard, or a ratchet.** One guard exists and is already in CI (V13); the ratchet
   belongs to #7005 and would be a bump-the-number ritual here (the pattern cannot tell a live fail-open
   from a benign idiom).
7. **Splitting the cutover body into steps — REJECTED.** Recorded as the rejected alternative in the ADR.
8. **Rewriting cutover *logic*.** Phase 6 is a verbatim move.

---

## Implementation Phases

### Phase 0 — Preconditions and issue filing

0.1 Re-run the corrected derivation (**`xargs -r`, `-E '^\s*plan_gate_assert_readable'`** — V1) and paste
    the output. Expect 11. If it differs, **stop and re-plan**.
0.2 Record the pre-work baseline: `TEST_GROUP=scripts bash scripts/test-all.sh` (expect **225/225 green,
    ~417 s**). Zero pre-existing failures means any later red is ours.
0.3 Confirm the actionlint hang and the buffer. **Never read `$?` after a pipe** — `… > log 2>&1; rc=$?`.
0.4 Read `tests/scripts/test-git-data-host-birth-gate.sh` **:664-760** and `test-plan-gate-preamble.sh`.
    Phase 1.5 extracts that harness; do **not** write a new one.
0.5 Read `.claude/hooks/grep-q-pipe-guard.test.sh` — Phase 7 edits its pathspec, nothing more.
0.6 **File the four deferral issues now** (Non-Goals 1-4). Phases 5 and 1.6 must cite real numbers; filing
    last would make those citations unwritable.

### Phase 1 — Helper, harness, and drift check (blocking precondition)

1.1 **RED first:** add an arm to `test-plan-gate-preamble.sh` for `"actions": [["delete"]]`; run against the
    **unmodified** helper; record the failure.
1.2 Add `and all(.change.actions[]; type == "string")` to `plan_gate_assert_classifiable`.
    **ADDITIVE — it does not subsume `(.change.actions | length) > 0`**, which already exists at `:104` and
    must remain (`all` over an empty stream is vacuously true, so only `length > 0` rejects `"actions": []`).
    Say so in the comment.
1.3 **Add `?` to the offender-extraction filter** (`:106` currently uses bare `.change.actions`). Without it
    a scalar `.change` makes the extraction raise, jq exits 5, `2>/dev/null` swallows it, and the ABORT names
    **no offender** — verdict right, operator's only diagnostic blank. `web-host-replace-gate.sh:225-227`
    documents this exact reason for its own `?`.
1.4 **Consumer-regression gate.** `test-plan-gate-preamble.sh` **and** `test-git-data-host-birth-gate.sh`
    both green before Phase 3 opens. `git_data_host_birth_gate` is live at `:4053` and is the helper's only
    existing consumer.
1.5 **Extract `tests/scripts/lib/gate-suite-harness.sh`** carrying `mk_plan`, `rc_entry`, `rc_noactions`,
    `check`, and `mutate_and_check` / `mutate_layered` with their `cmp -s` floors (V14). **Migrate
    `test-git-data-host-birth-gate.sh` onto it first** — it is the existing consumer, so the migration is
    self-proving and must leave its 55 arms green. This dedupes four existing `mk_plan` copies and, more
    importantly, means the subtle mutation contract is written **once** instead of nine times (nine
    hand-written copies is nine chances at a vacuous arm — R1, the top risk).
1.6 Add the **drift check inside `test-plan-gate-preamble.sh`** (~10 lines, no new file, already registered):
    re-run the corrected derivation; assert empty except a two-element exclusion array whose comments cite the
    Non-Goal 2 issue; assert **≥ 12 gate files scanned**; and assert no `tests/scripts/lib/*.sh` containing
    `local plan_json` falls outside the `*gate*` glob, so an off-pattern 13th grader cannot escape.

### Phase 2 — Degraded-plan fixtures (in the shared harness)

Built once per run by `gate-suite-harness.sh`, not re-synthesized per suite. **Synthesized, never captured**
(`cq-test-fixtures-synthesized-only`).

| # | Shape | Status against an unmodified Tier-1 gate |
|---|---|---|
| D1 | missing path | **already aborts** (V2) — full coverage lives in the preamble suite |
| D2 | unparseable JSON | **already aborts** (V2) — ditto |
| D3 | `resource_changes: null` | aborts on replace-style gates (positive-count verdict); the fail-open shape only bites count-of-bad-things-is-zero gates |
| **D5** | entry with `"actions": []` | **PASSES today — the measured hole (V4)** |
| **D6** | `.change` is scalar `42` | **PASSES on negative-search gates** |

**D1-D6 in full belong in `test-plan-gate-preamble.sh`** (which already covers D1 `:77`, D2 `:83`, D3 `:89`,
D4-equivalent `:99`, actions family `:107-120` — add D5-explicit and D6). Per gate, only Phase 3.1's arms.

### Phase 3 — Retrofit the seven live Tier-1 gates, then `web-host-birth`

Order by blast radius (V3). `web-host-birth-gate.sh` is **live** (`:3254/:3255`) so it belongs here, not in
Phase 4.

3.1 **Four arms per gate**, declared against the shared harness (~10 lines each):
    - **A1 = D5** → ABORT. Proves the `classifiable` call site on the shape with a measured destroy behind it.
    - **A2 = D6** → ABORT. Proves it on the shape a negative search reads as "condition false".
    - **A3 = happy path** → still **PASS**. The negative control; without it an always-aborting gate scores
      perfect.
    - **A4 = `mutate_layered`** deleting the `plan_gate_assert_classifiable` line → still rc 1, but the
      **preamble-distinctive** signature disappears.
    **Anchor A1/A2/A4 on preamble-distinctive text** (`unclassifiable plan entry`,
    `Fail-closed: an unreadable plan is not evidence of a safe one`) **plus** the gate name — *not the gate
    name alone*, because the gate's own pre-existing aborts also carry it (V2), which would make A4 a
    redness detector rather than a binding.
    **A1 and A2 must be RED pre-retrofit; A3 must be GREEN before and after; A4 is meaningless until 3.2.**
    *(v1's "every arm RED" was false for A3 and impossible for A4, and unachievable for D1/D2 at all.)*

3.2 **Guarded source at file scope**, copying `git-data-host-birth-gate.sh:72-77`:
```bash
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _<PREFIX>_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
  source "${_<PREFIX>_DIR}/plan-gate-preamble.sh"
fi
```

3.3 **Asserts INSIDE the gate function, as its first statements.** **The reason is that they consume
    `$plan_json`, a function parameter that does not exist at file scope** — not, as v1 claimed, that a
    file-scope failure fails open (`set -e` is re-enabled before every source, so it fails *closed*; V11).
```bash
plan_gate_assert_readable      "<gate_name>" "$plan_json" || return 1
plan_gate_assert_classifiable  "<gate_name>" "$plan_json" || return 1
```
`|| return 1` also catches a `127` undefined-function status.

3.4 Route every counter through `plan_gate_assert_numeric` before its first comparison, **replacing** any
    hand-rolled `^[0-9]+$` loop (`cq-ref-removal-sweep-cleanup-closures`). Add **A5** where this changes a
    gate: drive one counter non-numeric and assert `counter parse failed`.

3.5 **Delete the now-redundant inline checks — and migrate the suite messages that assert them.**
    `test-registry-luks-recut-gate.sh:284,287` assert the gate's **own** strings (`plan JSON not found`,
    `jq evaluation failed`); deleting the inline checks changes the message to the preamble's and turns both
    arms red. **Sweep all eight suites for those two strings before starting.** This is a named message
    migration, not an incidental fixup.

3.6 Re-run: all arms green, all pre-existing arms green.

### Phase 4 — `web2-retire-gate.sh` (blast radius zero, last)

4.1 Retrofit per 3.2-3.6. **No new suite.** Add A1/A2/A3/A4 to
    `tests/scripts/test-destroy-guard-counter-web-platform.sh`, which already sources the gate via
    `WEB2_RETIRE_GATE_LIB` and is already registered. Note in the gate header that it is **test-only** so a
    future reader does not over-rank it. Its filter comes from an external `.jq` (`WEB2_GATE_FILTER`), so
    its jq-failure path differs from its siblings — the preamble still runs first and independently.

### Phase 5 — Correct the prose this PR makes stale, and two claims that were already wrong

5.1 `plan-gate-preamble.sh` header — post-retrofit counts; **replace the published derivation command with
    the corrected one** (`xargs -r` + `-E '^\s*plan_gate_assert_readable'`) and say why the `grep -L` form
    goes vacuous once gates carry the `declare -F` guard (V1). Keep the "re-derive, do not remember"
    instruction. Name the residual two, citing the Non-Goal 2 issue. Add: *callers must check the gate's rc;
    all 19 sites in `apply-web-platform-infra.yml` do as of #6997.*
5.2 `ADR-149-…md` `## Consequences` (`:233`) — same counts and the same corrected command, **and correct the
    sentence at `:247-248`** claiming the three carry equivalent checks so "their retrofit is pure deletion
    and changes no safety property" (V5, V4). Record that `stock-preflight-gate.sh` is sourced 8×.
5.3 Re-run the quoted command; the quoted output must match what it now returns.
5.4 **Author the new ADR** (§ Architecture Decision) via `/soleur:architecture create …`.

### Phase 6 — #7002: extract the run body (two commits)

**Commit 6a — verbatim extraction. Nothing else in this commit; AC10 is evaluated here.**

6.1 **Measure, don't assume.** Parse `git show origin/main:.github/workflows/cutover-inngest.yml` with
    python3+PyYAML; record the `run:` scalar's SHA-256 and byte count. (Reproduced twice here at 118,068; a
    reviewer reported 118,722. The plan records the method, not the number.)
6.2 Create **`scripts/cutover-inngest.sh`** = `#!/usr/bin/env bash` + **the parsed scalar byte-for-byte**.
    YAML already dedents a `run: |` block scalar, so there is **no manual dedent and no whitespace
    normalization anywhere** — normalization is precisely the transform that would hide a dedent error. The
    body's existing first line `set -euo pipefail` travels with it; **do not add a second**.
    **Home:** `scripts/`, not `.github/scripts/` — the latter is six `check-*` PR-quality guards feeding a
    required check via `test/run-all.sh`, and every precedent this plan cites
    (`apply-sentry-infra.yml:299/308/321/605`, `apply-web-platform-infra.yml:712`) points at `scripts/` or
    `tests/scripts/` (V15).
6.3 Reduce the step to `run: bash "${GITHUB_WORKSPACE}/scripts/cutover-inngest.sh"`, keeping `name:` and
    `env:` (incl. the conditional `DOPPLER_TOKEN_INNGEST_ARM`) unchanged. **`if:` and `timeout-minutes:` are
    job-level (`:57`, `:59`), not step-level** — do not claim to preserve step keys that do not exist.
    **In the same commit, rewrite the checkout step's name and comment.** It reads
    `Checkout (for betterstack-query.sh — op=arm/rollback FSM confirm)` and calls itself *"Harmless (no-op
    source read) for the webhook ops"* — an open invitation to gate it `if: inputs.op == 'arm' || …`, which
    post-extraction would break **every** op on a path with no CI signal. It must state that checkout is
    required by all ops.
6.4 Re-parse the new workflow's `run:` scalar and the script minus shebang; assert **byte-identical, no
    normalization**.

**Commit 6b — findings triage, separate so 6a stays verbatim.**

6.5 `shellcheck scripts/cutover-inngest.sh` — confirm it **completes**. Record findings; fix only genuine
    correctness ones; defer style to Non-Goal 1.
6.6 `timeout 60 actionlint .github/workflows/cutover-inngest.yml > /tmp/al.out 2>&1; rc=$?` ∈ {0,1}, never 124.
6.7 **Baseline correctly.** `origin/main`'s **full-corpus** actionlint run **cannot be produced — it hangs.**
    The baseline is the **other 68 workflows** (V16). Post-extraction `cutover-inngest.yml` lints for the
    first time ever, so its findings are *newly visible by construction* and are **not** regressions — record
    them separately.
6.8 Confirm the two suites asserting actionlint runs in zero *workflows*
    (`apply-inngest-rls-dev-workflow.test.sh:8`, `scan-workflow.test.sh:6`) still hold — `lint-workflows.sh`
    is a script, not a workflow, so they should need no edit.

### Phase 7 — #7024: fix the two named files, extend the existing guard

7.1 **Deterministic RED via a synthetic harness.** The real inputs **cannot** produce 141 (V12: 16,892 B vs
    a 65,536 B buffer; 10/10 runs returned 0). Build a synthetic producer **> 65,536 bytes with an early
    match** and assert the pipeline's own status is **141**; then record, per real site, that it does **not**
    reproduce at current sizes. *Do not write an AC demanding 141 on real inputs.*
7.2 Apply the blessed forms (V12/§Sharp Edges). `|| true` on the `-c` form is **required**.
7.3 `phase-16.test.sh` — convert all 11 sites to herestrings. **Leave `:294-295`'s `| head -1`** to #7005
    (Non-Goal 3), and label it *deferred fail-open*, not safe.
7.4 `test-sentry-full-root-apply.sh` — drop the pipe:
```bash
_has_executable_target() {
  local body; body=$(_strip_comments "$1")
  grep -qE -- '-target=' <<<"$body"
}
```
    Convert L116/L128-129/L139 to herestrings against the captured `$body`. **Add a top-injection mutation
    arm** — the existing arm appends at the **bottom**, so it could never detect the shape even if it were
    live. *(It is GREEN today for both the pre- and post-fix predicate; its value is that it stays green for
    the right reason and will catch the shape if the file grows past the buffer.)*
7.5 **Extend the existing guard with a one-line pathspec edit** — add the two files to the `git grep`
    pathspec at `:33` and update the header's scope note. **Do not promote it to `scripts/`**: the pattern
    matches comments, so outside its narrow `.test.sh`-excluded pathspec it would match its own probe line at
    `:50` (V13). It is **already CI-enforced** via `test-all.sh:474`.

### Phase 8 — One durable guard, on the direct signal

8.1 **Put actionlint in CI with a timeout.** Add a step to `ci.yml` beside the existing `Lint …` steps:
```yaml
- name: actionlint hang guard (#7002)
  run: |
    set -euo pipefail
    command -v actionlint >/dev/null || { echo "::error::actionlint not installed on this runner"; exit 1; }
    timeout 120 actionlint .github/workflows/ > /tmp/al.out 2>&1; rc=$?
    if [ "$rc" -eq 124 ]; then
      echo "::error::actionlint HUNG — #7002 recurring: a run: body crossed the 65536-byte pipe buffer."
      exit 1
    fi
    echo "actionlint rc=$rc (0=clean, 1=findings; both acceptable — Non-Goal 1)"
```
    It asserts **only "not hung"**, which is why the 93 open findings do not block it — the objection that
    kept actionlint out of CI. It catches the deadlock **directly** (`rc=124`) rather than via a byte-count
    proxy, needs no PyYAML and no threshold to re-tune, and gives #7002's stated defect a terminal, enforced
    criterion. **Installing actionlint on the runner is part of this step's setup** — the tool currently
    exists on one laptop (V15), so the plan must provision it (pinned release download) rather than assume it.
    **RED-proof:** run the same step against `origin/main`'s pre-extraction workflow → exit 1.
8.2 `scripts/lint-workflows.sh` — the documented **local** entry point (~20 lines, **no `.test.sh`**, per the
    `lint-orphan-test-suites.sh` precedent). Wrap in `timeout`; **never pipe the tool into `head`/`tail`**;
    print `rc` and distinguish 124 from 1 and 0; document `-shellcheck=`; **exit 0 on both 0 and 1** so the
    discoverability chain does not break on the expected findings state.

### Phase 9 — Exit gate and bookkeeping

9.1 `bash scripts/test-all.sh` green across all shards, compared against the Phase 0.2 baseline
    (**225/225, 416.9 s**). With zero pre-existing failures, any red is attributable to this PR.
9.2 Comment on **#7005** with the removed sites, the re-scoped remainder, and the corrected corpus numbers.
    All deferral issues referenced `Refs #<N>` — **never `Closes`**.
9.3 **PR body carries one-shot measurements only** (~1 screen): the 0.1 derivation output; the 0.2/9.1
    baseline pair; the 6.4 byte-identical result; actionlint rc and delta vs the 68-workflow baseline; the
    synthetic-141 observation plus the per-site non-reproduction; the AGENTS budget. **Per-arm RED/GREEN
    evidence stays in CI** — the shared harness prints `ARM A1: RED pre-retrofit / GREEN post` itself, which
    keeps being true after merge, where 36 pasted paragraphs would not.
9.4 Append to `knowledge-base/project/specs/<branch>/decision-challenges.md` (already exists: DC-1/2/3).

---

## Files to Edit

**#6997** — `tests/scripts/lib/plan-gate-preamble.sh` (conjunct, `?`, header) ·
`tests/scripts/lib/{git-data-host-replace,workspaces-luks-recut,workspaces-luks-cutover,registry-luks-recut,registry-region-migrate,registry-host-replace,inngest-host-replace,web-host-birth,web2-retire}-gate.sh` ·
`tests/scripts/test-plan-gate-preamble.sh` (D5/D6/nested arms + drift check) ·
`tests/scripts/test-git-data-host-birth-gate.sh` (migrate onto the shared harness) ·
`tests/scripts/test-{git-data-host-replace,workspaces-luks-recut,workspaces-luks-cutover,registry-luks-recut,registry-region-migrate,registry-host-replace,inngest-host-replace,web-host-birth}-gate.sh`
(4-5 arms each; **`test-registry-luks-recut-gate.sh:284,287` need a message migration — §3.5**) ·
`tests/scripts/test-destroy-guard-counter-web-platform.sh` (web2-retire arms) ·
`knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`

**#7002** — `.github/workflows/cutover-inngest.yml` (run block → one-line invocation; checkout step
name/comment) · `.github/workflows/ci.yml` (actionlint hang guard + tool install)

**#7024** — `tests/scripts/test-sentry-full-root-apply.sh` · `plugins/soleur/skills/compound/test/phase-16.test.sh` ·
`.claude/hooks/grep-q-pipe-guard.test.sh` (pathspec + header)

**Shared** — `scripts/test-all.sh` (register the harness's consumers if needed) ·
`knowledge-base/project/specs/<branch>/decision-challenges.md` (append; **exists**)

## Files to Create

- `tests/scripts/lib/gate-suite-harness.sh` — shared fixtures + `mutate_and_check`/`mutate_layered`
- `scripts/cutover-inngest.sh` — the extracted body, byte-for-byte
- `scripts/lint-workflows.sh` — ~20 lines, no `.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-extract-cutover-inngest-run-body-to-script.md`

*Net new files: 4 (v1: 12).*

---

## Acceptance Criteria

Verification commands that can legitimately match zero must be written `… || true` or compare a captured
count — `grep -c` and `git grep` exit **1** on the very outcome several of these assert is good.

### Pre-merge (PR)

**#6997**

- **AC1** The corrected derivation (**`xargs -r` + `-E '^\s*plan_gate_assert_readable'`**) returns exactly
  **2** paths, down from 11. Output pasted. *The `grep -L` form is not acceptable — it is satisfied by the
  `declare -F` guard line (V1).*
- **AC2** **Invocation, not presence.** For each of the nine retrofitted gates, **A1 (D5)** and **A2 (D6)**
  return 1 with **preamble-distinctive** ABORT text plus the gate's own name, and **both were observed RED
  against the pre-retrofit gate**. *(D1/D2 are excluded: all nine already abort on them — V2.)*
- **AC3** **A4 (`mutate_layered`)** per gate: deleting the `plan_gate_assert_classifiable` line leaves the
  plan REJECTED but makes the **preamble-distinctive** signature disappear. Its `cmp -s` floor fails loudly
  on a no-op `sed`. *This is the AC that distinguishes "sourced" from "invoked"; a gate-name-only anchor
  cannot, because the gate's own aborts carry that name too.*
- **AC4** **A3 negative control** — the happy plan still PASSES for every retrofitted gate.
- **AC5** **A5** — where Phase 3.4 rerouted counters, one driven non-numeric produces `counter parse failed`.
- **AC6** `web-host-birth-gate.sh` returns 1 on D5, **and the pre-fix run of that fixture is recorded as
  having returned 0 (PASS)** — reproducing the measured hole (V4).
- **AC7** `plan_gate_assert_classifiable` rejects `[["delete"]]` (pre-Phase-1 RED recorded), still rejects
  `[]`, and **names the offending address on a scalar `.change`** (proving the Phase 1.3 `?`).
- **AC8** **Phase 1.4 consumer gate:** `test-plan-gate-preamble.sh` and `test-git-data-host-birth-gate.sh`
  both green *before* the first retrofit commit — and `test-git-data-host-birth-gate.sh` is green **after**
  its migration onto the shared harness, with its arm count unchanged.
- **AC9** The drift check inside `test-plan-gate-preamble.sh` exits non-zero when a synthetic 13th gate with
  `local plan_json` and no preamble **call** is added — **including one whose `declare -F` guard line is
  present** (proving it anchors on the call, not presence) **and one named off the `*gate*` glob**. Reports
  ≥ 12 files scanned and exactly two exclusions citing the Non-Goal 2 issue.
- **AC10** No gate retains a redundant inline readability/classifiability/numeric check, **and every suite
  arm that asserted a deleted gate-owned message was migrated to the preamble's** (§3.5).

**#7002**

- **AC11** **Byte-exact extraction, evaluated at commit 6a.** The PyYAML-parsed `run:` scalar of
  `origin/main`'s workflow and `scripts/cutover-inngest.sh` minus its shebang are **byte-identical, with no
  whitespace normalization**. The script's first body line is the body's own pre-existing `set -euo pipefail`;
  no second one added. Byte count recorded from measurement, not from this plan.
- **AC12** The step retains `name:` and `env:` (incl. the conditional `DOPPLER_TOKEN_INNGEST_ARM`); its
  `run:` is one `bash …` line; **job-level `if:` and `timeout-minutes:` are unchanged** (they are not step
  keys). No `${{ }}` moved into the script (there were none). The checkout step's name and comment now state
  it is required by **all** ops.
- **AC13** `timeout 60 actionlint .github/workflows/cutover-inngest.yml` → **rc ∈ {0,1}**, never 124.
- **AC14** `shellcheck scripts/cutover-inngest.sh` **completes**; findings recorded; correctness ones fixed
  **in commit 6b, not 6a**.
- **AC15** **The `ci.yml` hang guard exits 1 against `origin/main`'s pre-extraction workflow** and passes on
  HEAD, with actionlint installed by the step itself. RED output pasted. *This is the terminal criterion for
  "the linter can report at all" — the defect #7002 actually names.*
- **AC16** **No NEW findings vs the 68-workflow baseline** (Phase 6.7). Findings newly visible on
  `cutover-inngest.yml` are recorded separately and are **not** regressions. Must **not** assert `exits 0`.

**#7024**

- **AC17** `git grep -nE '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' -- '<the two files>'` returns **zero**
  hits (`|| true` on the command — `git grep` exits 1 on zero matches).
- **AC18** **The synthetic harness observes `rc=141`** on a >65,536-byte producer with an early match; and
  the **non-reproduction on the real inputs is recorded** (16,892 B vs a 65,536 B buffer — V12). *No AC
  demands 141 from a real site; it is not obtainable.*
- **AC19** `test-sentry-full-root-apply.sh` gains a **top-injection** mutation arm, green both before and
  after (documented as such), replacing an arm that appends at the bottom and therefore could never detect
  the shape.
- **AC20** `bash .claude/hooks/grep-q-pipe-guard.test.sh` passes with `.claude/hooks/`'s zero-invariant
  intact and the two new paths in scope, **exits non-zero against `origin/main`**, and its non-vacuity probe
  still distinguishes the forbidden shape from the fixed one. *(The guard is not promoted to `scripts/` —
  it would match its own probe line there; V13.)*

**Cross-cutting**

- **AC21** `bash scripts/test-all.sh` green across all shards, against the Phase 0.2 baseline
  (**225/225, 416.9 s** — zero pre-existing failures, so no `wg-when-tests-fail-and-are-confirmed-pre`
  exemption is available).
- **AC22** `plan-gate-preamble.sh` header and ADR-149 `## Consequences` state post-retrofit counts, **publish
  the corrected derivation command** (`xargs -r` + the `^\s*` call anchor) with an output that matches, and
  ADR-149 no longer claims the three carry equivalent checks / "pure deletion".
- **AC23** The new ADR exists, passes `scripts/check-adr-ordinals.sh`, and records the checkout dependency,
  the retracted fail-closed claim, `tests/scripts/lib/` as a production runtime path, and the rejected split.
- **AC24** Deferral issues (Phase 0.6) OPEN and `Refs #<N>`; **#7005 commented** with corrected corpus
  numbers; the PR body records that **#7024's title has the fail-open/fail-closed direction backwards** and
  that `phase-16.test.sh:294-295` is deferred **fail-open**, not safe.
- **AC25** PR body carries `Closes #6997`, `Closes #7002`, `Closes #7024`, each on its own line.

*25 ACs (v1: 32), with per-arm evidence moved into CI (§9.3).*

### Post-merge (operator)

**None.** Every step is executable in-session. The retrofitted gates take effect on the next dispatch of
`apply-web-platform-infra.yml` — they are sourced from the repo at run time.

---

## Observability

```yaml
liveness_signal:
  what:          "scripts/test-all.sh results — nine gate suites, the preamble suite (which also carries the #6997 drift check), the migrated birth-gate suite, and the extended .claude/hooks grep-q guard; plus the ci.yml actionlint hang guard. Each gate's A4 mutate_layered arm is the liveness proof that the preamble is invoked rather than merely sourced."
  cadence:       "per-PR (CI); the gates themselves run on every apply-web-platform-infra.yml dispatch"
  alert_target:  "CI red on the PR; ::error:: annotation in the Actions run log for a gate ABORT or an actionlint hang"
  configured_in: "scripts/test-all.sh (registration), .github/workflows/ci.yml (actionlint hang guard), .github/workflows/apply-web-platform-infra.yml (the 19 gate call sites)"

error_reporting:
  destination:   "GitHub Actions job log via ::error:: annotations; the preamble writes its ABORT reason to stdout prefixed with the gate's own name"
  fail_loud:     "the apply step exits non-zero and the run fails; the ABORT names WHICH assertion failed and WHICH plan entry caused it (offender addresses, first 10 — preserved on a scalar .change by the Phase 1.3 `?`)"

failure_modes:
  - mode:        "Retrofit is inert — preamble sourced but never invoked (this PR's own defect class)"
    detection:   "A4 mutate_layered per gate: deleting the assert must make the PREAMBLE-DISTINCTIVE signature disappear while the plan stays rejected. A gate-name-only anchor cannot detect this, because the gates' own pre-existing aborts also carry the gate name. cmp -s fails loudly if the sed matched nothing."
    alert_route: "CI red on the PR, naming the gate and the arm"
  - mode:        "A thirteenth gate is added later and is born without the preamble call"
    detection:   "the drift check inside test-plan-gate-preamble.sh re-runs the derivation anchored on '^\\s*plan_gate_assert_readable' (NOT grep -L, which the declare -F guard line satisfies), with xargs -r, a >=12-file floor, and an off-glob-name check"
    alert_route: "CI red on the PR that introduces the new gate"
  - mode:        "A future run: body crosses the 65536-byte pipe buffer and actionlint silently stops reporting"
    detection:   "ci.yml actionlint hang guard — timeout 120, rc=124 is the direct signal, not a byte-count proxy; asserts only 'not hung' so the 93 open findings do not block it; installs the tool itself rather than assuming a runner has it"
    alert_route: "CI red on the PR that introduces the oversized run block"
  - mode:        "A new piped grep -q is added to either enforced-zero file"
    detection:   ".claude/hooks/grep-q-pipe-guard.test.sh with the extended pathspec (wide -[A-Za-z]*q pattern), already CI-enforced via test-all.sh:474"
    alert_route: "CI red on the PR that introduces it"
  - mode:        "A guard's glob breaks and it scans nothing, reporting clean"
    detection:   "every xargs carries -r (measured: without it grep -L reads stdin); the drift check asserts >=12 files scanned; the hooks guard keeps its own non-vacuity probe"
    alert_route: "CI red with an explicit message rather than a silent pass"
  - mode:        "The extracted cutover script drifts from the body it replaced"
    detection:   "AC11 compares the PyYAML-parsed run: scalar byte-for-byte with NO normalization (YAML already dedents a block scalar, so no dedent step exists to hide an error); shellcheck now lints the script directly"
    alert_route: "CI red on the PR; the byte-exact diff is checkable without touching production"
  - mode:        "A future editor gates actions/checkout to arm/rollback, breaking every cutover op"
    detection:   "the checkout step's name and comment are rewritten in this PR to state it is required by ALL ops; the new ADR records it as a runtime dependency"
    alert_route: "human review — no CI signal exists on a workflow_dispatch-only path, which is why the in-file wording IS the mitigation"

logs:
  where:         "GitHub Actions run logs for apply-web-platform-infra.yml, cutover-inngest.yml and ci.yml; local stdout for scripts/test-all.sh"
  retention:     "GitHub Actions default (90 days); local test output is not retained"

discoverability_test:
  command:       "bash scripts/test-all.sh && bash scripts/lint-workflows.sh"
  expected_output: "test-all.sh reports all suites Pass with 0 Fail (baseline 225/225 in ~417 s on the scripts shard); lint-workflows.sh prints an explicit rc= that is 0 or 1, never 124, and itself exits 0 on both so the chain does not break on the expected findings state"
```

---

## Architecture Decision (ADR/C4)

### ADR

**1. Amend `ADR-149-…md` `## Consequences`** (Phase 5.2): restate counts, **publish the corrected derivation
command** (the `grep -L` form it currently publishes goes vacuous once gates carry the `declare -F` guard —
V1), and **correct the disproved sentence** at `:247-248`. Record that `stock-preflight-gate.sh` is sourced 8×.

**2. New ADR — `Extract the cutover-inngest run body to a checked-in script`** (Phase 5.4, in *Files to
Create*, verified by AC23). Phase 6 makes a repo file a **runtime dependency of a production cutover path**.
Record: the checkout dependency and the step-wording change protecting it; **the retracted claim** —
extraction is *posture-neutral* on `set -euo pipefail`, the real wins being that actionlint terminates and
shellcheck lints the body directly; the choice of `scripts/` over `.github/scripts/` and why; that
**`tests/scripts/lib/` is a production runtime path** — this PR takes `plan-gate-preamble.sh` from 1
consumer to 9, so one file now governs whether every destructive-infrastructure gate can fail closed, and a
future `tests/` reorg or sparse-checkout would disarm all of them at once; and the **rejected alternatives**
(the 13-arm step split, whose failure modes all fail OPEN and are undetectable by CI on a
`workflow_dispatch`-only workflow; and `exit 1` instead of `return 1` in the preamble, which would immunize
gates against a suppressing caller at the cost of a test-mode env var or subshell invocation in every suite).

The ordinal is provisional; `/ship` re-verifies against `origin/main`. If renumbered, sweep this plan,
`tasks.md`, and any AC naming it.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), read rather than grepped:

- **External human actors.** `founder` and `contributor` are the only human actors; no new correspondent,
  reviewer or recipient — the gates are pre-apply graders invoked by a workflow.
- **External systems / vendors.** The `#external` set (`anthropic`, `github`, `cloudflare`, `doppler`,
  `discord`, `stripe`, `plausible`, `resend`, `ghcr`, `letsencrypt`, `betterstack`, `sentry`, `sigstore`,
  plus zot/push/resolver entries) gains nothing. `actionlint`/`shellcheck` are developer tools, not services
  — consistent with a model that represents no linter.
- **Containers / data stores.** None touched. `platform.infra.hetzner`, `gitDataStore`, `sessionStore`,
  `workspacesVolume` and the registry are what these gates *grade plans about*; topology, ownership and
  relationships are unchanged. Phase 6 moves the *caller* of `platform.infra.inngest` from an inline `run:`
  body to a checked-in script; no edge added or removed.
- **Actor ↔ surface access relationships.** Unchanged — an existing pre-apply check gains the ability to
  classify a degraded document; who may reach what is untouched.

`views.c4` needs no new `include`; no element description is falsified.

### Sequencing

Deferral issues first (0.6) so Phase 5 and the drift check can cite real numbers; helper + harness (1) before
retrofits (3-4); prose (5) after the retrofits so the ADR never describes a state that does not exist.

---

## Domain Review

**Domains relevant:** Engineering

*(Product: NONE — the mechanical UI-surface override did not fire; no planned path matches any UI-surface
term or glob. Legal, Finance, Marketing, Sales, Support: no implications. Operations is subsumed by
Engineering — the only operational surfaces are `apply-web-platform-infra.yml`, which changes only in the
fail-closed direction, and `cutover-inngest.yml`, whose behaviour is byte-provably unchanged.)*

### Engineering

**Status:** reviewed (CTO at plan Phase 2.5; six-agent panel at plan-review)
**Assessment:** The CTO's three corrections were independently verified before folding in: web2-retire has
zero blast radius while `stock-preflight` is sourced 8× (inverting the stated priority); a `grep -q` guard
already exists and #7005 is open on the wider sweep; and the corpus is ~800 sites, not 38. The plan-review
panel then falsified five further premises — including two of three RED-first claims and the derivation
command the ADR publishes — and cut ~2,000 lines of scaffolding. All encoded in the phases, ACs and Risks.

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan)

### Product/UX Gate

Not applicable — Product assessed NONE and the mechanical UI-surface override did not fire.

---

## Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| **R1** | **Vacuity — the retrofit lands and the tests prove only that the preamble was SOURCED.** Sharpened by V2: the gates' own aborts carry the gate name, so the obvious anchor cannot bind. | Medium | Critical | AC3's A4 anchors on **preamble-distinctive** text and requires the signature to *disappear*; AC4's negative control blocks the always-abort degenerate; AC9's drift check anchors on the **call form**, not `grep -L`. The shared harness (1.5) writes this contract **once** rather than nine times. |
| **R2** | **The helper's shared predicate breaks its live consumer** (`git_data_host_birth_gate`, `:4053`). | Low | Critical | V6 ran the predicates: `.change.actions` is a closed enum of strings, so only the nested array is newly rejected, and that exists here only as a synthetic fixture. AC8 additionally gates Phase 3 on that consumer's suite — including after its harness migration. |
| **R3** | **Touching a live prod cutover that is mid-flight and already failing** (V9). | Medium | Critical | Extraction over splitting (V10) removes the step-boundary hazard class entirely; AC11's byte-exact un-normalized comparison is the evidence; the 6a/6b commit split keeps the move verbatim. |
| **R4** | **A future editor gates `actions/checkout`**, breaking every cutover op on a path with no CI signal. The step's own comment currently invites it. | Medium | Critical | Phase 6.3 rewrites the step name and comment **in this PR**; the ADR records the dependency. No CI signal exists here — the in-file wording *is* the mitigation. |
| **R5** | **A guard scans nothing and reports clean** — this PR's defect class in its own remedy. | Medium | High | Every `xargs` carries **`-r`**; the drift check asserts ≥ 12 files and catches off-glob names; the hooks guard keeps its non-vacuity probe. |
| **R6** | **The AC-verification commands themselves fail spuriously** — `grep -c` and `git grep` exit 1 on zero matches, which is the outcome several ACs assert is good. | Medium | Medium | Every such AC is written `… || true` or compares a captured count. Flagged in the AC preamble. |
| **R7** | **Scope collision with #7005** — two open issues over the same corpus, and #7005's own numbers are stale. | High | Medium | Non-Goal 3 + AC24: comment on #7005 with **corrected** figures, re-scope the remainder, state the slice relationship. `| head -1` explicitly left there and labelled deferred fail-open. |
| **R8** | **The actionlint baseline is unobtainable** — `origin/main`'s full-corpus run hangs — or the AC is written "exits 0" and can never pass. | Medium | Medium | AC16 compares against the **68-workflow** baseline and carves out findings newly visible on the extracted file. AC15 asserts only *not hung*. |
| **R9** | **#7024 is sold as a live fail-open it is not**, and an AC demands an unobtainable `rc=141`. | — | Medium | V12 records the measurement; AC18 requires 141 only from the **synthetic** harness and requires the real-input non-reproduction to be recorded; AC19 documents the top-injection arm as green-both-ways. |
| **R10** | **Post-retrofit prose goes stale again** — and the command it publishes goes *vacuous*. | Medium | Medium | AC22 requires both sites to publish the corrected command with matching current output, and Phase 5.1 preserves the "re-derive, do not remember" instruction. |
| **R11** | **`tests/scripts/lib/` becomes a production SPOF** — one file governs whether nine destructive gates fail closed, sourced at production runtime from a directory named `tests/`. | Low | Critical | Recorded in the new ADR (AC23) so a future `tests/` reorg or sparse-checkout has a written reason not to disarm every gate at once. No mechanical guard exists; naming it is the mitigation. |
| **R12** | **Local/CI loop slows.** The scripts shard is 417 s; the gate block grows. | Medium | Low | Measured: +17-32% projected. The shared harness builds D1-D6 **once per run** rather than per suite, recovering much of it. Named, not designed around. |
| **R13** | **One PR closing three issues is unreviewable.** | Medium | Medium | Commits are phase-scoped; Phase 1 lands alone, first; Phase 6a is a standalone verbatim move. #7002 is the most separable if review asks. |

---

## Test Scenarios

1. **Preamble invoked, not merely sourced.** A1 (D5) and A2 (D6) abort with preamble-distinctive text; both
   returned 0 pre-retrofit. *(D1/D2 are excluded — already aborting.)*
2. **A4 changes the failure MODE.** `mutate_layered` deleting the assert leaves the plan rejected but removes
   the preamble's signature; a no-op `sed` fails the `cmp -s` floor.
3. **Negative control (A3)** and **counter assert (A5)**.
4. **The measured `web-1` hole.** `web-host-birth-gate.sh` with `"actions": []` and `"after": null`:
   **PASS before, ABORT after.**
5. **Nested array + offender naming.** `[["delete"]]` aborts after Phase 1; a scalar `.change` still names its
   offender.
6. **Consumer regression + harness migration.** `test-git-data-host-birth-gate.sh` green after the helper
   change and after moving onto the shared harness, arm count unchanged.
7. **Drift check, three directions.** A synthetic 13th gate turns it red — including one that *sources but
   never calls* (proving the call anchor) and one named off the `*gate*` glob; an empty glob fails the ≥ 12
   floor rather than reporting clean.
8. **Message migration.** `test-registry-luks-recut-gate.sh:284,287` assert the preamble's strings after the
   inline checks are deleted.
9. **actionlint terminates; CI reports.** `timeout 60 actionlint <file>` → rc ∈ {0,1}; the `ci.yml` guard
   exits 1 against `origin/main`'s pre-extraction workflow and passes on HEAD.
10. **Byte-exact extraction.** Parsed `run:` scalar vs script minus shebang: identical, no normalization.
11. **SIGPIPE, synthetic.** A >65,536-byte producer with an early match: `producer | grep -q PAT` → **141**;
    `grep -q PAT <<<"$var"` → 0. On the real inputs, 10/10 runs return 0 — recorded as non-reproduction.
12. **Hooks guard.** Passes on HEAD with the two new paths in scope and `.claude/hooks/`'s zero-invariant
    intact; exits non-zero against `origin/main`; unchanged by a comment containing the banned shape.
13. **Full suite.** `bash scripts/test-all.sh` green; scripts shard compared against 225/225 in 416.9 s.

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6.
- **`xargs` without `-r` on an empty stage makes the downstream command read STDIN.** Measured:
  `printf '' | xargs grep -L PAT` printed `(standard input)`. In a guard that is both a hang and a vacuous
  pass — this plan's other two defects at once, inside the derivation command for the first.
- **A `grep -L <symbol>` "is it called?" check is a PRESENCE check.** Once gates carry
  `if ! declare -F <symbol>`, the guard line alone satisfies it, so a gate that sources and never calls
  passes. Anchor on the **call form** (`-E '^\s*<symbol>'`). This exact command is published in ADR-149 and
  the preamble header.
- **An anchor that both the guard and the guarded can emit binds nothing.** The gates' own aborts carry the
  gate's name, so a gate-name anchor cannot tell a preamble abort from a gate abort — a mutation arm built on
  it is a redness detector, not a binding. Anchor on text only the new code can produce.
- **Never read `$?` after a pipe.** `actionlint … | head -20; echo "exit=$?"` reports *head's* 0.
- **`grep -c` and `git grep` exit 1 on zero matches** — the outcome an absence-AC asserts is *good*. Use
  `|| true` or compare a captured count; otherwise a passing state reads as a failure under `set -e`.
- **SIGPIPE from `grep -q` needs a producer larger than the pipe buffer.** At 16,892 bytes against a 65,536
  byte buffer it is unreachable — so "I could not reproduce it" is not evidence the shape is safe, and
  demanding `rc=141` from such a site is demanding the impossible. Prove the mechanism synthetically; fix the
  shape anyway; record the non-reproduction.
- **An append-at-the-bottom mutation arm cannot detect a SIGPIPE bug** even in principle — `grep -q` only
  early-closes on an **early** match.
- **Use the wide flag-cluster pattern `-[A-Za-z]*q`.** The narrow `-q` misses `-Eq`/`-iq`/`-Fq` — the exact
  miss that let two live sites survive #6998.
- **A ban-pattern that matches comments cannot be widened past a narrow pathspec** without matching its own
  documentation and its own probe line.
- **Asserts belong inside the gate function because they consume `$plan_json`, a function parameter** — not
  because file scope fails open. `set -e` is re-enabled before every gate `source`, so a file-scope failure
  fails *closed*. Getting the right answer from the wrong mechanism is still a defect when the mechanism ends
  up in an ADR.
- **When a `run:` body is too big, ask whether it should be a `run:` body at all.** Splitting across steps
  pays for the size reduction with everything a step boundary destroys, plus per-step `if:` conditions that
  fail OPEN when mistyped. Extraction pays nothing. Check for `${{ }}` first; with none, the move is verbatim.
- **Never normalize whitespace in a diff meant to prove a verbatim move** — normalization is exactly the
  transform that would hide a dedent error. Parse the YAML block scalar (YAML already dedents it) and compare
  byte-for-byte.
- **A byte-count proxy is not a substitute for the direct signal.** `rc=124` measures the deadlock itself.
  When a defect has a direct exit-code signal, guard on that and put the tool where it runs.
- **A mutation battery that stops at the function boundary cannot see the call site** — and counting those
  call sites is easy to get wrong: this plan said nine and there are nineteen, so a "≥ 9" floor would have
  passed while missing half.
- **`jq -e` on a filter that ERRORS exits 5, and `if jq -e …; then` reads that as "condition false"** — which
  is why classifiability must be a positive `all(…)` assertion. The same trap applies to the
  **offender-extraction** filter: without `?` it raises on the entry it is trying to name, and the operator's
  only diagnostic goes blank while the verdict stays correct.
- **`all(…)` over an empty array is `true`.** `"actions": []` satisfies a type-only check and is invisible to
  `any(…)` and `index("delete")`. `length > 0` is not pedantry — it catches a real `web-1` destroy.
- **Do not "correct" ADR-149's or the header's counts at the start of this work** — they are already right.
  They become wrong only *after* the retrofit, which is why the prose edit is Phase 5.
- **"Tier 2" does not mean low blast radius.** `stock-preflight-gate.sh` is tier-2 and sourced **8×**;
  `web2-retire-gate.sh` is tier-1 and sourced by **no workflow at all**.
- **Check for an existing guard, whether it already runs in CI, and for an existing harness, before writing
  one.** `.claude/hooks/grep-q-pipe-guard.test.sh` is already swept by `test-all.sh:474`; `mutate_layered`
  already implements "removing the guard must change the failure signature, and a no-op `sed` must fail
  loudly" — the contract v1 wrote forty lines to invent.
- The AGENTS always-loaded budget is at **22900 / 23000** (WARN). Any instinct to add a rule rather than a
  guard must first run `python3 scripts/lint-agents-rule-budget.py …` and name the `wg-*` demotion that pays.
