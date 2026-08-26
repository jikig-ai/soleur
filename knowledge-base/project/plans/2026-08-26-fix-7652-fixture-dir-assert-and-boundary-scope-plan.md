---
title: "fix(test-fixtures): take the caller's repository out of reach, and make the repo-write boundary check what it claims"
date: 2026-08-26
slug: fix-7652-fixture-dir-assert-and-boundary-scope
branch: feat-one-shot-7652-fixture-dir-assert-boundary-scope
issue: 7652
closes: 7652
lane: cross-domain
type: bug
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> No spec.md exists for this branch, so `lane:` could not be carried forward and defaults to
> `cross-domain` (TR2 fail-closed).
>
> **Revision R2 (2026-08-26).** Rewritten after an eight-consult review panel. The primary mechanism
> changed: v1 proposed asserting the operand at every call site; the panel measured that the same
> class dies at **one chokepoint** — running each suite with its working directory outside any git
> repository. Five factual claims in v1 were falsified by measurement and are corrected in
> Research Reconciliation. The `${CI:-}` severity tier, the `.git/hooks/` dimension, ADR-197 and
> the ADR-177 cross-reference are cut. Provenance for each change is in `## Review Disposition`.

## Enhancement Summary

**Deepened on:** 2026-08-26. Gates run: 4.6 user-brand impact (pass), 4.7 observability (all five
fields present, non-placeholder, probe verb `bash`, no SSH), 4.8 PAT-shaped variables (no match),
4.9 UI wireframe (no UI surface — skip), 4.10 encryption posture (no store or new connection — skip),
4.11 guard contract (`scripts/lint-guard-contract.py` green over all three entries).

**Verification sweep — every citation resolved live, none from memory:**

| Class | Result |
|---|---|
| Issue / PR numbers (`#6750`, `#7098`, `#7424`, `#7652`) | all resolve; states and titles match their use here |
| AGENTS rule IDs (`cq-ac-must-not-depend-on-concurrent-sessions`, `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`) | all **active** in `AGENTS.md`; none retired or fabricated |
| ADRs (084, 166, 177, 180, 193, 196) | all present on disk. `ADR-197` is absent **by design** — it is named only as the ordinal this revision **cut** |
| Label `compliance/critical` | exists |
| AC grep self-scope | no acceptance criterion greps a scope containing this plan |
| Literal consistency | `assert_fixture_dir`, `repo-write-boundary.sh`, `fixture-scan.py`, `TESTALL_TARGET_OVERRIDE`, `MIN_FIRING_SUITES` each carry one canonical spelling across plan and `tasks.md` |

**Verify-the-negative pass** on the load-bearing negative claim — *"no shipped path executes these
suites"*, which is what bounds the blast radius to one operator. Independently confirmed: no
plugin-local runner exists under `plugins/soleur/scripts/`, and no `CLAUDE_PLUGIN_ROOT`-rooted
invocation of a `.test.sh` exists anywhere in the shipped subtree. Shipped `SKILL.md` files do
*mention* `.test.sh` paths, which is precisely why the plan calls this bound **contingent rather
than structural** — it is one edit away from being false.

**Key improvements over v1**, all traceable in `## Review Disposition`: the primary mechanism moved
from a per-call-site assertion sweep to CWD isolation at one chokepoint; the property split into
P1a (empty operand, measured to affect only `git -C`) and P1b (relative operand, deferred with a
tracking issue); the `${CI:-}` tier, the `.git/hooks/` dimension and a new ADR were cut; redaction
became "digest every value" so no allowlist can be incomplete; and the config↔refs **composition
hole** was closed — two individually-defensible projections that, together, made a
`git -C "" checkout -b` escape invisible in both dimensions at once.

## Overview

Two remaining instances of the "a fixture suite can write into the operator's real repository"
family filed on #7652. The `cd`-escape half is already merged (`cdx()` in
`plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`, plus the repo-wide scanner
`plugins/soleur/test/fixture-cd-containment.test.sh`) and is out of scope except for two corrections
that change made necessary (Reconciliation rows 4 and 5).

**Instance 1 — an unasserted directory operand silently retargets a git write at the caller.**
`git -C ""` does not error; it operates on the current directory. Measured:

```
$ d=$(mktemp -d); cd "$d" && git init -q .
$ git -C "" config user.name probe-value     # rc=0
$ git -C "$d" config --get user.name         # -> probe-value
```

Fixture suites bind a directory from a positional parameter or a command substitution and
interpolate it into `git -C "$dir" config commit.gpgsign false` and similar writes. Under the test
runner the caller's directory is a live worktree whose `.git/config` is the **shared** bare repo
every worktree on the machine inherits. Measured production damage: that config was flipped and six
commits were created unsigned.

**The mechanism only works because the caller is standing inside a repository.** Measured from a
directory outside any repo:

```
$ git -C "" config user.name probe   -> fatal: not in a git directory
$ git -C "" config --local x.y z     -> fatal: --local can only be used inside a git repository
$ git -C "" commit --allow-empty -m x -> fatal: not a git repository
```

So the class dies at one chokepoint — `run_suite()` — rather than at every call site. That is this
plan's primary mechanism, and it also closes the 2026-08-20 lost-`cd` class, for every suite present
and future, with no per-site edits and no idiom taxonomy to maintain.

