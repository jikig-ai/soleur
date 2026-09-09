---
title: "repo-write-boundary: prove no battery-reachable git fetch writes tags into the live repo"
type: feat
date: 2026-09-09
slug: feat-battery-tag-author-guard
branch: feat-one-shot-7917-battery-tag-author-guard
issue: 7917
closes: 7917
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# repo-write-boundary: prove no battery-reachable `git fetch` writes tags into the live repo

## Overview

`scripts/lib/repo-write-boundary.sh` softens a collision-free `refs/tags/*` **creation** to `REPORT`
when sibling worktrees share a ref store (ADR-207, exemption cell 6). That softening is live. Its
safety case is stated in ADR-207's own Consequences, verbatim:

> **The safety case rests on an author set that is NOT closed.** … #7795 removes two known
> battery-reachable authors (`plugin-delivery-canary.sh`, `run-migrations.sh`) and does not close
> the class: `worktree-manager.sh` and the rest of the `plugins/` and `.claude/hooks/` fetch
> population remain. This is the single largest accepted risk and must not be described as closed.

This work builds the guard that bounds that risk, and it builds it **RED first** so the population
is measured rather than asserted. Two prior passes reached opposite conclusions about the size of
that population; neither is taken on trust here, and the guard is what decides.

The plan also **reframes the property** the guard asserts, because the property as originally worded
is not statically decidable — see `## Problem Statement`. The reframing is the single most important
design decision in this plan and it is what makes a RED window meaningful.

## Research Insights

### Premise validation (plan Phase 0.6)

| Cited premise | Verified how | Verdict |
|---|---|---|
| Issue #7917 | `gh issue view 7917 --json state` → `OPEN`, `closedByPullRequestsReferences: []` | HOLDS |
| `scripts/lib/repo-write-boundary.sh` softens cell 6 | read; the arm reads `else printf 'REPORT\trefs\t%s (tag) was created\n'` after the collision conjunction | HOLDS |
| ADR-207 §2 anti-laundering invariant | read: "The `shared_store` predicate is read from the BEFORE snapshot and is never re-derived at classify time… There is deliberately **no** re-derivation fallback." | HOLDS |
| ADR-207 records the open author set | read; the Consequences bullet quoted in `## Overview` is present verbatim | HOLDS |
| `scripts/plugin-delivery-canary.sh`, `apps/web-platform/scripts/run-migrations.sh` were fixed | both carry `--no-tags`; `run-migrations.sh` carries the `#7795` rationale comment | HOLDS |
| `apps/cla-evidence/scripts/ccla-add.sh` precedent | present, with the quoted rationale comment on the two preceding lines | HOLDS |
| `scripts/lib/legal-base-ref.sh` passes `--no-tags` | present | HOLDS |
| `--print-suite-globs` returns 9 globs | measured: 9 | HOLDS |
| `scripts/*.test.sh` deliberately absent from `SUITE_GLOBS` | the array carries `scripts/lib/*.test.sh` only; the comment beside the registrations says so | HOLDS |
| `grep -cE 'run_suite .*scripts/[a-z0-9-]+\.test\.sh' scripts/test-all.sh` returns **77** | measured **78** | **STALE — the issue's figure has drifted by one.** No AC may hard-code it |
| "`tests/scripts/` appears in neither globs nor registrations" | measured: `tests/scripts/` is absent from the globs but **is** registered, by many explicit `run_suite` lines (`bash tests/scripts/test-*.sh`, `python3 -m unittest tests.scripts.*`) | **PARTLY FALSE.** It is invisible to the *glob* surface and to the `.test.sh`-anchored registration pattern, not to registrations as such |
| `repo-write-boundary.test.sh` has a `MIN_ASSERTIONS` not to be shared | measured `MIN_ASSERTIONS=57` | HOLDS |
| `.claude/hooks/ship-runbook-ssh-gate.sh` never invoked by its own test | its own `.test.sh` is pattern-only (it touches the hook once, as `bash -n "$HOOK"` — a syntax check) — but the hook **is** executed by `.claude/hooks/hook-input-contract.test.sh`, which loops `INSCOPE21` and runs `bash "$SCRIPT_DIR/$hook.sh"` | **REFINED — see the reachability finding below** |
| `lint-migration-fk-preconditions.sh` gated behind `--from-pr-diff` | **TRUE, with evidence.** No `run_suite` line names it; its `.test.sh` reaches it via the `apps/web-platform/scripts/*.test.sh` glob and invokes it four times, always with a file-path argument (the `else` arm). `--from-pr-diff` is passed exactly once in the repo, from `.github/workflows/tenant-integration.yml` | HOLDS |
| `worktree-manager.sh` fetches are all inside `cd`-guarded subshells | **FALSE as worded, TRUE in effect.** None of its ten fetch/pull sites is `cd`-guarded, `-C`-scoped or `GIT_DIR`-scoped *within the script*; containment is entirely in the callers, across seven distinct call shapes, and it currently holds | **REFRAMED — see the caller-discipline finding below** |
| the offender population is non-empty / is zero | a plan-time static walk over an over-approximated ~1500-file closure adjudicated **0** live-repo offenders | **NOT ADOPTED as a verdict.** It is a third static adjudication of the kind that already produced two contradictory passes. Phase 1's RED run decides |

### The reachability finding that reframes the deliverable

`.claude/hooks/ship-runbook-ssh-gate.sh` carries a bare `git fetch origin main 2>/dev/null || true`
with no `--no-tags` and no `git -C`. It is executed by the battery: `hook-input-contract.test.sh`
loops `INSCOPE21` (which contains `ship-runbook-ssh-gate`) and runs each hook. Read on its own,
that is an offender.

It is not, because every one of those executions is wrapped as
`out="$(cd "$sandbox" && … bash "$SCRIPT_DIR/$hook.sh" …)"` with `sandbox` under a
`mktemp -d -t hicroot.XXXXXXXX` root, and the helper's own header states the reason:
*"Run a hook from a NON-GIT temp CWD so the orthogonal, branch-dependent block-commit-on-main gate
resolves an empty branch and no-ops."*

**Two chains of static reasoning, both plausible, opposite verdicts, and the deciding datum was a
`cd` three call frames away.** That is the general case, not an unlucky one, and it is why the two
prior passes disagreed. A guard that tries to decide live-vs-fixture by static reading will be
wrong in both directions and silently. See `## Problem Statement`.

### The root set is already a runtime contract — do not hand-parse it

`scripts/test-all.sh` already carries `--enumerate <group>`, which runs the real registration path
(every `want_*` block, the `SUITE_GLOBS` expansion loop, the shard filter) and emits one
`SUITE_REGISTRATION\t<label>` line per registration through `_shard_enumerate_emit`. Measured:

```
env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash scripts/test-all.sh --enumerate all
  → 396 SUITE_REGISTRATION lines   (scripts 384, bun 7, webplat 4)
```

396 registrations is the `SUITE_GLOBS` ∪ `run_suite` union the issue's constraint 1 demands,
obtained **by construction** rather than by re-deriving it — the same argument `SUITE_GLOBS`' own
header already makes: *"Deriving turns a duplicated list into a contract."*

It emits only `$1`, the free-form display **label**. `scripts/lint-orphan-test-suites.sh` states
why the label is useless for this: *"run_suite's first argument is a free-form display LABEL, so a
pattern that accepts the path anywhere after `run_suite` followed by a space is satisfied by the label alone."*

So the root set needs the **argv**, and the cheap way to get it is a second, additive flag rather
than widening the record the shard-totality guard already consumes. See `## Technical Approach`.

### Measured shape of the registration surface (why a `.test.sh`-anchored parse is not enough)

