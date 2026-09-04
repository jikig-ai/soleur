---
title: "Enforce the shell-trace credential refusal at commit time"
date: 2026-09-04
slug: fix-bash-x-secret-trace-guard
branch: feat-one-shot-7797-bash-x-token-guard
issue: 7797
closes: 7797
type: enhancement
lane: procedural
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
---

## Overview

Shell tracing echoes commands *after expansion*, so a secret leaks the moment it
is bound to a variable. Issue #7797 records two live API tokens reaching an agent
transcript this way.

PR #7793 fixed the affected script with a preamble that refuses to run when
tracing is on. That preamble exists in **1** of 932 tracked scripts. This plan
mechanizes it: a commit-time lint requiring the refusal in every shell script
that binds a credential, the 21 scripts reading the actually-leaked credentials
remediated in-PR, and a one-site scrub on the single genuinely unmasked CI
channel.

**Revised after a five-agent panel.** v1 proposed a PreToolUse hook; v2 a lint
with a CI-workflow arm. Both were cut on measured evidence. The revision log is
in `## Research Insights` — it is the substance of this plan, not an appendix.

## Research Insights

### Premise validation (Phase 0.6)

| Premise | Verdict |
|---|---|
| #7797 open; PR #7793 merged with `curl --config -` | HOLDS |
| No hook detects `bash -x`; no ADR decides the mechanism | HOLDS |
| Highwater/ratchet prior art exists | HOLDS — 4 `.highwater` + 2 baseline files |
| `--changed --base REF` is opt-out; new untracked files count | HOLDS — `lint-credential-path-literals.py` |
| *"Fix (1) already shipped the prevention"* (brief) | **STALE** — it closed the argv vector only |

### Corrections to my own measured claims

Each was asserted from a grep I did not scrutinise, and each was falsified by a
reviewer or a re-measurement. They are recorded because the plan's credibility
rests on the ones that survived.

1. **"The trace vector is undefended"** → it is defended, in 1 script.
2. **"2 of 932 scripts carry the refusal"** → **1**. The second hit was
   `hook-input.sh` anchor `case "$-" in *f*` — a noglob test, not xtrace.
3. **"The argv→stdin sweep buys zero trace-vector protection"** → **false, and
   materially so.** Measured: xtrace is *not* inherited across `exec` or a child
   invocation (bash does not export `SHELLOPTS`). A traced parent calling
   `./child.sh "$TOK"` prints `+ ./child.sh <TOKEN>` and the child's preamble is
   **inert** — it sees `$- = hB`. For that shape argv hygiene is the *only*
   defense. The sweep buys real protection and its deferral rationale is
   corrected accordingly.
4. **"A CI log is a transcript the hook cannot see"** → true but weak as stated.
   GitHub Actions auto-masks `secrets.*` in log output including xtrace lines.
   The genuinely unmasked channel is narrower and better — see below.
5. **"`apply-web-platform-infra.yml` warns at two anchors"** → 5 anchors across
   3 workflows.
6. **"Lint suites register via `SUITE_GLOBS`"** → false for `scripts/*.test.sh`.
   `test-all.sh` says so itself at anchor `scripts/*.test.sh is NOT
   auto-globbed here`. Registration is an explicit `run_suite` line (182 exist).

### The property, corrected

The guard is **process-local**. Measured, a traced parent that binds a secret
and `exec`s a guarded child leaks before the child's preamble runs. The honest
property is therefore:

> A script does not emit, via **its own shell's** xtrace, a credential it itself
> binds.

v2 claimed "no expanded secret reaches any transcript," which is strictly wider
than the assembly delivers — the exact window-vs-property mismatch
`scripts/lint-guard-contract.py` exists to reject.

### Why the lint, not the hook

Two reasons survive the panel; the third was cut.

1. **Completeness by construction.** `case "$-" in *x*)` tests whether tracing
   is *on*. A hook enumerates the ways to turn it on — measured at eight forms,
   three carrying no `-x` token (`env SHELLOPTS=xtrace`, `env BASH_ENV=…`,
   `BASH_XTRACEFD`). That list cannot be proven complete; the state test needs
   no list.
2. **The scaffold is proven.** `lint-trap-tempfile-ownership.py` already walks
   *every tracked `*.sh`* with `--changed` and a highwater.
3. ~~CI coverage.~~ **Cut.** See below.

**Known limits of the state predicate, stated rather than implied:**

- It is point-in-time, not an invariant. A `set -x` *below* the preamble leaks
  everything after it — measured, 2 token lines from a file with a compliant
  preamble. This plan therefore adds a **second rule** (Rule B) rather than
  pretending the preamble covers it.