**Instance 2 — the repo-write boundary announces more than it inspects.** `scripts/test-all.sh`
snapshots `git rev-parse HEAD` plus `git status --porcelain | sha256sum` around the suite list and
prints `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY.` on a delta. It cannot see a `git config`
mutation — which is exactly instance 1 — nor a ref write. This is not a new architectural question:
**ADR-166 already decides it** ("No operator-facing message emitted by CI may name a cause the job
did not measure"), so this is an existing-ADR compliance fix, not a new decision.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| #7652 open, unclosed | `gh issue view 7652 --json state,closedByPullRequestsReferences` | **HOLDS** — `OPEN`, no closing PR |
| Both instances filed into #7652 | `gh issue view 7652 --json comments` | **HOLDS** — comment of 2026-08-25 |
| `git -C ""` targets the CWD | reproduced above | **HOLDS** |
| …and fails outside a repo | reproduced above | **HOLDS** — this is the chokepoint |
| `--local` in a worktree reads shared config | `git config --local --list` here | **HOLDS** — other worktrees' `branch.*` present |
| Six helpers take a directory positionally | read all six | **FALSIFIED** — rows 1-2 |
| Suggested `${1:?}` fix is right | measured both shapes | **FALSIFIED** — row 3 |
| `plugins/soleur/test/*.test.sh` auto-registers | `SUITE_GLOBS`, `scripts/test-all.sh:55-68` | **HOLDS** |
| The runner makes no git writes of its own | read the runner + its three libs; `orphan-process-reaper.sh` runs in `report` mode at `:812`, before `tc_acquire` at `:914` | **HOLDS** |
| An existing ADR already governs instance 2 | grepped the ADR corpus for the *mechanism* (a message naming more than it measured), not the issue number | **NEW — ADR-166** |

**Machine-state numbers are deliberately absent from this plan.** v1 asserted "55 config entries,
3074 refs"; both had drifted within hours (61 and 3080). Every such number is re-measured in Phase 0
and printed with the probe that produced it (`cq-cite-content-anchor-not-line-number`).

### Property List (Phase 0.6b)

- **P1a — empty operand.** A fixture's git write cannot be retargeted at the caller's repository by
  an **empty** directory operand. Measured: only `git -C` exhibits this. This is the demonstrated
  damage.
- **P1b — relative operand.** A fixture's destructive command cannot be mistargeted by a **relative**
  operand resolving against the caller's directory. Different property, no demonstrated firing.
- **P2 — the repair holds for the next edit**, without anyone remembering it.
- **P3 — the boundary says what it inspects**, names what it does not, and what it prints to make a
  delta adjudicable does not itself leak a credential.

### Cut List (Phase 0.6b)

| Mechanism | Property | Disposition |
|---|---|---|
| Per-call-site operand assertion at every binding | P1a | **DEMOTED to residual.** CWD isolation buys P1a at one chokepoint for every suite the runner starts. The assertion remains only where isolation does not reach (Phase 3) |
| CWD isolation at `run_suite` | P1a + the lost-`cd` class | **PRIMARY** |
| A `git -C`-only static scanner | P2 | **KEPT**, scoped to P1a |
| A four-family scanner (`rm -rf`, `mv`/`cp -r`, redirections) | P1b | **CUT.** Measured: `rm -rf ""` is a silent rc=0 no-op, `mv a ""` is rc=1, `cp -r s ""` is a no-op, `> ""/f` is rc=1. None widens on empty. Their hazard is P1b, a different property, deferred with a tracking issue rather than silently exempted |
| `.git/hooks/` snapshot dimension | P3 | **CUT.** `git rev-parse --git-path hooks` ignores `core.hooksPath` (which is set here) and resolves to the *shared* common dir, so it is neither the executing directory nor sibling-immune. The weaponisation — repointing `core.hooksPath` — is a config write already caught. Named in the not-inspected list |
| Loose objects in the snapshot | P3 | **CUT** — churned by `git gc` and by any fixture that creates objects. Named in the not-inspected list |
| `${CI:-}` severity tier | P3 without false REDs | **CUT.** With refs projected by harm class the FATAL set is environment-independent, so the tier serves nothing. Also: `scripts/test-all.sh:867` already refuses a full-gate run with `exit 4` when a stamped sibling run is in flight, *before* the boundary opens, which closes the sibling-**runner** class outright |
| Redaction allowlist + a CI key-name derivation step | P3 no-leak | **REPLACED** by "digest every value, print every key name" — one rule, no allowlist to leak through, detection unaffected |
| A new ADR (v1's ADR-197) | workflow gate | **CUT** — ADR-166 already decides it; an ADR-180 addendum covers the residue |
| ADR-177 cross-reference | none | **CUT** — the claim was false. ADR-177 is an exit-code contract; a non-failing named class already ships (the boundary's own not-measured NOTE) and ADR-177 was never amended for it |
| shellcheck / semgrep instead of a scanner | P2 | **CUT** — shellcheck 0.10.0 is clean on the exact shape under `-o all` except SC2250 (braces); SC2086 concerns *unquoted* expansion, so quoting the operand silences it while leaving the hazard. No tool models a callee's empty-operand semantics |

### Relevant institutional learnings

- `2026-08-20-every-guard-was-present-read-as-protective-and-did-not-hold.md` — a guard's claim is
  almost always narrower than its assembly; the narrowness is revealed by **mutating the guard and
  watching it accept**.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — name the
  cheapest edit that breaks the named property while leaving the guard GREEN. Prove each mutation
  landed with `diff -q` against a pristine copy, never against `HEAD`.
- `2026-08-20-every-guard-i-fixed-was-narrower-than-the-claim-it-carried.md` — diff the CODE against
  the COMMENT; after fixing an escape, re-run and assert the repository is unchanged.
- `2026-08-20-my-mutation-battery-sampled-the-axes-i-already-believed-in.md` — **state the axes you
  did NOT edit.** This plan's unsampled axes are listed at the end of the Guard Contract.
- `2026-08-16-my-guards-sentinel-matched-its-own-temp-directory-name.md` — a guard's own
  infrastructure is inside the space its oracle searches.
- `2026-08-10-my-verification-was-narrower-than-the-claim-it-certified.md` — suites that copy
  themselves out of the tree and re-execute break sourced-helper assumptions.
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — an empty variable in a command context widens
  the target rather than failing.
- AGENTS `cq-ac-must-not-depend-on-concurrent-sessions`; `cq-assert-anchor-not-bare-token`;
  `cq-cite-content-anchor-not-line-number`.
- ADR-166 (a CI message may only name a cause the job measured) — **governs instance 2**.
  ADR-193 (anti-vacuity floor contract). ADR-180 (guard contract as a plan-time deliverable).
  ADR-177 (runner result taxonomy). ADR-196 (refusal binds to a measured condition).

### Codebase facts established at plan time

- **The runner already has a sandbox vehicle for driving itself under mutation.**
  `scripts/test-all-killed-classification.test.sh` and `scripts/test-all-infra-coverage-notice.test.sh`
  set `TARGET="${TESTALL_TARGET_OVERRIDE:-…/scripts/test-all.sh}"` and `build_sandbox()` copies the
  runner plus the libs it sources into a temp tree, patching it with python. Its own comment:
  *"Overridable so the suite can be pointed at a mutated copy and PROVED to red against it."* This
  is Guard 2's execution vehicle; nothing needs inventing.
- **Those two sandboxes delete a region of the runner.**
  `test-all-killed-classification.test.sh:213-218` replaces everything between `tc_acquire "test-all"`
  and `tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"`. The boundary **start** block sits inside that
  window; the **end** block outside it reads `_repo_guard_ok` / `_repo_state_before`, which survive
  only because they are initialised *above* `tc_acquire`. Both sandboxes also `cp` each sourced lib
  explicitly — ADR-177 A3 records omitting that as **measured fatal**.
- `scripts/test-all.sh:867` refuses a full-gate run (`exit 4`) on a stamped non-zero sibling count.
- `SIBLING_RUN_DETECTED` (`scripts/lib/test-contention.sh:617`) is sampled once in `tc_preamble`,
  before the lock wait, and counts sibling **runners**.
- `SUITE_GLOBS` covers `plugins/soleur/test/*.test.sh` and `scripts/lib/*.test.sh`;
  `scripts/*.test.sh` is **not** globbed. `scripts/lint-orphan-test-suites.sh` derives from
  `--print-suite-globs` and is keyed on the `*.test.sh` **suffix**, which its own header records as
  a known blind spot for the `test-<name>.sh` convention.
- `plugins/soleur/test/fixture-cd-containment.test.sh`'s `WRITE` regex is
  `commit|push|add\b|update-ref|checkout|reset|branch\s+-[dD]|worktree\s+(add|remove)|rm\b|mv\b`
  — **`config` is absent**, so a `cd`-escape followed by `git config` is invisible to both existing
  guards. Adding it is one word.
- `scripts/lint-shell-capture-exit.py` establishes the house **shrink-only `--baseline`** pattern
  (`--write-baseline`, "This file may only SHRINK"), registered as a `lint-*` pair in the runner.
- `scripts/guard-vacuity-floor.test.sh`: `COVERED_DIRS='^(scripts/|plugins/soleur/test/)'`,
  `MIN_FIRING_SUITES=36` against a measured 45 — **nine slack, so adding suites cannot turn it red**.
- House style for a required-directory assertion is the `TMP_REAL`/`cdx()` shape in
  `lease-protects-active.test.sh`. `${1:?}` **does** have repo precedent (≥10 sites, including the
  `local x="${1:?…}"` shape in `plugins/soleur/skills/community/scripts/discord-community.sh:150`).
- `plugins/soleur/**` ships to installed users via the marketplace `git-subdir` source; 101 tracked
  `plugins/soleur/**/*.test.sh` are delivered bytes on every install. `.claude/hooks/*.test.sh` (45
  files) are not. **No shipped path executes any of them** — there is no plugin-local runner — so the
  blast radius stays one operator. That boundary is contingent, not structural (see User-Brand Impact).

### Value-proposition measurement (Phase 0.6c)

The change is justified by damage, not saving: three escapes in under two hours, one destroying hours
of uncommitted work, every suite green throughout. The one cost figure that matters is the migration
cost of CWD isolation, measured in Phase 0 — proxy already taken: **358 of 373** tracked `*.test.sh`
compute their root from `BASH_SOURCE` (CWD-independent); **29** use `git rev-parse --show-toplevel`
(CWD-dependent) and are the candidate breakage set.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Response |
|---|---|---|
| 1. `context-reviewed-gate.test.sh` `new_repo()` takes a positional dir | **False.** It binds `tmp=$(mktemp -d)`; its `$1` is *document content*, deliberately empty at `:134`. The prescribed `${1:?}` would break the suite | Fix its actual exposure — an unasserted `mktemp` result. Also fix the **caller**: `r=$(new_repo …)` then `git -C "$r" add` at `:80`, in a file with no `set -e`, is the identical defect one frame up. Fixing only the helper converts the escape into the same escape in the caller |
| 2. "Six helpers take a directory positionally" | Five do. A probe finds far more sites than the issue enumerates, and the counts differ by an order of magnitude depending on the family | **The scanner defines the population.** No inventory in this plan is an acceptance set. Phase 0 freezes the scanner's first output as a shrink-only baseline |
| 3. `${1:?}` vs the `case` shape "behaves identically in and out of a subshell" | **False, measured.** `exit 2` inside `$( )` terminates the substitution exactly as `${1:?}` does; both leave the caller proceeding with an empty variable. And `${1:?}` **has** ≥10 repo precedents | Keep the `case` shape for the reasons that survive (row 1's doc-content case; a message naming the live repository; house `cdx()` consistency). **Delete both false justifications.** The residual — a caller inside `$( )` proceeding with an empty variable — is a real gap, closed by CWD isolation rather than by the assertion |
| 4. "three of the five helpers are called from inside `$( )` / `< <( )`" | **False.** All five are plain statements. But the form is live elsewhere: `read -r work origin incidents < <(make_synced_branch …)` at ten sites in `ship-unpushed-commits-gate.test.sh`, and `new_repo` is `$( )`-called at 14 | Delete the fabricated claim; keep the binding form, sourced from the sites that actually exhibit it |
| 5. `git -C "<fixture>"` makes a write safe | The `cd` scanner **exempts** `git -C` and its header recommends it: *"Prefer the last: a write that names its own repository cannot be redirected at all."* Falsified by `git -C ""` | Amend that comment and prose, **and add `config` to its `WRITE` regex** — verified absent, and the cheapest line in this change |
| 6. `set -e` would have prevented this | Three of the five files already run `set -euo pipefail`; `git -C "" config` **succeeds** | State it. The property is orthogonal to shell strictness |
| 7. `rm -rf "$1"` at `ralph-loop.test.sh:45` proves the scanner must not be `git -C`-only | **False.** `rm -rf ""` is rc=0, a silent no-op. That site's hazard is a *relative* operand — property P1b, not P1a | Split P1a from P1b; scope the scanner to P1a; defer P1b with a tracking issue. A named deferral is a scope boundary; a silent exemption is a hole |
| 8. `--heads --tags` removes the sibling ref churn | It removes ~2% of refs. The retained local branches are fully sibling-shared | Delete the rationale. Refs are made safe by **harm-class projection**, not by that exclusion |
| 9. `_repo_state()` in a lib makes the boundary testable | It makes the **lib** testable. The window, the two call sites and the message text are properties of the runner | Use the existing `TESTALL_TARGET_OVERRIDE` + `build_sandbox` vehicle, and add both sandbox suites to Files to Edit so they copy the new lib (ADR-177 A3: omitting it is measured fatal) |
| 10. A per-dimension not-measured state is a refinement | It re-creates instance 2 one level down: the message would print a static inspected list naming a dimension it did not inspect | **Cut per-dimension degrade.** Whole-function degrade-open, as today. If the inspected list is ever made dynamic, it must be derived from what was measured |

## User-Brand Impact

**If this lands broken, the user experiences** — in their own terms, not the repository's:

- Their commits quietly stop showing **Verified** on GitHub, and a branch-protection rule starts
  rejecting a push with an error they cannot parse. Nothing told them their signing setting changed.
- An afternoon of work is **gone**, with no error at the moment it happened.
- **And every test said PASSED throughout.** That is the part that matters: Soleur's promise is an AI
  organization a non-technical founder can run, and the measured incident is that organization
  destroying their work and reporting success, three times in under two hours. The brand risk here
  is not data loss, it is the promise inverting.
- Two further modes created by the fix itself: a false accusation (`A SUITE WROTE TO THE LIVE
  REPOSITORY`) sending them into recovery surgery on a repository nothing wrote to; and a guard that
  correctly detects a real write and emits a **non-failing line into a wall of test output** that
  they will never see.

**Recovery, named rather than assumed.** `plugins/soleur/skills/git-worktree/SKILL.md` documents the
order: push the objects to durability *first*, then `update-ref` as a compare-and-swap, then restore
the checkout. The boundary message links it. Uncommitted work is unrecoverable, which is why the
prevention half is the priority.

**If this leaks, the user's credentials are exposed via** the boundary's own failure output. The
widened snapshot reads local git config, which on a CI runner carries an `http.*.extraheader` token
composite that GitHub's log masker does not reliably catch, and locally carries credential helpers.
This is a risk the fix creates; digesting every value is its answer (Risks R2).

**Blast radius today is one operator**, and the reason is contingent rather than structural: 101
`plugins/soleur/**/*.test.sh` are delivered to every installed user, but no shipped path executes
them (there is no plugin-local runner). Ship one — or make a shipped script resolve a runner through
`CLAUDE_PLUGIN_ROOT` — and this same defect becomes a write into every user's repository. That
precondition is recorded in the C4 note and in the deferred-work issue.

**Brand-survival threshold:** single-user incident. CPO sign-off is required before implementation;
`user-impact-reviewer` runs at review time.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` (64 issues), matched against every path
in Files to Create / Files to Edit. Positive control: the same query matches 33 issues on
`apps/web-platform`, so the zero is real.

- **No overlap** on any file this plan touches.
- Family-adjacent, not overlapping: **#7098** (*audit the 56 `run:` bodies whose `set` omits `-e`*).
  **Disposition: acknowledge** — different file set, and this defect is invisible to `set -e` because
  the offending command succeeds.

## Architecture Decision (ADR/C4)

**No new ADR.** Instance 2 is governed by **ADR-166** — *"No operator-facing message emitted by CI
may name a cause the job did not measure"* — whose §2 (do not collapse "could not check" into "bad")
and §4 (*"enforcement is the lint, not the prose"*) apply directly. This is compliance with an
existing decision, not a new one. v1 proposed ADR-197 on the strength of a "static environment
predicate" axis that no longer exists once the `${CI:-}` tier is cut.

Residue worth recording goes in a short **ADR-180 addendum**: a guard's inspected set is part of its
contract, and each dimension is projected by harm × churn rather than by storage locality. No new
ordinal, so none of v1's ordinal-collision ceremony applies.

### C4 views

**No C4 impact**, against an enumeration read from all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:

- **External human actors:** none added. Exercised by `founder` and, on the CI path, `contributor`;
  both modelled. `contributor`'s description already records that *"other operator-side execution of
  a checked-out PR head (running its tests, its scripts, its hooks) is covered by NEITHER boundary"*
  — still true, and CWD isolation narrows it without changing the model.
- **External systems / vendors:** none.
- **Containers / data stores:** none read or written.
- **Actor↔surface access relationships:** unchanged.

**Correction carried from review:** v1 asserted "every changed file is a developer-machine or CI-time
artifact." That is **false** — `plugins/soleur/**` files are delivered to every installed user by the
marketplace subtree. The accurate statement is **delivered, not executed**, and the load-bearing
precondition is the absence of a plugin-local runner. The `soleurMarketplace` element description is
already correct; no `.c4` edit is required, but the distinction is recorded here so the next reader
does not conclude this class is out of scope for the wrong reason.

## Implementation Phases

### Phase 0 — Measure, freeze, decide (no product edits)

1. Reproduce the mechanism in both directions: `git -C ""` inside a repo (writes) and outside one
   (`fatal`, rc≠0). Record both for the PR body.
2. **Cost the primary mechanism.** Run the affected shards with each suite's CWD set to a throwaway
   directory outside any repository (plus `GIT_CEILING_DIRECTORIES`), and record exactly which suites
   break. The candidate set is the 29 suites using `git rev-parse --show-toplevel`; the other 358
   resolve from `BASH_SOURCE` and are CWD-independent. **Decision rule, pre-committed:** if the
   breakage set is ≤ 40 suites and each break is a path-resolution fix, CWD isolation is the primary
   mechanism and Phase 3's sweep is the residual only. If it is larger, isolation still lands for the
   suites that pass, and the residual sweep widens — record the measured number either way.
3. Build the Phase 3 scanner as a **read-only probe** and freeze its first output — site count and
   file list — as a shrink-only baseline, before any remediation idiom is chosen. This is what makes
   later narrowing detectable rather than a judgment call: a reduced count with no matching
   remediation commit is a ratchet violation.
4. Re-measure every machine-state number this plan would otherwise assert (config entry count, ref
   counts, per-family site counts) and print the probe beside each.
5. Assert `extensions.worktreeConfig` is unset and no `config.worktree` exists — otherwise `--local`
   stops denoting the shared file and the config dimension silently narrows.
6. Record the pre-change verdict of every suite in scope, and of
   `scripts/test-all-killed-classification.test.sh` and `scripts/test-all-infra-coverage-notice.test.sh`.
7. **Observe-only full run, before any dimension becomes FATAL.** Run the complete battery with the
   widened `_repo_state` reporting but not failing, on a clean CI-shaped checkout **and** locally,
   and confirm a zero delta across every dimension. The plan's own premise is that a fixture *did*
   write into shared config during a run; if any such write is still reachable, flipping the
   dimension to FATAL before the sites are fixed turns every CI shard red for every author. Running
   each candidate suite individually (step 6) does not answer this — only a full run does. This is
   the gate on the claim that the boundary work is independently shippable.

### Phase 0 measurement — Addendum 2026-08-26 (#7652): the decision rule fires AGAINST isolation

Phase 0 step 2's decision rule was pre-committed as: *if the breakage set is ≤ 40 suites and each
break is a path-resolution fix, CWD isolation is the primary mechanism; if it is larger, isolation
still lands for the suites that pass and the residual sweep widens — record the measured number
either way.* Measured on this branch, at `main` = `924994b2f`:

| Probe | Command | Result |
|---|---|---|
| suites resolving their own root via `show-toplevel` | `git grep -l 'rev-parse --show-toplevel' -- '*.test.sh'`, minus fixture-scoped uses | **22** |
| `run_suite` call sites naming an existing **relative** command path | walk of `grep -E '^\s*run_suite '` over `scripts/test-all.sh` | **170 of 177** |
| suites reading the LIVE repo via a bare `git ls-files`/`grep`/`diff`/`log`/`rev-parse` | `git grep -lE '(^\|[^-])git (ls-files\|grep\|diff\|log\|rev-parse\|show\|config --get)' -- '*.test.sh'` | **64** |

**The plan's own estimate was the 22, and it was the wrong quantity.** Two costs it did not
project, both larger:

1. Every `run_suite` call site — and the auto-discovery glob loop's `run_suite "$f" bash "$f"` —
   passes the suite as a path relative to the repo root. Under isolation the interpreter cannot
   find the script at all, so the breakage is at the INVOCATION layer, not inside the suites.
   This one is centrally fixable (absolutise relative file args inside `run_suite`, ~10 lines) and
   is not the blocker.
2. **64 suites read the live repository on purpose.** A corpus scanner cannot run with the corpus
   unreachable, and `fixture-cd-containment.test.sh` — the guard this issue's first half shipped —
   is itself one of them. Their "fix" is `-C "$REPO_ROOT"` on every git call across 64 fixture
   suites, which is both far past the threshold and an en-masse edit of fixture suites: the exact
   activity the boundary detector exists to watch, performed before the detector has ever run
   green.

64 > 40, and these are not path-resolution fixes. **The rule therefore selects the residual sweep
as the primary mechanism**, and Phase 3 is promoted accordingly. Per-suite opt-in isolation for the
subset that would pass was considered and declined: classifying 374 suites by whether they need the
repo is a judgement call on every member, and a wrong classification fails OPEN — the suite keeps
its repo access and nothing reports that it was meant to lose it.

What is given up is stated rather than elided: the lost-`cd` class (#7553) does not die at a
chokepoint, so it stays covered only by `cdx()` in the one suite that has it plus
`fixture-cd-containment.test.sh`'s repo-wide scanner. The `git -C ""` class is covered by Phase 3
at every site the scanner can see, and the boundary reports any escape that gets past both.

### Phase 1 — CWD isolation at `run_suite` (SUPERSEDED — see the addendum above)

1. `run_suite()` starts each suite with its working directory in a per-run throwaway directory
   outside any git repository, with `GIT_CEILING_DIRECTORIES` set. Suites that need the repo root
   already compute it from `BASH_SOURCE`; the 29 that use `git rev-parse --show-toplevel` are
   converted to the `BASH_SOURCE` form, which is the majority convention.
2. This closes P1a **and** the lost-`cd` class for every suite the runner starts, present and future.
   It does **not** reach: a suite invoked directly (`bash path/to/x.test.sh`), lefthook's hook path,
   or the corpora outside `SUITE_GLOBS`. Those are Phase 3's residual, and the limit is stated in the
   boundary message rather than left implicit.
3. A guard asserts the isolation is still in place — a suite whose recorded CWD is inside a git
   repository fails.

### Phase 2 — the boundary: inspect more, claim exactly that

1. Extract `_repo_state()` into `scripts/lib/repo-write-boundary.sh`, sourced by the runner.
   **Placement is load-bearing:** the `source` line, the function definition and every new variable
   initialisation go **above** `tc_acquire "test-all"`, because the two SUT sandboxes delete
   everything between that anchor and `tc_epilogue`, and the end block runs under `set -u`.

   **Source contract — the `_REL_LIB` class, not `|| true`.** The runner's three existing libs use
   three deliberately different contracts, and `_REL_LIB`'s comment states the selection rule: a lib
   that decides whether the gate means anything is a **hard failure** when missing. This one
   qualifies. Under a `|| true` contract, an undefined `_repo_state` returns 127 inside
   `if _repo_state_before="$(_repo_state)"`, `set -e` does not fire in an `if` condition, and the run
   prints *"the repo-write boundary was not measured (**git unavailable at run start**)"* — naming a
   cause it did not measure, which is an ADR-166 violation manufactured by this fix. So: `exit 2` on
   a missing file, plus a `declare -F` check over a named function set in the `_TC_LIB` shape, so a
   **stale** lib is named rather than silently narrowing.

   **The claim renders from the check.** `_repo_state()` returns a machine-readable dimension
   manifest — the dimensions it measured, each marked `measured` or `not-measured` — and the message's
   "inspected:" and "not inspected:" lists are rendered **from that manifest**, never from a literal
   list in the runner. Otherwise the claim lives in `test-all.sh` and the check lives in the lib, and
   a stale lib beside a full-dimension claim is exactly the #7652 defect re-created one layer up
   across a brand-new module seam. This also gives per-dimension degrade an honest representation:
   a dimension that could not be captured is named as such instead of being silently included in a
   static claim.

2. Dimensions, each with its projection and the reason for it:

   | Dimension | Projection | Reason |
   |---|---|---|
   | HEAD | `git rev-parse HEAD` | per-worktree; status quo |
   | working tree / index | `git status --porcelain` | per-worktree; status quo |
   | local (shared) config | `git config --local --list -z`, split on NUL, **digest every value with a per-run salt, keep every key name**, sort. Carve out only `branch.*.vscode-merge-base` | See the composition note below — the naive `branch.*` cut opens a hole. Digesting every value means there is no redaction allowlist to be incomplete; the salt stops a low-entropy value (`credential.helper` ∈ {`store`, `cache`, …}) from being dictionary-reversible or comparable across logs, and the digest only needs to be stable **within** one before/after pair |
   | local refs | `git show-ref --heads --tags`, sorted, split by **harm class measured from `git worktree list`** — not by an environment predicate | See below |

   **Refs harm class.** FATAL: this worktree's checked-out branch; the default-branch ref; **any ref
   deleted**; any tag. REPORT: creation or movement of a head belonging to a branch that
   `git worktree list` reports checked out **elsewhere**. That enumeration is a measured read of the
   ref store, not a concurrency sniff, so it carries none of the objection that killed the `${CI:-}`
   tier. Deletion is FATAL because `git show-ref` exits 1 on *no refs*, and treating that as
   "capture failed" would fail open on the most destructive ref outcome. `refs/remotes/**` is
   excluded — not because it removes the churn (it removes ~2%) but because a fetch is the only
   thing that writes it and an escape has no reason to. *Accepted residual:* `tagOpt` is unset, so a
   sibling `fetch` during a run writes tags and produces a FATAL. Sibling fetches are rare inside a
   gate window and the printed diff names the tag, so this adjudicates in seconds.

   **Composition — why a blanket `branch.*` cut is wrong.** No tracked shell writes `git config
   branch.*` directly, so the "disjoint from the incident class" claim is true on the axis it was
   measured. It is the wrong axis: `branch.<n>.remote` and `.merge` are written as a **side effect**
   of `git push -u` and `git checkout -b --track`, and the fixture corpus is saturated with both.
   Measured: `git push -u origin HEAD:refs/heads/probe` writes `branch.main.remote` and
   `branch.main.merge`. Production code knows this — `worktree-manager.sh:1512` passes `--no-track`
   specifically to avoid it — and the fixtures do not. Compose the two naive projections against a
   `git -C "" checkout -b probe origin/main` escape: config writes only `branch.probe.*` (filtered
   out) and refs writes `refs/heads/probe` (REPORT). Local coverage: **zero**. Keeping
   `branch.*.remote` / `.merge` closes it; only `vscode-merge-base` is pure tooling churn.
3. **Shell discipline:** the config pipeline runs under the runner's `set -euo pipefail`, where a
   zero-match `grep` exits 1 and `pipefail` promotes it. Use the house brace form
   (`{ grep -v … || true; }`) *inside* the pipeline, per the reasoning at
   `scripts/guard-vacuity-floor.test.sh:160-165`. `git show-ref` exits 1 on **no refs**, which is a
   legitimate empty result, not a capture failure — distinguish them, or ref *deletion* reads as
   not-measured and the dimension fails open on its most destructive outcome.
4. Whole-function degrade-open, as today: `git rev-parse HEAD` failing returns non-zero and the run
   reports honestly that it is not evidence. No per-dimension not-measured state — a static inspected
   list plus a partially-measured snapshot is instance 2 reintroduced inside its own fix.
5. Rewrite the message, rendering both lists **from the manifest** (step 1), never from a literal:
   - **inspected:** HEAD; this worktree's tree and index; local config except
     `branch.*.vscode-merge-base`; refs by harm class as above.
   - **not inspected:** the *content* of a push to a remote (though `push -u` does leave a local
     `branch.*` artifact, which **is** inspected — see the composition note); loose or packed
     objects; `.git/hooks/` contents; `branch.*.vscode-merge-base`; remote-tracking refs; reflogs;
     the relative order of a multivalued config key (the projection sorts, so a reordering of
     repeated `http.*` or `remote.*.fetch` entries is invisible); any entry point other than runs of
     this runner; and any suite this runner did not start.
   - **next action, per dimension.** The current text offers `git reflog` and
     `git log origin/main..main`, which are HEAD/worktree instructions and say nothing about a config
     flip. Each dimension names its own next action, and the recovery order is linked.
   - **attribution:** point at the `[contention]` preamble, which lists the offending worktrees.
     Do **not** echo `SIBLING_RUN_DETECTED` at the boundary: it is sampled once before the lock wait,
     and the runner refuses outright when it is non-zero, so at the boundary it is ~always 0 —
     a number that is zero exactly when it would matter.
6. Emit the verdict once more in the breakdown area so it survives scrollback. It must **not** be
   `=== `-shaped: `=== N/M suites passed ===` has to remain the last `===` line (#6750/#7424).
7. Teach `scripts/test-all-killed-classification.test.sh` and
   `scripts/test-all-infra-coverage-notice.test.sh` to copy the new lib into their sandboxes.
8. A run killed before the end boundary emits nothing today (the runner has no `trap … EXIT`), and
   the escape most likely to kill a run is exactly the one that suppresses the verdict. Emit the
   not-measured NOTE from an EXIT trap so "no FATAL line" cannot be read as "clean".

### Phase 3 — the residual assertion, and the guard that keeps it

1. Add the assertion where CWD isolation does not reach, in the house shape, as a **named function**
   `assert_fixture_dir` with one canonical body — not a pasted idiom. The scanner then recognises a
   **name token** rather than three reformattable free-text spellings. Delivery is two-way, because a
   single sourced lib is not viable across the six trees (`plugins/soleur/` ships standalone and
   `scripts/lib/` does not ship with it; three live suites copy themselves out of the tree and
   re-execute; `REPO_ROOT` is computed five different ways; and the 40 existing `source` lines carry
   no `|| exit`):
   - **sourced** where the file already sources `plugins/soleur/test/test-helpers.sh`;
   - **defined inline** elsewhere — the `cdx()` precedent — with a rule that every inline definition's
     bytes equal the canonical copy, which is the drift check `cdx()` itself lacks.
   The body rejects empty, rejects relative, and rejects bare `/` (a `/*` case accepts `/`, and
   `rm -rf "/"/*` is the worst outcome in the corpus). It tests the leading `/` only — never a
   `realpath` comparison, which breaks on a symlinked `/tmp`.
2. The scanner is **one shared module** (`plugins/soleur/test/lib/fixture-scan.py`) imported by both
   `fixture-cd-containment.test.sh` and a new sibling suite. Do not rename or merge the existing
   suite: renaming costs the vacuity-floor bookkeeping, `TEST_TIMING_LOG` label identity and every
   prior-PR reference, for no property. The shared module is what makes the composition invariant
   code-adjacent instead of a prose comment spanning two files.
3. Scanner scope — **P1a only**: `git -C "$X" <write-verb>` where `X` is bound from a positional (at
   binding or at the use site), or from a **command substitution** (not only `mktemp` — the live
   forms include `$(new_repo …)`, `read … < <(make_synced_branch …)`, and `$(cd … && pwd)`), with no
   `assert_fixture_dir` call, `|| exit`/`|| return`, or `case` guard between binding and use. Name
   `init`, `clone` and `worktree add` explicitly in the verb list: `git -C "" init` returns rc=0 and
   re-initialises the caller's repository, which the intuition "init on an existing repo is harmless"
   will otherwise cull.
4. **Corpus:** `git ls-files '*.sh'`, not `'*.test.sh'`. The `*.test.sh` suffix misses
   `tests/hooks/test_hook_emissions.sh` (a `git -C "$path" init` helper that the runner **does** run),
   `.github/scripts/test/test-infra-suite-registration-mutations.sh`, sourced libs such as
   `test-helpers.sh`, and `scripts/context-reviewed-gate-discoverability.sh`. v1 named that last file
   and said the scanner would not cover it — a declaration site for a whole corpus.
5. **The population is managed by a shrink-only baseline**, in the established
   `scripts/lint-shell-capture-exit.py` shape (`--baseline`, `--write-baseline`, "this file may only
   SHRINK"). This is the pre-committed answer to "what if the first run returns 150 sites": land the
   guard with the measured baseline, burn it down, and let the ratchet forbid regrowth. Without it
   the plan dead-ends into a judgment call under schedule pressure, with its own doctrine forbidding
   both available escapes.
6. Add `config` to `fixture-cd-containment.test.sh`'s `WRITE` regex, and correct its `git -C`
   exemption comment and its *"Prefer the last"* header prose.
7. File the P1b tracking issue (relative operands: `rm -rf`, `mv`/`cp -r`, redirections), the
   deferred-work issue for the plugin-local-runner precondition, and the pre-existing
   `gdpr-gate`-rule-staleness issue (Compliance Gate below).
8. Bump `MIN_FIRING_SUITES` by the number of firing suites added. One line — it has nine slack and
   cannot fail either way, so it gets no phase step, no risk row and no acceptance criterion of its own.

### Phase 4 — Verification

1. Both new suites GREEN; every touched suite re-run individually.
2. Full battery for the affected shards, then assert the repository is unchanged across **all**
   inspected dimensions — not only HEAD and porcelain, which are the two that could never see this
   incident class.
3. Every mutation-matrix row executed and recorded, each mutation proven landed with `diff -q`
   against a pristine copy.
4. `scripts/lint-orphan-test-suites.sh` and `scripts/guard-vacuity-floor.test.sh` green; both SUT
   sandbox suites still pass.
5. **`bash scripts/lint-diagnosis-claims.sh` green.** This is a BLOCKING gate (its own header says
   so) enforcing principle AP-021 — *a diagnostic may only name a cause the run measured* — and its
   corpus is `.sh` files under `scripts/` with `*.test.sh` excluded, so both `scripts/test-all.sh`
   and the new `scripts/lib/repo-write-boundary.sh` are inside it. This plan rewrites ~20 lines of
   operator-facing diagnostic text and authors a new message-emitting lib; the gate owns that text.
   Three AP-021 obligations follow from it: the degraded NOTE must not name "git unavailable" for a
   lib-source failure (handled by the hard-fail contract in Phase 2 step 1); the REPORT arm must not
   let a reader treat a zero sibling count as evidence; and `_repo_last_suite` ("Last suite started")
   must be demoted in the REPORT arm, whose whole premise is that a suite probably was **not** the
   cause.
6. If either new suite is not mutant-constructible, **fix the suite** — `guard-vacuity-floor.test.sh`
   states "cover it, or promote its directory into COVERED_DIRS — do NOT raise this number", and both
   new paths already fall inside `COVERED_DIRS`. `MAX_CONSTRUCTION_FAILURES` is not to be raised.

## Compliance Gate (GDPR)

The canonical regulated-data regex matches nothing here. The gate was invoked anyway because the
declared threshold is `single-user incident`, which is an independent trigger. **Result: no finding
on this change** — it adds no data collection, no egress and no persistence. A **pre-existing** repo
condition surfaced instead: `gdpr-gate.sh` refused before scanning with *"rules 108 days stale (last
verified 2026-05-10)"* and `POSTURE_FAIL`. No open issue tracks it (checked, including the
`compliance/critical` label). Phase 3 files one; fixing it here would widen a bug fix into a
vendored-content refresh.

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/lib/repo-write-boundary.sh` | `_repo_state()`, its four dimensions, the value-digest projection. |
| `scripts/lib/repo-write-boundary.test.sh` | Guard 2 unit arm. Auto-registers via `SUITE_GLOBS`. |
| `plugins/soleur/test/lib/fixture-scan.py` | The shared scanner module (corpus walk, heredoc skipping, comment skipping) imported by both scanner suites. Not a `*.test.sh`, so the orphan lint is unaffected. |
| `plugins/soleur/test/fixture-dir-operand-assert.test.sh` | Guard 1 — the P1a rule plus its anti-vacuity battery. |
| `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` | Shrink-only grandfather list. |

## Files to Edit

| Path | Change |
|---|---|
| `scripts/test-all.sh` | CWD isolation in `run_suite`; source the new lib and place every new symbol above `tc_acquire`; call `_repo_state()` at both boundaries; rewrite the message (inspected / not-inspected / per-dimension next action / attribution); re-emit in the breakdown area; EXIT-trap NOTE. |
| `scripts/test-all-killed-classification.test.sh` | Copy the new lib into the sandbox; assert the boundary symbols survive the deleted window. |
| `scripts/test-all-infra-coverage-notice.test.sh` | Copy the new lib into the sandbox. |
| `plugins/soleur/test/fixture-cd-containment.test.sh` | Import the shared module; add `config` to `WRITE`; correct the `git -C` exemption comment and the "Prefer the last" prose. |
| `scripts/guard-vacuity-floor.test.sh` | `MIN_FIRING_SUITES` +N. `MAX_CONSTRUCTION_FAILURES` unchanged. |
| `scripts/test-all.sh` EXIT CONTRACT block (`:4-35`) | It enumerates rc 0/1/2/3/4 and documents the boundary explicitly. This change adds a REPORT class that increments nothing and changes no exit code — a state the contract does not describe. A new result class absent from the runner's own contract is the same claim/check drift being fixed. |
| The residual assertion sites | Derived from the Phase 0 frozen baseline — **not** from any table in this plan. Known-certain members: the five positional helpers; `context-reviewed-gate.test.sh`'s `mktemp` binding **and its caller at `:80`**; `ship-unpushed-commits-gate.test.sh`'s ten `read … < <(make_synced_branch …)` sites; `tests/hooks/test_hook_emissions.sh`; `scripts/context-reviewed-gate-discoverability.sh`. |
| The 29 `git rev-parse --show-toplevel` suites | Converted to `BASH_SOURCE` root resolution, if Phase 0 step 2 confirms the cost. |

## Guard Contract

### Guard 1 — the fixture directory operand (`plugins/soleur/test/fixture-dir-operand-assert.test.sh`)

**Property.** No tracked `*.sh` can have a git **write** retargeted at the caller's repository by an
**empty** directory operand (P1a). P1b is explicitly out of scope and tracked.

**Assembly.** Structural: `git ls-files '*.sh'` × {three binding forms} × {`git -C` write verbs}.
Binding forms: positional at binding, positional at the use site, and **any** command substitution
(`$(mktemp …)`, `$(new_repo …)`, `< <(make_synced_branch …)`, `$(cd … && pwd)`). Environment
variables, array elements, indirect expansion and `getopts` are cut — probed, zero live instances —
and that is stated rather than silently omitted.

**Mutation matrix** — each row must drive the suite RED:

| # | Mutation | Why |
|---|---|---|
| 1 | Remove `assert_fixture_dir` from one helper | The canonical instance |
| 2 | Remove it from a **second** file after the first is compliant | A check that stops at the first member is an instance of this family |
| 3 | Write `git -C "$1"` at the use site with no intermediate variable | Binding form 2, live in two files today |
| 4 | Bind from `$(new_repo …)` and write, unguarded | Binding form 3 in its live shape, not the `mktemp` special case |
| 5 | Replace an inline `assert_fixture_dir` body with a weakened one (non-empty only) | The name token must not be satisfiable by an empty shell; this is what the definition-equality rule enforces |
| 6 | Point the corpus at an empty file list | **Guard's own dispatch.** `SITES=0` over zero files must FAIL |
| 7 | Shrink the baseline without a matching remediation | The ratchet must be enforced, not documented |
| 8 | Neuter `fail()` to a no-op | **Harness row**, ADR-193: conservation fires first and names a discarded verdict |

**Must-PASS, none of them the canonical:** a site guarded with `d=$(mktemp -d) || return 1`;
`git -C "$X" status` / `worktree list` / `rev-parse` after an unasserted binding (reads are not
writes); `git -C "$X/work" commit` (derived operand, out of P1a); an absolute path under a symlinked
`/tmp`; the forbidden shape inside a heredoc body; and a `trap 'rm -rf "$WORK"' EXIT` string, whose
treatment is stated explicitly rather than left to the regex.

### Guard 2 — the repo-write boundary

**Property.** A run of this runner does not change this repository's HEAD, this worktree's tree or
index, local config outside `branch.*`, `refs/heads/main`, or its own checked-out branch — and where
it cannot see a change, cannot attribute one, or did not finish, it says so, without printing a
credential.

**Assembly.** `_repo_state()` has two call sites **in `scripts/test-all.sh`** (the unit suite adds
more, so the structural assertion is scoped to the runner). The window spans the whole suite list and
is sampled after `tc_acquire`. Execution vehicle: the existing `TESTALL_TARGET_OVERRIDE` +
`build_sandbox` pattern — no substring parse of the live 1900-line runner.

**Mutation matrix** — each row must drive the suite RED:

| # | Mutation | Why |
|---|---|---|
| 1 | A fixture writes `git config --local commit.gpgsign false` mid-run | **The instance-1 regression.** The narrow form does not report it; the widened form must |
| 2 | A fixture moves `refs/heads/main` while HEAD is a feature branch | The 2026-08-20 shape, invisible to `rev-parse HEAD` |
| 3 | A fixture deletes every local ref | `show-ref` exits 1 on no refs; this must be FATAL, not not-measured |
| 4 | A fixture commits (HEAD moves) | Regression of existing coverage |
| 5 | Make the start snapshot fail | **Guard's own dispatch** — the honest NOTE, never a silent clean claim |
| 6 | **Reorder**: move the end snapshot above the last `run_suite` | Order/lifetime row — a delete-only battery cannot see a window that shrank |
| 7 | **Reorder**: move the start snapshot above `tc_acquire` | The stale-by-an-hour failure the runner's own comment documents |
| 8 | Move the `source` line or a boundary variable below `tc_acquire` | Both SUT sandboxes delete that window; this must red rather than surface as two unrelated red suites |
| 9 | Drop the config dimension while leaving the inspected list intact | The claim and the check must move together — instance 2, reintroduced |
| 10 | Replace the value digest with raw values | **Security row.** No value of any key may reach the output |
| 11 | Kill the run before the end boundary | The EXIT-trap NOTE must fire; "no FATAL line" must never read as clean |
| 12 | A single escape doing `git -C "" checkout -b probe origin/main` — one config write (`branch.probe.*`) and one ref write (`refs/heads/probe`) | **The composition row.** Each projection is individually defensible and together they had a hole. No row that mutates one dimension at a time can see it |
| 13 | Delete `scripts/lib/repo-write-boundary.sh` | Must `exit 2`, and must **not** print "git unavailable at run start" — a cause the run did not measure |
| 14 | Replace the lib with a **stale** copy defining a narrower `_repo_state` | The manifest must shrink the rendered inspected list with it. A full-dimension claim beside a narrow check is #7652 one layer up, across the new module seam |
| 15 | Delete a dimension from the manifest while leaving `_repo_state` measuring it | The manifest is the claim's source of truth; it must not be able to under-report either |

**Must-PASS:** an already-dirty tree that stays equally dirty; a `refs/remotes/origin/*` update; a
`branch.*` config write; a sibling commit on another worktree's branch (REPORT, not FATAL); and a
`lefthook install` touching the shared `.git/hooks` — which must **not** fire, since hooks are not a
dimension.

### Guard 3 — the assertion refuses before it writes

**Property.** Invoked with an empty, relative or bare-`/` operand, `assert_fixture_dir` refuses and
the probe repository is byte-identical afterwards.

**Assembly.** The canonical body, exercised on **synthetic** helpers written inside the test file —
not extracted from tracked files by name, which is the substring-splice shape this plan rejects
elsewhere. Guard 1 guarantees the token is present at every site and that inline copies match the
canonical bytes; Guard 3 guarantees the canonical bytes refuse. The two compose without a
hand-maintained `(file, function)` table.

**Mutation matrix** — each row must drive the suite RED:

| # | Mutation | Why |
|---|---|---|
| 1 | Replace `exit 2` with `printf` alone, message intact | The message is what a reader checks; the refusal is what matters |
| 2 | Move the assertion **below** the first write | Order/lifetime row — post-return state is identical either way, so only the config-byte-identity post-condition catches it |
| 3 | Relax to a bare non-empty test | Non-empty is not absolute |
| 4 | Accept bare `/` | `/*` matches `/`, and `rm -rf "/"/*` is the worst case in the corpus |
| 5 | Call it from `v=$(helper "")` and let the caller proceed | The call context where the bug actually lives; `exit` inside `$( )` does not stop the caller |

**Axes deliberately not sampled** (stated, per the cited learning): P1b relative-operand families
(`rm -rf`, `mv`, `cp -r`, redirections) — tracked separately; suites invoked outside the runner;
`test-<name>.sh` corpora other than the ones named; and any escape reaching a remote, which no local
snapshot can observe.

## Observability

Triggered by `apps/web-platform/infra/` paths in scope. Every surface is developer-machine or
CI-time; nothing runs on a server.

```yaml
liveness_signal:
  what: "scripts/test-all.sh emits a REPO WRITE BOUNDARY verdict on every run, including a killed one"
  cadence: "every gate run (lefthook pre-commit, the CI shards, any manual run)"
  alert_target: "the run's own exit code — a FATAL delta increments `failed`"
  configured_in: "scripts/test-all.sh REPO WRITE BOUNDARY blocks + scripts/lib/repo-write-boundary.sh"
error_reporting:
  destination: "stderr of the run, plus a non-zero exit code; CI surfaces it as a failed job"
  fail_loud: true
failure_modes:
  - mode: "a suite writes HEAD, the tree, config, refs/heads/main, or the checked-out branch"
    detection: "widened _repo_state delta, with a capped diff naming the key or ref"
    alert_route: "FATAL, counted into `failed`, re-emitted in the breakdown area"
  - mode: "a delta on another worktree's branch or a tag"
    detection: "same snapshot, REPORT class"
    alert_route: "named non-failing REPORT, re-emitted in the breakdown area, pointing at the contention preamble"
  - mode: "the boundary cannot be measured (git unavailable at run start)"
    detection: "_repo_guard_ok stays 0"
    alert_route: "explicit NOTE that this run is not evidence; run NOT failed"
  - mode: "the run is killed before the end boundary"
    detection: "EXIT trap fires with the end snapshot untaken"
    alert_route: "the same not-measured NOTE, so absence of a FATAL line is never read as clean"
  - mode: "a suite's working directory is inside a git repository"
    detection: "the Phase 1 isolation guard"
    alert_route: "suite failure -> red shard"
  - mode: "a new unasserted operand site lands in a tracked *.sh"
    detection: "Guard 1 reports a site not in the shrink-only baseline"
    alert_route: "suite failure -> red shard"
logs:
  where: "run stderr; TEST_TIMING_LOG rows for the new suites"
  retention: "CI job logs per the repository's Actions retention; no separate sink"
discoverability_test:
  command: "bash plugins/soleur/test/fixture-dir-operand-assert.test.sh && bash scripts/lib/repo-write-boundary.test.sh"
  expected_output: "ALL TESTS PASSED from both suites, each preceded by a non-zero assertion count"
```

No soak or time-gated close criterion, so Phase 2.9.1 does not fire.

## Acceptance Criteria

### Pre-merge (PR)

1. **RED evidence, instance 1.** Output showing a helper returning rc=0 on an empty argument and the
   probe repository gaining `commit.gpgsign=false` before the fix, and refusing after.
2. **RED evidence, instance 2.** The narrow-form control: the pre-#7652 snapshot reports **no** delta
   across a `git config --local` write and a `refs/heads/main` move; the widened form reports both.
3. **CWD isolation is measured, not asserted.** The Phase 0 step 2 breakage count is recorded, the
   pre-committed decision rule is applied, and a suite started by the runner cannot reach the live
   repository with `git -C ""`.
4. Guard 1 reports zero **new** sites over `git ls-files '*.sh'`, prints a non-zero count of files
   scanned, and its baseline is smaller than the frozen Phase 0 baseline.
5. Every row of the Guard 1, Guard 2 **and Guard 3** matrices is executed and recorded, each mutation
   proven landed by `diff -q` against a pristine copy.
6. Both new suites carry an independent `cases` counter incremented at the call site, a conservation
   check reported before the floor, and an absolute floor — all via `printf >&2` + `exit 1`, never
   through the verdict helpers (ADR-193).
7. **No value of any config key appears in any boundary output**, asserted against both a
   `credential.*` key and an `http.*.extraheader` key — the CI vector, which v1 named in its risks and
   asserted nowhere.
8. The message enumerates an inspected list, a not-inspected list naming a push to a remote and
   suites this runner did not start, and a next action **per dimension**. Asserted by content anchor.
9. A killed run emits the not-measured NOTE.
10. `scripts/test-all-killed-classification.test.sh` and
    `scripts/test-all-infra-coverage-notice.test.sh` both still pass, with the new lib in their
    sandboxes.
11. A full run of the affected shards leaves **all four inspected dimensions** unchanged — not only
    HEAD and porcelain.
12. `scripts/lint-orphan-test-suites.sh` green.
13. `fixture-cd-containment.test.sh` matches `config` in its `WRITE` regex, its `git -C` exemption
    comment and header prose are corrected, and its assertion count is unchanged.
14. The three tracking issues are filed (P1b relative operands; the plugin-local-runner precondition;
    the stale `gdpr-gate` rule set).
15. The PR body uses `Closes #7652`.

### Post-merge

None. Every step is executed in-session by the gate this change ships with.

## Risks & Mitigations

**R1 — CWD isolation breaks suites that assume `CWD == repo root`.** Measured proxy: 358 of 373
tracked suites resolve their root from `BASH_SOURCE` and are unaffected; 29 use
`git rev-parse --show-toplevel`. *Mitigation:* Phase 0 measures the real set before anything is
committed, with a pre-committed decision rule; breakage is mechanically discoverable (run the battery,
read the failures) and one-time, unlike a scanner taxonomy which is a permanent obligation.

**R2 — the boundary's own output can leak a credential.** `actions/checkout` writes an
`http.*.extraheader` token composite into local config that GitHub's masker does not reliably catch,
and this machine's config already carries credential helpers. *Mitigation:* every value is digested,
so there is no allowlist to be incomplete; only key names are printed; the diff is capped. AC7 asserts
it against both the local and the CI vector.

**R3 — false REDs from a concurrent sibling session.** The sibling *runner* class is already closed —
`scripts/test-all.sh:867` refuses with `exit 4` before the boundary opens. The residual is a sibling
*interactive session*. *Mitigation:* harm-class projection puts only `refs/heads/main` and this
worktree's own branch in the FATAL class (a sibling worktree cannot have either checked out), config
drops `branch.*`, and everything else is a named REPORT. The printed diff adjudicates the rest.

**R4 — the population is larger than any table in this plan.** Candidate spaces measured in Phase 0
span orders of magnitude by family. *Mitigation:* the shrink-only baseline is the pre-committed
answer — land the guard at the measured baseline and burn it down. This is what stops the pressured
session from either shipping a partial fix or tuning the scanner down, both of which this plan's own
doctrine forbids and neither of which v1 gave an alternative to.

**R5 — the guard's own infrastructure is inside the space it observes.** Guard 1 scans tracked `*.sh`
and is one; Guard 2 drives the runner, and two other suites drive the runner in a sandbox.
*Mitigation:* heredoc bodies treated as data with a must-PASS proving the skip is scoped; both SUT
sandbox suites in Files to Edit with an AC; and the `TESTALL_TARGET_OVERRIDE` vehicle rather than a
substring parse.

**R6 — `extensions.worktreeConfig` would silently narrow the config dimension.** *Mitigation:*
asserted in Phase 0 **and** at runtime in the lib, which names the dimension not-measured rather than
silently reading a different file.

**R7 — a push reaches a remote the boundary cannot inspect.** A fixture `git push` with an empty
operand pushes the live repository to its remote. *Correction carried from review:* the claim that it
"leaves no local artifact" is **false** for the `-u` form, which writes `branch.<n>.remote` and
`branch.<n>.merge` — the very keys a blanket `branch.*` cut would have discarded, which is why that
cut is now narrowed to `vscode-merge-base`. What genuinely escapes inspection is the *content*
delivered to the remote. *Mitigation:* closed at source by CWD isolation, and stated precisely in
the not-inspected list rather than as a blanket "no local artifact".

**R8 — a spurious `exit 2` from an assertion is correctly classified.** Verified at
`scripts/test-all.sh:436-451`: `suite_exit_class` returns `killed` only for `rc > 128 && rc <= 192`
with a decodable signal name, so `exit 2` falls through to `failed`. ADR-177's unresolved class is
not perturbed and a spurious fire is a loud, correctly-attributed red shard rather than a
coverage-not-obtained result. Recorded because the question deserved an explicit answer.

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| Assert the operand at every call site (v1's primary) | Measured: the population spans 100-250 files depending on family, the scanner must recognise reformattable free-text idioms, and every new destructive verb becomes a scanner edit. CWD isolation buys the same property at one chokepoint |
| A single sourced `assert_fixture_dir` lib across all trees | `plugins/soleur/` ships standalone and `scripts/lib/` does not ship with it; three live suites copy themselves out of the tree and re-execute; `REPO_ROOT` is computed five ways; and the 40 existing `source` lines carry no `|| exit`, so a missing lib fails open |
| A pasted two-line `case` idiom | It is seven lines, not two, and it forces the scanner's detector to be either loose (vacuous) or strict (any reformat re-flags a fixed site, and someone then tunes the scanner) |
| `${1:?fixture dir required}` as the issue prescribed | Wrong for `context-reviewed-gate.test.sh`, whose `$1` is document content and is deliberately empty at one call site. (The "no repo precedent" and "subshell-safe" arguments v1 gave were both false and are withdrawn) |
| A four-family scanner covering `rm -rf`, `mv`/`cp -r`, redirections | Measured: none of them widens on an empty operand. Their hazard is P1b, tracked separately — a named deferral is a scope boundary, a silent exemption is a hole |
| Merge Guard 1 into `fixture-cd-containment.test.sh` | Renaming or absorbing that suite costs vacuity-floor bookkeeping, `TEST_TIMING_LOG` identity and every prior reference, for no property. A shared module gets the de-duplication without the churn |
| Narrow the FATAL message only, do not widen | The observed damage class **is** a config write; this leaves it undetectable forever while making the guard read honest |
| Tier severity on `${CI:-}` | Sorts on determinism and puts the teeth where the stakes are zero: a CI checkout is disposable, the founder's machine holds the only copy of their work. Harm-class projection makes the FATAL set environment-independent, so the tier serves nothing |
| A `.git/hooks/` dimension | Resolves a directory that is not necessarily the executing one (`--git-path hooks` ignores `core.hooksPath`), is sibling-shared rather than zero-churn, and its weaponisation is a config write already caught |
| Sample the boundary between shard groups | Attractive — it turns "somewhere in 20 minutes" into "in this shard". **Deferred with a tracking issue:** it turns one window into N, each needing its own order assertion, and the capped diff already names the exact key or ref |
| Split into two PRs (boundary first, then sweep) | **Recorded as a decision challenge, not decided here** — see `## Review Disposition`. Three reviewers recommended it, with the strongest argument being that the boundary *is* the detector for this family and should be live while the sweep edits fixture suites en masse |

## Review Disposition

An eight-consult panel reviewed v1: a scoped strong-model advisor, DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, CTO (devex lens) and CPO. Findings classified per
ADR-084.

**Mechanical (applied).** The CWD-isolation primary mechanism; the P1a/P1b property split; cutting
the `${CI:-}` tier, the `.git/hooks/` dimension, ADR-197 and the ADR-177 cross-reference; digesting
every config value with a per-run salt; harm-class refs projection keyed on `git worktree list`;
the narrowed `branch.*` carve-out and the config↔refs composition hole it closes; the manifest-rendered
inspected list and the `_REL_LIB` hard-fail source contract; the shared scanner module; adding
`config` to the `cd`-scanner's `WRITE` regex; the `TESTALL_TARGET_OVERRIDE` vehicle and both SUT
sandbox suites; the `tc_acquire` placement constraint; the shrink-only baseline; the corpus widening
to `*.sh`; the `grep`-under-`pipefail` and `show-ref`-rc=1 corrections; the EXIT-trap NOTE;
per-dimension next actions; the observe-only full-run precondition; `scripts/lint-diagnosis-claims.sh`
and AP-021; the runner's EXIT CONTRACT block; and the falsified claims in Research Reconciliation.

**Note on ordering.** The architecture review returned after this revision was drafted and therefore
assessed v1. Five of its findings survived the rewrite and are applied above; the rest had already
been resolved by the same cuts other reviewers reached independently. Its highest-value surviving
finding — the config↔refs composition hole — was invisible to every reviewer who examined the two
projections one at a time, which is the argument for keeping a composition row in the mutation matrix
permanently.

**Taste / User-Challenge (surfaced, not applied).** Splitting this into two PRs changes the
operator's stated scope ("the PR must close #7652", with the issue filing both instances together),
so it is not auto-applied. It is appended to
`knowledge-base/project/specs/<branch>/decision-challenges.md` for the operator to decide, with the
reviewers' reasoning and the recommended ordering (boundary first, sweep second, only the second
carrying `Closes`).

## Sharp Edges

- **`git -C ""` succeeds.** Every instinct that says "a bad path will error" is wrong, which is why
  `set -e` — present in three of the five helper files — bought nothing. Ask what a command does with
  an **empty** operand, not a **wrong** one. And check the answer per verb: `rm -rf ""` is a no-op,
  `mv a ""` is an error, `git -C ""` is a silent retarget. Only the third is this bug.
- **`exit` inside `$( )` does not stop the caller.** Neither does `${1:?}`. A helper that refuses
  correctly still leaves a caller in a no-`set -e` file proceeding with an empty variable — which is
  the same defect one frame up. This is why the chokepoint fix matters more than the assertion.
- **A guard that exits non-zero *after* writing has still failed.** Assert the post-condition, not the
  exit code.
- **The scanner defines the population; the baseline records it.** A hand-picked list with a scanner
  that finds more ships red; a scanner tuned to the list already fixed is vacuous. The shrink-only
  baseline is the only third option, and it must be frozen before the remediation idiom is chosen.
- **Anything new in the runner must sit above `tc_acquire "test-all"`.** Two suites delete everything
  between that anchor and `tc_epilogue` to build their sandbox, and the end block runs under `set -u`.
- **The sibling scanner recommends the shape this one forbids.** Until its comment is corrected, a
  reader following its advice writes a `git -C "$dir"` write believing it is the safe spelling.
- **The failure output of a repository guard is a disclosure surface.** Widening what a guard reads
  widens what its error message can print. Ask that question every time a snapshot grows.
- **`plugins/soleur/**` is delivered to every installed user.** Nothing shipped executes these
  suites today, which is the only reason the blast radius is one operator — a contingent fact, not a
  structural one, and it is the first thing to re-check if a plugin-local runner is ever added.