| Interpreter (field after the label) | Count |
|---|---|
| `bash` | 177 (176 resolve to a literal path; the 177th is the glob loop's `bash "$f"`) |
| `python3` | 16 (`python3 scripts/lint-*.py` and `python3 -m unittest tests.scripts.*`) |
| `bun` | 5 (`bun test <file>`, and one `bun test plugins/soleur/` — a **directory**) |
| `env` | 2 (`env VITEST_SHARD=… …` for the web-platform vitest shards) |
| `node` | 1 (`node --test scripts/md-to-mrkdwn.test.mjs`) |
| **total `run_suite` lines** | **201** |

`scripts/lint-orphan-test-suites.sh`'s surface-1 regex ends in `\.test\.sh"?…$`, so it sees none of
`tests/scripts/test-*.sh`, none of the `python3` registrations, and none of the bun/node/vitest
ones. That exclusion is correct for the orphan linter — it answers "is every tracked `*.test.sh`
registered?" — and wrong for this guard, which quantifies over what the battery *executes*.

### Mechanisms already on `origin/main` that must be reused, not reinvented

| Mechanism | Reuse |
|---|---|
| `scripts/test-all.sh --enumerate <group>` | the root-set contract. Extend additively (new flag), never re-parse |
| `scripts/test-all.sh --print-suite-globs` | the glob half, and its exact invocation idiom `env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" …` — without unsetting the shard vars the enumeration silently shrinks to one leg, which is fail-open |
| `scripts/lint-orphan-test-suites.sh`'s non-zero-exit refusal on a derivation flag | copy the refusal: a derivation that fails must ERROR, never fall through to an empty root set |
| `apps/web-platform/scripts/run-migrations-schema-probe.test.sh`'s `_nt_all` / `_nt_ok` both-counts-asserted idiom | **the DESIGN CONSTRAINT only, not the regex.** Its rationale is exactly constraint 5 — *"Anchored on the whole fetch command, not a bare `--no-tags` grep: the flag landing on some other fetch would satisfy that while this site kept auto-following tags"* — and the both-counts-asserted shape (`_nt_all` and `_nt_ok` must agree) is worth copying. Its **regex is not reusable**: it anchors at column 0, requires a literal a literal `if !` prefix, requires the remote/ref to be exactly `origin main`, and its flag class `--[a-z-]+` rejects any flag containing `=` or a digit — so it would reject this guard's own must-PASS fixture `git fetch --quiet --no-tags --depth=1 origin main`. Write a new whole-command matcher and say so in the guard's header |
| `apps/web-platform/scripts/run-migrations-schema-probe.test.sh`'s ADR-193 vacuity floor (`if [[ $((PASS + FAIL)) -lt 5 ]]` reported **directly**, not through `fail()`) | the floor shape |
| `scripts/lib/repo-write-boundary.test.sh`'s `ck()` call-site counter + `passes+fails == asserted` conservation check | the accounting shape (its `MIN_ASSERTIONS=57` is **not** shared — constraint 3) |
| `scripts/lint-orphan-test-suites.sh`'s `EXCLUSIONS` / `DOUBLE_COVERED_ACK` array shape (`"path\|reason citing #NNNN"`) | the exemption-ledger shape |
| `scripts/guard-vacuity-floor.test.sh` (`MIN_FIRING_SUITES=38`) | the new suite must be **visible to it**: emit the floor in a syntax form its sweep recognises, and ratchet `MIN_FIRING_SUITES` in the same PR. A private floor the meta-guard cannot see is an unmutation-tested floor |

Genuinely new, and only this: the fetch-population classifier and its declared-exemption ledger.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — *"What is the cheapest edit that breaks the property this guard NAMES, while leaving the guard
  GREEN?"* and *"Slack between a floor and the measured value is not padding — it is the budget an
  attacker spends."* Drives the RED-first ordering and the exact-ratchet floors.
- `knowledge-base/project/learnings/2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md`
  — *"An anti-vacuity gate must not share a call path with the thing it guards… The remedy is not a
  better floor; it is a self-test that drives the helpers and reports through neither."* Drives the
  helper self-test that runs before any case and asserts **both** a matching and a non-matching
  input moved the counters.
- `knowledge-base/project/learnings/2026-09-08-my-guard-could-not-fire-and-the-sweep-stopped-at-the-gate.md`
  — `grep` exits 1 on no match and `set -e` promotes it out of a pipeline, killing the step before
  the floor is reached. Every search site is wrapped `{ grep … || true; }`. Also: *"A count
  comparison cannot detect an orphan — set-compare the SOURCES."*
- `knowledge-base/project/learnings/2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md`
  — *"A guard's WINDOW, CHOKEPOINT or IDENTIFIER SET is narrower than the property it names."* The
  load-bearing question is *"what is the smallest edit that adds a member my guard cannot see?"*
- `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md`
  — *"Give every fixture set **two** members on the axis the guard quantifies over"*, and
  `cq-assert-anchor-not-bare-token`: *"anchor on a phrase a comment cannot produce."*
- `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md`
  — *"on a fix PR, the new assertions are the least-audited surface in the diff."*
- `knowledge-base/project/learnings/2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md`
  — *"Run the control first and require GREEN, in the harness that will run the rows… Give every
  search-based assertion a non-empty guard that aborts rather than concludes."*
- `knowledge-base/project/learnings/2026-07-29-a-per-producer-fix-left-seven-siblings-live-and-four-misread-signals.md`
  — enumerate every component sharing the shape and make the enumeration a test.

### External verification (deepen-plan)

Git's own documentation and one local measurement, resolved during the deepen pass. Three of these
**corrected** the plan rather than confirming it.

| Claim | Source | Effect on the plan |
|---|---|---|
| `git -C ""` leaves the working directory unchanged | `git(1)`: *"If `<path>` is present but empty, e.g. `-C ""`, then the current working directory is left unchanged."* Measured independently on git 2.53.0: `git -C "" rev-parse --show-toplevel` printed the enclosing repo | **Confirms** deleting the `SCOPED` verdict, and makes mutation row 17 must-RED |
| `git push … refs/tags/…` writes to the **remote**, never the local ref store | `git-push(1)` | **CORRECTION** — it was in an earlier draft's verb set and is now out of class with a stated reason |
| `git clone`, `git checkout`, `git switch`, `git worktree add`, `git replace`, `git notes`, `git bundle unbundle` do not write `refs/tags/*` in the live repo | `git(1)` family docs; the last three write `refs/replace/*`, `refs/notes/*`, `refs/bundle/*` | **Bounds** the verb set, and each exclusion is now stated rather than merely absent |
| `git fetch --prune` without `--prune-tags` leaves tags alone | `git-fetch(1)` | **Confirms** ADR-207's own measured note that the sibling-routine tag event is creation, and only creation |
| An explicit `+refs/tags/*:refs/tags/*` refspec fetches tags **despite** `--no-tags` | `git-fetch(1)` | **Confirms** the `SUPPRESSED` negative conjunct is necessary |
| Precedence when both `--no-tags` and `--tags` appear on one command line is **not formally documented** | absence in `git-fetch(1)` / `gitcli(7)`; last-one-wins is convention, not contract | **CORRECTION** — the negative conjunct is justified as *conservative refusal to guess*, not as "`--tags` wins" |
| Reliably excluding heredoc bodies needs a real shell parser; no grep-shaped rule is correct in general | current shell-linting practice; `shellcheck` and `mvdan/sh` are the parsers that do it properly | **CORRECTION** — comment/heredoc exclusion is now declared best-effort, with its failure direction (false OFFENDER, never false green) stated and covered by AC33 |
| There is no mature mutation-testing framework for bash; `bats`, `shellspec` and peers provide none | survey of current tooling | **Confirms** the hand-rolled mutation harness is the only option, and that the assertion-floor / accounting-conservation approach this repo already uses is the state of the practice |

### Applicable AGENTS rules

- `hr-write-boundary-sentinel-sweep-all-write-sites` — *"When a plan adds a guard/sentinel asserting
  a property at write sites, enumerate ALL write sites where it applies — not just diff sites."*
  Skill-enforced at `/work` Phase 0. This plan's Phase 1 **is** that sweep.
- `cq-assert-anchor-not-bare-token`, `cq-write-failing-tests-before`, `hr-verify-repo-capability-claim-before-assert`.
- `wg-architecture-decision-is-a-plan-deliverable` — satisfied by the ADR-207 amendment below.

### Property list and cut list (plan Phase 0.6b)

**Properties the ask is really about:**

1. A `git fetch` the battery executes cannot write `refs/tags/*` into the operator's live repository.
2. That claim is measured, not asserted — the population is observed before anything is fixed.
3. The claim stays true as the battery grows: a new suite, or a new fetch in an existing one, is
   caught rather than absorbed.
4. The guard itself cannot pass while checking nothing.

**Cut list:**

| Mechanism the ask proposes | Property it buys | What already buys it | Disposition |
|---|---|---|---|
| Hand-parse `run_suite` lines with a bespoke `sed` | 1, 3 (root set) | `--enumerate` already runs the real registration path through the `run_suite` chokepoint | **CUT the parse**; extend `--enumerate` additively instead. The parse survives only as a *cross-check* arm (see Guard 2 mutation 3) |
| A second copy of the `--print-suite-globs` pattern list | 3 | the flag itself | **CUT** — read the flag, never re-copy the list |
| A bespoke per-site `--no-tags` assertion | 1 | `run-migrations-schema-probe.test.sh`'s `_nt_all`/`_nt_ok` idiom | **CUT the bespoke version**; factor the existing idiom into a shared helper |
| A private anti-vacuity floor | 4 | `scripts/guard-vacuity-floor.test.sh` already mutation-tests floors it can *see* | **KEEP the floor, but shape it so the meta-guard sees it**, and ratchet `MIN_FIRING_SUITES` |
| A new ADR | — | ADR-207 already records this exact risk in Consequences | **CUT**; amend ADR-207 in place |

### Value-proposition measurement (plan Phase 0.6c)

No cost or performance saving is claimed, so nothing to quantify. The claimed value is risk
reduction on a named, already-recorded accepted risk (ADR-207 Consequences), and the measurement
that stands in for it is the RED-window population count in Phase 1 and the post-fix count in
Phase 3. Runtime cost of the guard is source-grep only, no network, no suite execution — the
neighbouring `scripts/*.test.sh` shape suites it sits beside measure in the 0.1 s range.

### Plan-time reconnaissance — a sizing input, explicitly NOT the measurement

A read-only static walk was run at plan time to size the phases and, more importantly, to find the
construction hazards the classifier has to survive. **It is not the deliverable and it does not
discharge constraint 2.** It is one more static adjudication of exactly the kind that produced two
contradictory prior passes, it rests on caller discipline it cannot verify at run time, and it flags
its own residual uncertainty. The Phase 1 RED transcript remains the measurement.

What it found, with the parts that change the design marked:

| | |
|---|---|
| Root set, Surface A (globs, expanded) | 196 files |
| Root set, Surface B (`run_suite` operands) | 198 (197 files + 1 **directory** operand, `bun test plugins/soleur/`); 102 of the 198 are **not** `*.test.sh` |
| Union | 393 (overlap 1: `scripts/lib/frontmatter-strip.test.sh` — the entry `lint-orphan-test-suites.sh` already ACKs as double-covered) |
| Over-approximated transitive closure | ~1500 files |
| `git remote update` repo-wide | **zero occurrences** |
| Live-repo `git fetch` offenders adjudicated | **0** |

Every `worktree-manager.sh` and hook site adjudicated `SAFE-fixture` is safe **by caller discipline
only** — see the finding two subsections down. Two sites carry residual uncertainty that does not
change their verdict (`scripts/lib/legal-base-ref.sh` and `scripts/plugin-delivery-canary.sh` both
sit behind a cache-miss predicate whose outcome depends on the operator's object store at run time;
both pass `--no-tags`, so the deciding datum is not needed). One root's membership was derived by
pattern rather than enumeration: `bun test plugins/soleur/` expands at run time, and settling it
needs a file listing from bun rather than a glob.

**Consequence for phase planning, not for the ACs:** the reframed property's RED window is large
(every undeclared site, including the ~10 in `worktree-manager.sh`) while the original property's
offender count may well be zero. That is the expected shape and it is fine — the issue says either
answer ships, and if the population is zero the guard's value is keeping it zero.

### Three construction hazards the reconnaissance surfaced

**1. A pattern anchored on the literal token the literal token `git fetch` under-counts by at least five sites.**
Measured, the population is spelled in at least three forms:

| Form | Example site |
|---|---|
| `git fetch …` | `.claude/hooks/ship-runbook-ssh-gate.sh` |
| `git -c <k>=<v> [-C <p>] fetch …` | `scripts/bootstrap-ccla-watch-7922.sh`, `scripts/followthroughs/ccla-representative-icla-7922.sh`, `apps/web-platform/infra/generate-apex-rollback-pr.sh` |
| array argv in TS — `["fetch", …]` / `["git", "fetch", …]` | `apps/web-platform/server/workspace-sync.ts`, `apps/web-platform/server/session-sync.ts` (×2), `test/pre-merge-rebase.test.ts`, `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` |

The classifier's occurrence pattern must tolerate interleaved `-c`/`-C`/`--git-dir` options between
`git` and `fetch`, and must recognise the array form. This is the single most likely way for the
guard to be born narrower than the property it names — the exact class
`2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md` describes. It is
mutation row 12 and AC31.

**2. Two nested runners expand the closure at run time and are invisible to a static path walk.**
`apps/web-platform/infra/run-registered-suites.sh` derives its list from `run: bash …` steps in
`.github/workflows/infra-validation.yml` plus `git ls-files "${SOLEUR_INFRA_DIR}/**/*.test.sh"`, and
`.github/scripts/test/run-all.sh` globs `"$DIR"/test-*.sh`. Both are registered `run_suite` roots, so
a walker that only follows literal path references stops at them and silently loses their whole
sub-population. **That sub-population is about a quarter of the battery.** Measured on the branch
tip, `bash scripts/lint-orphan-test-suites.sh` reports
`walked 418 tracked *.test.sh against 6 registration surfaces (s1=96 s2=196 s3=115 s4=1 s5=14 s6=2)`
— 115 suites reachable only through the infra runner, against 196 from the globs and 96 from
explicit `.test.sh` registrations. `scripts/lint-orphan-test-suites.sh` already solved the first one — its surface 3
**delegates** to `run-registered-suites.sh --list` and asserts a `MIN_INFRA_DERIVED` floor on the
parse. The guard reuses that delegation rather than re-deriving it, and treats an unexpanded nested
runner as UNCLASSIFIED.

**3. `bun test <dir>/` is a directory operand.** `run_suite "plugins/soleur" bun test plugins/soleur/`
registers a tree, not a file. Expanding it by glob is an approximation; the honest expansion asks the
runner what it collects.

### `worktree-manager.sh`: containment lives entirely in the callers

Full enumeration, measured: **ten** `git fetch`/`git pull` sites plus three `git ls-remote`
(read-only, out of class) — `fetch_origin_branch_base()`, `update_branch_ref()` (three),
`heal_stale_branch()` (two), and **four inside `cleanup_merged_worktrees()`**, including the
`git fetch --prune` that `scripts/lib/repo-write-boundary.sh`'s own comment names as the cell-6
evidence. **None** of the ten is inside a `cd`-guarded subshell within the script, uses `git -C`
against a temp path, or sets `GIT_DIR`/`GIT_WORK_TREE`. Every one runs against the ambient CWD.

They adjudicate `SAFE-fixture` because every battery site that *executes* the manager first enters a
`mktemp -d` fixture whose `origin` is a local bare repo — across seven distinct call shapes. That is
caller discipline, and caller discipline has already failed here once: `lease-protects-active.test.sh`
now uses a fail-hard `cdx` because, on 2026-08-20, a bare `cd` escaped the sandbox and committed onto
a live feature branch in another worktree. The suites also carry a `#7833` tripwire aborting with
`exit 97` on inherited `GIT_DIR`/`GIT_WORK_TREE`.

This is the plan's strongest argument for closing these sites in Phase 3 rather than exempting them:
`--no-tags` converts safety-by-caller-discipline into safety-by-construction, at one token per site,
on the exact file ADR-207 names.

## Problem Statement

### Why the property as originally worded cannot be the guard's property

The issue asks for a guard that proves *no `git fetch` reachable from `scripts/test-all.sh` writes
tags into the **live** repository*. "Live" is a runtime property of the process's working directory
at the moment the fetch runs. Establishing it statically requires deciding, for every call site,
the CWD of every caller of every function that reaches it — across `( cd … && … )` subshells,
`cdx` helpers, `git -C`, `GIT_DIR`/`GIT_WORK_TREE` overrides, and `mktemp` roots chosen three
frames up. The `ship-runbook-ssh-gate.sh` finding above is a worked example where two competent
static readings reach opposite verdicts.

A guard that guesses is worse than no guard: under-approximating reachability is **fail-open and
silent**, and over-approximating without a declaration channel is noise that gets suppressed.

### The property that is decidable, and fail-closed

> **Every tag-authoring git command in the closure of executables the battery reaches either
> suppresses tag creation on its own command line, or carries a declared exemption on one of the two
> lines immediately preceding it.**

**"Tag-authoring command", not "`git fetch`."** ADR-207 cell 6 softens a tag *creation* by anything,
so a property scoped to fetches would be narrower than the cell it exists to keep safe — and
measurably so: `git pull` accounts for two of `worktree-manager.sh`'s ten sites, and a battery suite
creates a tag directly with `git tag -a`. The verb set is enumerated in `## Technical Approach`
Stage C.

This is decidable by grep, is fail-closed by default (unclassified ⇒ OFFENDER), and keeps ADR-207
cell 6 safe for the reason that matters: the cheapest way to satisfy it is to add `--no-tags`, which
makes the live-vs-fixture question **moot rather than answered**. Where `--no-tags` is genuinely
wrong (a fixture that must fetch tags to test tag handling, or a suite that must create one), the
site declares itself, and the declaration is the artifact a future reader can audit — which the
enclosing `cd` three frames up was not.

**What the reframed property does NOT prove, stated plainly.** `EXEMPT` is an accepted risk, not a
proof: an exempted site that does write a tag into the live repo produces no guard failure, and
cell 6 renders it `REPORT`, not `FATAL`. So the guard bounds and enumerates the battery's tag
authors; it does not eliminate them. Phase 3 therefore requires each exemption to state why
`--no-tags` (or an equivalent suppression) *specifically breaks that site* — "it is fixture-scoped"
is not a reason, because that is the undecidable claim the reframing exists to stop relying on. This
paragraph is load-bearing and must reach ADR-207 verbatim; see `## Architecture Decision (ADR/C4)`.

The `-B2` window in constraint 4 is exactly this declaration channel: the exemption marker must be
one of the two preceding lines, so the acceptance check that reads it is the same check that grades
the site.

**Why 2 and not 1 or 3, and the limitation that comes with it.** Two is the issue's stated
constraint, and it is defensible on its own terms — one line forbids a marker that needs a
continuation, and a wider window starts absorbing unrelated commentary, so the declaration stops
being adjacent to the thing it declares. The cost is real and is declared rather than hidden: an
interposed line between the marker and the command — a `# shellcheck disable=…` directive is the
likely one — silently voids the exemption, and the site then reads as declared to a human and
undeclared to the guard. That is a **fail-closed** failure (the site grades OFFENDER and the run
reddens), so it costs an author one confusing minute rather than costing the operator a tag. The
guard's failure message for an OFFENDER carrying a marker outside the window says so explicitly.
Mutation row 4 pins the boundary.

### Why it must be built RED first

The cut guard in the #7795 plan was authored **after** the fix that made the tree clean, so it never
had a RED window and nothing proved it could fire. Phase 1 here builds and registers the guard and
captures its verbatim output naming every site, **before any site is touched**. That transcript is
the measurement the issue asks for, and it is a required acceptance artifact.

## Proposed Solution

Four moving parts, in dependency order:

1. **`scripts/test-all.sh` gains `--enumerate-commands <group>`** — additive, emitting
   `SUITE_COMMAND` records with tab-delimited argv, and `SUITE_COMMAND_DECLINED` for `skip_suite`.
   It sets `_ENUMERATE=1` alongside its own mode flag so all nine existing `_ENUMERATE` conjuncts
   apply, and `SUITE_REGISTRATION` output is unchanged apart from the one line this PR's own
   registration adds.
2. **`scripts/battery-tag-authorship.test.sh`** — the guard. Derives roots from
   `--enumerate-commands all`, walks to an over-approximated closure, classifies every tag-authoring
   command across both the verb and spelling axes, reports offenders by `path:line` with the command,
   and carries its own floors, ledger bijection and self-test.
3. **The measured offenders are closed** — a suppression where that is right, a declared exemption
   stating why suppression specifically breaks that site where it is not.
4. **ADR-207 gains a numbered section** carrying the reframed property, the accepted-risk nature of
   `EXEMPT`, and the exemption ledger's governance — plus a cell-6 ledger row naming the guard. No
   measured population figure is transcribed into the record; the guard is the live count.

## Technical Approach

### Architecture

#### Part 1 — `--enumerate-commands`, the root-set contract

`run_suite() { local label="$1"; shift; … }` — after the shift, `"$@"` is the command. `skip_suite`
takes `<label> <reason> <rerun>` and its `$3` is the rerun command string. Both already carry an
`if (( _ENUMERATE == 1 ))` arm.

Add a sibling mode emitting a distinct record — see the flag-inheritance requirement immediately below, which is what makes this safe:

```bash
_shard_enumerate_command_emit() {   # <label> <argv…>
  local label="$1"; shift
  printf 'SUITE_COMMAND\t%s\t%s\n' "$label" "$*"
}
```

**`--enumerate-commands` MUST set `_ENUMERATE=1` as well as its own `_ENUMERATE_COMMANDS=1`.** This
is the single highest-consequence detail in Part 1, and an earlier draft got it wrong by saying the
new mode is "gated on its own variable". `--enumerate` is **not** an early-exit flag the way
`--print-suite-globs` is: it sets `_ENUMERATE=1`, shifts, and then falls through the entire runner,
because registrations only exist far below in the `want_*` blocks. Its side-effect suppression is
**nine scattered `_ENUMERATE` sites**, measured:

| `_ENUMERATE` site | What it suppresses |
|---|---|
| the `--enumerate` argv parse | sets the mode |
| the `SOLEUR_SUBAGENT` full-gate refusal (`_ENUMERATE == 0` conjunct) | exempts the refusal |
| `run_suite`'s arm | the emit |
| `skip_suite`'s arm | the emit |
| the `tc_preamble` / `tc_tmp_entry_count` stubbing block | neuters a ~5.7 s `/proc` walk and its PID stamp |
| the `TC_SIBLING_RUN_COUNT` refusal (`"$_ENUMERATE" == "0"` conjunct) | exempts the sibling-gate refusal |
| `if (( _ENUMERATE == 1 )); then SOLEUR_DISABLE_SESSION_STATE=1; fi` immediately above `tc_acquire` | **the entire "takes no lock" property** |
| the epilogue arm | exits before `repo_boundary_classify` |

A mode on its own variable alone inherits **none** of them. The guard runs as a registered suite
*inside* a gate run that already holds the advisory lock, so it would reach `tc_acquire` and block up
to `TC_LOCK_TIMEOUT` — verbatim the hazard the `--print-suite-globs` block's own comment names:
*"the linter runs INSIDE the advisory lock this runner holds, so a code path that blocks on it would
deadlock the gate on itself."* It would also re-arm the sibling refusal (making the guard's colour a
function of another worktree), re-arm the subagent refusal, pay the `/proc` walk, and run a **second**
`repo_boundary_classify` nested inside the outer run's measurement window.