- A `BASH_ENV`-installed `DEBUG` trap gives per-command echo with no bit in
  `$-` or `SHELLOPTS`. `BASH_ENV` is inside the stated threat model, so this is
  a named hole, not an out-of-scope one.
- The `SHELLOPTS` arm is unreachable in bash (`env SHELLOPTS=xtrace` already
  sets `x` in `$-`). Kept as belt-and-braces and commented as such, so the next
  reader does not delete the load-bearing arm by mistake.

### Why the CI arm is cut

All five reviewers converged on this independently.

- **Zero live population.** No workflow or composite action enables tracing.
  All 6 grep hits are comments *forbidding* it.
- **It reintroduces the defect that killed the hook.** Detecting "enabling
  tracing" in a YAML `run:` body is an enumeration of spellings with no `$-` to
  lean on — including `shell: bash -x {0}` and `ACTIONS_STEP_DEBUG`, which v2
  did not list. The Guard Contract's "no list of trace spellings" claim was
  false for that half.
- **It is not the reused walker.** It needs a YAML loader and two schemas
  (`jobs.*.steps[].env` and composite `runs.steps[].env`); 100% new code.
- **The real channel is elsewhere and cheaper.** `sweep-followthroughs.sh`
  captures probe output (`out=$(… "$script" 2>&1)`) and posts it to a **public
  GitHub issue comment** via `gh issue comment --body-file -`. Issue-comment
  bodies do not pass through the runner's masker. One scrub at that site
  protects all 76 probes; a per-workflow form lint would not have covered it.

Filed as a follow-up in the shape the repo already uses for this class — a form
lint, sibling to `lint-workflow-errexit-capture.py`, with its own Guard Contract.

### Blast radius, measured

16 of the 22 credential readers are `scripts/followthroughs/*.sh`.

- The sweeper invokes probes under `env -i PATH=… HOME=…`, which **strips
  `SHELLOPTS` and `BASH_ENV`**, and xtrace does not cross `exec`. So under the
  sweeper the preamble is near-inert; its value for these 16 is the **local**
  `bash -x` case. Stated so the diff is not read as closing a CI hole.
- Exit-code contract: the sweeper maps `0`→PASS/close, `1`→FAIL/comment, **any
  other**→TRANSIENT. A refusal exit therefore comments every sweep forever on an
  open issue and produces **zero signal** on a closed one
  (`sweep-followthroughs.sh` anchor `TRANSIENT on a closed issue: no action AND
  no comment`). `followthrough-convention.md` names the never-converging shape
  as an anti-pattern, so the contract change is in scope.
- **`exit 64` is already `EX_USAGE` in 57 files.** The preamble must not reuse
  it. This plan uses **78** (`EX_CONFIG`), unused in the repo.

### Detection base rate, measured

| Detector | In scope / 932 |
|---|---|
| Naive (any token vocabulary) | 346 |
| Refined, `doppler run` **removed** (it binds nothing in the parent — 87 files, 39 with no secret expansion at all) | 248 |
| …excluding `*.test.sh`, `tests/`, `fixtures/` | 170 |
| …minus the 21 remediated in-PR | **149 deferred** |

Reproduce with:

```sh
git ls-files '*.sh' | while IFS= read -r f; do
  sed 's/^[[:space:]]*#.*$//' "$f" | grep -qE \
    '\$\{?[A-Za-z_][A-Za-z0-9_]*_(TOKEN|KEY|SECRET|PASSWORD|PAT)\}?|[A-Z][A-Z0-9_]*_(TOKEN|KEY|SECRET|PASSWORD|PAT)=\$\(|doppler secrets get|gh auth token' \
    && echo "$f"; done
```

The remediation subset (22 readers of `SENTRY_AUTH_TOKEN` /
`BETTERSTACK_API_TOKEN*`, of which 1 is already compliant) contains **zero**
test files — verified, because a bare-name grep returns 35 including 6 tests and
the expansion-anchored form excludes them.

### Constraints inherited from prior learnings

- **`2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md`** —
  same issue lineage as this work, and v2 failed to cite it. *"If it blocks a
  state you would need to recover from, that is a P1 whether or not anyone has
  hit it."* This is why Rule A ships an escape hatch.
- **`2026-08-10-a-guard-that-cannot-be-driven-red…`** — floors absolute; the
  deletion direction must redden.
- **`2026-08-13-i-wrote-two-guards-against-vacuity…`** — the anti-vacuity
  assertion must `exit 1` directly.
