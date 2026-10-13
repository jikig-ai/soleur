---
title: "test: doppler_sha256 + registry-userdata-budget.sh do not cover the registry_arch derivation"
date: 2026-10-13
slug: test-registry-arch-orientation-guard
branch: feat-one-shot-7335-registry-arch-orientation-test
issue: 7335
closes: 7335
type: test
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# test: prove the registry arch orientation guard durable and pin the precondition the budget script leans on

## Overview

Issue #7335 asked for an A16-style orientation test for `local.registry_arch` in `apps/web-platform/infra/zot-registry.tf`, mutation proof that it
fails where four suites stay green today, and a cover-or-scope-out decision for two neighbouring consumers (`local.doppler_sha256` and the hardcoded
amd64 branch in `registry-userdata-budget.sh`). Constraints from the brief: edit no user_data, never touch `cloud-init-registry.yml` (a merge of that
file replaces the production registry host), smallest fix, run every registered infra suite.

**The headline ask already exists on main.** `registry-boot-guard.test.sh` carries `R3` / `p_registry_arch_derivation` (lines ~386-423), landed in #7325
(the PR whose review spawned #7335). It extracts the prefix and both branch values from the declaration and replays `cax11/21/31/41 -> arm64`,
`ca99 -> amd64`, `cpx22/cx23/cx33/ccx13 -> amd64`. Measured on a sandbox worktree during this plan (see Research Insights): inverting the ternary and
deleting the local each turn `registry-boot-guard` RED (127 passed, 1 failed) while the other four suites stay green. R3's own header still says the two
sibling consumers are "still uncovered - #7335".

So the residual work is three things, all inside the one already-registered suite and none touching a user_data source:

1. **R3 durability.** R3 is a bare `assert()`; the git-data suite proves its twin (A16) with `assert_mutation` arms. R3 can be neutered (drop the `ca99`
   fixture, stop extracting the prefix, make it return 1) with the suite green. Add in-suite mutation arms driven against a temp copy.
2. **R4: the amd64-only precondition guard.** `registry-userdata-budget.sh` hardcodes `doppler_arch = "amd64"` and measures the amd64 pin. That is sound
   only because `hcloud_server.registry` refuses to plan an arm64 host (`precondition { condition = local.registry_arch == "amd64" }`, `zot-registry.tf`
   ~641). No test asserts that precondition exists. Add a block-scoped presence guard with its own mutation arms.
3. **Scope-out, cited.** `local.doppler_sha256` is already covered by `git-data-luks.test.sh` A15 (`p_doppler_checksum_parity`); replace R3's stale
   "still uncovered - #7335" comment with the citation. No new doppler test.

Decisions were ruled by the CTO agent (2026-10-13) and persisted in
`knowledge-base/project/specs/feat-one-shot-7335-registry-arch-orientation-test/decision-challenges.md`.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #7335 is OPEN (label `deferred-scope-out`, no closing PR); #10205 (epic, "complete the zot registry arc") is
OPEN; PR #7325 merged 2026-08-06; draft PR #10206 is this branch's WIP. STALE: the premise that "nothing asserts the orientation" - R3 landed in #7325.
STALE in a second way: `local.zot_image` (the arm64/amd64 selector that the issue says an inversion darks) has no `.tf` consumer left; since #8714
5.3b-iii the real user_data map passes `zot_asset_sha256 = local.zot_mirror_asset_sha256_amd64` / `zot_config_digest = local.zot_config_digest_amd64`
regardless of arch. What `registry_arch` still drives is `doppler_arch`, `doppler_sha256` and two plan-time preconditions. ADR corpus: the mechanism (a
bash replay predicate) is not in any ADR's rejected alternatives; ADR-169 (sole pull path) and ADR-252 (suite registration by filesystem glob) are the
relevant ones.

**Property List (Phase 0.6b).**

- P1: an inverted or deleted `local.registry_arch` derivation turns a registered infra suite RED (holds today via R3).
- P2: P1's guard cannot be neutered at green (does NOT hold today: R3 has no mutation arms).
- P3: the amd64-only measurement in `registry-userdata-budget.sh` is invalidated loudly if the plan-time arm64 refusal disappears (does NOT hold today).
- P4: a flip of `local.doppler_sha256`'s ternary is caught (holds today via A15).

**Cut List (Phase 0.6b).**

- New `doppler_sha256` orientation test (brief: "cover or scope out") -> buys P4 -> already bought by A15 in `git-data-luks.test.sh` (measured RED on
  selector-invert, literal-swap, amd64-literal-corrupt, delete). CUT, cite A15.
- Making `registry-userdata-budget.sh` derive/refuse on arch -> would buy P3 -> the measured byte size is arch-invariant (`amd64` and `arm64` are both 5
  chars, both Doppler checksums 64 hex), so arch logic there is dead code; R4 buys P3 at the source of truth instead. CUT.
- Refactoring `zot-registry.tf` so `zot_image`/`doppler_sha256` are independently mutation-testable (the issue's scope-out text) -> edits a file whose
  merge touches the registry host render path; the sibling selector is already byte-pinned by `zot-image-staleness.test.sh`. CUT.
- New sibling suite -> a registered suite needs its own floor; the work is ~15 assertions beside R1-R3. CUT.
- Comment-only edit in `registry-userdata-budget.sh` -> the file is a `pull_request` path trigger of `zot-image-mirror.yml` (docker rehearsal) for zero
  behavioural gain. CUT, pointer lives in the R4 header comment instead (CTO ruling).

**Value-proposition measurement (Phase 0.6c).** No cost claim; n/a. The suite runs in 0.42 s (`time bash registry-boot-guard.test.sh`).

**Sandbox measurement (git worktree at HEAD in the scratchpad; mutations applied to `zot-registry.tf` only).** Verdicts, suites in order
`registry-boot-guard / zot-image-staleness / git-data-luks / registry-luks / registry-userdata-budget`:

| mutation to `zot-registry.tf` | result today |
|---|---|
| INVERT `registry_arch` ternary | RED(127/1) / green / green / green / green |
| DELETE `registry_arch =` | RED(127/1) / green / green / green / green |
| `doppler_sha256` selector `"arm64"` -> `"amd64"` | green / green / RED (A15, 153/1) / green / RED (28/8) |
| `doppler_sha256` literals swapped | green / green / RED (A15) / green / green |
| `doppler_sha256` amd64 literal corrupted | green / green / RED (A15) / green / green |
| DELETE `doppler_sha256` | green / green / RED (A15) / green / RED (28/8) |
| DELETE the amd64-only `precondition` (not yet measured; no assertion exists, so by construction) | green everywhere |

Baselines: registry-boot-guard 128/0, zot-image-staleness 16/0, git-data-luks 154/0, registry-luks 34/0, registry-userdata-budget 28 checks 0 failed.
(The issue's 86/15/133/34 counts have grown since #7325; the verdict is what matters.)

**Prototype (scratchpad `proto.sh`, run against a pristine copy).** Predicates and a temp-copy mutation verdict function behave as designed: base arch=1,
pre=1; INVERT, TRUE-BRANCH-ONLY, DELETE, WIDEN (`"cax"`->`"ca"`), NARROW (`"cax"`->`"caxx"`), COMMENT-OUT all RED; a reformatted-but-equivalent
declaration is GREEN; a sed that matches nothing returns NOLAND; the precondition predicate goes RED on delete, flip to `"arm64"`, weaken to `true`,
comment-out and resource-rename, GREEN on a reformatted equivalent.

**Institutional learnings applied.**

- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` - the harness needs its own
  positive control and a mutation-landed check.
- `2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md` - derive the matrix from the property, not from the code.
- `2026-08-19-my-battery-reverted-the-fix-it-was-testing.md` - restore from a `cp` pristine copy, never `git checkout`; here the arms never touch the
  real tree at all (temp copy + trap).
- `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md` and `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md` -
  assert each sed landed (`cmp` against the pristine copy); set `MIN_ASSERTIONS` from a measured count.
- `2026-10-06-a-line-anchored-extractor-cannot-see-a-prefixed-assignment.md` - an anchored extractor must be checked against every spelling the `.tf`
  can take; the reformat must-PASS rows exist for this.
- `2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md` - `sed` exits 0 on no match; the NOLAND verdict is the answer.

**Open code-review overlap (Phase 1.7.5).** Queried open `code-review` issues for `registry-boot-guard.test.sh`, `zot-registry.tf`,
`registry-userdata-budget.sh`: none.

**Network-outage / community discovery / functional overlap.** Not triggered (no SSH/firewall keywords; stack is bash + Terraform, both covered;
the existing A16/R3 pair is the overlap and is the subject of this plan).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief / issue | Reality on `origin/main` (f7a0e2a443) | Plan response |
|---|---|---|
| "`local.registry_arch` has no test anywhere; inverting it leaves four suites green" | R3 in `registry-boot-guard.test.sh` (from #7325) already reds on INVERT and DELETE | Do not build a second orientation test. Prove R3 durable with in-suite mutation arms; record the measurement. |
| "Put it in registry-boot-guard.test.sh or a sibling" | R3 is already there | Keep all new work in `registry-boot-guard.test.sh` (CTO ruling). |
| "`local.doppler_sha256` ... unguarded" | `git-data-luks.test.sh` A15 3-way parity reds every doppler_sha256 mutation (measured) | Scope out, cite A15, replace the stale comment. |
| "`registry-userdata-budget.sh` hardcodes the `zot_image_amd64` branch, so under a flip it silently measures the wrong image" | The measurement is arch-invariant in size, `local.zot_image` has no `.tf` consumer, and a plan-time precondition refuses arm64; but no suite asserts that precondition | R4: block-scoped presence guard for the precondition + mutation arms. No script change. |
| "The inverted ternary darks the sole pull path (MANIFEST_UNKNOWN)" | True when written (#7325); since #8714 5.3b-iii the boot image is the amd64 mirror asset, so an inversion now fails the plan-time preconditions and selects the wrong Doppler build | R3 still the right guard; wording in new comments says what the derivation drives today. |

## Scope Check

| Ask (from the brief) | Mapped to | Provenance |
|---|---|---|
| Orientation test modelled on A16 (prefix + both branches, replay set) | R3 already present; extended by T1/T2 arms (keeps its fixture set) | operator-stated |
| Registered infra suite | `registry-boot-guard.test.sh` (glob-registered, ADR-252) | operator-stated |
| INVERT and DELETE mutation proof on a sandbox copy; four suites stay green today | Measured in Research Insights; re-run after the change (T4); permanent in-suite arms (T2) | operator-stated |
| Cover or scope out `doppler_sha256` | Scope out, cite A15 (T3) | operator-stated |
| Cover or scope out the budget script's amd64 branch | Cover via R4 precondition guard (T2) | operator-stated |
| Edit no user_data, do not touch `cloud-init-registry.yml` | Files lists below contain neither | operator-stated |
| Run all registered infra suites | T4 | operator-stated |
| Smallest fix | One file edited (plus plan artifacts) | operator-stated |
| PR body items (`Closes #7335`, `Ref #10205`, `## Changelog`, archived plan path, BASELINE re-check) | Ship-phase reminders below | operator-stated |
| Raise `MIN_ASSERTIONS` | follows from adding assertions to a floor-guarded suite | inferred (mechanically required: the floor must move in lockstep or the new arms are deletable at green; justified by the suite's own comment) |
| Arch-enum precondition presence arm | none | not added: outside the budget script's dependency (CTO ruling) |

Split assessment: one concern, one file; no split.

## Files to Edit

- `apps/web-platform/infra/registry-boot-guard.test.sh` - refresh the R2/R3 comment block (drop "still uncovered - #7335", cite A15 and R4); add the
  mutation harness helpers and R3 arms; add R4 (predicate, header comment, baseline + arms); raise `MIN_ASSERTIONS`.

## Files to Create

- None (plan artifacts only: this plan, `tasks.md`, `decision-challenges.md`).

**Explicitly NOT edited:** `apps/web-platform/infra/cloud-init-registry.yml` and any user_data source; `zot-registry.tf`;
`registry-userdata-budget.sh` (a `pull_request` path trigger of `zot-image-mirror.yml`); `git-data-luks.test.sh`.

## Implementation Phases

### Phase 1 - Harness (T1)

In `registry-boot-guard.test.sh`, directly after R3's `assert`, add:

- One owned scratch dir: `MUT_DIR="$(mktemp -d)"` with `trap 'rm -rf "$MUT_DIR"' EXIT` declared in the SAME hunk, before any arm runs. The suite has no
  `mktemp` and no EXIT trap today, so a bare `mktemp` would trip `scripts/lint-trap-tempfile-ownership.py` rule (c) (added-line `mktemp` with no owning trap).
  Verify the suite still exits with its own status after the trap is installed (the trap must not rewrite `$?`).
- `_mutant_verdict FN SED_EXPR` - writes `sed -E "$SED_EXPR" "$SCRIPT_DIR/zot-registry.tf"` into `$MUT_DIR/m.tf`; prints `SEDERR` if sed fails, `NOLAND`
  if `cmp -s` says the mutant equals the original, `RED` if the predicate prints `0` on the mutant, else `GREEN`. Never reads or writes the real file in
  place; never reads `cloud-init-registry.yml`. Each RED row's meaning rests on the baseline assertion that the SAME predicate returns `1` on the real
  file (R3 exists; R4 adds its own), so an unreadable-file `0` cannot masquerade as a caught mutation.
- Call it outside `assert` (compute `v="$(_mutant_verdict ...)"`, then `assert "<desc>" "[ '$v' = RED ]"`) so sed metacharacters never go through `eval`.

### Phase 2 - R3 arms and R4 (T2)

R3 arms (all against `p_registry_arch_derivation`, the existing predicate, unchanged):

1. INVERT: `/^[[:space:]]*registry_arch[[:space:]]*=/ s/\? "arm64" : "amd64"/? "amd64" : "arm64"/` -> RED. Anchored to the declaration line (the
   `zot_image` selector at line 108 also contains `registry_arch ==` and must not be rewritten).
2. DELETE: `/^[[:space:]]*registry_arch[[:space:]]*=/d` -> RED (the empty-extraction dispatch; also covers a commented-out declaration, which the
   comment-stripping extractor reads identically).
3. WIDEN prefix `"cax"` -> `"ca"` on the declaration line -> RED (only the `ca99` fixture separates it).
4. Must-PASS (non-canonical): reformatted equivalent (`?"arm64":"amd64"` plus a trailing comment, declaration line only) -> GREEN.
5. Harness control: a sed that matches nothing returns `NOLAND`.

(Review cut, taste: true-branch-only, narrow-prefix and comment-out arms were dropped - each is killed by the same fixture/extraction path as an arm kept.)

R4 - `p_registry_amd64_only_precondition FILE` (comment-stripped with the same `sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;'`, then an awk state machine:
inside `resource "hcloud_server" "registry" {`, inside a `precondition {` block, a line `condition = local.registry_arch == "amd64"` sets found; prints
`1`/`0`). Header comment: states the property in the precondition's own terms (the boot image is mirrored for amd64 only, `zot_mirror_asset_sha256_amd64` /
`zot_config_digest_amd64`; an arm64 host would boot with no asset), and that `registry-userdata-budget.sh` (lines ~35-39 and ~104: `doppler_arch = "amd64"`,
the amd64 operand of `doppler_sha256`, the `zot_image_amd64` pin) renders those amd64 artifacts, so its measurement describes the real host only while this
precondition exists (the byte SIZE is arch-invariant; the dependency is on which artifacts are rendered, not on the cap number); names `git-data-luks.test.sh` A15 as the `doppler_sha256`
owner; says the R1/R2/R3 pins are file-string pins that cannot see a tfvars override, which is the precondition's job. Arms (each sed anchored to the `condition` line, or to the `resource "hcloud_server" "registry" {` header, never file-wide, so the `error_message` text and other
references are untouched): baseline holds on the real file; DELETE the condition line -> RED; WEAKEN `local.registry_arch == "amd64"` to `true` on the condition
line -> RED; COMMENT-OUT the condition line -> RED; RESOURCE-RENAME (the header `"registry"` -> `"registry2"`, relocating the precondition out of the scoped
block) -> RED; must-PASS reformatted equivalent (`condition=local.registry_arch=="amd64" # ok`) -> GREEN. (Review cut, taste: FLIP-to-`arm64` dropped, killed
by the same exact-string match as DELETE.) Each arm lists its exact sed expression in the work-phase tasks; the NOLAND check catches an expression that
matches nothing, and the work phase confirms each mutant differs from the original by exactly the intended line (`diff` shows one changed line).

Assertion count: R3 adds 5, R4 adds 6 (baseline + 4 RED + 1 must-PASS) = **11 new**; current run is 128 against `MIN_ASSERTIONS=123` (slack 5), so
the floor becomes 134 and the run becomes 139.

### Phase 3 - Comment refresh (T3)

Rewrite the R2/R3 comment lines naming "still uncovered - #7335": `local.doppler_sha256` is owned by `git-data-luks.test.sh` A15; the budget script's
hardcoded amd64 branch is owned by R4. Do not restate the repin rationale (the existing comment forbids it).

### Phase 4 - Proof and full run (T4)

1. In a git worktree at the post-change HEAD (scratchpad, never the real tree), apply INVERT and DELETE to the sandbox `zot-registry.tf` and run the
   five suites; record verdicts (expected: `registry-boot-guard` RED on both, via R3 itself; the other four green, as today).
2. One-off harness proof, on a sandbox copy of the SUITE (recorded in the PR body, not a permanent assertion): delete the `ca99` fixture from R3's
   loop in the copy and show the WIDEN arm no longer reports RED there, i.e. that fixture is what pins the prefix length.
3. Run every registered infra suite: `bash apps/web-platform/infra/run-registered-suites.sh` (derives the set by `git ls-files` glob, ADR-252; match
   the `^RED` prefix, not `FAIL`). Terraform-dependent suites need `terraform` on PATH; record any SKIP honestly.
4. `shellcheck` and `bash -n` on the edited suite; `python3 scripts/lint-trap-tempfile-ownership.py` (rule (c): the new `mktemp` must have its owning EXIT trap); `markdownlint` on plan artifacts; `python3 scripts/lint-guard-contract.py` on this plan.

## Guard Contract

### Guard 1 - registry arch derivation orientation (R3 plus its mutation arms)

**Property.** An inversion, deletion, prefix drift (wider or narrower than `cax`) or hidden declaration of `local.registry_arch` in `zot-registry.tf`
turns `registry-boot-guard.test.sh` RED, and the guard cannot itself be neutered at green.

**Assembly.** The property quantifies over every way the derivation can be wrong, and it has ONE chokepoint: the single line-start assignment
`registry_arch = startswith(var.registry_server_type, "<prefix>") ? "<t>" : "<f>"` in `zot-registry.tf` (comment-stripped, first match), which
`p_registry_arch_derivation` parses into (prefix, true value, false value) and replays over the synthesized type set (`cax11/21/31/41`, `ca99`,
`cpx22`, `cx23`, `cx33`, `ccx13`). The consumers of the local (`zot_image` at line 108, `doppler_sha256` at line 110, the `doppler_arch` map entry at
~572, the two preconditions at ~641/646) all read `local.registry_arch`, never re-derive it; `git grep` shows no second declaration in the infra root, and
a second `locals` declaration of the same name is rejected by `terraform validate`, so there is no second chokepoint to guard. The harness assembly is
`_mutant_verdict` (temp-copy, sed, `cmp`, predicate) and the arms below.

**Mutation matrix.**

| # | Edit (on a temp copy of `zot-registry.tf`, or of the suite where stated) | Must go RED because |
|---|---|---|
| 1 | INVERT the two branch values on the declaration line | the `cax*` fixtures replay as `amd64` |
| 2 | DELETE the declaration line (the guard's own dispatch: empty extraction must fail loud, not replay vacuously; a commented-out declaration reads identically) | `expr` empty -> `0` |
| 3 | Widen the prefix to `ca` after the compliant first fixtures pass (the second-member row: cax11..41 all still pass, only `ca99` fails) | `ca99` replays as `arm64` |
| 4 | Harness (one-off T4 proof, on a copy of the SUITE): delete the `ca99` fixture from R3's loop | row 3 loses its only discriminator; the copy must be shown to differ from the real suite's verdict on the WIDEN mutant |
| 5 | Must-PASS: reformatted equivalent declaration (`?"arm64":"amd64"` plus trailing comment) | passes: proves the guard does not reject everything or demand one spelling |
| 6 | Harness control in-suite: a sed that matches nothing returns `NOLAND` | proves a non-landing mutation fails loud instead of reporting a false catch |

**Anchor.** The guard compares no stored hash or count; its truth source is the synthesized fixture table inside the suite (Hetzner's `cax` = Ampere
line). A weakening that edits both the `.tf` prefix and the fixtures in one diff passes the suite by construction; the independent anchor is the plan-time
precondition in `zot-registry.tf` (~646) that compares the derived arch to Hetzner's live architecture enum for the chosen type, and R4 below asserts that
the amd64 refusal exists. `MIN_ASSERTIONS` is an anti-vacuity floor on the suite, raised in lockstep with the 11 added assertions.

### Guard 2 - amd64-only precondition presence (R4)

**Property.** `hcloud_server.registry` carries a plan-time refusal of any arch other than amd64; if it is deleted, relocated, weakened or commented out,
`registry-boot-guard.test.sh` turns RED, because `registry-userdata-budget.sh`'s hardcoded amd64 measurement is valid only while that refusal exists.

**Assembly.** The refusal is a `precondition { condition = local.registry_arch == "amd64" }` inside `lifecycle` of `resource "hcloud_server" "registry"`.
It has one location. The predicate quantifies over: the resource block (awk scope, so a same-text condition elsewhere does not count), the
`precondition {` block (so an `error_message` string or comment containing the text does not count), and the comment-stripped condition line. The
neighbouring arch-enum precondition (~645-648) is deliberately not asserted (CTO ruling: outside the budget script's dependency).

**Mutation matrix.**

| # | Edit (temp copy of `zot-registry.tf`; each sed anchored to the condition line or the resource header) | Must go RED because |
|---|---|---|
| 1 | DELETE the `condition = local.registry_arch == "amd64"` line (the guard's dispatch: nothing found must be `0`, not "0 checked, pass") | not found |
| 2 | WEAKEN the condition to `true` | refusal gone while the block looks intact |
| 3 | COMMENT OUT the condition line (the `error_message` line, which repeats `local.registry_arch`, remains) | comment-stripped, and `error_message` is not a `condition` |
| 4 | RESOURCE-RENAME `"registry"` to `"registry2"` (the precondition is now in another block: the second-member row, a compliant-looking copy elsewhere) | outside the scoped block |
| 5 | Must-PASS: reformatted equivalent (`condition=local.registry_arch=="amd64" # ok`) | passes: the predicate is not spelling-bound |

**Anchor.** Presence of a line, not a stored value: nothing outside the commit needs to move except that deleting the precondition changes plan-time
behaviour for operators overriding `registry_server_type` via tfvars, which R1/R2/R3 (file-string pins) cannot see. The independent check is
`terraform plan` itself, which is not runnable in this suite; that limitation is stated in the R4 comment.

## Acceptance Criteria

- [ ] `registry-boot-guard.test.sh` passes (139 passed, 0 failed expected) and `MIN_ASSERTIONS` is raised by exactly the number of assertions added (123 -> 134).
- [ ] Each R3 and R4 RED arm reports `RED` and each must-PASS arm reports `GREEN` on the real tree; the NOLAND control reports `NOLAND`.
- [ ] Sandbox proof recorded in the PR body: INVERT and DELETE of `registry_arch` red `registry-boot-guard` (via R3) with the other four suites green, as measured; the R4 mutations are RED in-suite; the one-off `ca99` deletion on a suite copy shows the WIDEN arm depends on it.
- [ ] `git diff --name-only origin/main` contains `registry-boot-guard.test.sh` and files under `knowledge-base/project/{plans,specs}/` only; it contains no `cloud-init-registry.yml`, no `zot-registry.tf`, no `registry-userdata-budget.sh`, no user_data source.
- [ ] The mutation arms never write to the real tree: they operate on `mktemp -d` copies (verify: `git status --short` clean of `.tf` changes after a suite run).
- [ ] The R2/R3 comment no longer says "still uncovered - #7335" and cites A15 (doppler_sha256) and R4 (budget script's amd64 branch).
- [ ] `bash apps/web-platform/infra/run-registered-suites.sh` reports no `^RED` line attributable to this change (record pre-existing reds, if any, by name).
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan; `shellcheck` and `scripts/lint-trap-tempfile-ownership.py` clean on the edited suite.
- [ ] PR body: `Closes #7335`, `Ref #10205`, a `## Changelog` section, the plan cited by its ARCHIVED path (`knowledge-base/project/plans/archive/<timestamp>-2026-10-13-test-registry-arch-orientation-guard-plan.md`, after `archive-kb`), the note that R3 already landed in #7325 and what this PR adds, and the decision-challenges rows.
- [ ] Before the final push: re-check `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` against `origin/main` (66 at plan time, `f7a0e2a443`); this plan declares no `credentials_required`, so no bump is expected.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; a broken suite reddens CI for an infra PR (a merge-blocking check on registry changes), or, worse, a mutation harness bug could stay green while the guard it protects is neutered, so a later arch flip reaches the registry host replace path unchecked and the sole container pull path goes dark for every deploy.
**If this leaks, the user's [data / workflow / money] is exposed via:** no data surface: synthesized type names and public Doppler CLI checksums only; no credentials, no user data.
**Brand-survival threshold:** none
threshold: none, reason: the change adds test assertions to an existing suite and touches no production code, user_data, or credential path; the guarded surface is already protected at plan time by the Terraform preconditions this PR only asserts.

## Observability

```yaml
liveness_signal:
  what: the registry-boot-guard suite runs and reports its pass/fail ledger line
  cadence: every infra-touching PR and push (infra-validation.yml deploy-script-tests, sharded K=4, registered by filesystem glob)
  alert_target: infra-validation required-check status on the PR; main-health-monitor for main
  configured_in: .github/workflows/infra-validation.yml (run-registered-suites.sh)
error_reporting:
  destination: CI job log with per-suite `RED <path>` and ::error annotations
  fail_loud: yes - the suite exits 1 on any failed assertion and on the MIN_ASSERTIONS floor
failure_modes:
  - mode: R3 neutered or an arm silently not landing
    detection: NOLAND/SEDERR verdicts fail their assertion; floor trips if arms are deleted
    alert_route: RED suite on the PR
  - mode: precondition deleted from the registry host resource
    detection: R4 baseline assertion
    alert_route: RED suite on the PR
logs:
  where: GitHub Actions deploy-script-tests leg logs
  retention: GitHub default (90 days)
discoverability_test:
  command: bash apps/web-platform/infra/registry-boot-guard.test.sh
  expected_output: 0 failed
```

## Domain Review

**Domains relevant:** engineering (CTO consulted)

### Engineering

**Status:** reviewed
**Assessment:** CTO agent, 2026-10-13: Option B kept narrow; scope out `doppler_sha256` (A15); cover the budget script's amd64 branch by a precondition-presence guard; work in the existing suite; leave `registry-userdata-budget.sh` untouched (zot-image-mirror path trigger). Rulings recorded in `decision-challenges.md`.

No Product/UX, Legal, Marketing, Finance, Operations, Sales or Support implications: test-only change to an infra suite. No UI surface, no regulated data (GDPR gate not triggered), no new infrastructure (IaC routing gate not triggered), no architectural decision (no ADR/C4 change: the change asserts an existing precondition and adds no substrate, boundary or ownership move; C4 checked for actors/systems: no new actor, vendor or store).

## Test Scenarios

- Given the unmodified tree, when `registry-boot-guard.test.sh` runs, then 139 assertions pass and the floor holds.
- Given an inverted `registry_arch` in a temp copy, when R3's predicate replays it, then the verdict is RED.
- Given a precondition relocated to another resource block, when R4's predicate scans, then the verdict is RED.
- Given a sed expression that matches nothing, when `_mutant_verdict` runs, then it reports NOLAND and the arm fails loud.
- Given a copy of the suite with R3's `ca99` fixture removed, when the WIDEN arm runs, then it no longer reports RED (one-off proof).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- The new arms must pass sed expressions through `_mutant_verdict` outside `assert` (the suite's `assert` runs `eval`); quote-bearing seds inside the condition string will break.
- Restore nothing: arms operate on `mktemp -d` copies, so there is nothing to revert, and nothing here may use `git checkout` or `git stash` in the worktree.
- `terraform` is not needed by the new arms; the full registered run still needs it for neighbouring suites (CI fails closed without it; local SKIPs).
- Do not "fix" the floor by lowering it; raise it to the measured count minus the existing slack of 5.