Setting both flags means every existing conjunct applies unchanged and the two modes differ in
exactly one branch: which emit function fires. Do **not** add a new conjunct to the
`TC_SIBLING_RUN_COUNT` statement — `plugins/soleur/test/fanout-suite-scope.test.sh` anchors on its
literal prefix at column 0.

**The record must preserve argv boundaries.** `printf '…%s\n' "$label" "$*"` joins on `$IFS` and the
resolver would then re-split on spaces, re-introducing the free-form string parse this design
removes — and `env VITEST_SHARD=… bash -c 'cd X && npm run …'` is unrecoverable from the joined form.
Emit tab-delimited argv (`printf '%s' "$1"; shift; for a; do printf '\t%s' "$a"; done`) or `${*@Q}`,
and state the delimiter and escaping contract in the record's own header comment.

**`skip_suite` emits a DIFFERENT record type.** Its `$3` is a human-facing rerun **string**, not
argv, and it has already drifted from the real command: for `apps/web-platform [unit]`, `run_suite`'s
argv is `env VITEST_SHARD="${VITEST_SHARD:-}" bash -c 'cd apps/web-platform && npm run test:ci -- --project unit …'`
while `skip_suite`'s `$3` is `cd apps/web-platform && npm run test:ci -- --project unit`. Nothing
executes `$3`, so nothing keeps it in sync — the same defect class this design uses to reject the
label. Emit it as `SUITE_COMMAND_DECLINED` so one record type never carries two types, and resolve it
on a best-effort basis into the out-of-class ledger rather than the root set.

Reasons for a **separate flag and a separate record type**, not a widened `SUITE_REGISTRATION`:

- `_shard_enumerate_emit` sits inside the hot `run_suite` path that also feeds the runtime ceiling
  and the shard-totality guard. The shard-totality guard already consumes `SUITE_REGISTRATION` per
  leg; widening that line is a behaviour change to a live consumer for no gain here.
- Additive means the parity assertion is trivial and mechanical: `--enumerate all` output must be
  byte-identical before and after (Guard 2, mutation 1).
- `skip_suite`'s emit uses its `$3` rerun string as the command, which is exactly the command the
  suite *would* have run — a relevance-declined suite is still battery-reachable and must not
  vanish from the root set.

The flag must be handled in the same early block as `--print-suite-globs`, **before any side
effect** — no `TMPDIR` export, no bare-repo guard, no `tc_acquire` — for the reason that block
already states: the linter runs inside the advisory lock this runner holds, so a code path that
blocks on it would deadlock the gate on itself.

#### Part 2 — the guard, in four stages

**Stage A — roots (constraint 1).** Invoke, with the exact idiom
`env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --enumerate-commands all`.
Non-zero exit, or zero records, is a hard ERROR — never a fall-through to an empty root set. From
each `SUITE_COMMAND` record, resolve the invoked file:

| argv shape | Resolution |
|---|---|
| `bash <path>` / `sh <path>` / `sudo bash <path>` | `<path>` |
| `python3 <path>.py` | `<path>.py` |
| `python3 -m unittest <a.b.c>` | `<a/b/c>.py` |
| `node --test <path>` | `<path>` |
| `bun test <path>` | `<path>` |
| `bun test <dir>/` | a **directory** operand (`run_suite "plugins/soleur" bun test plugins/soleur/`) — expand by asking the runner what it collects, and record the expansion method; a bare glob is an approximation and must be declared as one |
| `env VAR=… <interp> …` | strip leading `VAR=…` assignments, recurse |
| a **nested runner** (`apps/web-platform/infra/run-registered-suites.sh`, `.github/scripts/test/run-all.sh`) | delegate, reusing `lint-orphan-test-suites.sh`'s surface-3 idiom **verbatim** — `( cd "$REPO_ROOT" && INFRA_ORPHAN_LIST=/dev/null bash "$INFRA_RUNNER" --list )` — together with its declared-vs-parsed cross-check and a floor on the parse (its own is `MIN_INFRA_DERIVED=90`; re-measure rather than copying the literal). A nested runner left unexpanded is UNCLASSIFIED, never silently dropped |
| anything else | **UNCLASSIFIED — reported loudly and counted, never silently skipped** |

Then assert, per constraint 1, that the union is non-empty **and covers a known member of each
source** — three members, three sources, so losing any one source reddens:

| Member | Source it proves |
|---|---|
| `scripts/lib/repo-write-boundary.test.sh` | the `SUITE_GLOBS` glob half (`scripts/lib/*.test.sh`) |
| `scripts/suite-exit-class-parity.test.sh` | the hand-registered repo-root `scripts/*.test.sh` class the globs deliberately exclude |
| `tests/scripts/test-plan-gate-preamble.sh` | the `tests/scripts/` class invisible to both the globs and a `.test.sh`-anchored parse |

Plus a hand-ratcheted `MIN_ROOTS` floor, so a derivation that collapses to a handful reddens before
any classification runs.

**Stage B — closure.** From each root, collect referenced tracked executables and iterate to a
fixpoint under a stated depth bound: `bash <path>`, `source <path>`, `. <path>`, `"$REPO_ROOT"/<path>`,
`${CLAUDE_PLUGIN_ROOT:-…}/<path>`, and literal repo-relative paths bound to a variable that is later
invoked (the `WM="$REPO_ROOT/…/worktree-manager.sh"` … `bash "$WM"` shape, which appears in 17
battery suites). **Over-approximate deliberately**: any tracked executable path literal appearing in
a closure member joins the closure. Under-approximation is fail-open; over-approximation costs only
exemption entries, and those are visible and ratchet.

**Stage C — classify (constraints 4 and 5).** First, find the occurrences.

**The quantified VERB set is tag-authoring commands, not fetches — this is the correction that
renamed the guard.** ADR-207 exemption cell 6 reads `refs: a collision-free refs/tags/* **CREATED**`
— created by *anything*. A guard scoped to `git fetch` is literally true about fetches while green
over every other way a tag reaches the ref store, which is the "window narrower than the property it
names" defect the plan cites and would otherwise have committed one level down. Three measured
in-battery sites sit in that gap:

| Site | Command | Why the fetch-only pattern misses it |
|---|---|---|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, `update_branch_ref()` else arm | `git pull origin "$branch" \|\| true` | `git pull` is a fetch plus a merge and auto-follows tags identically. It is already inside this plan's own reconnaissance count of "ten `git fetch`/`git pull` sites" — counted in the measurement, dropped from the classifier |
| same file, `cleanup_merged_worktrees()` | `git -C "$GIT_ROOT" pull --ff-only origin main` | same, and `$GIT_ROOT` resolves through the common dir to the operator's live repository |
| `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh` | `git tag -a -m "sandbox pin fixture" "vinngest-$_pin_tag"` | a **direct** tag creation in a battery suite, safe only by an enclosing `( cd "$SANDBOX_ROOT" … )` — the same caller-discipline argument this plan declines to accept elsewhere |

So the occurrence set is: **`git fetch`, `git pull`, `git remote update`, `git tag` in its creating
forms, and `git update-ref refs/tags/…`.**

Out of class, each for a stated reason rather than by omission — the boundary is part of the
contract and belongs in the guard's header:

| Command | Why it is not in the set |
|---|---|
| `git push … refs/tags/…` | writes to the **remote**, never to the local ref store. An earlier draft of this plan had it in the set; that was wrong |
| `git clone` | creates `refs/tags/*` in the **new** repository it creates, which by construction is not the live one |
| `git tag -d`, `git tag --list` / `-l` | delete or read; create nothing |
| `git ls-remote` | reads the remote; writes no ref |
| `git checkout`, `git switch`, `git worktree add` | move `HEAD`, including to a tag, but never write `refs/tags/*` |
| `git replace`, `git notes`, `git bundle unbundle` | write `refs/replace/*`, `refs/notes/*`, `refs/bundle/*` — different namespaces |
| `git fetch --prune` (without `--prune-tags`) | prunes remote-tracking refs only; documented as leaving tags alone, which is also what ADR-207's own measurement found |

**Each verb must be matched in every spelling.** A pattern anchored on a literal token under-counts
by at least five measured sites, so each verb's pattern must also match:

- `git` followed by any interleaving of `-c <k>=<v>`, `-C <path>` and `--git-dir=…` options before
  the verb — e.g. `git -c gc.auto=0 fetch --no-tags …`, `git -C "$p" -c tag.gpgSign=false tag probe-tag`
- the TS array-argv form: `["fetch", …]`, `["git", "fetch", …]`, `["tag", …]`

`git remote update` has **zero** occurrences repo-wide as measured; the pattern still covers it so the
first one to arrive is caught.

**Comment and heredoc exclusion is best-effort, and the guard says so.** A full-line comment is
cheap to drop. A heredoc body is not: reliably excluding one needs a real shell parser, and no
grep-shaped rule gets it right in general. The guard therefore drops full-line comments, makes a
best-effort heredoc skip, and **declares both as approximations in its header** under AC33 — the
same honesty rule the `bun test <dir>/` expansion is held to. The failure direction is safe: an
un-excluded heredoc or trailing comment produces a **false OFFENDER**, which reddens and is fixed
by a declaration, not a false green.

**Widening the verb set widens the ledger, and that is the intended trade.** `scripts/lib/repo-write-boundary.test.sh`
creates probe tags on purpose (`git -C "$p" -c tag.gpgSign=false tag probe-tag`) — those become
declared exemptions, which is the correct outcome: the suite that tests the tag boundary is the one
place a deliberate tag author belongs, and saying so in the ledger is strictly better than a
classifier that cannot see it.

Then, for every occurrence, read it with `grep -n -B2` so the two preceding lines are in hand, and
grade:

| Verdict | Condition |
|---|---|
| `SUPPRESSED` | the **same command** matches an anchored whole-invocation pattern carrying `--no-tags` — flag order and extra flags tolerated — **and** carries no positive tag request on that same command: no `--tags`, no `-t`, no `refs/tags/` in any operand, no `tagOpt` in a `-c`. The negative conjunct is load-bearing and deliberately **conservative**: `git fetch --no-tags origin '+refs/tags/*:refs/tags/*'` is documented to fetch tags anyway (an explicit refspec takes precedence over the flag), and for `git fetch --no-tags --tags origin` the precedence is **not formally documented** — the implied behaviour is last-one-wins, so the guard refuses to guess and grades it OFFENDER rather than trusting an undocumented order. Only `git fetch`/`git pull`/`git remote update` can reach this verdict — a `git tag` creation has no suppressing flag and must be `EXEMPT` or `OFFENDER` |
| `EXEMPT` | one of the two preceding lines carries the declared marker `repo-boundary-tag-exempt: <reason> (#<issue>)` **and** the site appears in the guard's exemption ledger with a matching issue citation |
| `OFFENDER` | everything else |