- **`2026-08-02-a-guard-that-derives-authority…`** — do not re-implement an
  authority's predicate.
- **ADR-157** — a gate that cannot evaluate must not silently pass.

## Open Code-Review Overlap

63 open `code-review` issues queried; #7218, #7208, #2348 mention
`.claude/hooks/` but touch none of this plan's files. **Acknowledge.**

## Files to Create

- `scripts/lint-shell-trace-credential-refusal.py`
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` — an **enumerated
  path list**, not an integer (see Phase 5).
- `scripts/lint-shell-trace-credential-refusal.test.sh`
- `scripts/fixtures/shell-trace-refusal/` — fixture corpus.

## Files to Edit

- The 21 credential readers — add the preamble.
- `scripts/sweep-followthroughs.sh` — scrub `^\+` lines from captured output
  before posting to an issue comment.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` —
  document exit 78.
- `scripts/test-all.sh` — explicit `run_suite` line (NOT glob-covered).
- `.github/workflows/ci.yml` + `scripts/required-checks.txt` — see Phase 6.
- `knowledge-base/engineering/architecture/principles-register.md` — one AP row.

**Dropped:** `AGENTS.md`/`AGENTS.rules.md` — budget authority returned
`B_ALWAYS=46000`, at the ratchet. The principles register is the zero-per-turn
home for the convention instead.

## Implementation Phases

### Phase 0 — Preconditions (DONE 2026-09-04)

Budget at ratchet; highwater prior art confirmed; remediation subset measured at
22/1-compliant; `exit 64` collision measured at 57 files; sweeper exit contract
and `env -i` behaviour read.

### Phase 1 — ADR + principles register

Write the ADR at the **general** altitude, not as "we picked a lint":

> Where a hazard is a property of runtime STATE, enforce it with a self-refusal
> the artifact carries, gated at commit time by a walker over every member —
> not with a boundary interceptor that must enumerate the ways to reach that
> state. The interceptor is the complement, scoped to what is never committed.

Cite ADR-198 and commit `223da596f` (same credential class, argv vector) and
carry Correction 3, so the two are not later read as duplicates. Add the
matching AP row. Re-verify the ordinal against freshly-fetched `origin/main`
before merge.

### Phase 2 — Mutation matrix, written first

### Phase 3 — The lint: two rules

**Rule A — prologue.** An in-scope file must carry the preamble within its first
executable lines, before any command other than `set`/`shopt`. Stated as a
prologue rule, not "before the first bind", because the latter couples the
ORDER dimension to the drifting `SECRET_SIGNALS` list (adding a class could
retroactively fail a file that passed yesterday) and is undecidable anyway —
function hoisting, `source` above the preamble, and quoted heredocs all defeat a
static bind-detector in both directions.

**Rule B — no trace enable below the preamble.** An in-scope file must contain
no trace-enabling token after the preamble line. This is the rule the five
workflow anchors are actually warning about, it is statically decidable, and it
closes the point-in-time gap in Rule A.

**Escape hatch (mandatory).** Every sibling lint ships one. The preamble permits
tracing when the credential is provably absent — refuse only when a
`SECRET_SIGNALS`-named variable in scope is non-empty — and the refusal message
names the path: `re-run with SENTRY_AUTH_TOKEN= to trace safely`. A hatch that
lets a *populated* credential through is a mutation row.

**Scope exclusions**, each with a recorded reason: `*.test.sh` and `tests/**`
(synthesized fixtures per `cq-test-fixtures-synthesized-only`, and they are the
files most needing traceability); `scripts/lib/*.sh` (a sourced `exit`
terminates the parent).

Exit codes mirror `lint-credential-path-literals.py`: 0 / 1 / 2, with
unparseable → 2 scoped to the scanned set so one malformed file does not redden
every PR.

### Phase 4 — Remediate the 21, then the sweeper scrub

Preamble first, baseline after, so the baseline records only the deferred set.

### Phase 5 — Enumerated baseline

A path list, not a count — the precedent is
`lint-window-closure-assertion.allowlist.txt`. A bare integer cannot say *which*
149, so nobody can pick up the next ten. Measured: no `.highwater` in this repo
has ever been deliberately driven down. Drawdown trigger, enforceable by the
`--changed` mode already being built: **any PR that edits a listed script must
remediate it.**

### Phase 6 — Wiring, decided not inherited

`lint-trap-tempfile-ownership.py` runs in `lint-bot-statuses`, which is
**advisory** — a PR merges with it red. For a credential guard that is theatre,
so this lint goes in `scripts/required-checks.txt` and the ruleset. The #6049
auto-fabrication content gate applies and is in scope.