**Three verdicts, and `git -C <path>` is deliberately NOT one of them.** An earlier draft graded a
`git -C …` fetch compliant on the reasoning that `-C` names a fixture. It does not — `-C` names
*which* repository, not that the repository is disposable, and two measured sites would have been
graded compliant while writing into the operator's live repo:
`apps/web-platform/infra/generate-apex-rollback-pr.sh` (`git -C "$REPO_ROOT" fetch -q origin main`)
and `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`, whose own preceding comment says
so in as many words: *"`git -C "$REPO_ROOT" fetch` below is a WRITE: it updates
refs/remotes/origin/main, appends to its reflog, and writes FETCH_HEAD into that repository."*
Grading `-C` compliant would have decided live-vs-fixture statically from a path expression — the
exact move `## Problem Statement` argues is undecidable — and would have done it fail-open. A
`-C`-scoped fetch that must follow tags declares itself like everything else.

And the path expression need not even name the live repo to reach it. Measured 2026-09-09 on
git 2.53.0, in a throwaway repo:

```
$ git -C "" rev-parse --show-toplevel
/tmp/gitCtest.uJRfWJ/probe
```

`git -C ""` is a **no-op** — it does not error, it runs in the current working directory. So
`git -C "$tmp" fetch origin main` with `$tmp` unset or empty runs against whatever repository the
caller is standing in, which is the failure ADR-207's Context names verbatim: *"a suite whose
fixture `cd` fails, or whose `git -C` operand is empty, runs git in the caller's live repository."*
An earlier draft made that shape a **must-PASS** mutation row; it is now must-**RED** (row 17).

The verdict is printed per site as `path:line\t<verdict>\t<battery-reachable?>\t<command>` so the
RED transcript is the measurement artifact.

**Stage C.2 — the exemption ledger is a BIJECTION, not a one-way check.** The marker does locality
(a reader at the call site learns why) and the ledger does census (a reviewer sees the cumulative
position) — the same two-place argument ADR-207 §3 makes for its own exemption list. But a
one-directional check is where offenders go to be forgotten, and this design quotes the fix without
applying it to itself: *"A count comparison cannot detect an orphan — set-compare the SOURCES."* So:

- **Both directions asserted.** Every ledger entry resolves to a live site currently graded
  `EXEMPT`, and every `EXEMPT` site has exactly one ledger entry. An entry whose file was deleted,
  whose site was later fixed with `--no-tags`, or whose marker a refactor removed is an **orphan**
  and reddens.
- **Site granularity, not path granularity.** `lint-orphan-test-suites.sh`'s `"path|reason"` shape
  would exempt *every* marked command in a file, so a copy-pasted marker on a new command in an
  already-exempt file would be silently absorbed. Key on path **plus the exempted command text**
  (line numbers drift), and state that key in the ledger's header.
- **The citation must stay live.** `(#7917)` is closed the moment this merges, after which every
  entry cites a dead reference and the citation carries no information. Each entry cites an **open**
  tracking issue for its removal, or a stated re-review trigger — the `wg-when-deferring-a-capability-create-a`
  shape.
- **A ceiling, paired with the bijection.** A ceiling makes an addition a decision rather than a
  drift, which is the right instrument for the growth axis — but on its own it is equally satisfied
  by an empty ledger and by a ledger full of ghosts. With the bijection in place the ceiling can be
  loose; without it, the ceiling measures nothing.

**Stage D — accounting and floors (constraint 3).** All private to this suite, none shared with
`repo-write-boundary.test.sh`:

- `ck()` incremented at the **call site**, never inside `pass()`/`fail()`, plus a
  `passes+fails == asserted` conservation check — the ADR-193 shape `repo-write-boundary.test.sh`
  already uses.
- `BATTERY_TAG_MIN_ASSERTIONS` — a distinct name, reported **directly** rather than through
  `fail()`, gated on assertions **executed**, in a syntax form `scripts/guard-vacuity-floor.test.sh`'s
  sweep recognises.
- `MIN_ROOTS` — a hand-ratcheted floor on the derived root set. **Ratcheting it DOWN is refused**:
  the guard fails if the committed value is below the previous committed value, so the only
  legitimate direction is up, and a shrinking registration surface reddens rather than being
  absorbed. That direction rule is what keeps the floor from decaying into a value people edit to
  make a run green.
- **Named-witness coverage instead of a `MIN_FETCH_SITES` floor.** An earlier draft carried a
  hand-ratcheted floor on the occurrence count. That instrument punishes the desired direction: it
  reds on any PR that legitimately *deletes* a fetch, whose only remedy is to lower the floor —
  training exactly the casual ratchet edits the anti-vacuity learning wants to prevent. (The
  learning's *"slack is the budget an attacker spends"* is about **assertion** floors, not
  population counts.) The anti-vacuity job is done instead by asserting the census contains named
  known sites in each spelling — see AC31 — which cannot be satisfied by a scan that found nothing
  and does not move when the population shrinks for good reasons.
- A **helper self-test** that runs before any case, drives `pass`/`fail`/`ck` with one matching and
  one non-matching input, asserts both moved the counters, and reports through neither helper.
  *(Dissent recorded: `code-simplicity-reviewer` argued this is a third instrument aimed at one
  failure mode and would cut it. Kept, because `2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md`
  is explicit that the remedy for that class is a self-test specifically — "The remedy is not a
  better floor; it is a self-test that drives the helpers and reports through neither" — and it
  costs about ten lines.)*

**Self-match and fixture hazards.** The guard's own source contains the literal strings `git fetch`,
`git tag` and `--no-tags`, and its mutation fixtures will contain them too. Two **separate,
separately size-asserted** exclusion arrays, not one:

- `SELF_EXCLUSION` — the guard's own path, exactly one entry.
- `FIXTURE_EXCLUSION` — the mutation fixtures' root.

Keeping these out of the exemption ledger is what lets AC18's ledger-vs-`EXEMPT` bijection be an
equality rather than an off-by-two.

#### Part 3 — where the guard lives and how it registers

`scripts/battery-tag-authorship.test.sh`, registered by an explicit `run_suite` line under
`want_scripts`, beside `scripts/test-all-webplat-gate.test.sh` and
`scripts/suite-exit-class-parity.test.sh` — the cluster whose own comment reads *"both assert shape
properties of test-all.sh that nothing else would notice rotting."* Repo-root `scripts/*.test.sh` is
deliberately not in `SUITE_GLOBS`, so the registration is explicit and
`scripts/lint-orphan-test-suites.sh`'s surface 1 fails if it is ever dropped.

**The registration's SHAPE and PLACEMENT are constrained by a second suite, and getting either
wrong reddens the battery in a place the diff does not touch.**
`plugins/soleur/test/scripts-shard-totality.test.sh` — glob-registered, and the only live consumer
of `--enumerate` — proves shard totality by comparing the runner's own enumeration against an
**independently derived reference set**. Half of that reference is a static extraction with a
narrow contract, read from its source:

```awk
/^if want_scripts; then$/ { inb=1; next }
inb && /^fi$/             { inb=0; next }
inb && /^[[:space:]]*(run_suite|skip_suite) "/ { … extract the quoted label … if (lbl !~ /\$/) print lbl }
```

So the new `run_suite` line must satisfy all three:

1. **Inside a column-0 `if want_scripts; then` … `fi` block.** A registration outside one is emitted
   by `--enumerate scripts` but invisible to the static extractor, so the two sets diverge and the
   totality comparison fails.
2. **A double-quoted literal label immediately after `run_suite`.** The extractor matches
   `run_suite "` with the quote adjacent; an unquoted or single-quoted label is skipped.
3. **No `$` in the label.** Labels containing `$` are deliberately skipped as the glob loop's
   `run_suite "$f"`, so a variable-bearing label would be dropped from the reference and kept by the
   enumeration.

The three suites named as neighbours all satisfy this, which is a second reason to register beside
them rather than anywhere else under `want_scripts`.

### Implementation Phases

#### Phase 0 — preconditions (no product edits)

- Re-run every measurement in `## Research Insights` against the branch tip and record any drift.
- Record `--enumerate all` output as the pre-change baseline, and record the current count of
  `_ENUMERATE` conjunct sites, which AC3(a) asserts is unchanged.
- Read `scripts/guard-vacuity-floor.test.sh`'s floor-shape detector and record the exact syntax form
  the new floor must take so the meta-guard can construct a mutant for it.
- Run the `hr-write-boundary-sentinel-sweep-all-write-sites` sweep at the **right scope**: the rule
  says enumerate all *write sites where the property applies*, and for cell 6 those are
  **tag-authoring** sites, not fetch sites. A fetch-scoped sweep here would reproduce, at the sweep,
  the same verb-narrowing the classifier was corrected for. Enumerate `git fetch`, `git pull`,
  `git remote update`, `git tag` creations and `git update-ref refs/tags/…`, repo-wide, in every
  spelling. (`git push … refs/tags/…` is deliberately out — it writes to the remote, not the local
  ref store; the full out-of-class table with reasons is in Stage C.)
- **Demonstrate closure membership for each AC31 witness candidate**, and substitute a demonstrated
  site wherever it cannot be shown. Two of the three candidates are unproven today: the followthrough
  script is referenced from a workflow, two runbooks and a baseline *text* file, and the roster gate
  is a vitest file reached through `bash -c 'cd apps/web-platform && npm run test:ci …'`. Widening
  the closure to make the AC pass is forbidden.
- Check whether `.claude/hooks/pre-merge-rebase.sh` and `.openhands/hooks/pre-merge-rebase.sh` are
  held in parity by an existing assertion, so Phase 3 does not edit one and silently redden the
  other.

#### Phase 1 — RED (constraint 2). **No offender is fixed in this phase.**

- Add `--enumerate-commands` to `scripts/test-all.sh`, setting `_ENUMERATE=1` alongside its own mode
  flag. Assert AC3(a)-(c) before going further — a flag that deadlocks on `tc_acquire` will not
  present as a wrong answer, it will present as a hung gate.
- Write `scripts/battery-tag-authorship.test.sh` through Stage D, with the exemption ledger
  **empty** and `MIN_ROOTS` set provisionally.
- Register it in `scripts/test-all.sh` and **`git add` it** — `guard-vacuity-floor.test.sh` sweeps
  `git ls-files`, so an untracked file never enters its population and AC24 cannot pass.
- Assert AC2: `--enumerate all` differs from the Phase 0 baseline by exactly one added line, this
  registration.
- Run it. Capture the **verbatim** transcript naming every `OFFENDER` and every `UNCLASSIFIED`
  registration. Commit the transcript into the plan as `## Measurement (RED window)` and carry it
  into the PR body.
- Success criterion: the guard exits non-zero **or** exits zero having reported a non-zero
  `roots`/`occurrences` census. A green run reporting `roots=0` or `occurrences=0` is a vacuous green
  and fails this phase.

#### Phase 2 — mutation battery, written from the design

- Implement the mutation matrix in `## Guard Contract` as a runnable battery, following
  `2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md`: control first and
  required GREEN, every mutation asserted to have **landed** against a pristine copy, baseline-identical
  treated as UN-RUN.
- Ratchet `BATTERY_TAG_MIN_ASSERTIONS` and `MIN_ROOTS` to their measured values, and record the
  no-downward-ratchet rule for `MIN_ROOTS` in the guard's header. There is deliberately no floor on
  the occurrence count — see Stage D.

#### Phase 3 — GREEN

- For each `OFFENDER` from Phase 1, apply the cheapest correct closure: `--no-tags` on the command,
  or a declared `repo-boundary-tag-exempt:` marker plus an exemption-array entry citing #7917.
  Prefer `--no-tags`; an exemption requires a stated reason why suppressing tags breaks the site.
- Resolve every `UNCLASSIFIED` registration — either the resolver learns the argv shape, or the
  shape is recorded as out-of-class with a reason.
- Re-run; guard green with a non-zero census.

#### Phase 4 — meta-guard and record

- Re-measure `scripts/guard-vacuity-floor.test.sh`'s firing population and ratchet
  `MIN_FIRING_SUITES` so the new floor is locked in.
- Amend ADR-207: the Consequences bullet gains the measured post-guard population and names
  `scripts/battery-tag-authorship.test.sh` as the mechanism bounding cell 6; the exemption
  ledger's cell-6 row gains the same reference. `status:` stays `accepted`.
- Run the full battery.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Hand-parse `run_suite` lines with a bespoke `sed`, as the issue prescribes | It is a third copy of an extraction that `lint-orphan-test-suites.sh` already carries once and that the runner itself can just publish. `--enumerate` already walks the real registration path including the glob loop and the shard filter; parsing re-derives it and can drift. **Retained as a cross-check arm only** (Guard 2, mutation 3), so the contract and the parse must agree |
| Widen `SUITE_REGISTRATION` to carry argv | Changes a record the shard-totality guard already consumes, inside the hot `run_suite` path, for no gain over an additive flag |
| Decide live-vs-fixture statically and only flag live sites | Not decidable — see `## Problem Statement`. Under-approximation is fail-open and silent |
| Run the battery and diff `git tag` before/after | That is what `scripts/lib/repo-write-boundary.sh` already does, and ADR-207 §2's anti-laundering invariant is precisely why it **cannot** attribute the result under `shared_store`. A guard built on it would reproduce the false negative it exists to remove |
| Derive roots from `--print-suite-globs` alone | The issue's own constraint 1 rejects this, and it is measurably wrong: it loses the 78 hand-registered `scripts/*.test.sh` suites and the whole `tests/scripts/` class |
| Share `repo-write-boundary.test.sh`'s `MIN_ASSERTIONS` | Constraint 3. Classifier arms could be deleted while the floor stayed green on source-grep arms |
| A new ADR | ADR-207 already records this exact risk; a new ADR would leave that bullet standing while the risk moved |

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue | Reality on the branch | Plan response |
|---|---|---|
| `grep -cE 'run_suite .*scripts/[a-z0-9-]+\.test\.sh' …` returns 77 | returns **78** | Cited as evidence of the class, never as an AC value. No AC hard-codes either number |
| `tests/scripts/` appears in neither globs nor registrations | absent from globs; **present** in registrations (`bash tests/scripts/test-*.sh`, `python3 -m unittest tests.scripts.*`) | The guard's root set covers it via `--enumerate-commands`; a `tests/scripts/` member is one of the three source-coverage assertions |
| root set = `SUITE_GLOBS` ∪ explicit `run_suite` registrations, never hand-typed | `--enumerate` already produces exactly that union at runtime | Constraint honoured by a stronger mechanism; the hand-parse is kept as a cross-check, not as the source |
| `.claude/hooks/ship-runbook-ssh-gate.sh` never invoked by its own test | true of its own test; **false** of the battery — `hook-input-contract.test.sh` executes it, inside a non-git temp CWD | Reframes the property (see `## Problem Statement`); the site is still closed in Phase 3 because `--no-tags` costs one token and removes the question |
| every `worktree-manager.sh` fetch reached only inside `cd`-guarded subshells | verified for two of the referencing suites; **unverified** for the other 15 | Not settled here by reasoning. The guard's reframed property does not depend on settling it |
| the population is non-empty / the population is zero | contradictory prior passes, neither reproduced | Neither adopted. Phase 1's RED transcript is the answer, and either answer ships |

## Open Code-Review Overlap

- **#7942** — *Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run in
  no gate.* Touches `scripts/test-all.sh`. **Disposition: acknowledge.** Different concern (whether
  a file is registered at all) from this plan's (what a registered file executes). Folding it in
  would widen scope past the guard. It is, however, direct evidence for this plan's Assembly
  boundary: a file the battery does not register is out of the battery by definition, and this
  guard must say so rather than imply coverage it does not have.

No other open `code-review` issue names a file in `## Files to Create` or `## Files to Edit`.

## Files to Create

- `scripts/battery-tag-authorship.test.sh` — the guard.

## Files to Edit

- `scripts/test-all.sh` — `--enumerate-commands` flag, `_shard_enumerate_command_emit`, the
  `run_suite`/`skip_suite` arms, and the `run_suite` registration for the new suite.
- `scripts/guard-vacuity-floor.test.sh` — `MIN_FIRING_SUITES` ratchet, re-measured. (The suite's
  sweep is `git ls-files`-based and auto-discovers floors written in the shape it recognises, so no
  list edit is needed — but the new file must be tracked, and AC24 asserts it by name rather than by
  the count.)
- `knowledge-base/engineering/architecture/decisions/ADR-207-repo-write-boundary-harm-partition.md`
  — a new numbered section, the cell-6 exemption-ledger row, and the ledger-ceiling governance rule.
  The existing Consequences bullet's closing sentence ("must not be described as closed") stays.
- **Phase 3, derived from the Phase 1 transcript rather than listed here.** Hard-coding the offender
  list now would pre-empt the measurement this plan exists to take. The Phase 1 census is the work
  list, and `hr-write-boundary-sentinel-sweep-all-write-sites` governs it. From the plan-time
  reconnaissance, the file most likely to dominate it is
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (ten undeclared sites, safe only
  by caller discipline, on the exact file ADR-207 cites), followed by
  `.claude/hooks/ship-runbook-ssh-gate.sh`, `.claude/hooks/pre-merge-rebase.sh`,
  `.openhands/hooks/pre-merge-rebase.sh` and `.claude/hooks/ship-unpushed-commits-gate.sh`.
  `plugins/soleur/scripts/sync-pr-behind.sh` and `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`
  are adjudicated unreachable and may not appear at all — which is itself a result worth recording.
- `knowledge-base/project/specs/feat-one-shot-7917-battery-tag-author-guard/tasks.md` — written by
  Save Tasks.

Deliberately **not** edited: `scripts/lint-orphan-test-suites.sh` (it derives its surfaces; a new
explicitly-registered suite needs no change there) and `scripts/lib/repo-write-boundary.sh` (this
plan does not touch the classifier).

**Not edited but AFFECTED, and therefore in scope for verification:**
`plugins/soleur/test/scripts-shard-totality.test.sh`. It is the only live consumer of `--enumerate`
and it derives an independent reference set that the new registration must land inside — see
`## Technical Approach` Part 3 for the three constraints on the registration's shape and placement,
and AC23b. Nothing in it changes; it is the suite that reddens, outside the diff, if the
registration is written in a shape its static extractor cannot see.

## User-Brand Impact

- **If this lands broken, the user experiences:** a guard that reports green over a battery it never
  walked, so `git fetch` sites keep auto-following tags into their working repository and
  `git tag --list` grows by thousands of remote tags they never asked for — while ADR-207 records
  the risk as bounded. The dangerous sub-case (a tag whose name shadows a branch, so `git log`,
  `git diff` and `git push <name>` silently follow the tag) is **not** newly exposed: that cell
  stays `FATAL` in `scripts/lib/repo-write-boundary.sh` regardless of this work.
- **If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector. The
  guard reads tracked source in-repo, opens no network connection, reads no credential, and writes
  nothing outside its own `mktemp` sandbox.
- **Brand-survival threshold:** `aggregate pattern`

Reasoning, stated rather than assumed: a vacuous guard here returns the system to the state ADR-207
already accepted and documented, so no single event is an incident; the harm is accumulation of ref
noise plus a decision record that overstates its own safety. The collision case that *would* be a
single-user incident remains `FATAL` and is untouched. `requires_cpo_signoff: false` follows from
that threshold.

## Observability

```yaml
liveness_signal:
  what:            "scripts/battery-tag-authorship.test.sh runs as a registered run_suite in every test-all.sh run that selects the scripts group (local gate and CI test-scripts job)"
  cadence:         "per-run — every local `bash scripts/test-all.sh` and every CI run of the test-scripts job"
  alert_target:    "CI test-scripts job failure on the PR (required check), and the local gate's [FAIL] line in the runner summary"
  configured_in:   "scripts/test-all.sh — the run_suite registration under want_scripts, beside scripts/suite-exit-class-parity.test.sh"

error_reporting:
  destination:     "layer 6 — the GitHub Actions workflow run log for the test-scripts job in .github/workflows/ci.yml; there is no Sentry surface because this code never executes server-side"
  fail_loud:       "non-zero exit from the suite, surfaced by test-all.sh as a [FAIL] row and a non-zero runner exit; the offender census prints one `path:line<TAB>VERDICT<TAB>command` line per site before the verdict"

failure_modes:
  - mode:          "an offending git fetch is added to a battery-reachable file"
    detection:     "the guard classifies it OFFENDER and exits non-zero; visible in the workflow run log for the test-scripts job (layer 6)"
    alert_route:   "required CI check fails on the PR that introduced it"
  - mode:          "the root-set derivation collapses (the flag errors, or a shard variable leaks in and shrinks the enumeration to one leg)"
    detection:     "the MIN_ROOTS floor and the hard ERROR on a non-zero derivation exit; the guard refuses rather than falling through to an empty root set. Visible in the workflow run log (layer 6)"
    alert_route:   "required CI check fails"
  - mode:          "the guard is neutered — arms deleted, pass/fail stubbed, or the census silenced"
    detection:     "BATTERY_TAG_MIN_ASSERTIONS reported directly rather than through fail(), the passes+fails==asserted conservation check, the pre-case helper self-test, and scripts/guard-vacuity-floor.test.sh's mutation of this suite's floor. Visible in the workflow run log (layer 6)"
    alert_route:   "required CI check fails; guard-vacuity-floor.test.sh also fails if MIN_FIRING_SUITES drops"
  - mode:          "the suite is de-registered from test-all.sh"
    detection:     "scripts/lint-orphan-test-suites.sh surface 1 reports it as an orphan (repo-root scripts/*.test.sh is not glob-covered). Visible in the workflow run log (layer 6)"
    alert_route:   "required CI check fails"
  - mode:          "a registration shape the resolver cannot parse enters test-all.sh"
    detection:     "reported UNCLASSIFIED and counted, never silently skipped; the guard fails on a non-zero unclassified count. Visible in the workflow run log (layer 6)"
    alert_route:   "required CI check fails"

logs:
  where:           "the suite's own stdout, captured by test-all.sh into the runner transcript and by the CI test-scripts job into its workflow run log"
  retention:       "GitHub Actions log retention for the CI copy; the local copy lives for the session"

discoverability_test:
  command:         "bash scripts/battery-tag-authorship.test.sh"
  expected_output: "a per-site census, then a final line of the form `battery-tag-authorship: <N> passed, 0 failed, <N> assertion(s) executed (floor <M>); roots=<R> occurrences=<S> offenders=0 unclassified=0` and exit 0"
```

## Guard Contract

### Guard 1 — battery tag-authorship classifier

**Property.** Every tag-authoring git command in the closure of executables reachable from
`scripts/test-all.sh` either suppresses tag creation on its own command line, or carries a declared
`repo-boundary-tag-exempt:` marker on one of the two lines immediately preceding it.

**Assembly.** The chokepoint is `scripts/test-all.sh`'s registration surface, and there is exactly
one: both `run_suite` and `skip_suite` — the two functions the file's own header calls "the two
chokepoints every group registration passes through, and EXACTLY ONE of them is called per
registration site" — are published by `--enumerate-commands`, which walks the real registration path
including the `SUITE_GLOBS` expansion loop and the shard filter. Two registered roots are themselves
**nested runners** that expand their own sub-population at run time
(`apps/web-platform/infra/run-registered-suites.sh`, `.github/scripts/test/run-all.sh`); they are a
second chokepoint and are named as one, reached by delegating to `run-registered-suites.sh --list`
rather than by re-deriving it. Downstream of the roots, the assembly is the transitive closure of
tracked executables those roots invoke (`bash`, `source`, `.`, `"$REPO_ROOT"/…`,
`${CLAUDE_PLUGIN_ROOT:-…}/…`, and variable-bound literal paths), computed to a fixpoint and
deliberately over-approximated: an unresolvable reference joins the closure rather than leaving it.
Within each closure member the quantified set is every **tag-authoring VERB** — `git fetch`,
`git pull`, `git remote update`, `git tag` in its creating forms, and `git update-ref refs/tags/…`
— in every **SPELLING**: bare, with interleaved
`-c`/`-C`/`--git-dir` options before the verb, and the TS array-argv form. Verb and spelling are two
independent axes and the guard is narrower than its property if either is under-enumerated. Each
occurrence is read with two lines of preceding context. Membership is never a list in the guard: the
only literal arrays are the exemption ledger, `SELF_EXCLUSION` and `FIXTURE_EXCLUSION`, each
separately size-asserted.

**Mutation matrix.** Rows marked *(fixture)* run against a synthetic sandboxed tree copy reached
through the `BATTERY_TAG_REPO_ROOT` / `BATTERY_TAG_RUNNER` injection seam, never by editing tracked
files in the live working tree — which would be racy with the outer gate and, for row 1, would mean
a live tree that momentarily fetches tags. The seam is part of Part 2's design, exercised by the
control run, not an afterthought of the battery.

| # | Mutation | Expected |
|---|---|---|
| 1 | *(fixture)* Remove `--no-tags` from the `git fetch` in a copy of `apps/web-platform/scripts/run-migrations.sh` | RED |
| 2 | Stub the root-set derivation so `--enumerate-commands` yields zero records (own dispatch — a guard reporting "0 checked" and exiting 0 is vacuous) | RED |
| 3 | *(fixture)* Add a **second**, unflagged `git fetch` to a closure member whose existing fetch is already compliant (a check that stops at the first member is the defect itself) | RED |
| 4 | *(fixture)* Move an accepted `repo-boundary-tag-exempt:` marker from 2 lines above its command to 4 lines above (proves `-B2` is the declared window, and that the window is what is asserted) | RED |
| 5 | *(fixture)* Replace the anchored whole-command assertion with a bare file-level `--no-tags` grep, then add `--no-tags` to a **different** command in that same file (constraint 5) | RED |
| 6 | *(fixture)* Delete an entry from the exemption ledger while leaving its in-file marker | RED |
| 6b | *(fixture)* The inverse — remove the in-file marker while leaving the ledger entry, and point a ledger entry at a site that has since been fixed with `--no-tags` (orphan detection; a one-directional check is where offenders go to be forgotten) | RED (each) |
| 7 | *(fixture)* Add a command to a closure member reached only through a variable-bound path (`WM="$REPO_ROOT/…"` … `bash "$WM"`) — the shape 17 battery suites use | RED |
| 8 | **Harness:** stub `fail()` to a no-op | RED via the directly-reported floor and the conservation check, neither of which routes through `fail()` |
| 9 | **Harness:** delete the pre-case helper self-test | RED via the assertion floor |
| 10 | **Must-PASS, non-canonical:** a compliant fetch with a different flag order and extra flags — `git fetch --quiet --no-tags --depth=1 origin main`, indented, with no a literal `if !` prefix. This exact string is also a helper self-test fixture, because the borrowed `_nt_ok` regex would reject it | PASS |
| 11 | **Must-PASS, non-canonical:** a `git tag -d` deletion and a `git ls-remote` — both out of class, neither may be graded OFFENDER | PASS (each) |
| 12 | *(fixture)* Add an unflagged command in a **non-literal spelling**: one as `git -c gc.auto=0 fetch origin main`, one as the TS array form `["fetch", "origin", "main"]` | RED (each) |
| 13 | *(fixture)* Replace the delegation to `run-registered-suites.sh --list` with a static path walk, so the nested runner's sub-population silently leaves the closure, then add an unflagged command inside that sub-population | RED |
| 14 | *(fixture)* Add an unflagged **`git pull`** (`git pull origin main`, and `git -C "$GIT_ROOT" pull --ff-only origin main`) — the verb axis, and the two spellings measured live in `worktree-manager.sh` | RED (each) |
| 15 | *(fixture)* Add a direct **`git tag -a -m … v1.2.3`** creation to a closure member — the verb ADR-207 cell 6 actually quantifies over | RED |
| 16 | *(fixture)* Write `git fetch --no-tags --tags origin`, then `git fetch --no-tags origin '+refs/tags/*:refs/tags/*'` — `--no-tags` present, tags fetched anyway; the `SUPPRESSED` negative conjunct | RED (each) |
| 17 | *(fixture)* Write `git -C "$GIT_ROOT" fetch origin main` with no `--no-tags` — a `-C`-scoped command against the live repo, which an earlier draft graded compliant | RED |