### Phase 7 — File three follow-ups, each with a re-evaluation trigger

1. **PreToolUse hook** — residual: ad-hoc `bash -c` and uncommitted scripts.
   Trigger: a second trace-leak incident from an uncommitted script.
2. **CI form lint (Guard 2)** — sibling to `lint-workflow-errexit-capture.py`,
   own Guard Contract. Trigger: the first workflow that enables tracing.
3. **argv→stdin sweep** — rationale **corrected**: it defends the traced-caller
   shape, which no callee preamble can. Trigger: any PR touching a listed
   caller.

## Guard Contract

### Guard 1 — lint-shell-trace-credential-refusal

**Property.** Every in-scope shell script refuses to emit, via its own shell's
xtrace, a credential it itself binds — by carrying the refusal in its prologue
(Rule A) and enabling no tracing below it (Rule B).

**Assembly.** The chokepoint is the walker over every tracked `*.sh`, reused
structurally from `lint-trap-tempfile-ownership.py`. Two member lists drift:
`SECRET_SIGNALS` (4 classes after cutting `doppler run`) and, **for Rule B
only**, `TRACE_TOKENS`. Rule A quantifies over no trace-spelling list — the
preamble tests state. Naming `TRACE_TOKENS` explicitly is the correction to v2,
which claimed the whole guard was list-free while its CI arm depended on a list.

**Mutation matrix:**

| # | Edit | Fixture that must redden | Targets |
|---|---|---|---|
| 1 | Drop a `SECRET_SIGNALS` class | script whose only signal is that class | list drift |
| 2 | Accept the preamble anywhere in the file | preamble at line 200 | Rule A prologue |
| 3 | Drop a `TRACE_TOKENS` spelling | `set -o xtrace` below the preamble | Rule B list drift |
| 4 | Skip Rule B entirely | compliant preamble + `set -x` below it | Rule B window |
| 5 | Make the walker yield nothing | every violation fixture | **own dispatch** |
| 6 | Treat unparseable as clean | malformed fixture | fail-closed (assert exit **exactly 2**) |
| 7 | Let the escape hatch pass a populated credential | hatch fixture with the var set | hatch integrity |
| 8 | Make the baseline advisory upward | fixture adding a new violation | ratchet direction |

**Harness rows:**

| # | Edit to the suite | Expected |
|---|---|---|
| H1 | Delete a mutation row's assertion | absolute floor fails via direct `exit 1` |
| H2 | Stub the runner to always report a violation | must-PASS row catches it |
| H3 | *must-PASS:* a compliant script differing from canonical in comment text and bind style | passes |
| H4 | *must-PASS:* an excluded `*.test.sh` binding a synthesized token | not reported |

## User-Brand Impact

**If this lands broken, the user experiences:** no leak and no symptom — the
hazard. A lint that scans nothing, or whose baseline goes advisory upward,
reports green while the class regresses, and the false confidence stops anyone
adding the preamble by hand. Rows 5 and 8 exist for those two shapes.

**If this leaks, the user's data is exposed via:** nothing this change adds. The
lint reads source and writes a path list. The one runtime edit — the sweeper
scrub — strictly removes content from a public comment.

**Over-enforcement is the second failure mode**, and it is the one the repo has
already been bitten by on this exact issue lineage: a guard that blocks a
recovery path gets deleted, taking the protection with it. Defended by the
escape hatch, the `*.test.sh` exclusion, and must-PASS rows H3/H4.

**Brand-survival threshold:** aggregate pattern. The threshold asks what happens
*if this lands broken*; a broken lint leaks nothing. Downgraded from
`single-user incident` after the CTO consult noted v2's impact section described
the *incident's* blast radius rather than the *guard's*.

## Observability

```yaml
liveness_signal:
  what: lint exit code plus scanned-file count, in a required CI check
  cadence: per PR
  alert_target: CI job status (blocking, per Phase 6)
  configured_in: .github/workflows/ci.yml + scripts/required-checks.txt
error_reporting:
  destination: lint stderr; violation lines name file, offending line, and the
    paste-ready preamble text
  fail_loud: unparseable and git errors exit 2, never 0
failure_modes:
  - mode: scans nothing, reports green
    detection: mutation row 5 + absolute scanned-count floor
    alert_route: CI failure
  - mode: baseline absorbs a new violation
    detection: mutation row 8
    alert_route: CI failure
  - mode: trace enabled below a compliant preamble
    detection: mutation row 4
    alert_route: CI failure
logs:
  where: CI job output
  retention: per GitHub Actions retention
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py
  expected_output: exit 0, scanned count at or above the floor
```