### Guard 2 — root-set derivation contract

**Property.** The guard's root set equals what `scripts/test-all.sh` actually registers — the
`SUITE_GLOBS` expansion and every explicit `run_suite`/`skip_suite` registration — with no
registration silently dropped and no shape silently unparsed.

**Assembly.** `scripts/test-all.sh`'s `SUITE_GLOBS` array plus its **208** registration call sites
(measured: 201 `run_suite` + 7 `skip_suite`; the interpreter census of 177+16+5+2+1 sums to the 201),
published through the `--enumerate-commands` accessor and read by the guard through the
`env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1` idiom over all five groups via
`all`. Exactly **3** of the 208 carry a variable in argv (the two `env VITEST_SHARD=…` vitest shards
and the glob loop's `bash "$f"`), which is why the independent `sed` cross-check is viable at all —
and why that cross-check must **join line continuations** before parsing, since four registrations
span one, and a line-oriented parse would report a permanent false disagreement. The contract is
asserted three ways that fail independently: source-coverage (one known member per source), the
`MIN_ROOTS` floor, and the continuation-joining `sed` cross-check.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `--enumerate`'s existing `SUITE_REGISTRATION` output in any byte beyond the single line this PR's own registration adds | RED |
| 2 | Delete one `SUITE_GLOBS` entry | RED — the glob-source member (`scripts/lib/repo-write-boundary.test.sh`) leaves the union, and `MIN_ROOTS` drops |
| 3 | Drop the `skip_suite` emit arm, so relevance-declined suites vanish from the root set | RED — the cross-check against the independent registration parse disagrees |
| 4 | Add a `run_suite` registration in an argv shape the resolver does not know | RED as UNCLASSIFIED, counted and reported — never silently skipped |
| 5 | Leak `SCRIPTS_SHARD=1/3` into the derivation environment so the enumeration returns one leg | RED via `MIN_ROOTS` |
| 6 | Give `--enumerate-commands` its own mode variable **without** also setting `_ENUMERATE=1`, so the nine `_ENUMERATE` conjuncts stop applying | RED — assert the invocation neither blocks on `tc_acquire` nor emits a nested `repo_boundary_classify` verdict, within a bounded timeout |
| 7 | Emit the record with `"$*"` instead of tab-delimited argv, then register a suite whose argv contains a space-bearing operand | RED — argv boundaries are part of the record contract |
| 8 | **Must-PASS:** add a new suite through the `SUITE_GLOBS` auto-discovery path | PASS, and the new file appears in the closure |

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-207-repo-write-boundary-harm-partition.md` by adding a numbered section; do not create
a new ADR.** No new *cell* is granted and no decision event on the classifier occurs, so ADR-207's
*"The next request is the seventh cell, and it should be refused"* is not engaged. But a Consequences
bullet edit alone is **not sufficient**, and an earlier draft of this plan was internally
contradictory on the point — calling the reframing *"the single most important design decision in
this plan"* while justifying amend-not-create with *"no new architectural choice is made here."* Both
cannot hold. Three things must reach the record and none of them fits in a bullet:

- **The reframed property, verbatim**, plus the reason it is reframed: live-vs-fixture is not
  statically decidable, with the `ship-runbook-ssh-gate.sh` worked example as the evidence. A reader
  of "bounded by a guard" would otherwise not know what was bounded.
- **`EXEMPT` is an accepted-risk verdict, not a proof.** An exempted site that writes a tag into the
  live repo produces no guard failure, and cell 6 renders it `REPORT`. The guard enumerates the
  battery's tag authors; it does not eliminate them.
- **The exemption ledger's governance.** Without this, the effective softened surface after this
  lands is `cell 6 ∪ every repo-boundary-tag-exempt entry`, and only the first half is in the record
  ADR-207 §3 exists to hold — re-creating, one file over, exactly the invisibility that section was
  written to prevent. So: the ceiling value lives in ADR-207 §3 under cell 6, and **raising it is an
  ADR edit, not a test-file edit.**

So the deliverable is a new numbered section — §5, *"what the tag-authorship guard does and does not
prove"* — carrying those three, plus a cell-6 exemption-ledger row citing
`scripts/battery-tag-authorship.test.sh`. `status:` stays `accepted`. There is no new ordinal, so
there is no ordinal-collision exposure. (Writing ADR-208 instead would also be acceptable — it
softens nothing — but the section keeps the cell and its bound in one document, which is where
ADR-207 §3 argues the cumulative position belongs.)

**The ADR must NOT transcribe a measured population figure.** An earlier draft required the bullet to
carry "the measured post-guard population". That number is stale the first time anyone adds a fetch,
and nothing ratchets it. Name the mechanism; the guard is the live count, and the record should point
at it rather than copy it.

**And the existing Consequences bullet must not be softened into a false claim.** It currently ends
*"This is the single largest accepted risk and must not be described as closed."* It stays. The
amendment adds that the class is now enumerated and bounded by a named guard — not that it is closed,
and not that the population is zero.

### C4 views

**No C4 impact**, and here is the enumeration that backs it, checked against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:

- **External human actors:** none. The change adds no correspondent, reviewer or recipient; the only
  human in the loop is the repository's own developer, already modelled.
- **External systems / vendors:** none. The guard opens no network connection, calls no vendor API,
  and adds no inbound webhook or outbound integration.
- **Containers / data stores:** none. It reads tracked files and writes only inside its own
  `mktemp` sandbox. No queue, table, bucket or cache is added or touched.
- **Actor↔surface access relationships:** none. No ownership, sharing or permission relationship
  changes; this is a repo-internal test gate with no runtime surface.
- **Derived cardinalities embedded in `model.c4` edge prose** (workflow counts, monitor counts,
  heartbeat slugs): none moved — no workflow, Sentry monitor or heartbeat slug is added or removed.
  Backed by a green `bash plugins/soleur/test/c4-count-parity.test.sh` run, which is an
  acceptance criterion below rather than an argument.

### Sequencing

None. The decision is true the moment the guard is green; nothing is soak-gated.

## Acceptance Criteria

### Pre-merge (PR)

#### Functional requirements

1. `scripts/test-all.sh --enumerate-commands all` emits one `SUITE_COMMAND` record per `run_suite`
   registration and one `SUITE_COMMAND_DECLINED` record per `skip_suite` registration. Verify by
   **set-compare, not by count** — a count comparison cannot detect an orphan, and one registration
   dropped plus one added nets to zero: the ordered sequence of labels in the `SUITE_COMMAND` +
   `SUITE_COMMAND_DECLINED` stream must equal the ordered sequence of labels from
   `env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash scripts/test-all.sh --enumerate all | grep '^SUITE_REGISTRATION'`.
   (Plan-time reading, for orientation only: 396 records. Do not hard-code it.)
2. `--enumerate all` output is identical to the Phase 0 baseline **except for exactly one added
   line**, this PR's own `run_suite` registration — the earlier "byte-identical" wording was
   unsatisfiable, since Phase 1 registers a new suite and the baseline necessarily grows by one.
   Verify: `diff <(<baseline>) <(env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash scripts/test-all.sh --enumerate all)`
   shows exactly one `>` line, and that line names `battery-tag-authorship`. Asserting *one added
   line and nothing else* is a stronger statement than byte-identity, not a weaker one.
3. `--enumerate-commands` is **parsed** in the same pre-side-effect block as `--print-suite-globs`
   and sets `_ENUMERATE=1` in addition to its own mode flag, so that all nine existing `_ENUMERATE`
   conjuncts apply unchanged. It does **not** exit early: registrations live in the `want_*` blocks
   far below, so a handler that exited there would emit nothing. Verify three ways:
   (a) `grep -c '_ENUMERATE == 0\|"$_ENUMERATE" == "0"\|(( _ENUMERATE == 1 ))' scripts/test-all.sh`
   is unchanged from the Phase 0 baseline — no conjunct was added, moved or lost;
   (b) `grep -c '_ENUMERATE=1' scripts/test-all.sh` → `2` (the `--enumerate` arm and the
   `--enumerate-commands` arm);
   (c) the invocation completes within a bounded timeout and emits no `repo_boundary_classify`
   verdict — i.e. it neither blocks on `tc_acquire` nor runs a second boundary classification nested
   inside the outer run's window. Guard-2 mutation row 6 is the RED counterpart.
4. `scripts/battery-tag-authorship.test.sh` exists, is **tracked** (`git ls-files --error-unmatch`
   succeeds — `guard-vacuity-floor.test.sh` sweeps `git ls-files`, so an untracked file is invisible
   to it), is registered by an explicit `run_suite` line under `want_scripts`, and the registration
   is anchored on the invoked **path**, not the label. Verify:
   `grep -cE '^[[:space:]]*run_suite .*[[:space:]]bash[[:space:]]+"?scripts/battery-tag-authorship\.test\.sh"?([[:space:]]|$)' scripts/test-all.sh` → `1`.
5. The guard asserts source coverage with all three named members — `scripts/lib/repo-write-boundary.test.sh`
   (glob-sourced), `scripts/suite-exit-class-parity.test.sh` (hand-registered repo-root
   `scripts/*.test.sh`), `tests/scripts/test-plan-gate-preamble.sh` (`tests/scripts/`, invisible to
   both the globs and a `.test.sh`-anchored parse) — and fails if any is absent from the derived
   root set.
6. Every registration is **accounted for**, in one of exactly two places, with no third: resolved
   into the root set, or recorded in a declared **out-of-class ledger** carrying a reason and a size
   ceiling. A shape that is neither is `UNCLASSIFIED` and fails the run. This replaces the earlier
   wording, under which AC6 ("fails on a non-zero unclassified count") and Phase 3 ("may be recorded
   as out-of-class with a reason") contradicted each other. The known members needing an explicit
   resolver row or a ledger entry: `bash -c '<inline script>'`, `env … bash -c '…'`,
   `bun test <dir>/`, and the two nested runners.
7. The guard's census prints one `path:line<TAB>VERDICT<TAB>battery-reachable?<TAB>command` line per
   occurrence, with verdicts drawn from exactly `SUPPRESSED | EXEMPT | OFFENDER`. Verify:
   `{ grep -c 'SCOPED' scripts/battery-tag-authorship.test.sh || true; }` → `0`. The `SCOPED`
   verdict is deliberately absent — see `## Technical Approach` Stage C.
8. Every classification reads its site with two lines of preceding context, and the
   `EXEMPT` verdict requires the marker within that window (constraint 4).
9. Every `SUPPRESSED` verdict is decided by an anchored **whole-command** match — not a bare
   `--no-tags` grep anywhere in the file (constraint 5) — **and** requires the absence of a positive
   tag request on that same command (`--tags`, `-t`, a `refs/tags/` operand, a `tagOpt` `-c`).
   Verify: mutation-matrix rows 5 and 16 are RED.
10. The guard's assertion floor is named `BATTERY_TAG_MIN_ASSERTIONS`, is distinct from
    `repo-write-boundary.test.sh`'s `MIN_ASSERTIONS`, and is reported directly rather than through
    `fail()` (constraint 3). Verify with two commands, because a bare
    `grep -c 'MIN_ASSERTIONS'` cannot decide this — `MIN_ASSERTIONS` is a **substring** of
    `BATTERY_TAG_MIN_ASSERTIONS`, so the count is identical whether or not the bare form is present:
    `{ grep -n 'MIN_ASSERTIONS' scripts/battery-tag-authorship.test.sh | grep -v 'BATTERY_TAG_MIN_ASSERTIONS' || true; }` → empty,
    and `grep -c '^BATTERY_TAG_MIN_ASSERTIONS=' scripts/battery-tag-authorship.test.sh` → `1`.
    Also: `git diff origin/main...HEAD --stat -- scripts/lib/repo-write-boundary.test.sh` → empty.
11. The guard carries a `MIN_ROOTS` floor, checked **before any verdict is graded**, and refuses a
    committed value **below** the previous committed value — the only legitimate ratchet direction is
    up. There is deliberately no floor on the occurrence count; see `## Technical Approach` Stage D
    for why a population floor punishes the desired direction.
12. A helper self-test runs before any case, drives the assertion helpers with one matching and one
    non-matching input, asserts both moved the counters, and reports through neither helper. Its
    fixture set includes the exact string `git fetch --quiet --no-tags --depth=1 origin main`
    (indented, no a literal `if !` prefix), which the borrowed `_nt_ok` regex would reject.
13. A non-zero exit or zero records from the derivation flag is a hard ERROR in the guard, never a
    fall-through to an empty root set. Verify: mutation-matrix Guard-2 row 5 is RED.
14. `SELF_EXCLUSION` and `FIXTURE_EXCLUSION` are two **separate** arrays, each size-asserted, and
    neither is part of the exemption ledger — which is what lets AC18's ledger↔`EXEMPT` comparison be
    an equality rather than an off-by-two.
15. Every search site in the guard is failure-tolerant under `set -e` (`{ grep … || true; }` form),
    so a zero-match grep cannot kill the run before the floors are reached.

#### The measurement (constraint 2)

16. `## Measurement (RED window)` exists in this plan file and contains the **verbatim** Phase 1
    transcript, captured with the exemption ledger empty and **before** any offender was edited. It
    names every `OFFENDER` by `path:line` and every `UNCLASSIFIED` registration, and records the
    `roots` and `occurrences` census.
17. The RED run is a genuine RED window: it either exits non-zero, or exits zero having reported a
    non-zero census. A run reporting `roots=0` or `occurrences=0` does not satisfy this criterion.
18. Every `OFFENDER` in that transcript is, at merge, either `SUPPRESSED` (a suppression on its own
    command) or `EXEMPT` (a `repo-boundary-tag-exempt:` marker within the `-B2` window **and** a
    ledger entry). Verify against the **final** run, not the RED one — the RED transcript is defined
    as having an empty ledger, so comparing the ledger to it would assert `ledger == 0`: the final
    guard run reports `offenders=0`, and its `EXEMPT` census is in **bijection** with the ledger
    (every entry resolves to an `EXEMPT` site, every `EXEMPT` site has exactly one entry, no
    orphans). `SELF_EXCLUSION` and `FIXTURE_EXCLUSION` are outside the ledger, so this is an
    equality.
18b. Every ledger entry states why suppression **specifically breaks that site**, and cites an
    **open** tracking issue or a stated re-review trigger — not `#7917`, which closes when this
    merges and would leave every entry citing a dead reference. "It is fixture-scoped" is not an
    accepted reason: that is the undecidable claim the reframing exists to stop relying on.

#### Mutation battery

19. Every row of both mutation matrices in `## Guard Contract` is executed, and each RED row is
    asserted to have **landed** against a pristine copy — a mutant whose file is byte-identical to
    the original is treated as UN-RUN, not as a pass. The harness prints one line per row naming the
    row, whether the mutation landed, and the resulting verdict; that output is the artifact.
20. The control run is executed first, in the same harness as the rows, and is required GREEN before
    any row's verdict is read.
21. Every mutation runs against a synthetic sandboxed tree copy through the
    `BATTERY_TAG_REPO_ROOT` / `BATTERY_TAG_RUNNER` seam. No row edits a tracked file in the live
    working tree — which would be racy with the outer gate and, for row 1, would mean a live tree
    that momentarily fetches tags. This is also what makes rows 4, 6 and 6b runnable: they need an
    accepted exemption to exist, Phase 1 runs with the ledger empty, and Phase 3 prefers `--no-tags`
    over exemptions — so against real sites those rows might never have a subject.
21b. Every must-PASS row (Guard 1 rows 10 and 11, Guard 2 row 8) passes, and none of them is the
    canonical fixture.

#### Quality gates

22. `bash scripts/battery-tag-authorship.test.sh` → exit 0, `offenders=0`, `unclassified=0`,
    assertions executed ≥ `BATTERY_TAG_MIN_ASSERTIONS`.
23. `bash scripts/lint-orphan-test-suites.sh` → exit 0 (the new suite is registered, not an orphan).
23b. `bash plugins/soleur/test/scripts-shard-totality.test.sh` → exit 0. This is the suite the new
    registration can break from outside the diff: it compares `--enumerate scripts` against an
    independently derived reference whose static half only sees `run_suite "<literal>"` lines inside
    a column-0 `if want_scripts; then` … `fi` block, with no `$` in the label. Verify the
    registration satisfies all three constraints, and that this suite's row count is unchanged.
24. `bash scripts/guard-vacuity-floor.test.sh` → exit 0, **and the new suite appears by name in its
    FIRES list**. A `MIN_FIRING_SUITES` bump alone does not discharge this: that ratchet already
    carries slack (its own comment records "45 firing against `MIN_FIRING_SUITES=36`"), so a count
    rising is satisfiable by any other suite's floor — the count-vs-set-compare defect this plan
    cites elsewhere. Assert the name; bump the ratchet as well so the population cannot silently
    shrink back.
25. `python3 scripts/lint-guard-contract.py` → exit 0 over this plan file.
26. `bash plugins/soleur/test/c4-count-parity.test.sh` → exit 0 (backs the "no C4 impact"
    conclusion mechanically rather than by argument).
27. `bash scripts/test-all.sh scripts` → exit 0.
28. `bash scripts/test-all.sh` (full battery) → exit 0.
29. ADR-207 carries the reframed property and the ledger's governance in a **new numbered section**,
    and its cell-6 exemption-ledger row cites the guard. A whole-file
    `grep -c 'battery-tag-authorship' → ≥ 2` does **not** discharge this — two mentions inside one
    paragraph satisfy it while the ledger row stays untouched, and it is a bare-token assert against
    `cq-assert-anchor-not-bare-token`. Verify with two independently range-scoped assertions: one
    over the new section's own slice, one over the cell-6 table row, each ≥ 1. The ADR must **not**
    transcribe a measured population figure — see `## Architecture Decision (ADR/C4)`.
30. No test or comment introduced by this PR hard-codes the count `77` or `78` for the
    hand-registered `scripts/*.test.sh` class. The plan file itself is **excluded**: it cites `78`
    deliberately, in `## Research Reconciliation`, as the correction of the issue's stale figure —
    without the exclusion this AC fails on its own plan. Verify — the `|| true` is load-bearing,
    since `grep -c` exits 1 on a zero count and this repo's shells run under `set -e`:
    `{ git diff origin/main...HEAD -- ':!knowledge-base/' | grep -cE '^\+.*\b7[78]\b' || true; }` → `0`.
31. The occurrence pattern covers both axes — **verb** and **spelling** — and is verified by fixture,
    never by reading the regex.
    *Spelling:* Guard-1 row 12 is RED for both the `git -c gc.auto=0 fetch` form and the TS array
    form. *Verb:* rows 14 (`git pull`, both spellings) and 15 (`git tag -a`) are RED.
    *Live witnesses:* the census over the unmodified tree names at least one site in each non-literal
    spelling and at least one `git pull` site. Candidate witnesses are
    `scripts/followthroughs/ccla-representative-icla-7922.sh` (a `git -c gc.auto=0 fetch`),
    `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` (an array form) and
    `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (`git pull`) — but **Phase 0
    must first demonstrate each candidate's closure membership** and substitute a demonstrated one
    where it cannot. Neither of the first two has demonstrated membership yet: the followthrough
    script is referenced from a workflow, two runbooks and a baseline **text** file (not an
    executable closure member), and the roster gate is a vitest file reached only through
    `bash -c 'cd apps/web-platform && npm run test:ci …'`, which the closure walker does not follow
    into vitest project globs. Widening the closure to make this AC pass would change the guard's
    scope without changing its name, and is forbidden.
32. The closure expands both nested runners. Verify: the guard's closure contains at least one file
    reachable only through `apps/web-platform/infra/run-registered-suites.sh --list`, the delegation
    carries a floor on its parse plus the declared-vs-parsed cross-check, and Guard-1 row 13 is RED.
33. The guard's header states, in its own words, every place its enumeration is an **approximation**
    rather than an enumeration, and every command it deliberately holds out of class. At minimum:
    the `bun test <dir>/` expansion method; that the closure covers **tracked** executables only, so
    an untracked-but-present sourced file leaves it silently; that comment and heredoc exclusion is
    best-effort with a false-OFFENDER (not false-green) failure direction; and the out-of-class
    table from `## Technical Approach` Stage C with its reasons. Verify by asserting the literal
    phrases are present, not by reading the prose — an honesty clause nothing checks is prose.

### Post-merge

None. There is no deploy surface, no infrastructure change, no external state to reconcile, and
nothing time-gated — so no follow-through enrolment is required.

## Test Scenarios

### Acceptance tests (RED-phase targets)

- The guard, run against the tree with an empty exemption ledger, names a non-zero census and every
  offender in it. (Phase 1; the artifact is AC16.)
- The guard, run against a tree where one known-compliant fetch has had `--no-tags` removed, is RED
  and names exactly that site.
- The guard, run with the derivation flag stubbed to emit nothing, is RED with a message naming the
  derivation rather than a fetch site.

### Regression tests

- **`plugins/soleur/test/scripts-shard-totality.test.sh` — the one live consumer of `--enumerate`,
  and therefore the concrete thing AC2's parity assertion protects.** Measured, it is the only
  file outside `scripts/test-all.sh` that reads the record stream, and it does so as
  `… | grep '^SUITE_REGISTRATION' | cut -f2` — anchored on the record type at line start and on
  field 2. That anchoring is exactly why the new mode must emit a **different record type** rather
  than widen this one, and why AC2 asserts "one added line and nothing else". The suite is
  glob-registered via `plugins/soleur/test/*.test.sh`, so it runs in the same battery; assert it
  green before and after. (`.github/workflows/ci.yml` mentions `--enumerate` only in a comment
  describing how a timing table was re-derived — it is not a consumer.)
- `scripts/lint-orphan-test-suites.sh` stays green with the new explicitly-registered suite.
- `scripts/lib/repo-write-boundary.test.sh` is unmodified and stays green at `MIN_ASSERTIONS=57`.

### Edge cases

- A registration whose label contains a path-shaped string but whose argv does not (the exact defect
  `lint-orphan-test-suites.sh` records: `run_suite "…/run-registered-suites.sh" bash -c true`) —
  must resolve from argv, and report UNCLASSIFIED rather than trusting the label.
- `bun test plugins/soleur/` — a directory operand, not a file.
- A relevance-declined suite (`skip_suite`) — still battery-reachable, must stay in the root set.
- A fetch inside a heredoc or a comment — must not be graded as a live call site.
- The guard's own source, which contains both `git fetch` and `--no-tags` literals — must be
  excluded exactly once, by a size-asserted ledger.

### Integration verification

- `bash scripts/test-all.sh scripts` and then the full battery, both green, with the new suite
  appearing in the runner's suite list and its census line in the transcript.

## Risk Analysis & Mitigation

| Risk | Why it bites | Mitigation |
|---|---|---|
| **Vacuous green** — the guard derives ~0 roots or ~0 occurrences and passes | Highest-probability failure and entirely invisible; it is the exact defect the cut #7795 guard had | `MIN_ROOTS` (no downward ratchet) checked before any verdict is graded; named-witness coverage on the occurrence census in each verb and spelling (AC31); hard ERROR on a failed derivation; the new suite asserted **by name** in `guard-vacuity-floor.test.sh`'s FIRES list; the pre-case helper self-test |
| **Shard leakage shrinks the root set** | `SCRIPTS_SHARD` in the environment makes `_shard_selects` return 1 for most registrations, so the enumeration silently returns one leg — fail-open | Reuse `lint-orphan-test-suites.sh`'s exact `env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1` idiom; `MIN_ROOTS` catches the residue |
| **Touching the `run_suite` hot path** | `_shard_enumerate_emit` shares that path with the runtime ceiling and the shard-totality guard | Additive flag and a distinct record type; AC2's byte-identical parity assertion on the existing output |
| **Exemption-ledger inflation** | Over-approximating the closure produces exemptions, and a growing array of individually-reasoned entries stops being read | Each entry must cite an issue number; the ledger size is asserted against a **ceiling**, not a floor, so growth is a decision rather than a drift |
| **Static closure under-approximates** | An offender reached through a shape the walker does not know is a silent fail-open | Deliberate over-approximation, plus the UNCLASSIFIED census which fails rather than skips |
| **The occurrence pattern is literal-token-anchored** | Measured: `git -c gc.auto=0 fetch` and the TS array form `["fetch", …]` account for at least five sites a the literal token `git fetch` grep never sees. The guard would then be narrower than the property it names, and green | Three-spelling pattern (AC31), mutation row 12 driving RED on both non-literal forms, and a census assertion naming two known non-literal sites so the coverage is proved by fixture rather than by reading the regex |
| **A nested runner's sub-population silently leaves the closure** | `run-registered-suites.sh` and `.github/scripts/test/run-all.sh` expand at run time; a static walker stops at them and loses everything behind them without saying so | Delegate to `run-registered-suites.sh --list` with a floor on the parse, exactly as `lint-orphan-test-suites.sh` surface 3 does; an unexpanded nested runner is UNCLASSIFIED (AC32, mutation row 13) |
| **The RED window is skipped under pipeline pressure** | It is the one phase with no green to show for it | AC16-17 make the verbatim transcript a merge-blocking artifact, and AC17 rejects a vacuous one |

## References & Research

### Internal

- `knowledge-base/engineering/architecture/decisions/ADR-207-repo-write-boundary-harm-partition.md`
- `knowledge-base/project/plans/2026-09-07-fix-repo-write-boundary-tag-shared-store-softening-plan.md`
- `scripts/lib/repo-write-boundary.sh`, `scripts/lib/repo-write-boundary.test.sh`
- `scripts/test-all.sh`, `scripts/lint-orphan-test-suites.sh`, `scripts/guard-vacuity-floor.test.sh`
- `apps/web-platform/scripts/run-migrations-schema-probe.test.sh`
- `apps/cla-evidence/scripts/ccla-add.sh`, `scripts/lib/legal-base-ref.sh`
- `.claude/hooks/hook-input-contract.test.sh`, `.claude/hooks/ship-runbook-ssh-gate.sh`
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Learnings, all verified present:
  `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`,
  `knowledge-base/project/learnings/2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md`,
  `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md`,
  `knowledge-base/project/learnings/2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md`,
  `knowledge-base/project/learnings/2026-09-08-every-guard-i-added-to-the-gate-could-not-fail.md`,
  `knowledge-base/project/learnings/2026-09-08-my-guard-could-not-fire-and-the-sweep-stopped-at-the-gate.md`,
  `knowledge-base/project/learnings/2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md`,
  `knowledge-base/project/learnings/2026-07-29-a-per-producer-fix-left-seven-siblings-live-and-four-misread-signals.md`
- Issues: #7917 (this), #7795 (the softening), #7942 (acknowledged overlap)

### External

None. Every claim in this plan is resolved against repository source.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Three findings were adopted and one was rejected after verification.

*Adopted.* (a) The root set does not need static parsing — `scripts/test-all.sh --enumerate` already
runs the real registration path and publishes it; the leverage is a small additive extension that
emits argv alongside the label. Verified: the flag exists, works, and emits label-only
(`_shard_enumerate_emit` prints `'SUITE_REGISTRATION\t%s\n' "$1"`); `--enumerate all` returns 396
records. (b) The extension must be a **separate** flag and record type rather than a widening of
`SUITE_REGISTRATION`, which the shard-totality guard already consumes inside the hot `run_suite`
path. (c) The interpreter boundary must not be declared away: a guard that closes bash while
excusing other interpreters leaves the class open while reading as closed — so unresolvable argv
shapes are reported as UNCLASSIFIED and fail, rather than being filtered out.

*Adopted with a correction.* The assessment named
`apps/web-platform/test/kb-*.test.ts` as carrying `git fetch`. Verified: it does not — the hits are
`fetchUserWorkspacePathSpy` and a mocked git-op object in `kb-route-helpers.test.ts`, and the one
real TS site (`apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts`) is already compliant
and already carries the exemption rationale. The earlier sizing that rested on those files is
withdrawn; nothing in this plan is built on them.

*Rejected after verification.* The assessment offered `.claude/hooks/ship-runbook-ssh-gate.sh` as a
confirmed live RED candidate reached from `hook-input-contract.test.sh`. The reach is real, but
every execution is `(cd "$sandbox" && … )` into a `mktemp -d -t hicroot.XXXXXXXX` root, and the
helper's own header states that intent. It is therefore **not** a confirmed live-repo author. That
correction is what produced this plan's central design decision: live-vs-fixture is not statically
decidable, so the guard's property is reframed to a declaration-based one (see
`## Problem Statement`). The site is still closed in Phase 3, because `--no-tags` costs one token
and removes the question entirely.

*Also adopted:* the ADR posture (amend ADR-207, no new ADR) and both named risks, which appear in
`## Risk Analysis & Mitigation`.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit`
matches nothing — no path under `components/**`, `app/**/page.tsx` or `app/**/layout.tsx`, and no
user-facing surface of any kind. Product assessed **NONE**.

**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan.

**Skipped specialists:** none.

## Compliance Gates

- **GDPR / compliance (Phase 2.7):** skipped. No schema, migration, auth flow, API route or `.sql`
  file is touched; no LLM or external API processes any data; no cron reads `learnings/` or
  `specs/`; no new artifact distribution surface. None of the four expansion triggers fire.
- **Infrastructure-as-Code (Phase 2.8):** skipped. No server, service, cron, vendor account, DNS
  record, certificate, secret or firewall rule is introduced. The change is confined to repository
  test tooling.
- **Encryption posture (Phase 2.11):** skipped. No persistent store and no new cross-component
  connection. The guard reads tracked files and writes only inside its own `mktemp` sandbox.

## Plan Review

Three reviewers ran against the first draft: `kieran-rails-reviewer` (correctness and convention),
`code-simplicity-reviewer` (YAGNI and scope), `architecture-strategist` (structure and ADR posture).
Every finding below was **verified against repository source before being adopted or rejected** —
two of the reviewers' own supporting claims did not survive that check, and are recorded as rejected.

### Adopted — P0

| Finding | Verified how | What changed |
|---|---|---|
| **The `SCOPED` verdict was fail-open.** `git -C <path>` names *which* repo, not that it is disposable. Raised independently by both `code-simplicity-reviewer` and `architecture-strategist` | `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`'s own comment reads *"`git -C "$REPO_ROOT" fetch` below is a WRITE: it updates refs/remotes/origin/main, appends to its reflog, and writes FETCH_HEAD into that repository."* `apps/web-platform/infra/generate-apex-rollback-pr.sh` carries an unsuppressed `git -C "$REPO_ROOT" fetch`, and `worktree-manager.sh` a `git -C "$GIT_ROOT" pull --ff-only` | `SCOPED` deleted; three verdicts; its must-PASS row replaced by mutation row 17, which requires that shape to be **RED**. AC7 asserts the token is absent from the guard's source |
| **The quantified VERB set was narrower than cell 6.** ADR-207 cell 6 softens a tag *creation* by anything; the classifier saw only `git fetch` | `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` carries `git pull origin "$branch" \|\| true` — already counted in this plan's own reconnaissance and absent from its own pattern. `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh` carries `git tag -a -m "sandbox pin fixture"` | Guard renamed `battery-tag-authorship`; verb set widened to `fetch`/`pull`/`remote update`/`tag`/`update-ref refs/tags`/`push refs/tags`; mutation rows 14-15; AC31 now covers verb **and** spelling as two axes |
| **`--enumerate-commands` on its own variable would deadlock the gate.** `--enumerate` is not an early-exit flag; its side-effect suppression is scattered `_ENUMERATE` conjuncts | `grep -n '_ENUMERATE' scripts/test-all.sh` → **9 sites**, including `if (( _ENUMERATE == 1 )); then SOLEUR_DISABLE_SESSION_STATE=1; fi` immediately above `tc_acquire`, the `TC_SIBLING_RUN_COUNT` refusal conjunct, and the epilogue arm that exits before `repo_boundary_classify` | The flag now sets `_ENUMERATE=1` **as well as** its own mode flag. AC3 rewritten from "exits early" (unsatisfiable — registrations live far below) to "parsed early, sets both flags, conjunct count unchanged, bounded runtime, no nested boundary verdict". Guard-2 row 6 is the RED counterpart |

### Adopted — P1

- **AC2 was unsatisfiable.** Phase 1 registers a new suite, so `--enumerate all` necessarily gains a
  line; byte-identity contradicted the plan's own phase list. Now: identical **except exactly one
  added line**, which must name the new suite — a stronger assertion than byte-identity.
- **The `_nt_ok` regex is not reusable.** Measured, it anchors at column 0, requires a literal
  a literal `if !` prefix and exactly `origin main`, and its flag class `--[a-z-]+` rejects any flag with `=`
  or a digit — so it would reject this guard's own must-PASS fixture `--depth=1`. The plan now
  borrows the *design constraint* and says a new matcher is written; the fixture is a named
  self-test input.
- **`SUPPRESSED` needed a negative conjunct.** `git fetch --no-tags --tags origin` carries the flag
  and fetches tags. Added, with mutation row 16.
- **The exemption ledger was one-directional.** Nothing detected an orphan entry — the plan quoted
  *"a count comparison cannot detect an orphan — set-compare the SOURCES"* and did not apply it to
  itself. Now a bijection (row 6b), site-granular keys, and an **open** tracking citation, since
  `#7917` closes at merge.
- **`skip_suite`'s `$3` is a display string and has already drifted** from the real argv for
  `apps/web-platform [unit]`. Now a distinct `SUITE_COMMAND_DECLINED` record type.
- **`"$*"` destroys argv boundaries.** Tab-delimited argv, contract stated in the record's header;
  Guard-2 row 7 pins it.
- **AC6 and Phase 3 contradicted each other** on unresolvable shapes. Now a declared out-of-class
  ledger with a ceiling, so "resolved" and "excused" are distinguishable and neither is silent.
- **AC24 was a count where a set-compare was needed.** `guard-vacuity-floor.test.sh` already carries
  ~7 of slack, so a 38→39 bump is satisfiable by any other suite's floor. Now: assert the new suite
  **by name** in its FIRES list, and `git add` the file in Phase 1 so the `git ls-files` sweep sees
  it.
- **AC29 was a bare-token whole-file grep** against `cq-assert-anchor-not-bare-token`. Now two
  independently range-scoped assertions.
- **AC30 self-violated** — this plan legitimately cites `78` — and exited 1 on success. Now scoped
  `-- ':!knowledge-base/'` and wrapped `|| true`.
- **AC10's `grep -c` could not decide its property**: `MIN_ASSERTIONS` is a substring of
  `BATTERY_TAG_MIN_ASSERTIONS`. Now a `grep -v` form plus an anchored count.
- **Mutation rows 4 and 6 consumed a contract only Phase 3 creates.** Rows now run against synthetic
  fixtures through a declared `BATTERY_TAG_REPO_ROOT` / `BATTERY_TAG_RUNNER` seam, which also stops
  the battery editing tracked files in a live tree.
- **The ADR amendment was insufficient**, and the plan was self-contradictory about it. Promoted from
  a Consequences bullet to a new numbered ADR-207 section carrying the reframed property, the
  accepted-risk nature of `EXEMPT`, and the ledger's governance — the last because otherwise the
  effective softened surface is `cell 6 ∪ the ledger` with only half of it in the record. The
  transcribed population figure is dropped.
- **A population floor punishes the desired direction.** `MIN_FETCH_SITES` would redden on any PR
  that legitimately deletes a fetch. Replaced by named-witness coverage; `MIN_ROOTS` survives with a
  stated no-downward-ratchet rule.
- **Phase 0's sweep was fetch-scoped** while the rule says *write sites where the property applies*.
  Re-scoped to tag-authoring commands.
- **The `-B2` window had no stated derivation.** Now justified, with its limitation (an interposed
  `# shellcheck disable` line voids an exemption) declared as fail-closed rather than hidden.
- **Honesty clauses were prose.** AC33 now asserts the literal phrases.
- Smaller: Guard-2's Assembly corrected to **208** (201 `run_suite` + 7 `skip_suite`); the `sed`
  cross-check must join line continuations, since four registrations span one; `FIXTURE_EXCLUSION`
  separated from `SELF_EXCLUSION`; AC11 reworded to "before any verdict is graded"; the
  `.claude/` ↔ `.openhands/` `pre-merge-rebase.sh` parity check added to Phase 0.

### Rejected after verification

- **`code-simplicity-reviewer`: cut `--enumerate-commands` entirely; a `sed` parse covers it.** The
  supporting measurement is correct — 208 registration lines, exactly **3** with a variable in argv,
  and those 3 are the two `env VITEST_SHARD=…` vitest shards plus the glob loop's `bash "$f"`, whose
  expansion `--print-suite-globs` already publishes. But the flag is kept, for a reason the review
  did not weigh: issue #7917's constraint 1 is that the root set is **never hand-typed**, and
  `--enumerate` is the only surface that walks the real registration path — `want_*` conditionality,
  glob expansion and shard filter included — rather than re-deriving it. The blast radius the review
  correctly identified is now closed by setting `_ENUMERATE=1` (P0 above), which is what made the
  flag dangerous in the first place. The `sed` parse survives as the independent cross-check, and
  building two mechanisms that must agree is the point, not an oversight.
- **`code-simplicity-reviewer`: cut the closure; sweep every tracked executable instead.** Genuinely
  attractive — a repo-wide sweep has no blind spot to widen, and the population is small (measured:
  **40 files, 59 occurrences, 11 already suppressed**). Not adopted, because constraint 1 requires
  the root-set derivation and the census must say which offenders bear on cell 6 *specifically*; a
  guard that cannot distinguish battery-reachable from repo-wide answers a different question than
  #7917 asked. The review's strongest point is kept in substance: the closure over-approximates by
  construction, an unresolvable reference joins it rather than leaving it, and an unresolvable
  registration fails rather than being skipped — so the fail-open direction the review feared is
  closed without discarding the reachability annotation.
- **`code-simplicity-reviewer`: cut the helper self-test.** Recorded as a dissent in
  `## Technical Approach` Stage D. `2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md`
  is explicit that the remedy for this class is a self-test specifically, and it costs ~10 lines.
- **`code-simplicity-reviewer`: cut AC26 (`c4-count-parity`).** Kept. The plan skill requires a
  "no C4 impact" conclusion to be backed by a green run rather than by argument, and it is measured
  green today in ~seconds.
- **CTO domain review: `.claude/hooks/ship-runbook-ssh-gate.sh` is a confirmed live RED candidate.**
  Rejected on evidence. It *is* executed by `hook-input-contract.test.sh`, but every invocation is
  `(cd "$sandbox" && … bash "$SCRIPT_DIR/$hook.sh")` under a `mktemp -d -t hicroot.XXXXXXXX` root,
  and the hook exits at its own trigger gate because no payload in that suite contains `gh pr`.
  Rejecting it is what produced this plan's central reframing.
- **CTO domain review: `apps/web-platform/test/kb-*.test.ts` carry `git fetch`.** Rejected on
  evidence: the hits are `fetchUserWorkspacePathSpy` and a mocked git-op object in
  `kb-route-helpers.test.ts`. No sizing in this plan rests on them.

### Decision classes

Every adopted finding above is **mechanical** — a verified defect in a command, a pattern, a
contract or a phase ordering — and was applied directly. No finding was classed **taste** or
**user-challenge**, so nothing is persisted to `decision-challenges.md`: none of them proposes
changing the operator's stated direction. The two scope proposals that came closest (cut the flag,
cut the closure) are refused precisely *because* they would relax issue #7917's non-negotiable
constraint 1, which is the operator's stated direction.