## Domain Review

**Domains relevant:** engineering. No UI-surface path; no regulated data; no
operational process change beyond the documented sweeper exit contract.

### Engineering

**Status:** reviewed — five-agent panel plus a CTO ruling and a scoped advisor
consult. CTO ruled lint over hook; adopted, with its grandfathering gloss
rejected (all 259 would have been unprotected on day one, so the 21 that read
the leaked credentials are remediated in-PR). The panel then cut the CI arm
unanimously, corrected the Property to process-local, replaced the ordering rule
with a prologue rule, and surfaced the unmasked issue-comment channel that
replaced the CI-log argument entirely.

## Acceptance Criteria

### Pre-merge

1. `bash scripts/lint-shell-trace-credential-refusal.test.sh` exits 0.
2. Mutation rows 1–8 each drive the suite RED against a pristine copy; the suite
   exposes a `--mutate N` mode so CI can re-run the matrix rather than relying
   on a claim recorded in a PR body.
3. Harness rows H1–H4 behave as tabled.
4. The assertion floor is an absolute integer recorded from a measured green run
   **after** Phase 4 remediation, asserted via a direct `exit 1`.
5. A run scanning zero files fails.
6. Each remediated script carries the preamble in its prologue, verified by the
   lint, and uses exit **78**.
7. `cutover-verify.sh` still passes unchanged apart from its exit-code update.
8. The baseline contains none of the 22 credential readers, and its membership
   is asserted as a set, not a count.
9. The malformed fixture exits **exactly 2**.
10. An excluded `*.test.sh` binding a synthesized token is not reported.
11. The violation message emits paste-ready preamble text, and a fixture asserts
    that emitted text itself passes the lint.
12. `scripts/sweep-followthroughs.sh` strips `^\+` lines before posting; a
    fixture asserts a traced probe's output cannot reach the comment body.
13. `followthrough-convention.md` documents exit 78.
14. The lint is in `scripts/required-checks.txt` and the ruleset.
15. `bash scripts/lint-orphan-test-suites.sh` exits 0 with the explicit
    `run_suite` line present.
16. The ADR and AP row exist; ordinal re-verified against freshly-fetched
    `origin/main`.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **PreToolUse hook** (v1) | Cannot see committed-script coverage; depends on an unprovable trace-form list. Filed — it owns the uncommitted residual, which is where #7797 actually happened. |
| **CI workflow arm** (v2) | Cut unanimously: zero live population, reintroduces the enumeration defect, 100% new YAML code, and the real channel is the issue comment. Filed as Guard 2. |
| Preamble in *every* script | Fails the debugging property for 673 credential-free scripts and maximises the delete-the-guard risk. |
| Remediate all 149 in-PR | Unreviewable; the enumerated baseline plus the touch-it-fix-it trigger is the drawdown path. |
| Integer highwater | Cannot say *which* files. No repo highwater has ever been deliberately lowered. |

## Non-Goals

- Rotating any credential (`SENTRY_AUTH_TOKEN` is a credential-entry gate on
  #7797).
- DNS or cutover code.
- `PS4` / `DEBUG`-trap hardening — named as a residual hole, not closed.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `SECRET_SIGNALS` misses a bind shape | Row 1 keeps classes load-bearing; drawdown trigger adds classes over time |
| Over-enforcement gets the preamble deleted | Escape hatch, test exclusions, must-PASS H3/H4 |
| Baseline becomes permanent | Enumerated list + touch-it-fix-it trigger + row 8 |
| Traced caller leaks a callee's argv | Named residual; the argv sweep follow-up owns it, with the corrected rationale |
| `DEBUG` trap via `BASH_ENV` evades `$-` | Named residual in the Property's limits |
| Sweeper comments forever on a refusal | Exit 78 documented in the runbook; scrub removes the leak channel independently |

## Sharp Edges

- `env SHELLOPTS=xtrace` cannot be reproduced as `SHELLOPTS=xtrace bash s.sh` —
  the assignment hits a readonly error and tracing never turns on, producing a
  false negative. Use the `env` form. Made and corrected during planning.
- xtrace does **not** cross `exec` or a child invocation. A callee preamble is
  inert against a traced caller. This falsified a confident claim in v2.
- The preamble is point-in-time, not an invariant — hence Rule B.
- `exit 64` is `EX_USAGE` in 57 files. Use 78.
- The assertion floor must be recorded after remediation, from a measured run.
- `scripts/*.test.sh` is **not** glob-registered; `test-all.sh` says so itself.