## Plan Metadata Notes

No `spec.md` preceded this plan, so it carries no `lane:` — defaulted to `cross-domain`
(TR2 fail-closed). No brainstorm preceded it either, so nothing was carried forward; every claim in
`## Research Insights` was resolved against repository source in this session.

`plan` Phase 4.5's scoped strong-model consult was **not** run separately. Its purpose is one
independent read of the riskiest decision, and that decision — the property reframing — was put to
`architecture-strategist` in `## Plan Review` with a prompt that asks for the strongest case against
it and for a concrete scenario where the reframed guard is green while ADR-207 cell 6 is unsafe.
Adding a second generic consult over the same question would have bought a duplicate, not a check.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled, and its threshold is
  reasoned rather than asserted.
- **Do not let Phase 3 start before Phase 1's transcript is committed.** The cut #7795 guard failed
  for exactly this reason: it was authored after the tree was already clean, so it never had a RED
  window and nothing proved it could fire. If the pipeline is under time pressure, the transcript is
  the thing to protect, not the fix.
- **The `-B2` window is a contract, not a convenience.** An exemption marker four lines above its
  fetch is invisible to the check that grades the site, so it exempts nothing — and the site then
  reads as declared to a human and undeclared to the guard. Mutation row 4 exists to pin this.
- **`grep` exits 1 on no match and `set -e` promotes it out of a pipeline.** Every search in the
  guard must be `{ grep … || true; }`; a bare one kills the run before the floors are reached, which
  is a green that is not evidence.
